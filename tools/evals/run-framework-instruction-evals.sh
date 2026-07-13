#!/usr/bin/env bash
# Provider-neutral local runner for Assistant Framework instruction eval fixtures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURE="$REPO_ROOT/docs/evals/framework-instruction-cases.json"
MODE=""
OUTPUT_DIR=""
RESPONSES_DIR=""
TRACES_DIR=""

usage() {
    cat <<'EOF'
Usage:
  run-framework-instruction-evals.sh --validate-fixture
  run-framework-instruction-evals.sh --list
  run-framework-instruction-evals.sh --emit-prompts DIR
  run-framework-instruction-evals.sh --responses DIR
  run-framework-instruction-evals.sh --validate-traces DIR
  run-framework-instruction-evals.sh --compare-traces DIR
  run-framework-instruction-evals.sh --help

Runs offline, provider-neutral helpers for docs/evals/framework-instruction-cases.json.
No provider SDKs, network calls, or model APIs are used.

Options:
  --validate-fixture   Validate fixture schema and case shape.
  --list               Print case id, category, and title as tab-separated lines.
  --emit-prompts DIR   Write one Markdown prompt packet per case into DIR.
  --responses DIR      Heuristically grade local response files from DIR.
  --validate-traces DIR
                       Validate imported, redacted trace result JSON files.
  --compare-traces DIR
                       Emit a deterministic baseline/candidate JSON comparison.
  -h, --help           Show this help.
EOF
}

die() {
    echo "Error: $1" >&2
    exit 1
}

require_jq() {
    command -v jq >/dev/null 2>&1 || die "jq is required."
}

validate_fixture() {
    require_jq
    [[ -f "$FIXTURE" ]] || die "Fixture not found: $FIXTURE"

    local validation_error
    validation_error="$(jq -r '
        def required_string($name):
          if has($name) and (.[$name] | type == "string" and length > 0) then empty
          else "missing or invalid top-level string field: \($name)" end;

        def required_bool($name; $value):
          if has($name) and .[$name] == $value then empty
          else "top-level field \($name) must be \($value)" end;

        def required_string_array($name):
          if has($name)
             and (.[$name] | type == "array")
             and (.[$name] | length > 0)
             and all(.[$name][]; type == "string" and length > 0)
          then empty
          else "missing or invalid non-empty string array field: \($name)" end;

        def case_string($index; $name):
          if has($name) and (.[$name] | type == "string" and length > 0) then empty
          else "case[\($index)] missing or invalid string field: \($name)" end;

        def case_string_array($index; $name):
          if has($name)
             and (.[$name] | type == "array")
             and (.[$name] | length > 0)
             and all(.[$name][]; type == "string" and length > 0)
          then empty
          else "case[\($index)] missing or invalid non-empty string array field: \($name)" end;

        def case_machine_expectation_array($index; $name):
          if (.machine_expectations | has($name))
             and (.machine_expectations[$name] | type == "array")
             and (.machine_expectations[$name] | length > 0)
             and all(.machine_expectations[$name][]; type == "string" and length > 0)
          then empty
          else "case[\($index)] missing or invalid machine_expectations.\($name) non-empty string array" end;

        def case_machine_expectations($index):
          if has("machine_expectations") and (.machine_expectations | type == "object") then
            case_machine_expectation_array($index; "required_substrings"),
            case_machine_expectation_array($index; "forbidden_substrings")
          else
            "case[\($index)] missing or invalid object field: machine_expectations"
          end;

        if type != "object" then
          "fixture root must be a JSON object"
        else
          required_string("schema_version"),
          required_string("suite_id"),
          required_string("title"),
          required_string("description"),
          required_string("eval_type"),
          required_bool("provider_neutral"; true),
          required_bool("model_specific_api_calls"; false),
          required_string_array("recommended_use"),
          (if (.cases | type == "array") and (.cases | length > 0) then empty
           else "top-level field cases must be a non-empty array" end),
          (if (.cases | type == "array") then
             .cases | to_entries[] | .key as $index | .value |
               if type != "object" then
                 "case[\($index)] must be an object"
               else
                 case_string($index; "id"),
                 case_string($index; "title"),
                 case_string($index; "category"),
                 case_string($index; "purpose"),
                 case_string($index; "prompt"),
                 case_string_array($index; "setup_context"),
                 case_string_array($index; "expected_behavior"),
                 case_string_array($index; "pass_criteria"),
                 case_string_array($index; "fail_signals"),
                 case_machine_expectations($index)
               end
           else empty end)
        end
    ' "$FIXTURE")" || die "Fixture is not valid JSON: $FIXTURE"

    if [[ -n "$validation_error" ]]; then
        echo "$validation_error" >&2
        exit 1
    fi
}

