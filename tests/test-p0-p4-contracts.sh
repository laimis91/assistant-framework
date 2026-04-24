#!/usr/bin/env bash
# Focused P0-P4 regression checks for installer idempotence and instruction contracts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

test_start() {
    printf '  - %s ... ' "$1"
}

pass() {
    echo "ok"
    PASS=$((PASS + 1))
}

fail() {
    echo "fail: $1"
    FAIL=$((FAIL + 1))
}

finish() {
    echo ""
    echo "P0-P4 Contract Tests"
    echo "===================="
    echo "  Passed: $PASS"
    echo "  Failed: $FAIL"
    if [[ "$FAIL" -gt 0 ]]; then
        exit 1
    fi
}

count_occurrences() {
    local pattern="$1"
    local file="$2"
    grep -c "$pattern" "$file" 2>/dev/null || true
}

test_start "installer reinstall keeps one memory protocol block and one legacy preamble"
INSTALL_HOME="$(mktemp -d)"
trap 'rm -rf "$INSTALL_HOME" "${INSTALL_HOME_TWO:-}" "${INSTALL_HOME_THREE:-}" "${INSTALL_HOME_FOUR:-}" "${INSTALL_HOME_FIVE:-}" "${INSTALL_HOME_SIX:-}" "${INSTALL_HOME_SEVEN:-}"' EXIT
if HOME="$INSTALL_HOME" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-1.out 2>/tmp/p0p4-install-1.err; then
    if HOME="$INSTALL_HOME" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-2.out 2>/tmp/p0p4-install-2.err; then
        agents_file="$INSTALL_HOME/.codex/AGENTS.md"
        starts="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START" "$agents_file")"
        ends="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END" "$agents_file")"
        preambles="$(count_occurrences "^# Assistant Framework — Memory Protocol$" "$agents_file")"
        if [[ "$starts" == "1" && "$ends" == "1" && "$preambles" == "1" ]]; then
            pass
        else
            fail "expected one protocol start/end/preamble, got start=$starts end=$ends preamble=$preambles"
        fi
    else
        fail "second install failed; see /tmp/p0p4-install-2.err"
    fi
else
    fail "first install failed; see /tmp/p0p4-install-1.err"
fi

test_start "installer replaces interrupted memory protocol install without duplicating blocks"
INSTALL_HOME_THREE="$(mktemp -d)"
mkdir -p "$INSTALL_HOME_THREE/.codex"
cat > "$INSTALL_HOME_THREE/.codex/AGENTS.md" <<'TRUNCATED'
User-managed heading before installer content.

# Assistant Framework — Memory Protocol

## Role

You are an orchestrator. You delegate ALL file editing, code implementation, and phase execution to specialized agents.
<!-- This is a template. Paths like ~/.codex/ are substituted during install.sh for non-Claude agents. -->
<!-- Appended by Assistant Framework install. Do not remove this marker. -->
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->

Interrupted installer-owned memory content that should be removed.
TRUNCATED
if HOME="$INSTALL_HOME_THREE" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-truncated.out 2>/tmp/p0p4-install-truncated.err; then
    agents_file="$INSTALL_HOME_THREE/.codex/AGENTS.md"
    starts="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START" "$agents_file")"
    ends="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END" "$agents_file")"
    preambles="$(count_occurrences "^# Assistant Framework — Memory Protocol$" "$agents_file")"
    if [[ "$starts" == "1" && "$ends" == "1" && "$preambles" == "1" ]] \
        && grep -q "User-managed heading before installer content." "$agents_file" \
        && ! grep -q "Interrupted installer-owned memory content" "$agents_file"; then
        pass
    else
        fail "expected truncated installer block to be replaced once while preserving user content"
    fi
else
    fail "install after truncated memory protocol failed; see /tmp/p0p4-install-truncated.err"
fi

test_start "Codex reinstall collapses duplicate and interrupted memory protocol blocks while preserving user content"
INSTALL_HOME_SIX="$(mktemp -d)"
mkdir -p "$INSTALL_HOME_SIX/.codex"
cat > "$INSTALL_HOME_SIX/.codex/AGENTS.md" <<'DUPLICATE_CODEX'
User-managed content before old installer blocks.

<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_START -->
# Old Codex installer section
<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_END -->

User-managed content before first memory block.

<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->
# Assistant Framework — Memory Protocol

Old complete memory content A.
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->

User-managed content between complete memory blocks.

