"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { test } = require("node:test");
const { validate, readDocument, MAX_BYTES } = require("../../tools/change-impact/validate-change-impact.cjs");

const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", "multidomain.v1.json"), "utf8"));
const commonExample = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "..", "tools", "change-impact", "example.completion.v1.json"), "utf8"));

function clone(value) { return JSON.parse(JSON.stringify(value)); }

function validDocuments() {
  const documents = clone(fixture);
  documents.expected.required_edges = clone(documents.capture.edges);
  documents.expected.required_requirements = documents.capture.requirements.map((requirement) => ({
    ...requirement,
    verification_source_id: requirement.id === "req-nav-success" || requirement.id === "req-nav-modal" ? "test-navigation-current" :
      requirement.id === "req-nav-dirty" ? "test-dirty-current" : requirement.id === "req-config" ? "test-config-current" :
      requirement.id === "req-event" ? "test-event-current" : requirement.id === "req-state" ? "test-state-current" :
      requirement.id === "req-cache" ? "test-cache-current" : "public-compatibility-evidence-current",
  }));
  const sources = new Map(documents.expected.required_requirements.map((requirement) => [requirement.id, requirement.verification_source_id]));
  documents.assessment.verification_plans = [
    ["plan-nav", "navigation", "route-success", "test-navigation-current"], ["plan-dirty", "navigation", "dirty-cancel", "test-dirty-current"],
    ["plan-config", "configuration", "loads-default", "test-config-current"], ["plan-event", "async-work", "stale-completion", "test-event-current"],
    ["plan-state", "state", "restore-draft", "test-state-current"], ["plan-cache", "cache", "fresh-miss", "test-cache-current"],
  ].map(([id, contract_id, state_transition, source_identity]) => ({ id, contract_id, state_transition, oracle: `oracle-${id}`, steps_ref: `steps-${id}`, source_identity }));
  const planFor = { "req-nav-success": "plan-nav", "req-nav-dirty": "plan-dirty", "req-nav-modal": "plan-nav", "req-config": "plan-config", "req-event": "plan-event", "req-state": "plan-state", "req-cache": "plan-cache" };
  documents.assessment.obligations = documents.capture.requirements.map((requirement, index) => ({
    id: `obligation-${index + 1}`, requirement_id: requirement.id, disposition: requirement.id === "req-public" ? "unaffected" : "preserve",
    rationale_ref: `rationale-${requirement.id}`, authorization_ref: null, verification_id: requirement.id === "req-nav-success" || requirement.id === "req-nav-modal" || requirement.id === "req-public" ? null : planFor[requirement.id],
    equivalence_group_id: requirement.id === "req-nav-success" || requirement.id === "req-nav-modal" ? "group-navigation-success" : null,
  }));
  documents.assessment.equivalence_groups = [{ id: "group-navigation-success", member_obligation_ids: ["obligation-1", "obligation-3"], justification_ref: "same-route-contract", verification_id: "plan-nav" }];
  documents.assessment.actual_verifications = documents.assessment.verification_plans.map((plan) => ({ verification_id: plan.id, outcome: "passed", executed_source_identity: plan.source_identity, evidence_ref: `result-${plan.id}` }));
  documents.expected.review_context.required_bindings = documents.capture.requirements.map((requirement, index) => ({ requirement_id: requirement.id, scope_item_id: `scope-${index + 1}`, coverage_concern_id: `concern-${index + 1}` }));
  documents.review.bindings = documents.assessment.obligations.map((obligation, index) => ({ obligation_id: obligation.id, requirement_id: obligation.requirement_id, scope_item_id: `scope-${index + 1}`, coverage_concern_id: `concern-${index + 1}` }));
  return documents;
}

function codes(result) { return result.reasons.map((reason) => reason.code); }

function runCli(documents, phase, mutate) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "change-impact-"));
  if (mutate) mutate(documents, directory);
  for (const [name, value] of Object.entries(documents)) fs.writeFileSync(path.join(directory, `${name}.json`), JSON.stringify(value));
  const args = [path.join(process.cwd(), "tools/change-impact/validate-change-impact.cjs"), "--phase", phase, "--capture", path.join(directory, "capture.json"), "--expected", path.join(directory, "expected.json")];
  if (phase !== "discovery") args.push("--assessment", path.join(directory, "assessment.json"));
  if (phase === "completion") args.push("--review", path.join(directory, "review.json"));
  const child = spawnSync(process.execPath, args, { encoding: "utf8" });
  return { ...child, result: JSON.parse(child.stdout) };
}

