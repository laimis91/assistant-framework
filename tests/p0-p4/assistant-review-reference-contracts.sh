if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

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

p0p4_finish_suite "${BASH_SOURCE[0]}"
