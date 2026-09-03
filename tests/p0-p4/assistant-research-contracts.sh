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
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/assistant-research-fixtures.sh"

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
            write_schema_valid_five_lens_eval_response delegated "$output_dir/assistant-research/$case_id.txt"
        elif [[ "$case_id" == "five-lens-sequential-fallback-preserves-process-evidence" ]] \
            && jq -e --arg case_id "$case_id" '
                .cases[] | select(.id == $case_id)
                | (.machine_expectations.structured_json_assertions? // [] | length > 0)
            ' "$research_evals" >/dev/null; then
            write_schema_valid_five_lens_eval_response sequential_fallback "$output_dir/assistant-research/$case_id.txt"
        else
            jq -r --arg case_id "$case_id" '
                .cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[]
            ' "$research_evals" >"$output_dir/assistant-research/$case_id.txt"
        fi
    done < <(jq -r '.cases[].id' "$research_evals")
}

research_structured_mutation_is_rejected() {
    local mutation="$1"
    local case_id="five-lens-decision-briefing-uses-storm-style-workflow"
    local eval_dir response_path mutation_filter

    eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-structured-negative.XXXXXX")"
    p0p4_register_cleanup "$eval_dir"
    write_research_eval_responses "$eval_dir"
    response_path="$eval_dir/assistant-research/$case_id.txt"
    case "$mutation" in
        duplicate_identity) mutation_filter='.five_lens_process_evidence.lens_dispatches[1].dispatch_identity = .five_lens_process_evidence.lens_dispatches[0].dispatch_identity' ;;
        missing_identity) mutation_filter='del(.five_lens_process_evidence.lens_dispatches[4].dispatch_identity)' ;;
        false_return_validated) mutation_filter='.five_lens_process_evidence.lens_dispatches[0].return_validated = false' ;;
        packet_binding_mismatch) mutation_filter='.five_lens_process_evidence.lens_dispatches[0].packet_content_digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' ;;
        ordering_failure) mutation_filter='.five_lens_process_evidence.frozen_packet_set.packet_manifest_order |= reverse' ;;
        content_digest_drift) mutation_filter='.five_lens_process_evidence.frozen_packet_set.packet_manifest[0].content_digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' ;;
        fallback_leakage) mutation_filter='.five_lens_process_evidence.fallback_lens_passes = []' ;;
        revision_disposition_id_mismatch) mutation_filter='.five_lens_process_evidence.peer_review_revision_disposition_id = "revision-closure-other"' ;;
        accepted_with_unresolved_revisions) mutation_filter='.peer_review.verdict = "accepted"' ;;
        revise_without_required_revisions) mutation_filter='.peer_review.required_revisions = []' ;;
        blocked_presentation) mutation_filter='.peer_review.status = "BLOCKED" | .peer_review.verdict = "accepted"' ;;
        peer_execution_mode_mismatch) mutation_filter='.five_lens_process_evidence.peer_review_execution_mode = "sequential_fallback"' ;;
        peer_identity_mismatch) mutation_filter='.five_lens_process_evidence.peer_reviewer_identity = "peer-native-other"' ;;
        perspective_digest_mismatch) mutation_filter='.perspective_scan[0].lens_result_digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' ;;
        perspective_assignment_mismatch) mutation_filter='.perspective_scan[0].assignment_id = "assignment-other"' ;;
        perspective_content_drift) mutation_filter='.perspective_scan[0].core_position = "Tampered perspective position"' ;;
        question_trace_content_drift) mutation_filter='.question_trace[0].answer = "Tampered answer"' ;;
        accepted_result_body_drift) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].core_position = "Tampered accepted result"' ;;
        accepted_result_assignment_drift) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].assignment_id = "assignment-other"' ;;
        peer_result_projection_drift) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].unique_insight = "Tampered ledger projection"' ;;
        process_result_digest_mismatch) mutation_filter='.five_lens_process_evidence.lens_dispatches[0].lens_result_digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' ;;
        missing_per_lens_usage) mutation_filter='del(.five_lens_process_evidence.lens_dispatches[0].search_resource_usage)' ;;
        negative_per_lens_usage) mutation_filter='.five_lens_process_evidence.lens_dispatches[0].search_resource_usage.actual_sources = -1' ;;
        per_lens_actual_over_ceiling) mutation_filter='.five_lens_process_evidence.lens_dispatches[0].search_resource_usage.actual_queries = 6' ;;
        overall_totals_over_ceiling) mutation_filter='.five_lens_process_evidence.overall_resource_usage.actual_queries = 26' ;;
        overall_query_sum_drift) mutation_filter='.five_lens_process_evidence.overall_resource_usage.actual_queries = 14' ;;
        wall_clock_drift) mutation_filter='.five_lens_process_evidence.overall_resource_usage.elapsed_minutes = 9' ;;
        peer_blocked_revise) mutation_filter='.peer_review.status = "BLOCKED" | .peer_review.verdict = "revise"' ;;
        missing_required_revisions) mutation_filter='del(.peer_review.required_revisions)' ;;
        missing_revision_disposition) mutation_filter='del(.peer_review.revision_disposition)' ;;
        peer_identity_reused_from_lens) mutation_filter='.peer_review.peer_reviewer_identity = .five_lens_process_evidence.lens_dispatches[0].dispatch_identity | .five_lens_process_evidence.peer_reviewer_identity = .five_lens_process_evidence.lens_dispatches[0].dispatch_identity' ;;
        reversed_freeze_proof) mutation_filter='.five_lens_process_evidence.frozen_packet_set.packet_set_frozen_at = "2026-09-03T10:02:00Z"' ;;
        missing_freeze_proof) mutation_filter='del(.five_lens_process_evidence.frozen_packet_set.first_lens_execution_evidence_ref)' ;;
        huge_budget_loop_forever) mutation_filter='.five_lens_process_evidence.search_resource_budget = {per_lens_max_queries:999,per_lens_max_sources:999,per_lens_max_minutes:999,overall_max_queries:9999,overall_max_sources:9999,overall_max_minutes:9999,stop_condition:"loop_forever"}' ;;
        source_invalid_domain) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = ["https://example.invalid/research"] | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].sources_or_verified_urls = ["https://example.invalid/follow-up"]' ;;
        source_private_loopback) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = ["https://127.0.0.1./research"] | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].sources_or_verified_urls = ["https://192.0.2.1/follow-up"]' ;;
        source_backed_empty) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = [] | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].sources_or_verified_urls = []' ;;
        synchronized_assignments) mutation_filter='.five_lens_process_evidence.accepted_lens_results |= map(.assignment_id = "assignment-shared") | .five_lens_process_evidence.lens_dispatches |= map(.assignment_id = "assignment-shared") | .five_lens_process_evidence.peer_review_assignment_id = "assignment-shared" | .peer_review.peer_review_assignment_id = "assignment-shared"' ;;
        missing_delegated_trigger_scope) mutation_filter='del(.five_lens_process_evidence.subagent_trigger_scope)' ;;
        lens_worker_synthesis) mutation_filter='.five_lens_process_evidence.root_synthesis_ownership = "lens_worker"' ;;
        schedule_wall_clock_drift) mutation_filter='
            .five_lens_process_evidence.lens_dispatches[2].wave_id = "wave-2"
            | .five_lens_process_evidence.lens_dispatches[3].wave_id = "wave-2"
            | .five_lens_process_evidence.lens_dispatches[4].wave_id = "wave-2"
            | .five_lens_process_evidence.wave_coverage = [
                {wave_id:"wave-1",capacity:2,lens_kinds:["practitioner","academic_or_technical_expert"]},
                {wave_id:"wave-2",capacity:3,lens_kinds:["skeptic","economist_or_incentives_analyst","historian_or_pattern_matcher"]}
              ]
            | .five_lens_process_evidence.overall_resource_usage.elapsed_minutes = 19' ;;
        *) return 2 ;;
    esac
    jq "$mutation_filter" "$response_path" >"$response_path.mutated" && mv "$response_path.mutated" "$response_path"
    case "$mutation" in
        source_invalid_domain|source_private_loopback|source_backed_empty|synchronized_assignments) research_refresh_response_derivatives "$response_path" ;;
    esac

    if research_response_oracle_is_valid "$response_path"; then
        printf 'accepted mutation: %s\n' "$mutation" >&2
        return 1
    fi
}

