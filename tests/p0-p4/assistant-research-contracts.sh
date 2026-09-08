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
        elif [[ "$case_id" == "five-lens-delegated-lenses-sequential-peer-fallback" ]] \
            && jq -e --arg case_id "$case_id" '
                .cases[] | select(.id == $case_id)
                | (.machine_expectations.structured_json_assertions? // [] | length > 0)
            ' "$research_evals" >/dev/null; then
            write_schema_valid_five_lens_eval_response delegated_peer_fallback "$output_dir/assistant-research/$case_id.txt"
        elif [[ "$case_id" == "five-lens-quick-normalizes-to-standard" ]] \
            && jq -e --arg case_id "$case_id" '
                .cases[] | select(.id == $case_id)
                | (.machine_expectations.structured_json_assertions? // [] | length > 0)
            ' "$research_evals" >/dev/null; then
            write_schema_valid_five_lens_eval_response quick_normalized "$output_dir/assistant-research/$case_id.txt"
        elif [[ "$case_id" == "five-lens-retains-all-material-follow-ups" ]] \
            && jq -e --arg case_id "$case_id" '
                .cases[] | select(.id == $case_id)
                | .semantic_validator == "assistant-research.five_lens_v3"
            ' "$research_evals" >/dev/null; then
            write_schema_valid_five_lens_eval_response retained_follow_ups "$output_dir/assistant-research/$case_id.txt"
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
        source_fully_encoded_private_loopback) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = ["https%3A%2F%2F127.0.0.1%2Fresearch"] | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].sources_or_verified_urls = ["https%3A%2F%2F127.0.0.1%2Ffollow-up"]' ;;
        source_backed_empty) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = [] | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].sources_or_verified_urls = []' ;;
        synchronized_assignments) mutation_filter='.five_lens_process_evidence.accepted_lens_results |= map(.assignment_id = "assignment-shared") | .five_lens_process_evidence.lens_dispatches |= map(.assignment_id = "assignment-shared") | .five_lens_process_evidence.peer_review_assignment_id = "assignment-shared" | .peer_review.peer_review_assignment_id = "assignment-shared"' ;;
        missing_delegated_trigger_scope) mutation_filter='del(.five_lens_process_evidence.subagent_trigger_scope)' ;;
        lens_worker_synthesis) mutation_filter='.five_lens_process_evidence.root_synthesis_ownership = "lens_worker"' ;;
        missing_findings) mutation_filter='del(.findings)' ;;
        missing_conflicts) mutation_filter='del(.conflicts)' ;;
        missing_gaps) mutation_filter='del(.gaps)' ;;
        missing_summary) mutation_filter='del(.summary)' ;;
        missing_contradiction_map) mutation_filter='del(.contradiction_map)' ;;
        missing_synthesis_briefing) mutation_filter='del(.synthesis_briefing)' ;;
        duplicate_none_needed) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].follow_ups += [.five_lens_process_evidence.accepted_lens_results[0].follow_ups[0]]' ;;
        mixed_none_needed_follow_up) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].follow_ups += [{decision:"follow_up",question:"What independent source can verify this?",answer_or_gap:"No independent source has been checked.",sources_or_verified_urls:["source:research-corpus:follow-up"],evidence_status:"source_backed"}]' ;;
        source_reserved_local) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = ["https://metadata.local/research"] | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].sources_or_verified_urls = ["https://metadata.local/follow-up"]' ;;
        source_bare_hostname) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = ["https://metadata/research"] | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].sources_or_verified_urls = ["https://metadata/follow-up"]' ;;
        malformed_candidate_mechanism) mutation_filter='.candidate_mechanisms = [{mechanism:"invest AI coding assistant .NET architecture malformed candidate",claim_status:"candidate",evidence:[{source:"source:research-corpus:summary",detail:"Candidate support.",evidence_status:"source_backed",unexpected:"field"}],confidence:"low",counterevidence_or_conflicts:["No counterevidence found."],gaps:["Independent validation pending."],validation_method:"Run an independent comparison."}]' ;;
        medium_single_secondary) mutation_filter='.findings[0].confidence = "medium"' ;;
        private_peer_evidence_url) mutation_filter='.peer_review.evidence[0].source = "https://metadata.local/private"' ;;
        unbound_final_finding_source) mutation_filter='.findings[0].sources = ["source:unbound-final-finding"]' ;;
        rebound_unsafe_packet_policies) mutation_filter='.five_lens_process_evidence.frozen_assignment_packets |= map(.source_policy = "public sources" | .isolation_policy = "sibling blind")' ;;
        source_backed_actual_sources_zero) mutation_filter='.five_lens_process_evidence.lens_dispatches[0].search_resource_usage.actual_sources = 0 | .five_lens_process_evidence.overall_resource_usage.actual_sources = 16' ;;
        local_repository_public_url) mutation_filter='.five_lens_process_evidence.peer_review_input_binding.verified_source_evidence[0].verification_reference = "https://www.iana.org/domains/example"' ;;
        authenticated_source_endpoint) mutation_filter='.five_lens_process_evidence.peer_review_input_binding.verified_source_evidence[0].verification_method = "authenticated_source" | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence[0].verification_reference = "connector:fixture/record:https://metadata.local/private"' ;;
        offline_citation_url) mutation_filter='.five_lens_process_evidence.peer_review_input_binding.verified_source_evidence[0].verification_method = "offline_authoritative_source" | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence[0].verification_reference = "citation:https://metadata.local/private"' ;;
        medium_single_public_row_aliases) mutation_filter='.findings[0].confidence = "medium" | .findings[0].sources = ["source:fixture-alias", "https://www.iana.org/domains/example"] | del(.findings[0].source_provenance) | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Alias evidence",source:"source:fixture-alias",verification_method:"public_url",verification_reference:"https://www.iana.org/domains/example",verified_url:"https://www.iana.org/domains/example",verification_detail:"Single public evidence row."}]' ;;
        malformed_peer_url_scheme) mutation_filter='.peer_review.evidence[0].source = "https:metadata.local/peer"' ;;
        malformed_peer_url_without_colon) mutation_filter='.peer_review.evidence[0].source = "https//metadata.local/peer"' ;;
        trailing_dot_peer_url) mutation_filter='.peer_review.evidence[0].source = "https://www.iana.org./peer"' ;;
        medium_host_case_public_url_aliases) mutation_filter='.findings[0].confidence = "medium" | .findings[0].sources = ["https://www.iana.org/domains/example", "https://WWW.IANA.ORG/domains/example", "https://www.%69ana.org/domains/example"] | del(.findings[0].source_provenance) | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Canonical public evidence",source:"https://www.iana.org/domains/example",verification_method:"public_url",verification_reference:"https://www.iana.org/domains/example",verified_url:"https://www.iana.org/domains/example",verification_detail:"First spelling of one public evidence identity."},{claim:"Canonical public evidence alias",source:"https://WWW.IANA.ORG/domains/example",verification_method:"public_url",verification_reference:"https://WWW.IANA.ORG/domains/example",verified_url:"https://WWW.IANA.ORG/domains/example",verification_detail:"Host-case alias of the same public evidence identity."},{claim:"Canonical encoded-host alias",source:"https://www.%69ana.org/domains/example",verification_method:"public_url",verification_reference:"https://www.%69ana.org/domains/example",verified_url:"https://www.%69ana.org/domains/example",verification_detail:"Percent-encoded-host alias of the same public evidence identity."}]' ;;
        high_host_case_public_url_aliases) mutation_filter='.findings[0].confidence = "high" | .findings[0].sources = ["https://www.iana.org/domains/example", "https://WWW.IANA.ORG/domains/example", "https://www.%69ana.org/domains/example"] | .findings[0].source_provenance = [{source:"https://www.iana.org/domains/example",independence_key:"first",authority:"official"},{source:"https://WWW.IANA.ORG/domains/example",independence_key:"second",authority:"primary"},{source:"https://www.%69ana.org/domains/example",independence_key:"third",authority:"secondary"}] | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Canonical public evidence",source:"https://www.iana.org/domains/example",verification_method:"public_url",verification_reference:"https://www.iana.org/domains/example",verified_url:"https://www.iana.org/domains/example",verification_detail:"First spelling."},{claim:"Canonical public evidence alias",source:"https://WWW.IANA.ORG/domains/example",verification_method:"public_url",verification_reference:"https://WWW.IANA.ORG/domains/example",verified_url:"https://WWW.IANA.ORG/domains/example",verification_detail:"Host-case alias."},{claim:"Canonical encoded-host alias",source:"https://www.%69ana.org/domains/example",verification_method:"public_url",verification_reference:"https://www.%69ana.org/domains/example",verified_url:"https://www.%69ana.org/domains/example",verification_detail:"Encoded-host alias."}]' ;;
        medium_path_percent_encoded_public_url_aliases) mutation_filter='.findings[0].confidence = "medium" | .findings[0].sources = ["https://www.iana.org/domains/example", "https://www.iana.org/%64omains/example", "https://www.iana.org/d%6fmains/example"] | del(.findings[0].source_provenance) | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Canonical public evidence",source:"https://www.iana.org/domains/example",verification_method:"public_url",verification_reference:"https://www.iana.org/domains/example",verified_url:"https://www.iana.org/domains/example",verification_detail:"First spelling of one public evidence identity."},{claim:"Canonical encoded path alias",source:"https://www.iana.org/%64omains/example",verification_method:"public_url",verification_reference:"https://www.iana.org/%64omains/example",verified_url:"https://www.iana.org/%64omains/example",verification_detail:"Percent-encoded path alias of the same public evidence identity."},{claim:"Canonical encoded path alias",source:"https://www.iana.org/d%6fmains/example",verification_method:"public_url",verification_reference:"https://www.iana.org/d%6fmains/example",verified_url:"https://www.iana.org/d%6fmains/example",verification_detail:"Percent-encoded path alias of the same public evidence identity."}]' ;;
        high_path_percent_encoded_public_url_aliases) mutation_filter='.findings[0].confidence = "high" | .findings[0].sources = ["https://www.iana.org/domains/example", "https://www.iana.org/%64omains/example", "https://www.iana.org/d%6fmains/example"] | .findings[0].source_provenance = [{source:"https://www.iana.org/domains/example",independence_key:"first",authority:"official"},{source:"https://www.iana.org/%64omains/example",independence_key:"second",authority:"primary"},{source:"https://www.iana.org/d%6fmains/example",independence_key:"third",authority:"secondary"}] | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Canonical public evidence",source:"https://www.iana.org/domains/example",verification_method:"public_url",verification_reference:"https://www.iana.org/domains/example",verified_url:"https://www.iana.org/domains/example",verification_detail:"First spelling."},{claim:"Canonical encoded path alias",source:"https://www.iana.org/%64omains/example",verification_method:"public_url",verification_reference:"https://www.iana.org/%64omains/example",verified_url:"https://www.iana.org/%64omains/example",verification_detail:"Percent-encoded path alias."},{claim:"Canonical encoded path alias",source:"https://www.iana.org/d%6fmains/example",verification_method:"public_url",verification_reference:"https://www.iana.org/d%6fmains/example",verified_url:"https://www.iana.org/d%6fmains/example",verification_detail:"Percent-encoded path alias."}]' ;;
        medium_fully_encoded_public_url_aliases) mutation_filter='.findings[0].confidence = "medium" | .findings[0].sources = ["https://www.iana.org/domains/example", "https%3A%2F%2Fwww.iana.org%2Fdomains%2Fexample"] | del(.findings[0].source_provenance) | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Canonical public evidence",source:"https://www.iana.org/domains/example",verification_method:"public_url",verification_reference:"https://www.iana.org/domains/example",verified_url:"https://www.iana.org/domains/example",verification_detail:"Canonical public evidence."}]' ;;
        high_fully_encoded_public_url_aliases) mutation_filter='.findings[0].confidence = "high" | .findings[0].sources = ["https://www.iana.org/domains/example", "https%3A%2F%2Fwww.iana.org%2Fdomains%2Fexample", "https://www.iana.org/help/example-domains"] | .findings[0].source_provenance = [{source:"https://www.iana.org/domains/example",independence_key:"first",authority:"official"},{source:"https%3A%2F%2Fwww.iana.org%2Fdomains%2Fexample",independence_key:"second",authority:"primary"},{source:"https://www.iana.org/help/example-domains",independence_key:"third",authority:"secondary"}] | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Canonical public evidence",source:"https://www.iana.org/domains/example",verification_method:"public_url",verification_reference:"https://www.iana.org/domains/example",verified_url:"https://www.iana.org/domains/example",verification_detail:"Canonical public evidence."},{claim:"Distinct public evidence",source:"https://www.iana.org/help/example-domains",verification_method:"public_url",verification_reference:"https://www.iana.org/help/example-domains",verified_url:"https://www.iana.org/help/example-domains",verification_detail:"Distinct public evidence."}]' ;;
        protocol_relative_peer_url) mutation_filter='.peer_review.evidence[0].source = "//metadata.local/peer"' ;;
        discard_only_compressed_peer_url) mutation_filter='.peer_review.evidence[0].source = "https://[100::1]/peer"' ;;
        encoded_public_url_secret) mutation_filter='.peer_review.evidence[0].source = "https://www.iana.org/peer?%74oken=private"' ;;
        encoded_public_url_traversal) mutation_filter='.peer_review.evidence[0].source = "https://www.iana.org/a/%2e%2e/private"' ;;
        encoded_public_url_pii) mutation_filter='.peer_review.evidence[0].source = "https://www.iana.org/peer?contact=person%40sample.invalid"' ;;
        encoded_typed_url_secret) mutation_filter='.five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Typed URL safety evidence",source:"source:typed-url-safety",verification_method:"public_url",verification_reference:"https://www.iana.org/peer?%74oken=private",verified_url:"https://www.iana.org/peer?%74oken=private",verification_detail:"Typed public URL mutation."}]' ;;
        encoded_typed_url_traversal) mutation_filter='.five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Typed URL safety evidence",source:"source:typed-url-safety",verification_method:"public_url",verification_reference:"https://www.iana.org/a/%2e%2e/private",verified_url:"https://www.iana.org/a/%2e%2e/private",verification_detail:"Typed public URL mutation."}]' ;;
        encoded_typed_url_pii) mutation_filter='.five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Typed URL safety evidence",source:"source:typed-url-safety",verification_method:"public_url",verification_reference:"https://www.iana.org/peer?contact=person%40sample.invalid",verified_url:"https://www.iana.org/peer?contact=person%40sample.invalid",verification_detail:"Typed public URL mutation."}]' ;;
        encoded_opaque_source_traversal) mutation_filter='.peer_review.evidence[0].source = "source:a/%2e%2e/docs"' ;;
        encoded_opaque_source_secret) mutation_filter='.peer_review.evidence[0].source = "source:%74oken=redacted"' ;;
        encoded_opaque_source_pii) mutation_filter='.candidate_mechanisms = [{mechanism:"Candidate source safety mechanism",claim_status:"candidate",evidence:[{source:"source:%65mail=person%40sample.invalid",detail:"Candidate source mutation.",evidence_status:"source_backed"}],confidence:"low",counterevidence_or_conflicts:["No counterevidence recorded."],gaps:["Independent validation remains pending."],validation_method:"Compare independent evidence."}]' ;;
        opaque_source_credential) mutation_filter='.peer_review.evidence[0].source = "source:credential=opaque-value"' ;;
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
        source_invalid_domain|source_private_loopback|source_fully_encoded_private_loopback|source_backed_empty|synchronized_assignments|duplicate_none_needed|mixed_none_needed_follow_up|source_reserved_local|source_bare_hostname|malformed_candidate_mechanism|medium_single_secondary|unbound_final_finding_source|rebound_unsafe_packet_policies|local_repository_public_url|authenticated_source_endpoint|offline_citation_url|medium_single_public_row_aliases|medium_host_case_public_url_aliases|medium_path_percent_encoded_public_url_aliases|high_host_case_public_url_aliases|high_path_percent_encoded_public_url_aliases|medium_fully_encoded_public_url_aliases|high_fully_encoded_public_url_aliases|encoded_typed_url_secret|encoded_typed_url_traversal|encoded_typed_url_pii|encoded_opaque_source_traversal|encoded_opaque_source_secret|encoded_opaque_source_pii|opaque_source_credential) research_refresh_response_derivatives "$response_path" ;;
    esac

    if research_response_oracle_is_valid "$response_path" "$case_id"; then
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
        fallback_wave_coverage_leakage) mutation_filter='.five_lens_process_evidence.wave_coverage = [{wave_id:"wave-1",capacity:5,lens_kinds:["practitioner","academic_or_technical_expert","skeptic","economist_or_incentives_analyst","historian_or_pattern_matcher"]}]' ;;
        *) return 2 ;;
    esac
    jq "$mutation_filter" "$response_path" >"$response_path.mutated" && mv "$response_path.mutated" "$response_path"

    ! research_response_oracle_is_valid "$response_path" "$case_id"
}

