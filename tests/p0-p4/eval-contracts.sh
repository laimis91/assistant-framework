if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

eval_runner="$FRAMEWORK_DIR/tools/evals/run-framework-instruction-evals.sh"
eval_fixture="$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json"

write_machine_expectation_responses() {
    local output_dir="$1"
    local omit_case="${2:-}"
    local omit_required="${3:-}"
    local id
    local response_path
    local required

    while IFS= read -r id; do
        response_path="$output_dir/$id.txt"
        {
            printf 'Local grading response for %s.\n' "$id"
            while IFS= read -r required; do
                if [[ "$id" == "$omit_case" && "$required" == "$omit_required" ]]; then
                    continue
                fi
                printf '%s\n' "$required"
            done < <(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .machine_expectations.required_substrings[]' "$eval_fixture")
        } >"$response_path"
    done < <(jq -r '.cases[].id' "$eval_fixture")
}

test_start "docs eval fixture JSON has required behavior cases"
if jq -e '
    .schema_version == "1.0"
    and (.cases | type == "array")
    and ([.cases[].id] | contains([
      "ambiguous-prompt-clarify-or-default-deterministically",
      "compaction-resume-reads-task-state-first",
      "codex-role-constraints-without-subagentstart",
      "executable-task-packet-before-build",
      "medium-feature-plans-before-build",
      "per-component-verification-before-advancing",
      "review-loop-continues-after-findings",
      "small-fix-stays-lightweight",
      "spec-review-not-replaced-by-quality-review",
      "tdd-red-before-green-handoff",
      "worker-status-packet-required"
    ]))
    and (.cases | length >= 11)
' "$eval_fixture" >/dev/null; then
    pass
else
    fail "eval JSON is invalid or missing required behavior cases"
fi

test_start "docs eval fixture JSON includes six new case areas"
if jq -e '
    def case_category($id; $category):
      any(.cases[]; .id == $id and .category == $category);
    case_category("tdd-red-before-green-handoff"; "tdd_handoff")
    and case_category("executable-task-packet-before-build"; "handoff_contracts")
    and case_category("per-component-verification-before-advancing"; "component_verification")
    and case_category("spec-review-not-replaced-by-quality-review"; "review_gates")
    and case_category("worker-status-packet-required"; "subagent_handoffs")
    and case_category("codex-role-constraints-without-subagentstart"; "role_constraints")
' "$eval_fixture" >/dev/null; then
    pass
else
    fail "eval JSON missing one or more new case id/category pairs"
fi

test_start "docs eval fixture JSON has machine expectation arrays for every case"
if jq -e '
    all(.cases[];
      (.machine_expectations | type == "object")
      and (.machine_expectations.required_substrings | type == "array")
      and (.machine_expectations.forbidden_substrings | type == "array")
      and (.machine_expectations.required_substrings | length > 0)
      and (.machine_expectations.forbidden_substrings | length > 0)
      and all(.machine_expectations.required_substrings[]; type == "string" and length > 0)
      and all(.machine_expectations.forbidden_substrings[]; type == "string" and length > 0)
    )
' "$eval_fixture" >/dev/null; then
    pass
else
    fail "eval JSON missing machine_expectations required/forbidden string arrays"
fi

test_start "docs eval README lists new behavior areas"
missing_eval_readme_terms=()
for term in \
    "TDD RED-before-GREEN handoff behavior" \
    "executable task packet requirements before build" \
    "per-component verification before advancing" \
    "separate spec review and quality review gates" \
    "structured worker status packets from subagents" \
    "Codex role constraints without SubagentStart reinforcement"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/docs/evals/README.md"; then
        missing_eval_readme_terms+=("$term")
    fi
done
if [[ "${#missing_eval_readme_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "docs/evals/README.md missing new behavior areas: ${missing_eval_readme_terms[*]}"
fi

test_start "docs eval runner exists and is executable"
if [[ -x "$eval_runner" ]]; then
    pass
else
    fail "eval runner is missing or not executable: $eval_runner"
fi

test_start "docs eval runner validates fixture"
if "$eval_runner" --validate-fixture >/dev/null; then
    pass
else
    fail "eval runner --validate-fixture failed"
fi

test_start "docs eval runner rejects empty machine expectation arrays"
empty_expectation_failure=0
for expectation_field in required_substrings forbidden_substrings; do
    empty_fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/framework-eval-empty-array.XXXXXX")"
    empty_fixture_err="$(mktemp "${TMPDIR:-/tmp}/framework-eval-empty-array-err.XXXXXX")"
    p0p4_register_cleanup "$empty_fixture_root" "$empty_fixture_err"
    mkdir -p "$empty_fixture_root/tools/evals" "$empty_fixture_root/docs/evals"
    cp "$eval_runner" "$empty_fixture_root/tools/evals/run-framework-instruction-evals.sh"
    chmod +x "$empty_fixture_root/tools/evals/run-framework-instruction-evals.sh"
    jq --arg expectation_field "$expectation_field" '
        (.cases[] | select(.id == "small-fix-stays-lightweight") | .machine_expectations[$expectation_field]) = []
    ' "$eval_fixture" >"$empty_fixture_root/docs/evals/framework-instruction-cases.json"

    if "$empty_fixture_root/tools/evals/run-framework-instruction-evals.sh" --validate-fixture >/dev/null 2>"$empty_fixture_err"; then
        empty_expectation_failure=1
        break
    elif ! grep -Fq "machine_expectations.$expectation_field non-empty string array" "$empty_fixture_err"; then
        empty_expectation_failure=1
        break
    fi
done
if [[ "$empty_expectation_failure" -eq 0 ]]; then
    pass
else
    fail "eval runner --validate-fixture accepted or misreported an empty machine expectation array"
fi

test_start "docs eval runner lists all fixture cases"
case_count="$(jq '.cases | length' "$eval_fixture")"
list_output="$("$eval_runner" --list)"
list_count="$(printf '%s\n' "$list_output" | grep -c .)"
if [[ "$list_count" -eq "$case_count" ]] \
    && printf '%s\n' "$list_output" | grep -Fq $'small-fix-stays-lightweight\tworkflow_sizing\tSmall fix should stay lightweight' \
    && printf '%s\n' "$list_output" | grep -Fq $'codex-role-constraints-without-subagentstart\trole_constraints\tCodex should honor role constraints without SubagentStart'; then
    pass
else
    fail "eval runner --list did not include expected case rows"
fi

test_start "docs eval runner emits one prompt packet per case"
prompt_dir="$(mktemp -d "${TMPDIR:-/tmp}/framework-eval-prompts.XXXXXX")"
p0p4_register_cleanup "$prompt_dir"
if "$eval_runner" --emit-prompts "$prompt_dir" >/dev/null \
    && [[ "$(find "$prompt_dir" -type f -name '*.md' | wc -l | tr -d ' ')" -eq "$case_count" ]] \
    && grep -Fq "## Setup Context" "$prompt_dir/small-fix-stays-lightweight.md" \
    && grep -Fq "## Pass Criteria" "$prompt_dir/small-fix-stays-lightweight.md" \
    && grep -Fq "## Machine Expectations" "$prompt_dir/small-fix-stays-lightweight.md" \
    && grep -Fq "### Required Substrings" "$prompt_dir/small-fix-stays-lightweight.md" \
    && grep -Fq "### Forbidden Substrings" "$prompt_dir/small-fix-stays-lightweight.md" \
    && grep -Fq "Fix the typo 'teh' to 'the' in docs/usage.md. Keep it simple." "$prompt_dir/small-fix-stays-lightweight.md"; then
    pass
else
    fail "eval runner --emit-prompts did not create recognizable prompt packets"
fi

test_start "docs eval runner fails cleanly for missing response directory"
missing_response_dir="${TMPDIR:-/tmp}/framework-eval-missing-$$"
response_missing_err="$(mktemp "${TMPDIR:-/tmp}/framework-eval-missing-err.XXXXXX")"
p0p4_register_cleanup "$response_missing_err"
if "$eval_runner" --responses "$missing_response_dir" >/dev/null 2>"$response_missing_err"; then
    fail "eval runner --responses unexpectedly passed for a missing directory"
elif grep -Fq "Response directory does not exist" "$response_missing_err"; then
    pass
else
    fail "eval runner --responses missing-directory error was not clear"
fi

test_start "docs eval runner fails for empty or missing response files"
response_dir="$(mktemp -d "${TMPDIR:-/tmp}/framework-eval-responses.XXXXXX")"
response_output="$(mktemp "${TMPDIR:-/tmp}/framework-eval-response-output.XXXXXX")"
p0p4_register_cleanup "$response_dir" "$response_output"
: >"$response_dir/small-fix-stays-lightweight.txt"
if "$eval_runner" --responses "$response_dir" >"$response_output" 2>&1; then
    fail "eval runner --responses unexpectedly passed with empty or missing responses"
elif grep -Fq "Heuristic/local grading only" "$response_output" \
    && grep -Fq $'FAIL\tsmall-fix-stays-lightweight' "$response_output" \
    && grep -Fq "empty response file" "$response_output" \
    && grep -Fq "missing response file" "$response_output"; then
    pass
else
    fail "eval runner --responses did not report empty and missing responses clearly"
fi

test_start "docs eval runner fails for missing required substrings"
missing_required_dir="$(mktemp -d "${TMPDIR:-/tmp}/framework-eval-missing-required.XXXXXX")"
missing_required_output="$(mktemp "${TMPDIR:-/tmp}/framework-eval-missing-required-output.XXXXXX")"
p0p4_register_cleanup "$missing_required_dir" "$missing_required_output"
omitted_required="$(jq -r '.cases[] | select(.id == "small-fix-stays-lightweight") | .machine_expectations.required_substrings[0]' "$eval_fixture")"
write_machine_expectation_responses "$missing_required_dir" "small-fix-stays-lightweight" "$omitted_required"
if "$eval_runner" --responses "$missing_required_dir" >"$missing_required_output" 2>&1; then
    fail "eval runner --responses unexpectedly passed with a missing required substring"
elif grep -Fq $'FAIL\tsmall-fix-stays-lightweight' "$missing_required_output" \
    && grep -Fq "missing required substring" "$missing_required_output" \
    && grep -Fq "missing_required_substrings=" "$missing_required_output"; then
    pass
else
    fail "eval runner --responses did not report missing required substrings clearly"
fi

test_start "docs eval runner fails for forbidden substrings"
forbidden_dir="$(mktemp -d "${TMPDIR:-/tmp}/framework-eval-forbidden.XXXXXX")"
forbidden_output="$(mktemp "${TMPDIR:-/tmp}/framework-eval-forbidden-output.XXXXXX")"
p0p4_register_cleanup "$forbidden_dir" "$forbidden_output"
forbidden_substring="$(jq -r '.cases[] | select(.id == "small-fix-stays-lightweight") | .machine_expectations.forbidden_substrings[0]' "$eval_fixture")"
write_machine_expectation_responses "$forbidden_dir"
printf '%s\n' "$forbidden_substring" >>"$forbidden_dir/small-fix-stays-lightweight.txt"
if "$eval_runner" --responses "$forbidden_dir" >"$forbidden_output" 2>&1; then
    fail "eval runner --responses unexpectedly passed with a forbidden substring"
elif grep -Fq $'FAIL\tsmall-fix-stays-lightweight' "$forbidden_output" \
    && grep -Fq "forbidden substring hit" "$forbidden_output" \
    && grep -Fq "forbidden_substring_hits=" "$forbidden_output"; then
    pass
else
    fail "eval runner --responses did not report forbidden substrings clearly"
fi

test_start "docs eval runner passes generated responses with all required substrings"
passing_response_dir="$(mktemp -d "${TMPDIR:-/tmp}/framework-eval-passing.XXXXXX")"
passing_response_output="$(mktemp "${TMPDIR:-/tmp}/framework-eval-passing-output.XXXXXX")"
p0p4_register_cleanup "$passing_response_dir" "$passing_response_output"
write_machine_expectation_responses "$passing_response_dir"
if "$eval_runner" --responses "$passing_response_dir" >"$passing_response_output" 2>&1 \
    && grep -Fq "Summary: total=$case_count passed=$case_count failed=0" "$passing_response_output" \
    && grep -Fq "missing_required_substrings=0" "$passing_response_output" \
    && grep -Fq "forbidden_substring_hits=0" "$passing_response_output"; then
    pass
else
    fail "eval runner --responses did not pass generated all-required response set"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
