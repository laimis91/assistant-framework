const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const {execFileSync} = require("child_process");

const validatorId = "assistant-skill-creator.behavior_v1";
const hashPattern = /^sha256:[0-9a-f]{64}$/;
const operations = new Set(["create", "update", "assess", "refresh_guidance"]);
const outcomes = new Set(["design_pending_approval", "authoring_complete", "read_only_assessment", "read_only_refresh", "comparison_assessment"]);
const metadataKeys = new Set(["name", "description", "compatibility", "license", "metadata", "allowed-tools", "policy", "requires"]);
const outputOnlyCaseIds = [
  "existing-skill-validation-enforces-checklist",
  "skill-creator-requires-verified-distillation",
  "skill-contract-design-preserves-semantic-interface-types",
  "skill-save-requires-verified-distillation",
  "loop-process-skill-applies-harness-patterns"
];
const nonblank = value => typeof value === "string" && value.trim().length > 0;
const exactKeys = (value, keys) => value && typeof value === "object" && !Array.isArray(value)
  && Object.keys(value).sort().join("|") === [...keys].sort().join("|");
const digestBytes = bytes => "sha256:" + crypto.createHash("sha256").update(bytes).digest("hex");
const comparePaths = (left, right) => String(left).localeCompare(String(right));
const fail = (errors, message) => errors.push(message);
const creatorFixturePath = path.resolve(__dirname, "../../../skills/assistant-skill-creator/evals/cases.json");

function stableJson(value) {
  if (Array.isArray(value)) return "[" + value.map(stableJson).join(",") + "]";
  if (value && typeof value === "object") return "{" + Object.keys(value).sort().map(key => JSON.stringify(key) + ":" + stableJson(value[key])).join(",") + "}";
  return JSON.stringify(value);
}
const digestJson = value => digestBytes(Buffer.from(stableJson(value), "utf8"));

function creatorCaseMap(errors) {
  const bytes = safeFile(creatorFixturePath, "canonical creator fixture", errors);
  if (!bytes) return new Map();
  try {
    const fixture = JSON.parse(bytes.toString("utf8"));
    return new Map((fixture.cases || [])
      .filter(item => item?.semantic_validator === validatorId)
      .map(item => [item.id, item]));
  } catch {
    fail(errors, "canonical creator fixture: readable JSON required");
    return new Map();
  }
}

function validRunBinding(binding, testCase, errors, label) {
  const fields = ["capture_id", "run_id", "source_root", "source_snapshot_sha256", "output_root", "comparison_sha256"];
  if (!exactKeys(binding, fields) || !nonblank(binding.capture_id) || !nonblank(binding.run_id)
    || !nonblank(binding.output_root) || !path.isAbsolute(binding.output_root)
    || (binding.source_root !== null && (typeof binding.source_root !== "string" || !path.isAbsolute(binding.source_root)))
    || (binding.source_snapshot_sha256 !== null && !hashPattern.test(binding.source_snapshot_sha256 || ""))
    || (binding.comparison_sha256 !== null && !hashPattern.test(binding.comparison_sha256 || ""))) {
    fail(errors, label + ": exact run_binding fields and valid identities required");
    return false;
  }
  const context = testCase?.semantic_context?.creator_evidence;
  if (!context) { fail(errors, label + ": canonical creator behavior case required"); return false; }
  const sourceRequired = ["update", "assess"].includes(context.operation);
  if ((sourceRequired && (!path.isAbsolute(binding.source_root || "") || !hashPattern.test(binding.source_snapshot_sha256 || "")))
    || (!sourceRequired && (binding.source_root !== null || binding.source_snapshot_sha256 !== null))) {
    fail(errors, label + ": source identity differs from canonical operation requirements");
  }
  if ((context.comparison_required && !hashPattern.test(binding.comparison_sha256 || ""))
    || (!context.comparison_required && binding.comparison_sha256 !== null)) {
    fail(errors, label + ": comparison identity differs from canonical case requirements");
  }
  return true;
}

function validateRunBindings(bytes, selectedCaseIds, fixturePaths) {
  const errors = [];
  if (!Array.isArray(selectedCaseIds) || !selectedCaseIds.length || selectedCaseIds.some(id => !nonblank(id))) {
    fail(errors, "selected canonical creator case IDs must be a non-empty string array");
    return errors;
  }
  if (new Set(selectedCaseIds).size !== selectedCaseIds.length) {
    fail(errors, "selected creator cases have ambiguous ownership; each case must have exactly one fixture owner");
    return errors;
  }
  if (!Array.isArray(fixturePaths) || !fixturePaths.length) {
    fail(errors, "selected creator fixture paths are required");
    return errors;
  }
  let manifest;
  try { manifest = JSON.parse(bytes.toString("utf8")); }
  catch { fail(errors, "creator run bindings must be readable JSON"); return errors; }
  if (!exactKeys(manifest, ["schema_version", "cases"]) || manifest.schema_version !== "1.0" || !Array.isArray(manifest.cases)) {
    fail(errors, "creator run bindings require schema_version 1.0 and an exact cases array");
    return errors;
  }

  const canonicalCases = creatorCaseMap(errors);
  const selected = new Set(selectedCaseIds);
  const owners = new Map();
  for (const fixturePath of fixturePaths) {
    const fixtureBytes = safeFile(fixturePath, "selected creator fixture", errors);
    if (!fixtureBytes) continue;
    let fixture;
    try { fixture = JSON.parse(fixtureBytes.toString("utf8")); }
    catch { fail(errors, "selected creator fixture must be readable JSON"); continue; }
    for (const testCase of (Array.isArray(fixture.cases) ? fixture.cases : [])) {
      if (!selected.has(testCase?.id) || testCase?.semantic_validator !== validatorId) continue;
      owners.set(testCase.id, (owners.get(testCase.id) || 0) + 1);
      const canonical = canonicalCases.get(testCase.id);
      if (!canonical) fail(errors, "selected creator behavior case is not canonical: " + testCase.id);
      else if (testCase.semantic_context?.creator_evidence?.run_binding !== null
        || stableJson(testCase) !== stableJson(canonical)) {
        fail(errors, "selected creator case differs from its canonical null-bound fixture: " + testCase.id);
      }
    }
  }
  for (const caseId of selectedCaseIds) {
    if (owners.get(caseId) !== 1) fail(errors, "selected creator case must have exactly one fixture owner: " + caseId);
    if (!canonicalCases.has(caseId)) fail(errors, "selected case is not a canonical creator behavior case: " + caseId);
  }

  const entries = new Map();
  for (const item of manifest.cases) {
    if (!exactKeys(item, ["case_id", "run_binding"]) || !nonblank(item.case_id)) {
      fail(errors, "creator run binding entry requires exact case_id and run_binding fields");
      continue;
    }
    if (entries.has(item.case_id)) fail(errors, "duplicate creator run binding case_id: " + item.case_id);
    entries.set(item.case_id, item.run_binding);
    const canonical = canonicalCases.get(item.case_id);
    if (!canonical) fail(errors, "creator run bindings contain an unknown case_id: " + item.case_id);
    else validRunBinding(item.run_binding, canonical, errors, "creator run binding " + item.case_id);
    if (!selected.has(item.case_id)) fail(errors, "creator run bindings contain an unselected case_id: " + item.case_id);
  }
  if (entries.size !== selected.size || [...selected].some(caseId => !entries.has(caseId))) {
    fail(errors, "creator run bindings must contain exactly one entry for every selected creator behavior case");
  }
  return errors;
}

function readPinnedRunBinding(file, expectedDigest, caseId, errors) {
  if (!hashPattern.test(expectedDigest || "")) {
    fail(errors, "creator run bindings require the preflight SHA-256 identity");
    return;
  }
  const bytes = safeFile(file, "creator run bindings", errors);
  if (!bytes) return;
  if (digestBytes(bytes) !== expectedDigest) {
    fail(errors, "creator run bindings changed after whole-manifest preflight");
    return;
  }
  let manifest;
  try { manifest = JSON.parse(bytes.toString("utf8")); }
  catch { fail(errors, "creator run bindings must be readable JSON"); return; }
  if (!exactKeys(manifest, ["schema_version", "cases"]) || manifest.schema_version !== "1.0" || !Array.isArray(manifest.cases)) {
    fail(errors, "creator run bindings require schema_version 1.0 and an exact cases array");
    return;
  }
  const matching = manifest.cases.filter(item => item?.case_id === caseId);
  if (matching.length !== 1) {
    fail(errors, "creator run bindings must contain exactly one entry for " + caseId);
    return;
  }
  const canonical = creatorCaseMap(errors).get(caseId);
  if (canonical) validRunBinding(matching[0].run_binding, canonical, errors, "creator run binding " + caseId);
  return matching[0].run_binding;
}

