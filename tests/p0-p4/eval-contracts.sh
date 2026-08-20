if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

eval_runner="$FRAMEWORK_DIR/tools/evals/run-framework-instruction-evals.sh"
eval_fixture="$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json"
trace_schema="$FRAMEWORK_DIR/docs/evals/framework-instruction-trace-result.schema.json"
comparison_program="$FRAMEWORK_DIR/tools/evals/lib/framework-comparison.jq"
codex_eval_runner="$FRAMEWORK_DIR/tools/evals/run-codex-framework-evals.sh"
semantic_finalizer="$FRAMEWORK_DIR/tools/evals/finalize-workflow-kernel-review.sh"
semantic_verdict_schema="$FRAMEWORK_DIR/docs/evals/framework-semantic-review-verdict.schema.json"
promotion_decision_schema="$FRAMEWORK_DIR/docs/evals/framework-promotion-decision.schema.json"
workflow_kernel_manifest="$FRAMEWORK_DIR/docs/evals/variants/workflow-kernel-v1/manifest.json"
eval_readme="$FRAMEWORK_DIR/docs/evals/README.md"

test_sha256_stream() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
    else shasum -a 256 | awk '{print $1}'; fi
}

test_trace_set_sha256() {
    local directory="$1" inventory="" file name digest
    while IFS= read -r file; do
        name="$(basename "$file")"
        digest="$(test_sha256_stream <"$file")"
        inventory+="$name $digest"$'\n'
    done < <(find "$directory" -maxdepth 1 -type f -name '*.json' -print | LC_ALL=C sort)
    printf '%s' "$inventory" | test_sha256_stream
}

test_hash_directory() {
    local directory="$1" inventory="" file relative digest
    while IFS= read -r file; do
        relative="${file#"$directory"/}"
        digest="$(test_sha256_stream <"$file")"
        inventory+="$relative $digest"$'\n'
    done < <(find "$directory" -type f -print | LC_ALL=C sort)
    printf '%s' "$inventory" | test_sha256_stream
}

