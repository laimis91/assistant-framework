if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "README avoids stale release skill, hook, and memory wording"
if rg -n 'Twelve|one or all eleven|Codex not yet supported|13 MCP tool implementations|14 MCP tools|generates project memory|generate project memory|\.claude/memory\.md|\.codex/memory\.md' \
    "$FRAMEWORK_DIR/README.md" >/tmp/p0p4-docs-drift-stale-readme.out; then
    fail "README contains stale framework wording; see /tmp/p0p4-docs-drift-stale-readme.out"
else
    pass
fi

test_start "README documents tracked assistant skills and local-only Unity policy"
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
elif ! grep -Fq 'skills/unity-*' "$FRAMEWORK_DIR/README.md" \
    || ! grep -Fq 'local-only' "$FRAMEWORK_DIR/README.md" \
    || ! grep -Fq 'ignored by git' "$FRAMEWORK_DIR/README.md"; then
    fail "README must document Unity skills as local-only and ignored"
elif rg -n '^### unity-' "$FRAMEWORK_DIR/README.md" >/tmp/p0p4-docs-drift-unity-readme.out; then
    fail "README should not list Unity skills as first-class release skills; see /tmp/p0p4-docs-drift-unity-readme.out"
else
    pass
fi

test_start "README memory graph tool list includes runtime count and memory_doctor"
runtime_tool_count="$(grep -c 'registry.Register(new ' "$FRAMEWORK_DIR/tools/memory-graph/src/MemoryGraph/Server/MemoryGraphRuntime.cs")"
if grep -Fq "**$runtime_tool_count MCP tools:**" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq '`memory_doctor`' "$FRAMEWORK_DIR/README.md"; then
    pass
else
    fail "README memory graph MCP tool list must match runtime count and include memory_doctor"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