function safeDirectory(directory, label, errors) {
  if (typeof directory !== "string" || !path.isAbsolute(directory)) { fail(errors, label + ": absolute directory required"); return; }
  try {
    const stat = fs.lstatSync(directory);
    const real = fs.realpathSync(directory);
    if (!stat.isDirectory() || stat.isSymbolicLink()) { fail(errors, label + ": non-symlink directory required"); return; }
    return real;
  } catch { fail(errors, label + ": readable directory required"); }
}

function safeFile(file, label, errors) {
  if (typeof file !== "string" || !path.isAbsolute(file)) { fail(errors, label + ": absolute file path required"); return; }
  try {
    const stat = fs.lstatSync(file);
    if (!stat.isFile() || stat.isSymbolicLink()) { fail(errors, label + ": non-symlink file required"); return; }
    return fs.readFileSync(file);
  } catch { fail(errors, label + ": readable file required"); }
}

function resolveUnder(root, relative, errors, label) {
  if (!nonblank(relative) || path.isAbsolute(relative) || relative.split(/[\\/]/).some(part => !part || part === "." || part === "..")) {
    fail(errors, label + ": safe relative path required"); return;
  }
  const resolved = path.resolve(root, relative);
  const rel = path.relative(root, resolved);
  if (rel.startsWith("..") || path.isAbsolute(rel)) { fail(errors, label + ": path escapes evidence root"); return; }
  let current = root;
  const parts = relative.split(/[\\/]/);
  for (let i = 0; i < parts.length; i += 1) {
    current = path.join(current, parts[i]);
    try {
      const stat = fs.lstatSync(current);
      if (stat.isSymbolicLink() || (i < parts.length - 1 && !stat.isDirectory()) || (i === parts.length - 1 && !stat.isFile())) {
        fail(errors, label + ": regular non-symlink file path required"); return;
      }
    } catch { fail(errors, label + ": file path does not exist"); return; }
  }
  return resolved;
}

function listFiles(root, errors, label) {
  const files = [];
  const visit = dir => {
    let entries;
    try { entries = fs.readdirSync(dir, {withFileTypes: true}); } catch { fail(errors, label + ": unreadable output tree"); return; }
    for (const entry of entries) {
      const full = path.join(dir, entry.name);
      if (entry.isSymbolicLink()) fail(errors, label + ": symlinks are not accepted");
      else if (entry.isDirectory()) visit(full);
      else if (entry.isFile()) files.push(path.relative(root, full).split(path.sep).join("/"));
      else fail(errors, label + ": unsupported filesystem entry");
    }
  };
  visit(root);
  return files.sort(comparePaths);
}

function artifactDigest(root, relative, errors) {
  const file = resolveUnder(root, relative, errors, "artifact");
  if (!file) return;
  const bytes = safeFile(file, "artifact", errors);
  if (!bytes) return;
  if (bytes.length === 0) fail(errors, "artifact: empty bytes are not evidence");
  return digestBytes(bytes);
}

function parseEnvelope(text) {
  const fence = String.fromCharCode(96).repeat(3);
  const blocks = new RegExp(fence + "(?:json)?[ \\t]*\\r?\\n([\\s\\S]*?)\\r?\\n" + fence, "gi");
  const candidates = [...text.matchAll(blocks)].map(match => match[1]);
  if (text.trim().startsWith("{")) candidates.push(text.trim());
  for (const candidate of candidates) {
    try {
      const value = JSON.parse(candidate);
      if (value && value.creator_evidence) return value;
    } catch { /* Try another structured block. */ }
  }
}

function parseResponseObject(text) {
  const fence = String.fromCharCode(96).repeat(3);
  const blocks = new RegExp(fence + "(?:json)?[ \\t]*\\r?\\n([\\s\\S]*?)\\r?\\n" + fence, "gi");
  const candidates = [...String(text).matchAll(blocks)].map(match => match[1]);
  if (String(text).trim().startsWith("{")) candidates.push(String(text).trim());
  for (const candidate of candidates) {
    try {
      const value = JSON.parse(candidate);
      if (value && typeof value === "object" && !Array.isArray(value)) return value;
    } catch { /* Try another structured block. */ }
  }
}

function validateDesign(design, context, presented, evidence, errors) {
  const fields = ["skill_name", "purpose", "category", "value_kind", "success_criteria", "contracts"];
  if (!exactKeys(design, fields) || !nonblank(design.skill_name) || !nonblank(design.purpose)
    || !["process", "analysis", "utility"].includes(design.category)
    || !["capability", "preference", "mixed"].includes(design.value_kind)
    || !Array.isArray(design.success_criteria) || !design.success_criteria.length || !design.success_criteria.every(nonblank)
    || !Array.isArray(design.contracts) || !design.contracts.length) {
    fail(errors, "design: typed purpose, value kind, success criteria, and contract boundaries required"); return;
  }
  const names = design.contracts.map(item => item?.name);
  const supported = new Set(["input.yaml", "output.yaml", "phase-gates.yaml", "handoffs.yaml"]);
  if (design.skill_name !== context.skill_name || design.category !== context.skill_category
    || names.some(name => !supported.has(name)) || new Set(names).size !== names.length) {
    fail(errors, "design: target, category, or contract list differs from frozen case");
  }
  const required = design.category === "process" ? ["input.yaml", "output.yaml", "phase-gates.yaml", "handoffs.yaml"]
    : design.category === "analysis" ? ["input.yaml", "output.yaml", "phase-gates.yaml"] : ["input.yaml", "output.yaml"];
  if (required.some(name => !names.includes(name))) fail(errors, "design: contract tier is incomplete");
  for (const contract of design.contracts) {
    if (!contract || !Array.isArray(contract.fields) || !contract.fields.length) { fail(errors, "design: each contract needs typed fields"); continue; }
    if (contract.name === "input.yaml") {
      if (contract.fields.some(field => !exactKeys(field, ["name", "type", "required", "on_missing"]) || !nonblank(field.name)
        || !nonblank(field.type) || typeof field.required !== "boolean" || (field.required && !nonblank(field.on_missing)))) fail(errors, "design: required input fields need type and on_missing recovery");
    } else if (contract.name === "output.yaml") {
      if (contract.fields.some(field => !exactKeys(field, ["name", "type", "required", "on_fail"]) || !nonblank(field.name)
        || !nonblank(field.type) || typeof field.required !== "boolean" || (field.required && !nonblank(field.on_fail)))) fail(errors, "design: required output fields need type and on_fail recovery");
    } else if (contract.name === "phase-gates.yaml") {
      if (contract.fields.some(field => !exactKeys(field, ["name", "condition", "assertion", "on_fail"]) || !nonblank(field.name)
        || !nonblank(field.condition) || !nonblank(field.assertion) || !nonblank(field.on_fail))) fail(errors, "design: phase gates need assertions and recovery");
    } else if (contract.name === "handoffs.yaml") {
      if (contract.fields.some(field => !exactKeys(field, ["name", "producer_fields", "consumer_fields"]) || !nonblank(field.name)
        || !Array.isArray(field.producer_fields) || !field.producer_fields.length || !field.producer_fields.every(nonblank)
        || stableJson(field.producer_fields) !== stableJson(field.consumer_fields))) fail(errors, "design: producer and consumer handoff fields must match");
    }
  }
  if (evidence.design_sha256 !== digestJson(design) || !presented || presented.sha256 !== evidence.design_sha256) {
    fail(errors, "design: response content is not bound to a successful presentation trace");
  }
}

