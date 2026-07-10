if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

eval_runner="$FRAMEWORK_DIR/tools/evals/run-framework-instruction-evals.sh"
eval_fixture="$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json"
trace_schema="$FRAMEWORK_DIR/docs/evals/framework-instruction-trace-result.schema.json"

write_completed_trace() {
    local path="$1"
    local run_id="$2"
    local case_id="$3"
    local variant="$4"
    local input_tokens="$5"
    local output_tokens="$6"
    local latency_ms="$7"
    local tool_calls="$8"
    local unnecessary_questions="$9"
    local time_to_first_useful_action_ms="${10}"
    local rework_count="${11}"
    local acceptance_passed="${12}"

    jq -n \
        --arg run_id "$run_id" \
        --arg case_id "$case_id" \
        --arg variant "$variant" \
        --argjson input_tokens "$input_tokens" \
        --argjson output_tokens "$output_tokens" \
        --argjson latency_ms "$latency_ms" \
        --argjson tool_calls "$tool_calls" \
        --argjson unnecessary_questions "$unnecessary_questions" \
        --argjson time_to_first_useful_action_ms "$time_to_first_useful_action_ms" \
        --argjson rework_count "$rework_count" \
        --argjson acceptance_passed "$acceptance_passed" '
        {
          schema_version: "1.0",
          run_id: $run_id,
          case_id: $case_id,
          model: "gpt-5.6-sol",
          variant: $variant,
          status: "completed",
          metrics: {
            input_tokens: $input_tokens,
            output_tokens: $output_tokens,
            latency_ms: $latency_ms,
            tool_calls: $tool_calls,
            unnecessary_questions: $unnecessary_questions,
            time_to_first_useful_action_ms: $time_to_first_useful_action_ms,
            rework_count: $rework_count,
            acceptance_passed: $acceptance_passed
          }
        }
    ' >"$path"
}

write_adapter_unavailable_trace() {
    local path="$1"
    local run_id="$2"
    local case_id="$3"
    local variant="$4"
    local message="$5"

    jq -n \
        --arg run_id "$run_id" \
        --arg case_id "$case_id" \
        --arg variant "$variant" \
        --arg message "$message" '
        {
          schema_version: "1.0",
          run_id: $run_id,
          case_id: $case_id,
          model: "gpt-5.6-sol",
          variant: $variant,
          status: "adapter_unavailable",
          error: {
            code: "adapter_not_configured",
            message: $message
          }
        }
    ' >"$path"
}

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
      "clear-medium-task-zero-clarification-questions",
      "ambiguous-risky-task-blocks-before-plan",
      "executable-task-packet-before-build",
      "medium-feature-plans-before-build",
      "per-slice-verification-before-advancing",
      "review-loop-continues-after-findings",
      "small-fix-stays-lightweight",
      "spec-review-not-replaced-by-quality-review",
      "subagent-authorization-denied-direct-fallback",
      "tdd-red-before-green-handoff",
      "worker-status-packet-required"
    ]))
    and (.cases | length >= 14)
' "$eval_fixture" >/dev/null; then
    pass
else
    fail "eval JSON is invalid or missing required behavior cases"
fi

test_start "docs eval fixture JSON includes seven new case areas"
if jq -e '
    def case_category($id; $category):
      any(.cases[]; .id == $id and .category == $category);
    case_category("tdd-red-before-green-handoff"; "tdd_handoff")
    and case_category("executable-task-packet-before-build"; "handoff_contracts")
    and case_category("per-slice-verification-before-advancing"; "slice_verification")
    and case_category("spec-review-not-replaced-by-quality-review"; "review_gates")
    and case_category("worker-status-packet-required"; "subagent_handoffs")
    and case_category("subagent-authorization-denied-direct-fallback"; "subagent_authorization")
    and case_category("codex-role-constraints-without-subagentstart"; "role_constraints")
' "$eval_fixture" >/dev/null; then
    pass