test("multidomain completion closes independent consumer, transition, verification, and review authority", () => {
  const result = validate({ phase: "completion", ...validDocuments() });
  assert.equal(result.valid, true);
  assert.equal(result.complete, true);
});

test("portable completion example is an executable protocol document", () => {
  assert.equal(validate({ phase: "completion", ...commonExample }).complete, true);
});

test("document admission reads a single descriptor with a byte bound before parsing", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "change-impact-descriptor-"));
  const document = path.join(directory, "document.json");
  fs.writeFileSync(document, '{"label":"é"}');
  assert.deepEqual(readDocument(document), { label: "é" });

  let shortRead = true;
  const originalReadSync = fs.readSync;
  fs.readSync = function shortReadSync(descriptor, buffer, offset, length, position) {
    if (shortRead) {
      shortRead = false;
      return originalReadSync.call(this, descriptor, buffer, offset, 1, position);
    }
    return originalReadSync.call(this, descriptor, buffer, offset, length, position);
  };
  try {
    assert.deepEqual(readDocument(document), { label: "é" });
  } finally {
    fs.readSync = originalReadSync;
  }

  fs.writeFileSync(document, "{}");
  fs.readSync = function boundedReadSync(...args) {
    fs.writeFileSync(document, " ".repeat(MAX_BYTES + 1));
    return originalReadSync.apply(this, args);
  };
  try {
    assert.throws(() => readDocument(document), /INPUT_TOO_LARGE/);
  } finally {
    fs.readSync = originalReadSync;
  }
});

test("document admission rejects a FIFO without blocking", (context) => {
  if (process.platform === "win32") return context.skip("FIFO admission is not available on Windows");
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "change-impact-fifo-"));
  const fifo = path.join(directory, "document.fifo");
  const create = spawnSync("mkfifo", [fifo]);
  if (create.error || create.status !== 0) return context.skip("mkfifo is unavailable");
  assert.throws(() => readDocument(fifo), /INPUT_TOO_LARGE/);
});

test("shared and material captures record a discovery root, while compact cosmetic controls remain optional", () => {
  const shared = clone(commonExample);
  shared.capture.roots = [];
  assert.ok(codes(validate({ phase: "completion", ...shared })).includes("CAPTURE_DISCOVERY_ROOTS_MISSING"));

  const material = validDocuments();
  material.expected.required_impact_scope = "local";
  material.assessment.impact_scope = "local";
  material.capture.roots = [];
  material.capture.unknown_boundaries.push({ id: "unknown-material-root", material: true, source_id: "boundary-current" });
  assert.ok(codes(validate({ phase: "discovery", capture: material.capture, expected: material.expected })).includes("CAPTURE_DISCOVERY_ROOTS_MISSING"));

  const cosmetic = validDocuments();
  cosmetic.expected.required_impact_scope = "not_applicable";
  cosmetic.assessment.impact_scope = "not_applicable";
  cosmetic.assessment.assessment_kind = "cosmetic";
  cosmetic.capture.roots = [];
  assert.equal(validate({ phase: "discovery", capture: cosmetic.capture, expected: cosmetic.expected }).valid, true);
});

test("shared inventory requires captured consumers and contract/state-transition requirements", () => {
  const emptyShared = clone(commonExample);
  emptyShared.capture.edges = []; emptyShared.capture.requirements = [];
  emptyShared.expected.required_edges = []; emptyShared.expected.required_requirements = [];
  emptyShared.expected.review_context.required_bindings = [];
  emptyShared.assessment.obligations = []; emptyShared.assessment.verification_plans = [];
  emptyShared.assessment.equivalence_groups = []; emptyShared.assessment.actual_verifications = [];
  emptyShared.review.bindings = [];
  const apiResult = validate({ phase: "pre_build", ...emptyShared });
  assert.equal(apiResult.phase, "pre_build");
  assert.deepEqual(codes(apiResult), ["CAPTURE_SHARED_CONSUMERS_EMPTY", "CAPTURE_SHARED_REQUIREMENTS_EMPTY"]);

  const cliResult = runCli(emptyShared, "pre_build");
  assert.equal(cliResult.status, 1);
  assert.deepEqual(cliResult.result, apiResult);

  const completionApiResult = validate({ phase: "completion", ...emptyShared });
  const completionCliResult = runCli(emptyShared, "completion");
  assert.equal(completionApiResult.phase, "completion");
  assert.equal(completionCliResult.status, 1);
  assert.deepEqual(completionCliResult.result, completionApiResult);
});