function parseYaml(file, errors, label) {
  const bytes = safeFile(file, label, errors);
  if (!bytes) return;
  try {
    const code = "require 'yaml'; require 'json'; value = YAML.safe_load(STDIN.read, permitted_classes: [], permitted_symbols: [], aliases: false); puts JSON.generate(value)";
    return JSON.parse(execFileSync("ruby", ["-e", code], {input: bytes, encoding: "utf8"}));
  } catch { fail(errors, label + ": YAML could not be parsed safely"); }
}

function canonicalArtifact(file, name, errors, label) {
  const document = parseYaml(file, errors, label);
  if (!document) return;
  const matches = Array.isArray(document.artifacts) ? document.artifacts.filter(artifact => artifact?.name === name) : [];
  if (matches.length !== 1) { fail(errors, label + ": canonical artifact must resolve exactly once: " + name); return; }
  return matches[0];
}

function validateCanonicalValue(value, field, label, errors) {
  const type = field?.type;
  const valid = type === "string" || type === "file" || type === "jsonl_line" ? typeof value === "string"
    : type === "int" ? Number.isInteger(value)
      : type === "boolean" ? typeof value === "boolean"
    : type === "enum" ? typeof value === "string" && Array.isArray(field.enum_values) && field.enum_values.includes(value)
      : type === "string[]" ? Array.isArray(value) && value.every(item => typeof item === "string")
        : type === "object" ? value !== null && typeof value === "object" && !Array.isArray(value)
          : type === "object[]" ? Array.isArray(value) && value.every(item => item !== null && typeof item === "object" && !Array.isArray(item))
            : false;
  if (!valid) { fail(errors, label + ": value does not satisfy canonical producer type " + String(type)); return; }
  if ((type === "string" || type === "file" || type === "jsonl_line") && !nonblank(value)) {
    fail(errors, label + ": canonical producer string must be non-empty"); return;
  }
  if (["string[]", "object[]"].includes(type) && Number.isInteger(field.min_items) && value.length < field.min_items) {
    fail(errors, label + ": fewer than the canonical producer minimum items"); return;
  }
  if (type === "string[]" && !value.every(nonblank)) {
    fail(errors, label + ": canonical producer string items must be non-empty"); return;
  }
  if (type === "object" || type === "object[]") {
    const fields = field.object_fields;
    if (!Array.isArray(fields)) {
      if (type === "object") return;
      fail(errors, label + ": canonical producer object fields are unavailable"); return;
    }
    const validateObject = (item, itemLabel) => {
      if (Object.keys(item).some(key => !fields.some(child => child.name === key))) {
        fail(errors, itemLabel + ": unknown canonical producer object field");
      }
      for (const child of fields) {
        const childLabel = itemLabel + "." + child.name;
        if (!Object.prototype.hasOwnProperty.call(item, child.name)) {
          if (child.required === true) fail(errors, childLabel + ": required canonical producer field is missing");
          continue;
        }
        validateCanonicalValue(item[child.name], child, childLabel, errors);
      }
    };
    if (type === "object") validateObject(value, label);
    else value.forEach((item, index) => validateObject(item, label + "[" + index + "]"));
  }
}

function validateCanonicalCreatorOutputs(response, errors, operation = null) {
  if (!nonblank(response?.operation_summary)) fail(errors, "ordinary operation_summary must be a non-empty canonical string");
  const creatorOutput = path.resolve(__dirname, "../../../skills/assistant-skill-creator/contracts/output.yaml");
  const summarySchema = canonicalArtifact(creatorOutput, "operation_summary", errors, "creator output contract");
  if (summarySchema) validateCanonicalValue(response?.operation_summary, summarySchema, "operation_summary", errors);

  const creatorAssessment = canonicalArtifact(creatorOutput, "evidence_assessment", errors, "creator output contract");
  const alias = "assistant-verification/contracts/output.yaml#evidence_assessment";
  if (!creatorAssessment?.validation?.includes(alias)) {
    fail(errors, "creator evidence_assessment must retain its canonical producer alias"); return;
  }
  const verifierOutput = path.resolve(__dirname, "../../../skills/assistant-verification/contracts/output.yaml");
  const assessmentSchema = canonicalArtifact(verifierOutput, "evidence_assessment", errors, "verification output contract");
  if (!assessmentSchema) return;
  const assessmentFields = assessmentSchema.object_fields;
  if (Array.isArray(assessmentFields) && !exactKeys(response?.evidence_assessment, assessmentFields.map(field => field.name))) {
    fail(errors, "ordinary evidence_assessment must use the canonical producer top-level shape");
  }
  validateCanonicalValue(response?.evidence_assessment, assessmentSchema, "evidence_assessment", errors);

  const applicableArtifacts = [
    ["validation_summary", ["create", "update"].includes(operation)],
    ["policy_safety_summary", ["create", "update"].includes(operation)],
    ["upstream_guidance_assessment", operation === "refresh_guidance"]
  ];
  for (const [name, applicable] of applicableArtifacts) {
    if (!applicable) continue;
    const schema = canonicalArtifact(creatorOutput, name, errors, "creator output contract");
    if (schema) validateCanonicalValue(response?.[name], schema, name, errors);
  }
}

function validateCapturedRefreshReport(response, refresh, checked, errors) {
  const report = response?.upstream_guidance_assessment;
  if (!report || !Array.isArray(report.results)) return;
  const creatorOutput = path.resolve(__dirname, "../../../skills/assistant-skill-creator/contracts/output.yaml");
  const reportSchema = canonicalArtifact(creatorOutput, "upstream_guidance_assessment", errors, "creator output contract");
  if (reportSchema) validateCanonicalValue(checked.checker_report, reportSchema, "captured checker report", errors);
  if (!checked.checker_report || stableJson(report) !== stableJson(checked.checker_report)) {
    fail(errors, "ordinary refresh report differs from the independently captured checker report");
  }
  if (checked.checker_report?.checked_at !== checked.checked_at || refresh.checked_at !== checked.checked_at
    || checked.checker_report?.registry_mutated !== false) {
    fail(errors, "captured refresh report differs from its successful checker event or read-only status");
  }
  const rows = checked.checker_report?.results?.filter(result => result?.source_id === checked.source_identity) || [];
  if (rows.length !== 1) { fail(errors, "captured checker report must retain exactly one result for the checked source identity"); return; }
  const result = rows[0];
  const digest = /^[0-9a-f]{64}$/.test(result.candidate_sha256 || "") ? "sha256:" + result.candidate_sha256 : null;
  if (checked.sha256 !== digest || refresh.revision_or_digest !== digest) {
    fail(errors, "refresh digest must match the captured helper report when available");
  }
  const expectedDisposition = result.status === "current" ? "already_current"
    : result.status === "unavailable" ? "not_adopted" : "requires_review";
  if (refresh.disposition !== expectedDisposition) fail(errors, "refresh disposition differs from the captured checker status");
  if (result.retrieval_state !== "complete"
    && (!Array.isArray(refresh.access_limits) || !refresh.access_limits.length || !refresh.access_limits.every(nonblank))) {
    fail(errors, "incomplete refresh requires explicit non-empty access limits");
  }
}

function validateOutputOnlyCreatorResponse(text, caseId) {
  const errors = [];
  if (!outputOnlyCaseIds.includes(caseId)) { fail(errors, "output-only creator case ID is not registered"); return errors; }
  const response = parseResponseObject(text);
  if (!response) { fail(errors, "ordinary creator response must contain one structured JSON object"); return errors; }
  validateCanonicalCreatorOutputs(response, errors);
  return [...new Set(errors)];
}

function validateArtifactContent(context, root, errors) {
  if (!Array.isArray(context.artifact_checks)) { fail(errors, "fixture content checks are required"); return; }
  for (const check of context.artifact_checks) {
    if (!exactKeys(check, ["path", "section", "name", "type", "recovery_field"]) || !nonblank(check.name)) {
      fail(errors, "fixture content check is malformed"); continue;
    }
    const file = resolveUnder(root, check.path, errors, "content check");
    if (!file) continue;
    const document = parseYaml(file, errors, "authored contract");
    const rows = document && document[check.section];
    const matches = Array.isArray(rows) ? rows.filter(row => row?.name === check.name) : [];
    if (matches.length !== 1 || matches[0].type !== check.type || matches[0].required !== true
      || !nonblank(matches[0][check.recovery_field])) fail(errors, "authored contract content does not satisfy frozen outcome check: " + check.path + "#" + check.name);
  }
}