research_fallback_structured_mutation_is_rejected() {
    local mutation="$1"
    local case_id="five-lens-sequential-fallback-preserves-process-evidence"
    local eval_dir response_path mutation_filter

    eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-fallback-negative.XXXXXX")"
    p0p4_register_cleanup "$eval_dir"
    write_research_eval_responses "$eval_dir"
    response_path="$eval_dir/assistant-research/$case_id.txt"
    case "$mutation" in
        false_return_validated) mutation_filter='.five_lens_process_evidence.fallback_lens_passes[0].return_validated = false' ;;
        packet_binding_mismatch) mutation_filter='.five_lens_process_evidence.fallback_lens_passes[0].packet_content_digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' ;;
        fallback_dispatch_identity_leakage) mutation_filter='.five_lens_process_evidence.fallback_lens_passes[0].dispatch_identity = "fabricated-native"' ;;
        peer_fallback_and_evidence_mismatch) mutation_filter='.five_lens_process_evidence.peer_review_fallback_pass_id = "peer-root-pass-other" | .five_lens_process_evidence.lens_fallback_evidence.detail = "" | .five_lens_process_evidence.peer_review_fallback_evidence.evidence_ref = ""' ;;
        peer_fallback_reuses_lens_pass) mutation_filter='.peer_review.peer_review_fallback_pass_id = "root-pass-1" | .five_lens_process_evidence.peer_review_fallback_pass_id = "root-pass-1"' ;;
        perspective_digest_mismatch) mutation_filter='.perspective_scan[0].lens_result_digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' ;;
        perspective_assignment_mismatch) mutation_filter='.perspective_scan[0].assignment_id = "fallback-assignment-other"' ;;
        perspective_content_drift) mutation_filter='.perspective_scan[0].core_position = "Tampered fallback perspective"' ;;
        question_trace_content_drift) mutation_filter='.question_trace[0].question = "Tampered fallback question"' ;;
        accepted_result_body_drift) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].answer_or_gap = "Tampered fallback accepted result"' ;;
        accepted_result_assignment_drift) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].assignment_id = "fallback-assignment-other"' ;;
        peer_result_projection_drift) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].gaps = []' ;;
        process_result_digest_mismatch) mutation_filter='.five_lens_process_evidence.fallback_lens_passes[0].lens_result_digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' ;;
        missing_per_lens_usage) mutation_filter='del(.five_lens_process_evidence.fallback_lens_passes[0].search_resource_usage)' ;;
        negative_per_lens_usage) mutation_filter='.five_lens_process_evidence.fallback_lens_passes[0].search_resource_usage.actual_sources = -1' ;;
        per_lens_actual_over_ceiling) mutation_filter='.five_lens_process_evidence.fallback_lens_passes[0].search_resource_usage.actual_queries = 6' ;;
        overall_totals_over_ceiling) mutation_filter='.five_lens_process_evidence.overall_resource_usage.actual_sources = 31' ;;
        overall_query_sum_drift) mutation_filter='.five_lens_process_evidence.overall_resource_usage.actual_queries = 24' ;;
        wall_clock_drift) mutation_filter='.five_lens_process_evidence.overall_resource_usage.elapsed_minutes = 14' ;;
        schedule_wall_clock_drift) mutation_filter='.five_lens_process_evidence.overall_resource_usage.elapsed_minutes = 74' ;;
        exhausted_without_low_confidence) mutation_filter='.perspective_scan[0].confidence = "medium"' ;;
        exhaustion_without_explicit_gap) mutation_filter='del(.five_lens_process_evidence.fallback_lens_passes[0].search_resource_usage.exhaustion_gap)' ;;
        missing_lens_fallback_evidence_ref) mutation_filter='del(.five_lens_process_evidence.lens_fallback_evidence.evidence_ref)' ;;
        *) return 2 ;;
    esac
    jq "$mutation_filter" "$response_path" >"$response_path.mutated" && mv "$response_path.mutated" "$response_path"

    ! research_response_oracle_is_valid "$response_path"
}

