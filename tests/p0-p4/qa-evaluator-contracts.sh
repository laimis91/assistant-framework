#!/usr/bin/env bash

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

test_start "QA evaluator agents exist and are read-only"
missing_agent_terms=()
for file in \
    "$FRAMEWORK_DIR/agents/codex/qa-evaluator.toml" \
    "$FRAMEWORK_DIR/agents/claude/qa-evaluator.md"; do
    if [[ ! -f "$file" ]]; then
        missing_agent_terms+=("${file#$FRAMEWORK_DIR/}: exists")
    fi
done
if [[ -f "$FRAMEWORK_DIR/agents/codex/qa-evaluator.toml" ]]; then
    for term in \
        'sandbox_mode = "read-only"' \
        "Done Contract" \
        "acceptance criteria" \
        "verification evidence" \
        "score progression" \
        "final acceptance result" \
        "Do NOT replace code-reviewer" \
        "Do NOT edit any files" \
        "final_verdict=rejected and result=HAS_REMAINING_ITEMS" \
        "failed acceptance items should return to Build before round 10"; do
        if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/agents/codex/qa-evaluator.toml"; then
            missing_agent_terms+=("agents/codex/qa-evaluator.toml: $term")
        fi
    done
fi
if [[ -f "$FRAMEWORK_DIR/agents/claude/qa-evaluator.md" ]]; then
    for term in \
        "tools: Read, Grep, Glob, LS" \
        "Done Contract" \
        "acceptance criteria" \
        "verification evidence" \
        "score progression" \
        "final acceptance result" \
        "Do NOT replace code-reviewer" \
        "Do NOT edit any files" \
        "final_verdict=rejected and result=HAS_REMAINING_ITEMS" \
        "failed acceptance items should return to Build before round 10"; do
        if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/agents/claude/qa-evaluator.md"; then
            missing_agent_terms+=("agents/claude/qa-evaluator.md: $term")
        fi
    done
    if grep -Eq '^tools: .*Edit|^tools: .*Write|^tools: .*Bash' "$FRAMEWORK_DIR/agents/claude/qa-evaluator.md"; then
        missing_agent_terms+=("agents/claude/qa-evaluator.md: unexpected write/shell tools")
    fi
