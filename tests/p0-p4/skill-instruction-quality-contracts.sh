if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

# Installed Codex path substitution is covered by installer-contracts.sh.
# This suite stays focused on source skill instruction quality.

p0p4_root_skill_files() {
    find "$FRAMEWORK_DIR/skills" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -path "$FRAMEWORK_DIR/skills/assistant-*/SKILL.md" -print | sort
}

p0p4_skill_output_allowlist_reason() {
    case "$1" in
        skills/assistant-review/SKILL.md)
            printf '%s\n' "review output is contract-backed by contracts/output.yaml and the final review summary template"
            ;;
        skills/assistant-skill-creator/SKILL.md)
            printf '%s\n' "skill creation output is contract-backed by contracts/output.yaml and the validate-phase summary"
            ;;
        skills/assistant-tdd/SKILL.md)
            printf '%s\n' "TDD output is contract-backed by contracts/output.yaml and cycle-log requirements"
            ;;
        skills/assistant-workflow/SKILL.md)
            printf '%s\n' "workflow output is contract-backed by contracts/output.yaml and visible workflow checkpoints"
            ;;
        *)
            return 1
            ;;
    esac
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

test_start "root skills declare output sections or documented exceptions"
missing_output_sections=()
while IFS= read -r skill_file; do
    rel_path="${skill_file#$FRAMEWORK_DIR/}"
    if grep -Eq '^## Output[[:space:]]*$' "$skill_file"; then
        continue
    fi

    if reason="$(p0p4_skill_output_allowlist_reason "$rel_path")"; then
        if [[ -z "$reason" ]]; then
            missing_output_sections+=("$rel_path: allowlist reason is empty")
        elif [[ ! -f "$(dirname "$skill_file")/contracts/output.yaml" ]]; then
            missing_output_sections+=("$rel_path: allowlisted without contracts/output.yaml")
        fi
    else
        missing_output_sections+=("$rel_path")
    fi
done < <(p0p4_root_skill_files)
if [[ "${#missing_output_sections[@]}" -eq 0 ]]; then
    pass
else
    fail "root SKILL.md files need a ## Output section or documented contract-backed exception: ${missing_output_sections[*]}"
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
    if ! p0p4_section_has_term "$tdd_skill" "## Orchestrated role ownership" "$term"; then
        missing_paired_guidance+=("assistant-tdd Orchestrated role ownership: $term")
    fi
done
for term in \
    "Each shortcut routes back to the RED gate:" \
    "| Shortcut | Required response |" \
    "Write the test now, before production code."; do
    if ! p0p4_section_has_term "$tdd_skill" "## Common shortcuts and required response" "$term"; then
        missing_paired_guidance+=("assistant-tdd Common shortcuts: $term")
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

p0p4_finish_suite "${BASH_SOURCE[0]}"
