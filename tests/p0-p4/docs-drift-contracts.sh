if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "README documents tracked assistant skills"
assistant_skill_count="$(find "$FRAMEWORK_DIR/skills" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -path "$FRAMEWORK_DIR/skills/assistant-*/SKILL.md" -print | wc -l | tr -d '[:space:]')"
missing_readme_skills=()
while IFS= read -r skill_file; do
    skill_name="$(basename "$(dirname "$skill_file")")"
    if ! grep -Fq "### $skill_name" "$FRAMEWORK_DIR/README.md"; then
        missing_readme_skills+=("$skill_name")
    fi
done < <(find "$FRAMEWORK_DIR/skills" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -path "$FRAMEWORK_DIR/skills/assistant-*/SKILL.md" -print | sort)

if [[ "$assistant_skill_count" -eq 0 ]]; then
    fail "tracked assistant skill inventory is empty"
elif [[ "${#missing_readme_skills[@]}" -ne 0 ]]; then
    fail "README is missing tracked assistant skill sections: ${missing_readme_skills[*]}"
elif ! grep -Fq "$assistant_skill_count first-class" "$FRAMEWORK_DIR/README.md"; then
    fail "README does not state the tracked assistant skill count"

else
    pass
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
