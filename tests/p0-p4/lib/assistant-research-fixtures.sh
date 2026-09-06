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
const ianaNonGlobalIpv4Cidrs = ["0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12", "192.0.0.0/24", "192.0.2.0/24", "192.88.99.0/24", "192.168.0.0/16", "198.18.0.0/15", "198.51.100.0/24", "203.0.113.0/24", "224.0.0.0/4", "240.0.0.0/4"];
const ianaNonGlobalIpv6Cidrs = ["::/128", "::1/128", "::ffff:0:0/96", "64:ff9b:1::/48", "100::/64", "100:0:0:1::/64", "2001::/23", "2001:db8::/32", "3fff::/20", "5f00::/16", "fc00::/7", "fe80::/10", "ff00::/8"];
const ianaGlobalIpv4Exceptions = new Set(["192.0.0.9", "192.0.0.10"]);
const ianaGlobalIpv6Exceptions = ["2001:1::1/128", "2001:1::2/128", "2001:1::3/128", "2001:3::/32", "2001:4:112::/48", "2001:20::/28", "2001:30::/28"];
function ipv4InCidr(host, cidr) {
  const [base, prefix] = cidr.split("/");
  const toNumber = value => value.split(".").reduce((result, part) => (result << 8) + Number(part), 0) >>> 0;
  const shift = 32 - Number(prefix);
  return (toNumber(host) >>> shift) === (toNumber(base) >>> shift);
}
function ipv6ToBigInt(host) {
  if (host.includes(".")) return undefined;
  const parts = host.toLowerCase().split("::");
  if (parts.length > 2) return undefined;
  const left = parts[0] ? parts[0].split(":") : [];
  const right = parts.length === 2 && parts[1] ? parts[1].split(":") : [];
  const omitted = 8 - left.length - right.length;
  if (left.concat(right).some(part => !/^[0-9a-f]{1,4}$/.test(part)) || (parts.length === 1 && omitted !== 0) || (parts.length === 2 && omitted < 1)) return undefined;
  return [...left, ...Array(omitted).fill("0"), ...right].reduce((result, part) => (result << 16n) + BigInt(`0x${part}`), 0n);
}
function ipv6InCidr(host, cidr) {
  const [base, prefix] = cidr.split("/");
  const address = ipv6ToBigInt(host), network = ipv6ToBigInt(base);
  return address !== undefined && network !== undefined && (address >> BigInt(128 - Number(prefix))) === (network >> BigInt(128 - Number(prefix)));
}
function nonGlobalLiteralIp(host) {
  const family = net.isIP(host);
  if (family === 4) return !ianaGlobalIpv4Exceptions.has(host) && ianaNonGlobalIpv4Cidrs.some(cidr => ipv4InCidr(host, cidr));
  return family === 6 && !ianaGlobalIpv6Exceptions.some(cidr => ipv6InCidr(host, cidr)) && ianaNonGlobalIpv6Cidrs.some(cidr => ipv6InCidr(host, cidr));
}
function lensResultBody(result) { return Object.fromEntries(lensResultFields.map(key => [key, result[key]])); }
function usage(mode, lens, tier) {
  if (mode === "delegated") return {actual_queries: tier === "standard" ? 2 : 3, actual_sources: tier === "standard" ? 3 : 4, elapsed_minutes: 10, termination_state: "saturation", exhausted_dimensions: [], confidence_downgraded: false};
  const gap = `Query, source, and time ceilings reached before confirming ${lens} coverage.`;
  return {actual_queries: 5, actual_sources: 6, elapsed_minutes: 15, termination_state: "ceiling_exhausted", exhausted_dimensions: ["queries", "sources", "elapsed_time"], exhaustion_gap: gap, confidence_downgraded: true};
}
function lensResult(mode, lens, followUpRequirements, topicTerms) {
  const fallback = mode === "sequential_fallback";
  const gap = `Query, source, and time ceilings reached before confirming ${lens} coverage.`;
  const topic = Array.isArray(topicTerms) && topicTerms.length > 0 ? `${topicTerms.join("; ")}: ` : "";
  const requirement = (followUpRequirements || []).find(value => value.lens_kind === lens);
  const follow_ups = requirement
    ? Array.from({length: requirement.exact_count}, (_, index) => requirement.decision === "follow_up"
      ? {decision: "follow_up", question: `Follow-up ${index + 1} for ${lens}`, answer_or_gap: `Additional verification question ${index + 1} for ${lens}.`, sources_or_verified_urls: [`source:research-corpus:${lens}:follow-up-${index + 1}`], evidence_status: "source_backed", gaps: []}
      : {decision: "none_needed", answer_or_gap: `No material follow-up for ${lens}.`, sources_or_verified_urls: [`source:research-corpus:${lens}`], evidence_status: "source_backed", gaps: []})
    : [{decision: "none_needed", answer_or_gap: fallback ? `No additional follow-up after ceilings for ${lens}` : `No material follow-up for ${lens}`, sources_or_verified_urls: fallback ? [] : [`source:research-corpus:${lens}`], evidence_status: fallback ? "unresolved" : "source_backed", gaps: fallback ? [gap] : []}];
  return {
    core_position: fallback ? `${topic}Unresolved position for ${lens}` : `${topic}Position for ${lens}`,
    lens_question: `${topic}Question for ${lens}`,
    answer_or_gap: fallback ? `${topic}Unresolved answer for ${lens}` : `${topic}Answer for ${lens}`,
    sources_or_verified_urls: fallback ? [] : [`source:research-corpus:${lens}`],
    follow_ups,
    evidence_status: fallback ? "unresolved" : "source_backed",
    likely_blind_spot: fallback ? `${topic}Unverified source coverage for ${lens}` : `${topic}Blind spot for ${lens}`,
    unique_insight: fallback ? `${topic}Fallback insight for ${lens}` : `${topic}Insight for ${lens}`,
    confidence: fallback ? "low" : "medium",
    gaps: fallback ? [gap] : []
  };
}
function packet(mode, lens, ordinal, tier, packetScope) {
  const budget = tier === "standard" ? {per_lens_max_queries: 3, per_lens_max_sources: 4, per_lens_max_minutes: 10, overall_max_queries: 15, overall_max_sources: 20, overall_max_minutes: 50, stop_condition: "saturation_or_hard_ceiling"} : {per_lens_max_queries: 5, per_lens_max_sources: 6, per_lens_max_minutes: 15, overall_max_queries: 25, overall_max_sources: 30, overall_max_minutes: 75, stop_condition: "saturation_or_hard_ceiling"};
  return {packet_id: `packet-${["practitioner", "academic", "skeptic", "economist", "historian"][ordinal]}`, packet_set_id: mode === "delegated" ? "packet-set-1" : "fallback-packet-set-1", question: packetScope.question, tier, user_role_or_goal: packetScope.user_role_or_goal, output_purpose: packetScope.output_purpose, known_context: ["local fixture"], evidence_budget: "six sources", search_resource_budget: budget, source_policy: "verified_sources_only", isolation_policy: "sibling_blind_no_synthesis", lens_kind: lens, packet_frozen_at: "2026-09-03T10:00:00Z"};
}
function semanticContext(value) {
  const fallback = {packet_scope: {question: "Should we adopt the tool?", user_role_or_goal: "architecture decision", output_purpose: "Answer the research question"}, follow_up_requirements: [], high_stakes_context: {applicable: true, caveat_or_not_applicable_reason: "This fixture is educational due diligence, not financial, legal, medical, or professional advice.", user_context_status: "unresolved", user_context_basis: "No decision-specific user constraints were supplied."}};
  if (!value) return fallback;
  const context = JSON.parse(value);
  return context && context.packet_scope && Array.isArray(context.follow_up_requirements) ? context : fallback;
}
function build(mode, report, semanticContextValue) {
  const lensMode = ["sequential_fallback", "sequential_fallback_revise"].includes(mode) ? "sequential_fallback" : "delegated";
  const peerMode = mode === "delegated_peer_fallback" || lensMode === "sequential_fallback" ? "sequential_fallback" : "delegated";
  const isFallback = lensMode === "sequential_fallback";
  const peerRevise = mode === "sequential_fallback_revise" || peerMode === "delegated";
  const requestedTier = mode === "quick_normalized" ? "quick" : "extensive";
  const effectiveTier = requestedTier === "quick" ? "standard" : "extensive";
  const context = semanticContext(semanticContextValue);
  const packetScope = context.packet_scope;
  const followUpRequirements = context.follow_up_requirements;
  const topicTerms = Array.isArray(context.required_topic_terms) && context.required_topic_terms.length > 0
    ? context.required_topic_terms
    : (/invest/i.test(packetScope.question) && /AI coding assistant/i.test(packetScope.question) && /\.NET architecture/i.test(packetScope.question) ? ["invest", "AI coding assistant", ".NET architecture"] : []);
  const packets = lenses.map((lens, index) => { const value = packet(lensMode, lens, index, effectiveTier, packetScope); return {...value, content_digest: digest(value)}; });
  const manifest = packets.map(({packet_id, lens_kind, content_digest}) => ({packet_id, lens_kind, content_digest}));
  const records = lenses.map((lens, index) => {
    const assignment_id = isFallback ? `fallback-assignment-${index + 1}` : `assignment-${index + 1}`;
    const result = lensResult(lensMode, lens, followUpRequirements, topicTerms);
    const resultDigest = digest(result);
    const resourceUsage = usage(lensMode, lens, effectiveTier);
    const common = {lens_kind: lens, assignment_id, packet_id: packets[index].packet_id, packet_set_id: packets[index].packet_set_id, packet_content_digest: packets[index].content_digest, lens_result_digest: resultDigest, search_resource_usage: resourceUsage, return_validated: true};
    return isFallback ? {...common, root_pass_id: `root-pass-${index + 1}`} : {...common, dispatch_identity: `lens-native-${index + 1}`, wave_id: "wave-1"};
  });
  const overall = isFallback ? {actual_queries: 25, actual_sources: 30, elapsed_minutes: 75, termination_state: "ceiling_exhausted", exhausted_dimensions: ["queries", "sources", "elapsed_time"], exhaustion_gap: "Overall ceilings reached before cross-lens verification.", confidence_downgraded: true} : {actual_queries: effectiveTier === "standard" ? 10 : 15, actual_sources: effectiveTier === "standard" ? 15 : 20, elapsed_minutes: 10, termination_state: "saturation", exhausted_dimensions: [], confidence_downgraded: false};
  const accepted_lens_results = records.map(record => { const result = lensResult(lensMode, record.lens_kind, followUpRequirements, topicTerms); return {lens_kind: record.lens_kind, assignment_id: record.assignment_id, lens_result_digest: record.lens_result_digest, ...result}; });
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
  const topic = topicTerms.length > 0 ? `${topicTerms.join("; ")}: ` : "";
  const synthesis_briefing = {executive_summary: isFallback ? `${topic}The available process evidence is insufficient for adoption.` : `${topic}The fixture supports a bounded verification step.`, ranked_key_findings: [`${topic}All five lenses completed their assigned process.`, isFallback ? `${topic}Ceilings exhausted before source confirmation.` : `${topic}The accepted results retain their source identifiers.`, `${topic}The recommendation remains calibrated to the evidence.`], hidden_connection: `${topic}The frozen packet ledger makes synthesis traceable.`, actionable_implication: `${topic}Run an independent source check before adopting the tool.`, recommendation: "investigate_further", high_stakes_caveat: "This fixture is educational due diligence, not financial, legal, medical, or professional advice.", frontier_question: `${topic}Which independent source would most change the decision?`};
  const high_stakes_context = context.high_stakes_context;
  const verified_source_evidence = [{claim: "Fixture decision evidence", source: "source:research-corpus:summary", verification_method: "local_repository", verification_reference: "skills/assistant-research/contracts/output.yaml", verification_detail: "Fixture-local stable reference."}];
  const findings = isFallback ? [] : [{finding: `${topic}The evidence supports a calibrated investigation.`, confidence: "low", sources: ["source:research-corpus:practitioner"]}];
  const candidate_mechanisms = [];
  const conflicts = [];
  const contradiction_map = {direct_conflicts: [], strongest_evidence: isFallback ? `${topic}No source-backed conclusion is available.` : `${topic}Validated lens source identifiers.`, weakest_evidence: isFallback ? `${topic}Ceiling-exhausted source coverage.` : `${topic}Fixture-only evidence scope.`, consensus: [isFallback ? `${topic}Further confirmation is required.` : `${topic}Proceed only with verification.`], biggest_unresolved_question: `${topic}Whether independent source confirmation changes the recommendation.`, missing_angle_or_gap: isFallback ? `${topic}Independent source confirmation.` : `${topic}Production evidence beyond the fixture.`};
  const peer_review_input_binding = {peer_review_assignment_id: process.peer_review_assignment_id, initial_synthesis: synthesis_briefing, validated_lens_results: accepted_lens_results, lens_execution_provenance: provenance, verified_source_evidence, verification_gaps: gaps, high_stakes_context, findings, candidate_mechanisms, conflicts, contradiction_map};
  peer_review_input_binding.peer_review_input_digest = digest(peer_review_input_binding);
  process.peer_review_input_binding = peer_review_input_binding;
  process.final_synthesis_digest = digest(synthesis_briefing);
  const reviseFields = peerRevise ? {status: "DONE_WITH_CONCERNS", verdict: "revise", required_revisions: ["downgrade unsupported claim"], revision_disposition_id: "revision-closure-1", revision_disposition: [{required_revision: "downgrade unsupported claim", outcome: "claim_downgraded", closure_evidence: "claim confidence updated", resulting_synthesis_digest: process.final_synthesis_digest}]} : {status: "DONE", verdict: "accepted", required_revisions: []};
  const peer_review = peerMode === "sequential_fallback" ? {peer_review_execution_mode: peerMode, peer_review_assignment_id: process.peer_review_assignment_id, peer_review_fallback_pass_id: process.peer_review_fallback_pass_id, peer_review_input_digest: peer_review_input_binding.peer_review_input_digest, supported_recommendation: "investigate_further", ...reviseFields, ...peerUsableFields} : {peer_review_execution_mode: peerMode, peer_review_assignment_id: "peer-assignment-1", peer_reviewer_identity: "peer-native-1", peer_review_input_digest: peer_review_input_binding.peer_review_input_digest, supported_recommendation: "investigate_further", ...reviseFields, ...peerUsableFields};
  return {report, research_method: "five_lens_briefing", tier: effectiveTier, findings, candidate_mechanisms, conflicts, peer_review, five_lens_process_evidence: process, perspective_scan, question_trace, contradiction_map, synthesis_briefing, summary: isFallback ? `${topic}Do not adopt until independent source confirmation is available.` : `${topic}Investigate further before deciding whether to adopt the tool.`, gaps};
}
function validate(response) {
  const errors = [];
  const expect = (condition, message) => { if (!condition) errors.push(message); };
  const exactKeys = (value, keys) => value && typeof value === "object" && !Array.isArray(value) && equal(Object.keys(value).sort(), [...keys].sort());
  let fixtureCase;
  try {
    const fixture = JSON.parse(fs.readFileSync(args[1], "utf8"));
    fixtureCase = Array.isArray(fixture?.cases) ? fixture.cases.find(item => item?.id === args[2]) : undefined;
  } catch { fixtureCase = undefined; }
  const semanticContext = fixtureCase?.semantic_context;
  if (!fixtureCase || !semanticContext) { console.error("semantic context: selected fixture case required"); return false; }
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
  expect(!(peerMode === "delegated" && ["delegation_opted_out", "policy_disallowed"].includes(process.subagent_policy_state)), "peer:global-policy-requires-fallback");
  const manifest = process.frozen_packet_set && process.frozen_packet_set.packet_manifest;
  const packetById = new Map((manifest || []).map(packet => [packet.packet_id, packet]));
  const retainedPackets = process.frozen_assignment_packets || [];
  const commonPacketScope = retainedPackets[0] && Object.fromEntries(["question", "tier", "user_role_or_goal", "output_purpose", "known_context", "evidence_budget", "search_resource_budget", "source_policy", "isolation_policy"].map(key => [key, retainedPackets[0][key]]));
  expect(Array.isArray(manifest) && manifest.length === 5 && equal(manifest.map(packet => packet.packet_id), process.frozen_packet_set?.packet_manifest_order) && equal(process.frozen_assignment_packet_ids, process.frozen_packet_set?.packet_manifest_order) && equal(process.frozen_packet_set?.packet_ids, process.frozen_packet_set?.packet_manifest_order) && Array.isArray(retainedPackets) && retainedPackets.length === 5 && retainedPackets.every(packet => equal(packet, {...packet, content_digest: digest(Object.fromEntries(Object.entries(packet).filter(([key]) => key !== "content_digest")))}) && Date.parse(packet.packet_frozen_at) <= Date.parse(process.frozen_packet_set?.packet_set_frozen_at) && Date.parse(packet.packet_frozen_at) < Date.parse(process.frozen_packet_set?.first_lens_execution_at) && packet.source_policy === "verified_sources_only" && packet.isolation_policy === "sibling_blind_no_synthesis" && equal(Object.fromEntries(Object.keys(commonPacketScope).map(key => [key, packet[key]])), commonPacketScope)) && equal(retainedPackets.map(packet => ({packet_id: packet.packet_id, lens_kind: packet.lens_kind, content_digest: packet.content_digest})), manifest), "packet-manifest:projection");
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
      if (/^\/\//.test(source) || /^https?(?::(?!\/\/)|\/(?!\/)|\/\/(?!\/))/i.test(source)) return false;
      if (/^https?:\/\//i.test(source)) return publicUrlValid(source);
      let decoded;
      try { decoded = decodeURIComponent(source); } catch { return false; }
      if (decoded !== source && (/^https?:\/\//i.test(decoded) || /^\/\//.test(decoded) || /^https?(?::(?!\/\/)|\/(?!\/)|\/\/(?!\/))/i.test(decoded))) return /^https?:\/\//i.test(decoded) && publicUrlValid(decoded);
      if (decoded !== source && encodedHttpSchemeLike(decoded)) return false;
      if (/^[A-Za-z][A-Za-z0-9+.-]*:\/\//.test(source) && !/^https?:\/\//i.test(source)) return false;
      if (!/^https?:\/\//i.test(source)) return decodedOpaqueReferenceSafetyValid(source);
      const rawAuthority = source.match(/^https:\/\/([^/?#]+)/i)?.[1];
      const rawHostPort = rawAuthority?.replace(/^.*@/, "");
      const rawHost = rawHostPort?.replace(/^\[([^\]]+)\](?::\d+)?$/, "$1").replace(/:\d+$/, "");
      if (!rawAuthority || rawAuthority.includes("@") || !rawHost || /(?:\]|[^:]):\d+$/.test(rawHostPort) || rawHost.split(".").some(part => /^(?:0x[0-9a-f]+|0[0-9]+)$/i.test(part)) || /^(?:0x[0-9a-f]+|0[0-9]+|[0-9]+)$/i.test(rawHost) || (/^\d+(?:\.\d+)+$/.test(rawHost) && rawHost.split(".").length !== 4) || !decodedUrlSafetyValid(source)) return false;
      let url; try { url = new URL(source); } catch { return false; }
      const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, "");
      if (url.protocol !== "https:" || url.username || url.password || url.port || !host || host.endsWith(".") || ["localhost", "invalid", "local", "internal", "test", "example"].includes(host) || /(?:\.invalid|\.localhost|\.local|\.internal|\.test|\.example)$/.test(host) || /^[0-9]+$/.test(host) || (!net.isIP(host) && !host.includes("."))) return false;
      return !nonGlobalLiteralIp(host);
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
    const returnedSourceCount = new Set([...(result?.sources_or_verified_urls || []), ...(Array.isArray(followUps) ? followUps.flatMap(followUp => followUp?.sources_or_verified_urls || []) : [])].filter(source => typeof source === "string" && source.trim().length > 0)).size;
    const validUsage = usage && ["actual_queries","actual_sources","elapsed_minutes"].every(key => Number.isInteger(usage[key]) && usage[key] >= 0) && usage.actual_queries <= budget.per_lens_max_queries && usage.actual_sources <= budget.per_lens_max_sources && usage.elapsed_minutes <= budget.per_lens_max_minutes;
    expect(validUsage && usage.actual_sources >= returnedSourceCount, "usage:per-lens-ceiling");
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
  const projectedLenses = rows => Array.isArray(rows) && rows.length === lenses.length && new Set(rows.map(row => row?.lens)).size === lenses.length && lenses.every(lens => rows.some(row => row?.lens === lens));
  expect(projectedLenses(response.perspective_scan), "perspective:exact-five-lenses");
  expect(projectedLenses(response.question_trace), "question-trace:exact-five-lenses");
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
  } else expect(!Object.hasOwn(process, "wave_coverage"), "waves:sequential-fallback-leakage");
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
  function nonblank(value) {
    return typeof value === "string" && value.length > 0;
  }
  function decodedOpaqueReferenceSafetyValid(value) {
    let decoded;
    try { decoded = decodeURIComponent(value); } catch { return false; }
    return !/(?:^|[?&#\\/:_-])(?:token|secret|key|password|email|api[_-]?key|access[_-]?token|bearer|credential|session|authorization)(?:=|$|[\\/:_-])/i.test(decoded) && !/(?:^|[\\/])\.\.(?:[\\/]|$)/.test(decoded) && !/^(?:[A-Za-z]:[\\/]|\\\\|\/(?:Users|home|private|var)(?:[\\/]|$)|~(?:[\\/]|$))/i.test(decoded) && !/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}|\b\d{3}-\d{2}-\d{4}\b|\b\d{3}[ .-]\d{3}[ .-]\d{4}\b/i.test(decoded);
  }
  function sensitiveUrlComponent(value) {
    return value.replace(/^[?#]/, "").split(/[&;]/).some(field => field.split("=").some(part => /(?:^|[\\/:_-])(?:token|secret|key|password|email|api[_-]?key|access[_-]?token|bearer|credential|session|authorization)(?:$|[\\/:_-])/i.test(part)));
  }
  function decodedUrlSafetyValid(value) {
    let decoded, url;
    try { decoded = decodeURIComponent(value); url = new URL(value); } catch { return false; }
    return !/(?:^|[\\/])\.\.(?:[\\/]|$)/.test(decoded) && !/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}|\b\d{3}-\d{2}-\d{4}\b|\b\d{3}[ .-]\d{3}[ .-]\d{4}\b/i.test(decoded) && ![url.search, url.hash].some(component => {
      try { return sensitiveUrlComponent(decodeURIComponent(component)); } catch { return true; }
    });
  }
  const sources = value => Array.isArray(value) && value.length > 0 && value.every(nonblank);
  const safeReference = value => {
    if (!nonblank(value) || value !== value.trim() || /^(?:[A-Za-z]:[\\/]|\\\\)/.test(value)) return false;
    if (/^\/\//.test(value) || /^https?(?::(?!\/\/)|\/(?!\/)|\/\/(?!\/))/i.test(value)) return false;
    if (/^https?:\/\//i.test(value)) return publicUrlValid(value);
    let decoded; try { decoded = decodeURIComponent(value); } catch { return false; }
    if (decoded !== value && (/^https?:\/\//i.test(decoded) || /^\/\//.test(decoded) || /^https?(?::(?!\/\/)|\/(?!\/)|\/\/(?!\/))/i.test(decoded))) return safeReference(decoded);
    if (decoded !== value && encodedHttpSchemeLike(decoded)) return false;
    if (/^[A-Za-z][A-Za-z0-9+.-]*:\/\//.test(value) && !/^https?:\/\//i.test(value)) return false;
    if (!/^https?:\/\//i.test(value)) return decodedOpaqueReferenceSafetyValid(value);
    try {
      const rawAuthority = value.match(/^https:\/\/([^/?#]+)/i)?.[1];
      const rawHostPort = rawAuthority?.replace(/^.*@/, "");
      const rawHost = rawHostPort?.replace(/^\[([^\]]+)\](?::\d+)?$/, "$1").replace(/:\d+$/, "");
      if (!rawAuthority || rawAuthority.includes("@") || !rawHost || /(?:\]|[^:]):\d+$/.test(rawHostPort) || rawHost.split(".").some(part => /^(?:0x[0-9a-f]+|0[0-9]+)$/i.test(part)) || /^(?:0x[0-9a-f]+|0[0-9]+|[0-9]+)$/i.test(rawHost) || (/^\d+(?:\.\d+)+$/.test(rawHost) && rawHost.split(".").length !== 4) || !decodedUrlSafetyValid(value)) return false;
      const url = new URL(value);
      const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, "");
      if (url.protocol !== "https:" || url.username || url.password || url.port || !host || host.endsWith(".") || ["localhost", "invalid", "local", "internal", "test", "example"].includes(host) || /(?:\.invalid|\.localhost|\.local|\.internal|\.test|\.example)$/.test(host) || /^[0-9]+$/.test(host) || (!net.isIP(host) && !host.includes("."))) return false;
      return !nonGlobalLiteralIp(host);
    } catch { return false; }
  };
  const malformedUrlSchemeLike = value => typeof value === "string" && /^https?(?::(?!\/\/)|\/(?!\/)|\/\/(?!\/))/i.test(value);
  function encodedHttpSchemeLike(value) {
    return typeof value === "string" && !/^https?:\/\//i.test(value) && /^(?:h|%(?:25)*(?:68|48))(?:t|%(?:25)*(?:74|54))(?:t|%(?:25)*(?:74|54))(?:p|%(?:25)*(?:70|50))(?:(?:s|%(?:25)*(?:73|53))?(?::|%(?:25)*3a)(?:\/|%(?:25)*2f){2})/i.test(value);
  }
  const unsafeOpaqueReference = value => {
    let decoded;
    try { decoded = decodeURIComponent(value); } catch { return true; }
    return /^\/\//.test(value) || malformedUrlSchemeLike(value) || encodedHttpSchemeLike(decoded) || !decodedOpaqueReferenceSafetyValid(value);
  };
  function publicUrlValid(value) {
    if (!nonblank(value) || !decodedUrlSafetyValid(value)) return false;
    const rawAuthority = value.match(/^https:\/\/([^/?#]+)/i)?.[1];
    const rawHostPort = rawAuthority?.replace(/^.*@/, "");
    const rawHost = rawHostPort?.replace(/^\[([^\]]+)\](?::\d+)?$/, "$1").replace(/:\d+$/, "");
    if (!rawAuthority || rawAuthority.includes("@") || !rawHost || /(?:\]|[^:]):\d+$/.test(rawHostPort) || rawHost.split(".").some(part => /^(?:0x[0-9a-f]+|0[0-9]+)$/i.test(part)) || /^(?:0x[0-9a-f]+|0[0-9]+|[0-9]+)$/i.test(rawHost) || (/^\d+(?:\.\d+)+$/.test(rawHost) && rawHost.split(".").length !== 4)) return false;
    let url; try { url = new URL(value); } catch { return false; }
    if (url.protocol !== "https:" || url.username || url.password || url.port) return false;
    const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, "");
    const specialUseHost = new Set(["local", "localhost", "invalid", "test", "example", "internal"]);
    if (!host || host.endsWith(".") || specialUseHost.has(host) || (!net.isIP(host) && !host.includes(".")) || /(?:\.local|\.localhost|\.invalid|\.test|\.example|\.internal)$/.test(host) || /^(?:0x|0)[0-9a-f]+$/i.test(host) || /^[0-9]+$/.test(host)) return false;
    if (net.isIP(host) === 4 && host.split(".").some(part => part.length > 1 && part.startsWith("0"))) return false;
    if (nonGlobalLiteralIp(host)) return false;
    return true;
  }
  const boundedPublicUrl = value => {
    if (publicUrlValid(value)) return value;
    let decoded;
    try { decoded = decodeURIComponent(value); } catch { return undefined; }
    return decoded !== value && publicUrlValid(decoded) ? decoded : undefined;
  };
  const publicUrlIdentity = value => {
    const boundedUrl = boundedPublicUrl(value);
    if (!boundedUrl) return undefined;
    const url = new URL(boundedUrl);
    const canonicalPercentEncodedComponent = component => {
      if (typeof component !== "string" || /%(?![0-9a-f]{2})/i.test(component)) return undefined;
      return component.replace(/%([0-9a-f]{2})/gi, (match, hex) => {
        const character = String.fromCharCode(Number.parseInt(hex, 16));
        return /^[A-Za-z0-9\-._~]$/.test(character) ? character : `%${hex.toUpperCase()}`;
      });
    };
    const host = canonicalPercentEncodedComponent(url.hostname.toLowerCase());
    const path = canonicalPercentEncodedComponent(url.pathname);
    const search = canonicalPercentEncodedComponent(url.search);
    const hash = canonicalPercentEncodedComponent(url.hash);
    return host === undefined || path === undefined || search === undefined || hash === undefined
      ? undefined
      : `https://${host}${path}${search}${hash}`;
  };
  const verifiedEvidenceRowValid = row => {
    const publicRow = row?.verification_method === "public_url";
    const keys = publicRow ? ["claim", "source", "verification_method", "verification_reference", "verified_url", "verification_detail"] : ["claim", "source", "verification_method", "verification_reference", "verification_detail"];
    if (!exactKeys(row, keys) || !nonblank(row.claim) || !nonblank(row.source) || !safeReference(row.source) || !nonblank(row.verification_reference) || !nonblank(row.verification_detail)) return false;
    if (!publicRow && unsafeOpaqueReference(row.verification_reference)) return false;
    if (row.verification_method === "local_repository") return /^(?!\/)(?!.*(?:^|\/)\.\.(?:\/|$))[A-Za-z0-9._/-]+(?:#[A-Za-z0-9._:-]+)?$/.test(row.verification_reference);
    if (publicRow) return row.verified_url === row.verification_reference && boundedPublicUrl(row.verified_url) !== undefined;
    if (row.verification_method === "authenticated_source") return /^connector:[A-Za-z0-9._-]+\/record:[A-Za-z0-9._-]+$/.test(row.verification_reference);
    return row.verification_method === "offline_authoritative_source" && /^(?:citation|isbn|doi):[^\s]+$/i.test(row.verification_reference) && !/:\/\//.test(row.verification_reference) && !/^(?:citation|isbn|doi):(?:\/(?:Users|home|private|var)(?:\/|$)|[A-Za-z]:[\\/]|\\\\)/i.test(row.verification_reference);
  };
  const verifiedEvidenceValid = rows => Array.isArray(rows) && rows.every(verifiedEvidenceRowValid);
  const provenanceValid = finding => {
    const rows = finding?.source_provenance;
    const evidenceSourceAliases = new Map((process.peer_review_input_binding?.verified_source_evidence || []).filter(verifiedEvidenceRowValid).flatMap(row => { const reference = row.verification_method === "public_url" ? publicUrlIdentity(row.verified_url) : row.verification_reference; const identity = `ledger:${row.verification_method}:${reference}`; return row.verification_method === "public_url" ? [[row.source, identity], [row.verified_url, identity], [reference, identity]] : [[row.source, identity]]; }));
    const canonicalSourceSet = new Set((finding?.sources || []).map(source => evidenceSourceAliases.get(source) || evidenceSourceAliases.get(publicUrlIdentity(source)) || publicUrlIdentity(source) || source));
    if (!Array.isArray(rows)) return finding?.confidence !== "high" && (finding?.confidence !== "medium" || canonicalSourceSet.size >= 2);
    const shape = rows.every(row => row && typeof row === "object" && Object.keys(row).length === 3 && nonblank(row.source) && safeReference(row.source) && nonblank(row.independence_key) && ["primary", "official", "secondary"].includes(row.authority));
    const sourcesMatch = shape && new Set(rows.map(row => row.source)).size === rows.length && new Set(finding?.sources || []).size === (finding?.sources || []).length && equal([...new Set(rows.map(row => row.source))].sort(), [...(finding?.sources || [])].sort());
    const highValid = finding?.confidence !== "high" || (sourcesMatch && canonicalSourceSet.size >= 3 && new Set(rows.map(row => row.independence_key)).size >= 3 && rows.some(row => ["primary", "official"].includes(row.authority)));
    const mediumValid = finding?.confidence !== "medium" || canonicalSourceSet.size >= 2 || (sourcesMatch && rows.length === 1 && ["primary", "official"].includes(rows[0].authority));
    return sourcesMatch && highValid && mediumValid;
  };
  const findings = response.findings;
  const sourceEmptyCompletion = (process.accepted_lens_results || []).every(result => Array.isArray(result?.sources_or_verified_urls) && result.sources_or_verified_urls.length === 0 && ["inference_only", "unresolved"].includes(result.evidence_status));
  const binding = process.peer_review_input_binding;
  const acceptedSources = new Set((process.accepted_lens_results || []).flatMap(result => [...(result?.sources_or_verified_urls || []), ...(Array.isArray(result?.follow_ups) ? result.follow_ups.flatMap(followUp => followUp?.sources_or_verified_urls || []) : [])]));
  const verifiedSourceIdentities = new Set((binding?.verified_source_evidence || []).filter(verifiedEvidenceRowValid).flatMap(row => row.verification_method === "public_url" ? [row.source, row.verified_url, publicUrlIdentity(row.verified_url)] : [row.source]));
  const findingSourceBound = finding => Array.isArray(finding?.sources) && finding.sources.every(source => acceptedSources.has(source) || verifiedSourceIdentities.has(source) || verifiedSourceIdentities.has(publicUrlIdentity(source)));
  const findingsValid = Array.isArray(findings) && ((findings.length > 0 && findings.every(finding => nonblank(finding?.finding) && ["high", "medium", "low"].includes(finding?.confidence) && sources(finding?.sources) && finding.sources.every(safeReference) && findingSourceBound(finding) && provenanceValid(finding) && (!Object.hasOwn(finding, "verified_urls") || (sources(finding.verified_urls) && finding.verified_urls.every(safeReference))))) || (findings.length === 0 && sourceEmptyCompletion && Array.isArray(response.gaps) && response.gaps.length > 0));
  expect(findingsValid, "artifacts:findings");
  const candidateMechanismsValid = Array.isArray(response.candidate_mechanisms) && response.candidate_mechanisms.every(mechanism => {
    const evidence = mechanism?.evidence;
    const sourceBackedIdentities = new Set((Array.isArray(evidence) ? evidence : []).filter(row => row?.evidence_status === "source_backed").map(row => publicUrlIdentity(row.source) || row.source));
    const unresolvedEvidence = Array.isArray(evidence) && evidence.some(row => row?.evidence_status === "unresolved");
    const confidenceValid = mechanism?.confidence === "low" || (!unresolvedEvidence && sourceBackedIdentities.size >= 2 && (mechanism?.confidence !== "high" || sourceBackedIdentities.size >= 3));
    return exactKeys(mechanism, ["mechanism", "claim_status", "evidence", "confidence", "counterevidence_or_conflicts", "gaps", "validation_method"]) && nonblank(mechanism.mechanism) && ["candidate", "needs_validation", "unsupported", "rejected"].includes(mechanism.claim_status) && Array.isArray(evidence) && evidence.length > 0 && evidence.every(row => exactKeys(row, ["source", "detail", "evidence_status"]) && nonblank(row.source) && safeReference(row.source) && nonblank(row.detail) && ["source_backed", "inference_only", "unresolved"].includes(row.evidence_status)) && ["high", "medium", "low"].includes(mechanism.confidence) && confidenceValid && Array.isArray(mechanism.counterevidence_or_conflicts) && mechanism.counterevidence_or_conflicts.every(nonblank) && Array.isArray(mechanism.gaps) && mechanism.gaps.every(nonblank) && nonblank(mechanism.validation_method);
  });
  expect(candidateMechanismsValid, "artifacts:candidate-mechanisms-normalized");
  expect(Array.isArray(response.conflicts) && response.conflicts.every(conflict => ["claim_a", "claim_b", "assessment"].every(key => nonblank(conflict?.[key])) && safeReference(conflict.source_a) && safeReference(conflict.source_b)), "artifacts:conflicts");
  expect(Array.isArray(response.gaps) && response.gaps.every(nonblank) && nonblank(response.summary), "artifacts:gaps-and-summary");
  const contradiction = response.contradiction_map || {};
  expect(Array.isArray(contradiction.direct_conflicts) && contradiction.direct_conflicts.every(nonblank) && nonblank(contradiction.strongest_evidence) && nonblank(contradiction.weakest_evidence) && Array.isArray(contradiction.consensus) && contradiction.consensus.every(nonblank) && nonblank(contradiction.biggest_unresolved_question) && nonblank(contradiction.missing_angle_or_gap), "artifacts:contradiction-map");
  const synthesis = response.synthesis_briefing || {};
  expect(nonblank(synthesis.executive_summary) && Array.isArray(synthesis.ranked_key_findings) && synthesis.ranked_key_findings.length >= 3 && synthesis.ranked_key_findings.every(nonblank) && nonblank(synthesis.hidden_connection) && nonblank(synthesis.actionable_implication) && ["do", "wait", "avoid", "investigate_further"].includes(synthesis.recommendation) && nonblank(synthesis.frontier_question), "artifacts:synthesis-briefing");
  const semanticContextValid = exactKeys(semanticContext, ["packet_scope", "follow_up_requirements", "required_topic_terms", "high_stakes_context"])
    && exactKeys(semanticContext.packet_scope, ["question", "user_role_or_goal", "output_purpose"])
    && Object.values(semanticContext.packet_scope).every(nonblank)
    && Array.isArray(semanticContext.required_topic_terms)
    && semanticContext.required_topic_terms.every(nonblank)
    && new Set(semanticContext.required_topic_terms).size === semanticContext.required_topic_terms.length
    && Array.isArray(semanticContext.follow_up_requirements);
  expect(semanticContextValid, "semantic-context:fixture-shape");
  expect(Array.isArray(retainedPackets) && retainedPackets.length === 5 && retainedPackets.every(packet => packet?.question === semanticContext.packet_scope?.question && packet?.user_role_or_goal === semanticContext.packet_scope?.user_role_or_goal && packet?.output_purpose === semanticContext.packet_scope?.output_purpose), "semantic-context:packet-scope");
  const semanticFollowUpsValid = Array.isArray(semanticContext.follow_up_requirements) && semanticContext.follow_up_requirements.every(requirement => {
    const result = (process.accepted_lens_results || []).find(item => item?.lens_kind === requirement?.lens_kind);
    return exactKeys(requirement, ["lens_kind", "decision", "exact_count"])
      && lenses.includes(requirement.lens_kind)
      && ["follow_up", "none_needed"].includes(requirement.decision)
      && Number.isInteger(requirement.exact_count)
      && requirement.exact_count > 0
      && Array.isArray(result?.follow_ups)
      && result.follow_ups.length === requirement.exact_count
      && result.follow_ups.every(followUp => followUp?.decision === requirement.decision);
  });
  expect(semanticFollowUpsValid, "semantic-context:follow-up-requirements");
  const topicTerms = semanticContext.required_topic_terms || [];
  const topicGroupContainsTerms = value => nonblank(value) && topicTerms.every(term => value.toLowerCase().includes(term.toLowerCase()));
  const joinedText = values => values.filter(nonblank).join("\n");
  const acceptedTopicText = joinedText((process.accepted_lens_results || []).flatMap(result => [result?.core_position, result?.lens_question, result?.answer_or_gap, result?.likely_blind_spot, result?.unique_insight]));
  const finalClaimTopicText = joinedText([
    ...(response.findings || []).map(finding => finding?.finding),
    ...(response.candidate_mechanisms || []).flatMap(mechanism => [mechanism?.mechanism, ...(Array.isArray(mechanism?.evidence) ? mechanism.evidence.map(evidence => evidence?.detail) : []), ...(Array.isArray(mechanism?.counterevidence_or_conflicts) ? mechanism.counterevidence_or_conflicts : []), ...(Array.isArray(mechanism?.gaps) ? mechanism.gaps : []), mechanism?.validation_method]),
    ...(response.conflicts || []).flatMap(conflict => [conflict?.claim_a, conflict?.claim_b, conflict?.assessment])
  ]);
  const synthesisTopicText = joinedText([...(contradiction.direct_conflicts || []), contradiction.strongest_evidence, contradiction.weakest_evidence, ...(contradiction.consensus || []), contradiction.biggest_unresolved_question, contradiction.missing_angle_or_gap, synthesis.executive_summary, ...(synthesis.ranked_key_findings || []), synthesis.hidden_connection, synthesis.actionable_implication, synthesis.high_stakes_caveat, synthesis.frontier_question, response.summary]);
  const topicArtifactsValid = topicTerms.length === 0 || [acceptedTopicText, finalClaimTopicText, synthesisTopicText].filter(nonblank).every(topicGroupContainsTerms);
  expect(topicArtifactsValid, "semantic-context:required-topic-terms");
  const peerEvidenceValid = !usablePeer || (Array.isArray(peer.evidence) && peer.evidence.length > 0 && peer.evidence.every(item => exactKeys(item, ["source", "detail", "evidence_status"]) && nonblank(item.source) && safeReference(item.source) && nonblank(item.detail) && ["source_backed", "inference_only", "unresolved"].includes(item.evidence_status)));
  expect(peerEvidenceValid, "peer:usable-evidence");
  const bindingPreimage = binding && Object.fromEntries(Object.entries(binding).filter(([key]) => key !== "peer_review_input_digest"));
  const provenance = binding?.lens_execution_provenance;
  expect(exactKeys(binding, ["peer_review_input_digest", "peer_review_assignment_id", "initial_synthesis", "validated_lens_results", "lens_execution_provenance", "verified_source_evidence", "verification_gaps", "high_stakes_context", "findings", "candidate_mechanisms", "conflicts", "contradiction_map"]) && binding.peer_review_input_digest === digest(bindingPreimage) && binding.peer_review_assignment_id === peer.peer_review_assignment_id && equal(binding.initial_synthesis, synthesis) && equal(binding.validated_lens_results, process.accepted_lens_results) && equal(binding.findings, response.findings) && equal(binding.candidate_mechanisms, response.candidate_mechanisms) && equal(binding.conflicts, response.conflicts) && equal(binding.contradiction_map, response.contradiction_map) && equal(binding.verification_gaps, response.gaps) && verifiedEvidenceValid(binding.verified_source_evidence) && exactKeys(provenance, ["lens_execution_mode", "reduced_independence", "fallback_basis", "fallback_evidence_ref"]) && provenance.lens_execution_mode === mode && provenance.reduced_independence === (mode === "sequential_fallback") && ((mode === "delegated" && provenance.fallback_basis === "not_applicable" && provenance.fallback_evidence_ref === "not_applicable") || (mode === "sequential_fallback" && provenance.fallback_basis === process.lens_fallback_evidence?.basis && provenance.fallback_evidence_ref === process.lens_fallback_evidence?.evidence_ref)) && peer.peer_review_input_digest === binding.peer_review_input_digest && process.final_synthesis_digest === digest(synthesis) && peer.supported_recommendation === synthesis.recommendation, "peer-input-and-synthesis:binding");
  const context = binding?.high_stakes_context;
  const trustedHighStakes = semanticContext.high_stakes_context;
  const stronger = ["do", "wait", "avoid"].includes(synthesis.recommendation);
  const basis = response.high_stakes_recommendation_basis;
  const publicEvidenceUrls = new Set((binding?.verified_source_evidence || []).filter(row => row?.verification_method === "public_url" && verifiedEvidenceRowValid(row)).map(row => row.verified_url));
  const trustedHighStakesValid = exactKeys(trustedHighStakes, ["applicable", "caveat_or_not_applicable_reason", "user_context_status", "user_context_basis"])
    && typeof trustedHighStakes.applicable === "boolean"
    && nonblank(trustedHighStakes.caveat_or_not_applicable_reason)
    && ["explicit", "unresolved", "not_applicable"].includes(trustedHighStakes.user_context_status)
    && nonblank(trustedHighStakes.user_context_basis)
    && ((trustedHighStakes.applicable && ["explicit", "unresolved"].includes(trustedHighStakes.user_context_status)) || (!trustedHighStakes.applicable && trustedHighStakes.caveat_or_not_applicable_reason === "not_applicable" && trustedHighStakes.user_context_status === "not_applicable" && trustedHighStakes.user_context_basis === "not_applicable"));
  const explicitContextPromptBound = trustedHighStakes?.user_context_status !== "explicit" || fixtureCase.prompt?.includes(trustedHighStakes.user_context_basis);
  expect(exactKeys(context, ["applicable", "caveat_or_not_applicable_reason", "user_context_status", "user_context_basis"]) && trustedHighStakesValid && explicitContextPromptBound && equal(context, trustedHighStakes) && ((trustedHighStakes.applicable && stronger && trustedHighStakes.user_context_status === "explicit" && exactKeys(basis, ["recommendation", "verified_decision_critical_urls", "user_context_basis", "peer_review_input_digest", "peer_supported_recommendation"]) && basis.recommendation === synthesis.recommendation && Array.isArray(basis.verified_decision_critical_urls) && basis.verified_decision_critical_urls.length > 0 && basis.verified_decision_critical_urls.every(value => publicUrlValid(value) && publicEvidenceUrls.has(value)) && basis.user_context_basis !== "not_applicable" && basis.user_context_basis === trustedHighStakes.user_context_basis && basis.peer_review_input_digest === binding?.peer_review_input_digest && basis.peer_supported_recommendation === peer.supported_recommendation && peer.supported_recommendation === synthesis.recommendation && (process.frozen_assignment_packets || []).every(packet => Array.isArray(packet?.known_context) && packet.known_context.includes(basis.user_context_basis))) || (!(trustedHighStakes.applicable && stronger) && !Object.hasOwn(response, "high_stakes_recommendation_basis"))), "high-stakes:recommendation-basis");
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
    binding.findings = response.findings;
    binding.candidate_mechanisms = response.candidate_mechanisms;
    binding.conflicts = response.conflicts;
    binding.contradiction_map = response.contradiction_map;
    binding.verification_gaps = response.gaps;
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
else if (operation === "build") process.stdout.write(JSON.stringify(build(args[0], args[1], args[2])));
else if (operation === "validate") process.exitCode = validate(JSON.parse(fs.readFileSync(args[0], "utf8"))) ? 0 : 1;
else if (operation === "refresh") process.stdout.write(JSON.stringify(refreshDerived(JSON.parse(fs.readFileSync(args[0], "utf8")))));
else throw new Error(`unknown research JCS operation: ${operation}`);
NODE
}

research_jcs_canonical_json() { local json; json="$(cat)"; research_jcs_node canonical "$json"; }
research_content_digest_json() { local json; json="$(cat)"; research_jcs_node digest "$json"; }
research_response_oracle_is_valid() {
    local response_path="$1"
    local case_id="$2"

    [[ -n "$case_id" ]] || return 2
    research_jcs_node validate "$response_path" "$research_evals" "$case_id"
}
research_refresh_response_derivatives() { local response_path="$1"; research_jcs_node refresh "$response_path" >"$response_path.refresh" && mv "$response_path.refresh" "$response_path"; }

write_schema_valid_five_lens_eval_response() {
    local mode="$1"
    local response_path="$2"
    local case_id report semantic_context

    if [[ "$mode" == "delegated" ]]; then
        case_id="five-lens-decision-briefing-uses-storm-style-workflow"
    elif [[ "$mode" == "quick_normalized" ]]; then
        case_id="five-lens-quick-normalizes-to-standard"
    elif [[ "$mode" == "delegated_peer_fallback" ]]; then
        case_id="five-lens-delegated-lenses-sequential-peer-fallback"
    elif [[ "$mode" == "retained_follow_ups" ]]; then
        case_id="five-lens-retains-all-material-follow-ups"
    else
        case_id="five-lens-sequential-fallback-preserves-process-evidence"
    fi
    report="$(jq -r --arg case_id "$case_id" '.cases[] | select(.id == $case_id) | .machine_expectations.required_substrings | join("\\n")' "$research_evals")"
    semantic_context="$(jq -c --arg case_id "$case_id" '.cases[] | select(.id == $case_id) | .semantic_context' "$research_evals")"
    research_jcs_node build "$mode" "$report" "$semantic_context" >"$response_path"
}
