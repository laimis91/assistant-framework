research_jcs_node() {
    local operation="$1"
    shift

    node - "$operation" "$@" <<'NODE'
const crypto = require("crypto");
const fs = require("fs");
const net = require("net");
const operation = process.argv[2];
const args = process.argv.slice(3);
const lenses = ["practitioner", "academic_or_technical_expert", "skeptic", "economist_or_incentives_analyst", "historian_or_pattern_matcher"];
function assertUnicodeScalars(value) {
  if (typeof value === "string") {
    for (let index = 0; index < value.length; index += 1) {
      const codeUnit = value.charCodeAt(index);
      if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
        const next = value.charCodeAt(index + 1);
        if (!Number.isInteger(next) || next < 0xdc00 || next > 0xdfff) throw new Error("JCS rejects an unpaired high surrogate");
        index += 1;
      } else if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
        throw new Error("JCS rejects an unpaired low surrogate");
      }
    }
  } else if (Array.isArray(value)) {
    value.forEach(assertUnicodeScalars);
  } else if (value && typeof value === "object") {
    Object.entries(value).forEach(([key, child]) => { assertUnicodeScalars(key); assertUnicodeScalars(child); });
  }
}
function jcs(value) {
  if (Array.isArray(value)) return `[${value.map(jcs).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${jcs(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
}
function canonical(value) { assertUnicodeScalars(value); return jcs(value); }
function digest(value) { return `sha256:${crypto.createHash("sha256").update(canonical(value), "utf8").digest("hex")}`; }
function equal(left, right) { return canonical(left) === canonical(right); }
const lensResultFields = ["core_position", "lens_question", "answer_or_gap", "sources_or_verified_urls", "follow_ups", "evidence_status", "likely_blind_spot", "unique_insight", "confidence", "gaps"];
function lensResultBody(result) { return Object.fromEntries(lensResultFields.map(key => [key, result[key]])); }
function usage(mode, lens, tier) {
  if (mode === "delegated") return {actual_queries: tier === "standard" ? 2 : 3, actual_sources: tier === "standard" ? 3 : 4, elapsed_minutes: 10, termination_state: "saturation", exhausted_dimensions: [], confidence_downgraded: false};
  const gap = `Query, source, and time ceilings reached before confirming ${lens} coverage.`;
  return {actual_queries: 5, actual_sources: 6, elapsed_minutes: 15, termination_state: "ceiling_exhausted", exhausted_dimensions: ["queries", "sources", "elapsed_time"], exhaustion_gap: gap, confidence_downgraded: true};
}
function lensResult(mode, lens) {
  const fallback = mode === "sequential_fallback";
  const gap = `Query, source, and time ceilings reached before confirming ${lens} coverage.`;
  return {
    core_position: fallback ? `Unresolved position for ${lens}` : `Position for ${lens}`,
    lens_question: `Question for ${lens}`,
    answer_or_gap: fallback ? `Unresolved answer for ${lens}` : `Answer for ${lens}`,
    sources_or_verified_urls: fallback ? [] : [`source:research-corpus:${lens}`],
    follow_ups: [{decision: "none_needed", answer_or_gap: fallback ? `No additional follow-up after ceilings for ${lens}` : `No material follow-up for ${lens}`, sources_or_verified_urls: fallback ? [] : [`source:research-corpus:${lens}`], evidence_status: fallback ? "unresolved" : "source_backed", gaps: fallback ? [gap] : []}],
    evidence_status: fallback ? "unresolved" : "source_backed",
    likely_blind_spot: fallback ? `Unverified source coverage for ${lens}` : `Blind spot for ${lens}`,
    unique_insight: fallback ? `Fallback insight for ${lens}` : `Insight for ${lens}`,
    confidence: fallback ? "low" : "medium",
    gaps: fallback ? [gap] : []
  };
}
function packet(mode, lens, ordinal, tier) {
  const budget = tier === "standard" ? {per_lens_max_queries: 3, per_lens_max_sources: 4, per_lens_max_minutes: 10, overall_max_queries: 15, overall_max_sources: 20, overall_max_minutes: 50, stop_condition: "saturation_or_hard_ceiling"} : {per_lens_max_queries: 5, per_lens_max_sources: 6, per_lens_max_minutes: 15, overall_max_queries: 25, overall_max_sources: 30, overall_max_minutes: 75, stop_condition: "saturation_or_hard_ceiling"};
  return {packet_id: `packet-${["practitioner", "academic", "skeptic", "economist", "historian"][ordinal]}`, packet_set_id: mode === "delegated" ? "packet-set-1" : "fallback-packet-set-1", question: "Should we adopt the tool?", tier, user_role_or_goal: "architecture decision", output_purpose: "Answer the research question", known_context: ["local fixture"], evidence_budget: "six sources", search_resource_budget: budget, source_policy: "public sources", isolation_policy: "sibling blind", lens_kind: lens, packet_frozen_at: "2026-09-03T10:00:00Z"};
}
function build(mode, report) {
  const lensMode = ["sequential_fallback", "sequential_fallback_revise"].includes(mode) ? "sequential_fallback" : "delegated";
  const peerMode = mode === "delegated_peer_fallback" || lensMode === "sequential_fallback" ? "sequential_fallback" : "delegated";
  const isFallback = lensMode === "sequential_fallback";
  const peerRevise = mode === "sequential_fallback_revise" || peerMode === "delegated";
  const requestedTier = mode === "quick_normalized" ? "quick" : "extensive";
  const effectiveTier = requestedTier === "quick" ? "standard" : "extensive";
  const packets = lenses.map((lens, index) => { const value = packet(lensMode, lens, index, effectiveTier); return {...value, content_digest: digest(value)}; });
  const manifest = packets.map(({packet_id, lens_kind, content_digest}) => ({packet_id, lens_kind, content_digest}));
  const records = lenses.map((lens, index) => {
    const assignment_id = isFallback ? `fallback-assignment-${index + 1}` : `assignment-${index + 1}`;
    const result = lensResult(lensMode, lens);
    const resultDigest = digest(result);
    const resourceUsage = usage(lensMode, lens, effectiveTier);
    const common = {lens_kind: lens, assignment_id, packet_id: packets[index].packet_id, packet_set_id: packets[index].packet_set_id, packet_content_digest: packets[index].content_digest, lens_result_digest: resultDigest, search_resource_usage: resourceUsage, return_validated: true};
    return isFallback ? {...common, root_pass_id: `root-pass-${index + 1}`} : {...common, dispatch_identity: `lens-native-${index + 1}`, wave_id: "wave-1"};
  });
  const overall = isFallback ? {actual_queries: 25, actual_sources: 30, elapsed_minutes: 75, termination_state: "ceiling_exhausted", exhausted_dimensions: ["queries", "sources", "elapsed_time"], exhaustion_gap: "Overall ceilings reached before cross-lens verification.", confidence_downgraded: true} : {actual_queries: effectiveTier === "standard" ? 10 : 15, actual_sources: effectiveTier === "standard" ? 15 : 20, elapsed_minutes: 10, termination_state: "saturation", exhausted_dimensions: [], confidence_downgraded: false};
  const accepted_lens_results = records.map(record => { const result = lensResult(lensMode, record.lens_kind); return {lens_kind: record.lens_kind, assignment_id: record.assignment_id, lens_result_digest: record.lens_result_digest, ...result}; });
  const provenance = {lens_execution_mode: lensMode, reduced_independence: isFallback, fallback_basis: isFallback ? "spawn_failure_or_unavailable" : "not_applicable", fallback_evidence_ref: isFallback ? "spawn-error-1" : "not_applicable"};
  const process = {lens_execution_mode: lensMode, peer_review_execution_mode: peerMode, subagent_policy_state: isFallback ? "subagents_unavailable" : "delegation_triggered", subagent_trigger_scope: isFallback ? undefined : ["five_lens_briefing"], reduced_independence: isFallback || peerMode === "sequential_fallback", tier_resolution: {requested_tier: requestedTier, effective_tier: effectiveTier, normalization_disclosure: requestedTier === "quick" ? "quick normalized to standard for five_lens_briefing" : "not_applicable"}, frozen_packet_set: {packet_set_id: packets[0].packet_set_id, packet_set_digest: digest(manifest), packet_ids: packets.map(p => p.packet_id), packet_manifest_order: packets.map(p => p.packet_id), packet_manifest: manifest, packet_set_frozen_at: "2026-09-03T10:00:00Z", pre_dispatch_record_id: "pre-dispatch-1", first_lens_execution_at: "2026-09-03T10:01:00Z", first_lens_execution_evidence_ref: "execution-log-1"}, frozen_assignment_packet_ids: packets.map(p => p.packet_id), frozen_assignment_packets: packets, accepted_lens_results, search_resource_budget: packets[0].search_resource_budget, overall_resource_usage: overall, root_synthesis_ownership: "orchestrator_only"};
  if (isFallback) Object.assign(process, {fallback_lens_passes: records, lens_fallback_evidence: {basis: "spawn_failure_or_unavailable", detail: "dispatch unavailable", evidence_ref: "spawn-error-1"}});
  else Object.assign(process, {lens_dispatches: records, wave_coverage: [{wave_id: "wave-1", capacity: 5, lens_kinds: lenses}]});
  if (peerMode === "sequential_fallback") Object.assign(process, {peer_review_assignment_id: isFallback ? "fallback-peer-assignment-1" : "peer-fallback-assignment-1", peer_review_fallback_pass_id: "peer-root-pass-1", peer_review_fallback_evidence: {basis: "spawn_failure_or_unavailable", detail: "peer dispatch unavailable", evidence_ref: "peer-spawn-error-1"}, ...(peerRevise ? {peer_review_revision_disposition_id: "revision-closure-1"} : {})});
  else Object.assign(process, {peer_review_assignment_id: "peer-assignment-1", peer_reviewer_identity: "peer-native-1", peer_review_revision_disposition_id: "revision-closure-1"});
  const peerUsableFields = {confidence_scores: ["medium"], weakest_claim: "The evidence base is limited to the frozen fixture.", bias_or_lens_dominance: "No lens dominates the root synthesis.", missing_sixth_perspective: "No additional perspective is required for this fixture.", falsification_test: "Compare against an independent source record.", revised_recommendation_if_needed: "Retain calibrated confidence.", evidence: [{source: "source:peer-review", detail: "Peer reviewed the accepted lens ledger.", evidence_status: "source_backed"}]};
  const perspective_scan = accepted_lens_results.map(result => ({lens: result.lens_kind, assignment_id: result.assignment_id, lens_result_digest: result.lens_result_digest, core_position: result.core_position, sources_or_verified_urls: result.sources_or_verified_urls, likely_blind_spot: result.likely_blind_spot, unique_insight: result.unique_insight, confidence: result.confidence}));
  const question_trace = accepted_lens_results.map(result => ({lens: result.lens_kind, assignment_id: result.assignment_id, lens_result_digest: result.lens_result_digest, question: result.lens_question, answer: result.answer_or_gap, sources_or_verified_urls: result.sources_or_verified_urls, follow_ups: result.follow_ups, evidence_status: result.evidence_status}));
  const gaps = isFallback ? ["Overall ceilings left source confirmation unresolved."] : [];
  const synthesis_briefing = {executive_summary: isFallback ? "The available process evidence is insufficient for adoption." : "The fixture supports a bounded verification step.", ranked_key_findings: ["All five lenses completed their assigned process.", isFallback ? "Ceilings exhausted before source confirmation." : "The accepted results retain their source identifiers.", "The recommendation remains calibrated to the evidence."], hidden_connection: "The frozen packet ledger makes synthesis traceable.", actionable_implication: "Run an independent source check before adopting the tool.", recommendation: "investigate_further", high_stakes_caveat: "This fixture is educational due diligence, not financial, legal, medical, or professional advice.", frontier_question: "Which independent source would most change the decision?"};
  const high_stakes_context = {applicable: true, caveat_or_not_applicable_reason: synthesis_briefing.high_stakes_caveat, user_context_status: "unresolved", user_context_basis: "No decision-specific user constraints were supplied."};
  const verified_source_evidence = [{claim: "Fixture decision evidence", source: "source:research-corpus:summary", verification_method: "local_repository", verification_reference: "skills/assistant-research/contracts/output.yaml", verification_detail: "Fixture-local stable reference."}];
  const peer_review_input_binding = {peer_review_assignment_id: process.peer_review_assignment_id, initial_synthesis: synthesis_briefing, validated_lens_results: accepted_lens_results, lens_execution_provenance: provenance, verified_source_evidence, verification_gaps: gaps, high_stakes_context};
  peer_review_input_binding.peer_review_input_digest = digest(peer_review_input_binding);
  process.peer_review_input_binding = peer_review_input_binding;
  process.final_synthesis_digest = digest(synthesis_briefing);
  const reviseFields = peerRevise ? {status: "DONE_WITH_CONCERNS", verdict: "revise", required_revisions: ["downgrade unsupported claim"], revision_disposition_id: "revision-closure-1", revision_disposition: [{required_revision: "downgrade unsupported claim", outcome: "claim_downgraded", closure_evidence: "claim confidence updated", resulting_synthesis_digest: process.final_synthesis_digest}]} : {status: "DONE", verdict: "accepted", required_revisions: []};
  const peer_review = peerMode === "sequential_fallback" ? {peer_review_execution_mode: peerMode, peer_review_assignment_id: process.peer_review_assignment_id, peer_review_fallback_pass_id: process.peer_review_fallback_pass_id, peer_review_input_digest: peer_review_input_binding.peer_review_input_digest, supported_recommendation: "investigate_further", ...reviseFields, ...peerUsableFields} : {peer_review_execution_mode: peerMode, peer_review_assignment_id: "peer-assignment-1", peer_reviewer_identity: "peer-native-1", peer_review_input_digest: peer_review_input_binding.peer_review_input_digest, supported_recommendation: "investigate_further", ...reviseFields, ...peerUsableFields};
  return {report, research_method: "five_lens_briefing", tier: effectiveTier, findings: isFallback ? [] : [{finding: "The evidence supports a calibrated investigation.", confidence: "medium", sources: ["source:research-corpus:summary"]}], conflicts: [], peer_review, five_lens_process_evidence: process, perspective_scan, question_trace, contradiction_map: {direct_conflicts: [], strongest_evidence: isFallback ? "No source-backed conclusion is available." : "Validated lens source identifiers.", weakest_evidence: isFallback ? "Ceiling-exhausted source coverage." : "Fixture-only evidence scope.", consensus: [isFallback ? "Further confirmation is required." : "Proceed only with verification."], biggest_unresolved_question: "Whether independent source confirmation changes the recommendation.", missing_angle_or_gap: isFallback ? "Independent source confirmation." : "Production evidence beyond the fixture."}, synthesis_briefing, summary: isFallback ? "Do not adopt until independent source confirmation is available." : "Investigate further before deciding whether to adopt the tool.", gaps};
}
function validate(response) {
  const errors = [];
  const expect = (condition, message) => { if (!condition) errors.push(message); };
  const exactKeys = (value, keys) => value && typeof value === "object" && !Array.isArray(value) && equal(Object.keys(value).sort(), [...keys].sort());
  const process = response.five_lens_process_evidence || {};
  const mode = process.lens_execution_mode;
  const peerMode = process.peer_review_execution_mode;
  const records = mode === "delegated" ? process.lens_dispatches : process.fallback_lens_passes;
  const budget = process.search_resource_budget || {};
  expect(Array.isArray(records) && records.length === 5, "records:exact-five");
  expect(mode === "delegated" || mode === "sequential_fallback", "process:execution-mode");
  if (mode === "delegated") {
    expect(!Object.hasOwn(process, "fallback_lens_passes"), "process:no-fallback-leakage");
    expect(process.subagent_policy_state === "delegation_triggered" && Array.isArray(process.subagent_trigger_scope) && process.subagent_trigger_scope.length > 0 && process.root_synthesis_ownership === "orchestrator_only", "lens:delegated-binding");
  } else {
    expect(!Object.hasOwn(process, "lens_dispatches") && process.root_synthesis_ownership === "orchestrator_only" && typeof process.lens_fallback_evidence?.detail === "string" && process.lens_fallback_evidence.detail.length > 0 && typeof process.lens_fallback_evidence?.evidence_ref === "string" && process.lens_fallback_evidence.evidence_ref.length > 0, "lens:fallback-binding");
  }
  const peer = response.peer_review || {};
  expect(peerMode === "delegated" || peerMode === "sequential_fallback", "peer:execution-mode");
  expect(peer.peer_review_execution_mode === peerMode && peer.peer_review_assignment_id === process.peer_review_assignment_id, "peer:assignment-binding");
  if (peerMode === "delegated") {
    expect(typeof process.peer_reviewer_identity === "string" && process.peer_reviewer_identity.length > 0 && peer.peer_reviewer_identity === process.peer_reviewer_identity && peer.verdict === "revise" && Array.isArray(peer.required_revisions) && peer.required_revisions.length > 0 && peer.revision_disposition_id === process.peer_review_revision_disposition_id && !Object.hasOwn(process, "peer_review_fallback_pass_id"), "peer:delegated-binding");
  } else {
    expect(!Object.hasOwn(process, "peer_reviewer_identity") && peer.peer_review_fallback_pass_id === process.peer_review_fallback_pass_id && typeof process.peer_review_fallback_evidence?.detail === "string" && process.peer_review_fallback_evidence.detail.length > 0 && typeof process.peer_review_fallback_evidence?.evidence_ref === "string" && process.peer_review_fallback_evidence.evidence_ref.length > 0, "peer:fallback-binding");
  }
  const manifest = process.frozen_packet_set && process.frozen_packet_set.packet_manifest;
  const packetById = new Map((manifest || []).map(packet => [packet.packet_id, packet]));
  expect(Array.isArray(manifest) && manifest.length === 5 && equal(manifest.map(packet => packet.packet_id), process.frozen_packet_set?.packet_manifest_order) && equal(process.frozen_assignment_packet_ids, process.frozen_packet_set?.packet_manifest_order) && equal(process.frozen_packet_set?.packet_ids, process.frozen_packet_set?.packet_manifest_order) && Array.isArray(process.frozen_assignment_packets) && process.frozen_assignment_packets.length === 5 && process.frozen_assignment_packets.every(packet => equal(packet, {...packet, content_digest: digest(Object.fromEntries(Object.entries(packet).filter(([key]) => key !== "content_digest")))}) && Date.parse(packet.packet_frozen_at) <= Date.parse(process.frozen_packet_set?.packet_set_frozen_at) && Date.parse(packet.packet_frozen_at) < Date.parse(process.frozen_packet_set?.first_lens_execution_at)) && equal(process.frozen_assignment_packets.map(packet => ({packet_id: packet.packet_id, lens_kind: packet.lens_kind, content_digest: packet.content_digest})), manifest), "packet-manifest:projection");
  expect(process.frozen_packet_set && process.frozen_packet_set.packet_set_digest === digest(manifest), "packet-set:digest");
  const seen = new Set(), identities = new Set(), rootPasses = new Set();
  let querySum = 0, sourceSum = 0, elapsedSum = 0, elapsedMax = 0;
  for (const record of records || []) {
    const accepted = (process.accepted_lens_results || []).find(value => value.lens_kind === record.lens_kind);
    const result = accepted && lensResultBody(accepted);
    const usage = record.search_resource_usage;
    const packet = packetById.get(record.packet_id);
    expect(lenses.includes(record.lens_kind) && !seen.has(record.lens_kind), "record:lens-identity"); seen.add(record.lens_kind);
    expect(record.return_validated === true, "record:return-validated");
    if (mode === "delegated") { expect(typeof record.dispatch_identity === "string" && record.dispatch_identity.length > 0 && !identities.has(record.dispatch_identity), "record:dispatch-identity"); identities.add(record.dispatch_identity); }
    else { expect(!Object.hasOwn(record, "dispatch_identity") && typeof record.root_pass_id === "string" && record.root_pass_id.length > 0 && !rootPasses.has(record.root_pass_id), "record:fallback-identity"); rootPasses.add(record.root_pass_id); }
    expect(packet && typeof packet.content_digest === "string" && /^sha256:[0-9a-f]{64}$/.test(packet.content_digest), "packet:digest-format");
    expect(record.packet_content_digest === packet?.content_digest, "packet:binding");
    expect((process.accepted_lens_results || []).length === 5 && accepted && accepted.assignment_id === record.assignment_id && accepted.lens_result_digest === record.lens_result_digest && record.lens_result_digest === digest(result) && !Object.hasOwn(record, "accepted_worker_return"), "accepted-ledger:digest-and-projection");
    const perspective = (response.perspective_scan || []).find(value => value.lens === record.lens_kind);
    expect(perspective && perspective.assignment_id === record.assignment_id && perspective.lens_result_digest === record.lens_result_digest && perspective.core_position === result?.core_position && equal(perspective.sources_or_verified_urls, result?.sources_or_verified_urls) && perspective.likely_blind_spot === result?.likely_blind_spot && perspective.unique_insight === result?.unique_insight && perspective.confidence === result?.confidence, "perspective:projection");
    const trace = (response.question_trace || []).find(value => value.lens === record.lens_kind);
    expect(trace && trace.assignment_id === record.assignment_id && trace.lens_result_digest === record.lens_result_digest && trace.question === result?.lens_question && trace.answer === result?.answer_or_gap && equal(trace.sources_or_verified_urls, result?.sources_or_verified_urls) && equal(trace.follow_ups, result?.follow_ups) && trace.evidence_status === result?.evidence_status, "question-trace:projection");
    const sourceReferenceValid = source => {
      if (typeof source !== "string" || source.trim().length === 0) return false;
      if (!/^https?:\/\//i.test(source)) return true;
      let url; try { url = new URL(source); } catch { return false; }
      const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, "").replace(/\.$/, "");
      const discardOnly100Prefix = value => {
        if (net.isIP(value) !== 6) return false;
        const [left, right] = value.split("::");
        const leftGroups = left ? left.split(":") : [];
        const rightGroups = right === undefined ? [] : right ? right.split(":") : [];
        const groups = right === undefined ? leftGroups : [...leftGroups, ...Array(8 - leftGroups.length - rightGroups.length).fill("0"), ...rightGroups];
        return groups.length === 8 && [0x100, 0, 0, 0].every((expected, index) => Number.parseInt(groups[index], 16) === expected);
      };
      if (url.protocol !== "https:" || url.username || url.password || !host || ["localhost", "invalid", "local", "internal", "test", "example"].includes(host) || /(?:\.invalid|\.localhost|\.local|\.internal|\.test|\.example)$/.test(host) || /^[0-9]+$/.test(host) || (!net.isIP(host) && !host.includes("."))) return false;
      if (net.isIP(host) === 4) {
        const [a, b] = host.split(".").map(Number);
        return !(a === 0 || a === 10 || a === 127 || a >= 224 || (a === 100 && b >= 64 && b <= 127) || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) || (a === 192 && (b === 0 || b === 168 || b === 2)) || (a === 198 && (b === 18 || b === 19 || b === 51)) || (a === 203 && b === 0));
      }
      return !(net.isIP(host) === 6 && (host === "::1" || host.startsWith("fc") || host.startsWith("fd") || host.startsWith("fe8") || host.startsWith("fe9") || host.startsWith("fea") || host.startsWith("feb") || host.startsWith("::ffff:") || discardOnly100Prefix(host)));
    };
    const sourcesValid = (status, sources, gaps, label) => {
      const populated = Array.isArray(sources) && sources.length > 0;
      expect(Array.isArray(sources) && sources.every(sourceReferenceValid) && (status !== "source_backed" || populated) && (populated || (Array.isArray(gaps) && gaps.length > 0)), label);
    };
    sourcesValid(result?.evidence_status, result?.sources_or_verified_urls, result?.gaps, "sources:accepted-result");
    const followUps = result?.follow_ups;
    const noneNeeded = Array.isArray(followUps) ? followUps.filter(followUp => followUp?.decision === "none_needed") : [];
    expect(Array.isArray(followUps) && followUps.length > 0 && ((noneNeeded.length === 1 && followUps.length === 1) || (noneNeeded.length === 0 && followUps.every(followUp => followUp?.decision === "follow_up" && typeof followUp?.question === "string" && followUp.question.length > 0))), "follow-ups:exclusive-none-needed");
    for (const followUp of Array.isArray(followUps) ? followUps : []) { expect(Array.isArray(followUp?.gaps) && followUp.gaps.every(value => typeof value === "string" && value.length > 0), "follow-up:own-gaps"); sourcesValid(followUp?.evidence_status, followUp?.sources_or_verified_urls, followUp?.gaps, "sources:follow-up"); }
    const validUsage = usage && ["actual_queries","actual_sources","elapsed_minutes"].every(key => Number.isInteger(usage[key]) && usage[key] >= 0) && usage.actual_queries <= budget.per_lens_max_queries && usage.actual_sources <= budget.per_lens_max_sources && usage.elapsed_minutes <= budget.per_lens_max_minutes;
    expect(validUsage, "usage:per-lens-ceiling");
    const exhausted = usage?.termination_state === "ceiling_exhausted";
    const complete = ["completed_scope", "saturation"].includes(usage?.termination_state);
    const dimensions = usage?.exhausted_dimensions || [];
    const dimensionCeilings = {queries: [usage?.actual_queries, budget.per_lens_max_queries], sources: [usage?.actual_sources, budget.per_lens_max_sources], elapsed_time: [usage?.elapsed_minutes, budget.per_lens_max_minutes]};
    const dimensionsValid = dimensions.length === new Set(dimensions).size && dimensions.every(dimension => Object.hasOwn(dimensionCeilings, dimension));
    expect(dimensionsValid && ((complete && dimensions.length === 0 && !usage?.exhaustion_gap && usage?.confidence_downgraded === false) || (exhausted && dimensions.length > 0 && dimensions.every(dimension => dimensionCeilings[dimension][0] === dimensionCeilings[dimension][1]) && typeof usage?.exhaustion_gap === "string" && usage.exhaustion_gap.length > 0 && usage.confidence_downgraded === true && result?.confidence === "low" && result?.gaps?.includes(usage.exhaustion_gap))), "usage:termination-truth-table");
    querySum += usage?.actual_queries || 0; sourceSum += usage?.actual_sources || 0; elapsedSum += usage?.elapsed_minutes || 0; elapsedMax = Math.max(elapsedMax, usage?.elapsed_minutes || 0);
  }
  const assignments = new Set((Array.isArray(records) ? records : []).map(record => record?.assignment_id));
  expect(assignments.size === lenses.length && !assignments.has(undefined), "record:unique-assignments");
  const freeze = process.frozen_packet_set || {};
  const freezeTimestamp = Date.parse(freeze.packet_set_frozen_at);
  const firstLensTimestamp = Date.parse(freeze.first_lens_execution_at);
  expect(typeof freeze.pre_dispatch_record_id === "string" && freeze.pre_dispatch_record_id.length > 0 && typeof freeze.first_lens_execution_evidence_ref === "string" && freeze.first_lens_execution_evidence_ref.length > 0 && Number.isFinite(freezeTimestamp) && Number.isFinite(firstLensTimestamp) && freezeTimestamp < firstLensTimestamp, "packet-freeze:proof");
  const canonicalBudget = {standard: [3, 4, 10, 15, 20, 50], extensive: [5, 6, 15, 25, 30, 75], deep: [8, 10, 25, 40, 50, 125]}[response.tier];
  const budgetValues = [budget.per_lens_max_queries, budget.per_lens_max_sources, budget.per_lens_max_minutes, budget.overall_max_queries, budget.overall_max_sources, budget.overall_max_minutes];
  expect(Array.isArray(canonicalBudget) && equal(budgetValues, canonicalBudget) && budget.stop_condition === "saturation_or_hard_ceiling", "usage:canonical-budget");
  const tierResolution = process.tier_resolution;
  expect(exactKeys(tierResolution, ["requested_tier", "effective_tier", "normalization_disclosure"]) && ["quick", "standard", "extensive", "deep", "not_explicitly_requested"].includes(tierResolution?.requested_tier) && tierResolution?.effective_tier === response.tier && (["standard", "extensive", "deep"].includes(tierResolution?.effective_tier)) && ((tierResolution?.requested_tier === "quick" && tierResolution.effective_tier === "standard" && typeof tierResolution.normalization_disclosure === "string" && tierResolution.normalization_disclosure.length > 0 && tierResolution.normalization_disclosure !== "not_applicable") || (tierResolution?.requested_tier !== "quick" && tierResolution?.normalization_disclosure === "not_applicable")), "tier:resolution");
  let scheduleElapsedLowerBound = elapsedSum;
  if (mode === "delegated") {
    const waves = process.wave_coverage;
    const coveredLenses = new Set(), waveIds = new Set();
    let delegatedCriticalPath = 0;
    expect(Array.isArray(waves) && waves.length > 0, "waves:present");
    for (const wave of waves || []) {
      const waveLenses = wave?.lens_kinds;
      const waveValid = typeof wave?.wave_id === "string" && wave.wave_id.length > 0 && !waveIds.has(wave.wave_id) && Number.isInteger(wave.capacity) && wave.capacity >= 1 && Array.isArray(waveLenses) && waveLenses.length > 0 && waveLenses.length <= wave.capacity && waveLenses.length === new Set(waveLenses).size && waveLenses.every(lens => lenses.includes(lens) && !coveredLenses.has(lens));
      expect(waveValid, "waves:coverage");
      if (!waveValid) continue;
      waveIds.add(wave.wave_id);
      waveLenses.forEach(lens => coveredLenses.add(lens));
      const waveRecords = (Array.isArray(records) ? records : []).filter(record => record.wave_id === wave.wave_id);
      expect(equal(waveRecords.map(record => record.lens_kind), waveLenses), "waves:record-membership");
      if (waveRecords.length === waveLenses.length) delegatedCriticalPath += Math.max(...waveRecords.map(record => record.search_resource_usage?.elapsed_minutes || 0));
    }
    expect(coveredLenses.size === lenses.length && lenses.every(lens => coveredLenses.has(lens)) && (Array.isArray(records) ? records : []).every(record => waveIds.has(record.wave_id)), "waves:exhaustive-record-coverage");
    scheduleElapsedLowerBound = delegatedCriticalPath;
  }
  const overall = process.overall_resource_usage;
  const overallDimensions = overall?.exhausted_dimensions || [];
  const overallCeilings = {queries: [overall?.actual_queries, budget.overall_max_queries], sources: [overall?.actual_sources, budget.overall_max_sources], elapsed_time: [overall?.elapsed_minutes, budget.overall_max_minutes]};
  const overallDimensionsValid = overallDimensions.length === new Set(overallDimensions).size && overallDimensions.every(dimension => Object.hasOwn(overallCeilings, dimension));
  const overallComplete = ["completed_scope", "saturation"].includes(overall?.termination_state);
  const overallExhausted = overall?.termination_state === "ceiling_exhausted";
  const overallTruthTable = overallDimensionsValid && ((overallComplete && overallDimensions.length === 0 && !overall?.exhaustion_gap && overall?.confidence_downgraded === false) || (overallExhausted && overallDimensions.length > 0 && overallDimensions.every(dimension => overallCeilings[dimension][0] === overallCeilings[dimension][1]) && typeof overall?.exhaustion_gap === "string" && overall.exhaustion_gap.length > 0 && overall.confidence_downgraded === true));
  expect(overall && [overall.actual_queries, overall.actual_sources, overall.elapsed_minutes].every(Number.isInteger) && overall.actual_queries >= 0 && overall.actual_sources >= 0 && overall.elapsed_minutes >= 0 && overall.actual_queries === querySum && overall.actual_sources === sourceSum && overall.actual_queries <= budget.overall_max_queries && overall.actual_sources <= budget.overall_max_sources && overall.elapsed_minutes >= scheduleElapsedLowerBound && overall.elapsed_minutes <= budget.overall_max_minutes && overallTruthTable, "usage:overall-sums-schedule-wall-clock-and-termination");
  if (peerMode === "sequential_fallback") expect(!rootPasses.has(process.peer_review_fallback_pass_id), "peer:fallback-fresh-pass");
  const usablePeer = ["DONE", "DONE_WITH_CONCERNS"].includes(peer.status);
  const peerVerdictValid = (peer.status === "DONE" && peer.verdict === "accepted") || (peer.status === "DONE_WITH_CONCERNS" && ["accepted_with_concerns", "revise"].includes(peer.verdict)) || (["NEEDS_CONTEXT", "BLOCKED"].includes(peer.status) && peer.verdict === "blocked");
  const peerUsableFields = ["confidence_scores", "weakest_claim", "bias_or_lens_dominance", "missing_sixth_perspective", "falsification_test", "revised_recommendation_if_needed", "evidence"];
  const peerUsableComplete = peerUsableFields.every(field => Array.isArray(peer[field]) ? peer[field].length > 0 : typeof peer[field] === "string" && peer[field].length > 0);
  const revisions = peer.required_revisions;
  const revisionClosure = peer.revision_disposition;
  const reviseClosureValid = peer.verdict !== "revise" || (Array.isArray(revisions) && revisions.length > 0 && typeof peer.revision_disposition_id === "string" && peer.revision_disposition_id.length > 0 && Array.isArray(revisionClosure) && revisionClosure.length === revisions.length && revisionClosure.every(item => revisions.includes(item?.required_revision) && ["applied", "claim_downgraded"].includes(item?.outcome) && typeof item?.closure_evidence === "string" && item.closure_evidence.length > 0 && item.resulting_synthesis_digest === process.final_synthesis_digest));
  expect(usablePeer && peerVerdictValid && peerUsableComplete && Array.isArray(revisions) && (peer.verdict === "revise" ? revisions.length > 0 : revisions.length === 0) && reviseClosureValid, "peer:status-and-revision-truth-table");
  if (peerMode === "delegated") expect(!identities.has(peer.peer_reviewer_identity), "peer:distinct-from-lens-identities");
  expect(process.reduced_independence === (mode === "sequential_fallback" || peerMode === "sequential_fallback"), "process:reduced-independence");
  const nonblank = value => typeof value === "string" && value.length > 0;
  const sources = value => Array.isArray(value) && value.length > 0 && value.every(nonblank);
  const findings = response.findings;
  const sourceEmptyCompletion = (process.accepted_lens_results || []).every(result => Array.isArray(result?.sources_or_verified_urls) && result.sources_or_verified_urls.length === 0 && ["inference_only", "unresolved"].includes(result.evidence_status));
  const findingsValid = Array.isArray(findings) && ((findings.length > 0 && findings.every(finding => nonblank(finding?.finding) && ["high", "medium", "low"].includes(finding?.confidence) && sources(finding?.sources) && (!Object.hasOwn(finding, "verified_urls") || sources(finding.verified_urls)))) || (findings.length === 0 && sourceEmptyCompletion && Array.isArray(response.gaps) && response.gaps.length > 0));
  expect(findingsValid, "artifacts:findings");
  expect(Array.isArray(response.conflicts) && response.conflicts.every(conflict => ["claim_a", "source_a", "claim_b", "source_b", "assessment"].every(key => nonblank(conflict?.[key]))), "artifacts:conflicts");
  expect(Array.isArray(response.gaps) && response.gaps.every(nonblank) && nonblank(response.summary), "artifacts:gaps-and-summary");
  const contradiction = response.contradiction_map || {};
  expect(Array.isArray(contradiction.direct_conflicts) && contradiction.direct_conflicts.every(nonblank) && nonblank(contradiction.strongest_evidence) && nonblank(contradiction.weakest_evidence) && Array.isArray(contradiction.consensus) && contradiction.consensus.every(nonblank) && nonblank(contradiction.biggest_unresolved_question) && nonblank(contradiction.missing_angle_or_gap), "artifacts:contradiction-map");
  const synthesis = response.synthesis_briefing || {};
  expect(nonblank(synthesis.executive_summary) && Array.isArray(synthesis.ranked_key_findings) && synthesis.ranked_key_findings.length >= 3 && synthesis.ranked_key_findings.every(nonblank) && nonblank(synthesis.hidden_connection) && nonblank(synthesis.actionable_implication) && ["do", "wait", "avoid", "investigate_further"].includes(synthesis.recommendation) && nonblank(synthesis.frontier_question), "artifacts:synthesis-briefing");
  const binding = process.peer_review_input_binding;
  const bindingPreimage = binding && Object.fromEntries(Object.entries(binding).filter(([key]) => key !== "peer_review_input_digest"));
  const provenance = binding?.lens_execution_provenance;
  expect(exactKeys(binding, ["peer_review_input_digest", "peer_review_assignment_id", "initial_synthesis", "validated_lens_results", "lens_execution_provenance", "verified_source_evidence", "verification_gaps", "high_stakes_context"]) && binding.peer_review_input_digest === digest(bindingPreimage) && binding.peer_review_assignment_id === peer.peer_review_assignment_id && equal(binding.initial_synthesis, synthesis) && equal(binding.validated_lens_results, process.accepted_lens_results) && exactKeys(provenance, ["lens_execution_mode", "reduced_independence", "fallback_basis", "fallback_evidence_ref"]) && provenance.lens_execution_mode === mode && provenance.reduced_independence === (mode === "sequential_fallback") && ((mode === "delegated" && provenance.fallback_basis === "not_applicable" && provenance.fallback_evidence_ref === "not_applicable") || (mode === "sequential_fallback" && provenance.fallback_basis === process.lens_fallback_evidence?.basis && provenance.fallback_evidence_ref === process.lens_fallback_evidence?.evidence_ref)) && peer.peer_review_input_digest === binding.peer_review_input_digest && process.final_synthesis_digest === digest(synthesis) && peer.supported_recommendation === synthesis.recommendation, "peer-input-and-synthesis:binding");
  const context = binding?.high_stakes_context;
  const stronger = ["do", "wait", "avoid"].includes(synthesis.recommendation);
  const basis = response.high_stakes_recommendation_basis;
  expect(exactKeys(context, ["applicable", "caveat_or_not_applicable_reason", "user_context_status", "user_context_basis"]) && typeof context.applicable === "boolean" && nonblank(context.caveat_or_not_applicable_reason) && ["explicit", "unresolved", "not_applicable"].includes(context.user_context_status) && nonblank(context.user_context_basis) && ((context.applicable && ["explicit", "unresolved"].includes(context.user_context_status)) || (!context.applicable && context.caveat_or_not_applicable_reason === "not_applicable" && context.user_context_status === "not_applicable" && context.user_context_basis === "not_applicable")) && ((context.applicable && stronger && context.user_context_status === "explicit" && exactKeys(basis, ["recommendation", "verified_decision_critical_urls", "user_context_basis", "peer_review_input_digest", "peer_supported_recommendation"]) && basis.recommendation === synthesis.recommendation && Array.isArray(basis.verified_decision_critical_urls) && basis.verified_decision_critical_urls.length > 0 && basis.verified_decision_critical_urls.every(value => typeof value === "string" && /^https:\/\//.test(value)) && basis.user_context_basis !== "not_applicable" && basis.user_context_basis === context.user_context_basis && basis.peer_review_input_digest === binding?.peer_review_input_digest && basis.peer_supported_recommendation === peer.supported_recommendation && peer.supported_recommendation === synthesis.recommendation && (process.frozen_assignment_packets || []).every(packet => Array.isArray(packet?.known_context) && packet.known_context.includes(basis.user_context_basis))) || (!(context.applicable && stronger) && !Object.hasOwn(response, "high_stakes_recommendation_basis"))), "high-stakes:recommendation-basis");
  if (errors.length) { console.error([...new Set(errors)].join("\n")); return false; }
  return true;
}
function refreshDerived(response) {
  const process = response.five_lens_process_evidence || {};
  const retainedPackets = Array.isArray(process.frozen_assignment_packets) ? process.frozen_assignment_packets : [];
  if (retainedPackets.length > 0) {
    for (const packet of retainedPackets) packet.content_digest = digest(Object.fromEntries(Object.entries(packet).filter(([key]) => key !== "content_digest")));
    const manifest = retainedPackets.map(packet => ({packet_id: packet.packet_id, lens_kind: packet.lens_kind, content_digest: packet.content_digest}));
    if (process.frozen_packet_set) {
      process.frozen_packet_set.packet_ids = retainedPackets.map(packet => packet.packet_id);
      process.frozen_packet_set.packet_manifest_order = retainedPackets.map(packet => packet.packet_id);
      process.frozen_packet_set.packet_manifest = manifest;
      process.frozen_packet_set.packet_set_digest = digest(manifest);
    }
    process.frozen_assignment_packet_ids = retainedPackets.map(packet => packet.packet_id);
    for (const record of [...(process.lens_dispatches || []), ...(process.fallback_lens_passes || [])]) {
      const packet = retainedPackets.find(value => value.packet_id === record.packet_id);
      if (packet) record.packet_content_digest = packet.content_digest;
    }
  }
  const results = Array.isArray(process.accepted_lens_results) ? process.accepted_lens_results : [];
  const records = process.lens_execution_mode === "delegated" ? process.lens_dispatches : process.fallback_lens_passes;
  for (const result of results) {
    result.lens_result_digest = digest(lensResultBody(result));
    for (const record of records || []) if (record.lens_kind === result.lens_kind) { record.assignment_id = result.assignment_id; record.lens_result_digest = result.lens_result_digest; }
  }
  response.perspective_scan = results.map(result => ({lens: result.lens_kind, assignment_id: result.assignment_id, lens_result_digest: result.lens_result_digest, core_position: result.core_position, sources_or_verified_urls: result.sources_or_verified_urls, likely_blind_spot: result.likely_blind_spot, unique_insight: result.unique_insight, confidence: result.confidence}));
  response.question_trace = results.map(result => ({lens: result.lens_kind, assignment_id: result.assignment_id, lens_result_digest: result.lens_result_digest, question: result.lens_question, answer: result.answer_or_gap, sources_or_verified_urls: result.sources_or_verified_urls, follow_ups: result.follow_ups, evidence_status: result.evidence_status}));
  const binding = process.peer_review_input_binding;
  if (binding) {
    binding.peer_review_assignment_id = response.peer_review?.peer_review_assignment_id;
    binding.initial_synthesis = response.synthesis_briefing;
    binding.validated_lens_results = results;
    binding.lens_execution_provenance = {lens_execution_mode: process.lens_execution_mode, reduced_independence: process.lens_execution_mode === "sequential_fallback", fallback_basis: process.lens_execution_mode === "sequential_fallback" ? process.lens_fallback_evidence?.basis : "not_applicable", fallback_evidence_ref: process.lens_execution_mode === "sequential_fallback" ? process.lens_fallback_evidence?.evidence_ref : "not_applicable"};
    binding.peer_review_input_digest = digest(Object.fromEntries(Object.entries(binding).filter(([key]) => key !== "peer_review_input_digest")));
    if (response.peer_review) response.peer_review.peer_review_input_digest = binding.peer_review_input_digest;
  }
  process.final_synthesis_digest = digest(response.synthesis_briefing);
  for (const item of response.peer_review?.revision_disposition || []) item.resulting_synthesis_digest = process.final_synthesis_digest;
  return response;
}
if (operation === "canonical") process.stdout.write(canonical(JSON.parse(args[0])));
else if (operation === "digest") process.stdout.write(digest(JSON.parse(args[0])));
else if (operation === "build") process.stdout.write(JSON.stringify(build(args[0], args[1])));
else if (operation === "validate") process.exitCode = validate(JSON.parse(fs.readFileSync(args[0], "utf8"))) ? 0 : 1;
else if (operation === "refresh") process.stdout.write(JSON.stringify(refreshDerived(JSON.parse(fs.readFileSync(args[0], "utf8")))));
else throw new Error(`unknown research JCS operation: ${operation}`);
NODE
}

research_jcs_canonical_json() { local json; json="$(cat)"; research_jcs_node canonical "$json"; }
research_content_digest_json() { local json; json="$(cat)"; research_jcs_node digest "$json"; }
research_response_oracle_is_valid() { research_jcs_node validate "$1"; }
research_refresh_response_derivatives() { local response_path="$1"; research_jcs_node refresh "$response_path" >"$response_path.refresh" && mv "$response_path.refresh" "$response_path"; }

write_schema_valid_five_lens_eval_response() {
    local mode="$1"
    local response_path="$2"
    local case_id report

    if [[ "$mode" == "delegated" ]]; then
        case_id="five-lens-decision-briefing-uses-storm-style-workflow"
    elif [[ "$mode" == "quick_normalized" ]]; then
        case_id="five-lens-quick-normalizes-to-standard"
    elif [[ "$mode" == "delegated_peer_fallback" ]]; then
        case_id="five-lens-delegated-lenses-sequential-peer-fallback"
    else
        case_id="five-lens-sequential-fallback-preserves-process-evidence"
    fi
    report="$(jq -r --arg case_id "$case_id" '.cases[] | select(.id == $case_id) | .machine_expectations.required_substrings | join("\\n")' "$research_evals")"
    research_jcs_node build "$mode" "$report" >"$response_path"
}
