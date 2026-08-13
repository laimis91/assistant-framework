if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

contract_field_block() {
    local file="$1"
    local field="$2"
    awk -v field="$field" '
        $0 == "  - name: " field { inside = 1 }
        inside && /^  - name: / && $0 != "  - name: " field { exit }
        inside { print }
    ' "$file"
}

test_start "standalone architecture records can project complete typed review facts"
review_missing=()
review_input="$FRAMEWORK_DIR/skills/assistant-review/contracts/input.yaml"
review_handoffs="$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml"
review_required_block="$(contract_field_block "$review_input" architecture_decision_pack_review_required)"
review_pack_block="$(contract_field_block "$review_input" architecture_decision_pack)"
for term in \
    'equivalent standalone architecture decision record' \
    'or a decision record that makes memory, performance, extensibility, public interface, data lifecycle, ownership, or'; do
    if ! grep -Fq -- "$term" <<<"$review_required_block"; then review_missing+=("review trigger: $term"); fi
done
for term in \
    'on_missing: infer' \
    'Only for standalone review with an equivalent decision record, derive its compact Pack projection from the supplied record' \
    'If a workflow Pack is required but absent' \
    '      - name: facts' \
    '          - name: claim' \
    '      - name: assumptions' \
    '          - name: statement' \
    '          - name: rationale_or_impact' \
    '      - name: material_questions' \
    '          - name: topic' \
    '          - name: why_needed' \
    '          - name: risk_if_guessed' \
    '          - name: recommended_default_or_none' \
    '      - name: independent_challenge_evidence' \
    '        on_missing: fail' \
    '          - name: challenge_ref' \
    '          - name: dissent_or_validation' \
    '          - name: resolution' \
    '          - name: selected_design_impact'; do
    if ! grep -Fq -- "$term" <<<"$review_pack_block"; then review_missing+=("Pack projection: $term"); fi
done
if ! grep -Fq -- 'standalone equivalent records derive its compact Pack projection' "$review_handoffs"; then
    review_missing+=("Reviewer handoff derivation rule")
