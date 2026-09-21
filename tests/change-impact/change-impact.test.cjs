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

function reverseObjectKeys(value) {
  if (Array.isArray(value)) return value.map(reverseObjectKeys);
  if (value && typeof value === "object") return Object.fromEntries(Object.entries(value).reverse().map(([key, child]) => [key, reverseObjectKeys(child)]));
  return value;
}

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
  documents.assessment.actual_verifications = documents.assessment.verification_plans.map((plan) => ({ verification_id: plan.id, outcome: "passed", executed_snapshot: clone(documents.assessment.snapshot), executed_source_identity: plan.source_identity, evidence_ref: `result-${plan.id}` }));
  documents.expected.review_context.required_bindings = documents.capture.requirements.map((requirement, index) => ({ requirement_id: requirement.id, scope_item_id: `scope-${index + 1}`, coverage_concern_id: `concern-${index + 1}` }));
  documents.review.bindings = documents.assessment.obligations.map((obligation, index) => ({ obligation_id: obligation.id, requirement_id: obligation.requirement_id, scope_item_id: `scope-${index + 1}`, coverage_concern_id: `concern-${index + 1}` }));
  return documents;
}

function codes(result) { return result.reasons.map((reason) => reason.code); }

function runCli(documents, phase, mutate, priorResult, indentation) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "change-impact-"));
  if (mutate) mutate(documents, directory);
  for (const [name, value] of Object.entries(documents)) fs.writeFileSync(path.join(directory, `${name}.json`), JSON.stringify(value, null, indentation));
  const args = [path.join(process.cwd(), "tools/change-impact/validate-change-impact.cjs"), "--phase", phase, "--capture", path.join(directory, "capture.json"), "--expected", path.join(directory, "expected.json")];
  if (phase !== "discovery") args.push("--assessment", path.join(directory, "assessment.json"));
  if (phase === "completion") args.push("--review", path.join(directory, "review.json"));
  if (priorResult !== undefined) {
    fs.writeFileSync(path.join(directory, "receipt.json"), JSON.stringify(priorResult));
    args.push("--receipt", path.join(directory, "receipt.json"));
  }
  const child = spawnSync(process.execPath, args, { encoding: "utf8" });
  return { ...child, result: JSON.parse(child.stdout) };
}

function runApiAtRuntime(version) {
  const script = [
    'const fs = require("node:fs");',
    'Object.defineProperty(process.versions, "node", { value: process.argv[2], configurable: true });',
    'const { validate } = require(process.argv[1]);',
    'const documents = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));',
    'process.stdout.write(JSON.stringify(validate({ phase: "completion", ...documents })));',
  ].join("");
  const child = spawnSync(process.execPath, ["-e", script, path.join(process.cwd(), "tools/change-impact/validate-change-impact.cjs"), version, path.join(process.cwd(), "tools/change-impact/example.completion.v1.json")], { encoding: "utf8" });
  return { ...child, result: JSON.parse(child.stdout) };
}

function runCliAtRuntime(version) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "change-impact-runtime-"));
  try {
    const bootstrap = path.join(directory, "runtime.cjs");
    fs.writeFileSync(bootstrap, `Object.defineProperty(process.versions, "node", { value: ${JSON.stringify(version)}, configurable: true });`);
    const child = spawnSync(process.execPath, ["--require", bootstrap, path.join(process.cwd(), "tools/change-impact/validate-change-impact.cjs"), "--phase", "discovery", "--capture", path.join(directory, "missing-capture.json"), "--expected", path.join(directory, "missing-expected.json")], { encoding: "utf8" });
    return { ...child, result: JSON.parse(child.stdout) };
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
}

test("multidomain completion closes independent consumer, transition, verification, and review authority", () => {
  const result = validate({ phase: "completion", ...validDocuments() });
  assert.equal(result.valid, true);
  assert.equal(result.complete, true);
});

test("portable completion example is an executable protocol document", () => {
  assert.equal(validate({ phase: "completion", ...commonExample }).complete, true);
});

test("API and CLI reject unsupported Node runtimes before validation while Node 22 remains supported", () => {
  for (const version of ["20.20.0", "21.7.3"]) {
    const api = runApiAtRuntime(version);
    assert.equal(api.status, 0, api.stderr);
    assert.deepEqual(api.result, { schema_version: "change-impact-validation-result/v1", valid: false, complete: false, phase: null, reasons: [{ code: "RUNTIME_NODE22_OR_NEWER_REQUIRED" }], receipt: null });

    const cli = runCliAtRuntime(version);
    assert.equal(cli.status, 2, cli.stderr);
    assert.deepEqual(cli.result, api.result);
  }

  const supported = runApiAtRuntime("22.0.0");
  assert.equal(supported.status, 0, supported.stderr);
  assert.equal(supported.result.complete, true);
});