list_cases() {
    validate_fixture
    jq -r '.cases[] | [.id, .category, .title] | @tsv' "$FIXTURE"
}

emit_prompts() {
    validate_fixture
    mkdir -p "$OUTPUT_DIR"

    local id packet_path
    while IFS= read -r id; do
        packet_path="$OUTPUT_DIR/$id.md"
        jq -r --arg id "$id" '
            def bullets($items):
              if ($items | length) > 0 then $items | map("- " + .) | join("\n")
              else "- (none)" end;
            .cases[]
            | select(.id == $id)
            | "# " + .title + "\n\n"
              + "Case ID: " + .id + "\n\n"
              + "Category: " + .category + "\n\n"
              + "Purpose: " + .purpose + "\n\n"
              + "## Setup Context\n\n" + bullets(.setup_context) + "\n\n"
              + "## Prompt\n\n" + .prompt + "\n\n"
              + "## Expected Behavior\n\n" + bullets(.expected_behavior) + "\n\n"
              + "## Pass Criteria\n\n" + bullets(.pass_criteria) + "\n\n"
              + "## Fail Signals\n\n" + bullets(.fail_signals) + "\n\n"
              + "## Machine Expectations\n\n"
              + "### Required Substrings\n\n"
              + bullets(.machine_expectations.required_substrings) + "\n\n"
              + "### Forbidden Substrings\n\n"
              + bullets(.machine_expectations.forbidden_substrings) + "\n"
        ' "$FIXTURE" >"$packet_path"
    done < <(jq -r '.cases[].id' "$FIXTURE")

    echo "Wrote $(jq '.cases | length' "$FIXTURE") prompt packets to $OUTPUT_DIR"
}

first_response_path_for_case() {
    local id="$1"
    if [[ -f "$RESPONSES_DIR/$id.txt" ]]; then
        printf '%s\n' "$RESPONSES_DIR/$id.txt"
    elif [[ -f "$RESPONSES_DIR/$id.md" ]]; then
        printf '%s\n' "$RESPONSES_DIR/$id.md"
    else
        printf '\n'
    fi
}

is_file_nonempty() {
    local path="$1"
    [[ -s "$path" ]] && grep -q '[^[:space:]]' "$path"
}