function validateArtifacts(evidence, context, trusted, events, root, errors) {
  const actual = listFiles(root, errors, "target output");
  const required = context.required_artifacts, allowed = context.allowed_artifacts;
  if (!Array.isArray(required) || !Array.isArray(allowed) || required.some(file => !allowed.includes(file))) {
    fail(errors, "fixture artifact policy: required paths must be within its fixed allowlist"); return;
  }
  const preserved = Array.isArray(context.preserved_target_files) ? context.preserved_target_files : [];
  const manifest = list => Array.isArray(list) ? list.map(item => item && ({path: item.path, sha256: item.sha256})) : null;
  const responseManifest = manifest(evidence.artifacts), trustedManifest = manifest(trusted.artifact_manifest);
  const sorted = list => [...list].sort((a, b) => comparePaths(a.path, b.path));
  const typedManifest = list => Array.isArray(list) && list.every(item => exactKeys(item, ["path", "sha256"])
    && nonblank(item.path) && hashPattern.test(item.sha256 || ""));
  if (!typedManifest(evidence.artifacts) || !typedManifest(trusted.artifact_manifest)
    || stableJson(responseManifest) !== stableJson(sorted(responseManifest))
    || stableJson(trustedManifest) !== stableJson(sorted(trustedManifest))) fail(errors, "artifact manifests must be typed and sorted");
  else {
    const expectedFiles = [...new Set([...trustedManifest.map(item => item?.path), ...preserved])].sort(comparePaths);
    if (required.some(file => !actual.includes(file)) || actual.some(file => !allowed.includes(file))
      || stableJson(actual) !== stableJson(expectedFiles)) fail(errors, "target output: file set differs from frozen artifact policy");
    if (stableJson(responseManifest) !== stableJson(trustedManifest)) fail(errors, "response artifact manifest differs from captured writes");
    const writeEvents = events.filter(event => event.action === "target_file_written");
    if (writeEvents.some(event => !trustedManifest.some(item => item?.path === event.path))) fail(errors, "write event names a file outside the captured artifact manifest");
    const successfulWrites = events.filter(event => event.action === "target_file_written" && event.status === "succeeded").map(event => event.path).sort(comparePaths);
    if (stableJson(successfulWrites) !== stableJson(trustedManifest.map(item => item?.path).sort(comparePaths))) fail(errors, "successful write events differ from the captured artifact manifest");
    if (events.some(event => event.action === "target_file_preserved" && event.status === "failed")) fail(errors, "failed preservation action cannot establish completion");
    for (const item of trustedManifest) {
      if (!item || !hashPattern.test(item.sha256 || "")) { fail(errors, "captured artifact digest required"); continue; }
      if (artifactDigest(root, item.path, errors) !== item.sha256) fail(errors, "artifact bytes differ from captured digest: " + item.path);
      const write = uniqueOutcomeForIdentity(events, "target_file_written", event => event.path === item.path,
        "write " + item.path, errors);
      if (!write || write.sha256 !== item.sha256) fail(errors, "successful write event required for artifact: " + item.path);
    }
    validateArtifactContent(context, root, errors);
  }
}

function validatePreservedTargetFiles(context, trusted, events, sourceRoot, outputRoot, errors) {
  const expected = context.preserved_target_files;
  if (!Array.isArray(expected) || !Array.isArray(trusted.preserved_files)
    || stableJson(trusted.preserved_files.map(item => item?.path)) !== stableJson(expected)) {
    fail(errors, "preserved target file manifest differs from fixture policy"); return;
  }
  const preservationEvents = events.filter(event => event.action === "target_file_preserved");
  if (preservationEvents.some(event => !expected.includes(event.path) || event.status === "failed")) fail(errors, "preservation event is outside the fixture policy or failed");
  const successfulPreservations = events.filter(event => event.action === "target_file_preserved" && event.status === "succeeded").map(event => event.path).sort(comparePaths);
  if (stableJson(successfulPreservations) !== stableJson(expected.slice().sort(comparePaths))) fail(errors, "successful preservation events differ from the fixture policy");
  for (const item of trusted.preserved_files) {
    if (!item || !exactKeys(item, ["path", "sha256"]) || !hashPattern.test(item.sha256 || "")) {
      fail(errors, "preserved target file digest required"); continue;
    }
    const beforePath = resolveUnder(sourceRoot, item.path, errors, "preserved source file");
    const afterPath = resolveUnder(outputRoot, item.path, errors, "preserved target file");
    if (!beforePath || !afterPath) continue;
    const before = safeFile(beforePath, "preserved source file", errors);
    const after = safeFile(afterPath, "preserved target file", errors);
    if (!before || !after) continue;
    if (digestBytes(before) !== item.sha256 || digestBytes(after) !== item.sha256) fail(errors, "preserved target file bytes changed: " + item.path);
    const preservation = uniqueOutcomeForIdentity(events, "target_file_preserved", event => event.path === item.path,
      "preservation " + item.path, errors);
    if (!preservation || preservation.sha256 !== item.sha256) fail(errors, "successful preservation event required: " + item.path);
  }
}

function parseMetadata(file, errors, label) {
  const bytes = safeFile(file, label, errors);
  const match = bytes && bytes.toString("utf8").match(/^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/);
  if (!match) { fail(errors, label + ": frontmatter required"); return; }
  try {
    const code = "require 'yaml'; require 'json'; require 'date'; value = YAML.safe_load(STDIN.read, permitted_classes: [Date, Time], permitted_symbols: [], aliases: false) || {}; keys = %w[name description compatibility license metadata allowed-tools policy requires]; puts JSON.generate(value.select { |key, _| keys.include?(key) })";
    return JSON.parse(execFileSync("ruby", ["-e", code], {input: match[1], encoding: "utf8"}));
  } catch { fail(errors, label + ": metadata could not be parsed safely"); }
}

function validateTargetSkillName(file, expected, label, errors) {
  const metadata = parseMetadata(file, errors, label);
  if (metadata && metadata.name !== expected) fail(errors, label + ": name differs from frozen skill name");
}

function validateCreatedSkillStructure(root, errors) {
  const validator = path.resolve(__dirname, "../../../tools/skills/validate-skills.sh");
  try {
    execFileSync("bash", [validator, "--skill", root], {encoding: "utf8"});
  } catch (error) {
    const details = String(error.stderr || error.stdout || error.message).trim();
    fail(errors, "created skill failed existing source validation" + (details ? ": " + details : ""));
  }
}

function validatePreservedMetadata(context, snapshot, root, errors) {
  if (context.operation !== "update") return;
  if (!Array.isArray(context.preserved_metadata) || context.preserved_metadata.some(key => !metadataKeys.has(key))) {
    fail(errors, "fixture metadata policy: unsupported preserved field"); return;
  }
  const before = snapshot && parseMetadata(snapshot.path, errors, "source skill");
  const after = parseMetadata(path.join(root, "SKILL.md"), errors, "updated skill");
  if (!before || !after) return;
  for (const key of context.preserved_metadata) if (stableJson(before[key] ?? null) !== stableJson(after[key] ?? null)) {
    fail(errors, "updated metadata was not preserved: " + key);
  }
}

