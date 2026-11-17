if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

triage_file="$FRAMEWORK_DIR/skills/assistant-workflow/references/triage-rubric.md"

test_start "canonical instruction block delegates phase detail to native skill routing"
if grep -Fq 'When a skill'"'"'s description matches the request, read its `SKILL.md` and follow it through to its handoff' \
    "$FRAMEWORK_DIR/docs/instruction-block.md" \
    && grep -Fq "approve a plan before medium+ or elevated-risk development edits" \
    "$FRAMEWORK_DIR/docs/instruction-block.md" \
    && ! grep -Fq "The orchestrator owns framework state files" "$FRAMEWORK_DIR/docs/instruction-block.md" \
    && ! grep -Fq "use direct fallback only after" "$FRAMEWORK_DIR/docs/instruction-block.md" \
    && ! grep -Fq "TRIAGE -> DISCOVER -> DECOMPOSE when needed -> PLAN -> DESIGN when needed -> BUILD -> REVIEW -> DOCUMENT" \
    "$FRAMEWORK_DIR/docs/instruction-block.md"; then
    pass
else
    fail "canonical instruction block must stay lean and defer phase mechanics to the matched skill"
fi

test_start "review delegation dispatches from applicable instruction triggers"
review_trigger_failures=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/index.yaml::schema_version: \"11.0\"" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/review-qa-router.md::sole owner of Reviewer and QAEvaluator worker packet schemas" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/index.yaml::id: review-entry-fields" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml::reviewed_scope" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/index.yaml::subagent_trigger_scope" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/index.yaml::policy_blocking_source" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/index.yaml::qa_evaluation_mode" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/input.yaml::delegation_triggered" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/input.yaml::subagents_unavailable" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/input.yaml::Formal review always triggers independent isolation" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/input.yaml::subagent_trigger_scope" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml::subagent_trigger_scope" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml::without a separate permission question"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! p0p4_contains_text "$file" "$term"; then
        review_trigger_failures+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#review_trigger_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review trigger delegation contract missing: ${review_trigger_failures[*]}"
fi

test_start "agentic loop safety review requires low-confidence escalation evidence"
missing_loop_safety_terms=()
for file in \
    "$FRAMEWORK_DIR/skills/assistant-review/references/review-checklists.md" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml"; do
    if ! grep -Fq "low-confidence escalation" "$file" && ! grep -Fq "low_confidence_escalation" "$file"; then
        missing_loop_safety_terms+=("$file")
    fi
done
if ! grep -Fq 'Agentic Loop Safety Checklist' "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml" \
    || ! grep -Fq 'references/review-checklists.md' "$FRAMEWORK_DIR/skills/assistant-review/contracts/index.yaml"; then
    missing_loop_safety_terms+=("assistant-review root/index worker-bundle routing")