# Assistant Framework — Memory Protocol

## Role

You are an orchestrator. You delegate ALL file editing, code implementation, and phase execution to specialized agents.
<!-- This is a template. Paths like ~/.codex/ are substituted during install.sh for non-Claude agents. -->
<!-- Appended by Assistant Framework install. Do not remove this marker. -->
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->

Old complete memory content B.
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->

User-managed content before interrupted memory block.

# Assistant Framework — Memory Protocol

## Role

You are an orchestrator. You delegate ALL file editing, code implementation, and phase execution to specialized agents.
<!-- This is a template. Paths like ~/.codex/ are substituted during install.sh for non-Claude agents. -->
<!-- Appended by Assistant Framework install. Do not remove this marker. -->
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->

Interrupted installer-owned memory content that should be removed.
DUPLICATE_CODEX
if HOME="$INSTALL_HOME_SIX" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-duplicate-codex.out 2>/tmp/p0p4-install-duplicate-codex.err; then
    agents_file="$INSTALL_HOME_SIX/.codex/AGENTS.md"
    starts="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START" "$agents_file")"
    ends="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END" "$agents_file")"
    preambles="$(count_occurrences "^# Assistant Framework — Memory Protocol$" "$agents_file")"
    agents_starts="$(count_occurrences "ASSISTANT_FRAMEWORK_AGENTS_MD_START" "$agents_file")"
    agents_ends="$(count_occurrences "ASSISTANT_FRAMEWORK_AGENTS_MD_END" "$agents_file")"
    if [[ "$starts" == "1" && "$ends" == "1" && "$preambles" == "1" ]] \
        && [[ "$agents_starts" == "1" && "$agents_ends" == "1" ]] \
        && grep -q "User-managed content before old installer blocks." "$agents_file" \
        && grep -q "User-managed content before first memory block." "$agents_file" \
        && grep -q "User-managed content between complete memory blocks." "$agents_file" \
        && grep -q "User-managed content before interrupted memory block." "$agents_file" \
        && ! grep -q "Old complete memory content A" "$agents_file" \
        && ! grep -q "Old complete memory content B" "$agents_file" \
        && ! grep -q "Interrupted installer-owned memory content" "$agents_file"; then
        pass
    else
        fail "expected duplicate and interrupted Codex memory protocol blocks to be replaced once while preserving user content"
    fi
else
    fail "Codex install with duplicate memory protocols failed; see /tmp/p0p4-install-duplicate-codex.err"
fi

test_start "installer strips substituted Gemini legacy memory preamble"
INSTALL_HOME_FOUR="$(mktemp -d)"
mkdir -p "$INSTALL_HOME_FOUR/.gemini"
cat > "$INSTALL_HOME_FOUR/.gemini/GEMINI.md" <<'TRUNCATED_GEMINI'
User-managed Gemini heading before installer content.

# Assistant Framework — Memory Protocol

## Role

You are an orchestrator. You delegate ALL file editing, code implementation, and phase execution to specialized agents.
<!-- This is a template. Paths like ~/.gemini/ are substituted during install.sh for non-Claude agents. -->
<!-- Appended by Assistant Framework install. Do not remove this marker. -->
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->

Interrupted installer-owned Gemini memory content that should be removed.
TRUNCATED_GEMINI
if HOME="$INSTALL_HOME_FOUR" bash "$FRAMEWORK_DIR/install.sh" --agent gemini --skill assistant-workflow --no-hooks >/tmp/p0p4-install-gemini-truncated.out 2>/tmp/p0p4-install-gemini-truncated.err; then
    gemini_file="$INSTALL_HOME_FOUR/.gemini/GEMINI.md"
    starts="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START" "$gemini_file")"
    ends="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END" "$gemini_file")"
    preambles="$(count_occurrences "^# Assistant Framework — Memory Protocol$" "$gemini_file")"
    if [[ "$starts" == "1" && "$ends" == "1" && "$preambles" == "1" ]] \
        && grep -q "User-managed Gemini heading before installer content." "$gemini_file" \
        && ! grep -q "Interrupted installer-owned Gemini memory content" "$gemini_file"; then
        pass
    else
        fail "expected substituted Gemini installer block to be replaced once while preserving user content"
    fi
else
    fail "Gemini install after truncated memory protocol failed; see /tmp/p0p4-install-gemini-truncated.err"
fi

