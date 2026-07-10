#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

workflow_output="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"
workflow_gates="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"
plan_template="$FRAMEWORK_DIR/skills/assistant-workflow/references/plan-template.md"
task_journal_template="$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md"
plan_harness_appendix="$FRAMEWORK_DIR/skills/assistant-workflow/references/plan-harness-appendix.md"
task_journal_harness_appendix="$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-harness-appendix.md"
reduction_doc="$FRAMEWORK_DIR/docs/instruction-overload-reduction.md"
benchmark_script="$FRAMEWORK_DIR/tools/hooks/benchmark-hook-output.sh"
benchmark_doc="$FRAMEWORK_DIR/docs/hook-output-benchmarks.md"
benchmark_columns="hook_name scenario stdout_bytes stdout_words stderr_bytes exit_code first_blocker_or_action"

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
    && grep -Fq "controller_intensity: light" "$workflow_output" \
    && grep -Fq "controller_intensity: standard" "$workflow_output" \
    && grep -Fq "controller_intensity: strict" "$workflow_output" \
    && grep -Fq "required_artifacts: [completion_policy, changed_files, validation_results, fresh_review_result]" "$workflow_output" \
    && grep -Fq "standard does not require Done Contract, Harness Recipe, Trace Ledger, Replay Packet, Artifact Reference Ledger, or QA evaluation" "$workflow_output" \
    && grep -Fq "fresh review after relevant validation" "$workflow_output" \
    && grep -Fq 'condition: "controller_intensity == strict or explicit project policy requires exact phase markers or user requested exact phase markers"' "$workflow_output" \
    && grep -Fq 'condition: "learning_capture_mode == required or (learning_capture_mode == auto and concrete lesson-bearing review finding, build/test failure, user correction, or memory trend evidence exists)"' "$workflow_output" \
    && grep -Fq 'condition: "manual_verification_mode == required"' "$workflow_output" \
    && grep -Fq "condition: \"size in [medium, large, mega] or risk_tier in [high, critical] or hook_profile == strict\"" "$workflow_output" \
    && grep -Fq "When size is medium/large/mega, risk_tier is high/critical, or hook_profile == strict: spec_review_result.status == PASS" "$workflow_output" \
    && grep -Fq "When size is medium/large/mega, risk_tier is high/critical, or hook_profile == strict: review_result.quality_review_status is not missing" "$workflow_output"; then
    pass
else
    fail "assistant-workflow output contract must define small/medium/large-critical completion tiers, controller intensity mapping, and conditional heavy review artifacts"
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
    && grep -Fq "Consolidated stop gate checks" "$FRAMEWORK_DIR/hooks/scripts/stop-review.sh"; then
    pass
else
    fail "strict hook templates should register only stop-review.sh as the stop gate: ${settings_failures[*]:-missing stop-review consolidation marker}"
fi

test_start "hook output benchmark baseline records required metric columns"
benchmark_failures=()
if [[ ! -f "$benchmark_script" ]]; then
    benchmark_failures+=("missing tools/hooks/benchmark-hook-output.sh")
fi
if [[ ! -f "$benchmark_doc" ]]; then
    benchmark_failures+=("missing docs/hook-output-benchmarks.md")
fi
if [[ -f "$benchmark_script" ]] && ! grep -Fq "METRIC_COLUMNS=($benchmark_columns)" "$benchmark_script"; then
    benchmark_failures+=("benchmark script metric columns changed")
fi
if [[ -f "$benchmark_doc" ]] && ! grep -Fq "| hook_name | scenario | stdout_bytes | stdout_words | stderr_bytes | exit_code | first_blocker_or_action |" "$benchmark_doc"; then
    benchmark_failures+=("benchmark doc missing exact metric table header")
fi
if [[ -f "$benchmark_doc" ]]; then
    for hook in session-start workflow-enforcer post-compact skill-router stop-review subagent-monitor; do
        if ! grep -Fq "| $hook |" "$benchmark_doc"; then
            benchmark_failures+=("benchmark doc missing $hook row")
        fi
    done
    if ! grep -Fq "runtime-gate-output-trim" "$benchmark_doc"; then
        benchmark_failures+=("benchmark doc missing runtime-gate-output-trim history row")
    fi
    workflow_enforcer_budget="$(awk -F'|' '
        $2 ~ /^[[:space:]]*workflow-enforcer[[:space:]]*$/ && $3 ~ /^[[:space:]]*codex building phase gates[[:space:]]*$/ {
            bytes = $4
            words = $5
            gsub(/[[:space:]]/, "", bytes)
            gsub(/[[:space:]]/, "", words)
            print bytes " " words
            exit
        }
    ' "$benchmark_doc")"
    if [[ -z "$workflow_enforcer_budget" ]]; then
        benchmark_failures+=("benchmark doc missing workflow-enforcer active journal metrics")
    else
        read -r workflow_enforcer_bytes workflow_enforcer_words <<< "$workflow_enforcer_budget"
        if (( workflow_enforcer_bytes >= 1511 || workflow_enforcer_words >= 164 )); then
            benchmark_failures+=("workflow-enforcer active metrics not reduced below 1511 bytes / 164 words")
        fi
    fi
