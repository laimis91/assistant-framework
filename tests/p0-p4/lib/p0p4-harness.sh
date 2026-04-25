#!/usr/bin/env bash
# Shared harness for P0-P4 contract suites.

set -euo pipefail

P0P4_HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P0P4_SUITE_DIR="$(cd "$P0P4_HARNESS_DIR/.." && pwd)"
SCRIPT_DIR="$(cd "$P0P4_SUITE_DIR/.." && pwd)"
FRAMEWORK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

P0P4_HARNESS_LOADED=1
PASS=0
FAIL=0
P0P4_CLEANUP_PATHS=()

p0p4_abs_path() {
    local path="$1"
    local dir
    dir="$(cd "$(dirname -- "$path")" && pwd)"
    printf '%s/%s\n' "$dir" "$(basename -- "$path")"
}

p0p4_bootstrap_suite() {
    local suite_source
    suite_source="$(p0p4_abs_path "$1")"
    if [[ -z "${P0P4_DIRECT_SUITE_SOURCE:-}" && "$suite_source" == "$(p0p4_abs_path "$0")" ]]; then
        P0P4_DIRECT_SUITE_SOURCE="$suite_source"
    fi
}

p0p4_finish_suite() {
    local suite_source
    suite_source="$(p0p4_abs_path "$1")"
    if [[ "${P0P4_DIRECT_SUITE_SOURCE:-}" == "$suite_source" ]]; then
        finish
    fi
}

p0p4_register_cleanup() {
    local path
    for path in "$@"; do
        if [[ -n "$path" ]]; then
            P0P4_CLEANUP_PATHS+=("$path")
        fi
    done
}

p0p4_cleanup() {
    local path
    for path in "${P0P4_CLEANUP_PATHS[@]:-}"; do
        if [[ -n "$path" ]]; then
            rm -rf "$path"
        fi
    done
}

trap p0p4_cleanup EXIT

p0p4_install_codex_fixture() {
    local install_home="$1"
    local install_out="$2"
    local install_err="$3"
    shift 3

    HOME="$install_home" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow "$@" >"$install_out" 2>"$install_err"
}

test_start() {
    printf '  - %s ... ' "$1"
}

pass() {
    echo "ok"
    PASS=$((PASS + 1))
}

fail() {
    echo "fail: $1"
    FAIL=$((FAIL + 1))
}

finish() {
    echo ""
    echo "P0-P4 Contract Tests"
    echo "===================="
    echo "  Passed: $PASS"
    echo "  Failed: $FAIL"
    if [[ "$FAIL" -gt 0 ]]; then
        exit 1
    fi
}

count_occurrences() {
    local pattern="$1"
    local file="$2"
    grep -c "$pattern" "$file" 2>/dev/null || true
}

field_required_true_after_anchor() {
    local file="$1"
    local anchor="$2"
    local field="$3"
    awk -v anchor="$anchor" -v field="$field" '
        index($0, anchor) { in_anchor = 1; next }
        in_anchor && /^      - name: / { exit }
        in_anchor && $0 == "          - name: " field { in_field = 1; next }
        in_field && /required: true/ { found = 1; exit }
        in_field && /^          - name: / { in_field = 0 }
        END { exit found ? 0 : 1 }
    ' "$file"
}

