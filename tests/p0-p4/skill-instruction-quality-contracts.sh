if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

# Installed Codex path substitution is covered by installer-contracts.sh.
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

test_start "assistant-clarify preserves material questions, explicit choices, and partial answers"
clarify_skill="$FRAMEWORK_DIR/skills/assistant-clarify/SKILL.md"
chaotic_prompts="$FRAMEWORK_DIR/skills/assistant-clarify/chaotic-prompts.md"
clarify_failures=()
for file_and_term in \
    "$clarify_skill::Ask every material question that cannot be discovered and lacks an evidence-backed safe default" \
    "$clarify_skill::Reversibility, convention, and a plausible preference alone do not establish product intent" \
    "$clarify_skill::A recommendation is not consent" \
    "$clarify_skill::wait for an explicit answer before work that depends on a proposed product choice" \
    "$clarify_skill::After a partial answer, carry forward the answered decisions and reassess the rest" \
    "$clarify_skill::Continue clear, independent work while a decision remains open" \
    "$chaotic_prompts::Do not silently resolve unanswered choices"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        clarify_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
if grep -Eiq 'ask.{0,20}[1-3].{0,20}questions max|recommendation (is|means) consent' "$chaotic_prompts"; then
    clarify_failures+=("numeric question cap or inferred consent")
