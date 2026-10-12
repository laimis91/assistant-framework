if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/feature-preparation-response-fixtures.sh"
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "worker-status filtered workflow eval keeps matched review authority coherent"
worker_status_filter_root="$(mktemp -d "${TMPDIR:-/tmp}/worker-status-eval-filter.XXXXXX")"
p0p4_register_cleanup "$worker_status_filter_root"
mkdir -p "$worker_status_filter_root/assistant-workflow/evals"
cp "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md" "$worker_status_filter_root/assistant-workflow/SKILL.md"
p0p4_filter_workflow_eval_cases \
    "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json" \
    "$worker_status_filter_root/assistant-workflow/evals/cases.json" \
    "standard-pack-review-result-retains-checklist"
if "$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --validate-fixture --skill "$worker_status_filter_root/assistant-workflow" >/dev/null \
    && jq -e '
        .canonical_review_batch_expectations as $authority
        | ($authority.case_template_refs | keys) == ["standard-pack-review-result-retains-checklist"]
        and ($authority.case_requirements | keys) == ["standard-pack-review-result-retains-checklist"]
        and ($authority.templates | keys) == ["workflow_small_current"]
        and ($authority.scope_manifests | keys) == ["workflow_small_current"]
        and (.canonical_review_snapshot_expectations | keys) == ["standard-pack-review-result-retains-checklist"]
        and (.canonical_review_closure_expectations | keys) == []
      ' "$worker_status_filter_root/assistant-workflow/evals/cases.json" >/dev/null; then
    pass
else
    fail "worker-status filtered workflow eval left a dangling canonical review authority"
fi

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
if [[ "$concrete_artifact_enum_count" -eq 0 ]]; then
    missing_typed_artifact_terms+=("no concrete ArtifactRef enums were checked")
fi
if ! ruby -ryaml -e '
    handoffs = YAML.load_file(ARGV.fetch(0))
    output = YAML.load_file(ARGV.fetch(1))
    types = handoffs.fetch("artifact_reference_protocol").fetch("artifact_types")
    exit 1 unless %w[verification_decision evidence_assessment].all? { |name| types.include?(name) }
    field = ->(fields, name) { fields.find { |f| f["name"] == name } || raise("missing #{name}") }
    owners = handoffs.fetch("handoffs").to_h { |h| [h.fetch("name"), h] }
    [["orchestrator_to_architect", "return_fields", "implementation_steps"],
     ["orchestrator_to_code_writer", "context_fields", "current_task_packet"],
     ["orchestrator_to_builder_tester", "context_fields", "current_task_packet"]].each do |name, side, parent|
        packet = field.call(owners.fetch(name).fetch(side), parent)
        refs = field.call(packet.fetch("object_fields"), "artifact_refs")
        exit 1 unless refs["type"] == "object[]" && field.call(refs.fetch("object_fields"), "artifact_type")["enum_values"] == types
    end
    %w[orchestrator_to_code_writer orchestrator_to_builder_tester].each do |name|
        refs = field.call(owners.fetch(name).fetch("return_fields"), "artifact_refs")
        exit 1 unless refs["type"] == "object[]" && field.call(refs.fetch("object_fields"), "artifact_type")["enum_values"] == types
    end
    ledger = field.call(output.fetch("artifacts"), "artifact_reference_ledger")
    exit 1 unless field.call(ledger.fetch("object_fields"), "artifact_type")["enum_values"] == types
' "$handoffs_file" "$output_contract"; then
    missing_typed_artifact_terms+=("typed producer/consumer ArtifactRefs or verification artifact registration differs from the canonical protocol")
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

test_start "Architect test_plan schema names the selected automated-test condition"
if ruby -ryaml -e '
  handoffs = YAML.load_file(ARGV.fetch(0)).fetch("handoffs")
  architect = handoffs.find { |h| h["name"] == "orchestrator_to_architect" }
  plan = architect.fetch("return_fields").find { |f| f["name"] == "test_plan" }
  exit 1 unless plan && plan["required"] == "conditional" &&
    plan["condition"] == "at least one slice\u0027s canonical verification_decision selects method == automated_test" &&
    plan.fetch("description").include?("required only for slices with selected automated_test CheckSpecs")
' "$handoffs_file"; then
    pass
else
    fail "Architect test_plan schema does not bind applicability to the selected automated-test decision"
fi