test_start "non-Claude skill install substitutes .claude paths in instruction/config files"
INSTALL_HOME_TWO="$(mktemp -d)"
if HOME="$INSTALL_HOME_TWO" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-subst.out 2>/tmp/p0p4-install-subst.err; then
    if find "$INSTALL_HOME_TWO/.codex/skills/assistant-workflow" -type f \( -name "*.md" -o -name "*.yaml" -o -name "*.yml" -o -name "*.conf" -o -name "*.toml" \) -print0 \
        | xargs -0 grep -n "\.claude/" >/tmp/p0p4-claude-paths.out 2>/dev/null; then
        fail "found unsubstituted .claude paths in installed codex skill; see /tmp/p0p4-claude-paths.out"
    else
        pass
    fi
else
    fail "codex skill install failed; see /tmp/p0p4-install-subst.err"
fi

test_start "installer reinstall removes stale installed tool build artifacts"
INSTALL_HOME_SEVEN="$(mktemp -d)"
if HOME="$INSTALL_HOME_SEVEN" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-tools-1.out 2>/tmp/p0p4-install-tools-1.err; then
    stale_publish="$INSTALL_HOME_SEVEN/.codex/tools/memory-graph/.publish"
    stale_bin="$INSTALL_HOME_SEVEN/.codex/tools/memory-graph/src/MemoryGraph/bin"
    stale_obj="$INSTALL_HOME_SEVEN/.codex/tools/memory-graph/src/MemoryGraph/obj"
    mkdir -p "$stale_publish" "$stale_bin" "$stale_obj"
    touch "$stale_publish/MemoryGraph" "$stale_bin/stale.dll" "$stale_obj/stale.dll"
    if HOME="$INSTALL_HOME_SEVEN" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-tools-2.out 2>/tmp/p0p4-install-tools-2.err; then
        if [[ ! -e "$stale_publish" && ! -e "$stale_bin" && ! -e "$stale_obj" ]]; then
            pass
        else
            fail "expected stale memory-graph .publish, bin, and obj artifacts to be removed after reinstall"
        fi
    else
        fail "second install for stale tool cleanup failed; see /tmp/p0p4-install-tools-2.err"
    fi
else
    fail "first install for stale tool cleanup failed; see /tmp/p0p4-install-tools-1.err"
fi

test_start "Codex hook template is valid JSON with one PreToolUse key"
if jq -e . "$FRAMEWORK_DIR/hooks/codex-settings.json" >/dev/null \
    && [[ "$(grep -o '"PreToolUse"' "$FRAMEWORK_DIR/hooks/codex-settings.json" | wc -l | tr -d ' ')" == "1" ]]; then
    pass
else
    fail "hooks/codex-settings.json must parse and contain exactly one raw PreToolUse key"
fi