test("discovery and pre-build permit planned work without fabricated actual execution", () => {
  const documents = validDocuments();
  assert.equal(validate({ phase: "discovery", capture: documents.capture, expected: documents.expected }).valid, true);
  documents.assessment.actual_verifications = [];
  assert.equal(validate({ phase: "pre_build", ...documents }).valid, true);
  documents.expected.review_context = null;
  assert.equal(validate({ phase: "discovery", capture: documents.capture, expected: documents.expected }).valid, true);
  assert.equal(validate({ phase: "pre_build", ...documents }).valid, true);
  assert.ok(codes(validate({ phase: "completion", ...documents })).includes("EXPECTED_REVIEW_CONTEXT_INVALID"));
});

test("invalid phase diagnostics retain PHASE_INVALID without echoing untrusted phase input", () => {
  const sentinel = "PRIVATE_PHASE_SENTINEL";
  const result = validate({ phase: sentinel, ...validDocuments() });
  assert.equal(result.phase, null);
  assert.deepEqual(codes(result), ["PHASE_INVALID"]);

  const child = runCli(validDocuments(), sentinel);
  assert.equal(child.status, 1);
  assert.equal(child.result.phase, null);
  assert.deepEqual(codes(child.result), ["PHASE_INVALID"]);
  assert.equal(child.stdout.includes(sentinel), false);
});

test("canonical pre_build passes through the API and CLI with the same result", () => {
  const documents = validDocuments();
  documents.assessment.actual_verifications = [];
  const apiResult = validate({ phase: "pre_build", ...documents });
  const cliResult = runCli(documents, "pre_build");
  assert.equal(apiResult.valid, true);
  assert.equal(cliResult.status, 0);
  assert.deepEqual(cliResult.result, apiResult);
});

test("known omitted consumer edge and omitted dirty-state transition fail against independent authority", () => {
  const documents = validDocuments();
  documents.capture.edges.pop();
  documents.capture.requirements = documents.capture.requirements.filter((requirement) => requirement.edge_id !== "edge-cache");
  assert.ok(codes(validate({ phase: "discovery", ...documents })).includes("CAPTURE_EXPECTED_EDGES_MISMATCH"));
  const transition = validDocuments();
  transition.assessment.obligations = transition.assessment.obligations.filter((item) => item.requirement_id !== "req-nav-dirty");
  assert.ok(codes(validate({ phase: "pre_build", ...transition })).includes("CAPTURE_REQUIREMENT_OBLIGATION_MISSING"));
});

test("base deletion, candidate addition, all supported dependency kinds, and equivalent navigation verification are covered", () => {
  const documents = validDocuments();
  assert.deepEqual(new Set(documents.capture.edges.map((edge) => edge.dependency_kind)), new Set(["call", "wrapper", "config", "registration", "event", "state", "public"]));
  assert.ok(documents.capture.edges.some((edge) => edge.presence === "base"));
  assert.ok(documents.capture.edges.some((edge) => edge.presence === "candidate"));
  assert.equal(validate({ phase: "completion", ...documents }).valid, true);
  documents.assessment.equivalence_groups[0].justification_ref = "";
  assert.ok(codes(validate({ phase: "pre_build", ...documents })).includes("EQUIVALENCE_GROUPS_INVALID"));
});

test("unsupported local claim, stale universe, stale verification source, and wrong review projection reject", () => {
  const local = validDocuments(); local.assessment.impact_scope = "local";
  assert.ok(codes(validate({ phase: "pre_build", ...local })).includes("IMPACT_SCOPE_CONTEXT_MISMATCH"));
  const stale = validDocuments(); stale.expected.snapshot.universe_id = "universe-after-new-registration";
  assert.ok(codes(validate({ phase: "completion", ...stale })).includes("CAPTURE_CONTEXT_MISMATCH"));
  const source = validDocuments(); source.assessment.verification_plans[1].source_identity = "old-test-source";
  assert.ok(codes(validate({ phase: "completion", ...source })).includes("VERIFICATION_REQUIREMENT_MISMATCH"));
  const review = validDocuments(); review.review.bindings[0].coverage_concern_id = "wrong-concern";
  assert.ok(codes(validate({ phase: "completion", ...review })).includes("REVIEW_OBLIGATION_BINDING_INCOMPLETE"));
});

