#!/usr/bin/env bash

set -euo pipefail

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "Creator semantic grader binds outcomes to captured artifacts and traces"
if node - "$FRAMEWORK_DIR" "${1:-}" "${2:-}" <<'NODE'
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {execFileSync, spawnSync} = require("node:child_process");

const repo = process.argv[2];
const exportTarget = process.argv[3] === "--export-bound-fixtures" ? process.argv[4] : null;
let exportSucceeded = false;
const fixturePath = path.join(repo, "skills/assistant-skill-creator/evals/cases.json");
const fixture = JSON.parse(fs.readFileSync(fixturePath, "utf8"));
const {validateCreatorResponse} = require(path.join(repo, "tools/evals/lib/skill-creator-semantic-validator.cjs"));
const root = fs.mkdtempSync(path.join(os.tmpdir(), "creator-domain-contract-"));
const sha = bytes => "sha256:" + crypto.createHash("sha256").update(bytes).digest("hex");
const stable = value => Array.isArray(value) ? `[${value.map(stable).join(",")}]`
  : value && typeof value === "object" ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${stable(value[key])}`).join(",")}}`
    : JSON.stringify(value);
const shaJson = value => sha(Buffer.from(stable(value), "utf8"));
const byId = id => fixture.cases.find(item => item.id === id);
const refreshCaptureCache = new Map();
const refreshCapture = (scenario = "review_required") => {
  if (refreshCaptureCache.has(scenario)) return refreshCaptureCache.get(scenario);
  const python = String.raw`
import datetime
import hashlib
import importlib.util
import contextlib
import io
import json
import sys
import tempfile
from pathlib import Path

repo = Path(sys.argv[1])
scenario = sys.argv[2]
helper = repo / "skills/assistant-skill-creator/scripts/check-upstream-guidance.py"
spec = importlib.util.spec_from_file_location("creator_upstream_checker", str(helper))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
registry = json.loads((repo / "skills/assistant-skill-creator/references/upstream-guidelines.json").read_text(encoding="utf-8"))
source = dict(registry["sources"][0])
new = b"# locally captured changed guidance\n"
if scenario in ("current", "stale"):
    source["last_assessed_sha256"] = hashlib.sha256(new).hexdigest()
    source["last_assessed_at"] = "2026-10-12T00:00:00+00:00" if scenario == "current" else "2026-08-01T00:00:00+00:00"
if scenario == "not_configured":
    source["refresh_url"] = None

def fetch(url, **kwargs):
    if scenario == "unavailable":
        return {"status_code": 503, "final_url": url, "headers": {}, "body": b""}
    if scenario == "partial":
        return {"status_code": 200, "final_url": url, "headers": {}, "body": b"partial", "partial": True, "error": "controlled incomplete response"}
    headers = {} if scenario == "complete_no_etag" else {"ETag": "local-capture"}
    return {"status_code": 200, "final_url": url, "headers": headers, "body": new}

report = module.refresh_registry(
    {"schema_version": registry["schema_version"], "assessment_window_days": registry["assessment_window_days"], "sources": [source]},
    now=datetime.datetime(2026, 10, 13, tzinfo=datetime.timezone.utc),
    fetcher=fetch,
    monotonic=lambda: 1.0,
    sleeper=lambda _: None,
)
module._fetch_url = fetch
module._snapshot_url = lambda _: None
with tempfile.TemporaryDirectory() as directory:
    registry_path = Path(directory) / "registry.json"
    registry_path.write_text(json.dumps({
        "schema_version": registry["schema_version"],
        "assessment_window_days": registry["assessment_window_days"],
        "sources": [source],
    }), encoding="utf-8")
    cli_output = io.StringIO()
    with contextlib.redirect_stdout(cli_output):
        cli_status = module.main(["--registry", str(registry_path)])
    if cli_status != 0:
        raise RuntimeError("checker CLI returned " + str(cli_status))
    cli_report = json.loads(cli_output.getvalue())
print(json.dumps({"source_id": source["source_id"], "report": report, "cli_report": cli_report,
    "fetch_had_etag": bool(fetch("unused")["headers"].get("ETag"))}))
`;
  const captured = JSON.parse(execFileSync("python3", ["-B", "-c", python, repo, scenario], {encoding: "utf8"}));
  const report = captured.report;
  const result = report.results.find(item => item.source_id === captured.source_id);
  assert.equal(Object.hasOwn(report, "schema_version"), true, scenario + ": helper report retains its versioned output shape");
  assert.equal(Object.hasOwn(result, "candidate_etag"), false, scenario + ": helper result has no undeclared ETag field");
  const cliReport = captured.cli_report;
  const cliResult = cliReport.results.find(item => item.source_id === captured.source_id);
  assert.equal(Object.hasOwn(cliReport, "schema_version"), true, scenario + ": CLI output retains its versioned output shape");
  assert.equal(Object.hasOwn(cliResult, "candidate_etag"), false, scenario + ": CLI result has no undeclared ETag field");
  const resultCapture = {
    report,
    sourceIdentity: captured.source_id,
    checkedAt: report.checked_at,
    digest: typeof result?.candidate_sha256 === "string" ? "sha256:" + result.candidate_sha256 : null,
    result,
    fetchHadEtag: captured.fetch_had_etag,
    cliCapture: {
      report: cliReport,
      sourceIdentity: captured.source_id,
      checkedAt: cliReport.checked_at,
      digest: typeof cliResult?.candidate_sha256 === "string" ? "sha256:" + cliResult.candidate_sha256 : null,
      result: cliResult
    }
  };
  refreshCaptureCache.set(scenario, resultCapture);
  return resultCapture;
};
const put = (file, content) => { fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, content); };
const mkdir = dir => { fs.mkdirSync(dir, {recursive: true}); return fs.realpathSync(dir); };
const fileBytes = file => fs.readFileSync(file);
const baseSkill = `---\nname: assistant-note-scope\ndescription: A narrow note skill.\ncompatibility: Codex\nlicense: MIT\nmetadata:\n  reviewed: true\nallowed-tools:\n  - Read\npolicy:\n  implicit: false\nrequires:\n  - assistant-docs\n---\n\nExisting body.\n`;
const ordinaryOutputs = (caseId, capturedRefreshReport = null) => {
  const operation = byId(caseId)?.semantic_context?.creator_evidence?.operation;
  const outputs = {
    operation_summary: "The captured operation result is recorded with its unresolved evidence limits.",
    evidence_assessment: {
    status: caseId === "new-process-skill-designs-contracts-before-build" ? "planned" : "insufficient",
    scope_and_evidence_refs: caseId === "new-process-skill-designs-contracts-before-build" ? [] : [{
      evidence_ref: "skills/assistant-skill-creator/contracts/output.yaml",
      claim_kind: "structural_validity",
      claim_scope: ["Canonical required output shape"],
      selected_check_ids: [],
      binding_obligation_refs: [],
      result_state: "not_applicable",
      freshness: "current",
      exclusions: ["Output schema alone does not establish behavior or activation."]
    }],
    gaps_and_limitations: ["The offline semantic fixture does not establish host activation or task behavior."],
    next_action: "Resolve the remaining evidence gaps before claiming adequacy."
    }
  };
  if (["create", "update"].includes(operation)) {
    outputs.validation_summary = "Applicable design and policy checks were recorded for this local fixture.";
    outputs.policy_safety_summary = "Applicable constraints were checked with provider-neutral local evidence.";
  }
  if (operation === "refresh_guidance") outputs.upstream_guidance_assessment = capturedRefreshReport || refreshCapture().report;
  return outputs;
};
const assessmentSourceFiles = skillName => {
  const source = path.join(repo, "skills/assistant-verification");
  const replaceName = bytes => Buffer.from(bytes.toString("utf8").replaceAll("assistant-verification", skillName));
  const files = {"SKILL.md": replaceName(fileBytes(path.join(source, "SKILL.md")))};
  for (const name of ["index.yaml", "input.yaml", "output.yaml", "phase-gates.yaml"]) {
    files[`contracts/${name}`] = replaceName(fileBytes(path.join(source, "contracts", name)));
  }
  files["evals/cases.json"] = Buffer.from(JSON.stringify({
    schema_version: "2.0", suite_id: skillName + "-activation", skill: skillName,
    title: "Local activation evidence", description: "Provider-neutral source fixture.",
    eval_type: "skill_prompt_fixture", provider_neutral: true, model_specific_api_calls: false,
    activation_cases: [
      {user_request: "Assess evidence for a code change.", should_activate: true},
      {user_request: "Select checks for a documentation change.", should_activate: true},
      {user_request: "Write a calendar invite.", should_activate: false}
    ],
    recommended_use: ["Use for offline fixture validation only."],
    cases: [{id: "local-activation", title: "Local activation", category: "activation", purpose: "Keeps a local structural fixture.",
      prompt: "Assess evidence for a code change.", setup_context: ["The target source is local."], expected_behavior: ["Use the named source."],
      pass_criteria: ["The fixture is structurally valid."], fail_signals: ["The fixture is malformed."],
      machine_expectations: {required_substrings: ["evidence"], forbidden_substrings: ["unbounded"]}}]
  }));
  return files;
};
const schema1AssessmentSourceFiles = (sourceFiles, includeActivationCases) => {
  const files = {...sourceFiles};
  const fixture = JSON.parse(files["evals/cases.json"].toString("utf8"));
  fixture.schema_version = "1.0";
  if (!includeActivationCases) delete fixture.activation_cases;
  files["evals/cases.json"] = Buffer.from(JSON.stringify(fixture));
  return files;
};

