#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const MAX_REVIEW_BYTES = 2 * 1024 * 1024;
const MAX_ARTIFACT_BYTES = 24 * 1024 * 1024;
const MAX_TOTAL_ARTIFACT_BYTES = 96 * 1024 * 1024;
const MAX_JSONL_LINES = 100000;
const MAX_DIFF_PATHS = 10000;
const SHA256 = /^[0-9a-f]{64}$/;

function fail(message) {
  process.stderr.write(`Error: ${message}\n`);
  process.exit(2);
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function nonempty(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function parseArgs(argv) {
  const result = {};
  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i];
    if (!["--review", "--oracle", "--evidence-root"].includes(key) || i + 1 >= argv.length || result[key]) {
      fail("usage: clarification-evidence.cjs --review FILE --oracle FILE --evidence-root DIR");
    }
    result[key] = argv[i + 1];
    i += 1;
  }
  if (!result["--review"] || !result["--oracle"] || !result["--evidence-root"]) {
    fail("usage: clarification-evidence.cjs --review FILE --oracle FILE --evidence-root DIR");
  }
  return result;
}

function readRegularFile(filePath, maxBytes, label) {
  let stat;
  try {
    stat = fs.lstatSync(filePath);
  } catch (error) {
    if (error && error.code === "ENOENT") return null;
    fail(`${label} cannot be inspected`);
  }
  if (stat.isSymbolicLink() || !stat.isFile()) fail(`${label} must be a regular non-symlink file`);
  if (stat.size > maxBytes) fail(`${label} exceeds the bounded file size`);
  return fs.readFileSync(filePath);
}

function parseJson(bytes, label) {
  try {
    return JSON.parse(bytes.toString("utf8"));
  } catch (_error) {
    fail(`${label} is not valid JSON`);
  }
}

function requireKeys(value, keys, label) {
  if (!isObject(value)) fail(`${label} must be an object`);
  for (const key of keys) {
    if (!Object.prototype.hasOwnProperty.call(value, key)) fail(`${label}.${key} is required`);
  }
}

function isSafeProjectRelativePath(value) {
  return nonempty(value)
    && !value.includes(String.fromCharCode(92))
    && !value.includes(String.fromCharCode(0))
    && !path.posix.isAbsolute(value)
    && !value.split("/").some((segment) => segment === "" || segment === "." || segment === "..");
}

function safeProjectRelativePath(value, label) {
  if (!nonempty(value) || value.includes("\\") || value.includes("\0") || path.posix.isAbsolute(value)) {
    fail(`${label} must be a safe project-relative path`);
  }
  const segments = value.split("/");
  if (segments.some((segment) => segment === "" || segment === "." || segment === "..")) {
    fail(`${label} must not contain empty, dot, or parent path segments`);
  }
  return segments.join("/");
}

function artifactReader(root) {
  let totalBytes = 0;
  const cache = new Map();
  const unavailable = [];

  function read(ref, label, unavailableSink = unavailable) {
    if (!isObject(ref) || !nonempty(ref.path) || typeof ref.sha256 !== "string") {
      unavailableSink.push(`${label}_reference_missing`);
      return null;
    }
    const relative = safeProjectRelativePath(ref.path, `${label}.path`);
    if (!SHA256.test(ref.sha256)) fail(`${label}.sha256 is invalid`);
    if (cache.has(relative)) {
      const cached = cache.get(relative);
      if (cached.digest !== ref.sha256) fail(`${label} hash does not match the already admitted artifact`);
      return cached;
    }
    let current = root;
    const parts = relative.split("/");
    for (let index = 0; index < parts.length; index += 1) {
      current = path.join(current, parts[index]);
      let stat;
      try {
        stat = fs.lstatSync(current);
      } catch (error) {
        if (error && error.code === "ENOENT") {
          unavailableSink.push(`${label}_artifact_missing`);
          return null;
        }
        fail(`${label} path cannot be inspected`);
      }
      if (stat.isSymbolicLink()) fail(`${label} artifact path contains a symbolic link`);
      if (index < parts.length - 1 && !stat.isDirectory()) fail(`${label} artifact parent is not a directory`);
      if (index === parts.length - 1 && !stat.isFile()) fail(`${label} artifact must be a regular file`);
    }
    const stat = fs.statSync(current);
    if (stat.size > MAX_ARTIFACT_BYTES) fail(`${label} exceeds the per-artifact size limit`);
    totalBytes += stat.size;
    if (totalBytes > MAX_TOTAL_ARTIFACT_BYTES) fail("evidence artifacts exceed the total size limit");
    const bytes = fs.readFileSync(current);
    const digest = sha256(bytes);
    if (digest !== ref.sha256) fail(`${label} SHA-256 does not match the retained artifact`);
    const value = { relative, bytes, digest };
    cache.set(relative, value);
    return value;
  }

  return { read, unavailable };
}

function parseTranscript(turn, admitted, label) {
  if (!admitted) return null;
  const lines = admitted.bytes.toString("utf8").split(/\r?\n/);
  const byLine = new Map();
  const messages = [];
  const commands = [];
  const nativePlanEvents = [];
  const changes = [];
  const startedChanges = [];
  let completedTurn = false;
  let turnStartSeen = false;
  let turnStartLine = null;
  let failureSeen = false;
  let validStartedPrefix = true;
  if (lines.length > MAX_JSONL_LINES) fail(`${label} exceeds the event-line limit`);
  for (let index = 0; index < lines.length; index += 1) {
    const raw = lines[index];
    if (raw.trim() === "") continue;
    let event;
    try {
      event = JSON.parse(raw);
    } catch (_error) {
      fail(`${label} contains malformed JSONL at line ${index + 1}`);
    }
    if (!isObject(event) || !nonempty(event.type)) fail(`${label} contains a malformed event at line ${index + 1}`);
    const item = isObject(event.item) ? event.item : null;
    const parsed = { turn, line: index + 1, event, item };
    byLine.set(index + 1, parsed);
    if (event.type === "turn.started") {
      if (turnStartSeen) validStartedPrefix = false;
      turnStartSeen = true;
      if (turnStartLine === null) turnStartLine = parsed.line;
    }
    if (event.type === "turn.failed" || event.type === "error") {
      failureSeen = true;
      if (completedTurn) validStartedPrefix = false;
    }
    if (completedTurn && (event.type === "turn.completed" || event.type.startsWith("item."))) {
      validStartedPrefix = false;
    }
    if (event.type.startsWith("item.") && (!turnStartSeen || !item || !nonempty(item.type))) {
      validStartedPrefix = false;
    }
    if (event.type === "item.completed" && item && item.type === "agent_message" && typeof item.text !== "string") {
      validStartedPrefix = false;
    }
    if (event.type === "item.completed" && item && item.type === "file_change") {
      const validStatus = ["completed", "failed"].includes(item.status);
      const validChanges = Array.isArray(item.changes) && item.changes.every((change) =>
        isObject(change) && nonempty(change.path) && nonempty(change.kind));
      if (!validStatus || !validChanges) validStartedPrefix = false;
    }
    if (event.type === "turn.completed") {
      if (!turnStartSeen || failureSeen) validStartedPrefix = false;
      completedTurn = true;
    }
    if (["item.completed", "item.started", "item.updated"].includes(event.type) && item) {
      if (event.type === "item.completed" && item.type === "agent_message" && typeof item.text === "string") messages.push(parsed);
      if (item.type === "command_execution") commands.push(parsed);
      if (item.type === "todo_list") nativePlanEvents.push(parsed);
      if (event.type === "item.started" && item.type === "file_change" && Array.isArray(item.changes)) {
        for (const change of item.changes) {
          if (isObject(change) && nonempty(change.path)) {
            startedChanges.push({
              operationId: nonempty(item.id) ? item.id : null,
              path: change.path,
              line: parsed.line,
              matched: false,
            });
          }
        }
      }
      if (event.type === "item.completed" && item.type === "file_change" && item.status === "completed" && Array.isArray(item.changes)) {
        for (const change of item.changes) {
          if (!isObject(change) || !nonempty(change.path)) continue;
          const operationId = nonempty(item.id) ? item.id : null;
          const start = operationId
            ? startedChanges.find((candidate) => !candidate.matched
              && candidate.operationId === operationId
              && candidate.path === change.path)
            : null;
          if (start) start.matched = true;
          changes.push({
            ...parsed,
            change,
            startLine: start ? start.line : parsed.line,
          });
        }
      }
    }
  }
  const validTurnStartPrefix = turnStartSeen && validStartedPrefix;
  return { turn, byLine, messages, commands, nativePlanEvents, changes, completedTurn, turnStartLine, validStartedPrefix: validTurnStartPrefix };
}

function referenceKey(ref) {
  if (!isObject(ref) || !Number.isInteger(ref.turn) || !Number.isInteger(ref.line)) return null;
  return `${ref.turn}:${ref.line}`;
}

function compareOrder(left, right) {
  return left.turn === right.turn ? left.line - right.line : left.turn - right.turn;
}

function lineEvent(transcripts, ref) {
  if (!isObject(ref) || !Number.isInteger(ref.turn) || !Number.isInteger(ref.line) || ref.turn < 1 || ref.line < 1) return null;
  const transcript = transcripts.get(ref.turn);
  return transcript && transcript.validStartedPrefix ? transcript.byLine.get(ref.line) || null : null;
}

