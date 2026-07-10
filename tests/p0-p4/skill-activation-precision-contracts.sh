if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

description_catalog() {
    local skill_file
    for skill_file in "$FRAMEWORK_DIR"/skills/assistant-*/SKILL.md; do
        awk '
            NR == 1 && $0 == "---" { frontmatter = 1; next }
            frontmatter && $0 == "---" { exit }
            frontmatter && /^description:[[:space:]]*/ {
                value = $0
                sub(/^description:[[:space:]]*/, "", value)
                gsub(/^"|"$/, "", value)
                print value
                exit
            }
        ' "$skill_file"
    done
}

skill_patterns() {
    awk -F'"' '/^[[:space:]]*- pattern:/ { print $2 }' "$1" | paste -sd'|' -
}

skill_matches() {
    local skill_file="$1"
    local prompt="$2"
    local patterns
    patterns="$(skill_patterns "$skill_file")"
    [[ -n "$patterns" ]] && printf '%s\n' "$prompt" | tr '[:upper:]' '[:lower:]' | grep -Eq "($patterns)"
}

test_start "native assistant skill description catalog stays below 2200 characters"
catalog="$(description_catalog)"
catalog_count="$(printf '%s\n' "$catalog" | grep -c . | tr -d ' ')"
catalog_characters="$(printf '%s\n' "$catalog" | wc -c | tr -d ' ')"
if [[ "$catalog_count" -ne 16 ]]; then
    fail "expected 16 assistant skill descriptions, found $catalog_count"
elif [[ "$catalog_characters" -le 2200 ]]; then
    pass
else
    fail "assistant skill descriptions use $catalog_characters characters; operating budget is 2200 (approved maximum 2500)"
fi

test_start "skill trigger precedence keeps broad prose away from specialist routes"
ideate_skill="$FRAMEWORK_DIR/skills/assistant-ideate/SKILL.md"
research_skill="$FRAMEWORK_DIR/skills/assistant-research/SKILL.md"
thinking_skill="$FRAMEWORK_DIR/skills/assistant-thinking/SKILL.md"
clarify_skill="$FRAMEWORK_DIR/skills/assistant-clarify/SKILL.md"
debugging_skill="$FRAMEWORK_DIR/skills/assistant-debugging/SKILL.md"
memory_skill="$FRAMEWORK_DIR/skills/assistant-memory/SKILL.md"
reflexion_skill="$FRAMEWORK_DIR/skills/assistant-reflexion/SKILL.md"
activation_failures=()

for file_and_prompt in \
    "$ideate_skill::brainstorm alternatives for our release flow" \
    "$ideate_skill::what else could improve our agent framework" \
    "$research_skill::research current approaches to agent memory" \
    "$research_skill::compare tools for prompt evaluation" \
    "$thinking_skill::stress test this architecture decision" \
    "$clarify_skill::help me untangle these two requests" \
    "$debugging_skill::investigate failure in the payment test" \
    "$memory_skill::remember this preference for future tasks" \
    "$reflexion_skill::what did we learn from this migration"; do
    file="${file_and_prompt%%::*}"
    prompt="${file_and_prompt#*::}"
    if ! skill_matches "$file" "$prompt"; then
        activation_failures+=("missing positive route: $(basename "$(dirname "$file")") -> $prompt")
    fi
done

for file_and_phrase in \
    "$ideate_skill::improve this" \
    "$research_skill::what is" \
    "$research_skill::Discovery phase" \
    "$thinking_skill::clarify"; do
    file="${file_and_phrase%%::*}"
    phrase="${file_and_phrase#*::}"
    if awk '/^description:/ { print; exit }' "$file" | grep -Fqi "$phrase"; then
        activation_failures+=("broad native description route: $(basename "$(dirname "$file")") -> $phrase")
    fi
done

for file_and_prompt in \
    "$ideate_skill::improve this function" \
    "$research_skill::what is this function doing" \
    "$research_skill::investigate failure in the payment test" \
    "$thinking_skill::clarify my request" \
    "$memory_skill::this function uses memory allocation"; do
    file="${file_and_prompt%%::*}"
    prompt="${file_and_prompt#*::}"
    if skill_matches "$file" "$prompt"; then
        activation_failures+=("false positive route: $(basename "$(dirname "$file")") -> $prompt")
    fi
done

