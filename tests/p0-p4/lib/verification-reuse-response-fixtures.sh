#!/usr/bin/env bash

write_verification_reuse_response() {
    local case_id="$1" response_path="$2" summary="$3" ids
    case "$case_id" in
        verification-reuse-current-scenario-matrix)
            ids='["unchanged-complete","unrelated-doc-input-boundary","changed-production","changed-tests","changed-config","changed-dependency","changed-argv","changed-cwd","changed-toolchain","changed-environment","prior-failed","prior-partial","prior-skipped","unknown-basis","explicit-fresh-run","mutable-external-state","new-integration-coverage","post-fix-source"]'
            ;;
        verification-reuse-preserves-independent-review)
            ids='["spec-review-required","independent-code-review-required","final-review-snapshot-current"]'
            ;;
        *) return 1 ;;
    esac
    jq -n --arg summary "$summary" --arg case_id "$case_id" --argjson ids "$ids" '
      {summary:$summary,decisions:[$ids[] | {
        id:.,
        action:(if $case_id == "verification-reuse-preserves-independent-review"
                   or . == "unchanged-complete" or . == "unrelated-doc-input-boundary"
                then "reuse" else "rerun" end),
        original_run_ref:("run/" + .),
        current_comparison_ref:("comparison/" + .),
        independent_review_status:"required"
      }]}
    ' >"$response_path"
}