fi
if [[ ${#clarify_failures[@]} -eq 0 ]]; then
    pass
else
    fail "clarification decision safeguards failed: ${clarify_failures[*]}"
fi

test_start "assistant-workflow routes repository changes through requirements discovery"
workflow_skill="$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md"
if grep -Fq -- "backlog items" "$workflow_skill" \
    && grep -Fq -- "intended-change ideas" "$workflow_skill" \
    && p0p4_contains_text "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md" "Requirements sufficiency"; then
    pass
else
    fail "workflow must retain change-bearing activation and its requirements discovery guidance"
fi

test_start "assistant-review resolves mode from authorization and asks on ambiguity"
review_input="$FRAMEWORK_DIR/skills/assistant-review/contracts/input.yaml"
review_audit_failures=()
for term in \
    "semantic modification authority" \
    "carried active approved implementation workflow" \
    "authorship, branch/PR ownership, platform, or connector" \
    "Should I only report findings, or also implement and verify fixes?"; do
    if ! grep -Fq "$term" "$review_input"; then
        review_audit_failures+=("missing $term")
    fi
done

if grep -Fq "default: review-fix" "$review_input"; then
    review_audit_failures+=("must not default to review-fix")
fi

if [[ "${#review_audit_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review mode resolution must use authorization and ask on ambiguity: ${review_audit_failures[*]}"
fi

test_start "assistant-review gates fixes and normalizes review eval authority"
review_authorization_failures=()
review_loop="$FRAMEWORK_DIR/skills/assistant-review/references/review-loop.md"
review_router="$FRAMEWORK_DIR/skills/assistant-workflow/references/review-qa-router.md"
review_evals="$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json"
for file_and_term in \
    "$review_loop::Infer review mode before review or mutation" \
    "$review_loop::run only in" \
    "$review_loop::evidence-backed must-fix and should-fix items" \
    "$review_loop::Dispatch every planned read-only Reviewer pass" \
    "$review_loop::never expose the mismatch details to discovery siblings" \
    "$review_loop::Return it to the composing workflow for planning or approval" \
    "$review_router::Before Stage 1 Spec Review or source inspection/mutation" \
    "$review_router::only when review-fix authority is explicit or carried by the" \
    "$review_router::Audit mode reports findings without source changes" \
    "$review_router::In audit mode, report the mismatch without source changes" \
    "$review_router::only evidence-backed findings within authorized scope" \
    "$review_router::returns to planning or approval before any mutation"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq "$term" "$file"; then
        review_authorization_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done

if ! jq -e '
    def case($id): .cases[] | select(.id == $id);
    (case("audit-one-pass").expected_behavior | index("Reports findings and residual risk without edits.")) and
    (case("audit-spec-review-fail-is-read-only").expected_behavior | index("Dispatches every planned read-only Reviewer pass and exits without repair, Build, or source-mutation dispatch.")) and
    (case("review-fix-loop-handles-findings").expected_behavior | index("Uses the user\u0027s explicit source-modification authorization to resolve mode=review-fix.")) and
    (case("workflow-carried-authorization-allows-bounded-review-fix").expected_behavior | index("Resolves mode=review-fix from carried active approved workflow authorization.")) and
    (case("ambiguous-standalone-review-asks-before-review-or-mutation").expected_behavior | index("Asks exactly: Should I only report findings, or also implement and verify fixes?")) and
    (case("ambiguous-standalone-review-asks-before-review-or-mutation").machine_expectations.forbidden_substrings | index("I reviewed")) and
    (case("ambiguous-standalone-review-asks-before-review-or-mutation").machine_expectations.forbidden_substrings | index("I changed"))
' "$review_evals" >/dev/null; then
    review_authorization_failures+=("assistant-review evals lack explicit audit/fix/workflow authority or ambiguity guard")
fi

if [[ "${#review_authorization_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review execution authorization contract drifted: ${review_authorization_failures[*]}"
fi

test_start "assistant-ideate owns brainstorming description activation"
thinking_skill="$FRAMEWORK_DIR/skills/assistant-thinking/SKILL.md"
ideate_skill="$FRAMEWORK_DIR/skills/assistant-ideate/SKILL.md"
brainstorm_trigger_failures=()
if grep -Eiq '^description:.*brainstorm' "$thinking_skill"; then
    brainstorm_trigger_failures+=("assistant-thinking frontmatter still routes brainstorm")
fi
if ! grep -Eiq '^description:.*brainstorm' "$ideate_skill"; then
    brainstorm_trigger_failures+=("assistant-ideate frontmatter does not route brainstorm")
fi

if [[ "${#brainstorm_trigger_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "brainstorm prompts should route to ideate only: ${brainstorm_trigger_failures[*]}"
fi

test_start "current routing guidance separates discovery fields from post-activation instructions"
routing_readme="$FRAMEWORK_DIR/README.md"
routing_presentation="$FRAMEWORK_DIR/docs/presentation.md"
routing_guidance_failures=()
for file_and_term in \
    "$routing_readme::required native discovery fields" \
    "$routing_readme::body instructions apply after activation" \
    "$routing_readme::optional repository dependency metadata" \
    "$routing_presentation::name and description" \
    "$routing_presentation::body instructions apply after activation"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! grep -Fqi "$term" "$file"; then
        routing_guidance_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
for file_and_stale_term in \
    "$routing_readme::name, description, and instructions" \
    "$routing_presentation::metadata and instructions"; do
    file="${file_and_stale_term%%::*}"
    stale_term="${file_and_stale_term#*::}"
    if grep -Fqi "$stale_term" "$file"; then
        routing_guidance_failures+=("${file#$FRAMEWORK_DIR/}: stale $stale_term")
    fi
done
if [[ ${#routing_guidance_failures[@]} -eq 0 ]]; then
    pass
else
    fail "native routing guidance is stale: ${routing_guidance_failures[*]}"
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

test_start "assistant-workflow small plans can proceed without ritual approval"
workflow_small_failures=()
workflow_skill="$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md"
workflow_phases="$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"
workflow_output="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"
workflow_phase_gates="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"

for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/workflow-controller.md::Record the compact plan and continue without waiting" \
    "$workflow_output::not_required_small" \
    "$workflow_phase_gates::no-wait eligibility was recorded"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! grep -Fq "$term" "$file"; then
        workflow_small_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done

if [[ "${#workflow_small_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-workflow small plans must support no-wait approval: ${workflow_small_failures[*]}"
fi

test_start "control guidance retains actionable evidence and recovery"
missing_paired_guidance=()
review_skill="$FRAMEWORK_DIR/skills/assistant-review/SKILL.md"
review_principles="$FRAMEWORK_DIR/skills/assistant-review/references/review-principles.md"
tdd_skill="$FRAMEWORK_DIR/skills/assistant-tdd/SKILL.md"
tdd_gates="$FRAMEWORK_DIR/skills/assistant-tdd/contracts/phase-gates.yaml"
workflow_skill="$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md"
workflow_phases="$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"
for file_and_term in \
    "$review_principles::specific observation to concrete risk and the smallest durable fix" \
    "$review_principles::Do not infer a finding from code size" \
    "$tdd_gates::RED" \
    "$tdd_gates::REFACTOR" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/prompts/refactor-safety.md::Public API signatures unchanged" \
    "$workflow_phases::controller_intensity=strict"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        missing_paired_guidance+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
# TDD ownership and meaningful RED are consumed interfaces, not root heading names.
for term in bounded_executor separated_workers test_authoring production refactor; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/build-worker-protocol.md"; then
        missing_paired_guidance+=("build-worker-protocol: missing $term")
    fi
done
if [[ ${#missing_paired_guidance[@]} -eq 0 ]]; then
    pass
else
    fail "control guidance needs actionable evidence/recovery: ${missing_paired_guidance[*]}"
fi

test_start "assistant-review applies clean-code principles with evidence"
review_principle_failures=()
review_principles="$FRAMEWORK_DIR/skills/assistant-review/references/review-principles.md"
review_rubric="$FRAMEWORK_DIR/skills/assistant-review/references/review-rubric.md"
review_handoffs="$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml"
review_phases="$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml"
review_evals="$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json"
review_loop="$FRAMEWORK_DIR/skills/assistant-review/references/review-loop.md"

for file_and_term in \
    "$review_skill::references/review-principles.md" \
    "$review_rubric::SOLID, KISS, DRY, YAGNI, and readability" \
    "$review_principles::duplicated knowledge, not merely similar-looking code" \
    "$review_principles::YAGNI is not permission to neglect code health" \
    "$review_principles::Readability is a human judgment" \
    "$review_principles::smallest durable change" \
    "$review_rubric::right-sized SOLID/KISS/DRY/YAGNI adherence" \
    "$review_handoffs::quality_principles_required" \
    "$review_phases::references/review-principles.md" \
    "$review_evals::review-applies-clean-code-principles"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq "$term" "$file"; then
        review_principle_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done

if [[ "${#review_principle_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review clean-code principle lens is incomplete: ${review_principle_failures[*]}"
fi

test_start "assistant-review detects nullable properties used as hidden state"
nullable_state_failures=()

for file_and_term in \
    "$review_principles::## State and Extensibility Modeling" \
    "$review_principles::null -> value" \
    "$review_principles::business or lifecycle transition" \
    "$review_principles::optional or missing data" \
    "$review_evals::review-detects-null-encoded-state-transitions" \
    "$review_evals::explicit transition methods or events" \
    "$review_evals::genuine optional data"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq "$term" "$file"; then
        nullable_state_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done

if [[ "${#nullable_state_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review nullable hidden-state guidance is incomplete: ${nullable_state_failures[*]}"
fi

test_start "assistant-review distinguishes open-ended enums from closed sets"
enum_extension_failures=()

for file_and_term in \
    "$review_principles::### Enums as extension points" \
    "$review_principles::open-ended feature set" \
    "$review_principles::switches or conditionals in several places" \
    "$review_principles::small, stable, closed set" \
    "$review_evals::review-detects-enum-extension-traps" \
    "$review_evals::handlers, strategies" \
    "$review_evals::stable closed enum"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq "$term" "$file"; then
        enum_extension_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done

if [[ "${#enum_extension_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review enum extension guidance is incomplete: ${enum_extension_failures[*]}"
fi

test_start "assistant-review classifies authoritative duplicate behavior through bounded reuse search"
reuse_search_principle_failures=()
for file_and_term in \
    "$review_principles::## Reuse Search and Authoritative Duplication" \
    "$review_principles::business rules, validation, calculations/conversions, mappings, schema/config semantics, permissions, or protocol details" \
    "$review_principles::should-fix" \
    "$review_principles::must-fix" \
    "$review_principles::coincidental similarity" \
    "$review_principles::independent concepts" \
    "$review_principles::divergence control" \
    "$review_evals::review-reuse-search-authoritative-conversion" \
    "$review_evals::nautical-mile" \
    "$review_evals::duplicated mapper arithmetic" \
    "$review_evals::differing rounding" \
    "$review_evals::non-finding"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        reuse_search_principle_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
if [[ "${#reuse_search_principle_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review reuse-search principle/eval coverage is incomplete: ${reuse_search_principle_failures[*]}"
fi

test_start "assistant-review direct fallback does not require reviewer dispatch"
review_fallback_failures=()
review_output="$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml"

for file_and_term in \
    "$review_loop::Infer review mode before review or mutation" \
    "$review_loop::In direct fallback, start a fresh isolated pass with the same bounded bundle" \
    "$review_input::subagent_execution_mode" \
    "$review_input::direct_fallback" \
    "$review_output::review_delegation_path" \
    "$review_output::fresh direct-fallback context" \
    "$review_phases::RS1A" \
    "$review_phases::In direct fallback mode, complete" \
    "$review_handoffs::when subagent_execution_mode=delegated" \
    "$review_handoffs::Direct fallback uses the same review" \
    "$review_handoffs::In direct fallback mode, complete the local review evidence"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq "$term" "$file"; then
        review_fallback_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done

if [[ "${#review_fallback_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review direct fallback still implies mandatory Reviewer dispatch: ${review_fallback_failures[*]}"
fi

test_start "assistant-thinking dispatches from applicable delegation triggers and records evidenced fallback"
thinking_delegation_proof_failures=()
thinking_delegation_proof_terms=(
    "$thinking_skill::A direct user request or applicable AGENTS.md or active-skill instruction"
    "$thinking_skill::contracts/input.yaml"
    "$thinking_skill::contracts/output.yaml"
    "$thinking_skill::contracts/phase-gates.yaml"
    "$FRAMEWORK_DIR/skills/assistant-thinking/contracts/input.yaml::policy_blocking_source"
    "$FRAMEWORK_DIR/skills/assistant-thinking/contracts/input.yaml::delegation_triggered"
    "$FRAMEWORK_DIR/skills/assistant-thinking/contracts/input.yaml::delegated requires subagent_policy_state=delegation_triggered"
    "$FRAMEWORK_DIR/skills/assistant-thinking/contracts/input.yaml::sequential_fallback requires delegation_opted_out, subagents_unavailable after a real spawn failure or supported configuration proof, or policy_disallowed with policy_blocking_source"
    "$FRAMEWORK_DIR/skills/assistant-thinking/contracts/output.yaml::policy_blocking_source"
    "$FRAMEWORK_DIR/skills/assistant-thinking/contracts/output.yaml::sequential_fallback"
    "$FRAMEWORK_DIR/skills/assistant-thinking/contracts/phase-gates.yaml::policy_blocking_source"
    "$FRAMEWORK_DIR/skills/assistant-thinking/contracts/phase-gates.yaml::dispatch without a separate permission question"
    "$FRAMEWORK_DIR/skills/assistant-thinking/perspectives.md::SKILL.md#independence-and-delegation"
    "$FRAMEWORK_DIR/skills/assistant-thinking/perspectives.md::SKILL.md#integrated-and-structured-output"
    "$FRAMEWORK_DIR/skills/assistant-thinking/stress-test.md::SKILL.md#independence-and-delegation"
    "$FRAMEWORK_DIR/skills/assistant-thinking/stress-test.md::SKILL.md#integrated-and-structured-output"
    "$FRAMEWORK_DIR/skills/assistant-thinking/evals/cases.json::thinking-required-roles-dispatch-from-instruction-trigger"
    "$FRAMEWORK_DIR/skills/assistant-thinking/evals/cases.json::delegation_triggered"
    "$FRAMEWORK_DIR/skills/assistant-thinking/evals/cases.json::policy_blocking_source"
)
for file_and_term in "${thinking_delegation_proof_terms[@]}"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]]; then
        thinking_delegation_proof_failures+=("${file#$FRAMEWORK_DIR/}: file missing")
    elif ! grep -Fq -- "$term" "$file"; then
        thinking_delegation_proof_failures+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
for method_file in \
    "$FRAMEWORK_DIR/skills/assistant-thinking/perspectives.md" \
    "$FRAMEWORK_DIR/skills/assistant-thinking/stress-test.md"; do
    if grep -Fq -- "If denied, unavailable, or policy-disallowed" "$method_file"; then
        thinking_delegation_proof_failures+=("${method_file#$FRAMEWORK_DIR/}: loose fallback wording")
    fi
done
if [[ "${#thinking_delegation_proof_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-thinking delegation fallback must carry trigger or policy-block evidence: ${thinking_delegation_proof_failures[*]}"
fi

test_start "assistant-review v7 prompts preserve deferred-QA and security-specialist routing"
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
    'schema_version: "8.0"' \
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

p0p4_finish_suite "${BASH_SOURCE[0]}"