else
    fail "eval JSON missing one or more new case id/category pairs"
fi

test_start "docs eval fixture JSON includes clarification admissibility cases"
if jq -e '
    def case_category($id; $category):
      any(.cases[]; .id == $id and .category == $category);
    case_category("clear-medium-task-zero-clarification-questions"; "clarification_admissibility")
    and case_category("ambiguous-risky-task-blocks-before-plan"; "clarification_admissibility")
' "$eval_fixture" >/dev/null; then
    pass
else
    fail "eval JSON missing clarification admissibility case id/category pairs"
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
    "per-slice verification before advancing" \
    "separate spec review and quality review gates" \
    "structured worker status packets from subagents" \
    "subagent authorization denial direct fallback" \
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

test_start "trace result schema is versioned and distinguishes count metrics from durations"
if [[ -f "$trace_schema" ]] \
    && jq -e '
        . as $schema
        | .type == "object"
        and .additionalProperties == false
        and (.["$schema"] | type == "string" and startswith("https://json-schema.org/"))
        and (.properties.metrics.required | contains([
          "input_tokens",
          "output_tokens",
          "latency_ms",
          "tool_calls",
          "unnecessary_questions",
          "time_to_first_useful_action_ms",
          "rework_count",
          "acceptance_passed"
        ]))
        and (.properties.error.required | contains(["code", "message"]))
        and (.required | contains([
          "schema_version",
          "run_id",
          "case_id",
          "model",
          "variant",
          "status"
        ]))
        and .properties.schema_version.const == "1.0"
        and (.properties.status.enum | contains(["completed", "adapter_unavailable"]))
        and all([
          "input_tokens",
          "output_tokens",
          "tool_calls",
          "unnecessary_questions",
          "rework_count"
        ][];
          . as $metric
          | $schema.properties.metrics.properties[$metric].type == "integer"
          and $schema.properties.metrics.properties[$metric].minimum == 0
        )
        and all([
          "latency_ms",
          "time_to_first_useful_action_ms"
        ][];
          . as $metric
          | $schema.properties.metrics.properties[$metric].type == "number"
          and $schema.properties.metrics.properties[$metric].minimum == 0
        )
    ' "$trace_schema" >/dev/null; then
    pass
else
    fail "versioned trace schema is missing identity/status fields or integer count metric types"
fi

test_start "eval fixture and README expose the trace validation and comparison contract"
if jq -e '
    .trace_results.schema == "framework-instruction-trace-result.schema.json"
    and (.trace_results.statuses | contains(["completed", "adapter_unavailable"]))
    and (.trace_results.variants | contains(["baseline", "candidate"]))
' "$eval_fixture" >/dev/null \
    && grep -Fq -- "--validate-traces DIR" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq -- "--compare-traces DIR" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq -- "adapter_unavailable" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq -- "not counted as an acceptance failure" "$FRAMEWORK_DIR/docs/evals/README.md"; then
    pass
else
    fail "eval fixture or README is missing the trace schema, modes, variants, or unavailable-run semantics"
fi

test_start "eval runner help keeps legacy modes and advertises trace modes"
trace_help_output="$("$eval_runner" --help)"
if printf '%s\n' "$trace_help_output" | grep -Fq -- "--validate-fixture" \
    && printf '%s\n' "$trace_help_output" | grep -Fq -- "--list" \
    && printf '%s\n' "$trace_help_output" | grep -Fq -- "--emit-prompts DIR" \
    && printf '%s\n' "$trace_help_output" | grep -Fq -- "--responses DIR" \
    && printf '%s\n' "$trace_help_output" | grep -Fq -- "--validate-traces DIR" \
    && printf '%s\n' "$trace_help_output" | grep -Fq -- "--compare-traces DIR"; then
    pass
else
    fail "eval runner help regressed a legacy mode or is missing a trace mode"
fi

