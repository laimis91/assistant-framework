#!/usr/bin/env bash
# Closed-world semantic validators used by provider-neutral local eval grading.

semantic_validator_id_for_case() {
    local fixture_file="$1"
    local case_id="$2"

    jq -r --arg id "$case_id" '.cases[] | select(.id == $id) | .semantic_validator // empty' "$fixture_file"
}

assistant_research_five_lens_v3_valid() {
    local response_path="$1"
    local fixture_file="$2"
    local case_id="$3"

    node - "$response_path" "$fixture_file" "$case_id" <<'NODE'
const crypto = require("crypto");
const fs = require("fs");
const net = require("net");
const responsePath = process.argv[2];
const fixturePath = process.argv[3];
const caseId = process.argv[4];
const lenses = ["practitioner", "academic_or_technical_expert", "skeptic", "economist_or_incentives_analyst", "historian_or_pattern_matcher"];
const resultKeys = ["core_position", "lens_question", "answer_or_gap", "sources_or_verified_urls", "follow_ups", "evidence_status", "likely_blind_spot", "unique_insight", "confidence", "gaps"];
const acceptedKeys = ["lens_kind", "assignment_id", "lens_result_digest", ...resultKeys];
const packetKeys = ["packet_id", "packet_set_id", "content_digest", "question", "tier", "user_role_or_goal", "output_purpose", "known_context", "evidence_budget", "search_resource_budget", "source_policy", "isolation_policy", "lens_kind", "packet_frozen_at"];
const synthesisBaseKeys = ["executive_summary", "ranked_key_findings", "hidden_connection", "actionable_implication", "recommendation", "frontier_question"];
const peerBindingKeys = ["peer_review_input_digest", "peer_review_assignment_id", "initial_synthesis", "validated_lens_results", "findings", "candidate_mechanisms", "conflicts", "contradiction_map", "lens_execution_provenance", "verified_source_evidence", "verification_gaps", "high_stakes_context"];
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
  if (value === undefined) { fail("digest: value required"); return ""; }
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
function tierResolutionValid(resolution, responseTier) {
  if (!exactKeys(resolution, ["requested_tier", "effective_tier", "normalization_disclosure"], "tier resolution")) return undefined;
  if (!["quick", "standard", "extensive", "deep", "not_explicitly_requested"].includes(resolution.requested_tier) || !["standard", "extensive", "deep"].includes(resolution.effective_tier) || !nonblank(resolution.normalization_disclosure)) {
    fail("tier resolution: supported requested/effective tiers and disclosure required");
    return undefined;
  }
  if ((resolution.requested_tier === "quick" && (resolution.effective_tier !== "standard" || resolution.normalization_disclosure === "not_applicable")) || (["standard", "extensive", "deep"].includes(resolution.requested_tier) && (resolution.effective_tier !== resolution.requested_tier || resolution.normalization_disclosure !== "not_applicable")) || (resolution.requested_tier === "not_explicitly_requested" && resolution.normalization_disclosure !== "not_applicable") || responseTier !== resolution.effective_tier) {
    fail("tier resolution: five-lens normalization/binding");
    return undefined;
  }
  return resolution.effective_tier;
}
function usageValid(usage, budget, result, label) {
  const keys = ["actual_queries", "actual_sources", "elapsed_minutes", "termination_state", "exhausted_dimensions", "exhaustion_gap", "confidence_downgraded"];
  allowedKeys(usage, keys, label);
  if (!usage || !["actual_queries", "actual_sources", "elapsed_minutes"].every(key => Number.isInteger(usage[key]) && usage[key] >= 0)) { fail(`${label}: non-negative integer actuals required`); return false; }
  if (usage.actual_queries > budget.per_lens_max_queries || usage.actual_sources > budget.per_lens_max_sources || usage.elapsed_minutes > budget.per_lens_max_minutes) fail(`${label}: per-lens ceiling exceeded`);
  const returnedSources = new Set([
    ...(Array.isArray(result?.sources_or_verified_urls) ? result.sources_or_verified_urls : []),
    ...(Array.isArray(result?.follow_ups) ? result.follow_ups.flatMap(followUp => Array.isArray(followUp?.sources_or_verified_urls) ? followUp.sources_or_verified_urls : []) : [])
  ].filter(nonblank));
  if (usage.actual_sources < returnedSources.size) fail(`${label}: actual sources cannot undercount returned sources`);
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
function overallUsageValid(overall, budget, records, mode, process, trustedAdapterCapacity) {
  const keys = ["actual_queries", "actual_sources", "elapsed_minutes", "termination_state", "exhausted_dimensions", "exhaustion_gap", "confidence_downgraded"];
  allowedKeys(overall, keys, "overall usage");
  if (!overall || !["actual_queries", "actual_sources", "elapsed_minutes"].every(key => Number.isInteger(overall[key]) && overall[key] >= 0)) { fail("overall usage: non-negative integer actuals required"); return; }
  const querySum = records.reduce((sum, record) => sum + (record.search_resource_usage?.actual_queries ?? 0), 0);
  const sourceSum = records.reduce((sum, record) => sum + (record.search_resource_usage?.actual_sources ?? 0), 0);
  if (overall.actual_queries !== querySum || overall.actual_sources !== sourceSum || overall.actual_queries > budget.overall_max_queries || overall.actual_sources > budget.overall_max_sources || overall.elapsed_minutes > budget.overall_max_minutes) fail("overall usage: sums or ceilings");
  let elapsedLowerBound;
  if (mode === "sequential_fallback") {
    if (Object.hasOwn(process, "wave_coverage")) fail("sequential fallback: wave coverage is delegated-only");
    elapsedLowerBound = records.reduce((sum, record) => sum + (record.search_resource_usage?.elapsed_minutes ?? 0), 0);
  }
  else {
    const waves = process.wave_coverage;
    if (!Array.isArray(waves) || waves.length === 0) { fail("delegated schedule: wave coverage required"); elapsedLowerBound = Infinity; }
    else {
      const waveIds = new Set(); const covered = [];
      elapsedLowerBound = 0;
      for (const wave of waves) {
        if (!exactKeys(wave, ["wave_id", "capacity", "lens_kinds"], "wave coverage") || !nonblank(wave.wave_id) || !Number.isInteger(wave.capacity) || wave.capacity < 1 || !Array.isArray(wave.lens_kinds) || wave.lens_kinds.length === 0) { fail("delegated schedule: invalid wave"); continue; }
        if (waveIds.has(wave.wave_id) || wave.capacity > trustedAdapterCapacity || new Set(wave.lens_kinds).size !== wave.lens_kinds.length || wave.lens_kinds.length > wave.capacity) fail("delegated schedule: duplicate or over-capacity wave");
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
function sourceReferencesValid(sources, evidenceStatus, gaps, label) {
  if (!Array.isArray(sources) || !sources.every(nonblank)) { fail(`${label}: nonblank source identifiers required`); return; }
  if (!['source_backed', 'inference_only', 'unresolved'].includes(evidenceStatus)) fail(`${label}: evidence status`);
  if (!Array.isArray(gaps) || !gaps.every(nonblank)) fail(`${label}: nonblank gaps array required`);
  if (evidenceStatus === 'source_backed' && sources.length === 0) fail(`${label}: source-backed result requires a source`);
  if (['inference_only', 'unresolved'].includes(evidenceStatus) && sources.length === 0 && gaps.length === 0) fail(`${label}: empty non-source evidence requires a gap`);
  for (const source of sources) sourceReferenceValid(source, label);
}
function sourceReferenceValid(source, label) {
  if (!nonblank(source)) { fail(`${label}: nonblank source identifiers required`); return false; }
  if (malformedUrlSchemeLike(source)) { fail(`${label}: malformed URL source`); return false; }
  if (/^https?:\/\//i.test(source)) {
    if (!publicUrlValid(source)) { fail(`${label}: non-public URL source`); return false; }
    return true;
  }
  let decoded;
  try { decoded = decodeURIComponent(source); } catch { fail(`${label}: invalid source encoding`); return false; }
  if (decoded !== source && (/^https?:\/\//i.test(decoded) || malformedUrlSchemeLike(decoded))) {
    if (malformedUrlSchemeLike(decoded) || !publicUrlValid(decoded)) { fail(`${label}: non-public URL source`); return false; }
    return true;
  }
  if (decoded !== source && encodedHttpSchemeLike(decoded)) { fail(`${label}: multiply encoded URL source`); return false; }
  let parsed; try { parsed = new URL(source); } catch { parsed = undefined; }
  if ((parsed && ["http:", "https:"].includes(parsed.protocol)) || /^[A-Za-z][A-Za-z0-9+.-]*:\/\//.test(source)) {
    if (!publicUrlValid(source)) { fail(`${label}: non-public URL source`); return false; }
  } else if (unsafeOpaqueReference(source)) {
    fail(`${label}: unsafe source reference`);
    return false;
  }
  return true;
}
function acceptedResultValid(result, label) {
  if (!["core_position", "lens_question", "answer_or_gap", "likely_blind_spot", "unique_insight"].every(key => nonblank(result[key])) || !["high", "medium", "low"].includes(result.confidence)) fail(`${label}: required result fields`);
  sourceReferencesValid(result.sources_or_verified_urls, result.evidence_status, result.gaps, label);
  if (["inference_only", "unresolved"].includes(result.evidence_status) && Array.isArray(result.sources_or_verified_urls) && result.sources_or_verified_urls.length === 0 && result.confidence !== "low") fail(`${label}: source-empty inference or unresolved result requires low confidence`);
  if (!Array.isArray(result.follow_ups) || result.follow_ups.length === 0) { fail(`${label}: follow-ups required`); return; }
  const noneNeeded = result.follow_ups.filter(followUp => followUp?.decision === "none_needed");
  if ((noneNeeded.length > 0 && (noneNeeded.length !== 1 || result.follow_ups.length !== 1)) || (noneNeeded.length === 0 && !result.follow_ups.every(followUp => followUp?.decision === "follow_up"))) fail(`${label}: follow-up none_needed exclusivity`);
  for (const followUp of result.follow_ups) {
    const followUpKeys = followUp?.decision === "follow_up" ? ["decision", "question", "answer_or_gap", "sources_or_verified_urls", "evidence_status", "gaps"] : ["decision", "answer_or_gap", "sources_or_verified_urls", "evidence_status", "gaps"];
    if (!exactKeys(followUp, followUpKeys, `${label} follow-up`) || !["follow_up", "none_needed"].includes(followUp?.decision) || !nonblank(followUp?.answer_or_gap) || (followUp?.decision === "follow_up" && !nonblank(followUp?.question))) { fail(`${label}: follow-up shape`); continue; }
    sourceReferencesValid(followUp.sources_or_verified_urls, followUp.evidence_status, followUp.gaps, `${label} follow-up`);
  }
}
function validTimestamp(value) {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(value) && Number.isFinite(Date.parse(value));
}
function synthesisValid(synthesis, highStakesApplicable, label) {
  const keys = highStakesApplicable ? [...synthesisBaseKeys, "high_stakes_caveat"] : synthesisBaseKeys;
  if (!exactKeys(synthesis, keys, label) || !nonblank(synthesis?.executive_summary) || !Array.isArray(synthesis?.ranked_key_findings) || synthesis.ranked_key_findings.length < 3 || !synthesis.ranked_key_findings.every(nonblank) || !nonblank(synthesis?.hidden_connection) || !nonblank(synthesis?.actionable_implication) || !["do", "wait", "avoid", "investigate_further"].includes(synthesis?.recommendation) || !nonblank(synthesis?.frontier_question) || (highStakesApplicable && !nonblank(synthesis?.high_stakes_caveat))) {
    fail(`${label}: exact synthesis shape`);
    return false;
  }
  return true;
}
function unsafeOpaqueReference(value) {
  let decoded;
  try { decoded = decodeURIComponent(value); } catch { return true; }
  return malformedUrlSchemeLike(value) || encodedHttpSchemeLike(decoded) || !decodedOpaqueReferenceSafetyValid(value);
}
function encodedHttpSchemeLike(value) {
  return typeof value === "string" && !/^https?:\/\//i.test(value) && /^(?:h|%(?:25)*(?:68|48))(?:t|%(?:25)*(?:74|54))(?:t|%(?:25)*(?:74|54))(?:p|%(?:25)*(?:70|50))(?:(?:s|%(?:25)*(?:73|53))?(?::|%(?:25)*3a)(?:\/|%(?:25)*2f){2})/i.test(value);
}
function malformedUrlSchemeLike(value) {
  return typeof value === "string" && (/^\/\//.test(value) || /^https?(?::(?!\/\/)|\/(?!\/)|\/\/(?!\/))/i.test(value));
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
function canonicalPercentEncodedComponent(value) {
  if (typeof value !== "string" || /%(?![0-9a-f]{2})/i.test(value)) return undefined;
  return value.replace(/%([0-9a-f]{2})/gi, (match, hex) => {
    const character = String.fromCharCode(Number.parseInt(hex, 16));
    return /^[A-Za-z0-9\-._~]$/.test(character) ? character : `%${hex.toUpperCase()}`;
  });
}
function boundedPublicUrl(value) {
  if (publicUrlValid(value)) return value;
  let decoded;
  try { decoded = decodeURIComponent(value); } catch { return undefined; }
  return decoded !== value && publicUrlValid(decoded) ? decoded : undefined;
}
function publicUrlIdentity(value) {
  const boundedUrl = boundedPublicUrl(value);
  if (!boundedUrl) return undefined;
  const url = new URL(boundedUrl);
  const host = canonicalPercentEncodedComponent(url.hostname.toLowerCase());
  const path = canonicalPercentEncodedComponent(url.pathname);
  const search = canonicalPercentEncodedComponent(url.search);
  const hash = canonicalPercentEncodedComponent(url.hash);
  return host === undefined || path === undefined || search === undefined || hash === undefined
    ? undefined
    : `https://${host}${path}${search}${hash}`;
}
function verifiedSourceEvidenceRowValid(row) {
  const method = row?.verification_method;
  const keys = method === "public_url" ? ["claim", "source", "verification_method", "verification_reference", "verified_url", "verification_detail"] : ["claim", "source", "verification_method", "verification_reference", "verification_detail"];
  if (!row || typeof row !== "object" || Array.isArray(row) || Object.keys(row).sort().join("|") !== [...keys].sort().join("|") || !nonblank(row.claim) || !nonblank(row.source) || !sourceReferenceValid(row.source, "verified source evidence source") || !["public_url", "local_repository", "authenticated_source", "offline_authoritative_source"].includes(method) || !nonblank(row.verification_reference) || !nonblank(row.verification_detail)) return false;
  if (method === "public_url") return row.verified_url === row.verification_reference && boundedPublicUrl(row.verified_url) !== undefined;
  if (method !== "public_url" && unsafeOpaqueReference(row.verification_reference)) return false;
  if (method === "local_repository") return /^(?!\/)(?!.*(?:^|\/)\.\.(?:\/|$))[A-Za-z0-9._/-]+(?:#[A-Za-z0-9._:-]+)?$/.test(row.verification_reference);
  if (method === "authenticated_source") return /^connector:[A-Za-z0-9._-]+\/record:[A-Za-z0-9._-]+$/.test(row.verification_reference);
  return /^(?:citation|isbn|doi):[^\s]+$/i.test(row.verification_reference) && !/:\/\//.test(row.verification_reference) && !/^(?:citation|isbn|doi):(?:\/(?:Users|home|private|var)(?:\/|$)|[A-Za-z]:[\\/]|\\\\)/i.test(row.verification_reference);
}
function verifiedSourceEvidenceValid(rows, label) {
  if (!Array.isArray(rows)) { fail(`${label}: evidence array required`); return false; }
  let valid = true;
  for (const row of rows) if (!verifiedSourceEvidenceRowValid(row)) { fail(`${label}: invalid typed evidence row`); valid = false; }
  return valid;
}
function retainedPacketsValid(process, packetSet, manifest, effectiveTier, budget) {
  const retained = process.frozen_assignment_packets;
  if (!Array.isArray(retained) || retained.length !== lenses.length) { fail("retained packets: exact five required"); return; }
  if (!equal(retained.map(packet => packet?.packet_id), packetSet.packet_manifest_order) || !exactLensSet(retained.map(packet => packet?.lens_kind))) fail("retained packets: ordered lens set");
  const sharedPacketFields = ["question", "tier", "user_role_or_goal", "output_purpose", "known_context", "evidence_budget", "search_resource_budget", "source_policy", "isolation_policy"];
  if (!retained.every(packet => sharedPacketFields.every(field => equal(packet?.[field], retained[0]?.[field])))) fail("retained packets: common scope binding");
  const manifestById = new Map((Array.isArray(manifest) ? manifest : []).map(packet => [packet.packet_id, packet]));
  for (const packet of retained) {
    if (!exactKeys(packet, packetKeys, "retained packet") || !nonblank(packet.packet_id) || !nonblank(packet.packet_set_id) || !nonblank(packet.question) || !nonblank(packet.user_role_or_goal) || !nonblank(packet.output_purpose) || !Array.isArray(packet.known_context) || !packet.known_context.every(nonblank) || !nonblank(packet.evidence_budget) || packet.source_policy !== "verified_sources_only" || packet.isolation_policy !== "sibling_blind_no_synthesis" || !lenses.includes(packet.lens_kind) || !validTimestamp(packet.packet_frozen_at)) { fail("retained packets: shape"); continue; }
    const manifestEntry = manifestById.get(packet.packet_id);
    const preimage = Object.fromEntries(packetKeys.filter(key => key !== "content_digest").map(key => [key, packet[key]]));
    if (packet.packet_set_id !== packetSet?.packet_set_id || packet.tier !== effectiveTier || !equal(packet.search_resource_budget, budget) || !manifestEntry || manifestEntry.lens_kind !== packet.lens_kind || manifestEntry.content_digest !== packet.content_digest || !contentDigest(packet.content_digest) || packet.content_digest !== digest(preimage) || Date.parse(packet.packet_frozen_at) > Date.parse(packetSet?.packet_set_frozen_at) || Date.parse(packet.packet_frozen_at) >= Date.parse(packetSet?.first_lens_execution_at)) fail("retained packets: digest/binding");
  }
}
function peerInputBindingValid(binding, process, accepted, lensMode, response) {
  if (!exactKeys(binding, peerBindingKeys, "peer review input binding") || !contentDigest(binding?.peer_review_input_digest) || !nonblank(binding?.peer_review_assignment_id) || binding.peer_review_assignment_id !== process.peer_review_assignment_id || !Array.isArray(binding.validated_lens_results) || !equal(binding.validated_lens_results, accepted) || !equal(binding.findings, response.findings) || !equal(binding.candidate_mechanisms, response.candidate_mechanisms) || !equal(binding.conflicts, response.conflicts) || !equal(binding.contradiction_map, response.contradiction_map) || !Array.isArray(binding.verification_gaps) || !binding.verification_gaps.every(nonblank) || !equal(binding.verification_gaps, response.gaps)) { fail("peer review input binding: shape/binding"); return false; }
  const provenance = binding.lens_execution_provenance;
  if (!exactKeys(provenance, ["lens_execution_mode", "reduced_independence", "fallback_basis", "fallback_evidence_ref"], "peer lens execution provenance") || provenance.lens_execution_mode !== lensMode || provenance.reduced_independence !== (lensMode === "sequential_fallback")) fail("peer lens execution provenance: process binding");
  if (lensMode === "delegated" && (provenance.fallback_basis !== "not_applicable" || provenance.fallback_evidence_ref !== "not_applicable")) fail("peer lens execution provenance: delegated fallback leakage");
  if (lensMode === "sequential_fallback" && (provenance.fallback_basis !== process.lens_fallback_evidence?.basis || provenance.fallback_evidence_ref !== process.lens_fallback_evidence?.evidence_ref)) fail("peer lens execution provenance: fallback binding");
  const evidenceValid = verifiedSourceEvidenceValid(binding.verified_source_evidence, "peer review input binding");
  if (Array.isArray(binding.verified_source_evidence) && binding.verified_source_evidence.length === 0 && binding.verification_gaps.length === 0) fail("peer review input binding: empty evidence requires gaps");
  const highStakes = binding.high_stakes_context;
  if (!exactKeys(highStakes, ["applicable", "caveat_or_not_applicable_reason", "user_context_status", "user_context_basis"], "peer high-stakes context") || typeof highStakes?.applicable !== "boolean" || !nonblank(highStakes?.caveat_or_not_applicable_reason) || !["explicit", "unresolved", "not_applicable"].includes(highStakes?.user_context_status) || !nonblank(highStakes?.user_context_basis) || (highStakes.applicable && !["explicit", "unresolved"].includes(highStakes.user_context_status)) || (!highStakes.applicable && (highStakes.caveat_or_not_applicable_reason !== "not_applicable" || highStakes.user_context_status !== "not_applicable" || highStakes.user_context_basis !== "not_applicable"))) fail("peer high-stakes context: shape");
  const preimage = Object.fromEntries(peerBindingKeys.filter(key => key !== "peer_review_input_digest").map(key => [key, binding[key]]));
  if (binding.peer_review_input_digest !== digest(preimage)) fail("peer review input binding: digest");
  return evidenceValid;
}
function substantiveText(values) {
  return values.filter(nonblank).join("\n");
}
function semanticContextValid(fixtureCase, retainedPackets, accepted, response, binding) {
  const context = fixtureCase?.semantic_context;
  if (!exactKeys(context, ["packet_scope", "follow_up_requirements", "required_topic_terms", "high_stakes_context", "adapter_context"], "semantic context") || !exactKeys(context?.packet_scope, ["question", "user_role_or_goal", "output_purpose"], "semantic packet scope") || !Object.values(context.packet_scope).every(nonblank) || !Array.isArray(context.follow_up_requirements) || !Array.isArray(context.required_topic_terms) || !context.required_topic_terms.every(nonblank) || new Set(context.required_topic_terms).size !== context.required_topic_terms.length || !exactKeys(context.adapter_context, ["max_concurrent_lens_workers"], "semantic adapter context") || !Number.isSafeInteger(context.adapter_context.max_concurrent_lens_workers) || context.adapter_context.max_concurrent_lens_workers < 1) { fail("semantic context: required shape"); return; }
  const trustedHighStakes = context.high_stakes_context;
  const trustedHighStakesValid = exactKeys(trustedHighStakes, ["applicable", "caveat_or_not_applicable_reason", "user_context_status", "user_context_basis"], "semantic high-stakes context")
    && typeof trustedHighStakes.applicable === "boolean"
    && nonblank(trustedHighStakes.caveat_or_not_applicable_reason)
    && ["explicit", "unresolved", "not_applicable"].includes(trustedHighStakes.user_context_status)
    && nonblank(trustedHighStakes.user_context_basis)
    && ((trustedHighStakes.applicable && ["explicit", "unresolved"].includes(trustedHighStakes.user_context_status))
      || (!trustedHighStakes.applicable && trustedHighStakes.caveat_or_not_applicable_reason === "not_applicable" && trustedHighStakes.user_context_status === "not_applicable" && trustedHighStakes.user_context_basis === "not_applicable"));
  if (!trustedHighStakesValid) { fail("semantic context: high-stakes binding"); return; }
  if (!equal(binding?.high_stakes_context, trustedHighStakes)) fail("semantic context: high-stakes binding");
  if (trustedHighStakes.user_context_status === "explicit" && !fixtureCase.prompt?.includes(trustedHighStakes.user_context_basis)) fail("semantic context: explicit user context must be prompt-derived");
  const requirementLenses = new Set();
  for (const requirement of context.follow_up_requirements) {
    if (!exactKeys(requirement, ["lens_kind", "decision", "exact_count"], "semantic follow-up requirement") || !lenses.includes(requirement.lens_kind) || requirementLenses.has(requirement.lens_kind) || !["follow_up", "none_needed"].includes(requirement.decision) || !Number.isInteger(requirement.exact_count) || requirement.exact_count < 1) { fail("semantic context: follow-up requirement"); continue; }
    requirementLenses.add(requirement.lens_kind);
    const result = Array.isArray(accepted) ? accepted.find(item => item?.lens_kind === requirement.lens_kind) : undefined;
    if (!result || !Array.isArray(result.follow_ups) || result.follow_ups.length !== requirement.exact_count || !result.follow_ups.every(followUp => followUp?.decision === requirement.decision)) fail("semantic context: follow-up binding");
  }
  if (!Array.isArray(retainedPackets) || retainedPackets.length !== lenses.length || !retainedPackets.every(packet => packet?.question === context.packet_scope.question && packet?.user_role_or_goal === context.packet_scope.user_role_or_goal && packet?.output_purpose === context.packet_scope.output_purpose)) fail("semantic context: packet scope binding");
  const acceptedText = substantiveText((Array.isArray(accepted) ? accepted : []).flatMap(result => [result?.core_position, result?.lens_question, result?.answer_or_gap, result?.likely_blind_spot, result?.unique_insight]));
  const finalClaimText = substantiveText([
    ...(Array.isArray(response?.findings) ? response.findings.flatMap(finding => [finding?.finding]) : []),
    ...(Array.isArray(response?.candidate_mechanisms) ? response.candidate_mechanisms.flatMap(mechanism => [mechanism?.mechanism, ...(Array.isArray(mechanism?.evidence) ? mechanism.evidence.map(evidence => evidence?.detail) : []), ...(Array.isArray(mechanism?.counterevidence_or_conflicts) ? mechanism.counterevidence_or_conflicts : []), ...(Array.isArray(mechanism?.gaps) ? mechanism.gaps : []), mechanism?.validation_method]) : []),
    ...(Array.isArray(response?.conflicts) ? response.conflicts.flatMap(conflict => [conflict?.claim_a, conflict?.claim_b, conflict?.assessment]) : [])
  ]);
  const contradiction = response?.contradiction_map;
  const synthesis = response?.synthesis_briefing;
  const synthesisText = substantiveText([
    ...(Array.isArray(contradiction?.direct_conflicts) ? contradiction.direct_conflicts : []),
    contradiction?.strongest_evidence,
    contradiction?.weakest_evidence,
    ...(Array.isArray(contradiction?.consensus) ? contradiction.consensus : []),
    contradiction?.biggest_unresolved_question,
    contradiction?.missing_angle_or_gap,
    synthesis?.executive_summary,
    ...(Array.isArray(synthesis?.ranked_key_findings) ? synthesis.ranked_key_findings : []),
    synthesis?.hidden_connection,
    synthesis?.actionable_implication,
    synthesis?.high_stakes_caveat,
    synthesis?.frontier_question,
    response?.summary
  ]);
  const requiredGroups = [acceptedText, synthesisText, ...(nonblank(finalClaimText) ? [finalClaimText] : [])];
  if (!nonblank(acceptedText) || !nonblank(synthesisText)) fail("semantic context: substantive groups required");
  if (!context.required_topic_terms.every(term => requiredGroups.every(group => group.toLowerCase().includes(term.toLowerCase())))) fail("semantic context: required topic term binding");
}
function peerReviewValid(peer, peerMode, process, lensIdentities, rootPasses, binding, finalSynthesisDigest, finalRecommendation) {
  const peerKeys = ["peer_review_execution_mode", "peer_review_assignment_id", "peer_reviewer_identity", "peer_review_fallback_pass_id", "peer_review_input_digest", "status", "verdict", "confidence_scores", "weakest_claim", "bias_or_lens_dominance", "missing_sixth_perspective", "falsification_test", "revised_recommendation_if_needed", "supported_recommendation", "required_revisions", "revision_disposition_id", "revision_disposition", "evidence", "open_questions", "status_detail", "blocker_type", "blocker_evidence"];
  if (!allowedKeys(peer, peerKeys, "peer review") || !peer || typeof peer !== "object" || peer.peer_review_execution_mode !== peerMode || !nonblank(peer.peer_review_assignment_id) || peer.peer_review_assignment_id !== process.peer_review_assignment_id || peer.peer_review_input_digest !== binding?.peer_review_input_digest || !["DONE", "DONE_WITH_CONCERNS", "NEEDS_CONTEXT", "BLOCKED"].includes(peer.status) || !["accepted", "accepted_with_concerns", "revise", "blocked"].includes(peer.verdict)) { fail("peer review: required status/binding"); return; }
  if (peerMode === "delegated") {
    if (!nonblank(peer.peer_reviewer_identity) || lensIdentities.has(peer.peer_reviewer_identity) || process.peer_reviewer_identity !== peer.peer_reviewer_identity) fail("peer review: distinct delegated identity");
  } else if (!nonblank(peer.peer_review_fallback_pass_id) || rootPasses.has(peer.peer_review_fallback_pass_id) || process.peer_review_fallback_pass_id !== peer.peer_review_fallback_pass_id || Object.hasOwn(peer, "peer_reviewer_identity")) fail("peer review: fresh fallback pass");
  const usable = ["DONE", "DONE_WITH_CONCERNS"].includes(peer.status);
  if (peer.status === "DONE" && peer.verdict !== "accepted") fail("peer review: DONE verdict");
  if (peer.status === "DONE_WITH_CONCERNS" && !["accepted_with_concerns", "revise"].includes(peer.verdict)) fail("peer review: DONE_WITH_CONCERNS verdict");
  if (!usable && peer.verdict !== "blocked") fail("peer review: blocked verdict");
  if (usable) {
    const usableFields = ["confidence_scores", "weakest_claim", "bias_or_lens_dominance", "missing_sixth_perspective", "falsification_test", "revised_recommendation_if_needed", "evidence"];
    if (!Array.isArray(peer.confidence_scores) || peer.confidence_scores.length === 0 || !peer.confidence_scores.every(nonblank) || !usableFields.slice(1, 6).every(field => nonblank(peer[field])) || !["do", "wait", "avoid", "investigate_further"].includes(peer.supported_recommendation) || peer.supported_recommendation !== finalRecommendation || !Array.isArray(peer.evidence) || peer.evidence.length === 0) fail("peer review: usable critique fields");
    const peerEvidence = Array.isArray(peer.evidence) ? peer.evidence : [];
    for (const item of peerEvidence) if (!exactKeys(item, ["source", "detail", "evidence_status"], "peer review evidence") || !nonblank(item.source) || !sourceReferenceValid(item.source, "peer review evidence source") || !nonblank(item.detail) || !["source_backed", "inference_only", "unresolved"].includes(item.evidence_status)) fail("peer review: usable evidence");
  } else if (!Array.isArray(peer.open_questions) || peer.open_questions.length === 0 || !peer.open_questions.every(nonblank) || !nonblank(peer.status_detail)) fail("peer review: blocked context fields");
  if (peer.status === "BLOCKED" && (!["missing_review_context", "policy_blocked", "tool_failure"].includes(peer.blocker_type) || !Array.isArray(peer.blocker_evidence) || peer.blocker_evidence.length === 0 || !peer.blocker_evidence.every(nonblank))) fail("peer review: blocker fields");
  if (!usable) fail("peer review: non-final status");
  const requiredRevisions = Array.isArray(peer.required_revisions) ? peer.required_revisions : [];
  if (["accepted", "accepted_with_concerns"].includes(peer.verdict)) {
    if (!Array.isArray(peer.required_revisions) || requiredRevisions.length !== 0 || Object.hasOwn(peer, "revision_disposition_id") || Object.hasOwn(peer, "revision_disposition")) fail("peer review: accepted revision closure");
    if (!contentDigest(finalSynthesisDigest) || digest(binding?.initial_synthesis) !== finalSynthesisDigest) fail("peer review: accepted synthesis must equal initial");
  }
  if (peer.verdict !== "revise" && (Object.hasOwn(process, "peer_review_revision_disposition_id") || Object.hasOwn(peer, "revision_disposition_id") || Object.hasOwn(peer, "revision_disposition"))) fail("peer review: non-revise revision closure leakage");
  if (peer.verdict === "revise") {
    if (!Array.isArray(peer.required_revisions) || requiredRevisions.length === 0 || !requiredRevisions.every(nonblank) || new Set(requiredRevisions).size !== requiredRevisions.length || !nonblank(peer.revision_disposition_id) || !Array.isArray(peer.revision_disposition) || peer.revision_disposition.length !== requiredRevisions.length || process.peer_review_revision_disposition_id !== peer.revision_disposition_id) fail("peer review: revision closure required");
    const closed = new Set();
    const revisionDisposition = Array.isArray(peer.revision_disposition) ? peer.revision_disposition : [];
    for (const disposition of revisionDisposition) {
      if (!exactKeys(disposition, ["required_revision", "outcome", "closure_evidence", "resulting_synthesis_digest"], "peer revision disposition") || !requiredRevisions.includes(disposition.required_revision) || closed.has(disposition.required_revision) || !["applied", "claim_downgraded"].includes(disposition.outcome) || !nonblank(disposition.closure_evidence) || disposition.resulting_synthesis_digest !== finalSynthesisDigest) fail("peer review: invalid revision disposition");
      closed.add(disposition?.required_revision);
    }
    if (closed.size !== requiredRevisions.length || digest(binding?.initial_synthesis) === finalSynthesisDigest) fail("peer review: revision closure must change synthesis");
  }
}
function verifiedEvidenceAliases(binding) {
  const rows = (Array.isArray(binding?.verified_source_evidence) ? binding.verified_source_evidence : []).filter(verifiedSourceEvidenceRowValid);
  return new Map(rows.flatMap(row => {
    const reference = row.verification_method === "public_url" ? publicUrlIdentity(row.verified_url) : row.verification_reference;
    const identity = `ledger:${row.verification_method}:${reference}`;
    return row.verification_method === "public_url" ? [[row.source, identity], [row.verified_url, identity], [reference, identity]] : [[row.source, identity]];
  }));
}
function canonicalEvidenceIdentity(source, aliases) {
  return aliases.get(source) || aliases.get(publicUrlIdentity(source)) || publicUrlIdentity(source) || source;
}
function candidateMechanismsValid(mechanisms, binding) {
  if (!Array.isArray(mechanisms)) { fail("candidate mechanisms: array required"); return; }
  const evidenceSourceAliases = verifiedEvidenceAliases(binding);
  for (const mechanism of mechanisms) {
    const evidence = mechanism?.evidence;
    const validEvidence = Array.isArray(evidence) && evidence.length > 0 && evidence.every(row => exactKeys(row, ["source", "detail", "evidence_status"], "candidate mechanism evidence") && nonblank(row.source) && sourceReferenceValid(row.source, "candidate mechanism evidence source") && nonblank(row.detail) && ["source_backed", "inference_only", "unresolved"].includes(row.evidence_status));
    const sourceBackedIdentities = new Set((Array.isArray(evidence) ? evidence : []).filter(row => row?.evidence_status === "source_backed").map(row => canonicalEvidenceIdentity(row.source, evidenceSourceAliases)));
    const unresolvedEvidence = Array.isArray(evidence) && evidence.some(row => row?.evidence_status === "unresolved");
    const confidenceValid = mechanism?.confidence === "low" || (!unresolvedEvidence && sourceBackedIdentities.size >= 2 && (mechanism?.confidence !== "high" || sourceBackedIdentities.size >= 3));
    if (!exactKeys(mechanism, ["mechanism", "claim_status", "evidence", "confidence", "counterevidence_or_conflicts", "gaps", "validation_method"], "candidate mechanism") || !nonblank(mechanism?.mechanism) || !["candidate", "needs_validation", "unsupported", "rejected"].includes(mechanism?.claim_status) || !validEvidence || !["high", "medium", "low"].includes(mechanism?.confidence) || !confidenceValid || !Array.isArray(mechanism?.counterevidence_or_conflicts) || !mechanism.counterevidence_or_conflicts.every(nonblank) || !Array.isArray(mechanism?.gaps) || !mechanism.gaps.every(nonblank) || !nonblank(mechanism?.validation_method)) fail("candidate mechanisms: closed-world shape");
  }
}
function finalArtifactsValid(response, accepted, binding) {
  const findings = response.findings;
  const evidenceEmpty = item => ["inference_only", "unresolved"].includes(item?.evidence_status) && Array.isArray(item.sources_or_verified_urls) && item.sources_or_verified_urls.length === 0;
  const evidenceEmptyCompletion = Array.isArray(accepted) && accepted.length === lenses.length && accepted.every(result => evidenceEmpty(result) && Array.isArray(result.follow_ups) && result.follow_ups.every(evidenceEmpty));
  if (!Array.isArray(findings) || (findings.length === 0 && (!evidenceEmptyCompletion || !Array.isArray(response.gaps) || response.gaps.length === 0))) fail("final artifacts: findings required unless evidence-empty completion has gaps");
  const acceptedSources = new Set((Array.isArray(accepted) ? accepted : []).flatMap(result => [
    ...(Array.isArray(result?.sources_or_verified_urls) ? result.sources_or_verified_urls : []),
    ...(Array.isArray(result?.follow_ups) ? result.follow_ups.flatMap(followUp => Array.isArray(followUp?.sources_or_verified_urls) ? followUp.sources_or_verified_urls : []) : [])
  ]));
  const verifiedEvidenceRows = (Array.isArray(binding?.verified_source_evidence) ? binding.verified_source_evidence : []).filter(verifiedSourceEvidenceRowValid);
  const verifiedSourceIdentities = new Set(verifiedEvidenceRows.flatMap(row => row.verification_method === "public_url" ? [row.source, row.verified_url, publicUrlIdentity(row.verified_url)] : [row.source]));
  const verifiedUrlIdentities = new Set(verifiedEvidenceRows.filter(row => row.verification_method === "public_url").flatMap(row => [row.verified_url, publicUrlIdentity(row.verified_url)]));
  const acceptedSourceIdentities = new Set([...acceptedSources].flatMap(source => [source, publicUrlIdentity(source)].filter(Boolean)));
  const evidenceSourceAliases = verifiedEvidenceAliases(binding);
  for (const finding of Array.isArray(findings) ? findings : []) {
    const provenance = finding?.source_provenance;
    const sourceSet = new Set(Array.isArray(finding?.sources) ? finding.sources : []);
    const provenanceSourceSet = new Set(Array.isArray(provenance) ? provenance.map(row => row?.source) : []);
    const provenanceValid = Array.isArray(provenance) && provenance.length === provenanceSourceSet.size && provenance.every(row => exactKeys(row, ["source", "independence_key", "authority"], "final finding source provenance") && nonblank(row.source) && sourceReferenceValid(row.source, "final finding provenance source") && nonblank(row.independence_key) && ["primary", "official", "secondary"].includes(row.authority)) && sourceSet.size === provenanceSourceSet.size && [...sourceSet].every(source => provenanceSourceSet.has(source));
    const sourceResolved = Array.isArray(finding?.sources) && finding.sources.every(source => acceptedSources.has(source) || acceptedSourceIdentities.has(source) || acceptedSourceIdentities.has(publicUrlIdentity(source)) || verifiedSourceIdentities.has(source) || verifiedSourceIdentities.has(publicUrlIdentity(source)));
    const canonicalSourceSet = new Set([...sourceSet].map(source => canonicalEvidenceIdentity(source, evidenceSourceAliases)));
    const mediumConfidenceValid = finding?.confidence !== "medium" || canonicalSourceSet.size >= 2 || (provenanceValid && provenance.length === 1 && ["primary", "official"].includes(provenance[0].authority));
    const verifiedUrlsResolved = !Object.hasOwn(finding, "verified_urls") || (Array.isArray(finding.verified_urls) && finding.verified_urls.every(url => publicUrlValid(url) && (acceptedSourceIdentities.has(url) || acceptedSourceIdentities.has(publicUrlIdentity(url)) || verifiedUrlIdentities.has(url) || verifiedUrlIdentities.has(publicUrlIdentity(url)))));
    if (!allowedKeys(finding, ["finding", "confidence", "sources", "verified_urls", "source_provenance"], "final finding") || !nonblank(finding?.finding) || !["high", "medium", "low"].includes(finding?.confidence) || !Array.isArray(finding?.sources) || finding.sources.length === 0 || !finding.sources.every(source => sourceReferenceValid(source, "final finding source")) || !sourceResolved || !verifiedUrlsResolved || (Object.hasOwn(finding, "source_provenance") && !provenanceValid) || !mediumConfidenceValid || (finding.confidence === "high" && (!provenanceValid || canonicalSourceSet.size < 3 || new Set(provenance.map(row => row.independence_key)).size < 3 || !provenance.some(row => ["primary", "official"].includes(row.authority))))) fail("final artifacts: finding shape");
  }
  candidateMechanismsValid(response.candidate_mechanisms, binding);
  const conflicts = response.conflicts;
  if (!Array.isArray(conflicts)) fail("final artifacts: conflicts array required");
  for (const conflict of Array.isArray(conflicts) ? conflicts : []) if (!exactKeys(conflict, ["claim_a", "source_a", "claim_b", "source_b", "assessment"], "final conflict") || !Object.values(conflict).every(nonblank) || !sourceReferenceValid(conflict.source_a, "final conflict source_a") || !sourceReferenceValid(conflict.source_b, "final conflict source_b")) fail("final artifacts: conflict shape");
  if (!Array.isArray(response.gaps) || !response.gaps.every(nonblank) || !nonblank(response.summary)) fail("final artifacts: gaps and summary required");
  const contradiction = response.contradiction_map;
  if (!exactKeys(contradiction, ["direct_conflicts", "strongest_evidence", "weakest_evidence", "consensus", "biggest_unresolved_question", "missing_angle_or_gap"], "contradiction map") || !Array.isArray(contradiction.direct_conflicts) || !contradiction.direct_conflicts.every(nonblank) || !Array.isArray(contradiction.consensus) || !contradiction.consensus.every(nonblank) || !["strongest_evidence", "weakest_evidence", "biggest_unresolved_question", "missing_angle_or_gap"].every(field => nonblank(contradiction[field]))) fail("final artifacts: contradiction map");
}
function highStakesRecommendationValid(response, binding, peer, retainedPackets, fixtureCase) {
  const trustedHighStakes = fixtureCase?.semantic_context?.high_stakes_context;
  if (!equal(binding?.high_stakes_context, trustedHighStakes)) { fail("high-stakes recommendation: trusted context binding"); return; }
  if (trustedHighStakes?.user_context_status === "explicit" && !fixtureCase.prompt?.includes(trustedHighStakes.user_context_basis)) { fail("high-stakes recommendation: explicit context must be prompt-derived"); return; }
  const applicable = trustedHighStakes?.applicable === true;
  const recommendation = response.synthesis_briefing?.recommendation;
  const basis = response.high_stakes_recommendation_basis;
  if (!applicable || recommendation === "investigate_further") {
    if (Object.hasOwn(response, "high_stakes_recommendation_basis")) fail("high-stakes recommendation: unexpected basis");
    return;
  }
  const basisKeys = ["recommendation", "verified_decision_critical_urls", "user_context_basis", "peer_review_input_digest", "peer_supported_recommendation"];
  if (!exactKeys(basis, basisKeys, "high-stakes recommendation basis") || trustedHighStakes.user_context_status !== "explicit" || basis.recommendation !== recommendation || !Array.isArray(basis.verified_decision_critical_urls) || basis.verified_decision_critical_urls.length === 0 || !basis.verified_decision_critical_urls.every(publicUrlValid) || !nonblank(basis.user_context_basis) || basis.user_context_basis === "not_applicable" || basis.user_context_basis !== trustedHighStakes.user_context_basis || basis.peer_review_input_digest !== binding.peer_review_input_digest || basis.peer_supported_recommendation !== peer?.supported_recommendation || basis.peer_supported_recommendation !== recommendation) { fail("high-stakes recommendation: binding"); return; }
  const publicEvidenceUrls = new Set((Array.isArray(binding.verified_source_evidence) ? binding.verified_source_evidence : []).filter(row => row?.verification_method === "public_url" && row.verified_url === row.verification_reference && publicUrlValid(row.verified_url)).map(row => row.verified_url));
  if (!basis.verified_decision_critical_urls.every(url => publicEvidenceUrls.has(url))) fail("high-stakes recommendation: public evidence binding");
  if (!Array.isArray(retainedPackets) || retainedPackets.length !== lenses.length || !retainedPackets.every(packet => Array.isArray(packet.known_context) && packet.known_context.includes(basis.user_context_basis))) fail("high-stakes recommendation: retained user context binding");
}
let fixtureCase;
try {
  const fixture = JSON.parse(fs.readFileSync(fixturePath, "utf8"));
  fixtureCase = Array.isArray(fixture?.cases) ? fixture.cases.find(item => item?.id === caseId) : undefined;
  if (!fixtureCase) fail("semantic context: selected fixture case required");
} catch { fail("semantic context: readable fixture case required"); }
let response;
try { response = JSON.parse(fs.readFileSync(responsePath, "utf8")); } catch { fail("response: valid JSON required"); }
if (response) {
  validateUnicode(response);
  if (!Object.hasOwn(response, "candidate_mechanisms")) response.candidate_mechanisms = [];
  if (response.research_method !== "five_lens_briefing") fail("response: five_lens_briefing required");
  const process = response.five_lens_process_evidence;
  const lensMode = process?.lens_execution_mode;
  const peerMode = process?.peer_review_execution_mode;
  if (!process || !["delegated", "sequential_fallback"].includes(lensMode) || !["delegated", "sequential_fallback"].includes(peerMode)) fail("process: supported execution modes required");
  else {
    const processKeys = ["lens_execution_mode", "peer_review_execution_mode", "subagent_policy_state", "subagent_trigger_scope", "policy_blocking_source", "tier_resolution", "frozen_packet_set", "frozen_assignment_packet_ids", "frozen_assignment_packets", "search_resource_budget", "accepted_lens_results", "lens_dispatches", "fallback_lens_passes", "wave_coverage", "root_synthesis_ownership", "peer_reviewer_identity", "peer_review_assignment_id", "peer_review_revision_disposition_id", "peer_review_fallback_pass_id", "lens_fallback_evidence", "peer_review_fallback_evidence", "reduced_independence", "overall_resource_usage", "peer_review_input_binding", "final_synthesis_digest"];
    allowedKeys(process, processKeys, "five-lens process evidence");
    const records = Array.isArray(lensMode === "delegated" ? process.lens_dispatches : process.fallback_lens_passes) ? (lensMode === "delegated" ? process.lens_dispatches : process.fallback_lens_passes) : [];
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
    const effectiveTier = tierResolutionValid(process.tier_resolution, response.tier);
    budgetValid(budget, effectiveTier);
    retainedPacketsValid(process, packetSet, manifest, effectiveTier, budget);
    const identities = new Set(); const rootPasses = new Set(); const assignmentIds = new Set();
    const perspectiveScan = Array.isArray(response.perspective_scan) ? response.perspective_scan : [];
    const questionTrace = Array.isArray(response.question_trace) ? response.question_trace : [];
    if (!Array.isArray(response.perspective_scan)) fail("perspective scan: array required");
    if (!Array.isArray(response.question_trace)) fail("question trace: array required");
    if (!exactLensSet(perspectiveScan.map(item => item?.lens))) fail("perspective scan: exact five unique lenses required");
    if (!exactLensSet(questionTrace.map(item => item?.lens))) fail("question trace: exact five unique lenses required");
    for (const record of records || []) {
      const label = `lens record ${record?.lens_kind || "unknown"}`;
      const recordKeys = lensMode === "delegated" ? ["lens_kind", "dispatch_identity", "assignment_id", "packet_id", "packet_set_id", "packet_content_digest", "lens_result_digest", "search_resource_usage", "wave_id", "return_validated"] : ["lens_kind", "assignment_id", "packet_id", "packet_set_id", "packet_content_digest", "lens_result_digest", "search_resource_usage", "root_pass_id", "return_validated"];
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
      if (lensMode === "delegated") { if (!nonblank(record.dispatch_identity) || identities.has(record.dispatch_identity)) fail(`${label}: unique native identity`); identities.add(record.dispatch_identity); }
      else { if (!nonblank(record.root_pass_id) || rootPasses.has(record.root_pass_id)) fail(`${label}: unique fallback pass`); rootPasses.add(record.root_pass_id); }
      usageValid(record.search_resource_usage, budget || {}, lensResult, label);
      const perspective = perspectiveScan.find(item => item?.lens === record.lens_kind);
      const trace = questionTrace.find(item => item?.lens === record.lens_kind);
      if (!perspective || !equal(perspective, {lens: result.lens_kind, assignment_id: result.assignment_id, lens_result_digest: result.lens_result_digest, core_position: result.core_position, sources_or_verified_urls: result.sources_or_verified_urls, likely_blind_spot: result.likely_blind_spot, unique_insight: result.unique_insight, confidence: result.confidence})) fail(`${label}: perspective projection`);
      if (!trace || !equal(trace, {lens: result.lens_kind, assignment_id: result.assignment_id, lens_result_digest: result.lens_result_digest, question: result.lens_question, answer: result.answer_or_gap, sources_or_verified_urls: result.sources_or_verified_urls, follow_ups: result.follow_ups, evidence_status: result.evidence_status})) fail(`${label}: question trace projection`);
    }
    if (!exactLensSet((records || []).map(record => record?.lens_kind))) fail("process: records must cover each lens once");
    overallUsageValid(process.overall_resource_usage, budget || {}, records || [], lensMode, process, fixtureCase?.semantic_context?.adapter_context?.max_concurrent_lens_workers);
    if (process.root_synthesis_ownership !== "orchestrator_only") fail("process: root synthesis ownership");
    if (process.reduced_independence !== (lensMode === "sequential_fallback" || peerMode === "sequential_fallback")) fail("process: reduced-independence mode binding");
    if (lensMode === "delegated") {
      if (process.subagent_policy_state !== "delegation_triggered" || !Array.isArray(process.subagent_trigger_scope) || process.subagent_trigger_scope.length === 0 || !process.subagent_trigger_scope.every(nonblank) || Object.hasOwn(process, "fallback_lens_passes") || Object.hasOwn(process, "lens_fallback_evidence") || Object.hasOwn(process, "policy_blocking_source")) fail("process: delegated lens lifecycle");
    } else {
      const lensFallback = process.lens_fallback_evidence;
      const fallbackPairValid = (process.subagent_policy_state === "delegation_opted_out" && lensFallback?.basis === "explicit_opt_out")
        || (process.subagent_policy_state === "subagents_unavailable" && ["spawn_failure_or_unavailable", "supported_configuration_proof"].includes(lensFallback?.basis))
        || (process.subagent_policy_state === "policy_disallowed" && lensFallback?.basis === "exact_policy_block");
      const policyBlockingSourceValid = process.subagent_policy_state === "policy_disallowed"
        ? nonblank(process.policy_blocking_source)
        : !Object.hasOwn(process, "policy_blocking_source");
      if (!fallbackPairValid || !lensFallback || !nonblank(lensFallback.detail) || !nonblank(lensFallback.evidence_ref) || !policyBlockingSourceValid || Object.hasOwn(process, "lens_dispatches") || Object.hasOwn(process, "subagent_trigger_scope")) fail("process: fallback lens lifecycle");
    }
    if (peerMode === "delegated") {
      if (!nonblank(process.peer_reviewer_identity) || !nonblank(process.peer_review_assignment_id) || ["delegation_opted_out", "policy_disallowed"].includes(process.subagent_policy_state) || Object.hasOwn(process, "peer_review_fallback_pass_id") || Object.hasOwn(process, "peer_review_fallback_evidence")) fail("process: delegated peer lifecycle");
    } else if (!nonblank(process.peer_review_assignment_id) || !nonblank(process.peer_review_fallback_pass_id) || !process.peer_review_fallback_evidence || !["explicit_opt_out", "spawn_failure_or_unavailable", "supported_configuration_proof", "exact_policy_block"].includes(process.peer_review_fallback_evidence.basis) || (process.subagent_policy_state === "delegation_opted_out" && process.peer_review_fallback_evidence.basis !== "explicit_opt_out") || (process.subagent_policy_state === "policy_disallowed" && process.peer_review_fallback_evidence.basis !== "exact_policy_block") || !nonblank(process.peer_review_fallback_evidence.detail) || !nonblank(process.peer_review_fallback_evidence.evidence_ref) || Object.hasOwn(process, "peer_reviewer_identity")) fail("process: fallback peer lifecycle");
    const binding = process.peer_review_input_binding;
    if (!peerInputBindingValid(binding, process, accepted, lensMode, response)) fail("peer review input binding: invalid evidence");
    finalArtifactsValid(response, accepted, binding);
    semanticContextValid(fixtureCase, process.frozen_assignment_packets, accepted, response, binding);
    const highStakesApplicable = fixtureCase?.semantic_context?.high_stakes_context?.applicable === true;
    synthesisValid(response.synthesis_briefing, highStakesApplicable, "synthesis briefing");
    synthesisValid(binding?.initial_synthesis, highStakesApplicable, "peer initial synthesis");
    if (!equal(binding?.initial_synthesis, response.synthesis_briefing) && ["accepted", "accepted_with_concerns"].includes(response.peer_review?.verdict)) fail("peer review: accepted initial/final synthesis drift");
    if (!contentDigest(process.final_synthesis_digest) || process.final_synthesis_digest !== digest(response.synthesis_briefing)) fail("final synthesis: digest");
    peerReviewValid(response.peer_review, peerMode, process, identities, rootPasses, binding, process.final_synthesis_digest, response.synthesis_briefing?.recommendation);
    highStakesRecommendationValid(response, binding, response.peer_review, process.frozen_assignment_packets, fixtureCase);
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
    local fixture_file="$3"
    local case_id="$4"

    case "$validator_id" in
        assistant-research.five_lens_v3) assistant_research_five_lens_v3_valid "$response_path" "$fixture_file" "$case_id" ;;
        *)
            echo "Unknown semantic validator: $validator_id" >&2
            return 1
            ;;
    esac
}
