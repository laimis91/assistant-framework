#!/usr/bin/env node
"use strict";

// This checker validates closure against caller-supplied capture authority.  It
// deliberately does not inspect a repository, run evidence commands, or infer
// whether the supplied authority contains every possible runtime consumer.

const fs = require("node:fs");

const MAX_BYTES = 256 * 1024;
const MAX_DEPTH = 16;
const MAX_ARRAY = 200;
const MAX_OBJECT_KEYS = 60;
const PHASES = new Set(["discovery", "pre-build", "completion"]);
const DEPENDENCY_KINDS = new Set(["call", "wrapper", "config", "registration", "event", "state", "public"]);
const PRESENCES = new Set(["base", "candidate", "both"]);
const DISPOSITIONS = new Set(["preserve", "change", "unaffected", "waived", "blocked"]);
const SCOPES = new Set(["not_applicable", "local", "shared", "unresolved"]);
const SAFE_ERROR_CODES = new Set(["INPUT_UNREADABLE", "INPUT_TOO_LARGE", "INPUT_MALFORMED", "INPUT_UNSAFE_SHAPE", "CLI_USAGE_INVALID", "RUNTIME_NODE22_OR_NEWER_REQUIRED"]);

function issue(code) {
  return { code };
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function bounded(value, depth = 0) {
  if (depth > MAX_DEPTH) return false;
  if (Array.isArray(value)) return value.length <= MAX_ARRAY && value.every((item) => bounded(item, depth + 1));
  if (isObject(value)) return Object.keys(value).length <= MAX_OBJECT_KEYS && Object.values(value).every((item) => bounded(item, depth + 1));
  return value === null || ["string", "number", "boolean"].includes(typeof value);
}

function nonBlank(value) {
  return typeof value === "string" && value.trim().length > 0 && value.length <= 512;
}

function exactKeys(value, keys) {
  return isObject(value) && Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));
}

function uniqueIds(items, field = "id") {
  return Array.isArray(items) && items.every((item) => isObject(item) && nonBlank(item[field])) && new Set(items.map((item) => item[field])).size === items.length;
}

function sameSnapshot(left, right) {
  return isObject(left) && isObject(right) &&
    left.base_id === right.base_id && left.candidate_id === right.candidate_id && left.universe_id === right.universe_id;
}

function sameEdge(left, right) {
  return left.id === right.id && left.consumer_id === right.consumer_id && left.contract_id === right.contract_id &&
    left.dependency_kind === right.dependency_kind && left.presence === right.presence && left.source_id === right.source_id;
}

function sameRequirement(left, right) {
  return left.id === right.id && left.edge_id === right.edge_id && left.contract_id === right.contract_id &&
    left.state_transition === right.state_transition && left.source_id === right.source_id;
}

function validSnapshot(value) {
  return exactKeys(value, ["base_id", "candidate_id", "universe_id"]) &&
    nonBlank(value.base_id) && nonBlank(value.candidate_id) && nonBlank(value.universe_id);
}

function indexBy(items, field = "id") {
  return new Map(items.map((item) => [item[field], item]));
}

function readDocument(path) {
  let descriptor;
  try {
    descriptor = fs.openSync(path, fs.constants.O_RDONLY | (fs.constants.O_NONBLOCK || 0));
  } catch {
    throw new Error("INPUT_UNREADABLE");
  }
  try {
    if (!fs.fstatSync(descriptor).isFile()) throw new Error("INPUT_TOO_LARGE");
    const chunks = [];
    let totalBytes = 0;
    while (totalBytes <= MAX_BYTES) {
      const buffer = Buffer.allocUnsafe(Math.min(64 * 1024, MAX_BYTES + 1 - totalBytes));
      const bytesRead = fs.readSync(descriptor, buffer, 0, buffer.length, totalBytes);
      if (bytesRead === 0) break;
      chunks.push(buffer.subarray(0, bytesRead));
      totalBytes += bytesRead;
    }
    if (totalBytes > MAX_BYTES) throw new Error("INPUT_TOO_LARGE");
    const value = JSON.parse(Buffer.concat(chunks, totalBytes).toString("utf8"));
    if (!bounded(value)) throw new Error("INPUT_UNSAFE_SHAPE");
    return value;
  } catch (error) {
    if (error.message === "INPUT_TOO_LARGE" || error.message === "INPUT_UNSAFE_SHAPE") throw error;
    throw new Error("INPUT_MALFORMED");
  } finally {
    fs.closeSync(descriptor);
  }
}

