if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

thinking_skill="$FRAMEWORK_DIR/skills/assistant-thinking/SKILL.md"
thinking_creative="$FRAMEWORK_DIR/skills/assistant-thinking/creative.md"
thinking_evals="$FRAMEWORK_DIR/skills/assistant-thinking/evals/cases.json"

# The creative method guides human-facing option generation; it is not a serialized interface.
test_start "assistant-thinking creative method keeps light and deep option generation and preserves constraints"
options_reference_failures=()
for file_and_term in \
    "$thinking_skill::\`creative.md\`" \
    "$thinking_creative::## Light" \
    "$thinking_creative::## Deep" \
    "$thinking_creative::Stop there." \
    "$thinking_creative::do not run a ritual repository scan" \
    "$thinking_creative::Keep hard constraints and prior attempts visible" \
    "$thinking_creative::do not re-propose a rejected approach unchanged" \
    "$thinking_creative::Keep generation apart from evaluation" \
    "$thinking_creative::without idea or candidate quotas" \
    "$thinking_creative::justify them"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        options_reference_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
for once_term in "try inversion or a different analogy" "numerical precision"; do
    if [[ "$(grep -o -i -F -- "$once_term" "$thinking_creative" | wc -l | tr -d ' ')" -ne 1 ]]; then
        options_reference_failures+=("creative.md must state '$once_term' exactly once")
    fi
done
if [[ -e "$FRAMEWORK_DIR/skills/assistant-thinking/ideation-pipeline.md" ]] \
    || [[ -e "$FRAMEWORK_DIR/skills/assistant-thinking/references/ideation-pipeline.md" ]]; then
    options_reference_failures+=("duplicate ideation-pipeline.md copied into assistant-thinking")
fi
if [[ ${#options_reference_failures[@]} -eq 0 ]]; then
    pass
else
    fail "creative.md lacks light mode stop rule or option-generation guidance: ${options_reference_failures[*]}"
fi

test_start "assistant-thinking distinguishes option recommendations from user choices"
if p0p4_contains_text "$thinking_creative" "A recommendation is not the user's choice" \
    && p0p4_contains_text "$thinking_creative" "Record a decision only after an explicit choice" \
    && p0p4_contains_text "$thinking_creative" "stop before unrequested implementation or persistence" \
    && p0p4_contains_text "$thinking_creative" "Offer a choice packet only when requested or needed" \
    && jq -e '
        .cases[] | select(.id == "quick-improvement-scan-uses-light-mode") |
        (.machine_expectations.forbidden_substrings | index("user_decision: selected")) and
        (.machine_expectations.forbidden_substrings | index("I started implementing"))
    ' "$thinking_evals" >/dev/null; then
    pass
else
    fail "option generation must preserve explicit choice and implementation authority"
fi

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