function validateRequestedBodyChange(testCase, snapshot, root, errors) {
  if (testCase.id !== "narrow-existing-skill-update-preserves-metadata-and-agent-policy") return;
  const change = testCase.semantic_context?.creator_evidence?.requested_body_change;
  if (!exactKeys(change, ["before_text", "after_text"]) || !nonblank(change.before_text)
    || !nonblank(change.after_text) || change.before_text === change.after_text) {
    fail(errors, "narrow update: frozen body correction required"); return;
  }
  const sourceBytes = snapshot && safeFile(snapshot.path, "source skill body", errors);
  const outputPath = resolveUnder(root, "SKILL.md", errors, "updated skill body");
  const outputBytes = outputPath && safeFile(outputPath, "updated skill body", errors);
  if (!sourceBytes || !outputBytes) return;
  const sourceText = sourceBytes.toString("utf8");
  const frontMatter = /^---\r?\n[\s\S]*?\r?\n---(?:\r?\n|$)/.exec(sourceText);
  if (!frontMatter) { fail(errors, "narrow update: source frontmatter is required"); return; }
  const bodyStart = Buffer.byteLength(frontMatter[0], "utf8");
  const body = sourceBytes.subarray(bodyStart);
  const before = Buffer.from(change.before_text, "utf8");
  const after = Buffer.from(change.after_text, "utf8");
  const offset = body.indexOf(before);
  if (offset < 0 || body.indexOf(before, offset + before.length) >= 0) {
    fail(errors, "narrow update: requested source text must occur exactly once in the body"); return;
  }
  const expected = Buffer.concat([sourceBytes.subarray(0, bodyStart + offset), after,
    sourceBytes.subarray(bodyStart + offset + before.length)]);
  if (!outputBytes.equals(expected)) fail(errors, "narrow update: output must contain only the requested body correction");
}

function validateMetric(value, numerator, denominator, label, errors) {
  if (!exactKeys(value, ["numerator", "denominator", "value", "availability"])
    || value.numerator !== numerator || value.denominator !== denominator) {
    fail(errors, label + ": raw counts and denominator do not match observations"); return;
  }
  if (denominator === 0) {
    if (value.value !== null || value.availability !== "unavailable") fail(errors, label + ": zero denominator must be unavailable");
  } else if (value.availability !== "available" || typeof value.value !== "number"
    || Math.abs(value.value - numerator / denominator) > 1e-9) fail(errors, label + ": metric must be derived from raw counts");
}

function validateComparison(report, trusted, events, errors) {
  const keys = ["schema_version", "prompt_set_digest", "rubric_digest", "conditions", "baseline", "candidate", "partitions", "candidate_selection_ids", "blind_labels", "observations", "metrics"];
  if (!exactKeys(report, keys) || !exactKeys(trusted, keys) || report.schema_version !== "1.0"
    || !hashPattern.test(report.prompt_set_digest || "") || !hashPattern.test(report.rubric_digest || "")) {
    fail(errors, "comparison: frozen typed record required"); return;
  }
  if (stableJson(report) !== stableJson(trusted)) fail(errors, "comparison: response differs from independent pair record");
  const c = report.conditions;
  const conditionKeys = ["host", "model", "runtime", "settings_digest", "tools_digest", "permissions_digest", "inputs_digest"];
  if (!exactKeys(c, conditionKeys) || ![c.host, c.model, c.runtime].every(nonblank)
    || conditionKeys.slice(3).some(key => !hashPattern.test(c[key] || ""))) fail(errors, "comparison conditions: host, model, runtime, settings, tools, permissions, and input identity required");
  const baseline = report.baseline, candidate = report.candidate;
  const runKeys = ["run_id", "source_snapshot", "output_root", "artifact_manifest"];
  if (![baseline, candidate].every(item => exactKeys(item, runKeys) && nonblank(item.run_id)
    && exactKeys(item.source_snapshot, ["path", "sha256"]) && hashPattern.test(item.source_snapshot.sha256 || ""))) {
    fail(errors, "comparison: baseline and candidate run/source identities required"); return;
  }
  if (baseline.run_id === candidate.run_id || baseline.source_snapshot.sha256 === candidate.source_snapshot.sha256) fail(errors, "comparison: distinct source and run identities required");
  const roots = [baseline, candidate].map(item => safeDirectory(item.output_root, "comparison output", errors));
  if (roots[0] && roots[1] && (roots[0] === roots[1] || roots[0].startsWith(roots[1] + path.sep) || roots[1].startsWith(roots[0] + path.sep))) fail(errors, "comparison outputs: isolated non-nested roots required");
  [baseline, candidate].forEach((run, index) => {
    const bytes = safeFile(run.source_snapshot.path, run.run_id + " source", errors);
    if (bytes && digestBytes(bytes) !== run.source_snapshot.sha256) fail(errors, run.run_id + ": source snapshot changed");
    if (!Array.isArray(run.artifact_manifest) || !run.artifact_manifest.length || !roots[index]) {
      fail(errors, run.run_id + ": non-empty raw artifact manifest required"); return;
    }
    const actual = listFiles(roots[index], errors, run.run_id + " output");
    if (run.artifact_manifest.some(item => !exactKeys(item, ["path", "sha256"]) || !nonblank(item.path))) {
      fail(errors, run.run_id + ": typed artifact manifest required"); return;
    }
    const expected = run.artifact_manifest.map(item => item.path).sort(comparePaths);
    if (stableJson(actual) !== stableJson(expected)) fail(errors, run.run_id + ": output files differ from manifest");
    for (const item of run.artifact_manifest) {
      if (!hashPattern.test(item.sha256 || "") || artifactDigest(roots[index], item.path, errors) !== item.sha256) fail(errors, run.run_id + ": actual artifact digest mismatch");
    }
    const completionAction = index === 0 ? "baseline_run_completed" : "candidate_run_completed";
    const completion = uniqueOutcomeForIdentity(events, completionAction,
      event => event.run_id === run.run_id, run.run_id + " comparison completion", errors);
    if (!completion || completion.source_snapshot_sha256 !== run.source_snapshot.sha256
      || completion.output_root !== run.output_root || completion.conditions_sha256 !== digestJson(c)
      || completion.prompt_set_digest !== report.prompt_set_digest || completion.rubric_digest !== report.rubric_digest) {
      fail(errors, run.run_id + ": successful run trace must bind source, output, conditions, prompt, and rubric identities");
    }
  });
  const p = report.partitions;
  if (!exactKeys(p, ["training_ids", "validation_ids", "final_acceptance_ids"])
    || ![p.training_ids, p.validation_ids, p.final_acceptance_ids].every(Array.isArray)) fail(errors, "comparison partitions: exact split identities required");
  else {
    const all = [...p.training_ids, ...p.validation_ids, ...p.final_acceptance_ids];
    if (all.some(id => !nonblank(id)) || new Set(all).size !== all.length || !p.validation_ids.length || !p.final_acceptance_ids.length) fail(errors, "comparison partitions must be non-empty and disjoint");
    if (!Array.isArray(report.candidate_selection_ids) || !report.candidate_selection_ids.length || report.candidate_selection_ids.some(id => !p.validation_ids.includes(id))) fail(errors, "candidate selection leaked outside validation, including final holdout");
  }
  if (!exactKeys(report.blind_labels, ["blind", "labels"]) || report.blind_labels.blind !== true
    || !exactKeys(report.blind_labels.labels, ["A", "B"]) || !nonblank(report.blind_labels.labels.A) || !nonblank(report.blind_labels.labels.B)
    || report.blind_labels.labels.A === report.blind_labels.labels.B
    || /baseline|candidate/i.test(report.blind_labels.labels.A + " " + report.blind_labels.labels.B)) fail(errors, "blind comparison requires opaque A/B labels");
  if (!Array.isArray(report.observations) || !report.observations.length) { fail(errors, "comparison raw outcomes required"); return; }
  let tp = 0, fn = 0, tn = 0, fp = 0;
  for (const row of report.observations) {
    if (!exactKeys(row, ["prompt_id", "partition", "expected_activate", "candidate_selected"])
      || !nonblank(row.prompt_id) || !["training", "validation", "final_acceptance"].includes(row.partition)
      || typeof row.expected_activate !== "boolean" || typeof row.candidate_selected !== "boolean") {
      fail(errors, "comparison observation is not a typed raw outcome"); continue;
    }
    const ids = p && p[row.partition + "_ids"];
    if (!Array.isArray(ids) || !ids.includes(row.prompt_id)) fail(errors, "comparison observation is outside its frozen partition");
    if (row.expected_activate && row.candidate_selected) tp += 1;
    else if (row.expected_activate) fn += 1;
    else if (row.candidate_selected) fp += 1;
    else tn += 1;
  }
  const requireObservedRows = (ids, partition, label) => {
    if (!Array.isArray(ids)) return;
    for (const id of ids) {
      const count = report.observations.filter(row => row?.prompt_id === id && row?.partition === partition).length;
      if (count === 0) fail(errors, "comparison " + label + " requires at least one observed outcome: " + id);
    }
  };
  requireObservedRows(p?.final_acceptance_ids, "final_acceptance", "final acceptance");
  requireObservedRows(report.candidate_selection_ids, "validation", "candidate selection");
  if (!exactKeys(report.metrics, ["positive_recall", "negative_false_positive_rate", "precision"])) fail(errors, "comparison per-class metrics required");
  else {
    validateMetric(report.metrics.positive_recall, tp, tp + fn, "positive recall", errors);
    validateMetric(report.metrics.negative_false_positive_rate, fp, tn + fp, "negative false-positive rate", errors);
    validateMetric(report.metrics.precision, tp, tp + fp, "precision", errors);
  }
}