function validateCapture(capture, expected, reasons) {
  if (!exactKeys(capture, ["schema_version", "capture_id", "snapshot", "roots", "edges", "requirements", "unknown_boundaries"]) ||
      capture.schema_version !== "change-impact-capture/v1" || !nonBlank(capture.capture_id) || !validSnapshot(capture.snapshot) ||
      !Array.isArray(capture.roots) || !Array.isArray(capture.edges) || !Array.isArray(capture.requirements) || !Array.isArray(capture.unknown_boundaries)) {
    reasons.push(issue("CAPTURE_SCHEMA_INVALID")); return;
  }
  const rootsValid = uniqueIds(capture.roots) && capture.roots.every((root) => exactKeys(root, ["id", "method", "source_id"]) && nonBlank(root.method) && nonBlank(root.source_id));
  const edgesValid = uniqueIds(capture.edges) && capture.edges.every((edge) =>
    exactKeys(edge, ["id", "consumer_id", "contract_id", "dependency_kind", "presence", "source_id"]) &&
    nonBlank(edge.consumer_id) && nonBlank(edge.contract_id) && DEPENDENCY_KINDS.has(edge.dependency_kind) && PRESENCES.has(edge.presence) && nonBlank(edge.source_id));
  if (!rootsValid) reasons.push(issue("CAPTURE_ROOTS_INVALID"));
  if (!edgesValid) { reasons.push(issue("CAPTURE_EDGES_INVALID")); return; }
  const edges = indexBy(capture.edges);
  const requirementsValid = uniqueIds(capture.requirements) && capture.requirements.every((requirement) =>
    exactKeys(requirement, ["id", "edge_id", "contract_id", "state_transition", "source_id"]) && nonBlank(requirement.edge_id) &&
    nonBlank(requirement.contract_id) && nonBlank(requirement.state_transition) && nonBlank(requirement.source_id) &&
    edges.has(requirement.edge_id) && edges.get(requirement.edge_id).contract_id === requirement.contract_id);
  const boundariesValid = uniqueIds(capture.unknown_boundaries) && capture.unknown_boundaries.every((boundary) =>
    exactKeys(boundary, ["id", "material", "source_id"]) && typeof boundary.material === "boolean" && nonBlank(boundary.source_id));
  if (!requirementsValid) reasons.push(issue("CAPTURE_REQUIREMENTS_INVALID"));
  if (!boundariesValid) reasons.push(issue("CAPTURE_BOUNDARIES_INVALID"));
  if (reasons.length) return;
  if (capture.roots.length === 0 && (expected.required_impact_scope === "shared" ||
      capture.unknown_boundaries.some((boundary) => boundary.material))) reasons.push(issue("CAPTURE_DISCOVERY_ROOTS_MISSING"));
  if (capture.edges.some((edge) => !capture.requirements.some((requirement) => requirement.edge_id === edge.id))) reasons.push(issue("CAPTURE_EDGE_REQUIREMENT_MISSING"));
  if (capture.capture_id !== expected.capture_id || !sameSnapshot(capture.snapshot, expected.snapshot)) reasons.push(issue("CAPTURE_CONTEXT_MISMATCH"));
  const captured = indexBy(capture.edges);
  const required = indexBy(expected.required_edges);
  if (captured.size !== required.size || [...required.entries()].some(([id, edge]) => !captured.has(id) || !sameEdge(captured.get(id), edge))) reasons.push(issue("CAPTURE_EXPECTED_EDGES_MISMATCH"));
  const capturedRequirements = indexBy(capture.requirements);
  const requiredRequirements = indexBy(expected.required_requirements);
  if (capturedRequirements.size !== requiredRequirements.size || [...requiredRequirements.entries()].some(([id, requirement]) =>
    !capturedRequirements.has(id) || !sameRequirement(capturedRequirements.get(id), requirement))) reasons.push(issue("CAPTURE_EXPECTED_REQUIREMENTS_MISMATCH"));
}