research_verified_source_evidence_is_valid() {
    ruby -rjson -ruri -ripaddr -e '
        def unsafe_opaque_reference?(text)
          return true if text.match?(/%(?![0-9a-f]{2})/i)
          decoded = URI::DEFAULT_PARSER.unescape(text)
          text.start_with?("//") || text.match?(%r{\Ahttps?(?::(?!//)|/(?!/)|//(?!/))}i) ||
            encoded_http_scheme_like?(decoded) ||
            decoded.match?(/(?:^|[?&#\\\/:_-])(?:token|secret|key|password|email|api[_-]?key|access[_-]?token|bearer|credential|session|authorization)(?:=|$|[\\\/:_-])/i) ||
            decoded.match?(%r{(?:^|[\\/])\.\.(?:[\\/]|$)}) ||
            decoded.match?(%r{\A(?:[A-Za-z]:[\\/]|\\\\|/(?:Users|home|private|var)(?:[\\/]|$)|~(?:[\\/]|$))}i) ||
            decoded.match?(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}|\b\d{3}-\d{2}-\d{4}\b|\b\d{3}[ .-]\d{3}[ .-]\d{4}\b/i)
        rescue ArgumentError
          true
        end
        def encoded_http_scheme_like?(text)
          !text.match?(%r{\Ahttps?://}i) && text.match?(%r{\A(?:h|%(?:25)*(?:68|48))(?:t|%(?:25)*(?:74|54))(?:t|%(?:25)*(?:74|54))(?:p|%(?:25)*(?:70|50))(?:(?:s|%(?:25)*(?:73|53))?(?::|%(?:25)*3a)(?:/|%(?:25)*2f){2})}i)
        end
        def safe_url_reference?(text)
          return false if text.match?(/%(?![0-9a-f]{2})/i)
          uri = URI.parse(text)
          sensitive_component = lambda do |component|
            URI::DEFAULT_PARSER.unescape(component.to_s).sub(/\A[?#]/, "").split(/[&;]/).any? do |field|
              field.split("=").any? { |part| part.match?(/(?:^|[\\\/:_-])(?:token|secret|key|password|email|api[_-]?key|access[_-]?token|bearer|credential|session|authorization)(?:$|[\\\/:_-])/i) }
            end
          end
          !encoded_http_scheme_like?(text) &&
            ![uri.query, uri.fragment].compact.any? { |component| sensitive_component.call(component) } &&
            !URI::DEFAULT_PARSER.unescape(text).match?(%r{(?:^|[\\/])\.\.(?:[\\/]|$)}) &&
            !URI::DEFAULT_PARSER.unescape(text).match?(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}|\b\d{3}-\d{2}-\d{4}\b|\b\d{3}[ .-]\d{3}[ .-]\d{4}\b/i)
        rescue ArgumentError
          false
        end
        def public_host?(host)
          normalized = URI::DEFAULT_PARSER.unescape(host).downcase
          return false if normalized.empty? || normalized.end_with?(".") || %w[local localhost invalid test example internal].include?(normalized) || normalized.end_with?(".localhost", ".internal", ".local", ".invalid", ".test", ".example")
          address = if normalized.match?(/\A\d+\z/) && Integer(normalized, 10) <= 0xffff_ffff
            IPAddr.new_ntoh([Integer(normalized, 10)].pack("N"))
          else
            IPAddr.new(normalized)
          end
          return normalized.include?(".") unless address
          return true if address.ipv4? && %w[192.0.0.9 192.0.0.10].include?(address.to_s)
          non_global_ranges = if address.ipv4?
            %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.88.99.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4]
          else
            %w[::/128 ::1/128 ::ffff:0:0/96 64:ff9b:1::/48 100::/64 100:0:0:1::/64 2001::/23 2001:db8::/32 3fff::/20 5f00::/16 fc00::/7 fe80::/10 ff00::/8]
          end
          global_ipv6_exceptions = %w[2001:1::1/128 2001:1::2/128 2001:1::3/128 2001:3::/32 2001:4:112::/48 2001:20::/28 2001:30::/28]
          return true if address.ipv6? && global_ipv6_exceptions.any? { |cidr| IPAddr.new(cidr).include?(address) }
          return false if address.loopback? || address.private? || address.link_local? || non_global_ranges.any? { |cidr| IPAddr.new(cidr).include?(address) }
          mapped = address.respond_to?(:ipv4_mapped?) && address.ipv4_mapped? ? address.native : nil
          return true unless mapped
          mapped_non_global = %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.88.99.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4]
          !(mapped.loopback? || mapped.private? || mapped.link_local? || mapped_non_global.any? { |cidr| IPAddr.new(cidr).include?(mapped) })
        rescue IPAddr::InvalidAddressError, ArgumentError
          normalized.include?(".") && !normalized.match?(%r{\A\d+(?:\.\d+)*\z})
        end
        evidence = JSON.parse(STDIN.read)
        method = evidence["verification_method"]
        reference = evidence["verification_reference"]
        url = evidence["verified_url"]
        exit 1 unless %w[public_url local_repository authenticated_source offline_authoritative_source].include?(method)
        exit 1 unless reference.is_a?(String) && reference == reference.strip && !reference.empty?
        exit 1 if [reference, url].compact.any? { |text| !text.is_a?(String) }
        valid = case method
        when "public_url"
          begin
            bounded_url = url.is_a?(String) ? (url.match?(%r{\Ahttps?://}i) ? url : URI::DEFAULT_PARSER.unescape(url)) : nil
            if bounded_url&.match?(%r{\Ahttps?://}i)
              uri = URI.parse(bounded_url)
              raw_authority = bounded_url.match(%r{\Ahttps://([^/?#]+)}i)&.[](1)
              host_port = raw_authority&.sub(%r{\A.*@}, "")
              raw_host = host_port&.match(%r{\A(\[[^\]]+\]|[^/:?#]+)})&.[](1)
              alternate_numeric = raw_host && (raw_host.match?(%r{\A(?:0x[0-9a-f]+|0[0-9]+|[0-9]+)\z}i) || raw_host.split(".").any? { |part| part.match?(%r{\A(?:0x[0-9a-f]+|0[0-9]+)\z}i) } || (raw_host.match?(%r{\A\d+(?:\.\d+)+\z}) && raw_host.split(".").length != 4))
              explicit_port = host_port&.match?(%r{(?:\]|[^:]):\d+\z})
              url == reference && uri.scheme == "https" && uri.host && uri.userinfo.nil? && !raw_authority.include?("@") && !explicit_port && !alternate_numeric && safe_url_reference?(bounded_url) && public_host?(uri.host)
            else
              false
            end
          rescue URI::InvalidURIError, TypeError
            false
          end
        when "local_repository"
          !evidence.key?("verified_url") && !unsafe_opaque_reference?(reference) && reference.match?(%r{\A(?!/)(?!.*(?:\A|/)\.\.(?:/|\z))[A-Za-z0-9._/-]+(?:#[A-Za-z0-9._:-]+)?\z})
        when "authenticated_source"
          !evidence.key?("verified_url") && !unsafe_opaque_reference?(reference) && reference.match?(/\Aconnector:[A-Za-z0-9._-]+\/record:[A-Za-z0-9._-]+\z/)
        else
          !evidence.key?("verified_url") && !unsafe_opaque_reference?(reference) && reference.match?(/\A(?:citation|isbn|doi):[^\s]+\z/i) && !reference.include?("://") && !reference.match?(%r{\A(?:citation|isbn|doi):(?:/(?:Users|home|private|var)(?:/|\z)|[A-Za-z]:[\\/]|\\\\)}i)
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

research_set_high_stakes_recommendation_basis() {
    local response_path="$1"
    local context_basis
    local peer_digest

    context_basis="$(jq -r '.five_lens_process_evidence.peer_review_input_binding.high_stakes_context.user_context_basis' "$response_path")"
    peer_digest="$(jq -r '.peer_review.peer_review_input_digest' "$response_path")"
    jq --arg basis "$context_basis" --arg digest "$peer_digest" '
      .high_stakes_recommendation_basis = {
        recommendation: "do",
        verified_decision_critical_urls: ["https://www.iana.org/domains/example"],
        user_context_basis: $basis,
        peer_review_input_digest: $digest,
        peer_supported_recommendation: "do"
      }
    ' "$response_path" >"$response_path.mutated" && mv "$response_path.mutated" "$response_path"
}

research_prepare_high_stakes_stronger_response() {
    local response_path="$1"
    local explicit_context='User supplied a capped reversible pilot with no trading authority.'

    jq --arg context "$explicit_context" '
      .synthesis_briefing.recommendation = "do"
      | .peer_review.supported_recommendation = "do"
      | .findings[0].confidence = "high"
      | .findings[0].sources = ["source:fixture-primary", "source:fixture-official", "source:fixture-secondary"]
      | .findings[0].source_provenance = [
          {source:"source:fixture-primary",independence_key:"fixture-primary",authority:"primary"},
          {source:"source:fixture-official",independence_key:"fixture-official",authority:"official"},
          {source:"source:fixture-secondary",independence_key:"fixture-secondary",authority:"secondary"}
        ]
      | .findings[0].verified_urls = ["https://www.iana.org/domains/example"]
      | .five_lens_process_evidence.peer_review_input_binding.high_stakes_context.user_context_status = "explicit"
      | .five_lens_process_evidence.peer_review_input_binding.high_stakes_context.user_context_basis = $context
      | .five_lens_process_evidence.frozen_assignment_packets |= map(.known_context += [$context])
      | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [
          {claim:"Fixture primary decision evidence",source:"source:fixture-primary",verification_method:"public_url",verification_reference:"https://www.iana.org/domains/example",verified_url:"https://www.iana.org/domains/example",verification_detail:"Primary public fixture evidence."},
          {claim:"Fixture official decision evidence",source:"source:fixture-official",verification_method:"public_url",verification_reference:"https://www.iana.org/help/example-domains",verified_url:"https://www.iana.org/help/example-domains",verification_detail:"Official public fixture evidence."},
          {claim:"Fixture secondary decision evidence",source:"source:fixture-secondary",verification_method:"public_url",verification_reference:"https://www.iana.org/assignments",verified_url:"https://www.iana.org/assignments",verification_detail:"Secondary public fixture evidence."}
        ]
    ' "$response_path" >"$response_path.mutated" && mv "$response_path.mutated" "$response_path"
    research_refresh_response_derivatives "$response_path"
    research_set_high_stakes_recommendation_basis "$response_path"
}

research_official_response_mutation_is_rejected() {
    local mutation="$1"
    local case_id="five-lens-decision-briefing-uses-storm-style-workflow"
    local eval_dir eval_output response_path mutation_filter manifest_digest stale_peer_input_digest final_synthesis_digest

    case "$mutation" in
        missing_lens_fallback_evidence_ref|unusable_peer_needs_context|unusable_peer_blocked|follow_up_own_gap_drift) case_id="five-lens-sequential-fallback-preserves-process-evidence" ;;
        stale_revision_metadata|invalid_peer_fallback_basis|accepted_final_synthesis_substitution) case_id="five-lens-delegated-lenses-sequential-peer-fallback" ;;
        missing_tier_normalization_disclosure|quick_effective_tier_drift|duplicate_perspective_lens|duplicate_question_trace_lens) case_id="five-lens-quick-normalizes-to-standard" ;;
        follow_up_requirement_drift) case_id="five-lens-retains-all-material-follow-ups" ;;
        opt_out_allows_delegated_peer|policy_block_allows_delegated_peer) case_id="five-lens-sequential-fallback-preserves-process-evidence" ;;
    esac
    eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-official-negative.XXXXXX")"
    eval_output="$(mktemp "${TMPDIR:-/tmp}/assistant-research-official-negative-output.XXXXXX")"
    p0p4_register_cleanup "$eval_dir" "$eval_output"
    if [[ "$mutation" == "fallback_wave_coverage_leakage" ]]; then
        case_id="five-lens-sequential-fallback-preserves-process-evidence"
    fi
    write_research_eval_responses "$eval_dir"
    response_path="$eval_dir/assistant-research/$case_id.txt"
    if ! "$research_eval_runner" --responses "$eval_dir" --skill assistant-research --case "$case_id" >"$eval_output" 2>&1; then
        printf 'official runner rejected its generated baseline: %s\n' "$mutation" >&2
        return 1
    fi
    case "$mutation" in
        stronger_context_not_applicable|stronger_context_unresolved|fully_rebound_response_only_high_stakes_context) research_prepare_high_stakes_stronger_response "$response_path" ;;
    esac
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
        source_fully_encoded_private_loopback) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = ["https%3A%2F%2F127.0.0.1%2Fresearch"] | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].sources_or_verified_urls = ["https%3A%2F%2F127.0.0.1%2Ffollow-up"]' ;;
        source_backed_empty) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = [] | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].sources_or_verified_urls = []' ;;
        synchronized_assignments) mutation_filter='.five_lens_process_evidence.accepted_lens_results |= map(.assignment_id = "assignment-shared") | .five_lens_process_evidence.lens_dispatches |= map(.assignment_id = "assignment-shared") | .five_lens_process_evidence.peer_review_assignment_id = "assignment-shared" | .peer_review.peer_review_assignment_id = "assignment-shared"' ;;
        missing_delegated_trigger_scope) mutation_filter='del(.five_lens_process_evidence.subagent_trigger_scope)' ;;
        lens_worker_synthesis) mutation_filter='.five_lens_process_evidence.root_synthesis_ownership = "lens_worker"' ;;
        missing_lens_fallback_evidence_ref) mutation_filter='del(.five_lens_process_evidence.lens_fallback_evidence.evidence_ref)' ;;
        missing_findings) mutation_filter='del(.findings)' ;;
        missing_conflicts) mutation_filter='del(.conflicts)' ;;
        missing_gaps) mutation_filter='del(.gaps)' ;;
        missing_summary) mutation_filter='del(.summary)' ;;
        missing_contradiction_map) mutation_filter='del(.contradiction_map)' ;;
        missing_synthesis_briefing) mutation_filter='del(.synthesis_briefing)' ;;
        unusable_peer_needs_context) mutation_filter='.peer_review.status = "NEEDS_CONTEXT" | .peer_review.verdict = "blocked" | .peer_review.open_questions = ["Which source is required to complete review?"] | .peer_review.status_detail = "Peer review cannot yet produce a usable verdict." | del(.peer_review.confidence_scores,.peer_review.weakest_claim,.peer_review.bias_or_lens_dominance,.peer_review.missing_sixth_perspective,.peer_review.falsification_test,.peer_review.revised_recommendation_if_needed,.peer_review.evidence,.peer_review.required_revisions)' ;;
        unusable_peer_blocked) mutation_filter='.peer_review.status = "BLOCKED" | .peer_review.verdict = "blocked" | .peer_review.open_questions = ["Which dependency prevents peer review?"] | .peer_review.status_detail = "Peer review is blocked by unavailable evidence." | .peer_review.blocker_type = "tool_failure" | .peer_review.blocker_evidence = ["fixture-peer-blocker"] | del(.peer_review.confidence_scores,.peer_review.weakest_claim,.peer_review.bias_or_lens_dominance,.peer_review.missing_sixth_perspective,.peer_review.falsification_test,.peer_review.revised_recommendation_if_needed,.peer_review.evidence,.peer_review.required_revisions)' ;;
        duplicate_none_needed) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].follow_ups += [.five_lens_process_evidence.accepted_lens_results[0].follow_ups[0]]' ;;
        mixed_none_needed_follow_up) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].follow_ups += [{decision:"follow_up",question:"What independent source can verify this?",answer_or_gap:"No independent source has been checked.",sources_or_verified_urls:["source:research-corpus:follow-up"],evidence_status:"source_backed"}]' ;;
        source_reserved_local) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = ["https://metadata.local/research"] | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].sources_or_verified_urls = ["https://metadata.local/follow-up"]' ;;
        source_bare_hostname) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = ["https://metadata/research"] | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].sources_or_verified_urls = ["https://metadata/follow-up"]' ;;
        source_ipv6_discard_only) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = ["https://[100::1]/research"] | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].sources_or_verified_urls = ["https://[100::1]/follow-up"]' ;;
        source_ipv6_dummy_prefix_compressed) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = ["https://[100:0:0:1::1]/research"] | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].sources_or_verified_urls = ["https://[100:0:0:1::1]/follow-up"]' ;;
        source_ipv6_dummy_prefix_full) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = ["https://[0100:0000:0000:0001:0000:0000:0000:0001]/research"] | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].sources_or_verified_urls = ["https://[0100:0000:0000:0001:0000:0000:0000:0001]/follow-up"]' ;;
        medium_path_percent_encoded_public_url_aliases) mutation_filter='.findings[0].confidence = "medium" | .findings[0].sources = ["https://www.iana.org/domains/example", "https://www.iana.org/%64omains/example", "https://www.iana.org/d%6fmains/example"] | del(.findings[0].source_provenance) | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Canonical public evidence",source:"https://www.iana.org/domains/example",verification_method:"public_url",verification_reference:"https://www.iana.org/domains/example",verified_url:"https://www.iana.org/domains/example",verification_detail:"First spelling of one public evidence identity."},{claim:"Canonical encoded path alias",source:"https://www.iana.org/%64omains/example",verification_method:"public_url",verification_reference:"https://www.iana.org/%64omains/example",verified_url:"https://www.iana.org/%64omains/example",verification_detail:"Percent-encoded path alias of the same public evidence identity."},{claim:"Canonical encoded path alias",source:"https://www.iana.org/d%6fmains/example",verification_method:"public_url",verification_reference:"https://www.iana.org/d%6fmains/example",verified_url:"https://www.iana.org/d%6fmains/example",verification_detail:"Percent-encoded path alias of the same public evidence identity."}]' ;;
        high_path_percent_encoded_public_url_aliases) mutation_filter='.findings[0].confidence = "high" | .findings[0].sources = ["https://www.iana.org/domains/example", "https://www.iana.org/%64omains/example", "https://www.iana.org/d%6fmains/example"] | .findings[0].source_provenance = [{source:"https://www.iana.org/domains/example",independence_key:"first",authority:"official"},{source:"https://www.iana.org/%64omains/example",independence_key:"second",authority:"primary"},{source:"https://www.iana.org/d%6fmains/example",independence_key:"third",authority:"secondary"}] | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Canonical public evidence",source:"https://www.iana.org/domains/example",verification_method:"public_url",verification_reference:"https://www.iana.org/domains/example",verified_url:"https://www.iana.org/domains/example",verification_detail:"First spelling."},{claim:"Canonical encoded path alias",source:"https://www.iana.org/%64omains/example",verification_method:"public_url",verification_reference:"https://www.iana.org/%64omains/example",verified_url:"https://www.iana.org/%64omains/example",verification_detail:"Percent-encoded path alias."},{claim:"Canonical encoded path alias",source:"https://www.iana.org/d%6fmains/example",verification_method:"public_url",verification_reference:"https://www.iana.org/d%6fmains/example",verified_url:"https://www.iana.org/d%6fmains/example",verification_detail:"Percent-encoded path alias."}]' ;;
        medium_fully_encoded_public_url_aliases) mutation_filter='.findings[0].confidence = "medium" | .findings[0].sources = ["https://www.iana.org/domains/example", "https%3A%2F%2Fwww.iana.org%2Fdomains%2Fexample"] | del(.findings[0].source_provenance) | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Canonical public evidence",source:"https://www.iana.org/domains/example",verification_method:"public_url",verification_reference:"https://www.iana.org/domains/example",verified_url:"https://www.iana.org/domains/example",verification_detail:"Canonical public evidence."}]' ;;
        high_fully_encoded_public_url_aliases) mutation_filter='.findings[0].confidence = "high" | .findings[0].sources = ["https://www.iana.org/domains/example", "https%3A%2F%2Fwww.iana.org%2Fdomains%2Fexample", "https://www.iana.org/help/example-domains"] | .findings[0].source_provenance = [{source:"https://www.iana.org/domains/example",independence_key:"first",authority:"official"},{source:"https%3A%2F%2Fwww.iana.org%2Fdomains%2Fexample",independence_key:"second",authority:"primary"},{source:"https://www.iana.org/help/example-domains",independence_key:"third",authority:"secondary"}] | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Canonical public evidence",source:"https://www.iana.org/domains/example",verification_method:"public_url",verification_reference:"https://www.iana.org/domains/example",verified_url:"https://www.iana.org/domains/example",verification_detail:"Canonical public evidence."},{claim:"Distinct public evidence",source:"https://www.iana.org/help/example-domains",verification_method:"public_url",verification_reference:"https://www.iana.org/help/example-domains",verified_url:"https://www.iana.org/help/example-domains",verification_detail:"Distinct public evidence."}]' ;;
        high_host_case_public_url_aliases) mutation_filter='.findings[0].confidence = "high" | .findings[0].sources = ["https://www.iana.org/domains/example", "https://WWW.IANA.ORG/domains/example", "https://www.%69ana.org/domains/example"] | .findings[0].source_provenance = [{source:"https://www.iana.org/domains/example",independence_key:"first",authority:"official"},{source:"https://WWW.IANA.ORG/domains/example",independence_key:"second",authority:"primary"},{source:"https://www.%69ana.org/domains/example",independence_key:"third",authority:"secondary"}] | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Canonical public evidence",source:"https://www.iana.org/domains/example",verification_method:"public_url",verification_reference:"https://www.iana.org/domains/example",verified_url:"https://www.iana.org/domains/example",verification_detail:"First spelling."},{claim:"Canonical public evidence alias",source:"https://WWW.IANA.ORG/domains/example",verification_method:"public_url",verification_reference:"https://WWW.IANA.ORG/domains/example",verified_url:"https://WWW.IANA.ORG/domains/example",verification_detail:"Host-case alias."},{claim:"Canonical encoded-host alias",source:"https://www.%69ana.org/domains/example",verification_method:"public_url",verification_reference:"https://www.%69ana.org/domains/example",verified_url:"https://www.%69ana.org/domains/example",verification_detail:"Encoded-host alias."}]' ;;
        malformed_candidate_mechanism) mutation_filter='.candidate_mechanisms = [{mechanism:"invest AI coding assistant .NET architecture malformed candidate",claim_status:"candidate",evidence:[{source:"source:research-corpus:summary",detail:"Candidate support.",evidence_status:"source_backed",unexpected:"field"}],confidence:"low",counterevidence_or_conflicts:["No counterevidence found."],gaps:["Independent validation pending."],validation_method:"Run an independent comparison."}]' ;;
        medium_single_secondary) mutation_filter='.findings[0].confidence = "medium"' ;;
        private_peer_evidence_url) mutation_filter='.peer_review.evidence[0].source = "https://metadata.local/private"' ;;
        unbound_final_finding_source) mutation_filter='.findings[0].sources = ["source:unbound-final-finding"]' ;;
        rebound_unsafe_packet_policies) mutation_filter='.five_lens_process_evidence.frozen_assignment_packets |= map(.source_policy = "public sources" | .isolation_policy = "sibling blind")' ;;
        source_backed_actual_sources_zero) mutation_filter='.five_lens_process_evidence.lens_dispatches[0].search_resource_usage.actual_sources = 0 | .five_lens_process_evidence.overall_resource_usage.actual_sources = 16' ;;
        local_repository_public_url) mutation_filter='.five_lens_process_evidence.peer_review_input_binding.verified_source_evidence[0].verification_reference = "https://www.iana.org/domains/example"' ;;
        authenticated_source_endpoint) mutation_filter='.five_lens_process_evidence.peer_review_input_binding.verified_source_evidence[0].verification_method = "authenticated_source" | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence[0].verification_reference = "connector:fixture/record:https://metadata.local/private"' ;;
        offline_citation_url) mutation_filter='.five_lens_process_evidence.peer_review_input_binding.verified_source_evidence[0].verification_method = "offline_authoritative_source" | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence[0].verification_reference = "citation:https://metadata.local/private"' ;;
        medium_single_public_row_aliases) mutation_filter='.findings[0].confidence = "medium" | .findings[0].sources = ["source:fixture-alias", "https://www.iana.org/domains/example"] | del(.findings[0].source_provenance) | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Alias evidence",source:"source:fixture-alias",verification_method:"public_url",verification_reference:"https://www.iana.org/domains/example",verified_url:"https://www.iana.org/domains/example",verification_detail:"Single public evidence row."}]' ;;
        malformed_peer_url_scheme) mutation_filter='.peer_review.evidence[0].source = "https:metadata.local/peer"' ;;
        malformed_peer_url_without_colon) mutation_filter='.peer_review.evidence[0].source = "https//metadata.local/peer"' ;;
        trailing_dot_peer_url) mutation_filter='.peer_review.evidence[0].source = "https://www.iana.org./peer"' ;;
        medium_host_case_public_url_aliases) mutation_filter='.findings[0].confidence = "medium" | .findings[0].sources = ["https://www.iana.org/domains/example", "https://WWW.IANA.ORG/domains/example", "https://www.%69ana.org/domains/example"] | del(.findings[0].source_provenance) | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Canonical public evidence",source:"https://www.iana.org/domains/example",verification_method:"public_url",verification_reference:"https://www.iana.org/domains/example",verified_url:"https://www.iana.org/domains/example",verification_detail:"First spelling of one public evidence identity."},{claim:"Canonical public evidence alias",source:"https://WWW.IANA.ORG/domains/example",verification_method:"public_url",verification_reference:"https://WWW.IANA.ORG/domains/example",verified_url:"https://WWW.IANA.ORG/domains/example",verification_detail:"Host-case alias of the same public evidence identity."},{claim:"Canonical encoded-host alias",source:"https://www.%69ana.org/domains/example",verification_method:"public_url",verification_reference:"https://www.%69ana.org/domains/example",verified_url:"https://www.%69ana.org/domains/example",verification_detail:"Percent-encoded-host alias of the same public evidence identity."}]' ;;
        protocol_relative_peer_url) mutation_filter='.peer_review.evidence[0].source = "//metadata.local/peer"' ;;
        discard_only_compressed_peer_url) mutation_filter='.peer_review.evidence[0].source = "https://[100::1]/peer"' ;;
        encoded_public_url_secret) mutation_filter='.peer_review.evidence[0].source = "https://www.iana.org/peer?%74oken=private"' ;;
        encoded_public_url_traversal) mutation_filter='.peer_review.evidence[0].source = "https://www.iana.org/a/%2e%2e/private"' ;;
        encoded_public_url_pii) mutation_filter='.peer_review.evidence[0].source = "https://www.iana.org/peer?contact=person%40sample.invalid"' ;;
        encoded_typed_url_secret) mutation_filter='.five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Typed URL safety evidence",source:"source:typed-url-safety",verification_method:"public_url",verification_reference:"https://www.iana.org/peer?%74oken=private",verified_url:"https://www.iana.org/peer?%74oken=private",verification_detail:"Typed public URL mutation."}]' ;;
        encoded_typed_url_traversal) mutation_filter='.five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Typed URL safety evidence",source:"source:typed-url-safety",verification_method:"public_url",verification_reference:"https://www.iana.org/a/%2e%2e/private",verified_url:"https://www.iana.org/a/%2e%2e/private",verification_detail:"Typed public URL mutation."}]' ;;
        encoded_typed_url_pii) mutation_filter='.five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Typed URL safety evidence",source:"source:typed-url-safety",verification_method:"public_url",verification_reference:"https://www.iana.org/peer?contact=person%40sample.invalid",verified_url:"https://www.iana.org/peer?contact=person%40sample.invalid",verification_detail:"Typed public URL mutation."}]' ;;
        encoded_opaque_source_traversal) mutation_filter='.peer_review.evidence[0].source = "source:a/%2e%2e/docs"' ;;
        encoded_opaque_source_secret) mutation_filter='.peer_review.evidence[0].source = "source:%74oken=redacted"' ;;
        encoded_opaque_source_pii) mutation_filter='.candidate_mechanisms = [{mechanism:"Candidate source safety mechanism",claim_status:"candidate",evidence:[{source:"source:%65mail=person%40sample.invalid",detail:"Candidate source mutation.",evidence_status:"source_backed"}],confidence:"low",counterevidence_or_conflicts:["No counterevidence recorded."],gaps:["Independent validation remains pending."],validation_method:"Compare independent evidence."}]' ;;
        opaque_source_credential) mutation_filter='.peer_review.evidence[0].source = "source:credential=opaque-value"' ;;
        fallback_wave_coverage_leakage) mutation_filter='.five_lens_process_evidence.wave_coverage = [{wave_id:"wave-1",capacity:5,lens_kinds:["practitioner","academic_or_technical_expert","skeptic","economist_or_incentives_analyst","historian_or_pattern_matcher"]}]' ;;
        peer_process_assignment_mismatch) mutation_filter='.five_lens_process_evidence.peer_review_assignment_id = "peer-assignment-other"' ;;
        finding_source_reserved_local) mutation_filter='.findings[0].sources = ["https://metadata.local/research"]' ;;
        finding_high_without_provenance) mutation_filter='.findings[0].confidence = "high" | del(.findings[0].source_provenance)' ;;
        finding_high_single_official) mutation_filter='.findings[0].confidence = "high" | .findings[0].sources = ["source:fixture-official"] | .findings[0].source_provenance = [{source:"source:fixture-official",independence_key:"fixture-official",authority:"official"}]' ;;
        finding_high_three_secondary) mutation_filter='.findings[0].confidence = "high" | .findings[0].sources = ["source:fixture-secondary-a","source:fixture-secondary-b","source:fixture-secondary-c"] | .findings[0].source_provenance = [{source:"source:fixture-secondary-a",independence_key:"fixture-a",authority:"secondary"},{source:"source:fixture-secondary-b",independence_key:"fixture-b",authority:"secondary"},{source:"source:fixture-secondary-c",independence_key:"fixture-c",authority:"secondary"}]' ;;
        conflict_source_private_loopback) mutation_filter='.conflicts = [{claim_a:"Fixture claim A",source_a:"https://127.0.0.1/private",claim_b:"Fixture claim B",source_b:"https://metadata.local/private",assessment:"The claims conflict."}]' ;;
        embedded_local_repository_traversal) mutation_filter='.five_lens_process_evidence.peer_review_input_binding.verified_source_evidence[0].verification_reference = "skills/assistant-research/../private-note"' ;;
        invalid_verified_evidence_shape) mutation_filter='.five_lens_process_evidence.peer_review_input_binding.verified_source_evidence += [{claim:"",source:"source:unsupported",verification_method:"unsupported_method",verification_reference:"records/unsupported",verification_detail:"Unsupported fixture evidence."}]' ;;
        windows_absolute_local_repository) mutation_filter='.five_lens_process_evidence.peer_review_input_binding.verified_source_evidence[0].verification_reference = "C:\\Users\\fixture\\private-note"' ;;
        whitespace_local_repository) mutation_filter='.five_lens_process_evidence.peer_review_input_binding.verified_source_evidence[0].verification_reference = "skills/assistant-research/contracts/output.yaml\nprivate-note"' ;;
        peer_binding_findings_drift) mutation_filter='.findings[0].finding = "Changed final finding after peer review"' ;;
        peer_binding_candidate_drift) mutation_filter='.candidate_mechanisms = [{mechanism:"Changed final candidate",claim_status:"candidate",evidence:[{source:"source:changed-candidate",detail:"Candidate-only support.",evidence_status:"source_backed"}],confidence:"low",counterevidence_or_conflicts:["No counterevidence found."],gaps:["Independent validation pending."],validation_method:"Run an independent comparison."}]' ;;
        peer_binding_conflicts_drift) mutation_filter='.conflicts = [{claim_a:"changed A",source_a:"source:changed-a",claim_b:"changed B",source_b:"source:changed-b",assessment:"changed"}]' ;;
        peer_binding_contradiction_drift) mutation_filter='.contradiction_map.strongest_evidence = "Changed final contradiction evidence"' ;;
        duplicate_perspective_lens) mutation_filter='.perspective_scan[4] = .perspective_scan[0]' ;;
        duplicate_question_trace_lens) mutation_filter='.question_trace[4] = .question_trace[0]' ;;
        common_packet_scope_drift) mutation_filter='.five_lens_process_evidence.frozen_assignment_packets[0].known_context += ["Drifted common scope"]' ;;
        semantic_context_scope_drift) mutation_filter='.five_lens_process_evidence.frozen_assignment_packets |= map(.question = "Should we adopt the tool?")' ;;
        follow_up_requirement_drift) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].follow_ups |= .[0:1]' ;;
        opt_out_allows_delegated_peer) mutation_filter='
            .five_lens_process_evidence.peer_review_execution_mode = "delegated"
            | .five_lens_process_evidence.subagent_policy_state = "delegation_opted_out"
            | .five_lens_process_evidence.lens_fallback_evidence = {basis:"explicit_opt_out",detail:"Process-wide user opt-out prohibits subagent delegation.",evidence_ref:"user-opt-out-1"}
            | del(.five_lens_process_evidence.peer_review_fallback_pass_id,.five_lens_process_evidence.peer_review_fallback_evidence)
            | .five_lens_process_evidence.peer_review_assignment_id = "peer-assignment-1"
            | .five_lens_process_evidence.peer_reviewer_identity = "peer-native-1"
            | .peer_review.peer_review_execution_mode = "delegated"
            | .peer_review.peer_review_assignment_id = "peer-assignment-1"
            | .peer_review.peer_reviewer_identity = "peer-native-1"
            | del(.peer_review.peer_review_fallback_pass_id)' ;;
        policy_block_allows_delegated_peer) mutation_filter='
            .five_lens_process_evidence.peer_review_execution_mode = "delegated"
            | .five_lens_process_evidence.subagent_policy_state = "policy_disallowed"
            | .five_lens_process_evidence.policy_blocking_source = "codex-rules/no-subagents"
            | .five_lens_process_evidence.lens_fallback_evidence = {basis:"exact_policy_block",detail:"Exact process-wide policy prohibits subagent delegation.",evidence_ref:"policy-record-1"}
            | del(.five_lens_process_evidence.peer_review_fallback_pass_id,.five_lens_process_evidence.peer_review_fallback_evidence)
            | .five_lens_process_evidence.peer_review_assignment_id = "peer-assignment-1"
            | .five_lens_process_evidence.peer_reviewer_identity = "peer-native-1"
            | .peer_review.peer_review_execution_mode = "delegated"
            | .peer_review.peer_review_assignment_id = "peer-assignment-1"
            | .peer_review.peer_reviewer_identity = "peer-native-1"
            | del(.peer_review.peer_review_fallback_pass_id)' ;;
        topic_substantive_fields_generic|topic_terms_only_assignment_id|topic_terms_only_unique_insight) mutation_filter='
            .five_lens_process_evidence.accepted_lens_results |= map(.core_position = "Generic position" | .lens_question = "Generic question" | .answer_or_gap = "Generic answer" | .likely_blind_spot = "Generic blind spot" | .unique_insight = "Generic insight")
            | .findings[0].finding = "Generic finding"
            | .synthesis_briefing.executive_summary = "Generic executive summary"
            | .synthesis_briefing.ranked_key_findings = ["Generic finding one","Generic finding two","Generic finding three"]
            | .synthesis_briefing.hidden_connection = "Generic hidden connection"
            | .synthesis_briefing.actionable_implication = "Generic action"
            | .synthesis_briefing.frontier_question = "Generic frontier question"
            | .contradiction_map.strongest_evidence = "Generic strongest evidence"
            | .contradiction_map.weakest_evidence = "Generic weakest evidence"
            | .contradiction_map.consensus = ["Generic consensus"]
            | .contradiction_map.biggest_unresolved_question = "Generic unresolved question"
            | .contradiction_map.missing_angle_or_gap = "Generic gap"
            | .summary = "Generic summary"' ;;
        hidden_finding_field) mutation_filter='.findings[0].unexpected = "hidden"' ;;
        delegated_policy_state_mismatch) mutation_filter='.five_lens_process_evidence.subagent_policy_state = "subagents_unavailable"' ;;
        stale_revision_metadata) mutation_filter='.five_lens_process_evidence.peer_review_revision_disposition_id = "stale-revision"' ;;
        invalid_peer_fallback_basis) mutation_filter='.five_lens_process_evidence.peer_review_fallback_evidence.basis = "unknown"' ;;
        missing_high_stakes_caveat) mutation_filter='del(.synthesis_briefing.high_stakes_caveat)' ;;
        malformed_findings) mutation_filter='.findings = {}' ;;
        malformed_conflicts) mutation_filter='.conflicts = {}' ;;
        malformed_perspective_scan) mutation_filter='.perspective_scan = {}' ;;
        malformed_question_trace) mutation_filter='.question_trace = {}' ;;
        malformed_peer_evidence) mutation_filter='.peer_review.evidence = {}' ;;
        malformed_revision_disposition) mutation_filter='.peer_review.revision_disposition = {}' ;;
        malformed_required_revisions) mutation_filter='.peer_review.required_revisions = {}' ;;
        follow_up_own_gap_drift) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].gaps = []' ;;
        retained_packet_preimage_drift) mutation_filter='.five_lens_process_evidence.frozen_assignment_packets[0].question = "Changed after freeze"' ;;
        peer_input_digest_drift) mutation_filter='.peer_review.peer_review_input_digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' ;;
        peer_input_synthesis_drift) mutation_filter='.five_lens_process_evidence.peer_review_input_binding.initial_synthesis.executive_summary = "Stale synthesis"' ;;
        peer_input_ledger_rebound_stale_peer_digest) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].core_position = "Rebound ledger result"' ;;
        accepted_final_synthesis_substitution) mutation_filter='.synthesis_briefing.executive_summary = "Post-review final synthesis substitution"' ;;
        peer_supported_recommendation_drift) mutation_filter='.peer_review.supported_recommendation = "do"' ;;
        fully_rebound_late_packet_freeze) mutation_filter='.five_lens_process_evidence.frozen_assignment_packets |= map(.packet_frozen_at = "2026-09-03T10:01:00Z")' ;;
        stronger_context_not_applicable) mutation_filter='.five_lens_process_evidence.peer_review_input_binding.high_stakes_context.user_context_status = "not_applicable" | .five_lens_process_evidence.peer_review_input_binding.high_stakes_context.user_context_basis = "not_applicable"' ;;
        stronger_context_unresolved) mutation_filter='.five_lens_process_evidence.peer_review_input_binding.high_stakes_context.user_context_status = "unresolved"' ;;
        malformed_null_follow_up) mutation_filter='.five_lens_process_evidence.accepted_lens_results[0].follow_ups = [null]' ;;
        lens_provenance_drift) mutation_filter='.five_lens_process_evidence.peer_review_input_binding.lens_execution_provenance.fallback_basis = "exact_policy_block"' ;;
        final_synthesis_digest_drift) mutation_filter='.five_lens_process_evidence.final_synthesis_digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' ;;
        revision_synthesis_digest_drift) mutation_filter='.peer_review.revision_disposition[0].resulting_synthesis_digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' ;;
        high_stakes_do_without_basis) mutation_filter='.synthesis_briefing.recommendation = "do" | .peer_review.supported_recommendation = "do"' ;;
        fully_rebound_response_only_high_stakes_context) mutation_filter='.' ;;
        missing_tier_normalization_disclosure) mutation_filter='.five_lens_process_evidence.tier_resolution.normalization_disclosure = "not_applicable"' ;;
        quick_effective_tier_drift) mutation_filter='.five_lens_process_evidence.tier_resolution.effective_tier = "extensive"' ;;
        *) return 2 ;;
    esac
    jq "$mutation_filter" "$response_path" >"$response_path.mutated" && mv "$response_path.mutated" "$response_path"
    case "$mutation" in
        topic_terms_only_assignment_id)
            jq '.five_lens_process_evidence.accepted_lens_results |= map(.assignment_id = "assignment-\(.lens_kind)-invest AI coding assistant .NET architecture")' "$response_path" >"$response_path.mutated" && mv "$response_path.mutated" "$response_path"
            ;;
        topic_terms_only_unique_insight)
            jq '.five_lens_process_evidence.accepted_lens_results[0].unique_insight = "invest AI coding assistant .NET architecture"' "$response_path" >"$response_path.mutated" && mv "$response_path.mutated" "$response_path"
            ;;
    esac
    if [[ "$mutation" == "hidden_packet_manifest_field" ]]; then
        manifest_digest="$(jq '.five_lens_process_evidence.frozen_packet_set.packet_manifest' "$response_path" | research_content_digest_json)"
        jq --arg digest "$manifest_digest" '.five_lens_process_evidence.frozen_packet_set.packet_set_digest = $digest' "$response_path" >"$response_path.mutated" \
            && mv "$response_path.mutated" "$response_path"
    fi
    case "$mutation" in
        source_invalid_domain|source_private_loopback|source_fully_encoded_private_loopback|source_backed_empty|synchronized_assignments|duplicate_none_needed|mixed_none_needed_follow_up|source_reserved_local|source_bare_hostname|source_ipv6_discard_only|source_ipv6_dummy_prefix_compressed|source_ipv6_dummy_prefix_full|finding_high_without_provenance|finding_high_single_official|finding_high_three_secondary|conflict_source_private_loopback|embedded_local_repository_traversal|invalid_verified_evidence_shape|windows_absolute_local_repository|whitespace_local_repository|common_packet_scope_drift|semantic_context_scope_drift|follow_up_requirement_drift|opt_out_allows_delegated_peer|policy_block_allows_delegated_peer|topic_substantive_fields_generic|topic_terms_only_assignment_id|topic_terms_only_unique_insight|malformed_candidate_mechanism|medium_single_secondary|unbound_final_finding_source|rebound_unsafe_packet_policies|local_repository_public_url|authenticated_source_endpoint|offline_citation_url|medium_single_public_row_aliases|medium_host_case_public_url_aliases|medium_path_percent_encoded_public_url_aliases|high_host_case_public_url_aliases|high_path_percent_encoded_public_url_aliases|medium_fully_encoded_public_url_aliases|high_fully_encoded_public_url_aliases|encoded_typed_url_secret|encoded_typed_url_traversal|encoded_typed_url_pii|encoded_opaque_source_traversal|encoded_opaque_source_secret|encoded_opaque_source_pii|opaque_source_credential) research_refresh_response_derivatives "$response_path" ;;
        peer_input_ledger_rebound_stale_peer_digest)
            stale_peer_input_digest="$(jq -r '.peer_review.peer_review_input_digest' "$response_path")"
            research_refresh_response_derivatives "$response_path"
            jq --arg digest "$stale_peer_input_digest" '.five_lens_process_evidence.peer_review_input_binding.peer_review_input_digest = $digest | .peer_review.peer_review_input_digest = $digest' "$response_path" >"$response_path.mutated" && mv "$response_path.mutated" "$response_path"
            ;;
        accepted_final_synthesis_substitution)
            final_synthesis_digest="$(jq '.synthesis_briefing' "$response_path" | research_content_digest_json)"
            jq --arg digest "$final_synthesis_digest" '.five_lens_process_evidence.final_synthesis_digest = $digest' "$response_path" >"$response_path.mutated" && mv "$response_path.mutated" "$response_path"
            ;;
        fully_rebound_late_packet_freeze)
            research_refresh_response_derivatives "$response_path"
            ;;
        stronger_context_not_applicable|stronger_context_unresolved|fully_rebound_response_only_high_stakes_context)
            research_refresh_response_derivatives "$response_path"
            research_set_high_stakes_recommendation_basis "$response_path"
            ;;
    esac

    if "$research_eval_runner" --responses "$eval_dir" --skill assistant-research --case "$case_id" >"$eval_output" 2>&1; then
        printf 'official runner accepted mutation: %s\n' "$mutation" >&2
        return 1
    fi
    if ! grep -Fq $'FAIL\tassistant-research\t'"$case_id" "$eval_output"; then
        printf 'official runner rejected mutation without its case failure record: %s\n' "$mutation" >&2
        return 1
    fi
    if [[ "$mutation" == malformed_* ]] && grep -Fq 'TypeError:' "$eval_output"; then
        printf 'official runner threw TypeError for malformed mutation: %s\n' "$mutation" >&2
        return 1
    fi
    case "$mutation" in
        finding_high_single_official|finding_high_three_secondary|invalid_verified_evidence_shape|windows_absolute_local_repository|whitespace_local_repository|peer_binding_findings_drift|peer_binding_candidate_drift|peer_binding_conflicts_drift|peer_binding_contradiction_drift|common_packet_scope_drift|topic_substantive_fields_generic|topic_terms_only_assignment_id|topic_terms_only_unique_insight|duplicate_perspective_lens|duplicate_question_trace_lens|opt_out_allows_delegated_peer|policy_block_allows_delegated_peer)
            if ! grep -Fq 'semantic_validation_failures=1' "$eval_output"; then
                printf 'official runner rejected mutation without semantic validation evidence: %s\n' "$mutation" >&2
                return 1
            fi
            ;;
    esac
}