function validateEvents(events, errors) {
  const schemas = {
    design_presented: ["sequence", "action", "status", "sha256"],
    approval_received: ["sequence", "action", "status", "sha256"],
    target_inspected: ["sequence", "action", "status", "path", "sha256"],
    target_file_written: ["sequence", "action", "status", "path", "sha256"],
    target_file_preserved: ["sequence", "action", "status", "path", "sha256"],
    guidance_source_checked: ["sequence", "action", "status", "source_identity", "sha256", "checked_at", "checker_report"],
    baseline_run_completed: ["sequence", "action", "status", "run_id", "source_snapshot_sha256", "output_root", "conditions_sha256", "prompt_set_digest", "rubric_digest"],
    candidate_run_completed: ["sequence", "action", "status", "run_id", "source_snapshot_sha256", "output_root", "conditions_sha256", "prompt_set_digest", "rubric_digest"]
  };
  if (!Array.isArray(events) || !events.length || events.length > 2000) { fail(errors, "bounded operation event trace required"); return []; }
  let previous = 0;
  for (const event of events) {
    const keys = schemas[event?.action];
    if (!keys || !exactKeys(event, keys) || !Number.isSafeInteger(event.sequence) || event.sequence <= previous
      || !["started", "succeeded", "failed"].includes(event.status)) fail(errors, "operation event is unsupported, unordered, or malformed");
    if (event && ["design_presented", "approval_received", "target_inspected", "target_file_written", "target_file_preserved"].includes(event.action)
      && !hashPattern.test(event.sha256 || "")) fail(errors, "operation event digest is invalid");
    if (event?.action === "target_file_written" || event?.action === "target_file_preserved") {
      if (!nonblank(event.path)) fail(errors, "file operation path is required");
    }
    if (event?.action === "target_inspected" && !nonblank(event.path)) fail(errors, "inspection path is required");
    if (event?.action === "guidance_source_checked" && (!nonblank(event.source_identity) || !nonblank(event.checked_at)
      || (event.sha256 !== null && !hashPattern.test(event.sha256 || ""))
      || !event.checker_report || typeof event.checker_report !== "object" || Array.isArray(event.checker_report))) {
      fail(errors, "guidance event must capture the checker report and any available digest");
    }
    if (["baseline_run_completed", "candidate_run_completed"].includes(event?.action)
      && (!nonblank(event.run_id) || !hashPattern.test(event.source_snapshot_sha256 || "") || !path.isAbsolute(event.output_root)
        || !hashPattern.test(event.conditions_sha256 || "") || !hashPattern.test(event.prompt_set_digest || "")
        || !hashPattern.test(event.rubric_digest || ""))) fail(errors, "comparison run event identity is incomplete");
    if (event && Number.isSafeInteger(event.sequence)) previous = event.sequence;
  }
  return events;
}

function uniqueOutcomeForIdentity(events, action, identityMatches, label, errors) {
  const matches = events.filter(event => event.action === action && identityMatches(event));
  const started = matches.filter(event => event.status === "started");
  const succeeded = matches.filter(event => event.status === "succeeded");
  const failed = matches.filter(event => event.status === "failed");
  if (failed.length) fail(errors, label + ": failed outcome cannot be masked by success");
  if (started.length > 1) fail(errors, label + ": duplicate started outcomes are not accepted");
  if (succeeded.length > 1) fail(errors, label + ": duplicate successful outcomes are not accepted");
  if (started.length && succeeded.length && started[0].sequence > succeeded[0].sequence) {
    fail(errors, label + ": started outcome after success is not accepted");
  }
  if (succeeded.length !== 1) fail(errors, label + ": exactly one successful outcome is required");
  return succeeded.length === 1 ? succeeded[0] : null;
}

function inspectSourcePath(sourceRoot, absolutePath, inspectedEvents, errors) {
  if (!sourceRoot || typeof absolutePath !== "string") return null;
  const relative = path.relative(sourceRoot, absolutePath);
  const file = resolveUnder(sourceRoot, relative.split(path.sep).join("/"), errors, "assessment evidence");
  if (!file || path.resolve(file) !== path.resolve(absolutePath)) return null;
  const bytes = safeFile(file, "assessment evidence", errors);
  if (!bytes) return null;
  const sha256 = digestBytes(bytes);
  const event = uniqueOutcomeForIdentity(inspectedEvents, "target_inspected",
    item => item.path === absolutePath && item.sha256 === sha256,
    "inspection " + relative.split(path.sep).join("/"), errors);
  if (!event) return null;
  return {path: absolutePath, sha256, event};
}

function validateMetAssessmentCriterion(criterion, evidencePath, context, sourceRoot, inspectedPaths, errors) {
  if (criterion === "contract structure is supported") {
    const requiredPaths = ["contracts/input.yaml", "contracts/output.yaml", "contracts/phase-gates.yaml"];
    if (requiredPaths.some(relative => !inspectedPaths.has(path.join(sourceRoot, relative)))) {
      fail(errors, "assessment met contract structure without inspecting the required contract files"); return;
    }
    const validator = path.resolve(__dirname, "../../skills/validate-skills.sh");
    try { execFileSync("bash", [validator, "--skill", sourceRoot], {encoding: "utf8"}); }
    catch (error) { fail(errors, "assessment met contract structure without passing the skill validator: " + String(error.stderr || error.stdout || error.message).trim()); }
    return;
  }
  if (criterion === "activation evidence is present") {
    const fixturePath = path.join(sourceRoot, "evals/cases.json");
    if (!inspectedPaths.has(fixturePath) || evidencePath !== fixturePath) {
      fail(errors, "assessment met activation evidence without inspecting the registered fixture"); return;
    }
    const inspection = inspectedPaths.get(fixturePath);
    const fixtureBytes = safeFile(fixturePath, "activation fixture", errors);
    if (!fixtureBytes || !inspection || digestBytes(fixtureBytes) !== inspection.sha256) {
      fail(errors, "assessment met activation evidence without citing the inspected fixture bytes"); return;
    }
    let fixture;
    try { fixture = JSON.parse(fixtureBytes.toString("utf8")); }
    catch { fail(errors, "assessment met activation evidence without a readable registered fixture"); return; }
    if (!Array.isArray(fixture.activation_cases) || !fixture.activation_cases.length) {
      fail(errors, "assessment met activation evidence without activation cases"); return;
    }
    const validator = path.resolve(__dirname, "../run-skill-evals.sh");
    try { execFileSync("bash", [validator, "--validate-fixture", "--skill", sourceRoot], {encoding: "utf8"}); }
    catch (error) { fail(errors, "assessment met activation evidence without passing the registered fixture validator: " + String(error.stderr || error.stdout || error.message).trim()); }
    return;
  }
  if (context.comparison_required && ["baseline and candidate are bound to matched conditions", "final acceptance is held out from selection"].includes(criterion)) return;
  fail(errors, "assessment met criterion has no registered supporting validator: " + criterion);
}

