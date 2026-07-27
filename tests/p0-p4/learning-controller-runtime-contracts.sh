#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

workflow="$FRAMEWORK_DIR/skills/assistant-workflow"
validator="$workflow/scripts/validate-learning-state.sh"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/learning-state-contracts.XXXXXX")"
p0p4_register_cleanup "$fixture_root"

write_journal() {
    local path="$1"
    shift
    printf '%s\n' "$@" >"$path"
}

test_start "learning state validator exists and accepts normal auto mode without lesson evidence"
write_journal "$fixture_root/auto-clean.md" \
    '# Task' \
    'Learning capture mode: auto' \
    'Learning capture reason: normal_default: evidence-triggered learning remains enabled' \
    'Learning evidence signals: none' \
    'Verification: focused and aggregate checks passed'
if [[ -f "$validator" ]] && bash "$validator" "$fixture_root/auto-clean.md" >/dev/null 2>&1; then
    pass
else
    fail "workflow must ship a validator that accepts the normal auto default"
fi

test_start "learning state validator rejects invalid manual mode"
write_journal "$fixture_root/manual.md" \
    '# Task' \
    'Learning capture mode: manual' \
    'Learning capture reason: normal_default: stale legacy value' \
    'Learning evidence signals: none'
if [[ -f "$validator" ]] && ! bash "$validator" "$fixture_root/manual.md" >/dev/null 2>&1; then
    pass
else
    fail "manual must not bypass the typed learning controller"
fi

test_start "learning state validator rejects unjustified not_required"
write_journal "$fixture_root/unjustified-skip.md" \
    '# Task' \
    'Learning capture mode: not_required' \
    'Learning capture reason: routine task' \
    'Learning evidence signals: none'
if [[ -f "$validator" ]] && ! bash "$validator" "$fixture_root/unjustified-skip.md" >/dev/null 2>&1; then
    pass
else
    fail "not_required must require policy_disallowed or explicit_exclusion evidence"
fi

test_start "learning state validator accepts explicit exclusion rationale"
write_journal "$fixture_root/excluded.md" \
    '# Task' \
    'Learning capture mode: not_required' \
    'Learning capture reason: explicit_exclusion: user requested a literal one-line translation only' \
    'Learning evidence signals: none'
if [[ -f "$validator" ]] && bash "$validator" "$fixture_root/excluded.md" >/dev/null 2>&1; then
    pass
else
    fail "a concrete explicit exclusion must remain valid"
fi

test_start "learning state validator rejects an empty exclusion prefix"
write_journal "$fixture_root/empty-exclusion.md" \
    '# Task' \
    'Learning capture mode: not_required' \
    'Learning capture reason: explicit_exclusion:' \
    'Learning evidence signals: none'
if [[ -f "$validator" ]] && ! bash "$validator" "$fixture_root/empty-exclusion.md" >/dev/null 2>&1; then
    pass
else
    fail "a reason prefix without a concrete rationale must not disable learning"
fi

test_start "lesson-bearing auto evidence requires a completed Learning Controller block"
write_journal "$fixture_root/missing-controller.md" \
    '# Task' \
    'Learning capture mode: auto' \
    'Learning capture reason: normal_default: evidence-triggered learning remains enabled' \
    'Learning evidence signals: build_test_failure'
write_journal "$fixture_root/complete-controller.md" \
    '# Task' \
    'Learning capture mode: auto' \
    'Learning capture reason: normal_default: evidence-triggered learning remains enabled' \
    'Learning evidence signals: build_test_failure' \
    '## Learning Controller' \
    'Memory trend checked: backend_unavailable' \
    'Learning evidence reviewed: build_test_failure — baseline compilation failed' \
    'Review findings considered: none — no review finding' \
    'Build/test failures considered: baseline compilation failure was repaired' \
    'User corrections considered: none — no user correction' \
    'Durable lesson decision: backend_unavailable' \
    'Persistence evidence: N/A' \
    'No-save rationale: isolated eval configuration exposes no Memory Graph backend'
