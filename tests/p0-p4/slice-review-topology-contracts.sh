if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

workflow_root="$FRAMEWORK_DIR/skills/assistant-workflow"
workflow_plugin="$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow"
topology_reference="$workflow_root/references/slice-review-topology.md"

test_start "workflow defines a canonical provider-neutral slice review topology reference"
missing_topology_terms=()
for term in \
    "# Slice Review Topology" \
    "feature/<task>" \
    "slice/<task>/<slice-id>" \
    "target_branch" \
    "task_branch" \
    "slice_branch" \
    "promotion_mode" \
    "local" \
    "review_gated" \
    "REVIEW_PENDING" \
    "verified_base_sha" \
    "verified_head_sha"; do
    if [[ ! -f "$topology_reference" ]] || ! grep -Fq -- "$term" "$topology_reference"; then
        missing_topology_terms+=("$term")
    fi
done
if [[ "${#missing_topology_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "slice-review-topology.md missing provider-neutral topology terms: ${missing_topology_terms[*]}"
fi

test_start "slice review examples use a repository target branch rather than normative main"
if grep -Fq -- "target_branch: <target-branch>" "$topology_reference" \
    && grep -Eq 'target branch|target_branch' "$FRAMEWORK_DIR/README.md" \
    && ! rg -n -i 'target_branch:[[:space:]]*main|--target-branch[[:space:]]+main|target branch[[:space:]]*=[[:space:]]*main' \
        "$topology_reference" "$FRAMEWORK_DIR/README.md" >/tmp/p0p4-slice-review-main-default.out; then
    pass
else
    fail "slice review topology and README must use <target-branch> examples, never normative main"
fi

test_start "new-topology branch guidance uses target-branch placeholders and never targets main"
branch_guidance_files=(
    "$topology_reference"
    "$workflow_root/references/sub-task-brief-template.md"
)
invalid_branch_guidance=()
for branch_guidance_file in "${branch_guidance_files[@]}"; do
    if [[ ! -f "$branch_guidance_file" ]] \
        || ! grep -Eq '<target-branch>|target branch' "$branch_guidance_file" \
        || rg -n -i '^[[:space:]]*main[[:space:]]*$|final task branch review targets main|target_branch:[[:space:]]*main|--target-branch[[:space:]]+main' "$branch_guidance_file" >/tmp/p0p4-slice-review-normative-main.out; then
        invalid_branch_guidance+=("${branch_guidance_file#$FRAMEWORK_DIR/}")
    fi
done
if [[ "${#invalid_branch_guidance[@]}" -eq 0 ]]; then
    pass
else
    fail "new-topology branch guidance must use repository-specific target branches, not normative main: ${invalid_branch_guidance[*]}"
fi

test_start "workflow review topology excludes provider execution mechanics without rejecting compatibility prose"
provider_mechanics_hits=()
for pattern in \
    '(^|[[:space:]])gh[[:space:]]+(pr|api|workflow|run)' \
    '(^|[[:space:]])glab[[:space:]]+(mr|api|ci)' \
    '\.github/workflows/' \
    '\.gitlab-ci\.ya?ml' \
    'GitHub Actions' \
    'GitLab CI' \
    'branch protection' \
    'provider authentication'; do
    if [[ -f "$topology_reference" ]] && rg -n -i -- "$pattern" "$topology_reference" >/tmp/p0p4-slice-review-provider-mechanics.out; then
        provider_mechanics_hits+=("$pattern")
    fi
done
if [[ "${#provider_mechanics_hits[@]}" -eq 0 ]]; then
    pass
else
    fail "slice review reference contains provider execution mechanics: ${provider_mechanics_hits[*]}"
fi

test_start "workflow SKILL conditionally loads the slice review topology reference"
if grep -Fq -- "references/slice-review-topology.md" "$workflow_root/SKILL.md" \
    && grep -Eqi 'review_gated|slice review|provider-neutral' "$workflow_root/SKILL.md"; then
    pass
else
    fail "assistant-workflow SKILL.md does not conditionally route slice review topology guidance"
fi

test_start "workflow contracts define provider-neutral promotion input output and gate evidence"
missing_contract_terms=()
for file_and_term in \
    "$workflow_root/contracts/input.yaml::- name: slice_promotion_mode" \
    "$workflow_root/contracts/input.yaml::enum_values: [local, review_gated]" \
    "$workflow_root/contracts/input.yaml::default: local" \
    "$workflow_root/contracts/input.yaml::remote-write authorization" \
    "$workflow_root/contracts/output.yaml::- name: slice_review_evidence" \
    "$workflow_root/contracts/output.yaml::REVIEW_PENDING" \
    "$workflow_root/contracts/output.yaml::REVIEW_APPROVED" \
    "$workflow_root/contracts/output.yaml::REVIEW_REJECTED" \
    "$workflow_root/contracts/output.yaml::REVIEW_STALE" \
    "$workflow_root/contracts/output.yaml::verified_base_sha" \
    "$workflow_root/contracts/output.yaml::verified_head_sha" \
    "$workflow_root/contracts/output.yaml::provider_gate_evidence_ref" \
    "$workflow_root/contracts/phase-gates.yaml::complete topology metadata" \
    "$workflow_root/contracts/phase-gates.yaml::must not mutate the task branch" \
    "$workflow_root/contracts/phase-gates.yaml::must not mark the slice VERIFIED" \
    "$workflow_root/contracts/phase-gates.yaml::exact reviewed SHAs" \
    "$workflow_root/contracts/phase-gates.yaml::provider evidence" \
    "$workflow_root/contracts/phase-gates.yaml::ancestry" \
    "$workflow_root/contracts/phase-gates.yaml::fresh verification" \
    "$workflow_root/contracts/phase-gates.yaml::REVIEW_PENDING" \
    "$workflow_root/contracts/phase-gates.yaml::REVIEW_REJECTED" \
    "$workflow_root/contracts/phase-gates.yaml::REVIEW_STALE"; do
    contract_file="${file_and_term%%::*}"
    contract_term="${file_and_term#*::}"
    if [[ ! -f "$contract_file" ]] || ! grep -Fq -- "$contract_term" "$contract_file"; then
        missing_contract_terms+=("${contract_file#$FRAMEWORK_DIR/}: $contract_term")
    fi
done
if [[ "${#missing_contract_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "slice review contracts missing provider-neutral promotion evidence: ${missing_contract_terms[*]}"
fi

test_start "workflow review evidence contract makes gate state and approval references state-dependent"
if ! rg -U -q 'name: review_request_ref[\s\S]{0,280}required: conditional[\s\S]{0,420}condition:.*REVIEW_(PENDING|APPROVED)' "$workflow_root/contracts/output.yaml"; then
    fail "slice review output contract does not state when review_request_ref is required"
elif ! rg -U -q 'name: provider_gate_state[\s\S]{0,260}enum_values: \[not_evaluated, passed, failed\]' "$workflow_root/contracts/output.yaml"; then
    fail "slice review output contract does not require provider_gate_state"
elif ! rg -U -q 'name: provider_gate_evidence_ref[\s\S]{0,280}condition:.*provider_gate_state.*(passed|failed)' "$workflow_root/contracts/output.yaml"; then
    fail "slice review output contract does not make provider gate evidence state-dependent"
else
    pass
fi

test_start "workflow typed review evidence binds promotion and immutable target base"
if ! rg -U -q 'name: slice_review_evidence[\s\S]{0,2600}name: promotion_mode[\s\S]{0,180}required: true' "$workflow_root/contracts/output.yaml"; then
    fail "slice review output schema does not require evidence promotion_mode"
elif ! rg -U -q 'name: slice_review_evidence[\s\S]{0,3000}name: target_base_sha[\s\S]{0,180}required: true' "$workflow_root/contracts/output.yaml"; then
    fail "slice review output schema does not require immutable target_base_sha"
else
    pass
fi

test_start "workflow approval evidence rejects whitespace-only opaque provider references"
if ! rg -U -q 'name: review_request_ref[\s\S]{0,320}validation:.*(nonblank|non-empty|whitespace)' "$workflow_root/contracts/output.yaml"; then
    fail "slice review output schema does not reject whitespace-only review_request_ref"
elif ! rg -U -q 'name: provider_gate_evidence_ref[\s\S]{0,320}validation:.*(nonblank|non-empty|whitespace)' "$workflow_root/contracts/output.yaml"; then
    fail "slice review output schema does not reject whitespace-only provider_gate_evidence_ref"
else
    pass
fi

test_start "workflow packet templates and output schema carry the complete five-field topology tuple"
tuple_files=(
    "$workflow_root/references/plan-template.md"
    "$workflow_root/contracts/output.yaml"
    "$workflow_root/contracts/phase-gates.yaml"
)
tuple_missing=()
for tuple_file in "${tuple_files[@]}"; do
    for tuple_field in target_branch target_base_sha task_branch slice_branch promotion_mode; do
        grep -Fq -- "$tuple_field" "$tuple_file" || tuple_missing+=("${tuple_file#$FRAMEWORK_DIR/}:$tuple_field")
    done
done
if [[ "${#tuple_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "five-field topology tuple is incomplete across packet/schema/gates: ${tuple_missing[*]}"
fi

test_start "workflow guidance carries review-gated promotion semantics through planning and handoffs"
missing_guidance_terms=()
for file in \
    "$workflow_root/references/plan-template.md" \
    "$workflow_root/references/task-journal-template.md" \
    "$workflow_root/references/sub-task-brief-template.md" \
    "$workflow_root/references/phases.md" \
    "$workflow_root/references/mega-and-patterns.md" \
    "$workflow_root/references/context-handoff-templates.md"; do
    if [[ ! -f "$file" ]] || ! grep -Eq 'review_gated|REVIEW_PENDING|slice review evidence' "$file"; then
        missing_guidance_terms+=("${file#$FRAMEWORK_DIR/}")
    fi
done
if [[ "${#missing_guidance_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "slice review guidance is missing from planning/journal/brief/phase/handoff surfaces: ${missing_guidance_terms[*]}"
fi

test_start "workflow contract index conditionally loads the canonical slice review reference"
index_file="$workflow_root/contracts/index.yaml"
if awk '
    /^  slice_review:/ { in_slice_review = 1; next }
    in_slice_review && /^  [a-z_]+:/ { exit }
    in_slice_review && /references\/slice-review-topology\.md/ { found_slice_review = 1 }
    in_slice_review && /slice_promotion_mode/ { found_promotion_selector = 1 }
    END { exit (found_slice_review && found_promotion_selector) ? 0 : 1 }
' "$index_file" \
    && ! awk '
        /^  entry:/ { in_entry = 1; next }
        in_entry && /^  [a-z_]+:/ { exit }
        in_entry && /references\/slice-review-topology\.md/ { found_entry = 1 }
        in_entry && /slice_promotion_mode/ { found_entry_selector = 1 }
        END { exit (found_entry || found_entry_selector) ? 0 : 1 }
    ' "$index_file" \
    && awk '
        /^  entry:/ { in_entry = 1; next }
        in_entry && /^  [a-z_]+:/ { exit }
        in_entry && /references\/triage-rubric\.md/ { found_triage = 1 }
        END { exit found_triage ? 0 : 1 }
    ' "$index_file" \
    && ! grep -Eq '^[[:space:]]*activation:' "$index_file"; then
    pass
else
    fail "assistant-workflow contract index must keep triage-rubric in entry, move slice_promotion_mode and slice-review-topology.md together into conditional slice_review, and avoid unsupported activation metadata"
fi

test_start "workflow output uses only provider_gate_evidence_ref for provider-neutral review evidence"
if grep -Fq -- "- name: provider_gate_evidence_ref" "$workflow_root/contracts/output.yaml" \
    && ! grep -Fq -- "- name: provider_evidence_ref" "$workflow_root/contracts/output.yaml"; then
    pass
else
    fail "slice_review_evidence must use canonical provider_gate_evidence_ref and reject redundant provider_evidence_ref"
fi

test_start "workflow evals require exact SHA review evidence without provider mechanics"
eval_file="$workflow_root/evals/cases.json"
if [[ ! -f "$eval_file" ]]; then
    fail "assistant-workflow eval cases file is missing"
elif ! rg -U -i 'review_gated[\s\S]{0,3000}(verified_head_sha|exact SHA)[\s\S]{0,3000}(no local promotion|must not.*promot)[\s\S]{0,3000}(provider-neutral|provider specific)' "$eval_file" >/dev/null; then
    fail "workflow evals lack a review_gated case requiring exact SHA evidence, no local promotion, and provider-neutral mechanics"
elif rg -n -i '(review_gated|slice review).*(gh pr|glab mr|GitHub Actions|GitLab CI|\.github/workflows|\.gitlab-ci)' "$eval_file" >/tmp/p0p4-slice-review-eval-provider.out; then
    fail "workflow slice review eval includes provider-specific execution mechanics"
else
    pass
fi

test_start "workflow eval grader rejects an old minimal review-gated response"
old_review_response_dir="$(mktemp -d "${TMPDIR:-/tmp}/workflow-old-review-response.XXXXXX")"
old_review_response_out="$(mktemp "${TMPDIR:-/tmp}/workflow-old-review-response-out.XXXXXX")"
p0p4_register_cleanup "$old_review_response_dir" "$old_review_response_out"
mkdir -p "$old_review_response_dir/assistant-workflow"
while IFS= read -r old_review_case_id; do
    [[ "$old_review_case_id" == "review-gated-slice-evidence-is-provider-neutral" ]] && continue
    old_review_case_response="$old_review_response_dir/assistant-workflow/${old_review_case_id}.txt"
    {
        jq -r --arg id "$old_review_case_id" '.cases[] | select(.id == $id) | .machine_expectations.required_substrings[]'
        jq -r --arg id "$old_review_case_id" '.cases[] | select(.id == $id) | .machine_expectations.ordered_substrings[]?[]'
    } <"$eval_file" >"$old_review_case_response"
done < <(jq -r '.cases[].id' "$eval_file")
cat >"$old_review_response_dir/assistant-workflow/review-gated-slice-evidence-is-provider-neutral.txt" <<'RESPONSE'
review_gated
verified_head_sha
no local promotion
provider-neutral
RESPONSE
if "$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$old_review_response_dir" --skill "$workflow_root" >"$old_review_response_out" 2>&1; then
    fail "eval grader accepted an old four-substring review-gated response"
elif grep -Eq $'FAIL\tassistant-workflow\treview-gated-slice-evidence-is-provider-neutral.*[1-9][0-9]* missing required substring' "$old_review_response_out" \
    && grep -Eq 'missing_required_substrings=[1-9][0-9]*' "$old_review_response_out"; then
    pass
else
    fail "eval grader did not report a nonzero target-case missing_required_substrings count"
fi

test_start "README describes the review topology concisely without provider coupling"
if grep -Eq 'slice review|review_gated|REVIEW_PENDING' "$FRAMEWORK_DIR/README.md"; then
    pass
else
    fail "README lacks concise provider-neutral slice review topology guidance"
fi

test_start "assistant-workflow plugin mirror matches all slice review topology surfaces"
mirror_mismatches=()
for relative_path in \
    "SKILL.md" \
    "contracts/index.yaml" \
    "contracts/input.yaml" \
    "contracts/output.yaml" \
    "contracts/phase-gates.yaml" \
    "references/slice-review-topology.md" \
    "references/plan-template.md" \
    "references/task-journal-template.md" \
    "references/sub-task-brief-template.md" \
    "references/phases.md" \
    "references/mega-and-patterns.md" \
    "references/context-handoff-templates.md" \
    "evals/cases.json"; do
    if [[ ! -f "$workflow_root/$relative_path" || ! -f "$workflow_plugin/$relative_path" ]] \
        || ! cmp -s "$workflow_root/$relative_path" "$workflow_plugin/$relative_path"; then
        mirror_mismatches+=("$relative_path")
    fi
done
if [[ "${#mirror_mismatches[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-workflow slice review topology mirrors differ: ${mirror_mismatches[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