function makeRun(caseId, {sourceFiles = {}, outputFiles = {}, events = [], manifestPaths = [], preservedPaths = [], design = null, assessment = null, refresh = null, refreshReport = null, comparison = null, comparisonPair = null, eventOverrides = null} = {}) {
  const testCase = JSON.parse(JSON.stringify(byId(caseId)));
  const context = testCase.semantic_context.creator_evidence;
  const work = path.join(root, caseId + "-" + crypto.randomBytes(4).toString("hex"));
  const sourceRootPath = path.join(work, context.skill_name);
  const outputRootPath = path.join(work, context.operation === "create" ? context.skill_name : "output");
  const responseRoot = path.join(work, "responses");
  const responseDir = path.join(responseRoot, "assistant-skill-creator");
  const skillDir = path.join(work, "assistant-skill-creator");
  const fixtureDir = path.join(skillDir, "evals");
  fs.mkdirSync(responseDir, {recursive: true});
  fs.mkdirSync(fixtureDir, {recursive: true});
  put(path.join(skillDir, "SKILL.md"), "# creator semantic fixture\n");
  const responsePath = path.join(responseDir, caseId + ".txt");
  let sourceRoot = null, snapshot = null;
  for (const [name, bytes] of Object.entries(sourceFiles)) put(path.join(sourceRootPath, name), bytes);
  if (Object.keys(sourceFiles).length) {
    sourceRoot = fs.realpathSync(sourceRootPath);
    const sourcePath = path.join(sourceRoot, "SKILL.md");
    snapshot = {path: sourcePath, sha256: sha(fileBytes(sourcePath))};
  }
  const outputRoot = mkdir(outputRootPath);
  for (const [name, bytes] of Object.entries(outputFiles)) put(path.join(outputRoot, name), bytes);
  const captureId = "capture-" + crypto.randomBytes(5).toString("hex");
  const runId = "run-" + crypto.randomBytes(5).toString("hex");
  const pair = comparisonPair || null;
  context.run_binding = {
    capture_id: captureId,
    run_id: runId,
    source_root: sourceRoot,
    source_snapshot_sha256: snapshot?.sha256 ?? null,
    output_root: outputRoot,
    comparison_sha256: pair ? shaJson(pair) : null
  };
  const artifactManifest = manifestPaths.map(name => ({path: name, sha256: sha(fileBytes(path.join(outputRoot, name)))}))
    .sort((left, right) => left.path.localeCompare(right.path));
  const preservedFiles = preservedPaths.map(name => ({path: name, sha256: sha(fileBytes(path.join(sourceRoot, name)))}));
  const traceEvents = eventOverrides || (typeof events === "function" ? events(sourceRoot, sourceFiles) : events);
  const assessmentValue = typeof assessment === "function" ? assessment(sourceRoot, sourceFiles) : assessment;
  const trace = {
    schema_version: "1.0", case_id: caseId, capture_id: captureId, run_id: runId,
    operation: context.operation, outcome: context.expected_outcome, skill_name: context.skill_name,
    source_root: sourceRoot, source_snapshot: snapshot, output_root: outputRoot,
    events: traceEvents, artifact_manifest: artifactManifest, preserved_files: preservedFiles
  };
  if (context.comparison_required) trace.comparison = pair;
  const traceBytes = Buffer.from(JSON.stringify(trace), "utf8");
  const evidencePath = path.join(responseDir, caseId + ".creator-evidence.json");
  put(evidencePath, traceBytes);
  const designHash = design ? shaJson(design) : null;
  const envelope = {
    schema_version: "1.0", case_id: caseId, capture_id: captureId, run_id: runId,
    operation: context.operation, outcome: context.expected_outcome, skill_name: context.skill_name,
    source_snapshot_sha256: snapshot?.sha256 ?? null, evidence_sha256: sha(traceBytes),
    design, design_sha256: designHash,
    artifacts: artifactManifest, assessment: assessmentValue, refresh, comparison
  };
  const fixtureCopy = JSON.parse(JSON.stringify(fixture));
  fixtureCopy.cases = fixtureCopy.cases.map(item => item.id === caseId ? testCase : item);
  put(path.join(fixtureDir, "cases.json"), JSON.stringify(fixtureCopy));
  const writeResponse = () => put(responsePath, JSON.stringify({summary: testCase.machine_expectations.required_substrings.join(" "),
    ...ordinaryOutputs(caseId, refreshReport), creator_evidence: envelope}) + "\n");
  writeResponse();
  return {errors: () => validateCreatorResponse(fs.readFileSync(responsePath, "utf8"), {cases: [testCase]}, caseId, responsePath), context, trace, envelope, outputRoot, sourceRoot, responsePath, evidencePath, responseRoot, skillDir, writeResponse, work};
}

function check(label, run, expected = false) {
  const errors = run.errors();
  if (expected) assert(errors.length > 0, `${label}: expected domain rejection`);
  else assert.deepEqual(errors, [], `${label}: ${errors.join("; ")}`);
  const graded = spawnSync("bash", [path.join(repo, "tools/evals/run-skill-evals.sh"), "--responses", run.responseRoot,
    "--skill", run.skillDir, "--case", run.contextCaseId || path.basename(run.responsePath, ".txt")], {encoding: "utf8"});
  if (expected) {
    assert.notEqual(graded.status, 0, `${label}: registered runner unexpectedly passed`);
    assert.match(graded.stdout + graded.stderr, /FAIL\s+assistant-skill-creator/);
  } else {
    assert.equal(graded.status, 0, `${label}: registered runner failed: ${graded.stdout}\n${graded.stderr}`);
    assert.match(graded.stdout, /PASS\s+assistant-skill-creator/);
  }
  process.stdout.write(`ok - ${label}\n`);
}

const findingControlFailures = [];
function findingControl(label, run) {
  try {
    check(label, run, true);
  } catch (error) {
    findingControlFailures.push(label + ": " + error.message);
    process.stdout.write("not ok - " + label + ": " + error.message.split("\n")[0] + "\n");
  }
}

function findingPositiveControl(label, action) {
  try {
    action();
    process.stdout.write(`ok - ${label}\n`);
  } catch (error) {
    findingControlFailures.push(label + ": " + error.message);
    process.stdout.write("not ok - " + label + ": " + error.message.split("\n")[0] + "\n");
  }
}

function fileEventsWithStarted(events, action, targetPath, count = 1, position = "before") {
  const outcome = events.find(event => event.action === action && event.path === targetPath && event.status === "succeeded");
  assert(outcome, `missing successful ${action} event for ${targetPath}`);
  const started = Array.from({length: count}, () => ({...outcome, status: "started"}));
  const expanded = [];
  for (const event of events) {
    if (position === "before" && event === outcome) expanded.push(...started);
    expanded.push(event);
  }
  if (position === "after") expanded.push(...started);
  return expanded.map((event, index) => ({...event, sequence: index + 1}));
}

function sharedMetadataProbe(file, skillName) {
  const command = 'source "$1/tools/skills/lib/validate-frontmatter.sh"; frontmatter_standard_metadata_errors "$2" "$3"';
  return spawnSync("bash", ["-c", command, "shared-frontmatter-metadata", repo, file, skillName], {cwd: repo, encoding: "utf8"});
}

function designFor(name, category, contracts) {
  return {skill_name: name, purpose: "Convert a user label into a stable slug.", category, value_kind: "capability",
    success_criteria: ["A required label input is validated", "A slug is returned or failure is recovered"], contracts};
}