research_verified_source_evidence_is_valid() {
    ruby -rjson -ruri -ripaddr -e '
        def unsafe_text?(text)
          text.match?(/token|secret|api[_-]?key|password|bearer|credential|session=|authorization/i) ||
            text.match?(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}|\b\d{3}-\d{2}-\d{4}\b|\b\d{3}[ .-]\d{3}[ .-]\d{4}\b/i)
        end
        def public_host?(host)
          normalized = host.downcase.delete_suffix(".")
          return false if normalized.empty? || normalized == "localhost" || normalized.end_with?(".localhost", ".internal", ".local", ".invalid")
          address = if normalized.match?(/\A\d+\z/) && Integer(normalized, 10) <= 0xffff_ffff
            IPAddr.new_ntoh([Integer(normalized, 10)].pack("N"))
          else
            IPAddr.new(normalized)
          end
          return true unless address
          non_global_ranges = if address.ipv4?
            %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4]
          else
            %w[::/128 ::1/128 100::/64 2001:db8::/32 fc00::/7 fe80::/10 ff00::/8]
          end
          return false if address.loopback? || address.private? || address.link_local? || non_global_ranges.any? { |cidr| IPAddr.new(cidr).include?(address) }
          mapped = address.respond_to?(:ipv4_mapped?) && address.ipv4_mapped? ? address.native : nil
          return true unless mapped
          mapped_non_global = %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4]
          !(mapped.loopback? || mapped.private? || mapped.link_local? || mapped_non_global.any? { |cidr| IPAddr.new(cidr).include?(mapped) })
        rescue IPAddr::InvalidAddressError, ArgumentError
          true
        end
        evidence = JSON.parse(STDIN.read)
        method = evidence["verification_method"]
        reference = evidence["verification_reference"]
        url = evidence["verified_url"]
        exit 1 unless %w[public_url local_repository authenticated_source offline_authoritative_source].include?(method)
        exit 1 unless reference.is_a?(String) && reference == reference.strip && !reference.empty?
        exit 1 if [reference, url].compact.any? { |text| !text.is_a?(String) || unsafe_text?(text) }
        valid = case method
        when "public_url"
          begin
            uri = URI.parse(url)
            url == reference && uri.scheme == "https" && uri.host && uri.userinfo.nil? && public_host?(uri.host)
          rescue URI::InvalidURIError, TypeError
            false
          end
        when "local_repository"
          !evidence.key?("verified_url") && reference.match?(%r{\A(?!/)(?!.*(?:\A|/)\.\.(?:/|\z))[A-Za-z0-9._/-]+(?:#[A-Za-z0-9._:-]+)?\z})
        when "authenticated_source"
          !evidence.key?("verified_url") && reference.match?(/\Aconnector:[A-Za-z0-9._-]+\/record:[A-Za-z0-9._-]+\z/)
        else
          !evidence.key?("verified_url") && reference.match?(/\Acitation:[^\s].*\z/)
        end
        exit(valid ? 0 : 1)
    '
}

research_sha256_stream() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    else
        return 127
    fi
}

research_content_digest_contract_is_strict() {
    local contract_text="$1"

    grep -Fq -- 'lowercase hexadecimal SHA-256' <<<"$contract_text" \
        && grep -Fq -- 'RFC 8785 JSON Canonicalization Scheme (JCS)' <<<"$contract_text" \
        && grep -Fq -- 'content_digest is ContentDigest over the RFC 8785 JCS bytes of a JSON object containing exactly' <<<"$contract_text" \
        && grep -Fq -- 'it excludes content_digest itself' <<<"$contract_text" \
        && grep -Fq -- 'Uses the ContentDigest format and excludes this field from its preimage.' <<<"$contract_text"
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

research_official_response_mutation_is_rejected() {
    local mutation="$1"
    local case_id="five-lens-decision-briefing-uses-storm-style-workflow"
    local eval_dir eval_output response_path mutation_filter manifest_digest

    case "$mutation" in
        missing_lens_fallback_evidence_ref) case_id="five-lens-sequential-fallback-preserves-process-evidence" ;;
    esac
    eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-official-negative.XXXXXX")"
    eval_output="$(mktemp "${TMPDIR:-/tmp}/assistant-research-official-negative-output.XXXXXX")"
    p0p4_register_cleanup "$eval_dir" "$eval_output"
    write_research_eval_responses "$eval_dir"
    response_path="$eval_dir/assistant-research/$case_id.txt"
    if ! "$research_eval_runner" --responses "$eval_dir" --skill assistant-research --case "$case_id" >"$eval_output" 2>&1; then
        printf 'official runner rejected its generated baseline: %s\n' "$mutation" >&2
        return 1
    fi
    case "$mutation" in
        accepted_result_body_with_unchanged_digest) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].core_position = "Tampered accepted result"' ;;
        missing_per_lens_usage) mutation_filter='del(.five_lens_process_evidence.lens_dispatches[0].search_resource_usage)' ;;
        hidden_extra_accepted_result_field) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].invented_hidden_field = "must not be accepted"' ;;
        missing_resource_budget) mutation_filter='del(.five_lens_process_evidence.search_resource_budget)' ;;
        hidden_packet_manifest_field) mutation_filter='.five_lens_process_evidence.frozen_packet_set.packet_manifest[0].invented_hidden_field = "must not enter the digest preimage"' ;;
        peer_blocked_revise) mutation_filter='.peer_review.status = "BLOCKED" | .peer_review.verdict = "revise"' ;;
        missing_required_revisions) mutation_filter='del(.peer_review.required_revisions)' ;;
        missing_revision_disposition) mutation_filter='del(.peer_review.revision_disposition)' ;;
        peer_identity_reused_from_lens) mutation_filter='.peer_review.peer_reviewer_identity = .five_lens_process_evidence.lens_dispatches[0].dispatch_identity | .five_lens_process_evidence.peer_reviewer_identity = .five_lens_process_evidence.lens_dispatches[0].dispatch_identity' ;;
        reversed_freeze_proof) mutation_filter='.five_lens_process_evidence.frozen_packet_set.packet_set_frozen_at = "2026-09-03T10:02:00Z"' ;;
        missing_freeze_proof) mutation_filter='del(.five_lens_process_evidence.frozen_packet_set.first_lens_execution_evidence_ref)' ;;
        huge_budget_loop_forever) mutation_filter='.five_lens_process_evidence.search_resource_budget = {per_lens_max_queries:999,per_lens_max_sources:999,per_lens_max_minutes:999,overall_max_queries:9999,overall_max_sources:9999,overall_max_minutes:9999,stop_condition:"loop_forever"}' ;;
        source_invalid_domain) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = ["https://example.invalid/research"] | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].sources_or_verified_urls = ["https://example.invalid/follow-up"]' ;;
        source_private_loopback) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = ["https://127.0.0.1./research"] | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].sources_or_verified_urls = ["https://192.0.2.1/follow-up"]' ;;
        source_backed_empty) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = [] | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].sources_or_verified_urls = []' ;;
        synchronized_assignments) mutation_filter='.five_lens_process_evidence.accepted_lens_results |= map(.assignment_id = "assignment-shared") | .five_lens_process_evidence.lens_dispatches |= map(.assignment_id = "assignment-shared") | .five_lens_process_evidence.peer_review_assignment_id = "assignment-shared" | .peer_review.peer_review_assignment_id = "assignment-shared"' ;;
        missing_delegated_trigger_scope) mutation_filter='del(.five_lens_process_evidence.subagent_trigger_scope)' ;;
        lens_worker_synthesis) mutation_filter='.five_lens_process_evidence.root_synthesis_ownership = "lens_worker"' ;;
        missing_lens_fallback_evidence_ref) mutation_filter='del(.five_lens_process_evidence.lens_fallback_evidence.evidence_ref)' ;;
        *) return 2 ;;
    esac
    jq "$mutation_filter" "$response_path" >"$response_path.mutated" && mv "$response_path.mutated" "$response_path"
    if [[ "$mutation" == "hidden_packet_manifest_field" ]]; then
        manifest_digest="$(jq '.five_lens_process_evidence.frozen_packet_set.packet_manifest' "$response_path" | research_content_digest_json)"
        jq --arg digest "$manifest_digest" '.five_lens_process_evidence.frozen_packet_set.packet_set_digest = $digest' "$response_path" >"$response_path.mutated" \
            && mv "$response_path.mutated" "$response_path"
    fi
    case "$mutation" in
        source_invalid_domain|source_private_loopback|source_backed_empty|synchronized_assignments) research_refresh_response_derivatives "$response_path" ;;
    esac

    if "$research_eval_runner" --responses "$eval_dir" --skill assistant-research --case "$case_id" >"$eval_output" 2>&1; then
        printf 'official runner accepted mutation: %s\n' "$mutation" >&2
        return 1
    fi
    grep -Fq $'FAIL\tassistant-research\t'"$case_id" "$eval_output"
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
    /^handoffs:/ { handoffs = 1 }
    handoffs && /^  - name: orchestrator_to_research_peer_reviewer/ { active = 1 }
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
    /^handoffs:/ { handoffs = 1 }
    handoffs && /^  - name: orchestrator_to_research_peer_reviewer/ { active = 1 }
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
    /^handoffs:/ { handoffs = 1 }
    handoffs && /^  - name: orchestrator_to_lens_researcher/ { active = 1 }
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
    /^handoffs:/ { handoffs = 1 }
    handoffs && /^  - name: orchestrator_to_research_peer_reviewer/ { active = 1 }
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
    /^handoffs:/ { handoffs = 1 }
    handoffs && /^  - name: orchestrator_to_lens_researcher/ { active = 1 }
    active { print }
    active && /^  - name: / && $0 !~ /orchestrator_to_lens_researcher/ { exit }
