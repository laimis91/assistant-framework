#!/usr/bin/env bash
# Test-only independent oracle for feature-preparation response-case records.
if [[ -n "${FEATURE_PREPARATION_CASE_ORACLE_LOADED:-}" ]]; then
    return 0
fi
readonly FEATURE_PREPARATION_CASE_ORACLE_LOADED=1

readonly FEATURE_PREP_EXPECTED_CASE_RECORDS=(
    'medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|plan_document'
    'medium-prepare-only-readiness-reports-pending-requirement-map|medium|plan_document'
    'medium-prepare-only-qa-request-routing|medium|plan_document'
    'combined-preparation-and-implementation-routes-end-to-end|small|'
    'viewing-route-preserves-active-behavior|light|plan_document'
    'feature-preparation-counterclassifies-unknown-conflict-and-gap|light|plan_document'
    'medium-prepare-only-terminal-route|medium|plan_document'
    'large-prepare-only-terminal-route|large|plan_document'
)

feature_prep_expected_case_records() {
    printf '%s\n' "${FEATURE_PREP_EXPECTED_CASE_RECORDS[@]}"
}
