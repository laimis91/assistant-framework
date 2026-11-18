if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"
harness_ref="$workflow_dir/references/harness-controller.md"
plan_appendix="$workflow_dir/references/plan-harness-appendix.md"
task_journal_appendix="$workflow_dir/references/task-journal-harness-appendix.md"

test_start "implement-only consumes the exact deferred preparation harness obligation"
if ruby -ryaml -e '
  input = YAML.load_file(ARGV.fetch(0)).fetch("fields").to_h { |field| [field.fetch("name"), field] }
  obligation = input.fetch("approved_feature_preparation_harness_obligation")
  harness = input.fetch("harness_capable")
  fields = obligation.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  valid = obligation.fetch("type") == "object" &&
    obligation.fetch("required") == "conditional" &&
    obligation.fetch("condition").include?("implement_only") &&
    fields.keys == %w[requested_scope evidence_basis execution_prerequisite source_feature_preparation_evidence_ref source_preparation_basis] &&
    fields.fetch("source_feature_preparation_evidence_ref").fetch("condition") == "feature_preparation_scope == existing_system" &&
    fields.fetch("source_preparation_basis").fetch("condition") == "feature_preparation_scope == not_applicable" &&
    fields.fetch("source_preparation_basis").fetch("enum_values") == ["not_applicable"] &&
    harness.fetch("validation").include?("accepted approved_feature_preparation_harness_obligation") &&
    harness.fetch("infer_from").include?("implement_only plus accepted approved_feature_preparation_harness_obligation -> true before Build")
  exit(valid ? 0 : 1)
' "$workflow_dir/contracts/input.yaml" \
    && [[ "$(rg -c -- '^- name: feature_preparation_harness_obligation$|^      - name: feature_preparation_harness_obligation$|^          - name: feature_preparation_harness_obligation$' "$workflow_dir/contracts/handoffs.yaml")" -eq 9 ]] \
    && grep -Fq -- '- feature_preparation_harness_obligation:' "$workflow_dir/references/sub-task-brief-template.md" \
    && grep -Fq -- '`approved_feature_preparation_harness_obligation`' "$workflow_dir/references/feature-preparation-evidence.md" \
    && grep -Fq -- '`harness_capable=true`' "$workflow_dir/references/feature-preparation-evidence.md"; then
    pass
else
    fail "deferred harness obligation is not typed and carried into implementation handoffs"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
