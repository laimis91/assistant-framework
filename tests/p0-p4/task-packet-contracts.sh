if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "workflow plan template defines executable task packet fields"
missing_packet_terms=()
for term in \
    "## Executable Task Packet" \
    "### Task [ID]: [short name]" \
    "- Behavior / acceptance criteria:" \
    "- Files:" \
    "- TDD / RED step:" \
    "- Implementation notes / constraints:" \
    "- Verification:" \
    "- Deviation / rollback rule:" \
    "- Worker status / evidence:" \
    "## Task packets"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/plan-template.md"; then
        missing_packet_terms+=("$term")
    fi
done
if [[ "${#missing_packet_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "plan-template.md missing executable task packet terms: ${missing_packet_terms[*]}"
fi

test_start "workflow phase gates enforce executable task packet planning checks"
missing_phase_gate_terms=()
for term in \
    "- id: P9" \
    "For medium+ tasks: implementation work is represented as executable task packets using plan-template.md" \
    "- id: P10" \
    "verification command and expected success signal" \
    "- id: P11" \
    "deviation/rollback rule" \
    "- id: B12" \
    "every component's verification criteria from DECOMPOSE phase are independently checked, passing"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"; then
        missing_phase_gate_terms+=("$term")
    fi
done
if [[ "${#missing_phase_gate_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "phase-gates.yaml missing executable task packet gates: ${missing_phase_gate_terms[*]}"
fi

test_start "workflow phases enforce medium component verification loop"
missing_component_phase_terms=()
for term in \
    "**For medium+ tasks with components:** execute one component at a time" \
    "Load the approved task packet for the component, including files, criteria, verification command, expected success signal, and deviation/rollback rule" \
    "Confirm prior component status is \`VERIFIED\` before advancing" \
    "Check each verification criterion from the component manifest independently" \
    "Record verification evidence in the task journal component verification ledger" \
    "Run a small self-check/local sanity check" \
    "Mark the component \`VERIFIED\` only after all criteria pass and evidence is recorded" \
    "Only proceed to the next component after the current one is fully verified"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"; then
        missing_component_phase_terms+=("$term")
    fi
done
if [[ "${#missing_component_phase_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "phases.md missing per-component verification loop terms: ${missing_component_phase_terms[*]}"
fi

test_start "workflow task journal template includes component verification ledger fields"
missing_component_ledger_terms=()
for term in \
    "## Component Verification Ledger" \
    "[required for medium+ tasks; update after each component before starting the next]" \
    "| Component | Task Packet | RED Status | Implementation Status | Verification Command/Result | Criteria Checked | Self-Check Result | Final Status |" \
    "[X/Y passed]" \
    "[pass/fail + note]" \
    "[VERIFIED/BLOCKED]" \
    "do not start the next component until the current one is \`VERIFIED\`"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md"; then
        missing_component_ledger_terms+=("$term")
    fi
done
if [[ "${#missing_component_ledger_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "task-journal-template.md missing component verification ledger terms: ${missing_component_ledger_terms[*]}"
fi

test_start "workflow output contract requires component verification summary for medium tasks"
missing_component_output_terms=()
for term in \
    "- name: component_verification_summary" \
    "condition: \"size in [medium, large, mega]\"" \
    "task_packet_id" \
    "red_status" \
    "verification_result" \
    "criteria_checked" \
    "self_check_result" \
    "final_status" \
    "enum_values: [VERIFIED]" \
    "Every component final status must be VERIFIED before"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"; then
        missing_component_output_terms+=("$term")
    fi
done
if ! awk '
    /- name: component_verification_summary/ { in_summary = 1; next }
    in_summary && /^  - name: / { exit }
    in_summary && /required: true/ { found = 1; exit }
    END { exit found ? 0 : 1 }
' "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"; then
    missing_component_output_terms+=("component_verification_summary required: true")
fi
if [[ "${#missing_component_output_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "output.yaml missing medium component_verification_summary contract terms: ${missing_component_output_terms[*]}"
fi

test_start "workflow phase gates require recorded component evidence before advancing"
missing_component_gate_terms=()
for term in \
    "- id: B12" \
    "independently checked, passing, and recorded with command/result evidence in the task journal component verification ledger" \
    "record command/result evidence in the task journal ledger" \
    "- id: B13" \
    "each component has a final status of VERIFIED, including self-check result, before the next component started" \
    "components must be verified sequentially with evidence before advancing"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"; then
        missing_component_gate_terms+=("$term")
    fi
done
if [[ "${#missing_component_gate_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "phase-gates.yaml missing recorded/sequential component verification gate terms: ${missing_component_gate_terms[*]}"
fi

test_start "workflow handoffs pass current task packets to CodeWriter and BuilderTester"
handoffs_file="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml"
task_packet_handoffs="$(count_occurrences "name: current_task_packet" "$handoffs_file")"
missing_task_packet_fields=()
for field in \
    task_id \
    name \
    behavior_acceptance_criteria \
    files_to_test \
    verification_command \
    expected_success_signal; do
    if ! grep -Fq -- "name: $field" "$handoffs_file"; then
        missing_task_packet_fields+=("$field")
    fi
done
if [[ "$task_packet_handoffs" -ge 2 && "${#missing_task_packet_fields[@]}" -eq 0 ]]; then
    pass
else
    fail "handoffs.yaml must define CodeWriter and BuilderTester current_task_packet fields; count=$task_packet_handoffs missing=${missing_task_packet_fields[*]}"
fi

test_start "workflow architect plan handoff requires task packet execution fields"
missing_required_fields=()
for field in \
    files_to_create \
    files_to_modify \
    files_to_test \
    acceptance_criteria \
    verification_command \
    expected_success_signal \
    deviation_rollback_rule; do
    if ! field_required_true_after_anchor "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml" "- name: implementation_steps" "$field"; then
        missing_required_fields+=("$field")
    fi
done
if [[ "${#missing_required_fields[@]}" -eq 0 ]]; then
    pass
else
    fail "architect implementation_steps must require executable task packet fields: ${missing_required_fields[*]}"
fi

test_start "workflow architect plan keeps legacy generic files optional only"
missing_architect_legacy_files_terms=()
if ! handoff_return_field_has_line "$handoffs_file" "orchestrator_to_architect" "implementation_steps" "Legacy readers may also inspect files when present"; then
    missing_architect_legacy_files_terms+=("implementation_steps description mentions legacy readers only")
fi
if ! field_required_true_after_anchor "$handoffs_file" "- name: implementation_steps" "files"; then
    :
else
    missing_architect_legacy_files_terms+=("implementation_steps.files must not be required")
fi
for term in \
    "          - name: files" \
    "            required: false" \
    "Legacy-readable summary of file paths this step touches; do not use as the executable task packet contract"; do
    if ! awk -v term="$term" '
        $0 == "  - name: orchestrator_to_architect" { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && $0 == "      - name: implementation_steps" { in_steps = 1; next }
        in_steps && index($0, term) { found = 1; exit }
        in_steps && $0 == "      - name: files_to_create" { exit }
        END { exit found ? 0 : 1 }
    ' "$handoffs_file"; then
        missing_architect_legacy_files_terms+=("$term")
    fi
done
if [[ "${#missing_architect_legacy_files_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "architect implementation_steps must use files_to_* as required fields and keep legacy files optional: ${missing_architect_legacy_files_terms[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