' "$research_handoffs")"
peer_handoff_schema="$(awk '
    /^handoffs:/ { handoffs = 1 }
    handoffs && /^  - name: orchestrator_to_research_peer_reviewer/ { active = 1 }
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
    if ! grep -Fq -- "$term" <<<"$lens_handoff_schema
$peer_handoff_schema
$output_peer_schema
$process_evidence_schema"; then
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
    /^handoffs:/ { handoffs = 1 }
    handoffs && /^  - name: orchestrator_to_research_peer_reviewer/ { active = 1 }
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
    /^handoffs:/ { handoffs = 1 }
    handoffs && /^  - name: orchestrator_to_research_peer_reviewer/ { active = 1 }
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
    /^handoffs:/ { handoffs = 1 }
    handoffs && /^  - name: orchestrator_to_lens_researcher/ { active = 1 }
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
    'ordered manifest array' \
    'packet_content_digest' \
    'matching non-self-referential packet content_digest'; do
    if ! grep -Fq -- "$term" <<<"$lens_handoff_schema
$process_evidence_schema"; then
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
    length >= 4
    and any(.[]; . == {"operator":"equals","path":["five_lens_process_evidence","lens_execution_mode"],"expected":"delegated"})
    and any(.[]; . == {"operator":"path_absent","path":["five_lens_process_evidence","fallback_lens_passes"]})
    and any(.[]; .operator == "array_field_values_exact" and .path == ["five_lens_process_evidence","lens_dispatches"] and .field == "lens_kind")
    and any(.[]; .operator == "array_field_values_exact" and .path == ["five_lens_process_evidence","accepted_lens_results"] and .field == "lens_kind")
    and any(.[]; . == {"operator":"equals","path":["peer_review","verdict"],"expected":"revise"})
    and any(.[]; . == {"operator":"equals_path","path":["five_lens_process_evidence","peer_reviewer_identity"],"other_path":["peer_review","peer_reviewer_identity"]})
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
    && research_structured_mutation_is_rejected blocked_presentation \
    && research_structured_mutation_is_rejected peer_execution_mode_mismatch \
    && research_structured_mutation_is_rejected peer_identity_mismatch \
    && research_structured_mutation_is_rejected perspective_digest_mismatch \
    && research_structured_mutation_is_rejected perspective_assignment_mismatch \
    && research_structured_mutation_is_rejected perspective_content_drift \
    && research_structured_mutation_is_rejected question_trace_content_drift \
    && research_structured_mutation_is_rejected accepted_result_body_drift \
    && research_structured_mutation_is_rejected accepted_result_assignment_drift \
    && research_structured_mutation_is_rejected peer_result_projection_drift \
    && research_structured_mutation_is_rejected process_result_digest_mismatch \
    && research_structured_mutation_is_rejected missing_per_lens_usage \
    && research_structured_mutation_is_rejected negative_per_lens_usage \
    && research_structured_mutation_is_rejected per_lens_actual_over_ceiling \
    && research_structured_mutation_is_rejected overall_totals_over_ceiling \
    && research_structured_mutation_is_rejected overall_query_sum_drift \
    && research_structured_mutation_is_rejected wall_clock_drift \
    && research_structured_mutation_is_rejected schedule_wall_clock_drift \
    && research_structured_mutation_is_rejected peer_blocked_revise \
    && research_structured_mutation_is_rejected missing_required_revisions \
    && research_structured_mutation_is_rejected missing_revision_disposition \
    && research_structured_mutation_is_rejected peer_identity_reused_from_lens \
    && research_structured_mutation_is_rejected reversed_freeze_proof \
    && research_structured_mutation_is_rejected missing_freeze_proof \
    && research_structured_mutation_is_rejected huge_budget_loop_forever \
    && research_structured_mutation_is_rejected source_invalid_domain \
    && research_structured_mutation_is_rejected source_private_loopback \
    && research_structured_mutation_is_rejected source_backed_empty \
    && research_structured_mutation_is_rejected synchronized_assignments \
    && research_structured_mutation_is_rejected missing_delegated_trigger_scope \
    && research_structured_mutation_is_rejected lens_worker_synthesis; then
    pass
