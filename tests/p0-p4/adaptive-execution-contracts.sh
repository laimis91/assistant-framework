#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

workflow="$FRAMEWORK_DIR/skills/assistant-workflow"
tdd="$FRAMEWORK_DIR/skills/assistant-tdd"

test_start "workflow defines adaptive build execution lanes"
if p0p4_contains_text "$workflow/contracts/input.yaml" "- name: build_execution_lane" \
    && p0p4_contains_text "$workflow/contracts/input.yaml" "enum_values: [none, inline_direct, bounded_executor, separated_workers]" \
    && p0p4_contains_text "$workflow/contracts/output.yaml" "- name: build_execution_lane"; then
    pass
else
    fail "workflow does not expose a typed execution lane"
fi

test_start "prepare-only routes to no execution lane"
if p0p4_contains_text "$workflow/contracts/input.yaml" "For execution_intent == prepare_only, use none" \
    && p0p4_contains_text "$workflow/contracts/phase-gates.yaml" "build_execution_lane=none"; then
    pass
else
    fail "prepare-only routing does not select the no-execution lane"
fi

test_start "ordinary medium defaults to bounded executor plus independent review"
if p0p4_contains_text "$workflow/references/workflow-controller.md" "ordinary medium" \
    && p0p4_contains_text "$workflow/references/workflow-controller.md" "build_execution_lane=bounded_executor" \
    && p0p4_contains_text "$workflow/references/workflow-controller.md" "independent Code Reviewer"; then
    pass
else
    fail "ordinary medium still requires split write/test workers"
fi

test_start "separated workers are conditional rather than size ceremony"
if p0p4_contains_text "$workflow/references/build-worker-protocol.md" "broad or noisy verification" \
    && p0p4_contains_text "$workflow/references/build-worker-protocol.md" "environment-heavy" \
    && p0p4_contains_text "$workflow/references/build-worker-protocol.md" "high or critical risk"; then
    pass
else
    fail "Builder/Tester separation lacks explicit risk and verification triggers"
fi

test_start "phase gates accept bounded executor evidence without fake Builder dispatch"
if p0p4_contains_text "$workflow/contracts/phase-gates.yaml" "build_execution_lane == bounded_executor" \
    && p0p4_contains_text "$workflow/contracts/phase-gates.yaml" "implementation, selected-check results, and changed-file evidence" \
    && p0p4_contains_text "$workflow/contracts/phase-gates.yaml" "Builder/Tester is required only when build_execution_lane == separated_workers"; then
    pass
else
    fail "build gates still hard-code Writer plus Builder for ordinary medium"
fi

test_start "all build and recovery surfaces obey the selected execution lane"
if ! grep -Fq 'run the Code Writer -> Builder/Tester loop' "$workflow/references/phases.md" \
    && p0p4_contains_text "$workflow/references/build-worker-protocol.md" "the bounded executor adds or extends" \
    && p0p4_contains_text "$workflow/references/build-worker-protocol.md" "Builder/Tester returns one typed" \
    && p0p4_contains_text "$workflow/references/build-worker-protocol.md" "Code Writer owns production and records" \
    && p0p4_contains_text "$workflow/references/build-worker-protocol.md" "pre_production_red" \
    && p0p4_contains_text "$workflow/references/build-worker-protocol.md" "route verification through the selected build_execution_lane" \
    && ! grep -Fq 'return to Builder/Tester RED evidence' "$workflow/references/build-worker-protocol.md" \
    && p0p4_contains_text "$workflow/contracts/phase-gates.yaml" "Repair evidence according to build_execution_lane" \
    && p0p4_contains_text "$workflow/contracts/phase-gates.yaml" "Inactive bounded_executor: CodeWriter owns selected verification" \
    && p0p4_contains_text "$workflow/contracts/phase-gates.yaml" "separated_workers dispatches BuilderTester final_verification" \
    && ! grep -Fq 'Add per-slice Code Writer and Builder/Tester dispatch/result evidence' "$workflow/contracts/phase-gates.yaml"; then
    pass
else
    fail "a phase, recovery, or gate surface still forces Builder/Tester in bounded_executor"
fi

test_start "required roles are lane aware instead of unconditional"
if p0p4_contains_text "$workflow/contracts/input.yaml" "bounded_executor requires one implementation and selected-verification owner plus independent Code Reviewer responsibility" \
    && p0p4_contains_text "$workflow/contracts/input.yaml" "separated_workers requires Code Writer, Builder/Tester, and independent Code Reviewer responsibilities" \
    && ! grep -Fq 'Standard/strict development work that changes project artifacts includes Code Writer, Builder/Tester, and Code Reviewer responsibilities.' "$workflow/contracts/input.yaml"; then
    pass
else
    fail "required_agents validation still makes Builder/Tester universal"
fi

test_start "subagent evidence contract follows selected execution lane"
if p0p4_contains_text "$workflow/contracts/output.yaml" "bounded_executor_evidence" \
    && p0p4_contains_text "$workflow/contracts/output.yaml" "separated_worker_evidence" \
    && p0p4_contains_text "$workflow/contracts/output.yaml" "Independent Code Reviewer evidence remains required"; then
    pass
else
    fail "completion evidence cannot distinguish bounded and separated lanes"
fi

test_start "TDD supports one bounded owner without weakening RED"
if p0p4_contains_text "$tdd/SKILL.md" "one owner authors tests, observes RED, implements, and verifies GREEN and REFACTOR" \
    && p0p4_contains_text "$tdd/SKILL.md" "observe the intended missing-behavior failure before production edits" \
    && p0p4_contains_text "$tdd/contracts/input.yaml" "enum_values: [bounded_executor, separated_workers]"; then
    pass
else
    fail "TDD still requires a cross-agent telephone game"
fi

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
valid = source.include?("load `contracts/index.yaml` and the relevant entry, current-phase, selected-handoff, packet-admission, and completion sets") &&
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
