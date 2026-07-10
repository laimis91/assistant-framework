if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

sync_tool="$FRAMEWORK_DIR/tools/skills/sync-skill-contract-guide.sh"
canonical_guide="$FRAMEWORK_DIR/docs/skill-contract-design-guide.md"
generated_guide="$FRAMEWORK_DIR/skills/assistant-skill-creator/references/skill-contract-design-guide.md"
plugin_sync_tool="$FRAMEWORK_DIR/tools/plugins/sync-plugin-skills.sh"

test_start "contract guide sync tool keeps docs source canonical"
if [[ -x "$sync_tool" ]] \
    && grep -Fq "docs/skill-contract-design-guide.md is canonical" "$canonical_guide" \
    && grep -Fq "sync-skill-contract-guide.sh --apply" "$canonical_guide" \
    && grep -Fq "generated from docs/skill-contract-design-guide.md" "$FRAMEWORK_DIR/skills/assistant-skill-creator/SKILL.md" \
    && grep -Fq 'sync-skill-contract-guide.sh' "$plugin_sync_tool" \
    && "$sync_tool" --check >/dev/null 2>&1 \
    && cmp -s "$canonical_guide" "$generated_guide"; then
    pass
else
    fail "canonical contract guide or generated skill reference is not synchronized"
fi

test_start "contract guide sync fails closed on drift and apply restores parity"
if [[ ! -x "$sync_tool" ]]; then
    fail "contract guide sync tool is missing or not executable"
else
    fixture_root="$(mktemp -d)"
    p0p4_register_cleanup "$fixture_root"
    fixture_source="$fixture_root/source.md"
    fixture_target="$fixture_root/target.md"
    printf 'canonical\n' >"$fixture_source"
    printf 'drifted\n' >"$fixture_target"
    if SKILL_CONTRACT_GUIDE_SOURCE="$fixture_source" SKILL_CONTRACT_GUIDE_TARGET="$fixture_target" "$sync_tool" --check >/dev/null 2>&1; then
        fail "contract guide sync check accepted drift"
    elif ! SKILL_CONTRACT_GUIDE_SOURCE="$fixture_source" SKILL_CONTRACT_GUIDE_TARGET="$fixture_target" "$sync_tool" --apply >/dev/null 2>&1; then
        fail "contract guide sync apply failed for isolated fixture"
    elif ! cmp -s "$fixture_source" "$fixture_target"; then
        fail "contract guide sync apply did not restore exact parity"
    elif ! SKILL_CONTRACT_GUIDE_SOURCE="$fixture_source" SKILL_CONTRACT_GUIDE_TARGET="$fixture_target" "$sync_tool" --check >/dev/null 2>&1; then
        fail "contract guide sync check did not pass after apply"
    else
        pass
    fi
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
