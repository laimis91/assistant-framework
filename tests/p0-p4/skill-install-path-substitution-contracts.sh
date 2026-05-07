#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "Codex skill install substitutes representative .claude paths in copied instruction/config files"
INSTALL_HOME="$(mktemp -d)"
FIXTURE_FRAMEWORK="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME" "$FIXTURE_FRAMEWORK"
mkdir -p "$FIXTURE_FRAMEWORK/skills/path-substitution-contract/contracts" \
    "$FIXTURE_FRAMEWORK/skills/path-substitution-contract/references"
cp "$FRAMEWORK_DIR/install.sh" "$FIXTURE_FRAMEWORK/install.sh"
cat > "$FIXTURE_FRAMEWORK/skills/path-substitution-contract/SKILL.md" <<'SKILL_FIXTURE'
---
name: path-substitution-contract
description: "Fixture for install-time path substitution."
---

# Path Substitution Contract

Load ~/.claude/skills/path-substitution-contract/SKILL.md before acting.
Persist active work in `.claude/task.md`.
Claude-specific prose can stay when it is not an agent state path.
SKILL_FIXTURE
cat > "$FIXTURE_FRAMEWORK/skills/path-substitution-contract/contracts/output.yaml" <<'CONTRACT_FIXTURE'
artifacts:
  - name: task_journal
    location: ".claude/task.md"
  - name: workflow_metrics
    location: "~/.claude/memory/metrics/workflow-metrics.jsonl"
CONTRACT_FIXTURE
cat > "$FIXTURE_FRAMEWORK/skills/path-substitution-contract/references/task-journal-template.md" <<'REFERENCE_FIXTURE'
# Task Journal Template

Write to `.claude/task.md` in nested references.
Read `~/.claude/agents/code-writer.md` for worker-specific instructions.
REFERENCE_FIXTURE
if HOME="$INSTALL_HOME" bash "$FIXTURE_FRAMEWORK/install.sh" --agent codex --skill path-substitution-contract --no-hooks >/tmp/p0p4-install-subst.out 2>/tmp/p0p4-install-subst.err; then
    installed_skill="$INSTALL_HOME/.codex/skills/path-substitution-contract"
    installed_root="$installed_skill/SKILL.md"
    installed_contract="$installed_skill/contracts/output.yaml"
    installed_reference="$installed_skill/references/task-journal-template.md"

    if [[ ! -f "$installed_root" || ! -f "$installed_contract" || ! -f "$installed_reference" ]]; then
        fail "expected Codex fixture skill files to be installed"
    elif ! grep -Fq "Load ~/.codex/skills/path-substitution-contract/SKILL.md before acting." "$installed_root"; then
        fail "expected root SKILL.md to contain substituted ~/.codex skill path"
    elif ! grep -Fq 'Persist active work in `.codex/task.md`.' "$installed_root"; then
        fail "expected root SKILL.md to contain substituted .codex task path"
    elif ! grep -Fq "Claude-specific prose can stay when it is not an agent state path." "$installed_root"; then
        fail "expected non-path Claude prose in root SKILL.md to remain untouched"
    elif ! grep -Fq 'location: ".codex/task.md"' "$installed_contract"; then
        fail "expected nested contract file to contain substituted .codex task path"
    elif ! grep -Fq 'location: "~/.codex/memory/metrics/workflow-metrics.jsonl"' "$installed_contract"; then
        fail "expected nested contract file to contain substituted ~/.codex metrics path"
    elif ! grep -Fq 'Write to `.codex/task.md` in nested references.' "$installed_reference"; then
        fail "expected nested reference file to contain substituted .codex task path"
    elif ! grep -Fq 'Read `~/.codex/agents/code-writer.md` for worker-specific instructions.' "$installed_reference"; then
        fail "expected nested reference file to contain substituted ~/.codex agent path"
    elif grep -Fq "~/.claude/skills/path-substitution-contract/SKILL.md" "$installed_root" \
        || grep -Fq '`.claude/task.md`' "$installed_root" \
        || grep -Fq 'location: ".claude/task.md"' "$installed_contract" \
        || grep -Fq 'location: "~/.claude/memory/metrics/workflow-metrics.jsonl"' "$installed_contract" \
        || grep -Fq '`.claude/task.md`' "$installed_reference" \
        || grep -Fq '`~/.claude/agents/code-writer.md`' "$installed_reference"; then
        fail "found representative unsubstituted .claude path in installed Codex fixture skill"
    else
        pass
    fi
else
    fail "codex fixture skill install failed; see /tmp/p0p4-install-subst.err"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
