if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

research_skill="$FRAMEWORK_DIR/skills/assistant-research/SKILL.md"
research_reference="$FRAMEWORK_DIR/skills/assistant-research/research.md"
research_output="$FRAMEWORK_DIR/skills/assistant-research/contracts/output.yaml"
research_phase_gates="$FRAMEWORK_DIR/skills/assistant-research/contracts/phase-gates.yaml"
research_evals="$FRAMEWORK_DIR/skills/assistant-research/evals/cases.json"
research_eval_runner="$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh"

write_research_eval_responses() {
    local output_dir="$1"
    local case_id

    mkdir -p "$output_dir/assistant-research"
    while IFS= read -r case_id; do
        jq -r --arg case_id "$case_id" '
            .cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[]
        ' "$research_evals" >"$output_dir/assistant-research/$case_id.txt"
    done < <(jq -r '.cases[].id' "$research_evals")
}

research_forbidden_response_is_rejected() {
    local case_id="$1"
    local forbidden="$2"
    local case_count
    local eval_dir
    local eval_output

    case_count="$(jq '.cases | length' "$research_evals")"
    eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-research-negative.XXXXXX")"
    eval_output="$(mktemp "${TMPDIR:-/tmp}/assistant-research-negative-output.XXXXXX")"
    p0p4_register_cleanup "$eval_dir" "$eval_output"
    write_research_eval_responses "$eval_dir"
    printf '%s\n' "$forbidden" >>"$eval_dir/assistant-research/$case_id.txt"

    if "$research_eval_runner" --responses "$eval_dir" --skill assistant-research >"$eval_output" 2>&1; then
        return 1
    fi

    grep -Fq $'FAIL\tassistant-research\t'"$case_id" "$eval_output" \
        && grep -Fq "Summary: total=$case_count passed=$((case_count - 1)) failed=1" "$eval_output" \
        && grep -Fq "missing_required_substrings=0" "$eval_output" \
        && grep -Fq "forbidden_substring_hits=1" "$eval_output"
}

test_start "assistant-research candidate mechanisms stay evidence-backed and unproven"
missing_candidate_mechanism_terms=()
for term in \
    "candidate_mechanisms" \
    "counterevidence_or_conflicts" \
    "validation_method" \
    "claim_status"; do
    if ! grep -Fq "$term" "$research_output"; then
        missing_candidate_mechanism_terms+=("contracts/output.yaml: $term")
    fi
done
for term in \
    "SY_CANDIDATE_MECHANISMS" \
    "VR_CANDIDATE_MECHANISMS" \
    "not presented as a proven cause"; do
    if ! grep -Fq "$term" "$research_phase_gates"; then
        missing_candidate_mechanism_terms+=("contracts/phase-gates.yaml: $term")
    fi
done
for term in \
    "Candidate mechanisms" \
    "validation method"; do
    if ! grep -Fq "$term" "$research_skill"; then
        missing_candidate_mechanism_terms+=("SKILL.md: $term")
    fi
    if ! grep -Fq "$term" "$research_reference"; then
        missing_candidate_mechanism_terms+=("research.md: $term")
    fi
done
for term in \
    "candidate-mechanisms-are-evidence-backed-hypotheses" \
    "CANDIDATE MECHANISMS" \
    "Validation method"; do
    if ! grep -Fq "$term" "$research_evals"; then
        missing_candidate_mechanism_terms+=("evals/cases.json: $term")
    fi
done
if [[ "${#missing_candidate_mechanism_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research candidate-mechanism contract missing terms: ${missing_candidate_mechanism_terms[*]}"
fi

test_start "assistant-research retains every material five-lens follow-up"
follow_up_missing=()
for term in \
    "- name: follow_ups" \
    "typed none_needed decision" \
    "Every material follow-up is retained" \
    "- name: question" \
    "- name: answer_or_gap" \
    "- name: sources_or_verified_urls" \
    "- name: evidence_status"; do
    if ! grep -Fq -- "$term" "$research_output"; then
        follow_up_missing+=("contracts/output.yaml: $term")
    fi
done
for term in \
    "SY_FIVE_LENS_FOLLOW_UPS" \
    "every material follow-up"; do
    if ! grep -Fq -- "$term" "$research_phase_gates"; then
        follow_up_missing+=("contracts/phase-gates.yaml: $term")
    fi
done
for term in \
    "Follow-ups:" \
    "none_needed" \
    "every material follow-up"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-research/five-lens-briefing.md"; then
        follow_up_missing+=("five-lens-briefing.md: $term")
    fi
done
for term in \
    "five-lens-retains-all-material-follow-ups" \
    "follow_ups" \
    "follow_up_question"; do
    if ! grep -Fq -- "$term" "$research_evals"; then
        follow_up_missing+=("evals/cases.json: $term")
    fi
done
for file in \
    "$FRAMEWORK_DIR/skills/assistant-research/contracts/index.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-research/contracts/input.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-research/contracts/output.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-research/contracts/phase-gates.yaml"; do
    if ! grep -Fq -- 'schema_version: "2.0"' "$file"; then
        follow_up_missing+=("${file#$FRAMEWORK_DIR/}: v2 migration version")
    fi
done
if ! grep -Fq -- "Migration note: assistant-research contracts are v2.0" "$research_skill"; then
    follow_up_missing+=("SKILL.md: v2 follow-up migration note")
fi
if [[ "${#follow_up_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research five-lens follow-up contract missing: ${follow_up_missing[*]}"
fi

test_start "assistant-research v2 follows the authoritative none_needed enum"
none_needed_missing=()
for file in \
    "$research_output" \
    "$research_phase_gates" \
    "$FRAMEWORK_DIR/skills/assistant-research/five-lens-briefing.md" \
    "$research_evals"; do
    if grep -Fq -- "none-needed" "$file"; then
        none_needed_missing+=("${file#$FRAMEWORK_DIR/}: stale none-needed spelling")
    fi
done
for term in \
    "follow_ups=[follow_up, follow_up]" \
    "decision=none_needed" \
    "none_needed cannot coexist with material follow-ups"; do
    if ! grep -Fq -- "$term" "$research_evals"; then
        none_needed_missing+=("evals/cases.json: $term")
    fi
done
if [[ "${#none_needed_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research none_needed enum contract missing: ${none_needed_missing[*]}"
fi

test_start "assistant-research grader rejects a keyword-complete mixed follow-up trace"
if research_forbidden_response_is_rejected \
    "five-lens-retains-all-material-follow-ups" \
    "accept follow_ups=[follow_up, none_needed] for the same trace"; then
    pass
else
    fail "research grader accepts follow_up and none_needed in one trace"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