test_start "Decompose slices preserve task TDD choice and derive local applicability from selected checks"
if ruby -ryaml -e '
  handoffs = YAML.load_file(ARGV.fetch(0)).fetch("handoffs")
  decompose = handoffs.find { |h| h["name"] == "orchestrator_to_architect_decompose" }
  field = ->(fields, name) { fields.find { |f| f["name"] == name } || raise("missing #{name}") }
  context_decision = field.call(decompose.fetch("context_fields"), "verification_decision")
  context_tdd_mode = field.call(decompose.fetch("context_fields"), "tdd_mode")
  return_fields = decompose.fetch("return_fields")
  manifest = field.call(return_fields, "slice_manifest")
  slice_fields = manifest.fetch("object_fields")
  slice_decision = field.call(slice_fields, "verification_decision")
  selected_ids = field.call(slice_fields, "selected_check_ids")
  binding_refs = field.call(slice_fields, "binding_obligation_refs")
  slice_tdd = field.call(slice_fields, "tdd_applies")
  binding_names = binding_refs.fetch("object_fields").map { |item| item.fetch("name") }
  valid_schema = context_decision["required"] == true && context_tdd_mode["required"] == true &&
    context_tdd_mode.fetch("validation").include?("Equals verification_decision.tdd_choice.mode") &&
    manifest["required"] == true && manifest["type"] == "object[]" &&
    slice_decision["required"] == true && selected_ids["required"] == true && binding_refs["required"] == true && slice_tdd["required"] == true &&
    slice_decision.fetch("validation").include?("equals context_fields.verification_decision") &&
    selected_ids.fetch("validation").include?("An ordered unique subset") &&
    binding_refs.fetch("validation").include?("Each {kind,value,source_ref} exactly equals a canonical policy tuple") &&
    %w[kind value source_ref].all? { |name| binding_names.count(name) == 1 } &&
    slice_tdd.fetch("validation").include?("True exactly when selected_check_ids intersect verification_decision.tdd_choice.applicable_check_ids")
  inline_fields = {"verification_decision" => "object", "selected_check_ids" => "string[]", "binding_obligation_refs" => "object[]", "tdd_applies" => "boolean"}
  valid_schema &&= %w[orchestrator_to_code_writer orchestrator_to_builder_tester].all? do |name|
    context = handoffs.find { |h| h["name"] == name }.fetch("context_fields")
    packet = field.call(context, "current_task_packet")
    mode = field.call(context, "tdd_mode")
    inline = inline_fields.all? do |key, type|
      carried = field.call(context, key)
      carried["type"] == type && carried["required"] == "conditional" &&
        carried["condition"] == "current_task_packet is absent" &&
        carried.fetch("validation").include?("when current_task_packet is present")
    end
    local_tdd = field.call(context, "tdd_applies").fetch("validation")
    tuples = field.call(context, "binding_obligation_refs").fetch("object_fields")
    packet["required"] == "conditional" && inline &&
      local_tdd.include?("True exactly when selected_check_ids intersect verification_decision.tdd_choice.applicable_check_ids") &&
      tuples.map { |f| f.fetch("name") } == %w[kind value source_ref] &&
      tuples.all? { |f| f["required"] == true } &&
      mode.fetch("validation").include?("when current_task_packet is present") &&
      mode.fetch("validation").include?("otherwise equals verification_decision.tdd_choice.mode")
  end
  root = File.expand_path("../../..", File.dirname(ARGV.fetch(0)))
  valid_schema &&= %w[agents/codex/code-writer.toml agents/claude/code-writer.md agents/codex/builder-tester.toml agents/claude/builder-tester.md].all? do |path|
    File.read(File.join(root, path)).include?("from current_task_packet when present, otherwise")
  end
  exit(valid_schema ? 0 : 1)
' "$handoffs_file"; then
    pass
else
    fail "Architect Decompose schema does not require the canonical verification/TDD projection in each slice"
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
        '`validation_results`: in `bounded_executor`' \
        'required for `DONE`, `DONE_WITH_CONCERNS`, or `DEVIATED`, and whenever verification was attempted; omit only when blocked before any check.' \
        '`binding_obligation_refs` tuples `{kind,value,source_ref}`' \
        'For a started command-based CheckSpec, include `executed_command`' \
        'its sole `check_id` and exact CheckSpec `argv` and `cwd`' \
        'In `separated_workers`, Builder/Tester owns these verification result rows.' \
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