else
    fail "assistant-research delegated structured eval oracle is incomplete or accepts a process-evidence mutation: ${structured_oracle_missing[*]-}"
fi

test_start "assistant-research eval structurally validates sequential fallback without native leakage"
if research_fallback_structured_mutation_is_rejected false_return_validated \
    && research_fallback_structured_mutation_is_rejected packet_binding_mismatch \
    && research_fallback_structured_mutation_is_rejected fallback_dispatch_identity_leakage \
    && research_fallback_structured_mutation_is_rejected peer_fallback_reuses_lens_pass \
    && research_fallback_structured_mutation_is_rejected perspective_digest_mismatch \
    && research_fallback_structured_mutation_is_rejected perspective_assignment_mismatch \
    && research_fallback_structured_mutation_is_rejected perspective_content_drift \
    && research_fallback_structured_mutation_is_rejected question_trace_content_drift \
    && research_fallback_structured_mutation_is_rejected accepted_result_body_drift \
    && research_fallback_structured_mutation_is_rejected accepted_result_assignment_drift \
    && research_fallback_structured_mutation_is_rejected peer_result_projection_drift \
    && research_fallback_structured_mutation_is_rejected process_result_digest_mismatch \
    && research_fallback_structured_mutation_is_rejected missing_per_lens_usage \
    && research_fallback_structured_mutation_is_rejected negative_per_lens_usage \
    && research_fallback_structured_mutation_is_rejected per_lens_actual_over_ceiling \
    && research_fallback_structured_mutation_is_rejected overall_totals_over_ceiling \
    && research_fallback_structured_mutation_is_rejected overall_query_sum_drift \
    && research_fallback_structured_mutation_is_rejected wall_clock_drift \
    && research_fallback_structured_mutation_is_rejected schedule_wall_clock_drift \
    && research_fallback_structured_mutation_is_rejected exhausted_without_low_confidence \
    && research_fallback_structured_mutation_is_rejected exhaustion_without_explicit_gap \
    && research_fallback_structured_mutation_is_rejected missing_lens_fallback_evidence_ref; then
    pass
else
    fail "assistant-research fallback structured eval oracle accepts invalid fallback evidence"
fi

test_start "assistant-research official response grading rejects semantic process-evidence mutations"
if research_official_response_mutation_is_rejected accepted_result_body_with_unchanged_digest \
    && research_official_response_mutation_is_rejected missing_per_lens_usage \
    && research_official_response_mutation_is_rejected hidden_extra_accepted_result_field \
    && research_official_response_mutation_is_rejected missing_resource_budget \
    && research_official_response_mutation_is_rejected hidden_packet_manifest_field \
    && research_official_response_mutation_is_rejected peer_blocked_revise \
    && research_official_response_mutation_is_rejected missing_required_revisions \
    && research_official_response_mutation_is_rejected missing_revision_disposition \
    && research_official_response_mutation_is_rejected peer_identity_reused_from_lens \
    && research_official_response_mutation_is_rejected reversed_freeze_proof \
    && research_official_response_mutation_is_rejected missing_freeze_proof \
    && research_official_response_mutation_is_rejected huge_budget_loop_forever \
    && research_official_response_mutation_is_rejected source_invalid_domain \
    && research_official_response_mutation_is_rejected source_private_loopback \
    && research_official_response_mutation_is_rejected source_backed_empty \
    && research_official_response_mutation_is_rejected synchronized_assignments \
    && research_official_response_mutation_is_rejected missing_delegated_trigger_scope \
    && research_official_response_mutation_is_rejected lens_worker_synthesis \
    && research_official_response_mutation_is_rejected missing_lens_fallback_evidence_ref; then
    pass
else
    fail "assistant-research official response grading accepted a semantic process-evidence mutation"
fi

test_start "assistant-research fixture validation keeps semantic evaluators closed-world"
semantic_fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-semantic-fixture.XXXXXX")"
semantic_fixture_output="$(mktemp "${TMPDIR:-/tmp}/assistant-research-semantic-fixture-output.XXXXXX")"
p0p4_register_cleanup "$semantic_fixture_root" "$semantic_fixture_output"
cp -R "$FRAMEWORK_DIR/skills/assistant-research" "$semantic_fixture_root/assistant-research"
semantic_fixture="$semantic_fixture_root/assistant-research/evals/cases.json"
jq '(.cases[] | select(.id == "five-lens-decision-briefing-uses-storm-style-workflow") | .semantic_validator) = "untrusted.command"' \
    "$semantic_fixture" >"$semantic_fixture.next" && mv "$semantic_fixture.next" "$semantic_fixture"
unknown_semantic_validator_rejected=false
if ! "$research_eval_runner" --validate-fixture --skill "$semantic_fixture_root/assistant-research" >"$semantic_fixture_output" 2>&1 \
    && grep -Fq -- 'semantic_validator must be the allowlisted assistant-research.five_lens_v3' "$semantic_fixture_output"; then
    unknown_semantic_validator_rejected=true
fi
cp "$research_evals" "$semantic_fixture"
jq 'del(.cases[] | select(.id == "five-lens-sequential-fallback-preserves-process-evidence") | .semantic_validator)' \
    "$semantic_fixture" >"$semantic_fixture.next" && mv "$semantic_fixture.next" "$semantic_fixture"
partial_semantic_validator_declaration_rejected=false
if ! "$research_eval_runner" --validate-fixture --skill "$semantic_fixture_root/assistant-research" >"$semantic_fixture_output" 2>&1 \
    && grep -Fq -- 'semantic_validator must be declared by exactly the two five-lens assistant-research cases' "$semantic_fixture_output"; then
    partial_semantic_validator_declaration_rejected=true
fi
if [[ "$unknown_semantic_validator_rejected" == true && "$partial_semantic_validator_declaration_rejected" == true ]]; then
    pass
else
    fail "assistant-research fixture validation accepted an unknown or partially declared semantic evaluator"
fi

test_start "assistant-research scopes peer follow-up validation to the peer handoff subtree"
peer_lens_schema="$(awk '
    /^handoffs:/ { handoffs = 1 }
    handoffs && /^  - name: orchestrator_to_research_peer_reviewer/ { peer = 1 }
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

