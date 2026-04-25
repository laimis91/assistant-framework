#!/usr/bin/env bash
# Provider-neutral local runner for Assistant Framework instruction eval fixtures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURE="$REPO_ROOT/docs/evals/framework-instruction-cases.json"
MODE=""
OUTPUT_DIR=""
RESPONSES_DIR=""

usage() {
    cat <<'EOF'
Usage:
  run-framework-instruction-evals.sh --validate-fixture
  run-framework-instruction-evals.sh --list
  run-framework-instruction-evals.sh --emit-prompts DIR
  run-framework-instruction-evals.sh --responses DIR
  run-framework-instruction-evals.sh --help

Runs offline, provider-neutral helpers for docs/evals/framework-instruction-cases.json.
No provider SDKs, network calls, or model APIs are used.

Options:
  --validate-fixture   Validate fixture schema and case shape.
  --list               Print case id, category, and title as tab-separated lines.
  --emit-prompts DIR   Write one Markdown prompt packet per case into DIR.
  --responses DIR      Heuristically grade local response files from DIR.
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
                 case_string_array($index; "fail_signals")
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
            def bullets($items): $items | map("- " + .) | join("\n");
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
              + "## Fail Signals\n\n" + bullets(.fail_signals) + "\n"
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

grade_responses() {
    validate_fixture
    [[ -d "$RESPONSES_DIR" ]] || die "Response directory does not exist: $RESPONSES_DIR"

    local total=0
    local passed=0
    local failed=0
    local missing=0
    local empty=0
    local signal_failures=0
    local id category title response_path fail_signal_hits status reason

    echo "Heuristic/local grading only. No provider API is invoked."
    echo ""

    while IFS=$'\t' read -r id category title; do
        total=$((total + 1))
        response_path="$(first_response_path_for_case "$id")"
        status="PASS"
        reason="non-empty response with no exact fail-signal phrase hits"

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
            if [[ "$fail_signal_hits" -gt 0 ]]; then
                status="FAIL"
                reason="$fail_signal_hits exact fail-signal phrase hit(s)"
                signal_failures=$((signal_failures + 1))
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
    printf 'Summary: total=%s passed=%s failed=%s missing=%s empty=%s fail_signal_hits=%s\n' \
        "$total" "$passed" "$failed" "$missing" "$empty" "$signal_failures"

    [[ "$failed" -eq 0 ]]
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
    *)
        die "No mode specified."
        ;;
esac