function validateCreatorResponse(text, fixture, caseId, responsePath, runBinding = null) {
  const errors = [];
  const testCase = fixture?.cases?.find(item => item?.id === caseId);
  const context = testCase?.semantic_context?.creator_evidence;
  if (!testCase || testCase.semantic_validator !== validatorId || !context) { fail(errors, "registered creator evidence case required"); return errors; }
  const response = parseEnvelope(text);
  const evidence = response?.creator_evidence;
  if (!evidence) { fail(errors, "structured creator_evidence envelope required"); return errors; }
  validateCanonicalCreatorOutputs(response, errors, context.operation);
  if (!/\.(?:txt|md)$/i.test(responsePath)) { fail(errors, "response path must end in .txt or .md"); return errors; }
  const evidencePath = path.resolve(responsePath).replace(/\.(?:txt|md)$/i, ".creator-evidence.json");
  let trusted, raw;
  try {
    raw = safeFile(evidencePath, "companion trace", errors);
    if (!raw) return errors;
    trusted = JSON.parse(raw.toString("utf8"));
  } catch { fail(errors, "independently captured companion trace is missing or invalid"); return errors; }
  if (evidence.evidence_sha256 !== digestBytes(raw)) fail(errors, "response does not bind companion evidence bytes");
  const expectedTraceKeys = ["schema_version", "case_id", "capture_id", "run_id", "operation", "outcome", "skill_name", "source_root", "source_snapshot", "output_root", "events", "artifact_manifest", "preserved_files"];
  if (context.comparison_required) expectedTraceKeys.push("comparison");
  if (!exactKeys(trusted, expectedTraceKeys) || trusted.schema_version !== "1.0" || trusted.case_id !== caseId
    || !nonblank(trusted.capture_id) || !nonblank(trusted.run_id) || !operations.has(trusted.operation) || !outcomes.has(trusted.outcome)
    || !nonblank(trusted.skill_name) || !Array.isArray(trusted.artifact_manifest) || !Array.isArray(trusted.preserved_files)) {
    fail(errors, "companion trace has an invalid fixed schema"); return errors;
  }
  let binding = context.run_binding;
  if (runBinding !== null) {
    const canonicalCase = creatorCaseMap(errors).get(caseId);
    if (!canonicalCase || context.run_binding !== null || stableJson(testCase) !== stableJson(canonicalCase)) {
      fail(errors, "manifest overlay requires the unchanged canonical null-bound creator case");
      return [...new Set(errors)];
    }
    binding = runBinding;
  }
  if (!exactKeys(binding, ["capture_id", "run_id", "source_root", "source_snapshot_sha256", "output_root", "comparison_sha256"]) || !nonblank(binding.capture_id)
    || !nonblank(binding.run_id) || !nonblank(binding.output_root) || (binding.source_snapshot_sha256 !== null && !hashPattern.test(binding.source_snapshot_sha256 || ""))
    || (binding.comparison_sha256 !== null && !hashPattern.test(binding.comparison_sha256 || ""))) {
    fail(errors, "fixture has no per-run trusted capture binding"); return errors;
  }
  if (trusted.capture_id !== binding.capture_id || trusted.run_id !== binding.run_id || trusted.operation !== context.operation
    || trusted.outcome !== context.expected_outcome || trusted.skill_name !== context.skill_name) fail(errors, "trace identity differs from frozen run or case authority");
  const envelopeKeys = ["schema_version", "case_id", "capture_id", "run_id", "operation", "outcome", "skill_name", "source_snapshot_sha256", "evidence_sha256", "design", "design_sha256", "artifacts", "assessment", "refresh", "comparison"];
  if (!exactKeys(evidence, envelopeKeys) || evidence.schema_version !== "1.0" || evidence.case_id !== caseId
    || evidence.capture_id !== trusted.capture_id || evidence.run_id !== trusted.run_id || evidence.operation !== trusted.operation
    || evidence.outcome !== trusted.outcome || evidence.skill_name !== trusted.skill_name) fail(errors, "response evidence is not bound to the captured operation");
  const events = validateEvents(trusted.events, errors);
  let sourceRoot = null;
  if (trusted.source_root === null) {
    if (binding.source_root !== null || trusted.source_snapshot !== null || binding.source_snapshot_sha256 !== null) fail(errors, "unexpected source root or snapshot");
  } else {
    sourceRoot = safeDirectory(trusted.source_root, "source skill", errors);
    const boundSourceRoot = safeDirectory(binding.source_root, "bound source skill", errors);
    if (!sourceRoot || !boundSourceRoot || sourceRoot !== boundSourceRoot) fail(errors, "source root differs from frozen run binding");
  }
  const snapshot = trusted.source_snapshot;
  if (snapshot === null) {
    if (["update", "assess"].includes(context.operation) || evidence.source_snapshot_sha256 !== null) fail(errors, "existing-target operation requires source identity");
  } else if (!sourceRoot || !exactKeys(snapshot, ["path", "sha256"]) || !nonblank(snapshot.path) || !hashPattern.test(snapshot.sha256 || "")) {
    fail(errors, "source snapshot identity is invalid");
  } else {
    const sourcePath = resolveUnder(sourceRoot, "SKILL.md", errors, "source skill snapshot");
    const realSnapshot = (() => { try { return fs.realpathSync(snapshot.path); } catch { return null; } })();
    const sourceBytes = safeFile(snapshot.path, "source snapshot", errors);
    if (!sourcePath || realSnapshot !== sourcePath || !sourceBytes || digestBytes(sourceBytes) !== snapshot.sha256
      || snapshot.sha256 !== binding.source_snapshot_sha256 || evidence.source_snapshot_sha256 !== snapshot.sha256) fail(errors, "source snapshot differs from frozen run identity or actual bytes");
    else validateTargetSkillName(snapshot.path, context.skill_name, "source skill", errors);
  }
  const outputRoot = safeDirectory(trusted.output_root, "target output", errors);
  const boundOutputRoot = safeDirectory(binding.output_root, "bound target output", errors);
  if (!outputRoot || !boundOutputRoot || outputRoot !== boundOutputRoot) { fail(errors, "output root differs from frozen run binding"); return errors; }
  if (!Array.isArray(context.preserved_target_files) || !Array.isArray(context.allowed_artifacts)
    || context.preserved_target_files.some(file => !context.allowed_artifacts.includes(file))) fail(errors, "fixture preservation paths exceed fixed artifact policy");
  if (trusted.outcome === "design_pending_approval") {
    const presented = context.design_required ? uniqueOutcomeForIdentity(events, "design_presented",
      event => event.sha256 === evidence.design_sha256, "design presentation " + evidence.design_sha256, errors) : null;
    const approved = events.some(event => event.action === "approval_received" && event.sha256 === evidence.design_sha256 && event.status === "succeeded");
    if (!context.design_required || !presented || approved
      || events.some(event => event.action === "target_file_written") || listFiles(outputRoot, errors, "pending design").length
      || evidence.artifacts?.length || trusted.artifact_manifest.length || trusted.preserved_files.length) fail(errors, "design must be evidenced before approval and before any target write");
    validateDesign(evidence.design, context, presented, evidence, errors);
  } else if (trusted.outcome === "authoring_complete") {
    const design = context.design_required ? uniqueOutcomeForIdentity(events, "design_presented",
      event => event.sha256 === evidence.design_sha256, "design presentation " + evidence.design_sha256, errors) : null;
    const approval = context.design_required ? uniqueOutcomeForIdentity(events, "approval_received",
      event => event.sha256 === evidence.design_sha256, "design approval " + evidence.design_sha256, errors) : null;
    const unexpectedSuccessfulGate = events.some(event =>
      ["design_presented", "approval_received"].includes(event.action) && event.status === "succeeded");
    if (context.design_required) {
      if (!design || !approval || approval.sequence <= design.sequence || approval.sha256 !== evidence.design_sha256) fail(errors, "approved design must precede authoring");
      if (events.some(event => event.action === "target_file_written" && ["started", "succeeded"].includes(event.status) && (!approval || event.sequence <= approval.sequence))) fail(errors, "premature authoring before approval");
      validateDesign(evidence.design, context, design, evidence, errors);
    } else if (unexpectedSuccessfulGate || design || approval || evidence.design !== null || evidence.design_sha256 !== null) fail(errors, "design gate was not required for this bounded update");
    if (events.some(event => event.action === "target_file_written" && event.status === "failed")) fail(errors, "failed file action cannot establish completion");
    if (stableJson(trusted.preserved_files.map(item => item?.path)) !== stableJson(context.preserved_target_files)) fail(errors, "preserved target paths differ from fixture authority");
    validateArtifacts(evidence, context, trusted, events, outputRoot, errors);
    if (context.operation === "create") validateCreatedSkillStructure(outputRoot, errors);
    validateTargetSkillName(path.join(outputRoot, "SKILL.md"), context.skill_name, "target skill", errors);
    if (context.operation === "update") {
      validatePreservedMetadata(context, snapshot, outputRoot, errors);
      validatePreservedTargetFiles(context, trusted, events, sourceRoot, outputRoot, errors);
      validateRequestedBodyChange(testCase, snapshot, outputRoot, errors);
    } else if (context.preserved_target_files.length || trusted.preserved_files.length) fail(errors, "create operation cannot claim preserved target files");
  } else {
    const actual = listFiles(outputRoot, errors, "read-only output");
    if (actual.length || trusted.artifact_manifest.length || evidence.artifacts?.length || trusted.preserved_files.length
      || events.some(event => event.action === "target_file_written" || event.action === "target_file_preserved")) fail(errors, "read-only operation produced target artifacts or write actions");
    if (trusted.outcome === "read_only_assessment" || trusted.outcome === "comparison_assessment") {
      const assessment = evidence.assessment;
      const inspectedEvents = events.filter(event => event.action === "target_inspected");
      const inspected = snapshot ? inspectSourcePath(sourceRoot, snapshot.path, inspectedEvents, errors) : null;
      if (!snapshot || !inspected || inspected.sha256 !== snapshot.sha256) fail(errors, "assessment lacks successful inspection of the current target");
      if (!exactKeys(assessment, ["summary", "inspected_paths", "criteria_results", "findings", "gaps"]) || !nonblank(assessment.summary)
        || !Array.isArray(assessment.inspected_paths) || !assessment.inspected_paths.length || !assessment.inspected_paths.every(nonblank)
        || !Array.isArray(assessment.criteria_results) || !Array.isArray(context.assessment_criteria)
        || !Array.isArray(assessment.findings) || !Array.isArray(assessment.gaps)) fail(errors, "assessment must cite inspected evidence and disclose gaps");
      else {
        const inspectedPathEvidence = new Map();
        for (const inspectedPath of assessment.inspected_paths) {
          const record = inspectSourcePath(sourceRoot, inspectedPath, inspectedEvents, errors);
          if (record) inspectedPathEvidence.set(inspectedPath, record);
        }
        if (!inspectedPathEvidence.has(snapshot.path)) fail(errors, "assessment inspected paths omit the frozen target snapshot");
        const results = assessment.criteria_results;
        if (results.length !== context.assessment_criteria.length || results.some((item, index) => !exactKeys(item, ["criterion", "result", "evidence_path"])
          || item.criterion !== context.assessment_criteria[index] || !["met", "not_met", "not_assessed"].includes(item.result)
          || !inspectedPathEvidence.has(item.evidence_path))) fail(errors, "assessment results must match frozen criteria and successful inspected evidence");
        else {
          for (const result of results) {
            if (result.result === "met") validateMetAssessmentCriterion(result.criterion, result.evidence_path, context, sourceRoot, inspectedPathEvidence, errors);
          }
        }
        if (assessment.findings.some(item => !exactKeys(item, ["criterion", "evidence_path", "summary"]) || !nonblank(item.summary)
          || !results.some(result => result.criterion === item.criterion && result.result === "not_met")
          || !inspectedPathEvidence.has(item.evidence_path))) fail(errors, "assessment findings must support a failed criterion with successful inspected evidence");
        if (results.some(result => result.result === "not_met" && !assessment.findings.some(item => item.criterion === result.criterion))) fail(errors, "every failed criterion needs an evidence-backed finding");
        if (results.some(result => result.result === "not_assessed") && (!assessment.gaps.length || assessment.gaps.some(gap => !nonblank(gap)))) fail(errors, "unassessed criteria require honest gap disclosure");
        if (assessment.gaps.some(gap => !nonblank(gap))) fail(errors, "assessment gap disclosures must be non-empty");
      }
    } else {
      const refresh = evidence.refresh;
      const checked = exactKeys(refresh, ["summary", "source_identity", "checked_at", "revision_or_digest", "relevance", "disposition", "affected_consumers", "access_limits", "adopted"])
        ? uniqueOutcomeForIdentity(events, "guidance_source_checked",
          event => event.source_identity === refresh.source_identity && event.checked_at === refresh.checked_at,
          "guidance check " + refresh.source_identity + " at " + refresh.checked_at, errors)
        : null;
      if (!checked || !nonblank(checked.source_identity)
        || !nonblank(refresh.summary) || refresh.source_identity !== checked.source_identity || refresh.checked_at !== checked.checked_at
        || !nonblank(refresh.checked_at) || !nonblank(refresh.relevance) || !["not_adopted", "requires_review", "already_current"].includes(refresh.disposition)
        || !Array.isArray(refresh.affected_consumers) || !Array.isArray(refresh.access_limits) || refresh.adopted !== false
        || refresh.revision_or_digest !== checked?.sha256) fail(errors, "refresh must bind provenance and keep adoption separate from retrieval");
      if (checked) validateCapturedRefreshReport(response, refresh, checked, errors);
    }
    if (trusted.outcome === "comparison_assessment") {
      if (!context.comparison_required || !hashPattern.test(binding.comparison_sha256 || "")
        || digestJson(trusted.comparison) !== binding.comparison_sha256) fail(errors, "comparison differs from frozen pair binding");
      validateComparison(evidence.comparison, trusted.comparison, events, errors);
    } else if (evidence.comparison !== null || binding.comparison_sha256 !== null) fail(errors, "unrequested comparison evidence is not accepted");
  }
  return [...new Set(errors)];
}