function exportBoundFixtureProjection(targetDir, runs) {
  const bundle = path.resolve(targetDir);
  const skillDir = path.join(bundle, "skill", "assistant-skill-creator");
  const fixtureDir = path.join(skillDir, "evals");
  const responseDir = path.join(bundle, "responses", "assistant-skill-creator");
  fs.mkdirSync(fixtureDir, {recursive: true});
  fs.mkdirSync(responseDir, {recursive: true});
  put(path.join(skillDir, "SKILL.md"), fs.readFileSync(path.join(runs[0].skillDir, "SKILL.md")));
  const projected = JSON.parse(JSON.stringify(fixture));
  projected.cases = runs.map(run => {
    const caseId = path.basename(run.responsePath, ".txt");
    const capturedFixture = JSON.parse(fs.readFileSync(path.join(run.skillDir, "evals/cases.json"), "utf8"));
    const testCase = capturedFixture.cases.find(item => item.id === caseId);
    assert(testCase, "bound case fixture is missing: " + caseId);
    assert.equal(testCase.semantic_context.creator_evidence.run_binding.run_id, run.trace.run_id,
      "fixture binding must match the actual captured trace: " + caseId);
    const capturedResponse = fs.readFileSync(run.responsePath, "utf8");
    const capturedOutputs = JSON.parse(capturedResponse);
    assert(capturedOutputs.operation_summary && capturedOutputs.evidence_assessment && capturedOutputs.creator_evidence,
      "positive case response did not retain its tested ordinary outputs and envelope: " + caseId);
    const response = {summary: testCase.machine_expectations.required_substrings.join(" "), ...capturedOutputs};
    const exportedResponsePath = path.join(responseDir, caseId + ".txt");
    fs.writeFileSync(exportedResponsePath, JSON.stringify(response) + "\n");
    fs.copyFileSync(run.evidencePath, path.join(responseDir, caseId + ".creator-evidence.json"));
    const exportedErrors = validateCreatorResponse(fs.readFileSync(exportedResponsePath, "utf8"), {cases: [testCase]}, caseId, exportedResponsePath);
    assert.deepEqual(exportedErrors, [], caseId + ": exported response differs from its tested positive capture");
    return testCase;
  });
  const genericCases = fixture.cases.filter(testCase => !testCase.semantic_validator);
  for (const testCase of genericCases) {
    const caseId = testCase.id;
    const response = {
      summary: ["Local grading response for assistant-skill-creator/" + caseId + ".", ...testCase.machine_expectations.required_substrings].join("\n"),
      ...ordinaryOutputs(caseId)
    };
    fs.writeFileSync(path.join(responseDir, caseId + ".txt"), JSON.stringify(response) + "\n");
  }
  projected.cases.push(...genericCases);
  put(path.join(fixtureDir, "cases.json"), JSON.stringify(projected));
  const runner = path.join(repo, "tools/evals/run-skill-evals.sh");
  const graded = spawnSync("bash", [runner, "--responses", path.join(bundle, "responses"), "--skill", skillDir], {encoding: "utf8"});
  assert.equal(graded.status, 0, "projected bound creator fixtures failed registered grading: " + graded.stdout + graded.stderr);
  assert.match(graded.stdout, /Summary: total=11 passed=11 failed=0/);
  const outputControlId = "assess-existing-skill-without-authoring";
  const outputControlPath = path.join(responseDir, outputControlId + ".txt");
  const validOutputControl = JSON.parse(fs.readFileSync(outputControlPath, "utf8"));
  const rejectOutputControl = (label, mutate) => {
    const invalid = JSON.parse(JSON.stringify(validOutputControl));
    mutate(invalid);
    fs.writeFileSync(outputControlPath, JSON.stringify(invalid) + "\n");
    const result = spawnSync("bash", [runner, "--responses", path.join(bundle, "responses"), "--skill", skillDir, "--case", outputControlId], {encoding: "utf8"});
    assert.notEqual(result.status, 0, label + ": registered grader unexpectedly accepted invalid ordinary output");
    assert.match(result.stdout + result.stderr, /FAIL\s+assistant-skill-creator/);
    process.stdout.write("ok - " + label + " is rejected by registered grading\n");
  };
  rejectOutputControl("missing operation_summary", value => { delete value.operation_summary; });
  rejectOutputControl("type-invalid operation_summary", value => { value.operation_summary = {summary: "nested"}; });
  rejectOutputControl("missing evidence_assessment", value => { delete value.evidence_assessment; });
  rejectOutputControl("type-invalid evidence_assessment", value => { value.evidence_assessment = []; });
  rejectOutputControl("malformed canonical scope evidence item", value => {
    value.evidence_assessment.scope_and_evidence_refs = [{junk: 1}];
  });
  rejectOutputControl("non-string canonical evidence gap", value => {
    value.evidence_assessment.gaps_and_limitations = [7];
  });
  rejectOutputControl("malformed nested evidence assessment", value => {
    value.evidence_assessment = {status: "insufficient", scope_and_evidence_refs: [{junk: 1}], gaps_and_limitations: [7], next_action: "review"};
  });
  const boundNested = spawnSync("bash", [runner, "--responses", path.join(bundle, "responses"), "--skill", skillDir, "--case", outputControlId], {encoding: "utf8"});
  assert.match(boundNested.stdout, /Summary: total=1 passed=0 failed=1 .*structured_json_assertion_failures=0 semantic_validation_failures=1/);
  fs.writeFileSync(outputControlPath, JSON.stringify(validOutputControl) + "\n");

  const genericOutputId = "existing-skill-validation-enforces-checklist";
  const genericOutputPath = path.join(responseDir, genericOutputId + ".txt");
  const validGenericOutput = JSON.parse(fs.readFileSync(genericOutputPath, "utf8"));
  const malformedGenericOutput = JSON.parse(JSON.stringify(validGenericOutput));
  malformedGenericOutput.evidence_assessment = {
    status: "insufficient", scope_and_evidence_refs: [{junk: 1}], gaps_and_limitations: [7], next_action: "review"
  };
  fs.writeFileSync(genericOutputPath, JSON.stringify(malformedGenericOutput) + "\n");
  const genericNested = spawnSync("bash", [runner, "--responses", path.join(bundle, "responses"), "--skill", skillDir, "--case", genericOutputId], {encoding: "utf8"});
  assert.notEqual(genericNested.status, 0, "generic creator case unexpectedly accepted malformed nested producer output");
  assert.match(genericNested.stdout + genericNested.stderr, /FAIL\s+assistant-skill-creator/);
  assert.match(genericNested.stdout, /Summary: total=1 passed=0 failed=1 .*structured_json_assertion_failures=1 semantic_validation_failures=0/);
  process.stdout.write("ok - malformed nested producer output is rejected for an output-only creator case\n");
  fs.writeFileSync(genericOutputPath, JSON.stringify(validGenericOutput) + "\n");
  const foreignId = "unregistered-creator-output-case";
  const foreignCase = JSON.parse(JSON.stringify(genericCases[0]));
  foreignCase.id = foreignId;
  const foreignFixture = JSON.parse(JSON.stringify(projected));
  foreignFixture.cases.push(foreignCase);
  put(path.join(fixtureDir, "cases.json"), JSON.stringify(foreignFixture));
  put(path.join(responseDir, foreignId + ".txt"), JSON.stringify({
    summary: ["Local grading response for assistant-skill-creator/" + foreignId + ".", ...foreignCase.machine_expectations.required_substrings].join("\n"),
    ...ordinaryOutputs(foreignId)
  }) + "\n");
  const foreign = spawnSync("bash", [runner, "--responses", path.join(bundle, "responses"), "--skill", skillDir, "--case", foreignId], {encoding: "utf8"});
  assert.notEqual(foreign.status, 0, "foreign creator case bypassed the closed output-only identity set");
  assert.match(foreign.stderr, /creator ordinary output validation: output-only creator case ID is not registered/);
  process.stdout.write("ok - foreign creator case cannot bypass the closed ordinary-output identities\n");
  fs.rmSync(path.join(responseDir, foreignId + ".txt"), {force: true});
  put(path.join(fixtureDir, "cases.json"), JSON.stringify(projected));

  const canonicalFixtureHashBeforeBindings = sha(fileBytes(fixturePath));
  const bindingsPath = path.join(bundle, "creator-run-bindings.json");
  const bindingEntries = runs.map(run => ({
    case_id: path.basename(run.responsePath, ".txt"),
    run_binding: JSON.parse(JSON.stringify(run.context.run_binding))
  }));
  const fullBindings = {schema_version: "1.0", cases: bindingEntries};
  const writeBindings = value => put(bindingsPath, JSON.stringify(value, null, 2) + "\n");
  const bindingRunnerArgs = extra => [runner, "--responses", path.join(bundle, "responses"), "--skill", "assistant-skill-creator",
    ...extra, "--creator-run-bindings", bindingsPath];
  const bindingNegative = (label, manifest, extra = [], expectPreflight = true) => {
    writeBindings(manifest);
    const result = spawnSync("bash", bindingRunnerArgs(extra), {encoding: "utf8"});
    const output = result.stdout + result.stderr;
    assert.notEqual(result.status, 0, label + ": registered grader unexpectedly accepted invalid run bindings");
    if (expectPreflight) assert.match(output, /creator run bindings:/, label + ": expected whole-manifest rejection");
    else assert.match(output, /FAIL\s+assistant-skill-creator/, label + ": expected semantic capture rejection");
    process.stdout.write("ok - " + label + " is rejected\n");
    return result;
  };

  writeBindings(fullBindings);
  const canonicalBound = spawnSync("bash", bindingRunnerArgs([]), {encoding: "utf8"});
  assert.equal(canonicalBound.status, 0, "canonical null-bound fixture must grade all six cases with an independent manifest: "
    + canonicalBound.stdout + canonicalBound.stderr);
  assert.match(canonicalBound.stdout, /Summary: total=11 passed=11 failed=0/);
  process.stdout.write("ok - all six canonical creator cases pass through the selected run-binding manifest\n");

  const noManifest = spawnSync("bash", [runner, "--responses", path.join(bundle, "responses"), "--skill", "assistant-skill-creator"], {encoding: "utf8"});
  assert.notEqual(noManifest.status, 0, "canonical null-bound fixture unexpectedly passed without an explicit run manifest");
  assert.match(noManifest.stdout, /FAIL\s+assistant-skill-creator/);
  process.stdout.write("ok - response and companion files cannot replace a missing run-binding manifest\n");

  bindingNegative("missing selected binding", {...fullBindings, cases: bindingEntries.slice(1)});
  bindingNegative("duplicate binding entry", {...fullBindings, cases: [...bindingEntries, bindingEntries[0]]});
  bindingNegative("unknown binding case", {...fullBindings, cases: bindingEntries.map((entry, index) => index === 0 ? {...entry, case_id: "unregistered-case"} : entry)});
  bindingNegative("malformed binding fields", {...fullBindings, cases: bindingEntries.map((entry, index) => index === 0
    ? {...entry, run_binding: {...entry.run_binding, unknown: true}} : entry)});
  bindingNegative("extra unselected binding", fullBindings, ["--case", bindingEntries[0].case_id]);

  const assessBindingId = "assess-existing-skill-without-authoring";
  const comparisonBindingId = "assess-skill-contracts-under-frozen-comparison";
  const pristineBindingEntries = JSON.stringify(bindingEntries);
  const oneBinding = caseId => ({schema_version: "1.0", cases: [JSON.parse(JSON.stringify(bindingEntries.find(entry => entry.case_id === caseId)))]});
  const bindingFor = (caseId, mutate) => {
    const value = oneBinding(caseId);
    mutate(value.cases[0].run_binding);
    return value;
  };
  bindingFor("assess-existing-skill-without-authoring", binding => { binding.capture_id = "control-only-capture"; });
  assert.equal(JSON.stringify(bindingEntries), pristineBindingEntries,
    "an individual binding control must not mutate the pristine manifest baseline");
  const oneCaseArgs = caseId => ["--case", caseId];
  const bindingPositive = caseId => {
    writeBindings(oneBinding(caseId));
    const result = spawnSync("bash", bindingRunnerArgs(oneCaseArgs(caseId)), {encoding: "utf8"});
    assert.equal(result.status, 0, caseId + ": valid one-case binding was rejected: " + result.stdout + result.stderr);
    assert.match(result.stdout, /PASS\s+assistant-skill-creator/);
    assert(result.stdout.includes(caseId), caseId + ": selected creator case was not reported as passing");
    process.stdout.write("ok - valid single-case binding passes for " + caseId + "\n");
  };
  bindingPositive(assessBindingId);
  bindingPositive(comparisonBindingId);
  for (const [label, mutate] of [
    ["capture ID mismatch", binding => { binding.capture_id = "different-capture"; }],
    ["run ID mismatch", binding => { binding.run_id = "different-run"; }],
    ["output path mismatch", binding => { binding.output_root = mkdir(path.join(bundle, "wrong-output-root")); }],
    ["source path mismatch", binding => { binding.source_root = mkdir(path.join(bundle, "wrong-source-root")); }],
    ["source snapshot hash mismatch", binding => { binding.source_snapshot_sha256 = "sha256:" + "0".repeat(64); }]
  ]) bindingNegative(label, bindingFor(assessBindingId, mutate), oneCaseArgs(assessBindingId), false);
  bindingNegative("comparison hash mismatch", bindingFor(comparisonBindingId,
    binding => { binding.comparison_sha256 = "sha256:" + "0".repeat(64); }), oneCaseArgs(comparisonBindingId), false);

  const responsePath = path.join(responseDir, assessBindingId + ".txt");
  const tracePath = path.join(responseDir, assessBindingId + ".creator-evidence.json");
  const savedResponse = fileBytes(responsePath);
  const savedTrace = fileBytes(tracePath);
  try {
    const response = JSON.parse(savedResponse.toString("utf8"));
    response.creator_evidence.capture_id = "response-forged-capture";
    put(responsePath, JSON.stringify(response) + "\n");
    bindingNegative("response cannot override manifest capture identity", oneBinding(assessBindingId), oneCaseArgs(assessBindingId), false);
    put(responsePath, savedResponse);
    const trace = JSON.parse(savedTrace.toString("utf8"));
    trace.output_root = mkdir(path.join(bundle, "tampered-trace-output"));
    put(tracePath, JSON.stringify(trace));
    bindingNegative("companion tampering is rejected", oneBinding(assessBindingId), oneCaseArgs(assessBindingId), false);
  } finally {
    put(responsePath, savedResponse);
    put(tracePath, savedTrace);
  }

  writeBindings(oneBinding(assessBindingId));
  const wrongPin = spawnSync("node", [path.join(repo, "tools/evals/lib/skill-creator-semantic-validator.cjs"),
    responsePath, fixturePath, assessBindingId, "--creator-run-bindings", bindingsPath, "sha256:" + "0".repeat(64)], {encoding: "utf8"});
  assert.notEqual(wrongPin.status, 0, "per-case validator unexpectedly accepted a changed manifest digest");
  assert.match(wrongPin.stderr, /changed after whole-manifest preflight/);
  process.stdout.write("ok - per-case creator checks reject a manifest that differs from the pinned preflight bytes\n");

  const customSkillDir = mkdir(path.join(bundle, "custom", "assistant-skill-creator"));
  fs.copyFileSync(path.join(repo, "skills/assistant-skill-creator/SKILL.md"), path.join(customSkillDir, "SKILL.md"));
  const customFixturePath = path.join(customSkillDir, "evals/cases.json");
  put(customFixturePath, fileBytes(fixturePath));
  const customFixture = JSON.parse(fileBytes(customFixturePath).toString("utf8"));
  customFixture.cases.find(item => item.id === assessBindingId).semantic_context.creator_evidence.assessment_criteria.pop();
  put(customFixturePath, JSON.stringify(customFixture));
  writeBindings(oneBinding(assessBindingId));
  const customPolicy = spawnSync("bash", [runner, "--responses", path.join(bundle, "responses"), "--skill", customSkillDir,
    "--case", assessBindingId, "--creator-run-bindings", bindingsPath], {encoding: "utf8"});
  assert.notEqual(customPolicy.status, 0, "custom fixture policy mutation unexpectedly weakened the manifest authority");
  assert.match(customPolicy.stderr, /creator run bindings:/);
  process.stdout.write("ok - custom creator policy cannot be combined with the canonical run manifest\n");

  const duplicateSkillDirs = ["first", "second"].map(name => mkdir(path.join(bundle, "ambiguous", name, "assistant-skill-creator")));
  for (const dir of duplicateSkillDirs) {
    fs.copyFileSync(path.join(repo, "skills/assistant-skill-creator/SKILL.md"), path.join(dir, "SKILL.md"));
    put(path.join(dir, "evals/cases.json"), fileBytes(fixturePath));
  }
  writeBindings(oneBinding(assessBindingId));
  const ambiguousFixtures = spawnSync("bash", [runner, "--responses", path.join(bundle, "responses"),
    "--skill", duplicateSkillDirs[0], "--skill", duplicateSkillDirs[1], "--case", assessBindingId,
    "--creator-run-bindings", bindingsPath], {encoding: "utf8"});
  assert.notEqual(ambiguousFixtures.status, 0, "duplicate selected fixture ownership unexpectedly passed");
  assert.match(ambiguousFixtures.stderr, /exactly one fixture owner/);
  process.stdout.write("ok - ambiguous selected creator fixture ownership is rejected\n");

  writeBindings(fullBindings);
  const existingBoundFixture = spawnSync("bash", [runner, "--responses", path.join(bundle, "responses"), "--skill", skillDir,
    "--creator-run-bindings", bindingsPath], {encoding: "utf8"});
  assert.notEqual(existingBoundFixture.status, 0, "manifest option unexpectedly overwrote non-null fixture run bindings");
  assert.match(existingBoundFixture.stderr, /null-bound fixture/);
  process.stdout.write("ok - manifest option rejects already-bound fixture cases\n");

  assert.equal(sha(fileBytes(fixturePath)), canonicalFixtureHashBeforeBindings,
    "manifest grading and all negative controls must leave the canonical fixture bytes unchanged");
  process.stdout.write("ok - canonical creator fixture hash is unchanged after manifest grading controls\n");

  fs.writeFileSync(path.join(bundle, "manifest.json"), JSON.stringify({
    schema_version: "1.0",
    retained_run_root: root,
    skill_dir: skillDir,
    fixture_path: path.join(fixtureDir, "cases.json"),
    response_dir: responseDir,
    case_ids: projected.cases.map(item => item.id)
  }, null, 2) + "\n");
  process.stdout.write("ok - six bound creator cases and five generic cases pass through the registered runner\n");
  process.stdout.write(graded.stdout.split("\n").find(line => line.startsWith("Summary:")) + "\n");
  exportSucceeded = true;
}

