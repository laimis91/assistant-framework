#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

workflow_output="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"
workflow_gates="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"
reduction_doc="$FRAMEWORK_DIR/docs/instruction-overload-reduction.md"

count_framework_hooks_in_event() {
    local settings_file="$1"
    local event="$2"
    jq -r --arg event "$event" '[(.hooks[$event] // [])[]?.hooks[]?.command? | select(test("/hooks/assistant/"))] | length' "$settings_file"
}

test_start "workflow output contract has tiered completion artifacts"
if grep -Fq "completion_tiers:" "$workflow_output" \
    && grep -Fq "small:" "$workflow_output" \
    && grep -Fq "medium:" "$workflow_output" \
    && grep -Fq "large_critical:" "$workflow_output" \
    && grep -Fq "self-review or explicit validation summary" "$workflow_output" \
    && grep -Fq "phase_checkpoints are strict-profile only" "$workflow_output" \
    && grep -Fq "condition: \"size in [medium, large, mega] or risk_tier in [high, critical] or hook_profile == strict\"" "$workflow_output" \
    && grep -Fq "When size is medium/large/mega, risk_tier is high/critical, or hook_profile == strict: spec_review_result.status == PASS" "$workflow_output" \
    && grep -Fq "When size is medium/large/mega, risk_tier is high/critical, or hook_profile == strict: review_result.quality_review_status is not missing" "$workflow_output"; then
    pass
else
    fail "assistant-workflow output contract must define small/medium/large-critical completion tiers and conditional heavy review artifacts"
fi

test_start "phase gates separate blockers from guidance"
if grep -Fq "gate_tiers:" "$workflow_gates" \
    && grep -Fq "guidance_assertions:" "$workflow_gates" \
    && grep -Fq "severity: guidance" "$workflow_gates" \
    && grep -Fq "severity: strict_only" "$workflow_gates" \
    && grep -Fq 'MUST evaluate `exit_assertions`' "$workflow_gates" \
    && grep -Fq '`guidance_assertions` are non-blocking reminders' "$workflow_gates" \
    && grep -Fq "do not ask ritual questions or block low-risk progress" "$workflow_gates"; then
    pass
else
    fail "phase-gates.yaml must include gate_tiers and move non-blocking ceremony into guidance_assertions"
fi

test_start "strict hook settings use one consolidated stop gate"
settings_failures=()
for settings in hooks/claude-settings.json hooks/gemini-settings.json hooks/codex-settings.json; do
    settings_file="$FRAMEWORK_DIR/$settings"
    if grep -Fq "harness-gate.sh" "$settings_file"; then
        settings_failures+=("$settings still registers harness-gate.sh")
    fi
    if [[ "$(count_framework_hooks_in_event "$settings_file" "Stop")" -gt 1 ]]; then
        settings_failures+=("$settings has multiple Stop framework hooks")
    fi
    if [[ "$settings" == "hooks/gemini-settings.json" ]] && [[ "$(count_framework_hooks_in_event "$settings_file" "AfterAgent")" -gt 1 ]]; then
        settings_failures+=("$settings has multiple AfterAgent framework hooks")
    fi
done
if [[ "${#settings_failures[@]}" -eq 0 ]] \
    && grep -Fq "Consolidated strict stop gate" "$FRAMEWORK_DIR/hooks/scripts/stop-review.sh"; then
    pass
else
    fail "strict hook templates should register only stop-review.sh as the stop gate: ${settings_failures[*]:-missing stop-review consolidation marker}"
fi

test_start "plugin-local skills are generated mirrors with a sync check"
if [[ -x "$FRAMEWORK_DIR/tools/plugins/sync-plugin-skills.sh" ]] \
    && "$FRAMEWORK_DIR/tools/plugins/sync-plugin-skills.sh" --check >/tmp/p0p4-plugin-sync-check.out 2>/tmp/p0p4-plugin-sync-check.err \
    && grep -Fq "generated skill mirrors" /tmp/p0p4-plugin-sync-check.out \
    && grep -Fq "generated release artifacts" "$FRAMEWORK_DIR/docs/plugin-architecture.md" \
    && grep -Fq "sync-plugin-skills.sh --check" "$FRAMEWORK_DIR/README.md"; then
    pass
else
    fail "plugin-local copies must be documented and checkable as generated mirrors; see /tmp/p0p4-plugin-sync-check.err"
fi

test_start "prompt bloat lint flags duplicated strict hooks and always-required heavy artifacts"
bloat_failures=()
if grep -R --line-number 'harness-gate.sh' "$FRAMEWORK_DIR/hooks/claude-settings.json" "$FRAMEWORK_DIR/hooks/gemini-settings.json" "$FRAMEWORK_DIR/hooks/codex-settings.json" >/tmp/p0p4-bloat-hooks.out; then
    bloat_failures+=("strict templates still register harness-gate.sh")
fi
if awk '
    $0 == "  - name: spec_review_result" { in_spec = 1; next }
    in_spec && /^  - name: / { in_spec = 0 }
    in_spec && /^    required: true/ { found = 1 }
    END { exit found ? 0 : 1 }
' "$workflow_output"; then
    bloat_failures+=("spec_review_result is still unconditionally required")
fi
if awk '
    $0 == "  - name: review_result" { in_review = 1; next }
    in_review && /^  - name: / { in_review = 0 }
    in_review && /^    required: true/ { found = 1 }
    END { exit found ? 0 : 1 }
' "$workflow_output"; then
    bloat_failures+=("review_result is still unconditionally required")
fi
if [[ "${#bloat_failures[@]}" -eq 0 ]] && grep -Fq "Prompt bloat linting" "$reduction_doc"; then
    pass
else
    fail "prompt bloat lint failed: ${bloat_failures[*]:-reduction doc missing Prompt bloat linting section}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