handoff_return_field_required() {
    local file="$1"
    local handoff="$2"
    local field="$3"
    awk -v handoff="$handoff" -v field="$field" '
        $0 == "  - name: " handoff { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && /^    return_fields:/ { in_return = 1; next }
        in_return && $0 == "      - name: " field { in_field = 1; next }
        in_field && /required: true/ { found = 1; exit }
        in_field && /^      - name: / { exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

handoff_return_field_present() {
    local file="$1"
    local handoff="$2"
    local field="$3"
    awk -v handoff="$handoff" -v field="$field" '
        $0 == "  - name: " handoff { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && /^    return_fields:/ { in_return = 1; next }
        in_return && $0 == "      - name: " field { found = 1; exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

handoff_return_field_has_condition() {
    local file="$1"
    local handoff="$2"
    local field="$3"
    local condition="$4"
    awk -v handoff="$handoff" -v field="$field" -v condition="$condition" '
        $0 == "  - name: " handoff { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && /^    return_fields:/ { in_return = 1; next }
        in_return && $0 == "      - name: " field { in_field = 1; next }
        in_field && index($0, condition) { found = 1; exit }
        in_field && /^      - name: / { exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

handoff_return_field_has_line() {
    local file="$1"
    local handoff="$2"
    local field="$3"
    local expected="$4"
    awk -v handoff="$handoff" -v field="$field" -v expected="$expected" '
        $0 == "  - name: " handoff { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && /^    return_fields:/ { in_return = 1; next }
        in_return && $0 == "      - name: " field { in_field = 1; next }
        in_field && index($0, expected) { found = 1; exit }
        in_field && /^      - name: / { exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

handoff_return_field_has_direct_line() {
    local file="$1"
    local handoff="$2"
    local field="$3"
    local expected="$4"
    awk -v handoff="$handoff" -v field="$field" -v expected="$expected" '
        $0 == "  - name: " handoff { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && /^    return_fields:/ { in_return = 1; next }
        in_return && $0 == "      - name: " field { in_field = 1; next }
        in_field && /^        object_fields:/ { exit }
        in_field && index($0, expected) { found = 1; exit }
        in_field && /^      - name: / { exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

handoff_return_object_field_has_line() {
    local file="$1"
    local handoff="$2"
    local object_field="$3"
    local nested_field="$4"
    local expected="$5"
    awk -v handoff="$handoff" -v object_field="$object_field" -v nested_field="$nested_field" -v expected="$expected" '
        $0 == "  - name: " handoff { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && /^    return_fields:/ { in_return = 1; next }
        in_return && $0 == "      - name: " object_field { in_object = 1; next }
        in_object && /^      - name: / { exit }
        in_object && $0 == "          - name: " nested_field { in_nested = 1; next }
        in_nested && index($0, expected) { found = 1; exit }
        in_nested && /^          - name: / { exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

codewriter_current_task_packet_field_required() {
    local file="$1"
    local field="$2"
    awk -v field="$field" '
        $0 == "  - name: orchestrator_to_code_writer" { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && $0 == "      - name: current_task_packet" { in_packet = 1; next }
        in_packet && $0 == "          - name: " field { in_field = 1; next }
        in_field && /required: true/ { found = 1; exit }
        in_field && /^          - name: / { exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

codewriter_red_evidence_field_required() {
    local file="$1"
    local field="$2"
    awk -v field="$field" '
        $0 == "  - name: orchestrator_to_code_writer" { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && $0 == "      - name: current_task_packet" { in_packet = 1; next }
        in_packet && $0 == "          - name: red_evidence" { in_red = 1; next }
        in_red && $0 == "              - name: " field { in_field = 1; next }
        in_field && /required: true/ { found = 1; exit }
        in_field && /^              - name: / { exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

codewriter_red_evidence_has_line() {
    local file="$1"
    local expected="$2"
    awk -v expected="$expected" '
        $0 == "  - name: orchestrator_to_code_writer" { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && $0 == "      - name: current_task_packet" { in_packet = 1; next }
        in_packet && $0 == "          - name: red_evidence" { in_red = 1; next }
        in_red && index($0, expected) { found = 1; exit }
        in_red && $0 == "          - name: implementation_notes" { exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

protocol_status_present() {
    local file="$1"
    local status="$2"
    awk -v status="$status" '
        /^worker_status_protocol:/ { in_protocol = 1; next }
        in_protocol && /^handoffs:/ { exit }
        in_protocol && $0 == "    - value: " status { found = 1; exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}