test("waived obligations require authorization at pre-build and remain residual risk at completion", () => {
  const missingAuthority = validDocuments(); missingAuthority.assessment.obligations[6].disposition = "waived"; missingAuthority.assessment.actual_verifications = [];
  assert.deepEqual(codes(validate({ phase: "pre_build", ...missingAuthority })), ["AUTHORIZATION_REFERENCE_MISSING"]);
  const waived = validDocuments(); waived.assessment.obligations[6].disposition = "waived"; waived.assessment.obligations[6].authorization_ref = "existing-policy-approval"; waived.assessment.actual_verifications = [];
  assert.equal(validate({ phase: "pre_build", ...waived }).valid, true);
  assert.ok(codes(validate({ phase: "completion", ...waived })).includes("UNVERIFIED_RESIDUAL_RISK"));
});

test("blocked, unresolved, and planned-as-actual completion states remain incomplete", () => {
  const blocked = validDocuments(); blocked.assessment.obligations[6].disposition = "blocked"; blocked.assessment.actual_verifications = [];
  assert.ok(codes(validate({ phase: "pre_build", ...blocked })).includes("BLOCKED_IMPACT_UNRESOLVED"));
  assert.ok(codes(validate({ phase: "completion", ...blocked })).includes("UNVERIFIED_RESIDUAL_RISK"));
  const unresolved = validDocuments(); unresolved.capture.unknown_boundaries.push({ id: "unknown-public-client", material: true, source_id: "boundary-current" });
  assert.ok(codes(validate({ phase: "pre_build", ...unresolved })).includes("MATERIAL_IMPACT_UNRESOLVED"));
  assert.ok(codes(validate({ phase: "completion", ...unresolved })).includes("MATERIAL_IMPACT_UNRESOLVED"));
  const planned = validDocuments(); planned.assessment.actual_verifications = [];
  assert.ok(codes(validate({ phase: "completion", ...planned })).includes("EXECUTED_VERIFICATION_MISSING_OR_STALE"));
});

test("capture requirements, reciprocal equivalence, and exact plan and actual consumption cannot be bypassed", () => {
  const edgeWithoutRequirement = validDocuments();
  edgeWithoutRequirement.capture.requirements = edgeWithoutRequirement.capture.requirements.filter((item) => item.edge_id !== "edge-cache");
  edgeWithoutRequirement.expected.required_requirements = edgeWithoutRequirement.expected.required_requirements.filter((item) => item.edge_id !== "edge-cache");
  edgeWithoutRequirement.expected.review_context.required_bindings = edgeWithoutRequirement.expected.review_context.required_bindings.filter((item) => item.requirement_id !== "req-cache");
  assert.ok(codes(validate({ phase: "discovery", ...edgeWithoutRequirement })).includes("CAPTURE_EDGE_REQUIREMENT_MISSING"));
  const directReuse = validDocuments(); directReuse.assessment.equivalence_groups = [];
  directReuse.assessment.obligations[0].verification_id = "plan-nav"; directReuse.assessment.obligations[0].equivalence_group_id = null;
  directReuse.assessment.obligations[2].verification_id = "plan-nav"; directReuse.assessment.obligations[2].equivalence_group_id = null;
  assert.ok(codes(validate({ phase: "pre_build", ...directReuse })).includes("DIRECT_VERIFICATION_REUSE_REQUIRES_EQUIVALENCE"));
  const reciprocal = validDocuments(); reciprocal.assessment.obligations[2].equivalence_group_id = null;
  assert.ok(codes(validate({ phase: "pre_build", ...reciprocal })).includes("EQUIVALENCE_GROUP_BINDING_INVALID"));
  const orphan = validDocuments(); orphan.assessment.verification_plans.push({ id: "unused-plan", contract_id: "cache", state_transition: "fresh-miss", oracle: "unused", steps_ref: "unused", source_identity: "test-cache-current" }); orphan.assessment.actual_verifications = [];
  assert.ok(codes(validate({ phase: "pre_build", ...orphan })).includes("VERIFICATION_PLAN_ORPHANED"));
  const actual = validDocuments(); actual.assessment.actual_verifications.push({ verification_id: "unconsumed", outcome: "passed", executed_source_identity: "anything", evidence_ref: "anything" });
  assert.ok(codes(validate({ phase: "completion", ...actual })).includes("ACTUAL_VERIFICATION_ORPHANED"));
});