function runCli(...args) {
  if (args[0] === "--validate-run-bindings") {
    const [, file, selectedIdsJson, ...fixturePaths] = args;
    const errors = [];
    const bytes = safeFile(file, "creator run bindings", errors);
    let selectedIds;
    try { selectedIds = JSON.parse(selectedIdsJson); }
    catch { fail(errors, "selected creator case IDs must be JSON"); }
    if (bytes && selectedIds !== undefined) errors.push(...validateRunBindings(bytes, selectedIds, fixturePaths));
    if (errors.length) {
      console.error("creator run bindings: " + [...new Set(errors)].slice(0, 16).join("; "));
      process.exitCode = 1;
    } else {
      process.stdout.write(digestBytes(bytes) + "\n");
    }
    return;
  }
  if (args[0] === "--list-output-only-case-ids") {
    process.stdout.write(outputOnlyCaseIds.join("\n") + "\n");
    return;
  }
  if (args[0] === "--validate-ordinary-output") {
    const [, caseId, responsePath] = args;
    const errors = [];
    let text;
    try { text = fs.readFileSync(responsePath, "utf8"); } catch { errors.push("response file required"); }
    if (text !== undefined) errors.push(...validateOutputOnlyCreatorResponse(text, caseId));
    if (errors.length) {
      console.error("creator ordinary output validation: " + errors.slice(0, 16).join("; "));
      process.exitCode = 1;
    }
    return;
  }
  const [responsePath, fixturePath, caseId, ...options] = args;
  const errors = [];
  let runBinding = null;
  if (options.length) {
    if (options.length !== 3 || options[0] !== "--creator-run-bindings") {
      fail(errors, "usage: response fixture case [--creator-run-bindings FILE PREFLIGHT_SHA256]");
    } else {
      runBinding = readPinnedRunBinding(options[1], options[2], caseId, errors);
    }
  }
  let fixture, text;
  try { fixture = JSON.parse(fs.readFileSync(fixturePath, "utf8")); } catch { errors.push("fixture JSON required"); }
  try { text = fs.readFileSync(responsePath, "utf8"); } catch { errors.push("response file required"); }
  if (fixture && text !== undefined) errors.push(...validateCreatorResponse(text, fixture, caseId, responsePath, runBinding));
  if (errors.length) {
    console.error("creator semantic validation: " + errors.slice(0, 16).join("; "));
    process.exitCode = 1;
  }
}

module.exports = {validatorId, validateCreatorResponse, validateOutputOnlyCreatorResponse, outputOnlyCaseIds, validateRunBindings};
if (require.main === module) runCli(...process.argv.slice(2));
