#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"
source "$P0P4_SUITE_DIR/lib/response-fixture-preflight.sh"

preflight_test_root="$(mktemp -d "${TMPDIR:-/tmp}/response-preflight-test.XXXXXX")"
p0p4_register_cleanup "$preflight_test_root"
preflight_test_fixture="$preflight_test_root/cases.json"
cat >"$preflight_test_fixture" <<'JSON'
{"skill":"fixture-skill","cases":[
  {"id":"structured","machine_expectations":{"structured_json_assertions":[{}]}},
  {"id":"semantic","semantic_validator":"assistant-research.five_lens_v3","machine_expectations":{}},
  {"id":"text","machine_expectations":{}}
]}
JSON

preflight_test_builder() {
    mkdir -p "$1/fixture-skill"
    printf '{"status":"ok"}\n' >"$1/fixture-skill/structured.txt"
    printf '{"status":"ok"}\n' >"$1/fixture-skill/semantic.txt"
    printf 'Plain response.\n' >"$1/fixture-skill/text.txt"
    case "$preflight_test_mutation" in
        missing) rm "$1/fixture-skill/structured.txt" ;;
        empty) : >"$1/fixture-skill/text.txt" ;;
        whitespace) printf ' \n\t' >"$1/fixture-skill/text.txt" ;;
        malformed) printf '{broken' >"$1/fixture-skill/structured.txt" ;;
        multiple) printf '{}\n{}\n' >"$1/fixture-skill/structured.txt" ;;
        semantic_malformed) printf '{broken' >"$1/fixture-skill/semantic.txt" ;;
        semantic_multiple) printf '{}\n{}\n' >"$1/fixture-skill/semantic.txt" ;;
        exit_failure) return 1 ;;
        counted_failure) fail "fixture builder reported a failure" ;;
    esac
}

test_start "response preflight accepts complete assertion, semantic-validator, and plain fixtures"
preflight_test_mutation=valid
if p0p4_preflight_response_fixtures preflight_test_builder "$preflight_test_fixture" >"$preflight_test_root/valid.log" 2>&1; then
    pass
else
    fail "complete response fixtures were rejected"
fi

for preflight_test_mutation in missing empty whitespace malformed multiple semantic_malformed semantic_multiple exit_failure counted_failure; do
    test_start "response preflight rejects $preflight_test_mutation output"
    if p0p4_preflight_response_fixtures preflight_test_builder "$preflight_test_fixture" >"$preflight_test_root/$preflight_test_mutation.log" 2>&1; then
        fail "preflight accepted $preflight_test_mutation"
    else
        pass
    fi
done

test_start "response preflight cannot reuse files from an earlier builder invocation"
preflight_test_mutation=valid
preflight_empty_builder() { :; }
if p0p4_preflight_response_fixtures preflight_test_builder "$preflight_test_fixture" >/dev/null 2>&1 \
    && ! p0p4_preflight_response_fixtures preflight_empty_builder "$preflight_test_fixture" >"$preflight_test_root/stale.log" 2>&1; then
    pass
else
    fail "preflight reused stale files or rejected its valid control"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
