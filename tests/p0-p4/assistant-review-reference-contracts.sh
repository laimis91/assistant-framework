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
review_principles="$FRAMEWORK_DIR/skills/assistant-review/references/review-principles.md"
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
    "$review_loop::triggered checklist sections" \
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

test_start "assistant-review requires evidence-bound medium-scope design coherence"
design_coherence_failures=()
for file_and_term in \
    "$review_skill::Design Coherence Pass" \
    "$review_loop::Design Coherence evidence" \
    "$review_handoffs::scope_size" \
    "$review_handoffs::design_coherence" \
    "$review_phase_gates::RS6A" \
    "$review_phase_gates::principle_checks.design_coherence" \
    "$review_evals::review-medium-scope-design-coherence" \
    "$review_evals::review-design-coherence-avoids-structural-heuristic"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        design_coherence_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
for section_and_term in \
    "## Design Coherence Pass::independent reasons to change" \
    "## Design Coherence Pass::no concrete risk found" \
    "## Design Coherence Pass::structural diff shape"; do
    section="${section_and_term%%::*}"
    term="${section_and_term#*::}"
    if ! p0p4_reference_section_has_term "$review_principles" "$section" "$term"; then
        design_coherence_failures+=("skills/assistant-review/references/review-principles.md $section missing $term")
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
            if (item == "scope_size") found = 1
        }
    }
    END { exit found ? 0 : 1 }
' "$review_handoffs"; then
    design_coherence_failures+=("fresh_reviewer_context.context_fields_from_dispatch missing scope_size")
fi
if ! awk '
    $0 == "      - name: principle_checks" { in_checks = 1; next }
    in_checks && /^      - name: / { exit }
    in_checks && $0 == "        required: conditional" { required = 1 }
    in_checks && $0 == "        condition: \"quality_principles_required is true or scope_size in [medium, large]\"" { condition = 1 }
    END { exit required && condition ? 0 : 1 }
' "$review_handoffs"; then
    design_coherence_failures+=("principle_checks is not conditionally required for its applicable scope")
fi
if ! awk '
    $0 == "      - name: principle_checks" { in_checks = 1; next }
    in_checks && /^      - name: / { exit }
    in_checks && $0 == "          - name: design_coherence" { in_design_coherence = 1; next }
    in_design_coherence && /^          - name: / { exit }
    in_design_coherence && $0 == "            required: conditional" { required = 1 }
    in_design_coherence && $0 == "            condition: \"scope_size in [medium, large]\"" { condition = 1 }
    END { exit required && condition ? 0 : 1 }
' "$review_handoffs"; then
    design_coherence_failures+=("principle_checks.design_coherence is not conditionally required for medium/large scope")
fi
if [[ "${#design_coherence_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review medium-scope design-coherence contract is incomplete: ${design_coherence_failures[*]}"
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
    pack_input_names = index.fetch("load_sets").fetch("architecture_pack_input").fetch("selectors").find { |selector| selector["id"] == "review-architecture-pack-input" }.fetch("names")
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
    valid = input["schema_version"] == "7.1" && handoffs["schema_version"] == "7.1" && output["schema_version"] == "7.1" && index["schema_version"] == "7.1" &&
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
      !entry_names.include?("architecture_decision_pack") &&
      pack_input_names == ["architecture_decision_pack"] &&
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
    (.machine_expectations.structured_json_assertions | length == 4) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"equals","path":["architecture_design_mode"],"expected":"review_intensive"})) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"equals_path","path":["architecture_design_mode"],"other_path":["architecture_decision_pack","mode"]})) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"equals","path":["architecture_decision_pack_review","independent_challenge_evidence"],"expected":"missing independent challenge evidence"})) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"equals","path":["architecture_decision_pack_review","architecture_pack_findings_summary"],"expected":"Blocked: independent_challenge_evidence is missing for review_intensive mode."}))
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
    "$review_skill::Migration note: assistant-review contracts are v7" \
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

test_start "assistant-review defaults to one complete audit batch and at most one post-fix re-review batch"
review_round_policy_failures=()
review_output="$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml"
review_handoffs="$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml"

for file_and_term in \
    "$review_skill::Audit mode stops after one review batch." \
    "$review_skill::initial review batch, fixes and validation, then one fresh re-review batch" \
    "$review_loop::Audit mode exits after one started batch reaches terminal accounting, complete or incomplete" \
    "$review_loop::The normal review-fix path is round 1 review batch, fixes and validation, then one fresh round 2 re-review batch." \
    "$review_loop::references/review-batch.md" \
    "$review_loop::Round 3+ requires a recorded" \
    "$review_handoffs::- name: additional_round_reason" \
    "$review_handoffs::condition: \"round >= 3\"" \
    "$review_output::- name: additional_round_reasons" \
    "$review_output::condition: \"rounds >= 2\"" \
    "$review_output::Contains one entry for every round from 2 through rounds" \
    "$review_output::round 2 records changed-files/fix evidence retrospectively" \
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
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml"; do
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
    "$review_loop::bounded independent capability search" \
    "$review_loop::carried Mapper evidence cannot satisfy review" \
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

test_start "assistant-review v7 preserves recoverable selected-design Pack projections"
pack_projection_cardinality_failures=()
if ! ruby -ryaml -e '
    input = YAML.load_file(ARGV.fetch(0))
    contracts = ARGV.map { |path| YAML.load_file(path) }
    pack = input.fetch("fields").find { |field| field["name"] == "architecture_decision_pack" }
    fields = pack.fetch("object_fields").to_h { |field| [field["name"], field] }
    boundaries = fields.fetch("boundaries_and_dependencies")
    pressure = fields.fetch("design_pressure_checks")
    required_concerns = %w[control_and_early_exit ownership_and_disposal resource_envelope extension_registration representative_path]
    ref = fields.fetch("ref")
    valid = contracts.all? { |contract| contract.fetch("schema_version") == "7.1" } &&
      boundaries["required"] == true && boundaries["min_items"] == 1 &&
      pressure["required"] == true && pressure["min_items"] == 5 && pressure["max_items"] == 5 &&
      ref["required"] == true && ref.fetch("validation").include?("selected design") && ref.fetch("validation").include?("rationale") && ref.fetch("validation").include?("viable alternatives") &&
      required_concerns.all? { |concern| pressure.fetch("validation").include?(concern) }
    exit valid ? 0 : 1
' "$review_input" "$review_output" "$review_phase_gates" "$review_handoffs" "$review_index"; then
    pack_projection_cardinality_failures+=("v7 input does not preserve recoverable selected design, rationale, viable alternative dispositions, non-empty boundaries, and exact five-concern pressure coverage")
fi
if ! grep -Fq 'Migration note: assistant-review contracts are v7' "$review_skill" \
    || ! grep -Fq 'recoverable selected design, rationale, and viable alternatives/dispositions' "$review_skill"; then
    pack_projection_cardinality_failures+=("v7 migration note does not describe recoverable selected design evidence")
fi
if ! jq -e '
    .cases[] | select(.id == "architecture-pack-empty-review-evidence-blocks") |
    (.prompt | contains("Return exactly one valid JSON object")) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"equals","path":["architecture_decision_pack_review","architecture_pack_findings_summary"],"expected":"Blocked: boundaries_and_dependencies_or_design_pressure_checks is empty."})) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"path_absent","path":["architecture_decision_pack_review","independent_challenge_evidence"]}))
' "$review_evals" >/dev/null; then
    pack_projection_cardinality_failures+=("empty Pack projection negative eval is missing structured blocked evidence")