research_mixed_peer_fallback_official_runner_is_accepted() {
    local case_id="five-lens-delegated-lenses-sequential-peer-fallback"
    local eval_dir eval_output response_path report

    eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-mixed-peer.XXXXXX")"
    eval_output="$(mktemp "${TMPDIR:-/tmp}/assistant-research-mixed-peer-output.XXXXXX")"
    p0p4_register_cleanup "$eval_dir" "$eval_output"
    write_research_eval_responses "$eval_dir"
    response_path="$eval_dir/assistant-research/$case_id.txt"
    report="$(jq -r --arg case_id "$case_id" '.cases[] | select(.id == $case_id) | .machine_expectations.required_substrings | join("\\n")' "$research_evals")"
    research_jcs_node build delegated_peer_fallback "$report" >"$response_path"
    "$research_eval_runner" --responses "$eval_dir" --skill assistant-research --case "$case_id" >"$eval_output" 2>&1
}

research_high_stakes_stronger_official_runner_is_accepted() {
    local case_id="five-lens-decision-briefing-uses-storm-style-workflow"
    local eval_dir eval_output response_path fixture_root fixture_skill fixture_path original_research_evals status explicit_context

    eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-high-stakes.XXXXXX")"
    eval_output="$(mktemp "${TMPDIR:-/tmp}/assistant-research-high-stakes-output.XXXXXX")"
    fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-high-stakes-fixture.XXXXXX")"
    fixture_skill="$fixture_root/assistant-research"
    fixture_path="$fixture_skill/evals/cases.json"
    p0p4_register_cleanup "$eval_dir" "$eval_output" "$fixture_root"
    mkdir -p "$fixture_skill/evals"
    cp "$research_skill" "$fixture_skill/SKILL.md"
    explicit_context='User supplied a capped reversible pilot with no trading authority.'
    jq --arg context "$explicit_context" '
      .cases[] |= if .id == "five-lens-decision-briefing-uses-storm-style-workflow" then
        .prompt += " " + $context
        | .semantic_context.high_stakes_context.user_context_status = "explicit"
        | .semantic_context.high_stakes_context.user_context_basis = $context
      else . end
    ' "$research_evals" >"$fixture_path"
    original_research_evals="$research_evals"
    research_evals="$fixture_path"
    write_research_eval_responses "$eval_dir"
    response_path="$eval_dir/assistant-research/$case_id.txt"
    research_prepare_high_stakes_stronger_response "$response_path"
    status=0
    "$research_eval_runner" --responses "$eval_dir" --skill "$fixture_skill" --case "$case_id" >"$eval_output" 2>&1 || status=$?
    research_evals="$original_research_evals"
    return "$status"
}

