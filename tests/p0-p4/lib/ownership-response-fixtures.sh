#!/usr/bin/env bash
# Fixed nonexecuting instruction projections of selected existing contract fields.
# These partial projections are neither full admitted packets nor runtime evidence.
write_ownership_response() {
    local case_id="$1" response_path="$2"
    case "$case_id" in
        ownership-authoring-without-red)
            cat >"$response_path" <<'RESPONSE'
{"summary":"ownership protocol: nonexecuting instruction projection; no admitted packet or runtime claim","changed_files":[{"path":"tests/ownership_test.rb","change_type":"created","description":"Writer-authored test."},{"path":"tests/fixtures/ownership.json","change_type":"created","description":"Writer-authored fixture."}],"current_task_packet":{"worker_stage":"test_authoring","writer_selection":{"agent":"intelligent-writer","rationale":"Test oracle selection requires judgment."},"execution":{"state":"RUNNING"}},"status":"DONE"}
RESPONSE
            ;;
        ownership-production-invalid-red)
            cat >"$response_path" <<'RESPONSE'
{"summary":"ownership protocol: nonexecuting instruction projection; no admitted packet or runtime claim","status":"NEEDS_CONTEXT","changed_files":[],"current_task_packet":{"worker_stage":"production","writer_selection":{"agent":"intelligent-writer","rationale":"Preserve semantic ownership."},"execution":{"state":"BLOCKED"}}}
RESPONSE
            ;;
        ownership-verifier-prohibited-mutation)
            cat >"$response_path" <<'RESPONSE'
{"summary":"ownership protocol: nonexecuting instruction projection; no admitted packet or runtime claim","status":"DEVIATED","changed_files":[{"path":"tests/fixtures/ownership.json","change_type":"modified","description":"Actual prohibited verifier mutation preserved in evidence."}],"current_task_packet":{"execution":{"state":"BLOCKED"}}}
RESPONSE
            ;;
        ownership-mechanical-fixed-tests)
            cat >"$response_path" <<'RESPONSE'
{"summary":"ownership protocol: nonexecuting instruction projection; no admitted packet or runtime claim","current_task_packet":{"worker_stage":"test_authoring","writer_selection":{"agent":"mechanical-writer","rationale":"BOTH tests and implementation have fixed cases, expected values, negative cases and assertion/fixture patterns.","mechanical_eligibility":{"recipe_or_example_ref":"recipe.md","resolved_decisions_ref":"decisions.md","scope_and_dependencies_ref":"scope.md","correctness_expectations_ref":"expectations.md"}}}}
RESPONSE
            ;;
        ownership-unresolved-test-oracle)
            cat >"$response_path" <<'RESPONSE'
{"summary":"ownership protocol: nonexecuting instruction projection; no admitted packet or runtime claim","current_task_packet":{"worker_stage":"test_authoring","writer_selection":{"agent":"intelligent-writer","rationale":"Unresolved oracle and counterexample selection requires judgment for BOTH tests and implementation."}}}
RESPONSE
            ;;
        ownership-separated-stage-order)
            cat >"$response_path" <<'RESPONSE'
{"summary":"ownership protocol: nonexecuting instruction projection; no admitted packet or runtime claim","ownership_stage_projection":{"stage_order":["test_authoring","pre_production_red","production","GREEN","refactor","REFACTOR"],"owner_order":["intelligent-writer","builder-tester","intelligent-writer","builder-tester","intelligent-writer","builder-tester"],"completes_build":false,"production_requires_red":true,"refactor_requires_green":true},"task_journal_entry":"SAME intelligent-writer test_authoring (tests only, no incoming RED) -> builder-tester pre_production_red -> SAME intelligent-writer production (current exact meaningful RED) -> builder-tester GREEN -> SAME intelligent-writer refactor (current passing GREEN) -> builder-tester distinct REFACTOR; stage-only DONE never completes Build or permits Review."}
RESPONSE
            ;;
        *) return 1 ;;
    esac
}