fi
if [[ "${#missing_agent_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "QA evaluator agent prompts missing read-only role terms: ${missing_agent_terms[*]}"
fi

test_start "Codex installer keeps AGENTS lean and installs read-only qa-evaluator"
INSTALL_HOME_QA="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_QA"
if HOME="$INSTALL_HOME_QA" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow >/tmp/p0p4-install-qa-evaluator.out 2>/tmp/p0p4-install-qa-evaluator.err; then
    agents_file="$INSTALL_HOME_QA/.codex/AGENTS.md"
    if grep -Fq "Codex uses installed skills through native skill routing." "$agents_file" \
        && ! grep -Fq "| qa-evaluator |" "$agents_file" \
        && ! grep -Fq "independent QA acceptance evaluation by qa-evaluator" "$agents_file" \
        && [[ -f "$INSTALL_HOME_QA/.codex/agents/qa-evaluator.toml" ]] \
        && grep -Fq 'sandbox_mode = "read-only"' "$INSTALL_HOME_QA/.codex/agents/qa-evaluator.toml"; then
        pass
    else
        fail "Codex install must keep standing AGENTS guidance lean and install the read-only qa-evaluator config"
    fi
else
    fail "Codex install failed; see /tmp/p0p4-install-qa-evaluator.err"
fi

test_start "assistant-review routes independent QA evaluation to reference with 10-round cap"
review_dir="$FRAMEWORK_DIR/skills/assistant-review"
missing_review_terms=()
for file_and_term in \
    "$review_dir/SKILL.md::# Autonomous Review And QA Evaluation" \
    "$review_dir/SKILL.md::QA evaluation runs after code-review/build evidence" \
    "$review_dir/SKILL.md::Load \`references/qa-evaluation-loop.md\`" \
    "$review_dir/references/review-loop.md::load \`qa-evaluation-loop.md\` before dispatching QAEvaluator" \
    "$review_dir/references/review-loop.md::That reference owns the detailed QA algorithm" \
    "$review_dir/references/qa-evaluation-loop.md::while round <= 10" \
    "$review_dir/references/qa-evaluation-loop.md::Round 10 is terminal" \
    "$review_dir/references/qa-evaluation-loop.md::does not replace code-reviewer" \
    "$review_dir/contracts/handoffs.yaml::to: QAEvaluator" \
    "$review_dir/contracts/handoffs.yaml::- name: debate_record" \
    "$review_dir/contracts/handoffs.yaml::pre-build debate/subagent-perspective evidence" \
    "$review_dir/contracts/handoffs.yaml::previously_failed_acceptance_items" \
    "$review_dir/contracts/handoffs.yaml::qa_filter_policy" \
    "$review_dir/contracts/handoffs.yaml::debate_record when Done Contract exists" \
    "$review_dir/contracts/handoffs.yaml::qa_scorecard" \
    "$review_dir/contracts/handoffs.yaml::score_entry" \
    "$review_dir/contracts/handoffs.yaml::The loop never starts round 11." \
    "$review_dir/contracts/input.yaml::- name: qa_evaluation_mode" \
    "$review_dir/contracts/input.yaml::- name: debate_record" \
    "$review_dir/contracts/input.yaml::pre-build debate/subagent-perspective evidence" \
    "$review_dir/contracts/input.yaml::- name: qa_filter_policy" \
    "$review_dir/contracts/output.yaml::- name: qa_evaluation_result" \
    "$review_dir/contracts/output.yaml::final_verdict" \
    "$review_dir/contracts/output.yaml::score_progression" \
    "$review_dir/references/qa-evaluation-loop.md::debate_record" \
    "$review_dir/references/qa-evaluation-loop.md::pre-build debate/subagent-perspective evidence" \
    "$review_dir/contracts/phase-gates.yaml::QA_EVALUATION_STEP" \
    "$review_dir/contracts/phase-gates.yaml::QA evaluation starts only after build/test verification evidence and Code Reviewer or Reviewer compatibility result are available" \
    "$review_dir/contracts/phase-gates.yaml::INV_QA4" \
    "$review_dir/contracts/phase-gates.yaml::QA findings require acceptance criteria, Done Contract, verification evidence, scoped domain-context support, and debate_record when Done Contract exists" \
    "$review_dir/contracts/phase-gates.yaml::round 10 is terminal"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        missing_review_terms+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#missing_review_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review QA loop contract terms missing: ${missing_review_terms[*]}"
fi

test_start "assistant-review canonical QA scorecard preserves QAEvaluator return semantics"
if ruby -ryaml -rbigdecimal -e '
  output = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: false)
  handoffs = YAML.safe_load(File.read(ARGV.fetch(1)), aliases: false)

  qa_output = output.fetch("artifacts").find { |artifact| artifact["name"] == "qa_evaluation_result" }
  qa_handoff = handoffs.fetch("handoffs").find { |handoff| handoff["name"] == "orchestrator_to_qa_evaluator" }
  output_scorecard = qa_output.fetch("object_fields").find { |field| field["name"] == "qa_scorecard" }
  handoff_scorecard = qa_handoff.fetch("return_fields").find { |field| field["name"] == "qa_scorecard" }

  output_fields = output_scorecard.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  handoff_fields = handoff_scorecard.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  score_names = %w[acceptance_coverage evidence_strength domain_quality final_readiness]
  score_semantics_match = score_names.all? do |name|
    output_field = output_fields.fetch(name)
    handoff_field = handoff_fields.fetch(name)
    output_field["required"] == true &&
      output_field["type"] == "float" &&
      output_field["validation"] == handoff_field["validation"] &&
      output_field.fetch("validation").include?("1.0 to 5.0 in 0.5 increments")
  end

  output_rationale = output_fields.fetch("rationale")
  handoff_rationale = handoff_fields.fetch("rationale")
  output_rationale_fields = output_rationale.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  handoff_rationale_fields = handoff_rationale.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  rationale_names = %w[acceptance_coverage evidence_strength domain_quality final_readiness]
  rationale_semantics_match = output_rationale["required"] == true &&
    output_rationale["type"] == "object" &&
    output_rationale_fields.keys.sort == rationale_names.sort &&
    rationale_names.all? do |name|
      output_rationale_fields.fetch(name) == handoff_rationale_fields.fetch(name)
    end

  weighted_semantics_match = output_fields.fetch("weighted_score")["validation"] ==
    handoff_fields.fetch("weighted_score")["validation"]

  exit(score_semantics_match && rationale_semantics_match && weighted_semantics_match ? 0 : 1)
' "$review_dir/contracts/output.yaml" "$review_dir/contracts/handoffs.yaml"; then
    pass
else
    fail "assistant-review canonical QA scorecard does not preserve bounded QAEvaluator scores and required rationale"
fi

test_start "assistant-review canonical QA result preserves conditional producer semantics"
if ruby -ryaml -rbigdecimal -e '
  output = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: false)
  handoffs = YAML.safe_load(File.read(ARGV.fetch(1)), aliases: false)
  qa_loop = File.read(ARGV.fetch(2))
  qa_output = output.fetch("artifacts").find { |artifact| artifact["name"] == "qa_evaluation_result" }
  qa_handoff = handoffs.fetch("handoffs").find { |handoff| handoff["name"] == "orchestrator_to_qa_evaluator" }
  output_fields = qa_output.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  handoff_fields = qa_handoff.fetch("return_fields").to_h { |field| [field.fetch("name"), field] }

  output_pivot = output_fields.fetch("pivot_restart_signal")
  handoff_pivot = handoff_fields.fetch("pivot_restart_signal")
  pivot_shape_match = output_pivot.fetch("object_fields") == handoff_pivot.fetch("object_fields") &&
    output_pivot.fetch("condition").include?("final score_progression entry") &&
    output_pivot.fetch("validation").include?("current final QA round")
  valid_pivot_packet = ->(signal, current_round) do
    signal.is_a?(Hash) && %w[STAGNATION repeated_DRIFT repeated_REGRESSION pivot].include?(signal["trigger"]) &&
      signal["evidence"].is_a?(Array) && !signal["evidence"].empty? &&
      signal["evidence"].all? { |entry| entry["source"].is_a?(String) && !entry["source"].strip.empty? && entry["detail"].is_a?(String) && !entry["detail"].strip.empty? } &&
      signal["affected_round"] == current_round && signal["recommended_recovery_focus"].is_a?(String) && !signal["recommended_recovery_focus"].strip.empty?
  end
  valid_signal = {"trigger" => "pivot", "evidence" => [{"source" => "domain rubric", "detail" => "wrong direction"}], "affected_round" => 2, "recommended_recovery_focus" => "replan acceptance approach"}
  pivot_mutations_rejected = valid_pivot_packet.call(valid_signal, 2) &&
    !valid_pivot_packet.call(nil, 2) &&
    !valid_pivot_packet.call(valid_signal.merge("trigger" => "other"), 2) &&
    !valid_pivot_packet.call(valid_signal.merge("evidence" => []), 2) &&
    !valid_pivot_packet.call(valid_signal.merge("affected_round" => 1), 2) &&
    !valid_pivot_packet.call(valid_signal.merge("recommended_recovery_focus" => " "), 2)

  scoped_fields_match = %w[selected_domain_rubrics domain_quality_scores].all? do |name|
    output_fields.fetch(name) == handoff_fields.fetch(name)
  end
  domain_fields = output_fields.fetch("domain_quality_scores").fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  allowed_families = %w[ui_visual_design ux_product_acceptance documentation_quality developer_experience domain_specific_craft]
  selected_validation = output_fields.fetch("selected_domain_rubrics").fetch("validation")
  scoped_constraints_present = allowed_families.all? { |family| selected_validation.include?(family) } &&
    domain_fields.fetch("score").fetch("validation").include?("1.0 to 5.0 in 0.5 increments") &&
    domain_fields.fetch("evidence").fetch("validation").include?("Cites acceptance criteria")

  valid_domain_packet = ->(rubrics, scores) do
    rubrics.is_a?(Array) && !rubrics.empty? && rubrics.all? { |family| allowed_families.include?(family) } &&
      scores.is_a?(Array) && !scores.empty? && scores.all? do |score|
        rubrics.include?(score["rubric_ref"]) && score["score"].is_a?(Numeric) && score["score"].between?(1.0, 5.0) &&
          ((score["score"] * 2) % 1).zero? && score["evidence"].is_a?(String) && !score["evidence"].strip.empty?
      end
  end
  valid_scores = [{"rubric_ref" => "documentation_quality", "score" => 4.5, "evidence" => "Cites acceptance criteria and rendered docs"}]
  mutations_rejected = valid_domain_packet.call(["documentation_quality"], valid_scores) &&
    !valid_domain_packet.call(["invented_rubric"], valid_scores) &&
    !valid_domain_packet.call(["documentation_quality"], [valid_scores.first.merge("score" => 4.25)]) &&
    !valid_domain_packet.call(["documentation_quality"], [valid_scores.first.merge("score" => 5.5)]) &&
    !valid_domain_packet.call(["documentation_quality"], [valid_scores.first.merge("evidence" => " ")])

  formula = "weighted_score = round_half_up((acceptance_coverage * 0.30) + (evidence_strength * 0.25) + (domain_quality * 0.20) + (final_readiness * 0.25), 2 decimal places)"
  output_formula = output_fields.fetch("qa_scorecard").fetch("object_fields").find { |field| field["name"] == "weighted_score" }.fetch("validation")
  handoff_formula = handoff_fields.fetch("qa_scorecard").fetch("object_fields").find { |field| field["name"] == "weighted_score" }.fetch("validation")
  raw = (BigDecimal("4.5") * BigDecimal("0.30")) + (BigDecimal("4.0") * BigDecimal("0.25")) +
    (BigDecimal("5.0") * BigDecimal("0.20")) + (BigDecimal("3.5") * BigDecimal("0.25"))
  half_up = raw.round(2, :half_up).to_f
  prompts = ARGV.drop(3).map { |path| File.read(path) }
  formula_valid = output_formula == formula && handoff_formula == formula && qa_loop.include?(formula) && prompts.all? { |prompt| prompt.include?(formula) } && half_up == 4.23

  exit(pivot_shape_match && pivot_mutations_rejected && scoped_fields_match && scoped_constraints_present && mutations_rejected && formula_valid ? 0 : 1)