research_unsafe_high_stakes_decision_critical_url_is_rejected() {
    local case_id="five-lens-decision-briefing-uses-storm-style-workflow"
    local eval_dir eval_output response_path fixture_root fixture_skill fixture_path original_research_evals explicit_context private_status official_status

    eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-unsafe-high-stakes.XXXXXX")"
    eval_output="$(mktemp "${TMPDIR:-/tmp}/assistant-research-unsafe-high-stakes-output.XXXXXX")"
    fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-unsafe-high-stakes-fixture.XXXXXX")"
    fixture_skill="$fixture_root/assistant-research"
    fixture_path="$fixture_skill/evals/cases.json"
    p0p4_register_cleanup "$eval_dir" "$eval_output" "$fixture_root"
    mkdir -p "$fixture_skill/evals"
    cp "$research_skill" "$fixture_skill/SKILL.md"
    explicit_context='User supplied a capped reversible pilot with no trading authority.'
    jq --arg context "$explicit_context" '
      .cases[] |= if .id == "five-lens-decision-briefing-uses-storm-style-workflow" then
        .prompt += " " + $context
        | .semantic_context.high_stakes_context.user_context_status = "explicit"
        | .semantic_context.high_stakes_context.user_context_basis = $context
      else . end
    ' "$research_evals" >"$fixture_path"
    original_research_evals="$research_evals"
    research_evals="$fixture_path"
    write_research_eval_responses "$eval_dir"
    response_path="$eval_dir/assistant-research/$case_id.txt"
    research_prepare_high_stakes_stronger_response "$response_path"
    jq '
      .high_stakes_recommendation_basis.verified_decision_critical_urls = ["https://metadata.local/private"]
      | .high_stakes_recommendation_basis.peer_review_input_digest = .peer_review.peer_review_input_digest
    ' "$response_path" >"$response_path.mutated" && mv "$response_path.mutated" "$response_path"
    private_status=0
    research_response_oracle_is_valid "$response_path" "$case_id" >/dev/null 2>&1 || private_status=$?
    official_status=0
    "$research_eval_runner" --responses "$eval_dir" --skill "$fixture_skill" --case "$case_id" >"$eval_output" 2>&1 || official_status=$?
    research_evals="$original_research_evals"
    [[ "$private_status" -ne 0 && "$official_status" -ne 0 ]]
}

research_response_only_high_stakes_context_is_rejected() {
    local case_id="five-lens-decision-briefing-uses-storm-style-workflow"
    local eval_dir response_path

    eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-private-high-stakes.XXXXXX")"
    p0p4_register_cleanup "$eval_dir"
    write_research_eval_responses "$eval_dir"
    response_path="$eval_dir/assistant-research/$case_id.txt"
    research_prepare_high_stakes_stronger_response "$response_path"
    ! research_response_oracle_is_valid "$response_path" "$case_id"
}

research_fallback_revise_official_runner_is_accepted() {
    local case_id="five-lens-sequential-fallback-preserves-process-evidence"
    local eval_dir eval_output response_path report

    eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-fallback-revise.XXXXXX")"
    eval_output="$(mktemp "${TMPDIR:-/tmp}/assistant-research-fallback-revise-output.XXXXXX")"
    p0p4_register_cleanup "$eval_dir" "$eval_output"
    write_research_eval_responses "$eval_dir"
    response_path="$eval_dir/assistant-research/$case_id.txt"
    report="$(jq -r --arg case_id "$case_id" '.cases[] | select(.id == $case_id) | .machine_expectations.required_substrings | join("\\n")' "$research_evals")"
    research_jcs_node build sequential_fallback_revise "$report" >"$response_path"
    "$research_eval_runner" --responses "$eval_dir" --skill assistant-research --case "$case_id" >"$eval_output" 2>&1
}

research_typed_url_label_validators_match() {
    local expected="$1"
    local response_path="$2"
    local case_id="$3"
    local private_actual official_actual

    if research_response_oracle_is_valid "$response_path" "$case_id" >/dev/null 2>&1; then private_actual=accept; else private_actual=reject; fi
    if ( source "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-semantic-validators.sh"; assistant_research_five_lens_v3_valid "$response_path" "$research_evals" "$case_id" ) >/dev/null 2>&1; then official_actual=accept; else official_actual=reject; fi
    [[ "$private_actual" == "$expected" && "$official_actual" == "$expected" ]]
}

research_typed_url_label_source_resolution_controls() {
    local case_id="five-lens-decision-briefing-uses-storm-style-workflow"
    local control_dir response_path evidence expected control_name method reference verified_url source finding_source finding_verified_url
    local failures=()

    control_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-typed-label-resolution.XXXXXX")"
    p0p4_register_cleanup "$control_dir"
    while IFS='|' read -r expected control_name method reference verified_url source finding_source finding_verified_url; do
        response_path="$control_dir/$control_name.json"
        write_schema_valid_five_lens_eval_response delegated "$response_path"
        evidence="$(jq -cn --arg method "$method" --arg reference "$reference" --arg verified_url "$verified_url" --arg source "$source" '
            {claim:"Typed URL-label evidence.",source:$source,verification_method:$method,verification_reference:$reference,verification_detail:"Typed URL-label control."}
            + (if $method == "public_url" then {verified_url:$verified_url} else {} end)
        ')"
        jq --argjson evidence "$evidence" --arg source "$finding_source" --arg verified_url "$finding_verified_url" '
            .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [$evidence]
            | .findings[0].sources = [$source]
            | .findings[0].confidence = "low"
            | del(.findings[0].source_provenance)
            | if $verified_url == "-" then del(.findings[0].verified_urls) else .findings[0].verified_urls = [$verified_url] end
        ' "$response_path" >"$response_path.next" && mv "$response_path.next" "$response_path"
        research_refresh_response_derivatives "$response_path"
        research_typed_url_label_validators_match "$expected" "$response_path" "$case_id" || failures+=("$control_name")
    done <<'EOF'
accept|public-url-raw-label|public_url|https://www.iana.org/typed-public|https://www.iana.org/typed-public|https://WWW.IANA.ORG/%6ctyped-public-label|https://WWW.IANA.ORG/%6ctyped-public-label|-
accept|public-url-canonical-label|public_url|https://www.iana.org/typed-public|https://www.iana.org/typed-public|https://WWW.IANA.ORG/%6ctyped-public-label|https://www.iana.org/ltyped-public-label|-
accept|local-repository-raw-label|local_repository|skills/assistant-research/contracts/output.yaml|-|https://WWW.IANA.ORG/%6clocal-repository-label|https://WWW.IANA.ORG/%6clocal-repository-label|-
accept|local-repository-canonical-label|local_repository|skills/assistant-research/contracts/output.yaml|-|https://WWW.IANA.ORG/%6clocal-repository-label|https://www.iana.org/llocal-repository-label|-
accept|authenticated-source-raw-label|authenticated_source|connector:research/record:typed-label|-|https://WWW.IANA.ORG/%6cauthenticated-source-label|https://WWW.IANA.ORG/%6cauthenticated-source-label|-
accept|authenticated-source-canonical-label|authenticated_source|connector:research/record:typed-label|-|https://WWW.IANA.ORG/%6cauthenticated-source-label|https://www.iana.org/lauthenticated-source-label|-
accept|offline-authoritative-source-raw-label|offline_authoritative_source|doi:10.1000/typed-label|-|https://WWW.IANA.ORG/%6coffline-authoritative-source-label|https://WWW.IANA.ORG/%6coffline-authoritative-source-label|-
accept|offline-authoritative-source-canonical-label|offline_authoritative_source|doi:10.1000/typed-label|-|https://WWW.IANA.ORG/%6coffline-authoritative-source-label|https://www.iana.org/loffline-authoritative-source-label|-
reject|public-url-label-is-not-verified-url|public_url|https://www.iana.org/typed-public|https://www.iana.org/typed-public|https://WWW.IANA.ORG/%6ctyped-public-label|https://www.iana.org/ltyped-public-label|https://www.iana.org/ltyped-public-label
reject|wrong-method-label-is-not-verified-url|local_repository|skills/assistant-research/contracts/output.yaml|-|https://WWW.IANA.ORG/%6clocal-repository-label|https://www.iana.org/llocal-repository-label|https://www.iana.org/llocal-repository-label
reject|authenticated-source-label-is-not-verified-url|authenticated_source|connector:research/record:typed-label|-|https://WWW.IANA.ORG/%6cauthenticated-source-label|https://www.iana.org/lauthenticated-source-label|https://www.iana.org/lauthenticated-source-label
reject|offline-authoritative-source-label-is-not-verified-url|offline_authoritative_source|doi:10.1000/typed-label|-|https://WWW.IANA.ORG/%6coffline-authoritative-source-label|https://www.iana.org/loffline-authoritative-source-label|https://www.iana.org/loffline-authoritative-source-label
reject|unbound-opaque-finding-source|public_url|https://www.iana.org/typed-public|https://www.iana.org/typed-public|https://WWW.IANA.ORG/%6ctyped-public-label|source:unbound-final-finding|-
EOF
    if [[ "${#failures[@]}" -eq 0 ]]; then
        return 0
    fi
    printf 'typed URL-label source-resolution controls failed: %s\n' "${failures[*]}" >&2
    return 1
}

research_typed_url_label_identity_counting_controls() {
    local case_id="five-lens-decision-briefing-uses-storm-style-workflow"
    local control_dir response_path evidence expected control_name confidence sources
    local failures=()

    control_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-typed-label-counting.XXXXXX")"
    p0p4_register_cleanup "$control_dir"
    evidence='[{"claim":"Typed URL-label evidence.","source":"https://WWW.IANA.ORG/%6cabel","verification_method":"public_url","verification_reference":"https://www.iana.org/typed-public","verified_url":"https://www.iana.org/typed-public","verification_detail":"Typed URL-label control."}]'
    while IFS='|' read -r expected control_name confidence sources; do
        response_path="$control_dir/$control_name.json"
        write_schema_valid_five_lens_eval_response delegated "$response_path"
        jq --argjson evidence "$evidence" --arg confidence "$confidence" --argjson sources "$sources" '
            .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = $evidence
            | .candidate_mechanisms = [{
                mechanism:"Typed URL-label identity counting.",claim_status:"candidate",
                evidence:($sources | map({source:.,detail:"Typed URL-label evidence.",evidence_status:"source_backed"})),
                confidence:$confidence,counterevidence_or_conflicts:["No conflict recorded."],
                gaps:["Independent validation remains pending."],validation_method:"Compare independent evidence."
              }]
        ' "$response_path" >"$response_path.next" && mv "$response_path.next" "$response_path"
        research_refresh_response_derivatives "$response_path"
        research_typed_url_label_validators_match "$expected" "$response_path" "$case_id" || failures+=("$control_name")
    done <<'EOF'
reject|canonical-label-plus-verified-url-medium|medium|["https://www.iana.org/label","https://www.iana.org/typed-public"]
accept|canonical-label-plus-verified-url-low|low|["https://www.iana.org/label","https://www.iana.org/typed-public"]
reject|raw-and-canonical-label-medium|medium|["https://WWW.IANA.ORG/%6cabel","https://www.iana.org/label"]
accept|canonical-label-plus-independent-url-medium|medium|["https://www.iana.org/label","https://www.iana.org/independent"]
accept|reserved-delimiter-remains-distinct|medium|["https://WWW.IANA.ORG/label%2Fpart","https://www.iana.org/label/part"]
EOF
    while IFS='|' read -r expected control_name confidence sources collected_sources; do
        response_path="$control_dir/$control_name.json"
        write_schema_valid_five_lens_eval_response delegated "$response_path"
        jq --argjson evidence "$evidence" --arg confidence "$confidence" --argjson sources "$sources" --argjson collected_sources "$collected_sources" '
            .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = $evidence
            | .five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = $collected_sources
            | .findings[0].sources = $sources
            | .findings[0].confidence = $confidence
            | del(.findings[0].source_provenance, .findings[0].verified_urls)
        ' "$response_path" >"$response_path.next" && mv "$response_path.next" "$response_path"
        research_refresh_response_derivatives "$response_path"
        research_typed_url_label_validators_match "$expected" "$response_path" "$case_id" || failures+=("$control_name")
    done <<'EOF'
accept|canonical-label-finding-low|low|["https://www.iana.org/label"]|["source:research-corpus:typed-label-control"]
reject|canonical-label-and-verified-url-finding-medium|medium|["https://www.iana.org/label","https://www.iana.org/typed-public"]|["https://www.iana.org/label"]
accept|canonical-label-and-independent-finding-medium|medium|["https://www.iana.org/label","https://www.iana.org/independent"]|["https://www.iana.org/label","https://www.iana.org/independent"]
EOF
    if [[ "${#failures[@]}" -eq 0 ]]; then
        return 0
    fi
    printf 'typed URL-label identity-counting controls failed: %s\n' "${failures[*]}" >&2
    return 1
}