fi
if [[ ${#review_missing[@]} -eq 0 ]]; then pass; else fail "assistant-review Pack projection gaps: ${review_missing[*]}"; fi

p0p4_reference_section_has_term() {
    local file="$1"
    local heading="$2"
    local term="$3"

    awk -v heading="$heading" -v term="$term" '
        $0 == heading { in_section = 1; next }
        in_section && /^## / { exit }
        in_section && index($0, term) { found = 1; exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

review_skill="$FRAMEWORK_DIR/skills/assistant-review/SKILL.md"
review_checklists="$FRAMEWORK_DIR/skills/assistant-review/references/review-checklists.md"
review_loop="$FRAMEWORK_DIR/skills/assistant-review/references/review-loop.md"
review_index="$FRAMEWORK_DIR/skills/assistant-review/contracts/index.yaml"
review_phase_gates="$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml"
review_rubric="$FRAMEWORK_DIR/skills/assistant-review/references/review-rubric.md"
review_evals="$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json"

test_start "assistant-review applies mandatory review checklists from reference"
review_checklist_failures=()

if [[ ! -f "$review_checklists" ]]; then
    review_checklist_failures+=("skills/assistant-review/references/review-checklists.md missing")
fi

for inline_heading in \
    "## Agentic Loop Safety Checklist" \
    "## Behavioral Contract Review Checklist" \
    "## Semantic Contract Review Checklist"; do
    if grep -Fqx "$inline_heading" "$review_skill"; then
        review_checklist_failures+=("skills/assistant-review/SKILL.md still has inline section $inline_heading")
    fi
done

for file_and_term in \
    "$review_skill::references/review-checklists.md" \
    "$review_skill::fresh Reviewer context bundle points to \`references/review-checklists.md\`" \
    "$review_skill::load \`references/review-loop.md\` before the first REVIEW step" \
    "$review_loop::only triggered sections from \`references/review-checklists.md\`" \
    "$review_index::references/review-checklists.md" \
    "$review_skill::Agentic Loop Safety Checklist" \
    "$review_skill::Behavioral Contract Review Checklist" \
    "$review_skill::Semantic Contract Review Checklist" \
    "$review_skill::Architecture Decision Pack Review Checklist" \
    "$review_evals::review-checklists-reference-is-mandatory" \
    "$review_evals::references/review-checklists.md" \
    "$review_evals::Agentic Loop Safety Checklist" \
    "$review_evals::Behavioral Contract Review Checklist" \
    "$review_evals::Semantic Contract Review Checklist" \
    "$review_evals::bounded execution" \
    "$review_evals::interface-implementation alignment" \
    "$review_evals::template-contract alignment"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq "$term" "$file"; then
        review_checklist_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done

if [[ -f "$review_checklists" ]]; then
    for section_and_term in \
        "## Agentic Loop Safety Checklist::Bounded execution" \
        "## Agentic Loop Safety Checklist::Stop condition" \
        "## Agentic Loop Safety Checklist::empty-result" \
        "## Agentic Loop Safety Checklist::Tool-error handling" \
        "## Agentic Loop Safety Checklist::Progress/stagnation detection" \
        "## Agentic Loop Safety Checklist::Cost/token guardrails" \
        "## Agentic Loop Safety Checklist::Low-confidence escalation" \
        "## Behavioral Contract Review Checklist::Existing behavior and invariants" \
        "## Behavioral Contract Review Checklist::Interface-implementation alignment" \
        "## Behavioral Contract Review Checklist::Test inheritance coverage" \
        "## Behavioral Contract Review Checklist::External protocol / algorithm fidelity" \
        "## Behavioral Contract Review Checklist::High-impact operation guards" \
        "## Behavioral Contract Review Checklist::Runtime surface sync" \
        "## Semantic Contract Review Checklist::Inherited contract obligations" \
        "## Semantic Contract Review Checklist::Template-contract alignment" \
        "## Semantic Contract Review Checklist::Eval coverage inheritance" \
        "## Semantic Contract Review Checklist::External-method signature fidelity" \
        "## Semantic Contract Review Checklist::High-stakes recommendation guard" \
        "## Semantic Contract Review Checklist::Mirror surfaces"; do
        section="${section_and_term%%::*}"
        term="${section_and_term#*::}"
        if ! p0p4_reference_section_has_term "$review_checklists" "$section" "$term"; then
            review_checklist_failures+=("skills/assistant-review/references/review-checklists.md $section missing $term")
        fi
    done
fi

if [[ "${#review_checklist_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review mandatory review checklist reference is incomplete: ${review_checklist_failures[*]}"
fi

test_start "assistant-review checks applicable Architecture Decision Packs"
architecture_pack_review_failures=()
for file_and_term in \
    "$review_checklists::## Architecture Decision Pack Review Checklist" \
    "$review_checklists::Freshness, facts, and material questions" \
    "$review_checklists::Ownership, dependency, and lifecycle boundary" \
    "$review_checklists::Design-pressure checks" \
    "$review_checklists::Semantic type ledger and primitive exceptions" \
    "$review_checklists::Falsifiable quality scenarios" \
    "$review_checklists::Compatibility, extension, and verification handoff" \
    "$review_index::architecture_decision_pack_review_required" \
    "$review_phase_gates::RS10" \
    "$review_evals::architecture-decision-pack-review-is-fresh-and-falsifiable"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        architecture_pack_review_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
for section_and_term in \
    "## Architecture Decision Pack Review Checklist::Freshness, facts, and material questions" \
    "## Architecture Decision Pack Review Checklist::Design-pressure checks" \
    "## Architecture Decision Pack Review Checklist::Semantic type ledger and primitive exceptions" \
    "## Architecture Decision Pack Review Checklist::Falsifiable quality scenarios" \
    "## Architecture Decision Pack Review Checklist::Compatibility, extension, and verification handoff"; do
    section="${section_and_term%%::*}"
    term="${section_and_term#*::}"
    if ! p0p4_reference_section_has_term "$review_checklists" "$section" "$term"; then
        architecture_pack_review_failures+=("skills/assistant-review/references/review-checklists.md $section missing $term")
    fi
done
if [[ ${#architecture_pack_review_failures[@]} -eq 0 ]]; then
    pass
else
    fail "assistant-review Architecture Decision Pack reference is incomplete: ${architecture_pack_review_failures[*]}"
fi

test_start "assistant-review binds Pack review to the canonical architecture mode"
architecture_pack_mode_consumer_failures=()
review_output="$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml"
if ! ruby -ryaml -e '
    input = YAML.load_file(ARGV.fetch(0))
    handoffs = YAML.load_file(ARGV.fetch(1))
    output = YAML.load_file(ARGV.fetch(2))
    index = YAML.load_file(ARGV.fetch(3))
    entry_names = index.fetch("load_sets").fetch("entry").fetch("selectors").find { |selector| selector["id"] == "review-entry-fields" }.fetch("names")
    input_fields = input.fetch("fields").to_h { |field| [field["name"], field] }
    canonical_mode = input_fields.fetch("architecture_design_mode")
    pack = input_fields.fetch("architecture_decision_pack")
    pack_fields = pack.fetch("object_fields").to_h { |field| [field["name"], field] }
    handoff = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_reviewer" }
    context = handoff.fetch("context_fields").to_h { |field| [field["name"], field] }
    reviewer_checks = handoff.fetch("return_fields").find { |field| field["name"] == "architecture_decision_pack_checks" }
    reviewer_challenge = reviewer_checks.fetch("object_fields").find { |field| field["name"] == "independent_challenge_evidence" }
    output_pack = output.fetch("artifacts").find { |artifact| artifact["name"] == "architecture_decision_pack_review" }
    output_challenge = output_pack.fetch("object_fields").find { |field| field["name"] == "independent_challenge_evidence" }
    valid = input["schema_version"] == "5.0" && handoffs["schema_version"] == "5.0" && output["schema_version"] == "5.0" && index["schema_version"] == "5.0" &&
      canonical_mode["required"] == "conditional" && canonical_mode["condition"] == "architecture_decision_pack_review_required is true" &&
      canonical_mode["enum_values"] == %w[lightweight required review_intensive] &&
      canonical_mode["on_missing"] == "infer" &&
      canonical_mode.fetch("infer_from").include?("standalone equivalent architecture decision record") &&
      canonical_mode.fetch("infer_from").include?("one local owner, dependency, type, or verification decision") &&
      canonical_mode.fetch("infer_from").include?("cross-boundary/public contract") &&
      canonical_mode.fetch("infer_from").include?("high-risk or conflicting drivers") &&
      canonical_mode.fetch("infer_from").include?("memory vs throughput") &&
      canonical_mode.fetch("infer_from").include?("irreversible public/data decision") &&
      canonical_mode.fetch("infer_from").include?("independent_challenge_evidence") &&
      canonical_mode.fetch("infer_from").include?("corroborate but must not determine") &&
      canonical_mode.fetch("infer_from").include?("workflow Pack or handoff") &&
      entry_names.include?("architecture_design_mode") &&
      pack_fields.fetch("mode")["validation"] == "Must equal canonical architecture_design_mode" &&
      pack_fields.fetch("independent_challenge_evidence")["condition"] == "architecture_design_mode == review_intensive" &&
      context.fetch("architecture_design_mode")["required"] == "conditional" && context.fetch("architecture_design_mode")["condition"] == "architecture_decision_pack_review_required is true" &&
      context.fetch("architecture_design_mode")["enum_values"] == %w[lightweight required review_intensive] &&
      reviewer_challenge["condition"] == "architecture_design_mode == review_intensive" &&
      output_challenge["condition"] == "architecture_design_mode == review_intensive"
    exit valid ? 0 : 1
' "$review_input" "$review_handoffs" "$review_output" "$review_index"; then
    architecture_pack_mode_consumer_failures+=("canonical input, Reviewer context, and output Pack mode binding")
fi
if ! jq -e '
    .cases[] | select(.id == "standalone-architecture-record-derives-review-projection") |
    (.setup_context | any(. == "No workflow architecture_design_mode is supplied; the standalone record must normalize review_intensive from its high-risk/conflicting drivers before treating independent challenge evidence as corroboration.")) and
    (.expected_behavior | any(. == "Infers canonical architecture_design_mode=review_intensive from the standalone record\u0027s high-risk/conflicting drivers, keeps architecture_decision_pack.mode=architecture_design_mode, and treats independent challenge evidence as corroboration rather than the mode determinant.")) and
    (.machine_expectations.required_substrings | index("architecture_design_mode=review_intensive")) and
    (.machine_expectations.required_substrings | index("architecture_decision_pack.mode=architecture_design_mode"))
' "$review_evals" >/dev/null; then
    architecture_pack_mode_consumer_failures+=("standalone review eval does not prove review_intensive normalization")
fi
if ! jq -e '
    .cases[] | select(.id == "standalone-high-risk-record-without-challenge-remains-review-intensive") |
    (.setup_context | any(. == "The standalone ADR has conflicting memory-versus-throughput and irreversible public-data decision drivers, but no independent_challenge_evidence.")) and
    (.expected_behavior | any(. == "Infers architecture_design_mode=review_intensive from the ADR drivers before inspecting challenge evidence and does not downgrade to required.")) and
    (.expected_behavior | any(. == "Reports missing independent challenge evidence as a validation failure, finding, or blocker required by review_intensive mode.")) and
    (.machine_expectations.required_substrings | index("architecture_design_mode=review_intensive")) and
    (.machine_expectations.required_substrings | index("missing independent challenge evidence")) and
    (.machine_expectations.forbidden_substrings | index("architecture_design_mode=required"))
' "$review_evals" >/dev/null; then
    architecture_pack_mode_consumer_failures+=("standalone high-risk review eval does not retain review_intensive when challenge evidence is missing")
fi
if ! jq -e '
    .cases[] | select(.id == "standalone-high-risk-record-without-challenge-remains-review-intensive") |
    (.prompt | contains("Return exactly one valid JSON object")) and
    (.machine_expectations.structured_json_assertions | length == 5) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"equals","path":["architecture_design_mode"],"expected":"review_intensive"})) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"equals_path","path":["architecture_design_mode"],"other_path":["architecture_decision_pack","mode"]})) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"equals","path":["validation_result","status"],"expected":"blocked"})) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"equals","path":["validation_result","missing_field"],"expected":"independent_challenge_evidence"})) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"nonempty_string","path":["validation_result","evidence_or_gap"]}))
