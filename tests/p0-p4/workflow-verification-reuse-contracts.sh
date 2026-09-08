if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"
source "$FRAMEWORK_DIR/tests/p0-p4/lib/verification-reuse-response-fixtures.sh"

workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"
fixture="$workflow_dir/evals/cases.json"
worker_protocol="$workflow_dir/references/build-worker-protocol.md"
phases="$workflow_dir/references/phases.md"
output_contract="$workflow_dir/contracts/output.yaml"
runner="$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh"
matrix_case="verification-reuse-current-scenario-matrix"
review_case="verification-reuse-preserves-independent-review"
matrix_ids=(unchanged-complete unrelated-doc-input-boundary changed-production changed-tests changed-config changed-dependency changed-argv changed-cwd changed-toolchain changed-environment prior-failed prior-partial prior-skipped unknown-basis explicit-fresh-run mutable-external-state new-integration-coverage post-fix-source)
matrix_actions=(reuse reuse rerun rerun rerun rerun rerun rerun rerun rerun rerun rerun rerun rerun rerun rerun rerun rerun)
review_ids=(spec-review-required independent-code-review-required final-review-snapshot-current)

normalized_contains() { tr -s '[:space:]' ' ' <"$1" | grep -Fq "$2"; }

test_start "current verification reuse keeps conservative invalidation and review boundaries"
missing=()
for term in "exact argv and cwd" "complete passing result/log" "source/test/config/dependency" "toolchain and relevant non-secret environment" "covered acceptance obligations" "Unknown identity, freshness, or coverage requires rerun" "mutable external state" "user explicitly requests a fresh run" "source changes after a fix"; do normalized_contains "$worker_protocol" "$term" || missing+=("protocol:$term"); done
for term in "references/build-worker-protocol.md" "reuse only full matching identity/coverage evidence" "new integration coverage" "final current validation" "independent code review" "final review snapshot"; do normalized_contains "$phases" "$term" || missing+=("phases:$term"); done
for term in "original run and current comparison" "does not claim a newly executed verification" "no new mandatory"; do normalized_contains "$output_contract" "$term" || missing+=("contract:$term"); done
if [[ ${#missing[@]} -eq 0 ]]; then pass; else fail "missing reuse controls: ${missing[*]}"; fi

expected_matrix="$(for index in "${!matrix_ids[@]}"; do jq -n --arg id "${matrix_ids[$index]}" --arg action "${matrix_actions[$index]}" '{id:$id,action:$action}'; done | jq -s .)"
expected_review="$(for id in "${review_ids[@]}"; do jq -n --arg id "$id" '{id:$id,action:"reuse"}'; done | jq -s .)"
review_ids_json="$(printf '%s\n' "${review_ids[@]}" | jq -R . | jq -s .)"

test_start "verification reuse fixtures disclose external decision records and complete scenario coverage"
if jq -e --arg matrix_case "$matrix_case" --arg review_case "$review_case" --argjson matrix "$expected_matrix" --argjson review "$expected_review" '
  .provider_neutral == true and .model_specific_api_calls == false
  and (.cases[] | select(.id == $matrix_case)
       | (.prompt | contains("top-level decisions array") and contains("unchanged-complete") and contains("post-fix-source") and (contains("=reuse") or contains("=rerun") | not))
       and (has("decision_expectations") | not)
       and any(.machine_expectations.structured_json_assertions[]; .operator == "array_object_values_exact" and .path == ["decisions"] and .fields == ["id", "action"] and .expected_objects == $matrix)
       and any(.machine_expectations.structured_json_assertions[]; .operator == "array_field_values_exact" and .path == ["decisions"] and .field == "independent_review_status" and .expected_values == [range(0; $matrix | length) | "required"])
       and ([.machine_expectations.structured_json_assertions[] | select(.operator == "array_items_nonempty_fields" and .path == ["decisions"] and .fields == ["id", "action", "original_run_ref", "current_comparison_ref", "independent_review_status"])] | length == 1))
  and (.cases[] | select(.id == $review_case)
       | (.prompt | contains("top-level decisions array") and contains("independent-code-review-required") and (contains("action=reuse") | not))
       and (has("decision_expectations") | not)
       and any(.machine_expectations.structured_json_assertions[]; .operator == "array_object_values_exact" and .path == ["decisions"] and .fields == ["id", "action"] and .expected_objects == $review)
       and any(.machine_expectations.structured_json_assertions[]; .operator == "array_field_values_exact" and .path == ["decisions"] and .field == "independent_review_status" and .expected_values == ["required", "required", "required"])
       and ([.machine_expectations.structured_json_assertions[] | select(.operator == "array_items_nonempty_fields" and .path == ["decisions"] and .fields == ["id", "action", "original_run_ref", "current_comparison_ref", "independent_review_status"])] | length == 1))
' "$fixture" >/dev/null; then pass; else fail "fixtures do not use the canonical structured decision oracle"; fi

write_external_contract() {
    local path="$1"
    mkdir -p "$path/contracts"
    printf '%s\n' 'artifacts:' '  - name: decisions' '    type: object[]' '    required: true' '    object_fields:' '      - name: id' '        type: string' '        required: true' '      - name: action' '        type: enum' '        required: true' '        enum_values: [reuse, rerun]' '      - name: original_run_ref' '        type: string' '        required: true' '      - name: current_comparison_ref' '        type: string' '        required: true' '      - name: independent_review_status' '        type: enum' '        required: true' '        enum_values: [required]' >"$path/contracts/output.yaml"
}

write_response() {
    local response="$1" ids="$2" actions="$3" action_index="$4" action_override="$5" basis="$6"
    jq -n --argjson ids "$ids" --argjson actions "$actions" --argjson action_index "$action_index" --arg action_override "$action_override" --arg basis "$basis" '
      def record($index): {id:$ids[$index],action:(if $index == $action_index then $action_override else $actions[$index] end),original_run_ref:(if $basis == "missing-original" then null else "run/" + $ids[$index] end),current_comparison_ref:(if $basis == "missing-current" then null else "comparison/" + $ids[$index] end),independent_review_status:"required"} | with_entries(select(.value != null));
      {decisions:[range(0; $ids | length) as $index | record($index)]}
    ' >"$response"
}

prepare_oracle_fixture() {
    local path="$1"
    jq --arg matrix_case "$matrix_case" --arg review_case "$review_case" '
      .skill = "external-verification-fixture"
      | .cases = [.cases[] | select(.id == $matrix_case or .id == $review_case)]
    ' "$fixture" >"$path/evals/cases.json"
}

test_start "canonical decision oracle accepts the full matrix and rejects flipped action or missing basis"
root="$(mktemp -d "${TMPDIR:-/tmp}/workflow-verification-reuse.XXXXXX")"
p0p4_register_cleanup "$root"
skill="$root/external-verification-fixture"
responses="$root/responses"
mkdir -p "$skill/evals" "$responses/external-verification-fixture"
printf '%s\n' '---' 'name: external-verification-fixture' 'description: "Temporary external decision fixture."' '---' >"$skill/SKILL.md"
write_external_contract "$skill"
failures=()
matrix_ids_json="$(printf '%s\n' "${matrix_ids[@]}" | jq -R . | jq -s .)"
matrix_actions_json="$(printf '%s\n' "${matrix_actions[@]}" | jq -R . | jq -s .)"
review_actions='["reuse","reuse","reuse"]'
prepare_oracle_fixture "$skill"

grade_case() {
    local case_id="$1" ids="$2" actions="$3" index="$4" action_override="$5" basis="$6" label="$7"
    local response="$responses/external-verification-fixture/$case_id.txt"
    write_response "$response" "$ids" "$actions" "$index" "$action_override" "$basis"
    if "$runner" --responses "$responses" --skill "$skill" --case "$case_id" >"$root/$label.out" 2>&1; then
        return 0
    fi
    return 1
}

if ! grade_case "$matrix_case" "$matrix_ids_json" "$matrix_actions_json" 0 reuse complete matrix-positive; then failures+=("full matrix positive"); fi
if grade_case "$matrix_case" "$matrix_ids_json" "$matrix_actions_json" 2 reuse complete matrix-flipped-action; then failures+=("flipped matrix action accepted"); fi
if grade_case "$matrix_case" "$matrix_ids_json" "$matrix_actions_json" 0 reuse missing-original matrix-missing-basis; then failures+=("missing matrix basis accepted"); fi
if ! grade_case "$review_case" "$review_ids_json" "$review_actions" 0 reuse complete review-positive; then failures+=("review positive"); fi
if [[ ${#failures[@]} -eq 0 ]]; then pass; else fail "external decision oracle failures: ${failures[*]}"; fi

test_start "shared response builders satisfy both canonical verification reuse cases"
mkdir -p "$responses/assistant-workflow"
failures=()
for case_id in "$matrix_case" "$review_case"; do
    write_verification_reuse_response "$case_id" "$responses/assistant-workflow/$case_id.txt" ""
    if ! "$runner" --responses "$responses" --skill assistant-workflow --case "$case_id" >"$root/$case_id.out" 2>&1; then
        failures+=("$case_id")
    fi
done
if [[ ${#failures[@]} -eq 0 ]]; then pass; else fail "shared response builder failed canonical grading: ${failures[*]}"; fi
p0p4_finish_suite "${BASH_SOURCE[0]}"