research_overlapping_evidence_alias_controls() {
    local case_id="five-lens-decision-briefing-uses-storm-style-workflow"
    local control_dir response_path expected control_name kind confidence evidence sources collected_sources private_actual official_actual
    local failures=()

    control_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-overlapping-aliases.XXXXXX")"
    p0p4_register_cleanup "$control_dir"
    while IFS='|' read -r expected control_name kind confidence evidence sources collected_sources; do
        response_path="$control_dir/$control_name.json"
        write_schema_valid_five_lens_eval_response delegated "$response_path"
        if [[ "$kind" == "candidate" ]]; then
            jq --argjson evidence "$evidence" --argjson sources "$sources" --arg confidence "$confidence" '
                .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = $evidence
                | .candidate_mechanisms = [{
                    mechanism:"Overlapping typed evidence aliases.",claim_status:"candidate",
                    evidence:($sources | map({source:.,detail:"Typed public evidence.",evidence_status:"source_backed"})),
                    confidence:$confidence,counterevidence_or_conflicts:["No conflict recorded."],
                    gaps:["Independent validation remains pending."],validation_method:"Compare independent evidence."
                  }]
            ' "$response_path" >"$response_path.next" && mv "$response_path.next" "$response_path"
        else
            jq --argjson evidence "$evidence" --argjson sources "$sources" --argjson collected_sources "$collected_sources" --arg confidence "$confidence" '
                .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = $evidence
                | .five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = $collected_sources
                | .findings[0].sources = $sources
                | .findings[0].confidence = $confidence
                | del(.findings[0].source_provenance, .findings[0].verified_urls)
            ' "$response_path" >"$response_path.next" && mv "$response_path.next" "$response_path"
        fi
        research_refresh_response_derivatives "$response_path"
        if research_response_oracle_is_valid "$response_path" "$case_id" >/dev/null 2>&1; then private_actual=accept; else private_actual=reject; fi
        if ( source "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-semantic-validators.sh"; assistant_research_five_lens_v3_valid "$response_path" "$research_evals" "$case_id" ) >/dev/null 2>&1; then official_actual=accept; else official_actual=reject; fi
        [[ "$private_actual" == "$expected" && "$official_actual" == "$expected" ]] || failures+=("$control_name:$private_actual/$official_actual")
    done <<'EOF'
reject|candidate-overlap-forward-medium|candidate|medium|[{"claim":"Alias A.","source":"source:alias-a","verification_method":"public_url","verification_reference":"https://www.iana.org/alias-b","verified_url":"https://www.iana.org/alias-b","verification_detail":"First alias."},{"claim":"Alias B.","source":"https://www.iana.org/alias-b","verification_method":"public_url","verification_reference":"https://www.iana.org/alias-c","verified_url":"https://www.iana.org/alias-c","verification_detail":"Second alias."}]|["source:alias-a","https://www.iana.org/alias-b"]|[]
reject|candidate-overlap-reversed-medium|candidate|medium|[{"claim":"Alias B.","source":"https://www.iana.org/alias-b","verification_method":"public_url","verification_reference":"https://www.iana.org/alias-c","verified_url":"https://www.iana.org/alias-c","verification_detail":"Second alias."},{"claim":"Alias A.","source":"source:alias-a","verification_method":"public_url","verification_reference":"https://www.iana.org/alias-b","verified_url":"https://www.iana.org/alias-b","verification_detail":"First alias."}]|["source:alias-a","https://www.iana.org/alias-b"]|[]
accept|candidate-overlap-low|candidate|low|[{"claim":"Alias A.","source":"source:alias-a","verification_method":"public_url","verification_reference":"https://www.iana.org/alias-b","verified_url":"https://www.iana.org/alias-b","verification_detail":"First alias."},{"claim":"Alias B.","source":"https://www.iana.org/alias-b","verification_method":"public_url","verification_reference":"https://www.iana.org/alias-c","verified_url":"https://www.iana.org/alias-c","verification_detail":"Second alias."}]|["source:alias-a","https://www.iana.org/alias-b"]|[]
reject|finding-overlap-forward-medium|finding|medium|[{"claim":"Alias A.","source":"source:alias-a","verification_method":"public_url","verification_reference":"https://www.iana.org/alias-b","verified_url":"https://www.iana.org/alias-b","verification_detail":"First alias."},{"claim":"Alias B.","source":"https://www.iana.org/alias-b","verification_method":"public_url","verification_reference":"https://www.iana.org/alias-c","verified_url":"https://www.iana.org/alias-c","verification_detail":"Second alias."}]|["source:alias-a","https://www.iana.org/alias-b"]|["source:alias-a","https://www.iana.org/alias-b"]
reject|finding-overlap-reversed-medium|finding|medium|[{"claim":"Alias B.","source":"https://www.iana.org/alias-b","verification_method":"public_url","verification_reference":"https://www.iana.org/alias-c","verified_url":"https://www.iana.org/alias-c","verification_detail":"Second alias."},{"claim":"Alias A.","source":"source:alias-a","verification_method":"public_url","verification_reference":"https://www.iana.org/alias-b","verified_url":"https://www.iana.org/alias-b","verification_detail":"First alias."}]|["source:alias-a","https://www.iana.org/alias-b"]|["source:alias-a","https://www.iana.org/alias-b"]
accept|finding-overlap-low|finding|low|[{"claim":"Alias A.","source":"source:alias-a","verification_method":"public_url","verification_reference":"https://www.iana.org/alias-b","verified_url":"https://www.iana.org/alias-b","verification_detail":"First alias."},{"claim":"Alias B.","source":"https://www.iana.org/alias-b","verification_method":"public_url","verification_reference":"https://www.iana.org/alias-c","verified_url":"https://www.iana.org/alias-c","verification_detail":"Second alias."}]|["source:alias-a","https://www.iana.org/alias-b"]|["source:alias-a","https://www.iana.org/alias-b"]
reject|candidate-transitive-bridge-last-medium|candidate|medium|[{"claim":"Alias A.","source":"source:alias-a","verification_method":"public_url","verification_reference":"https://www.iana.org/alias-b","verified_url":"https://www.iana.org/alias-b","verification_detail":"First alias."},{"claim":"Alias C.","source":"https://www.iana.org/alias-c","verification_method":"public_url","verification_reference":"https://www.iana.org/alias-d","verified_url":"https://www.iana.org/alias-d","verification_detail":"Third alias."},{"claim":"Bridge.","source":"https://www.iana.org/alias-b","verification_method":"public_url","verification_reference":"https://www.iana.org/alias-c","verified_url":"https://www.iana.org/alias-c","verification_detail":"Bridge alias."}]|["source:alias-a","https://www.iana.org/alias-c"]|[]
reject|candidate-transitive-permuted-medium|candidate|medium|[{"claim":"Bridge.","source":"https://www.iana.org/alias-b","verification_method":"public_url","verification_reference":"https://www.iana.org/alias-c","verified_url":"https://www.iana.org/alias-c","verification_detail":"Bridge alias."},{"claim":"Alias C.","source":"https://www.iana.org/alias-c","verification_method":"public_url","verification_reference":"https://www.iana.org/alias-d","verified_url":"https://www.iana.org/alias-d","verification_detail":"Third alias."},{"claim":"Alias A.","source":"source:alias-a","verification_method":"public_url","verification_reference":"https://www.iana.org/alias-b","verified_url":"https://www.iana.org/alias-b","verification_detail":"First alias."}]|["source:alias-a","https://www.iana.org/alias-c"]|[]
reject|candidate-duplicate-medium|candidate|medium|[{"claim":"Alias A.","source":"source:alias-a","verification_method":"public_url","verification_reference":"https://www.iana.org/alias-b","verified_url":"https://www.iana.org/alias-b","verification_detail":"First alias."},{"claim":"Alias A again.","source":"source:alias-a","verification_method":"public_url","verification_reference":"https://www.iana.org/alias-b","verified_url":"https://www.iana.org/alias-b","verification_detail":"Repeated alias."}]|["source:alias-a","https://www.iana.org/alias-b"]|[]
reject|candidate-cycle-medium|candidate|medium|[{"claim":"Cycle A.","source":"https://www.iana.org/cycle-a","verification_method":"public_url","verification_reference":"https://www.iana.org/cycle-b","verified_url":"https://www.iana.org/cycle-b","verification_detail":"First cycle alias."},{"claim":"Cycle B.","source":"https://www.iana.org/cycle-b","verification_method":"public_url","verification_reference":"https://www.iana.org/cycle-a","verified_url":"https://www.iana.org/cycle-a","verification_detail":"Second cycle alias."}]|["https://www.iana.org/cycle-a","https://www.iana.org/cycle-b"]|[]
accept|candidate-self-alias-low|candidate|low|[{"claim":"Self alias.","source":"https://www.iana.org/self-alias","verification_method":"public_url","verification_reference":"https://www.iana.org/self-alias","verified_url":"https://www.iana.org/self-alias","verification_detail":"Self alias."}]|["https://www.iana.org/self-alias"]|[]
accept|candidate-independent-medium|candidate|medium|[{"claim":"Independent one.","source":"source:independent-one","verification_method":"public_url","verification_reference":"https://www.iana.org/independent-one","verified_url":"https://www.iana.org/independent-one","verification_detail":"Independent evidence."},{"claim":"Independent two.","source":"source:independent-two","verification_method":"public_url","verification_reference":"https://www.iana.org/independent-two","verified_url":"https://www.iana.org/independent-two","verification_detail":"Independent evidence."}]|["source:independent-one","source:independent-two"]|[]
accept|finding-independent-medium|finding|medium|[{"claim":"Independent one.","source":"source:independent-one","verification_method":"public_url","verification_reference":"https://www.iana.org/independent-one","verified_url":"https://www.iana.org/independent-one","verification_detail":"Independent evidence."},{"claim":"Independent two.","source":"source:independent-two","verification_method":"public_url","verification_reference":"https://www.iana.org/independent-two","verified_url":"https://www.iana.org/independent-two","verification_detail":"Independent evidence."}]|["source:independent-one","source:independent-two"]|["source:independent-one","source:independent-two"]
accept|candidate-independent-high|candidate|high|[{"claim":"Independent one.","source":"source:independent-one","verification_method":"public_url","verification_reference":"https://www.iana.org/independent-one","verified_url":"https://www.iana.org/independent-one","verification_detail":"Independent evidence."},{"claim":"Independent two.","source":"source:independent-two","verification_method":"public_url","verification_reference":"https://www.iana.org/independent-two","verified_url":"https://www.iana.org/independent-two","verification_detail":"Independent evidence."},{"claim":"Independent three.","source":"source:independent-three","verification_method":"public_url","verification_reference":"https://www.iana.org/independent-three","verified_url":"https://www.iana.org/independent-three","verification_detail":"Independent evidence."}]|["source:independent-one","source:independent-two","source:independent-three"]|[]
reject|candidate-local-repository-shared-reference-medium|candidate|medium|[{"claim":"Local one.","source":"source:local-one","verification_method":"local_repository","verification_reference":"skills/assistant-research/contracts/output.yaml","verification_detail":"Local evidence."},{"claim":"Local two.","source":"source:local-two","verification_method":"local_repository","verification_reference":"skills/assistant-research/contracts/output.yaml","verification_detail":"Local evidence."}]|["source:local-one","source:local-two"]|[]
accept|candidate-local-repository-shared-reference-low|candidate|low|[{"claim":"Local one.","source":"source:local-one","verification_method":"local_repository","verification_reference":"skills/assistant-research/contracts/output.yaml","verification_detail":"Local evidence."},{"claim":"Local two.","source":"source:local-two","verification_method":"local_repository","verification_reference":"skills/assistant-research/contracts/output.yaml","verification_detail":"Local evidence."}]|["source:local-one","source:local-two"]|[]
accept|candidate-local-repository-distinct-reference-medium|candidate|medium|[{"claim":"Local one.","source":"source:local-one","verification_method":"local_repository","verification_reference":"skills/assistant-research/contracts/output.yaml","verification_detail":"Local evidence."},{"claim":"Local two.","source":"source:local-two","verification_method":"local_repository","verification_reference":"skills/assistant-research/contracts/handoffs.yaml","verification_detail":"Local evidence."}]|["source:local-one","source:local-two"]|[]
reject|finding-local-repository-shared-reference-medium|finding|medium|[{"claim":"Local one.","source":"source:local-one","verification_method":"local_repository","verification_reference":"skills/assistant-research/contracts/output.yaml","verification_detail":"Local evidence."},{"claim":"Local two.","source":"source:local-two","verification_method":"local_repository","verification_reference":"skills/assistant-research/contracts/output.yaml","verification_detail":"Local evidence."}]|["source:local-one","source:local-two"]|["source:local-one","source:local-two"]
accept|finding-local-repository-shared-reference-low|finding|low|[{"claim":"Local one.","source":"source:local-one","verification_method":"local_repository","verification_reference":"skills/assistant-research/contracts/output.yaml","verification_detail":"Local evidence."},{"claim":"Local two.","source":"source:local-two","verification_method":"local_repository","verification_reference":"skills/assistant-research/contracts/output.yaml","verification_detail":"Local evidence."}]|["source:local-one","source:local-two"]|["source:local-one","source:local-two"]
accept|finding-local-repository-distinct-reference-medium|finding|medium|[{"claim":"Local one.","source":"source:local-one","verification_method":"local_repository","verification_reference":"skills/assistant-research/contracts/output.yaml","verification_detail":"Local evidence."},{"claim":"Local two.","source":"source:local-two","verification_method":"local_repository","verification_reference":"skills/assistant-research/contracts/handoffs.yaml","verification_detail":"Local evidence."}]|["source:local-one","source:local-two"]|["source:local-one","source:local-two"]
reject|candidate-authenticated-source-shared-reference-medium|candidate|medium|[{"claim":"Authenticated one.","source":"source:authenticated-one","verification_method":"authenticated_source","verification_reference":"connector:research/record:shared","verification_detail":"Authenticated evidence."},{"claim":"Authenticated two.","source":"source:authenticated-two","verification_method":"authenticated_source","verification_reference":"connector:research/record:shared","verification_detail":"Authenticated evidence."}]|["source:authenticated-one","source:authenticated-two"]|[]
accept|candidate-authenticated-source-shared-reference-low|candidate|low|[{"claim":"Authenticated one.","source":"source:authenticated-one","verification_method":"authenticated_source","verification_reference":"connector:research/record:shared","verification_detail":"Authenticated evidence."},{"claim":"Authenticated two.","source":"source:authenticated-two","verification_method":"authenticated_source","verification_reference":"connector:research/record:shared","verification_detail":"Authenticated evidence."}]|["source:authenticated-one","source:authenticated-two"]|[]
accept|candidate-authenticated-source-distinct-reference-medium|candidate|medium|[{"claim":"Authenticated one.","source":"source:authenticated-one","verification_method":"authenticated_source","verification_reference":"connector:research/record:one","verification_detail":"Authenticated evidence."},{"claim":"Authenticated two.","source":"source:authenticated-two","verification_method":"authenticated_source","verification_reference":"connector:research/record:two","verification_detail":"Authenticated evidence."}]|["source:authenticated-one","source:authenticated-two"]|[]
reject|finding-authenticated-source-shared-reference-medium|finding|medium|[{"claim":"Authenticated one.","source":"source:authenticated-one","verification_method":"authenticated_source","verification_reference":"connector:research/record:shared","verification_detail":"Authenticated evidence."},{"claim":"Authenticated two.","source":"source:authenticated-two","verification_method":"authenticated_source","verification_reference":"connector:research/record:shared","verification_detail":"Authenticated evidence."}]|["source:authenticated-one","source:authenticated-two"]|["source:authenticated-one","source:authenticated-two"]
accept|finding-authenticated-source-shared-reference-low|finding|low|[{"claim":"Authenticated one.","source":"source:authenticated-one","verification_method":"authenticated_source","verification_reference":"connector:research/record:shared","verification_detail":"Authenticated evidence."},{"claim":"Authenticated two.","source":"source:authenticated-two","verification_method":"authenticated_source","verification_reference":"connector:research/record:shared","verification_detail":"Authenticated evidence."}]|["source:authenticated-one","source:authenticated-two"]|["source:authenticated-one","source:authenticated-two"]
accept|finding-authenticated-source-distinct-reference-medium|finding|medium|[{"claim":"Authenticated one.","source":"source:authenticated-one","verification_method":"authenticated_source","verification_reference":"connector:research/record:one","verification_detail":"Authenticated evidence."},{"claim":"Authenticated two.","source":"source:authenticated-two","verification_method":"authenticated_source","verification_reference":"connector:research/record:two","verification_detail":"Authenticated evidence."}]|["source:authenticated-one","source:authenticated-two"]|["source:authenticated-one","source:authenticated-two"]
reject|candidate-offline-authoritative-source-shared-reference-medium|candidate|medium|[{"claim":"Offline one.","source":"source:offline-one","verification_method":"offline_authoritative_source","verification_reference":"doi:10.1000/shared","verification_detail":"Offline evidence."},{"claim":"Offline two.","source":"source:offline-two","verification_method":"offline_authoritative_source","verification_reference":"doi:10.1000/shared","verification_detail":"Offline evidence."}]|["source:offline-one","source:offline-two"]|[]
accept|candidate-offline-authoritative-source-shared-reference-low|candidate|low|[{"claim":"Offline one.","source":"source:offline-one","verification_method":"offline_authoritative_source","verification_reference":"doi:10.1000/shared","verification_detail":"Offline evidence."},{"claim":"Offline two.","source":"source:offline-two","verification_method":"offline_authoritative_source","verification_reference":"doi:10.1000/shared","verification_detail":"Offline evidence."}]|["source:offline-one","source:offline-two"]|[]
accept|candidate-offline-authoritative-source-distinct-reference-medium|candidate|medium|[{"claim":"Offline one.","source":"source:offline-one","verification_method":"offline_authoritative_source","verification_reference":"doi:10.1000/one","verification_detail":"Offline evidence."},{"claim":"Offline two.","source":"source:offline-two","verification_method":"offline_authoritative_source","verification_reference":"doi:10.1000/two","verification_detail":"Offline evidence."}]|["source:offline-one","source:offline-two"]|[]
reject|finding-offline-authoritative-source-shared-reference-medium|finding|medium|[{"claim":"Offline one.","source":"source:offline-one","verification_method":"offline_authoritative_source","verification_reference":"doi:10.1000/shared","verification_detail":"Offline evidence."},{"claim":"Offline two.","source":"source:offline-two","verification_method":"offline_authoritative_source","verification_reference":"doi:10.1000/shared","verification_detail":"Offline evidence."}]|["source:offline-one","source:offline-two"]|["source:offline-one","source:offline-two"]
accept|finding-offline-authoritative-source-shared-reference-low|finding|low|[{"claim":"Offline one.","source":"source:offline-one","verification_method":"offline_authoritative_source","verification_reference":"doi:10.1000/shared","verification_detail":"Offline evidence."},{"claim":"Offline two.","source":"source:offline-two","verification_method":"offline_authoritative_source","verification_reference":"doi:10.1000/shared","verification_detail":"Offline evidence."}]|["source:offline-one","source:offline-two"]|["source:offline-one","source:offline-two"]
accept|finding-offline-authoritative-source-distinct-reference-medium|finding|medium|[{"claim":"Offline one.","source":"source:offline-one","verification_method":"offline_authoritative_source","verification_reference":"doi:10.1000/one","verification_detail":"Offline evidence."},{"claim":"Offline two.","source":"source:offline-two","verification_method":"offline_authoritative_source","verification_reference":"doi:10.1000/two","verification_detail":"Offline evidence."}]|["source:offline-one","source:offline-two"]|["source:offline-one","source:offline-two"]
EOF
    if [[ "${#failures[@]}" -eq 0 ]]; then
        return 0
    fi
    printf 'overlapping evidence alias controls failed: %s\n' "${failures[*]}" >&2
    return 1
}

research_optional_verified_urls_controls() {
    node "$FRAMEWORK_DIR/tests/p0-p4/lib/assistant-research-semantic-controls.cjs" --optional-urls "$FRAMEWORK_DIR" "$research_evals"
}

research_completion_validator_controls() {
    node "$FRAMEWORK_DIR/tests/p0-p4/lib/assistant-research-semantic-controls.cjs" --completion "$FRAMEWORK_DIR" "$research_evals" "$1"
}

research_fixture_capacity_controls() {
    local control_dir expected name capacity fixture_path actual output expected_error
    local failures=()
    control_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-fixture-capacity.XXXXXX")"
    p0p4_register_cleanup "$control_dir"
    mkdir -p "$control_dir/evals"
    ln -s "$FRAMEWORK_DIR/skills/assistant-research/contracts" "$control_dir/contracts"
    while IFS='|' read -r expected name capacity; do
        fixture_path="$control_dir/evals/$name.json"
        jq --argjson capacity "$capacity" '(.cases[] | select(.semantic_context) | .semantic_context.adapter_context.max_concurrent_lens_workers) = $capacity' "$research_evals" >"$fixture_path"
        if output="$(source "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-common.sh"; source "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-fixtures.sh"; REPO_ROOT="$FRAMEWORK_DIR"; validate_fixture "$fixture_path" assistant-research 2>&1)"; then actual=accept; else actual=reject; fi
        printf 'fixture capacity %s: expected=%s actual=%s\n%s\n' "$name" "$expected" "$actual" "$output"
        [[ "$actual" == "$expected" ]] || failures+=("$name:$actual")
        expected_error="$(jq -r '.cases | to_entries[] | select(.value.semantic_context) | "case[\(.key)].semantic_context.adapter_context must contain a positive integer max_concurrent_lens_workers"' "$fixture_path")"
        if [[ "$actual" == reject && "$output" != "$fixture_path: $expected_error" ]]; then failures+=("$name:wrong-reason"); fi
    done <<'EOF'
accept|one|1
accept|two|2
accept|max-safe|9007199254740991
reject|fraction-one-half|1.5
reject|fraction-half|0.5
reject|string|"2"
reject|zero|0
reject|overflow|9007199254740992
EOF
    research_completion_validator_controls capacity || failures+=("semantic-consumer-compatibility")
    [[ "${#failures[@]}" -eq 0 ]] && return 0
    printf 'fixture capacity controls failed: %s\n' "${failures[*]}" >&2
    return 1
}