if [[ "${#activation_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "skill activation boundaries failed: ${activation_failures[*]}"
fi

test_start "reflexion and workflow recall activate only from relevant evidence"
workflow_phases="$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"
workflow_patterns="$FRAMEWORK_DIR/skills/assistant-workflow/references/mega-and-patterns.md"
reflexion_failures=()
for file_and_term in \
    "$reflexion_skill::Run reflection only when the user explicitly asks or concrete evidence suggests a durable lesson." \
    "$reflexion_skill::Recall prior lessons only when current work depends on earlier context." \
    "$workflow_phases::Recall prior lessons only when they can materially affect the current task" \
    "$workflow_patterns::when prior lessons are relevant" \
    "$workflow_patterns::when concrete durable lessons exist"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! grep -Fq "$term" "$file"; then
        reflexion_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
for forbidden in \
    "Auto-activates at task completion" \
    "Triggered automatically at workflow completion" \
    "Triggered automatically during the Discover phase" \
    "Never skip reflection on medium+ tasks"; do
    if grep -Fq "$forbidden" "$reflexion_skill"; then
        reflexion_failures+=("assistant-reflexion still requires: $forbidden")
    fi
done
if [[ "${#reflexion_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "conditional reflexion contract failed: ${reflexion_failures[*]}"
fi

test_start "memory protocol retrieves cross-session context only when relevant"
memory_protocol="$FRAMEWORK_DIR/memory-protocol.md"
memory_failures=()
for term in \
    "Query memory only for relevant corrections, stable preferences, requested recall, task recovery, or durable lessons; otherwise skip it." \
    "Try \`memory_context\` before \`memory_search\`."; do
    if ! grep -Fq "$term" "$memory_protocol"; then
        memory_failures+=("memory-protocol.md missing $term")
    fi
done
if ! grep -Fq "when the current task depends on prior corrections, preferences, recovery state, or durable lessons" "$memory_skill"; then
    memory_failures+=("assistant-memory query guidance is not relevance-based")
fi
if grep -Fq 'At session start, call `memory_context`' "$memory_protocol"; then
    memory_failures+=("memory-protocol.md still requires memory_context at every session start")
fi
if grep -Fq '(session start)' "$memory_skill"; then
    memory_failures+=("assistant-memory still labels memory_context as a session-start default")
fi
if [[ "${#memory_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "relevance-based memory retrieval failed: ${memory_failures[*]}"
fi

test_start "assistant-ideate contracts distinguish light and deep modes"
ideate_input="$FRAMEWORK_DIR/skills/assistant-ideate/contracts/input.yaml"
ideate_output="$FRAMEWORK_DIR/skills/assistant-ideate/contracts/output.yaml"
ideate_gates="$FRAMEWORK_DIR/skills/assistant-ideate/contracts/phase-gates.yaml"
ideate_reference="$FRAMEWORK_DIR/skills/assistant-ideate/references/ideation-pipeline.md"
ideate_deep_reference="$FRAMEWORK_DIR/skills/assistant-ideate/references/deep-ideation.md"
ideate_evals="$FRAMEWORK_DIR/skills/assistant-ideate/evals/cases.json"
ideate_failures=()
for file_and_term in \
    "$ideate_skill::Light mode" \
    "$ideate_skill::Deep mode" \
    "$ideate_skill::Contract v2 makes the former deep-only ranking, refinement, and decision" \
    "$ideate_input::schema_version: \"2.0\"" \
    "$ideate_input::- name: ideation_mode" \
    "$ideate_input::enum_values: [light, deep]" \
    "$ideate_output::- name: quick_ranking" \
    "$ideate_output::- name: recommended_next_step" \
    "$ideate_output::schema_version: \"2.0\"" \
    "$ideate_gates::when ideation_mode is light" \
    "$ideate_gates::when ideation_mode is deep" \
    "$ideate_gates::schema_version: \"2.0\"" \
    "$ideate_reference::Light mode: 3-5 options" \
    "$ideate_deep_reference::Deep mode: 8-15 ideas" \
    "$ideate_evals::quick-improvement-scan-uses-light-mode" \
    "$ideate_evals::explicit-brainstorm-uses-deep-mode"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! grep -Fq -- "$term" "$file"; then
        ideate_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
if [[ "${#ideate_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "mode-aware ideation contract failed: ${ideate_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
