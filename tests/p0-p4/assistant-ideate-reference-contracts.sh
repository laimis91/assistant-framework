if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

ideate_skill="$FRAMEWORK_DIR/skills/assistant-ideate/SKILL.md"
ideate_reference="$FRAMEWORK_DIR/skills/assistant-ideate/references/ideation-pipeline.md"
ideate_deep_reference="$FRAMEWORK_DIR/skills/assistant-ideate/references/deep-ideation.md"
ideate_evals="$FRAMEWORK_DIR/skills/assistant-ideate/evals/cases.json"

# These references guide human-facing ideation; they are not serialized interfaces.
test_start "assistant-ideate routes optional detail and preserves constraints"
ideate_reference_failures=()
for file_and_term in \
    "$ideate_skill::references/ideation-pipeline.md" \
    "$ideate_skill::references/deep-ideation.md" \
    "$ideate_skill::Respect prior attempts" \
    "$ideate_reference::Use a quick comparison for a quick scan" \
    "$ideate_reference::Respect existing capabilities and prior attempts" \
    "$ideate_deep_reference::Keep hard constraints and prior attempts visible" \
    "$ideate_deep_reference::justify them and do not imply numerical precision from guesses"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        ideate_reference_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
if [[ ${#ideate_reference_failures[@]} -eq 0 ]]; then
    pass
else
    fail "ideation reference guidance is incomplete: ${ideate_reference_failures[*]}"
fi

test_start "assistant-ideate distinguishes recommendations from user choices"
if p0p4_contains_text "$ideate_skill" "Record a decision only after an explicit choice" \
    && p0p4_contains_text "$ideate_skill" "stop before unrequested implementation or persistence" \
    && p0p4_contains_text "$ideate_reference" "A recommendation does not record a user decision" \
    && jq -e '
        .cases[] | select(.id == "quick-improvement-scan-uses-light-mode") |
        (.machine_expectations.forbidden_substrings | index("user_decision: selected")) and
        (.machine_expectations.forbidden_substrings | index("I started implementing"))
    ' "$ideate_evals" >/dev/null; then
    pass
else
    fail "ideation must preserve explicit choice and implementation authority"
fi

ideate_response_matches() {
    local responses_dir="$1"
    local expected="$2"
    local output
    if output="$("$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$responses_dir" --skill assistant-ideate --case quick-improvement-scan-uses-light-mode 2>&1)"; then
        [[ "$expected" == PASS ]] || return 1
    else
        [[ "$expected" == FAIL ]] || return 1
    fi
    grep -Fq "$expected"$'\tassistant-ideate\tquick-improvement-scan-uses-light-mode' <<<"$output"
}

test_start "quick ideation grader accepts a useful comparison and rejects invented action"
ideate_responses="$(mktemp -d "${TMPDIR:-/tmp}/ideate-quick-eval.XXXXXX")"
p0p4_register_cleanup "$ideate_responses"
mkdir -p "$ideate_responses/assistant-ideate"
ideate_response="$ideate_responses/assistant-ideate/quick-improvement-scan-uses-light-mode.txt"
cat >"$ideate_response" <<'RESPONSE'
1. Tighten overlapping descriptions. This makes routing intent clearer; the trade-off is checking nearby requests for regressions.
2. Reuse activation fixtures to expose false positives. This offers stronger evidence but needs observed native selections.
Recommended next step: inspect the overlapping descriptions and validate their existing positive and negative requests. Neither option adds standing instructions.
RESPONSE
ideate_valid_response="$(cat "$ideate_response")"
ideate_grader_failures=()
if ! ideate_response_matches "$ideate_responses" PASS; then
    ideate_grader_failures+=("useful concise comparison rejected")
fi
for unsafe_claim in 'user_decision: selected' 'I started implementing'; do
    printf '%s\n%s\n' "$ideate_valid_response" "$unsafe_claim" >"$ideate_response"
    if ! ideate_response_matches "$ideate_responses" FAIL; then
        ideate_grader_failures+=("invented choice/action accepted: $unsafe_claim")
    fi
done
if [[ ${#ideate_grader_failures[@]} -eq 0 ]]; then
    pass
else
    fail "ideation fixture controls failed: ${ideate_grader_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
