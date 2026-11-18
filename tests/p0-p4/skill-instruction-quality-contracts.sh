if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

# This suite stays focused on source skill instruction quality.

p0p4_root_skill_files() {
    find "$FRAMEWORK_DIR/skills" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -path "$FRAMEWORK_DIR/skills/assistant-*/SKILL.md" -print | sort
}

test_start "root skill inventory is filesystem based and limited to assistant skills"
skill_inventory="$(p0p4_root_skill_files)"
non_assistant_inventory_skills=()
while IFS= read -r skill_file; do
    if [[ -z "$skill_file" ]]; then
        continue
    fi

    rel_path="${skill_file#$FRAMEWORK_DIR/}"
    if [[ "$rel_path" != skills/assistant-*/SKILL.md ]]; then
        non_assistant_inventory_skills+=("$rel_path")
    fi
done <<< "$skill_inventory"
if [[ -z "$skill_inventory" ]]; then
    fail "root skill inventory did not find assistant-* skills"
elif [[ "${#non_assistant_inventory_skills[@]}" -eq 0 ]]; then
    pass
else
    fail "root skill inventory should include only assistant-* skills: ${non_assistant_inventory_skills[*]}"
fi

# Root headings and prompt-only YAML envelopes are not public interfaces.
# The skill validator covers metadata and referenced contracts; preserve behavior here.

test_start "assistant-thinking owns brainstorming description activation"
thinking_skill="$FRAMEWORK_DIR/skills/assistant-thinking/SKILL.md"
brainstorm_trigger_failures=()
if ! grep -Eiq '^description:.*brainstorm' "$thinking_skill"; then
    brainstorm_trigger_failures+=("assistant-thinking frontmatter does not route brainstorm")
fi
for skill_file in "$FRAMEWORK_DIR"/skills/*/SKILL.md; do
    [[ "$skill_file" == "$thinking_skill" ]] && continue
    if grep -Eiq '^description:.*brainstorm' "$skill_file"; then
        brainstorm_trigger_failures+=("$(basename "$(dirname "$skill_file")") frontmatter also routes brainstorm")
    fi
done

if [[ "${#brainstorm_trigger_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "brainstorm prompts should route to thinking only: ${brainstorm_trigger_failures[*]}"
fi

test_start "assistant-workflow routes concrete dev creation without stealing brainstorming"
workflow_skill="$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md"
workflow_creation_failures=()
workflow_description="$(awk -F'"' '/^description:/ { print $2; exit }' "$workflow_skill")"
for term in plan build implement; do
    if ! printf '%s\n' "$workflow_description" | grep -Fqi "$term"; then
        workflow_creation_failures+=("description does not cover $term")
    fi
done
if printf '%s\n' "$workflow_description" | grep -Fqi 'brainstorm'; then
    workflow_creation_failures+=("description steals brainstorming")
fi

if [[ "${#workflow_creation_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-workflow dev creation routing failed: ${workflow_creation_failures[*]}"
fi

review_output="$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml"
test_start "assistant-review v7 prompts preserve deferred-QA and security-specialist routing"
review_rubric="$FRAMEWORK_DIR/skills/assistant-review/references/review-rubric.md"
review_handoffs="$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml"
review_v7_prompt_failures=()
qa_evaluator_agents=(
    "$FRAMEWORK_DIR/agents/claude/qa-evaluator.md"
    "$FRAMEWORK_DIR/agents/codex/qa-evaluator.toml"
)
for review_agent in "${qa_evaluator_agents[@]}"; do
    for review_term in \
        "approved_feature_preparation_qa_acceptance_obligation_result" \
        "requested_scope_status" \
        "execution_prerequisite_status" \
        "accepted_with_concerns" \
        "HAS_REMAINING_ITEMS"; do
        if ! grep -Fq "$review_term" "$review_agent"; then
            review_v7_prompt_failures+=("${review_agent#$FRAMEWORK_DIR/}: missing $review_term")
        fi
    done
done
for reviewer_agent in \
    "$FRAMEWORK_DIR/agents/claude/code-reviewer.md" \
    "$FRAMEWORK_DIR/agents/claude/reviewer.md" \
    "$FRAMEWORK_DIR/agents/codex/code-reviewer.toml" \
    "$FRAMEWORK_DIR/agents/codex/reviewer.toml"; do
    for review_term in \
        "risk_selected_specialist" \
        "assistant-security" \
        "canonical Reviewer schema"; do
        if ! grep -Fq "$review_term" "$reviewer_agent"; then
            review_v7_prompt_failures+=("${reviewer_agent#$FRAMEWORK_DIR/}: missing $review_term")
        fi
    done
done
for review_term in \
    'schema_version: "11.0"' \
    "risk_selected_specialist" \
    "assistant-security"; do
    if ! grep -Fq "$review_term" "$review_handoffs"; then
        review_v7_prompt_failures+=("skills/assistant-review/contracts/handoffs.yaml: missing $review_term")
    fi
done
if [[ "$(grep -F 'weighted_score = ' "$review_rubric" | wc -l | tr -d ' ')" -ne 1 ]] \
    || ! grep -Fq 'Example: correctness=4, quality=3.5, architecture=4, security=5, coverage=3' "$review_rubric" \
    || ! grep -Fq '= (4 * 0.30) + (3.5 * 0.20) + (4 * 0.20) + (5 * 0.15) + (3 * 0.15)' "$review_rubric" \
    || ! grep -Fq '= 1.20 + 0.70 + 0.80 + 0.75 + 0.45' "$review_rubric" \
    || ! grep -Fq '= 3.90 → REFINE' "$review_rubric" \
    || ! grep -Fq '  weighted_score: 3.90' "$review_rubric" \
    || ! grep -Fq '(4.0 * 0.30) + (3.5 * 0.20)' "$FRAMEWORK_DIR/skills/assistant-review/references/score-tracking.md"; then
    review_v7_prompt_failures+=("assistant-review rubric arithmetic is not canonically 3.90")
fi
if [[ "${#review_v7_prompt_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review v7 prompt/rubric parity failed: ${review_v7_prompt_failures[*]}"
fi

test_start "assistant-advisory-triage keeps a shipped-release close bar and read-only authority"
triage_skill="$FRAMEWORK_DIR/skills/assistant-advisory-triage/SKILL.md"
triage_failures=()
for triage_term in \
    "close" \
    "keep open" \
    "keep open but narrow" \
    "fixed on main" \
    "shipped release" \
    "is never by itself a reason to close" \
    "Triage is read-only by default" \
    "only when the user's task authorizes that specific action" \
    "post nothing" \
    "do not close on that assumption" \
    "assistant-security" \
    "assistant-workflow" \
    "draft"; do
    if ! p0p4_contains_text "$triage_skill" "$triage_term"; then
        triage_failures+=("skills/assistant-advisory-triage/SKILL.md: missing $triage_term")
    fi
done
if [[ -f "$triage_skill" ]]; then
    for banned_term in "OpenClaw" "Peter" "Cyber Classifier"; do
        if grep -Fqi -- "$banned_term" "$triage_skill"; then
            triage_failures+=("skills/assistant-advisory-triage/SKILL.md: contains $banned_term")
        fi
    done
    if grep -Eqi 'pbcopy|clipboard' "$triage_skill"; then
        triage_failures+=("skills/assistant-advisory-triage/SKILL.md: mentions clipboard actions")
    fi
    if grep -Eq '^requires:' "$triage_skill"; then
        triage_failures+=("skills/assistant-advisory-triage/SKILL.md: declares requires")
    fi
fi
if [[ "${#triage_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-advisory-triage close bar and authority guidance failed: ${triage_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