trace_valid_dir="$(mktemp -d "${TMPDIR:-/tmp}/framework-eval-valid-traces.XXXXXX")"
trace_invalid_dir="$(mktemp -d "${TMPDIR:-/tmp}/framework-eval-invalid-traces.XXXXXX")"
trace_compare_dir="$(mktemp -d "${TMPDIR:-/tmp}/framework-eval-compare-traces.XXXXXX")"
trace_output="$(mktemp "${TMPDIR:-/tmp}/framework-eval-trace-output.XXXXXX")"
trace_error="$(mktemp "${TMPDIR:-/tmp}/framework-eval-trace-error.XXXXXX")"
trace_compare_output="$(mktemp "${TMPDIR:-/tmp}/framework-eval-compare-output.XXXXXX")"
trace_compare_output_repeat="$(mktemp "${TMPDIR:-/tmp}/framework-eval-compare-output-repeat.XXXXXX")"
p0p4_register_cleanup \
    "$trace_valid_dir" \
    "$trace_invalid_dir" \
    "$trace_compare_dir" \
    "$trace_output" \
    "$trace_error" \
    "$trace_compare_output" \
    "$trace_compare_output_repeat"

write_completed_trace \
    "$trace_valid_dir/completed.json" \
    "run-valid-completed" \
    "small-fix-stays-lightweight" \
    "baseline" \
    1000 100 1200 2 0 400 0 true
write_adapter_unavailable_trace \
    "$trace_valid_dir/unavailable.json" \
    "run-valid-unavailable" \
    "small-fix-stays-lightweight" \
    "candidate" \
    "The local adapter is not configured."

test_start "eval runner validates completed and adapter-unavailable trace results"
if "$eval_runner" --validate-traces "$trace_valid_dir" >"$trace_output" 2>"$trace_error"; then
    pass
else
    fail "eval runner rejected valid completed or adapter_unavailable trace results"
fi