try {
  const genericBoundaryDir = path.join(root, "strict-generic-boundary");
  const genericBoundaryFixture = {schema_version: "1.0", skill: "assistant-note-scope", cases: [{
    id: "neutral-structured-assertion",
    machine_expectations: {structured_json_assertions: [{operator: "equals", path: ["count"], expected: 1}]}
  }]};
  const genericBoundaryFixturePath = path.join(genericBoundaryDir, "fixture.json");
  const genericBoundaryResponsePath = path.join(genericBoundaryDir, "response.json");
  put(genericBoundaryFixturePath, JSON.stringify(genericBoundaryFixture));
  put(genericBoundaryResponsePath, JSON.stringify({count: 1}) + "\n");
  const genericBoundaryCommand = 'set -euo pipefail; REPO_ROOT="$1"; source "$REPO_ROOT/tools/evals/lib/skill-eval-grade.sh"; count_structured_json_assertion_failures "$2" neutral-structured-assertion "$3" assistant-note-scope; printf "caller reached end\\n"';
  const genericBoundary = spawnSync("bash", ["-c", genericBoundaryCommand, "strict-generic-boundary",
    repo, genericBoundaryFixturePath, genericBoundaryResponsePath], {cwd: repo, encoding: "utf8"});
  findingPositiveControl("strict grade-only generic caller evaluates a structured assertion without the registry", () => {
    assert.equal(genericBoundary.status, 0, genericBoundary.stderr);
    assert.equal(genericBoundary.stdout, "0\ncaller reached end\n");
  });

  // The generic grader still characterizes phrase-only behavior; the exact registered
  // creator case must then reject the same response without a trusted capture.
  const processCase = byId("new-process-skill-designs-contracts-before-build");
  const genericDir = path.join(root, "generic");
  const genericSkill = path.join(genericDir, "assistant-note-scope");
  const genericResponses = path.join(genericDir, "responses");
  fs.mkdirSync(path.join(genericSkill, "evals"), {recursive: true});
  fs.mkdirSync(path.join(genericResponses, "assistant-note-scope"), {recursive: true});
  put(path.join(genericSkill, "SKILL.md"), baseSkill);
  const genericFixture = JSON.parse(JSON.stringify(fixture));
  genericFixture.skill = "assistant-note-scope";
  genericFixture.cases = genericFixture.cases.filter(item => item.id === processCase.id).map(item => {
    delete item.semantic_context;
    delete item.semantic_validator;
    delete item.machine_expectations.structured_json_assertions;
    return item;
  });
  put(path.join(genericSkill, "evals/cases.json"), JSON.stringify(genericFixture));
  const phraseOnly = processCase.machine_expectations.required_substrings.join("\n");
  put(path.join(genericResponses, "assistant-note-scope", processCase.id + ".txt"), phraseOnly);
  const runner = path.join(repo, "tools/evals/run-skill-evals.sh");
  const genericOutput = execFileSync("bash", [runner, "--responses", genericResponses, "--skill", genericSkill, "--case", processCase.id], {encoding: "utf8"});
  assert.match(genericOutput, /PASS\s+assistant-note-scope\s+new-process-skill-designs-contracts-before-build/);
  process.stdout.write("ok - isolated neutral phrase-only control reaches the generic grader\n");
  const registeredSkill = path.join(genericDir, "assistant-skill-creator");
  fs.mkdirSync(path.join(registeredSkill, "evals"), {recursive: true});
  put(path.join(registeredSkill, "SKILL.md"), "# registered creator fixture\n");
  put(path.join(registeredSkill, "evals/cases.json"), JSON.stringify(fixture));
  put(path.join(genericResponses, "assistant-skill-creator", processCase.id + ".txt"), phraseOnly);
  const registered = spawnSync("bash", [runner, "--responses", genericResponses, "--skill", registeredSkill, "--case", processCase.id], {encoding: "utf8"});
  assert.notEqual(registered.status, 0, `registered grader unexpectedly passed phrase-only response: ${registered.stdout}`);
  assert.match(registered.stdout + registered.stderr, /FAIL\s+assistant-skill-creator\s+new-process-skill-designs-contracts-before-build/);
  process.stdout.write("ok - registered creator case rejects phrase-only completion\n");

  const processDesign = designFor("assistant-deploy", "process", [
    {name: "input.yaml", fields: [{name: "release", type: "string", required: true, on_missing: "Ask for release identifier"}]},
    {name: "output.yaml", fields: [{name: "deployment", type: "object", required: true, on_fail: "Stop and report deployment evidence"}]},
    {name: "phase-gates.yaml", fields: [{name: "approval", condition: "before deploy", assertion: "approval exists", on_fail: "Wait for approval"}]},
    {name: "handoffs.yaml", fields: [{name: "release_review", producer_fields: ["release"], consumer_fields: ["release"]}]}
  ]);
  const designHash = shaJson(processDesign);
  const pending = makeRun(processCase.id, {design: processDesign, events: [
    {sequence: 1, action: "design_presented", status: "succeeded", sha256: designHash}
  ]});
  check("typed design can await approval without writes", pending);

  const utilityId = "create-minimal-utility-validates-label-to-slug-contract";
  const utilityDesign = designFor("assistant-label-slug", "utility", [
    {name: "input.yaml", fields: [{name: "label", type: "string", required: true, on_missing: "Ask for label"}]},
    {name: "output.yaml", fields: [{name: "slug", type: "string", required: true, on_fail: "Report why slug could not be made"}]}
  ]);
  const utilityDesignHash = shaJson(utilityDesign);
  const utilityFiles = {
    "SKILL.md": "---\nname: assistant-label-slug\ndescription: Turn a label into a slug.\n---\n\nReturn a stable slug.\n",
    "contracts/input.yaml": "schema_version: \"2.0\"\ncontract: input\nskill: assistant-label-slug\n\nfields:\n  - name: label\n    type: string\n    required: true\n    description: The label to normalize.\n    validation: A non-empty user supplied label.\n    on_missing: Ask for the label.\n",
    "contracts/output.yaml": "schema_version: \"2.0\"\ncontract: output\nskill: assistant-label-slug\n\nartifacts:\n  - name: slug\n    type: string\n    required: true\n    description: The normalized label.\n    validation: A lowercase hyphenated value derived from the label.\n    on_fail: Report why a slug could not be produced.\n"
  };
  const utilityEvents = [
    {sequence: 1, action: "design_presented", status: "succeeded", sha256: utilityDesignHash},
    {sequence: 2, action: "approval_received", status: "succeeded", sha256: utilityDesignHash},
    ...Object.entries(utilityFiles).sort(([a], [b]) => a.localeCompare(b)).map(([name, bytes], index) => ({sequence: index + 3, action: "target_file_written", status: "succeeded", path: name, sha256: sha(Buffer.from(bytes))}))
  ];
  const utilityRunFor = (files = utilityFiles, events = utilityEvents) => {
    const capturedEvents = events.map(event => event.action === "target_file_written"
      ? {...event, sha256: sha(Buffer.from(files[event.path] ?? ""))} : event);
    return makeRun(utilityId, {design: utilityDesign, outputFiles: files, events: capturedEvents, manifestPaths: Object.keys(files)});
  };
  const utility = utilityRunFor();
  check("approved Utility design and actual YAML boundaries pass", utility);
  const validStartedCreate = utilityRunFor(utilityFiles,
    fileEventsWithStarted(utilityEvents, "target_file_written", "SKILL.md"));
  findingPositiveControl("CREATE accepts one started write before its matching success", () => check("CREATE started-before-success control", validStartedCreate));
  findingControl("CREATE rejects a started-only write after its earlier success", utilityRunFor(utilityFiles,
    fileEventsWithStarted(utilityEvents, "target_file_written", "SKILL.md", 1, "after")));
  findingControl("CREATE rejects duplicate starts for one written file", utilityRunFor(utilityFiles,
    fileEventsWithStarted(utilityEvents, "target_file_written", "SKILL.md", 2)));
  const missingCreateValidation = makeRun(utilityId, {design: utilityDesign, outputFiles: utilityFiles, events: utilityEvents, manifestPaths: Object.keys(utilityFiles)});
  const missingCreateValidationResponse = JSON.parse(fileBytes(missingCreateValidation.responsePath).toString("utf8"));
  delete missingCreateValidationResponse.validation_summary;
  put(missingCreateValidation.responsePath, JSON.stringify(missingCreateValidationResponse) + "\n");
  findingControl("create retains its applicable canonical validation summary", missingCreateValidation);
  for (const action of ["design_presented", "approval_received"]) {
    for (const status of ["failed", "started"]) {
      const contradictoryEvents = [...utilityEvents, {sequence: utilityEvents.length + 1, action, status, sha256: utilityDesignHash}];
      findingControl("same-design " + action + " " + status + " cannot contradict an earlier success",
        makeRun(utilityId, {design: utilityDesign, outputFiles: utilityFiles, events: contradictoryEvents, manifestPaths: Object.keys(utilityFiles)}));
    }
  }
  const wrongNameUtilityFiles = {...utilityFiles, "SKILL.md": utilityFiles["SKILL.md"].replace("assistant-label-slug", "assistant-unrelated")};
  const wrongNameUtilityEvents = utilityEvents.map(event => event.action === "target_file_written"
    ? {...event, sha256: sha(Buffer.from(wrongNameUtilityFiles[event.path]))} : event);
  check("completed output metadata must match the frozen skill name", makeRun(utilityId, {
    design: utilityDesign, outputFiles: wrongNameUtilityFiles, events: wrongNameUtilityEvents,
    manifestPaths: Object.keys(wrongNameUtilityFiles)
  }), true);
  const missingDescriptionUtilityFiles = {...utilityFiles,
    "SKILL.md": utilityFiles["SKILL.md"].replace(/^description:.*\n/m, "")};
  findingControl("completed CREATE rejects a missing required description", utilityRunFor(missingDescriptionUtilityFiles));
  const missingContractHeaderFiles = {...utilityFiles,
    "contracts/input.yaml": utilityFiles["contracts/input.yaml"].replace("contract: input\n", "")};
  findingControl("completed CREATE rejects a missing required contract header", utilityRunFor(missingContractHeaderFiles));
  const wrongUtilityBytes = {...utilityFiles, "contracts/input.yaml": "fields:\n  - name: label\n    type: string\n    required: true\n"};
  const wrongUtilityEvents = utilityEvents.map(event => event.action === "target_file_written" && event.path === "contracts/input.yaml"
    ? {...event, sha256: sha(Buffer.from(wrongUtilityBytes["contracts/input.yaml"]))} : event);
  const wrongUtility = makeRun(utilityId, {design: utilityDesign, outputFiles: wrongUtilityBytes, events: wrongUtilityEvents, manifestPaths: Object.keys(wrongUtilityBytes)});
  check("missing contract recovery is rejected", wrongUtility, true);
  const emptyUtilityFiles = {...utilityFiles, "SKILL.md": ""};
  const emptyUtilityEvents = utilityEvents.map(event => event.action === "target_file_written" && event.path === "SKILL.md"
    ? {...event, sha256: sha(Buffer.from(""))} : event);
  const emptyUtility = makeRun(utilityId, {design: utilityDesign, outputFiles: emptyUtilityFiles, events: emptyUtilityEvents, manifestPaths: Object.keys(emptyUtilityFiles)});
  check("empty artifact is rejected", emptyUtility, true);
  const staleUtility = makeRun(utilityId, {design: utilityDesign, outputFiles: utilityFiles, events: utilityEvents, manifestPaths: Object.keys(utilityFiles)});
  put(path.join(staleUtility.outputRoot, "SKILL.md"), "stale output bytes\n");
  check("artifact changed after captured digest is rejected", staleUtility, true);
  const failedWriteEvents = utilityEvents.map(event => event.action === "target_file_written" && event.path === "contracts/output.yaml"
    ? {...event, status: "failed"} : event);
  const failedWrite = makeRun(utilityId, {design: utilityDesign, outputFiles: utilityFiles, events: failedWriteEvents, manifestPaths: Object.keys(utilityFiles)});
  check("failed write cannot establish completion", failedWrite, true);
  const wrongPathEvents = [...utilityEvents, {sequence: utilityEvents.length + 1, action: "target_file_written", status: "succeeded", path: "agents/openai.yaml", sha256: sha(Buffer.from("unapproved policy write"))}];
  const wrongPath = makeRun(utilityId, {design: utilityDesign, outputFiles: utilityFiles, events: wrongPathEvents, manifestPaths: Object.keys(utilityFiles)});
  check("write action outside the captured manifest is rejected", wrongPath, true);
  const prematureEvents = [
    utilityEvents[0],
    {...utilityEvents[2], sequence: 2},
    {...utilityEvents[1], sequence: 3},
    ...utilityEvents.slice(3).map((event, index) => ({...event, sequence: index + 4}))
  ];
  const premature = makeRun(utilityId, {design: utilityDesign, outputFiles: utilityFiles, events: prematureEvents, manifestPaths: Object.keys(utilityFiles)});
  check("authoring before approval is rejected", premature, true);

  const updateId = "narrow-existing-skill-update-preserves-metadata-and-agent-policy";
  const preservedFiles = {
    "agents/openai.yaml": "interface:\n  display_name: Notes\npolicy:\n  allow_implicit_invocation: false\n",
    "contracts/input.yaml": "schema_version: '2.0'\nfields: []\n",
    "contracts/output.yaml": "schema_version: '2.0'\nartifacts: []\n",
    "evals/cases.json": "{\"schema_version\":\"2.0\",\"cases\":[]}\n"
  };
  const updatedFiles = {...preservedFiles, "SKILL.md": baseSkill.replace("Existing body.", "Updated body-only correction.")};
  const preservedPaths = Object.keys(preservedFiles).sort((a, b) => a.localeCompare(b));
  const updateEvents = [
    {sequence: 1, action: "target_file_written", status: "succeeded", path: "SKILL.md", sha256: sha(Buffer.from(updatedFiles["SKILL.md"]))},
    ...preservedPaths.map((name, index) => ({sequence: index + 2, action: "target_file_preserved", status: "succeeded", path: name, sha256: sha(Buffer.from(preservedFiles[name]))}))
  ];
  const updateRun = (skillBytes, sourceSkill = baseSkill, eventTransform = events => events) => {
    const outputFiles = {...preservedFiles, "SKILL.md": skillBytes};
    const events = eventTransform(updateEvents.map(event => event.action === "target_file_written"
      ? {...event, sha256: sha(Buffer.from(skillBytes))} : event));
    return makeRun(updateId, {sourceFiles: {"SKILL.md": sourceSkill, ...preservedFiles}, outputFiles, events, manifestPaths: ["SKILL.md"], preservedPaths});
  };
  const update = updateRun(updatedFiles["SKILL.md"]);
  check("narrow update writes SKILL.md and byte-binds four preserved files", update);
  const validStartedUpdate = updateRun(updatedFiles["SKILL.md"], baseSkill, events =>
    fileEventsWithStarted(fileEventsWithStarted(events, "target_file_written", "SKILL.md"),
      "target_file_preserved", "agents/openai.yaml"));
  findingPositiveControl("UPDATE accepts a started write and preservation before their matching successes", () =>
    check("UPDATE started-before-success controls", validStartedUpdate));
  findingControl("UPDATE rejects a started-only write after its earlier success", updateRun(updatedFiles["SKILL.md"], baseSkill,
    events => fileEventsWithStarted(events, "target_file_written", "SKILL.md", 1, "after")));
  findingControl("UPDATE rejects a started-only preservation after its earlier success", updateRun(updatedFiles["SKILL.md"], baseSkill,
    events => fileEventsWithStarted(events, "target_file_preserved", "agents/openai.yaml", 1, "after")));
  const dateTimeSkill = baseSkill.replace("  reviewed: true\n", "  reviewed: true\n  created: 2026-10-14\n  updated_at: 2026-10-14T11:25:00Z\n");
  const dateTimeUpdate = updateRun(dateTimeSkill.replace("Existing body.", "Updated body-only correction."), dateTimeSkill);
  const sharedDateTime = sharedMetadataProbe(path.join(dateTimeUpdate.sourceRoot, "SKILL.md"), "assistant-note-scope");
  findingPositiveControl("shared safe frontmatter parser accepts nested Date and Time metadata", () => {
    assert.equal(sharedDateTime.status, 0, sharedDateTime.stderr);
    assert.equal(sharedDateTime.stdout, "");
  });
  findingPositiveControl("narrow UPDATE preserves unquoted nested Date and Time metadata", () =>
    check("Date and Time metadata remain compatible", dateTimeUpdate));
  const unsafeMetadataSkill = dateTimeSkill.replace("created: 2026-10-14", "created: !ruby/object:UnexpectedMetadata {}");
  const unsafeMetadataUpdate = updateRun(unsafeMetadataSkill.replace("Existing body.", "Updated body-only correction."), unsafeMetadataSkill);
  findingPositiveControl("shared safe frontmatter parser rejects unsupported Ruby object tags", () => {
    const unsafeProbe = sharedMetadataProbe(path.join(unsafeMetadataUpdate.sourceRoot, "SKILL.md"), "assistant-note-scope");
    assert.equal(unsafeProbe.status, 0, unsafeProbe.stderr);
    assert.match(unsafeProbe.stdout, /PARSE_ERROR/);
  });
  findingControl("creator metadata parser continues to reject unsupported Ruby object tags", unsafeMetadataUpdate);
  for (const action of ["design_presented", "approval_received"]) {
    const unexpectedGateUpdate = makeRun(updateId, {
      sourceFiles: {"SKILL.md": baseSkill, ...preservedFiles},
      outputFiles: updatedFiles,
      events: [...updateEvents, {sequence: updateEvents.length + 1, action, status: "succeeded", sha256: shaJson({unexpected: action})}],
      manifestPaths: ["SKILL.md"],
      preservedPaths
    });
    findingControl("design-free narrow update rejects unexpected successful " + action, unexpectedGateUpdate);
  }
  const missingUpdateSafety = updateRun(updatedFiles["SKILL.md"]);
  const missingUpdateSafetyResponse = JSON.parse(fileBytes(missingUpdateSafety.responsePath).toString("utf8"));
  delete missingUpdateSafetyResponse.policy_safety_summary;
  put(missingUpdateSafety.responsePath, JSON.stringify(missingUpdateSafetyResponse) + "\n");
  findingControl("update retains its applicable canonical policy summary", missingUpdateSafety);
  check("no-op narrow update is rejected", updateRun(baseSkill), true);
  check("unrelated body addition is rejected", updateRun(updatedFiles["SKILL.md"] + "\nUnrequested paragraph.\n"), true);
  assert.deepEqual(byId(updateId).semantic_context.creator_evidence.requested_body_change,
    {before_text: "Existing body.", after_text: "Updated body-only correction."},
    "fixed narrow-update case must freeze its exact body correction");
  const creatorInstructions = fs.readFileSync(path.join(repo, "skills/assistant-skill-creator/SKILL.md"), "utf8");
  assert.match(creatorInstructions, /v3 contract migration/i);
  assert.match(creatorInstructions, /operation_summary/);
  assert.match(creatorInstructions, /evidence_assessment/);
  assert.match(creatorInstructions, /refresh or adapt.*v2.*packet/i);
  const alteredPreservation = makeRun(updateId, {sourceFiles: {"SKILL.md": baseSkill, ...preservedFiles}, outputFiles: {...updatedFiles, "agents/openai.yaml": "policy:\n  allow_implicit_invocation: true\n"}, events: updateEvents, manifestPaths: ["SKILL.md"], preservedPaths});
  check("changed agent policy is rejected", alteredPreservation, true);
  const staleUpdate = makeRun(updateId, {sourceFiles: {"SKILL.md": baseSkill, ...preservedFiles}, outputFiles: updatedFiles, events: updateEvents, manifestPaths: ["SKILL.md"], preservedPaths});
  staleUpdate.trace.run_id = "different-run";
  put(staleUpdate.evidencePath, JSON.stringify(staleUpdate.trace));
  staleUpdate.envelope.evidence_sha256 = sha(Buffer.from(JSON.stringify(staleUpdate.trace)));
  staleUpdate.writeResponse();
  check("stale companion run identity is rejected", staleUpdate, true);

  const assessId = "assess-existing-skill-without-authoring";
  const assessCase = byId(assessId);
  const assessTarget = assessCase.semantic_context.creator_evidence.skill_name;
  assert(assessCase.prompt.includes(assessTarget), "assessment prompt must name its bound target");
  const inspectBytes = Buffer.from(baseSkill.replace("assistant-note-scope", assessTarget));
  const inspectSourceFiles = assessmentSourceFiles(assessTarget);
  const buildInspectionEvents = (sourceRoot, sourceFiles, extras = []) => [
    ...Object.entries(sourceFiles).map(([relative, bytes], index) => ({sequence: index + 1, action: "target_inspected", status: "succeeded",
      path: path.join(sourceRoot, relative), sha256: sha(Buffer.from(bytes))})),
    ...extras.map((extra, index) => {
      const bytes = sourceFiles[extra.path];
      return {sequence: Object.keys(sourceFiles).length + index + 1, action: "target_inspected", status: extra.status,
        path: path.join(sourceRoot, extra.path), sha256: sha(Buffer.from(bytes))};
    })
  ];
  const buildAssessment = sourceRoot => {
    const skillPath = path.join(sourceRoot, "SKILL.md");
    const contractPath = path.join(sourceRoot, "contracts/output.yaml");
    const fixturePath = path.join(sourceRoot, "evals/cases.json");
    const paths = Object.keys(inspectSourceFiles).map(relative => path.join(sourceRoot, relative));
    return {summary: "The inspected target meets the frozen structural and fixture checks.", inspected_paths: paths, criteria_results: [
      {criterion: "contract structure is supported", result: "met", evidence_path: contractPath},
      {criterion: "activation evidence is present", result: "met", evidence_path: fixturePath}
    ], findings: [], gaps: []};
  };
  const makeAssessmentRun = (sourceFiles = inspectSourceFiles, extras = [], useSupportedAssessment = sourceFiles === inspectSourceFiles) => makeRun(assessId, {
    sourceFiles,
    events: (sourceRoot, values) => buildInspectionEvents(sourceRoot, values, extras),
    assessment: sourceRoot => useSupportedAssessment ? buildAssessment(sourceRoot) : {
      summary: "The target was inspected, but required evidence is missing.", inspected_paths: [path.join(sourceRoot, "SKILL.md")], criteria_results: [
        {criterion: "contract structure is supported", result: "not_met", evidence_path: path.join(sourceRoot, "SKILL.md")},
        {criterion: "activation evidence is present", result: "not_assessed", evidence_path: path.join(sourceRoot, "SKILL.md")}
      ], findings: [{criterion: "contract structure is supported", evidence_path: path.join(sourceRoot, "SKILL.md"), summary: "No valid contract set was available."}],
      gaps: ["The registered activation fixture was not available to inspect."]
    }
  });
  const inspect = makeAssessmentRun();
  check("read-only assessment validates inspected contracts and activation fixture", inspect);
  const schema1WithActivationCases = schema1AssessmentSourceFiles(inspectSourceFiles, true);
  check("schema1 activation cases support a met assessment", makeAssessmentRun(schema1WithActivationCases, [], true));
  check("schema1 activation cases allow honest not_assessed results", makeRun(assessId, {
    sourceFiles: schema1WithActivationCases,
    events: (sourceRoot, sourceFiles) => buildInspectionEvents(sourceRoot, {"SKILL.md": sourceFiles["SKILL.md"]}),
    assessment: sourceRoot => {
      const skillPath = path.join(sourceRoot, "SKILL.md");
      return {summary: "The target was inspected, but activation evidence was not assessed.", inspected_paths: [skillPath], criteria_results: [
        {criterion: "contract structure is supported", result: "not_met", evidence_path: skillPath},
        {criterion: "activation evidence is present", result: "not_assessed", evidence_path: skillPath}
      ], findings: [{criterion: "contract structure is supported", evidence_path: skillPath, summary: "The inspected path set did not include the required contract files."}],
      gaps: ["The schema 1 activation cases were not evaluated for this assessment."]};
    }
  }));
  check("schema1 all-met assessment without activation cases is rejected", makeAssessmentRun(schema1AssessmentSourceFiles(inspectSourceFiles, false), [], true), true);
  const unsupportedAllMet = makeRun(assessId, {
    sourceFiles: {"SKILL.md": inspectBytes},
    events: (sourceRoot, sourceFiles) => buildInspectionEvents(sourceRoot, sourceFiles),
    assessment: sourceRoot => ({summary: "The inspected target meets the frozen checks.", inspected_paths: [path.join(sourceRoot, "SKILL.md")], criteria_results: [
      {criterion: "contract structure is supported", result: "met", evidence_path: path.join(sourceRoot, "SKILL.md")},
      {criterion: "activation evidence is present", result: "met", evidence_path: path.join(sourceRoot, "SKILL.md")}
    ], findings: [], gaps: []})
  });
  check("all-met assessment without contracts or activation fixture is rejected", unsupportedAllMet, true);
  check("honest not_met and not_assessed assessment remains legal", makeAssessmentRun({"SKILL.md": inspectBytes}));
  for (const [status, label] of [["failed", "failed"], ["started", "late started"], ["succeeded", "duplicate success"]]) {
    const contradictory = makeAssessmentRun(inspectSourceFiles, [{path: "contracts/output.yaml", status}]);
    check("inspection " + label + " for the same path and digest is rejected", contradictory, true);
  }
  const unrelatedSourceFiles = {...inspectSourceFiles, "references/unrelated.md": Buffer.from("unreferenced source note\n")};
  const unrelatedInspection = makeAssessmentRun(unrelatedSourceFiles, [], true);
  check("unreferenced inspection identity remains legal", unrelatedInspection);
  const assessmentWithCitation = (evidencePath, extraSourceFiles = {}) => {
    const sourceFiles = {"SKILL.md": inspectBytes, ...extraSourceFiles};
    const assessment = {summary: "The inspected target meets the frozen checks.", inspected_paths: [], criteria_results: [
      {criterion: "contract structure is supported", result: "met", evidence_path: ""},
      {criterion: "activation evidence is present", result: "met", evidence_path: ""}
    ], findings: [], gaps: []};
    const run = makeRun(assessId, {sourceFiles, events: [
      {sequence: 1, action: "target_inspected", status: "succeeded", path: path.join(root, "PLACEHOLDER"), sha256: sha(inspectBytes)}
    ], assessment});
    run.trace.events[0].path = path.join(run.sourceRoot, "SKILL.md");
    const citedPath = path.join(run.sourceRoot, evidencePath);
    run.envelope.assessment.inspected_paths = [run.trace.source_snapshot.path, citedPath];
    run.envelope.assessment.criteria_results.forEach(item => { item.evidence_path = citedPath; });
    put(run.evidencePath, JSON.stringify(run.trace));
    run.envelope.evidence_sha256 = sha(Buffer.from(JSON.stringify(run.trace)));
    run.writeResponse();
    return run;
  };
  const wrongSourceName = Buffer.from(inspectBytes.toString("utf8").replace(`name: ${assessTarget}`, "name: assistant-unrelated"));
  assert(wrongSourceName.includes(Buffer.from("name: assistant-unrelated")));
  const wrongSourceAssessment = makeRun(assessId, {sourceFiles: {"SKILL.md": wrongSourceName}, events: [
    {sequence: 1, action: "target_inspected", status: "succeeded", path: path.join(root, "PLACEHOLDER"), sha256: sha(wrongSourceName)}
  ], assessment: JSON.parse(JSON.stringify(inspect.envelope.assessment))});
  wrongSourceAssessment.trace.events[0].path = path.join(wrongSourceAssessment.sourceRoot, "SKILL.md");
  wrongSourceAssessment.envelope.assessment.inspected_paths = [wrongSourceAssessment.trace.events[0].path];
  wrongSourceAssessment.envelope.assessment.criteria_results.forEach(item => { item.evidence_path = wrongSourceAssessment.trace.events[0].path; });
  put(wrongSourceAssessment.evidencePath, JSON.stringify(wrongSourceAssessment.trace));
  wrongSourceAssessment.envelope.evidence_sha256 = sha(Buffer.from(JSON.stringify(wrongSourceAssessment.trace)));
  wrongSourceAssessment.writeResponse();
  check("inspected source metadata must match the frozen skill name", wrongSourceAssessment, true);
  const nonexistentEvidence = assessmentWithCitation("contracts/never-created.yaml");
  assert.equal(fs.existsSync(path.join(nonexistentEvidence.sourceRoot, "contracts/never-created.yaml")), false);
  check("assessment cannot cite a nonexistent unobserved path", nonexistentEvidence, true);
  const existingUnobservedEvidence = assessmentWithCitation("contracts/input.yaml", {
    "contracts/input.yaml": "fields:\n  - name: ignored\n"
  });
  assert.equal(fs.existsSync(path.join(existingUnobservedEvidence.sourceRoot, "contracts/input.yaml")), true);
  check("assessment cannot cite an existing but unobserved path", existingUnobservedEvidence, true);
  const positiveCaseFixturePath = path.join(inspect.skillDir, "evals/cases.json");
  const positiveCaseFixtureBytes = fileBytes(positiveCaseFixturePath);
  const mismatchedTargetSkillDir = mkdir(path.join(inspect.work, "negative-target-control", "assistant-skill-creator"));
  fs.copyFileSync(path.join(inspect.skillDir, "SKILL.md"), path.join(mismatchedTargetSkillDir, "SKILL.md"));
  const mismatchedTargetFixturePath = path.join(mismatchedTargetSkillDir, "evals/cases.json");
  put(mismatchedTargetFixturePath, positiveCaseFixtureBytes);
  const mismatchedTargetFixture = JSON.parse(fileBytes(mismatchedTargetFixturePath).toString("utf8"));
  mismatchedTargetFixture.cases.find(item => item.id === assessId).semantic_context.creator_evidence.skill_name = "assistant-changelog";
  put(mismatchedTargetFixturePath, JSON.stringify(mismatchedTargetFixture));
  const mismatchedTargetValidation = spawnSync("bash", [path.join(repo, "tools/evals/run-skill-evals.sh"), "--validate-fixture", "--skill", mismatchedTargetSkillDir], {encoding: "utf8"});
  assert.notEqual(mismatchedTargetValidation.status, 0, "registered fixture validator must reject a target absent from the prompt");
  assert.match(mismatchedTargetValidation.stdout + mismatchedTargetValidation.stderr, /target skill name must appear in the prompt/);
  assert.deepEqual(fileBytes(positiveCaseFixturePath), positiveCaseFixtureBytes,
    "mismatched-target negative control must preserve the positive assessment fixture bytes");
  process.stdout.write("ok - creator fixture rejects a target that differs from the prompt\n");
  const uninspected = makeRun(assessId, {sourceFiles: {"SKILL.md": inspectBytes}, events: [], assessment: inspect.envelope.assessment});
  check("assessment without inspection is rejected", uninspected, true);
  const writeFromAssessment = makeRun(assessId, {sourceFiles: {"SKILL.md": inspectBytes}, outputFiles: {"SKILL.md": "new target bytes\n"},
    events: [{sequence: 1, action: "target_inspected", status: "succeeded", path: path.join(root, "assessment-placeholder"), sha256: sha(inspectBytes)},
      {sequence: 2, action: "target_file_written", status: "succeeded", path: "SKILL.md", sha256: sha(Buffer.from("new target bytes\n"))}],
    assessment: inspect.envelope.assessment});
  writeFromAssessment.trace.events[0].path = path.join(writeFromAssessment.sourceRoot, "SKILL.md");
  writeFromAssessment.envelope.assessment.inspected_paths = [writeFromAssessment.trace.events[0].path];
  writeFromAssessment.envelope.assessment.criteria_results.forEach(item => { item.evidence_path = writeFromAssessment.trace.events[0].path; });
  put(writeFromAssessment.evidencePath, JSON.stringify(writeFromAssessment.trace));
  writeFromAssessment.envelope.evidence_sha256 = sha(Buffer.from(JSON.stringify(writeFromAssessment.trace)));
  writeFromAssessment.writeResponse();
  check("read-only assessment write is rejected", writeFromAssessment, true);

  const refreshId = "refresh-guidance-is-read-only-and-provenance-bound";
  const refreshForCapture = captured => {
    const result = captured.result;
    const disposition = result.status === "current" ? "already_current"
      : result.status === "unavailable" ? "not_adopted" : "requires_review";
    return {summary: "The captured checker report records " + result.status + " without implying adoption.",
      source_identity: captured.sourceIdentity, checked_at: captured.checkedAt, revision_or_digest: captured.digest,
      relevance: "Contract guidance", disposition, affected_consumers: ["assistant-skill-creator"],
      access_limits: result.retrieval_state === "complete" ? [] : [result.reason], adopted: false};
  };
  const refreshEventFor = (captured, includeCheckerReport = true) => {
    const event = {sequence: 1, action: "guidance_source_checked", status: "succeeded",
      source_identity: captured.sourceIdentity, sha256: captured.digest, checked_at: captured.checkedAt};
    if (includeCheckerReport) event.checker_report = captured.report;
    return event;
  };
  const makeRefreshRun = (captured, includeCheckerReport = true, refreshOverrides = {}) => makeRun(refreshId, {
    events: [refreshEventFor(captured, includeCheckerReport)],
    refresh: {...refreshForCapture(captured), ...refreshOverrides},
    refreshReport: captured.report
  });
  const rewriteTrace = run => {
    const bytes = Buffer.from(JSON.stringify(run.trace), "utf8");
    put(run.evidencePath, bytes);
    run.envelope.evidence_sha256 = sha(bytes);
    run.writeResponse();
  };
  const mutateRefreshResponse = (run, mutation) => {
    const response = JSON.parse(fileBytes(run.responsePath).toString("utf8"));
    mutation(response);
    put(run.responsePath, JSON.stringify(response) + "\n");
  };
  const capturedRefresh = refreshCapture("review_required");
  const refresh = refreshForCapture(capturedRefresh);
  const refreshEvent = refreshEventFor(capturedRefresh);
  const refreshRun = makeRefreshRun(capturedRefresh);
  assert.equal(capturedRefresh.fetchHadEtag, true, "complete helper capture includes the controlled upstream ETag");
  check("refresh binds provenance without adoption", refreshRun);
  const standaloneCliRun = makeRefreshRun(capturedRefresh.cliCapture);
  check("standalone checker CLI report validates without field projection", standaloneCliRun);
  for (const [scenario, expectedStatus, expectedRetrieval] of [
    ["current", "current", "complete"], ["stale", "stale", "complete"],
    ["complete_no_etag", "review_required", "complete"],
    ["unavailable", "unavailable", "unavailable"], ["partial", "unavailable", "partial"],
    ["not_configured", "unavailable", "not_configured"]
  ]) {
    const capture = refreshCapture(scenario);
    assert.equal(capture.result.status, expectedStatus, scenario + ": fixture must retain the actual helper status");
    assert.equal(capture.result.retrieval_state, expectedRetrieval, scenario + ": fixture must retain the actual helper retrieval state");
    if (scenario === "complete_no_etag") assert.equal(capture.fetchHadEtag, false, "complete capture omits upstream ETag");
    if (expectedRetrieval !== "complete") assert.equal(capture.digest, null, scenario + ": incomplete retrieval must not invent a digest");
    check("captured helper report preserves " + scenario + " without changing adoption", makeRefreshRun(capture));
  }
  const missingRefreshReport = makeRefreshRun(capturedRefresh, false);
  mutateRefreshResponse(missingRefreshReport, response => { delete response.upstream_guidance_assessment; });
  findingControl("refresh requires the actual canonical helper report", missingRefreshReport);
  const inventedRefreshDigest = makeRefreshRun(capturedRefresh, false, {revision_or_digest: "sha256:" + "0".repeat(64)});
  findingControl("refresh rejects a digest that differs from captured and reported bytes", inventedRefreshDigest);
  const contradictedRefreshStatus = makeRefreshRun(capturedRefresh, false);
  mutateRefreshResponse(contradictedRefreshStatus, response => { response.upstream_guidance_assessment.results[0].status = "current"; });
  findingControl("refresh status remains bound to captured bytes and prior identity", contradictedRefreshStatus);
  const rewrittenPriorIdentity = makeRefreshRun(capturedRefresh, false);
  mutateRefreshResponse(rewrittenPriorIdentity, response => {
    response.upstream_guidance_assessment.results[0].last_assessed.last_assessed_revision = "unobserved-revision";
  });
  findingControl("refresh report preserves the registered prior source identity", rewrittenPriorIdentity);
  const capturedReportTamperCases = [
    ["limits", report => { report.limits.maximum_total_bytes += 1; }],
    ["status", report => { report.results[0].status = "current"; }],
    ["digest", report => { report.results[0].candidate_sha256 = "0".repeat(64); }],
    ["unknown candidate_etag field", report => { report.results[0].candidate_etag = "undeclared"; }]
  ];
  for (const [field, mutation] of capturedReportTamperCases) {
    const tampered = makeRefreshRun(capturedRefresh);
    mutateRefreshResponse(tampered, response => mutation(response.upstream_guidance_assessment));
    findingControl("ordinary refresh report cannot override the captured checker " + field, tampered);
    const uncaptured = makeRefreshRun(capturedRefresh, false);
    rewriteTrace(uncaptured);
    mutateRefreshResponse(uncaptured, response => mutation(response.upstream_guidance_assessment));
    findingControl("uncaptured legacy event cannot authorize a tampered checker " + field, uncaptured);
  }
  const capturedOrdinaryDigest = makeRefreshRun(capturedRefresh);
  mutateRefreshResponse(capturedOrdinaryDigest, response => {
    response.upstream_guidance_assessment.results[0].candidate_sha256 = "0".repeat(64);
  });
  findingControl("ordinary report digest must match the captured helper report", capturedOrdinaryDigest);
  const adoptedRefresh = makeRun(refreshId, {events: [refreshEvent], refresh: {...refresh, adopted: true}});
  check("retrieval is not accepted as adoption", adoptedRefresh, true);
  for (const [status, label] of [["failed", "failed"], ["started", "late started"], ["succeeded", "duplicate success"]]) {
    const repeated = makeRun(refreshId, {events: [refreshEvent, {...refreshEvent, sequence: 2, status}], refresh});
    check("guidance " + label + " for the same source identity is rejected", repeated, true);
  }
  const unrelatedGuidance = makeRun(refreshId, {events: [refreshEvent, {...refreshEvent, sequence: 2, source_identity: "https://example.invalid/unrelated"}], refresh});
  check("unrelated guidance identity remains legal", unrelatedGuidance);

  const comparisonId = "assess-skill-contracts-under-frozen-comparison";
  const compareSource = Buffer.from(baseSkill.replace("name: assistant-note-scope", "name: assistant-skill-creator"));
  const baselineSource = path.join(root, "baseline-source.md");
  const candidateSource = path.join(root, "candidate-source.md");
  put(baselineSource, Buffer.from("baseline source revision\n"));
  put(candidateSource, Buffer.from("candidate source revision\n"));
  const baselineOut = mkdir(path.join(root, "baseline-output"));
  const candidateOut = mkdir(path.join(root, "candidate-output"));
  put(path.join(baselineOut, "SKILL.md"), "baseline output\n");
  put(path.join(candidateOut, "SKILL.md"), "candidate output\n");
  const conditions = {host: "Codex", model: "test-model", runtime: "fixture", settings_digest: sha(Buffer.from("settings")), tools_digest: sha(Buffer.from("tools")), permissions_digest: sha(Buffer.from("permissions")), inputs_digest: sha(Buffer.from("inputs"))};
  const baseline = {run_id: "baseline-run", source_snapshot: {path: baselineSource, sha256: sha(fileBytes(baselineSource))}, output_root: baselineOut, artifact_manifest: [{path: "SKILL.md", sha256: sha(fileBytes(path.join(baselineOut, "SKILL.md")))}]};
  const candidate = {run_id: "candidate-run", source_snapshot: {path: candidateSource, sha256: sha(fileBytes(candidateSource))}, output_root: candidateOut, artifact_manifest: [{path: "SKILL.md", sha256: sha(fileBytes(path.join(candidateOut, "SKILL.md")))}]};
  const pairBase = {schema_version: "1.0", prompt_set_digest: sha(Buffer.from("prompts")), rubric_digest: sha(Buffer.from("rubric")), conditions, baseline, candidate,
    partitions: {training_ids: ["train"], validation_ids: ["valid"], final_acceptance_ids: ["holdout"]}, candidate_selection_ids: ["valid"],
    blind_labels: {blind: true, labels: {A: "Quartz", B: "Cedar"}},
    observations: ["train", "valid", "holdout"].map((prompt_id, index) => ({prompt_id, partition: ["training", "validation", "final_acceptance"][index], expected_activate: true, candidate_selected: true})),
    metrics: {positive_recall: {numerator: 3, denominator: 3, value: 1, availability: "available"}, negative_false_positive_rate: {numerator: 0, denominator: 0, value: null, availability: "unavailable"}, precision: {numerator: 3, denominator: 3, value: 1, availability: "available"}}};
  const pairEvents = [
    {sequence: 1, action: "target_inspected", status: "succeeded", path: path.join(root, "comparison-target", "SKILL.md"), sha256: sha(compareSource)},
    {sequence: 2, action: "baseline_run_completed", status: "succeeded", run_id: baseline.run_id, source_snapshot_sha256: baseline.source_snapshot.sha256, output_root: baselineOut, conditions_sha256: shaJson(conditions), prompt_set_digest: pairBase.prompt_set_digest, rubric_digest: pairBase.rubric_digest},
    {sequence: 3, action: "candidate_run_completed", status: "succeeded", run_id: candidate.run_id, source_snapshot_sha256: candidate.source_snapshot.sha256, output_root: candidateOut, conditions_sha256: shaJson(conditions), prompt_set_digest: pairBase.prompt_set_digest, rubric_digest: pairBase.rubric_digest}
  ];
  const pairAssessment = {summary: "The current target was inspected and the matched comparison is complete.", inspected_paths: [], criteria_results: [
    {criterion: "baseline and candidate are bound to matched conditions", result: "met", evidence_path: ""},
    {criterion: "final acceptance is held out from selection", result: "met", evidence_path: ""}
  ], findings: [], gaps: []};
  const makeComparisonRun = (comparison, events) => {
    const run = makeRun(comparisonId, {sourceFiles: {"SKILL.md": compareSource}, events, assessment: pairAssessment, comparison, comparisonPair: comparison});
    run.trace.events[0].path = path.join(run.sourceRoot, "SKILL.md");
    run.envelope.assessment.inspected_paths = [run.trace.events[0].path];
    run.envelope.assessment.criteria_results.forEach(item => { item.evidence_path = run.trace.events[0].path; });
    put(run.evidencePath, JSON.stringify(run.trace));
    run.envelope.evidence_sha256 = sha(Buffer.from(JSON.stringify(run.trace)));
    run.writeResponse();
    return run;
  };
  const pairRun = makeComparisonRun(pairBase, pairEvents);
  check("matched comparison accepts zero-denominator class as unavailable", pairRun);
  const candidateCompletion = pairEvents.find(event => event.action === "candidate_run_completed");
  for (const [status, label] of [["failed", "failed"], ["started", "late started"], ["succeeded", "duplicate success"]]) {
    const contradictory = makeComparisonRun(pairBase, [...pairEvents, {...candidateCompletion, sequence: 4, status}]);
    check("comparison " + label + " for the bound candidate run is rejected", contradictory, true);
  }
  const unrelatedCompletion = makeComparisonRun(pairBase, [...pairEvents, {...candidateCompletion, sequence: 4, run_id: "unrelated-run"}]);
  check("unrelated comparison run identity remains legal", unrelatedCompletion);
  const repeatedOutcomes = JSON.parse(JSON.stringify(pairBase));
  repeatedOutcomes.observations.push(
    JSON.parse(JSON.stringify(repeatedOutcomes.observations.find(row => row.prompt_id === "valid"))),
    JSON.parse(JSON.stringify(repeatedOutcomes.observations.find(row => row.prompt_id === "holdout")))
  );
  const repeatedPositiveOutcomes = repeatedOutcomes.observations.filter(row => row.expected_activate && row.candidate_selected).length;
  repeatedOutcomes.metrics = {
    positive_recall: {numerator: repeatedPositiveOutcomes, denominator: repeatedPositiveOutcomes, value: 1, availability: "available"},
    negative_false_positive_rate: {numerator: 0, denominator: 0, value: null, availability: "unavailable"},
    precision: {numerator: repeatedPositiveOutcomes, denominator: repeatedPositiveOutcomes, value: 1, availability: "available"}
  };
  check("matched comparison preserves repeated validation and final-acceptance outcomes", makeComparisonRun(repeatedOutcomes, pairEvents));
  const comparisonWithObservations = omittedId => {
    const report = JSON.parse(JSON.stringify(pairBase));
    report.observations = report.observations.filter(row => row.prompt_id !== omittedId);
    const positives = report.observations.filter(row => row.expected_activate && row.candidate_selected).length;
    report.metrics = {
      positive_recall: {numerator: positives, denominator: positives, value: 1, availability: "available"},
      negative_false_positive_rate: {numerator: 0, denominator: 0, value: null, availability: "unavailable"},
      precision: {numerator: positives, denominator: positives, value: 1, availability: "available"}
    };
    return report;
  };
  check("comparison requires every declared final acceptance outcome", makeComparisonRun(
    comparisonWithObservations("holdout"), pairEvents), true);
  check("comparison requires every declared candidate-selection outcome", makeComparisonRun(
    comparisonWithObservations("valid"), pairEvents), true);
  const leakedPair = JSON.parse(JSON.stringify(pairBase));
  leakedPair.candidate_selection_ids = ["holdout"];
  const leaked = makeComparisonRun(leakedPair, pairEvents);
  check("candidate selection from final holdout is rejected", leaked, true);
  const badDenominator = JSON.parse(JSON.stringify(pairBase));
  badDenominator.metrics.negative_false_positive_rate = {numerator: 0, denominator: 1, value: 0, availability: "available"};
  const denominatorRun = makeComparisonRun(badDenominator, pairEvents);
  check("incorrect raw metric denominator is rejected", denominatorRun, true);
  const mismatchedConditions = JSON.parse(JSON.stringify(pairBase));
  mismatchedConditions.conditions.model = "different-model";
  const mismatched = makeComparisonRun(mismatchedConditions, pairEvents);
  check("comparison model identity must match captured run conditions", mismatched, true);
  for (const [identity, value] of [["prompt_set_digest", "changed prompts"], ["rubric_digest", "changed rubric"]]) {
    const changedScoringIdentity = JSON.parse(JSON.stringify(pairBase));
    changedScoringIdentity[identity] = sha(Buffer.from(value));
    check(`stale completion trace is rejected after ${identity} changes`, makeComparisonRun(changedScoringIdentity, pairEvents), true);
  }
  const emptyBaselineOut = mkdir(path.join(root, "empty-baseline-output"));
  const emptyCandidateOut = mkdir(path.join(root, "empty-candidate-output"));
  const emptyPair = JSON.parse(JSON.stringify(pairBase));
  emptyPair.baseline.output_root = emptyBaselineOut;
  emptyPair.baseline.artifact_manifest = [];
  emptyPair.candidate.output_root = emptyCandidateOut;
  emptyPair.candidate.artifact_manifest = [];
  const emptyPairEvents = pairEvents.map(event => event.action === "baseline_run_completed" ? {...event, output_root: emptyBaselineOut}
    : event.action === "candidate_run_completed" ? {...event, output_root: emptyCandidateOut} : event);
  check("comparison with empty raw outputs is rejected", makeComparisonRun(emptyPair, emptyPairEvents), true);
  assert.deepEqual(findingControlFailures, [], "finding-specific counterexamples must be rejected by both semantic validation and registered grading");
  if (exportTarget) {
    exportBoundFixtureProjection(exportTarget, [pending, utility, update, inspect, refreshRun, pairRun]);
  }
} finally {
  if (!exportSucceeded) fs.rmSync(root, {recursive: true, force: true});
}
NODE
then
    pass
