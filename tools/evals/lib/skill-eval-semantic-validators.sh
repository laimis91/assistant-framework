#!/usr/bin/env bash
# Closed-world semantic validators used by provider-neutral local eval grading.

semantic_validator_id_for_case() {
    local fixture_file="$1"
    local case_id="$2"

    jq -r --arg id "$case_id" '.cases[] | select(.id == $id) | .semantic_validator // empty' "$fixture_file"
}

assistant_research_five_lens_v3_valid() {
    local response_path="$1"

    node - "$response_path" <<'NODE'
const crypto = require("crypto");
const fs = require("fs");
const net = require("net");
const responsePath = process.argv[2];
const lenses = ["practitioner", "academic_or_technical_expert", "skeptic", "economist_or_incentives_analyst", "historian_or_pattern_matcher"];
const resultKeys = ["core_position", "lens_question", "answer_or_gap", "sources_or_verified_urls", "follow_ups", "evidence_status", "likely_blind_spot", "unique_insight", "confidence", "gaps"];
const acceptedKeys = ["lens_kind", "assignment_id", "lens_result_digest", ...resultKeys];
const errors = [];
const fail = message => errors.push(message);
const nonblank = value => typeof value === "string" && value.trim().length > 0;
const exactKeys = (value, keys, label) => {
  if (!value || typeof value !== "object" || Array.isArray(value) || Object.keys(value).sort().join("|") !== [...keys].sort().join("|")) {
    fail(`${label}: exact keys required`);
    return false;
  }
  return true;
};
const allowedKeys = (value, keys, label) => {
  if (!value || typeof value !== "object" || Array.isArray(value) || Object.keys(value).some(key => !keys.includes(key))) {
    fail(`${label}: unsupported field`);
    return false;
  }
  return true;
};
function validateUnicode(value, path = "$") {
  if (typeof value === "string") {
    for (let index = 0; index < value.length; index += 1) {
      const code = value.charCodeAt(index);
      if (code >= 0xd800 && code <= 0xdbff) {
        if (index + 1 >= value.length || value.charCodeAt(index + 1) < 0xdc00 || value.charCodeAt(index + 1) > 0xdfff) fail(`${path}: unpaired high surrogate`);
        else index += 1;
      } else if (code >= 0xdc00 && code <= 0xdfff) fail(`${path}: unpaired low surrogate`);
    }
  } else if (Array.isArray(value)) value.forEach((item, index) => validateUnicode(item, `${path}[${index}]`));
  else if (value && typeof value === "object") Object.entries(value).forEach(([key, item]) => { validateUnicode(key, `${path}.<key>`); validateUnicode(item, `${path}.${key}`); });
}
function jcs(value) {
  if (Array.isArray(value)) return `[${value.map(jcs).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${jcs(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
}
function digest(value) {
  validateUnicode(value);
  return `sha256:${crypto.createHash("sha256").update(jcs(value), "utf8").digest("hex")}`;
}
const equal = (left, right) => {
  validateUnicode(left); validateUnicode(right);
  return jcs(left) === jcs(right);
};
const contentDigest = value => typeof value === "string" && /^sha256:[0-9a-f]{64}$/.test(value);
const exactLensSet = values => Array.isArray(values) && values.length === lenses.length && values.every(value => lenses.includes(value)) && new Set(values).size === lenses.length;
function budgetValid(budget, tier) {
  const keys = ["per_lens_max_queries", "per_lens_max_sources", "per_lens_max_minutes", "overall_max_queries", "overall_max_sources", "overall_max_minutes", "stop_condition"];
  if (!exactKeys(budget, keys, "search resource budget")) return false;
  const expected = {
    standard: [3, 4, 10, 15, 20, 50],
    extensive: [5, 6, 15, 25, 30, 75],
    deep: [8, 10, 25, 40, 50, 125]
  }[tier];
  const fields = ["per_lens_max_queries", "per_lens_max_sources", "per_lens_max_minutes", "overall_max_queries", "overall_max_sources", "overall_max_minutes"];
  if (!expected || !fields.every((key, index) => budget[key] === expected[index]) || budget.stop_condition !== "saturation_or_hard_ceiling") {
    fail("search resource budget: canonical tier mapping required");
    return false;
  }
  return true;
}
function usageValid(usage, budget, result, label) {
  const keys = ["actual_queries", "actual_sources", "elapsed_minutes", "termination_state", "exhausted_dimensions", "exhaustion_gap", "confidence_downgraded"];
  allowedKeys(usage, keys, label);
  if (!usage || !["actual_queries", "actual_sources", "elapsed_minutes"].every(key => Number.isInteger(usage[key]) && usage[key] >= 0)) { fail(`${label}: non-negative integer actuals required`); return false; }
  if (usage.actual_queries > budget.per_lens_max_queries || usage.actual_sources > budget.per_lens_max_sources || usage.elapsed_minutes > budget.per_lens_max_minutes) fail(`${label}: per-lens ceiling exceeded`);
  const dimensions = usage.exhausted_dimensions;
  const ceiling = {queries: [usage.actual_queries, budget.per_lens_max_queries], sources: [usage.actual_sources, budget.per_lens_max_sources], elapsed_time: [usage.elapsed_minutes, budget.per_lens_max_minutes]};
  const dimensionsValid = Array.isArray(dimensions) && dimensions.length === new Set(dimensions).size && dimensions.every(dimension => Object.hasOwn(ceiling, dimension));
  const complete = ["completed_scope", "saturation"].includes(usage.termination_state);
  const exhausted = usage.termination_state === "ceiling_exhausted";
  if (!dimensionsValid || (!complete && !exhausted)) fail(`${label}: invalid termination state`);
  if (complete && (dimensions.length !== 0 || Object.hasOwn(usage, "exhaustion_gap") || usage.confidence_downgraded !== false)) fail(`${label}: completed/saturation truth table`);
  if (exhausted && (!(dimensions.length > 0 && dimensions.every(dimension => ceiling[dimension][0] === ceiling[dimension][1])) || !nonblank(usage.exhaustion_gap) || usage.confidence_downgraded !== true || result.confidence !== "low" || !Array.isArray(result.gaps) || !result.gaps.includes(usage.exhaustion_gap))) fail(`${label}: ceiling exhaustion truth table`);
  return true;
}
function overallUsageValid(overall, budget, records, mode, process) {
  const keys = ["actual_queries", "actual_sources", "elapsed_minutes", "termination_state", "exhausted_dimensions", "exhaustion_gap", "confidence_downgraded"];
  allowedKeys(overall, keys, "overall usage");
  if (!overall || !["actual_queries", "actual_sources", "elapsed_minutes"].every(key => Number.isInteger(overall[key]) && overall[key] >= 0)) { fail("overall usage: non-negative integer actuals required"); return; }
  const querySum = records.reduce((sum, record) => sum + (record.search_resource_usage?.actual_queries ?? 0), 0);
  const sourceSum = records.reduce((sum, record) => sum + (record.search_resource_usage?.actual_sources ?? 0), 0);
  if (overall.actual_queries !== querySum || overall.actual_sources !== sourceSum || overall.actual_queries > budget.overall_max_queries || overall.actual_sources > budget.overall_max_sources || overall.elapsed_minutes > budget.overall_max_minutes) fail("overall usage: sums or ceilings");
  let elapsedLowerBound;
  if (mode === "sequential_fallback") elapsedLowerBound = records.reduce((sum, record) => sum + (record.search_resource_usage?.elapsed_minutes ?? 0), 0);
  else {
    const waves = process.wave_coverage;
    if (!Array.isArray(waves) || waves.length === 0) { fail("delegated schedule: wave coverage required"); elapsedLowerBound = Infinity; }
    else {
      const waveIds = new Set(); const covered = [];
      elapsedLowerBound = 0;
      for (const wave of waves) {
        if (!exactKeys(wave, ["wave_id", "capacity", "lens_kinds"], "wave coverage") || !nonblank(wave.wave_id) || !Number.isInteger(wave.capacity) || wave.capacity < 1 || !Array.isArray(wave.lens_kinds) || wave.lens_kinds.length === 0) { fail("delegated schedule: invalid wave"); continue; }
        if (waveIds.has(wave.wave_id) || new Set(wave.lens_kinds).size !== wave.lens_kinds.length || wave.lens_kinds.length > wave.capacity) fail("delegated schedule: duplicate or over-capacity wave");
        waveIds.add(wave.wave_id); covered.push(...wave.lens_kinds);
        const members = records.filter(record => record.wave_id === wave.wave_id);
        if (members.length !== wave.lens_kinds.length || !equal(members.map(record => record.lens_kind).sort(), [...wave.lens_kinds].sort())) fail("delegated schedule: record coverage");
        elapsedLowerBound += Math.max(0, ...members.map(record => record.search_resource_usage?.elapsed_minutes ?? 0));
      }
      if (!exactLensSet(covered)) fail("delegated schedule: lenses must be exhaustive and disjoint");
    }
  }
  if (overall.elapsed_minutes < elapsedLowerBound) fail("overall usage: schedule-aware elapsed lower bound");
  const dimensions = overall.exhausted_dimensions;
  const ceiling = {queries: [overall.actual_queries, budget.overall_max_queries], sources: [overall.actual_sources, budget.overall_max_sources], elapsed_time: [overall.elapsed_minutes, budget.overall_max_minutes]};
  const dimensionsValid = Array.isArray(dimensions) && dimensions.length === new Set(dimensions).size && dimensions.every(dimension => Object.hasOwn(ceiling, dimension));
  const complete = ["completed_scope", "saturation"].includes(overall.termination_state);
  const exhausted = overall.termination_state === "ceiling_exhausted";
  if (!dimensionsValid || (!complete && !exhausted)) fail("overall usage: invalid termination state");
  if (complete && (dimensions.length !== 0 || Object.hasOwn(overall, "exhaustion_gap") || overall.confidence_downgraded !== false)) fail("overall usage: completed/saturation truth table");
  if (exhausted && (!(dimensions.length > 0 && dimensions.every(dimension => ceiling[dimension][0] === ceiling[dimension][1])) || !nonblank(overall.exhaustion_gap) || overall.confidence_downgraded !== true)) fail("overall usage: ceiling exhaustion truth table");
}
function publicUrlValid(value) {
  if (!nonblank(value) || /(?:^|[?&#])(?:token|secret|key|password|email)=/i.test(value)) return false;
  let url; try { url = new URL(value); } catch { return false; }
  if (url.protocol !== "https:" || url.username || url.password || url.port) return false;
  const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, "");
  if (!host || host.endsWith(".") || host === "localhost" || /(?:\.invalid|\.localhost|\.test|\.example|\.internal)$/.test(host) || /^(?:0x|0)[0-9a-f]+$/i.test(host) || /^[0-9]+$/.test(host)) return false;
  if (net.isIP(host) === 4) {
    if (host.split(".").some(part => part.length > 1 && part.startsWith("0"))) return false;
    const [a, b, c] = host.split(".").map(Number);
    if (a === 0 || a === 10 || a === 127 || a >= 224 || (a === 100 && b >= 64 && b <= 127) || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 192 && b === 0 && (c === 0 || c === 2)) || (a === 198 && (b === 18 || b === 19)) || (a === 198 && b === 51 && c === 100) || (a === 203 && b === 0 && c === 113)) return false;
  }
  if (net.isIP(host) === 6) {
    if (host === "::" || host === "::1" || host.startsWith("fc") || host.startsWith("fd") || host.startsWith("fe8") || host.startsWith("fe9") || host.startsWith("fea") || host.startsWith("feb") || host.startsWith("ff") || host.startsWith("::ffff:") || host.startsWith("2001:db8:")) return false;
  }
  return true;
}
function sourceReferencesValid(sources, evidenceStatus, gaps, label) {
  if (!Array.isArray(sources) || !sources.every(nonblank)) { fail(`${label}: nonblank source identifiers required`); return; }
  if (!['source_backed', 'inference_only', 'unresolved'].includes(evidenceStatus)) fail(`${label}: evidence status`);
  if (!Array.isArray(gaps) || !gaps.every(nonblank)) fail(`${label}: nonblank gaps array required`);
  if (evidenceStatus === 'source_backed' && sources.length === 0) fail(`${label}: source-backed result requires a source`);
  if (['inference_only', 'unresolved'].includes(evidenceStatus) && sources.length === 0 && gaps.length === 0) fail(`${label}: empty non-source evidence requires a gap`);
  for (const source of sources) {
    if (/\.\.|(?:^|[\\/])~?(?:Users|home|private|var)(?:[\\/]|$)|(?:token|secret|password|api[_-]?key|email)=/i.test(source)) fail(`${label}: unsafe source reference`);
    let parsed; try { parsed = new URL(source); } catch { parsed = undefined; }
    if ((parsed && ["http:", "https:"].includes(parsed.protocol)) || /^[A-Za-z][A-Za-z0-9+.-]*:\/\//.test(source)) {
      if (!publicUrlValid(source)) fail(`${label}: non-public URL source`);
    }
  }
}
function acceptedResultValid(result, label) {
  if (!["core_position", "lens_question", "answer_or_gap", "likely_blind_spot", "unique_insight"].every(key => nonblank(result[key])) || !["high", "medium", "low"].includes(result.confidence)) fail(`${label}: required result fields`);
  sourceReferencesValid(result.sources_or_verified_urls, result.evidence_status, result.gaps, label);
  if (!Array.isArray(result.follow_ups) || result.follow_ups.length === 0) { fail(`${label}: follow-ups required`); return; }
  for (const followUp of result.follow_ups) {
    const followUpKeys = followUp?.decision === "follow_up" ? ["decision", "question", "answer_or_gap", "sources_or_verified_urls", "evidence_status"] : ["decision", "answer_or_gap", "sources_or_verified_urls", "evidence_status"];
    if (!exactKeys(followUp, followUpKeys, `${label} follow-up`) || !["follow_up", "none_needed"].includes(followUp.decision) || !nonblank(followUp.answer_or_gap) || (followUp.decision === "follow_up" && !nonblank(followUp.question))) fail(`${label}: follow-up shape`);
    sourceReferencesValid(followUp.sources_or_verified_urls, followUp.evidence_status, result.gaps, `${label} follow-up`);
  }
}
function validTimestamp(value) {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(value) && Number.isFinite(Date.parse(value));
}
function peerReviewValid(peer, mode, process, lensIdentities, rootPasses) {
  if (!peer || typeof peer !== "object" || peer.peer_review_execution_mode !== mode || !nonblank(peer.peer_review_assignment_id) || !["DONE", "DONE_WITH_CONCERNS", "NEEDS_CONTEXT", "BLOCKED"].includes(peer.status) || !["accepted", "accepted_with_concerns", "revise", "blocked"].includes(peer.verdict)) { fail("peer review: required status/binding"); return; }
  if (mode === "delegated") {
    if (!nonblank(peer.peer_reviewer_identity) || lensIdentities.has(peer.peer_reviewer_identity) || process.peer_reviewer_identity !== peer.peer_reviewer_identity) fail("peer review: distinct delegated identity");
  } else if (!nonblank(peer.peer_review_fallback_pass_id) || rootPasses.has(peer.peer_review_fallback_pass_id) || process.peer_review_fallback_pass_id !== peer.peer_review_fallback_pass_id || Object.hasOwn(peer, "peer_reviewer_identity")) fail("peer review: fresh fallback pass");
  const usable = ["DONE", "DONE_WITH_CONCERNS"].includes(peer.status);
  if (peer.status === "DONE" && peer.verdict !== "accepted") fail("peer review: DONE verdict");
  if (peer.status === "DONE_WITH_CONCERNS" && !["accepted_with_concerns", "revise"].includes(peer.verdict)) fail("peer review: DONE_WITH_CONCERNS verdict");
  if (!usable && peer.verdict !== "blocked") fail("peer review: blocked verdict");
  if (usable) {
    const usableFields = ["confidence_scores", "weakest_claim", "bias_or_lens_dominance", "missing_sixth_perspective", "falsification_test", "revised_recommendation_if_needed", "evidence"];
    if (!Array.isArray(peer.confidence_scores) || peer.confidence_scores.length === 0 || !peer.confidence_scores.every(nonblank) || !usableFields.slice(1, 6).every(field => nonblank(peer[field])) || !Array.isArray(peer.evidence) || peer.evidence.length === 0) fail("peer review: usable critique fields");
    for (const item of peer.evidence || []) if (!item || !nonblank(item.source) || !nonblank(item.detail) || !["source_backed", "inference_only", "unresolved"].includes(item.evidence_status)) fail("peer review: usable evidence");
  } else if (!Array.isArray(peer.open_questions) || peer.open_questions.length === 0 || !peer.open_questions.every(nonblank) || !nonblank(peer.status_detail)) fail("peer review: blocked context fields");
  if (peer.status === "BLOCKED" && (!["missing_review_context", "policy_blocked", "tool_failure"].includes(peer.blocker_type) || !Array.isArray(peer.blocker_evidence) || peer.blocker_evidence.length === 0 || !peer.blocker_evidence.every(nonblank))) fail("peer review: blocker fields");
  if (["accepted", "accepted_with_concerns"].includes(peer.verdict)) {
    if (!Array.isArray(peer.required_revisions) || peer.required_revisions.length !== 0 || Object.hasOwn(peer, "revision_disposition_id") || Object.hasOwn(peer, "revision_disposition")) fail("peer review: accepted revision closure");
  }
  if (peer.verdict === "revise") {
    if (!Array.isArray(peer.required_revisions) || peer.required_revisions.length === 0 || !peer.required_revisions.every(nonblank) || new Set(peer.required_revisions).size !== peer.required_revisions.length || !nonblank(peer.revision_disposition_id) || !Array.isArray(peer.revision_disposition) || peer.revision_disposition.length !== peer.required_revisions.length || process.peer_review_revision_disposition_id !== peer.revision_disposition_id) fail("peer review: revision closure required");
    const closed = new Set();
    for (const disposition of peer.revision_disposition || []) {
      if (!exactKeys(disposition, ["required_revision", "outcome", "closure_evidence"], "peer revision disposition") || !peer.required_revisions.includes(disposition.required_revision) || closed.has(disposition.required_revision) || !["applied", "claim_downgraded"].includes(disposition.outcome) || !nonblank(disposition.closure_evidence)) fail("peer review: invalid revision disposition");
      closed.add(disposition?.required_revision);
    }
    if (closed.size !== peer.required_revisions.length) fail("peer review: incomplete revision closure");
  }
}
let response;
try { response = JSON.parse(fs.readFileSync(responsePath, "utf8")); } catch { fail("response: valid JSON required"); }
if (response) {
  validateUnicode(response);
  if (response.research_method !== "five_lens_briefing") fail("response: five_lens_briefing required");
  const process = response.five_lens_process_evidence;
  const mode = process?.lens_execution_mode;
  if (!process || !["delegated", "sequential_fallback"].includes(mode)) fail("process: supported execution mode required");
  else {
    const records = Array.isArray(mode === "delegated" ? process.lens_dispatches : process.fallback_lens_passes) ? (mode === "delegated" ? process.lens_dispatches : process.fallback_lens_passes) : [];
    if (records.length !== 5) fail("process: exactly five lens records required");
    const packetSet = process.frozen_packet_set;
    const manifest = packetSet?.packet_manifest;
    const manifestShapeValid = Array.isArray(manifest) && manifest.length === 5 && manifest.every((packet, index) => exactKeys(packet, ["packet_id", "lens_kind", "content_digest"], `packet manifest entry ${index}`) && nonblank(packet.packet_id) && contentDigest(packet.content_digest));
    const packetSetKeys = ["packet_set_id", "packet_set_digest", "packet_ids", "packet_manifest_order", "packet_manifest", "packet_set_frozen_at", "pre_dispatch_record_id", "first_lens_execution_at", "first_lens_execution_evidence_ref"];
    const freezeProofValid = exactKeys(packetSet, packetSetKeys, "frozen packet set") && nonblank(packetSet.packet_set_id) && nonblank(packetSet.pre_dispatch_record_id) && nonblank(packetSet.first_lens_execution_evidence_ref) && validTimestamp(packetSet.packet_set_frozen_at) && validTimestamp(packetSet.first_lens_execution_at) && Date.parse(packetSet.packet_set_frozen_at) < Date.parse(packetSet.first_lens_execution_at);
    if (!freezeProofValid || !manifestShapeValid || !exactLensSet(manifest.map(packet => packet?.lens_kind)) || !equal(manifest.map(packet => packet?.packet_id), packetSet.packet_manifest_order) || !equal(packetSet.packet_ids, packetSet.packet_manifest_order) || !equal(process.frozen_assignment_packet_ids, packetSet.packet_manifest_order) || !contentDigest(packetSet.packet_set_digest) || packetSet.packet_set_digest !== digest(manifest)) fail("packet manifest: digest, projection, or freeze proof");
    const packets = new Map((Array.isArray(manifest) ? manifest : []).filter(packet => packet && typeof packet === "object").map(packet => [packet.packet_id, packet]));
    const accepted = Array.isArray(process.accepted_lens_results) ? process.accepted_lens_results : [];
    if (accepted.length !== 5 || !exactLensSet(accepted.map(result => result?.lens_kind))) fail("accepted ledger: exact five lenses required");
    const byLens = new Map(accepted.filter(result => result && typeof result === "object").map(result => [result.lens_kind, result]));
    const budget = process.search_resource_budget;
    budgetValid(budget, response.tier);
    const identities = new Set(); const rootPasses = new Set(); const assignmentIds = new Set();
    for (const record of records || []) {
      const label = `lens record ${record?.lens_kind || "unknown"}`;
      const recordKeys = mode === "delegated" ? ["lens_kind", "dispatch_identity", "assignment_id", "packet_id", "packet_set_id", "packet_content_digest", "lens_result_digest", "search_resource_usage", "wave_id", "return_validated"] : ["lens_kind", "assignment_id", "packet_id", "packet_set_id", "packet_content_digest", "lens_result_digest", "search_resource_usage", "root_pass_id", "return_validated"];
      if (!exactKeys(record, recordKeys, label)) continue;
      const result = byLens.get(record?.lens_kind);
      if (!result || !exactKeys(result, acceptedKeys, `accepted result ${record?.lens_kind || "unknown"}`)) continue;
      const lensResult = Object.fromEntries(resultKeys.map(key => [key, result[key]]));
      acceptedResultValid(result, `accepted result ${record.lens_kind}`);
      const packet = packets.get(record.packet_id);
      if (!contentDigest(result.lens_result_digest) || result.lens_result_digest !== digest(lensResult) || record.lens_result_digest !== result.lens_result_digest || record.assignment_id !== result.assignment_id) fail(`${label}: accepted result digest/binding`);
      if (!packet || !contentDigest(packet.content_digest) || record.packet_set_id !== packetSet.packet_set_id || record.packet_content_digest !== packet.content_digest || packet.lens_kind !== record.lens_kind) fail(`${label}: frozen packet binding`);
      if (record.return_validated !== true) fail(`${label}: return must be validated`);
      if (!nonblank(record.assignment_id) || assignmentIds.has(record.assignment_id)) fail(`${label}: unique assignment id`);
      assignmentIds.add(record.assignment_id);
      if (mode === "delegated") { if (!nonblank(record.dispatch_identity) || identities.has(record.dispatch_identity)) fail(`${label}: unique native identity`); identities.add(record.dispatch_identity); }
      else { if (!nonblank(record.root_pass_id) || rootPasses.has(record.root_pass_id)) fail(`${label}: unique fallback pass`); rootPasses.add(record.root_pass_id); }
      usageValid(record.search_resource_usage, budget || {}, lensResult, label);
      const perspective = (response.perspective_scan || []).find(item => item?.lens === record.lens_kind);
      const trace = (response.question_trace || []).find(item => item?.lens === record.lens_kind);
      if (!perspective || !equal(perspective, {lens: result.lens_kind, assignment_id: result.assignment_id, lens_result_digest: result.lens_result_digest, core_position: result.core_position, sources_or_verified_urls: result.sources_or_verified_urls, likely_blind_spot: result.likely_blind_spot, unique_insight: result.unique_insight, confidence: result.confidence})) fail(`${label}: perspective projection`);
      if (!trace || !equal(trace, {lens: result.lens_kind, assignment_id: result.assignment_id, lens_result_digest: result.lens_result_digest, question: result.lens_question, answer: result.answer_or_gap, sources_or_verified_urls: result.sources_or_verified_urls, follow_ups: result.follow_ups, evidence_status: result.evidence_status})) fail(`${label}: question trace projection`);
    }
    if (!exactLensSet((records || []).map(record => record?.lens_kind))) fail("process: records must cover each lens once");
    overallUsageValid(process.overall_resource_usage, budget || {}, records || [], mode, process);
    if (process.root_synthesis_ownership !== "orchestrator_only") fail("process: root synthesis ownership");
    if (mode === "delegated") {
      if (process.peer_review_execution_mode !== "delegated" || process.reduced_independence !== false || !Array.isArray(process.subagent_trigger_scope) || process.subagent_trigger_scope.length === 0 || !process.subagent_trigger_scope.every(nonblank)) fail("process: delegated lifecycle binding");
    } else if (process.peer_review_execution_mode !== "sequential_fallback" || process.reduced_independence !== true || ![process.lens_fallback_evidence, process.peer_review_fallback_evidence].every(evidence => evidence && nonblank(evidence.basis) && nonblank(evidence.detail) && nonblank(evidence.evidence_ref))) fail("process: fallback evidence binding");
    peerReviewValid(response.peer_review, mode, process, identities, rootPasses);
  }
}
if (errors.length) {
  console.error(`five-lens semantic validation: ${[...new Set(errors)].slice(0, 12).join("; ")}`);
  process.exitCode = 1;
}
NODE
}

run_semantic_validator() {
    local validator_id="$1"
    local response_path="$2"

    case "$validator_id" in
        assistant-research.five_lens_v3) assistant_research_five_lens_v3_valid "$response_path" ;;
        *)
            echo "Unknown semantic validator: $validator_id" >&2
            return 1
            ;;
    esac
}
