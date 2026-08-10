if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

handoff_context_field_required() {
    local file="$1"
    local handoff="$2"
    local field="$3"
    ruby -ryaml -e '
        handoff = YAML.load_file(ARGV.fetch(0)).fetch("handoffs").find { |entry| entry["name"] == ARGV.fetch(1) }
        context = handoff && handoff.fetch("context_fields").find { |entry| entry["name"] == ARGV.fetch(2) }
        exit context && context["required"] == true ? 0 : 1
    ' "$file" "$handoff" "$field"
}

test_start "workflow handoffs define worker status protocol statuses and packet rules"
handoffs_file="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml"
missing_worker_status_terms=()
for status in \
    DONE \
    DONE_WITH_CONCERNS \
    NEEDS_CONTEXT \
    BLOCKED \
    DEVIATED \
    FAILED_VERIFICATION; do
    if ! protocol_status_present "$handoffs_file" "$status"; then
        missing_worker_status_terms+=("status:$status")
    fi
done
for term in \
    "worker_status_protocol:" \
    "CodeMapper, Explorer, Architect, CodeWriter, and BuilderTester returns include a compact status packet" \
    "status is required on CodeMapper, Explorer, Architect, CodeWriter, and BuilderTester returns." \
    "evidence is required for CodeMapper, Explorer, Architect, and CodeWriter returns with DONE, DONE_WITH_CONCERNS, DEVIATED, or FAILED_VERIFICATION." \
    "verification.evidence is required for BuilderTester returns." \
    "deviation_details is required for Architect and CodeWriter returns with DEVIATED." \
    "CodeMapper and Explorer status values are limited to DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT, and BLOCKED." \
    "Architect and CodeWriter status values also include DEVIATED." \
    "BuilderTester status values also include DEVIATED and FAILED_VERIFICATION." \
    "changed_files and files_changed are required with at least one item for CodeWriter returns with DONE, DONE_WITH_CONCERNS, or DEVIATED; they may be omitted or empty for NEEDS_CONTEXT/BLOCKED returns before file changes occur." \
    "verification is required for BuilderTester returns; if status is NEEDS_CONTEXT or BLOCKED before verification runs, return result not_run with concise blocker evidence."; do
    if ! grep -Fq -- "$term" "$handoffs_file"; then
        missing_worker_status_terms+=("$term")
    fi