else
    fail "creator semantic validator did not bind outcomes to captured artifacts and traces"
fi

test_start "creator fixture reader treats contract YAML aliases and Ruby object tags as invalid passive data"
creator_contract_reader_root="$(mktemp -d "${TMPDIR:-/tmp}/creator-contract-yaml-reader.XXXXXX")"
p0p4_register_cleanup "$creator_contract_reader_root"
creator_contract_reader_skill="$creator_contract_reader_root/creator-contract-reader-skill"
mkdir -p "$creator_contract_reader_skill/evals" "$creator_contract_reader_skill/contracts"
cat >"$creator_contract_reader_skill/SKILL.md" <<'EOF'
# Local contract-reader fixture
EOF
node - "$FRAMEWORK_DIR/skills/assistant-skill-creator/evals/cases.json" "$creator_contract_reader_skill/evals/cases.json" <<'NODE'
const fs = require("node:fs");
const fixture = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
fixture.skill = "creator-contract-reader-skill";
fixture.suite_id = "creator-contract-reader-skill-behavior";
fixture.cases = [fixture.cases[0]];
const testCase = fixture.cases[0];
delete testCase.semantic_validator;
delete testCase.semantic_context;
testCase.machine_expectations.structured_json_assertions = [
  {operator: "nonempty_string", path: ["result"]}
];
fs.writeFileSync(process.argv[3], JSON.stringify(fixture, null, 2) + "\n");
NODE
write_creator_contract_reader_output() {
    local metadata_case="$1"
    cat >"$creator_contract_reader_skill/contracts/output.yaml" <<'EOF'
schema_version: "1.0"
contract: output
skill: creator-contract-reader-skill

artifacts:
  - name: result
    type: string
    required: true
    description: "Fixture result"
    validation: "Non-empty fixture result"
    on_fail: "Provide a non-empty fixture result"
EOF
    case "$metadata_case" in
        ordinary)
            cat >>"$creator_contract_reader_skill/contracts/output.yaml" <<'EOF'
metadata:
  note: ordinary passive contract metadata
EOF
            ;;
        alias)
            cat >>"$creator_contract_reader_skill/contracts/output.yaml" <<'EOF'
metadata:
  note: &ordinary_note ordinary
  copied_note: *ordinary_note
EOF
            ;;
        object_tag)
            cat >>"$creator_contract_reader_skill/contracts/output.yaml" <<'EOF'
metadata:
  note: !ruby/object:Object {}
EOF
            ;;
    esac
}
creator_contract_reader_failures=()
for creator_contract_reader_case in ordinary alias object_tag; do
    write_creator_contract_reader_output "$creator_contract_reader_case"
    if "$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --validate-fixture --skill "$creator_contract_reader_skill" >/dev/null 2>&1; then
        if [[ "$creator_contract_reader_case" != ordinary ]]; then
            creator_contract_reader_failures+=("$creator_contract_reader_case accepted")
        fi
    elif [[ "$creator_contract_reader_case" == ordinary ]]; then
        creator_contract_reader_failures+=("ordinary_contract_rejected")
    fi
done
if [[ ${#creator_contract_reader_failures[@]} -eq 0 ]]; then
    pass
else
    fail "creator contract reader trust controls failed: ${creator_contract_reader_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