count_fail_signal_hits() {
    local id="$1"
    local response_path="$2"
    local signal
    local hits=0

    while IFS= read -r signal; do
        if [[ ${#signal} -ge 12 ]] && grep -Fqi -- "$signal" "$response_path"; then
            hits=$((hits + 1))
        fi
    done < <(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .fail_signals[]' "$FIXTURE")

    printf '%s\n' "$hits"
}

count_missing_required_substrings() {
    local id="$1"
    local response_path="$2"
    local expected
    local misses=0

    while IFS= read -r expected; do
        if ! grep -Fqi -- "$expected" "$response_path"; then
            misses=$((misses + 1))
        fi
    done < <(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .machine_expectations.required_substrings[]' "$FIXTURE")

    printf '%s\n' "$misses"
}

count_forbidden_substring_hits() {
    local id="$1"
    local response_path="$2"
    local forbidden
    local hits=0

    while IFS= read -r forbidden; do
        if grep -Fqi -- "$forbidden" "$response_path"; then
            hits=$((hits + 1))
        fi
    done < <(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .machine_expectations.forbidden_substrings[]' "$FIXTURE")

    printf '%s\n' "$hits"
}

grade_responses() {
    validate_fixture
    [[ -d "$RESPONSES_DIR" ]] || die "Response directory does not exist: $RESPONSES_DIR"

    local total=0
    local passed=0
    local failed=0
    local missing=0
    local empty=0
    local signal_failures=0
    local missing_required_failures=0
    local forbidden_substring_failures=0
    local id category title response_path fail_signal_hits required_misses forbidden_hits status reason

    echo "Heuristic/local grading only. Deterministic substring checks are local proxies; no provider API is invoked."
    echo ""

    while IFS=$'\t' read -r id category title; do
        total=$((total + 1))
        response_path="$(first_response_path_for_case "$id")"
        status="PASS"
        reason="non-empty response with no exact fail-signal phrase hits and no machine expectation failures"

        if [[ -z "$response_path" ]]; then
            status="FAIL"
            reason="missing response file"
            missing=$((missing + 1))
        elif ! is_file_nonempty "$response_path"; then
            status="FAIL"
            reason="empty response file"
            empty=$((empty + 1))
        else
            fail_signal_hits="$(count_fail_signal_hits "$id" "$response_path")"
            required_misses="$(count_missing_required_substrings "$id" "$response_path")"
            forbidden_hits="$(count_forbidden_substring_hits "$id" "$response_path")"
            if [[ "$fail_signal_hits" -gt 0 ]]; then
                status="FAIL"
                reason="$fail_signal_hits exact fail-signal phrase hit(s)"
                signal_failures=$((signal_failures + 1))
            fi
            if [[ "$required_misses" -gt 0 ]]; then
                if [[ "$status" == "FAIL" ]]; then
                    reason="$reason; $required_misses missing required substring(s)"
                else
                    status="FAIL"
                    reason="$required_misses missing required substring(s)"
                fi
                missing_required_failures=$((missing_required_failures + required_misses))
            fi
            if [[ "$forbidden_hits" -gt 0 ]]; then
                if [[ "$status" == "FAIL" ]]; then
                    reason="$reason; $forbidden_hits forbidden substring hit(s)"
                else
                    status="FAIL"
                    reason="$forbidden_hits forbidden substring hit(s)"
                fi
                forbidden_substring_failures=$((forbidden_substring_failures + forbidden_hits))
            fi
        fi

        if [[ "$status" == "PASS" ]]; then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
        fi

        printf '%s\t%s\t%s\t%s\t%s\n' "$status" "$id" "$category" "$title" "$reason"
    done < <(jq -r '.cases[] | [.id, .category, .title] | @tsv' "$FIXTURE")

    echo ""
    printf 'Summary: total=%s passed=%s failed=%s missing=%s empty=%s fail_signal_hits=%s missing_required_substrings=%s forbidden_substring_hits=%s\n' \
        "$total" "$passed" "$failed" "$missing" "$empty" "$signal_failures" "$missing_required_failures" "$forbidden_substring_failures"

    [[ "$failed" -eq 0 ]]
}

trace_validation_errors() {
    local trace_file="$1"

    jq -r --slurpfile fixture "$FIXTURE" '
      def nonempty_string: type == "string" and length > 0;
      def sha256_string: type == "string" and test("^[0-9a-f]{64}$");
      def allowed_top: ["schema_version", "run_id", "pair_id", "trial_index", "case_id", "model", "variant", "status", "metrics", "error", "provenance", "execution"];
      def allowed_metrics: ["input_tokens", "output_tokens", "latency_ms", "tool_calls", "question_mark_count_proxy", "time_to_first_useful_action_ms", "rework_count", "acceptance_passed", "acceptance_items_passed", "acceptance_items_total", "seeded_defects_detected", "seeded_defects_total", "false_positive_marker_hits", "forbidden_command_hits", "scope_deviations", "verifier_exit_code"];
      def allowed_error: ["code", "message"];
      def allowed_provenance: ["fixture_sha256", "case_sha256", "instruction_sha256", "grader_sha256", "seed_workspace_sha256", "cli_version", "requested_model", "runtime_model_attestation", "model_selection_evidence", "requested_model_catalog_entry_sha256", "codex_executable_sha256", "adapter_version"];
      def allowed_execution: ["exit_code", "verifier", "metric_methods", "raw_artifacts_retained", "semantic_checkpoint_sha256"];
      def allowed_verifier: ["status", "required_missing", "missing_required_ids", "forbidden_hits", "forbidden_hit_ids", "fail_signal_hits", "fail_signal_hit_ids", "acceptance_items_passed", "acceptance_items_total", "seeded_defects_detected", "seeded_defects_total", "seeded_defect_missed_ids", "false_positive_marker_hits", "false_positive_marker_hit_ids", "forbidden_command_hits", "workspace_status", "workspace_exit_code", "workspace_failure_ids", "scope_deviations"];
      def unknown($allowed): keys_unsorted - $allowed;
      def require_string($field):
        if has($field) and (.[$field] | nonempty_string) then empty
        else "missing or invalid field " + $field end;
      def require_number($field):
        if has($field) and (.[$field] | type == "number" and . >= 0) then empty
        else "missing or invalid numeric metric " + $field end;
      def require_integer($field):
        if has($field) then
          .[$field] as $value
          | if ($value | type) != "number" then
              "missing or invalid nonnegative integer metric " + $field
            elif $value < 0 or $value != ($value | floor) then
              "missing or invalid nonnegative integer metric " + $field
            else empty end
        else "missing or invalid nonnegative integer metric " + $field end;
      def bounded_ids($field; $pattern):
        if has($field)
           and (.[$field] | type == "array" and length <= 999 and length == (unique | length)
             and all(.[]; type == "string" and test($pattern)))
        then empty else "missing or invalid bounded verifier IDs " + $field end;

      if type != "object" then
        "trace root must be an object"
      else
        (unknown(allowed_top)[]? | "additional top-level field is not allowed: " + .),
        (if .schema_version == "1.0" then empty else "schema_version must be 1.0" end),
        require_string("run_id"),
        (if has("pair_id") then require_string("pair_id") else empty end),
        (if has("trial_index") then
          (if (.trial_index | type == "number" and . >= 1 and . == floor) then empty
           else "trial_index must be a positive integer" end)
         else empty end),
        require_string("case_id"),
        (if (.case_id | nonempty_string) then
          .case_id as $case_id
          | if any($fixture[0].cases[]; .id == $case_id) then empty
            else "case_id is not declared in the eval fixture: " + $case_id end
         else empty end),
        require_string("model"),
        (if has("provenance") and (.provenance | type) == "object" and (.provenance.requested_model | nonempty_string) then
           (if .model == .provenance.requested_model then empty else "model must equal provenance.requested_model" end)
         else empty end),
        (if .variant == "baseline" or .variant == "candidate" then empty
         else "variant must be baseline or candidate" end),
        (if .status == "completed" or .status == "adapter_unavailable" then empty
         else "status must be completed or adapter_unavailable" end),
        (if .status == "completed" then
           (if has("provenance") then empty else "completed trace requires provenance" end),
           (if has("execution") then empty else "completed trace requires execution" end),
           (if .execution.exit_code == 0 then empty else "completed trace execution.exit_code must be 0" end),
           (if .execution.verifier.status == "passed" or .execution.verifier.status == "failed"
            then empty else "completed trace verifier.status must be passed or failed" end),
           (if .execution | has("metric_methods") then empty else "completed trace requires exact metric_methods" end),
           (if (.execution | has("raw_artifacts_retained")) and .execution.raw_artifacts_retained == false
            then empty else "completed trace requires raw_artifacts_retained=false" end),
           (if (.metrics.acceptance_passed == true and .execution.verifier.status == "passed")
                or (.metrics.acceptance_passed == false and .execution.verifier.status == "failed")
            then empty else "completed trace acceptance_passed does not match verifier.status" end),
           (if .metrics.acceptance_items_passed == .execution.verifier.acceptance_items_passed
                and .metrics.acceptance_items_total == .execution.verifier.acceptance_items_total
            then empty else "completed trace metric acceptance item counts do not match verifier counts" end)
         else empty end),
        (if has("provenance") then
          (if (.provenance | type) == "object" then
            (.provenance | unknown(allowed_provenance)[]? | "additional provenance field is not allowed: " + .),
            (if (.provenance.fixture_sha256 | sha256_string) then empty else "provenance.fixture_sha256 must be a lowercase SHA-256" end),
            (if (.provenance.case_sha256 | sha256_string) then empty else "provenance.case_sha256 must be a lowercase SHA-256" end),
            (if (.provenance.instruction_sha256 | sha256_string) then empty else "provenance.instruction_sha256 must be a lowercase SHA-256" end),
            (if (.provenance.grader_sha256 | sha256_string) then empty else "provenance.grader_sha256 must be a lowercase SHA-256" end),
            (if (.provenance | has("seed_workspace_sha256")) then
               (if (.provenance.seed_workspace_sha256 | sha256_string) then empty else "provenance.seed_workspace_sha256 must be a lowercase SHA-256" end)
             else empty end),
            (.provenance | require_string("cli_version")),
            (.provenance | require_string("requested_model")),
            (if .provenance.runtime_model_attestation == "not_exposed_by_codex_jsonl" then empty else "provenance.runtime_model_attestation must disclose unavailable runtime telemetry" end),
            (if .provenance.model_selection_evidence == "catalog_entry_and_explicit_model_argument"
                 or .provenance.model_selection_evidence == "explicit_model_argument_only"
             then empty else "provenance.model_selection_evidence is invalid" end),
            (if .provenance.requested_model_catalog_entry_sha256 == null
                 or (.provenance.requested_model_catalog_entry_sha256 | sha256_string)
             then empty else "provenance.requested_model_catalog_entry_sha256 must be null or a lowercase SHA-256" end),
            (if .provenance.codex_executable_sha256 == null
                 or (.provenance.codex_executable_sha256 | sha256_string)
             then empty else "provenance.codex_executable_sha256 must be null or a lowercase SHA-256" end),
            (if .provenance.model_selection_evidence == "catalog_entry_and_explicit_model_argument" then
               (if (.provenance.requested_model_catalog_entry_sha256 | sha256_string)
                    and (.provenance.codex_executable_sha256 | sha256_string)
                then empty else "model-selection evidence hashes are inconsistent with catalog attestation" end)
             elif .provenance.model_selection_evidence == "explicit_model_argument_only" then
               (if .provenance.requested_model_catalog_entry_sha256 == null
                then empty else "model-selection evidence hashes are inconsistent with argument-only selection" end)
             else empty end),
            (if (.provenance | has("resolved_model")) then "provenance.resolved_model is unsupported because Codex JSONL does not expose runtime resolution" else empty end),
            (.provenance | require_string("adapter_version"))
           else "provenance must be an object" end)
         else empty end),
        (if has("execution") then
          (if (.execution | type) == "object" then
            (.execution | unknown(allowed_execution)[]? | "additional execution field is not allowed: " + .),
            (if (.execution | has("semantic_checkpoint_sha256")) then
               (if (.execution.semantic_checkpoint_sha256 | sha256_string) then empty else "execution.semantic_checkpoint_sha256 must be a lowercase SHA-256" end)
             else empty end),
            (if (.execution.exit_code | type == "number" and . >= 0 and . == floor) then empty
             else "execution.exit_code must be a nonnegative integer" end),
            (if (.execution.verifier | type) == "object" then
              (.execution.verifier | unknown(allowed_verifier)[]? | "additional verifier field is not allowed: " + .),
              (if (.execution.verifier.status == "passed" or .execution.verifier.status == "failed" or .execution.verifier.status == "not_run") then empty
               else "execution.verifier.status is invalid" end),
              (.execution.verifier | if has("required_missing") then require_integer("required_missing") else empty end),
              (.execution.verifier | if has("missing_required_ids") then bounded_ids("missing_required_ids"; "^required-[0-9]{3}$") else empty end),
              (.execution.verifier | if has("forbidden_hits") then require_integer("forbidden_hits") else empty end),
              (.execution.verifier | if has("forbidden_hit_ids") then bounded_ids("forbidden_hit_ids"; "^forbidden-[0-9]{3}$") else empty end),
              (.execution.verifier | if has("fail_signal_hits") then require_integer("fail_signal_hits") else empty end),
              (.execution.verifier | if has("fail_signal_hit_ids") then bounded_ids("fail_signal_hit_ids"; "^fail-signal-[0-9]{3}$") else empty end),
              (.execution.verifier | if has("acceptance_items_passed") then require_integer("acceptance_items_passed") else empty end),
              (.execution.verifier | if has("acceptance_items_total") then require_integer("acceptance_items_total") else empty end),
              (.execution.verifier | if has("seeded_defects_detected") then require_integer("seeded_defects_detected") else empty end),
              (.execution.verifier | if has("seeded_defects_total") then require_integer("seeded_defects_total") else empty end),
              (.execution.verifier | if has("seeded_defect_missed_ids") then bounded_ids("seeded_defect_missed_ids"; "^seeded-defect-[0-9]{3}$") else empty end),
              (.execution.verifier | if has("false_positive_marker_hits") then require_integer("false_positive_marker_hits") else empty end),
              (.execution.verifier | if has("false_positive_marker_hit_ids") then bounded_ids("false_positive_marker_hit_ids"; "^false-positive-[0-9]{3}$") else empty end),
              (.execution.verifier | if has("forbidden_command_hits") then require_integer("forbidden_command_hits") else empty end),
              (.execution.verifier | if has("workspace_exit_code") then require_integer("workspace_exit_code") else empty end),
              (.execution.verifier | if has("workspace_failure_ids") then bounded_ids("workspace_failure_ids"; "^workspace-[0-9]{3}$") else empty end),
              (.execution.verifier | if has("scope_deviations") then require_integer("scope_deviations") else empty end),
              (.execution.verifier.workspace_status as $workspace_status
               | if (.execution.verifier | has("workspace_status")) and (["passed", "failed", "not_applicable"] | index($workspace_status)) == null
                 then "execution.verifier.workspace_status is invalid" else empty end),
              (if .execution.verifier.status == "passed" or .execution.verifier.status == "failed" then
                 (.execution.verifier | bounded_ids("missing_required_ids"; "^required-[0-9]{3}$")),
                 (.execution.verifier | bounded_ids("forbidden_hit_ids"; "^forbidden-[0-9]{3}$")),
                 (.execution.verifier | bounded_ids("fail_signal_hit_ids"; "^fail-signal-[0-9]{3}$")),
                 (.execution.verifier | bounded_ids("seeded_defect_missed_ids"; "^seeded-defect-[0-9]{3}$")),
                 (.execution.verifier | bounded_ids("false_positive_marker_hit_ids"; "^false-positive-[0-9]{3}$")),
                 (.execution.verifier | bounded_ids("workspace_failure_ids"; "^workspace-[0-9]{3}$")),
                 (.execution.verifier | require_integer("acceptance_items_passed")),
                 (.execution.verifier | require_integer("acceptance_items_total")),
                 (if .execution.verifier | has("workspace_status") then empty else "completed trace verifier requires workspace_status" end),
                 (.execution.verifier | require_integer("workspace_exit_code")),
                 (if .execution.verifier.required_missing == (.execution.verifier.missing_required_ids | length) then empty else "required_missing count does not match missing_required_ids" end),
                 (if .execution.verifier.forbidden_hits == (.execution.verifier.forbidden_hit_ids | length) then empty else "forbidden_hits count does not match forbidden_hit_ids" end),
                 (if .execution.verifier.fail_signal_hits == (.execution.verifier.fail_signal_hit_ids | length) then empty else "fail_signal_hits count does not match fail_signal_hit_ids" end),
                 (if .execution.verifier.seeded_defects_detected == (.execution.verifier.seeded_defects_total - (.execution.verifier.seeded_defect_missed_ids | length)) then empty else "seeded defect count does not match seeded_defect_missed_ids" end),
                 (if .execution.verifier.false_positive_marker_hits == (.execution.verifier.false_positive_marker_hit_ids | length) then empty else "false_positive_marker_hits count does not match false_positive_marker_hit_ids" end),
                 (if .execution.verifier.acceptance_items_passed <= .execution.verifier.acceptance_items_total then empty else "acceptance_items_passed exceeds acceptance_items_total" end),
                 (if ((.execution.verifier.workspace_status == "failed") == ((.execution.verifier.workspace_failure_ids | length) > 0))
                  then empty else "workspace_status does not match workspace_failure_ids" end)
               else empty end)
             else "execution.verifier must be an object" end),
            (if (.execution | has("metric_methods")) then
              (if (.execution.metric_methods | type) == "object"
                   and (.execution.metric_methods | keys_unsorted | sort) == ["question_mark_count_proxy", "rework_count", "time_to_first_useful_action_ms"]
                   and .execution.metric_methods.time_to_first_useful_action_ms == "completion_latency_upper_bound"
                   and .execution.metric_methods.question_mark_count_proxy == "question_mark_count_proxy"
                   and .execution.metric_methods.rework_count == "additional_file_change_events_proxy"
               then empty else "execution.metric_methods does not match the published proxy contract" end)
             else empty end),
            (if (.execution | has("raw_artifacts_retained")) and .execution.raw_artifacts_retained != false then
              "execution.raw_artifacts_retained must be false"
             else empty end)
           else "execution must be an object" end)
         else empty end),
        (if .status == "completed" then
          (if has("error") then "completed trace must not contain error" else empty end),
          (if (.metrics | type) == "object" then
            (.metrics | unknown(allowed_metrics)[]? | "additional metrics field is not allowed: " + .),
            (.metrics | require_integer("input_tokens")),
            (.metrics | require_integer("output_tokens")),
            (.metrics | require_number("latency_ms")),
            (.metrics | require_integer("tool_calls")),
            (.metrics | require_integer("question_mark_count_proxy")),
            (.metrics | require_number("time_to_first_useful_action_ms")),
            (.metrics | require_integer("rework_count")),
            (if .metrics | has("acceptance_passed") and (.acceptance_passed | type == "boolean")
             then empty else "missing or invalid boolean metric acceptance_passed" end),
            (.metrics | require_integer("acceptance_items_passed")),
            (.metrics | require_integer("acceptance_items_total")),
            (if .metrics.acceptance_items_passed <= .metrics.acceptance_items_total then empty else "acceptance_items_passed exceeds acceptance_items_total" end),
            (.metrics | if has("seeded_defects_detected") then require_integer("seeded_defects_detected") else empty end),
            (.metrics | if has("seeded_defects_total") then require_integer("seeded_defects_total") else empty end),
            (.metrics | if has("false_positive_marker_hits") then require_integer("false_positive_marker_hits") else empty end),
            (.metrics | if has("forbidden_command_hits") then require_integer("forbidden_command_hits") else empty end),
            (.metrics | if has("scope_deviations") then require_integer("scope_deviations") else empty end),
            (.metrics | if has("verifier_exit_code") then require_integer("verifier_exit_code") else empty end)
           else "completed trace requires metrics object" end)
         elif .status == "adapter_unavailable" then
          (if has("metrics") then "adapter_unavailable trace must not contain metrics" else empty end),
          (if (.error | type) == "object" then
            (.error | unknown(allowed_error)[]? | "additional error field is not allowed: " + .),
            (if .error.code | nonempty_string then empty else "missing or invalid error.code" end),
            (.error.code as $error_code | if ([
                  "adapter_not_configured",
                  "codex_not_found",
                  "codex_exit_nonzero",
                  "codex_reported_failure",
                  "local_execution_restricted",
                  "model_unavailable",
                  "authentication_failed",
                  "quota_or_rate_limited",
                  "network_unavailable",
                  "configuration_error",
                  "cli_usage_error",
                  "unknown_event_shape",
                  "missing_usage",
                  "missing_final_output",
                  "execution_timed_out",
                  "evaluation_time_cap_reached"
                ] | index($error_code)) != null
             then empty else "error.code is not in the bounded vocabulary" end),
            (if .error.message | nonempty_string then empty else "missing or invalid error.message" end),
            (if (.error.code | nonempty_string) and (.error.message | nonempty_string) then
              (.error.code as $error_code
               | .error.message as $error_message
               | if ({
                  "adapter_not_configured": "The local adapter is not configured.",
                  "codex_not_found": "Codex executable is unavailable.",
                  "codex_exit_nonzero": "Codex exited non-zero without a recognized structured failure class.",
                  "codex_reported_failure": "Codex reported a structured execution failure.",
                  "local_execution_restricted": "Local execution restrictions prevented Codex startup.",
                  "model_unavailable": "Requested model is unavailable or inaccessible.",
                  "authentication_failed": "Codex authentication failed.",
                  "quota_or_rate_limited": "Codex quota or rate limit prevented execution.",
                  "network_unavailable": "Codex could not reach the model service.",
                  "configuration_error": "Codex configuration prevented execution.",
                  "cli_usage_error": "Codex rejected the adapter command shape.",
                  "unknown_event_shape": "Codex JSONL contained an unknown event shape.",
                  "missing_usage": "Codex JSONL did not contain completed token usage.",
                  "missing_final_output": "Codex did not produce a final response.",
                  "execution_timed_out": "Codex exceeded the bounded per-run timeout.",
                  "evaluation_time_cap_reached": "The bounded total evaluation time cap was reached."
                  }[$error_code] == $error_message)
                 then empty else "error.message does not match bounded message for error.code" end)
             else empty end)
           else "adapter_unavailable trace requires error object with error.code and error.message" end)
         else empty end)
      end
    ' "$trace_file"
}

validate_trace_directory() {
    local trace_dir="$1"
    local quiet="${2:-false}"
    [[ -d "$trace_dir" ]] || die "Trace directory does not exist: $trace_dir"

    local trace_file errors found=0 invalid=0
    local run_id_index duplicate_errors
    run_id_index="$(mktemp "${TMPDIR:-/tmp}/framework-eval-run-ids.XXXXXX")"
    while IFS= read -r trace_file; do
        found=$((found + 1))
        if ! jq empty "$trace_file" >/dev/null 2>&1; then
            echo "$(basename "$trace_file"): invalid JSON" >&2
            invalid=$((invalid + 1))
            continue
        fi
        if jq -e '.run_id | type == "string" and length > 0' "$trace_file" >/dev/null 2>&1; then
            jq -cn \
                --arg run_id "$(jq -r '.run_id' "$trace_file")" \
                --arg file "$(basename "$trace_file")" \
                '{run_id: $run_id, file: $file}' >>"$run_id_index"
        fi
        errors="$(trace_validation_errors "$trace_file")"
        if [[ -n "$errors" ]]; then
            while IFS= read -r error; do
                [[ -n "$error" ]] && echo "$(basename "$trace_file"): $error" >&2
            done <<<"$errors"
            invalid=$((invalid + 1))
        fi
    done < <(find "$trace_dir" -maxdepth 1 -type f -name '*.json' -print | LC_ALL=C sort)

    duplicate_errors="$(jq -s -r '
      sort_by(.run_id)
      | group_by(.run_id)[]
      | select(length > 1)
      | .[]
      | "\(.file): duplicate run_id field: \(.run_id)"
    ' "$run_id_index")"
    rm -f "$run_id_index"
    if [[ -n "$duplicate_errors" ]]; then
        printf '%s\n' "$duplicate_errors" >&2
        invalid=$((invalid + 1))
    fi

    [[ "$found" -gt 0 ]] || die "Trace directory contains no JSON files: $trace_dir"
    [[ "$invalid" -eq 0 ]] || return 1
    if [[ "$quiet" != "true" ]]; then
        echo "Trace results valid: $found file(s)"
    fi
}

compare_trace_directory() {
    local trace_dir="$1"
    validate_trace_directory "$trace_dir" true

    local combined
    combined="$(mktemp "${TMPDIR:-/tmp}/framework-eval-traces.XXXXXX")"
    trap 'rm -f "$combined"' RETURN

    # Sorted input makes both array order and formatted JSON deterministic.
    while IFS= read -r trace_file; do
        jq -c . "$trace_file"
    done < <(find "$trace_dir" -maxdepth 1 -type f -name '*.json' -print | LC_ALL=C sort) \
        | jq -s 'sort_by(.case_id, .model, .variant, .run_id)' >"$combined"

    jq '
      def mean($values):
        if ($values | length) == 0 then null else ($values | add) / ($values | length) end;
      def metric_summary($runs; $name):
        {mean: mean([$runs[] | .metrics[$name]])};
      def variant_summary($all; $paired; $variant):
        [$paired[] | select(.variant == $variant)] as $runs
        | [$all[] | select(.variant == $variant and .status == "adapter_unavailable")] as $unavailable
        | [$runs[] | select(.metrics.acceptance_passed == true)] as $passed
        | {
            completed_runs: ($runs | length),
            adapter_unavailable_runs: ($unavailable | length),
            acceptance: {
              passed: ($passed | length),
              failed: (($runs | length) - ($passed | length)),
              rate: (if ($runs | length) == 0 then null else ($passed | length) / ($runs | length) end)
            },
            metrics: {
              input_tokens: metric_summary($runs; "input_tokens"),
              output_tokens: metric_summary($runs; "output_tokens"),
              latency_ms: metric_summary($runs; "latency_ms"),
              tool_calls: metric_summary($runs; "tool_calls"),
              question_mark_count_proxy: metric_summary($runs; "question_mark_count_proxy"),
              time_to_first_useful_action_ms: metric_summary($runs; "time_to_first_useful_action_ms"),
              rework_count: metric_summary($runs; "rework_count")
            }
          };
      def delta($baseline; $candidate):
        if $baseline == null or $candidate == null then
          {absolute: null, percent: null}
        else
          {
            absolute: ($candidate - $baseline),
            percent: (if $baseline == 0 then null else (($candidate - $baseline) / $baseline) * 100 end)
          }
        end;

      . as $all
      | [$all[] | select(.status == "completed")]
      | sort_by(.case_id, .model, .variant, .run_id)
      | group_by([.case_id, .model])
      | map(select(any(.[]; .variant == "baseline") and any(.[]; .variant == "candidate")))
      | (add // []) as $paired
      | variant_summary($all; $paired; "baseline") as $baseline
      | variant_summary($all; $paired; "candidate") as $candidate
      | {
          schema_version: "1.0",
          baseline_variant: "baseline",
          candidate_variant: "candidate",
          paired_case_models: ($paired | map([.case_id, .model]) | unique | length),
          variants: {
            baseline: $baseline,
            candidate: $candidate
          },
          deltas: {
            input_tokens: delta($baseline.metrics.input_tokens.mean; $candidate.metrics.input_tokens.mean),
            output_tokens: delta($baseline.metrics.output_tokens.mean; $candidate.metrics.output_tokens.mean),
            latency_ms: delta($baseline.metrics.latency_ms.mean; $candidate.metrics.latency_ms.mean),
            tool_calls: delta($baseline.metrics.tool_calls.mean; $candidate.metrics.tool_calls.mean),
            question_mark_count_proxy: delta($baseline.metrics.question_mark_count_proxy.mean; $candidate.metrics.question_mark_count_proxy.mean),
            time_to_first_useful_action_ms: delta($baseline.metrics.time_to_first_useful_action_ms.mean; $candidate.metrics.time_to_first_useful_action_ms.mean),
            rework_count: delta($baseline.metrics.rework_count.mean; $candidate.metrics.rework_count.mean),
            acceptance_rate: delta($baseline.acceptance.rate; $candidate.acceptance.rate)
          },
          adapter_unavailable_runs: [
            $all[]
            | select(.status == "adapter_unavailable")
            | {
                run_id,
                case_id,
                model,
                variant,
                error_code: .error.code
              }
          ]
        }
    ' "$combined"

    rm -f "$combined"
    trap - RETURN
}

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --validate-fixture)
            [[ -z "$MODE" ]] || die "Only one mode may be specified."
            MODE="validate"
            shift
            ;;
        --list)
            [[ -z "$MODE" ]] || die "Only one mode may be specified."
            MODE="list"
            shift
            ;;
        --emit-prompts)
            [[ -z "$MODE" ]] || die "Only one mode may be specified."
            [[ $# -ge 2 ]] || die "Missing directory for --emit-prompts."
            MODE="emit"
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --responses)
            [[ -z "$MODE" ]] || die "Only one mode may be specified."
            [[ $# -ge 2 ]] || die "Missing directory for --responses."
            MODE="responses"
            RESPONSES_DIR="$2"
            shift 2
            ;;
        --validate-traces)
            [[ -z "$MODE" ]] || die "Only one mode may be specified."
            [[ $# -ge 2 ]] || die "Missing directory for --validate-traces."
            MODE="validate-traces"
            TRACES_DIR="$2"
            shift 2
            ;;
        --compare-traces)
            [[ -z "$MODE" ]] || die "Only one mode may be specified."
            [[ $# -ge 2 ]] || die "Missing directory for --compare-traces."
            MODE="compare-traces"
            TRACES_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

case "$MODE" in
    validate)
        validate_fixture
        echo "Fixture valid: $FIXTURE"
        ;;
    list)
        list_cases
        ;;
    emit)
        emit_prompts
        ;;
    responses)
        grade_responses
        ;;
    validate-traces)
        require_jq
        validate_trace_directory "$TRACES_DIR"
        ;;
    compare-traces)
        require_jq
        compare_trace_directory "$TRACES_DIR"
        ;;
    *)
        die "No mode specified."
        ;;
esac
