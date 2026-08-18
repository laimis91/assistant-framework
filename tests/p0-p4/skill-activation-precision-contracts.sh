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

description_prompt_anchor_count() {
    local skill_file="$1"
    local prompt="$2"
    local description
    local token
    local count=0

    description="$(awk -F'"' '/^description:/ { print $2; exit }' "$skill_file" | tr '[:upper:]' '[:lower:]')"
    while IFS= read -r token; do
        [[ ${#token} -ge 5 ]] || continue
        if printf '%s\n' "$prompt" | tr '[:upper:]' '[:lower:]' | grep -Fqw "$token"; then
            count=$((count + 1))
        fi
    done < <(printf '%s\n' "$description" | tr -cs '[:alnum:]' '\n' | sort -u)
    printf '%s\n' "$count"
}

test_start "native assistant skill description catalog stays below 2200 characters"
catalog="$(description_catalog)"
catalog_count="$(printf '%s\n' "$catalog" | grep -c . | tr -d ' ')"
catalog_characters="$(printf '%s\n' "$catalog" | wc -c | tr -d ' ')"
if [[ "$catalog_count" -ne 14 ]]; then
    fail "expected 14 assistant skill descriptions, found $catalog_count"
elif [[ "$catalog_characters" -le 2200 ]]; then
    pass
else
    fail "assistant skill descriptions use $catalog_characters characters; operating budget is 2200 (approved maximum 2500)"
fi

test_start "deterministic lexical description proxy keeps broad prose away from specialist routes"
ideate_skill="$FRAMEWORK_DIR/skills/assistant-ideate/SKILL.md"
research_skill="$FRAMEWORK_DIR/skills/assistant-research/SKILL.md"
thinking_skill="$FRAMEWORK_DIR/skills/assistant-thinking/SKILL.md"
clarify_skill="$FRAMEWORK_DIR/skills/assistant-clarify/SKILL.md"
debugging_skill="$FRAMEWORK_DIR/skills/assistant-debugging/SKILL.md"
activation_failures=()

for file_and_prompt in \
    "$ideate_skill::generate and rank brainstorm options" \
    "$ideate_skill::run a quick improvement scan for our agent framework" \
    "$research_skill::research current source-backed evidence" \
    "$research_skill::compare source-backed options" \
    "$thinking_skill::stress test this complex architecture decision" \
    "$clarify_skill::clarify this ambiguous request and help me untangle it" \
    "$debugging_skill::diagnose this unknown failure before fixing"; do
    file="${file_and_prompt%%::*}"
    prompt="${file_and_prompt#*::}"
    if [[ "$(description_prompt_anchor_count "$file" "$prompt")" -lt 2 ]]; then
        activation_failures+=("fewer than two lexical description anchors: $(basename "$(dirname "$file")") -> $prompt")
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
    "$thinking_skill::clarify my request"; do
    file="${file_and_prompt%%::*}"
    prompt="${file_and_prompt#*::}"
    if [[ "$(description_prompt_anchor_count "$file" "$prompt")" -ge 2 ]]; then
        activation_failures+=("false positive lexical proxy route: $(basename "$(dirname "$file")") -> $prompt")
    fi
done

if [[ "${#activation_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "skill activation boundaries failed: ${activation_failures[*]}"
fi

test_start "skill activation inventory excludes retired custom memory routes"
if [[ ! -e "$FRAMEWORK_DIR/skills/assistant-memory" ]] \
    && [[ ! -e "$FRAMEWORK_DIR/skills/assistant-reflexion" ]] \
    && [[ ! -e "$FRAMEWORK_DIR/memory-protocol.md" ]] \
    && ! rg -n -i -e 'memory_reflect' -e 'learning controller' \
        "$FRAMEWORK_DIR/skills/assistant-workflow" >/tmp/p0p4-retired-activation-routes.out; then
    pass
else
    fail "skill activation inventory retains retired custom-memory routes"
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