research_empty_findings_producer_controls() {
    local validators_status=0 producer_status=0
    research_completion_validator_controls findings || validators_status=$?
    ruby -ryaml - "$five_lens_reference" "$research_phase_gates" "$research_output" <<'RUBY' || producer_status=$?
guide = File.read(ARGV[0])
template = guide.split("\nFINDINGS\n", 2).fetch(1).split("\nCONFLICTS\n", 2).first
gate = YAML.load_file(ARGV[1]).fetch("gates").flat_map { |g| g.fetch("exit_assertions", []) }.find { |g| g["id"] == "SY5" }.fetch("check")
consumer = YAML.load_file(ARGV[2]).fetch("artifacts").find { |a| a["name"] == "findings" }.fetch("validation")
failures = []
{"FINDINGS template" => template, "SY5 gate" => gate, "output findings consumer" => consumer}.each do |name, text|
  failures << name unless text.match?(/every accepted main result and material follow-up/) && text.include?("source-empty") && text.include?("top-level gaps")
end
failures << "guide must remain below the 5000-word load budget" if guide.split.size >= 5000
puts "empty-findings producer alignment: #{failures.empty? ? 'PASS' : failures.join(', ')}"
exit(failures.empty? ? 0 : 1)
RUBY
    [[ "$validators_status" -eq 0 && "$producer_status" -eq 0 ]]
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
    fail "assistant-research eval branches are mixed or do not reject mixed delegated/fallback evidence: ${branch_eval_missing[*]-}"
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
    if ! grep -Fq -- "$term" <<<"$output_peer_schema"$'\n'"$process_evidence_schema"; then
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
if ! grep -Fq -- 'When research_method=five_lens_briefing, every finding source resolves' "$research_output"; then
    structured_oracle_missing+=("five-lens finding lineage must not constrain direct source_research")
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
    && research_structured_mutation_is_rejected source_fully_encoded_private_loopback \
    && research_structured_mutation_is_rejected source_backed_empty \
    && research_structured_mutation_is_rejected malformed_candidate_mechanism \
    && research_structured_mutation_is_rejected medium_single_secondary \
    && research_structured_mutation_is_rejected private_peer_evidence_url \
    && research_structured_mutation_is_rejected unbound_final_finding_source \
    && research_structured_mutation_is_rejected rebound_unsafe_packet_policies \
    && research_structured_mutation_is_rejected source_backed_actual_sources_zero \
    && research_structured_mutation_is_rejected local_repository_public_url \
    && research_structured_mutation_is_rejected authenticated_source_endpoint \
    && research_structured_mutation_is_rejected offline_citation_url \
    && research_structured_mutation_is_rejected medium_single_public_row_aliases \
    && research_structured_mutation_is_rejected malformed_peer_url_scheme \
    && research_structured_mutation_is_rejected malformed_peer_url_without_colon \
    && research_structured_mutation_is_rejected trailing_dot_peer_url \
    && research_structured_mutation_is_rejected protocol_relative_peer_url \
    && research_structured_mutation_is_rejected discard_only_compressed_peer_url \
    && research_structured_mutation_is_rejected medium_host_case_public_url_aliases \
    && research_structured_mutation_is_rejected medium_path_percent_encoded_public_url_aliases \
    && research_structured_mutation_is_rejected medium_fully_encoded_public_url_aliases \
    && research_structured_mutation_is_rejected encoded_public_url_secret \
    && research_structured_mutation_is_rejected encoded_public_url_traversal \
    && research_structured_mutation_is_rejected encoded_public_url_pii \
    && research_structured_mutation_is_rejected encoded_typed_url_secret \
    && research_structured_mutation_is_rejected encoded_typed_url_traversal \
    && research_structured_mutation_is_rejected encoded_typed_url_pii \
    && research_structured_mutation_is_rejected encoded_opaque_source_traversal \
    && research_structured_mutation_is_rejected encoded_opaque_source_secret \
    && research_structured_mutation_is_rejected encoded_opaque_source_pii \
    && research_structured_mutation_is_rejected opaque_source_credential \
    && research_structured_mutation_is_rejected high_host_case_public_url_aliases \
    && research_structured_mutation_is_rejected high_path_percent_encoded_public_url_aliases \
    && research_structured_mutation_is_rejected high_fully_encoded_public_url_aliases \
    && research_structured_mutation_is_rejected synchronized_assignments \
    && research_structured_mutation_is_rejected missing_delegated_trigger_scope \
    && research_structured_mutation_is_rejected lens_worker_synthesis \
    && research_structured_mutation_is_rejected missing_findings \
    && research_structured_mutation_is_rejected missing_conflicts \
    && research_structured_mutation_is_rejected missing_gaps \
    && research_structured_mutation_is_rejected missing_summary \
    && research_structured_mutation_is_rejected missing_contradiction_map \
    && research_structured_mutation_is_rejected missing_synthesis_briefing \
    && research_structured_mutation_is_rejected duplicate_none_needed \
    && research_structured_mutation_is_rejected mixed_none_needed_follow_up \
    && research_structured_mutation_is_rejected source_reserved_local \
    && research_structured_mutation_is_rejected source_bare_hostname; then
    pass
else
    fail "assistant-research delegated structured eval oracle is incomplete or accepts a process-evidence mutation: ${structured_oracle_missing[*]-}"
fi

test_start "assistant-research eval structurally validates sequential fallback without native leakage"
if research_fallback_structured_mutation_is_rejected false_return_validated \
    && research_fallback_structured_mutation_is_rejected packet_binding_mismatch \
    && research_fallback_structured_mutation_is_rejected fallback_dispatch_identity_leakage \
    && research_fallback_structured_mutation_is_rejected peer_fallback_and_evidence_mismatch \
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
    && research_fallback_structured_mutation_is_rejected missing_lens_fallback_evidence_ref \
    && research_fallback_structured_mutation_is_rejected fallback_wave_coverage_leakage; then
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
    && research_official_response_mutation_is_rejected source_fully_encoded_private_loopback \
    && research_official_response_mutation_is_rejected source_backed_empty \
    && research_official_response_mutation_is_rejected malformed_candidate_mechanism \
    && research_official_response_mutation_is_rejected medium_single_secondary \
    && research_official_response_mutation_is_rejected private_peer_evidence_url \
    && research_official_response_mutation_is_rejected unbound_final_finding_source \
    && research_official_response_mutation_is_rejected rebound_unsafe_packet_policies \
    && research_official_response_mutation_is_rejected source_backed_actual_sources_zero \
    && research_official_response_mutation_is_rejected local_repository_public_url \
    && research_official_response_mutation_is_rejected authenticated_source_endpoint \
    && research_official_response_mutation_is_rejected offline_citation_url \
    && research_official_response_mutation_is_rejected medium_single_public_row_aliases \
    && research_official_response_mutation_is_rejected malformed_peer_url_scheme \
    && research_official_response_mutation_is_rejected malformed_peer_url_without_colon \
    && research_official_response_mutation_is_rejected trailing_dot_peer_url \
    && research_official_response_mutation_is_rejected protocol_relative_peer_url \
    && research_official_response_mutation_is_rejected discard_only_compressed_peer_url \
    && research_official_response_mutation_is_rejected medium_host_case_public_url_aliases \
    && research_official_response_mutation_is_rejected medium_path_percent_encoded_public_url_aliases \
    && research_official_response_mutation_is_rejected medium_fully_encoded_public_url_aliases \
    && research_official_response_mutation_is_rejected encoded_public_url_secret \
    && research_official_response_mutation_is_rejected encoded_public_url_traversal \
    && research_official_response_mutation_is_rejected encoded_public_url_pii \
    && research_official_response_mutation_is_rejected encoded_typed_url_secret \
    && research_official_response_mutation_is_rejected encoded_typed_url_traversal \
    && research_official_response_mutation_is_rejected encoded_typed_url_pii \
    && research_official_response_mutation_is_rejected encoded_opaque_source_traversal \
    && research_official_response_mutation_is_rejected encoded_opaque_source_secret \
    && research_official_response_mutation_is_rejected encoded_opaque_source_pii \
    && research_official_response_mutation_is_rejected opaque_source_credential \
    && research_official_response_mutation_is_rejected high_host_case_public_url_aliases \
    && research_official_response_mutation_is_rejected high_path_percent_encoded_public_url_aliases \
    && research_official_response_mutation_is_rejected high_fully_encoded_public_url_aliases \
    && research_official_response_mutation_is_rejected fallback_wave_coverage_leakage \
    && research_official_response_mutation_is_rejected synchronized_assignments \
    && research_official_response_mutation_is_rejected missing_delegated_trigger_scope \
    && research_official_response_mutation_is_rejected lens_worker_synthesis \
    && research_official_response_mutation_is_rejected missing_lens_fallback_evidence_ref \
    && research_official_response_mutation_is_rejected missing_findings \
    && research_official_response_mutation_is_rejected missing_conflicts \
    && research_official_response_mutation_is_rejected missing_gaps \
    && research_official_response_mutation_is_rejected missing_summary \
    && research_official_response_mutation_is_rejected missing_contradiction_map \
    && research_official_response_mutation_is_rejected missing_synthesis_briefing \
    && research_official_response_mutation_is_rejected unusable_peer_needs_context \
    && research_official_response_mutation_is_rejected unusable_peer_blocked \
    && research_official_response_mutation_is_rejected duplicate_none_needed \
    && research_official_response_mutation_is_rejected mixed_none_needed_follow_up \
    && research_official_response_mutation_is_rejected source_reserved_local \
    && research_official_response_mutation_is_rejected source_bare_hostname \
    && research_official_response_mutation_is_rejected source_ipv6_discard_only \
    && research_official_response_mutation_is_rejected source_ipv6_dummy_prefix_compressed \
    && research_official_response_mutation_is_rejected source_ipv6_dummy_prefix_full \
    && research_official_response_mutation_is_rejected peer_process_assignment_mismatch \
    && research_official_response_mutation_is_rejected finding_source_reserved_local \
    && research_official_response_mutation_is_rejected finding_high_without_provenance \
    && research_official_response_mutation_is_rejected finding_high_single_official \
    && research_official_response_mutation_is_rejected finding_high_three_secondary \
    && research_official_response_mutation_is_rejected conflict_source_private_loopback \
    && research_official_response_mutation_is_rejected embedded_local_repository_traversal \
    && research_official_response_mutation_is_rejected invalid_verified_evidence_shape \
    && research_official_response_mutation_is_rejected windows_absolute_local_repository \
    && research_official_response_mutation_is_rejected whitespace_local_repository \
    && research_official_response_mutation_is_rejected peer_binding_findings_drift \
    && research_official_response_mutation_is_rejected peer_binding_candidate_drift \
    && research_official_response_mutation_is_rejected peer_binding_conflicts_drift \
    && research_official_response_mutation_is_rejected peer_binding_contradiction_drift \
    && research_official_response_mutation_is_rejected duplicate_perspective_lens \
    && research_official_response_mutation_is_rejected duplicate_question_trace_lens \
    && research_official_response_mutation_is_rejected common_packet_scope_drift \
    && research_official_response_mutation_is_rejected semantic_context_scope_drift \
    && research_official_response_mutation_is_rejected follow_up_requirement_drift \
    && research_official_response_mutation_is_rejected opt_out_allows_delegated_peer \
    && research_official_response_mutation_is_rejected policy_block_allows_delegated_peer \
    && research_official_response_mutation_is_rejected topic_substantive_fields_generic \
    && research_official_response_mutation_is_rejected topic_terms_only_assignment_id \
    && research_official_response_mutation_is_rejected topic_terms_only_unique_insight \
    && research_official_response_mutation_is_rejected hidden_finding_field \
    && research_official_response_mutation_is_rejected delegated_policy_state_mismatch \
    && research_official_response_mutation_is_rejected stale_revision_metadata \
    && research_official_response_mutation_is_rejected invalid_peer_fallback_basis \
    && research_official_response_mutation_is_rejected missing_high_stakes_caveat \
    && research_official_response_mutation_is_rejected malformed_findings \
    && research_official_response_mutation_is_rejected malformed_conflicts \
    && research_official_response_mutation_is_rejected malformed_perspective_scan \
    && research_official_response_mutation_is_rejected malformed_question_trace \
    && research_official_response_mutation_is_rejected malformed_peer_evidence \
    && research_official_response_mutation_is_rejected malformed_revision_disposition \
    && research_official_response_mutation_is_rejected malformed_required_revisions \
    && research_official_response_mutation_is_rejected follow_up_own_gap_drift \
    && research_official_response_mutation_is_rejected retained_packet_preimage_drift \
    && research_official_response_mutation_is_rejected peer_input_digest_drift \
    && research_official_response_mutation_is_rejected peer_input_synthesis_drift \
    && research_official_response_mutation_is_rejected peer_input_ledger_rebound_stale_peer_digest \
    && research_official_response_mutation_is_rejected accepted_final_synthesis_substitution \
    && research_official_response_mutation_is_rejected peer_supported_recommendation_drift \
    && research_official_response_mutation_is_rejected fully_rebound_late_packet_freeze \
    && research_official_response_mutation_is_rejected stronger_context_not_applicable \
    && research_official_response_mutation_is_rejected stronger_context_unresolved \
    && research_official_response_mutation_is_rejected malformed_null_follow_up \
    && research_official_response_mutation_is_rejected lens_provenance_drift \
    && research_official_response_mutation_is_rejected final_synthesis_digest_drift \
    && research_official_response_mutation_is_rejected revision_synthesis_digest_drift \
    && research_official_response_mutation_is_rejected high_stakes_do_without_basis \
    && research_official_response_mutation_is_rejected fully_rebound_response_only_high_stakes_context \
    && research_official_response_mutation_is_rejected missing_tier_normalization_disclosure \
    && research_official_response_mutation_is_rejected quick_effective_tier_drift \
    && research_response_only_high_stakes_context_is_rejected \
    && research_high_stakes_stronger_official_runner_is_accepted \
    && research_unsafe_high_stakes_decision_critical_url_is_rejected \
    && research_fallback_revise_official_runner_is_accepted \
    && research_mixed_peer_fallback_official_runner_is_accepted; then
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
jq 'del(.cases[] | select(.id == "five-lens-quick-normalizes-to-standard") | .semantic_validator)' \
    "$semantic_fixture" >"$semantic_fixture.next" && mv "$semantic_fixture.next" "$semantic_fixture"
partial_semantic_validator_declaration_rejected=false
if ! "$research_eval_runner" --validate-fixture --skill "$semantic_fixture_root/assistant-research" >"$semantic_fixture_output" 2>&1 \
    && grep -Fq -- 'semantic_validator must be declared by exactly the five five-lens assistant-research cases' "$semantic_fixture_output"; then
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
    && printf '%s\n' '{"verification_method":"offline_authoritative_source","verification_reference":"doi:10.1000/typed-fixture"}' \
        | research_verified_source_evidence_is_valid \
    && printf '%s\n' '{"verification_method":"offline_authoritative_source","verification_reference":"isbn:978-0-00-000000-0"}' \
        | research_verified_source_evidence_is_valid \
    && printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://192.0.1.1/source","verified_url":"https://192.0.1.1/source"}' \
        | research_verified_source_evidence_is_valid \
    && printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://198.51.101.1/source","verified_url":"https://198.51.101.1/source"}' \
        | research_verified_source_evidence_is_valid \
    && printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://203.0.114.1/source","verified_url":"https://203.0.114.1/source"}' \
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
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://www.iana.org./source","verified_url":"https://www.iana.org./source"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://[100::1]/source","verified_url":"https://[100::1]/source"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://%31%32%37.0.0.1/source","verified_url":"https://%31%32%37.0.0.1/source"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://www.iana.org/peer?%74oken=private","verified_url":"https://www.iana.org/peer?%74oken=private"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://www.iana.org/a/%2e%2e/private","verified_url":"https://www.iana.org/a/%2e%2e/private"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://www.iana.org/peer?contact=person%40sample.invalid","verified_url":"https://www.iana.org/peer?contact=person%40sample.invalid"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"public_url","verification_reference":"https://www.iana.org/peer?token=%zz","verified_url":"https://www.iana.org/peer?token=%zz"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"local_repository","verification_reference":"../secrets#record"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"local_repository","verification_reference":"skills/assistant-research/../private-note"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"local_repository","verification_reference":"/Users/name/repo#record"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"local_repository","verification_reference":"C:\\Users\\fixture\\private-note"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"local_repository","verification_reference":"skills/assistant-research/contracts/output.yaml\nprivate-note"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"local_repository","verification_reference":"https://www.iana.org/domains/example"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"local_repository","verification_reference":"https//metadata.local/private"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"local_repository","verification_reference":"//metadata.local/private"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"authenticated_source","verification_reference":"connector:private/record:person@example.com"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"authenticated_source","verification_reference":"connector:fixture/record:https://metadata.local/private"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"authenticated_source","verification_reference":"https://user:token@connector.invalid/record:source-1"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"authenticated_source","verification_reference":"connector:private.internal/record:token-placeholder"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"offline_authoritative_source","verification_reference":"citation:123-45-6789"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"offline_authoritative_source","verification_reference":"citation:555-123-4567"}' | research_verified_source_evidence_is_valid \
    && ! printf '%s\n' '{"verification_method":"offline_authoritative_source","verification_reference":"citation:https://metadata.local/private"}' | research_verified_source_evidence_is_valid \
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
investment_semantic_context="$(jq -c '.cases[] | select(.id == "five-lens-decision-briefing-uses-storm-style-workflow") | .semantic_context' "$research_evals")"
research_jcs_node build delegated alternate "$investment_semantic_context" >"$alternate_response"
jq '
  .five_lens_process_evidence.lens_dispatches |= map(
    .search_resource_usage = {actual_queries:2,actual_sources:3,elapsed_minutes:8,termination_state:"saturation",exhausted_dimensions:[],confidence_downgraded:false}
  )
  | .five_lens_process_evidence.overall_resource_usage = {actual_queries:10,actual_sources:15,elapsed_minutes:8,termination_state:"saturation",exhausted_dimensions:[],confidence_downgraded:false}
' "$alternate_response" >"$alternate_response.next" && mv "$alternate_response.next" "$alternate_response"
if research_response_oracle_is_valid "$alternate_response" "five-lens-decision-briefing-uses-storm-style-workflow"; then
    pass
else
    fail "assistant-research relational resource oracle rejected a valid alternate under-ceiling response"
fi

test_start "assistant-research relational resource oracle accepts a valid multi-wave delegated schedule"
multi_wave_response="$(mktemp "${TMPDIR:-/tmp}/assistant-research-multi-wave.XXXXXX")"
p0p4_register_cleanup "$multi_wave_response"
research_jcs_node build delegated alternate "$investment_semantic_context" >"$multi_wave_response"
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
if research_response_oracle_is_valid "$multi_wave_response" "five-lens-decision-briefing-uses-storm-style-workflow"; then
    pass
else
    fail "assistant-research relational resource oracle rejected a valid multi-wave delegated schedule"
fi

test_start "assistant-research fixture oracle permits an allocated global IPv6 source"
global_ipv6_response="$(mktemp "${TMPDIR:-/tmp}/assistant-research-global-ipv6.XXXXXX")"
p0p4_register_cleanup "$global_ipv6_response"
research_jcs_node build delegated alternate "$investment_semantic_context" >"$global_ipv6_response"
jq '
  .five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = ["https://[2001:4860:4860::8888]/research"]
  | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].sources_or_verified_urls = ["https://[2001:4860:4860::8888]/follow-up"]
  | .findings[0].sources = ["https://[2001:4860:4860::8888]/research"]
' "$global_ipv6_response" >"$global_ipv6_response.next" && mv "$global_ipv6_response.next" "$global_ipv6_response"
research_refresh_response_derivatives "$global_ipv6_response"
if research_response_oracle_is_valid "$global_ipv6_response" "five-lens-decision-briefing-uses-storm-style-workflow"; then
    pass
else
    fail "assistant-research fixture oracle rejected an allocated global IPv6 source"
fi

test_start "assistant-research fixture oracle accepts IANA IPv4 exceptions and admissible DNS references"
external_reference_response="$(mktemp "${TMPDIR:-/tmp}/assistant-research-external-reference.XXXXXX")"
p0p4_register_cleanup "$external_reference_response"
research_jcs_node build delegated alternate "$investment_semantic_context" >"$external_reference_response"
jq '
  .five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = ["https://192.0.0.9/research"]
  | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].sources_or_verified_urls = ["https://localtest.me/follow-up"]
  | .findings[0].sources = ["https://192.0.0.9/research"]
' "$external_reference_response" >"$external_reference_response.next" && mv "$external_reference_response.next" "$external_reference_response"
research_refresh_response_derivatives "$external_reference_response"
if research_response_oracle_is_valid "$external_reference_response" "five-lens-decision-briefing-uses-storm-style-workflow"; then
    pass
else
    fail "assistant-research fixture oracle rejected IANA IPv4 exceptions or admissible DNS references"
fi

test_start "assistant-research accepts ordinary semantic public URL paths in private and official whole fixtures"
public_path_failures=()
while IFS= read -r public_path; do
    public_path_eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-public-path.XXXXXX")"
    public_path_response="$public_path_eval_dir/assistant-research/five-lens-decision-briefing-uses-storm-style-workflow.txt"
    p0p4_register_cleanup "$public_path_eval_dir"
    write_research_eval_responses "$public_path_eval_dir"
    jq --arg source "$public_path" '.peer_review.evidence[0].source = $source' "$public_path_response" >"$public_path_response.next" && mv "$public_path_response.next" "$public_path_response"
    research_refresh_response_derivatives "$public_path_response"
    if ! research_response_oracle_is_valid "$public_path_response" "five-lens-decision-briefing-uses-storm-style-workflow" \
        || ! "$research_eval_runner" --responses "$public_path_eval_dir" --skill assistant-research --case five-lens-decision-briefing-uses-storm-style-workflow >/dev/null 2>&1; then
        public_path_failures+=("$public_path")
    fi
done <<'EOF'
https://www.iana.org/private
https://www.iana.org/oauth/token
https://www.iana.org/home/about
https://www.iana.org/var/reference
https://www.iana.org/Users/guide
EOF
if [[ "${#public_path_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research public URL path validation rejected safe whole fixtures: ${public_path_failures[*]}"
fi

test_start "assistant-research admits one encoded public HTTPS layer and rejects nested URL forms consistently"
encoded_url_failures=()
while IFS='|' read -r expected matrix_name source; do
    encoded_url_eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-encoded-url.XXXXXX")"
    encoded_url_response="$encoded_url_eval_dir/assistant-research/five-lens-decision-briefing-uses-storm-style-workflow.txt"
    p0p4_register_cleanup "$encoded_url_eval_dir"
    write_research_eval_responses "$encoded_url_eval_dir"
    jq --arg source "$source" '
      .five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = [$source]
      | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].sources_or_verified_urls = [$source]
      | .findings[0].sources = [$source]
      | .peer_review.evidence[0].source = $source
    ' "$encoded_url_response" >"$encoded_url_response.next" && mv "$encoded_url_response.next" "$encoded_url_response"
    research_refresh_response_derivatives "$encoded_url_response"
    if private_output="$(research_response_oracle_is_valid "$encoded_url_response" "five-lens-decision-briefing-uses-storm-style-workflow" 2>&1)"; then private_actual=accept; elif grep -Eq 'ReferenceError|SyntaxError|TypeError' <<<"$private_output"; then private_actual=crash; else private_actual=reject; fi
    if official_output="$("$research_eval_runner" --responses "$encoded_url_eval_dir" --skill assistant-research --case five-lens-decision-briefing-uses-storm-style-workflow 2>&1)"; then official_actual=accept; elif grep -Eq 'ReferenceError|SyntaxError|TypeError' <<<"$official_output"; then official_actual=crash; else official_actual=reject; fi
    [[ "$private_actual" == "$expected" && "$official_actual" == "$expected" ]] || encoded_url_failures+=("$matrix_name:$private_actual/$official_actual")
done <<'EOF'
accept|public-depth-1-lower|https%3a%2f%2fwww.iana.org%2fresearch
reject|private-depth-1-lower|https%3a%2f%2f127.0.0.1%2fresearch
reject|public-depth-2-upper|https%253A%252F%252Fwww.iana.org%252Fresearch
reject|private-depth-2-lower|https%253a%252f%252f127.0.0.1%252fresearch
reject|public-depth-3-lower|https%25253a%25252f%25252fwww.iana.org%25252fresearch
reject|private-depth-3-upper|HTTPS%25253A%25252F%25252F127.0.0.1%25252Fresearch
reject|public-depth-4-upper|https%2525253A%2525252F%2525252Fwww.iana.org%2525252Fresearch
reject|private-depth-4-lower|https%2525253a%2525252f%2525252f127.0.0.1%2525252fresearch
reject|public-depth-6-lower|https%2525252525253a%2525252525252f%2525252525252fwww.iana.org%2525252525252fresearch
reject|private-depth-6-upper|HTTPS%2525252525253A%2525252525252F%2525252525252F127.0.0.1%2525252525252Fresearch
reject|public-depth-2-mixed-slashes|https%253A//www.iana.org%252Fresearch
reject|private-depth-2-mixed-slashes|https%253a%252F/127.0.0.1%252fresearch
reject|public-depth-2-encoded-h|%2568ttps%253A%252F%252Fwww.iana.org%252Fresearch
reject|private-depth-2-encoded-h|%2568tTpS%253a%252f%252f127.0.0.1%252fresearch
reject|public-depth-3-partial-scheme|h%252574tps%25253A%25252F%25252Fwww.iana.org%25252Fresearch
reject|private-depth-4-full-scheme|%25252568%25252574%25252574%25252570%25252573%2525253A%2525252F%2525252F127.0.0.1%2525252Fresearch
reject|public-depth-6-encoded-punctuation|https%2525252525253A%2525252525252F%2525252525252Fwww.iana.org%2525252525252Fresearch
accept|public-depth-1-encoded-h|%68tTpS%3a%2f%2fwww.iana.org%2fresearch
accept|safe-opaque-encoded-delimiters|source:opaque%25253Acontrol
accept|safe-opaque-reserved-delimiter|doi:10.1000%252Fprivate
EOF
encoded_scheme_letter_failures=()
research_nested_http_scheme_reference() {
    local scheme="$1" depth="$2" host="$3" reference iteration
    reference="${scheme}%3A%2F%2F${host}%2Fresearch"
    for ((iteration = 1; iteration < depth; iteration++)); do
        reference="${reference//%/%25}"
    done
    printf '%s' "$reference"
}
while IFS='|' read -r matrix_name scheme host; do
    for depth in 2 3 6; do
        source="$(research_nested_http_scheme_reference "$scheme" "$depth" "$host")"
        encoded_scheme_eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-encoded-scheme-letter.XXXXXX")"
        encoded_scheme_response="$encoded_scheme_eval_dir/assistant-research/five-lens-decision-briefing-uses-storm-style-workflow.txt"
        p0p4_register_cleanup "$encoded_scheme_eval_dir"
        write_research_eval_responses "$encoded_scheme_eval_dir"
        jq --arg source "$source" '
          .five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = [$source]
          | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].sources_or_verified_urls = [$source]
          | .findings[0].sources = [$source]
          | .peer_review.evidence[0].source = $source
        ' "$encoded_scheme_response" >"$encoded_scheme_response.next" && mv "$encoded_scheme_response.next" "$encoded_scheme_response"
        research_refresh_response_derivatives "$encoded_scheme_response"
        if private_output="$(research_response_oracle_is_valid "$encoded_scheme_response" "five-lens-decision-briefing-uses-storm-style-workflow" 2>&1)"; then private_actual=accept; elif grep -Eq 'ReferenceError|SyntaxError|TypeError' <<<"$private_output"; then private_actual=crash; else private_actual=reject; fi
        if official_output="$("$research_eval_runner" --responses "$encoded_scheme_eval_dir" --skill assistant-research --case five-lens-decision-briefing-uses-storm-style-workflow 2>&1)"; then official_actual=accept; elif grep -Eq 'ReferenceError|SyntaxError|TypeError' <<<"$official_output"; then official_actual=crash; else official_actual=reject; fi
        [[ "$private_actual" == reject && "$official_actual" == reject ]] || encoded_scheme_letter_failures+=("${matrix_name}-depth-${depth}:$private_actual/$official_actual")
    done