test_start "assistant-research PR-53 handoff recovery, bindings, and fallback oracle stay strict"
pr53_missing=()
lens_return_schema="$(printf '%s\n' "$lens_handoff_schema" | awk '/return_fields:/ { active = 1 } active { print }')"
if ! printf '%s\n' "$lens_return_schema" | grep -Fq -- '{name: packet_set_id, type: string, required: true}'; then
    pr53_missing+=("lens return packet_set_id")
fi
output_purpose_schema="$(awk '
    /- name: output_purpose/ { active = 1 }
    active { print }
    active && /^  - name: / && $0 !~ /output_purpose/ { exit }
' "$FRAMEWORK_DIR/skills/assistant-research/contracts/input.yaml")"
if ! printf '%s\n' "$output_purpose_schema" | grep -Fq -- 'on_missing: infer' \
    || ! printf '%s\n' "$output_purpose_schema" | grep -Fq -- 'user research question'; then
    pr53_missing+=("safe output_purpose inference")
fi
peer_context_schema="$(awk '
    /^handoffs:/ { handoffs = 1 }
    handoffs && /^  - name: orchestrator_to_research_peer_reviewer/ { active = 1 }
    active { print }
    active && /^    return_fields:/ { exit }
' "$research_handoffs")"
if ! printf '%s\n' "$peer_context_schema" | awk '/name: verification_gaps/ { active = 1 } active { print } active && /name: high_stakes_context/ { exit }' \
    | grep -Fq -- 'Non-empty whenever verified_source_evidence is empty'; then
    pr53_missing+=("verification gaps for empty evidence")
fi
if ! grep -Fq -- 'id: research-common-dispatch-protocol' "$research_index" \
    || ! grep -Fq -- 'id: research-selected-return-validation' "$research_index"; then
    pr53_missing+=("selectable handoff protocol bundles")
fi
for binding in \
    'peer_review.peer_review_assignment_id' \
    'peer_review.peer_review_execution_mode' \
    'peer_review.peer_reviewer_identity' \
    'peer_review.peer_review_fallback_pass_id'; do
    if ! printf '%s\n' "$process_evidence_schema" | grep -Fq -- "Exactly equals $binding"; then
        pr53_missing+=("process peer binding: $binding")
    fi
done
fallback_assertions="$(jq -c '.cases[] | select(.id == "five-lens-sequential-fallback-preserves-process-evidence") | .machine_expectations.structured_json_assertions // []' "$research_evals")"
if ! jq -e '
    length >= 12
    and any(.[]; . == {"operator":"equals","path":["five_lens_process_evidence","lens_execution_mode"],"expected":"sequential_fallback"})
    and any(.[]; .operator == "array_field_values_exact" and .path == ["five_lens_process_evidence","fallback_lens_passes"] and .field == "lens_kind")
    and any(.[]; .operator == "array_field_values_exact" and .path == ["five_lens_process_evidence","accepted_lens_results"] and .field == "lens_kind")
    and any(.[]; . == {"operator":"path_absent","path":["five_lens_process_evidence","lens_dispatches"]})
    and any(.[]; . == {"operator":"nonempty_string","path":["five_lens_process_evidence","lens_fallback_evidence","detail"]})
    and any(.[]; . == {"operator":"nonempty_string","path":["five_lens_process_evidence","peer_review_fallback_evidence","evidence_ref"]})
    and any(.[]; . == {"operator":"equals_path","path":["five_lens_process_evidence","peer_review_fallback_pass_id"],"other_path":["peer_review","peer_review_fallback_pass_id"]})
' <<<"$fallback_assertions" >/dev/null; then
    pr53_missing+=("structured sequential fallback oracle")
fi
if ! printf '%s\n' "$process_evidence_schema" | grep -Fq -- 'distinct from every fallback_lens_passes.root_pass_id'; then
    pr53_missing+=("peer fallback pass must differ from every lens root pass")
fi
for handoff_name in orchestrator_to_lens_researcher orchestrator_to_research_peer_reviewer; do
    handoff_slice="$(awk -v handoff_name="$handoff_name" '
        /^handoffs:/ { handoffs = 1 }
        handoffs && $0 == "  - name: " handoff_name { active = 1 }
        active { print }
        active && /^  - name: / && $0 != "  - name: " handoff_name { exit }
    ' "$research_handoffs")"
    if ! printf '%s\n' "$handoff_slice" | grep -Fq -- 'on_missing_field:'; then
        pr53_missing+=("$handoff_name actionable on_missing_field")
    elif [[ "$handoff_name" == "orchestrator_to_lens_researcher" ]] \
        && (! printf '%s\n' "$handoff_slice" | grep -Fq -- 'same LensResearcher assignment once' \
            || ! printf '%s\n' "$handoff_slice" | grep -Fq -- 'complete lens stage' \
            || ! printf '%s\n' "$handoff_slice" | grep -Fq -- 'fallback or block'); then
        pr53_missing+=("lens on_missing_field must cap retry then fallback-or-block")
    elif [[ "$handoff_name" == "orchestrator_to_research_peer_reviewer" ]] \
        && (! printf '%s\n' "$handoff_slice" | grep -Fq -- 'one peer correction' \
            || ! printf '%s\n' "$handoff_slice" | grep -Fq -- 'reviewer-only fallback' \
            || ! printf '%s\n' "$handoff_slice" | grep -Fq -- 'or block'); then
        pr53_missing+=("peer on_missing_field must cap correction then reviewer fallback-or-block")
    fi
done
if ! jq -e '.cases[] | select(.id == "five-lens-sequential-fallback-preserves-process-evidence") | .machine_expectations.forbidden_substrings | index("dispatch_identity")' "$research_evals" >/dev/null; then
    pr53_missing+=("fallback raw dispatch identity rejection")
