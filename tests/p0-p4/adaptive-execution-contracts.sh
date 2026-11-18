#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

workflow="$FRAMEWORK_DIR/skills/assistant-workflow"
tdd="$FRAMEWORK_DIR/skills/assistant-tdd"

test_start "Codex writer is a bounded edit test executor when selected"
if p0p4_contains_text "$FRAMEWORK_DIR/agents/codex/code-writer.toml" "bounded_executor" \
    && p0p4_contains_text "$FRAMEWORK_DIR/agents/codex/code-writer.toml" "own the selected implementation and verification" \
    && p0p4_contains_text "$FRAMEWORK_DIR/agents/claude/code-writer.md" "own the selected implementation and verification" \
    && p0p4_contains_text "$FRAMEWORK_DIR/agents/codex/code-writer.toml" "When TDD is false, no RED is required and none should be fabricated."; then
    pass
else
    fail "Codex writer prompt lacks selected execution ownership or inactive-TDD guard"
fi

test_start "Builder Tester prompt is conditional and remains production read-only"
if p0p4_contains_text "$FRAMEWORK_DIR/agents/codex/builder-tester.toml" "separated_workers" \
    && p0p4_contains_text "$FRAMEWORK_DIR/agents/codex/builder-tester.toml" "conditional verifier" \
    && p0p4_contains_text "$FRAMEWORK_DIR/agents/codex/builder-tester.toml" "Do NOT modify production code" \
    && p0p4_contains_text "$FRAMEWORK_DIR/agents/codex/builder-tester.toml" "packet-local tdd_applies=true" \
    && p0p4_contains_text "$FRAMEWORK_DIR/agents/claude/builder-tester.md" "packet-local tdd_applies=true" \
    && p0p4_contains_text "$FRAMEWORK_DIR/agents/codex/builder-tester.toml" "When tdd_applies=false, do not require or" \
    && p0p4_contains_text "$FRAMEWORK_DIR/agents/claude/builder-tester.md" "When tdd_applies=false, do not require or" \
    && p0p4_contains_text "$FRAMEWORK_DIR/agents/codex/builder-tester.toml" "do not default the packet to false" \
    && p0p4_contains_text "$FRAMEWORK_DIR/agents/claude/builder-tester.md" "do not default the packet to false"; then
    pass
else
    fail "Builder/Tester role does not match conditional separated verification"
fi

test_start "Claude and Codex execution roles keep provider neutral semantics"
if p0p4_contains_text "$FRAMEWORK_DIR/agents/claude/code-writer.md" "bounded_executor" \
    && grep -Eq '^tools:.*Bash' "$FRAMEWORK_DIR/agents/claude/code-writer.md" \
    && p0p4_contains_text "$FRAMEWORK_DIR/agents/claude/builder-tester.md" "separated_workers"; then
    pass
else
    fail "provider role mirrors diverge from adaptive execution semantics"
fi

test_start "entry loading defers exact field names to the canonical selector"
if ruby -ryaml - "$workflow" <<'RUBY'
root = ARGV.fetch(0)
source = File.read(File.join(root, "SKILL.md")).gsub(/\s+/, " ")
index = YAML.load_file(File.join(root, "contracts/index.yaml"))
entry = index.fetch("load_sets").fetch("entry").fetch("selectors").find { |item| item["id"] == "workflow-entry-fields" }
valid = source.include?("load `contracts/index.yaml` and the relevant entry, current-phase, selected-handoff, packet-admission, and completion sets; executable admission also loads `build_admission` or `completion_admission`") &&
  entry && entry["path"] == "contracts/input.yaml" && entry["section"] == "fields" && entry["key"] == "name" &&
  !entry.fetch("names").empty? && entry.fetch("names").uniq == entry.fetch("names") &&
  !source.include?("select `task_description`, `task_type`, `scope_hint`")
exit(valid ? 0 : 1)
RUBY
then
    pass
else
    fail "always-loaded workflow root duplicates and drifts from the entry selector"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
