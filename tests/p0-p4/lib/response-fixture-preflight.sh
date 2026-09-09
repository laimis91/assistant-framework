#!/usr/bin/env bash

# Completeness only: the owning suites still perform semantic grading.
# Run builders in a fresh directory and subshell so prior files and harness
# counters cannot make a missing handler appear successful.
p0p4_preflight_response_fixtures() {
    local builder="$1" fixture root skill case_id structured response
    local failures_before="${FAIL:-0}" invalid=0
    shift
    [[ "$#" -gt 0 ]] || { echo "No response fixtures selected" >&2; return 1; }
    root="$(mktemp -d "${TMPDIR:-/tmp}/response-fixture-preflight.XXXXXX")" || return 1
    p0p4_register_cleanup "$root"
    mkdir -p "$root/responses" || return 1
    for fixture in "$@"; do
        if ! jq -e '
          (.skill | type == "string" and length > 0)
          and (.cases | type == "array" and length > 0)
          and all(.cases[]; .id | type == "string" and length > 0)
        ' "$fixture" >/dev/null; then
            echo "Invalid response fixture inventory: $fixture" >&2
            return 1
        fi
        jq -r '.skill as $skill | .cases[] |
          [$skill,.id,((.machine_expectations.structured_json_assertions // [] | length) > 0
            or .semantic_validator != null)] | @tsv
        ' "$fixture" >>"$root/cases.tsv" || return 1
    done
    if ! (
        "$builder" "$root/responses" || exit 1
        [[ "${FAIL:-0}" -eq "$failures_before" ]]
    ) >"$root/builder.log" 2>&1; then
        cat "$root/builder.log" >&2
        echo "Response fixture builder failed: $builder" >&2
        return 1
    fi
    while IFS=$'\t' read -r skill case_id structured; do
        response="$root/responses/$skill/$case_id.txt"
        if [[ ! -s "$response" ]] || ! grep -q '[^[:space:]]' "$response"; then
            echo "Missing or empty response fixture: $skill/$case_id" >&2
            invalid=1
        elif [[ "$structured" == true ]] && ! jq -e -s 'length == 1' "$response" >/dev/null 2>&1; then
            echo "Expected one JSON value for structured response fixture: $skill/$case_id" >&2
            invalid=1
        fi
    done <"$root/cases.tsv"
    [[ "$invalid" -eq 0 ]]
}