function validateExpected(expected, phase, reasons) {
  if (!exactKeys(expected, ["schema_version", "authority_id", "capture_id", "snapshot", "required_impact_scope", "required_edges", "required_requirements", "review_context"]) ||
      expected.schema_version !== "change-impact-expected-context/v1" || !nonBlank(expected.authority_id) || !nonBlank(expected.capture_id) ||
      !validSnapshot(expected.snapshot) || !SCOPES.has(expected.required_impact_scope) || !Array.isArray(expected.required_edges) || !Array.isArray(expected.required_requirements)) {
    reasons.push(issue("EXPECTED_CONTEXT_SCHEMA_INVALID")); return;
  }
  const edgesValid = uniqueIds(expected.required_edges) && expected.required_edges.every((edge) =>
    exactKeys(edge, ["id", "consumer_id", "contract_id", "dependency_kind", "presence", "source_id"]) &&
    nonBlank(edge.consumer_id) && nonBlank(edge.contract_id) && DEPENDENCY_KINDS.has(edge.dependency_kind) && PRESENCES.has(edge.presence) && nonBlank(edge.source_id));
  if (!edgesValid) { reasons.push(issue("EXPECTED_CONTEXT_EDGES_INVALID")); return; }
  const edges = indexBy(expected.required_edges);
  const requirementsValid = uniqueIds(expected.required_requirements) && expected.required_requirements.every((requirement) =>
    exactKeys(requirement, ["id", "edge_id", "contract_id", "state_transition", "source_id", "verification_source_id"]) &&
    nonBlank(requirement.edge_id) && nonBlank(requirement.contract_id) && nonBlank(requirement.state_transition) && nonBlank(requirement.source_id) &&
    nonBlank(requirement.verification_source_id) && edges.has(requirement.edge_id) && edges.get(requirement.edge_id).contract_id === requirement.contract_id);
  if (!requirementsValid) { reasons.push(issue("EXPECTED_CONTEXT_REQUIREMENTS_INVALID")); return; }
  const context = expected.review_context;
  if (phase !== "completion" && context === null) return;
  if (!exactKeys(context, ["scope_manifest_id", "coverage_ledger_id", "review_snapshot_id", "snapshot_id", "required_bindings"]) ||
      !nonBlank(context.scope_manifest_id) || !nonBlank(context.coverage_ledger_id) || !nonBlank(context.review_snapshot_id) || !nonBlank(context.snapshot_id) ||
      !Array.isArray(context.required_bindings) || !context.required_bindings.every((binding) =>
        exactKeys(binding, ["requirement_id", "scope_item_id", "coverage_concern_id"]) && nonBlank(binding.requirement_id) && nonBlank(binding.scope_item_id) && nonBlank(binding.coverage_concern_id)) ||
      !uniqueStrings(context.required_bindings.map((binding) => binding.requirement_id))) reasons.push(issue("EXPECTED_REVIEW_CONTEXT_INVALID"));
  if (reasons.length === 0 && (context.required_bindings.length !== expected.required_requirements.length ||
      context.required_bindings.some((binding) => !expected.required_requirements.some((requirement) => requirement.id === binding.requirement_id)))) reasons.push(issue("EXPECTED_REVIEW_CONTEXT_INCOMPLETE"));
}

