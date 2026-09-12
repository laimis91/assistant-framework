"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const fsp = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const { test } = require("node:test");
const { validate } = require("../../tools/change-impact/validate-change-impact.cjs");

const truthRoot = path.join(__dirname, "fixtures", "independent-fixture-truth");
const truth = JSON.parse(fs.readFileSync(path.join(truthRoot, "truth.expected.json"), "utf8"));
const fixtureAuthority = JSON.parse(fs.readFileSync(path.join(truthRoot, "fixture-authority.json"), "utf8"));

function clone(value) { return JSON.parse(JSON.stringify(value)); }
function codes(result) { return result.reasons.map((reason) => reason.code); }
function caseId(value) { return value.id.replace(/[^a-z0-9]+/gi, "-"); }

function sourceInventory(value) {
  const contracts = value.expected_contracts || [value.id];
  const consumers = value.expected_consumers;
  const transitions = [...value.expected_transitions];
  while (transitions.length < consumers.length) transitions.push(value.expected_transitions[0]);
  const sharedHighFanoutSource = value.id === "high-fanout-equivalent-control" ? `fixture-truth:${value.id}:equivalent` : null;
  const edges = consumers.map((consumer, index) => ({
    id: `edge-${caseId(value)}-${index + 1}`,
    consumer_id: consumer,
    contract_id: contracts[index % contracts.length],
    dependency_kind: value.id === "serialization-config-public-compatibility" ? (index === 0 ? "public" : "config") :
      value.id === "cache-retry-material-state" ? "state" : value.id === "high-fanout-equivalent-control" ? "wrapper" : "call",
    presence: value.id === "serialization-config-public-compatibility" ? (index === 0 ? "base" : "candidate") : "both",
    source_id: `fixture-source:${value.id}:${consumer}`,
  }));
  const requirements = transitions.map((transition, index) => {
    const edge = edges[index % edges.length];
    return {
      id: `requirement-${caseId(value)}-${index + 1}`,
      edge_id: edge.id,
      contract_id: edge.contract_id,
      state_transition: transition,
      source_id: `fixture-source:${value.id}:${transition}`,
      verification_source_id: sharedHighFanoutSource && transition === value.expected_transitions[0] ? sharedHighFanoutSource : `fixture-truth:${value.id}:${index + 1}`,
    };
  });
  return { edges, requirements };
}

