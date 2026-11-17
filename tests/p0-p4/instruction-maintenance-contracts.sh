if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "docs root routes prose editing to an existing editing checklist"
docs_root="$FRAMEWORK_DIR/skills/assistant-docs/SKILL.md"
if [[ -f "$FRAMEWORK_DIR/skills/assistant-docs/editing-checklist.md" ]] \
    && grep -Fq '`editing-checklist.md`' "$docs_root"; then
    pass
else
    fail "assistant-docs routes prose editing to a missing editing-checklist.md"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
