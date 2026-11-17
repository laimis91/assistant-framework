if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

require_terms() {
    local label="$1"
    local file="$2"
    shift 2

    local missing=()
    local term
    for term in "$@"; do
        if ! grep -Fq -- "$term" "$file"; then
            missing+=("${file#$FRAMEWORK_DIR/}: $term")
        fi
    done

    if [[ "${#missing[@]}" -eq 0 ]]; then
        pass
    else
        fail "$label missing terms: ${missing[*]}"
    fi
}

require_normalized_terms() {
    local label="$1"
    local file="$2"
    shift 2

    local normalized_content
    normalized_content="$(tr '\n' ' ' <"$file" | sed 's/[[:space:]][[:space:]]*/ /g')"

    local missing=()
    local term
    for term in "$@"; do
        if [[ "$normalized_content" != *"$term"* ]]; then
            missing+=("${file#$FRAMEWORK_DIR/}: $term")
        fi
    done

    if [[ "${#missing[@]}" -eq 0 ]]; then
        pass
    else
        fail "$label missing terms: ${missing[*]}"
    fi
}

workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"
workflow_controller_ref="$workflow_dir/references/workflow-controller.md"
harness_ref="$workflow_dir/references/harness-controller.md"
harness_runtime_ref="$workflow_dir/references/harness-runtime-artifacts.md"
plan_appendix="$workflow_dir/references/plan-harness-appendix.md"
task_journal_appendix="$workflow_dir/references/task-journal-harness-appendix.md"

test_start "workflow defaults harness_capable false unless explicitly scoped"
require_terms "workflow input contract" "$workflow_dir/contracts/input.yaml" \
    "- name: harness_capable" \
    "default: false" \
    "For execution_intent == prepare_only, always false" \
    "accepted approved_feature_preparation_harness_obligation" \
    "explicitly requested harness work" \
    "long-running" \
    "trace/replay-ready multi-slice" \
    "high-risk harness" \
    "domain-scored" \
    "UI/visual/product/UX/docs/DX-facing" \
    "Do not infer true from size=medium+" \
    "delegation alone" \
    "ordinary medium+ workflow tasks default to false" \
    "source-changing workflow tasks"

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

test_start "workflow controller preserves ordinary defaults and harness boundary"
require_terms "workflow controller defaults" "$workflow_controller_ref" \
    'ordinary medium+ source-changing work defaults to' \
    '`controller_intensity=standard`, `harness_capable=false`, and' \
    '`qa_evaluation_mode=not_required`' \
    "Do not infer \`strict\`, \`harness_capable=true\`, or required QA from" \
    "size=medium+ or delegation alone" \
    'During `prepare_only`, always treat `harness_capable` as false' \
    'For `implement_only`, an accepted' \
    '`approved_feature_preparation_harness_obligation` is explicit harness scope' \
    'Treat `qa_evaluation_mode=not_required` unless'
require_terms "workflow controller harness boundary" "$workflow_controller_ref" \
    '`references/harness-controller.md` is loaded only after' \
    '`harness_capable=true` is established' \
    "Do not load \`references/harness-controller.md\` for ordinary medium work" \
    "source-changing work alone" \
    "delegation alone" \
    "When harness routing applies, \`references/harness-controller.md\` owns Done" \
    "Contract, Harness Recipe, and the harness entry gate." \
    '`references/harness-runtime-artifacts.md` owns Harness Run State, Trace'
require_terms "harness runtime reference" "$harness_runtime_ref" \
    "## Harness Run State" \
    "## Trace Ledger" \
    "## Replay Packet" \
    "## Artifact Reference Ledger" \
    "## Pivot/Restart Controller" \
    "Missing run-state/trace/replay evidence"
require_normalized_terms "workflow controller review QA separation" "$workflow_controller_ref" \
    "Code Reviewer and QA Evaluator responsibilities stay separate" \
    "Code Reviewer reviews code quality, defects, security, architecture, and test" \
    "QA Evaluator runs only when \`qa_evaluation_mode=required\`"
require_normalized_terms "workflow controller review QA separation" "$workflow_controller_ref" \
    "does not satisfy required QA Evaluator evidence"

p0p4_finish_suite "${BASH_SOURCE[0]}"
