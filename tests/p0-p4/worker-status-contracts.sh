if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

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
    "CodeMapper, Explorer, Architect, CodeWriter, BuilderTester, and Reviewer returns include a compact status packet" \
    "status is required on CodeMapper, Explorer, Architect, CodeWriter, BuilderTester, and Reviewer returns." \
    "evidence is required for CodeMapper, Explorer, Architect, CodeWriter, and Reviewer returns with DONE, DONE_WITH_CONCERNS, DEVIATED, or FAILED_VERIFICATION." \
    "verification.evidence is required for BuilderTester returns." \
    "deviation_details is required for Architect and CodeWriter returns with DEVIATED." \
    "CodeMapper, Explorer, and Reviewer status values are limited to DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT, and BLOCKED." \
    "Architect and CodeWriter status values also include DEVIATED." \
    "BuilderTester status values also include DEVIATED and FAILED_VERIFICATION." \
    "changed_files and files_changed are required with at least one item for CodeWriter returns with DONE, DONE_WITH_CONCERNS, or DEVIATED; they may be omitted or empty for NEEDS_CONTEXT/BLOCKED returns before file changes occur." \
    "verification is required for BuilderTester returns; if status is NEEDS_CONTEXT or BLOCKED before verification runs, return result not_run with concise blocker evidence." \
    "findings is required for Reviewer returns."; do
    if ! grep -Fq -- "$term" "$handoffs_file"; then
        missing_worker_status_terms+=("$term")
    fi
done
if [[ "${#missing_worker_status_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow handoffs missing worker status protocol terms: ${missing_worker_status_terms[*]}"
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
    "For DONE, DONE_WITH_CONCERNS, or DEVIATED, it must also return changed_files, evidence, and files_changed with real implementation evidence" \
    "for NEEDS_CONTEXT/BLOCKED, require open_questions and do not require fabricated changed-file entries"; do
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

test_start "Reviewer handoffs preserve findings verdict and require status evidence"
missing_reviewer_status_terms=()
for file_and_handoff in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml:orchestrator_to_reviewer" \
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

p0p4_finish_suite "${BASH_SOURCE[0]}"
