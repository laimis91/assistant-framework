#!/usr/bin/env bash
# Test-only independent oracle for feature-preparation response-case records.
if [[ -n "${FEATURE_PREPARATION_CASE_ORACLE_LOADED:-}" ]]; then
    return 0
fi
readonly FEATURE_PREPARATION_CASE_ORACLE_LOADED=1

readonly FEATURE_PREP_EXPECTED_CASE_RECORDS=(
    'medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|none'
    'medium-prepare-only-readiness-reports-pending-requirement-map|medium|none'
    'medium-prepare-only-qa-request-routing|medium|none'
    'combined-preparation-and-implementation-routes-end-to-end|small|execution'
    'viewing-route-preserves-active-behavior|light|none'
    'feature-preparation-counterclassifies-unknown-conflict-and-gap|light|none'
    'medium-prepare-only-terminal-route|medium|none'
    'large-prepare-only-terminal-route|large|none'
    'medium-prepare-only-readiness-plan|medium|inline'
    'medium-prepare-only-not-applicable-readiness-plan|medium|inline'
    'large-strict-prepare-only-readiness-plan|large|inline'
)

feature_prep_expected_case_records() {
    printf '%s\n' "${FEATURE_PREP_EXPECTED_CASE_RECORDS[@]}"
}