' "$review_evals" >/dev/null; then
    architecture_pack_mode_consumer_failures+=("standalone high-risk review eval is missing structured mode and blocked-validation assertions")
fi
adversarial_review_root="$(mktemp -d "${TMPDIR:-/tmp}/assistant-review-structured-adversary.XXXXXX")"
adversarial_review_responses="$adversarial_review_root/responses"
adversarial_review_output="$adversarial_review_root/grader.out"
p0p4_register_cleanup "$adversarial_review_root"
mkdir -p "$adversarial_review_responses/assistant-review"
while IFS= read -r adversarial_case_id; do
    adversarial_response_path="$adversarial_review_responses/assistant-review/$adversarial_case_id.txt"
    adversarial_required_summary="$(jq -r --arg id "$adversarial_case_id" '.cases[] | select(.id == $id) | .machine_expectations.required_substrings[]' "$review_evals" | paste -sd ' ' -)"
    if [[ "$adversarial_case_id" == "standalone-high-risk-record-without-challenge-remains-review-intensive" ]]; then
        jq -n --arg summary "$adversarial_required_summary" '{summary: $summary, architecture_design_mode: "required", architecture_decision_pack: {mode: "required"}, validation_result: {status: "accepted", missing_field: "none", evidence_or_gap: "challenge evidence is accepted"}}' >"$adversarial_response_path"
    else
        printf '%s\n' "$adversarial_required_summary" >"$adversarial_response_path"
    fi