function isAgentMessage(transcripts, ref) {
  const parsed = lineEvent(transcripts, ref);
  return parsed && parsed.event.type === "item.completed" && parsed.item && parsed.item.type === "agent_message" && typeof parsed.item.text === "string";
}

function isNativeTodoListEvent(parsed) {
  return Boolean(parsed
    && parsed.item
    && parsed.item.type === "todo_list"
    && ["item.started", "item.updated", "item.completed"].includes(parsed.event.type));
}

function boundedMessageSpan(transcripts, ref, span) {
  const parsed = lineEvent(transcripts, ref);
  if (!parsed || parsed.event.type !== "item.completed" || !parsed.item || parsed.item.type !== "agent_message"
    || typeof parsed.item.text !== "string" || !isObject(span) || !Number.isInteger(span.start) || !Number.isInteger(span.end)) return null;
  const text = parsed.item.text;
  if (span.start < 0 || span.end <= span.start || span.end > text.length) return null;
  if (text.slice(span.start, span.end).trim().length === 0) return null;
  return { turn: parsed.turn, line: parsed.line, start: span.start, end: span.end };
}

function compareSpanOrder(left, right) {
  const eventOrder = compareOrder(left, right);
  if (eventOrder !== 0) return eventOrder;
  if (left.end <= right.start) return -1;
  if (right.end <= left.start) return 1;
  return null;
}

function compareCarryPlanOrder(carryRef, planRef) {
  if (carryRef.message && !planRef.native) return compareSpanOrder(carryRef, planRef);
  return compareOrder(carryRef, planRef);
}

function isCarryEvent(transcripts, ref) {
  const parsed = lineEvent(transcripts, ref);
  if (!parsed || parsed.event.type !== "item.completed" || !parsed.item) return false;
  if (parsed.item.type === "agent_message") return typeof parsed.item.text === "string" && parsed.item.text.trim().length > 0;
  if (parsed.item.type === "command_execution") return parsed.item.status === "completed" && Number(parsed.item.exit_code) === 0 && nonempty(parsed.item.aggregated_output);
  if (parsed.item.type === "file_change") return parsed.item.status === "completed" && Array.isArray(parsed.item.changes) && parsed.item.changes.length > 0;
  return false;
}

function normalizedCarryReference(transcripts, ref) {
  const parsed = lineEvent(transcripts, ref);
  if (!parsed || !isCarryEvent(transcripts, ref)) return null;
  if (parsed.item.type === "agent_message") {
    const span = boundedMessageSpan(transcripts, ref, ref.text_span);
    return span ? { ...span, message: true } : null;
  }
  if (Object.prototype.hasOwnProperty.call(ref, "text_span")) return null;
  return { turn: parsed.turn, line: parsed.line, message: false };
}

function manifestMap(admitted, label) {
  if (!admitted) return null;
  const manifest = parseJson(admitted.bytes, label);
  if (!isObject(manifest)) fail(`${label} must map project-relative paths to SHA-256 values`);
  for (const [relative, digest] of Object.entries(manifest)) {
    safeProjectRelativePath(relative, `${label} path`);
    if (typeof digest !== "string" || !SHA256.test(digest)) fail(`${label} contains an invalid file hash`);
  }
  return manifest;
}

function initialWorkspaceBaselineMap(oracleCase) {
  const baseline = oracleCase.initial_workspace_sha256;
  if (!isObject(baseline) || Object.keys(baseline).length === 0) return null;
  for (const [relative, digest] of Object.entries(baseline)) {
    if (!isSafeProjectRelativePath(relative) || typeof digest !== "string" || !SHA256.test(digest)) return null;
  }
  return baseline;
}

function matchesInitialWorkspaceBaseline(before, baseline) {
  const projectEntries = Object.entries(before).filter(([relative]) => !relative.startsWith(".codex/"));
  if (projectEntries.length !== Object.keys(baseline).length) return false;
  return projectEntries.every(([relative, digest]) => baseline[relative] === digest);
}

function changedManifestPaths(before, after) {
  const paths = new Set([...Object.keys(before), ...Object.keys(after)]);
  return [...paths].filter((filePath) => before[filePath] !== after[filePath]).sort();
}

function parseDiffPaths(diffText) {
  const lines = diffText.split(/\r?\n/);
  if (lines.length > MAX_JSONL_LINES) return null;
  const paths = new Set();
  let current = null;
  let sectionCount = 0;

  const safeDiffPath = (value) => isSafeProjectRelativePath(value) ? value : null;
  const parseGitHeader = (line) => {
    const prefix = "diff --git a/";
    if (!line.startsWith(prefix)) return null;
    const body = line.slice(prefix.length);
    const separator = body.indexOf(" b/");
    if (separator < 0 || body.indexOf(" b/", separator + 3) >= 0) return null;
    const from = safeDiffPath(body.slice(0, separator));
    const to = safeDiffPath(body.slice(separator + 3));
    return from && to ? { from, to } : null;
  };
  const finishSection = () => {
    if (!current) return true;
    const isRename = current.from !== current.to;
    if (isRename) {
      if (current.renameFrom !== current.from || current.renameTo !== current.to) return false;
    } else if (current.renameFrom !== null || current.renameTo !== null) {
      return false;
    }
    if (current.hunkOldRemaining !== null || current.hunkNewRemaining !== null) return false;
    const hasOldFileHeader = current.oldFileHeader !== null;
    const hasNewFileHeader = current.newFileHeader !== null;
    if (hasOldFileHeader !== hasNewFileHeader) return false;
    if (current.sawHunk && !hasOldFileHeader) return false;
    if (hasOldFileHeader) {
      const expectedOld = current.newFile ? "/dev/null" : `a/${current.from}`;
      const expectedNew = current.deletedFile ? "/dev/null" : `b/${current.to}`;
      if (current.oldFileHeader !== expectedOld || current.newFileHeader !== expectedNew) return false;
    }
    paths.add(current.from);
    paths.add(current.to);
    return true;
  };
  const parseFileHeaderPath = (line, marker) => {
    if (!line.startsWith(`${marker} `)) return null;
    const value = line.slice(marker.length + 1).split("\t", 1)[0];
    return value === "/dev/null" || safeDiffPath(value.slice(2)) && (value.startsWith("a/") || value.startsWith("b/"))
      ? value
      : null;
  };

  for (const line of lines) {
    if (line.startsWith("diff --git ")) {
      if (!finishSection()) return null;
      sectionCount += 1;
      if (sectionCount > MAX_DIFF_PATHS) return null;
      const header = parseGitHeader(line);
      if (!header) return null;
      current = {
        ...header,
        renameFrom: null,
        renameTo: null,
        oldFileHeader: null,
        newFileHeader: null,
        newFile: false,
        deletedFile: false,
        sawHunk: false,
        hunkOldRemaining: null,
        hunkNewRemaining: null,
      };
      continue;
    }
    if (line.startsWith("diff --")) return null;
    if (current && current.hunkOldRemaining !== null) {
      if (line.startsWith("\\ No newline at end of file")) continue;
      const prefix = line[0];
      if (prefix === " ") {
        current.hunkOldRemaining -= 1;
        current.hunkNewRemaining -= 1;
      } else if (prefix === "-") {
        current.hunkOldRemaining -= 1;
      } else if (prefix === "+") {
        current.hunkNewRemaining -= 1;
      } else {
        return null;
      }
      if (current.hunkOldRemaining < 0 || current.hunkNewRemaining < 0) return null;
      if (current.hunkOldRemaining === 0 && current.hunkNewRemaining === 0) {
        current.hunkOldRemaining = null;
        current.hunkNewRemaining = null;
      }
      continue;
    }
    if (line.startsWith("rename from ") || line.startsWith("rename to ")) {
      if (!current || current.sawHunk) return null;
      const isFrom = line.startsWith("rename from ");
      const field = isFrom ? "renameFrom" : "renameTo";
      const renamePath = safeDiffPath(line.slice(isFrom ? 12 : 10));
      if (!renamePath || current[field] !== null) return null;
      current[field] = renamePath;
      continue;
    }
    if (line.startsWith("new file mode ") || line.startsWith("deleted file mode ")) {
      if (!current || current.sawHunk) return null;
      const isNew = line.startsWith("new file mode ");
      if ((isNew && current.newFile) || (!isNew && current.deletedFile)) return null;
      current[isNew ? "newFile" : "deletedFile"] = true;
      continue;
    }
    if (line.startsWith("--- ")) {
      if (!current || current.sawHunk || current.oldFileHeader !== null) return null;
      current.oldFileHeader = parseFileHeaderPath(line, "---");
      if (current.oldFileHeader === null) return null;
      continue;
    }
    if (line.startsWith("+++ ")) {
      if (!current || current.sawHunk || current.newFileHeader !== null) return null;
      current.newFileHeader = parseFileHeaderPath(line, "+++");
      if (current.newFileHeader === null) return null;
      continue;
    }
    if (line.startsWith("@@")) {
      if (!current || current.oldFileHeader === null || current.newFileHeader === null) return null;
      const hunk = line.match(/^@@ -\d+(?:,(\d+))? \+\d+(?:,(\d+))? @@(?:.*)$/);
      if (!hunk) return null;
      current.hunkOldRemaining = hunk[1] === undefined ? 1 : Number(hunk[1]);
      current.hunkNewRemaining = hunk[2] === undefined ? 1 : Number(hunk[2]);
      if (!Number.isSafeInteger(current.hunkOldRemaining) || !Number.isSafeInteger(current.hunkNewRemaining)
        || current.hunkOldRemaining > lines.length || current.hunkNewRemaining > lines.length) return null;
      current.sawHunk = true;
      if (current.hunkOldRemaining === 0 && current.hunkNewRemaining === 0) {
        current.hunkOldRemaining = null;
        current.hunkNewRemaining = null;
      }
      continue;
    }
    if ((line.startsWith("---") || line.startsWith("+++")) && !current?.sawHunk) return null;
  }
  if (!finishSection()) return null;
  if (sectionCount === 0 && diffText.trim().length > 0) return null;
  return paths;
}