function documentsFromTruth(value) {
  const inventory = sourceInventory(value);
  const snapshot = { base_id: `base:${value.id}`, candidate_id: `candidate:${value.id}`, universe_id: `content-sha256/no-git:${value.id}` };
  const capture = {
    schema_version: "change-impact-capture/v1",
    capture_id: `capture:${value.id}`,
    snapshot: clone(snapshot),
    roots: value.scope === "shared" ? [{ id: `root:${value.id}`, method: "fixture-source", source_id: `fixture-root:${value.id}` }] : [],
    edges: inventory.edges.map(({ verification_source_id, ...edge }) => edge),
    requirements: inventory.requirements.map(({ verification_source_id, ...requirement }) => requirement),
    unknown_boundaries: [],
  };
  const expected = {
    schema_version: "change-impact-expected-context/v1",
    authority_id: `independent-fixture-truth:${value.id}`,
    capture_id: capture.capture_id,
    snapshot: clone(snapshot),
    required_impact_scope: value.scope === "shared" ? "shared" : "not_applicable",
    required_edges: clone(capture.edges),
    required_requirements: clone(inventory.requirements),
    review_context: null,
  };
  if (value.assessment_kind === "cosmetic") return { capture, expected };

  const groupRequirementIds = value.id === "high-fanout-equivalent-control" ?
    inventory.requirements.filter((requirement) => requirement.verification_source_id.endsWith(":equivalent")).map((requirement) => requirement.id) : [];
  const groupVerificationId = groupRequirementIds.length > 0 ? `verification:${value.id}:equivalent` : null;
  const verificationPlans = [];
  const planForRequirement = new Map();
  for (const requirement of inventory.requirements) {
    const verificationId = groupRequirementIds.includes(requirement.id) ? groupVerificationId : `verification:${requirement.id}`;
    planForRequirement.set(requirement.id, verificationId);
    if (!verificationPlans.some((plan) => plan.id === verificationId)) {
      verificationPlans.push({ id: verificationId, contract_id: requirement.contract_id, state_transition: requirement.state_transition,
        oracle: `fixture-oracle:${requirement.id}`, steps_ref: `fixture-steps:${requirement.id}`, source_identity: requirement.verification_source_id });
    }
  }
  const obligations = inventory.requirements.map((requirement, index) => ({
    id: `obligation:${value.id}:${index + 1}`,
    requirement_id: requirement.id,
    disposition: "preserve",
    rationale_ref: `fixture-rationale:${requirement.id}`,
    authorization_ref: null,
    verification_id: groupRequirementIds.includes(requirement.id) ? null : planForRequirement.get(requirement.id),
    equivalence_group_id: groupRequirementIds.includes(requirement.id) ? `equivalence:${value.id}` : null,
  }));
  const reviewBindings = inventory.requirements.map((requirement, index) => ({
    requirement_id: requirement.id, scope_item_id: `scope:${value.id}:${index + 1}`, coverage_concern_id: `coverage:${value.id}:${index + 1}`,
  }));
  expected.review_context = {
    scope_manifest_id: `scope-manifest:${value.id}`,
    coverage_ledger_id: `coverage-ledger:${value.id}`,
    review_snapshot_id: `review-snapshot:${value.id}`,
    snapshot_id: `snapshot:${value.id}`,
    required_bindings: reviewBindings,
  };
  const assessment = {
    schema_version: "change-impact-assessment/v1",
    capture_id: capture.capture_id,
    snapshot: clone(snapshot),
    impact_scope: "shared",
    assessment_kind: "behavior",
    obligations,
    verification_plans: verificationPlans,
    equivalence_groups: groupVerificationId ? [{ id: `equivalence:${value.id}`, member_obligation_ids: obligations.filter((obligation) => obligation.equivalence_group_id).map((obligation) => obligation.id), justification_ref: `fixture-equivalence:${value.id}`, verification_id: groupVerificationId }] : [],
    actual_verifications: verificationPlans.map((plan) => ({ verification_id: plan.id, outcome: "passed", executed_source_identity: plan.source_identity, evidence_ref: `fixture-evidence:${plan.id}` })),
  };
  const review = {
    schema_version: "change-impact-review/v1",
    capture_id: capture.capture_id,
    snapshot: clone(snapshot),
    review_source: {
      scope_manifest_id: expected.review_context.scope_manifest_id,
      coverage_ledger_id: expected.review_context.coverage_ledger_id,
      review_snapshot_id: expected.review_context.review_snapshot_id,
      snapshot_id: expected.review_context.snapshot_id,
    },
    bindings: obligations.map((obligation, index) => ({ obligation_id: obligation.id, requirement_id: obligation.requirement_id,
      scope_item_id: reviewBindings[index].scope_item_id, coverage_concern_id: reviewBindings[index].coverage_concern_id })),
  };
  return { capture, expected, assessment, review };
}

