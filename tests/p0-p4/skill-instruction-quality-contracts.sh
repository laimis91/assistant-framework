if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

# Installed Codex path substitution is covered by installer-contracts.sh.
# This suite stays focused on source skill instruction quality.

p0p4_root_skill_files() {
    find "$FRAMEWORK_DIR/skills" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -path "$FRAMEWORK_DIR/skills/assistant-*/SKILL.md" -print | sort
}

p0p4_section_has_term() {
    local file="$1"
    local heading="$2"
    local term="$3"

    awk -v heading="$heading" -v term="$term" '
        $0 == heading { in_section = 1; next }
        in_section && /^## / { exit }
        in_section && index($0, term) { found = 1; exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

p0p4_required_fields_missing_behavior_count() {
    local file="$1"

    awk '
        /^  - name:/ {
            if (in_required && !has_on_missing) {
                missing++
            }
            in_required = 0
            has_on_missing = 0
        }
        /^    required:[[:space:]]*true[[:space:]]*$/ {
            in_required = 1
        }
        /^    on_missing:/ {
            has_on_missing = 1
        }
        END {
            if (in_required && !has_on_missing) {
                missing++
            }
            print missing + 0
        }
    ' "$file"
}

p0p4_required_artifacts_failure_behavior_count() {
    local file="$1"

    awk '
        /^  - name:/ {
            if (in_required && !has_failure_behavior) {
                missing++
            }
            in_required = 0
            has_failure_behavior = 0
        }
        /^    required:[[:space:]]*true[[:space:]]*$/ {
            in_required = 1
        }
        /^    (on_fail:|validation:)/ {
            has_failure_behavior = 1
        }
        END {
            if (in_required && !has_failure_behavior) {
                missing++
            }
            print missing + 0
        }
    ' "$file"
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

test_start "root skills declare outcome-shaped sections"
missing_skill_sections=()
required_skill_sections=(
    "## Goal"
    "## Success Criteria"
    "## Constraints"
    "## Output"
    "## Stop Rules"
)
while IFS= read -r skill_file; do
    rel_path="${skill_file#$FRAMEWORK_DIR/}"
    for heading in "${required_skill_sections[@]}"; do
        if ! grep -Eq "^${heading}[[:space:]]*$" "$skill_file"; then
            missing_skill_sections+=("$rel_path: $heading")
        fi
    done
done < <(p0p4_root_skill_files)
if [[ "${#missing_skill_sections[@]}" -eq 0 ]]; then
    pass
else
    fail "root SKILL.md files need outcome-shaped root sections: ${missing_skill_sections[*]}"
fi

test_start "assistant-clarify declares utility input and output contracts"
clarify_skill="$FRAMEWORK_DIR/skills/assistant-clarify/SKILL.md"
clarify_input="$FRAMEWORK_DIR/skills/assistant-clarify/contracts/input.yaml"
clarify_output="$FRAMEWORK_DIR/skills/assistant-clarify/contracts/output.yaml"
clarify_contract_failures=()

for contract_file in "$clarify_input" "$clarify_output"; do
    if [[ ! -f "$contract_file" ]]; then
        clarify_contract_failures+=("${contract_file#$FRAMEWORK_DIR/}: missing")
    fi
done

if [[ -f "$clarify_input" ]]; then
    for term in \
        'schema_version: "1.0"' \
        "contract: input" \
        "skill: assistant-clarify" \
        "on_missing:"; do
        if ! grep -Fq "$term" "$clarify_input"; then
            clarify_contract_failures+=("skills/assistant-clarify/contracts/input.yaml missing $term")
        fi
    done

    if [[ "$(p0p4_required_fields_missing_behavior_count "$clarify_input")" -ne 0 ]]; then
        clarify_contract_failures+=("skills/assistant-clarify/contracts/input.yaml has required fields without on_missing")
    fi
fi

if [[ -f "$clarify_output" ]]; then
    for term in \
        'schema_version: "1.0"' \
        "contract: output" \
        "skill: assistant-clarify" \
        "on_fail:"; do
        if ! grep -Fq "$term" "$clarify_output"; then
            clarify_contract_failures+=("skills/assistant-clarify/contracts/output.yaml missing $term")
        fi
    done

    if [[ "$(p0p4_required_artifacts_failure_behavior_count "$clarify_output")" -ne 0 ]]; then
        clarify_contract_failures+=("skills/assistant-clarify/contracts/output.yaml has required artifacts without validation or on_fail")
    fi
fi

for term in \
    "## Contracts" \
    'contracts/input.yaml' \
    'contracts/output.yaml' \
    "Utility skill" \
    "no phase gates or sub-agent handoffs"; do
    if ! grep -Fq "$term" "$clarify_skill"; then
        clarify_contract_failures+=("skills/assistant-clarify/SKILL.md missing $term")
    fi
done

if [[ "${#clarify_contract_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-clarify utility contract requirements failed: ${clarify_contract_failures[*]}"
fi

test_start "assistant-review audit mode covers findings-only requests"
review_input="$FRAMEWORK_DIR/skills/assistant-review/contracts/input.yaml"
review_audit_failures=()
for term in \
    "provide findings" \
    "report findings" \
    "list findings" \
    "summarize findings" \
    "review against" \
    "audit. Otherwise"; do
    if ! grep -Fq "$term" "$review_input"; then
        review_audit_failures+=("missing $term")
    fi
done

if [[ "${#review_audit_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review findings-only prompts must infer audit mode: ${review_audit_failures[*]}"
fi

test_start "assistant-ideate owns brainstorming trigger"
thinking_skill="$FRAMEWORK_DIR/skills/assistant-thinking/SKILL.md"
ideate_skill="$FRAMEWORK_DIR/skills/assistant-ideate/SKILL.md"
brainstorm_trigger_failures=()
if grep -Eq '^(description:|  - pattern:).*brainstorm' "$thinking_skill"; then
    brainstorm_trigger_failures+=("assistant-thinking frontmatter still routes brainstorm")
fi
if ! grep -Eq '^(description:|  - pattern:).*brainstorm' "$ideate_skill"; then
    brainstorm_trigger_failures+=("assistant-ideate frontmatter does not route brainstorm")
fi

if [[ "${#brainstorm_trigger_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "brainstorm prompts should route to ideate only: ${brainstorm_trigger_failures[*]}"
fi

test_start "assistant-workflow routes concrete dev creation without stealing brainstorming"
workflow_skill="$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md"
workflow_pattern="$(awk -F'"' '/^[[:space:]]*- pattern:/ { print $2; exit }' "$workflow_skill")"
workflow_creation_failures=()

workflow_prompt_matches() {
    local prompt="$1"
    printf '%s\n' "$prompt" | tr '[:upper:]' '[:lower:]' | grep -qE "\b($workflow_pattern)\b"
}

if [[ -z "$workflow_pattern" ]]; then
    workflow_creation_failures+=("assistant-workflow pattern missing")
else
    for prompt in \
        "create a new REST endpoint" \
        "make a dashboard" \
        "turn this idea into an implementation plan"; do
        if ! workflow_prompt_matches "$prompt"; then
            workflow_creation_failures+=("does not route: $prompt")
        fi
    done
    for prompt in \
        "brainstorm dashboard ideas" \
        "ideas for dashboard"; do
        if workflow_prompt_matches "$prompt"; then
            workflow_creation_failures+=("steals brainstorming: $prompt")
        fi
    done
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
    "$workflow_skill::inline plan and proceeds without ceremony unless risk requires approval" \
    "$workflow_phases::print the inline plan and continue directly to Build" \
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

test_start "high-control skills pair restrictions with actionable guidance"
missing_paired_guidance=()

review_skill="$FRAMEWORK_DIR/skills/assistant-review/SKILL.md"
for term in \
    "Allowed risk categories:" \
    "Every refactor-related finding MUST state" \
    "Use concrete risk framing instead" \
    "smallest durable fix"; do
    if ! p0p4_section_has_term "$review_skill" "## Refactor-Related Findings" "$term"; then
        missing_paired_guidance+=("assistant-review Refactor-Related Findings: $term")
    fi
done

tdd_skill="$FRAMEWORK_DIR/skills/assistant-tdd/SKILL.md"
for term in \
    "Builder/Tester owns RED" \
    "Code Writer owns GREEN" \
    "Required RED evidence before production implementation:"; do
    if ! p0p4_section_has_term "$tdd_skill" "## Ownership" "$term"; then
        missing_paired_guidance+=("assistant-tdd Ownership: $term")
    fi
done
for term in \
    "RED" \
    "passes unexpectedly" \
    "Repair regressions before continuing"; do
    if ! p0p4_section_has_term "$tdd_skill" "## Cycle" "$term"; then
        missing_paired_guidance+=("assistant-tdd Cycle recovery: $term")
    fi
done

workflow_skill="$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md"
for term in \
    "Justify it with a concrete risk only" \
    "Tie incidental or scope-expanding refactors to concrete risk" \
    "Choose the smallest useful, durable fix"; do
    if ! p0p4_section_has_term "$workflow_skill" "## Refactor Guidance" "$term"; then
        missing_paired_guidance+=("assistant-workflow Refactor Guidance: $term")
    fi
done
for term in \
    "Use this exact format:" \
    "--- PHASE: [name] ---" \
    "--- PHASE: [name] COMPLETE ---"; do
    if ! p0p4_section_has_term "$workflow_skill" "## Visible Checkpoints" "$term"; then
        missing_paired_guidance+=("assistant-workflow Visible Checkpoints: $term")
    fi
done

if [[ "${#missing_paired_guidance[@]}" -eq 0 ]]; then
    pass
else
    fail "high-control skill restrictions need nearby paired guidance: ${missing_paired_guidance[*]}"
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
    "$review_skill::Principle and Readability Lens" \
    "$review_skill::SOLID, KISS, DRY, YAGNI, and readability" \
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

test_start "assistant-review direct fallback does not require reviewer dispatch"
review_fallback_failures=()
review_output="$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml"

for file_and_term in \
    "$review_skill::load \`references/review-loop.md\` before the first REVIEW step" \
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

test_start "assistant-thinking asks before sequential fallback without an evidenced policy block"
thinking_delegation_proof_failures=()
thinking_delegation_proof_terms=(
    "$thinking_skill::required roles lack a delegation decision"
    "$thinking_skill::policy_blocking_source"
    "$FRAMEWORK_DIR/skills/assistant-thinking/contracts/input.yaml::policy_blocking_source"
    "$FRAMEWORK_DIR/skills/assistant-thinking/contracts/input.yaml::authorization_required"
    "$FRAMEWORK_DIR/skills/assistant-thinking/contracts/input.yaml::delegated requires subagent_policy_state=delegation_authorized"
    "$FRAMEWORK_DIR/skills/assistant-thinking/contracts/input.yaml::sequential_fallback requires authorization_denied, subagents_unavailable after a real spawn failure, or policy_disallowed with policy_blocking_source"
    "$FRAMEWORK_DIR/skills/assistant-thinking/contracts/output.yaml::policy_blocking_source"
    "$FRAMEWORK_DIR/skills/assistant-thinking/contracts/output.yaml::sequential_fallback"
    "$FRAMEWORK_DIR/skills/assistant-thinking/contracts/phase-gates.yaml::policy_blocking_source"
    "$FRAMEWORK_DIR/skills/assistant-thinking/contracts/phase-gates.yaml::Plan approval is not delegation approval"
    "$FRAMEWORK_DIR/skills/assistant-thinking/perspectives.md::delegated requires subagent_policy_state=delegation_authorized"
    "$FRAMEWORK_DIR/skills/assistant-thinking/perspectives.md::sequential_fallback requires authorization_denied, subagents_unavailable after a real spawn failure, or policy_disallowed with policy_blocking_source"
    "$FRAMEWORK_DIR/skills/assistant-thinking/stress-test.md::delegated requires subagent_policy_state=delegation_authorized"
    "$FRAMEWORK_DIR/skills/assistant-thinking/stress-test.md::sequential_fallback requires authorization_denied, subagents_unavailable after a real spawn failure, or policy_disallowed with policy_blocking_source"
    "$FRAMEWORK_DIR/skills/assistant-thinking/evals/cases.json::thinking-required-roles-missing-delegation-authorization"
    "$FRAMEWORK_DIR/skills/assistant-thinking/evals/cases.json::authorization_required"
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
        thinking_delegation_proof_failures+=("${method_file#$FRAMEWORK_DIR/}: loose not-authorized fallback wording")
    fi
done
if [[ "${#thinking_delegation_proof_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-thinking delegation fallback must carry authorization or policy-block evidence: ${thinking_delegation_proof_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