function validateAssessment(assessment, capture, expected, phase, reasons) {
  if (!exactKeys(assessment, ["schema_version", "capture_id", "snapshot", "impact_scope", "assessment_kind", "obligations", "verification_plans", "equivalence_groups", "actual_verifications"]) ||
      assessment.schema_version !== "change-impact-assessment/v1" || !nonBlank(assessment.capture_id) || !validSnapshot(assessment.snapshot) ||
      !SCOPES.has(assessment.impact_scope) || !["behavior", "cosmetic"].includes(assessment.assessment_kind) ||
      !Array.isArray(assessment.obligations) || !Array.isArray(assessment.verification_plans) ||
      !Array.isArray(assessment.equivalence_groups) || !Array.isArray(assessment.actual_verifications)) {
    reasons.push(issue("ASSESSMENT_SCHEMA_INVALID")); return;
  }
  if (assessment.capture_id !== expected.capture_id || !sameSnapshot(assessment.snapshot, expected.snapshot)) reasons.push(issue("ASSESSMENT_CONTEXT_STALE"));
  if (assessment.impact_scope !== expected.required_impact_scope) reasons.push(issue("IMPACT_SCOPE_CONTEXT_MISMATCH"));
  if (assessment.assessment_kind === "cosmetic" && assessment.impact_scope !== "not_applicable") reasons.push(issue("COSMETIC_SCOPE_INVALID"));
  if (assessment.assessment_kind === "behavior" && assessment.impact_scope === "not_applicable") reasons.push(issue("BEHAVIOR_SCOPE_INVALID"));

  const requirements = indexBy(capture.requirements);
  const expectedRequirements = indexBy(expected.required_requirements);
  if (!uniqueIds(assessment.obligations) || !assessment.obligations.every((obligation) =>
    exactKeys(obligation, ["id", "requirement_id", "disposition", "rationale_ref", "authorization_ref", "verification_id", "equivalence_group_id"]) &&
    nonBlank(obligation.requirement_id) && DISPOSITIONS.has(obligation.disposition) && nonBlank(obligation.rationale_ref) &&
    (obligation.authorization_ref === null || nonBlank(obligation.authorization_ref)) &&
    (obligation.verification_id === null || nonBlank(obligation.verification_id)) &&
    (obligation.equivalence_group_id === null || nonBlank(obligation.equivalence_group_id)))) {
    reasons.push(issue("OBLIGATIONS_SCHEMA_INVALID")); return;
  }
  const obligationsByRequirement = new Map();
  for (const obligation of assessment.obligations) {
    if (!requirements.has(obligation.requirement_id)) reasons.push(issue("OBLIGATION_REQUIREMENT_DANGLING"));
    if (obligationsByRequirement.has(obligation.requirement_id)) reasons.push(issue("OBLIGATION_REQUIREMENT_DUPLICATE"));
    obligationsByRequirement.set(obligation.requirement_id, obligation);
    const needsVerification = ["preserve", "change"].includes(obligation.disposition);
    if (["change", "waived"].includes(obligation.disposition) && !nonBlank(obligation.authorization_ref)) reasons.push(issue("AUTHORIZATION_REFERENCE_MISSING"));
    if (!["change", "waived"].includes(obligation.disposition) && obligation.authorization_ref !== null) reasons.push(issue("AUTHORIZATION_REFERENCE_UNEXPECTED"));
    if (needsVerification && !obligation.verification_id && !obligation.equivalence_group_id) reasons.push(issue("OBLIGATION_VERIFICATION_MISSING"));
    if (!needsVerification && (obligation.verification_id || obligation.equivalence_group_id)) reasons.push(issue("UNVERIFIED_DISPOSITION_MARKED_VERIFIED"));
  }
  if (obligationsByRequirement.size !== requirements.size || [...requirements.keys()].some((id) => !obligationsByRequirement.has(id))) reasons.push(issue("CAPTURE_REQUIREMENT_OBLIGATION_MISSING"));

  const plansValid = uniqueIds(assessment.verification_plans) && assessment.verification_plans.every((plan) =>
    exactKeys(plan, ["id", "contract_id", "state_transition", "oracle", "steps_ref", "source_identity"]) &&
    nonBlank(plan.contract_id) && nonBlank(plan.state_transition) && nonBlank(plan.oracle) && nonBlank(plan.steps_ref) && nonBlank(plan.source_identity));
  if (!plansValid) { reasons.push(issue("VERIFICATION_PLANS_INVALID")); return; }
  const plans = indexBy(assessment.verification_plans);
  for (const obligation of assessment.obligations) {
    if (obligation.verification_id && !plans.has(obligation.verification_id)) reasons.push(issue("VERIFICATION_PLAN_DANGLING"));
    if (obligation.verification_id && requirements.has(obligation.requirement_id) && plans.has(obligation.verification_id) &&
      (plans.get(obligation.verification_id).contract_id !== requirements.get(obligation.requirement_id).contract_id ||
       plans.get(obligation.verification_id).state_transition !== requirements.get(obligation.requirement_id).state_transition ||
       plans.get(obligation.verification_id).source_identity !== expectedRequirements.get(obligation.requirement_id)?.verification_source_id)) reasons.push(issue("VERIFICATION_REQUIREMENT_MISMATCH"));
  }

  const groupsValid = uniqueIds(assessment.equivalence_groups) && assessment.equivalence_groups.every((group) =>
    exactKeys(group, ["id", "member_obligation_ids", "justification_ref", "verification_id"]) &&
    Array.isArray(group.member_obligation_ids) && group.member_obligation_ids.length >= 2 && uniqueStrings(group.member_obligation_ids) &&
    nonBlank(group.justification_ref) && nonBlank(group.verification_id));
  if (!groupsValid) { reasons.push(issue("EQUIVALENCE_GROUPS_INVALID")); return; }
  const groups = indexBy(assessment.equivalence_groups);
  for (const group of assessment.equivalence_groups) {
    const members = group.member_obligation_ids.map((id) => assessment.obligations.find((obligation) => obligation.id === id));
    if (members.some((member) => !member) || !plans.has(group.verification_id)) { reasons.push(issue("EQUIVALENCE_GROUP_DANGLING")); continue; }
    const contracts = new Set(members.map((member) => requirements.get(member.requirement_id)?.contract_id));
    const transitions = new Set(members.map((member) => requirements.get(member.requirement_id)?.state_transition));
    const verificationSources = new Set(members.map((member) => expectedRequirements.get(member.requirement_id)?.verification_source_id));
    if (contracts.size !== 1 || transitions.size !== 1 || verificationSources.size !== 1 || plans.get(group.verification_id).contract_id !== [...contracts][0] ||
      plans.get(group.verification_id).state_transition !== [...transitions][0] || plans.get(group.verification_id).source_identity !== [...verificationSources][0]) reasons.push(issue("EQUIVALENCE_GROUP_UNJUSTIFIED"));
    if (members.some((member) => member.equivalence_group_id !== group.id || member.verification_id !== null)) reasons.push(issue("EQUIVALENCE_GROUP_BINDING_INVALID"));
  }
  for (const obligation of assessment.obligations) if (obligation.equivalence_group_id &&
    (!groups.has(obligation.equivalence_group_id) || !groups.get(obligation.equivalence_group_id).member_obligation_ids.includes(obligation.id))) reasons.push(issue("EQUIVALENCE_GROUP_BINDING_INVALID"));

  const directPlanUse = new Map();
  for (const obligation of assessment.obligations) if (obligation.verification_id) directPlanUse.set(obligation.verification_id, (directPlanUse.get(obligation.verification_id) || 0) + 1);
  if ([...directPlanUse.values()].some((count) => count > 1)) reasons.push(issue("DIRECT_VERIFICATION_REUSE_REQUIRES_EQUIVALENCE"));
  const consumedPlans = new Set([...directPlanUse.keys(), ...assessment.equivalence_groups.map((group) => group.verification_id)]);
  if (assessment.verification_plans.some((plan) => !consumedPlans.has(plan.id))) reasons.push(issue("VERIFICATION_PLAN_ORPHANED"));
  if (assessment.equivalence_groups.some((group) => directPlanUse.has(group.verification_id))) reasons.push(issue("VERIFICATION_REUSE_BINDING_INVALID"));

  const actualsValid = uniqueIds(assessment.actual_verifications, "verification_id") && assessment.actual_verifications.every((actual) =>
    exactKeys(actual, ["verification_id", "outcome", "executed_source_identity", "evidence_ref"]) &&
    nonBlank(actual.verification_id) && actual.outcome === "passed" && nonBlank(actual.executed_source_identity) && nonBlank(actual.evidence_ref));
  if (!actualsValid) { reasons.push(issue("ACTUAL_VERIFICATIONS_INVALID")); return; }
  if (phase === "pre-build" && assessment.actual_verifications.length > 0) reasons.push(issue("PREBUILD_EXECUTION_NOT_ALLOWED"));
  if (phase !== "discovery" && (capture.unknown_boundaries.some((boundary) => boundary.material) || assessment.impact_scope === "unresolved")) reasons.push(issue("MATERIAL_IMPACT_UNRESOLVED"));
  if (phase === "pre-build" && assessment.obligations.some((obligation) => obligation.disposition === "blocked")) reasons.push(issue("BLOCKED_IMPACT_UNRESOLVED"));
  if (phase === "completion") {
    if (assessment.obligations.some((obligation) => ["waived", "blocked"].includes(obligation.disposition))) reasons.push(issue("UNVERIFIED_RESIDUAL_RISK"));
    const actuals = indexBy(assessment.actual_verifications, "verification_id");
    const needed = new Map(assessment.obligations.flatMap((obligation) => obligation.verification_id ? [[obligation.verification_id, obligation.requirement_id]] : obligation.equivalence_group_id ? [[groups.get(obligation.equivalence_group_id)?.verification_id, obligation.requirement_id]] : []));
    for (const [verificationId, requirementId] of needed) if (!actuals.has(verificationId) || actuals.get(verificationId).executed_source_identity !== plans.get(verificationId)?.source_identity || actuals.get(verificationId).executed_source_identity !== expectedRequirements.get(requirementId)?.verification_source_id) reasons.push(issue("EXECUTED_VERIFICATION_MISSING_OR_STALE"));
    if (actuals.size !== consumedPlans.size || [...actuals.keys()].some((id) => !consumedPlans.has(id))) reasons.push(issue("ACTUAL_VERIFICATION_ORPHANED"));
  }
}

