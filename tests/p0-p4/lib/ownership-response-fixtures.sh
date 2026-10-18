#!/usr/bin/env bash
# Fixed canonical outcome projections independent of mutable fixture assertions.
write_ownership_response() {
    local case_id="$1" response_path="$2"
    case "$case_id" in
        ownership-authoring-without-red)
            cat >"$response_path" <<'RESPONSE'
{"summary":"ownership protocol","slice_manifest":[{"worker_stage":"test_authoring","writer_selection":{"agent":"intelligent-writer","rationale":"Test oracle selection requires judgment."}}],"slice_verification_summary":[{"implementation_status":"done","final_status":"BLOCKED","red_status":"not_started"}],"changed_files":[{"path":"tests/ownership_test.rb","change_type":"created","description":"Writer-authored test."},{"path":"tests/fixtures/ownership.json","change_type":"created","description":"Writer-authored fixture."}]}
RESPONSE
            ;;
        ownership-production-invalid-red)
            cat >"$response_path" <<'RESPONSE'
{"summary":"ownership protocol","status":"NEEDS_CONTEXT","slice_manifest":[{"worker_stage":"production","writer_selection":{"agent":"intelligent-writer","rationale":"Preserve semantic ownership."}}],"slice_verification_summary":[{"implementation_status":"blocked","final_status":"BLOCKED","red_status":"stale_wrong_identity_no_authorization"}],"changed_files":[]}
RESPONSE
            ;;
        ownership-verifier-prohibited-mutation)
            cat >"$response_path" <<'RESPONSE'
{"summary":"ownership protocol","status":"DEVIATED","slice_verification_summary":[{"implementation_status":"blocked","final_status":"BLOCKED","self_check_result":"DEVIATED: verifier changed authored fixture; route repair to selected writer."}],"changed_files":[{"path":"tests/fixtures/ownership.json","change_type":"modified","description":"Actual prohibited verifier mutation preserved in evidence."}]}
RESPONSE
            ;;
        ownership-mechanical-fixed-tests)
            cat >"$response_path" <<'RESPONSE'
{"summary":"ownership protocol","slice_manifest":[{"worker_stage":"test_authoring","writer_selection":{"agent":"mechanical-writer","rationale":"BOTH tests and implementation have fixed cases, expected values, negative cases and assertion/fixture patterns.","mechanical_eligibility":{"recipe_or_example_ref":"recipe.md","resolved_decisions_ref":"decisions.md","scope_and_dependencies_ref":"scope.md","correctness_expectations_ref":"expectations.md"}}}]}
RESPONSE
            ;;
        ownership-unresolved-test-oracle)
            cat >"$response_path" <<'RESPONSE'
{"summary":"ownership protocol","slice_manifest":[{"worker_stage":"test_authoring","writer_selection":{"agent":"intelligent-writer","rationale":"Unresolved oracle and counterexample selection requires judgment for BOTH tests and implementation."}}]}
RESPONSE
            ;;
        ownership-separated-stage-order)
            cat >"$response_path" <<'RESPONSE'
{"summary":"ownership protocol","ownership_stage_projection":{"stage_order":["test_authoring","pre_production_red","production","GREEN","refactor","REFACTOR"],"owner_order":["intelligent-writer","builder-tester","intelligent-writer","builder-tester","intelligent-writer","builder-tester"],"completes_build":false,"production_requires_red":true,"refactor_requires_green":true},"task_journal_entry":"SAME intelligent-writer test_authoring (tests only, no incoming RED) -> builder-tester pre_production_red -> SAME intelligent-writer production (current exact meaningful RED) -> builder-tester GREEN -> SAME intelligent-writer refactor (current passing GREEN) -> builder-tester distinct REFACTOR; stage-only DONE never completes Build or permits Review."}
RESPONSE
            ;;
        *) return 1 ;;
    esac
}