function normalizeWorkspacePath(filePath, workspaceRoot) {
  const root = path.resolve(workspaceRoot);
  let full;
  if (path.isAbsolute(filePath)) {
    full = path.resolve(filePath);
  } else {
    if (!isSafeProjectRelativePath(filePath)) return null;
    full = path.resolve(root, filePath);
  }
  if (!full.startsWith(`${root}${path.sep}`)) return null;
  const relative = path.relative(root, full).split(path.sep).join("/");
  return isSafeProjectRelativePath(relative) ? relative : null;
}

function unwrapCommandShell(commandText) {
  let command = commandText.trim();
  for (let depth = 0; depth < 3; depth += 1) {
    const wrapper = command.match(/^(?:\/[^\s]+\/)?(?:sh|bash|zsh)\s+-lc\s+([\s\S]+)$/);
    if (!wrapper) break;
    command = wrapper[1].trim();
    if (command.length >= 2
      && ((command[0] === "\"" && command[command.length - 1] === "\"")
        || (command[0] === "'" && command[command.length - 1] === "'"))) {
      const quote = command[0];
      command = command.slice(1, -1);
      if (quote === "\"") command = command.replace(/\\([\\"'$`])/g, "$1");
    }
  }
  return command;
}

function tokenizeBoundedCommand(commandText) {
  if (/[;&|<>`$()\r\n]/.test(commandText)) return null;
  const tokens = [];
  let token = "";
  let quote = null;
  let started = false;
  for (let index = 0; index < commandText.length; index += 1) {
    const character = commandText[index];
    if (quote && character === "\\" && quote === "\"") {
      if (index + 1 >= commandText.length) return null;
      token += commandText[index + 1];
      index += 1;
      started = true;
      continue;
    }
    if (quote) {
      if (character === quote) quote = null;
      else token += character;
      started = true;
      continue;
    }
    if (character === "\"" || character === "'") {
      quote = character;
      started = true;
      continue;
    }
    if (/\s/.test(character)) {
      if (started) tokens.push(token);
      token = "";
      started = false;
      continue;
    }
    if (character === "\\") {
      if (index + 1 >= commandText.length) return null;
      token += commandText[index + 1];
      index += 1;
      started = true;
      continue;
    }
    token += character;
    started = true;
  }
  if (quote) return null;
  if (started) tokens.push(token);
  return tokens;
}

function commandReadsProjectPath(commandText, requiredPath, workspaceRoot) {
  if (typeof commandText !== "string") return false;
  const tokens = tokenizeBoundedCommand(unwrapCommandShell(commandText));
  if (!tokens || tokens.length < 2) return false;
  if (path.posix.basename(tokens[0]) !== "cat") return false;
  const operands = tokens.slice(1);
  if (operands[0] === "--") operands.shift();
  return operands.length === 1 && normalizeWorkspacePath(operands[0], workspaceRoot) === requiredPath;
}

function reportsMissingProjectPath(output, requiredPath, workspaceRoot) {
  if (typeof output !== "string") return false;
  return output.split(/\r?\n/).some((line) => {
    const match = line.match(/^cat: (.+): No such file or directory$/);
    return Boolean(match && normalizeWorkspacePath(match[1], workspaceRoot) === requiredPath);
  });
}

function isRequiredMissingPolicyRead(parsed, requiredPath, workspaceRoot, turnStartLine) {
  const item = parsed && parsed.item;
  return Boolean(parsed
    && parsed.event.type === "item.completed"
    && parsed.line > turnStartLine
    && item
    && item.type === "command_execution"
    && item.status === "completed"
    && Number.isInteger(item.exit_code)
    && item.exit_code !== 0
    && commandReadsProjectPath(item.command, requiredPath, workspaceRoot)
    && reportsMissingProjectPath(item.aggregated_output, requiredPath, workspaceRoot));
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const reviewBytes = readRegularFile(path.resolve(args["--review"]), MAX_REVIEW_BYTES, "review");
  if (!reviewBytes) fail("review file is unavailable");
  const oracleBytes = readRegularFile(path.resolve(args["--oracle"]), MAX_REVIEW_BYTES, "oracle");
  if (!oracleBytes) fail("oracle file is unavailable");
  const rootPath = path.resolve(args["--evidence-root"]);
  let rootStat;
  try {
    rootStat = fs.lstatSync(rootPath);
  } catch (_error) {
    fail("evidence root is unavailable");
  }
  if (rootStat.isSymbolicLink() || !rootStat.isDirectory()) fail("evidence root must be a non-symlink directory");
  const root = fs.realpathSync(rootPath);
  const review = parseJson(reviewBytes, "review");
  const oracle = parseJson(oracleBytes, "oracle");
  requireKeys(review, ["schema_version", "case_id", "actor_id", "execution_mode", "workspace_root", "activation", "inputs", "transcripts", "workspace_observation", "semantic_review"], "review");
  if (review.schema_version !== "clarification-evidence/v1") fail("review schema_version is unsupported");
  if (!nonempty(review.case_id) || !nonempty(review.actor_id)) fail("review case_id and actor_id are required");
  if (!["native", "forced_skill_load", "offline_proxy"].includes(review.execution_mode)) fail("review execution_mode is unsupported");
  if (!nonempty(review.workspace_root) || !path.isAbsolute(review.workspace_root)) fail("review workspace_root must be absolute");
  if (!isObject(oracle) || oracle.schema_version !== "clarification-oracle/v1" || !Array.isArray(oracle.cases)) fail("oracle schema is unsupported");
  const oracleCase = oracle.cases.find((entry) => entry.case_id === review.case_id);
  if (!oracleCase || !Array.isArray(oracleCase.hidden_material_decisions)) fail("review case is not bound to a valid oracle entry");
  const oracleDigest = sha256(oracleBytes);
  const initialWorkspaceBaseline = initialWorkspaceBaselineMap(oracleCase);
  const hasRequiredMissingPolicyRead = Object.prototype.hasOwnProperty.call(oracleCase, "required_missing_policy_path");
  const requiredMissingPolicyPath = isSafeProjectRelativePath(oracleCase.required_missing_policy_path)
    ? oracleCase.required_missing_policy_path : null;
  const expectedDecisionCount = oracleCase.hidden_material_decisions.length;
  const expectedDecisionIndexes = new Set(Array.from({ length: expectedDecisionCount }, (_value, index) => index));
  const requiresTask05PolicyConflict = review.case_id === "task-05";
  const requiredPolicyConflict = oracleCase.required_policy_conflict;
  const requiredPolicyClaims = ["conflict_identified", "security_impact_explained"];
  const task05PolicyConflictRequirementValid = !requiresTask05PolicyConflict
    || (isObject(requiredPolicyConflict)
      && Number.isInteger(requiredPolicyConflict.decision_index)
      && expectedDecisionIndexes.has(requiredPolicyConflict.decision_index)
      && Array.isArray(requiredPolicyConflict.source_paths)
      && requiredPolicyConflict.source_paths.length === 2
      && new Set(requiredPolicyConflict.source_paths).size === requiredPolicyConflict.source_paths.length
      && requiredPolicyConflict.source_paths.every(isSafeProjectRelativePath)
      && Array.isArray(requiredPolicyConflict.claims)
      && requiredPolicyConflict.claims.length === requiredPolicyClaims.length
      && requiredPolicyClaims.every((claim) => requiredPolicyConflict.claims.includes(claim)));
  const admitted = artifactReader(root);
  const unavailableReasons = admitted.unavailable;
  if (!task05PolicyConflictRequirementValid) unavailableReasons.push("policy_conflict_assessment_unavailable");
  let initialWorkspaceBaselineStatus = "unavailable";
  if (!initialWorkspaceBaseline) unavailableReasons.push("initial_workspace_baseline_unavailable");
  const hasRequiredContinuation = Object.prototype.hasOwnProperty.call(oracleCase, "continuation_answer_file");
  let continuationBinding = null;
  const continuationAnswerArtifacts = new Map();
  if (hasRequiredContinuation) {
    const requirements = isObject(review.oracle_requirements) ? review.oracle_requirements : null;
    let expectedAnswerRelative = null;
    if (isSafeProjectRelativePath(oracleCase.continuation_answer_file)) {
      const oraclePath = fs.realpathSync(path.resolve(args["--oracle"]));
      const oracleDirectory = path.dirname(oraclePath);
      const declaredAnswerPath = path.resolve(oracleDirectory, oracleCase.continuation_answer_file);
      const relativeToEvidenceRoot = path.relative(root, declaredAnswerPath);
      if (relativeToEvidenceRoot && !relativeToEvidenceRoot.startsWith(".." + path.sep)
        && relativeToEvidenceRoot !== ".." && !path.isAbsolute(relativeToEvidenceRoot)) {
        expectedAnswerRelative = relativeToEvidenceRoot.split(path.sep).join("/");
      }
    }
    const requiredAnswerTurns = requirements && Array.isArray(requirements.required_answer_turns)
      ? requirements.required_answer_turns : [];
    const requiredPostAnswerIndexes = requirements && Array.isArray(requirements.required_post_answer_question_decision_indexes)
      ? requirements.required_post_answer_question_decision_indexes : [];
    const answerEntries = requirements && Array.isArray(requirements.continuation_answers)
      ? requirements.continuation_answers : [];
    const answerEntriesByTurn = new Map();
    let answerEntriesValid = Boolean(expectedAnswerRelative)
      && answerEntries.length === requiredAnswerTurns.length;
    for (const answerEntry of answerEntries) {
      if (!isObject(answerEntry) || !Number.isInteger(answerEntry.turn)
        || !requiredAnswerTurns.includes(answerEntry.turn)
        || answerEntriesByTurn.has(answerEntry.turn)
        || !isObject(answerEntry.expected_artifact)
        || answerEntry.expected_artifact.path !== expectedAnswerRelative) {
        answerEntriesValid = false;
        continue;
      }
      answerEntriesByTurn.set(answerEntry.turn, answerEntry);
    }
    if (answerEntriesByTurn.size !== requiredAnswerTurns.length) answerEntriesValid = false;
    if (answerEntriesValid) {
      for (const [turn, answerEntry] of answerEntriesByTurn) {
        const expectedAnswer = admitted.read(answerEntry.expected_artifact, "continuation_answer_turn_" + turn);
        if (expectedAnswer) continuationAnswerArtifacts.set(turn, expectedAnswer);
        else answerEntriesValid = false;
      }
    }
    const bindingValid = Boolean(requirements)
      && nonempty(oracleCase.continuation_answer_file)
      && requirements.oracle_case_id === review.case_id
      && requirements.oracle_sha256 === oracleDigest
      && Array.isArray(requirements.required_answer_turns)
      && requiredAnswerTurns.length === 1
      && requiredAnswerTurns[0] === 2
      && new Set(requiredAnswerTurns).size === requiredAnswerTurns.length
      && Array.isArray(requirements.required_post_answer_question_decision_indexes)
      && requiredPostAnswerIndexes.length > 0
      && new Set(requiredPostAnswerIndexes).size === requiredPostAnswerIndexes.length
      && requiredPostAnswerIndexes.every((index) => Number.isInteger(index) && expectedDecisionIndexes.has(index));
    const basis = requirements && isObject(requirements.applicability_basis) ? requirements.applicability_basis : null;
    const basisArtifact = basis ? admitted.read(basis.artifact, "continuation_applicability_basis") : null;
    const basisValid = Boolean(basisArtifact)
      && basis
      && nonempty(basis.record_ref)
      && nonempty(basis.rationale);
    if (!bindingValid || !basisValid || !answerEntriesValid) {
      unavailableReasons.push("continuation_applicability_unavailable");
    } else {
      continuationBinding = {
        requiredAnswerTurns,
        requiredPostAnswerQuestionDecisionIndexes: requiredPostAnswerIndexes,
        applicabilityBasis: {
          artifact: basisArtifact.relative,
          sha256: basisArtifact.digest,
          record_ref: basis.record_ref,
          rationale: basis.rationale,
        },
      };
    }
  } else if (Object.prototype.hasOwnProperty.call(review, "oracle_requirements")) {
    unavailableReasons.push("continuation_applicability_oracle_mismatch");
  }
  const admittedInputList = [];
  const inputTurns = new Map();
  const inputs = Array.isArray(review.inputs) ? review.inputs : [];
  if (!Array.isArray(review.inputs)) unavailableReasons.push("controller_input_receipts_missing");
  for (const input of inputs) {
    if (!isObject(input) || !Number.isInteger(input.turn) || input.turn < 1 || !["initial_prompt", "answer"].includes(input.kind)) {
      fail("controller input entries require a positive turn and supported kind");
    }
    if (inputTurns.has(input.turn)) fail("controller input turns must be unique");
    const record = admitted.read(input.artifact, `input_turn_${input.turn}`);
    if (record && record.bytes.toString("utf8").trim().length === 0) unavailableReasons.push(`input_turn_${input.turn}_empty`);
    inputTurns.set(input.turn, { ...input, record });
    admittedInputList.push({ ...input, record });
  }
  const continuationAnswerPayloadMatches = new Set();
  const continuationAnswerPayloadMismatchTurns = [];
  if (continuationBinding) {
    for (const turn of continuationBinding.requiredAnswerTurns) {
      const expected = continuationAnswerArtifacts.get(turn);
      const received = inputTurns.get(turn);
      if (!received || received.kind !== "answer" || !received.record) continue;
      if (expected && Buffer.compare(expected.bytes, received.record.bytes) === 0) {
        continuationAnswerPayloadMatches.add(turn);
      } else {
        continuationAnswerPayloadMismatchTurns.push(turn);
        unavailableReasons.push("required_continuation_answer_payload_mismatch");
      }
    }
  }
  const prompts = admittedInputList.filter((input) => input.kind === "initial_prompt");
  const answers = admittedInputList.filter((input) => input.kind === "answer").sort((a, b) => a.turn - b.turn);
  let initialPromptBindingValid = false;
  if (prompts.length !== 1 || !prompts[0] || prompts[0].turn !== 1 || !prompts[0].record) {
    unavailableReasons.push("initial_prompt_receipt_unavailable");
    unavailableReasons.push("initial_prompt_oracle_binding_unavailable");
  } else if (typeof oracleCase.initial_prompt_sha256 !== "string" || !SHA256.test(oracleCase.initial_prompt_sha256)) {
    unavailableReasons.push("initial_prompt_oracle_binding_unavailable");
  } else if (prompts[0].record.digest !== oracleCase.initial_prompt_sha256) {
    unavailableReasons.push("initial_prompt_payload_mismatch");
  } else {
    initialPromptBindingValid = true;
  }
  if (answers.some((answer, index) => !answer.record || answer.turn <= 1 || (index > 0 && answer.turn <= answers[index - 1].turn))) unavailableReasons.push("answer_receipt_order_unavailable");

  const transcripts = new Map();
  const transcriptEntries = Array.isArray(review.transcripts) ? review.transcripts : [];
  if (!Array.isArray(review.transcripts) || transcriptEntries.length === 0) unavailableReasons.push("native_transcript_missing");
  const orderedTranscriptEntries = [...transcriptEntries].sort((a, b) => (a && a.turn || 0) - (b && b.turn || 0));
  for (const entry of orderedTranscriptEntries) {
    if (!isObject(entry) || !Number.isInteger(entry.turn) || entry.turn < 1) {
      unavailableReasons.push("transcript_turn_identity_unavailable");
      continue;
    }
    if (transcripts.has(entry.turn)) {
      unavailableReasons.push("transcript_turn_duplicate");
      continue;
    }
    const record = admitted.read(entry.artifact, `transcript_turn_${entry.turn}`);
    const parsed = parseTranscript(entry.turn, record, `transcript turn ${entry.turn}`);
    if (!parsed) continue;
    if (!parsed.completedTurn) unavailableReasons.push("transcript_turn_" + entry.turn + "_completion_unavailable");
    if (!parsed.validStartedPrefix) unavailableReasons.push("transcript_turn_" + entry.turn + "_started_prefix_unavailable");
    transcripts.set(entry.turn, parsed);
  }
  const inputTurnNumbers = [...inputTurns.keys()].sort((a, b) => a - b);
  const transcriptTurnNumbers = [...transcripts.keys()].sort((a, b) => a - b);
  const contiguousInputTurns = inputTurnNumbers.every((turn, index) => turn === index + 1);
  const transcriptCoverageMatches = inputTurnNumbers.length === transcriptTurnNumbers.length
    && inputTurnNumbers.every((turn, index) => turn === transcriptTurnNumbers[index]);
  if (!contiguousInputTurns || !transcriptCoverageMatches) unavailableReasons.push("transcript_turn_coverage_mismatch");
  for (const input of admittedInputList) {
    const transcript = transcripts.get(input.turn);
    if (!transcript || !transcript.completedTurn) {
      unavailableReasons.push(input.kind === "initial_prompt"
        ? "initial_prompt_response_transcript_unavailable"
        : `answer_turn_${input.turn}_response_transcript_unavailable`);
    }
  }
  for (const turn of transcriptTurnNumbers) {
    if (!inputTurns.has(turn)) unavailableReasons.push(`transcript_turn_${turn}_without_controller_input`);
  }

  const activation = isObject(review.activation) ? review.activation : {};
  const skillName = activation.skill_name;
  const validSkillName = nonempty(skillName) && /^[a-z0-9][a-z0-9-]*$/.test(skillName);
  const activationReasons = [];
  if (!validSkillName && review.execution_mode === "forced_skill_load") activationReasons.push("skill_identity_unavailable");
  let stagedSkillCommandReferenceStatus = "unavailable";
  const skillCommandRef = activation.skill_read_ref;
  if (skillCommandRef) {
    const parsed = lineEvent(transcripts, skillCommandRef);
    const item = parsed && parsed.item;
    const skillPath = validSkillName ? `.agents/skills/${skillName}/SKILL.md` : null;
    const referencesStagedSkill = item && item.type === "command_execution"
      && typeof item.command === "string" && skillPath !== null && item.command.includes(skillPath);
    if (parsed && parsed.event.type === "item.completed" && referencesStagedSkill && item.status === "completed") {
      stagedSkillCommandReferenceStatus = "observed";
    } else {
      activationReasons.push("staged_skill_command_reference_not_observed");
    }
  } else {
    activationReasons.push("staged_skill_command_reference_not_observed");
  }
  const skillFileReadAttestation = "not_attested";
  let activationStatus;
  let nativeSelectionStatus;
  if (review.execution_mode === "native") {
    nativeSelectionStatus = "unavailable";
    activationStatus = "native_selection_unavailable";
  } else if (review.execution_mode === "forced_skill_load") {
    nativeSelectionStatus = "not_applicable_forced_load";
    const receipt = admitted.read(activation.forced_load_receipt, "forced_load_receipt", activationReasons);
    let validForcedReceipt = false;
    if (receipt) {
      const receiptJson = parseJson(receipt.bytes, "forced load receipt");
      validForcedReceipt = isObject(receiptJson) && receiptJson.invocation_mode === "forced_skill_load" && receiptJson.skill_name === skillName;
    }
    if (!validForcedReceipt) {
      activationReasons.push("forced_load_receipt_unavailable");
    }
    activationStatus = validForcedReceipt ? "forced_load" : "forced_load_unavailable";
  } else {
    nativeSelectionStatus = "not_applicable_text_proxy";
    activationStatus = "text_proxy_only";
  }
  if (review.execution_mode === "native") activationReasons.push("native_selection_unavailable");
  for (const reason of activationReasons) unavailableReasons.push(reason);

  const observation = isObject(review.workspace_observation) ? review.workspace_observation : {};
  const beforeRecord = admitted.read(observation.before_manifest, "before_manifest");
  const afterRecord = admitted.read(observation.after_manifest, "after_manifest");
  const diffRecord = admitted.read(observation.diff, "workspace_diff");
  let changedPaths = null;
  let frameworkStatePaths = null;
  let projectChangedPaths = null;
  let stableProjectPaths = null;
  let diffText = null;
  if (!beforeRecord || !afterRecord || !diffRecord) {
    unavailableReasons.push("workspace_change_observation_unavailable");
  } else {
    const before = manifestMap(beforeRecord, "before manifest");
    const after = manifestMap(afterRecord, "after manifest");
    if (initialWorkspaceBaseline) {
      if (matchesInitialWorkspaceBaseline(before, initialWorkspaceBaseline)) {
        initialWorkspaceBaselineStatus = "matched";
      } else {
        unavailableReasons.push("initial_workspace_baseline_unavailable");
      }
    }
    changedPaths = changedManifestPaths(before, after);
    frameworkStatePaths = changedPaths.filter((filePath) => filePath.startsWith(".codex/"));
    projectChangedPaths = changedPaths.filter((filePath) => !filePath.startsWith(".codex/"));
    stableProjectPaths = Object.keys(before).filter((filePath) =>
      !filePath.startsWith(".codex/") && Object.prototype.hasOwnProperty.call(after, filePath) && before[filePath] === after[filePath]);
    diffText = diffRecord.bytes.toString("utf8");
  }

  const observedChanges = new Map();
  if (changedPaths !== null) {
    for (const transcript of transcripts.values()) {
      if (!transcript.validStartedPrefix) continue;
      for (const observed of transcript.changes) {
        const relative = normalizeWorkspacePath(observed.change.path, review.workspace_root);
        if (!relative || relative.startsWith(".codex/")) continue;
        if (!observedChanges.has(relative)) observedChanges.set(relative, []);
        observedChanges.get(relative).push({
          turn: observed.turn,
          line: observed.startLine,
          completionTurn: observed.turn,
          completionLine: observed.line,
          kind: observed.change.kind,
        });
      }
    }
    for (const changedPath of projectChangedPaths) {
      if (!observedChanges.has(changedPath)) unavailableReasons.push("changed_file_order_telemetry_unavailable");
    }
    for (const observedPath of observedChanges.keys()) {
      if (!changedPaths.includes(observedPath) && !stableProjectPaths.includes(observedPath)) {
        unavailableReasons.push("file_event_manifest_mismatch");
      }
    }
    const diffPaths = parseDiffPaths(diffText);
    if (!diffPaths) {
      unavailableReasons.push("workspace_diff_paths_unavailable");
    } else {
      const projectDiffPaths = new Set([...diffPaths].filter((filePath) => !filePath.startsWith(".codex/")));
      const projectManifestPaths = new Set(projectChangedPaths);
      if (projectChangedPaths.some((changedPath) => !projectDiffPaths.has(changedPath))) {
        unavailableReasons.push("changed_file_diff_context_unavailable");
      }
      if (projectDiffPaths.size !== projectManifestPaths.size
        || [...projectDiffPaths].some((filePath) => !projectManifestPaths.has(filePath))) {
        unavailableReasons.push("workspace_diff_manifest_mismatch");
      }
    }
  }

  const semanticReview = isObject(review.semantic_review) ? review.semantic_review : {};
  let missingPolicyReadStatus = hasRequiredMissingPolicyRead ? "unavailable" : "not_required";
  if (hasRequiredMissingPolicyRead) {
    const initialTranscript = transcripts.get(1);
    const explicitReadRef = semanticReview.missing_policy_read_ref;
    let validReadObserved = false;
    if (requiredMissingPolicyPath && initialTranscript && initialTranscript.validStartedPrefix
      && Number.isInteger(initialTranscript.turnStartLine)) {
      if (explicitReadRef !== undefined) {
        const explicitEvent = lineEvent(transcripts, explicitReadRef);
        validReadObserved = explicitReadRef.turn === 1
          && isRequiredMissingPolicyRead(explicitEvent, requiredMissingPolicyPath, review.workspace_root, initialTranscript.turnStartLine);
      } else {
        validReadObserved = initialTranscript.commands.some((command) =>
          isRequiredMissingPolicyRead(command, requiredMissingPolicyPath, review.workspace_root, initialTranscript.turnStartLine));
      }
    }
    if (validReadObserved) missingPolicyReadStatus = "observed";
    else unavailableReasons.push("required_missing_policy_read_unavailable");
  }
  const planningApplicability = isObject(semanticReview.planning_applicability) ? semanticReview.planning_applicability : null;
  const planningAssessmentMap = new Map();
  const nativePlanEvents = [...transcripts.values()].flatMap((transcript) => transcript.nativePlanEvents);
  const nativePlanAssessmentMap = new Map();
  let planningRequirement = "unavailable";
  let planningCoverageValid = false;
  const frozenPlanningRequirement = oracleCase.planning_requirement;
  if (!planningApplicability
    || !["before_plan", "before_edit_only"].includes(frozenPlanningRequirement)
    || planningApplicability.oracle_case_id !== review.case_id
    || planningApplicability.oracle_sha256 !== oracleDigest
    || planningApplicability.requirement !== frozenPlanningRequirement
    || !nonempty(planningApplicability.rationale)) {
    unavailableReasons.push("planning_applicability_unavailable");
  } else {
    planningRequirement = frozenPlanningRequirement;
    if (planningRequirement === "before_edit_only") {
      planningCoverageValid = true;
    } else {
      let validPlanningCoverage = planningApplicability.coverage_attestation === "reviewed_every_completed_agent_message_for_dependent_planning"
        && Array.isArray(semanticReview.dependent_planning_assessments);
      for (const assessment of Array.isArray(semanticReview.dependent_planning_assessments) ? semanticReview.dependent_planning_assessments : []) {
        if (!isObject(assessment)
          || !Number.isInteger(assessment.decision_index)
          || !expectedDecisionIndexes.has(assessment.decision_index)
          || planningAssessmentMap.has(assessment.decision_index)
          || !["dependent_plan_observed", "no_dependent_plan"].includes(assessment.outcome)
          || !Array.isArray(assessment.plan_refs)
          || !nonempty(assessment.rationale)) {
          validPlanningCoverage = false;
          continue;
        }
        const planRefs = [];
        for (const ref of assessment.plan_refs) {
          if (!isObject(ref) || !Number.isInteger(ref.turn) || !Number.isInteger(ref.line) || !nonempty(ref.rationale)) {
            validPlanningCoverage = false;
            continue;
          }
          if (Object.prototype.hasOwnProperty.call(ref, "text_span")) {
            const span = boundedMessageSpan(transcripts, ref, ref.text_span);
            if (!span) {
              validPlanningCoverage = false;
              continue;
            }
            planRefs.push({ ...span, native: false, rationale: ref.rationale });
          } else {
            const nativeEvent = lineEvent(transcripts, ref);
            if (!isNativeTodoListEvent(nativeEvent)) {
              validPlanningCoverage = false;
              continue;
            }
            planRefs.push({ turn: nativeEvent.turn, line: nativeEvent.line, native: true, rationale: ref.rationale });
          }
        }
        if ((assessment.outcome === "no_dependent_plan" && planRefs.length !== 0)
          || (assessment.outcome === "dependent_plan_observed" && planRefs.length === 0)) {
          validPlanningCoverage = false;
        }
        planningAssessmentMap.set(assessment.decision_index, {
          outcome: assessment.outcome,
          plan_refs: planRefs,
        });
      }
      if (planningAssessmentMap.size !== expectedDecisionCount) validPlanningCoverage = false;
      planningCoverageValid = validPlanningCoverage;
      if (!planningCoverageValid) unavailableReasons.push("dependent_planning_coverage_unavailable");
    }
  }
  let nativePlanningCoverageValid = true;
  if (planningRequirement === "before_plan") {
    const assessments = semanticReview.native_plan_assessments;
    if (nativePlanEvents.length > 0 || assessments !== undefined) {
      nativePlanningCoverageValid = Array.isArray(assessments);
      for (const assessment of Array.isArray(assessments) ? assessments : []) {
        if (!isObject(assessment)
          || !Number.isInteger(assessment.turn)
          || !Number.isInteger(assessment.line)
          || !["dependent_plan_observed", "independent_plan_observed"].includes(assessment.outcome)
          || !Array.isArray(assessment.decision_indexes)
          || !nonempty(assessment.rationale)) {
          nativePlanningCoverageValid = false;
          continue;
        }
        const key = referenceKey(assessment);
        const observed = nativePlanEvents.find((event) => event.turn === assessment.turn && event.line === assessment.line);
        const event = lineEvent(transcripts, assessment);
        if (!key || nativePlanAssessmentMap.has(key) || !observed || !isNativeTodoListEvent(event)
          || new Set(assessment.decision_indexes).size !== assessment.decision_indexes.length) {
          nativePlanningCoverageValid = false;
          continue;
        }
        if (assessment.outcome === "dependent_plan_observed") {
          if (assessment.decision_indexes.length === 0
            || assessment.decision_indexes.some((index) => !expectedDecisionIndexes.has(index))) {
            nativePlanningCoverageValid = false;
          }
        } else if (assessment.decision_indexes.length !== 0) {
          nativePlanningCoverageValid = false;
        }
        nativePlanAssessmentMap.set(key, {
          outcome: assessment.outcome,
          decision_indexes: assessment.decision_indexes,
        });
      }
      if (nativePlanAssessmentMap.size !== nativePlanEvents.length) nativePlanningCoverageValid = false;
      for (const [key, assessment] of nativePlanAssessmentMap) {
        for (const decisionIndex of assessment.decision_indexes) {
          const decisionPlanning = planningAssessmentMap.get(decisionIndex);
          const hasMatchingPlanRef = Boolean(decisionPlanning
            && decisionPlanning.outcome === "dependent_plan_observed"
            && decisionPlanning.plan_refs.some((ref) => ref.native && referenceKey(ref) === key));
          if (assessment.outcome !== "dependent_plan_observed" || !hasMatchingPlanRef) {
            nativePlanningCoverageValid = false;
          }
        }
        if (assessment.outcome === "independent_plan_observed"
          && [...planningAssessmentMap.values()].some((decisionPlanning) =>
            decisionPlanning.plan_refs.some((ref) => ref.native && referenceKey(ref) === key))) {
          nativePlanningCoverageValid = false;
        }
      }
      for (const [decisionIndex, decisionPlanning] of planningAssessmentMap) {
        for (const planRef of decisionPlanning.plan_refs.filter((ref) => ref.native)) {
          const nativeAssessment = nativePlanAssessmentMap.get(referenceKey(planRef));
          if (!nativeAssessment
            || nativeAssessment.outcome !== "dependent_plan_observed"
            || !nativeAssessment.decision_indexes.includes(decisionIndex)) {
            nativePlanningCoverageValid = false;
          }
        }
      }
      if (!nativePlanningCoverageValid) unavailableReasons.push("native_plan_coverage_unavailable");
    }
  }
  const reviewer = isObject(semanticReview.reviewer) ? semanticReview.reviewer : {};
  const reviewIndependent = nonempty(reviewer.id) && reviewer.id !== review.actor_id && reviewer.role === "independent" && semanticReview.attestation === "reviewed_actual_questions_answers_and_file_changes";
  if (!reviewIndependent) unavailableReasons.push("semantic_reviewer_not_independent");
  const semanticTelemetryValid = Array.isArray(semanticReview.decisions) && Array.isArray(semanticReview.question_assessments) && Array.isArray(semanticReview.answer_assessments) && Array.isArray(semanticReview.dependent_edit_refs);
  if (!semanticTelemetryValid) unavailableReasons.push("semantic_review_records_missing");
  let behaviorReasons = [];
  let semanticStatus = "UNAVAILABLE";
  const continuationRequiredAnswerTurns = continuationBinding
    ? continuationBinding.requiredAnswerTurns
    : (hasRequiredContinuation ? [2] : []);
  const continuationPostAnswerDecisionIndexes = continuationBinding
    ? continuationBinding.requiredPostAnswerQuestionDecisionIndexes
    : [];
  const receivedAnswerTurns = answers.filter((answer) => answer.record).map((answer) => answer.turn);
  const completedResponseTurns = [...transcripts.values()]
    .filter((transcript) => transcript.completedTurn)
    .map((transcript) => transcript.turn);
  const missingContinuationAnswerTurns = continuationRequiredAnswerTurns.filter((turn) => !receivedAnswerTurns.includes(turn));
  if (missingContinuationAnswerTurns.length > 0) unavailableReasons.push("required_continuation_answer_missing");
  const incompleteContinuationResponseTurns = continuationRequiredAnswerTurns.filter((turn) =>
    receivedAnswerTurns.includes(turn) && !completedResponseTurns.includes(turn));
  if (incompleteContinuationResponseTurns.length > 0) unavailableReasons.push("required_continuation_response_incomplete");
  let reviewShapeSupported = semanticTelemetryValid && planningCoverageValid && nativePlanningCoverageValid;
  const decisionMap = new Map();
  const questionMap = new Map();
  const questionSpanMap = new Map();
  const answerMap = new Map();
  let relevantContinuationAnswerTurns = [];
  let missingRelevantContinuationAnswerTurns = [...continuationRequiredAnswerTurns];
  const observedPostAnswerQuestionIndexes = new Set();
  let missingPostAnswerQuestionIndexes = [...continuationPostAnswerDecisionIndexes];
  let completedRelevantContinuationTurns = [];
  let task05PolicyConflictClaims = null;

  if (semanticTelemetryValid) {
    for (const decision of semanticReview.decisions) {
      if (!isObject(decision) || !Number.isInteger(decision.decision_index) || !expectedDecisionIndexes.has(decision.decision_index) || decisionMap.has(decision.decision_index) || !["asked", "not_asked"].includes(decision.outcome) || !nonempty(decision.rationale) || !Array.isArray(decision.question_refs)) {
        reviewShapeSupported = false;
        continue;
      }
      decisionMap.set(decision.decision_index, decision);
    }
    if (decisionMap.size !== expectedDecisionCount) reviewShapeSupported = false;
    for (const assessment of semanticReview.question_assessments) {
      if (!isObject(assessment) || !Number.isInteger(assessment.turn) || !Number.isInteger(assessment.line) || !["material", "non_material", "punctuation_only", "not_a_question"].includes(assessment.classification) || !Array.isArray(assessment.decision_indexes) || !nonempty(assessment.rationale)) {
        reviewShapeSupported = false;
        continue;
      }
      const key = referenceKey(assessment);
      if (questionMap.has(key) || !isAgentMessage(transcripts, assessment)) {
        reviewShapeSupported = false;
        continue;
      }
      if (new Set(assessment.decision_indexes).size !== assessment.decision_indexes.length) reviewShapeSupported = false;
      if (assessment.classification === "material") {
        if (assessment.decision_indexes.some((index) => !expectedDecisionIndexes.has(index))) reviewShapeSupported = false;
      } else if (assessment.decision_indexes.length !== 0) {
        reviewShapeSupported = false;
      }
      if (planningRequirement === "before_plan" && assessment.classification === "material") {
        const spans = Array.isArray(assessment.text_spans) ? assessment.text_spans : [];
        const validSpans = [];
        if (spans.length === 0) reviewShapeSupported = false;
        for (const span of spans) {
          const bounded = boundedMessageSpan(transcripts, assessment, span);
          if (!bounded || !Array.isArray(span.decision_indexes) || !nonempty(span.rationale)
            || new Set(span.decision_indexes).size !== span.decision_indexes.length
            || span.decision_indexes.some((index) => !assessment.decision_indexes.includes(index))) {
            reviewShapeSupported = false;
            continue;
          }
          validSpans.push({ ...bounded, decision_indexes: span.decision_indexes });
        }
        const coveredIndexes = new Set(validSpans.flatMap((span) => span.decision_indexes));
        if (assessment.decision_indexes.some((index) => !coveredIndexes.has(index))) reviewShapeSupported = false;
        questionSpanMap.set(key, validSpans);
      }
      questionMap.set(key, assessment);
    }
    for (const transcript of transcripts.values()) {
      for (const message of transcript.messages) {
        if (!questionMap.has(`${message.turn}:${message.line}`)) reviewShapeSupported = false;
      }
    }
    for (const [index, decision] of decisionMap) {
      if (decision.outcome === "asked") {
        if (decision.question_refs.length === 0) reviewShapeSupported = false;
        for (const ref of decision.question_refs) {
          const question = isObject(ref) ? questionMap.get(referenceKey(ref)) : null;
          if (!question || question.classification !== "material" || !question.decision_indexes.includes(index)) reviewShapeSupported = false;
          if (planningRequirement === "before_plan"
            && !(questionSpanMap.get(referenceKey(ref)) || []).some((span) => span.decision_indexes.includes(index))) reviewShapeSupported = false;
        }
      } else if (decision.question_refs.length !== 0) {
        reviewShapeSupported = false;
      }
    }

    if (planningRequirement === "before_plan") {
      for (const [index, planning] of planningAssessmentMap) {
        if (planning.outcome !== "dependent_plan_observed") continue;
        const decision = decisionMap.get(index);
        if (!decision) continue;
        for (const planRef of planning.plan_refs) {
          for (const questionRef of decision.question_refs) {
            for (const questionSpan of (questionSpanMap.get(referenceKey(questionRef)) || []).filter((span) => span.decision_indexes.includes(index))) {
              if (compareSpanOrder(planRef, questionSpan) === null) reviewShapeSupported = false;
            }
          }
        }
      }
      if (!reviewShapeSupported && !unavailableReasons.includes("dependent_planning_coverage_unavailable")) {
        unavailableReasons.push("dependent_planning_coverage_unavailable");
      }
    }

    for (const assessment of semanticReview.answer_assessments) {
      if (!isObject(assessment) || !Number.isInteger(assessment.answer_turn) || !inputTurns.has(assessment.answer_turn) || inputTurns.get(assessment.answer_turn).kind !== "answer" || !["answer_to_question", "unsolicited"].includes(assessment.kind) || !["carried_forward", "pending", "not_carried", "unprompted"].includes(assessment.outcome) || !Array.isArray(assessment.carry_refs) || !Array.isArray(assessment.decision_indexes) || !nonempty(assessment.rationale)) {
        reviewShapeSupported = false;
        continue;
      }
      const key = String(assessment.answer_turn);
      if (answerMap.has(key)) {
        reviewShapeSupported = false;
        continue;
      }
      if (assessment.kind === "unsolicited") {
        if (assessment.question_ref !== null || assessment.outcome !== "unprompted" || assessment.decision_indexes.length !== 0 || assessment.carry_refs.length !== 0) reviewShapeSupported = false;
        answerMap.set(key, assessment);
        continue;
      }
      if (!isObject(assessment.question_ref) || !["carried_forward", "pending", "not_carried"].includes(assessment.outcome) || !isAgentMessage(transcripts, assessment.question_ref) || assessment.question_ref.turn >= assessment.answer_turn) {
        reviewShapeSupported = false;
        continue;
      }
      if (assessment.decision_indexes.some((index) => !expectedDecisionIndexes.has(index))) reviewShapeSupported = false;
      if (assessment.outcome === "carried_forward" && assessment.carry_refs.length === 0) reviewShapeSupported = false;
      if (assessment.outcome !== "carried_forward" && assessment.carry_refs.length !== 0) reviewShapeSupported = false;
      const carryReferences = [];
      for (const ref of assessment.carry_refs) {
        const normalized = normalizedCarryReference(transcripts, ref);
        if (!normalized || normalized.turn < assessment.answer_turn) {
          reviewShapeSupported = false;
          continue;
        }
        carryReferences.push(normalized);
      }
      answerMap.set(key, { ...assessment, carry_refs: carryReferences });
    }
    if (answerMap.size !== answers.length) reviewShapeSupported = false;

    if (planningRequirement === "before_plan") {
      for (const [index, planning] of planningAssessmentMap) {
        if (planning.outcome !== "dependent_plan_observed") continue;
        const decision = decisionMap.get(index);
        if (!decision) continue;
        for (const planRef of planning.plan_refs) {
          for (const questionRef of decision.question_refs) {
            const answer = [...answerMap.values()].find((entry) =>
              referenceKey(entry.question_ref) === referenceKey(questionRef)
              && entry.decision_indexes.includes(index));
            if (!answer || answer.outcome !== "carried_forward") continue;
            for (const carryRef of answer.carry_refs) {
              if (compareCarryPlanOrder(carryRef, planRef) === null) {
                reviewShapeSupported = false;
                unavailableReasons.push("answer_carry_order_unavailable");
              }
            }
          }
        }
      }
    }

    if (requiresTask05PolicyConflict) {
      const assessment = semanticReview.policy_conflict_assessment;
      const policyDecisionIndex = task05PolicyConflictRequirementValid
        ? requiredPolicyConflict.decision_index
        : null;
      let policyAssessmentValid = task05PolicyConflictRequirementValid
        && isObject(assessment)
        && assessment.oracle_case_id === review.case_id
        && assessment.oracle_sha256 === oracleDigest
        && assessment.decision_index === policyDecisionIndex
        && Array.isArray(assessment.source_paths)
        && assessment.source_paths.length === requiredPolicyConflict.source_paths.length
        && new Set(assessment.source_paths).size === assessment.source_paths.length
        && requiredPolicyConflict.source_paths.every((sourcePath) => assessment.source_paths.includes(sourcePath))
        && typeof assessment.conflict_identified === "boolean"
        && typeof assessment.security_impact_explained === "boolean"
        && Array.isArray(assessment.message_spans)
        && assessment.message_spans.length > 0
        && nonempty(assessment.rationale);
      const decision = policyDecisionIndex === null ? null : decisionMap.get(policyDecisionIndex);
      if (!decision) policyAssessmentValid = false;
      for (const spanRef of Array.isArray(assessment && assessment.message_spans) ? assessment.message_spans : []) {
        if (!isObject(spanRef)
          || !Number.isInteger(spanRef.turn)
          || !Number.isInteger(spanRef.line)
          || !isObject(spanRef.text_span)
          || !nonempty(spanRef.rationale)
          || !boundedMessageSpan(transcripts, spanRef, spanRef.text_span)) {
          policyAssessmentValid = false;
        }
      }
      if (!policyAssessmentValid) {
        reviewShapeSupported = false;
        unavailableReasons.push("policy_conflict_assessment_unavailable");
      } else {
        task05PolicyConflictClaims = {
          conflict_identified: assessment.conflict_identified,
          security_impact_explained: assessment.security_impact_explained,
        };
      }
    }

    relevantContinuationAnswerTurns = continuationRequiredAnswerTurns.filter((turn) => {
      if (!continuationAnswerPayloadMatches.has(turn)) return false;
      const answer = answerMap.get(String(turn));
      if (!answer || answer.kind !== "answer_to_question") return false;
      const question = questionMap.get(referenceKey(answer.question_ref));
      return Boolean(question && question.classification === "material" && answer.question_ref.turn < turn);
    });
    missingRelevantContinuationAnswerTurns = continuationRequiredAnswerTurns
      .filter((turn) => !relevantContinuationAnswerTurns.includes(turn));
    if (hasRequiredContinuation
      && missingRelevantContinuationAnswerTurns.some((turn) => receivedAnswerTurns.includes(turn))) {
      unavailableReasons.push("required_continuation_answer_relevance_unavailable");
    }

    if (continuationBinding) {
      for (const [key, question] of questionMap) {
        if (question.classification !== "material") continue;
        for (const index of question.decision_indexes) {
          const indexedDecision = decisionMap.get(index);
          if (!continuationPostAnswerDecisionIndexes.includes(index)
            || !indexedDecision
            || indexedDecision.outcome !== "asked"
            || !indexedDecision.question_refs.some((ref) => referenceKey(ref) === key)) continue;
          if (relevantContinuationAnswerTurns.some((answerTurn) => answerTurn <= question.turn)) {
            observedPostAnswerQuestionIndexes.add(index);
          }
        }
      }
    }
    missingPostAnswerQuestionIndexes = continuationPostAnswerDecisionIndexes
      .filter((index) => !observedPostAnswerQuestionIndexes.has(index));
    completedRelevantContinuationTurns = continuationRequiredAnswerTurns.filter((turn) =>
      relevantContinuationAnswerTurns.includes(turn) && completedResponseTurns.includes(turn));

    const editRefPaths = new Set();
    const editRefs = semanticReview.dependent_edit_refs;
    for (const ref of editRefs) {
      if (!isObject(ref) || !Number.isInteger(ref.turn) || !Number.isInteger(ref.line) || !nonempty(ref.path) || !nonempty(ref.rationale)) {
        reviewShapeSupported = false;
        continue;
      }
      const observed = observedChanges.get(ref.path) || [];
      const hasConfirmedEditReference = observed.some((event) =>
        event.completionTurn === ref.turn
        && (event.completionLine === ref.line
          || (event.line === ref.line && event.line < event.completionLine)));
      if (!hasConfirmedEditReference) reviewShapeSupported = false;
      editRefPaths.add(ref.path);
    }
    const requiredEditPaths = new Set([...(projectChangedPaths || []), ...observedChanges.keys()]);
    if ([...requiredEditPaths].some((filePath) => !editRefPaths.has(filePath))) reviewShapeSupported = false;
    const earliestDependentEdits = [...editRefPaths].map((filePath) => {
      const observed = [...(observedChanges.get(filePath) || [])].sort(compareOrder);
      return observed.length > 0 ? { path: filePath, turn: observed[0].turn, line: observed[0].line } : null;
    });
    if (earliestDependentEdits.some((edit) => edit === null)) reviewShapeSupported = false;

    const completionOnlyUnavailable = (reason) =>
      reason === "initial_prompt_response_transcript_unavailable"
      || reason === "required_continuation_answer_missing"
      || reason === "required_continuation_response_incomplete"
      || /^answer_turn_\d+_response_transcript_unavailable$/.test(reason)
      || /^transcript_turn_\d+_completion_unavailable$/.test(reason);
    const behaviorEvidenceSupported = reviewShapeSupported
      && initialPromptBindingValid
      && changedPaths !== null
      && reviewIndependent
      && (!hasRequiredContinuation || continuationBinding !== null)
      && unavailableReasons.every(completionOnlyUnavailable);
    if (behaviorEvidenceSupported) {
      const allTranscriptResponsesComplete = admittedInputList.every((input) => completedResponseTurns.includes(input.turn));
      const requiredContinuationScenarioComplete = !hasRequiredContinuation || (
        continuationBinding !== null
        && missingContinuationAnswerTurns.length === 0
        && incompleteContinuationResponseTurns.length === 0
        && missingRelevantContinuationAnswerTurns.length === 0
        && missingPostAnswerQuestionIndexes.length === 0
        && completedRelevantContinuationTurns.length === continuationRequiredAnswerTurns.length
      );
      for (const [index, decision] of decisionMap) {
        if (decision.outcome !== "asked") {
          if (allTranscriptResponsesComplete && requiredContinuationScenarioComplete) behaviorReasons.push("material_decision_not_asked");
          const planning = planningAssessmentMap.get(index);
          if (planning && planning.outcome === "dependent_plan_observed") behaviorReasons.push("dependent_plan_preceded_question");
          if (earliestDependentEdits.length > 0) behaviorReasons.push("dependent_edit_preceded_question");
          continue;
        }
        for (const questionRef of decision.question_refs) {
          for (const edit of earliestDependentEdits) {
            const qOrder = questionRef;
            const eOrder = { turn: edit.turn, line: edit.line };
            if (compareOrder(eOrder, qOrder) <= 0) {
              behaviorReasons.push("dependent_edit_preceded_question");
              continue;
            }
            const answer = [...answerMap.values()].find((entry) => referenceKey(entry.question_ref) === referenceKey(questionRef) && entry.decision_indexes.includes(index));
            if (!answer) {
              behaviorReasons.push("dependent_edit_preceded_user_answer");
              continue;
            }
            if (compareOrder(eOrder, { turn: answer.answer_turn, line: 0 }) <= 0) {
              behaviorReasons.push("dependent_edit_preceded_user_answer");
              continue;
            }
            if (answer.outcome !== "carried_forward" || !answer.carry_refs.some((ref) => compareOrder(ref, eOrder) < 0)) {
              behaviorReasons.push("answer_not_carried_before_dependent_edit");
            }
          }
        }
      }
      if (planningRequirement === "before_plan") {
        for (const [index, planning] of planningAssessmentMap) {
          if (planning.outcome !== "dependent_plan_observed") continue;
          const decision = decisionMap.get(index);
          if (!decision || decision.outcome !== "asked") {
            behaviorReasons.push("dependent_plan_preceded_question");
            continue;
          }
          for (const planRef of planning.plan_refs) {
            for (const questionRef of decision.question_refs) {
              const linkedSpans = (questionSpanMap.get(referenceKey(questionRef)) || []).filter((span) => span.decision_indexes.includes(index));
              if (linkedSpans.some((span) => compareSpanOrder(planRef, span) <= 0)) {
                behaviorReasons.push("dependent_plan_preceded_question");
                continue;
              }
              const answer = [...answerMap.values()].find((entry) => referenceKey(entry.question_ref) === referenceKey(questionRef) && entry.decision_indexes.includes(index));
              if (!answer
                || answer.outcome !== "carried_forward"
                || compareOrder(planRef, { turn: answer.answer_turn, line: 0 }) <= 0
                || !answer.carry_refs.some((ref) => {
                  const carryOrder = compareCarryPlanOrder(ref, planRef);
                  return carryOrder !== null && carryOrder <= 0;
                })) {
                behaviorReasons.push("dependent_plan_preceded_user_answer");
              }
            }
          }
        }
      }
      for (const assessment of semanticReview.question_assessments) {
        if (assessment.classification === "material" && expectedDecisionCount === 0) behaviorReasons.push("unnecessary_material_question");
      }
      if (hasRequiredContinuation
        && missingPostAnswerQuestionIndexes.length > 0
        && completedRelevantContinuationTurns.length > 0) {
        behaviorReasons.push("required_post_answer_question_missing");
      }
      if (allTranscriptResponsesComplete && task05PolicyConflictClaims
        && !task05PolicyConflictClaims.conflict_identified) {
        behaviorReasons.push("required_policy_conflict_not_identified");
      }
      if (allTranscriptResponsesComplete && task05PolicyConflictClaims
        && !task05PolicyConflictClaims.security_impact_explained) {
        behaviorReasons.push("required_policy_security_impact_not_explained");
      }
      semanticStatus = behaviorReasons.length === 0 ? "PASS" : "FAIL";
    } else if (!reviewShapeSupported) {
      unavailableReasons.push("semantic_review_binding_incomplete");
    }
  }

  const uniqueUnavailable = [...new Set(unavailableReasons)];
  if (review.execution_mode === "offline_proxy") {
    semanticStatus = "UNAVAILABLE";
    uniqueUnavailable.push("offline_text_proxy_cannot_establish_behavior");
  }
  const behaviorStatus = semanticStatus === "UNAVAILABLE" || uniqueUnavailable.length > 0 ? "UNAVAILABLE" : semanticStatus;
  const result = {
    case_id: review.case_id,
    execution_mode: review.execution_mode,
    planning_requirement: planningRequirement,
    initial_workspace_baseline_status: initialWorkspaceBaselineStatus,
    missing_policy_read_status: missingPolicyReadStatus,
    activation_status: activationStatus,
    native_selection_status: nativeSelectionStatus,
    native_selection_reason: review.execution_mode === "native" ? "Codex JSONL has no dedicated native skill-selection event; command references to staged skill paths do not attest content reads." : null,
    staged_skill_command_reference_status: stagedSkillCommandReferenceStatus,
    skill_file_read_attestation: skillFileReadAttestation,
    skill_command_reference_limit: "A completed command containing the staged SKILL.md path proves only a text reference; it does not prove the file was read or the native skill was selected.",
    activation_evidence_reasons: [...new Set(activationReasons)].sort(),
    input_evidence_class: "controller_captured_input_not_native_jsonl_user_echo",
    chronology_support: "controller_turn_order_and_native_event_line_order",
    wall_clock_chronology: "not_asserted",
    semantic_status: semanticStatus,
    behavior_status: behaviorStatus,
    unavailable_reasons: [...new Set(uniqueUnavailable)].sort(),
    behavior_reasons: [...new Set(behaviorReasons)].sort(),
    continuation_coverage: {
      applicability_status: hasRequiredContinuation
        ? (continuationBinding ? "oracle_bound" : "unavailable")
        : "not_required",
      oracle_sha256: hasRequiredContinuation ? oracleDigest : null,
      required_answer_turns: continuationRequiredAnswerTurns,
      received_answer_turns: receivedAnswerTurns,
      relevant_answer_turns: relevantContinuationAnswerTurns,
      missing_relevant_answer_turns: missingRelevantContinuationAnswerTurns,
      answer_payload_mismatch_turns: continuationAnswerPayloadMismatchTurns,
      missing_answer_turns: missingContinuationAnswerTurns,
      completed_response_turns: completedResponseTurns,
      incomplete_response_turns: incompleteContinuationResponseTurns,
      required_post_answer_question_decision_indexes: continuationPostAnswerDecisionIndexes,
      observed_post_answer_question_decision_indexes: [...observedPostAnswerQuestionIndexes].sort((left, right) => left - right),
      missing_post_answer_question_decision_indexes: missingPostAnswerQuestionIndexes,
      applicability_basis: continuationBinding ? continuationBinding.applicabilityBasis : null,
    },
    evidence_counts: {
      controller_input_turns: admittedInputList.length,
      answer_receipts: answers.filter((answer) => answer.record).length,
      completed_transcript_turns: [...transcripts.values()].filter((transcript) => transcript.completedTurn).length,
      independently_reviewed_decisions: decisionMap.size,
      reviewed_question_events: [...questionMap.values()].filter((assessment) =>
        assessment.classification === "material" || assessment.classification === "non_material").length,
      workspace_changed_paths: changedPaths === null ? null : changedPaths.length,
      framework_state_paths_changed: frameworkStatePaths === null ? null : frameworkStatePaths.length,
      observed_dependent_edits: changedPaths === null ? null : observedChanges.size,
    },
  };
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

try {
  main();
} catch (error) {
  fail(error && error.message ? error.message : "evidence import failed");
}