done < <(jq -r '.cases[].id' "$review_evals")
if "$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$adversarial_review_responses" --skill assistant-review >"$adversarial_review_output" 2>&1; then
    architecture_pack_mode_consumer_failures+=("adversarial standalone ADR grader response passed")
elif ! grep -Fq $'FAIL\tassistant-review\tstandalone-high-risk-record-without-challenge-remains-review-intensive' "$adversarial_review_output" \
    || ! grep -Fq "structured JSON assertion failure" "$adversarial_review_output"; then
    architecture_pack_mode_consumer_failures+=("adversarial standalone ADR grader response did not fail structured assertions")
fi
for file_and_term in \
    "$review_skill::Migration note: assistant-review contracts are v5" \
    "$review_phase_gates::architecture_design_mode" \
    "$review_handoffs::architecture_decision_pack.mode must equal canonical architecture_design_mode"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        architecture_pack_mode_consumer_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
if [[ ${#architecture_pack_mode_consumer_failures[@]} -eq 0 ]]; then
    pass
else
    fail "assistant-review canonical Pack mode consumer gaps: ${architecture_pack_mode_consumer_failures[*]}"
fi

test_start "assistant-review does not use rubric score alone to force round 3 or stronger claims"
review_threshold_failures=()

for file_and_forbidden in \
    "$review_skill::REFINE with zero findings -> EXIT CLEAN" \
    "$review_skill::Rubric score {score} is below target" \
    "$review_rubric::| 4-5 |"; do
    file="${file_and_forbidden%%::*}"
    forbidden="${file_and_forbidden#*::}"
    if [[ -f "$file" ]] && grep -Fq "$forbidden" "$file"; then
        review_threshold_failures+=("${file#$FRAMEWORK_DIR/}: still contains $forbidden")
    fi
done

for file_and_term in \
    "$review_loop::A score below the rubric threshold alone is insufficient to start round 3 or later." \
    "$review_loop::additional_round_reason" \
    "$review_phase_gates::Score below threshold alone is insufficient" \
    "$review_phase_gates::changed_files" \
    "$review_phase_gates::unresolved_finding" \
    "$review_phase_gates::validation_failure" \
    "$review_phase_gates::regression_or_drift" \
    "$review_phase_gates::changed_hypothesis" \
    "$review_rubric::A score below threshold alone does not authorize round 3 or later."; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq "$term" "$file"; then
        review_threshold_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done

if [[ "${#review_threshold_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review additional-round and evidence-bounded claim contract drifted: ${review_threshold_failures[*]}"
fi

test_start "assistant-review defaults to one audit pass and at most one post-fix re-review"
review_round_policy_failures=()
review_output="$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml"
review_handoffs="$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml"

for file_and_term in \
    "$review_skill::Audit mode stops after one review pass." \
    "$review_skill::initial review, fixes and validation, then one fresh re-review" \
    "$review_loop::Audit mode exits after round 1" \
    "$review_loop::The normal review-fix path is round 1 review, fixes and validation, then one fresh round 2 re-review." \
    "$review_loop::Round 3+ requires a recorded" \
    "$review_handoffs::- name: additional_round_reason" \
    "$review_handoffs::condition: \"round >= 3\"" \
    "$review_output::- name: additional_round_reasons" \
    "$review_output::condition: \"rounds >= 3\"" \
    "$review_evals::bounded-review-default-rounds" \
    "$review_evals::audit-one-pass" \
    "$review_evals::additional_round_reason"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        review_round_policy_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done

if [[ "${#review_round_policy_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review default round policy is incomplete: ${review_round_policy_failures[*]}"
fi

test_start "assistant-review final no-finding claim is evidence-bounded and role-separated"
review_claim_failures=()
bounded_claim="No material findings within the reviewed scope and available evidence"

for file_and_term in \
    "$review_skill::$bounded_claim" \
    "$review_loop::$bounded_claim" \
    "$review_output::- name: evidence_bounded_claim" \
    "$review_output::$bounded_claim" \
    "$FRAMEWORK_DIR/agents/codex/code-reviewer.toml::$bounded_claim" \
    "$FRAMEWORK_DIR/agents/claude/code-reviewer.md::$bounded_claim" \
    "$review_skill::QA evaluation separate from code review" \
    "$FRAMEWORK_DIR/agents/codex/code-reviewer.toml::Do not replace the separate QA Evaluator" \
    "$FRAMEWORK_DIR/agents/claude/code-reviewer.md::Do not replace the separate QA Evaluator" \
    "$review_evals::evidence-bounded-review-claim" \
    "$review_evals::$bounded_claim"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        review_claim_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done

if [[ "${#review_claim_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review evidence-bounded claim or reviewer/QA role split is incomplete: ${review_claim_failures[*]}"
fi

test_start "assistant-review phase-gate IDs are unique"
phase_gate_id_failures=()
for phase_gate_file in \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml" \
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-review/contracts/phase-gates.yaml"; do
    if [[ ! -f "$phase_gate_file" ]]; then
        phase_gate_id_failures+=("${phase_gate_file#$FRAMEWORK_DIR/}: missing")
        continue
    fi

    duplicate_phase_gate_ids="$(
        awk '/^[[:space:]]+- id: / { count[$3]++ } END { for (id in count) if (count[id] > 1) print id }' "$phase_gate_file" \
            | sort
    )"

    if [[ -n "$duplicate_phase_gate_ids" ]]; then
        duplicate_phase_gate_ids="${duplicate_phase_gate_ids//$'\n'/ }"
        phase_gate_id_failures+=("${phase_gate_file#$FRAMEWORK_DIR/}: duplicate ids $duplicate_phase_gate_ids")
    fi
done

if [[ "${#phase_gate_id_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review phase-gate IDs must be unique: ${phase_gate_id_failures[*]}"
fi

test_start "review scores and finding counts calibrate without manufacturing work"
workflow_gates="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"
review_gates="$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml"
if ! grep -Fq 'final rubric weighted score >= 4.0' "$workflow_gates" \
    && ! grep -Fq 'Fix lowest-scoring dimensions and re-review' "$workflow_gates" \
    && p0p4_contains_text "$workflow_gates" "A score below 4.0 records residual risk but does not by itself authorize fixes or another review round" \
    && ! grep -Fq 'Each round finds fewer or equal issues than the previous round' "$review_gates" \
    && p0p4_contains_text "$review_gates" "Never suppress a new evidence-backed finding to preserve a monotonic count"; then
    pass
else
    fail "score or issue-count gates still bias review toward churn or suppressed findings"
fi

test_start "assistant-review return requires evidence-bounded reuse-search results"
reuse_search_return_failures=()
for file_and_term in \
    "$review_handoffs::- name: reuse_search" \
    "$review_handoffs::applicability" \
    "$review_handoffs::enum_values: [applicable, not_applicable]" \
    "$review_handoffs::applicability_reason" \
    "$review_handoffs::query_or_path" \
    "$review_handoffs::scope" \
    "$review_handoffs::outcome" \
    "$review_handoffs::disposition" \
    "$review_handoffs::enum_values: [reuse, extend, intentional_duplicate, reject_coincidental, reject_independent]" \
    "$review_handoffs::no_candidate_reason" \
    "$review_handoffs::decision_rationale" \
    "$review_handoffs::divergence_control" \
    "$review_phase_gates::reuse_search" \
    "$review_phase_gates::cannot return clean"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        reuse_search_return_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
if [[ "${#reuse_search_return_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review reuse-search return contract is incomplete: ${reuse_search_return_failures[*]}"
fi

test_start "assistant-review requires an independent reuse search in every fresh review"
independent_reuse_search_failures=()
for file_and_term in \
    "$review_handoffs::- name: reuse_search_instruction" \
    "$review_loop::independently during review" \
    "$review_loop::Carried Mapper/task-packet evidence alone cannot satisfy review" \
    "$review_phase_gates::fresh independent capability search" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/review-principles.md::independently during review" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/review-principles.md::Carried Mapper/task-packet evidence alone cannot satisfy review"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        independent_reuse_search_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
if ! awk '
    $0 == "  - name: fresh_reviewer_context" { in_bundle = 1; next }
    in_bundle && /^  - name: / { exit }
    in_bundle && /^[[:space:]]+context_fields_from_dispatch: / {
        fields = $0
        sub(/^.*\[/, "", fields)
        sub(/\].*$/, "", fields)
        count = split(fields, items, ",")
        for (item_index = 1; item_index <= count; item_index++) {
            item = items[item_index]
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", item)
            if (item == "reuse_search_instruction") found = 1
        }
    }
    END { exit found ? 0 : 1 }
' "$review_handoffs"; then
    independent_reuse_search_failures+=("fresh_reviewer_context.context_fields_from_dispatch missing reuse_search_instruction")
fi
if [[ "${#independent_reuse_search_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review fresh independent reuse-search instruction is incomplete: ${independent_reuse_search_failures[*]}"
fi

test_start "assistant-review v5 preserves Pack projection cardinality and rejects empty evidence"
pack_projection_cardinality_failures=()
if ! ruby -ryaml -e '
    input = YAML.load_file(ARGV.fetch(0))
    contracts = ARGV.map { |path| YAML.load_file(path) }
    pack = input.fetch("fields").find { |field| field["name"] == "architecture_decision_pack" }
    fields = pack.fetch("object_fields").to_h { |field| [field["name"], field] }
    boundaries = fields.fetch("boundaries_and_dependencies")
    pressure = fields.fetch("design_pressure_checks")
    required_concerns = %w[control_and_early_exit ownership_and_disposal resource_envelope extension_registration representative_path]
    valid = contracts.all? { |contract| contract.fetch("schema_version") == "5.0" } &&
      boundaries["required"] == true && boundaries["min_items"] == 1 &&
      pressure["required"] == true && pressure["min_items"] == 5 && pressure["max_items"] == 5 &&
      required_concerns.all? { |concern| pressure.fetch("validation").include?(concern) }
    exit valid ? 0 : 1
' "$review_input" "$review_output" "$review_phase_gates" "$review_handoffs" "$review_index"; then
    pack_projection_cardinality_failures+=("v5 input does not preserve non-empty boundaries and exact five-concern pressure coverage")
fi
if ! grep -Fq 'Migration note: assistant-review contracts are v5' "$review_skill" \
    || ! grep -Fq 'Pack projections require non-empty boundaries and exact five-concern design-pressure coverage' "$review_skill"; then
    pack_projection_cardinality_failures+=("v5 migration note does not describe Pack projection cardinality")
fi
if ! jq -e '
    .cases[] | select(.id == "architecture-pack-empty-review-evidence-blocks") |
    (.prompt | contains("Return exactly one valid JSON object")) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"equals","path":["validation_result","status"],"expected":"blocked"})) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"equals","path":["validation_result","missing_field"],"expected":"boundaries_and_dependencies_or_design_pressure_checks"})) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"nonempty_string","path":["validation_result","evidence_or_gap"]}))
' "$review_evals" >/dev/null; then
    pack_projection_cardinality_failures+=("empty Pack projection negative eval is missing structured blocked evidence")
fi
if [[ ${#pack_projection_cardinality_failures[@]} -eq 0 ]]; then
    pass
else
    fail "assistant-review Pack projection cardinality gaps: ${pack_projection_cardinality_failures[*]}"
fi

test_start "assistant-review v5 conditionally requires Pack checks in Reviewer returns"
reviewer_pack_return_failures=()
if ! ruby -ryaml -e '
    handoffs = YAML.load_file(ARGV.fetch(0))
    reviewer = handoffs.fetch("handoffs").find { |handoff| handoff["name"] == "orchestrator_to_reviewer" }
    checks = reviewer.fetch("return_fields").find { |field| field["name"] == "architecture_decision_pack_checks" }
    validation = handoffs.fetch("return_validation_bundles").find { |bundle| bundle["name"] == "reviewer_return_validation" }
    valid = checks["required"] == "conditional" &&
      checks["condition"] == "architecture_decision_pack_review_required is true" &&
      validation.fetch("validation").include?("architecture_decision_pack_checks when triggered")
    exit valid ? 0 : 1
' "$review_handoffs"; then
    reviewer_pack_return_failures+=("Reviewer return can omit triggered architecture_decision_pack_checks")
fi
if [[ ${#reviewer_pack_return_failures[@]} -eq 0 ]]; then
    pass
else
    fail "assistant-review Reviewer Pack return requiredness gaps: ${reviewer_pack_return_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