write_completed_trace() {
    local path="$1"
    local run_id="$2"
    local case_id="$3"
    local variant="$4"
    local input_tokens="$5"
    local output_tokens="$6"
    local latency_ms="$7"
    local tool_calls="$8"
    local question_mark_count_proxy="$9"
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
        --argjson question_mark_count_proxy "$question_mark_count_proxy" \
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
            question_mark_count_proxy: $question_mark_count_proxy,
            time_to_first_useful_action_ms: $time_to_first_useful_action_ms,
            rework_count: $rework_count,
            acceptance_passed: $acceptance_passed,
            acceptance_items_passed: (if $acceptance_passed then 1 else 0 end),
            acceptance_items_total: 1
          },
          provenance: {
            fixture_sha256: ("0" * 64),
            case_sha256: ("1" * 64),
            instruction_sha256: ("2" * 64),
            grader_sha256: ("3" * 64),
            cli_version: "codex-cli test",
            requested_model: "gpt-5.6-sol",
            runtime_model_attestation: "not_exposed_by_codex_jsonl",
            model_selection_evidence: "explicit_model_argument_only",
            requested_model_catalog_entry_sha256: null,
            codex_executable_sha256: null,
            adapter_version: "eval-contract-test"
          },
          execution: {
            exit_code: 0,
            raw_artifacts_retained: false,
            metric_methods: {
              time_to_first_useful_action_ms: "completion_latency_upper_bound",
              question_mark_count_proxy: "question_mark_count_proxy",
              rework_count: "additional_file_change_events_proxy"
            },
            verifier: {
              status: (if $acceptance_passed then "passed" else "failed" end),
              required_missing: (if $acceptance_passed then 0 else 1 end),
              missing_required_ids: (if $acceptance_passed then [] else ["required-001"] end),
              forbidden_hits: 0,
              forbidden_hit_ids: [],
              fail_signal_hits: 0,
              fail_signal_hit_ids: [],
              acceptance_items_passed: (if $acceptance_passed then 1 else 0 end),
              acceptance_items_total: 1,
              seeded_defects_detected: 0,
              seeded_defects_total: 0,
              seeded_defect_missed_ids: [],
              false_positive_marker_hits: 0,
              false_positive_marker_hit_ids: [],
              forbidden_command_hits: 0,
              workspace_status: "not_applicable",
              workspace_exit_code: 0,
              workspace_failure_ids: [],
              scope_deviations: 0
            }
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
      "codex-role-constraints-native",
      "clear-medium-task-zero-clarification-questions",
      "ambiguous-risky-task-blocks-before-plan",
      "executable-task-packet-before-build",
      "medium-feature-plans-before-build",
      "per-slice-verification-before-advancing",
      "review-loop-continues-after-findings",
      "small-fix-stays-lightweight",
      "spec-review-not-replaced-by-quality-review",
      "subagent-opt-out-uses-direct-fallback",
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
    and case_category("subagent-opt-out-uses-direct-fallback"; "subagent_delegation_trigger")
    and case_category("codex-role-constraints-native"; "role_constraints")
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
    "subagent opt-out direct fallback" \
    "Native Codex role constraints without extra runtime reinforcement"; do
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
    && printf '%s\n' "$list_output" | grep -Fq $'codex-role-constraints-native\trole_constraints\tCodex should honor native role constraints'; then
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
          "question_mark_count_proxy",
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
          "question_mark_count_proxy",
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

test_start "completed trace imports require provenance and execution evidence"
completed_evidence_contract_failure=0
for field in provenance execution; do
    rm -f "$trace_invalid_dir"/*.json
    jq --arg field "$field" 'del(.[$field])' \
        "$trace_valid_dir/completed.json" >"$trace_invalid_dir/missing-$field.json"
    if "$eval_runner" --validate-traces "$trace_invalid_dir" >"$trace_output" 2>"$trace_error" \
        || ! grep -Fq "missing-$field.json" "$trace_error" \
        || ! grep -Fqi "$field" "$trace_error"; then
        completed_evidence_contract_failure=1
        break
    fi
done
if [[ "$completed_evidence_contract_failure" -eq 0 ]]; then
    pass
else
    fail "completed trace import accepted missing $field evidence"
fi

test_start "completed trace execution evidence rejects nonzero not-run omitted and acceptance-mismatched states"
completed_execution_contract_failure=0
for mutation in nonzero not-run missing-methods missing-retention acceptance-mismatch; do
    rm -f "$trace_invalid_dir"/*.json
    case "$mutation" in
        nonzero)
            jq '.run_id = "run-invalid-nonzero" | .execution.exit_code = 9' \
                "$trace_valid_dir/completed.json" >"$trace_invalid_dir/$mutation.json"
            expected_error="exit_code must be 0"
            ;;
        not-run)
            jq '.run_id = "run-invalid-not-run" | .execution.verifier.status = "not_run"' \
                "$trace_valid_dir/completed.json" >"$trace_invalid_dir/$mutation.json"
            expected_error="verifier.status must be passed or failed"
            ;;
        missing-methods)
            jq '.run_id = "run-invalid-missing-methods" | del(.execution.metric_methods)' \
                "$trace_valid_dir/completed.json" >"$trace_invalid_dir/$mutation.json"
            expected_error="requires exact metric_methods"
            ;;
        missing-retention)
            jq '.run_id = "run-invalid-missing-retention" | del(.execution.raw_artifacts_retained)' \
                "$trace_valid_dir/completed.json" >"$trace_invalid_dir/$mutation.json"
            expected_error="requires raw_artifacts_retained=false"
            ;;
        acceptance-mismatch)
            jq '.run_id = "run-invalid-acceptance-mismatch" | .execution.verifier.status = "failed"' \
                "$trace_valid_dir/completed.json" >"$trace_invalid_dir/$mutation.json"
            expected_error="acceptance_passed does not match verifier.status"
            ;;
    esac
    if "$eval_runner" --validate-traces "$trace_invalid_dir" >"$trace_output" 2>"$trace_error" \
        || ! grep -Fq "$expected_error" "$trace_error"; then
        completed_execution_contract_failure=1
        break
    fi
done
if [[ "$completed_execution_contract_failure" -eq 0 ]]; then
    pass
else
    fail "completed trace validation accepted or misreported the $mutation state"
fi

test_start "completed traces require workspace diagnostics and acceptance item totals"
completed_verifier_field_failure=0
for path in \
    metrics.acceptance_items_passed \
    metrics.acceptance_items_total \
    execution.verifier.acceptance_items_passed \
    execution.verifier.acceptance_items_total \
    execution.verifier.workspace_failure_ids; do
    rm -f "$trace_invalid_dir"/*.json
    jq --arg path "$path" 'delpaths([($path | split("."))])' \
        "$trace_valid_dir/completed.json" >"$trace_invalid_dir/missing-current-field.json"
    if "$eval_runner" --validate-traces "$trace_invalid_dir" >"$trace_output" 2>"$trace_error" \
        || ! grep -Fq "${path##*.}" "$trace_error"; then
        completed_verifier_field_failure=1
        break
    fi
done
if [[ "$completed_verifier_field_failure" -eq 0 ]]; then
    pass
else
    fail "completed trace accepted missing current verifier evidence: $path"
fi

test_start "workspace status and failure ids cannot contradict each other"
workspace_parity_failure=0
for mutation in passed-with-id not-applicable-with-id failed-without-id; do
    rm -f "$trace_invalid_dir"/*.json
    case "$mutation" in
        passed-with-id)
            jq '.execution.verifier.workspace_status = "passed"
                | .execution.verifier.workspace_failure_ids = ["workspace-001"]' \
                "$trace_valid_dir/completed.json" >"$trace_invalid_dir/$mutation.json"
            ;;
        not-applicable-with-id)
            jq '.execution.verifier.workspace_status = "not_applicable"
                | .execution.verifier.workspace_failure_ids = ["workspace-001"]' \
                "$trace_valid_dir/completed.json" >"$trace_invalid_dir/$mutation.json"
            ;;
        failed-without-id)
            jq '.metrics.acceptance_passed = false
                | .metrics.acceptance_items_passed = 0
                | .execution.verifier.status = "failed"
                | .execution.verifier.required_missing = 1
                | .execution.verifier.missing_required_ids = ["required-001"]
                | .execution.verifier.acceptance_items_passed = 0
                | .execution.verifier.workspace_status = "failed"
                | .execution.verifier.workspace_exit_code = 1
                | .execution.verifier.workspace_failure_ids = []' \
                "$trace_valid_dir/completed.json" >"$trace_invalid_dir/$mutation.json"
            ;;
    esac
    if "$eval_runner" --validate-traces "$trace_invalid_dir" >"$trace_output" 2>"$trace_error" \
        || ! grep -Fq "workspace_status does not match workspace_failure_ids" "$trace_error"; then
        workspace_parity_failure=1
        break
    fi
done
if [[ "$workspace_parity_failure" -eq 0 ]]; then
    pass
else
    fail "trace validation accepted contradictory workspace evidence: $mutation"
fi

test_start "acceptance item passed counts cannot exceed totals"
acceptance_count_failure=0
for location in metrics execution.verifier; do
    rm -f "$trace_invalid_dir"/*.json
    jq --arg location "$location" '
      if $location == "metrics" then
        .metrics.acceptance_items_passed = 2 | .metrics.acceptance_items_total = 1
      else
        .execution.verifier.acceptance_items_passed = 2 | .execution.verifier.acceptance_items_total = 1
      end
    ' "$trace_valid_dir/completed.json" >"$trace_invalid_dir/invalid-acceptance-count.json"
    if "$eval_runner" --validate-traces "$trace_invalid_dir" >"$trace_output" 2>"$trace_error" \
        || ! grep -Fq "acceptance_items_passed exceeds acceptance_items_total" "$trace_error"; then
        acceptance_count_failure=1
        break
    fi
done
if [[ "$acceptance_count_failure" -eq 0 ]]; then
    pass
else
    fail "trace validation accepted acceptance passed greater than total in $location"
fi

test_start "trace schema publishes current verifier required and workspace parity rules"
if jq -e '
    (.properties.metrics.required | contains(["acceptance_items_passed", "acceptance_items_total"]))
    and any(.properties.execution.properties.verifier.allOf[];
      (.then.required // []) | contains([
        "acceptance_items_passed", "acceptance_items_total", "workspace_status", "workspace_exit_code", "workspace_failure_ids"
      ]))
    and any(.properties.execution.properties.verifier.allOf[];
      .if.properties.workspace_status.enum == ["passed", "not_applicable"]
      and .then.properties.workspace_failure_ids.maxItems == 0)
    and any(.properties.execution.properties.verifier.allOf[];
      .if.properties.workspace_status.const == "failed"
      and .then.properties.workspace_failure_ids.minItems == 1)
  ' "$trace_schema" >/dev/null; then
    pass
else
    fail "published trace schema omits current verifier evidence or workspace parity"
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
    question_mark_count_proxy \
    time_to_first_useful_action_ms \
    rework_count \
    acceptance_items_passed \
    acceptance_items_total \
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
    question_mark_count_proxy \
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
    "The local adapter is not configured."
write_adapter_unavailable_trace \
    "$trace_compare_dir/c-candidate.json" \
    "run-c-candidate" \
    "review-loop-continues-after-findings" \
    "candidate" \
    "The local adapter is not configured."

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
        and .deltas.question_mark_count_proxy.absolute == 0
        and .deltas.question_mark_count_proxy.percent == null
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

test_start "framework comparison separates failure scopes and question-mark proxy semantics"
framework_compare_dir="$(mktemp -d "${TMPDIR:-/tmp}/framework-comparison-traces.XXXXXX")"
framework_compare_output="$(mktemp "${TMPDIR:-/tmp}/framework-comparison-output.XXXXXX")"
p0p4_register_cleanup "$framework_compare_dir" "$framework_compare_output"
for spec in \
    'pair-a 1 case-a baseline true 0 not_applicable 0' \
    'pair-a 1 case-a candidate false 0 not_applicable 0' \
    'pair-b 2 case-a baseline false 0 failed 1' \
    'pair-b 2 case-a candidate false 0 failed 1' \
    'pair-c 1 case-b baseline false 0 not_applicable 0' \
    'pair-c 1 case-b candidate false 0 not_applicable 0' \
    'pair-d 1 case-c baseline true 0 not_applicable 0' \
    'pair-d 1 case-c candidate true 1 not_applicable 0'; do
    read -r pair_id trial_index case_id variant accepted question_marks workspace_status workspace_exit_code <<<"$spec"
    trace_path="$framework_compare_dir/$pair_id-$variant.json"
    write_completed_trace "$trace_path" "$pair_id-$variant" "small-fix-stays-lightweight" "$variant" 100 10 20 1 "$question_marks" 20 0 "$accepted"
    jq \
      --arg pair_id "$pair_id" \
      --arg case_id "$case_id" \
      --arg workspace_status "$workspace_status" \
      --argjson trial_index "$trial_index" \
      --argjson workspace_exit_code "$workspace_exit_code" '
      .pair_id = $pair_id
      | .trial_index = $trial_index
      | .case_id = $case_id
      | .provenance.seed_workspace_sha256 = ("4" * 64)
      | .metrics += {
          seeded_defects_detected:0,
          seeded_defects_total:0,
          false_positive_marker_hits:0,
          scope_deviations:0,
          verifier_exit_code:$workspace_exit_code
        }
      | .execution.verifier.workspace_status = $workspace_status
      | .execution.verifier.workspace_exit_code = $workspace_exit_code
    ' "$trace_path" >"$trace_path.tmp"
    mv "$trace_path.tmp" "$trace_path"
done
jq -s \
    --argjson manifest '{}' \
    --arg candidate_manifest_sha256 "$(printf '0%.0s' {1..64})" \
    -f "$comparison_program" "$framework_compare_dir/"*.json >"$framework_compare_output"
if jq -e '
      .promotion_gate_results.must_pass_pairwise_regressions == 1
      and .promotion_gate_results.candidate_must_pass_failed_runs == 3
      and .promotion_gate_results.candidate_must_pass_failed_cases == 2
      and .promotion_gate_results.shared_must_pass_failed_runs == 2
      and .promotion_gate_results.shared_must_pass_failed_cases == 2
      and .variants.baseline.metrics.overall_verifier_failures == 2
      and .variants.candidate.metrics.overall_verifier_failures == 3
      and .variants.baseline.metrics.workspace_verifier_failures == 1
      and .variants.candidate.metrics.workspace_verifier_failures == 1
      and .variants.baseline.metrics.question_mark_count_proxy_mean == 0
      and .variants.candidate.metrics.question_mark_count_proxy_mean == 0.25
      and .promotion_gate_results.question_mark_count_proxy_not_higher == false
      and .promotion_gate_results.overall_verifier_failures_not_higher == false
      and .promotion_gate_results.workspace_verifier_failures_not_higher == true
      and (.variants.baseline.metrics | has("unnecessary_questions_mean") | not)
      and (.variants.baseline.metrics | has("verifier_failures") | not)
      and (.promotion_gate_results | has("unnecessary_questions_not_higher") | not)
      and (.promotion_gate_results | has("verifier_failures_not_higher") | not)
    ' "$framework_compare_output" >/dev/null; then
    pass
else
    fail "framework comparison conflated failed runs and cases, shared and pairwise failures, verifier scopes, or question-mark proxy semantics"
fi

test_start "framework comparison excludes every complete-pair provenance mismatch"
provenance_mismatch_dir="$(mktemp -d "${TMPDIR:-/tmp}/framework-provenance-mismatch.XXXXXX")"
provenance_mismatch_output="$(mktemp "${TMPDIR:-/tmp}/framework-provenance-mismatch-output.XXXXXX")"
p0p4_register_cleanup "$provenance_mismatch_dir" "$provenance_mismatch_output"
for field in fixture_sha256 case_sha256 grader_sha256 seed_workspace_sha256 adapter_version cli_version; do
    pair_id="mismatch-${field//_/-}"
    for variant in baseline candidate; do
        trace_path="$provenance_mismatch_dir/$pair_id-$variant.json"
        cp "$framework_compare_dir/pair-d-$variant.json" "$trace_path"
        jq --arg pair_id "$pair_id" --arg field "$field" --arg variant "$variant" '
          .pair_id = $pair_id
          | .run_id = ($pair_id + "-" + $variant)
          | if $variant == "candidate" then
              if $field == "adapter_version" then .provenance.adapter_version = "mismatched-adapter"
              elif $field == "cli_version" then .provenance.cli_version = "mismatched-cli"
              else .provenance[$field] = ("f" * 64)
              end
            else . end
        ' "$trace_path" >"$trace_path.tmp"
        mv "$trace_path.tmp" "$trace_path"
    done
done
jq -s --argjson manifest '{}' --arg candidate_manifest_sha256 "$(printf '0%.0s' {1..64})" \
    -f "$comparison_program" "$provenance_mismatch_dir/"*.json >"$provenance_mismatch_output"
if jq -e '
      .complete_pairs == 0
      and .excluded_incomplete_pairs == 6
      and (.incomplete_pairs | length == 6)
      and all(.incomplete_pairs[]; .exclusion_reason == "provenance_mismatch")
    ' "$provenance_mismatch_output" >/dev/null; then
    pass
else
    fail "comparison aggregated a pair with mismatched fixture case grader seed adapter or CLI provenance"
fi

test_start "finalizer binds the full trace snapshot and current trace identities"
binding_root="$(mktemp -d "${TMPDIR:-/tmp}/finalizer-trace-binding.XXXXXX")"
binding_results="$binding_root/results"
binding_traces="$binding_results/traces"
binding_template="$binding_root/verdict-template.json"
binding_plan="$binding_results/run-plan.json"
p0p4_register_cleanup "$binding_root"
mkdir -p "$binding_traces"
case_hash="$(jq -cS '.cases[] | select(.id == "small-fix-stays-lightweight")' "$eval_fixture" | test_sha256_stream)"
grader_contract_hash="$(jq -cS '.cases[] | select(.id == "small-fix-stays-lightweight") | {fail_signals,machine_expectations,semantic_review}' "$eval_fixture" | test_sha256_stream)"
grader_runner_hash="$(test_sha256_stream <"$codex_eval_runner")"
grader_hash="$(printf 'contract_sha256=%s\nrunner_sha256=%s\n' "$grader_contract_hash" "$grader_runner_hash" | test_sha256_stream)"
for variant in baseline candidate; do
    if [[ "$variant" == baseline ]]; then instruction_hash="$(printf '2%.0s' {1..64})"; else instruction_hash="$(printf '3%.0s' {1..64})"; fi
    jq -n --arg variant "$variant" --arg instruction_hash "$instruction_hash" \
      --arg case_hash "$case_hash" --arg grader_hash "$grader_hash" '
      {pair_id:"identity-pair",trial_index:1,case_id:"small-fix-stays-lightweight",model:"test-model",variant:$variant,
       provenance:{fixture_sha256:("1"*64),case_sha256:$case_hash,grader_sha256:$grader_hash,
         instruction_sha256:$instruction_hash,seed_workspace_sha256:("4"*64),requested_model:"test-model",
         runtime_model_attestation:"not_exposed_by_codex_jsonl",model_selection_evidence:"explicit_model_argument_only",
         requested_model_catalog_entry_sha256:null,codex_executable_sha256:null,
         cli_version:"codex-cli test",adapter_version:"codex-framework-eval-v5"}}' \
      >"$binding_traces/identity-pair-$variant.json"
done
jq -n '{planned_runs:2,fixture_sha256:("1"*64),requested_model:"test-model",cli_version:"codex-cli test",
  requested_model_catalog_entry_sha256:null,codex_executable_sha256:null,runs:[
  {pair_id:"identity-pair",case_id:"small-fix-stays-lightweight",trial_index:1,variant:"baseline",instruction_sha256:("2"*64)},
  {pair_id:"identity-pair",case_id:"small-fix-stays-lightweight",trial_index:1,variant:"candidate",instruction_sha256:("3"*64)}]}' >"$binding_plan"
jq -n '{schema_version:"1.0",review_kind:"workflow_kernel_semantic_false_positive",
  scope:{data_classification:"synthetic",case_category:"seeded_review",case_ids:["seeded-code-review-regressions"],synthetic_fixture_ref:"docs/evals/fixtures/seeded-code-review-regressions",synthetic_fixture_sha256:("0"*64),raw_artifacts_retained:false},
  bindings:{run_plan_sha256:("0"*64),comparison_sha256:("0"*64),fixture_sha256:("0"*64),candidate_manifest_sha256:("0"*64),baseline_instruction_sha256:("0"*64),candidate_instruction_sha256:("0"*64)},
  reviewability:{status:"ready",reason_codes:[]},pairs:[{pair_id:"seeded-pair",case_id:"seeded-code-review-regressions",pair_sha256:("0"*64),candidate:{findings:[]}}],diagnostics:[]}' >"$binding_results/semantic-review-packet.json"
expected_trace_set_sha="$(test_trace_set_sha256 "$binding_traces")"
identity_ok=false
if (export FINALIZER_SOURCE_ONLY=true; source "$semantic_finalizer"; validate_plan_trace_contract "$binding_plan" "$binding_traces"); then identity_ok=true; fi
cp "$binding_traces/identity-pair-candidate.json" "$binding_root/candidate-valid.json"
stale_trace_rejected=false
jq --arg stale_hash "$grader_contract_hash" '
  .provenance.grader_sha256 = $stale_hash
  | .provenance.adapter_version = "codex-framework-eval-v2"
' "$binding_root/candidate-valid.json" >"$binding_traces/identity-pair-candidate.json"
if (export FINALIZER_SOURCE_ONLY=true; source "$semantic_finalizer"; ! validate_plan_trace_contract "$binding_plan" "$binding_traces"); then
    stale_trace_rejected=true
fi
identity_rejection_ok=true
for identity_field in case grader adapter; do
    case "$identity_field" in
        case) jq '.provenance.case_sha256 = ("f"*64)' "$binding_root/candidate-valid.json" >"$binding_traces/identity-pair-candidate.json" ;;
        grader) jq '.provenance.grader_sha256 = ("f"*64)' "$binding_root/candidate-valid.json" >"$binding_traces/identity-pair-candidate.json" ;;
        adapter) jq '.provenance.adapter_version = "stale-adapter"' "$binding_root/candidate-valid.json" >"$binding_traces/identity-pair-candidate.json" ;;
    esac
    if (export FINALIZER_SOURCE_ONLY=true; source "$semantic_finalizer"; validate_plan_trace_contract "$binding_plan" "$binding_traces"); then
        identity_rejection_ok=false
        break
    fi
done
cp "$binding_root/candidate-valid.json" "$binding_traces/identity-pair-candidate.json"
actual_trace_set_sha="$(export FINALIZER_SOURCE_ONLY=true; source "$semantic_finalizer"; trace_set_sha256 "$binding_traces")"
if [[ "$actual_trace_set_sha" == "$expected_trace_set_sha" ]] \
    && jq -e '.properties.bindings.required | index("trace_set_sha256") != null' "$semantic_verdict_schema" >/dev/null \
    && jq -e '.properties.bindings.required | index("context_budget_evidence_sha256") != null' "$semantic_verdict_schema" >/dev/null \
    && jq -e '.properties.bindings.required | index("trace_set_sha256") != null' "$promotion_decision_schema" >/dev/null \
    && jq -e '.properties.bindings.required | index("context_budget_evidence_sha256") != null' "$promotion_decision_schema" >/dev/null \
    && [[ "$identity_ok" == true && "$identity_rejection_ok" == true && "$stale_trace_rejected" == true ]]; then
    pass
else
    fail "finalizer did not bind every trace or reject stale case grader and adapter identities"
fi

test_start "finalizer hashes the same Codex materialization as the eval runner"
materialization_root="$(mktemp -d "${TMPDIR:-/tmp}/finalizer-materialization.XXXXXX")"
materialization_overlay="$materialization_root/overlay/SKILL.md"
materialization_expected="$materialization_root/expected"
p0p4_register_cleanup "$materialization_root"
mkdir -p "$(dirname "$materialization_overlay")" "$materialization_expected"
printf '%s\n' 'state directory: {agent_state_dir}' >"$materialization_overlay"
while IFS= read -r entry; do
    cp -R "$entry" "$materialization_expected/"
done < <(find "$FRAMEWORK_DIR/skills/assistant-workflow" -mindepth 1 -maxdepth 1 ! -name evals -print | LC_ALL=C sort)
cp "$materialization_overlay" "$materialization_expected/SKILL.md"
while IFS= read -r instruction_file; do
    sed -i.bak -e 's|{agent_state_dir}|.codex|g' "$instruction_file"
    rm -f "${instruction_file}.bak"
done < <(find "$materialization_expected" -type f \( \
    -name '*.md' -o -name '*.yaml' -o -name '*.yml' -o -name '*.json' \
    -o -name '*.conf' -o -name '*.toml' \))
expected_materialization_hash="$(test_hash_directory "$materialization_expected")"
actual_materialization_hash="$(export FINALIZER_SOURCE_ONLY=true; source "$semantic_finalizer"; materialized_candidate_hash "$materialization_overlay")"
if [[ "$actual_materialization_hash" == "$expected_materialization_hash" ]] \
    && ! grep -R -Fq '{agent_state_dir}' "$materialization_expected"; then
    pass
else
    fail "finalizer did not mirror installer instruction materialization and agent-state substitution before hashing"
fi

test_start "question-mark proxy naming is explicit across manifest comparison and docs"
if jq -e '.promotion_gates.question_mark_count_proxy_must_not_increase == true and (.promotion_gates | has("unnecessary_questions_must_not_increase") | not)' "$workflow_kernel_manifest" >/dev/null \
    && grep -Fq 'question_mark_count_proxy_not_higher' "$comparison_program" \
    && grep -Fq 'question-mark-count proxy' "$eval_readme"; then
    pass
else
    fail "promotion surfaces still present the question-mark proxy as semantic unnecessary-question evidence"
fi

test_start "trace contract rejects the ambiguous legacy unnecessary_questions field"
legacy_metric_trace="$trace_invalid_dir/legacy-unnecessary-questions.json"
rm -f "$trace_invalid_dir"/*.json
jq '
  .metrics.unnecessary_questions = .metrics.question_mark_count_proxy
  | .execution.metric_methods.unnecessary_questions = "question_mark_count_proxy"
' "$trace_valid_dir/completed.json" >"$legacy_metric_trace"
if "$eval_runner" --validate-traces "$trace_invalid_dir" >"$trace_output" 2>"$trace_error"; then
    fail "trace validator accepted the ambiguous legacy unnecessary_questions field"
elif grep -Fq 'unnecessary_questions' "$trace_error" \
    && jq -e '
      (.properties.metrics.required | index("question_mark_count_proxy") != null)
      and (.properties.metrics.properties | has("question_mark_count_proxy"))
      and (.properties.metrics.properties | has("unnecessary_questions") | not)
      and (.properties.execution.properties.metric_methods.required | index("question_mark_count_proxy") != null)
      and (.properties.execution.properties.metric_methods.properties | has("unnecessary_questions") | not)
    ' "$trace_schema" >/dev/null; then
    pass
else
    fail "trace schema and validator did not converge on the explicit question_mark_count_proxy field"
fi

test_start "stale-journal workspace predicates expose bounded diagnostic ids"
if grep -Fq 'workspace_failure_ids' "$codex_eval_runner" \
    && grep -Fq 'workspace-001' "$codex_eval_runner" \
    && grep -Fq 'workspace-002' "$codex_eval_runner" \
    && grep -Fq 'workspace-003' "$codex_eval_runner" \
    && jq -e '
      .properties.execution.properties.verifier.properties.workspace_failure_ids
      | .type == "array"
        and .maxItems == 999
        and .uniqueItems == true
        and .items.pattern == "^workspace-[0-9]{3}$"
    ' "$trace_schema" >/dev/null \
    && grep -Fq '"workspace_failure_ids"' "$eval_runner" \
    && grep -Fq 'bounded_ids("workspace_failure_ids"; "^workspace-[0-9]{3}$")' "$eval_runner"; then
    pass
else
    fail "stale-journal workspace failures are not traceable through bounded verifier ids"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
