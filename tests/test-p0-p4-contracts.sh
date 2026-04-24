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
trap 'rm -rf "$INSTALL_HOME" "${INSTALL_HOME_TWO:-}" "${INSTALL_HOME_THREE:-}" "${INSTALL_HOME_FOUR:-}"' EXIT
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

test_start "memory protocol wording uses graph-only storage and matching installed-agent paths"
if jq -e . >/dev/null 2>&1 <<< '{}'; then
    :
fi
if rg -n "WAL|markdown sync|memory files are the source of truth|\.claude/" "$INSTALL_HOME_TWO/.codex/AGENTS.md" >/tmp/p0p4-memory-wording.out; then
    fail "installed Codex memory protocol has stale memory wording or paths; see /tmp/p0p4-memory-wording.out"
else
    pass
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