' "$review_dir/contracts/output.yaml" "$review_dir/contracts/handoffs.yaml" "$review_dir/references/qa-evaluation-loop.md" "$FRAMEWORK_DIR/agents/claude/qa-evaluator.md" "$FRAMEWORK_DIR/agents/codex/qa-evaluator.toml"; then
    pass
else
    fail "assistant-review canonical QA result loses pivot, scoped-domain, or deterministic weighted-score semantics"
fi

test_start "assistant-review QA Done Contract debate_record contract is mirrored"
debate_mirror_failures=()
for qa_review_dir in \
    "$FRAMEWORK_DIR/skills/assistant-review"; do
    for file_and_term in \
        "$qa_review_dir/contracts/input.yaml::- name: debate_record" \
        "$qa_review_dir/contracts/input.yaml::pre-build debate/subagent-perspective evidence" \
        "$qa_review_dir/contracts/handoffs.yaml::- name: debate_record" \
        "$qa_review_dir/contracts/handoffs.yaml::pre-build debate/subagent-perspective evidence" \
        "$qa_review_dir/references/qa-evaluation-loop.md::debate_record" \
        "$qa_review_dir/contracts/phase-gates.yaml::INV_QA4" \
        "$qa_review_dir/contracts/phase-gates.yaml::QA findings require acceptance criteria, Done Contract, verification evidence, scoped domain-context support, and debate_record when Done Contract exists"; do
        file="${file_and_term%%::*}"
        term="${file_and_term#*::}"
        if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
            debate_mirror_failures+=("${file#$FRAMEWORK_DIR/}: $term")
        fi
    done
