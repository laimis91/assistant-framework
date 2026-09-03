if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

research_skill="$FRAMEWORK_DIR/skills/assistant-research/SKILL.md"
research_reference="$FRAMEWORK_DIR/skills/assistant-research/research.md"
five_lens_reference="$FRAMEWORK_DIR/skills/assistant-research/five-lens-briefing.md"
research_index="$FRAMEWORK_DIR/skills/assistant-research/contracts/index.yaml"
research_output="$FRAMEWORK_DIR/skills/assistant-research/contracts/output.yaml"
research_phase_gates="$FRAMEWORK_DIR/skills/assistant-research/contracts/phase-gates.yaml"
research_handoffs="$FRAMEWORK_DIR/skills/assistant-research/contracts/handoffs.yaml"
research_evals="$FRAMEWORK_DIR/skills/assistant-research/evals/cases.json"
research_eval_runner="$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh"

write_research_eval_responses() {
    local output_dir="$1"
    local case_id

    mkdir -p "$output_dir/assistant-research"
    while IFS= read -r case_id; do
        if [[ "$case_id" == "five-lens-decision-briefing-uses-storm-style-workflow" ]] \
            && jq -e --arg case_id "$case_id" '
                .cases[] | select(.id == $case_id)
                | (.machine_expectations.structured_json_assertions? // [] | length > 0)
            ' "$research_evals" >/dev/null; then
            write_delegated_five_lens_eval_response "$output_dir/assistant-research/$case_id.txt"
        else
            jq -r --arg case_id "$case_id" '
                .cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[]
            ' "$research_evals" >"$output_dir/assistant-research/$case_id.txt"
        fi
    done < <(jq -r '.cases[].id' "$research_evals")
}

write_delegated_five_lens_eval_response() {
    local response_path="$1"
    local report

    report="$(jq -r '
        .cases[] | select(.id == "five-lens-decision-briefing-uses-storm-style-workflow")
        | .machine_expectations.required_substrings | join("\\n")
    ' "$research_evals")"
    jq -n --arg report "$report" '
      {
        report: $report,
        research_method: "five_lens_briefing",
        tier: "extensive",
        peer_review: {
          peer_review_execution_mode: "delegated",
          peer_review_assignment_id: "peer-assignment-1",
          peer_reviewer_identity: "peer-native-1",
          status: "DONE_WITH_CONCERNS",
          verdict: "revise",
          required_revisions: ["downgrade unsupported claim"],
          revision_disposition_id: "revision-closure-1",
          revision_disposition: [
            {required_revision: "downgrade unsupported claim", outcome: "claim_downgraded", closure_evidence: "claim confidence updated"}
          ]
        },
        five_lens_process_evidence: {
          lens_execution_mode: "delegated",
          peer_review_execution_mode: "delegated",
          reduced_independence: false,
          frozen_packet_set: {
            packet_set_id: "packet-set-1",
            packet_set_digest: "sha256:packet-set-1",
            packet_manifest_order: ["packet-practitioner", "packet-academic", "packet-skeptic", "packet-economist", "packet-historian"],
            packet_manifest: [
              {packet_id: "packet-practitioner", lens_kind: "practitioner", content_digest: "sha256:practitioner"},
              {packet_id: "packet-academic", lens_kind: "academic_or_technical_expert", content_digest: "sha256:academic"},
              {packet_id: "packet-skeptic", lens_kind: "skeptic", content_digest: "sha256:skeptic"},
              {packet_id: "packet-economist", lens_kind: "economist_or_incentives_analyst", content_digest: "sha256:economist"},
              {packet_id: "packet-historian", lens_kind: "historian_or_pattern_matcher", content_digest: "sha256:historian"}
            ],
            packet_set_frozen_at: "2026-09-03T10:00:00Z",
            pre_dispatch_record_id: "pre-dispatch-1",
            first_lens_execution_at: "2026-09-03T10:01:00Z",
            first_lens_execution_evidence_ref: "execution-log-1"
          },
          lens_dispatches: [
            {lens_kind: "practitioner", dispatch_identity: "lens-native-1", assignment_id: "assignment-1", packet_id: "packet-practitioner", packet_set_id: "packet-set-1", packet_content_digest: "sha256:practitioner", wave_id: "wave-1", return_validated: true},
            {lens_kind: "academic_or_technical_expert", dispatch_identity: "lens-native-2", assignment_id: "assignment-2", packet_id: "packet-academic", packet_set_id: "packet-set-1", packet_content_digest: "sha256:academic", wave_id: "wave-1", return_validated: true},
            {lens_kind: "skeptic", dispatch_identity: "lens-native-3", assignment_id: "assignment-3", packet_id: "packet-skeptic", packet_set_id: "packet-set-1", packet_content_digest: "sha256:skeptic", wave_id: "wave-1", return_validated: true},
            {lens_kind: "economist_or_incentives_analyst", dispatch_identity: "lens-native-4", assignment_id: "assignment-4", packet_id: "packet-economist", packet_set_id: "packet-set-1", packet_content_digest: "sha256:economist", wave_id: "wave-1", return_validated: true},
            {lens_kind: "historian_or_pattern_matcher", dispatch_identity: "lens-native-5", assignment_id: "assignment-5", packet_id: "packet-historian", packet_set_id: "packet-set-1", packet_content_digest: "sha256:historian", wave_id: "wave-1", return_validated: true}
          ],
          peer_review_assignment_id: "peer-assignment-1",
          peer_reviewer_identity: "peer-native-1",
          peer_review_revision_disposition_id: "revision-closure-1"
        }
      }
    ' >"$response_path"
}

research_structured_mutation_is_rejected() {
    local mutation="$1"
    local case_id="five-lens-decision-briefing-uses-storm-style-workflow"
    local case_count eval_dir eval_output response_path mutation_filter

    case_count="$(jq '.cases | length' "$research_evals")"
    eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-structured-negative.XXXXXX")"
    eval_output="$(mktemp "${TMPDIR:-/tmp}/assistant-research-structured-negative-output.XXXXXX")"
    p0p4_register_cleanup "$eval_dir" "$eval_output"
    write_research_eval_responses "$eval_dir"
    response_path="$eval_dir/assistant-research/$case_id.txt"
    case "$mutation" in
        duplicate_identity) mutation_filter='.five_lens_process_evidence.lens_dispatches[1].dispatch_identity = .five_lens_process_evidence.lens_dispatches[0].dispatch_identity' ;;
        missing_identity) mutation_filter='del(.five_lens_process_evidence.lens_dispatches[4].dispatch_identity)' ;;
        false_return_validated) mutation_filter='.five_lens_process_evidence.lens_dispatches[0].return_validated = false' ;;
        packet_binding_mismatch) mutation_filter='.five_lens_process_evidence.lens_dispatches[0].packet_content_digest = "sha256:tampered"' ;;
        ordering_failure) mutation_filter='.five_lens_process_evidence.frozen_packet_set.packet_manifest_order |= reverse' ;;
        content_digest_drift) mutation_filter='.five_lens_process_evidence.frozen_packet_set.packet_manifest[0].content_digest = "sha256:tampered"' ;;
        fallback_leakage) mutation_filter='.five_lens_process_evidence.fallback_lens_passes = []' ;;
        revision_disposition_id_mismatch) mutation_filter='.five_lens_process_evidence.peer_review_revision_disposition_id = "revision-closure-other"' ;;
        accepted_with_unresolved_revisions) mutation_filter='.peer_review.verdict = "accepted"' ;;
        revise_without_required_revisions) mutation_filter='.peer_review.required_revisions = []' ;;
        blocked_presentation) mutation_filter='.peer_review.status = "BLOCKED" | .peer_review.verdict = "accepted"' ;;
        *) return 2 ;;
    esac
    jq "$mutation_filter" "$response_path" >"$response_path.mutated" && mv "$response_path.mutated" "$response_path"

    if "$research_eval_runner" --responses "$eval_dir" --skill assistant-research >"$eval_output" 2>&1; then
        return 1
    fi

    grep -Fq $'FAIL\tassistant-research\t'"$case_id" "$eval_output" \
        && grep -Fq "Summary: total=$case_count passed=$((case_count - 1)) failed=1" "$eval_output" \
        && grep -Eq 'structured_json_assertion_failures=[1-9]' "$eval_output"
}

