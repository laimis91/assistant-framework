if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"


# The creative method guides human-facing option generation; it is not a serialized interface.
thinking_options_response_matches() {
    local responses_dir="$1"
    local expected="$2"
    local output
    if output="$("$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$responses_dir" --skill assistant-thinking --case quick-improvement-scan-uses-light-mode 2>&1)"; then
        [[ "$expected" == PASS ]] || return 1
    else
        [[ "$expected" == FAIL ]] || return 1
    fi
    grep -Fq "$expected"$'\tassistant-thinking\tquick-improvement-scan-uses-light-mode' <<<"$output"
}

test_start "quick option-scan grader accepts a useful comparison and rejects invented action"
thinking_options_responses="$(mktemp -d "${TMPDIR:-/tmp}/thinking-quick-eval.XXXXXX")"
p0p4_register_cleanup "$thinking_options_responses"
mkdir -p "$thinking_options_responses/assistant-thinking"
thinking_options_response="$thinking_options_responses/assistant-thinking/quick-improvement-scan-uses-light-mode.txt"
cat >"$thinking_options_response" <<'RESPONSE'
1. Tighten overlapping descriptions. This makes routing intent clearer; the trade-off is checking nearby requests for regressions.
2. Reuse activation fixtures to expose false positives. This offers stronger evidence but needs observed native selections.
Recommended next step: inspect the overlapping descriptions and validate their existing positive and negative requests. Neither option adds standing instructions.
RESPONSE
thinking_options_valid_response="$(cat "$thinking_options_response")"
thinking_options_grader_failures=()
if ! thinking_options_response_matches "$thinking_options_responses" PASS; then
    thinking_options_grader_failures+=("useful concise comparison rejected")
fi
for unsafe_claim in 'user_decision: selected' 'I started implementing'; do
    printf '%s\n%s\n' "$thinking_options_valid_response" "$unsafe_claim" >"$thinking_options_response"
    if ! thinking_options_response_matches "$thinking_options_responses" FAIL; then
        thinking_options_grader_failures+=("invented choice/action accepted: $unsafe_claim")
    fi
done
if [[ ${#thinking_options_grader_failures[@]} -eq 0 ]]; then
    pass
else
    fail "option-generation fixture controls failed: ${thinking_options_grader_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