done
if [[ "${#debate_mirror_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review QA Done Contract debate_record contract terms missing or not mirrored: ${debate_mirror_failures[*]}"
fi

test_start "workflow records separate Code Reviewer and QA Evaluator evidence"
workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"
review_qa_router="$workflow_dir/references/review-qa-router.md"
missing_workflow_terms=()
for file_and_term in \
    "$workflow_dir/contracts/handoffs.yaml::contract_ref: assistant-review/contracts/handoffs.yaml" \
    "$workflow_dir/contracts/handoffs.yaml::orchestrator_to_qa_evaluator" \
    "$workflow_dir/contracts/input.yaml::- name: qa_evaluation_mode" \
    "$workflow_dir/contracts/output.yaml::- name: qa_evaluation_result" \
    "$workflow_dir/contracts/output.yaml::QA evaluation does not replace review_result" \
    "$workflow_dir/contracts/output.yaml::assistant-review/contracts/output.yaml#qa_evaluation_result" \
    "$workflow_dir/contracts/output.yaml::canonical_result_ref" \
    "$workflow_dir/contracts/phase-gates.yaml::R_QA_EVALUATION" \
    "$workflow_dir/contracts/phase-gates.yaml::Code Reviewer or Reviewer compatibility evidence is recorded separately from QA Evaluator evidence" \
    "$workflow_dir/contracts/phase-gates.yaml::When qa_evaluation_mode == required: required_agents includes QA Evaluator" \
    "$workflow_dir/contracts/phase-gates.yaml::assistant-review owns QAEvaluator dispatch and return validation" \
    "$review_qa_router::Stage 3 - QA Evaluation" \
    "$review_qa_router::workflow records only validated refs" \
    "$workflow_dir/references/subagent-dispatch.md::QA Evaluator" \
    "$workflow_dir/references/subagent-dispatch.md::QA evidence gate" \
    "$workflow_dir/references/subagent-roles.md::QA Evaluator dispatch" \
    "$workflow_dir/references/task-journal-template.md::QA Evaluator dispatch" \
    "$workflow_dir/references/task-journal-harness-appendix.md::### QA Evaluation #1" \
    "$workflow_dir/references/sub-task-brief-template.md::qa-evaluator"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        missing_workflow_terms+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#missing_workflow_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow QA evaluator evidence surfaces missing: ${missing_workflow_terms[*]}"
fi

test_start "QA evaluation required mode is explicitly scoped"
review_dir="$FRAMEWORK_DIR/skills/assistant-review"
qa_positive_trigger_wording="QA required positive triggers: explicit QA/acceptance evaluation request, accepted Done Contract, harness-capable acceptance scope, domain-scored scope, or scoped UI/visual/product/UX/docs/DX acceptance."
qa_negative_trigger_wording="QA non-triggers: template labels/placeholders, generic acceptance criteria labels, optional/not_required reasons, delegation/source-changing work alone, and ordinary medium+ code-review-only/source-changing work."
require_terms "workflow QA mode" "$workflow_dir/contracts/input.yaml" \
    "- name: harness_capable" \
    "default: false" \
    "Use required when the user explicitly requests QA/acceptance evaluation" \
    "accepted Done Contract" \
    "harness_capable == true and acceptance evaluation is in scope" \
    "domain-scored" \
    "UI/visual/product/UX/docs/DX" \
    "Use not_required for ordinary medium+ code-review-only/source-changing work"
require_terms "review QA mode" "$review_dir/contracts/input.yaml" \
    "- name: harness_capable" \
    "default: false" \
    "Use required when the user explicitly requests QA/acceptance evaluation" \
    "accepted Done Contract" \
    "harness_capable == true and acceptance evaluation is in scope" \
    "domain-scored" \
    "UI/visual/product/UX/docs/DX" \
    "Use not_required for ordinary medium+ code-review-only/source-changing work"
require_terms "QA loop routing" "$review_dir/references/qa-evaluation-loop.md" \
    "The user explicitly asks for QA or acceptance evaluation." \
    "The task has an accepted Done Contract." \
    "The task is harness-capable and acceptance evaluation is in scope." \
    "Skip QA evaluation when the task has no explicit QA request, Done Contract, harness-capable acceptance scope, domain-scored criteria, or UI/visual/product/UX/docs/DX scope"
require_terms "workflow QA output mode" "$workflow_dir/contracts/output.yaml" \
    'condition: "execution_intent != prepare_only and qa_evaluation_mode == required"' \
    "QA evaluation does not replace review_result"

test_start "workflow and review QA trigger wording is mirrored"
qa_trigger_wording_missing=()
for file in \
    "$workflow_dir/contracts/input.yaml" \
    "$workflow_dir/contracts/phase-gates.yaml" \
    "$workflow_dir/references/review-qa-router.md" \
    "$workflow_dir/references/plan-harness-appendix.md" \
    "$workflow_dir/references/subagent-dispatch.md" \
    "$workflow_dir/references/plan-template.md" \
    "$workflow_dir/references/task-journal-template.md" \
    "$review_dir/SKILL.md" \
    "$review_dir/contracts/input.yaml" \
    "$review_dir/references/qa-evaluation-loop.md"; do
    for term in "$qa_positive_trigger_wording" "$qa_negative_trigger_wording"; do
        if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
            qa_trigger_wording_missing+=("${file#$FRAMEWORK_DIR/}: $term")
        fi
    done
done
if [[ "${#qa_trigger_wording_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "QA positive/negative trigger wording is not mirrored: ${qa_trigger_wording_missing[*]}"
fi

test_start "workflow QA trigger wording avoids broad DX-facing scope"
if rg -n "UI/visual/product/UX/docs/DX-facing" \
    "$workflow_dir/SKILL.md" \
    "$workflow_dir/references/plan-harness-appendix.md" >/tmp/p0p4-stale-qa-facing-wording.out; then
    fail "workflow root QA surfaces contain broad DX-facing wording; see /tmp/p0p4-stale-qa-facing-wording.out"
else
    pass
fi

test_start "workflow delegates QA packet ownership to assistant-review"
workflow_qa_ownership_failures=()
for workflow_qa_dir in \
    "$FRAMEWORK_DIR/skills/assistant-workflow"; do
    if grep -Fq -- '- name: orchestrator_to_qa_evaluator' "$workflow_qa_dir/contracts/handoffs.yaml"; then
        workflow_qa_ownership_failures+=("${workflow_qa_dir#$FRAMEWORK_DIR/}/contracts/handoffs.yaml: duplicated QAEvaluator handoff")
    fi
    for file_and_term in \
        "$workflow_qa_dir/contracts/handoffs.yaml::delegated_skill_contract_owners:" \
        "$workflow_qa_dir/contracts/handoffs.yaml::contract_ref: assistant-review/contracts/handoffs.yaml" \
        "$workflow_qa_dir/contracts/output.yaml::assistant-review/contracts/output.yaml#qa_evaluation_result" \
        "$workflow_qa_dir/contracts/output.yaml::- name: canonical_result_ref" \
        "$workflow_qa_dir/contracts/output.yaml::- name: validation_status"; do
        file="${file_and_term%%::*}"
        term="${file_and_term#*::}"
        if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
            workflow_qa_ownership_failures+=("${file#$FRAMEWORK_DIR/}: $term")
        fi
    done
done
if [[ "${#workflow_qa_ownership_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow does not delegate QA schema ownership cleanly: ${workflow_qa_ownership_failures[*]}"
fi

test_start "code-reviewer remains distinct from QA evaluator"
distinct_terms_missing=()
for file_and_term in \
    "$FRAMEWORK_DIR/agents/codex/code-reviewer.toml::Stay in the code-review lane" \
    "$FRAMEWORK_DIR/agents/codex/qa-evaluator.toml::Stay in the QA lane" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/subagent-dispatch.md::Code Reviewer" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/subagent-dispatch.md::QA Evaluator" \
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md::Keep QA evaluation separate from code review" \
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md::Code Reviewer continues to own code defects, security, architecture, and test-coverage review"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        distinct_terms_missing+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#distinct_terms_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "code-reviewer and QA evaluator role separation terms missing: ${distinct_terms_missing[*]}"
fi

test_start "QA prompts preserve per-round score and conditional pivot return semantics"
if ruby -ryaml -e '
  handoffs = YAML.load_file(ARGV.shift)
  output = YAML.load_file(ARGV.shift)
  loop = File.read(ARGV.shift)
  gates = YAML.load_file(ARGV.shift)
  prompts = ARGV.map { |path| File.read(path) }
  qa = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_qa_evaluator" }
  bundle = handoffs.fetch("dispatch_context_bundles").find { |entry| entry["name"] == "qa_evaluator_context" }
  selector = bundle.fetch("worker_return_schema_selector")
  fields = qa.fetch("return_fields").to_h { |field| [field["name"], field] }
  qa_output = output.fetch("artifacts").find { |artifact| artifact["name"] == "qa_evaluation_result" }
  output_progression = qa_output.fetch("object_fields").find { |field| field["name"] == "score_progression" }
  pivot = fields.fetch("pivot_restart_signal")
  pivot_names = pivot.fetch("object_fields").map { |field| field["name"] }
  canonical_projection = %w[round weighted_score failed_acceptance_count delta drift_status]
  prompt_terms = ["Before first response, resolve `worker_return_schema`: from the active assistant-review skill root, load named `return_fields` recursively with bounded keys from `contracts/handoffs.yaml`; verify it equals the schema identified by `return_schema_ref`, or return `NEEDS_CONTEXT` without a partial result.", "`score_entry` is required for every QA round.", "`score_progression` is optional prior-round history; when returned, every entry is the same canonical projection: `round` (int), `weighted_score` (float), `failed_acceptance_count` (int), `delta` (string), and `drift_status` (the canonical enum).", "When score_entry.drift_status=STAGNATION, repeated QA DRIFT/REGRESSION occurs, or a scoped domain action=pivot, return `pivot_restart_signal` with `trigger`, `evidence`, `affected_round`, and `recommended_recovery_focus`."]
  valid_projection = ->(entry) { entry.is_a?(Hash) && entry.keys.sort == canonical_projection.sort && entry["round"].is_a?(Integer) && entry["weighted_score"].is_a?(Numeric) && entry["failed_acceptance_count"].is_a?(Integer) && entry["delta"].is_a?(String) && %w[GENUINE SUSPICIOUS DRIFT REGRESSION STAGNATION NEUTRAL NOT_APPLICABLE].include?(entry["drift_status"]) }
  valid_packet = ->(packet) {
    score = packet["score_entry"]
    return false unless valid_projection.call(score)
    return false if packet.key?("score_progression") && (!packet["score_progression"].is_a?(Array) || !packet["score_progression"].all? { |entry| valid_projection.call(entry) })
    triggered = score["drift_status"] == "STAGNATION" || packet["repeated_drift"] || packet["domain_pivot"]
    return !packet.key?("pivot_restart_signal") unless triggered
    signal = packet["pivot_restart_signal"]
    signal.is_a?(Hash) && %w[STAGNATION repeated_DRIFT repeated_REGRESSION pivot].include?(signal["trigger"]) && signal["evidence"].is_a?(Array) && !signal["evidence"].empty? && signal["affected_round"] == packet.dig("score_entry", "round") && signal["recommended_recovery_focus"].is_a?(String) && !signal["recommended_recovery_focus"].strip.empty?
  }
  normal = {"score_entry" => {"round" => 2, "weighted_score" => 4.0, "failed_acceptance_count" => 0, "delta" => "initial", "drift_status" => "NEUTRAL"}}
  with_progression = normal.merge("score_progression" => [normal.fetch("score_entry")])
  progression_only = {"score_progression" => []}
  triggered = {"score_entry" => normal["score_entry"].merge("drift_status" => "STAGNATION"), "pivot_restart_signal" => {"trigger" => "STAGNATION", "evidence" => [{"source" => "score", "detail" => "stalled"}], "affected_round" => 2, "recommended_recovery_focus" => "recover"}}
  resolution = "Worker recursively loads named handoff return_fields (bounded keys); worker_return_schema equals schema identified by return_schema_ref before response; else NEEDS_CONTEXT, no partial result."
  resolve_schema = ->(document, ref) { _root, handoff_name, field_name = ref.split("."); document.fetch("handoffs").find { |entry| entry["name"] == handoff_name }.fetch(field_name) }
  resolved_schema_key = selector.fetch("resolution").match(/(worker_return_schema) equals schema identified by return_schema_ref before response/)[1]
  rendered_dispatch = {resolved_schema_key => resolve_schema.call(handoffs, selector.fetch("return_schema_ref")), "return_schema_ref" => selector.fetch("return_schema_ref"), "resolution_proof" => selector.fetch("resolution")}
  selector_valid = selector.fetch("return_schema_ref") == "handoffs.orchestrator_to_qa_evaluator.return_fields" && selector.fetch("source_path") == "contracts/handoffs.yaml" && selector.fetch("resolution") == resolution && selector.fetch("recursive_shape").include?("required/conditional fields, types, enums, and cardinality") && selector.fetch("excludes").include?("sibling/batch state")
  projection_schema = ->(field) { field.fetch("object_fields").map { |item| item.slice("name", "type", "required", "enum_values") } }
  qa2 = gates.fetch("gates").flat_map { |phase| phase.fetch("exit_assertions", []) }.find { |gate| gate["id"] == "QA2" }
  valid = fields.fetch("score_entry")["required"] == true && fields.fetch("score_progression")["required"] == false && projection_schema.call(fields.fetch("score_entry")) == projection_schema.call(fields.fetch("score_progression")) && projection_schema.call(fields.fetch("score_progression")) == projection_schema.call(output_progression) && fields.fetch("score_progression").fetch("object_fields").map { |field| field.fetch("name") } == canonical_projection && loop.include?("same canonical projection: `round` (int), `weighted_score` (float), `failed_acceptance_count` (int), exact adjacent `delta` (string), and derived `drift_status` (the canonical enum)") && pivot["required"] == "conditional" && pivot.fetch("condition").include?("score_entry.drift_status == STAGNATION") && pivot_names == %w[trigger evidence affected_round recommended_recovery_focus] && selector_valid && rendered_dispatch.fetch(resolved_schema_key) == qa.fetch("return_fields") && rendered_dispatch.fetch("return_schema_ref") == selector.fetch("return_schema_ref") && rendered_dispatch.fetch("resolution_proof") == resolution && qa2.fetch("check").include?("worker_return_schema_selector") && qa2.fetch("check").include?("worker_return_schema") && qa2.fetch("check").include?("fails closed") && prompts.all? { |prompt| prompt_terms.all? { |term| prompt.include?(term) } } && valid_packet.call(normal) && valid_packet.call(with_progression) && !valid_packet.call(progression_only) && !valid_packet.call(with_progression.dup.tap { |packet| packet["score_progression"] = [packet["score_progression"].first.dup.tap { |entry| entry.delete("delta") }] }) && !valid_packet.call(with_progression.dup.tap { |packet| packet["score_progression"] = [packet["score_progression"].first.dup.tap { |entry| entry["weighted_score"] = "4" }] }) && valid_packet.call(triggered) && !valid_packet.call(normal.dup.tap { |packet| packet["score_entry"] = packet["score_entry"].dup; packet["score_entry"].delete("weighted_score") }) && !valid_packet.call(normal.dup.tap { |packet| packet["score_entry"] = packet["score_entry"].dup; packet["score_entry"]["drift_status"] = "BAD" }) && !valid_packet.call(triggered.dup.tap { |packet| packet.delete("pivot_restart_signal") }) && !valid_packet.call(triggered.dup.tap { |packet| packet["pivot_restart_signal"] = packet["pivot_restart_signal"].dup; packet["pivot_restart_signal"]["evidence"] = [] })
  exit valid ? 0 : 1
' "$review_dir/contracts/handoffs.yaml" "$review_dir/contracts/output.yaml" "$review_dir/references/qa-evaluation-loop.md" "$review_dir/contracts/phase-gates.yaml" "$FRAMEWORK_DIR/agents/codex/qa-evaluator.toml" "$FRAMEWORK_DIR/agents/claude/qa-evaluator.md"; then
    pass
else
    fail "QA prompts or return contract permit progression-only or triggered-pivot omissions"
fi

test_start "QAEvaluator return schema recursively rejects required, type, enum, and cardinality mutations"
if ruby -ryaml -e '
  handoffs = YAML.load_file(ARGV.fetch(0))
  bundle = handoffs.fetch("dispatch_context_bundles").find { |entry| entry["name"] == "qa_evaluator_context" }
  selector = bundle.fetch("worker_return_schema_selector")
  fields = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_qa_evaluator" }.fetch("return_fields")
  sample = nil
  sample = ->(field) {
    return field.fetch("enum_values").first if field["type"] == "enum"
    case field["type"]
    when "string" then "value"
    when "int" then 1
    when "float" then 1.0
    when "boolean" then true
    when "string[]" then Array.new([field["min_items"] || 1, 1].max, "value")
    when "object" then field.fetch("object_fields", []).to_h { |child| [child.fetch("name"), sample.call(child)] }
    when "object[]" then Array.new([field["min_items"] || 1, 1].max) { field.fetch("object_fields", []).to_h { |child| [child.fetch("name"), sample.call(child)] } }
    else raise "unsupported #{field["type"]}"
    end
  }
  schema_valid = nil
  schema_valid = ->(packet, schema) {
    return false unless packet.is_a?(Hash) && (packet.keys - schema.map { |field| field.fetch("name") }).empty?
    schema.all? do |field|
      name = field.fetch("name")
      next false if [true, "conditional"].include?(field["required"]) && !packet.key?(name)
      next true unless packet.key?(name)
      value = packet[name]
      ok = case field["type"]
        when "string" then value.is_a?(String)
        when "int" then value.is_a?(Integer)
        when "float" then value.is_a?(Numeric)
        when "boolean" then value == true || value == false
        when "string[]" then value.is_a?(Array) && value.all? { |item| item.is_a?(String) }
        when "object" then value.is_a?(Hash)
        when "object[]" then value.is_a?(Array)
        when "enum" then value.is_a?(String) && field.fetch("enum_values").include?(value)
        else false
      end
      next false unless ok && (!field["min_items"] || value.length >= field["min_items"])
      children = field["object_fields"]
      children ? (field["type"] == "object" ? schema_valid.call(value, children) : field["type"] == "object[]" ? value.all? { |item| schema_valid.call(item, children) } : true) : true
    end
  }
  complete = fields.to_h { |field| [field.fetch("name"), sample.call(field)] }
  resolution = "Worker recursively loads named handoff return_fields (bounded keys); worker_return_schema equals schema identified by return_schema_ref before response; else NEEDS_CONTEXT, no partial result."
  resolve_schema = ->(document, ref) { _root, handoff_name, field_name = ref.split("."); document.fetch("handoffs").find { |entry| entry["name"] == handoff_name }.fetch(field_name) }
  resolved_schema_key = selector.fetch("resolution").match(/(worker_return_schema) equals schema identified by return_schema_ref before response/)[1]
  rendered_dispatch = {resolved_schema_key => resolve_schema.call(handoffs, selector.fetch("return_schema_ref")), "return_schema_ref" => selector.fetch("return_schema_ref"), "resolution_proof" => selector.fetch("resolution")}
  copy = ->(value) { Marshal.load(Marshal.dump(value)) }
  nodes = []; walk = nil
  walk = ->(schema, path) { schema.each { |field| nodes << [path + [field.fetch("name")], field]; walk.call(field["object_fields"], path + [field.fetch("name")] + (field["type"] == "object[]" ? [0] : [])) if field["object_fields"] } }
  walk.call(fields, [])
  parent_at = ->(packet, path) { path[0...-1].reduce(packet) { |current, key| current[key] } }
  invalid = ->(field) { {"string" => 1, "int" => "1", "float" => "1", "boolean" => "true", "string[]" => [1], "object" => [], "object[]" => {}, "enum" => "INVALID_ENUM"}.fetch(field.fetch("type")) }
  mutate_all = ->(pairs, &mutation) { pairs.all? { |path, field| trial = copy.call(complete); mutation.call(parent_at.call(trial, path), path.last, field); !schema_valid.call(trial, fields) } }
  omissions = mutate_all.call(nodes.select { |_path, field| [true, "conditional"].include?(field["required"]) }) { |parent, name, _field| parent.delete(name) }
  types = mutate_all.call(nodes) { |parent, name, field| parent[name] = invalid.call(field) }
  enums = mutate_all.call(nodes.select { |_path, field| field["type"] == "enum" }) { |parent, name, _field| parent[name] = "INVALID_ENUM" }
  cardinality = mutate_all.call(nodes.select { |_path, field| field["min_items"].to_i > 0 }) { |parent, name, _field| parent[name] = [] }
  selector_valid = selector.fetch("source_path") == "contracts/handoffs.yaml" && selector.fetch("resolution") == resolution
  exit(selector_valid && rendered_dispatch.fetch(resolved_schema_key) == fields && rendered_dispatch.fetch("return_schema_ref") == selector.fetch("return_schema_ref") && schema_valid.call(complete, rendered_dispatch.fetch(resolved_schema_key)) && omissions && types && enums && cardinality ? 0 : 1)
' "$review_dir/contracts/handoffs.yaml"; then
    pass
else
    fail "QAEvaluator recursive return schema accepts a required, type, enum, or cardinality mutation"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