fi
if [[ -f "$benchmark_script" ]] && ! grep -Fq "runtime-gate-output-trim" "$benchmark_script"; then
    benchmark_failures+=("benchmark script does not render runtime-gate-output-trim history")
fi
if [[ "${#benchmark_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "hook output benchmark guard failed: ${benchmark_failures[*]}"
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
if [[ "${#bloat_failures[@]}" -eq 0 ]] \
    && grep -Fq "Prompt bloat linting" "$reduction_doc" \
    && grep -Fq "Phase-scoped hook warnings" "$reduction_doc" \
    && grep -Fq 'gate:key missing=... action=...' "$reduction_doc"; then
    pass
else
    fail "prompt bloat lint failed: ${bloat_failures[*]:-reduction doc missing phase-scoped warning/prompt bloat sections}"
fi

test_start "base workflow templates keep harness detail in optional appendices"
template_bloat_failures=()
combined_template_words=$(( $(wc -w < "$plan_template") + $(wc -w < "$task_journal_template") ))
if [[ "$combined_template_words" -gt 3984 ]]; then
    template_bloat_failures+=("base plan+journal word count $combined_template_words exceeds 3984")
fi
for file in "$plan_harness_appendix" "$task_journal_harness_appendix"; do
    if [[ ! -f "$file" ]]; then
        template_bloat_failures+=("missing ${file#$FRAMEWORK_DIR/}")
    fi
done
if ! grep -Fq "references/plan-harness-appendix.md" "$plan_template"; then
    template_bloat_failures+=("plan-template.md missing plan harness appendix pointer")
fi
if ! grep -Fq "references/task-journal-harness-appendix.md" "$task_journal_template"; then
    template_bloat_failures+=("task-journal-template.md missing task journal harness appendix pointer")
fi
if ! grep -Fq "N/A: [reason]" "$plan_template" || ! grep -Fq "N/A: [reason]" "$task_journal_template"; then
    template_bloat_failures+=("base templates missing N/A-with-reason fields")
fi
if [[ "${#template_bloat_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "optional harness appendix split failed: ${template_bloat_failures[*]}"
fi

test_start "internal workflow controller is decision-boundary oriented"
workflow_controller_ref="$FRAMEWORK_DIR/skills/assistant-workflow/references/workflow-controller.md"
controller_shape_failures=()
for term in \
    "## Controller Role and Non-Goals" \
    "## Invocation and Loading Rules" \
    "## Routing Defaults" \
    "## Move Forward, Step Back, or Replan" \
    "## Harness Boundary" \
    "## Subagent, Review, and QA Separation" \
    "## Validation Expectations" \
    "Organize decisions by boundary, not by phase name"; do
    if [[ ! -f "$workflow_controller_ref" ]] || ! grep -Fq "$term" "$workflow_controller_ref"; then
        controller_shape_failures+=("workflow-controller.md: $term")
    fi
done
if [[ -f "$workflow_controller_ref" ]] && rg -n '^## (Phase:|Triage|Discover|Decompose|Plan|Design|Build|Review|Document)\b' "$workflow_controller_ref" >/tmp/p0p4-workflow-controller-phase-fragmentation.out; then
    controller_shape_failures+=("phase-name fragmentation; see /tmp/p0p4-workflow-controller-phase-fragmentation.out")
fi
if [[ "${#controller_shape_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow controller should be organized by decision boundary: ${controller_shape_failures[*]}"
fi

test_start "assistant-workflow decision-boundary split stays under final load thresholds"
workflow_skill="$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md"
workflow_contract_index="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/index.yaml"
workflow_phases="$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"
boundary_split_failures=()
skill_words="$(wc -w < "$workflow_skill")"
contract_index_words="$(wc -w < "$workflow_contract_index")"
entry_words=$(( skill_words + contract_index_words ))
phase_words="$(wc -w < "$workflow_phases")"
root_phase_words=$(( skill_words + phase_words ))
if (( entry_words > 2200 )); then
    boundary_split_failures+=("SKILL.md+contracts/index.yaml entry word count $entry_words exceeds 2200")
fi
if (( phase_words > 3400 )); then
    boundary_split_failures+=("phases.md word count $phase_words exceeds 3400")
fi
if (( root_phase_words > 6043 )); then
    boundary_split_failures+=("root+phase word count $root_phase_words exceeds 6043")
fi
for ref in \
    references/build-worker-protocol.md \
    references/review-qa-router.md \
    references/harness-runtime-artifacts.md \
    references/completion-controller.md; do
    if grep -Fq "$ref" "$workflow_skill"; then
        boundary_split_failures+=("SKILL.md always-loads $ref")
    fi
done
for file_and_term in \
    "$workflow_phases::Load \`references/build-worker-protocol.md\` for source-changing Build work" \
    "$workflow_phases::Load \`references/review-qa-router.md\`" \
    "$workflow_phases::Load \`references/completion-controller.md\`" \
    "$workflow_phases::\`harness_capable=true\`"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! grep -Fq "$term" "$file"; then
        boundary_split_failures+=("${file#$FRAMEWORK_DIR/}: missing conditional loader term: $term")
    fi
done
if [[ "${#boundary_split_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-workflow boundary split threshold guard failed: ${boundary_split_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