done
if [[ "${#missing_worker_status_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow handoffs missing worker status protocol terms: ${missing_worker_status_terms[*]}"
fi

test_start "workflow handoffs define typed artifact references for worker packets"
workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"
output_contract="$workflow_dir/contracts/output.yaml"
plan_template="$workflow_dir/references/plan-template.md"
plan_harness_appendix="$workflow_dir/references/plan-harness-appendix.md"
task_journal_template="$workflow_dir/references/task-journal-template.md"
task_journal_harness_appendix="$workflow_dir/references/task-journal-harness-appendix.md"
phases_ref="$workflow_dir/references/phases.md"
build_worker_ref="$workflow_dir/references/build-worker-protocol.md"
harness_ref="$workflow_dir/references/harness-controller.md"
harness_runtime_ref="$workflow_dir/references/harness-runtime-artifacts.md"
missing_typed_artifact_terms=()
for term in \
    "artifact_reference_protocol:" \
    "required_fields: [artifact_id, artifact_type, producer, consumer, location_ref, schema_or_contract, validation_status, summary]" \
    "artifact_types: [done_contract, harness_recipe, harness_run_state, trace_ledger, replay_packet, pivot_restart_decision, changed_files, verification_evidence, plan_deviation, task_packet, context_map, architecture_decision_pack, test_result, review_result, qa_evaluation_result]" \
    "location_ref is the typed location/ref pointer" \
    "Producer responsibility: create or update the artifact" \
    "Consumer responsibility: validate schema_or_contract and validation_status before relying on location_ref" \
    "CodeWriter and BuilderTester task packets receive artifact_refs for the Architecture Decision Pack, Done Contract, Harness Recipe, Harness Run State, Trace Ledger, Replay Packet, Pivot/Restart Decision, changed files, verification evidence, and plan deviation refs when applicable." \
    "CodeWriter returns produced artifact_refs for changed files and plan deviation refs when applicable." \
    "BuilderTester returns validated artifact_refs for verification evidence and runtime-artifact validation." \
    "- name: artifact_refs" \
    "schema_or_contract" \
    "validation_status"; do
    if ! grep -Fq -- "$term" "$handoffs_file"; then
        missing_typed_artifact_terms+=("handoffs.yaml: $term")
    fi
done
for term in \
    "- name: artifact_reference_ledger" \
    "artifact_id" \
    "artifact_type" \
    "producer" \
    "consumer" \
    "location_ref" \
    "schema_or_contract" \
    "validation_status" \
    "ledger covers Done Contract, Harness Recipe, Harness Run State, Trace Ledger, Replay Packet, Pivot/Restart Decision, changed files, verification evidence, and plan deviation refs when applicable." \
    "enum_values: [done_contract, harness_recipe, harness_run_state, trace_ledger, replay_packet, pivot_restart_decision, changed_files, verification_evidence, plan_deviation, task_packet, context_map, architecture_decision_pack, test_result, review_result, qa_evaluation_result]" \
    "- name: pivot_restart_decision"; do
    if ! grep -Fq -- "$term" "$output_contract"; then
        missing_typed_artifact_terms+=("output.yaml: $term")
    fi
done
canonical_artifact_types="$(sed -n 's/^  artifact_types: //p' "$handoffs_file" | head -n 1)"
concrete_artifact_enum_count=0
for artifact_contract_file in "$handoffs_file" "$output_contract"; do
    while IFS= read -r concrete_artifact_enum; do
        concrete_artifact_enum_count=$((concrete_artifact_enum_count + 1))
        if [[ "${concrete_artifact_enum#*enum_values: }" != "$canonical_artifact_types" ]]; then
            missing_typed_artifact_terms+=("$artifact_contract_file: concrete artifact_type enum differs from artifact_reference_protocol")
        fi
    done < <(grep -F "enum_values: [done_contract" "$artifact_contract_file")
done
if [[ "$concrete_artifact_enum_count" -ne 6 ]]; then
    missing_typed_artifact_terms+=("expected five handoff and one output concrete artifact_type enums; found $concrete_artifact_enum_count")
fi
for term in \
    "## Harness Appendix Routing" \
    "references/plan-harness-appendix.md" \
    "artifact_reference_ledger_ref"; do
    if ! grep -Fq -- "$term" "$plan_template"; then
        missing_typed_artifact_terms+=("plan-template.md: $term")
    fi
done
for term in \
    "## Artifact Reference Ledger" \
    "Typed artifact refs:" \
    "Artifact ID | Artifact Type | Producer | Consumer | Location Ref | Schema or Contract | Validation Status | Summary"; do
    if [[ ! -f "$plan_harness_appendix" ]] || ! grep -Fq -- "$term" "$plan_harness_appendix"; then
        missing_typed_artifact_terms+=("plan-harness-appendix.md: $term")
    fi
done
for term in \
    "## Harness Appendix Routing" \
    "references/task-journal-harness-appendix.md"; do
    if ! grep -Fq -- "$term" "$task_journal_template"; then
        missing_typed_artifact_terms+=("task-journal-template.md: $term")
    fi
done
for term in \
    "## Artifact Reference Ledger" \
    "Producer roles update Artifact Reference Ledger entries" \
    'Consumer roles validate `schema_or_contract` and update `validation_status`'; do
    if [[ ! -f "$task_journal_harness_appendix" ]] || ! grep -Fq -- "$term" "$task_journal_harness_appendix" "$task_journal_template"; then
        missing_typed_artifact_terms+=("task-journal-harness-appendix.md/task-journal-template.md: $term")
    fi
done
if ! grep -Fq -- "Artifact Reference Ledger refs before task packets" "$phases_ref"; then
    missing_typed_artifact_terms+=("phases.md: Artifact Reference Ledger refs before task packets")
fi
for term in \
    'typed `artifact_refs`' \
    "changed_files, verification_evidence, pivot_restart_decision, and plan_deviation refs"; do
    if ! p0p4_contains_text "$build_worker_ref" "$term"; then
        missing_typed_artifact_terms+=("build-worker-protocol.md: $term")
    fi
done
for term in \
    "## Artifact Reference Ledger" \
    "Producer responsibility: create or update the artifact" \
    'Consumer responsibility: validate `schema_or_contract` and' \
    "Done Contract, Harness Recipe, Harness Run State, Trace"; do
    if ! p0p4_contains_text "$harness_runtime_ref" "$term"; then
        missing_typed_artifact_terms+=("harness-runtime-artifacts.md: $term")
    fi
done
if ! grep -Fq -- "references/harness-runtime-artifacts.md" "$harness_ref"; then
    missing_typed_artifact_terms+=("harness-controller.md: references/harness-runtime-artifacts.md")
fi
if [[ "${#missing_typed_artifact_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow typed artifact reference terms missing: ${missing_typed_artifact_terms[*]}"
fi

test_start "CodeMapper and Explorer return schemas require status evidence"
missing_discovery_schema_terms=()
for handoff in orchestrator_to_code_mapper orchestrator_to_explorer; do
    for field in status evidence; do
        if ! handoff_return_field_required "$handoffs_file" "$handoff" "$field"; then
            missing_discovery_schema_terms+=("$handoff: $field required")
        fi
    done
done
for enum in \
    "enum_values: [DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT, BLOCKED]"; do
    if ! grep -Fq -- "$enum" "$handoffs_file"; then
        missing_discovery_schema_terms+=("CodeMapper/Explorer status enum values")
    fi
done
if [[ "${#missing_discovery_schema_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "CodeMapper/Explorer return schemas missing status/evidence requirements: ${missing_discovery_schema_terms[*]}"
fi

test_start "Architect decompose and plan return schemas require status evidence deviation support"
missing_architect_schema_terms=()
for handoff in orchestrator_to_architect_decompose orchestrator_to_architect; do
    for field in status evidence; do
        if ! handoff_return_field_required "$handoffs_file" "$handoff" "$field"; then
            missing_architect_schema_terms+=("$handoff: $field required")
        fi
    done
    if ! handoff_return_field_present "$handoffs_file" "$handoff" "deviation_details"; then
        missing_architect_schema_terms+=("$handoff: deviation_details present")
    fi
    if ! handoff_return_field_has_condition "$handoffs_file" "$handoff" "deviation_details" "status is DEVIATED"; then
        missing_architect_schema_terms+=("$handoff: deviation_details condition status is DEVIATED")
    fi
done
if ! grep -Fq -- "enum_values: [DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT, BLOCKED, DEVIATED]" "$handoffs_file"; then
    missing_architect_schema_terms+=("Architect status enum values include DEVIATED")
fi
if [[ "${#missing_architect_schema_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "Architect DECOMPOSE/PLAN return schemas missing status/evidence/deviation support: ${missing_architect_schema_terms[*]}"
fi

test_start "Code Writer status packet schema and prompts require status changed_files evidence"
missing_code_writer_status_terms=()
if ! handoff_return_field_required "$handoffs_file" "orchestrator_to_code_writer" "status"; then
    missing_code_writer_status_terms+=("handoff return status required")
fi
for field in changed_files evidence files_changed; do
    if handoff_return_field_has_direct_line "$handoffs_file" "orchestrator_to_code_writer" "$field" "required: true"; then
        missing_code_writer_status_terms+=("handoff return $field must be conditional, not unconditionally required")
    fi
    for term in \
        "required: false" \
        "condition: \"required with min_items: 1 when status in [DONE, DONE_WITH_CONCERNS, DEVIATED]; optional and may be empty or omitted when status in [NEEDS_CONTEXT, BLOCKED]\"" \
        "min_items: 0"; do
        if ! handoff_return_field_has_direct_line "$handoffs_file" "orchestrator_to_code_writer" "$field" "$term"; then
            missing_code_writer_status_terms+=("handoff return $field: $term")
        fi
    done
done
for field in changed_files files_changed; do
    for term in \
        "Do not invent" \
        "NEEDS_CONTEXT or BLOCKED"; do
        if ! handoff_return_field_has_line "$handoffs_file" "orchestrator_to_code_writer" "$field" "$term"; then
            missing_code_writer_status_terms+=("handoff return $field description: $term")
        fi
    done
done
if ! grep -Fq -- "enum_values: [DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT, BLOCKED, DEVIATED]" "$handoffs_file"; then
    missing_code_writer_status_terms+=("CodeWriter status enum values")
fi
for term in \
    "changed_files and files_changed are required with at least one item for CodeWriter returns with DONE, DONE_WITH_CONCERNS, or DEVIATED" \
    "For DONE, DONE_WITH_CONCERNS, or DEVIATED, it must also return changed_files, evidence, files_changed, and typed artifact_refs when the task packet carried artifact_refs or harness_capable == true" \
    "for NEEDS_CONTEXT/BLOCKED, require open_questions and do not require fabricated changed-file or artifact-ref entries"; do
    if ! grep -Fq -- "$term" "$handoffs_file"; then
        missing_code_writer_status_terms+=("$term")
    fi
done
for file in \
    agents/codex/code-writer.toml \
    agents/claude/code-writer.md; do
    for term in \
        '`status`: one of `DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, `BLOCKED`, or `DEVIATED`' \
        '`changed_files`: files created, modified, or deleted with brief descriptions' \
        '`evidence`: concrete implementation evidence, usually file paths plus behavior changed' \
        "## Status meanings" \
        '`DONE`: implementation complete with no known concerns' \
        '`DONE_WITH_CONCERNS`: implementation is usable but follow-up risk remains' \
        '`NEEDS_CONTEXT`: missing requirements or required RED evidence need orchestrator clarification' \
        '`BLOCKED`: environment, dependency, permission, or tool issue prevents implementation' \
        '`DEVIATED`: implementation departed from the approved plan or requested scope'; do
        if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/$file"; then
            missing_code_writer_status_terms+=("$file: $term")
        fi
    done
done
if [[ "${#missing_code_writer_status_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "Code Writer status packet schema/prompts missing terms: ${missing_code_writer_status_terms[*]}"
fi

test_start "Builder Tester status packet schema and prompts require status verification"
missing_builder_status_terms=()
for field in status verification; do
    if ! handoff_return_field_required "$handoffs_file" "orchestrator_to_builder_tester" "$field"; then
        missing_builder_status_terms+=("handoff return $field required")
    fi
done
if ! grep -Fq -- "enum_values: [DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT, BLOCKED, DEVIATED, FAILED_VERIFICATION]" "$handoffs_file"; then
    missing_builder_status_terms+=("BuilderTester status enum values")
fi
if ! handoff_return_field_has_line "$handoffs_file" "orchestrator_to_builder_tester" "build_result" "enum_values: [passed, failed, not_run]"; then
    missing_builder_status_terms+=("build_result enum supports not_run")
fi
if ! handoff_return_field_has_line "$handoffs_file" "orchestrator_to_builder_tester" "build_result" "Use not_run only when status is NEEDS_CONTEXT or BLOCKED before verification can run"; then
    missing_builder_status_terms+=("build_result not_run is limited to NEEDS_CONTEXT/BLOCKED")
fi
if ! handoff_return_object_field_has_line "$handoffs_file" "orchestrator_to_builder_tester" "verification" "commands" "min_items: 0"; then
    missing_builder_status_terms+=("verification.commands may be empty")
fi
if ! handoff_return_object_field_has_line "$handoffs_file" "orchestrator_to_builder_tester" "verification" "commands" "empty only when verification.result is not_run for NEEDS_CONTEXT or BLOCKED"; then
    missing_builder_status_terms+=("verification.commands empty only for NEEDS_CONTEXT/BLOCKED not_run")
fi
if ! handoff_return_object_field_has_line "$handoffs_file" "orchestrator_to_builder_tester" "verification" "result" "enum_values: [passed, failed, not_run]"; then
    missing_builder_status_terms+=("verification.result enum supports not_run")
fi
for file in \
    agents/codex/builder-tester.toml \
    agents/claude/builder-tester.md; do
    for term in \
        '**Status**: `DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, `BLOCKED`, `DEVIATED`, or `FAILED_VERIFICATION`' \
        '**Verification**: commands/checks run plus concise success signals or failure messages' \
        '`FAILED_VERIFICATION`: build, tests, or required checks ran and failed'; do
        if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/$file"; then
            missing_builder_status_terms+=("$file: $term")
        fi
    done
done
if [[ "${#missing_builder_status_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "Builder/Tester status packet schema/prompts missing terms: ${missing_builder_status_terms[*]}"
fi

test_start "assistant-review solely owns Reviewer handoff status and evidence"
missing_reviewer_status_terms=()
workflow_handoffs="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml"
if grep -Fq -- '- name: orchestrator_to_reviewer' "$workflow_handoffs" \
    || grep -Fq -- '- name: orchestrator_to_qa_evaluator' "$workflow_handoffs"; then
    missing_reviewer_status_terms+=("assistant-workflow must not duplicate Reviewer or QAEvaluator handoffs")
fi
for file_and_handoff in \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml:orchestrator_to_reviewer"; do
    file="${file_and_handoff%%:*}"
    handoff="${file_and_handoff##*:}"
    for field in status findings evidence verdict; do
        if ! handoff_return_field_required "$file" "$handoff" "$field"; then
            missing_reviewer_status_terms+=("$file: $field required")
        fi
    done
    if ! grep -Fq -- "status, findings, evidence, and verdict are never optional" "$file"; then
        missing_reviewer_status_terms+=("$file: missing non-optional status/findings/evidence/verdict wording")
    fi
done
for term in \
    "Reviewer returns include a compact status packet while preserving the findings/rubric schema." \
    "findings, summary, and verdict remain required and are not replaced by status." \
    "evidence is required to support the verdict and any findings."; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml"; then
        missing_reviewer_status_terms+=("assistant-review handoff: $term")
    fi
done
if [[ "${#missing_reviewer_status_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "Reviewer handoffs missing status/evidence or findings/verdict preservation terms: ${missing_reviewer_status_terms[*]}"
fi

test_start "CodeMapper receives architecture mode and returns bounded mapping evidence with prompt parity"
code_mapper_pressure_contract_valid() {
    local file="$1"
    ruby -ryaml -e '
        expected = %w[control_and_early_exit ownership_and_disposal resource_envelope extension_registration representative_path]
        handoff = YAML.load_file(ARGV.fetch(0)).fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_code_mapper" }
        evidence = handoff.fetch("return_fields").find { |field| field["name"] == "architecture_mapping_evidence" }
        pressure = evidence.fetch("object_fields").find { |field| field["name"] == "design_pressure_checks" }
        concern = pressure.fetch("object_fields").find { |field| field["name"] == "concern" }
        valid = evidence["required"] == "conditional" && evidence["condition"] == "architecture_design_mode in [lightweight, required, review_intensive]" &&
          pressure["type"] == "object[]" && pressure["required"] == true && pressure["min_items"] == 5 && pressure["max_items"] == 5 &&
          pressure.fetch("validation").include?("exactly one") && concern["enum_values"] == expected
        exit valid ? 0 : 1
    ' "$file"
}

mutate_code_mapper_pressure_enum() {
    local source="$1"
    local destination="$2"
    local mutation="$3"
    ruby -ryaml -e '
        document = YAML.load_file(ARGV.fetch(0))
        handoff = document.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_code_mapper" }
        evidence = handoff.fetch("return_fields").find { |field| field["name"] == "architecture_mapping_evidence" }
        pressure = evidence.fetch("object_fields").find { |field| field["name"] == "design_pressure_checks" }
        concern = pressure.fetch("object_fields").find { |field| field["name"] == "concern" }
        case ARGV.fetch(2)
        when "delete" then concern["enum_values"].shift
        when "add" then concern["enum_values"] << "unexpected_concern"
        when "duplicate" then concern["enum_values"] << concern.fetch("enum_values").first
        else raise "unknown mutation"
        end
        File.write(ARGV.fetch(1), YAML.dump(document))
    ' "$source" "$destination" "$mutation"
}

mapper_contract_failures=()
mapper_handoff="orchestrator_to_code_mapper"
for field in architecture_design_mode architecture_design_trigger_reasons; do
    if ! handoff_context_field_required "$handoffs_file" "$mapper_handoff" "$field"; then
        mapper_contract_failures+=("context $field required")
    fi
done
if ! code_mapper_pressure_contract_valid "$handoffs_file"; then
    mapper_contract_failures+=("architecture_mapping_evidence parsed pressure schema requires exact ordered five-concern enum and min/max items")
else
    mapper_mutation_dir="$(mktemp -d "${TMPDIR:-/tmp}/code-mapper-pressure.XXXXXX")"
    p0p4_register_cleanup "$mapper_mutation_dir"
    for mutation in delete add duplicate; do
        mutated_mapper_handoff="$mapper_mutation_dir/$mutation.yaml"
        mutate_code_mapper_pressure_enum "$handoffs_file" "$mutated_mapper_handoff" "$mutation"
        if code_mapper_pressure_contract_valid "$mutated_mapper_handoff"; then
            mapper_contract_failures+=("$mutation concern enum mutation accepted")
        fi
    done
fi
for prompt in agents/codex/code-mapper.toml agents/claude/code-mapper.md; do
    for term in architecture_design_mode architecture_design_trigger_reasons architecture_mapping_evidence 'maps evidence, never designs'; do
        if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/$prompt"; then
            mapper_contract_failures+=("$prompt: $term")
        fi
    done
done
if [[ ${#mapper_contract_failures[@]} -eq 0 ]]; then
    pass
else
    fail "CodeMapper architecture mapping contract/prompt gaps: ${mapper_contract_failures[*]}"
fi

mapper_not_applicable_omits_evidence() {
    local response="$1"
    jq -e 'has("architecture_mapping_evidence") | not' <<<"$response" >/dev/null
}

test_start "not-applicable CodeMapper eval forbids every architecture mapping evidence representation"
mapper_eval_failures=()
mapper_eval="$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json"
if ! jq -e '
    .cases[] | select(.id == "code-mapper-not-applicable-omits-pack-evidence") |
    (.machine_expectations.required_substrings | all(. != "architecture_mapping_evidence" and (. | contains("architecture_mapping_evidence") | not))) and
    (.machine_expectations.forbidden_substrings | index("architecture_mapping_evidence") != null)
' "$mapper_eval" >/dev/null; then
    mapper_eval_failures+=("not-applicable fixture requires no evidence literal and forbids bare evidence token")
fi
if ! mapper_not_applicable_omits_evidence '{"context_map_markdown":"map"}'; then
    mapper_eval_failures+=("absent evidence mutation rejected")
fi
for response in \
    '{"architecture_mapping_evidence":null}' \
    '{"architecture_mapping_evidence":[]}' \
    '{"architecture_mapping_evidence":{"evidence_refs":["source"]}}'; do
    if mapper_not_applicable_omits_evidence "$response"; then
        mapper_eval_failures+=("present evidence mutation accepted: $response")
    fi
done
if [[ ${#mapper_eval_failures[@]} -eq 0 ]]; then
    pass
else
    fail "not-applicable CodeMapper eval omission guards: ${mapper_eval_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
