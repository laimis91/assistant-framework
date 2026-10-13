#!/usr/bin/env bash

if [[ -z "$P0P4_HARNESS_LOADED" ]]; then
    source "$(cd "$(dirname "$BASH_SOURCE")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "$BASH_SOURCE"

workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"
input_contract="$workflow_dir/contracts/input.yaml"
phase_gates="$workflow_dir/contracts/phase-gates.yaml"
phases="$workflow_dir/references/phases.md"
map_ref="$workflow_dir/references/requirement-acceptance-map.md"
feature_ref="$workflow_dir/references/feature-preparation-evidence.md"
journal="$workflow_dir/references/task-journal-template.md"
output="$workflow_dir/contracts/output.yaml"
handoffs="$workflow_dir/contracts/handoffs.yaml"
contract_index="$workflow_dir/contracts/index.yaml"
discover_view="$workflow_dir/references/phases/discover.md"

test_start "prepare-only Discover completes with retained open decisions while dependent intents remain gated"
if ruby -ryaml -e '
  gates = YAML.load_file(ARGV.fetch(0)).fetch("gates")
  phases = File.read(ARGV.fetch(1))
  generated = File.read(ARGV.fetch(2))
  discover = gates.find { |gate| gate["phase"] == "DISCOVER" }
  sufficiency = discover && discover.fetch("exit_assertions").find { |item| item["id"] == "D_REQUIREMENTS_SUFFICIENCY" }
  acceptance = discover && discover.fetch("exit_assertions").find { |item| item["id"] == "D_REQUIREMENT_ACCEPTANCE_MAP" }
  d2 = discover && discover.fetch("exit_assertions").find { |item| item["id"] == "D2" }
  d3 = discover && discover.fetch("exit_assertions").find { |item| item["id"] == "D3" }
  normalize = ->(value) { value.downcase.delete("`").gsub(/\s+/, " ") }
  pack = discover && discover.fetch("exit_assertions").find { |item| item["id"] == "D_ARCHITECTURE_DECISION_PACK" }
  pack_check = normalize.call(pack.fetch("check"))
  pack_failure = normalize.call(pack.fetch("on_fail"))
  pack_resolution_scoped = pack_check.include?("for execution_intent != prepare_only, resolve blocking material questions")
  pack_retains_open = pack_check.include?("prepare_only retains unresolved questions in feature_preparation_result.open_decisions")
  pack_keeps_integrity = pack_check.include?("architecture_decision_pack is current") &&
    pack_check.include?("architecture_decision_pack.mode equals canonical architecture_design_mode") &&
    pack_check.include?("verified evidence and verification_ref are permitted only when status=verified")
  pack_condition_preserved = pack.fetch("condition") == "architecture_design_mode in [lightweight, required, review_intensive]"
  pack_failure_scoped = pack_failure.include?("for prepare_only, retain unresolved questions in feature_preparation_result.open_decisions and only the context/journal ref through preparation completion; do not wait") &&
    pack_failure.include?("for execution intents, resolve material questions before dependent work and bind the pack ref")
  architecture_ref = File.read(ARGV.fetch(3))
  discovery = architecture_ref[/^## AI-led question discovery.*?(?=^## Semantic interface policy)/m]
  question_policy = normalize.call(discovery.to_s)
  prepare_questions_retained = question_policy.include?("for prepare_only, record open architecture questions in the typed pack and feature_preparation_result.open_decisions; do not wait")
  execution_questions_resolved = question_policy.include?("resolve blocking material questions before dependent work for execution intents")
  map_check = normalize.call(acceptance.fetch("check"))
  d3_check = normalize.call(d3.fetch("check"))
  map_ready_scope = map_check.include?("for execution_intent != prepare_only, no unresolved material questions remain")
  map_retains_open = map_check.include?("for prepare_only, retain unresolved material questions in map and feature_preparation_result.open_decisions")
  d3_ready_scope = d3_check.include?("for execution_intent != prepare_only, unresolved clarification topics are empty before discover completes")
  defaults_consistency = d3_check.include?("clarification_defaults_applied is true exactly when clarification_defaults contains automatically applied entries with topic, value, source, and rationale")
  d3_retains_open = normalize.call(d3.fetch("on_fail")).include?("prepare_only preserves unresolved topics and their open_decisions")
  map_is_still_required = map_check.include?("requirement_acceptance_map exists with stable requirement_id values") && map_check.include?("assumptions/defaults, non-goals")
  map_condition = "size in [medium, large, mega] or (progressive_artifact_retention_state != terminally_archived and progressive_route_clear_consumption_state != pending and (architecture_design_mode in [required, review_intensive] or progressive_route_clear_consumption_state == consumed))"
  map_trigger_preserved = acceptance.fetch("condition") == map_condition
  sufficiency_check = "Dependent work requires references/phases.md sufficiency; block guesses and controlling-source gaps/conflicts."
  sufficiency_failure = "Return to Discover; ask about material choices and resolve controlling-source gaps/conflicts."
  sufficiency_scoped = sufficiency && sufficiency["condition"] == "execution_intent != prepare_only"
  d2_scoped = d2 && d2["condition"] == "execution_intent != prepare_only"
  source_phase = phases[/^## Phase: Discover.*?(?=^## Phase: Decompose)/m]
  generated_phase = generated[/^## Phase: Discover.*?(?=^## Phase: Decompose|\z)/m]
  prep_state = normalize.call(source_phase.to_s)
  prep_requirements = [
    "for execution_intent=prepare_only, retain unresolved topics and provisional recommendations",
    "finish discover through preparation completion without readiness or dependent work",
    "in feature_preparation_result.open_decisions and existing map/state",
    "preserve needs_clarification and actual technical defaults",
    "optional readiness context settles no decisions",
    "the following clarification wait rules apply to other execution intents",
    "for execution_intent != prepare_only, discover does not complete while clarification status: needs_clarification"
  ]
  source_allows_preparation = prep_requirements.all? { |term| prep_state.include?(normalize.call(term)) } && normalize.call(generated_phase.to_s) == prep_state
  unresolved_topic = ["product choice: open question"]
  gate_blocks = lambda do |intent|
    d2_applies = !(d2_scoped && intent == "prepare_only")
    d3_applies = !(d3_ready_scope && intent == "prepare_only")
    map_applies = !(map_ready_scope && intent == "prepare_only")
    sufficiency_applies = !(sufficiency_scoped && intent == "prepare_only")
    {
      "D_REQUIREMENTS_SUFFICIENCY" => ["material product choice", "controlling-source conflict"].any? && sufficiency_applies,
      "D2" => unresolved_topic.any? && d2_applies,
      "D3" => unresolved_topic.any? && d3_applies,
      "D_REQUIREMENT_ACCEPTANCE_MAP" => unresolved_topic.any? && map_applies
    }
  end
  preparation = gate_blocks.call("prepare_only")
  preparation["D_ARCHITECTURE_DECISION_PACK"] = unresolved_topic.any? &&
    !(pack_resolution_scoped && pack_retains_open && pack_condition_preserved)
  end_to_end = gate_blocks.call("end_to_end")
  end_to_end["D_ARCHITECTURE_DECISION_PACK"] = unresolved_topic.any?
  implement_only = gate_blocks.call("implement_only")
  implement_only["D_ARCHITECTURE_DECISION_PACK"] = unresolved_topic.any?
  result_valid = pack_resolution_scoped && pack_retains_open && pack_keeps_integrity &&
    pack_condition_preserved && pack_failure_scoped && prepare_questions_retained && execution_questions_resolved &&
    d2_scoped && map_ready_scope && map_retains_open && d3_ready_scope &&
    defaults_consistency && d3_retains_open && map_is_still_required && map_trigger_preserved &&
    source_allows_preparation && sufficiency_scoped && sufficiency.fetch("check") == sufficiency_check &&
    sufficiency.fetch("on_fail") == sufficiency_failure && preparation.values.none? &&
    end_to_end["D_ARCHITECTURE_DECISION_PACK"] && implement_only["D_ARCHITECTURE_DECISION_PACK"] &&
    %w[D_REQUIREMENTS_SUFFICIENCY D2 D3 D_REQUIREMENT_ACCEPTANCE_MAP].all? { |id| end_to_end[id] && implement_only[id] }
  exit(result_valid ? 0 : 1)
' "$phase_gates" "$phases" "$discover_view" "$workflow_dir/references/architecture-decision-pack.md"; then
    pass
else
    fail "prepare-only Discover cannot complete with recorded open decisions while execution intents remain gated"
fi

test_start "optional preparation readiness Plan retains pending decisions through entry and exit"
if ruby -ryaml -e '
  source = File.read(ARGV.fetch(0))
  view = File.read(ARGV.fetch(1))
  normalize = ->(value) { value.downcase.delete(96.chr).gsub(/\s+/, " ") }
  plan = source[/^## Phase: Plan.*?(?=^## Phase: Design)/m]
  entry = plan.to_s.lines.find { |line| line.start_with?("**Entry rule:") }
  scoped = entry && entry.include?("For `execution_intent != prepare_only`,")
  freshness = entry && entry.include?("Architecture Decision Pack must also be fresh")
  preparation = plan.to_s.include?("For `prepare_only`, an explicitly requested readiness Plan is inline and never waits.")
  pack_questions_retained = normalize.call(plan.to_s).include?("unresolved pack questions") &&
    normalize.call(plan.to_s).include?("feature_preparation_result.open_decisions") &&
    normalize.call(plan.to_s).include?("optional plan never waits")
  generated_pack_questions_retained = normalize.call(view).include?("unresolved pack questions") &&
    normalize.call(view).include?("feature_preparation_result.open_decisions")
  pending_allowed = scoped && preparation && pack_questions_retained && generated_pack_questions_retained
  dependent_blocked = entry && entry.downcase.include?("do not enter plan while the saved clarification state is pending")
  mirror = view.include?(entry.to_s.strip) && view.include?("For `prepare_only`, an explicitly requested readiness Plan is inline and never waits.")
  gates = YAML.load_file(ARGV.fetch(2)).fetch("gates")
  p8 = gates.find { |gate| gate["phase"] == "PLAN" }.fetch("exit_assertions").find { |assertion| assertion["id"] == "P8" }.fetch("check")
  common_defaults = p8.include?("clarification_defaults_applied is explicit (true/false)")
  execution_ready = p8.include?("execution_intent != prepare_only requires ready/empty topics")
  preparation_retained = p8.include?("prepare_only preserves pending state/topics in feature_preparation_result.open_decisions")
  exit(pending_allowed && dependent_blocked && freshness && mirror && common_defaults && execution_ready && preparation_retained ? 0 : 1)
' "$phases" "$workflow_dir/references/phases/plan.md" "$phase_gates"; then
    pass
else
    fail "readiness Plan contradicts preserved pending preparation state or loses execution/freshness guards"
fi

test_start "Discover and selected no-Plan Build gates enforce positive sufficiency and partial-answer readiness"
if ruby -ryaml -e '
  gates = YAML.load_file(ARGV.fetch(0)).fetch("gates")
  phases = File.read(ARGV.fetch(1))
  selector = YAML.load_file(ARGV.fetch(2)).fetch("load_sets").fetch("current_phase").fetch("selectors").find do |item|
    item["id"] == "workflow-current-phase-gate"
  end
  generated = File.read(ARGV.fetch(3))
  normalized = ->(value) { value.downcase.gsub(/\s+/, " ") }
  select_phase = lambda do |phase|
    next nil unless selector && selector.fetch("allowed_names").include?(phase)
    gates.find { |gate| gate["phase"] == phase }
  end
  discover_gate = select_phase.call("DISCOVER")
  build_gate = select_phase.call("BUILD")
  discover = discover_gate && discover_gate.fetch("exit_assertions").find { |item| item["id"] == "D_REQUIREMENTS_SUFFICIENCY" }
  d2 = discover_gate && discover_gate.fetch("exit_assertions").find { |item| item["id"] == "D2" }
  build = build_gate && build_gate.fetch("entry_assertions").find { |item| item["id"] == "B_REQUIREMENTS_SUFFICIENCY" }
  discover_phase = phases[/^## Phase: Discover.*?(?=^## Phase: Decompose)/m]
  generated_phase = generated[/^## Phase: Discover.*?(?=^## Phase: Decompose)/m]
  source_state = discover_phase && discover_phase[/^\*\*Clarification state rules:\*\*.*?(?=^\*\*Rules:\*\*)/m]
  generated_state = generated[/^\*\*Clarification state rules:\*\*.*?(?=^\*\*Rules:\*\*)/m]
  d_check = "Dependent work requires references/phases.md sufficiency; block guesses and controlling-source gaps/conflicts."
  d2_check = "clarification_status=ready; each implementation-shaping field is explicit, source-backed-defaulted, accepted from displayed recommendations, or resolved; approval alone never resolves choices."
  tick = 96.chr
  d2_fail = "Follow Discover step 5. Partial answers resolve answered topics only; defaults accepts displayed recommendations."
  expected_build = "plan_mode=none: revalidate fresh Discover sufficiency before Build; criteria carry confirmed answers and sourced defaults, not guessed choices or evidence_gap/source_conflict."
  required = [
    "requested intent",
    "applicable authoritative behavior",
    "source-backed technical defaults",
    "proposed product assumptions",
    "unresolved choices",
    "record topic, value, source, and rationale",
    "new material product choices require a concrete question and explicit answer before dependent work",
    "missing plumbing, convention, reversibility, recommendation, or Plan approval alone does not establish intent",
    "explicit acceptance of a clearly presented choice is an answer",
    "empty question list alone is not proof",
    "partial answers resolve only answered choices",
    "record confirmed answers in existing acceptance criteria before dependent edits",
    "repeat for newly exposed choices",
    "existing-policy and complete tasks need no ritual questions",
    "missing or conflicting controlling authority remains evidence_gap/source_conflict",
    "do not invent or reframe it as a product question"
  ]
  selector_valid = selector &&
    selector.fetch("path") == "contracts/phase-gates.yaml" &&
    selector.fetch("section") == "gates" &&
    selector.fetch("key") == "phase" &&
    selector.fetch("name_from") == "active_workflow_phase" &&
    selector.fetch("allowed_names").include?("DISCOVER") &&
    selector.fetch("allowed_names").include?("BUILD")
  source_rules = [
    ["ready only if no unresolved material topics remain", 2],
    ["otherwise retain remaining topics and set clarification status: needs_clarification", 2],
    ["clear only answered topics", 2],
    ["one or more open question ids", 1]
  ]
  phase_source = phases.delete("`").downcase.gsub(/\s+/, " ")
  generated_source = generated.delete("`").downcase.gsub(/\s+/, " ")
  transition_valid = source_rules.all? do |rule, count|
    phase_source.scan(rule).length == count && generated_source.scan(rule).length == count
  end
  discover_body = normalized.call(discover_phase.to_s)
  valid = selector_valid &&
    discover && discover.fetch("check") == d_check &&
    discover.fetch("on_fail").include?("Return to Discover") &&
    d2 && d2.fetch("check") == d2_check && d2.fetch("on_fail") == d2_fail &&
    build && build.fetch("condition") == "execution_intent != prepare_only and plan_mode == none" &&
    build.fetch("check") == expected_build &&
    build.fetch("on_fail") == "Stop Build; return to Discover for explicit answers or controlling-source resolution." &&
    required.all? { |term| discover_body.include?(normalized.call(term)) } &&
    source_state && generated_state && source_state == generated_state &&
    transition_valid
  exit(valid ? 0 : 1)
' "$phase_gates" "$phases" "$contract_index" "$discover_view"; then
    pass
else
    fail "selected Discover/Build gates or their bound sufficiency and partial-answer procedures are incomplete"
fi

test_start "Discover rejects contradictory preservation and default guidance"
if ruby -ryaml -e '
  phases = File.read(ARGV.fetch(0))
  generated = File.read(ARGV.fetch(1))
  contract = YAML.load_file(ARGV.fetch(2))
  gates = contract.fetch("gates")
  invariant = contract.fetch("invariants").find { |item| item["id"] == "INV_FEATURE_PREPARATION_QUESTION_ADMISSIBILITY" }
  feature_reference = File.read(ARGV.fetch(3))
  discover_gate = gates.find { |gate| gate["phase"] == "DISCOVER" }
  prep_gate = discover_gate.fetch("exit_assertions").find { |item| item["id"] == "D_FEATURE_PREPARATION_EVIDENCE" }
  discover_source = phases[/^## Phase: Discover.*?(?=^## Phase: Decompose)/m]
  discover_view = generated[/^## Phase: Discover.*?(?=^## Phase: Decompose|\z)/m]
  normalized = ->(value) { value.downcase.delete("`*").gsub(/\s+/, " ").gsub(/context, while a new audience/, "context; a new audience").gsub(/preserve established observable behavior/, "preserve existing observable behavior") }
  scoped_preservation = [
    "only within the actor, data, and authorization context supported by its sources",
    "adding a route does not itself change that context; a new audience or disclosure boundary may"
  ]
  provisional_fragments = ["unanswered material", "recommendation", "provisional", "response", "task journal", "do not record", "applied default", "confirmed criterion"]
  positive_controls = [
    "automatically apply only source-backed technical defaults",
    "existing-policy and complete tasks need no ritual questions"
  ]
  same_context_control = "for viewing without enabling editing"
  unsafe_rules = [
    "existing observable behavior is preserved unless explicitly changed",
    "existing observable behavior defaults to preservation unless explicitly changed",
    "a new route/scope is existing_behavior_to_preserve + implementation_gap",
    "apply every unanswered recommendation as a default",
    "apply unanswered product recommendations as defaults",
    "record each unanswered material choice as an applied default"
  ].map { |term| normalized.call(term) }
  policy_valid = lambda do |source_text, generated_text, gate_text, feature_text|
    source = normalized.call(source_text)
    generated = normalized.call(generated_text)
    gate = normalized.call(gate_text)
    feature = normalized.call(feature_text)
    combined = [source, generated, gate, feature].join(" ")
    generated == source &&
      scoped_preservation.all? { |term| source.include?(normalized.call(term)) } &&
      provisional_fragments.all? { |term| source.include?(normalized.call(term)) } &&
      positive_controls.all? { |term| source.include?(normalized.call(term)) } &&
      feature.include?(normalized.call(same_context_control)) &&
      scoped_preservation.all? { |term| gate.include?(normalized.call(term)) } &&
      provisional_fragments.all? { |term| gate.include?(normalized.call(term)) } &&
      unsafe_rules.none? { |term| combined.include?(term) }
  end
  gate = prep_gate.fetch("check") + " " + invariant.fetch("check")
  valid = prep_gate.fetch("check").include?("INV_FEATURE_PREPARATION_QUESTION_ADMISSIBILITY") && discover_source && discover_view && policy_valid.call(discover_source, discover_view, gate, feature_reference)
  safe_source = "#{scoped_preservation.join(" ")} #{provisional_fragments.join(" ")} #{positive_controls.join(" ")}"
  safe_gate = "#{scoped_preservation.join(" ")} #{provisional_fragments.join(" ")}"
  safe_feature = same_context_control
  safe_fixture = [safe_source, safe_source, safe_gate, safe_feature]
  admits_safe_fixture = policy_valid.call(*safe_fixture)
  rejects_contradictions = unsafe_rules.all? do |term|
    mutated = safe_fixture.map(&:dup)
    mutated[0] += " #{term}"
    mutated[1] += " #{term}"
    !policy_valid.call(*mutated)
  end
  exit(valid && admits_safe_fixture && rejects_contradictions ? 0 : 1)
' "$phases" "$discover_view" "$phase_gates" "$feature_ref"; then
    pass
else
    fail "Discover or its selected evidence gate broadens preservation or promotes unanswered recommendations"
fi

test_start "sufficiency evidence uses existing maps and journal rationale without question-count shortcuts"
if ruby -ryaml -e '
  output = YAML.load_file(ARGV.fetch(0))
  map = output.fetch("artifacts").find { |artifact| artifact["name"] == "requirement_acceptance_map" }
  map_ref = File.read(ARGV.fetch(1))
  journal = File.read(ARGV.fetch(2))
  fields = map.fetch("object_fields").map { |field| field.fetch("name") }
  normalized = ->(value) { value.downcase.gsub(/\s+/, " ") }
  map_validation = normalized.call(map.fetch("validation"))
  valid = fields.include?("assumptions_and_defaults") &&
    fields.include?("open_material_questions") &&
    map_validation.include?("sufficiency basis") &&
    map_validation.include?("empty open_material_questions list alone") &&
    normalized.call(map_ref).include?("empty list of questions alone is not evidence of sufficiency") &&
    normalized.call(map_ref).include?("partial answers resolve only answered choices") &&
    normalized.call(map_ref).include?("confirmed answers in existing acceptance criteria before dependent implementation") &&
    normalized.call(journal).include?("clarification admissibility") &&
    normalized.call(journal).include?("sufficiency basis") &&
    normalized.call(journal).include?("rationale: [why this default is justified by its source")
  exit(valid ? 0 : 1)
' "$output" "$map_ref" "$journal"; then
    pass
else
    fail "map and journal do not retain a proportionate positive sufficiency basis"
fi

test_start "feature preparation validates every evidence row and typed product-choice boundary"
if ruby -ryaml -e '
  output = YAML.load_file(ARGV.fetch(0))
  artifact = output.fetch("artifacts").find { |item| item["name"] == "feature_preparation_evidence" }
  contract = artifact.fetch("validation")
  normalized = ->(value) { value.downcase.gsub(/\s+/, " ") }
  required = [
    "Every row traces generic requirements",
    "design evidence",
    "not_applicable/unavailable disposition",
    "current implementation/observable execution behavior",
    "typed inspection gap",
    "behavioral tests/assertions",
    "inspected absence/access gap",
    "conflict analysis",
    "evidence gaps",
    "rationale",
    "implementation implication",
    "Product questions require implementation/test inspection",
    "requirements/design omission insufficient",
    "existing behavior defaults to preservation only within the actor, data, and authorization context supported by its sources",
    "a new audience or disclosure boundary may change that context, and unanswered choices remain unresolved with recommendations provisional in both the response and task journal",
    "Uninspected/inaccessible evidence: evidence_gap",
    "contradictions require both source_conflict and source_conflict_resolution",
    "route/scope adaptation is classified as existing_behavior_to_preserve plus implementation_gap only when the source-supported actor, data, and authorization context remains the same",
    "Sufficiency classifies requested intent",
    "applicable authoritative behavior",
    "justified technical defaults",
    "proposed product assumptions",
    "unresolved material choices from rows",
    "empty questions alone insufficient",
    "Missing/conflicting authority blocks dependent work as evidence_gap/source_conflict until resolved"
  ]
  valid = required.all? { |term| normalized.call(contract).include?(normalized.call(term)) }
  exit(valid ? 0 : 1)
' "$output"; then
    pass
else
    fail "feature-preparation validation omits evidence-row obligations or typed sufficiency controls"
fi

test_start "planning and Build handoffs carry confirmed criteria instead of reopening or guessing them"
if ruby -ryaml -e '
  handoffs = YAML.load_file(ARGV.fetch(0)).fetch("handoffs")
  decompose = handoffs.find { |item| item["name"] == "orchestrator_to_architect_decompose" }
  plan = handoffs.find { |item| item["name"] == "orchestrator_to_architect" }
  writer = handoffs.find { |item| item["name"] == "orchestrator_to_code_writer" }
  field = lambda do |handoff, name|
    handoff.fetch("context_fields").find { |item| item["name"] == name }
  end
  map_fields = [field.call(decompose, "requirement_acceptance_map"), field.call(plan, "requirement_acceptance_map")]
  plan_text = field.call(writer, "plan")
  required = [
    "sufficiency basis",
    "confirmed answers",
    "existing acceptance criteria",
    "before dependent implementation"
  ]
  valid = map_fields.all? do |map_field|
      map_field && required.all? { |term| map_field.fetch("description").include?(term) }
    end &&
    plan_text && required.all? { |term| plan_text.fetch("validation").include?(term) }
  exit(valid ? 0 : 1)
' "$handoffs"; then
    pass
else
    fail "Architect and CodeWriter handoffs can lose sufficiency evidence or confirmed acceptance criteria"
fi


test_start "entry, Discover, and Plan distinguish product choices from evidence-backed defaults"
if ruby -ryaml -e '
  skill = File.read(ARGV.fetch(0))
  phases = File.read(ARGV.fetch(1))
  generated = File.read(ARGV.fetch(2))
  controller = File.read(ARGV.fetch(3))
  plan = File.read(ARGV.fetch(4))
  gates = YAML.load_file(ARGV.fetch(5)).fetch("gates")
  normalized = ->(value) { value.downcase.gsub(/\s+/, " ") }
  discover = phases[/^\*\*Requirements sufficiency.*?(?=^\d+\.)/m]
  generated_discover = generated[/^\*\*Requirements sufficiency.*?(?=^\d+\.)/m]
  step5 = phases.lines.find { |line| line.start_with?("5. Preserve applicable authoritative existing behavior") }
  root_requirements = [
    "enter Discover requirements check",
    "Explicit user or repository artifact schemas override workflow-internal shapes",
    "Apply source-backed defaults and ask precise questions for material product choices",
    "Plan approval cannot settle intent",
    "assistant-clarify owns prompt-level ambiguity"
  ]
  discover_requirements = [
    "ready work needs a sufficient intended outcome and material product behavior",
    "before Plan or plan_mode=none dependent work",
    "before treating a material product outcome as settled in progress, Plan, or dependent implementation",
    "whether the request and applicable authority still leave materially different observable outcomes open",
    "ask only about that remaining material choice; compatibility alone does not select intent",
    "Keep technical alternatives that achieve the accepted outcome automatic",
    "provisional options or recommendations open during discovery",
    "Use existing inline criteria, the Requirement Acceptance Map, or carried state to distinguish the requested outcome from constraints",
    "inspect task-relevant behavior, affected data/users, dependencies, likely failures, and acceptance implications",
    "classify material points as requested intent, applicable authoritative behavior, source-backed technical defaults, proposed product assumptions, or unresolved choices",
    "missing or conflicting controlling authority remains evidence_gap/source_conflict",
    "do not invent or reframe it as a product question",
    "empty question list alone is not proof",
    "partial answers resolve only answered choices",
    "record confirmed answers in existing acceptance criteria before dependent edits",
    "repeat for newly exposed choices",
    "existing-policy and complete tasks need no ritual questions",
    "no parallel report or ledger"
  ]
  step5_requirements = [
    "automatically apply only source-backed technical defaults",
    "record topic, value, source, and rationale",
    "new material product choices require a concrete question and explicit answer before dependent work",
    "missing plumbing, convention, reversibility, recommendation, or Plan approval alone does not establish intent",
    "explicit acceptance of a clearly presented choice is an answer",
    "ask other admissible unresolved questions by topic",
    "there is no numeric question cap"
  ]
  controller_requirements = [
    "before Plan or plan_mode=none dependent work, confirm a sufficient intended outcome and material behavior",
    "use references/phases.md step 5 for defaults and choice answers",
    "missing or conflicting controlling authority remains evidence_gap/source_conflict",
    "an empty question list alone is not proof",
    "record the basis in existing criteria/map and task journal or carried state"
  ]
  controller_state_requirements = [
    "preserve applicable authoritative behavior and apply only source-backed technical defaults automatically",
    "do not confirm it",
    "defaults accepts displayed recommendations only when a response was required"
  ]
  assumption_line = plan.lines.find { |line| line.start_with?("- Assumed (not explicitly asked):") }
  expected_assumption = "- Assumed (not explicitly asked): [only source-backed technical defaults or applicable authoritative behavior, with source and rationale; no unanswered new material product choices]"
  discover_gate = gates.find { |gate| gate["phase"] == "DISCOVER" }
  discover_check = discover_gate && discover_gate.fetch("exit_assertions").find { |item| item["id"] == "D_REQUIREMENTS_SUFFICIENCY" }
  d2 = discover_gate && discover_gate.fetch("exit_assertions").find { |item| item["id"] == "D2" }
  d3a = discover_gate && discover_gate.fetch("exit_assertions").find { |item| item["id"] == "D3A" }
  build_gate = gates.find { |gate| gate["phase"] == "BUILD" }
  build_check = build_gate && build_gate.fetch("entry_assertions").find { |item| item["id"] == "B_REQUIREMENTS_SUFFICIENCY" }
  plan_approval = "Plan approval alone does not settle an unanswered product choice; an explicit answer that accepts a clearly presented choice resolves it without ritual reconfirmation."
  d_check = "Dependent work requires references/phases.md sufficiency; block guesses and controlling-source gaps/conflicts."
  d2_check = "clarification_status=ready; each implementation-shaping field is explicit, source-backed-defaulted, accepted from displayed recommendations, or resolved; approval alone never resolves choices."
  d2_fail = "Follow Discover step 5. Partial answers resolve answered topics only; defaults accepts displayed recommendations."
  b_check = "plan_mode=none: revalidate fresh Discover sufficiency before Build; criteria carry confirmed answers and sourced defaults, not guessed choices or evidence_gap/source_conflict."
  phase_state = phases[/^\*\*Clarification state rules:\*\*.*?(?=^\*\*Rules:\*\*)/m]
  generated_state = generated[/^\*\*Clarification state rules:\*\*.*?(?=^\*\*Rules:\*\*)/m]
  transition_rules = [
    ["ready only if no unresolved material topics remain", 2],
    ["otherwise retain remaining topics and set clarification status: needs_clarification", 2],
    ["clear only answered topics", 2],
    ["one or more open question ids", 1]
  ]
  tick = 96.chr
  phase_source = phases.delete(tick).downcase.gsub(/\s+/, " ")
  generated_source = generated.delete(tick).downcase.gsub(/\s+/, " ")
  transitions_match = transition_rules.all? do |rule, count|
    phase_source.scan(rule).length == count && generated_source.scan(rule).length == count
  end
  valid = root_requirements.all? { |term| normalized.call(skill).include?(normalized.call(term)) } &&
    discover && generated_discover && discover_requirements.all? { |term| normalized.call(discover).include?(normalized.call(term)) } &&
    normalized.call(generated_discover) == normalized.call(discover) &&
    step5 && step5_requirements.all? { |term| normalized.call(step5).include?(normalized.call(term)) } &&
    controller_requirements.all? { |term| normalized.call(controller).include?(normalized.call(term)) } &&
    controller_state_requirements.all? { |term| normalized.call(controller).include?(normalized.call(term)) } &&
    normalized.call(assumption_line.to_s.strip) == normalized.call(expected_assumption) &&
    normalized.call(plan).include?(normalized.call(plan_approval)) &&
    discover_check && discover_check.fetch("check") == d_check &&
    discover_check.fetch("on_fail").include?("ask about material choices") &&
    d2 && d2.fetch("check") == d2_check && d2.fetch("on_fail") == d2_fail &&
    d3a && d3a.fetch("check").include?("never default new material choices") &&
    build_check && build_check.fetch("condition") == "execution_intent != prepare_only and plan_mode == none" &&
    build_check.fetch("check") == b_check &&
    build_check.fetch("on_fail") == "Stop Build; return to Discover for explicit answers or controlling-source resolution." &&
    phase_state && generated_state && phase_state == generated_state && transitions_match
  exit(valid ? 0 : 1)
' "$workflow_dir/SKILL.md" "$phases" "$discover_view" "$workflow_dir/references/workflow-controller.md" "$workflow_dir/references/plan-template.md" "$phase_gates"; then
    pass
else
    fail "entry, Discover, gates, and Plan do not share the explicit product-choice boundary"
fi


test_start "selected Decompose and Plan gates require positive sufficiency before dependent work"
if ruby -ryaml -e '
  root = YAML.load_file(ARGV.fetch(0))
  index = YAML.load_file(ARGV.fetch(1))
  selector = index.fetch("load_sets").fetch("current_phase").fetch("selectors").find { |item| item["id"] == "workflow-current-phase-gate" }
  valid = lambda do |candidate|
    selector && %w[DECOMPOSE PLAN].all? do |phase|
      gate = candidate.fetch("gates").find { |item| item["phase"] == phase }
      prefix, action = phase == "DECOMPOSE" ? ["DC", "decomposition"] : ["P", "planning"]
      entries = gate && gate.fetch("entry_assertions", []).select { |item| item["id"] == "#{prefix}_REQUIREMENTS_SUFFICIENCY" }
      expected_check = "Before dependent #{action}, all applicable Discover exit assertions pass on current evidence, including D_REQUIREMENTS_SUFFICIENCY, D2, and the existing conditions for D_REQUIREMENT_ACCEPTANCE_MAP and D_FEATURE_PREPARATION_EVIDENCE. Compact criteria or carried state substitute only where those conditions permit. No unresolved material product choice or controlling-source evidence_gap/source_conflict remains; missing saved state is not readiness evidence."
      expected_failure = "Stop dependent #{action}; return to Discover and revalidate applicable exit assertions. Preserve unanswered topics and derive clarification status from their actual resolution. Technical defaults cover implementation details only; request missing or reconciled controlling authority. Do not fabricate ready or pending state to satisfy a gate."
      selector.fetch("allowed_names").include?(phase) && entries && entries.length == 1 &&
        entries.first.fetch("condition") == "execution_intent != prepare_only" &&
        entries.first.fetch("check") == expected_check && entries.first.fetch("on_fail") == expected_failure
    end
  end
  exit 1 unless valid.call(root)
  %w[DECOMPOSE PLAN].each do |phase|
    %w[missing moved_to_exit persisted_only unsafe_recovery omit_required_map omit_required_feature_evidence].each do |mutation|
      candidate = Marshal.load(Marshal.dump(root))
      gate = candidate.fetch("gates").find { |item| item["phase"] == phase }
      entry = gate.fetch("entry_assertions").find { |item| item["id"].end_with?("_REQUIREMENTS_SUFFICIENCY") }
      case mutation
      when "missing" then gate.fetch("entry_assertions").delete(entry)
      when "moved_to_exit"
        gate.fetch("entry_assertions").delete(entry)
        gate.fetch("exit_assertions") << entry
      when "persisted_only" then entry["condition"] = "clarification state was persisted"
      when "unsafe_recovery" then entry["on_fail"] = "Persist ready and clear unresolved topics."
      when "omit_required_map" then entry["check"] = entry.fetch("check").sub("D_REQUIREMENT_ACCEPTANCE_MAP", "optional map")
      when "omit_required_feature_evidence" then entry["check"] = entry.fetch("check").sub("D_FEATURE_PREPARATION_EVIDENCE", "optional evidence")
      end
      exit 1 if valid.call(candidate)
    end
  end
' "$phase_gates" "$contract_index"; then
    pass
else
    fail "selected Decompose/Plan entry checks permit missing readiness evidence or unsafe recovery"
fi

test_start "Decompose and Plan recovery preserves unresolved clarification until supported resolution"
if ruby -ryaml -e '
  gates = YAML.load_file(ARGV.fetch(0)).fetch("gates")
  expected = "Return to Discover and revalidate its applicable exit assertions against request/source/answer evidence. Preserve unanswered topics; needs_clarification requires unresolved material topics, while ready requires a sufficient basis and none remaining. Missing metadata alone does not create questions. Material product choices require explicit answers or accepted displayed choices; defaults cover only technical implementation details; controlling-source gaps/conflicts require missing or reconciled authority. Record clarification_defaults_applied from actual recorded defaults."
  valid = lambda do |candidate|
    {"DECOMPOSE" => "DC7", "PLAN" => "P8"}.all? do |phase, id|
      owner = candidate.find { |gate| gate["phase"] == phase }
      assertions = owner && owner.fetch("exit_assertions", []).select { |item| item["id"] == id }
      assertions && assertions.length == 1 && assertions.first.fetch("on_fail") == expected
    end
  end
  exit 1 unless valid.call(gates)
  %w[DC7 P8].each do |id|
    ["Persist ready and clear unanswered topics.", "Always set needs_clarification, even with no unresolved topic."].each do |unsafe|
      candidate = Marshal.load(Marshal.dump(gates))
      candidate.flat_map { |gate| gate.fetch("exit_assertions", []) }.find { |item| item["id"] == id }["on_fail"] = unsafe
      exit 1 if valid.call(candidate)
    end
    candidate = Marshal.load(Marshal.dump(gates))
    owner = candidate.find { |gate| gate.fetch("exit_assertions", []).any? { |item| item["id"] == id } }
    moved = owner.fetch("exit_assertions").find { |item| item["id"] == id }
    owner.fetch("exit_assertions").delete(moved)
    other = candidate.find { |gate| gate["phase"] == (owner["phase"] == "PLAN" ? "DECOMPOSE" : "PLAN") }
    other.fetch("exit_assertions") << moved
    exit 1 if valid.call(candidate)
  end
' "$phase_gates"; then
    pass
else
    fail "DC7/P8 recovery can fabricate ready state instead of retaining unanswered topics"
fi

test_start "canonical clarification contracts restrict automatic defaults to sourced technical details"
if ruby -ryaml -e '
  fields = YAML.load_file(ARGV.fetch(0)).fetch("fields")
  journal = File.read(ARGV.fetch(1))
  validation = File.read(ARGV.fetch(0)).split(/^# Validation behavior:/, 2).last
  by_name = fields.to_h { |field| [field.fetch("name"), field] }
  expected_shapes = {
    "clarification_status" => ["enum", true, nil],
    "clarification_admissibility" => ["enum", false, "not_applicable"],
    "unresolved_clarification_topics" => ["string[]", true, []],
    "clarification_defaults_applied" => ["boolean", true, false],
    "clarification_defaults" => ["object[]", true, []]
  }
  shapes_valid = expected_shapes.all? do |name, (type, required, default)|
    field = by_name[name]
    field && field["type"] == type && field["required"] == required && field["default"] == default
  end
  defaults = by_name.fetch("clarification_defaults")
  defaults_applied = by_name.fetch("clarification_defaults_applied")
  defaults_object_fields = defaults.fetch("object_fields").map { |field| field.fetch("name") }
  status = by_name.fetch("clarification_status")
  admissibility = by_name.fetch("clarification_admissibility")
  required = [
    status.fetch("validation"), status.fetch("infer_from"),
    admissibility.fetch("validation"), defaults.fetch("description"),
    defaults.fetch("validation"), defaults_applied.fetch("description"),
    defaults_applied.fetch("validation"), validation, journal
  ].join(" ").downcase.gsub(/[`*]/, "").gsub(/\s+/, " ")
  required_phrases = [
    "source-backed technical default",
    "material product choice",
    "explicit acceptance of a displayed recommendation",
    "explicit answers",
    "convention or reversibility alone",
    "source and rationale",
    "not an automatic default"
  ]
  valid = shapes_valid && defaults_object_fields == %w[topic value source rationale] &&
    required_phrases.all? { |phrase| required.include?(phrase) } &&
    defaults.fetch("object_fields").find { |field| field["name"] == "source" }.fetch("description").downcase.include?("technical default") &&
    defaults.fetch("object_fields").find { |field| field["name"] == "rationale" }.fetch("description").downcase.include?("product choice") &&
    !defaults.fetch("object_fields").find { |field| field["name"] == "source" }.fetch("description").downcase.include?("stable local convention")
  exit(valid ? 0 : 1)
' "$input_contract" "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md"; then
    pass
else
    fail "input and journal contracts still allow conventions or reversibility to auto-settle material product choices"
fi

p0p4_finish_suite "$BASH_SOURCE"