if [[ -f "$validator" ]] \
    && ! bash "$validator" "$fixture_root/missing-controller.md" >/dev/null 2>&1 \
    && bash "$validator" "$fixture_root/complete-controller.md" >/dev/null 2>&1; then
    pass
else
    fail "lesson-bearing evidence must activate a complete Learning Controller decision"
fi

test_start "workflow contracts make auto the normal default and validate journal learning state"
if grep -Fq 'normal work MUST use auto' "$workflow/contracts/input.yaml" \
    && grep -Fq 'not_required is valid only with a policy_disallowed: or explicit_exclusion: reason' "$workflow/contracts/input.yaml" \
    && grep -Fq 'validate-learning-state.sh' "$workflow/contracts/phase-gates.yaml" \
    && grep -Fq 'Learning capture reason:' "$workflow/references/task-journal-template.md" \
    && grep -Fq 'Learning evidence signals:' "$workflow/references/task-journal-template.md"; then
    pass
else
    fail "workflow contract surfaces do not yet enforce the learning-state policy"
fi

test_start "Reflexion records privacy-safe typed signals without raw user text"
if grep -Fq 'memory_signal' "$FRAMEWORK_DIR/skills/assistant-reflexion/SKILL.md" \
    && grep -Fq 'Never send raw user text' "$FRAMEWORK_DIR/skills/assistant-reflexion/SKILL.md" \
    && grep -Fq 'correction, pivot, frustration, or non-routine approval' "$FRAMEWORK_DIR/skills/assistant-reflexion/SKILL.md"; then
    pass
else
    fail "Reflexion lacks the bounded signal-capture contract"
fi

test_start "README describes evidence-triggered improvement instead of every-task reflection"
if grep -Fq 'Evidence-backed lessons improve future tasks; routine tasks skip reflection.' "$FRAMEWORK_DIR/README.md" \
    && ! grep -Fq 'Every task makes the next task better through reflexion' "$FRAMEWORK_DIR/README.md" \
    && grep -Fq '**16 MCP tools:**' "$FRAMEWORK_DIR/README.md" \
    && grep -Fq '`memory_signal`' "$FRAMEWORK_DIR/README.md"; then
    pass
else
    fail "README still overclaims self-improvement or omits the signal tool"
fi

test_start "Codex behavioral fixtures include trace-verified Reflexion activation"
if jq -e '
      any(.cases[];
        .id == "learning-evidence-activates-reflexion"
        and .category == "learning_controller"
        and (.pass_criteria | any(contains("JSONL trace"))))
    ' "$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json" >/dev/null \
    && grep -Fq 'learning-evidence-activates-reflexion:.assistant-eval/learning-controller.json' "$FRAMEWORK_DIR/tools/evals/run-codex-framework-evals.sh" \
    && grep -Fq 'assistant-reflexion/SKILL' "$FRAMEWORK_DIR/tools/evals/run-codex-framework-evals.sh" \
    && grep -Fq 'memory_reflect' "$FRAMEWORK_DIR/tools/evals/run-codex-framework-evals.sh"; then
    pass
else
    fail "the real Codex runner lacks a Reflexion-load plus persistence/no-save trace verifier"
fi

test_start "Codex learning eval hides Reflexion grader fixtures and rejects path-only load claims"
if grep -Fq 'skills/assistant-reflexion" -mindepth 1 -maxdepth 1 ! -name evals' "$FRAMEWORK_DIR/tools/evals/run-codex-framework-evals.sh" \
    && grep -Fq 'read_command' "$FRAMEWORK_DIR/tools/evals/run-codex-framework-evals.sh" \
    && grep -Fq 'cat|sed|head|tail|awk|rg' "$FRAMEWORK_DIR/tools/evals/run-codex-framework-evals.sh"; then
    pass
else
    fail "the learning eval exposes grader fixtures or accepts a command that only mentions the skill path"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