test("behavior pre-build and completion reject an all-unaffected assessment without a bound current verification", () => {
  const documents = clone(commonExample);
  documents.assessment.obligations = documents.assessment.obligations.map((obligation) => ({
    ...obligation,
    disposition: "unaffected",
    verification_id: null,
    equivalence_group_id: null,
  }));
  documents.assessment.verification_plans = [];
  documents.assessment.equivalence_groups = [];
  documents.assessment.actual_verifications = [];

  assert.equal(validate({ phase: "discovery", capture: documents.capture, expected: documents.expected }).valid, true);
  const preBuildResult = validate({ phase: "pre_build", ...documents });
  assert.equal(preBuildResult.valid, false);
  const preBuildCliResult = runCli(documents, "pre_build");
  assert.equal(preBuildCliResult.status, 1);
  assert.deepEqual(preBuildCliResult.result, preBuildResult);
  const apiResult = validate({ phase: "completion", ...documents });
  assert.equal(apiResult.complete, false);
  assert.ok(codes(apiResult).includes("BEHAVIOR_COMPLETION_VERIFICATION_MISSING"));

  const cliResult = runCli(documents, "completion");
  assert.equal(cliResult.status, 1);
  assert.deepEqual(cliResult.result, apiResult);
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
  cosmetic.assessment.obligations = cosmetic.assessment.obligations.map((obligation) => ({
    ...obligation,
    disposition: "unaffected",
    verification_id: null,
    equivalence_group_id: null,
  }));
  cosmetic.assessment.verification_plans = [];
  cosmetic.assessment.equivalence_groups = [];
  cosmetic.assessment.actual_verifications = [];
  assert.equal(validate({ phase: "discovery", capture: cosmetic.capture, expected: cosmetic.expected }).valid, true);
  assert.equal(validate({ phase: "pre_build", ...cosmetic }).valid, true);
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

test("behavior assessments require roots, consumers, and requirements at pre-build and completion, including local", () => {
  for (const phase of ["pre_build", "completion"]) {
    const missingRoots = validDocuments();
    missingRoots.expected.required_impact_scope = "local";
    missingRoots.assessment.impact_scope = "local";
    missingRoots.capture.roots = [];
    if (phase === "pre_build") missingRoots.assessment.actual_verifications = [];
    assert.ok(codes(validate({ phase, ...missingRoots })).includes("CAPTURE_BEHAVIOR_ROOTS_EMPTY"), phase);

    const missingConsumers = validDocuments();
    missingConsumers.expected.required_impact_scope = "local";
    missingConsumers.assessment.impact_scope = "local";
    missingConsumers.capture.edges = [];
    missingConsumers.capture.requirements = [];
    missingConsumers.expected.required_edges = [];
    missingConsumers.expected.required_requirements = [];
    missingConsumers.expected.review_context.required_bindings = [];
    missingConsumers.assessment.obligations = [];
    missingConsumers.assessment.verification_plans = [];
    missingConsumers.assessment.equivalence_groups = [];
    missingConsumers.assessment.actual_verifications = [];
    missingConsumers.review.bindings = [];
    assert.ok(codes(validate({ phase, ...missingConsumers })).includes("CAPTURE_BEHAVIOR_CONSUMERS_EMPTY"), phase);

    const missingRequirements = validDocuments();
    missingRequirements.expected.required_impact_scope = "local";
    missingRequirements.assessment.impact_scope = "local";
    missingRequirements.capture.requirements = [];
    missingRequirements.expected.required_requirements = [];
    missingRequirements.expected.review_context.required_bindings = [];
    missingRequirements.assessment.obligations = [];
    missingRequirements.assessment.verification_plans = [];
    missingRequirements.assessment.equivalence_groups = [];
    missingRequirements.assessment.actual_verifications = [];
    missingRequirements.review.bindings = [];
    assert.ok(codes(validate({ phase, ...missingRequirements })).includes("CAPTURE_EDGE_REQUIREMENT_MISSING"), phase);
  }

  const emptyLocal = clone(commonExample);
  emptyLocal.expected.required_impact_scope = "local";
  emptyLocal.assessment.impact_scope = "local";
  emptyLocal.capture.roots = [];
  emptyLocal.capture.edges = [];
  emptyLocal.capture.requirements = [];
  emptyLocal.expected.required_edges = [];
  emptyLocal.expected.required_requirements = [];
  emptyLocal.expected.review_context.required_bindings = [];
  emptyLocal.assessment.obligations = [];
  emptyLocal.assessment.verification_plans = [];
  emptyLocal.assessment.equivalence_groups = [];
  emptyLocal.assessment.actual_verifications = [];
  emptyLocal.review.bindings = [];
  const apiResult = validate({ phase: "completion", ...emptyLocal });
  const cliResult = runCli(emptyLocal, "completion");
  assert.equal(apiResult.valid, false);
  assert.equal(cliResult.status, 1);
  assert.deepEqual(cliResult.result, apiResult);

  const populatedLocal = validDocuments();
  populatedLocal.expected.required_impact_scope = "local";
  populatedLocal.assessment.impact_scope = "local";
  assert.equal(validate({ phase: "completion", ...populatedLocal }).complete, true);
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

test("canonical planned pre_build retains unaffected plus bound direct and equivalence plans through the API and CLI", () => {
  const documents = validDocuments();
  documents.assessment.actual_verifications = [];
  const apiResult = validate({ phase: "pre_build", ...documents });
  const cliResult = runCli(documents, "pre_build");
  assert.equal(apiResult.valid, true);
  assert.equal(cliResult.status, 0);
  assert.deepEqual(cliResult.result, apiResult);
});

test("validation receipts bind current relevant parsed inputs for API and CLI reuse", () => {
  const documents = validDocuments();
  documents.assessment.actual_verifications = [];
  const fresh = validate({ phase: "pre_build", ...documents });
  assert.deepEqual(fresh.receipt, {
    schema_version: "change-impact-validation-receipt/v1",
    validation_contract: "change-impact-validator/v1",
    canonicalization: "change-impact-canonical-json/v1",
    digest_algorithm: "sha256",
    phase: "pre_build",
    input_digests: fresh.receipt.input_digests,
  });
  assert.ok(Object.values(fresh.receipt.input_digests).every((value) => value === null || /^sha256:[0-9a-f]{64}$/.test(value)));
  assert.equal(fresh.receipt.input_digests.review, null);

  const apiReuse = validate({ phase: "pre_build", ...documents, priorResult: fresh });
  const cliReuse = runCli(documents, "pre_build", null, fresh);
  assert.deepEqual(apiReuse, fresh);
  assert.equal(cliReuse.status, 0);
  assert.deepEqual(cliReuse.result, fresh);

  const reordered = clone(documents);
  reordered.capture = Object.fromEntries(Object.entries(reordered.capture).reverse());
  assert.deepEqual(validate({ phase: "pre_build", ...reordered }).receipt, fresh.receipt);
  const reorderedArrays = clone(documents);
  reorderedArrays.capture.roots.reverse();
  assert.notEqual(validate({ phase: "pre_build", ...reorderedArrays }).receipt.input_digests.capture, fresh.receipt.input_digests.capture);

  const changedAssessment = clone(documents);
  changedAssessment.assessment.verification_plans[0].oracle = "changed-current-oracle";
  const mismatch = validate({ phase: "pre_build", ...changedAssessment, priorResult: fresh });
  assert.equal(mismatch.valid, false);
  assert.equal(mismatch.receipt, null);
  assert.ok(codes(mismatch).includes("RECEIPT_MISMATCH"));

  const malformed = validate({ phase: "pre_build", ...documents, priorResult: { valid: true } });
  assert.equal(malformed.receipt, null);
  assert.ok(codes(malformed).includes("RECEIPT_SCHEMA_INVALID"));
  const outerPhaseMismatch = clone(fresh);
  outerPhaseMismatch.phase = "completion";
  assert.ok(codes(validate({ phase: "pre_build", ...documents, priorResult: outerPhaseMismatch })).includes("RECEIPT_SCHEMA_INVALID"));
  const outerCompletionMismatch = clone(fresh);
  outerCompletionMismatch.complete = true;
  assert.ok(codes(validate({ phase: "pre_build", ...documents, priorResult: outerCompletionMismatch })).includes("RECEIPT_SCHEMA_INVALID"));
  const phaseSlotMismatch = clone(fresh);
  phaseSlotMismatch.receipt.input_digests.review = phaseSlotMismatch.receipt.input_digests.capture;
  assert.ok(codes(validate({ phase: "pre_build", ...documents, priorResult: phaseSlotMismatch })).includes("RECEIPT_SCHEMA_INVALID"));
  const invalidCurrent = clone(documents);
  invalidCurrent.assessment.obligations.pop();
  const invalidResult = validate({ phase: "pre_build", ...invalidCurrent, priorResult: fresh });
  assert.equal(invalidResult.receipt, null);
  assert.ok(codes(invalidResult).includes("CAPTURE_REQUIREMENT_OBLIGATION_MISSING"));

  const completion = validDocuments();
  const phaseMismatch = validate({ phase: "completion", ...completion, priorResult: fresh });
  assert.ok(codes(phaseMismatch).includes("RECEIPT_MISMATCH"));
  const discovery = validate({ phase: "discovery", capture: documents.capture, expected: documents.expected, assessment: { ignored: true } });
  assert.equal(discovery.receipt.input_digests.assessment, null);
  assert.equal(discovery.receipt.input_digests.review, null);
});

test("receipts reuse every phase and reject valid current capture, expected, and review changes", () => {
  for (const phase of ["discovery", "pre_build", "completion"]) {
    const documents = validDocuments();
    if (phase === "pre_build") documents.assessment.actual_verifications = [];
    const fresh = validate({ phase, ...documents });
    assert.equal(fresh.valid, true, phase);
    assert.deepEqual(validate({ phase, ...documents, priorResult: fresh }), fresh, `${phase} API`);
    const cli = runCli(documents, phase, null, fresh);
    assert.equal(cli.status, 0, `${phase} CLI`);
    assert.deepEqual(cli.result, fresh, `${phase} CLI result`);
  }

  const preBuild = validDocuments();
  preBuild.assessment.actual_verifications = [];
  const priorPreBuild = validate({ phase: "pre_build", ...preBuild });
  const changedCapture = clone(preBuild);
  changedCapture.capture.roots[0].source_id = "current-capture-changed";
  assert.ok(codes(validate({ phase: "pre_build", ...changedCapture, priorResult: priorPreBuild })).includes("RECEIPT_MISMATCH"));
  const changedExpected = clone(preBuild);
  changedExpected.expected.authority_id = "current-expected-changed";
  assert.ok(codes(validate({ phase: "pre_build", ...changedExpected, priorResult: priorPreBuild })).includes("RECEIPT_MISMATCH"));

  const completion = validDocuments();
  const priorCompletion = validate({ phase: "completion", ...completion });
  const reorderedReview = clone(completion);
  reorderedReview.review.bindings.reverse();
  assert.equal(validate({ phase: "completion", ...reorderedReview }).valid, true);
  assert.ok(codes(validate({ phase: "completion", ...reorderedReview, priorResult: priorCompletion })).includes("RECEIPT_MISMATCH"));
});

test("receipt canonicalization ignores recursive object order and CLI whitespace, while API admission fails safely", () => {
  const documents = validDocuments();
  documents.assessment.actual_verifications = [];
  const fresh = validate({ phase: "pre_build", ...documents });
  const reordered = reverseObjectKeys(documents);
  assert.deepEqual(validate({ phase: "pre_build", ...reordered }).receipt, fresh.receipt);
  const compactCli = runCli(documents, "pre_build");
  const spacedCli = runCli(documents, "pre_build", null, undefined, 2);
  assert.deepEqual(spacedCli.result.receipt, compactCli.result.receipt);

  const aliased = validDocuments();
  for (const actual of aliased.assessment.actual_verifications) actual.executed_snapshot = aliased.assessment.snapshot;
  const aliasedResult = validate({ phase: "completion", ...aliased });
  const jsonClonedResult = validate({ phase: "completion", ...clone(aliased) });
  assert.equal(aliasedResult.valid, true);
  assert.deepEqual(aliasedResult, jsonClonedResult);

  const cyclic = validDocuments();
  cyclic.assessment.actual_verifications = [];
  cyclic.capture.snapshot.loop = cyclic.capture.snapshot;
  const cyclicResult = validate({ phase: "pre_build", ...cyclic });
  assert.equal(cyclicResult.valid, false);
  assert.equal(cyclicResult.receipt, null);
  const oversized = validDocuments();
  oversized.assessment.actual_verifications = [];
  oversized.capture.roots[0].source_id = "x".repeat(MAX_BYTES + 1);
  const oversizedResult = validate({ phase: "pre_build", ...oversized });
  assert.equal(oversizedResult.valid, false);
  assert.equal(oversizedResult.receipt, null);

  const dense = validDocuments();
  dense.assessment.actual_verifications = [];
  const densePrior = validate({ phase: "pre_build", ...dense });
  const sparse = clone(dense);
  sparse.capture.unknown_boundaries = Array(1);
  for (const priorResult of [undefined, densePrior]) {
    const sparseResult = validate({ phase: "pre_build", ...sparse, priorResult });
    assert.equal(sparseResult.receipt, null);
    assert.ok(codes(sparseResult).includes("INPUT_UNSAFE_SHAPE"));
  }

  const accessor = clone(dense);
  let accessorReads = 0;
  Object.defineProperty(accessor.capture, "capture_id", { enumerable: true, get() { accessorReads += 1; return "capture-example-current"; } });
  for (const priorResult of [undefined, densePrior]) {
    const accessorResult = validate({ phase: "pre_build", ...accessor, priorResult });
    assert.equal(accessorResult.receipt, null);
    assert.ok(codes(accessorResult).includes("INPUT_UNSAFE_SHAPE"));
  }
  assert.equal(accessorReads, 0);
  const proxy = clone(dense);
  proxy.capture = new Proxy(proxy.capture, {});
  assert.ok(codes(validate({ phase: "pre_build", ...proxy })).includes("INPUT_UNSAFE_SHAPE"));
  const symbol = clone(dense);
  symbol.capture[Symbol("unexpected")] = "value";
  assert.ok(codes(validate({ phase: "pre_build", ...symbol })).includes("INPUT_UNSAFE_SHAPE"));
  const nonEnumerable = clone(dense);
  Object.defineProperty(nonEnumerable.capture, "hidden", { value: "value", enumerable: false });
  assert.ok(codes(validate({ phase: "pre_build", ...nonEnumerable })).includes("INPUT_UNSAFE_SHAPE"));
  const extraArrayKey = clone(dense);
  extraArrayKey.capture.unknown_boundaries.extra = "value";
  for (const priorResult of [undefined, densePrior]) assert.ok(codes(validate({ phase: "pre_build", ...extraArrayKey, priorResult })).includes("INPUT_UNSAFE_SHAPE"));
  const frozen = clone(dense);
  Object.freeze(frozen.capture);
  const frozenResult = validate({ phase: "pre_build", ...frozen });
  assert.equal(frozenResult.valid, true);
  assert.deepEqual(validate({ phase: "pre_build", ...frozen, priorResult: frozenResult }), frozenResult);

  const prior = fresh;
  assert.equal(runCli(documents, "pre_build", null, { valid: true }).status, 1);
  assert.equal(runCli(documents, "pre_build", null, "x".repeat(MAX_BYTES + 1)).status, 2);
  let deep = {};
  for (let index = 0; index <= 17; index += 1) deep = { nested: deep };
  assert.equal(runCli(documents, "pre_build", null, deep).status, 2);
  assert.equal(runCli(documents, "pre_build", null, prior).status, 0);
});

test("completion binds direct and equivalence verification records to the executed snapshot", () => {
  const current = validDocuments();
  assert.equal(validate({ phase: "completion", ...current }).complete, true);

  const stale = validDocuments();
  const refreshedSnapshot = { base_id: "base-refreshed", candidate_id: "candidate-refreshed", universe_id: "universe-refreshed" };
  stale.capture.capture_id = "capture-refreshed";
  stale.expected.capture_id = "capture-refreshed";
  stale.assessment.capture_id = "capture-refreshed";
  stale.review.capture_id = "capture-refreshed";
  stale.capture.snapshot = clone(refreshedSnapshot);
  stale.expected.snapshot = clone(refreshedSnapshot);
  stale.assessment.snapshot = clone(refreshedSnapshot);
  stale.review.snapshot = clone(refreshedSnapshot);
  const apiResult = validate({ phase: "completion", ...stale });
  assert.ok(codes(apiResult).includes("EXECUTED_VERIFICATION_MISSING_OR_STALE"));
  const cliResult = runCli(stale, "completion");
  assert.equal(cliResult.status, 1);
  assert.deepEqual(cliResult.result, apiResult);

  for (const mutate of [
    (documents) => { delete documents.assessment.actual_verifications[0].executed_snapshot; },
    (documents) => { documents.assessment.actual_verifications[0].executed_snapshot = { candidate_id: "candidate-only" }; },
    (documents) => { documents.assessment.actual_verifications[0].executed_snapshot.base_id = "base-stale"; },
    (documents) => { documents.assessment.actual_verifications[0].executed_snapshot.candidate_id = "candidate-stale"; },
    (documents) => { documents.assessment.actual_verifications[0].executed_snapshot.universe_id = "universe-stale"; },
  ]) {
    const documents = validDocuments();
    mutate(documents);
    const result = validate({ phase: "completion", ...documents });
    assert.equal(result.valid, false);
    assert.ok(codes(result).some((code) => ["ACTUAL_VERIFICATIONS_INVALID", "EXECUTED_VERIFICATION_MISSING_OR_STALE"].includes(code)));
  }
});

test("completion rejects each stale component on the direct and equivalence execution records", () => {
  for (const verificationId of ["plan-nav", "plan-dirty"]) {
    for (const component of ["base_id", "candidate_id", "universe_id"]) {
      const documents = validDocuments();
      const actual = documents.assessment.actual_verifications.find((item) => item.verification_id === verificationId);
      actual.executed_snapshot[component] = `${actual.executed_snapshot[component]}-stale`;
      assert.ok(codes(validate({ phase: "completion", ...documents })).includes("EXECUTED_VERIFICATION_MISSING_OR_STALE"), `${verificationId} ${component}`);
    }
  }
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
  const actual = validDocuments(); actual.assessment.actual_verifications.push({ verification_id: "unconsumed", outcome: "passed", executed_snapshot: clone(actual.assessment.snapshot), executed_source_identity: "anything", evidence_ref: "anything" });
  assert.ok(codes(validate({ phase: "completion", ...actual })).includes("ACTUAL_VERIFICATION_ORPHANED"));
});

test("a verification plan cannot be reused by two disjoint equivalence groups", () => {
  const documents = validDocuments();
  for (const [suffix, consumer] of [["a", "viewer"], ["b", "dialog"]]) {
    const edge = { id: `edge-nav-${suffix}`, consumer_id: consumer, contract_id: "navigation", dependency_kind: "call", presence: "both", source_id: `${consumer}-current` };
    const requirement = { id: `req-nav-${suffix}`, edge_id: edge.id, contract_id: "navigation", state_transition: "route-success", source_id: edge.source_id, verification_source_id: "test-navigation-current" };
    documents.capture.edges.push(edge);
    const { verification_source_id, ...capturedRequirement } = requirement;
    documents.capture.requirements.push(capturedRequirement);
    documents.expected.required_edges.push(clone(edge));
    documents.expected.required_requirements.push(requirement);
  }
  const next = documents.assessment.obligations.length + 1;
  documents.assessment.obligations.push(
    { id: `obligation-${next}`, requirement_id: "req-nav-a", disposition: "preserve", rationale_ref: "rationale-req-nav-a", authorization_ref: null, verification_id: null, equivalence_group_id: "group-navigation-second" },
    { id: `obligation-${next + 1}`, requirement_id: "req-nav-b", disposition: "preserve", rationale_ref: "rationale-req-nav-b", authorization_ref: null, verification_id: null, equivalence_group_id: "group-navigation-second" },
  );
  documents.assessment.equivalence_groups.push({ id: "group-navigation-second", member_obligation_ids: [`obligation-${next}`, `obligation-${next + 1}`], justification_ref: "same-route-contract-second", verification_id: "plan-nav" });
  documents.expected.review_context.required_bindings.push(
    { requirement_id: "req-nav-a", scope_item_id: `scope-${next}`, coverage_concern_id: `concern-${next}` },
    { requirement_id: "req-nav-b", scope_item_id: `scope-${next + 1}`, coverage_concern_id: `concern-${next + 1}` },
  );
  documents.review.bindings.push(
    { obligation_id: `obligation-${next}`, requirement_id: "req-nav-a", scope_item_id: `scope-${next}`, coverage_concern_id: `concern-${next}` },
    { obligation_id: `obligation-${next + 1}`, requirement_id: "req-nav-b", scope_item_id: `scope-${next + 1}`, coverage_concern_id: `concern-${next + 1}` },
  );
  assert.ok(codes(validate({ phase: "pre_build", ...{ ...documents, assessment: { ...documents.assessment, actual_verifications: [] } } })).includes("EQUIVALENCE_VERIFICATION_REUSE_REQUIRES_SEPARATE_PLANS"));
  assert.ok(codes(validate({ phase: "completion", ...documents })).includes("EQUIVALENCE_VERIFICATION_REUSE_REQUIRES_SEPARATE_PLANS"));
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