test_start "CodeWriter verification results are bounded-lane conditional and preserve exact identity fields"
if ruby -ryaml -e '
    handoffs = YAML.load_file(ARGV.fetch(0)).fetch("handoffs").to_h { |item| [item.fetch("name"), item] }
    find_field = ->(fields, name) { fields.find { |item| item["name"] == name } || raise("missing #{name}") }
    writer_results = find_field.call(handoffs.fetch("orchestrator_to_code_writer").fetch("return_fields"), "validation_results")
    tester_results = find_field.call(handoffs.fetch("orchestrator_to_builder_tester").fetch("return_fields"), "validation_results")
    expected_condition = "build_execution_lane == bounded_executor and (status in [DONE, DONE_WITH_CONCERNS, DEVIATED] or verification was attempted)"
    raise "CodeWriter result condition or cardinality changed" unless writer_results["required"] == "conditional" && writer_results["condition"] == expected_condition && writer_results["min_items"] == 1
    predicate = ->(lane, status, attempted) do
      condition = writer_results.fetch("condition")
      lane == condition.split(" and ", 2).first.sub("build_execution_lane == ", "") &&
        (condition[/status in \[([^\]]+)\]/, 1].split(", ").include?(status) || attempted)
    end
    raise "bounded DONE should require verification" unless predicate.call("bounded_executor", "DONE", false)
    raise "separated implementation must not own verification" if predicate.call("separated_workers", "DONE", true)
    raise "pre-check blockers must allow omitted results" if predicate.call("bounded_executor", "BLOCKED", false)
    %w[NEEDS_CONTEXT BLOCKED].each do |status|
      raise "attempted checks must survive #{status}" unless predicate.call("bounded_executor", status, true)
    end
    raise "pre-check omission must be explicit" unless writer_results.fetch("description").include?("Omit only when blocked before any check")
    raise "BuilderTester result carrier must remain required" unless tester_results["required"] == true && tester_results["min_items"] == 1
    [writer_results, tester_results].each do |results|
      fields = results.fetch("object_fields")
      ids = find_field.call(fields, "selected_check_ids")
      tuples = find_field.call(fields, "binding_obligation_refs")
      raise "selected IDs must be a required string array" unless ids["type"] == "string[]" && ids["required"] == true
      raise "binding tuples must be a required object array" unless tuples["type"] == "object[]" && tuples["required"] == true
      tuple_fields = tuples.fetch("object_fields")
      raise "binding tuple fields changed" unless tuple_fields.map { |item| item.fetch("name") }.sort == %w[kind source_ref value]
      raise "binding tuple fields must retain required typed values" unless tuple_fields.all? { |item| item["required"] == true } && tuple_fields.to_h { |item| [item.fetch("name"), item.fetch("type")] } == {"kind"=>"enum", "value"=>"string", "source_ref"=>"string"}
    end
  ' "$handoffs_file"; then
    pass
else
    fail "CodeWriter/BuilderTester validation result lane or identity schema is inconsistent"
fi

test_start "Builder Tester status packet keeps selected-check and no-build outcomes distinct"
missing_builder_status_terms=()
for field in status verification validation_results build_result test_summary; do
    if ! handoff_return_field_required "$handoffs_file" "orchestrator_to_builder_tester" "$field"; then
        missing_builder_status_terms+=("handoff return $field required")
    fi
done
if ! handoff_return_field_has_line "$handoffs_file" "orchestrator_to_builder_tester" "validation_results" "min_items: 1"; then
    missing_builder_status_terms+=("BuilderTester validation_results must remain non-empty")
fi
if ! handoff_return_field_has_line "$handoffs_file" "orchestrator_to_builder_tester" "validation_results" "enum_values: [passed, failed, partial, unavailable, skipped, not_applicable, blocked]"; then
    missing_builder_status_terms+=("BuilderTester per-check result enum includes blocked")
fi
if ! handoff_return_field_has_direct_line "$handoffs_file" "orchestrator_to_builder_tester" "validation_results" "Blocked is a distinct explicit gap and never closes a due check or establishes sufficiency."; then
    missing_builder_status_terms+=("blocked per-check results remain gaps")
fi
if ! grep -Fq -- "enum_values: [DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT, BLOCKED, DEVIATED, FAILED_VERIFICATION]" "$handoffs_file"; then
    missing_builder_status_terms+=("BuilderTester status enum values")
fi
if ! handoff_return_field_has_line "$handoffs_file" "orchestrator_to_builder_tester" "build_result" "enum_values: [passed, failed, not_run, not_applicable]"; then
    missing_builder_status_terms+=("build_result enum includes not_applicable")
fi
for term in \
    "Derive build applicability from the concrete due selected CheckSpecs and resolved binding constraints" \
    "do not infer it from file type, command presence, method, or technique alone" \
    "Use not_run only for a required build that could not start, with status NEEDS_CONTEXT or BLOCKED, or with FAILED_VERIFICATION because a different executed required check failed. Retain the unstarted build's blocked row and the other check's failed row; never label the unstarted build failed." \
    "Use not_applicable only when no due selected or binding build check applies and no build was executed"; do
    if ! handoff_return_field_has_direct_line "$handoffs_file" "orchestrator_to_builder_tester" "build_result" "$term"; then
        missing_builder_status_terms+=("build_result missing scoped applicability rule: $term")
    fi
done
if ! handoff_return_object_field_has_line "$handoffs_file" "orchestrator_to_builder_tester" "verification" "commands" "min_items: 0"; then
    missing_builder_status_terms+=("verification.commands may be empty")
fi
if ! handoff_return_object_field_has_line "$handoffs_file" "orchestrator_to_builder_tester" "verification" "commands" "may be empty for selected checks whose concrete procedure has no command" \
    || ! handoff_return_object_field_has_line "$handoffs_file" "orchestrator_to_builder_tester" "verification" "commands" "Empty commands do not waive a selected or binding check"; then
    missing_builder_status_terms+=("verification.commands distinguish no-command checks without waiving selected/binding checks")