fi
if [[ "${#missing_loop_safety_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "agentic loop safety lacks low-confidence escalation in: ${missing_loop_safety_terms[*]}"
fi

test_start "canonical triage routing retains every required consumer field"
if ruby -ryaml -e '
  output = YAML.load_file(ARGV.fetch(0))
  triage = File.read(ARGV.fetch(1))
  result = output.fetch("artifacts").find { |artifact| artifact.fetch("name") == "triage_result" }
  section = triage[/^## Routing decisions\n(.*?)(?=^## |\z)/m, 1]
  required = result.fetch("object_fields").select { |field| field.fetch("required") == true }.map { |field| field.fetch("name") }
  exit(section && required.all? { |name| section.include?("`#{name}`") } ? 0 : 1)
' "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml" "$triage_file"; then
    pass
else
    fail "triage routing guidance omits a required canonical triage_result field"
fi

test_start "workflow records bounded reuse-search evidence for rule-like changes"
reuse_search_workflow_failures=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml::reuse_search" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml::business rules, validation, calculations/conversions, mappings, schema/config semantics, permissions, or protocol details" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml::before implementation" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/context-map-template.md::## Reuse Search" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/context-map-template.md::applicability_reason: [concrete reason]" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/plan-template.md::- Reuse search:" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/plan-template.md::decision_rationale"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! p0p4_contains_text "$file" "$term"; then
        reuse_search_workflow_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
if [[ "${#reuse_search_workflow_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow reuse-search evidence gate/template is incomplete: ${reuse_search_workflow_failures[*]}"
fi

test_start "internal workflow controller reference exists and is linked"
workflow_controller_ref="$FRAMEWORK_DIR/skills/assistant-workflow/references/workflow-controller.md"
controller_link_failures=()
if [[ ! -f "$workflow_controller_ref" ]]; then
    controller_link_failures+=("missing skills/assistant-workflow/references/workflow-controller.md")
fi
for file in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"; do
    if ! grep -Fq "references/workflow-controller.md" "$file"; then
        controller_link_failures+=("${file#$FRAMEWORK_DIR/}: missing references/workflow-controller.md")
    fi
done
public_controller_dirs=()
while IFS= read -r public_controller_dir; do
    public_controller_dirs+=("$public_controller_dir")
done < <(find "$FRAMEWORK_DIR/skills" -mindepth 1 -maxdepth 1 -type d -name '*workflow-controller*' -print)
if [[ "${#public_controller_dirs[@]}" -ne 0 ]]; then
    controller_link_failures+=("public workflow-controller skill dirs: ${public_controller_dirs[*]}")
fi
for ref in \
    build-worker-protocol \
    review-qa-router \
    harness-runtime-artifacts \
    completion-controller; do
    if [[ ! -f "$FRAMEWORK_DIR/skills/assistant-workflow/references/$ref.md" ]]; then
        controller_link_failures+=("missing skills/assistant-workflow/references/$ref.md")
    fi
done
public_boundary_dirs=()
while IFS= read -r public_boundary_dir; do
    public_boundary_dirs+=("$public_boundary_dir")
done < <(find "$FRAMEWORK_DIR/skills" -mindepth 1 -maxdepth 1 -type d \( \
    -name '*build-worker-protocol*' -o \
    -name '*review-qa-router*' -o \
    -name '*harness-runtime-artifacts*' -o \
    -name '*completion-controller*' \
\) -print)
if [[ "${#public_boundary_dirs[@]}" -ne 0 ]]; then
    controller_link_failures+=("public workflow boundary skill dirs: ${public_boundary_dirs[*]}")
fi
phases_ref="$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"
for copied_matrix_phrase in \
    "light for small low-risk work" \
    "strict only for high/critical" \
    "Treat \`harness_capable\` as false unless" \
    "Treat harness_capable as false unless" \
    "Treat \`qa_evaluation_mode=not_required\` unless" \
    "Treat qa_evaluation_mode=not_required unless"; do
    if grep -Fq "$copied_matrix_phrase" "$phases_ref"; then
        controller_link_failures+=("phases.md copied controller routing matrix phrase: $copied_matrix_phrase")
    fi
done
for term in \
    "Use \`references/workflow-controller.md\` for routing." \
    "Only \`harness_capable=true\` loads \`references/harness-controller.md\` and \`references/plan-harness-appendix.md\`" \
    "retain accepted Done Contract, Harness Recipe, runtime state/trace/replay, and Artifact Reference Ledger before Build" \
    "Load \`references/build-worker-protocol.md\` for canonical packet or worker Build execution" \
    "Load \`references/review-qa-router.md\`" \
    "Load \`references/completion-controller.md\`"; do
    if ! p0p4_contains_text "$phases_ref" "$term"; then
        controller_link_failures+=("phases.md missing controller handoff term: $term")
    fi
done
if ! grep -Fq "references/harness-runtime-artifacts.md" "$phases_ref" \
    || ! grep -Fq "references/harness-runtime-artifacts.md" "$FRAMEWORK_DIR/skills/assistant-workflow/references/harness-controller.md"; then
    controller_link_failures+=("harness runtime artifact reference is not linked from phases.md and harness-controller.md")
fi
skill_entrypoint="$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md"
for term in \
    "references/workflow-controller.md" \
    "when risk, approval, state, delegation, harness, or QA routing needs resolution"; do
    if ! p0p4_contains_text "$skill_entrypoint" "$term"; then
        controller_link_failures+=("SKILL.md missing lean controller term: $term")
    fi
done
for entrypoint_bloat_phrase in \
    "## Internal Workflow Controller" \
    "Load \`references/workflow-controller.md\` for shared routing/default decisions, then load \`references/phases.md\`" \
    "Shared routing/default decisions come from the internal \`references/workflow-controller.md\` reference"; do
    if grep -Fq "$entrypoint_bloat_phrase" "$skill_entrypoint"; then
        controller_link_failures+=("SKILL.md reintroduced controller bloat phrase: $entrypoint_bloat_phrase")
    fi
done
if [[ "${#controller_link_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow controller reference/linkage guard failed: ${controller_link_failures[*]}"
fi

test_start "workflow candidate-search phase 1 contracts are present and company-safe"
missing_candidate_terms=()
for term in \
    "search_mode" \
    "none, lightweight, candidate_search" \
    "candidate_search triggers"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/input.yaml"; then
        missing_candidate_terms+=("input.yaml: $term")
    fi
done
for term in \
    "candidate_search_result" \
    "goal_tree" \
    "candidate_archive" \
    "selected_candidate" \
    "search_exit_summary" \
    "empty_result_handling" \
    "plan_deviation"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"; then
        missing_candidate_terms+=("output.yaml: $term")
    fi
done
for term in \
    "CS1" \
    "candidate archive exists at {agent_state_dir}/candidate-search.md when local state artifacts are configured and policy-allowed" \
    "CS5" \
    "candidate_search_result includes search_exit_summary" \
    "Post-approval candidate pivots are recorded as plan deviations"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"; then
        missing_candidate_terms+=("phase-gates.yaml: $term")
    fi
done
for term in \
    "references/candidate-search.md" \
    "Candidate Search"; do
    if ! grep -Fqi "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md"; then
        missing_candidate_terms+=("SKILL.md: $term")
    fi
    if [[ ! -f "$FRAMEWORK_DIR/skills/assistant-workflow/references/candidate-search.md" ]] || ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/candidate-search.md"; then
        missing_candidate_terms+=("candidate-search.md: $term")
    fi
done
for term in \
    "Search mode:" \
    "Candidate search summary:" \
    "Candidate archive:"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/plan-template.md"; then
        missing_candidate_terms+=("plan-template.md: $term")
    fi
done
for term in \
    "docs/specs/candidate-search.md"; do
    if [[ ! -f "$FRAMEWORK_DIR/$term" ]]; then
        missing_candidate_terms+=("candidate-search specification missing: $term")
    fi
done
if [[ "${#missing_candidate_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow candidate-search phase 1 contract missing terms: ${missing_candidate_terms[*]}"
fi

test_start "workflow state artifacts are orchestrator-owned and ignored"
missing_state_terms=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md::framework-owned ignored artifact" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md::may be updated by the orchestrator" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md::Framework-owned ignored state never authorizes project mutations" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md::When state files are unavailable or policy disallows them, retain equivalent carried state"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        missing_state_terms+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if ! ruby -ryaml -e '
  gates = YAML.load_file(ARGV.fetch(0)).fetch("gates")
  d5 = gates.find { |gate| gate["phase"] == "DISCOVER" }
    .fetch("exit_assertions")
    .find { |assertion| assertion["id"] == "D5" }
  check = d5.fetch("check")
  valid = check.include?("context map exists at {agent_state_dir}/context-map.md") &&
    check.include?("local state artifacts are configured and policy-allowed") &&
    check.include?("For prepare_only") &&
    check.include?("readiness evidence/context") &&
    check.include?("without a task or plan packet") &&
    check.include?("for execution_intent != prepare_only") &&
    check.include?("state files are unavailable") &&
    check.include?("task/plan packet")
  exit(valid ? 0 : 1)
' "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"; then
    missing_state_terms+=("phase-gates.yaml: D5 must branch local-state context-map, prepare-only readiness, and execution unavailable-state handling")
fi
for term in \
    "context_map_markdown" \
    "orchestrator to persist to {agent_state_dir}/context-map.md when local state artifacts are configured and policy-allowed"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml"; then
        missing_state_terms+=("handoffs.yaml: $term")
    fi
done
if ! grep -Fq ".codex/" "$FRAMEWORK_DIR/.gitignore"; then
    missing_state_terms+=(".gitignore: .codex/")
fi
if [[ "${#missing_state_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow state artifact ownership missing terms: ${missing_state_terms[*]}"
fi

test_start "workflow preparation routing keeps QA, harness, delegated state, and typed future obligations distinct"
preparation_routing_failures=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/workflow-controller.md::For \`prepare_only\`, force \`harness_capable=false\`" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/workflow-controller.md::workflow_state_mode=journal" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/workflow-controller.md::feature_preparation_result.future_qa_acceptance_obligation" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/workflow-controller.md::feature_preparation_result.future_harness_obligation" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/triage-rubric.md::future_harness_obligation" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md::future_harness_obligation" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md::Future harness obligation"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! p0p4_contains_text "$file" "$term"; then
        preparation_routing_failures+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#preparation_routing_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow preparation routing distinction is incomplete: ${preparation_routing_failures[*]}"
fi

test_start "workflow entry and preparation admissibility retain explicit QA, harness, lane, state, and manual-verification boundaries"
if ruby -ryaml -e '
  index = YAML.load_file(ARGV.fetch(0))
  gates = YAML.load_file(ARGV.fetch(1))
  entry = index.fetch("load_sets").fetch("entry").fetch("selectors").find { |selector| selector["id"] == "workflow-entry-fields" }.fetch("names")
  triage = gates.fetch("gates").find { |gate| gate["phase"] == "TRIAGE" }
  admissibility = triage.fetch("exit_assertions").find { |assertion| assertion["id"] == "T_PREPARATION_ADMISSIBILITY" }
  check = admissibility.fetch("check")
  input = YAML.load_file(ARGV.fetch(2))
  manual = input.fetch("fields").find { |field| field.fetch("name") == "manual_verification_mode" }
  harness = input.fetch("fields").find { |field| field.fetch("name") == "harness_capable" }
  valid = %w[acceptance_criteria qa_evaluation_mode harness_capable build_execution_lane workflow_state_mode manual_verification_mode].all? { |name| entry.include?(name) } &&
    manual.fetch("infer_from").include?("destructive or migration-related") &&
    harness.fetch("validation").include?("prepare_only, always false") &&
    harness.fetch("validation").include?("future_harness_obligation") &&
    check.include?("qa_evaluation_mode=not_required") &&
    check.include?("build_execution_lane=none") &&
    check.include?("harness_capable=false") &&
    check.include?("typed future obligations") &&
    check.include?("workflow_state_mode") &&
    check.include?("progressive uncertainty") &&
    check.include?("risk-selected strict preparation") &&
    check.include?("explicit persisted-state request")
  exit(valid ? 0 : 1)
' "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/index.yaml" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/input.yaml"; then
    pass
else
    fail "workflow entry loading or preparation admissibility does not preserve explicit QA, harness, lane, state, and manual-verification boundaries"
fi

test_start "workflow task classification maps compact high-signal aliases to exact categories and gate packs"
if ruby -ryaml -e '
  input = YAML.load_file(ARGV.fetch(0))
  task_type = input.fetch("fields").find { |field| field.fetch("name") == "task_type" }
  triage = File.read(ARGV.fetch(1))
  mapping = {
    "fix/bug/broken" => ["bugfix", "Bugfix"],
    "rewrite/port" => ["rewrite", "Refactor / Migration / Rewrite"],
    "migrate/migration" => ["migration", "Refactor / Migration / Rewrite"],
    "refactor/clean/reorganize" => ["refactor", "Refactor / Migration / Rewrite"],
    "config/setting/env" => ["config", "Config / Infra"],
    "infra/deploy/lifecycle/install" => ["infra", "Config / Infra"],
    "security/auth/PII/payment/input validation" => ["security", "Security / Input"],
    "docs/readme/document/changelog" => ["docs", "Docs-Only"],
    "spike/explore/investigate" => ["spike", "Spike"]
  }
  valid = mapping.all? do |aliases, (category, gate)|
    task_type.fetch("infer_from").include?("#{aliases} -> #{category}") && triage.include?("### #{gate}")
  end
  exit(valid ? 0 : 1)
' "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/input.yaml" "$FRAMEWORK_DIR/skills/assistant-workflow/references/triage-rubric.md"; then
    pass
else
    fail "workflow task aliases or gate-pack routing drifted"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