done <<'EOF'
encoded-h-lower|%68ttps|www.iana.org
encoded-h-upper|%48TTPS|127.0.0.1
encoded-t-first-lower|h%74tps|www.iana.org
encoded-t-first-upper|H%54TPS|127.0.0.1
encoded-t-second-lower|ht%74ps|www.iana.org
encoded-t-second-upper|HT%54PS|127.0.0.1
encoded-p-lower|htt%70s|www.iana.org
encoded-p-upper|HTT%50S|127.0.0.1
encoded-s-lower|http%73|www.iana.org
encoded-s-upper|HTTP%53|127.0.0.1
EOF
for depth in 2 3 6; do
    source="$(research_nested_http_scheme_reference '%48%54t%50%73' "$depth" 'www.iana.org')"
    encoded_scheme_eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-encoded-scheme-mixed.XXXXXX")"
    encoded_scheme_response="$encoded_scheme_eval_dir/assistant-research/five-lens-decision-briefing-uses-storm-style-workflow.txt"
    p0p4_register_cleanup "$encoded_scheme_eval_dir"
    write_research_eval_responses "$encoded_scheme_eval_dir"
    jq --arg source "$source" '
      .five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = [$source]
      | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0].sources_or_verified_urls = [$source]
      | .findings[0].sources = [$source]
      | .peer_review.evidence[0].source = $source
    ' "$encoded_scheme_response" >"$encoded_scheme_response.next" && mv "$encoded_scheme_response.next" "$encoded_scheme_response"
    research_refresh_response_derivatives "$encoded_scheme_response"
    if private_output="$(research_response_oracle_is_valid "$encoded_scheme_response" "five-lens-decision-briefing-uses-storm-style-workflow" 2>&1)"; then private_actual=accept; elif grep -Eq 'ReferenceError|SyntaxError|TypeError' <<<"$private_output"; then private_actual=crash; else private_actual=reject; fi
    if official_output="$("$research_eval_runner" --responses "$encoded_scheme_eval_dir" --skill assistant-research --case five-lens-decision-briefing-uses-storm-style-workflow 2>&1)"; then official_actual=accept; elif grep -Eq 'ReferenceError|SyntaxError|TypeError' <<<"$official_output"; then official_actual=crash; else official_actual=reject; fi
    [[ "$private_actual" == reject && "$official_actual" == reject ]] || encoded_scheme_letter_failures+=("mixed-prefix-depth-${depth}:$private_actual/$official_actual")
done
typed_encoded_url_failures=()
while IFS='|' read -r expected matrix_name source; do
    evidence="$(jq -cn --arg source "$source" '{verification_method:"public_url",verification_reference:$source,verified_url:$source}')"
    if research_verified_source_evidence_is_valid <<<"$evidence"; then ruby_actual=accept; else ruby_actual=reject; fi
    typed_eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-typed-url.XXXXXX")"
    typed_response="$typed_eval_dir/assistant-research/five-lens-decision-briefing-uses-storm-style-workflow.txt"
    p0p4_register_cleanup "$typed_eval_dir"
    write_research_eval_responses "$typed_eval_dir"
    jq --arg source "$source" '
      .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Typed public URL evidence",source:"source:typed-public",verification_method:"public_url",verification_reference:$source,verified_url:$source,verification_detail:"Typed public URL parity fixture."}]
    ' "$typed_response" >"$typed_response.next" && mv "$typed_response.next" "$typed_response"
    research_refresh_response_derivatives "$typed_response"
    if private_output="$(research_response_oracle_is_valid "$typed_response" "five-lens-decision-briefing-uses-storm-style-workflow" 2>&1)"; then private_actual=accept; elif grep -Eq 'ReferenceError|SyntaxError|TypeError' <<<"$private_output"; then private_actual=crash; else private_actual=reject; fi
    if official_output="$("$research_eval_runner" --responses "$typed_eval_dir" --skill assistant-research --case five-lens-decision-briefing-uses-storm-style-workflow 2>&1)"; then official_actual=accept; elif grep -Eq 'ReferenceError|SyntaxError|TypeError' <<<"$official_output"; then official_actual=crash; else official_actual=reject; fi
    [[ "$ruby_actual" == "$expected" && "$private_actual" == "$expected" && "$official_actual" == "$expected" ]] || typed_encoded_url_failures+=("$matrix_name:$ruby_actual/$private_actual/$official_actual")
