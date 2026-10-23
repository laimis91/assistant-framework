if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

sync_tool="$FRAMEWORK_DIR/tools/skills/sync-skill-contract-guide.sh"
canonical_guide="$FRAMEWORK_DIR/docs/skill-contract-design-guide.md"
generated_guide="$FRAMEWORK_DIR/skills/assistant-skill-creator/references/skill-contract-design-guide.md"

test_start "contract guide sync tool keeps docs source canonical"
if [[ -x "$sync_tool" ]] \
    && grep -Fq "docs/skill-contract-design-guide.md is canonical" "$canonical_guide" \
    && grep -Fq "sync-skill-contract-guide.sh --apply" "$canonical_guide" \
    && grep -Fq "generated from docs/skill-contract-design-guide.md" "$FRAMEWORK_DIR/skills/assistant-skill-creator/SKILL.md" \
    && "$sync_tool" --check >/dev/null 2>&1 \
    && cmp -s "$canonical_guide" "$generated_guide" \
    && bash "$FRAMEWORK_DIR/tools/skills/sync-lifecycle-verification.sh" --check >/dev/null 2>&1; then
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

lifecycle_sync="$FRAMEWORK_DIR/tools/skills/sync-lifecycle-verification.sh"
test_start "lifecycle guide sync rejects missing and drifted mirrors and restores only three destinations"
if [[ ! -x "$lifecycle_sync" ]]; then
    fail "lifecycle sync cannot restore required three-copy parity: helper missing"
else
    fixture_root="$(mktemp -d)"
    p0p4_register_cleanup "$fixture_root"
    mkdir -p "$fixture_root/tools/skills" "$fixture_root/docs" "$fixture_root/skills/unrelated/references"
    cp "$lifecycle_sync" "$fixture_root/tools/skills/"
    printf 'canonical lifecycle\n' >"$fixture_root/docs/lifecycle-verification.md"
    printf 'unrelated\n' >"$fixture_root/skills/unrelated/references/keep.md"
    fixture_sync="$fixture_root/tools/skills/sync-lifecycle-verification.sh"
    lifecycle_ok=true
    if "$fixture_sync" --check >/dev/null 2>&1; then lifecycle_ok=false; fi
    if ! "$fixture_sync" --apply >/dev/null 2>&1; then lifecycle_ok=false; fi
    for consumer in assistant-debugging assistant-verification assistant-review; do
        target="$fixture_root/skills/$consumer/references/lifecycle-verification.md"
        if ! cmp -s "$fixture_root/docs/lifecycle-verification.md" "$target"; then lifecycle_ok=false; fi
        rm -f "$target"
        if "$fixture_sync" --check >/dev/null 2>&1; then lifecycle_ok=false; fi
        "$fixture_sync" --apply >/dev/null 2>&1 || lifecycle_ok=false
        printf 'drifted\n' >"$target"
        if "$fixture_sync" --check >/dev/null 2>&1; then lifecycle_ok=false; fi
        "$fixture_sync" --apply >/dev/null 2>&1 || lifecycle_ok=false
        if ! cmp -s "$fixture_root/docs/lifecycle-verification.md" "$target"; then lifecycle_ok=false; fi
    done
    [[ "$(cat "$fixture_root/skills/unrelated/references/keep.md")" == unrelated ]] || lifecycle_ok=false
    [[ "$(find "$fixture_root/skills" -type f | wc -l | tr -d ' ')" == 4 ]] || lifecycle_ok=false
    "$fixture_sync" --check >/dev/null 2>&1 || lifecycle_ok=false
    if [[ "$lifecycle_ok" == true ]]; then pass; else fail "lifecycle missing/drift/apply parity or write boundary failed"; fi
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