fi
if ! handoff_return_object_field_has_line "$handoffs_file" "orchestrator_to_builder_tester" "verification" "result" "enum_values: [passed, failed, partial, unavailable, not_run, not_applicable]"; then
    missing_builder_status_terms+=("verification.result preserves complete, incomplete, and no-check outcomes")
fi
if ! handoff_return_object_field_has_line "$handoffs_file" "orchestrator_to_builder_tester" "verification" "result" "passed requires current observed or admissibly reused passing results for every due selected and binding check" \
    || ! handoff_return_object_field_has_line "$handoffs_file" "orchestrator_to_builder_tester" "verification" "result" "not_run means a due required check could not run and requires NEEDS_CONTEXT or BLOCKED"; then
    missing_builder_status_terms+=("verification.result preserves due-check pass and blocker conditions")
fi
if ! handoff_return_object_field_has_line "$handoffs_file" "orchestrator_to_builder_tester" "verification" "evidence" "When commands is empty for a no-command check, identify the concrete procedure performed and its observed result"; then
    missing_builder_status_terms+=("no-command verification requires observed procedure/result evidence")
fi
for term in \
    "Actual test counts for selected or binding automated-test checks" \
    "Zero counts mean no tests were executed; they do not mean required tests passed" \
    "Applicability comes from due selected CheckSpecs and resolved binding constraints"; do
    if ! handoff_return_field_has_direct_line "$handoffs_file" "orchestrator_to_builder_tester" "test_summary" "$term"; then
        missing_builder_status_terms+=("test_summary missing scoped count rule: $term")
    fi
done
for file in \
    agents/codex/builder-tester.toml \
    agents/claude/builder-tester.md; do
    for term in \
        '**Status**: `DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, `BLOCKED`, `DEVIATED`, or `FAILED_VERIFICATION`' \
        '**Verification**: commands/checks run plus concise success signals or failure messages' \
        '`validation_results`: non-empty per-check rows for every due selected check and applicable binding obligation, even when blocked; each row includes `command_or_check`, `result`, `evidence`, exact `selected_check_ids`, and exact `binding_obligation_refs` tuples `{kind, value, source_ref}`.' \
        'Use `result` values `passed`, `failed`, `partial`, `unavailable`, `skipped`, `not_applicable`, or `blocked`; blocked is a distinct gap and never closes a due check or establishes sufficiency.' \
        'For a started command-based selected CheckSpec, include `executed_command` with `check_id` as the sole selected ID and exact `argv` and `cwd`; omit it when the command did not start.' \
        'Only when no command or no-command procedure has started, a due command check that cannot start leaves `verification.commands` empty and aggregate `verification.result` `not_run` with status `NEEDS_CONTEXT` or `BLOCKED`. Otherwise preserve every started command and actual per-check outcome, then derive aggregate/status from all due evidence using canonical precedence; `failed`/`FAILED_VERIFICATION` takes precedence. Always retain each `blocked` row with its check ID and blocker evidence.' \
        'When no check applies, return one `not_applicable` row with empty IDs and binding refs plus the exact rationale.' \
        'For a no-command check, evidence states the concrete procedure and observed result.' \
        '`FAILED_VERIFICATION`: an executed build, test, or other required check failed'; do
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
    "findings, summary, coverage_entries, and verdict remain required and are not replaced by status." \
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

test_start "CodeMapper receives architecture mode and returns cohesive semantic inspection evidence with prompt parity"
code_mapper_semantic_inspection_contract_valid() {
    local file="$1"
    ruby -ryaml -e '
        expected = %w[control_and_early_exit ownership_and_disposal resource_envelope extension_registration representative_path]
        handoff = YAML.load_file(ARGV.fetch(0)).fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_code_mapper" }
        evidence = handoff.fetch("return_fields").find { |field| field["name"] == "architecture_mapping_evidence" }
        pressure = evidence.fetch("object_fields").find { |field| field["name"] == "design_pressure_checks" }
        concern = pressure.fetch("object_fields").find { |field| field["name"] == "concern" }
        semantic = evidence.fetch("object_fields").find { |field| field["name"] == "semantic_type_inspection" }
        representative_paths = evidence.fetch("object_fields").find { |field| field["name"] == "representative_paths" }
        semantic_fields = semantic.fetch("object_fields").to_h { |field| [field["name"], field] }
        outcome = semantic_fields.fetch("outcome")
        candidates = semantic_fields.fetch("candidates")
        candidate_fields = candidates.fetch("object_fields").map { |field| field["name"] }
        representative_path_fields = representative_paths.fetch("object_fields").to_h { |field| [field["name"], field] }
        valid = evidence["required"] == "conditional" && evidence["condition"] == "architecture_design_mode in [lightweight, required, review_intensive]" &&
          pressure["type"] == "object[]" && pressure["required"] == true && pressure["min_items"] == 5 && pressure["max_items"] == 5 &&
          pressure.fetch("validation").include?("exactly one") && !pressure.fetch("validation").include?("semantic_type_candidates") && concern["enum_values"] == expected &&
          semantic["type"] == "object" && semantic["required"] == true &&
          outcome["enum_values"] == %w[candidates_found inspected_empty unresolved] &&
          semantic_fields.fetch("evidence_or_gap")["required"] == true && semantic_fields.fetch("source_refs")["min_items"] == 1 &&
          candidates["required"] == "conditional" && candidates["condition"] == "outcome == candidates_found" && candidates["min_items"] == 1 &&
          candidate_fields == %w[concept current_representation boundary finding_kind evidence_ref] &&
          representative_paths["type"] == "object[]" && representative_paths["required"] == true && representative_paths["min_items"] == 0 &&
          representative_paths.fetch("validation").include?("concern=representative_path") &&
          representative_paths.fetch("validation").include?("status=observed") &&
          representative_paths.fetch("validation").include?("not_applicable, unresolved") &&
          representative_path_fields.keys == %w[producer consumer failure_or_cancellation source_ref] &&
          representative_path_fields.values.all? { |field| field["type"] == "string" && field["required"] == true && field.fetch("validation").include?("Non-empty") } &&
          evidence.fetch("object_fields").none? { |field| field["name"] == "semantic_type_candidates" }
        exit valid ? 0 : 1
    ' "$file"
}