done <<'EOF'
accept|raw-public|https://www.iana.org/research
accept|raw-public-plus|https://www.iana.org/a+b
accept|raw-public-percent-space|https://www.iana.org/a%20b
accept|raw-public-percent-literal|https://www.iana.org/rate%25
accept|public-depth-1-encoded-h|%68tTpS%3a%2f%2fwww.iana.org%2fresearch
accept|encoded-public-host|https://www.%69ana.org/research
reject|encoded-public-trailing-dot-lower|https://www.iana.org%2e/research
reject|encoded-public-trailing-dot-upper|https://www.iana.org%2E/research
reject|encoded-localhost-trailing-dot|https://localhost%2e/research
reject|private-depth-1|https%3A%2F%2F127.0.0.1%2Fresearch
reject|encoded-private-host|https://%31%32%37.0.0.1/research
reject|encoded-query-token|https%3A%2F%2Fwww.iana.org%2Fresearch%3Ftoken%3Dprivate
reject|public-depth-2|https%253A%252F%252Fwww.iana.org%252Fresearch
reject|public-depth-3|https%25253A%25252F%25252Fwww.iana.org%25252Fresearch
reject|public-depth-4|https%2525253A%2525252F%2525252Fwww.iana.org%2525252Fresearch
reject|public-depth-6|https%2525252525253A%2525252525252F%2525252525252Fwww.iana.org%2525252525252Fresearch
reject|public-depth-2-mixed-slashes|https%253A//www.iana.org%252Fresearch
reject|private-depth-2-encoded-h|%2568ttps%253A%252F%252F127.0.0.1%252Fresearch
reject|private-depth-2-encoded-upper-h|%2548TTPS%253A%252F%252F127.0.0.1%252Fresearch
reject|public-depth-3-partial-scheme|h%252574tps%25253A%25252F%25252Fwww.iana.org%25252Fresearch
EOF
if [[ "${#encoded_url_failures[@]}" -eq 0 && "${#encoded_scheme_letter_failures[@]}" -eq 0 && "${#typed_encoded_url_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research encoded URL source-policy parity failed: ${encoded_url_failures[*]-} ${encoded_scheme_letter_failures[*]-} ${typed_encoded_url_failures[*]-}"
fi

test_start "assistant-research candidate confidence follows canonical source-backed support"
candidate_confidence_failures=()
while IFS='|' read -r expected matrix_name confidence evidence; do
    candidate_eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-candidate-confidence.XXXXXX")"
    candidate_response="$candidate_eval_dir/assistant-research/five-lens-decision-briefing-uses-storm-style-workflow.txt"
    p0p4_register_cleanup "$candidate_eval_dir"
    write_research_eval_responses "$candidate_eval_dir"
    jq --arg confidence "$confidence" --argjson evidence "$evidence" '
      .candidate_mechanisms = [{mechanism:"Candidate confidence calibration fixture.",claim_status:"candidate",evidence:$evidence,confidence:$confidence,counterevidence_or_conflicts:["No material conflict recorded."],gaps:["Independent validation remains pending."],validation_method:"Compare independent source-backed evidence."}]
    ' "$candidate_response" >"$candidate_response.next" && mv "$candidate_response.next" "$candidate_response"
    research_refresh_response_derivatives "$candidate_response"
    if private_output="$(research_response_oracle_is_valid "$candidate_response" "five-lens-decision-briefing-uses-storm-style-workflow" 2>&1)"; then private_actual=accept; elif grep -Eq 'ReferenceError|SyntaxError|TypeError' <<<"$private_output"; then private_actual=crash; else private_actual=reject; fi
    if official_output="$("$research_eval_runner" --responses "$candidate_eval_dir" --skill assistant-research --case five-lens-decision-briefing-uses-storm-style-workflow 2>&1)"; then official_actual=accept; elif grep -Eq 'ReferenceError|SyntaxError|TypeError' <<<"$official_output"; then official_actual=crash; else official_actual=reject; fi
    [[ "$private_actual" == "$expected" && "$official_actual" == "$expected" ]] || candidate_confidence_failures+=("$matrix_name:$private_actual/$official_actual")
done <<'EOF'
accept|low-single-source-backed|low|[{"source":"source:research-corpus:candidate-a","detail":"One source-backed observation.","evidence_status":"source_backed"}]
reject|medium-single-source-backed|medium|[{"source":"source:research-corpus:candidate-a","detail":"One source-backed observation.","evidence_status":"source_backed"}]
reject|high-single-source-backed|high|[{"source":"source:research-corpus:candidate-a","detail":"One source-backed observation.","evidence_status":"source_backed"}]
accept|low-inference-only|low|[{"source":"source:research-corpus:candidate-a","detail":"Inference-only observation.","evidence_status":"inference_only"}]
reject|medium-inference-only|medium|[{"source":"source:research-corpus:candidate-a","detail":"Inference-only observation.","evidence_status":"inference_only"}]
accept|low-unresolved|low|[{"source":"source:research-corpus:candidate-a","detail":"Unresolved observation.","evidence_status":"unresolved"}]
reject|medium-unresolved|medium|[{"source":"source:research-corpus:candidate-a","detail":"Unresolved observation.","evidence_status":"unresolved"}]
accept|medium-two-source-backed|medium|[{"source":"source:research-corpus:candidate-a","detail":"First source-backed observation.","evidence_status":"source_backed"},{"source":"source:research-corpus:candidate-b","detail":"Second source-backed observation.","evidence_status":"source_backed"}]
accept|medium-two-source-backed-plus-inference|medium|[{"source":"source:research-corpus:candidate-a","detail":"First source-backed observation.","evidence_status":"source_backed"},{"source":"source:research-corpus:candidate-b","detail":"Second source-backed observation.","evidence_status":"source_backed"},{"source":"source:research-corpus:candidate-c","detail":"Additional inference observation.","evidence_status":"inference_only"}]
reject|high-two-source-backed|high|[{"source":"source:research-corpus:candidate-a","detail":"First source-backed observation.","evidence_status":"source_backed"},{"source":"source:research-corpus:candidate-b","detail":"Second source-backed observation.","evidence_status":"source_backed"}]
accept|high-three-source-backed|high|[{"source":"source:research-corpus:candidate-a","detail":"First source-backed observation.","evidence_status":"source_backed"},{"source":"source:research-corpus:candidate-b","detail":"Second source-backed observation.","evidence_status":"source_backed"},{"source":"source:research-corpus:candidate-c","detail":"Third source-backed observation.","evidence_status":"source_backed"}]
EOF
if [[ "${#candidate_confidence_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research candidate confidence parity failed: ${candidate_confidence_failures[*]}"
fi

test_start "assistant-research classifies explicit non-HTTPS schemes consistently with opaque source identifiers"
scheme_reference_failures=()
while IFS='|' read -r expected matrix_name source; do
    scheme_eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-scheme-reference.XXXXXX")"
    scheme_response="$scheme_eval_dir/assistant-research/five-lens-decision-briefing-uses-storm-style-workflow.txt"
    p0p4_register_cleanup "$scheme_eval_dir"
    write_research_eval_responses "$scheme_eval_dir"
    jq --arg source "$source" '.peer_review.evidence[0].source = $source' "$scheme_response" >"$scheme_response.next" && mv "$scheme_response.next" "$scheme_response"
    research_refresh_response_derivatives "$scheme_response"
    if research_response_oracle_is_valid "$scheme_response" "five-lens-decision-briefing-uses-storm-style-workflow"; then private_actual=accept; else private_actual=reject; fi
    if "$research_eval_runner" --responses "$scheme_eval_dir" --skill assistant-research --case five-lens-decision-briefing-uses-storm-style-workflow >/dev/null 2>&1; then official_actual=accept; else official_actual=reject; fi
    [[ "$private_actual" == "$expected" && "$official_actual" == "$expected" ]] || scheme_reference_failures+=("$matrix_name:$private_actual/$official_actual")
done <<'EOF'
reject|ftp-url|ftp://www.iana.org/research
reject|file-url|file:///etc/passwd
accept|https-url|https://www.iana.org/research
accept|source-opaque|source:research-corpus:peer
accept|doi-opaque|doi:10.1000/typed-fixture
accept|citation-opaque|citation:ISBN-978-0-00-000000-0
EOF
if [[ "${#scheme_reference_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research source scheme parity failed: ${scheme_reference_failures[*]}"
fi

test_start "assistant-research classifies IANA special-purpose literal IP sources consistently"
literal_ip_policy_failures=()
while IFS='|' read -r expected literal_ip_source; do
    literal_ip_eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-literal-ip.XXXXXX")"
    literal_ip_response="$literal_ip_eval_dir/assistant-research/five-lens-decision-briefing-uses-storm-style-workflow.txt"
    p0p4_register_cleanup "$literal_ip_eval_dir"
    write_research_eval_responses "$literal_ip_eval_dir"
    jq --arg source "$literal_ip_source" '.peer_review.evidence[0].source = $source' "$literal_ip_response" >"$literal_ip_response.next" && mv "$literal_ip_response.next" "$literal_ip_response"
    research_refresh_response_derivatives "$literal_ip_response"
    if research_response_oracle_is_valid "$literal_ip_response" "five-lens-decision-briefing-uses-storm-style-workflow"; then private_actual=accept; else private_actual=reject; fi
    if "$research_eval_runner" --responses "$literal_ip_eval_dir" --skill assistant-research --case five-lens-decision-briefing-uses-storm-style-workflow >/dev/null 2>&1; then official_actual=accept; else official_actual=reject; fi
    [[ "$private_actual" == "$expected" && "$official_actual" == "$expected" ]] || literal_ip_policy_failures+=("$literal_ip_source:$private_actual/$official_actual")
done <<'EOF'
reject|https://192.88.99.2/research
accept|https://192.0.0.9/research
reject|https://[64:ff9b:1::1]/research
accept|https://[2001:1::1]/research
accept|https://[2001:1::2]/research
accept|https://[2001:1::3]/research
reject|https://[2001:2::1]/research
accept|https://[2001:3::1]/research
accept|https://[2001:4:112::1]/research
reject|https://[2001:5::1]/research
accept|https://[2001:20::1]/research
accept|https://[2001:30::1]/research
reject|https://[3fff::1]/research
reject|https://[5f00::1]/research
EOF
if [[ "${#literal_ip_policy_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research literal IP source-policy parity failed: ${literal_ip_policy_failures[*]}"
fi

test_start "assistant-research accepts final finding identities from valid typed evidence ledgers"
typed_evidence_failures=()
while IFS='|' read -r typed_source typed_method typed_reference; do
    typed_eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-typed-evidence.XXXXXX")"
    typed_response="$typed_eval_dir/assistant-research/five-lens-decision-briefing-uses-storm-style-workflow.txt"
    p0p4_register_cleanup "$typed_eval_dir"
    write_research_eval_responses "$typed_eval_dir"
    jq --arg source "$typed_source" --arg method "$typed_method" --arg reference "$typed_reference" '
      .findings[0].sources = [$source]
      | del(.findings[0].source_provenance, .findings[0].verified_urls)
      | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Typed fixture evidence",source:$source,verification_method:$method,verification_reference:$reference,verification_detail:"Typed fixture evidence validation."}]
    ' "$typed_response" >"$typed_response.next" && mv "$typed_response.next" "$typed_response"
    research_refresh_response_derivatives "$typed_response"
    if ! research_response_oracle_is_valid "$typed_response" "five-lens-decision-briefing-uses-storm-style-workflow" \
        || ! "$research_eval_runner" --responses "$typed_eval_dir" --skill assistant-research --case five-lens-decision-briefing-uses-storm-style-workflow >/dev/null 2>&1; then
        typed_evidence_failures+=("$typed_method")
    fi
done <<'EOF'
source:typed-local|local_repository|skills/assistant-research/contracts/output.yaml
source:typed-authenticated|authenticated_source|connector:fixture/record:typed-authenticated
source:typed-offline|offline_authoritative_source|citation:typed-offline
source:typed-doi|offline_authoritative_source|doi:10.1000/typed-fixture
source:typed-doi-path|offline_authoritative_source|doi:10.1000/private
source:typed-isbn|offline_authoritative_source|isbn:978-0-00-000000-0
EOF
for identity_confidence in medium high; do
    identity_eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-encoded-identity.XXXXXX")"
    identity_response="$identity_eval_dir/assistant-research/five-lens-decision-briefing-uses-storm-style-workflow.txt"
    p0p4_register_cleanup "$identity_eval_dir"
    write_research_eval_responses "$identity_eval_dir"
    if [[ "$identity_confidence" == "medium" ]]; then
        jq '
          .findings[0].confidence = "medium"
          | .findings[0].sources = ["https%3A%2F%2Fwww.iana.org%2Fdomains%2Fexample", "https://www.iana.org/domains%2Fexample"]
          | del(.findings[0].source_provenance)
          | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [
              {claim:"Decoded public evidence",source:"https://www.iana.org/domains/example",verification_method:"public_url",verification_reference:"https://www.iana.org/domains/example",verified_url:"https://www.iana.org/domains/example",verification_detail:"Decoded public fixture evidence."},
              {claim:"Reserved delimiter public evidence",source:"https://www.iana.org/domains%2Fexample",verification_method:"public_url",verification_reference:"https://www.iana.org/domains%2Fexample",verified_url:"https://www.iana.org/domains%2Fexample",verification_detail:"Reserved delimiter remains a distinct public URL."}
            ]
        ' "$identity_response" >"$identity_response.next" && mv "$identity_response.next" "$identity_response"
    else
        jq '
          .findings[0].confidence = "high"
          | .findings[0].sources = ["https%3A%2F%2Fwww.iana.org%2Fdomains%2Fexample", "https://www.iana.org/domains%2Fexample", "https://www.iana.org/help/example-domains"]
          | .findings[0].source_provenance = [
              {source:"https%3A%2F%2Fwww.iana.org%2Fdomains%2Fexample",independence_key:"decoded",authority:"official"},
              {source:"https://www.iana.org/domains%2Fexample",independence_key:"reserved",authority:"primary"},
              {source:"https://www.iana.org/help/example-domains",independence_key:"distinct",authority:"secondary"}
            ]
          | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [
              {claim:"Decoded public evidence",source:"https://www.iana.org/domains/example",verification_method:"public_url",verification_reference:"https://www.iana.org/domains/example",verified_url:"https://www.iana.org/domains/example",verification_detail:"Decoded public fixture evidence."},
              {claim:"Reserved delimiter public evidence",source:"https://www.iana.org/domains%2Fexample",verification_method:"public_url",verification_reference:"https://www.iana.org/domains%2Fexample",verified_url:"https://www.iana.org/domains%2Fexample",verification_detail:"Reserved delimiter remains a distinct public URL."},
              {claim:"Distinct public evidence",source:"https://www.iana.org/help/example-domains",verification_method:"public_url",verification_reference:"https://www.iana.org/help/example-domains",verified_url:"https://www.iana.org/help/example-domains",verification_detail:"Distinct public fixture evidence."}
            ]
        ' "$identity_response" >"$identity_response.next" && mv "$identity_response.next" "$identity_response"
    fi
    research_refresh_response_derivatives "$identity_response"
    if ! research_response_oracle_is_valid "$identity_response" "five-lens-decision-briefing-uses-storm-style-workflow" \
        || ! "$research_eval_runner" --responses "$identity_eval_dir" --skill assistant-research --case five-lens-decision-briefing-uses-storm-style-workflow >/dev/null 2>&1; then
        typed_evidence_failures+=("fully-encoded-$identity_confidence")
    fi
done
if [[ "${#typed_evidence_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research typed verified evidence identities rejected by private or official validation: ${typed_evidence_failures[*]}"
fi

test_start "assistant-research URL and candidate negative fixtures reach source safety with valid counterparts"
fixture_safety_failures=()
while IFS='|' read -r expected fixture_name fixture_kind source; do
    fixture_eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-fixture-safety.XXXXXX")"
    fixture_response="$fixture_eval_dir/assistant-research/five-lens-decision-briefing-uses-storm-style-workflow.txt"
    p0p4_register_cleanup "$fixture_eval_dir"
    write_research_eval_responses "$fixture_eval_dir"
    jq --arg kind "$fixture_kind" --arg source "$source" '
      if $kind == "typed" then
        .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{
          claim:"Public fixture evidence",source:"source:typed-public",verification_method:"public_url",
          verification_reference:$source,verified_url:$source,verification_detail:"Typed source safety fixture."
        }]
      else
        .candidate_mechanisms = [{
          mechanism:"Candidate fixture mechanism",claim_status:"candidate",
          evidence:[{source:$source,detail:"Candidate source safety fixture.",evidence_status:"source_backed"}],
          confidence:"low",counterevidence_or_conflicts:["No counterevidence recorded."],
          gaps:["Independent validation remains pending."],validation_method:"Compare independent evidence."
        }]
      end
    ' "$fixture_response" >"$fixture_response.next" && mv "$fixture_response.next" "$fixture_response"
    research_refresh_response_derivatives "$fixture_response"
    if research_response_oracle_is_valid "$fixture_response" "five-lens-decision-briefing-uses-storm-style-workflow"; then private_actual=accept; else private_actual=reject; fi
    if "$research_eval_runner" --responses "$fixture_eval_dir" --skill assistant-research --case five-lens-decision-briefing-uses-storm-style-workflow >/dev/null 2>&1; then official_actual=accept; else official_actual=reject; fi
    [[ "$private_actual" == "$expected" && "$official_actual" == "$expected" ]] || fixture_safety_failures+=("$fixture_name:$private_actual/$official_actual")
done <<'EOF'
accept|typed-public-control|typed|https://www.iana.org/typed-fixture
reject|typed-public-secret|typed|https://www.iana.org/typed-fixture?%74oken=private
accept|candidate-opaque-control|candidate|source:research-corpus:candidate
reject|candidate-opaque-pii|candidate|source:%65mail=person%40sample.invalid
EOF
if [[ "${#fixture_safety_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research source safety fixture coverage failed: ${fixture_safety_failures[*]}"
fi

test_start "assistant-research typed evidence rejects decoded opaque hazards and accepts static DNS references"
typed_reference_failures=()
while IFS='|' read -r expected method reference verified_url; do
    evidence="$(jq -cn --arg method "$method" --arg reference "$reference" --arg verified_url "$verified_url" '{verification_method:$method,verification_reference:$reference} + (if $method == "public_url" then {verified_url:$verified_url} else {} end)')"
    if research_verified_source_evidence_is_valid <<<"$evidence"; then
        actual=accept
    else
        actual=reject
    fi
    [[ "$actual" == "$expected" ]] || typed_reference_failures+=("$method:$reference")
done <<'EOF'
reject|offline_authoritative_source|citation:a/../docs|
reject|offline_authoritative_source|citation:a/%2e%2e/docs|
reject|offline_authoritative_source|citation:/Users/redacted/notes|
reject|offline_authoritative_source|doi:10.1000/example?token=redacted|
accept|offline_authoritative_source|doi:10.1000/private|
reject|public_url|https://@www.iana.org/path|https://@www.iana.org/path
reject|public_url|https://:@www.iana.org/path|https://:@www.iana.org/path
reject|public_url|https%3A%2F%2F127.0.0.1%2Fpath|https%3A%2F%2F127.0.0.1%2Fpath
reject|public_url|https://%31%32%37.0.0.1/path|https://%31%32%37.0.0.1/path
accept|public_url|https://www.%69ana.org/path|https://www.%69ana.org/path
accept|public_url|https://localtest.me/path|https://localtest.me/path
accept|public_url|https://192.0.0.9/path|https://192.0.0.9/path
accept|public_url|https://192.0.0.10/path|https://192.0.0.10/path
accept|public_url|https://www.iana.org/private|https://www.iana.org/private
accept|public_url|https://www.iana.org/oauth/token|https://www.iana.org/oauth/token
accept|public_url|https://www.iana.org/home/about|https://www.iana.org/home/about
accept|public_url|https://www.iana.org/var/reference|https://www.iana.org/var/reference
accept|public_url|https://www.iana.org/Users/guide|https://www.iana.org/Users/guide
reject|public_url|https://192.88.99.2/path|https://192.88.99.2/path
accept|public_url|https://192.0.0.9/path|https://192.0.0.9/path
reject|public_url|https://[64:ff9b:1::1]/path|https://[64:ff9b:1::1]/path
accept|public_url|https://[2001:1::1]/path|https://[2001:1::1]/path
accept|public_url|https://[2001:1::2]/path|https://[2001:1::2]/path
accept|public_url|https://[2001:1::3]/path|https://[2001:1::3]/path
reject|public_url|https://[2001:2::1]/path|https://[2001:2::1]/path
accept|public_url|https://[2001:3::1]/path|https://[2001:3::1]/path
accept|public_url|https://[2001:4:112::1]/path|https://[2001:4:112::1]/path
reject|public_url|https://[2001:5::1]/path|https://[2001:5::1]/path
accept|public_url|https://[2001:20::1]/path|https://[2001:20::1]/path
accept|public_url|https://[2001:30::1]/path|https://[2001:30::1]/path
reject|public_url|https://[3fff::1]/path|https://[3fff::1]/path
reject|public_url|https://[5f00::1]/path|https://[5f00::1]/path
reject|public_url|https://192.0.0.8/path|https://192.0.0.8/path
EOF
if [[ "${#typed_reference_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research typed evidence source-policy parity failed: ${typed_reference_failures[*]}"
fi

test_start "assistant-research semantic fixtures reject unbound evidence, false revision closure, and response-authored capacity"
semantic_closeout_failures=()
while IFS='|' read -r expected fixture_name mutation; do
    semantic_closeout_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-semantic-closeout.XXXXXX")"
    semantic_closeout_response="$semantic_closeout_dir/assistant-research/five-lens-decision-briefing-uses-storm-style-workflow.txt"
    p0p4_register_cleanup "$semantic_closeout_dir"
    write_research_eval_responses "$semantic_closeout_dir"
    case "$mutation" in
      source_empty_high)
        jq '.five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = [] | .five_lens_process_evidence.accepted_lens_results[0].evidence_status = "inference_only" | .five_lens_process_evidence.accepted_lens_results[0].confidence = "high" | .five_lens_process_evidence.accepted_lens_results[0].gaps = ["Source verification is pending."]' "$semantic_closeout_response" >"$semantic_closeout_response.next" && mv "$semantic_closeout_response.next" "$semantic_closeout_response"
        ;;
      unbound_verified_url)
        jq '.findings[0].verified_urls = ["https://www.iana.org/unrelated"]' "$semantic_closeout_response" >"$semantic_closeout_response.next" && mv "$semantic_closeout_response.next" "$semantic_closeout_response"
        ;;
      non_public_evidence_url_label)
        jq '.findings[0].verified_urls = ["https://www.iana.org/uncollected-review-probe"] | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence[0].source = "https://www.iana.org/uncollected-review-probe"' "$semantic_closeout_response" >"$semantic_closeout_response.next" && mv "$semantic_closeout_response.next" "$semantic_closeout_response"
        ;;
      canonical_collected_source)
        jq '.five_lens_process_evidence.accepted_lens_results[0].sources_or_verified_urls = ["https://www.iana.org/domains/example"] | .findings[0].sources = ["https://WWW.IANA.ORG/%64omains/example"] | .findings[0].verified_urls = ["https://WWW.IANA.ORG/%64omains/example"]' "$semantic_closeout_response" >"$semantic_closeout_response.next" && mv "$semantic_closeout_response.next" "$semantic_closeout_response"
        ;;
      source_empty_completion)
        jq '.findings = [] | .gaps = ["Sources remain unavailable."] | .five_lens_process_evidence.accepted_lens_results |= map(.sources_or_verified_urls = [] | .confidence = "low" | .evidence_status = "unresolved" | .gaps = ["Sources remain unavailable."] | .follow_ups |= map(.sources_or_verified_urls = [] | .evidence_status = "unresolved" | .gaps = ["Sources remain unavailable."]))' "$semantic_closeout_response" >"$semantic_closeout_response.next" && mv "$semantic_closeout_response.next" "$semantic_closeout_response"
        ;;
      material_follow_up)
        jq '.findings = [] | .gaps = ["Sources remain unavailable."] | .five_lens_process_evidence.accepted_lens_results |= map(.sources_or_verified_urls = [] | .confidence = "low" | .evidence_status = "unresolved" | .gaps = ["Sources remain unavailable."] | .follow_ups |= map(.sources_or_verified_urls = [] | .evidence_status = "unresolved" | .gaps = ["Sources remain unavailable."])) | .five_lens_process_evidence.accepted_lens_results[0].follow_ups[0] = {decision:"follow_up",question:"What does the accepted source say?",answer_or_gap:"A source-backed follow-up exists.",sources_or_verified_urls:["source:research-corpus:material-follow-up"],evidence_status:"source_backed",gaps:[]}' "$semantic_closeout_response" >"$semantic_closeout_response.next" && mv "$semantic_closeout_response.next" "$semantic_closeout_response"
        ;;
      response_capacity)
        jq '.five_lens_process_evidence.wave_coverage[0].capacity = 999' "$semantic_closeout_response" >"$semantic_closeout_response.next" && mv "$semantic_closeout_response.next" "$semantic_closeout_response"
        ;;
      multi_wave_capacity_two)
        jq '.five_lens_process_evidence.lens_dispatches[2].wave_id = "wave-2" | .five_lens_process_evidence.lens_dispatches[3].wave_id = "wave-2" | .five_lens_process_evidence.lens_dispatches[4].wave_id = "wave-3" | .five_lens_process_evidence.wave_coverage = [{wave_id:"wave-1",capacity:2,lens_kinds:["practitioner","academic_or_technical_expert"]},{wave_id:"wave-2",capacity:2,lens_kinds:["skeptic","economist_or_incentives_analyst"]},{wave_id:"wave-3",capacity:2,lens_kinds:["historian_or_pattern_matcher"]}] | .five_lens_process_evidence.overall_resource_usage.elapsed_minutes = 30' "$semantic_closeout_response" >"$semantic_closeout_response.next" && mv "$semantic_closeout_response.next" "$semantic_closeout_response"
        ;;
      unchanged_revision)
        jq '.five_lens_process_evidence.peer_review_input_binding.initial_synthesis = .synthesis_briefing' "$semantic_closeout_response" >"$semantic_closeout_response.next" && mv "$semantic_closeout_response.next" "$semantic_closeout_response"
        ;;
      candidate_ledger_alias)
        jq '.candidate_mechanisms = [{mechanism:"Alias-count calibration.",claim_status:"candidate",evidence:[{source:"typed-public-label",detail:"A typed public source label.",evidence_status:"source_backed"},{source:"https://www.iana.org/typed-public",detail:"The same typed public source URL.",evidence_status:"source_backed"}],confidence:"medium",counterevidence_or_conflicts:["No conflict recorded."],gaps:["Independent validation remains pending."],validation_method:"Compare a second source."}] | .five_lens_process_evidence.peer_review_input_binding.verified_source_evidence = [{claim:"Typed public evidence",source:"typed-public-label",verification_method:"public_url",verification_reference:"https://www.iana.org/typed-public",verified_url:"https://www.iana.org/typed-public",verification_detail:"Fixture public evidence."}]' "$semantic_closeout_response" >"$semantic_closeout_response.next" && mv "$semantic_closeout_response.next" "$semantic_closeout_response"
        ;;
      delegated_accepted)
        jq 'del(.peer_review.revision_disposition_id, .peer_review.revision_disposition, .five_lens_process_evidence.peer_review_revision_disposition_id) | .peer_review.status = "DONE" | .peer_review.verdict = "accepted" | .peer_review.required_revisions = [] | .five_lens_process_evidence.peer_review_input_binding.initial_synthesis = .synthesis_briefing' "$semantic_closeout_response" >"$semantic_closeout_response.next" && mv "$semantic_closeout_response.next" "$semantic_closeout_response"
        ;;
    esac
    research_refresh_response_derivatives "$semantic_closeout_response"
    if research_response_oracle_is_valid "$semantic_closeout_response" "five-lens-decision-briefing-uses-storm-style-workflow"; then private_actual=accept; else private_actual=reject; fi
    if [[ "$fixture_name" == "delegated-peer-accepted" ]]; then
        if ( source "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-semantic-validators.sh"; assistant_research_five_lens_v3_valid "$semantic_closeout_response" "$research_evals" five-lens-decision-briefing-uses-storm-style-workflow ) >/dev/null 2>&1; then official_actual=accept; else official_actual=reject; fi
    elif "$research_eval_runner" --responses "$semantic_closeout_dir" --skill assistant-research --case five-lens-decision-briefing-uses-storm-style-workflow >/dev/null 2>&1; then official_actual=accept; else official_actual=reject; fi
    [[ "$private_actual" == "$expected" && "$official_actual" == "$expected" ]] || semantic_closeout_failures+=("$fixture_name:$private_actual/$official_actual")
done <<'EOF'
reject|source-empty-high|source_empty_high
reject|unbound-verified-url|unbound_verified_url
reject|non-public-evidence-url-label|non_public_evidence_url_label
accept|canonical-collected-source|canonical_collected_source
accept|source-empty-completion|source_empty_completion
reject|material-follow-up-with-empty-findings|material_follow_up
reject|response-authored-capacity|response_capacity
accept|three-waves-with-conservative-capacity-two|multi_wave_capacity_two
reject|unchanged-revision|unchanged_revision
reject|candidate-typed-label-and-url-alias|candidate_ledger_alias
accept|delegated-peer-accepted|delegated_accepted
EOF
if [[ "${#semantic_closeout_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research close-out semantic regressions: ${semantic_closeout_failures[*]}"
fi

test_start "assistant-research derivative refresh retains accepted peer initial synthesis"
retained_peer_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-retained-peer.XXXXXX")"
p0p4_register_cleanup "$retained_peer_dir"
retained_peer_response="$retained_peer_dir/assistant-research/five-lens-decision-briefing-uses-storm-style-workflow.txt"
write_research_eval_responses "$retained_peer_dir"
jq 'del(.peer_review.revision_disposition_id, .peer_review.revision_disposition, .five_lens_process_evidence.peer_review_revision_disposition_id) | .peer_review.status = "DONE" | .peer_review.verdict = "accepted" | .peer_review.required_revisions = [] | .five_lens_process_evidence.peer_review_input_binding.initial_synthesis = .synthesis_briefing' "$retained_peer_response" >"$retained_peer_response.next" && mv "$retained_peer_response.next" "$retained_peer_response"
research_refresh_response_derivatives "$retained_peer_response"
retained_initial_synthesis="$(jq -c '.five_lens_process_evidence.peer_review_input_binding.initial_synthesis' "$retained_peer_response")"
jq '.synthesis_briefing.executive_summary += " Post-review substitution."' "$retained_peer_response" >"$retained_peer_response.next" && mv "$retained_peer_response.next" "$retained_peer_response"
research_refresh_response_derivatives "$retained_peer_response"
if [[ "$retained_initial_synthesis" == "$(jq -c '.five_lens_process_evidence.peer_review_input_binding.initial_synthesis' "$retained_peer_response")" ]] \
    && ! research_response_oracle_is_valid "$retained_peer_response" "five-lens-decision-briefing-uses-storm-style-workflow"; then
    pass
else
    fail "assistant-research derivative refresh overwrote accepted peer initial synthesis"
fi

test_start "assistant-research semantic fixture adapter context is typed and required"
adapter_context_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-adapter-context.XXXXXX")"
p0p4_register_cleanup "$adapter_context_dir"
missing_adapter_fixture="$adapter_context_dir/missing-adapter-context.json"
invalid_adapter_fixture="$adapter_context_dir/invalid-adapter-context.json"
oversized_adapter_fixture="$adapter_context_dir/oversized-adapter-context.json"
upper_bound_adapter_fixture="$adapter_context_dir/upper-bound-adapter-context.json"
jq '(.cases[] | select(.semantic_validator == "assistant-research.five_lens_v3") | .semantic_context) |= del(.adapter_context)' "$research_evals" >"$missing_adapter_fixture"
jq '(.cases[] | select(.semantic_validator == "assistant-research.five_lens_v3") | .semantic_context.adapter_context.max_concurrent_lens_workers) = 0' "$research_evals" >"$invalid_adapter_fixture"
jq '(.cases[] | select(.semantic_validator == "assistant-research.five_lens_v3") | .semantic_context.adapter_context.max_concurrent_lens_workers) = 9007199254740992' "$research_evals" >"$oversized_adapter_fixture"
jq '(.cases[] | select(.semantic_validator == "assistant-research.five_lens_v3") | .semantic_context.adapter_context.max_concurrent_lens_workers) = 9007199254740991' "$research_evals" >"$upper_bound_adapter_fixture"
write_research_eval_responses "$adapter_context_dir/responses"
upper_bound_response="$adapter_context_dir/responses/assistant-research/five-lens-decision-briefing-uses-storm-style-workflow.txt"
if ( source "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-fixtures.sh"; validate_fixture "$research_evals" assistant-research ) >/dev/null 2>&1 \
    && ! ( source "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-fixtures.sh"; validate_fixture "$missing_adapter_fixture" assistant-research ) >/dev/null 2>&1 \
    && ! ( source "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-fixtures.sh"; validate_fixture "$invalid_adapter_fixture" assistant-research ) >/dev/null 2>&1 \
    && ! ( source "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-fixtures.sh"; validate_fixture "$oversized_adapter_fixture" assistant-research ) >/dev/null 2>&1 \
    && ( source "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-fixtures.sh"; validate_fixture "$upper_bound_adapter_fixture" assistant-research ) >/dev/null 2>&1 \
    && ( source "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-semantic-validators.sh"; assistant_research_five_lens_v3_valid "$upper_bound_response" "$upper_bound_adapter_fixture" five-lens-decision-briefing-uses-storm-style-workflow ) >/dev/null 2>&1; then
    pass
else
    fail "assistant-research semantic adapter context accepted a missing or non-positive capacity"
fi

test_start "assistant-research semantic fixtures bind common packet scope and required follow-ups"
semantic_context_fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-semantic-context.XXXXXX")"
p0p4_register_cleanup "$semantic_context_fixture_root"
write_research_eval_responses "$semantic_context_fixture_root"
semantic_context_failures=()
while IFS= read -r semantic_case_id; do
    semantic_context="$(jq -c --arg case_id "$semantic_case_id" '.cases[] | select(.id == $case_id) | .semantic_context' "$research_evals")"
    semantic_response="$semantic_context_fixture_root/assistant-research/$semantic_case_id.txt"
    if [[ ! -s "$semantic_response" ]] \
        || ! jq -e --arg case_id "$semantic_case_id" --argjson context "$semantic_context" '
            . as $response
            | .five_lens_process_evidence.frozen_assignment_packets as $packets
            | ($context.packet_scope) as $scope
            | ($context.follow_up_requirements) as $requirements
            | ($context.required_topic_terms) as $topic_terms
            | ($topic_terms | type == "array")
            and (if $case_id == "five-lens-decision-briefing-uses-storm-style-workflow" then $topic_terms == ["invest", "AI coding assistant", ".NET architecture"] else $topic_terms == [] end)
            and ($packets | length == 5 and all(.[]; .question == $scope.question and .user_role_or_goal == $scope.user_role_or_goal and .output_purpose == $scope.output_purpose))
            and all($requirements[];
                . as $requirement
                | ([$response.five_lens_process_evidence.accepted_lens_results[] | select(.lens_kind == $requirement.lens_kind).follow_ups[] | select(.decision == $requirement.decision)] | length) == $requirement.exact_count
              )
        ' "$semantic_response" >/dev/null \
        || ! research_response_oracle_is_valid "$semantic_response" "$semantic_case_id"; then
        semantic_context_failures+=("$semantic_case_id")
    fi
done < <(jq -r '.cases[] | select(.semantic_validator == "assistant-research.five_lens_v3") | .id' "$research_evals")
if [[ "$(jq '[.cases[] | select(.semantic_validator == "assistant-research.five_lens_v3")] | length' "$research_evals")" == "5" ]] \
    && [[ "${#semantic_context_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research semantic fixture context or follow-up binding invalid: ${semantic_context_failures[*]-}"
fi

test_start "assistant-research resolves canonical URL typed-source labels without verified-URL authority"
if research_typed_url_label_source_resolution_controls; then
    pass
else
    fail "assistant-research canonical typed-source label resolution controls failed"
fi

test_start "assistant-research counts canonical URL typed-source aliases once"
if research_typed_url_label_identity_counting_controls; then
    pass
else
    fail "assistant-research canonical typed-source label identity-counting controls failed"
fi

test_start "assistant-research counts overlapping typed evidence aliases independently of row order"
if research_overlapping_evidence_alias_controls; then
    pass
else
    fail "assistant-research overlapping typed evidence alias controls failed"
fi

test_start "assistant-research accepts optional verified URL arrays without weakening entry validation"
if research_optional_verified_urls_controls; then
    pass
else
    fail "assistant-research optional verified URL controls failed"
fi

test_start "assistant-research import validation keeps caller state isolated"
if node "$FRAMEWORK_DIR/tests/p0-p4/lib/assistant-research-semantic-controls.cjs" --isolation "$FRAMEWORK_DIR" "$research_evals"; then
    pass
else
    fail "assistant-research import isolation controls failed"
fi

test_start "assistant-research CLI preserves fixture and response failure diagnostics"
if node "$FRAMEWORK_DIR/tests/p0-p4/lib/assistant-research-semantic-controls.cjs" --cli-compat "$FRAMEWORK_DIR" "$research_evals"; then
    pass
else
    fail "assistant-research CLI compatibility controls failed"
fi

test_start "assistant-research direct controls account for production misclassifications"
if node "$FRAMEWORK_DIR/tests/p0-p4/lib/assistant-research-semantic-controls.cjs" --counter-accounting "$FRAMEWORK_DIR" "$research_evals" capacity; then
    pass
else
    fail "assistant-research direct-control classification accounting failed"
fi

test_start "assistant-research accepted peers exclude all revision closure metadata"
if research_completion_validator_controls peer; then
    pass
else
    fail "assistant-research peer revision metadata controls failed"
fi

test_start "assistant-research fixture capacity admits only positive safe integers"
if research_fixture_capacity_controls; then
    pass
else
    fail "assistant-research fixture capacity controls failed"
fi

test_start "assistant-research empty findings account for material follow-ups in producers and consumers"
if research_empty_findings_producer_controls; then
    pass
else
    fail "assistant-research empty-findings producer controls failed"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