test("frozen independent fixture truth executes its domain behavior before protocol adaptation", async () => {
  const validation = await import(pathToFileURL(path.join(truthRoot, "fixture-src", "validation.mjs")).href);
  const retry = await import(pathToFileURL(path.join(truthRoot, "fixture-src", "cache-retry.mjs")).href);
  const base = JSON.parse(await fsp.readFile(path.join(truthRoot, "fixture-src", "base-registry.json"), "utf8"));
  const candidate = JSON.parse(await fsp.readFile(path.join(truthRoot, "fixture-src", "candidate-registry.json"), "utf8"));
  assert.deepEqual(validation.formSubmit(null), { state: "untouched" });
  assert.deepEqual(validation.formSubmit("  "), { state: "required-error" });
  assert.deepEqual(validation.bulkImport(null), { state: "use-default-mapping" });
  assert.deepEqual(validation.bulkImport("  "), { state: "no-column-error" });
  assert.deepEqual(retry.foregroundRead({ stale: true, cancelled: false }), ["stale", "retrying", "fresh"]);
  assert.deepEqual(retry.foregroundRead({ stale: true, cancelled: true }), ["stale", "cancelled"]);
  assert.deepEqual(retry.backgroundRefresh({ stale: true, cancelled: false }), ["stale", "queued", "fresh"]);
  assert.deepEqual(retry.backgroundRefresh({ stale: true, cancelled: true }), ["stale", "cancelled"]);
  assert.deepEqual(base.registrations.map((entry) => entry.id), ["legacy-json"]);
  assert.deepEqual(candidate.registrations.map((entry) => entry.id), ["yaml"]);
  assert.deepEqual(validation.equivalentFormConsumers, ["form-submit", "form-draft", "form-accessibility"]);
  for (const consumer of validation.equivalentFormConsumers) assert.deepEqual(validation.equivalentFormConsumer(""), { state: "required-error" }, consumer);
});

test("adapted independent truth retains the frozen source authority hashes", () => {
  for (const [relativePath, expectedHash] of Object.entries(fixtureAuthority.sha256)) {
    const actualHash = crypto.createHash("sha256").update(fs.readFileSync(path.join(truthRoot, relativePath))).digest("hex");
    assert.equal(actualHash, expectedHash, relativePath);
  }
});

test("independent fixture authority adapts known consumers and transitions without accepting assessment omissions", () => {
  for (const value of truth.cases) {
    const documents = documentsFromTruth(value);
    assert.equal(documents.expected.required_edges.length, value.expected_consumers.length, value.id);
    assert.ok(value.expected_transitions.every((transition) => documents.expected.required_requirements.some((requirement) => requirement.state_transition === transition)), value.id);
    if (value.assessment_kind === "cosmetic") {
      assert.equal(validate({ phase: "discovery", ...documents }).valid, true, value.id);
      continue;
    }
    assert.equal(validate({ phase: "completion", ...documents }).complete, true, value.id);
    const missingConsumer = clone(documents);
    const omittedEdge = missingConsumer.capture.edges.pop();
    missingConsumer.capture.requirements = missingConsumer.capture.requirements.filter((requirement) => requirement.edge_id !== omittedEdge.id);
    assert.ok(codes(validate({ phase: "completion", ...missingConsumer })).includes("CAPTURE_EXPECTED_EDGES_MISMATCH"), `${value.id} consumer omission`);
    const missingTransition = clone(documents);
    missingTransition.assessment.obligations.pop();
    assert.ok(codes(validate({ phase: "pre-build", ...missingTransition })).includes("CAPTURE_REQUIREMENT_OBLIGATION_MISSING"), `${value.id} transition omission`);
  }
});

test("independent no-git content capture ignores unrelated dirt and invalidates current relevant content", async () => {
  const { capture } = await import(pathToFileURL(path.join(truthRoot, "capture.mjs")).href);
  const tempRoot = await fsp.mkdtemp(path.join(os.tmpdir(), "change-impact-independent-truth-"));
  const source = path.join(tempRoot, "fixture-src");
  try {
    await fsp.cp(path.join(truthRoot, "fixture-src"), source, { recursive: true });
    const initial = await capture(source);
    await fsp.writeFile(path.join(source, "unrelated-dirty-note.txt"), "unrelated dirty work\n");
    assert.deepEqual(await capture(source), initial);
    await fsp.writeFile(path.join(source, "new-relevant-consumer.mjs"), "export const consumer = 'new';\n");
    const afterAddedRelevant = await capture(source);
    assert.notEqual(afterAddedRelevant.universe_sha256, initial.universe_sha256);
    await fsp.appendFile(path.join(source, "validation.mjs"), "\n// relevant mutation\n");
    assert.notEqual((await capture(source)).universe_sha256, afterAddedRelevant.universe_sha256);
    assert.equal(initial.identity_kind, "content-sha256/no-git");
  } finally {
    await fsp.rm(tempRoot, { recursive: true, force: true });
  }
});