mutate_code_mapper_semantic_inspection() {
    local source="$1"
    local destination="$2"
    local mutation="$3"
    ruby -ryaml -e '
        document = YAML.load_file(ARGV.fetch(0))
        handoff = document.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_code_mapper" }
        evidence = handoff.fetch("return_fields").find { |field| field["name"] == "architecture_mapping_evidence" }
        pressure = evidence.fetch("object_fields").find { |field| field["name"] == "design_pressure_checks" }
        concern = pressure.fetch("object_fields").find { |field| field["name"] == "concern" }
        semantic = evidence.fetch("object_fields").find { |field| field["name"] == "semantic_type_inspection" }
        representative_paths = evidence.fetch("object_fields").find { |field| field["name"] == "representative_paths" }
        semantic_fields = semantic.fetch("object_fields").to_h { |field| [field["name"], field] }
        case ARGV.fetch(2)
        when "delete_pressure_concern" then concern["enum_values"].shift
        when "weaken_candidate_condition" then semantic_fields.fetch("candidates")["condition"] = "outcome == inspected_empty"
        when "restore_invalid_pressure_coupling" then pressure["validation"] += " Empty semantic_type_candidates require a matching pressure check."
        when "weaken_representative_path_requiredness" then representative_paths["validation"] = "Representative paths are optional."
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
if ! code_mapper_semantic_inspection_contract_valid "$handoffs_file"; then
    mapper_contract_failures+=("architecture_mapping_evidence requires independent pressure checks and typed semantic inspection outcomes")
else
    mapper_mutation_dir="$(mktemp -d "${TMPDIR:-/tmp}/code-mapper-semantic-inspection.XXXXXX")"
    p0p4_register_cleanup "$mapper_mutation_dir"
    for mutation in delete_pressure_concern weaken_candidate_condition restore_invalid_pressure_coupling weaken_representative_path_requiredness; do
        mutated_mapper_handoff="$mapper_mutation_dir/$mutation.yaml"
        mutate_code_mapper_semantic_inspection "$handoffs_file" "$mutated_mapper_handoff" "$mutation"
        if code_mapper_semantic_inspection_contract_valid "$mutated_mapper_handoff"; then
            mapper_contract_failures+=("$mutation semantic inspection mutation accepted")
        fi
    done
fi
for prompt in agents/codex/code-mapper.toml agents/claude/code-mapper.md; do
    for term in architecture_design_mode architecture_design_trigger_reasons architecture_mapping_evidence semantic_type_inspection candidates_found inspected_empty unresolved representative_paths 'maps evidence, never designs'; do
        if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/$prompt"; then
            mapper_contract_failures+=("$prompt: $term")
        fi
    done
done
if ! jq -e '
    . as $fixture |
    ($fixture.cases[] | select(.id == "code-mapper-applicable-architecture-evidence") |
      (.machine_expectations.required_substrings | index("semantic_type_inspection")) and
      (.machine_expectations.required_substrings | index("inspected_empty") | not) and
      (.machine_expectations.required_substrings | index("representative_paths")) and
      (.machine_expectations.required_substrings | index("representative_path status=observed requires at least one detailed producer-consumer path")) and
      (any(.machine_expectations.structured_json_assertions[]; .operator == "equals" and .path == ["architecture_mapping_evidence", "design_pressure_checks", 4, "concern"] and .expected == "representative_path")) and
      (any(.machine_expectations.structured_json_assertions[]; .operator == "equals" and .path == ["architecture_mapping_evidence", "design_pressure_checks", 4, "status"] and .expected == "observed")) and
      (any(.machine_expectations.structured_json_assertions[]; .operator == "array_items_nonempty_fields" and .path == ["architecture_mapping_evidence", "representative_paths"] and .fields == ["producer", "consumer", "failure_or_cancellation", "source_ref"])) and
      (.machine_expectations.forbidden_substrings | index("empty semantic_type_candidates require a design-pressure check"))) and
    (any(.cases[]; .id == "code-mapper-inspected-empty-requires-evidence" and
        (.machine_expectations.required_substrings | index("outcome=inspected_empty") | not) and
        (.machine_expectations.required_substrings | index("evidence_or_gap")) and
        (.machine_expectations.required_substrings | index("source_refs")) and
        any(.machine_expectations.structured_json_assertions[]; .operator == "equals" and .path == ["architecture_mapping_evidence", "semantic_type_inspection", "outcome"] and .expected == "inspected_empty")))
' "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json" >/dev/null; then
    mapper_contract_failures+=("CodeMapper applicable eval does not distinguish semantic inspection from design-pressure checks")
fi
if [[ ${#mapper_contract_failures[@]} -eq 0 ]]; then
    pass
else
    fail "CodeMapper architecture mapping contract/prompt gaps: ${mapper_contract_failures[*]}"
fi

run_code_mapper_outcome_eval() {
    local fixture="$1"
    local case_id="$2"
    local response="$3"
    local expected_status="$4"
    local eval_root
    local temporary_skill
    local responses_dir
    local runner_output

    eval_root="$(mktemp -d "${TMPDIR:-/tmp}/code-mapper-outcome-eval.XXXXXX")"
    p0p4_register_cleanup "$eval_root"
    temporary_skill="$eval_root/assistant-workflow"
    responses_dir="$eval_root/responses"
    mkdir -p "$temporary_skill/evals" "$responses_dir/assistant-workflow"
    cp "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md" "$temporary_skill/SKILL.md"
    p0p4_filter_workflow_eval_cases "$fixture" "$temporary_skill/evals/cases.json" "$case_id"
    printf '%s\n' "$response" >"$responses_dir/assistant-workflow/$case_id.txt"
    if ! runner_output="$("$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$responses_dir" --skill "$temporary_skill" 2>&1)"; then
        [[ "$expected_status" == "FAIL" ]] || return 1
    elif [[ "$expected_status" == "FAIL" ]]; then
        return 1
    fi
    grep -Fq $'\tassistant-workflow\t'"$case_id" <<<"$runner_output" \
        && grep -Fq "Summary: total=1 passed=$([[ "$expected_status" == "PASS" ]] && echo 1 || echo 0) failed=$([[ "$expected_status" == "PASS" ]] && echo 0 || echo 1)" <<<"$runner_output"
}

test_start "CodeMapper eval accepts every typed semantic inspection outcome and rejects empty evidence gaps"
mapper_outcome_eval_failures=()
mapper_applicable_eval="$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json"
mapper_common_response=$'architecture_mapping_evidence\ncontrol_and_early_exit\nownership_and_disposal\nresource_envelope\nextension_registration\nrepresentative_path\nsemantic_type_inspection\nrepresentative_paths\nrepresentative_path status=observed requires at least one detailed producer-consumer path\nmaps evidence, never designs'
mapper_common_structured="$(jq -n --arg summary "$mapper_common_response" '{summary: $summary, architecture_mapping_evidence: {design_pressure_checks: [{concern: "control_and_early_exit", status: "observed", evidence_or_gap: "consumer cancellation inspected", source_ref: "src/order.rb"}, {concern: "ownership_and_disposal", status: "observed", evidence_or_gap: "request ownership inspected", source_ref: "src/order.rb"}, {concern: "resource_envelope", status: "observed", evidence_or_gap: "bounded request inspected", source_ref: "src/order.rb"}, {concern: "extension_registration", status: "observed", evidence_or_gap: "registration seam inspected", source_ref: "src/order.rb"}, {concern: "representative_path", status: "observed", evidence_or_gap: "order producer reaches validator", source_ref: "src/order.rb"}], representative_paths: [{producer: "OrderRequest", consumer: "OrderValidator", failure_or_cancellation: "validation failure stops processing", source_ref: "src/order.rb"}]}}')"
for outcome in candidates_found inspected_empty unresolved; do
    case "$outcome" in
        candidates_found)
            response="$(jq '.architecture_mapping_evidence.semantic_type_inspection = {outcome: "candidates_found", evidence_or_gap: "OrderId crosses the request boundary", source_refs: ["src/order.rb"], candidates: [{concept: "OrderId", current_representation: "string", boundary: "domain_or_public_semantic_type", finding_kind: "semantic_type_candidate", evidence_ref: "src/order.rb"}]}' <<<"$mapper_common_structured")"
            ;;
        inspected_empty)
            response="$(jq '.architecture_mapping_evidence.semantic_type_inspection = {outcome: "inspected_empty", evidence_or_gap: "no domain concept crosses this boundary", source_refs: ["src/order.rb"]}' <<<"$mapper_common_structured")"
            ;;
        unresolved)
            response="$(jq '.architecture_mapping_evidence.semantic_type_inspection = {outcome: "unresolved", evidence_or_gap: "need owner clarification", source_refs: ["src/order.rb"]}' <<<"$mapper_common_structured")"
            ;;
    esac
    if ! jq -e --arg outcome "$outcome" '
        .architecture_mapping_evidence.semantic_type_inspection.outcome == $outcome and
        (.architecture_mapping_evidence.semantic_type_inspection.evidence_or_gap | type == "string" and length > 0) and
        (.architecture_mapping_evidence.semantic_type_inspection.source_refs | type == "array" and length > 0) and
        (if $outcome == "candidates_found" then (.architecture_mapping_evidence.semantic_type_inspection.candidates | type == "array" and length > 0) else true end)
    ' <<<"$response" >/dev/null; then
        mapper_outcome_eval_failures+=("$outcome fixture response does not bind the loop outcome to semantic_type_inspection")
    elif ! run_code_mapper_outcome_eval "$mapper_applicable_eval" "code-mapper-applicable-architecture-evidence" "$response" PASS; then
        mapper_outcome_eval_failures+=("actual eval runner rejects a valid typed semantic inspection outcome")
    fi
done
unsafe_empty_response=$'architecture_mapping_evidence\nsemantic_type_inspection\noutcome=inspected_empty\nsource_refs=[src/order.rb]\nrepresentative_paths=[src/order.rb]'
if ! run_code_mapper_outcome_eval "$mapper_applicable_eval" "code-mapper-inspected-empty-requires-evidence" "$unsafe_empty_response" FAIL; then
    mapper_outcome_eval_failures+=("actual eval runner accepts inspected_empty without evidence_or_gap")
fi
unsafe_observed_representative_response="$(jq '(.architecture_mapping_evidence.representative_paths) = []' <<<"$mapper_common_structured")"
if ! run_code_mapper_outcome_eval "$mapper_applicable_eval" "code-mapper-applicable-architecture-evidence" "$unsafe_observed_representative_response" FAIL; then
    mapper_outcome_eval_failures+=("actual eval runner accepts observed representative_path without a detailed path")
fi
if [[ ${#mapper_outcome_eval_failures[@]} -eq 0 ]]; then
    pass
else
    fail "CodeMapper typed semantic inspection eval gaps: ${mapper_outcome_eval_failures[*]}"
fi

test_start "CodeMapper structured JSON rejects empty semantic inspection evidence"
mapper_structured_json_failures=()
if ! jq -e '
    .cases[] | select(.id == "code-mapper-inspected-empty-requires-evidence") |
    .machine_expectations.structured_json_assertions as $assertions |
    ($assertions | type == "array") and
    (any($assertions[]; .operator == "equals" and .path == ["architecture_mapping_evidence", "semantic_type_inspection", "outcome"] and .expected == "inspected_empty")) and
    (any($assertions[]; .operator == "nonempty_string" and .path == ["architecture_mapping_evidence", "semantic_type_inspection", "evidence_or_gap"])) and
    (any($assertions[]; .operator == "nonempty_array" and .path == ["architecture_mapping_evidence", "semantic_type_inspection", "source_refs"])) and
    (.machine_expectations.required_substrings | index("outcome=inspected_empty") | not)
' "$mapper_applicable_eval" >/dev/null; then
    mapper_structured_json_failures+=("inspected-empty case lacks structured evidence assertions")
fi
mapper_structured_valid='{"architecture_mapping_evidence":{"semantic_type_inspection":{"outcome":"inspected_empty","evidence_or_gap":"no domain concept crosses this boundary","source_refs":["src/order.rb"]},"representative_paths":["src/order.rb"]}}'
if ! run_code_mapper_outcome_eval "$mapper_applicable_eval" "code-mapper-inspected-empty-requires-evidence" "$mapper_structured_valid" PASS; then
    mapper_structured_json_failures+=("actual runner rejects valid structured semantic inspection evidence")
fi
for mutation in \
    '(.architecture_mapping_evidence.semantic_type_inspection.outcome) = "unresolved"' \
    '(.architecture_mapping_evidence.semantic_type_inspection.evidence_or_gap) = ""' \
    '(.architecture_mapping_evidence.semantic_type_inspection.evidence_or_gap) = "   "' \
    '(.architecture_mapping_evidence.semantic_type_inspection.source_refs) = []'; do
    unsafe_mapper_response="$(jq "$mutation" <<<"$mapper_structured_valid")"
    if ! run_code_mapper_outcome_eval "$mapper_applicable_eval" "code-mapper-inspected-empty-requires-evidence" "$unsafe_mapper_response" FAIL; then
        mapper_structured_json_failures+=("actual runner accepts $mutation")
    fi
done
if [[ ${#mapper_structured_json_failures[@]} -eq 0 ]]; then
    pass
else
    fail "CodeMapper structured semantic inspection eval gaps: ${mapper_structured_json_failures[*]}"
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

test_start "CodeMapper structured eval requests raw JSON and covers every representative-path status"
mapper_path_branch_failures=()
if ! jq -e '
    . as $fixture |
    ($fixture.cases[] | select(.id == "code-mapper-applicable-architecture-evidence") |
      (.prompt | contains("Return the complete response as one valid JSON object")) and
      (.expected_behavior | index("For this observed representative path, records at least one detailed producer-consumer path with failure or cancellation and source evidence.")) and
      (.expected_behavior | all(contains("not_applicable or unresolved keeps the path array empty") | not)) and
      (.machine_expectations.structured_json_assertions | any(
        .operator == "array_field_values_exact" and
        .path == ["architecture_mapping_evidence", "design_pressure_checks"] and
        .field == "concern" and
        .expected_values == ["control_and_early_exit", "ownership_and_disposal", "resource_envelope", "extension_registration", "representative_path"]
      )) and
      (.machine_expectations.structured_json_assertions | any(
        .operator == "array_items_nonempty_fields" and
        .path == ["architecture_mapping_evidence", "design_pressure_checks"] and
        .fields == ["concern", "status", "evidence_or_gap", "source_ref"]
      ))) and
    (["not_applicable", "unresolved"] | all(. as $status |
      ($fixture.cases[] | select(.id == ("code-mapper-representative-path-" + ($status | gsub("_"; "-")))) |
        (.prompt | contains("Return the complete response as one valid JSON object")) and
        (.expected_behavior | any(contains("representative_path status=" + $status))) and
        (.machine_expectations.structured_json_assertions | any(
          .operator == "equals" and
          .path == ["architecture_mapping_evidence", "design_pressure_checks", 4, "status"] and
          .expected == $status
        )) and
        (.machine_expectations.structured_json_assertions | any(
          .operator == "empty_array" and
          .path == ["architecture_mapping_evidence", "representative_paths"]
        )) and
        (.machine_expectations.structured_json_assertions | any(
          .operator == "array_field_values_exact" and
          .path == ["architecture_mapping_evidence", "design_pressure_checks"] and
          .field == "concern" and
          .expected_values == ["control_and_early_exit", "ownership_and_disposal", "resource_envelope", "extension_registration", "representative_path"]
        )) and
        (.machine_expectations.structured_json_assertions | any(
          .operator == "array_items_nonempty_fields" and
          .path == ["architecture_mapping_evidence", "design_pressure_checks"] and
          .fields == ["concern", "status", "evidence_or_gap", "source_ref"]
        ))
      )
    ))
' "$mapper_eval" >/dev/null; then
    mapper_path_branch_failures+=("fixture does not request raw JSON and split observed/not-applicable/unresolved path branches")
fi
for status in not_applicable unresolved; do
    case_id="code-mapper-representative-path-${status//_/-}"
    required_summary="$(jq -r --arg id "$case_id" '.cases[] | select(.id == $id) | .machine_expectations.required_substrings[]' "$mapper_eval" | paste -sd ' ' -)"
    response="$(jq -n --arg summary "$required_summary" --arg status "$status" '{
      summary: $summary,
      architecture_mapping_evidence: {
        design_pressure_checks: [
          {concern: "control_and_early_exit", status: "observed", evidence_or_gap: "consumer cancellation inspected", source_ref: "src/order.rb"},
          {concern: "ownership_and_disposal", status: "observed", evidence_or_gap: "request ownership inspected", source_ref: "src/order.rb"},
          {concern: "resource_envelope", status: "observed", evidence_or_gap: "bounded request inspected", source_ref: "src/order.rb"},
          {concern: "extension_registration", status: "observed", evidence_or_gap: "registration seam inspected", source_ref: "src/order.rb"},
          {concern: "representative_path", status: $status, evidence_or_gap: "No executable path is available at this boundary.", source_ref: "src/order.rb"}
        ],
        representative_paths: [],
        semantic_type_inspection: {outcome: "inspected_empty", evidence_or_gap: "No semantic type candidate crosses this boundary.", source_refs: ["src/order.rb"]}
      }
    }')"
    if ! run_code_mapper_outcome_eval "$mapper_eval" "$case_id" "$response" PASS; then
        mapper_path_branch_failures+=("actual eval runner rejects representative_path status=$status with an empty path collection")
    fi
    for mutation in \
        '(.architecture_mapping_evidence.design_pressure_checks[0]) = {}' \
        '(.architecture_mapping_evidence.design_pressure_checks[4].source_ref) = ""' \
        '(.architecture_mapping_evidence.design_pressure_checks[3].concern) = "representative_path"'; do
        unsafe_response="$(jq "$mutation" <<<"$response")"
        if ! run_code_mapper_outcome_eval "$mapper_eval" "$case_id" "$unsafe_response" FAIL; then
            mapper_path_branch_failures+=("actual eval runner accepts $status mutation $mutation")
        fi
    done
done
if [[ ${#mapper_path_branch_failures[@]} -eq 0 ]]; then
    pass
else
    fail "CodeMapper representative-path eval branch gaps: ${mapper_path_branch_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