function uniqueStrings(values) {
  return values.every(nonBlank) && new Set(values).size === values.length;
}

function validateReview(review, assessment, expected, reasons) {
  if (!exactKeys(review, ["schema_version", "capture_id", "snapshot", "review_source", "bindings"]) || review.schema_version !== "change-impact-review/v1" ||
      !nonBlank(review.capture_id) || !validSnapshot(review.snapshot) || !Array.isArray(review.bindings)) { reasons.push(issue("REVIEW_SCHEMA_INVALID")); return; }
  if (review.capture_id !== expected.capture_id || !sameSnapshot(review.snapshot, expected.snapshot)) reasons.push(issue("REVIEW_CONTEXT_STALE"));
  const source = review.review_source;
  const expectedSource = expected.review_context;
  if (!exactKeys(source, ["scope_manifest_id", "coverage_ledger_id", "review_snapshot_id", "snapshot_id"]) ||
      source.scope_manifest_id !== expectedSource.scope_manifest_id || source.coverage_ledger_id !== expectedSource.coverage_ledger_id ||
      source.review_snapshot_id !== expectedSource.review_snapshot_id || source.snapshot_id !== expectedSource.snapshot_id) reasons.push(issue("REVIEW_SOURCE_STALE_OR_WRONG"));
  if (!review.bindings.every((binding) => exactKeys(binding, ["obligation_id", "requirement_id", "scope_item_id", "coverage_concern_id"]) &&
      nonBlank(binding.obligation_id) && nonBlank(binding.requirement_id) && nonBlank(binding.scope_item_id) && nonBlank(binding.coverage_concern_id)) ||
      !uniqueStrings(review.bindings.map((binding) => binding.obligation_id)) || !uniqueStrings(review.bindings.map((binding) => binding.requirement_id))) { reasons.push(issue("REVIEW_BINDINGS_INVALID")); return; }
  const obligations = indexBy(assessment.obligations);
  const expectedBindings = indexBy(expectedSource.required_bindings, "requirement_id");
  if (review.bindings.length !== obligations.size || review.bindings.length !== expectedBindings.size || review.bindings.some((binding) =>
    !obligations.has(binding.obligation_id) || obligations.get(binding.obligation_id).requirement_id !== binding.requirement_id ||
    !expectedBindings.has(binding.requirement_id) || expectedBindings.get(binding.requirement_id).scope_item_id !== binding.scope_item_id ||
    expectedBindings.get(binding.requirement_id).coverage_concern_id !== binding.coverage_concern_id)) reasons.push(issue("REVIEW_OBLIGATION_BINDING_INCOMPLETE"));
}