test_start "eval runner rejects a trace missing required run identity with a clear error"
rm -f "$trace_invalid_dir"/*.json
jq 'del(.model)' "$trace_valid_dir/completed.json" >"$trace_invalid_dir/missing-model.json"
if "$eval_runner" --validate-traces "$trace_invalid_dir" >"$trace_output" 2>"$trace_error"; then
    fail "eval runner accepted a trace missing model"
elif grep -Fq "missing-model.json" "$trace_error" \
    && grep -Fqi "model" "$trace_error"; then
    pass
else
    fail "eval runner missing-model validation error did not identify the file and field"
fi

test_start "trace validation rejects case IDs absent from the eval fixture"
rm -f "$trace_invalid_dir"/*.json
jq '.case_id = "not-a-declared-framework-eval-case"' \
    "$trace_valid_dir/completed.json" >"$trace_invalid_dir/unknown-case-id.json"
if "$eval_runner" --validate-traces "$trace_invalid_dir" >"$trace_output" 2>"$trace_error"; then
    fail "eval runner accepted a case_id absent from docs/evals/framework-instruction-cases.json"
elif grep -Fq "unknown-case-id.json" "$trace_error" \
    && grep -Fq "not-a-declared-framework-eval-case" "$trace_error"; then
    pass
else
    fail "unknown-case validation error did not identify the trace file and undeclared case_id"
fi

test_start "completed traces require every numeric metric and acceptance result"
metric_contract_failure=0
for metric in \
    input_tokens \
    output_tokens \
    latency_ms \
    tool_calls \
    unnecessary_questions \
    time_to_first_useful_action_ms \
    rework_count \
    acceptance_passed; do
    rm -f "$trace_invalid_dir"/*.json
    jq --arg metric "$metric" 'del(.metrics[$metric])' \
        "$trace_valid_dir/completed.json" >"$trace_invalid_dir/missing-$metric.json"
    if "$eval_runner" --validate-traces "$trace_invalid_dir" >"$trace_output" 2>"$trace_error" \
        || ! grep -Fq "missing-$metric.json" "$trace_error" \
        || ! grep -Fqi "$metric" "$trace_error"; then
        metric_contract_failure=1
        break
    fi
done
if [[ "$metric_contract_failure" -eq 0 ]]; then
    pass
else
    fail "completed-trace validation accepted or misreported a missing required metric: $metric"
fi

test_start "completed traces reject invalid metric types with a clear error"
rm -f "$trace_invalid_dir"/*.json
jq '.metrics.input_tokens = "one thousand"' \
    "$trace_valid_dir/completed.json" >"$trace_invalid_dir/invalid-input-tokens.json"
if "$eval_runner" --validate-traces "$trace_invalid_dir" >"$trace_output" 2>"$trace_error"; then
    fail "eval runner accepted a non-numeric input_tokens metric"
elif grep -Fq "invalid-input-tokens.json" "$trace_error" \
    && grep -Fqi "input_tokens" "$trace_error"; then
    pass
else
    fail "completed-trace validation error did not identify invalid input_tokens"
fi

test_start "completed traces reject fractional values for discrete count metrics"
discrete_metric_contract_failure=0
for metric in \
    input_tokens \
    output_tokens \
    tool_calls \
    unnecessary_questions \
    rework_count; do
    rm -f "$trace_invalid_dir"/*.json
    jq --arg metric "$metric" '.metrics[$metric] = 1.5' \
        "$trace_valid_dir/completed.json" >"$trace_invalid_dir/fractional-$metric.json"
    if "$eval_runner" --validate-traces "$trace_invalid_dir" >"$trace_output" 2>"$trace_error" \
        || ! grep -Fq "fractional-$metric.json" "$trace_error" \
        || ! grep -Fqi "$metric" "$trace_error"; then
        discrete_metric_contract_failure=1
        break
    fi
done
if [[ "$discrete_metric_contract_failure" -eq 0 ]]; then
    pass
else
    fail "completed-trace validation accepted or misreported fractional discrete metric: $metric"
fi

test_start "adapter-unavailable traces require a structured error"
error_contract_failure=0
for error_field in code message; do
    rm -f "$trace_invalid_dir"/*.json
    jq --arg error_field "$error_field" 'del(.error[$error_field])' \
        "$trace_valid_dir/unavailable.json" >"$trace_invalid_dir/missing-error-$error_field.json"
    if "$eval_runner" --validate-traces "$trace_invalid_dir" >"$trace_output" 2>"$trace_error" \
        || ! grep -Fq "missing-error-$error_field.json" "$trace_error" \
        || ! grep -Fqi "error.$error_field" "$trace_error"; then
        error_contract_failure=1
        break
    fi
done
if [[ "$error_contract_failure" -eq 0 ]]; then
    pass
else
    fail "adapter-unavailable validation accepted or misreported missing error.$error_field"
fi

test_start "trace validation rejects undeclared prompt or secret fields"
rm -f "$trace_invalid_dir"/*.json
jq '.raw_prompt = "raw prompt body" | .api_key = "secret-fixture-value"' \
    "$trace_valid_dir/completed.json" >"$trace_invalid_dir/raw-fields.json"
if "$eval_runner" --validate-traces "$trace_invalid_dir" >"$trace_output" 2>"$trace_error"; then
    fail "eval runner accepted undeclared raw prompt or secret fields"
elif grep -Fq "raw-fields.json" "$trace_error" \
    && grep -Eqi "raw_prompt|api_key|additional" "$trace_error"; then
    pass
else
    fail "trace validation did not clearly reject undeclared prompt/secret fields"
fi

test_start "trace validation rejects duplicate run IDs within one import directory"
rm -f "$trace_invalid_dir"/*.json
cp "$trace_valid_dir/completed.json" "$trace_invalid_dir/duplicate-run-a.json"
jq '.variant = "candidate"' \
    "$trace_valid_dir/completed.json" >"$trace_invalid_dir/duplicate-run-b.json"
if "$eval_runner" --validate-traces "$trace_invalid_dir" >"$trace_output" 2>"$trace_error"; then
    fail "eval runner accepted duplicate run_id values in one trace directory"
elif grep -Fq "run-valid-completed" "$trace_error" \
    && grep -Eqi 'duplicate.*run_id|run_id.*duplicate' "$trace_error"; then
    pass
else
    fail "duplicate-run validation error did not identify the duplicated run_id"
fi

write_completed_trace "$trace_compare_dir/a-baseline.json" "run-a-baseline" "small-fix-stays-lightweight" "baseline" 1000 100 1000 2 0 500 1 false
write_completed_trace "$trace_compare_dir/a-candidate.json" "run-a-candidate" "small-fix-stays-lightweight" "candidate" 800 80 700 1 0 300 0 true
write_completed_trace "$trace_compare_dir/b-baseline.json" "run-b-baseline" "medium-feature-plans-before-build" "baseline" 2000 200 2000 4 0 1000 2 true
write_completed_trace "$trace_compare_dir/b-candidate.json" "run-b-candidate" "medium-feature-plans-before-build" "candidate" 1500 150 1600 3 0 800 1 true
write_adapter_unavailable_trace \
    "$trace_compare_dir/c-baseline.json" \
    "run-c-baseline" \
    "review-loop-continues-after-findings" \
    "baseline" \
    "secret-fixture-value raw prompt body must not enter aggregate output"
write_adapter_unavailable_trace \
    "$trace_compare_dir/c-candidate.json" \
    "run-c-candidate" \
    "review-loop-continues-after-findings" \
    "candidate" \
    "Adapter unavailable for the candidate."

test_start "trace comparison emits deterministic paired JSON summaries and deltas"
if "$eval_runner" --compare-traces "$trace_compare_dir" >"$trace_compare_output" 2>"$trace_error" \
    && "$eval_runner" --compare-traces "$trace_compare_dir" >"$trace_compare_output_repeat" 2>"$trace_error" \
    && cmp -s "$trace_compare_output" "$trace_compare_output_repeat" \
    && jq -e '
        .schema_version == "1.0"
        and .baseline_variant == "baseline"
        and .candidate_variant == "candidate"
        and .variants.baseline.completed_runs == 2
        and .variants.candidate.completed_runs == 2
        and .variants.baseline.adapter_unavailable_runs == 1
        and .variants.candidate.adapter_unavailable_runs == 1
        and .variants.baseline.acceptance == {passed: 1, failed: 1, rate: 0.5}
        and .variants.candidate.acceptance == {passed: 2, failed: 0, rate: 1}
        and .variants.baseline.metrics.input_tokens.mean == 1500
        and .variants.candidate.metrics.input_tokens.mean == 1150
        and .deltas.input_tokens.absolute == -350
        and ((.deltas.input_tokens.percent + 23.3333333333) | fabs < 0.0001)
        and .deltas.unnecessary_questions.absolute == 0
        and .deltas.unnecessary_questions.percent == null
        and .deltas.acceptance_rate.absolute == 0.5
        and .deltas.acceptance_rate.percent == 100
        and (.adapter_unavailable_runs | length == 2)
        and all(.adapter_unavailable_runs[];
          (.run_id | type == "string")
          and (.case_id | type == "string")
          and (.model | type == "string")
          and (.variant == "baseline" or .variant == "candidate")
          and .error_code == "adapter_not_configured"
          and (has("error_message") | not)
        )
    ' "$trace_compare_output" >/dev/null \
    && ! grep -Fq "secret-fixture-value" "$trace_compare_output" \
    && ! grep -Fq "raw prompt body" "$trace_compare_output"; then
    pass
else
    fail "trace comparison was non-deterministic or missing paired summaries, deltas, acceptance rates, unavailable separation, or redaction"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