research_forbidden_response_is_rejected() {
    local case_id="$1"
    local forbidden="$2"
    local case_count
    local eval_dir
    local eval_output

    case_count="$(jq '.cases | length' "$research_evals")"
    eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-negative.XXXXXX")"
    eval_output="$(mktemp "${TMPDIR:-/tmp}/assistant-research-negative-output.XXXXXX")"
    p0p4_register_cleanup "$eval_dir" "$eval_output"
    write_research_eval_responses "$eval_dir"
    printf '%s\n' "$forbidden" >>"$eval_dir/assistant-research/$case_id.txt"

    if "$research_eval_runner" --responses "$eval_dir" --skill assistant-research >"$eval_output" 2>&1; then
        return 1
    fi

    grep -Fq $'FAIL\tassistant-research\t'"$case_id" "$eval_output" \
        && grep -Fq "Summary: total=$case_count passed=$((case_count - 1)) failed=1" "$eval_output" \
        && grep -Fq "missing_required_substrings=0" "$eval_output" \
        && grep -Fq "forbidden_substring_hits=1" "$eval_output"
}

research_old_five_lens_response_is_rejected() {
    local case_id="five-lens-retains-all-material-follow-ups"
    local case_count eval_dir eval_output

    case_count="$(jq '.cases | length' "$research_evals")"
    eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-old-five-lens.XXXXXX")"
    eval_output="$(mktemp "${TMPDIR:-/tmp}/assistant-research-old-five-lens-output.XXXXXX")"
    p0p4_register_cleanup "$eval_dir" "$eval_output"
    write_research_eval_responses "$eval_dir"
    {
        jq -r --arg case_id "$case_id" '
            .cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[] | select(. != "FIVE-LENS PROCESS EVIDENCE")
        ' "$research_evals"
        printf '%s\n' 'PERSPECTIVE SCAN' 'QUESTION TRACE / EVIDENCE LEDGER' 'CONTRADICTION MAP' 'SYNTHESIS' 'PEER REVIEW' 'SOURCES / VERIFIED URLS' 'GAPS'
    } >"$eval_dir/assistant-research/$case_id.txt"

    if "$research_eval_runner" --responses "$eval_dir" --skill assistant-research >"$eval_output" 2>&1; then
        return 1
    fi

    grep -Fq $'FAIL\tassistant-research\t'"$case_id" "$eval_output" \
        && grep -Fq "Summary: total=$case_count passed=$((case_count - 1)) failed=1" "$eval_output" \
        && grep -Fq 'missing_required_substrings=1' "$eval_output"
}

test_start "assistant-research candidate mechanisms stay evidence-backed and unproven"
missing_candidate_mechanism_terms=()
for term in \
    "candidate_mechanisms" \
    "counterevidence_or_conflicts" \
    "validation_method" \
    "claim_status"; do
    if ! grep -Fq "$term" "$research_output"; then
        missing_candidate_mechanism_terms+=("contracts/output.yaml: $term")
    fi
done
for term in \
    "SY_CANDIDATE_MECHANISMS" \
    "VR_CANDIDATE_MECHANISMS" \
    "not presented as a proven cause"; do
    if ! grep -Fq "$term" "$research_phase_gates"; then
        missing_candidate_mechanism_terms+=("contracts/phase-gates.yaml: $term")
    fi