test_start "Codex hook reinstall merges hooks sanely"
INSTALL_HOME_FIVE="$(mktemp -d)"
mkdir -p "$INSTALL_HOME_FIVE/.codex"
cat > "$INSTALL_HOME_FIVE/.codex/hooks.json" <<'JSON'
{
  "hooks": {
    "PostCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.codex/hooks/assistant/post-compact.sh"
          },
          {
            "type": "command",
            "command": "/tmp/user-custom-hook.sh"
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.codex/hooks/assistant/pre-compress.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.codex/hooks/assistant/workflow-guard.sh"
          },
          {
            "type": "command",
            "command": "/tmp/user-pretool-hook.sh"
          }
        ]
      }
    ]
  }
}
JSON
if HOME="$INSTALL_HOME_FIVE" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow >/tmp/p0p4-install-codex-hooks.out 2>/tmp/p0p4-install-codex-hooks.err; then
    if jq -e . "$INSTALL_HOME_FIVE/.codex/hooks.json" >/dev/null && jq -e '
        [.. | objects | .command? // empty] as $commands
        | [$commands[] | select(startswith("$HOME/.codex/hooks/assistant/"))] as $frameworkCommands
        | {
            stale: ($commands | any(. == "$HOME/.codex/hooks/assistant/post-compact.sh"
                or . == "$HOME/.codex/hooks/assistant/pre-compress.sh"
                or . == "$HOME/.codex/hooks/assistant/session-end.sh"
                or . == "$HOME/.codex/hooks/assistant/task-completed.sh")),
            custom: ($commands | any(. == "/tmp/user-custom-hook.sh")),
            preToolCustom: ($commands | any(. == "/tmp/user-pretool-hook.sh")),
            uniqueFramework: (($frameworkCommands | length) == ($frameworkCommands | unique | length)),
            sessionStart: ([.hooks.SessionStart[]?.hooks[]?.command?] | any(. == "$HOME/.codex/hooks/assistant/session-start.sh")),
            workflowGuard: ([.hooks.PreToolUse[]?.hooks[]?.command?] | any(. == "$HOME/.codex/hooks/assistant/workflow-guard.sh"))
        }
        | (.stale | not) and .custom and .preToolCustom and .uniqueFramework and .sessionStart and .workflowGuard
    ' "$INSTALL_HOME_FIVE/.codex/hooks.json" >/dev/null; then
        pass
    else
        fail "Codex hook reinstall did not remove stale framework hooks, preserve custom hooks, or dedupe framework commands"
    fi
else
    fail "codex hook reinstall failed; see /tmp/p0p4-install-codex-hooks.err"
fi

test_start "canonical workflow phase lists do not inject standalone TEST/VERIFY phases"
if rg -n "TRIAGE -> DISCOVER -> PLAN -> BUILD -> TEST|BUILD -> TEST -> VERIFY|TEST -> VERIFY" \
    "$FRAMEWORK_DIR/install.sh" \
    "$FRAMEWORK_DIR/hooks/scripts/workflow-enforcer.sh" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml" >/tmp/p0p4-stale-phases.out; then
    fail "found stale TEST/VERIFY phase list; see /tmp/p0p4-stale-phases.out"
else
    pass
fi

test_start "Codex AGENTS generated phase list includes conditional decompose and design"
if grep -q "TRIAGE -> DISCOVER -> DECOMPOSE when needed -> PLAN -> DESIGN when needed -> BUILD -> REVIEW -> DOCUMENT" \
    "$FRAMEWORK_DIR/install.sh"; then
    pass
else
    fail "generated Codex AGENTS phase list is missing canonical conditional DECOMPOSE/DESIGN wording"
fi

test_start "review contracts support review_material_snapshot without diff-only gates"
if rg -n "diff_content|Reviewer received: diff|current diff|from the diff|review_scope is resolved to one of: files, diff" \
    "$FRAMEWORK_DIR/skills/assistant-review" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/review-rubric.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml" >/tmp/p0p4-review-diff-only.out; then
    fail "found diff-only review contract wording; see /tmp/p0p4-review-diff-only.out"
else
    pass
fi

test_start "reviewer handoff rejects diff-only material fields and finding gates"
if rg -n "name: diff|Full diff|exists in the diff" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml" >/tmp/p0p4-review-handoff-diff-only.out; then
    fail "found diff-only reviewer handoff wording; see /tmp/p0p4-review-handoff-diff-only.out"
else
    pass
fi

test_start "workflow templates and scripts do not use stale Build & Test or VERIFYING labels"
if rg -n "Build & Test|VERIFYING" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/decompose.sh" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/generate-agents-md.sh" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/context-handoff-templates.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/sub-task-brief-template.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/mega-and-patterns.md" >/tmp/p0p4-stale-workflow-labels.out; then
    fail "found stale workflow template/script labels; see /tmp/p0p4-stale-workflow-labels.out"
else
    pass
fi

test_start "memory protocol wording avoids graph-only storage and matching installed-agent paths"
if jq -e . >/dev/null 2>&1 <<< '{}'; then
    :
fi
if rg -n "WAL|markdown sync|memory files are the source of truth|knowledge graph .+source of truth|loaded at session start via hooks|graph\\.jsonl.+source of truth|\\.claude/" "$INSTALL_HOME_TWO/.codex/AGENTS.md" >/tmp/p0p4-memory-wording.out; then
    fail "installed Codex memory protocol has stale memory wording or paths; see /tmp/p0p4-memory-wording.out"
else
    pass
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

test_start "docs eval fixture JSON has the five required behavior cases"
if jq -e '
    .schema_version == "1.0"
    and ([.cases[].id] | sort) == ([
      "ambiguous-prompt-clarify-or-default-deterministically",
      "compaction-resume-reads-task-state-first",
      "medium-feature-plans-before-build",
      "review-loop-continues-after-findings",
      "small-fix-stays-lightweight"
    ] | sort)
    and (.cases | length == 5)
' "$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json" >/dev/null; then
    pass
else
    fail "eval JSON is invalid or missing required behavior cases"
fi

finish
