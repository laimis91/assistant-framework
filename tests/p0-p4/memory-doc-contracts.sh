if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "memory protocol wording avoids graph-only storage and matching installed-agent paths"
if jq -e . >/dev/null 2>&1 <<< '{}'; then
    :
fi
MEMORY_DOC_INSTALL_HOME="$(mktemp -d)"
p0p4_register_cleanup "$MEMORY_DOC_INSTALL_HOME"
if p0p4_install_codex_fixture "$MEMORY_DOC_INSTALL_HOME" /tmp/p0p4-memory-doc-install.out /tmp/p0p4-memory-doc-install.err --no-hooks; then
    if rg -n "WAL|markdown sync|memory files are the source of truth|knowledge graph .+source of truth|loaded at session start via hooks|graph\\.jsonl.+source of truth|\\.claude/" "$MEMORY_DOC_INSTALL_HOME/.codex/AGENTS.md" >/tmp/p0p4-memory-wording.out; then
        fail "installed Codex memory protocol has stale memory wording or paths; see /tmp/p0p4-memory-wording.out"
    else
        pass
    fi
else
    fail "codex memory doc install failed; see /tmp/p0p4-memory-doc-install.err"
fi

test_start "installer and protocol docs do not describe graph.jsonl as live source of truth"
if rg -n 'graph\.jsonl.*source of truth|source of truth.*graph\.jsonl|rules are still loaded from graph\.jsonl|session-start hook directly from `graph\.jsonl`|knowledge graph seed installed' \
    "$FRAMEWORK_DIR/install.sh" \
    "$FRAMEWORK_DIR/memory-protocol.md" \
    "$FRAMEWORK_DIR/skills/assistant-memory/SKILL.md" >/tmp/p0p4-graph-source-wording.out; then
    fail "found stale graph-only storage wording; see /tmp/p0p4-graph-source-wording.out"
else
    pass
fi

test_start "memory graph docs and help avoid stale graph-only runtime wording"
if rg -n 'knowledge graph over (the existing )?markdown memory|markdown memory system|graph\.jsonl.*persistent graph storage|persistent graph storage.*graph\.jsonl|graph\.jsonl.*authoritative store|authoritative store.*graph\.jsonl|graph\.jsonl.*source of truth|source of truth.*graph\.jsonl|JSONL over SQLite|SQLite would be premature|JSONL graph remains the source of truth|SQLite is (only )?an acceleration layer|--graph-file PATH[[:space:]]+Graph file path' \
    "$FRAMEWORK_DIR/README.md" \
    "$FRAMEWORK_DIR/tools/memory-graph/DESIGN.md" \
    "$FRAMEWORK_DIR/tools/memory-graph/src/MemoryGraph/Program.cs" >/tmp/p0p4-memory-graph-stale-runtime-wording.out; then
    fail "found stale memory graph runtime storage wording; see /tmp/p0p4-memory-graph-stale-runtime-wording.out"
else
    pass
fi

test_start "memory graph docs and help state DB authority and JSONL compatibility"
if grep -q "SQLite-backed knowledge graph" "$FRAMEWORK_DIR/README.md" \
    && grep -q "SQLite as authoritative local storage" "$FRAMEWORK_DIR/tools/memory-graph/DESIGN.md" \
    && grep -q "Legacy JSONL import/fallback path" "$FRAMEWORK_DIR/tools/memory-graph/src/MemoryGraph/Program.cs"; then
    pass
else
    fail "memory graph docs/help must state SQLite DB authority and legacy JSONL import/fallback compatibility"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