fi
if [[ "${#pr53_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research PR-53 contract repair missing: ${pr53_missing[*]}"
fi

test_start "assistant-research binds canonical digests, result projections, usage, and non-URL verification"
integrity_missing=()
for term in ContentDigest SearchResourceUsage 'lowercase hexadecimal SHA-256' 'RFC 8785 JSON Canonicalization Scheme (JCS)' 'number serialization' 'no trailing newline is hashed' 'lens_result_digest'; do
    if ! grep -Fq -- "$term" "$research_handoffs"; then integrity_missing+=("handoff: $term"); fi
done
for term in lens_result_digest search_resource_usage overall_resource_usage verification_method verification_reference; do
    if ! grep -Fq -- "$term" "$research_output" && ! grep -Fq -- "$term" "$research_handoffs"; then integrity_missing+=("contract: $term"); fi
done
for term in local_repository authenticated_source offline_authoritative_source 'Exactly one matching LensKind, assignment_id, and recomputed lens_result_digest' 'usable output never exceeds overall ceilings'; do
    if ! grep -Fq -- "$term" "$research_output" && ! grep -Fq -- "$term" "$research_handoffs"; then integrity_missing+=("rule: $term"); fi
done
if [[ "${#integrity_missing[@]}" -eq 0 ]]; then pass; else fail "assistant-research integrity contract missing: ${integrity_missing[*]}"; fi

test_start "assistant-research executable verified-source evidence predicate enforces method-specific URL rules"
if printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://www.iana.org/domains/example","verified_url":"https://www.iana.org/domains/example"}' \
    | research_verified_source_evidence_is_valid \
    && printf '%s\n' '{"verification_method":"local_repository","verification_reference":"skills/assistant-research/contracts/handoffs.yaml#verified_source_evidence"}' \
    | research_verified_source_evidence_is_valid \
    && printf '%s\n' '{"verification_method":"authenticated_source","verification_reference":"connector:research-index/record:source-1"}' \
        | research_verified_source_evidence_is_valid \
    && printf '%s\n' '{"verification_method":"offline_authoritative_source","verification_reference":"citation:ISBN-978-0-00-000000-0"}' \
        | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://example.invalid/source"}' \
        | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"local_repository"}' \
        | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"offline_authoritative_source","verification_reference":"publication:stable-citation","verified_url":"https://example.invalid/source"}' \
        | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"http://example.invalid/source","verified_url":"http://example.invalid/source"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://user:token@example.invalid/source","verified_url":"https://user:token@example.invalid/source"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://127.0.0.1/source","verified_url":"https://127.0.0.1/source"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://[::1]/source","verified_url":"https://[::1]/source"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://catalog.invalid/source","verified_url":"https://catalog.invalid/source"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://[fd00::1]/source","verified_url":"https://[fd00::1]/source"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://[::ffff:127.0.0.1]/source","verified_url":"https://[::ffff:127.0.0.1]/source"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://2130706433/source","verified_url":"https://2130706433/source"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://catalog.internal/source","verified_url":"https://catalog.internal/source"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://198.51.100.1/source","verified_url":"https://198.51.100.1/source"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://192.0.2.1/source","verified_url":"https://192.0.2.1/source"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://203.0.113.1/source","verified_url":"https://203.0.113.1/source"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://[2001:db8::1]/source","verified_url":"https://[2001:db8::1]/source"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://[ff02::1]/source","verified_url":"https://[ff02::1]/source"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://[::]/source","verified_url":"https://[::]/source"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"local_repository","verification_reference":"../secrets#record"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"local_repository","verification_reference":"/Users/name/repo#record"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"authenticated_source","verification_reference":"connector:private/record:person@example.com"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"authenticated_source","verification_reference":"https://user:token@connector.invalid/record:source-1"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"authenticated_source","verification_reference":"connector:private.internal/record:token-placeholder"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"offline_authoritative_source","verification_reference":"citation:123-45-6789"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"offline_authoritative_source","verification_reference":"citation:555-123-4567"}' | research_verified_source_evidence_is_valid \
    && ruby -ryaml -e '
        handoffs = YAML.load_file(ARGV.fetch(0)).fetch("handoffs")
        peer = handoffs.find { |handoff| handoff["name"] == "orchestrator_to_research_peer_reviewer" }
        evidence = peer.fetch("context_fields").find { |field| field["name"] == "verified_source_evidence" }
        fields = evidence.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
        method = fields.fetch("verification_method")
        reference = fields.fetch("verification_reference")
        url = fields.fetch("verified_url")
        guard = evidence.fetch("validation") + " " + reference.fetch("validation")
        exit method["type"] == "enum" && method["enum_values"] == ["public_url", "local_repository", "authenticated_source", "offline_authoritative_source"] &&
          reference["type"] == "string" && reference["required"] == true &&
          url["type"] == "string" && url["required"] == "conditional" &&
          url["condition"] == "verification_method == public_url" &&
          url.fetch("validation").include?("absent") && url.fetch("validation").include?("non-URL") &&
          ["credential", "token", "PII", "private", "absolute host path"].all? { |term| guard.include?(term) } ? 0 : 1
    ' "$research_handoffs"; then
    pass
else
    fail "assistant-research verified-source evidence predicate or conditional contract fields accepted an invalid URL method combination"
fi

test_start "assistant-research JCS rejects unpaired surrogates and accepts paired Unicode scalars"
lone_high_surrogate='{"value":"\uD800"}'
lone_low_surrogate='{"value":"\uDC00"}'
lone_high_key='{"\uD800":"value"}'
paired_surrogate='{"value":"\uD83D\uDE00"}'
if ! printf '%s' "$lone_high_surrogate" | research_jcs_canonical_json >/dev/null 2>&1 \
    && ! printf '%s' "$lone_low_surrogate" | research_jcs_canonical_json >/dev/null 2>&1 \
    && ! printf '%s' "$lone_high_key" | research_jcs_canonical_json >/dev/null 2>&1 \
    && [[ "$(printf '%s' "$paired_surrogate" | research_jcs_canonical_json)" == '{"value":"😀"}' ]]; then
    pass
else
    fail "assistant-research JCS canonicalization accepted an unpaired surrogate or rejected a valid Unicode scalar"
fi

test_start "assistant-research canonical ContentDigest excludes self fields and preserves manifest order"
packet_preimage_a='{"packet_id":"packet-practitioner","packet_set_id":"packet-set-1","content_digest":"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","question":"Should we adopt the tool?","tier":"extensive","user_role_or_goal":"architecture decision","output_purpose":"Answer the research question","known_context":["local fixture"],"evidence_budget":"six sources","search_resource_budget":{"per_lens_max_queries":5,"per_lens_max_sources":6,"per_lens_max_minutes":15,"overall_max_queries":25,"overall_max_sources":30,"overall_max_minutes":75,"stop_condition":"saturation_or_hard_ceiling"},"source_policy":"public sources","isolation_policy":"sibling blind","lens_kind":"practitioner","packet_frozen_at":"2026-09-03T10:00:00Z"}'
packet_preimage_b='{"packet_frozen_at":"2026-09-03T10:00:00Z","lens_kind":"practitioner","isolation_policy":"sibling blind","source_policy":"public sources","search_resource_budget":{"stop_condition":"saturation_or_hard_ceiling","overall_max_minutes":75,"overall_max_sources":30,"overall_max_queries":25,"per_lens_max_minutes":15,"per_lens_max_sources":6,"per_lens_max_queries":5},"evidence_budget":"six sources","known_context":["local fixture"],"output_purpose":"Answer the research question","user_role_or_goal":"architecture decision","tier":"extensive","question":"Should we adopt the tool?","content_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","packet_set_id":"packet-set-1","packet_id":"packet-practitioner"}'
canonical_packet_a="$(jq 'del(.content_digest)' <<<"$packet_preimage_a" | research_jcs_canonical_json)"
canonical_packet_b="$(jq 'del(.content_digest)' <<<"$packet_preimage_b" | research_jcs_canonical_json)"
packet_digest_a="$(jq 'del(.content_digest)' <<<"$packet_preimage_a" | research_content_digest_json)"
packet_digest_b="$(jq 'del(.content_digest)' <<<"$packet_preimage_b" | research_content_digest_json)"
packet_digest_mutated="$(jq '.question = "Should we defer the tool?" | del(.content_digest)' <<<"$packet_preimage_a" | research_content_digest_json)"
manifest_a='[{"packet_id":"packet-practitioner","lens_kind":"practitioner","content_digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},{"packet_id":"packet-academic","lens_kind":"academic_or_technical_expert","content_digest":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]'
manifest_b='[{"packet_id":"packet-academic","lens_kind":"academic_or_technical_expert","content_digest":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},{"packet_id":"packet-practitioner","lens_kind":"practitioner","content_digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]'
manifest_digest_a="$(printf '%s' "$manifest_a" | research_content_digest_json)"
manifest_digest_b="$(printf '%s' "$manifest_b" | research_content_digest_json)"
jcs_vector='{"z":"é","control":"\u000f\n\"\\\\","whole":1.0,"negative_zero":-0.0,"small":1e-7,"large":1e21}'
jcs_vector_canonical="$(printf '%s' "$jcs_vector" | research_jcs_canonical_json)"
content_digest_contract="$(printf '%s\n%s\n' "$(sed -n '1,125p' "$research_handoffs")" "$(sed -n '360,385p' "$research_output")")"
content_digest_without_preimage="$(sed '/content_digest is ContentDigest over the RFC 8785 JCS bytes of a JSON object containing exactly/d' <<<"$content_digest_contract")"
content_digest_without_exclusion="$(sed 's/it excludes content_digest itself/omits the self-field rule/' <<<"$content_digest_contract")"
content_digest_without_algorithm="$(sed '/lowercase hexadecimal SHA-256/d' <<<"$content_digest_contract")"
if jq -e 'has("content_digest")' <<<"$packet_preimage_a" >/dev/null \
    && [[ "$canonical_packet_a" == "$canonical_packet_b" ]] \
    && [[ "$packet_digest_a" == "$packet_digest_b" ]] \
    && [[ "$packet_digest_a" =~ ^sha256:[0-9a-f]{64}$ ]] \
    && [[ "$packet_digest_a" != "$packet_digest_mutated" ]] \
    && [[ "$manifest_digest_a" =~ ^sha256:[0-9a-f]{64}$ ]] \
    && [[ "$manifest_digest_a" != "$manifest_digest_b" ]] \
    && [[ "$jcs_vector_canonical" == *'"negative_zero":0'* ]] \
    && [[ "$jcs_vector_canonical" == *'"whole":1'* ]] \
    && [[ "$jcs_vector_canonical" == *'"small":1e-7'* ]] \
    && [[ "$jcs_vector_canonical" == *'"large":1e+21'* ]] \
    && grep -Fq '\u000f' <<<"$jcs_vector_canonical" \
    && grep -Fq '\n' <<<"$jcs_vector_canonical" \
    && grep -Fq '\\' <<<"$jcs_vector_canonical" \
    && [[ "$jcs_vector_canonical" == *'"z":"é"'* ]] \
    && research_content_digest_contract_is_strict "$content_digest_contract" \
    && ! research_content_digest_contract_is_strict "$content_digest_without_preimage" \
    && ! research_content_digest_contract_is_strict "$content_digest_without_exclusion" \
    && ! research_content_digest_contract_is_strict "$content_digest_without_algorithm"; then
    pass
else
    fail "assistant-research ContentDigest oracle did not enforce canonical preimages, self-field exclusion, or ordered manifests"
fi

test_start "assistant-research relational resource oracle accepts an alternate under-ceiling response"
alternate_response="$(mktemp "${TMPDIR:-/tmp}/assistant-research-under-ceiling.XXXXXX")"
p0p4_register_cleanup "$alternate_response"
research_jcs_node build delegated alternate >"$alternate_response"
jq '
  .five_lens_process_evidence.lens_dispatches |= map(
    .search_resource_usage = {actual_queries:2,actual_sources:3,elapsed_minutes:8,termination_state:"saturation",exhausted_dimensions:[],confidence_downgraded:false}
  )
  | .five_lens_process_evidence.overall_resource_usage = {actual_queries:10,actual_sources:15,elapsed_minutes:8,termination_state:"saturation",exhausted_dimensions:[],confidence_downgraded:false}
' "$alternate_response" >"$alternate_response.next" && mv "$alternate_response.next" "$alternate_response"
if research_response_oracle_is_valid "$alternate_response"; then
    pass
else
    fail "assistant-research relational resource oracle rejected a valid alternate under-ceiling response"
fi

test_start "assistant-research relational resource oracle accepts a valid multi-wave delegated schedule"
multi_wave_response="$(mktemp "${TMPDIR:-/tmp}/assistant-research-multi-wave.XXXXXX")"
p0p4_register_cleanup "$multi_wave_response"
research_jcs_node build delegated alternate >"$multi_wave_response"
jq '
  .five_lens_process_evidence.lens_dispatches[2].wave_id = "wave-2"
  | .five_lens_process_evidence.lens_dispatches[3].wave_id = "wave-2"
  | .five_lens_process_evidence.lens_dispatches[4].wave_id = "wave-2"
  | .five_lens_process_evidence.wave_coverage = [
      {wave_id:"wave-1",capacity:2,lens_kinds:["practitioner","academic_or_technical_expert"]},
      {wave_id:"wave-2",capacity:3,lens_kinds:["skeptic","economist_or_incentives_analyst","historian_or_pattern_matcher"]}
    ]
  | .five_lens_process_evidence.overall_resource_usage.elapsed_minutes = 20
' "$multi_wave_response" >"$multi_wave_response.next" && mv "$multi_wave_response.next" "$multi_wave_response"
if research_response_oracle_is_valid "$multi_wave_response"; then
    pass
else
    fail "assistant-research relational resource oracle rejected a valid multi-wave delegated schedule"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