function validate({ phase, capture, expected, assessment, review }) {
  const reasons = [];
  if (!PHASES.has(phase)) return { valid: false, complete: false, phase: null, reasons: [issue("PHASE_INVALID")] };
  validateExpected(expected, phase, reasons);
  if (reasons.length === 0) validateCapture(capture, expected, reasons);
  if (phase !== "discovery" && reasons.length === 0) validateAssessment(assessment, capture, expected, phase, reasons);
  if (phase === "completion" && reasons.length === 0) validateReview(review, assessment, expected, reasons);
  return { valid: reasons.length === 0, complete: phase === "completion" && reasons.length === 0, phase, reasons };
}

function parseArgs(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index]; const value = argv[index + 1];
    if (!key || !["--phase", "--capture", "--expected", "--assessment", "--review"].includes(key) || value === undefined || options[key]) throw new Error("CLI_USAGE_INVALID");
    options[key] = value;
  }
  if (!options["--phase"] || !options["--capture"] || !options["--expected"] ||
      (options["--phase"] !== "discovery" && !options["--assessment"]) ||
      (options["--phase"] === "completion" && !options["--review"])) throw new Error("CLI_USAGE_INVALID");
  return options;
}

function main() {
  try {
    if (Number(process.versions.node.split(".")[0]) < 22) throw new Error("RUNTIME_NODE22_OR_NEWER_REQUIRED");
    const options = parseArgs(process.argv.slice(2));
    const result = validate({
      phase: options["--phase"],
      capture: readDocument(options["--capture"]),
      expected: readDocument(options["--expected"]),
      assessment: options["--assessment"] ? readDocument(options["--assessment"]) : undefined,
      review: options["--review"] ? readDocument(options["--review"]) : undefined,
    });
    process.stdout.write(`${JSON.stringify(result)}\n`);
    process.exitCode = result.valid ? 0 : 1;
  } catch (error) {
    const code = SAFE_ERROR_CODES.has(error?.message) ? error.message : "VALIDATOR_INPUT_ERROR";
    process.stdout.write(`${JSON.stringify({ valid: false, complete: false, phase: null, reasons: [issue(code)] })}\n`);
    process.exitCode = 2;
  }
}

if (require.main === module) main();

module.exports = { validate, readDocument, MAX_BYTES };