fi
if [[ ${#pack_projection_cardinality_failures[@]} -eq 0 ]]; then
    pass
else
    fail "assistant-review Pack projection cardinality gaps: ${pack_projection_cardinality_failures[*]}"
fi

test_start "assistant-review reviewer-context ceiling matches its canonical loop reference"
if ruby -ryaml -rjson -e '
    index = YAML.load_file(ARGV.fetch(0))
    budget = index.fetch("load_sets").fetch("reviewer_context").fetch("budget_words")
    reference = File.read(ARGV.fetch(1))
    exit reference.include?("strictly below #{budget} words") ? 0 : 1
  ' "$review_index" "$review_loop"; then
    pass
else
    fail "assistant-review reviewer-context budget_words and review-loop closure ceiling diverged"
fi

test_start "assistant-review grader rejects unrecoverable selected Pack decisions"
review_identity_eval_root="$(mktemp -d "${TMPDIR:-/tmp}/assistant-review-selected-decision.XXXXXX")"
p0p4_register_cleanup "$review_identity_eval_root"
mkdir -p "$review_identity_eval_root/skill" "$review_identity_eval_root/skill/evals"
cp "$review_skill" "$review_identity_eval_root/skill/SKILL.md"
jq '.skill = "skill" | .cases = [.cases[] | select(.id == "architecture-pack-selected-design-recovery-blocks")]' "$review_evals" >"$review_identity_eval_root/skill/evals/cases.json"
review_identity_required="$(jq -r '.cases[0].machine_expectations.required_substrings[]' "$review_identity_eval_root/skill/evals/cases.json" | paste -sd ' ' -)"
jq -n --arg summary "$review_identity_required" '{summary: $summary, architecture_decision_pack_review: {architecture_pack_findings_summary: "Validated selected design.", freshness_and_facts: "current", material_questions_and_invalidators: "none", ownership_dependency_and_lifecycle_boundary: "checked", design_pressure_checks: "checked", semantic_type_and_primitive_exception_ledger: "checked", quality_scenario_falsifiability: "checked", compatibility_and_extension_seam: "checked", verification_handoff_and_rollback: "checked"}}' >"$review_identity_eval_root/skill/architecture-pack-selected-design-recovery-blocks.txt"
if "$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$review_identity_eval_root" --skill "$review_identity_eval_root/skill" >"$review_identity_eval_root/grader.out" 2>&1; then
    fail "real grader accepted unrecoverable selected Pack decision"
elif grep -Fq $'FAIL\tskill\tarchitecture-pack-selected-design-recovery-blocks' "$review_identity_eval_root/grader.out" \
    && grep -Fq 'structured JSON assertion failure' "$review_identity_eval_root/grader.out"; then
    pass
else
    fail "real grader did not reject unrecoverable selected Pack decision for the intended reason"
fi

test_start "assistant-review v7 conditionally requires Pack checks in Reviewer returns"
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

test_start "assistant-review batches independent passes before aggregation or exit"
review_batch_failures=()
review_batch_reference="$FRAMEWORK_DIR/skills/assistant-review/references/review-batch.md"
for file_and_term in \
    "$review_input::review_snapshot_id" \
    "$review_input::snapshot_identity" \
    "$review_index::harness_capable" \
    "$review_handoffs::review_batch" \
    "$review_handoffs::expected_passes" \
    "$review_handoffs::review_pass_id" \
    "$review_handoffs::sibling-blind" \
    "$review_handoffs::coverage_entries" \
    "$review_phase_gates::all expected passes reach terminal accounting" \
    "$review_phase_gates::coverage is incomplete" \
    "$review_phase_gates::HAS_REMAINING_ITEMS" \
    "$review_output::coverage_complete" \
    "$review_output::coverage_ledger" \
    "$review_loop::wait for all expected responses" \
    "$review_batch_reference::minimum of two independent narrow passes" \
    "$review_batch_reference::Do not aggregate, fix, exit, or report a clean result" \
    "$review_evals::audit-batch-waits-for-all-pass-results" \
    "$review_evals::incomplete-review-batch-never-cleans" \
    "$review_evals::post-fix-review-uses-fresh-snapshot-batch"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        review_batch_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
if [[ "${#review_batch_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review multi-pass batch contract is incomplete: ${review_batch_failures[*]}"
fi

test_start "assistant-review incomplete-batch eval keeps clean states out of generated success text"
if ruby -rjson -e '
  review = JSON.parse(File.read(ARGV.fetch(0)))
  item = review.fetch("cases").find { |entry| entry["id"] == "incomplete-review-batch-never-cleans" }
  expectations = item.fetch("machine_expectations")
  generated_success_text = (item.fetch("expected_behavior") + item.fetch("pass_criteria")).join(" ")
  forbidden = expectations.fetch("forbidden_substrings")
  valid = expectations.fetch("required_substrings").include?("HAS_REMAINING_ITEMS") &&
    forbidden.include?("final result: CLEAN") &&
    forbidden.include?("final result: ISSUES_FIXED") &&
    !generated_success_text.include?("CLEAN") && !generated_success_text.include?("ISSUES_FIXED")
  exit valid ? 0 : 1
' "$review_evals"; then
    pass
else
    fail "assistant-review incomplete-batch eval collides with its generated success response"
fi

test_start "assistant-review batch topology preserves snapshot, closure, and aggregate semantics"
if ruby -ryaml -e '
  input = YAML.load_file(ARGV.fetch(0))
  handoffs = YAML.load_file(ARGV.fetch(1))
  output = YAML.load_file(ARGV.fetch(2))
  gates = YAML.load_file(ARGV.fetch(3))
  input_snapshot = input.fetch("fields").find { |field| field["name"] == "review_material_snapshot" }
  reviewer = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_reviewer" }
  context = reviewer.fetch("context_fields").to_h { |field| [field["name"], field] }
  returns = reviewer.fetch("return_fields").to_h { |field| [field["name"], field] }
  handoff_snapshot = context.fetch("review_material_snapshot")
  batch = context.fetch("review_batch")
  expected = batch.fetch("object_fields").find { |field| field["name"] == "expected_passes" }
  topology = batch.fetch("object_fields").find { |field| field["name"] == "topology" }
  final = output.fetch("artifacts").find { |artifact| artifact["name"] == "final_summary" }
  final_fields = final.fetch("object_fields").to_h { |field| [field["name"], field] }
  batch_identity = final_fields.fetch("batch_summaries").fetch("object_fields").find { |field| field["name"] == "snapshot_identity" }.fetch("object_fields")
  audit = output.fetch("artifacts").find { |artifact| artifact["name"] == "audit_report" }
  audit_finding = audit.fetch("object_fields").find { |field| field["name"] == "findings" }
  audit_fields = audit_finding.fetch("object_fields").map { |field| field["name"] }
  review = gates.fetch("gates").find { |gate| gate["phase"] == "REVIEW_STEP" }
  gate_ids = review.fetch("exit_assertions").to_h { |gate| [gate["id"], gate] }
  snapshot_shape = input_snapshot.fetch("object_fields").find { |field| field["name"] == "snapshot_identity" }.fetch("object_fields")
  handoff_shape = handoff_snapshot.fetch("object_fields").find { |field| field["name"] == "snapshot_identity" }.fetch("object_fields")
  perspective = expected.fetch("object_fields").find { |field| field["name"] == "perspective" }
  previous = context.fetch("previously_fixed")
  valid = snapshot_shape == handoff_shape &&
    snapshot_shape.map { |field| field["name"] } == %w[basis value captured_at scope_manifest_digest] &&
    expected["min_items"] == 2 && expected["max_items"] == 6 &&
    perspective.fetch("enum_values").include?("closure_verification") &&
    topology.fetch("validation").include?("trivial/small=2") && topology.fetch("validation").include?("medium=3") && topology.fetch("validation").include?("large=4") &&
    topology.fetch("validation").include?("maximum of 6") && topology.fetch("validation").include?("one retry") &&
    previous["required"] == "conditional" && previous["condition"] == "review_perspective == closure_verification" &&
    returns.fetch("verdict").fetch("description").include?("pass-level") &&
    final_fields.key?("batch_summaries") && final_fields.key?("aggregation_ledger") && final_fields.key?("aggregated_findings") &&
    audit_fields.include?("aggregate_finding_id") && audit_fields.include?("source_pass_ids") &&
    gate_ids.key?("RS_BATCH_AGGREGATION") && gate_ids.fetch("RS_BATCH_AGGREGATION").fetch("check").include?("complete aggregated union")
  exit valid ? 0 : 1
' "$review_input" "$review_handoffs" "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml" "$review_phase_gates" \
  && grep -Fq 'Load `references/review-batch.md` before batch planning.' "$review_loop" \
  && grep -Fq 'same locus, invariant, and failure mechanism' "$review_batch_reference" \
  && grep -Fq 'started batches' "$review_batch_reference" \
  && grep -Fq 'closure_verification' "$FRAMEWORK_DIR/agents/codex/code-reviewer.toml" \
  && grep -Fq 'pass-level verdict' "$FRAMEWORK_DIR/agents/claude/reviewer.md"; then
    pass
else
    fail "assistant-review batch topology, aggregate provenance, or closure isolation is incomplete"
fi

test_start "assistant-review realizes discovery coverage and final-snapshot aggregation"
if ruby -ryaml -e '
  input = YAML.load_file(ARGV.fetch(0))
  handoffs = YAML.load_file(ARGV.fetch(1))
  output = YAML.load_file(ARGV.fetch(2))
  gates = YAML.load_file(ARGV.fetch(3))
  snapshot = input.fetch("fields").find { |field| field["name"] == "review_material_snapshot" }
  reviewer = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_reviewer" }
  context = reviewer.fetch("context_fields").to_h { |field| [field["name"], field] }
  returns = reviewer.fetch("return_fields").to_h { |field| [field["name"], field] }
  input_fields = snapshot.fetch("object_fields").to_h { |field| [field["name"], field] }
  handoff_fields = context.fetch("review_material_snapshot").fetch("object_fields").to_h { |field| [field["name"], field] }
  manifest = input_fields.fetch("scope_manifest")
  handoff_manifest = handoff_fields.fetch("scope_manifest")
  manifest_names = manifest.fetch("object_fields").map { |field| field["name"] }
  identity = input_fields.fetch("snapshot_identity").fetch("object_fields")
  expected = context.fetch("review_batch").fetch("object_fields").find { |field| field["name"] == "expected_passes" }
  expected_perspective = expected.fetch("object_fields").find { |field| field["name"] == "perspective" }
  coverage = returns.fetch("coverage_entries").fetch("object_fields").to_h { |field| [field["name"], field] }
  final = output.fetch("artifacts").find { |artifact| artifact["name"] == "final_summary" }
  final_fields = final.fetch("object_fields").to_h { |field| [field["name"], field] }
  batch_identity = final_fields.fetch("batch_summaries").fetch("object_fields").find { |field| field["name"] == "snapshot_identity" }.fetch("object_fields")
  ledger = final_fields.fetch("aggregation_ledger")
  finding_fields = final_fields.fetch("aggregated_findings").fetch("object_fields").map { |field| field["name"] }
  rubric = output.fetch("artifacts").find { |artifact| artifact["name"] == "rubric_summary" }
  progression = rubric.fetch("object_fields").find { |field| field["name"] == "score_progression" }
  review = gates.fetch("gates").find { |gate| gate["phase"] == "REVIEW_STEP" }
  gate_ids = review.fetch("exit_assertions").to_h { |gate| [gate["id"], gate] }
  required_perspectives = %w[contract_and_test_oracle runtime_lifecycle_and_failure_paths integration_compatibility_and_consumers architecture_maintainability_and_reuse risk_selected_specialist closure_verification]
  valid = manifest_names == %w[scope_item_id locator content_digest applicable_concerns] &&
    manifest == handoff_manifest && identity.map { |field| field["name"] }.include?("scope_manifest_digest") &&
    expected_perspective.fetch("enum_values") == required_perspectives &&
    context.fetch("review_perspective").fetch("enum_values") == required_perspectives &&
    returns.fetch("review_perspective").fetch("enum_values") == required_perspectives &&
    returns.fetch("snapshot_identity").fetch("object_fields") == identity &&
    returns.fetch("pass_completion_state").fetch("enum_values") == %w[completed needs_context blocked] &&
    final_fields.fetch("coverage_ledger").fetch("object_fields").find { |field| field["name"] == "terminal_state" }.fetch("enum_values").include?("failed") &&
    coverage.fetch("scope_item_id").fetch("type") == "string" && coverage.fetch("scope_item_id")["required"] == true && !coverage.key?("scope_item_ids") &&
    final.fetch("validation").include?("current final snapshot") && final_fields.fetch("coverage_complete").fetch("description").include?("current final snapshot") && batch_identity == final_fields.fetch("final_snapshot_identity").fetch("object_fields") &&
    ledger["min_items"].nil? && ledger.fetch("object_fields").find { |field| field["name"] == "disposition" }.fetch("enum_values") == %w[retained merged fixed_closed observation rejected_invalid coverage_gap] &&
    finding_fields.include?("evidence") && finding_fields.include?("smallest_useful_fix") &&
    rubric.fetch("description").include?("post-barrier aggregated union") && progression.fetch("object_fields").any? { |field| field["name"] == "aggregated_finding_count" } &&
    gate_ids.fetch("RS5").fetch("check").include?("post-barrier aggregated union")
  exit valid ? 0 : 1
' "$review_input" "$review_handoffs" "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml" "$review_phase_gates" \
  && grep -Fq 'canonical discovery passes' "$review_loop" \
  && grep -Fq 'Security uses Code Reviewer' "$review_batch_reference" \
  && grep -Fq 'Historical incomplete or invalidated batches remain in history' "$review_batch_reference" \
  && grep -Fq 'QA is the separate acceptance lane' "$review_loop" \
  && grep -Fq 'aggregated union finding count' "$FRAMEWORK_DIR/skills/assistant-review/references/score-tracking.md" \
  && grep -Fq 'pass_completion_state' "$FRAMEWORK_DIR/agents/codex/code-reviewer.toml" \
  && grep -Fq 'snapshot_identity' "$FRAMEWORK_DIR/agents/codex/reviewer.toml" \
  && grep -Fq 'coverage_obligation' "$FRAMEWORK_DIR/agents/claude/code-reviewer.md" \
  && grep -Fq 'pass_completion_state' "$FRAMEWORK_DIR/agents/claude/reviewer.md"; then
    pass
else
    fail "assistant-review discovery topology, scope manifest, final-snapshot lifecycle, or aggregate rubric contract is incomplete"
fi

test_start "assistant-review preserves carried feature-preparation QA acceptance obligation"
if ruby -ryaml -e '
  input = YAML.load_file(ARGV.fetch(0))
  handoffs = YAML.load_file(ARGV.fetch(1))
  gates = YAML.load_file(ARGV.fetch(2))
  workflow = YAML.load_file(ARGV.fetch(3))
  field = input.fetch("fields").find { |entry| entry["name"] == "approved_feature_preparation_qa_acceptance_obligation" }
  qa = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_qa_evaluator" }
  handoff = qa.fetch("context_fields").find { |entry| entry["name"] == "approved_feature_preparation_qa_acceptance_obligation" }
  fields = field.fetch("object_fields").to_h { |entry| [entry["name"], entry] }
  canonical = workflow.fetch("fields").find { |entry| entry["name"] == "approved_feature_preparation_qa_acceptance_obligation" }
  canonical_fields = canonical.fetch("object_fields")
  projection = ->(entries) { entries.map { |entry| entry.slice("name", "type", "enum_values", "required", "condition", "validation") } }
  entry = gates.fetch("gates").find { |gate| gate["phase"] == "ENTRY" }.fetch("exit_assertions").to_h { |gate| [gate["id"], gate] }
  qa_gates = gates.fetch("gates").find { |gate| gate["phase"] == "QA_EVALUATION_STEP" }.fetch("exit_assertions").to_h { |gate| [gate["id"], gate] }
  valid = field["type"] == "object" && field["required"] == "conditional" && field["condition"] == "approved_feature_preparation_qa_acceptance_obligation is carried from workflow" &&
    projection.call(field.fetch("object_fields")) == projection.call(canonical_fields) &&
    projection.call(handoff.fetch("object_fields")) == projection.call(canonical_fields) &&
    fields.fetch("requested_scope")["type"] == "string" && field.fetch("validation").include?("unchanged") &&
    entry.fetch("E7").fetch("check").include?("approved_feature_preparation_qa_acceptance_obligation") &&
    qa_gates.fetch("QA1").fetch("check").include?("execution_prerequisite") && qa_gates.fetch("QA1").fetch("on_fail").downcase.include?("block")
  exit valid ? 0 : 1
' "$review_input" "$review_handoffs" "$review_phase_gates" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/input.yaml" \
  && grep -Fq 'approved_feature_preparation_qa_acceptance_obligation' "$review_index" \
  && grep -Fq 'qa_evaluation_mode=required' "$FRAMEWORK_DIR/skills/assistant-review/references/qa-evaluation-loop.md" \
  && grep -Fq 'execution_prerequisite' "$FRAMEWORK_DIR/skills/assistant-review/references/qa-evaluation-loop.md" \
  && grep -Fq 'block if prerequisite or evidence is missing' "$FRAMEWORK_DIR/skills/assistant-review/references/qa-evaluation-loop.md"; then
    pass
else
    fail "assistant-review drops or weakens carried feature-preparation QA acceptance obligation"
fi

test_start "assistant-review requires exact pass assignment, terminal accounting, and mutation-safe aggregation"
if ruby -ryaml -e '
  index, input, handoffs, output, gates = ARGV.map { |path| YAML.load_file(path) }
  reviewer = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_reviewer" }
  context = reviewer.fetch("context_fields").to_h { |field| [field["name"], field] }
  returns = reviewer.fetch("return_fields").to_h { |field| [field["name"], field] }
  batch = context.fetch("review_batch").fetch("object_fields").to_h { |field| [field["name"], field] }
  expected = batch.fetch("expected_passes").fetch("object_fields").to_h { |field| [field["name"], field] }
  coverage = returns.fetch("coverage_entries").fetch("object_fields").to_h { |field| [field["name"], field] }
  finding = returns.fetch("findings").fetch("object_fields").to_h { |field| [field["name"], field] }
  final = output.fetch("artifacts").find { |item| item["name"] == "final_summary" }.fetch("object_fields").to_h { |field| [field["name"], field] }
  aggregate = final.fetch("aggregated_findings").fetch("object_fields").to_h { |field| [field["name"], field] }
  audit = output.fetch("artifacts").find { |item| item["name"] == "audit_report" }.fetch("object_fields").to_h { |field| [field["name"], field] }
  attempt = batch.fetch("pass_attempt_ledger").fetch("object_fields").to_h { |field| [field["name"], field] }
  qa = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_qa_evaluator" }.fetch("context_fields").to_h { |field| [field["name"], field] }
  workflow_scope = YAML.load_file(ARGV.fetch(5)).fetch("fields").find { |field| field["name"] == "feature_preparation_scope" }
  review_scope = input.fetch("fields").find { |field| field["name"] == "feature_preparation_scope" }
  entry_names = index.fetch("load_sets").fetch("entry").fetch("selectors").first.fetch("names")
  gate = gates.fetch("gates").find { |item| item["phase"] == "ENTRY" }.fetch("exit_assertions").to_h { |item| [item["id"], item] }
  invariant_names = index.fetch("load_sets").fetch("current_round").fetch("selectors").find { |item| item["id"] == "review-round-invariants" }.fetch("names")
  rubric = output.fetch("artifacts").find { |item| item["name"] == "rubric_summary" }
  obligation = input.fetch("fields").find { |field| field["name"] == "approved_feature_preparation_qa_acceptance_obligation" }.fetch("object_fields").to_h { |field| [field["name"], field] }
  qa_obligation = qa.fetch("approved_feature_preparation_qa_acceptance_obligation").fetch("object_fields").to_h { |field| [field["name"], field] }
  expected_assignment = { "p1" => { "scope" => ["s1"], "obligations" => ["contract"] }, "p2" => { "scope" => ["s2"], "obligations" => ["runtime"] } }
  incomplete_entries = [{ "pass" => "p1", "scope" => ["s1"], "obligation" => "contract" }]
  exact_closure = expected_assignment.all? { |pass, assignment| assignment.fetch("scope").product(assignment.fetch("obligations")).all? { |scope, obligation_name| incomplete_entries.any? { |entry| entry["pass"] == pass && entry.fetch("scope").include?(scope) && entry["obligation"] == obligation_name } } }
  valid = %w[assigned_scope coverage_obligations quality_principles_required].all? { |name| context.key?(name) } &&
    expected.fetch("assigned_scope").fetch("min_items") == 1 && expected.fetch("coverage_obligations").fetch("min_items") == 1 &&
    coverage.fetch("scope_item_id").fetch("validation").include?("assigned_scope") && coverage.fetch("coverage_obligation").fetch("validation").include?("coverage_obligations") &&
    final.fetch("coverage_complete").fetch("description").include?("exact") && final.fetch("coverage_ledger").fetch("validation").include?("required_coverage_tuples") &&
    %w[locus invariant failure_mechanism evidence smallest_useful_fix].all? { |name| finding.fetch(name)["required"] == true } &&
    %w[locus invariant failure_mechanism evidence smallest_useful_fix].all? { |name| aggregate.fetch(name).slice("type", "required") == finding.fetch(name).slice("type", "required") } &&
    review_scope.slice("type", "enum_values", "default", "validation", "infer_from") == workflow_scope.slice("type", "enum_values", "default", "validation", "infer_from") &&
    entry_names.include?("feature_preparation_scope") && qa.fetch("feature_preparation_scope").slice("type", "enum_values") == workflow_scope.slice("type", "enum_values") &&
    obligation.fetch("source_feature_preparation_evidence_ref").fetch("condition") == "feature_preparation_scope == existing_system" && qa_obligation.fetch("source_feature_preparation_evidence_ref").fetch("condition") == "feature_preparation_scope == existing_system" &&
    obligation.fetch("source_preparation_basis").fetch("condition") == "feature_preparation_scope == not_applicable" && qa_obligation.fetch("source_preparation_basis").fetch("condition") == "feature_preparation_scope == not_applicable" &&
    gate.fetch("E7").fetch("check").include?("feature_preparation_scope") &&
    attempt.fetch("review_pass_id")["required"] == true && attempt.fetch("active_terminal_attempt_id")["required"] == "conditional" && attempt.fetch("attempts").fetch("object_fields").any? { |field| field["name"] == "attempt_count" && field["validation"].include?("<= 2") } &&
    invariant_names.include?("INV_BATCH") && rubric.fetch("condition") == "scope_size in [medium, large]" &&
    !exact_closure && audit.key?("coverage_complete") && audit.key?("batch_summaries") && audit.key?("coverage_ledger_ref")
  exit valid ? 0 : 1
' "$review_index" "$review_input" "$review_handoffs" "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml" "$review_phase_gates" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/input.yaml"; then
    pass
else
    fail "assistant-review lacks exact assignment closure, terminal ledger, typed QA discriminator, or aggregate rubric parity"
fi

test_start "assistant-review models batch lifecycle, overlapping manifest coverage, and pre-batch provenance"
if ruby -ryaml -rjson -e '
  input, handoffs, output, gates = ARGV.take(4).map { |path| YAML.load_file(path) }
  evals = JSON.parse(File.read(ARGV.fetch(4)))
  reviewer = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_reviewer" }
  context = reviewer.fetch("context_fields").to_h { |field| [field["name"], field] }
  batch = context.fetch("review_batch").fetch("object_fields").to_h { |field| [field["name"], field] }
  expected = batch.fetch("expected_passes").fetch("object_fields").to_h { |field| [field["name"], field] }
  attempt = batch.fetch("pass_attempt_ledger").fetch("object_fields").to_h { |field| [field["name"], field] }
  returns = reviewer.fetch("return_fields").to_h { |field| [field["name"], field] }
  coverage = returns.fetch("coverage_entries").fetch("object_fields").to_h { |field| [field["name"], field] }
  final = output.fetch("artifacts").find { |item| item["name"] == "final_summary" }.fetch("object_fields").to_h { |field| [field["name"], field] }
  aggregate = final.fetch("aggregated_findings").fetch("object_fields").to_h { |field| [field["name"], field] }
  audit = output.fetch("artifacts").find { |item| item["name"] == "audit_report" }.fetch("object_fields").to_h { |field| [field["name"], field] }
  snapshot = input.fetch("fields").find { |field| field["name"] == "review_material_snapshot" }.fetch("object_fields").to_h { |field| [field["name"], field] }
  concern = snapshot.fetch("scope_manifest").fetch("object_fields").find { |field| field["name"] == "applicable_concerns" }
  terminal = %w[completed needs_context blocked timed_out failed invalidated]
  lifecycle_valid = ->(status, records, expected_ids) {
    case status
    when "planned", "dispatched"
      records.empty? || records.all? { |record| record["record_state"] == "pending" && record["attempt_count"] == 0 }
    when "collecting"
      records.length < expected_ids.length && records.all? { |record| expected_ids.include?(record["review_pass_id"]) && record.fetch("attempt_count") <= 2 }
    else
      records.length == expected_ids.length && records.map { |record| record["review_pass_id"] }.uniq.length == expected_ids.length && records.all? { |record| record["record_state"] == "terminal" && terminal.include?(record["terminal_state"]) && (1..2).cover?(record["attempt_count"]) }
    end
  }
  expected_ids = %w[p-contract p-runtime]
  planned = lifecycle_valid.call("planned", [], expected_ids)
  collecting = lifecycle_valid.call("collecting", [{"review_pass_id" => "p-contract", "record_state" => "pending", "attempt_count" => 1}], expected_ids)
  repaired_timeout = lifecycle_valid.call("incomplete", [{"review_pass_id" => "p-contract", "record_state" => "terminal", "attempt_count" => 1, "terminal_state" => "completed"}, {"review_pass_id" => "p-runtime", "record_state" => "terminal", "attempt_count" => 2, "terminal_state" => "timed_out", "failure_evidence" => "timeout", "repair_disposition" => "exhausted"}], expected_ids)
  completed = lifecycle_valid.call("complete", expected_ids.map { |id| {"review_pass_id" => id, "record_state" => "terminal", "attempt_count" => 1, "terminal_state" => "completed"} }, expected_ids)
  manifest = {"s-api" => ["contract"], "s-runtime" => ["runtime"]}
  expected_tuples = [["p-contract", "s-api", "contract", "contract_and_test_oracle"], ["p-runtime", "s-api", "contract", "runtime_lifecycle_and_failure_paths"], ["p-runtime", "s-runtime", "runtime", "runtime_lifecycle_and_failure_paths"]]
  overlap_entries = expected_tuples.dup
  missing_manifest_tuple = expected_tuples.reject { |tuple| tuple[1] == "s-runtime" }
  exact_tuple_closure = ->(entries) { expected_tuples.all? { |tuple| entries.include?(tuple) } && entries.all? { |tuple| expected_tuples.include?(tuple) } }
  noncompleted_fail_closed = terminal.reject { |state| state == "completed" }.all? { |state| state != "completed" }
  adversarial = { "summary" => "all expected responses; HAS_REMAINING_ITEMS", "expected" => 2, "terminal" => 1, "coverage_complete" => true }
  rejects_adversarial = adversarial.fetch("terminal") != adversarial.fetch("expected") && adversarial.fetch("coverage_complete")
  bundle = handoffs.fetch("dispatch_context_bundles").find { |item| item["name"] == "fresh_reviewer_context" }
  context_names = bundle.fetch("context_fields_from_dispatch")
  provenance = aggregate.fetch("source_provenance").fetch("object_fields").to_h { |field| [field["name"], field] }
  audit_provenance = audit.fetch("findings").fetch("object_fields").to_h { |field| [field["name"], field] }.fetch("source_provenance")
  audit_eval = evals.fetch("cases").find { |item| item["id"] == "audit-spec-review-fail-is-read-only" }
  later_eval = evals.fetch("cases").find { |item| item["id"] == "audit-spec-review-fail-continues-complete-batch" }
  mutation_eval = evals.fetch("cases").find { |item| item["id"] == "in-flight-mutation-invalidates-review-batch" }
  valid = planned && collecting && repaired_timeout && completed && exact_tuple_closure.call(overlap_entries) && !exact_tuple_closure.call(missing_manifest_tuple) && noncompleted_fail_closed && rejects_adversarial &&
    concern.fetch("min_items") == 1 && expected.fetch("assigned_scope").fetch("validation").include?("may overlap") && batch.key?("required_coverage_tuples") &&
    %w[scope_item_id applicable_concern review_perspective].all? { |name| coverage.key?(name) } && coverage.fetch("scope_item_id").fetch("validation").include?("assigned_scope") &&
    final.fetch("coverage_complete").fetch("description").include?("concern") && final.fetch("coverage_ledger").fetch("validation").include?("needs_context") &&
    batch.key?("pre_batch_findings") && !context_names.include?("pre_batch_findings") && context_names.include?("pre_batch_criteria_ref") && !context_names.include?("spec_review_pass_ref") &&
    provenance.fetch("source_kind").fetch("enum_values") == %w[spec_review review_pass] && provenance.fetch("source_id").fetch("required") == true && audit_provenance.fetch("required") == true &&
    gates.fetch("gates").find { |item| item["phase"] == "EVALUATE_STEP" }.fetch("exit_assertions").to_h { |item| [item["id"], item] }.fetch("EV2").fetch("check").include?("needs_context") &&
    audit_eval.fetch("expected_behavior").join(" ").include?("read-only Reviewer pass") && later_eval.fetch("expected_behavior").join(" ").include?("later runtime finding") && mutation_eval.fetch("expected_behavior").join(" ").include?("HAS_REMAINING_ITEMS")
  exit valid ? 0 : 1
' "$review_input" "$review_handoffs" "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml" "$review_phase_gates" "$review_evals"; then
    pass
else
    fail "assistant-review lacks lifecycle-safe terminal accounting, overlapping manifest tuple closure, or sibling-blind pre-batch provenance"
fi

test_start "assistant-review closes required obligation tuples and canonical perspectives exactly"
if ruby -ryaml -e '
  handoffs, output, gates = ARGV.map { |path| YAML.load_file(path) }
  reviewer = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_reviewer" }
  context = reviewer.fetch("context_fields").to_h { |field| [field["name"], field] }
  batch = context.fetch("review_batch").fetch("object_fields").to_h { |field| [field["name"], field] }
  topology = batch.fetch("topology").fetch("object_fields").to_h { |field| [field["name"], field] }
  canonical = topology.fetch("canonical_discovery_perspectives").fetch("object_fields").to_h { |field| [field["name"], field] }
  tuples = batch.fetch("required_coverage_tuples").fetch("object_fields").to_h { |field| [field["name"], field] }
  coverage = reviewer.fetch("return_fields").find { |field| field["name"] == "coverage_entries" }.fetch("object_fields").to_h { |field| [field["name"], field] }
  finding = reviewer.fetch("return_fields").find { |field| field["name"] == "findings" }.fetch("object_fields").to_h { |field| [field["name"], field] }
  prebatch = batch.fetch("pre_batch_findings").fetch("object_fields").to_h { |field| [field["name"], field] }.fetch("finding").fetch("object_fields").to_h { |field| [field["name"], field] }
  final = output.fetch("artifacts").find { |item| item["name"] == "final_summary" }.fetch("object_fields").to_h { |field| [field["name"], field] }
  ledger = final.fetch("coverage_ledger").fetch("object_fields").to_h { |field| [field["name"], field] }
  expected = { "trivial_small" => %w[contract_and_test_oracle runtime_lifecycle_and_failure_paths], "medium" => %w[contract_and_test_oracle runtime_lifecycle_and_failure_paths integration_compatibility_and_consumers], "large" => %w[contract_and_test_oracle runtime_lifecycle_and_failure_paths integration_compatibility_and_consumers architecture_maintainability_and_reuse] }
  supported_types = %w[string int boolean enum string[] object object[]]
  canonical_valid = expected.all? do |size, values|
    field = canonical.fetch(size)
    field.fetch("type") == "string[]" && field.fetch("enum_values") == values &&
      field.fetch("min_items") == values.length && field.fetch("max_items") == values.length &&
      field.fetch("validation").include?("unique") && field.fetch("validation").include?("exact")
  end
  required = [["p-contract", "s-api", "contract", "contract_and_test_oracle", "api"], ["p-contract", "s-api", "contract", "contract_and_test_oracle", "negative-path"]]
  complete = required.dup
  omitted_obligation = required.reject { |tuple| tuple.last == "negative-path" }
  blocked = required.map { |tuple| tuple + [tuple.last == "api" ? "inspected_no_risk" : "blocked"] }
  not_applicable = required.map { |tuple| tuple + [tuple.last == "api" ? "finding" : "not_applicable"] }
  closes = ->(entries) { required.all? { |tuple| entries.any? { |entry| entry.take(5) == tuple && %w[inspected_no_risk finding].include?(entry[5]) } } && entries.all? { |entry| required.include?(entry.take(5)) && %w[inspected_no_risk finding].include?(entry[5]) } }
  plan_closes = ->(scope_size, perspectives) { perspectives.uniq.length == perspectives.length && perspectives.sort == expected.fetch(scope_size).sort }
  duplicate_perspectives = %w[contract_and_test_oracle contract_and_test_oracle]
  missing_perspective = %w[contract_and_test_oracle runtime_lifecycle_and_failure_paths integration_compatibility_and_consumers]
  valid = canonical_valid && closes.call(complete.map { |tuple| tuple + ["inspected_no_risk"] }) && !closes.call(omitted_obligation.map { |tuple| tuple + ["inspected_no_risk"] }) && !closes.call(blocked) && !closes.call(not_applicable) &&
    !plan_closes.call("trivial_small", duplicate_perspectives) && !plan_closes.call("large", missing_perspective) && plan_closes.call("medium", expected.fetch("medium")) &&
    canonical.values.all? { |field| supported_types.include?(field.fetch("type")) } &&
    tuples.key?("coverage_obligation") && coverage.key?("coverage_obligation") && !coverage.key?("scope_item_ids") && ledger.key?("coverage_obligation") &&
    coverage.fetch("status").fetch("validation").include?("inspected_no_risk") && coverage.fetch("status").fetch("validation").include?("not_applicable") &&
    %w[finding_id file line locus invariant failure_mechanism severity evidence smallest_useful_fix description confidence_pct].all? { |name| prebatch.fetch(name).slice("type", "required", "enum_values") == finding.fetch(name).slice("type", "required", "enum_values") } &&
    batch.fetch("required_coverage_tuples").fetch("validation").include?("canonical_discovery_perspectives") && final.fetch("coverage_ledger").fetch("validation").include?("coverage_obligation") &&
    gates.fetch("gates").find { |gate| gate["phase"] == "REVIEW_STEP" }.fetch("exit_assertions").to_h { |item| [item["id"], item] }.fetch("RS_BATCH_AGGREGATION").fetch("check").include?("coverage_obligation")
  exit valid ? 0 : 1
' "$review_handoffs" "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml" "$review_phase_gates"; then
    pass
else
    fail "assistant-review does not exactly close required obligations, canonical perspectives, or typed pre-batch findings"
fi

test_start "assistant-review preserves the full canonical finding projection and explicit delegation"
if ruby -ryaml -e '
  handoffs, output, input, gates = ARGV.map { |path| YAML.load_file(path) }
  reviewer = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_reviewer" }
  batch = reviewer.fetch("context_fields").to_h { |field| [field["name"], field] }.fetch("review_batch").fetch("object_fields").to_h { |field| [field["name"], field] }
  returned = reviewer.fetch("return_fields").find { |field| field["name"] == "findings" }.fetch("object_fields").to_h { |field| [field["name"], field] }
  prebatch = batch.fetch("pre_batch_findings").fetch("object_fields").to_h { |field| [field["name"], field] }.fetch("finding").fetch("object_fields").to_h { |field| [field["name"], field] }
  final = output.fetch("artifacts").find { |item| item["name"] == "final_summary" }.fetch("object_fields").to_h { |field| [field["name"], field] }
  aggregate = final.fetch("aggregated_findings").fetch("object_fields").to_h { |field| [field["name"], field] }
  audit = output.fetch("artifacts").find { |item| item["name"] == "audit_report" }.fetch("object_fields").to_h { |field| [field["name"], field] }.fetch("findings").fetch("object_fields").to_h { |field| [field["name"], field] }
  fields = %w[finding_id file line locus invariant failure_mechanism severity evidence smallest_useful_fix description confidence_pct]
  same_shape = ->(left, right) { fields.all? { |name| left.fetch(name).slice("type", "required", "enum_values") == right.fetch(name).slice("type", "required", "enum_values") } }
  gates_by_id = gates.fetch("gates").find { |gate| gate["phase"] == "REVIEW_STEP" }.fetch("exit_assertions").to_h { |item| [item["id"], item] }
  mode = input.fetch("fields").find { |field| field["name"] == "subagent_execution_mode" }
  valid = same_shape.call(returned, prebatch) && same_shape.call(returned, aggregate) && same_shape.call(returned, audit) &&
    prebatch.fetch("confidence_pct").fetch("validation").include?("spec_review") && aggregate.fetch("confidence_pct").fetch("validation").include?("minimum") &&
    gates_by_id.fetch("RS1").fetch("condition") == "subagent_execution_mode == delegated" &&
    gates_by_id.fetch("RS1B").fetch("condition") == "scope_size in [trivial, small] and subagent_execution_mode == direct_fallback" &&
    mode.fetch("infer_from").include?("applicable trigger") && mode.fetch("infer_from").include?("trivial/small")
  exit valid ? 0 : 1
' "$review_handoffs" "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml" "$review_input" "$review_phase_gates"; then
    pass
else
    fail "assistant-review lacks a lossless finding projection or explicit-trigger delegation"
fi

test_start "assistant-review rejects unsupported perspective field types"
if ruby -ryaml -e '
  handoffs = YAML.load_file(ARGV.fetch(0))
  reviewer = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_reviewer" }
  batch = reviewer.fetch("context_fields").to_h { |field| [field["name"], field] }.fetch("review_batch").fetch("object_fields").to_h { |field| [field["name"], field] }
  topology = batch.fetch("topology").fetch("object_fields").to_h { |field| [field["name"], field] }
  canonical = topology.fetch("canonical_discovery_perspectives").fetch("object_fields")
  supported = %w[string int boolean enum string[] object object[]]
  valid_type = ->(type) { supported.include?(type) }
  valid = canonical.all? { |field| valid_type.call(field.fetch("type")) } && !valid_type.call("enum[]")
  exit valid ? 0 : 1
' "$review_handoffs"; then
    pass
else
    fail "assistant-review allows unsupported enum[] perspective fields"
fi

test_start "assistant-review gives drift precedence over a large score increase"
if ruby -e '
  classify = ->(score_delta, finding_delta) {
    return "DRIFT" if score_delta > 0 && finding_delta >= 0
    return "SUSPICIOUS" if score_delta > 1.0 && finding_delta < 0
    "OTHER"
  }
  exit (classify.call(1.1, -1) == "SUSPICIOUS" && classify.call(1.1, 0) == "DRIFT" && classify.call(1.1, 1) == "DRIFT") ? 0 : 1
' && grep -Fq 'score_delta > 1.0 AND aggregated_finding_count_delta < 0 → SUSPICIOUS' "$FRAMEWORK_DIR/skills/assistant-review/references/score-tracking.md" \
  && grep -Fq 'DRIFT takes precedence whenever finding count is unchanged or increased' "$FRAMEWORK_DIR/skills/assistant-review/references/score-tracking.md"; then
    pass
else
    fail "assistant-review score tracking does not make SUSPICIOUS and DRIFT mutually exclusive"
fi

test_start "assistant-review rubric examples use correct arithmetic"
if ruby -ryaml -e '
  rubric = File.read(ARGV.fetch(0))
  weights = {"correctness" => 0.30, "quality" => 0.20, "architecture" => 0.20, "security" => 0.15, "coverage" => 0.15}
  example = rubric.match(/Example: correctness=([\d.]+), quality=([\d.]+), architecture=([\d.]+), security=([\d.]+), coverage=([\d.]+).*?= ([\d.]+) → REFINE/m)
  return_block = rubric.match(/rubric_scores:\n(?<body>.*?)\n  action: REFINE/m)
  exit 1 unless example && return_block
  example_scores = weights.keys.zip(example.captures.first(5).map(&:to_f)).to_h
  example_total = example_scores.sum { |name, score| score * weights.fetch(name) }.round(2)
  returned = YAML.safe_load("rubric_scores:\n#{return_block[:body]}\n", aliases: false).fetch("rubric_scores")
  return_scores = {"correctness" => returned.fetch("correctness"), "quality" => returned.fetch("code_quality"), "architecture" => returned.fetch("architecture"), "security" => returned.fetch("security"), "coverage" => returned.fetch("test_coverage")}
  return_total = return_scores.sum { |name, score| score * weights.fetch(name) }.round(2)
  exit(example_total == example.captures.last.to_f && return_total == returned.fetch("weighted_score") ? 0 : 1)
' "$FRAMEWORK_DIR/skills/assistant-review/references/review-rubric.md" \
  && grep -Fq 'weighted_score: 3.90' "$FRAMEWORK_DIR/agents/claude/code-reviewer.md" \
  && grep -Fq 'weighted_score: 3.90' "$FRAMEWORK_DIR/agents/claude/reviewer.md" \
  && grep -Fq 'weighted_score: 3.90' "$FRAMEWORK_DIR/skills/assistant-review/references/score-tracking.md"; then
    pass
else
    fail "assistant-review rubric examples do not match the 3.90 arithmetic"
fi

test_start "assistant-review v7 migration wording preserves source and target direction"
if grep -Fq 'Rebuild persisted 6.0 or incompatible 7.0 under 7.1 from a fresh snapshot' "$FRAMEWORK_DIR/skills/assistant-review/references/review-batch.md" \
  && ! grep -Fq 'Rebuild 7.1 from' "$FRAMEWORK_DIR/skills/assistant-review/references/review-batch.md"; then
    pass
else
    fail "assistant-review review-batch migration wording reverses the v6-to-v7 rebuild direction"
fi

test_start "assistant-review correlates active attempts, QA obligations, and finding closure"
if ruby -ryaml -e '
  handoffs, output, gates = ARGV.map { |path| YAML.load_file(path) }
  reviewer = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_reviewer" }
  qa = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_qa_evaluator" }
  fields = reviewer.fetch("context_fields").to_h { |field| [field["name"], field] }
  batch = fields.fetch("review_batch").fetch("object_fields").to_h { |field| [field["name"], field] }
  attempts = batch.fetch("pass_attempt_ledger").fetch("object_fields").to_h { |field| [field["name"], field] }
  returned = reviewer.fetch("return_fields").to_h { |field| [field["name"], field] }
  coverage = returned.fetch("coverage_entries").fetch("object_fields").to_h { |field| [field["name"], field] }
  qa_return = qa.fetch("return_fields").to_h { |field| [field["name"], field] }
  qa_finding = qa_return.fetch("acceptance_findings").fetch("object_fields").to_h { |field| [field["name"], field] }
  final = output.fetch("artifacts").find { |item| item["name"] == "final_summary" }.fetch("object_fields").to_h { |field| [field["name"], field] }
  ledger = final.fetch("aggregation_ledger").fetch("object_fields").to_h { |field| [field["name"], field] }
  aggregate = final.fetch("aggregated_findings").fetch("object_fields").to_h { |field| [field["name"], field] }
  qa_output = output.fetch("artifacts").find { |item| item["name"] == "qa_evaluation_result" }.fetch("object_fields").to_h { |field| [field["name"], field] }
  qa_output_finding = qa_output.fetch("acceptance_findings").fetch("object_fields").to_h { |field| [field["name"], field] }
  bundle = handoffs.fetch("dispatch_context_bundles").find { |item| item["name"] == "fresh_reviewer_context" }
  qa_shape = %w[severity criterion evidence impact recommendation disposition]
  review_gates = gates.fetch("gates").find { |item| item["phase"] == "REVIEW_STEP" }.fetch("exit_assertions").to_h { |item| [item["id"], item] }
  qa_gates = gates.fetch("gates").find { |item| item["phase"] == "QA_EVALUATION_STEP" }.fetch("exit_assertions").to_h { |item| [item["id"], item] }
  attempt_fields = attempts.fetch("attempts").fetch("object_fields").to_h { |field| [field["name"], field] }
  events = attempt_fields.fetch("response_events").fetch("object_fields").to_h { |field| [field["name"], field] }
  valid = fields.key?("review_attempt_id") && returned.key?("review_attempt_id") && attempts.key?("active_terminal_attempt_id") &&
    events.fetch("disposition").fetch("enum_values") == %w[active_terminal stale duplicate] && attempt_fields.fetch("review_attempt_id").fetch("required") == true &&
    coverage.fetch("finding_ids").fetch("condition") == "status == finding" && ledger.fetch("source_finding_ids").fetch("min_items") == 1 && aggregate.fetch("source_finding_ids").fetch("min_items") == 1 &&
    qa_shape.all? { |name| qa_finding.fetch(name).slice("type", "required", "enum_values") == qa_output_finding.fetch(name).slice("type", "required", "enum_values") } &&
    qa_return.fetch("approved_feature_preparation_qa_acceptance_obligation_result").fetch("required") == "conditional" && qa_output.fetch("approved_feature_preparation_qa_acceptance_obligation_result").fetch("required") == "conditional" &&
    qa_gates.fetch("QA3").fetch("check").include?("approved_feature_preparation_qa_acceptance_obligation_result") && qa_gates.fetch("QA5").fetch("check").include?("fulfilled") &&
    bundle.fetch("selected_dispatch_context_ref") == "handoffs.orchestrator_to_reviewer.reviewer_pass_context_fields" && !bundle.fetch("context_fields_from_dispatch").include?("review_batch") &&
    review_gates.fetch("RS_BATCH_BARRIER").fetch("check").include?("active review_attempt_id") && review_gates.fetch("RS_BATCH_AGGREGATION").fetch("check").include?("source_finding_ids")
  exit valid ? 0 : 1
' "$review_handoffs" "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml" "$review_phase_gates"; then
    pass
else
    fail "assistant-review lacks attempt correlation, canonical QA findings, or exact finding closure"
fi

test_start "assistant-review rejects stale attempts, lossy provenance, and incompatible terminal audit results"
if ruby -ryaml -e '
  handoffs, output, gates = ARGV.map { |path| YAML.load_file(path) }
  reviewer = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_reviewer" }
  qa = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_qa_evaluator" }
  fields = reviewer.fetch("context_fields").to_h { |field| [field["name"], field] }
  batch = fields.fetch("review_batch").fetch("object_fields").to_h { |field| [field["name"], field] }
  ledger = batch.fetch("pass_attempt_ledger").fetch("object_fields").to_h { |field| [field["name"], field] }
  returned = reviewer.fetch("return_fields").to_h { |field| [field["name"], field] }
  coverage = returned.fetch("coverage_entries").fetch("object_fields").to_h { |field| [field["name"], field] }
  audit = output.fetch("artifacts").find { |item| item["name"] == "audit_report" }.fetch("object_fields").to_h { |field| [field["name"], field] }.fetch("findings").fetch("object_fields").to_h { |field| [field["name"], field] }
  final = output.fetch("artifacts").find { |item| item["name"] == "final_summary" }.fetch("object_fields").to_h { |field| [field["name"], field] }
  qa_result = qa.fetch("return_fields").to_h { |field| [field["name"], field] }.fetch("approved_feature_preparation_qa_acceptance_obligation_result").fetch("object_fields").to_h { |field| [field["name"], field] }
  qa_output = output.fetch("artifacts").find { |item| item["name"] == "qa_evaluation_result" }.fetch("object_fields").to_h { |field| [field["name"], field] }.fetch("approved_feature_preparation_qa_acceptance_obligation_result").fetch("object_fields").to_h { |field| [field["name"], field] }
  review = gates.fetch("gates").find { |item| item["phase"] == "REVIEW_STEP" }.fetch("exit_assertions").to_h { |item| [item["id"], item] }
  evaluate = gates.fetch("gates").find { |item| item["phase"] == "EVALUATE_STEP" }.fetch("exit_assertions").to_h { |item| [item["id"], item] }
  active_terminal = ->(records, active) { records.count { |record| record["review_attempt_id"] == active && record.fetch("response_events", []).count { |event| event["disposition"] == "active_terminal" } == 1 } == 1 }
  late_a_active_b = active_terminal.call([{"review_attempt_id" => "A", "response_events" => [{"disposition" => "stale"}]}, {"review_attempt_id" => "B", "response_events" => [{"disposition" => "active_terminal"}]}], "B")
  duplicate_b = active_terminal.call([{"review_attempt_id" => "A", "response_events" => [{"disposition" => "stale"}]}, {"review_attempt_id" => "B", "response_events" => [{"disposition" => "active_terminal"}, {"disposition" => "duplicate"}]}], "B")
  all_stale = active_terminal.call([{"review_attempt_id" => "A", "response_events" => [{"disposition" => "stale"}]}], "B")
  wrong_active = active_terminal.call([{"review_attempt_id" => "A", "response_events" => [{"disposition" => "active_terminal"}]}], "B")
  severity = {"nit" => 0, "should-fix" => 1, "must-fix" => 2}
  source = [{"severity" => "nit"}, {"severity" => "must-fix"}]
  valid = ledger.key?("attempts") && ledger.key?("active_terminal_attempt_id") && ledger.fetch("attempts").fetch("type") == "object[]" &&
    late_a_active_b && duplicate_b && !all_stale && !wrong_active &&
    returned.fetch("review_attempt_id").fetch("required") == true && coverage.fetch("finding_ids").fetch("condition") == "status == finding" &&
    audit.fetch("source_finding_ids").fetch("min_items") == 1 && final.key?("final_snapshot_identity") &&
    qa_result.key?("requested_scope") && qa_result.key?("execution_prerequisite") && qa_result.key?("feature_preparation_scope") && !qa_result.key?("source_binding") &&
    %w[requested_scope execution_prerequisite feature_preparation_scope source_feature_preparation_evidence_ref source_preparation_basis].all? { |name| qa_result.fetch(name).slice("type", "required", "condition", "enum_values", "validation") == qa_output.fetch(name).slice("type", "required", "condition", "enum_values", "validation") } &&
    severity.fetch(source.map { |finding| finding.fetch("severity") }.max_by { |value| severity.fetch(value) }) == 2 &&
    evaluate.fetch("EV4").fetch("check").include?("complete or incomplete") && evaluate.fetch("EV8").fetch("check").include?("complete or incomplete")
  exit valid ? 0 : 1
' "$review_handoffs" "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml" "$review_phase_gates"; then
    pass
else
    fail "assistant-review lacks active-attempt, typed-QA, provenance, or incomplete-audit safeguards"
fi

test_start "assistant-review v7 invalidates real v6 packets with Unicode-safe collision IDs"
if ruby -ryaml -e '
  input, handoffs, output = ARGV.map { |path| YAML.load_file(path) }
  reviewer = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_reviewer" }
  bundle = handoffs.fetch("dispatch_context_bundles").find { |entry| entry["name"] == "fresh_reviewer_context" }
  require "digest"
  legacy_packet = {
    "schema_version" => "6.0",
    "final_summary" => {"result" => "CLEAN", "final_review_snapshot_id" => "legacy-snapshot"},
    "previously_fixed" => [
      {"description" => "standalone", "fixed_in_round" => 1},
      {"description" => "e\u0301", "fixed_in_round" => 2},
      {"description" => "\u00e9", "fixed_in_round" => 2}
    ]
  }
  base = ->(record) { "legacy-v6:#{record.fetch("fixed_in_round")}:#{Digest::SHA256.hexdigest(record.fetch("description").unicode_normalize(:nfc).encode("UTF-8"))[0, 24]}" }
  migrate_ids = ->(records) {
    groups = records.each_with_index.group_by { |record, _index| base.call(record) }
    records.each_with_index.map do |record, index|
      members = groups.fetch(base.call(record))
      members.length == 1 ? base.call(record) : "#{base.call(record)}:#{members.index { |_member, member_index| member_index == index } + 1}"
    end
  }
  migrated_ids = migrate_ids.call(legacy_packet.fetch("previously_fixed"))
  current_schema_version = input.fetch("schema_version")
  migration = {"source_schema_version" => legacy_packet.fetch("schema_version"), "batch_disposition" => "invalidated_rebuild_required", "rebuilt_review_snapshot_id" => "fresh-v#{current_schema_version}-snapshot"}
  legacy_v7_packet = {"schema_version" => "7.0", "final_summary" => {"result" => "CLEAN"}}
  can_claim_clean = ->(packet, migration_state) { packet.fetch("schema_version") == "7.1" && migration_state.fetch("batch_disposition") != "invalidated_rebuild_required" }
  previously_fixed = input.fetch("fields").find { |field| field["name"] == "previously_fixed" }.fetch("object_fields").to_h { |field| [field["name"], field] }
  migration_contract = input.fetch("fields").find { |field| field["name"] == "persisted_v6_packet_migration" }
  v7_invalidation = input.fetch("fields").find { |field| field["name"] == "persisted_v7_0_packet_invalidation" }
  pass_fields = reviewer.fetch("context_fields").map { |field| field.fetch("name") }
  final = output.fetch("artifacts").find { |item| item["name"] == "final_summary" }.fetch("object_fields").to_h { |field| [field["name"], field] }
  valid = legacy_packet.fetch("schema_version") == "6.0" && legacy_packet.dig("final_summary", "result") == "CLEAN" &&
    migrated_ids[0] == base.call(legacy_packet.fetch("previously_fixed")[0]) && migrated_ids[1].end_with?(":1") && migrated_ids[2].end_with?(":2") && migrated_ids[1] != migrated_ids[2] &&
    migration.fetch("source_schema_version") == "6.0" && migration.fetch("batch_disposition") == "invalidated_rebuild_required" && !can_claim_clean.call(legacy_packet, migration) && !can_claim_clean.call(legacy_v7_packet, {"batch_disposition" => "current"}) &&
    previously_fixed.fetch("aggregate_finding_id").fetch("condition") == "entry was created under producer schema 7.1 or later" &&
    migration_contract.fetch("description").include?(current_schema_version) && migration_contract.fetch("validation").include?("freshly rehashed #{current_schema_version} snapshot") && migration_contract.fetch("object_fields").find { |field| field["name"] == "rebuilt_snapshot_identity" }.fetch("description").include?(current_schema_version) &&
    migration_contract.fetch("validation").include?("UTF-8 NFC") && migration_contract.fetch("validation").include?("SHA-256") && migration_contract.fetch("validation").downcase.include?("invalidate") &&
    migration_contract.fetch("validation").downcase.include?("non-colliding records use") && migration_contract.fetch("validation").include?("every colliding record appends") &&
    v7_invalidation.fetch("condition").include?("7.0") && v7_invalidation.fetch("validation").include?("do not reinterpret") && v7_invalidation.fetch("validation").include?("7.1") &&
    bundle.fetch("context_fields_from_dispatch").include?("review_focus") && pass_fields.include?("review_focus") &&
    bundle.fetch("review_evidence_pointer").fetch("required_refs").include?("review_material_snapshot") &&
    !bundle.fetch("review_evidence_pointer").fetch("required_refs").include?("review_material_snapshot_ref") &&
    final.fetch("final_review_snapshot_id").fetch("validation").downcase.include?("exactly equals current review_snapshot_id")
  exit valid ? 0 : 1
' "$review_input" "$review_handoffs" "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml"; then
    pass
else
    fail "assistant-review lacks v7 invalidate/rebuild migration, Unicode-safe legacy IDs, pass-only focus, or final identity binding"
fi

test_start "assistant-review enforces orchestrator terminals, response events, and exact batch closure"
if ruby -ryaml -e '
  handoffs, output, gates = ARGV.map { |path| YAML.load_file(path) }
  reviewer = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_reviewer" }
  context = reviewer.fetch("context_fields").to_h { |field| [field["name"], field] }
  returns = reviewer.fetch("return_fields").to_h { |field| [field["name"], field] }
  batch = context.fetch("review_batch").fetch("object_fields").to_h { |field| [field["name"], field] }
  attempts = batch.fetch("pass_attempt_ledger").fetch("object_fields").to_h { |field| [field["name"], field] }
  attempt = attempts.fetch("attempts").fetch("object_fields").to_h { |field| [field["name"], field] }
  final = output.fetch("artifacts").find { |item| item["name"] == "final_summary" }.fetch("object_fields").to_h { |field| [field["name"], field] }
  ledger = final.fetch("aggregation_ledger").fetch("object_fields").to_h { |field| [field["name"], field] }
  summaries = final.fetch("batch_summaries").fetch("object_fields").to_h { |field| [field["name"], field] }
  terminal = ->(records, active) {
    records.length.between?(1, 2) && records.map { |r| r["attempt_count"] } == (1..records.length).to_a &&
      records.map { |r| r["review_attempt_id"] }.uniq.length == records.length &&
      records.count { |r| r["review_attempt_id"] == active && r["response_events"].count { |e| e["disposition"] == "active_terminal" } == 1 } == 1
  }
  good = [{"review_attempt_id"=>"A", "attempt_count"=>1, "response_events"=>[{"response_event_id"=>"e1", "disposition"=>"stale"}]}, {"review_attempt_id"=>"B", "attempt_count"=>2, "response_events"=>[{"response_event_id"=>"e2", "disposition"=>"active_terminal"}, {"response_event_id"=>"e3", "disposition"=>"duplicate"}]}]
  bad_three = good + [{"review_attempt_id"=>"C", "attempt_count"=>3, "response_events"=>[]}]
  bad_pending = [{"review_attempt_id"=>"A", "attempt_count"=>1, "response_events"=>[{"response_event_id"=>"e1", "disposition"=>"active_terminal"}]}, {"review_attempt_id"=>"B", "attempt_count"=>2, "response_events"=>[]}]
  tuple = ->(required, returned) { required.sort == returned.sort && returned.all? { |t| t.length == 5 } }
  required = [["p1", "s1", "contract", "contract_and_test_oracle", "api"]]
  valid = !returns.key?("terminal_pass_state") && returns.fetch("status").fetch("enum_values") == %w[DONE DONE_WITH_CONCERNS NEEDS_CONTEXT BLOCKED] &&
    attempt.key?("response_events") && attempt.fetch("response_events").fetch("type") == "object[]" && attempt["response_disposition"].nil? &&
    terminal.call(good, "B") && !terminal.call(bad_three, "B") && !terminal.call(bad_pending, "B") &&
    ledger.fetch("source_finding_ids").fetch("required") == "conditional" && ledger.key?("source_coverage_gap_ids") &&
    summaries.key?("started_batch_ordinal") && summaries.fetch("started_batch_ordinal").fetch("validation").include?("contiguous") &&
    !tuple.call(required, []) && !tuple.call(required, required + [["p1", "s1", "contract", "contract_and_test_oracle", "extra"]])
  exit valid ? 0 : 1
' "$review_handoffs" "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml" "$review_phase_gates"; then
    pass
else
    fail "assistant-review lacks orchestrator terminal ownership, response-event lifecycle, or exact gap closure"
fi

test_start "assistant-review audit, repair, small-scope, and prompt routes preserve complete batches"
route_failures=()
for file_and_term in \
    "$review_skill::audit retains the Spec Review mismatch as an aggregate finding and continues a frozen read-only multi-pass batch" \
    "$review_loop::stay read-only" \
    "$review_phase_gates::continues the frozen read-only multi-pass batch" \
    "$review_handoffs::at most one transient/schema repair" \
    "$review_handoffs::recompute the current scope-manifest/content identity at the response barrier and immediately before final exit" \
    "$review_handoffs::direct_fallback" \
    "$review_loop::trivial/small uses two purpose-specific isolated direct-fallback passes" \
    "$review_evals::audit-spec-review-fail-continues-complete-batch" \
    "$review_evals::in-flight-mutation-invalidates-review-batch" \
    "$review_evals::trivial-audit-uses-two-isolated-passes"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        route_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
for prompt in \
    "$FRAMEWORK_DIR/agents/codex/code-reviewer.toml" \
    "$FRAMEWORK_DIR/agents/codex/reviewer.toml" \
    "$FRAMEWORK_DIR/agents/claude/code-reviewer.md" \
    "$FRAMEWORK_DIR/agents/claude/reviewer.md"; do
    for term in 'locus' 'failure_mechanism' 'smallest_useful_fix' 'For round 3 or later, require `additional_round_reason`' 'No material findings within the reviewed scope and available evidence' 'scope_item_id' 'applicable_concern' 'coverage_obligation' 'inspected_no_risk' 'snapshot_identity' 'basis' 'value' 'captured_at' 'scope_manifest_digest' 'review_attempt_id' 'finding_ids' 'regressions' 'QA'; do
        if ! grep -Fq -- "$term" "$prompt"; then route_failures+=("${prompt#$FRAMEWORK_DIR/}: missing $term"); fi
    done
done
if [[ ${#route_failures[@]} -eq 0 ]]; then
    pass
else
    fail "assistant-review batch routing or prompt parity is incomplete: ${route_failures[*]}"
fi

test_start "assistant-review v7 fail-closes response, mutation, identity, QA, and legacy lifecycle seams"
if ruby -ryaml -e '
  input, output, handoffs, gates = ARGV.map { |path| YAML.load_file(path) }
  reviewer = handoffs.fetch("handoffs").find { |item| item["name"] == "orchestrator_to_reviewer" }
  context = reviewer.fetch("context_fields").to_h { |field| [field["name"], field] }
  returns = reviewer.fetch("return_fields").to_h { |field| [field["name"], field] }
  batch = context.fetch("review_batch").fetch("object_fields").to_h { |field| [field["name"], field] }
  attempts = batch.fetch("pass_attempt_ledger").fetch("object_fields").to_h { |field| [field["name"], field] }.fetch("attempts").fetch("object_fields").to_h { |field| [field["name"], field] }
  expected = batch.fetch("expected_passes").fetch("object_fields").to_h { |field| [field["name"], field] }
  tuples = batch.fetch("required_coverage_tuples").fetch("validation")
  manifest = input.fetch("fields").find { |field| field["name"] == "review_material_snapshot" }.fetch("object_fields").to_h { |field| [field["name"], field] }.fetch("scope_manifest").fetch("object_fields").to_h { |field| [field["name"], field] }
  identity = input.fetch("fields").find { |field| field["name"] == "review_material_snapshot" }.fetch("object_fields").to_h { |field| [field["name"], field] }.fetch("snapshot_identity").fetch("object_fields")
  final = output.fetch("artifacts").find { |item| item["name"] == "final_summary" }.fetch("object_fields").to_h { |field| [field["name"], field] }
  final_identity = final.fetch("final_snapshot_identity").fetch("object_fields")
  qa = handoffs.fetch("handoffs").find { |item| item["name"] == "orchestrator_to_qa_evaluator" }
  qa_context = qa.fetch("context_fields").to_h { |field| [field["name"], field] }
  qa_return = qa.fetch("return_fields").to_h { |field| [field["name"], field] }
  review_gates = gates.fetch("gates").find { |item| item["phase"] == "REVIEW_STEP" }.fetch("exit_assertions").to_h { |item| [item["id"], item] }
  qa_gates = gates.fetch("gates").find { |item| item["phase"] == "QA_EVALUATION_STEP" }.fetch("exit_assertions").to_h { |item| [item["id"], item] }
  exact_multiset = ->(required, actual) { required.group_by { |entry| entry }.transform_values(&:length) == actual.group_by { |entry| entry }.transform_values(&:length) }
  required = [["p1", "s1", "contract", "contract_and_test_oracle", "api"]]
  response_terminal = ->(events) { events.count { |event| event["disposition"] == "active_terminal" } == 1 }
  synthetic_failure = ->(events, kind, evidence) { events.none? { |event| event["disposition"] == "active_terminal" } && %w[timeout transport schema_invalid source_mutation].include?(kind) && !evidence.empty? }
  truth = returns.fetch("status").fetch("validation")
  valid = [input, output, handoffs, gates].all? { |schema| schema.fetch("schema_version") == "7.1" } &&
    identity == final_identity && final_identity.find { |field| field["name"] == "basis" }.fetch("type") == "enum" &&
    final.fetch("final_review_snapshot_id").fetch("validation").downcase.include?("exactly equals current review_snapshot_id") &&
    manifest.fetch("scope_item_id").fetch("validation").downcase.include?("unique") && manifest.fetch("applicable_concerns").fetch("validation").downcase.include?("unique") &&
    expected.fetch("review_pass_id").fetch("validation").downcase.include?("unique") && expected.fetch("assigned_scope").fetch("validation").downcase.include?("unique") && expected.fetch("coverage_obligations").fetch("validation").downcase.include?("unique") &&
    tuples.include?("exact multiset") && exact_multiset.call(required, required) && !exact_multiset.call(required, required + required) &&
    attempts.fetch("failure_kind").fetch("enum_values") == %w[timeout transport schema_invalid source_mutation] &&
    attempts.fetch("response_events").fetch("validation").include?("exactly one active_terminal") && attempts.fetch("failure_evidence").fetch("validation").include?("typed failure") &&
    response_terminal.call([{"disposition" => "active_terminal"}]) && !response_terminal.call([]) && synthetic_failure.call([], "timeout", "deadline exceeded") && !synthetic_failure.call([], "timeout", "") &&
    returns.fetch("findings").fetch("object_fields").find { |field| field["name"] == "finding_id" }.fetch("validation").include?("review_pass_id namespace") &&
    returns.fetch("closure_results").fetch("object_fields").any? { |field| field["name"] == "aggregate_finding_id" } && !returns.fetch("closure_results").fetch("object_fields").any? { |field| field["name"] == "finding_id" } &&
    returns.fetch("verdict").fetch("enum_values").include?("not_assessed") && truth.include?("DONE => completed") && truth.include?("DONE_WITH_CONCERNS => completed") && truth.include?("NEEDS_CONTEXT => needs_context") && truth.include?("BLOCKED => blocked") &&
    returns.fetch("open_questions").fetch("required") == "conditional" &&
    review_gates.fetch("RS_BATCH_BARRIER").fetch("check").downcase.include?("response-backed") && review_gates.fetch("RS_BATCH_BARRIER").fetch("check").include?("typed failure evidence") &&
    qa_context.fetch("code_review_result").fetch("validation").include?("fresh complete final review batch") && qa_context.fetch("code_review_result").fetch("validation").include?("digest equality") &&
    qa_return.fetch("approved_feature_preparation_qa_acceptance_obligation_result").fetch("validation").include?("accepted_with_concerns") &&
    qa_gates.fetch("QA5").fetch("check").include?("accepted_with_concerns/ISSUES_FIXED") &&
    qa_gates.fetch("QA5").fetch("check").include?("requested_scope_status=fulfilled") &&
    handoffs.fetch("worker_status_protocol").fetch("packet_rules").join(" ").include?("6.0") && handoffs.fetch("worker_status_protocol").fetch("packet_rules").join(" ").include?("7.0") &&
    handoffs.fetch("worker_status_protocol").fetch("packet_rules").join(" ").include?("UTF-8 NFC") && handoffs.fetch("worker_status_protocol").fetch("packet_rules").join(" ").include?("SHA-256") &&
    batch.fetch("expected_passes").fetch("validation").include?("assistant-security checklist/perspective") &&
    review_gates.fetch("RS2").fetch("check").include?("assistant-security checklist/perspective")
  exit valid ? 0 : 1
' "$review_input" "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml" "$review_handoffs" "$review_phase_gates"; then
    pass
else
    fail "assistant-review v7 lifecycle contract does not fail-close active responses, mutation, identity, QA, or legacy packet migration"
fi

test_start "assistant-review v7 nested packet oracle rejects schema and lifecycle mutations"
if ruby -ryaml -e '
  input, handoffs, output = ARGV.map { |path| YAML.load_file(path) }
  reviewer_handoff = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_reviewer" }
  qa_handoff = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_qa_evaluator" }
  reviewer_fields = reviewer_handoff.fetch("return_fields")
  qa_return_fields = qa_handoff.fetch("return_fields")
  qa_context_fields = qa_handoff.fetch("context_fields").to_h { |field| [field["name"], field] }
  final_fields = output.fetch("artifacts").find { |entry| entry["name"] == "final_summary" }.fetch("object_fields")
  final_field_map = final_fields.to_h { |field| [field["name"], field] }
  batch_summary_fields = final_field_map.fetch("batch_summaries").fetch("object_fields").to_h { |field| [field["name"], field] }
  batch_identity_fields = batch_summary_fields.fetch("snapshot_identity").fetch("object_fields")
  identity = {"basis" => "content_digest", "value" => "sha256:review", "captured_at" => "2026-08-26T00:00:00Z", "scope_manifest_digest" => "sha256:scope"}
  manifest = [{"scope_item_id" => "item-1", "locator" => "contracts/example.yaml", "content_digest" => "sha256:item", "applicable_concerns" => ["contract"]}]
  expected_passes = [
    {"review_pass_id" => "pass-contract", "perspective" => "contract_and_test_oracle", "assigned_scope" => ["item-1"], "coverage_obligations" => ["contract"], "prior_finding_visibility" => "none"},
    {"review_pass_id" => "pass-runtime", "perspective" => "runtime_lifecycle_and_failure_paths", "assigned_scope" => ["item-1"], "coverage_obligations" => ["runtime"], "prior_finding_visibility" => "none"}
  ]
  topology = {"discovery_pass_count" => 2, "canonical_discovery_perspectives" => {"trivial_small" => %w[contract_and_test_oracle runtime_lifecycle_and_failure_paths], "medium" => %w[contract_and_test_oracle runtime_lifecycle_and_failure_paths integration_compatibility_and_consumers], "large" => %w[contract_and_test_oracle runtime_lifecycle_and_failure_paths integration_compatibility_and_consumers architecture_maintainability_and_reuse]}, "security_specialist_triggered" => false, "closure_verification_required" => false, "max_required_responses" => 2, "max_repair_attempts_per_pass" => 1}
  tuples = expected_passes.map { |pass| {"review_pass_id" => pass["review_pass_id"], "scope_item_id" => "item-1", "applicable_concern" => "contract", "review_perspective" => pass["perspective"], "coverage_obligation" => pass["coverage_obligations"].first} }
  coverage = ->(pass) { {"scope_item_id" => "item-1", "applicable_concern" => "contract", "review_perspective" => pass["perspective"], "coverage_obligation" => pass["coverage_obligations"].first, "status" => "inspected_no_risk", "evidence" => "inspected #{pass["review_pass_id"]}"} }
  reviewer_return = ->(pass) {
    {"status" => "DONE", "round" => 1, "batch_id" => "batch-1", "review_snapshot_id" => "snapshot-1", "snapshot_identity" => identity,
     "review_pass_id" => pass["review_pass_id"], "review_attempt_id" => "#{pass["review_pass_id"]}:attempt-1", "review_perspective" => pass["perspective"], "pass_completion_state" => "completed",
     "reviewed_scope" => ["item-1"], "findings" => [], "coverage_entries" => [coverage.call(pass)], "summary" => "inspected #{pass["perspective"]}",
     "evidence" => [{"source" => "contracts/example.yaml", "detail" => "reviewed"}], "reuse_search" => {"applicability" => "not_applicable", "applicability_reason" => "no rule-like change"}, "verdict" => "clean"}
  }
  returns = expected_passes.map { |pass| reviewer_return.call(pass) }
  attempts = expected_passes.map do |pass|
    attempt_id = "#{pass["review_pass_id"]}:attempt-1"
    {"review_pass_id" => pass["review_pass_id"], "active_terminal_attempt_id" => attempt_id, "attempts" => [{"review_attempt_id" => attempt_id, "attempt_count" => 1, "record_state" => "terminal", "terminal_state" => "completed", "repair_disposition" => "not_needed", "response_events" => [{"response_event_id" => "#{attempt_id}:response", "dispatch_attempt_id" => attempt_id, "disposition" => "active_terminal"}]}]}
  end
  final_summary = {
    "reviewed_scope" => ["item-1"], "rounds" => 1, "final_review_snapshot_id" => "snapshot-1", "final_snapshot_identity" => identity, "coverage_complete" => true,
    "final_batch_plan" => {"batch_id" => "batch-1", "review_snapshot_id" => "snapshot-1", "scope_size" => "small", "topology" => topology, "expected_passes" => expected_passes, "required_coverage_tuples" => tuples},
    "coverage_ledger" => tuples.map { |tuple| {"batch_id" => "batch-1", "review_snapshot_id" => "snapshot-1", "review_pass_id" => tuple["review_pass_id"], "perspective" => tuple["review_perspective"], "coverage_obligation" => tuple["coverage_obligation"], "assigned_scope" => ["item-1"], "scope_item_id" => "item-1", "applicable_concern" => "contract", "terminal_state" => "completed", "coverage_status" => "complete", "coverage_disposition" => "inspected_no_risk", "evidence" => "reviewed"} },
    "batch_summaries" => [{"started_batch_ordinal" => 1, "batch_id" => "batch-1", "review_snapshot_id" => "snapshot-1", "snapshot_identity" => identity, "batch_status" => "complete", "expected_response_count" => 2, "terminal_response_count" => 2, "aggregate_rubric_recomputed" => true}],
    "aggregation_ledger" => [], "aggregated_findings" => [], "result" => "CLEAN", "evidence_bounded_claim" => "No material findings within the reviewed scope and available evidence", "fixed_items" => [], "nits" => []
  }
  qa_return = {"status" => "DONE", "round" => 1, "acceptance_findings" => [], "qa_scorecard" => {"acceptance_coverage" => 5.0, "evidence_strength" => 5.0, "domain_quality" => 5.0, "final_readiness" => 5.0, "weighted_score" => 5.0, "rationale" => {"acceptance_coverage" => "covered", "evidence_strength" => "current", "domain_quality" => "not_applicable", "final_readiness" => "ready"}}, "final_verdict" => "accepted", "result" => "CLEAN", "evidence" => [{"source" => "test", "detail" => "passed"}], "score_entry" => {"round" => 1, "weighted_score" => 5.0, "failed_acceptance_count" => 0, "delta" => "initial", "drift_status" => "NEUTRAL"}}
  packet = {"review_material_snapshot" => {"review_snapshot_id" => "snapshot-1", "snapshot_identity" => identity, "scope_manifest" => manifest}, "review_batch" => {"batch_id" => "batch-1", "review_snapshot_id" => "snapshot-1", "topology" => topology, "expected_passes" => expected_passes, "required_coverage_tuples" => tuples, "pass_attempt_ledger" => attempts}, "reviewer_returns" => returns, "final_summary" => final_summary, "qa_packet" => {"code_review_result" => {"role" => "Reviewer", "result" => "CLEAN", "rounds" => 1, "final_review_snapshot_id" => "snapshot-1", "final_snapshot_identity" => identity, "coverage_complete" => true, "remaining_risks" => []}, "return" => qa_return}}
  duplicate = ->(value) { Marshal.load(Marshal.dump(value)) }
  type_ok = ->(value, type) {
    case type
    when "string" then value.is_a?(String)
    when "int" then value.is_a?(Integer)
    when "float" then value.is_a?(Numeric)
    when "boolean" then value == true || value == false
    when "string[]" then value.is_a?(Array) && value.all? { |item| item.is_a?(String) }
    when "object" then value.is_a?(Hash)
    when "object[]" then value.is_a?(Array)
    when "enum" then value.is_a?(String)
    else false
    end
  }
  shape_ok = nil
  shape_ok = ->(value, fields) {
    return false unless value.is_a?(Hash)
    names = fields.map { |field| field["name"] }
    return false unless (value.keys - names).empty?
    fields.all? do |field|
      name = field["name"]
      next false if field["required"] == true && !value.key?(name)
      next true unless value.key?(name)
      item = value[name]
      next false unless type_ok.call(item, field["type"])
      next false if field["type"] == "enum" && field["enum_values"] && !field["enum_values"].include?(item)
      next false if field["min_items"] && item.respond_to?(:length) && item.length < field["min_items"]
      children = field["object_fields"]
      if children && field["type"] == "object"
        shape_ok.call(item, children)
      elsif children && field["type"] == "object[]"
        item.all? { |entry| shape_ok.call(entry, children) }
      else
        true
      end
    end
  }
  tuple_key = ->(tuple) { %w[review_pass_id scope_item_id applicable_concern review_perspective coverage_obligation].map { |key| tuple[key] }.join("\u0000") }
  reviewer_valid = ->(reply, pass, full_packet) {
    return false unless shape_ok.call(reply, reviewer_fields)
    return false unless reply["batch_id"] == full_packet.dig("review_batch", "batch_id") && reply["review_snapshot_id"] == full_packet.dig("review_material_snapshot", "review_snapshot_id") && reply["snapshot_identity"] == full_packet.dig("review_material_snapshot", "snapshot_identity")
    return false unless reply["review_pass_id"] == pass["review_pass_id"] && reply["review_attempt_id"] == "#{pass["review_pass_id"]}:attempt-1" && reply["review_perspective"] == pass["perspective"] && reply["reviewed_scope"] == pass["assigned_scope"]
    coverage_keys = reply["coverage_entries"].map { |entry| [reply["review_pass_id"], entry["scope_item_id"], entry["applicable_concern"], entry["review_perspective"], entry["coverage_obligation"]].join("\u0000") }
    required_keys = full_packet.dig("review_batch", "required_coverage_tuples").select { |tuple| tuple["review_pass_id"] == pass["review_pass_id"] }.map { |tuple| tuple_key.call(tuple) }
    return false unless coverage_keys == required_keys
    case reply["status"]
    when "DONE" then reply["pass_completion_state"] == "completed" && reply["verdict"] == "clean" && reply["findings"].empty? && reply["coverage_entries"].all? { |entry| %w[inspected_no_risk finding].include?(entry["status"]) } && !reply.key?("open_questions")
    when "DONE_WITH_CONCERNS" then reply["pass_completion_state"] == "completed" && %w[has_must_fix has_should_fix has_nits_only].include?(reply["verdict"]) && !reply["findings"].empty? && reply["coverage_entries"].all? { |entry| %w[inspected_no_risk finding].include?(entry["status"]) } && !reply.key?("open_questions")
    when "NEEDS_CONTEXT" then reply["pass_completion_state"] == "needs_context" && reply["verdict"] == "not_assessed" && reply["findings"].empty? && reply["coverage_entries"].all? { |entry| entry["status"] == "blocked" } && reply["open_questions"].is_a?(Array) && !reply["open_questions"].empty?
    when "BLOCKED" then reply["pass_completion_state"] == "blocked" && reply["verdict"] == "not_assessed" && reply["findings"].empty? && reply["coverage_entries"].all? { |entry| entry["status"] == "blocked" } && reply["open_questions"].is_a?(Array) && !reply["open_questions"].empty?
    else false
    end
  }
  lifecycle_valid = ->(full_packet) {
    batch = full_packet["review_batch"]
    expected = batch["expected_passes"]
    return false unless expected.map { |entry| entry["review_pass_id"] }.uniq.length == expected.length && expected.all? { |entry| entry["assigned_scope"].uniq == entry["assigned_scope"] && entry["coverage_obligations"].uniq == entry["coverage_obligations"] }
    return false unless batch["required_coverage_tuples"].map { |tuple| tuple_key.call(tuple) }.uniq.length == batch["required_coverage_tuples"].length
    return false unless batch["pass_attempt_ledger"].length == expected.length
    batch["pass_attempt_ledger"].all? do |ledger|
      attempt = ledger["attempts"]&.first
      attempt && ledger["active_terminal_attempt_id"] == attempt["review_attempt_id"] && attempt["record_state"] == "terminal" && attempt["terminal_state"] == "completed" && attempt["response_events"].count { |event| event["disposition"] == "active_terminal" && event["dispatch_attempt_id"] == attempt["review_attempt_id"] } == 1
    end
  }
  final_valid = ->(full_packet) {
    final = full_packet["final_summary"]
    return false unless shape_ok.call(final, final_fields) && final["final_review_snapshot_id"] == full_packet.dig("review_material_snapshot", "review_snapshot_id") && final["final_snapshot_identity"] == full_packet.dig("review_material_snapshot", "snapshot_identity") && final["coverage_complete"] && final["result"] == "CLEAN"
    plan = final.fetch("final_batch_plan")
    return false unless plan["batch_id"] == full_packet.dig("review_batch", "batch_id") && plan["review_snapshot_id"] == full_packet.dig("review_batch", "review_snapshot_id") && plan["scope_size"] == "small" && plan["topology"] == full_packet.dig("review_batch", "topology") && plan["expected_passes"] == full_packet.dig("review_batch", "expected_passes") && plan["required_coverage_tuples"] == full_packet.dig("review_batch", "required_coverage_tuples")
    current = final.fetch("batch_summaries").max_by { |entry| entry.fetch("started_batch_ordinal") }
    return false unless batch_identity_fields.map { |field| field.fetch("name") } == %w[basis value captured_at scope_manifest_digest] && current.fetch("review_snapshot_id") == final.fetch("final_review_snapshot_id") && current.fetch("snapshot_identity") == final.fetch("final_snapshot_identity")
    aggregate_source_ids = final.fetch("aggregated_findings").flat_map { |finding| finding.fetch("source_finding_ids") }
    coverage_dispositions_valid = final.fetch("coverage_ledger").all? do |entry|
      case entry.fetch("coverage_disposition")
      when "inspected_no_risk"
        entry.fetch("coverage_status") == "complete" && !entry.key?("finding_ids")
      when "finding"
        entry.fetch("coverage_status") == "complete" && entry["finding_ids"].is_a?(Array) && !entry["finding_ids"].empty? && entry["finding_ids"].all? { |id| aggregate_source_ids.include?(id) }
      when "incomplete"
        %w[incomplete invalidated].include?(entry.fetch("coverage_status")) && !entry.key?("finding_ids")
      else
        false
      end
    end
    actual = final["coverage_ledger"].map { |entry| [entry["review_pass_id"], entry["scope_item_id"], entry["applicable_concern"], entry["perspective"], entry["coverage_obligation"]].join("\u0000") }
    required = full_packet.dig("review_batch", "required_coverage_tuples").map { |tuple| tuple_key.call(tuple) }
    coverage_dispositions_valid && actual.sort == required.sort && final["coverage_ledger"].all? { |entry| entry["terminal_state"] == "completed" && entry["coverage_status"] == "complete" && entry["coverage_disposition"] == "inspected_no_risk" }
  }
  qa_valid = ->(full_packet) {
    qa = full_packet["qa_packet"]
    return false unless shape_ok.call(qa["return"], qa_return_fields) && shape_ok.call(qa["code_review_result"], qa_context_fields.fetch("code_review_result").fetch("object_fields"))
    code_review = qa["code_review_result"]
    code_review["coverage_complete"] && code_review["final_review_snapshot_id"] == full_packet.dig("final_summary", "final_review_snapshot_id") && code_review["final_snapshot_identity"] == full_packet.dig("final_summary", "final_snapshot_identity") && qa.dig("return", "status") == "DONE" && qa.dig("return", "final_verdict") == "accepted" && qa.dig("return", "result") == "CLEAN"
  }
  packet_valid = ->(full_packet) {
    passes = full_packet.dig("review_batch", "expected_passes")
    lifecycle_valid.call(full_packet) && full_packet["reviewer_returns"].length == passes.length && passes.zip(full_packet["reviewer_returns"]).all? { |pass, reply| reviewer_valid.call(reply, pass, full_packet) } && final_valid.call(full_packet) && qa_valid.call(full_packet)
  }
  finding = {"severity" => "must-fix", "file" => "contracts/example.yaml", "description" => "broken", "confidence_pct" => 95, "finding_id" => "pass-contract:f1", "locus" => "field", "invariant" => "contract", "failure_mechanism" => "missing value", "evidence" => "fixture", "smallest_useful_fix" => "add value"}
  truth_cases = [
    ["DONE", "completed", "clean", [], [{"status" => "inspected_no_risk"}], nil, true],
    ["DONE_WITH_CONCERNS", "completed", "has_must_fix", [finding], [{"status" => "finding", "finding_ids" => ["pass-contract:f1"]}], nil, true],
    ["DONE_WITH_CONCERNS", "completed", "has_should_fix", [finding.merge("severity" => "should-fix")], [{"status" => "finding", "finding_ids" => ["pass-contract:f1"]}], nil, true],
    ["DONE_WITH_CONCERNS", "completed", "has_nits_only", [finding.merge("severity" => "nit")], [{"status" => "finding", "finding_ids" => ["pass-contract:f1"]}], nil, true],
    ["NEEDS_CONTEXT", "needs_context", "not_assessed", [], [{"status" => "blocked"}], ["need scope"], true],
    ["BLOCKED", "blocked", "not_assessed", [], [{"status" => "blocked"}], ["blocked"], true],
    ["DONE", "completed", "clean", [finding], [{"status" => "finding", "finding_ids" => ["pass-contract:f1"]}], nil, false],
    ["DONE_WITH_CONCERNS", "completed", "has_should_fix", [], [{"status" => "inspected_no_risk"}], nil, false],
    ["NEEDS_CONTEXT", "completed", "not_assessed", [], [{"status" => "blocked"}], ["need scope"], false],
    ["BLOCKED", "blocked", "not_assessed", [], [{"status" => "blocked"}], nil, false]
  ]
  truth_results = truth_cases.map do |status, state, verdict, findings, coverage_values, questions, expected_valid|
    trial = reviewer_return.call(expected_passes.first)
    trial["status"] = status; trial["pass_completion_state"] = state; trial["verdict"] = verdict; trial["findings"] = findings; trial["coverage_entries"] = coverage_values.map { |entry| coverage.call(expected_passes.first).merge(entry) }
    questions ? trial["open_questions"] = questions : trial.delete("open_questions")
    reviewer_valid.call(trial, expected_passes.first, packet) == expected_valid
  end
  truth_valid = truth_results.all?
  mutations = {
    "missing" => ->(trial) { trial["reviewer_returns"][0].delete("review_attempt_id") },
    "extra" => ->(trial) { trial["reviewer_returns"][0]["unexpected"] = true },
    "duplicate" => ->(trial) { trial["review_batch"]["expected_passes"] << duplicate.call(trial["review_batch"]["expected_passes"][0]) },
    "stale" => ->(trial) { trial["review_batch"]["pass_attempt_ledger"][0]["attempts"][0]["response_events"][0]["disposition"] = "stale" },
    "invalid_type" => ->(trial) { trial["final_summary"]["rounds"] = "1" },
    "wrong_final_batch_identity" => ->(trial) { trial["final_summary"]["batch_summaries"][0]["snapshot_identity"] = trial["final_summary"]["batch_summaries"][0]["snapshot_identity"].merge("value" => "sha256:stale") },
    "wrong_attempt" => ->(trial) { trial["reviewer_returns"][0]["review_attempt_id"] = "wrong-attempt" },
    "wrong_tuple" => ->(trial) { trial["reviewer_returns"][0]["coverage_entries"][0]["coverage_obligation"] = "wrong" },
    "missing_final_plan_pass" => ->(trial) { trial["final_summary"]["final_batch_plan"]["expected_passes"].pop },
    "missing_final_plan_tuple" => ->(trial) { trial["final_summary"]["final_batch_plan"]["required_coverage_tuples"].pop },
    "missing_coverage_disposition" => ->(trial) { trial["final_summary"]["coverage_ledger"][0].delete("coverage_disposition") },
    "finding_without_ids" => ->(trial) { trial["final_summary"]["coverage_ledger"][0]["coverage_disposition"] = "finding" },
    "unbound_finding_id" => ->(trial) { trial["final_summary"]["coverage_ledger"][0]["coverage_disposition"] = "finding"; trial["final_summary"]["coverage_ledger"][0]["finding_ids"] = ["foreign-finding"] },
    "coordinated_invalid_terminal" => ->(trial) { trial["review_batch"]["pass_attempt_ledger"][0]["attempts"][0]["terminal_state"] = "blocked"; trial["reviewer_returns"][0]["status"] = "BLOCKED"; trial["reviewer_returns"][0]["pass_completion_state"] = "blocked"; trial["reviewer_returns"][0]["verdict"] = "not_assessed"; trial["reviewer_returns"][0]["coverage_entries"] = []; trial["reviewer_returns"][0]["open_questions"] = ["blocked"] }
  }
  mutation_valid = mutations.all? { |_name, mutate| trial = duplicate.call(packet); mutate.call(trial); !packet_valid.call(trial) }
  valid = input.fetch("schema_version") == "7.1" && handoffs.fetch("schema_version") == "7.1" && output.fetch("schema_version") == "7.1" && packet_valid.call(packet) && truth_valid && mutation_valid
  exit valid ? 0 : 1
' "$review_input" "$review_handoffs" "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml"; then
    pass
else
    fail "assistant-review nested v7 packet oracle accepts an invalid schema, truth-table, lifecycle, closure, or QA packet"
fi

test_start "assistant-review behavioral batch oracle rejects topology, barrier, closure, invalidation, and cap escapes"
if ruby -ryaml -rjson -e '
  handoffs, gates, cases = ARGV.then { |paths| [YAML.load_file(paths[0]), YAML.load_file(paths[1]), JSON.parse(File.read(paths[2]))] }
  reviewer = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_reviewer" }
  batch = reviewer.fetch("context_fields").to_h { |field| [field["name"], field] }.fetch("review_batch").fetch("object_fields").to_h { |field| [field["name"], field] }
  canonical = batch.fetch("topology").fetch("object_fields").to_h { |field| [field["name"], field] }.fetch("canonical_discovery_perspectives").fetch("object_fields").to_h { |field| [field["name"], field] }
  expected = { "trivial_small" => %w[contract_and_test_oracle runtime_lifecycle_and_failure_paths], "medium" => %w[contract_and_test_oracle runtime_lifecycle_and_failure_paths integration_compatibility_and_consumers], "large" => %w[contract_and_test_oracle runtime_lifecycle_and_failure_paths integration_compatibility_and_consumers architecture_maintainability_and_reuse] }
  topology_valid = ->(size, perspectives) { perspectives.uniq == perspectives && perspectives.sort == expected.fetch(size).sort }
  barrier_valid = ->(expected_count, terminal_count, early_aggregation) { terminal_count == expected_count && !early_aggregation }
  closure_valid = ->(required, returned) { required.sort == returned.sort && required.all? { |tuple| tuple.length == 5 } }
  cap_valid = ->(started, invalidated, next_batch) { started <= 10 && !(started == 10 && (invalidated || next_batch)) }
  review = gates.fetch("gates").find { |item| item["phase"] == "REVIEW_STEP" }.fetch("exit_assertions").to_h { |item| [item["id"], item] }
  ids = cases.fetch("cases").map { |item| item.fetch("id") }
  required = [["p1", "s1", "contract", "contract_and_test_oracle", "api"]]
  valid = expected.all? { |size, values| canonical.fetch(size).fetch("enum_values") == values && topology_valid.call(size, values) } &&
    !topology_valid.call("trivial_small", %w[contract_and_test_oracle contract_and_test_oracle]) && !topology_valid.call("large", expected.fetch("large")[0, 3]) &&
    barrier_valid.call(3, 3, false) && !barrier_valid.call(3, 2, true) && closure_valid.call(required, required) && !closure_valid.call(required, []) &&
    cap_valid.call(9, false, true) && !cap_valid.call(10, true, true) && !cap_valid.call(10, false, true) &&
    review.fetch("RS_BATCH_BARRIER").fetch("check").include?("five-dimensional closure") && review.fetch("RS_BATCH_BARRIER").fetch("check").include?("early aggregation") &&
    %w[audit-batch-waits-for-all-pass-results incomplete-review-batch-never-cleans in-flight-mutation-invalidates-review-batch trivial-audit-uses-two-isolated-passes].all? { |id| ids.include?(id) }
  exit valid ? 0 : 1
' "$review_handoffs" "$review_phase_gates" "$review_evals"; then
    pass
else
    fail "assistant-review behavioral oracle does not reject batch escape cases"
fi

test_start "Reviewer prompts expose the canonical return schema before first response"
if ruby -ryaml -e '
  handoffs = YAML.load_file(ARGV.shift)
  gates = YAML.load_file(ARGV.pop)
  prompts = ARGV.map { |path| File.read(path) }
  reviewer = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_reviewer" }
  return_fields = reviewer.fetch("return_fields")
  fields = return_fields.to_h { |field| [field["name"], field] }
  bundle = handoffs.fetch("dispatch_context_bundles").find { |entry| entry["name"] == "fresh_reviewer_context" }
  selector = bundle.fetch("worker_return_schema_selector")
  required = fields.values.select { |field| field["required"] == true }.map { |field| field.fetch("name") }
  triggered_fields = fields.values.select { |field| field["required"] == "conditional" }.map { |field| field.fetch("name") }
  conditional = {"closure_results" => "review_perspective == closure_verification", "agentic_loop_safety_checks" => "agentic_loop_safety_review_required is true", "behavioral_contract_checks" => "behavioral_contract_review_required is true", "semantic_contract_checks" => "semantic_contract_review_required is true", "architecture_decision_pack_checks" => "architecture_decision_pack_review_required is true", "principle_checks" => "quality_principles_required is true or scope_size in [medium, large]", "pivot_restart_signal" => "rubric_scores.action == PIVOT"}
  prompt_terms = ["Before first response, resolve `worker_return_schema`: from the active assistant-review skill root, load named `return_fields` recursively with bounded keys from `contracts/handoffs.yaml`; verify it equals the schema identified by `return_schema_ref`, or return `NEEDS_CONTEXT` without a partial result.", "Before first response, return the canonical Reviewer schema:", "Always include: `status`, `round`, `batch_id`, `review_snapshot_id`, `snapshot_identity`, `review_pass_id`, `review_attempt_id`, `review_perspective`, `pass_completion_state`, `reviewed_scope`, `findings`, `coverage_entries`, `summary`, `evidence`, `reuse_search`, and `verdict`.", "When `review_perspective=closure_verification`, include `closure_results`.", "When selected, return `agentic_loop_safety_checks`, `behavioral_contract_checks`, `semantic_contract_checks`, and `architecture_decision_pack_checks`.", "When quality principles apply, return `principle_checks`.", "When pivot/stagnation/drift/regression is triggered, return `pivot_restart_signal`."]
  visible_fields = required + triggered_fields
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
      type_ok = case field["type"]
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
      next false unless type_ok && (!field["min_items"] || value.length >= field["min_items"])
      children = field["object_fields"]
      children ? (field["type"] == "object" ? schema_valid.call(value, children) : field["type"] == "object[]" ? value.all? { |item| schema_valid.call(item, children) } : true) : true
    end
  }
  complete = return_fields.to_h { |field| [field.fetch("name"), sample.call(field)] }
  deep_copy = ->(value) { Marshal.load(Marshal.dump(value)) }
  nodes = []
  walk = nil
  walk = ->(schema, path) { schema.each { |field| nodes << [path + [field.fetch("name")], field]; children = field["object_fields"]; walk.call(children, path + [field.fetch("name")] + (field["type"] == "object[]" ? [0] : [])) if children } }
  walk.call(return_fields, [])
  parent_at = ->(packet, path) { path[0...-1].reduce(packet) { |current, key| current[key] } }
  invalid = ->(field) { {"string" => 1, "int" => "1", "float" => "1", "boolean" => "true", "string[]" => [1], "object" => [], "object[]" => {}, "enum" => "INVALID_ENUM"}.fetch(field.fetch("type")) }
  required_nodes = nodes.select { |_path, field| [true, "conditional"].include?(field["required"]) }
  type_nodes = nodes
  enum_nodes = nodes.select { |_path, field| field["type"] == "enum" }
  cardinality_nodes = nodes.select { |_path, field| field["min_items"].to_i > 0 }
  mutate_all = ->(pairs, &mutation) { pairs.all? { |path, field| trial = deep_copy.call(complete); mutation.call(parent_at.call(trial, path), path.last, field); !schema_valid.call(trial, return_fields) } }
  omissions_rejected = mutate_all.call(required_nodes) { |parent, name, _field| parent.delete(name) }
  types_rejected = mutate_all.call(type_nodes) { |parent, name, field| parent[name] = invalid.call(field) }
  enums_rejected = mutate_all.call(enum_nodes) { |parent, name, _field| parent[name] = "INVALID_ENUM" }
  cardinality_rejected = mutate_all.call(cardinality_nodes) { |parent, name, _field| parent[name] = [] }
  mutations_rejected = schema_valid.call(complete, return_fields) && omissions_rejected && types_rejected && enums_rejected && cardinality_rejected
  prompt_schema_visible = prompts.all? { |prompt| visible_fields.all? { |name| prompt.include?("`#{name}`") } }
  clean_literal = "No material findings within the reviewed scope and available evidence"
  exact_clean_literal = prompts.all? { |prompt| prompt.include?("\"#{clean_literal}\"") && !prompt.include?("\"#{clean_literal}.\"") }
  resolve_schema = ->(document, ref) { _root, handoff_name, field_name = ref.split("."); document.fetch("handoffs").find { |entry| entry["name"] == handoff_name }.fetch(field_name) }
  resolution = "Worker recursively loads named handoff return_fields (bounded keys); worker_return_schema equals schema identified by return_schema_ref before response; else NEEDS_CONTEXT, no partial result."
  resolved_schema_key = selector.fetch("resolution").match(/(worker_return_schema) equals schema identified by return_schema_ref before response/)[1]
  resolved_schema = resolve_schema.call(handoffs, selector.fetch("return_schema_ref"))
  rendered_dispatch = {resolved_schema_key => resolved_schema, "return_schema_ref" => selector.fetch("return_schema_ref"), "resolution_proof" => selector.fetch("resolution")}
  selector_valid = selector.fetch("return_schema_ref") == "handoffs.orchestrator_to_reviewer.return_fields" && selector.fetch("source_path") == "contracts/handoffs.yaml" && selector.fetch("resolution") == resolution && selector.fetch("recursive_shape").include?("required/conditional fields, types, enums, and cardinality") && selector.fetch("excludes").include?("sibling/batch state")
  dispatch_valid = rendered_dispatch.fetch(resolved_schema_key) == return_fields && rendered_dispatch.fetch("return_schema_ref") == selector.fetch("return_schema_ref") && rendered_dispatch.fetch("resolution_proof") == resolution && schema_valid.call(complete, rendered_dispatch.fetch(resolved_schema_key))
  rs2 = gates.fetch("gates").flat_map { |phase| phase.fetch("exit_assertions", []) }.find { |gate| gate["id"] == "RS2" }
  valid = conditional.all? { |name, condition| fields.fetch(name)["required"] == "conditional" && fields.fetch(name).fetch("condition").include?(condition) } && selector_valid && dispatch_valid && rs2.fetch("check").include?("worker_return_schema_selector") && rs2.fetch("check").include?("worker_return_schema") && rs2.fetch("check").include?("fails closed") && prompts.all? { |prompt| prompt_terms.all? { |term| prompt.include?(term) } } && prompt_schema_visible && exact_clean_literal && mutations_rejected
  exit valid ? 0 : 1
' "$review_handoffs" "$FRAMEWORK_DIR/agents/codex/reviewer.toml" "$FRAMEWORK_DIR/agents/claude/reviewer.md" "$FRAMEWORK_DIR/agents/codex/code-reviewer.toml" "$FRAMEWORK_DIR/agents/claude/code-reviewer.md" "$review_phase_gates"; then
    pass
else
    fail "Reviewer prompts or return contract omit mandatory, triggered, or pivot return fields"
fi

test_start "assistant-review preserves discovery outcomes, closure identities, and final planned topology"
if ruby -ryaml -rjson -e '
  input, output, handoffs, index, cases, gates = ARGV.then { |paths| [YAML.load_file(paths[0]), YAML.load_file(paths[1]), YAML.load_file(paths[2]), YAML.load_file(paths[3]), JSON.parse(File.read(paths[4])), YAML.load_file(paths[5])] }
  input_fields = input.fetch("fields").to_h { |field| [field.fetch("name"), field] }
  previous = input_fields.fetch("previously_fixed").fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  canonical_identity = input_fields.fetch("review_material_snapshot").fetch("object_fields").find { |field| field.fetch("name") == "snapshot_identity" }.fetch("object_fields")
  migration_identity = input_fields.fetch("persisted_v6_packet_migration").fetch("object_fields").find { |field| field.fetch("name") == "rebuilt_snapshot_identity" }.fetch("object_fields")
  invalidation_identity = input_fields.fetch("persisted_v7_0_packet_invalidation").fetch("object_fields").find { |field| field.fetch("name") == "rebuilt_snapshot_identity" }.fetch("object_fields")
  f3 = gates.fetch("gates").flat_map { |phase| phase.fetch("exit_assertions", []) }.find { |gate| gate.fetch("id") == "F3" }
  reviewer = handoffs.fetch("handoffs").find { |entry| entry.fetch("name") == "orchestrator_to_reviewer" }
  reviewer_context = reviewer.fetch("context_fields").to_h { |field| [field.fetch("name"), field] }
  handoff_previous = reviewer_context.fetch("previously_fixed").fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  batch = reviewer_context.fetch("review_batch").fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  expected_pass_fields = batch.fetch("expected_passes").fetch("object_fields")
  final_artifact = output.fetch("artifacts").find { |artifact| artifact.fetch("name") == "final_summary" }
  final = final_artifact.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  coverage = final.fetch("coverage_ledger").fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  review_delegation = output.fetch("artifacts").find { |artifact| artifact.fetch("name") == "review_delegation_path" }
  qa_delegation = output.fetch("artifacts").find { |artifact| artifact.fetch("name") == "qa_evaluation_delegation_path" }
  review_trigger_scope = review_delegation.fetch("object_fields").find { |field| field.fetch("name") == "subagent_trigger_scope" }
  qa_trigger_scope = qa_delegation.fetch("object_fields").find { |field| field.fetch("name") == "subagent_trigger_scope" }
  plan = final.fetch("final_batch_plan")
  plan_fields = plan.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  case_item = cases.fetch("cases").find { |entry| entry.fetch("id") == "post-fix-review-uses-fresh-snapshot-batch" }
  batch_expectations = cases.fetch("canonical_review_batch_expectations")
  qa_case_requirements = cases.fetch("canonical_qa_case_requirements")
  closure_expectations = cases.fetch("canonical_review_closure_expectations")
  expectation_refs = batch_expectations.fetch("case_template_refs")
  case_requirements = batch_expectations.fetch("case_requirements")
  scope_manifests = batch_expectations.fetch("scope_manifests")
  post_fix_expectation = batch_expectations.fetch("templates").fetch(expectation_refs.fetch("post-fix-review-uses-fresh-snapshot-batch"))
  trivial_expectation = batch_expectations.fetch("templates").fetch(expectation_refs.fetch("trivial-audit-uses-two-isolated-passes"))
  post_fix_paths = case_item.fetch("machine_expectations").fetch("structured_json_assertions").select { |assertion| assertion.fetch("operator") == "nonempty_string" }.map { |assertion| assertion.fetch("path") }
  entry_names = index.fetch("load_sets").fetch("entry").fetch("selectors").first.fetch("names")
  expected_names = %w[review_pass_id perspective assigned_scope coverage_obligations prior_finding_visibility]
  fixed_fields = final.fetch("fixed_items").fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  closure_results = final.fetch("closure_results")
  template_scope_authority_valid = batch_expectations.fetch("templates").all? do |template_ref, template|
    manifest = scope_manifests[template_ref]
    next false unless manifest.is_a?(Array) && !manifest.empty?
    manifest_by_scope = manifest.to_h { |item| [item["scope_item_id"], item] }
    expected = template.fetch("expected_passes").flat_map do |review_pass|
      review_pass.fetch("assigned_scope").flat_map do |scope_item_id|
        Array(manifest_by_scope.dig(scope_item_id, "applicable_concerns")).flat_map do |concern|
          review_pass.fetch("coverage_obligations").map do |obligation|
            [review_pass.fetch("review_pass_id"), scope_item_id, concern, review_pass.fetch("perspective"), obligation]
          end
        end
      end
    end
    actual = template.fetch("required_coverage_tuples").map { |tuple| [tuple["review_pass_id"], tuple["scope_item_id"], tuple["applicable_concern"], tuple["review_perspective"], tuple["coverage_obligation"]] }
    actual.uniq.length == actual.length && actual.sort == expected.sort
  end
  valid = [input, output, handoffs, index].all? { |schema| schema.fetch("schema_version") == "7.1" } &&
    entry_names.include?("previously_fixed") && entry_names.include?("persisted_v6_packet_migration") && entry_names.include?("persisted_v7_0_packet_invalidation") &&
    previous.key?("aggregate_finding_id") && previous.fetch("source_finding_ids").fetch("condition").include?("producer schema 7.1") && previous.fetch("source_provenance").fetch("condition").include?("producer schema 7.1") && !previous.key?("finding_id") &&
    migration_identity == canonical_identity && invalidation_identity == canonical_identity &&
    f3.fetch("check").include?("source_finding_ids") && f3.fetch("check").include?("source_provenance") &&
    handoff_previous.key?("aggregate_finding_id") && handoff_previous.fetch("source_finding_ids").fetch("required") == true && handoff_previous.fetch("source_provenance").fetch("required") == true && !handoff_previous.key?("finding_id") &&
    batch.fetch("scope_size").fetch("enum_values") == %w[trivial small medium large] &&
    coverage.fetch("coverage_disposition").fetch("enum_values") == %w[inspected_no_risk finding incomplete] &&
    coverage.fetch("finding_ids").fetch("condition") == "coverage_disposition == finding" && coverage.fetch("finding_ids").fetch("min_items") == 1 &&
    coverage.fetch("coverage_gap_id").fetch("validation").include?("every incomplete or invalidated coverage record") &&
    plan_fields.fetch("scope_size").fetch("enum_values") == %w[trivial small medium large] && plan_fields.fetch("topology").fetch("required") == true && plan_fields.fetch("expected_passes").fetch("required") == true && plan_fields.fetch("required_coverage_tuples").fetch("required") == true &&
    plan_fields.fetch("expected_passes").fetch("object_fields").map { |field| field.fetch("name") } == expected_names &&
    plan_fields.fetch("expected_passes").fetch("object_fields").map { |field| field.slice("type", "required", "enum_values") } == expected_pass_fields.map { |field| field.slice("type", "required", "enum_values") } &&
    review_delegation.fetch("validation").include?("not_required requires direct_fallback") && !review_trigger_scope.key?("min_items") && review_trigger_scope.fetch("validation").include?("empty only when not_required + direct_fallback") &&
    qa_delegation.fetch("validation").include?("delegation_triggered requires delegated") && !qa_trigger_scope.key?("min_items") && qa_trigger_scope.fetch("validation").include?("empty only when not_required + not_applicable") &&
    batch_expectations.keys.sort == %w[case_requirements case_template_refs scope_manifests templates] && scope_manifests.keys.sort == batch_expectations.fetch("templates").keys.sort && case_requirements.keys.sort == expectation_refs.keys.sort && template_scope_authority_valid &&
    expectation_refs.keys.sort == %w[audit-batch-waits-for-all-pass-results audit-spec-review-fail-continues-complete-batch in-flight-mutation-invalidates-review-batch incomplete-review-batch-never-cleans post-fix-review-regression-remains-open post-fix-review-uses-fresh-snapshot-batch post-fix-verified-closure-with-incomplete-coverage trivial-audit-uses-two-isolated-passes].sort &&
    case_requirements.all? { |case_id, requirement| requirement.keys.sort == %w[mode required_artifacts required_envelope_alias] && requirement.fetch("required_envelope_alias") == "final_summary" && requirement.fetch("required_artifacts").include?("final_summary") && requirement.fetch("required_artifacts").include?("review_delegation_path") && (requirement.fetch("mode") == "audit") == requirement.fetch("required_artifacts").include?("audit_report") } &&
    case_requirements.fetch("incomplete-review-batch-never-cleans") == {"mode" => "audit", "required_artifacts" => ["final_summary", "audit_report", "review_delegation_path"], "required_envelope_alias" => "final_summary"} &&
    qa_case_requirements == {
      "qa-obligation-echo-fulfills-exact-binding" => {"required_artifacts" => ["qa_evaluation_result", "qa_evaluation_delegation_path"]},
      "qa-obligation-blocks-missing-or-mismatched-binding" => {"required_artifacts" => ["qa_evaluation_result", "qa_evaluation_delegation_path"]},
      "qa-obligation-blocked-when-required-evidence-is-unavailable" => {"required_artifacts" => ["qa_evaluation_result", "qa_evaluation_delegation_path"]}
    } &&
    trivial_expectation.fetch("scope_size") == "trivial" &&
    post_fix_expectation.fetch("topology").fetch("closure_verification_required") == true && post_fix_expectation.fetch("expected_passes").any? { |pass| pass.fetch("perspective") == "closure_verification" } &&
    closure_expectations.fetch("post-fix-review-uses-fresh-snapshot-batch") == closure_expectations.fetch("post-fix-review-regression-remains-open") && closure_expectations.fetch("post-fix-review-uses-fresh-snapshot-batch") == closure_expectations.fetch("post-fix-verified-closure-with-incomplete-coverage") && closure_expectations.fetch("post-fix-review-uses-fresh-snapshot-batch").first.fetch("aggregate_finding_id") == "aggregate-fixed-1" &&
    fixed_fields.fetch("aggregate_finding_id").fetch("required") == true &&
    closure_results.fetch("condition") == "fixed_items is non-empty" && closure_results.fetch("validation").include?("exact set equality") && closure_results.fetch("validation").include?("HAS_REMAINING_ITEMS") &&
    final_artifact.fetch("validation").include?("final_batch_plan") &&
    post_fix_paths.include?(["final_summary", "coverage_ledger", 0, "coverage_gap_id"]) && post_fix_paths.include?(["final_summary", "coverage_ledger", 1, "coverage_gap_id"])
  exit valid ? 0 : 1
' "$review_input" "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml" "$review_handoffs" "$review_index" "$review_evals" "$review_phase_gates" \
  && ! grep -Fq -- "medium+ scope only" "$review_handoffs" \
  && grep -Fq -- "including triggered trivial/small scope" "$review_handoffs"; then
    pass
else
    fail "assistant-review loses version, fallback, scope, closure identity, historical gap, or final planned-pass binding"
fi

test_start "assistant-review producer clean claim keeps the canonical literal unperiodized"
clean_claim="No material findings within the reviewed scope and available evidence"
clean_claim_failures=()
for file in \
    "$review_skill" \
    "$FRAMEWORK_DIR/agents/codex/reviewer.toml" \
    "$FRAMEWORK_DIR/agents/claude/reviewer.md" \
    "$FRAMEWORK_DIR/agents/codex/code-reviewer.toml" \
    "$FRAMEWORK_DIR/agents/claude/code-reviewer.md"; do
    if ! grep -Fq -- "\"$clean_claim\"" "$file" || grep -Fq -- "\"$clean_claim.\"" "$file"; then
        clean_claim_failures+=("${file#$FRAMEWORK_DIR/}: quoted canonical clean literal")
    fi
done
if ! grep -Fq -- "**$clean_claim**" "$review_loop" || grep -Fq -- "**$clean_claim.**" "$review_loop"; then
    clean_claim_failures+=("${review_loop#$FRAMEWORK_DIR/}: bold canonical clean literal")
fi
if ! grep -Fq -- "'$clean_claim'" "$review_handoffs" || grep -Fq -- "'$clean_claim.'" "$review_handoffs"; then
    clean_claim_failures+=("${review_handoffs#$FRAMEWORK_DIR/}: contract canonical clean literal")
fi
if [[ ${#clean_claim_failures[@]} -eq 0 ]]; then
    pass
else
    fail "assistant-review clean claim has periodized or missing producer literal: ${clean_claim_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