done
for term in \
    "Candidate mechanisms" \
    "validation method"; do
    if ! grep -Fq "$term" "$research_skill"; then
        missing_candidate_mechanism_terms+=("SKILL.md: $term")
    fi
    if ! grep -Fq "$term" "$research_reference"; then
        missing_candidate_mechanism_terms+=("research.md: $term")
    fi
done
for term in \
    "candidate-mechanisms-are-evidence-backed-hypotheses" \
    "CANDIDATE MECHANISMS" \
    "Validation method"; do
    if ! grep -Fq "$term" "$research_evals"; then
        missing_candidate_mechanism_terms+=("evals/cases.json: $term")
    fi
done
if [[ "${#missing_candidate_mechanism_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research candidate-mechanism contract missing terms: ${missing_candidate_mechanism_terms[*]}"
fi

test_start "assistant-research v3 dispatches five independent lenses before root synthesis and separate peer review"
five_lens_process_missing=()
for file in \
    "$research_index" \
    "$FRAMEWORK_DIR/skills/assistant-research/contracts/input.yaml" \
    "$research_output" \
    "$research_phase_gates" \
    "$research_handoffs"; do
    if ! grep -Fq -- 'schema_version: "3.0"' "$file"; then
        five_lens_process_missing+=("${file#$FRAMEWORK_DIR/}: v3 schema version")
    fi
done
for term in \
    'contracts/handoffs.yaml' \
    'selected_handoff' \
    'orchestrator_to_lens_researcher' \
    'orchestrator_to_research_peer_reviewer'; do
    if ! grep -Fq -- "$term" "$research_index"; then
        five_lens_process_missing+=("contracts/index.yaml: $term")
    fi
done
for term in \
    'LensKind' \
    'five distinct native dispatch or agent identities' \
    'sibling-blind' \
    'all lens assignment packets are frozen before first dispatch' \
    'ResearchPeerReviewer' \
    'one same-assignment schema-correction retry' \
    'complete lens stage via evidenced fallback or block'; do
    if ! grep -Fq -- "$term" "$research_handoffs"; then
        five_lens_process_missing+=("contracts/handoffs.yaml: $term")
    fi
done
for term in \
    'five frozen, sibling-blind assignment packets' \
    'Orchestrator alone builds the contradiction map and initial synthesis' \
    'distinct ResearchPeerReviewer'; do
    if ! grep -Fq -- "$term" "$research_skill"; then
        five_lens_process_missing+=("SKILL.md: $term")
    fi
done
for term in \
    'capacity-bounded waves' \
    'later waves cannot consume earlier results' \
    'sequential fallback' \
    'reduced independence' \
    'separate fresh pass'; do
    if ! grep -Fqi -- "$term" "$five_lens_reference"; then
        five_lens_process_missing+=("five-lens-briefing.md: $term")
    fi
done
for term in \
    'five unique native lens dispatch identities' \
    'peer reviewer identity' \
    'root-only contradiction map and initial synthesis'; do
    if ! grep -Fqi -- "$term" "$research_phase_gates"; then
        five_lens_process_missing+=("contracts/phase-gates.yaml: $term")
    fi
done
for term in \
    'LensResearcher' \
    'ResearchPeerReviewer' \
    'five independent lens dispatches' \
    'sequential fallback'; do
    if ! grep -Fq -- "$term" "$research_evals"; then
        five_lens_process_missing+=("evals/cases.json: $term")
    fi
done
if [[ "${#five_lens_process_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research five-lens v3 process contract missing: ${five_lens_process_missing[*]}"
fi

test_start "assistant-research v3 models policy state and fallback evidence without fabricated dispatch identities"
policy_and_fallback_missing=()
for term in \
    '- name: subagent_policy_state' \
    'enum_values: [not_required, delegation_triggered, delegation_opted_out, subagents_unavailable, policy_disallowed]' \
    '- name: subagent_execution_mode' \
    'enum_values: [delegated, sequential_fallback, not_applicable]' \
    '- name: subagent_trigger_scope' \
    '- name: policy_blocking_source' \
    '- name: sequential_fallback_evidence'; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-research/contracts/input.yaml"; then
        policy_and_fallback_missing+=("contracts/input.yaml: $term")
    fi
done
for term in \
    'subagent_policy_state' \
    'subagent_execution_mode' \
    'subagent_trigger_scope' \
    'policy_blocking_source' \
    'sequential_fallback_evidence'; do
    if ! grep -Fq -- "$term" "$research_index"; then
        policy_and_fallback_missing+=("contracts/index.yaml entry selector: $term")
    fi
done
for term in \
    '- name: lens_execution_mode' \
    '- name: peer_review_execution_mode' \
    '- name: fallback_lens_passes' \
    '- name: peer_review_fallback_pass_id' \
    '- name: required_revisions' \
    'condition: "lens_execution_mode == delegated"' \
    'condition: "lens_execution_mode == sequential_fallback"' \
    'condition: "peer_review_execution_mode == delegated"' \
    'condition: "peer_review_execution_mode == sequential_fallback"'; do
    if ! grep -Fq -- "$term" "$research_output"; then
        policy_and_fallback_missing+=("contracts/output.yaml: $term")
    fi
done
fallback_lens_schema="$(awk '
    /- name: fallback_lens_passes/ { active = 1 }
    active { print }
    active && /^      - name: / && $0 !~ /fallback_lens_passes/ { exit }
' "$research_output")"
if printf '%s\n' "$fallback_lens_schema" | grep -Eq -- 'name:[[:space:]]*dispatch_identity'; then
    policy_and_fallback_missing+=("contracts/output.yaml: fallback_lens_passes must not carry dispatch_identity")
fi

peer_handoff_schema="$(awk '
    /- name: orchestrator_to_research_peer_reviewer/ { active = 1 }
    active { print }
    active && /^  - name: / && $0 !~ /orchestrator_to_research_peer_reviewer/ { exit }
' "$research_handoffs")"
for term in \
    'phase: SYNTHESIZE' \
    '- name: original_question' \
    '- name: findings' \
    '- name: candidate_mechanisms' \
    '- name: high_stakes_context' \
    '- name: follow_ups' \
    '- name: evidence' \
    'object_fields:'; do
    if ! printf '%s\n' "$peer_handoff_schema" | grep -Fq -- "$term" \
        && ! printf '%s\n' "$peer_handoff_schema" | grep -Fq -- "{name: ${term#- name: }" \
        && ! grep -Fq -- "$term" "$research_handoffs"; then
        policy_and_fallback_missing+=("contracts/handoffs.yaml typed peer handoff: $term")
    fi
done
if ! grep -Fq -- 'tools: Read, Grep, Glob, LS, WebSearch, WebFetch' "$FRAMEWORK_DIR/agents/claude/lens-researcher.md"; then
    policy_and_fallback_missing+=("agents/claude/lens-researcher.md: WebSearch/WebFetch tool access")
fi
for term in \
    'self-critique-only' \
    'one agent covering all lenses' \
    'partial mixed compliance' \
    'fabricated fallback dispatch refs'; do
    if ! grep -Fq -- "$term" "$research_evals"; then
        policy_and_fallback_missing+=("evals/cases.json: $term")
    fi
done
if [[ "${#policy_and_fallback_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research policy/fallback contract missing: ${policy_and_fallback_missing[*]}"
fi

test_start "assistant-research v3 binds packets and peer assignments without requiring source access"
lifecycle_schema_missing=()
if ! grep -Fq -- 'five_lens_process_evidence' "$research_index"; then
    lifecycle_schema_missing+=("contracts/index.yaml completion selector: five_lens_process_evidence")
fi
if grep -Fq -- 'A repeated model identity' "$research_handoffs"; then
    lifecycle_schema_missing+=("contracts/handoffs.yaml: model identity must not define independent dispatch identity")
fi
for term in \
    '- name: peer_review_assignment_id' \
    '- name: verification_gaps' \
    '- name: source_policy' \
    '- name: isolation_policy' \
    '- name: packet_id' \
    '- name: subagent_policy_state' \
    'condition: "subagent_policy_state == delegation_triggered"' \
    'condition: "subagent_policy_state == policy_disallowed"' \
    'reduced_independence is true whenever' \
    'distinct native dispatch or agent identities'; do
    if ! grep -Fq -- "$term" "$research_handoffs" && ! grep -Fq -- "$term" "$research_output"; then
        lifecycle_schema_missing+=("research contracts: $term")
    fi
done
peer_handoff_schema="$(awk '
    /- name: orchestrator_to_research_peer_reviewer/ { active = 1 }
    active { print }
    active && /^  - name: / && $0 !~ /orchestrator_to_research_peer_reviewer/ { exit }
' "$research_handoffs")"
peer_return_schema="$(printf '%s\n' "$peer_handoff_schema" | awk '
    /    return_fields:/ { active = 1 }
    active && /^return_validation:/ { exit }
    active { print }
')"
if ! printf '%s\n' "$peer_handoff_schema" | grep -Fq -- 'peer_review_assignment_id'; then
    lifecycle_schema_missing+=("contracts/handoffs.yaml peer context: peer_review_assignment_id")
fi
if printf '%s\n' "$peer_return_schema" | grep -Fq -- 'peer_reviewer_identity'; then
    lifecycle_schema_missing+=("contracts/handoffs.yaml peer return: peer_reviewer_identity must be orchestrator metadata only")
fi
verified_source_schema="$(printf '%s\n' "$peer_handoff_schema" | awk '
    /- name: verified_source_evidence/ { active = 1 }
    active { print }
    active && /^      - name: / && $0 !~ /verified_source_evidence/ { exit }
')"
if printf '%s\n' "$verified_source_schema" | grep -Fq -- 'min_items:'; then
    lifecycle_schema_missing+=("contracts/handoffs.yaml verified_source_evidence must allow empty arrays")
fi
for term in \
    '- name: lens_execution_mode' \
    '- name: peer_review_execution_mode' \
    '- name: peer_review_assignment_id' \
    '- name: packet_id' \
    '- name: subagent_policy_state' \
    '- name: subagent_trigger_scope' \
    '- name: policy_blocking_source' \
    'reduced_independence' \
    'false only when both are delegated'; do
    if ! grep -Fq -- "$term" "$research_output"; then
        lifecycle_schema_missing+=("contracts/output.yaml: $term")
    fi
done
for term in \
    'counterevidence_or_conflicts' \
    'sources_or_verified_urls' \
    'likely_blind_spot' \
    'unique_insight' \
    'verification_gaps' \
    'same model may serve multiple independent lens assignments'; do
    if ! grep -Fq -- "$term" "$research_handoffs"; then
        lifecycle_schema_missing+=("contracts/handoffs.yaml typed lifecycle context: $term")
    fi
done
for term in \
    'repeated model identity as noncompliance' \
    'peer reviewer identity from worker return' \
    'verified sources are required even when verification gaps' \
    'packet binding omitted'; do
    if ! grep -Fq -- "$term" "$research_evals"; then
        lifecycle_schema_missing+=("evals/cases.json lifecycle negative: $term")
    fi
done
if [[ "${#lifecycle_schema_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research lifecycle schema missing: ${lifecycle_schema_missing[*]}"
fi

test_start "assistant-research source-unavailable lens returns stay complete and peer workers remain orchestration-blind"
source_return_missing=()
lens_handoff_schema="$(awk '
    /- name: orchestrator_to_lens_researcher/ { active = 1 }
    active { print }
    active && /^  - name: / && $0 !~ /orchestrator_to_lens_researcher/ { exit }
' "$research_handoffs")"
lens_result_schema="$(printf '%s\n' "$lens_handoff_schema" | awk '
    /- name: lens_result/ { active = 1 }
    active { print }
    active && /^      - name: evidence/ { exit }
')"
direct_lens_source_count="$(printf '%s\n' "$lens_result_schema" | grep -Ec '^          - name: sources_or_verified_urls$' || true)"
if [[ "$direct_lens_source_count" != "1" ]]; then
    source_return_missing+=("lens_result must contain exactly one direct sources_or_verified_urls field")
fi
if printf '%s\n' "$lens_result_schema" | grep -A4 -E '^          - name: sources_or_verified_urls$' | grep -Fq -- 'min_items:'; then
    source_return_missing+=("lens_result sources_or_verified_urls must allow empty inference/unresolved evidence")
fi
if printf '%s\n' "$lens_result_schema" | grep -A4 -E '^              - name: sources_or_verified_urls$' | grep -Fq -- 'min_items:'; then
    source_return_missing+=("lens_result follow-up sources_or_verified_urls must allow empty inference/unresolved evidence")
fi
peer_handoff_schema="$(awk '
    /- name: orchestrator_to_research_peer_reviewer/ { active = 1 }
    active { print }
    active && /^  - name: / && $0 !~ /orchestrator_to_research_peer_reviewer/ { exit }
' "$research_handoffs")"
peer_lens_schema="$(printf '%s\n' "$peer_handoff_schema" | awk '
    /- name: validated_lens_results/ { active = 1 }
    active { print }
    active && /^      - name: findings/ { exit }
')"
if ! printf '%s\n' "$peer_lens_schema" | grep -Eq '^          - name: sources_or_verified_urls$'; then
    source_return_missing+=("peer validated_lens_results must carry a direct empty-allowed sources_or_verified_urls field")
fi
if printf '%s\n' "$peer_lens_schema" | grep -A4 -E '^              - name: sources_or_verified_urls$' | grep -Fq -- 'min_items:'; then
    source_return_missing+=("peer validated_lens_results follow-up sources_or_verified_urls must allow empty inference/unresolved evidence")
fi
peer_return_schema="$(printf '%s\n' "$peer_handoff_schema" | awk '
    /    return_fields:/ { active = 1 }
    active && /^return_validation:/ { exit }
    active { print }
')"
for forbidden_field in peer_reviewer_identity peer_review_execution_mode peer_review_fallback_pass_id; do
    if printf '%s\n' "$peer_return_schema" | grep -Fq -- "$forbidden_field"; then
        source_return_missing+=("peer worker return must omit $forbidden_field")
    fi
done
if ! printf '%s\n' "$peer_return_schema" | grep -Fq -- 'peer_review_assignment_id'; then
    source_return_missing+=("peer worker return must echo peer_review_assignment_id")
fi
for term in \
    'empty only for inference_only or unresolved' \
    'do not self-report execution or fallback orchestration metadata'; do
    if ! grep -Fqi -- "$term" "$research_handoffs"; then
        source_return_missing+=("contracts/handoffs.yaml: $term")
    fi
done
if [[ "${#source_return_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research source-return/peer-worker contract missing: ${source_return_missing[*]}"
fi

test_start "assistant-research v3 gates fallback, worker status, frozen evidence, and bounded resources"
v3_process_repair_missing=()
search_gate_schema="$(awk '
    /  - phase: SEARCH/ { active = 1 }
    active { print }
    active && /  - phase: SYNTHESIZE/ { exit }
' "$research_phase_gates")"
synthesize_gate_schema="$(awk '
    /  - phase: SYNTHESIZE/ { active = 1 }
    active { print }
    active && /  - phase: VERIFY/ { exit }
' "$research_phase_gates")"
verify_gate_schema="$(awk '
    /  - phase: VERIFY/ { active = 1 }
    active { print }
    active && /^invariants:/ { exit }
' "$research_phase_gates")"
for term in \
    'condition: "research_method == five_lens_briefing and lens_execution_mode == delegated"' \
    'exactly five frozen root passes' \
    'no native dispatch identity' \
    'reviewer-only fallback' \
    'fresh peer fallback pass ID' \
    'no fabricated native identity' \
    'valid fresh fallback completed'; do
    if ! printf '%s\n%s\n%s\n' "$search_gate_schema" "$synthesize_gate_schema" "$verify_gate_schema" | grep -Fq -- "$term"; then
        v3_process_repair_missing+=("phase gates: $term")
    fi
done
lens_handoff_schema="$(awk '
    /- name: orchestrator_to_lens_researcher/ { active = 1 }
    active { print }
    active && /^  - name: / && $0 !~ /orchestrator_to_lens_researcher/ { exit }
' "$research_handoffs")"
peer_handoff_schema="$(awk '
    /- name: orchestrator_to_research_peer_reviewer/ { active = 1 }
    active { print }
    active && /^return_validation:/ { exit }
' "$research_handoffs")"
output_peer_schema="$(awk '
    /  - name: peer_review$/ { active = 1 }
    active { print }
    active && /^  - name: five_lens_process_evidence$/ { exit }
' "$research_output")"
process_evidence_schema="$(awk '
    /  - name: five_lens_process_evidence$/ { active = 1 }
    active { print }
    active && /^  - name: conflicts$/ { exit }
' "$research_output")"
for term in \
    'status in [DONE, DONE_WITH_CONCERNS]' \
    'status in [NEEDS_CONTEXT, BLOCKED]' \
    'blocker_type' \
    'blocker_evidence' \
    'cannot finalize' \
    'BLOCKED => verdict=blocked' \
    'packet_set_id' \
    'frozen_packet_set' \
    'packet_frozen_at' \
    'first_lens_execution_at' \
    'search_resource_budget'; do
    if ! printf '%s\n%s\n%s\n%s\n' "$lens_handoff_schema" "$peer_handoff_schema" "$output_peer_schema" "$process_evidence_schema" | grep -Fq -- "$term"; then
        v3_process_repair_missing+=("handoff/output lifecycle: $term")
    fi
done
for exact_array in perspective_scan question_trace validated_lens_results frozen_assignment_packet_ids; do
    if ! grep -A12 -E "name: ${exact_array}$" "$research_output" "$research_handoffs" | grep -Fq -- 'max_items: 5'; then
        v3_process_repair_missing+=("exact-five cardinality: $exact_array")
    fi
done
for role_file in \
    "$FRAMEWORK_DIR/agents/codex/lens-researcher.toml" \
    "$FRAMEWORK_DIR/agents/claude/lens-researcher.md"; do
    for term in \
        'Only block for an invalid or missing assignment or an unrecoverable policy or tool failure' \
        'inference_only or unresolved' \
        'LOW confidence' \
        'empty source arrays' \
        'explicit gaps'; do
        if ! grep -Fq -- "$term" "$role_file"; then
            v3_process_repair_missing+=("${role_file#$FRAMEWORK_DIR/}: $term")
        fi
    done
done
for term in \
    'assistant-research is a Process skill' \
    'lens-researcher' \
    'research-peer-reviewer'; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/CLAUDE.md"; then
        v3_process_repair_missing+=("CLAUDE.md: $term")
    fi
done
if [[ "${#v3_process_repair_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research v3 process repair missing: ${v3_process_repair_missing[*]}"
fi

test_start "assistant-research eval rejects an old heading-complete five-lens response without process evidence"
if research_old_five_lens_response_is_rejected; then
    pass
else
    fail "research eval accepts a heading-complete old five-lens response without FIVE-LENS PROCESS EVIDENCE"
fi

test_start "assistant-research retains every material five-lens follow-up"
follow_up_missing=()
for term in \
    "- name: follow_ups" \
    "typed none_needed decision" \
    "Every material follow-up is retained" \
    "- name: question" \
    "- name: answer_or_gap" \
    "- name: sources_or_verified_urls" \
    "- name: evidence_status"; do
    if ! grep -Fq -- "$term" "$research_output"; then
        follow_up_missing+=("contracts/output.yaml: $term")
    fi
done
for term in \
    "SY_FIVE_LENS_FOLLOW_UPS" \
    "every material follow-up"; do
    if ! grep -Fq -- "$term" "$research_phase_gates"; then
        follow_up_missing+=("contracts/phase-gates.yaml: $term")
    fi
done
for term in \
    "Follow-ups:" \
    "none_needed" \
    "every material follow-up"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-research/five-lens-briefing.md"; then
        follow_up_missing+=("five-lens-briefing.md: $term")
    fi
done
for term in \
    "five-lens-retains-all-material-follow-ups" \
    "follow_ups" \
    "follow_up_question"; do
    if ! grep -Fq -- "$term" "$research_evals"; then
        follow_up_missing+=("evals/cases.json: $term")
    fi
done
for file in \
    "$research_index" \
    "$FRAMEWORK_DIR/skills/assistant-research/contracts/input.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-research/contracts/output.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-research/contracts/phase-gates.yaml" \
    "$research_handoffs"; do
    if ! grep -Fq -- 'schema_version: "3.0"' "$file"; then
        follow_up_missing+=("${file#$FRAMEWORK_DIR/}: v3 migration version")
    fi
done
if ! grep -Fq -- "Migration note: assistant-research contracts are v3.0" "$research_skill"; then
    follow_up_missing+=("SKILL.md: v3 migration note")
fi
if [[ "${#follow_up_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research five-lens follow-up contract missing: ${follow_up_missing[*]}"
fi

test_start "assistant-research v3 follows the authoritative none_needed enum"
none_needed_missing=()
for file in \
    "$research_output" \
    "$research_phase_gates" \
    "$FRAMEWORK_DIR/skills/assistant-research/five-lens-briefing.md" \
    "$research_evals"; do
    if grep -Fq -- "none-needed" "$file"; then
        none_needed_missing+=("${file#$FRAMEWORK_DIR/}: stale none-needed spelling")
    fi
done
for term in \
    "follow_ups=[follow_up, follow_up]" \
    "decision=none_needed" \
    "none_needed cannot coexist with material follow-ups"; do
    if ! grep -Fq -- "$term" "$research_evals"; then
        none_needed_missing+=("evals/cases.json: $term")
    fi
done
if [[ "${#none_needed_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research none_needed enum contract missing: ${none_needed_missing[*]}"
fi

test_start "assistant-research grader rejects a keyword-complete mixed follow-up trace"
if research_forbidden_response_is_rejected \
    "five-lens-retains-all-material-follow-ups" \
    "accept follow_ups=[follow_up, none_needed] for the same trace"; then
    pass
else
    fail "research grader accepts follow_up and none_needed in one trace"
fi

test_start "assistant-research grader rejects invalid five-lens fallback and peer status truth tables"
if research_forbidden_response_is_rejected \
    "five-lens-decision-briefing-uses-storm-style-workflow" \
    "BLOCKED with accepted verdict" \
    && research_forbidden_response_is_rejected \
        "five-lens-decision-briefing-uses-storm-style-workflow" \
        "fabricated fallback dispatch refs"; then
    pass
else
    fail "research grader accepts an invalid peer status/verdict or fabricated fallback dispatch refs"
fi

test_start "assistant-research separates delegated and sequential-fallback eval evidence branches"
branch_eval_missing=()
delegated_case="$(jq -c '.cases[] | select(.id == "five-lens-decision-briefing-uses-storm-style-workflow")' "$research_evals")"
fallback_case="$(jq -c '.cases[] | select(.id == "five-lens-sequential-fallback-preserves-process-evidence")' "$research_evals")"
for term in \
    'lens_execution_mode: delegated' \
    'peer_review_execution_mode: delegated' \
    'reduced_independence: false'; do
    if ! printf '%s\n' "$delegated_case" | grep -Fq -- "$term"; then
        branch_eval_missing+=("delegated eval: $term")
    fi
done
for forbidden in fallback_lens_passes peer_review_fallback_pass_id lens_fallback_evidence peer_review_fallback_evidence; do
    if ! printf '%s\n' "$delegated_case" | jq -r '.machine_expectations.forbidden_substrings[]' | grep -Fxq -- "$forbidden"; then
        branch_eval_missing+=("delegated eval must reject $forbidden")
    fi
done
for term in \
    'lens_execution_mode: sequential_fallback' \
    'peer_review_execution_mode: sequential_fallback' \
    'fallback_lens_passes' \
    'exactly five frozen root passes' \
    'lens_fallback_evidence' \
    'peer_review_fallback_pass_id' \
    'peer_review_fallback_evidence' \
    'reduced_independence: true'; do
    if ! printf '%s\n' "$fallback_case" | grep -Fq -- "$term"; then
        branch_eval_missing+=("fallback eval: $term")
    fi
done
for forbidden in 'five unique native dispatch identities' peer_reviewer_identity; do
    if ! printf '%s\n' "$fallback_case" | jq -r '.machine_expectations.forbidden_substrings[]' | grep -Fxq -- "$forbidden"; then
        branch_eval_missing+=("fallback eval must reject $forbidden")
    fi
done
if [[ "${#branch_eval_missing[@]}" -eq 0 ]] \
    && research_forbidden_response_is_rejected \
        "five-lens-decision-briefing-uses-storm-style-workflow" \
        "fallback_lens_passes" \
    && research_forbidden_response_is_rejected \
        "five-lens-sequential-fallback-preserves-process-evidence" \
        "five unique native dispatch identities"; then
    pass
else
    fail "assistant-research eval branches are mixed or do not reject mixed delegated/fallback evidence: ${branch_eval_missing[*]}"
fi

test_start "assistant-research closes peer revisions and binds freeze evidence canonically"
closure_and_freeze_missing=()
output_peer_schema="$(awk '
    /  - name: peer_review$/ { active = 1 }
    active { print }
    active && /^  - name: five_lens_process_evidence$/ { exit }
' "$research_output")"
process_evidence_schema="$(awk '
    /  - name: five_lens_process_evidence$/ { active = 1 }
    active { print }
    active && /^  - name: conflicts$/ { exit }
' "$research_output")"
peer_handoff_return="$(awk '
    /- name: orchestrator_to_research_peer_reviewer/ { active = 1 }
    active && /    return_fields:/ { in_return = 1 }
    in_return { print }
    active && /^return_validation:/ { exit }
' "$research_handoffs")"
for term in \
    'revision_disposition' \
    'condition: "verdict == revise"' \
    'required_revision' \
    'outcome' \
    'applied' \
    'claim_downgraded' \
    'unresolved revision blocks presentation' \
    'pre_dispatch_record_id' \
    'first_lens_execution_evidence_ref'; do
    if ! printf '%s\n%s\n' "$output_peer_schema" "$process_evidence_schema" | grep -Fq -- "$term"; then
        closure_and_freeze_missing+=("output lifecycle: $term")
    fi
done
if printf '%s\n' "$peer_handoff_return" | grep -Fq -- 'revision_disposition'; then
    closure_and_freeze_missing+=("peer worker return must not self-attest revision application")
fi
for term in \
    'standard=3 queries, 4 sources, and 10 minutes per lens / 15 queries, 20 sources, and 50 minutes overall' \
    'extensive=5, 6, and 15 / 25, 30, and 75' \
    'deep=8, 10, and 25 / 40, 50, and 125' \
    'saturation or its hard ceiling'; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-research/contracts/input.yaml" \
        && ! grep -Fq -- "$term" "$research_phase_gates"; then
        closure_and_freeze_missing+=("canonical resource policy: $term")
    fi
done
if [[ "${#closure_and_freeze_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research revision closure/freeze/resource contract missing: ${closure_and_freeze_missing[*]}"
fi

test_start "assistant-research binds revise closure identity from peer review to process evidence"
revision_identity_binding_missing=()
output_peer_schema="$(awk '
    /  - name: peer_review$/ { active = 1 }
    active { print }
    active && /^  - name: five_lens_process_evidence$/ { exit }
' "$research_output")"
process_evidence_schema="$(awk '
    /  - name: five_lens_process_evidence$/ { active = 1 }
    active { print }
    active && /^  - name: conflicts$/ { exit }
' "$research_output")"
for term in \
    'revision_disposition_id' \
    'type: string' \
    'condition: "verdict == revise"' \
    'Orchestrator-owned'; do
    if ! printf '%s\n' "$output_peer_schema" | grep -Fq -- "$term"; then
        revision_identity_binding_missing+=("peer_review revision identity: $term")
    fi
done
for term in \
    'peer_review_revision_disposition_id' \
    'condition: "peer_review.verdict == revise"' \
    'Exactly equals peer_review.revision_disposition_id'; do
    if ! printf '%s\n' "$process_evidence_schema" | grep -Fq -- "$term"; then
        revision_identity_binding_missing+=("five_lens_process_evidence revision identity binding: $term")
    fi
done
if [[ "${#revision_identity_binding_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research revise closure identity binding missing: ${revision_identity_binding_missing[*]}"
fi

test_start "assistant-research closes every peer revision and normalizes quick five-lens requests"
peer_truth_and_tier_missing=()
output_peer_schema="$(awk '
    /  - name: peer_review$/ { active = 1 }
    active { print }
    active && /^  - name: five_lens_process_evidence$/ { exit }
' "$research_output")"
peer_return_schema="$(awk '
    /- name: orchestrator_to_research_peer_reviewer/ { active = 1 }
    active && /    return_fields:/ { in_return = 1 }
    in_return { print }
    active && /^return_validation:/ { exit }
' "$research_handoffs")"
for term in \
    'accepted and accepted_with_concerns require required_revisions=[]' \
    'revise requires one or more required_revisions' \
    'revision_disposition_id' \
    'Covers every required_revisions entry exactly once' \
    'unresolved revision blocks presentation'; do
    if ! printf '%s\n%s\n' "$output_peer_schema" "$peer_return_schema" | grep -Fq -- "$term"; then
        peer_truth_and_tier_missing+=("peer revision truth table: $term")
    fi
done
for term in \
    'quick five_lens_briefing normalizes to standard' \
    'preserves five_lens_briefing' \
    'standard, extensive, deep' \
    'tier normalization disclosure'; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-research/contracts/input.yaml" \
        && ! grep -Fq -- "$term" "$research_phase_gates" \
        && ! grep -Fq -- "$term" "$research_reference"; then
        peer_truth_and_tier_missing+=("tier/method cross-field rule: $term")
    fi
done
if [[ "${#peer_truth_and_tier_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research peer revision truth table or five-lens tier normalization missing: ${peer_truth_and_tier_missing[*]}"
fi

test_start "assistant-research freezes content-addressed ordered lens packets"
immutable_packet_missing=()
lens_handoff_schema="$(awk '
    /- name: orchestrator_to_lens_researcher/ { active = 1 }
    active { print }
    active && /^  - name: orchestrator_to_research_peer_reviewer/ { exit }
' "$research_handoffs")"
process_evidence_schema="$(awk '
    /  - name: five_lens_process_evidence$/ { active = 1 }
    active { print }
    active && /^  - name: conflicts$/ { exit }
' "$research_output")"
for term in \
    'packet_manifest_order' \
    'packet_manifest' \
    'content_digest' \
    'ordered manifest contents' \
    'packet_content_digest' \
    'matching packet content_digest'; do
    if ! printf '%s\n%s\n' "$lens_handoff_schema" "$process_evidence_schema" | grep -Fq -- "$term"; then
        immutable_packet_missing+=("immutable packet contract: $term")
    fi
done
if [[ "${#immutable_packet_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research immutable packet manifest contract missing: ${immutable_packet_missing[*]}"
fi

test_start "assistant-research eval structurally validates delegated five-lens process evidence"
structured_oracle_missing=()
delegated_assertions="$(jq -c '
    .cases[] | select(.id == "five-lens-decision-briefing-uses-storm-style-workflow")
    | .machine_expectations.structured_json_assertions // []
' "$research_evals")"
if ! jq -e '
    length >= 10
    and any(.[]; . == {"operator":"equals","path":["five_lens_process_evidence","lens_execution_mode"],"expected":"delegated"})
    and any(.[]; . == {"operator":"path_absent","path":["five_lens_process_evidence","fallback_lens_passes"]})
    and any(.[]; .operator == "array_object_values_exact" and .path == ["five_lens_process_evidence","lens_dispatches"])
    and any(.[]; . == {"operator":"equals","path":["peer_review","verdict"],"expected":"revise"})
    and any(.[]; . == {"operator":"equals","path":["peer_review","required_revisions"],"expected":["downgrade unsupported claim"]})
    and any(.[]; . == {"operator":"equals_path","path":["five_lens_process_evidence","peer_review_revision_disposition_id"],"other_path":["peer_review","revision_disposition_id"]})
' <<<"$delegated_assertions" >/dev/null; then
    structured_oracle_missing+=("delegated structured JSON assertions for dispatch, fallback absence, and revision identity")
fi
technology_case="$(jq -c '.cases[] | select(.id == "technology-comparison-uses-standard-tier")' "$research_evals")"
if ! printf '%s\n' "$technology_case" | grep -Fq -- 'evidence-only source comparison' \
    || printf '%s\n' "$technology_case" | grep -Fq -- 'decision support'; then
    structured_oracle_missing+=("technology comparison must be evidence-only source_research without decision support")
fi
if [[ "${#structured_oracle_missing[@]}" -eq 0 ]] \
    && research_structured_mutation_is_rejected duplicate_identity \
    && research_structured_mutation_is_rejected missing_identity \
    && research_structured_mutation_is_rejected false_return_validated \
    && research_structured_mutation_is_rejected packet_binding_mismatch \
    && research_structured_mutation_is_rejected ordering_failure \
    && research_structured_mutation_is_rejected content_digest_drift \
    && research_structured_mutation_is_rejected fallback_leakage \
    && research_structured_mutation_is_rejected revision_disposition_id_mismatch \
    && research_structured_mutation_is_rejected accepted_with_unresolved_revisions \
    && research_structured_mutation_is_rejected revise_without_required_revisions \
    && research_structured_mutation_is_rejected blocked_presentation; then
    pass
else
    fail "assistant-research delegated structured eval oracle is incomplete or accepts a process-evidence mutation: ${structured_oracle_missing[*]}"
fi

test_start "assistant-research scopes peer follow-up validation to the peer handoff subtree"
peer_lens_schema="$(awk '
    /- name: orchestrator_to_research_peer_reviewer/ { peer = 1 }
    peer && /- name: validated_lens_results/ { results = 1 }
    results { print }
    results && /^      - name: findings/ { exit }
' "$research_handoffs")"
peer_follow_up_schema="$(printf '%s\n' "$peer_lens_schema" | awk '
    /name: follow_ups/ { active = 1 }
    active { print }
    active && /name: evidence_status/ { exit }
')"
peer_follow_up_shape_complete() {
    local schema="$1"
    for term in \
        'name: follow_ups' \
        'object_fields:' \
        'name: decision' \
        'name: question' \
        'name: answer_or_gap' \
        'name: sources_or_verified_urls' \
        'name: evidence_status'; do
        printf '%s\n' "$schema" | grep -Fq -- "$term" || return 1
    done
}
peer_follow_up_without_nested_sources="$(printf '%s\n' "$peer_follow_up_schema" | sed '/name: sources_or_verified_urls/d')"
if peer_follow_up_shape_complete "$peer_follow_up_schema" \
    && ! peer_follow_up_shape_complete "$peer_follow_up_without_nested_sources"; then
    pass
else
    fail "assistant-research peer follow-up schema is not scoped or deletion of its nested sources field is accepted"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
