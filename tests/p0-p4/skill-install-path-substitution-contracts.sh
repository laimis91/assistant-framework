#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "installable skill and protocol sources use {agent_state_dir} instead of raw .claude paths"
RAW_CLAUDE_SCAN_OUT="/tmp/p0p4-raw-claude-installable-scan.out"
if rg -n '(~?/)?\.claude/' \
    "$FRAMEWORK_DIR/skills" \
    "$FRAMEWORK_DIR/plugins" \
    "$FRAMEWORK_DIR/memory-protocol.md" \
    >"$RAW_CLAUDE_SCAN_OUT"; then
    fail "installable skill/protocol sources must not contain raw .claude paths; see $RAW_CLAUDE_SCAN_OUT"
else
    pass
fi

test_start "Codex skill install substitutes {agent_state_dir} placeholders in copied instruction/config files"
INSTALL_HOME="$(mktemp -d)"
FIXTURE_FRAMEWORK="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME" "$FIXTURE_FRAMEWORK"
mkdir -p "$FIXTURE_FRAMEWORK/skills/path-substitution-contract/contracts" \
    "$FIXTURE_FRAMEWORK/skills/path-substitution-contract/evals" \
    "$FIXTURE_FRAMEWORK/skills/path-substitution-contract/references"
cp "$FRAMEWORK_DIR/install.sh" "$FIXTURE_FRAMEWORK/install.sh"
cat > "$FIXTURE_FRAMEWORK/skills/path-substitution-contract/SKILL.md" <<'SKILL_FIXTURE'
---
name: path-substitution-contract
description: "Fixture for install-time path substitution."
---

# Path Substitution Contract

Load ~/{agent_state_dir}/skills/path-substitution-contract/SKILL.md before acting.
Persist active work in `{agent_state_dir}/task.md`.
Claude-specific prose can stay when it is not an agent state path.
SKILL_FIXTURE
cat > "$FIXTURE_FRAMEWORK/skills/path-substitution-contract/contracts/output.yaml" <<'CONTRACT_FIXTURE'
artifacts:
  - name: task_journal
    location: "{agent_state_dir}/task.md"
  - name: workflow_metrics
    location: "~/{agent_state_dir}/memory/metrics/workflow-metrics.jsonl"
CONTRACT_FIXTURE
cat > "$FIXTURE_FRAMEWORK/skills/path-substitution-contract/references/task-journal-template.md" <<'REFERENCE_FIXTURE'
# Task Journal Template

Write to `{agent_state_dir}/task.md` in nested references.
Read `~/{agent_state_dir}/agents/code-writer.md` for worker-specific instructions.
REFERENCE_FIXTURE
cat > "$FIXTURE_FRAMEWORK/skills/path-substitution-contract/evals/cases.json" <<'EVAL_FIXTURE'
[
  {
    "id": "json-path-substitution",
    "setup_context": [
      "An existing project `{agent_state_dir}/telos.md` may be present.",
      "A global file may live at `~/{agent_state_dir}/memory/graph.jsonl`."
    ]
  }
]
EVAL_FIXTURE
if HOME="$INSTALL_HOME" bash "$FIXTURE_FRAMEWORK/install.sh" --agent codex --skill path-substitution-contract --no-hooks >/tmp/p0p4-install-subst.out 2>/tmp/p0p4-install-subst.err; then
    installed_skill="$INSTALL_HOME/.codex/skills/path-substitution-contract"
    installed_root="$installed_skill/SKILL.md"
    installed_contract="$installed_skill/contracts/output.yaml"
    installed_reference="$installed_skill/references/task-journal-template.md"
    installed_eval="$installed_skill/evals/cases.json"

    if [[ ! -f "$installed_root" || ! -f "$installed_contract" || ! -f "$installed_reference" || ! -f "$installed_eval" ]]; then
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
    elif ! grep -Fq 'An existing project `.codex/telos.md` may be present.' "$installed_eval"; then
        fail "expected JSON eval fixture to contain substituted .codex project path"
    elif ! grep -Fq 'A global file may live at `~/.codex/memory/graph.jsonl`.' "$installed_eval"; then
        fail "expected JSON eval fixture to contain substituted ~/.codex memory path"
    elif grep -Fq "{agent_state_dir}" "$installed_root" \
        || grep -Fq "{agent_state_dir}" "$installed_contract" \
        || grep -Fq "{agent_state_dir}" "$installed_reference" \
        || grep -Fq "{agent_state_dir}" "$installed_eval"; then
        fail "found unresolved {agent_state_dir} placeholder in installed Codex fixture skill"
    else
        pass
    fi
else
    fail "codex fixture skill install failed; see /tmp/p0p4-install-subst.err"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