test("scalar and null array members never throw and return structural reasons", () => {
  for (const mutate of [
    (documents) => { documents.capture.edges = [null]; },
    (documents) => { documents.expected.required_edges = [null]; },
    (documents) => { documents.assessment.equivalence_groups = [null]; },
    (documents) => { documents.assessment.actual_verifications = [null]; },
  ]) {
    const documents = validDocuments(); mutate(documents);
    assert.doesNotThrow(() => validate({ phase: "completion", ...documents }));
    assert.equal(validate({ phase: "completion", ...documents }).valid, false);
  }
});

test("duplicate and dangling identities fail with closure reasons", () => {
  const duplicate = validDocuments();
  duplicate.assessment.obligations.push({ ...duplicate.assessment.obligations[0], id: "obligation-duplicate" });
  assert.ok(codes(validate({ phase: "pre_build", ...duplicate })).includes("OBLIGATION_REQUIREMENT_DUPLICATE"));
  const dangling = validDocuments(); dangling.assessment.obligations[3].verification_id = "not-a-plan";
  assert.ok(codes(validate({ phase: "pre_build", ...dangling })).includes("VERIFICATION_PLAN_DANGLING"));
});

test("cosmetic local control remains proportionate", () => {
  const documents = validDocuments();
  documents.capture.edges = []; documents.capture.requirements = []; documents.expected.required_edges = []; documents.expected.required_requirements = [];
  documents.expected.required_impact_scope = "not_applicable"; documents.expected.review_context.required_bindings = [];
  documents.assessment.impact_scope = "not_applicable"; documents.assessment.assessment_kind = "cosmetic"; documents.assessment.obligations = []; documents.assessment.verification_plans = []; documents.assessment.equivalence_groups = []; documents.assessment.actual_verifications = [];
  documents.review.bindings = [];
  assert.equal(validate({ phase: "completion", ...documents }).valid, true);
});

test("CLI rejects malformed, oversized, nested, and command-looking input without executing it or echoing it", () => {
  const documents = validDocuments();
  const clean = runCli(documents, "completion");
  assert.equal(clean.status, 0, JSON.stringify({ stdout: clean.stdout, stderr: clean.stderr, result: clean.result })); assert.equal(clean.result.complete, true);
  const marker = path.join(os.tmpdir(), `change-impact-marker-${process.pid}`);
  const malicious = validDocuments(); malicious.assessment.verification_plans[0].steps_ref = `$(touch ${marker})`; malicious.assessment.actual_verifications = [];
  const noExecution = runCli(malicious, "pre_build");
  assert.equal(noExecution.status, 0); assert.equal(fs.existsSync(marker), false); assert.equal(noExecution.stdout.includes(marker), false);
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "change-impact-bounds-"));
  fs.writeFileSync(path.join(directory, "capture.json"), "{".repeat(MAX_BYTES + 1));
  fs.writeFileSync(path.join(directory, "expected.json"), JSON.stringify(validDocuments().expected));
  const oversized = spawnSync(process.execPath, [path.join(process.cwd(), "tools/change-impact/validate-change-impact.cjs"), "--phase", "discovery", "--capture", path.join(directory, "capture.json"), "--expected", path.join(directory, "expected.json")], { encoding: "utf8" });
  assert.equal(oversized.status, 2); assert.ok(oversized.stdout.includes("INPUT_TOO_LARGE"));
  fs.writeFileSync(path.join(directory, "capture.json"), "{broken");
  const malformed = spawnSync(process.execPath, [path.join(process.cwd(), "tools/change-impact/validate-change-impact.cjs"), "--phase", "discovery", "--capture", path.join(directory, "capture.json"), "--expected", path.join(directory, "expected.json")], { encoding: "utf8" });
  assert.equal(malformed.status, 2); assert.ok(malformed.stdout.includes("INPUT_MALFORMED"));
  const nested = validDocuments(); let cursor = {}; nested.capture.roots = cursor; for (let index = 0; index < 20; index += 1) cursor.next = cursor = {};
  const nestedResult = runCli(nested, "discovery");
  assert.equal(nestedResult.status, 2); assert.ok(nestedResult.stdout.includes("INPUT_UNSAFE_SHAPE"));
});
