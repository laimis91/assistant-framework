#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

skill_validator="$FRAMEWORK_DIR/tools/skills/validate-skills.sh"

validator_load_set_closure_words() {
    local skill_name="$1"
    local load_set="$2"
    local fixture_root
    local fixture_skill
    local fixture_index
    local validator_err

    fixture_root="$(mktemp -d)"
    p0p4_register_cleanup "$fixture_root"
    fixture_skill="$fixture_root/$skill_name"
    cp -R "$FRAMEWORK_DIR/skills/$skill_name" "$fixture_skill"
    fixture_index="$fixture_skill/contracts/index.yaml"
    validator_err="$fixture_root/validator.err"

    # Force only the selected load set to report its actual closure. The validator
    # computes root + index + declared references + key-selected item content.
    awk -v load_set="$load_set" '
        $0 == "  " load_set ":" { in_target = 1 }
        in_target && /^  [^[:space:]#][^:]*:[[:space:]]*$/ && $0 != "  " load_set ":" { in_target = 0 }
        in_target && /^    budget_words:/ { print "    budget_words: 1"; next }
        { print }
    ' "$fixture_index" > "$fixture_index.tmp"
    mv "$fixture_index.tmp" "$fixture_index"

    "$skill_validator" --skill "$fixture_skill" >/dev/null 2>"$validator_err" || true
    sed -nE "s/.*load set '$load_set' declared boundary closure is ([0-9]+) words.*/\\1/p" "$validator_err" | head -n 1
}

workflow_entry_words="$(validator_load_set_closure_words assistant-workflow entry)"
review_entry_words="$(validator_load_set_closure_words assistant-review entry)"
reviewer_bundle_words="$(validator_load_set_closure_words assistant-review reviewer_context)"
test_start "boundary-reachable entry closure stays below budgets (workflow=$workflow_entry_words review=$review_entry_words)"
boundary_failures=()
if [[ ! "$workflow_entry_words" =~ ^[0-9]+$ ]]; then
    boundary_failures+=("workflow validator did not report an entry closure")
elif (( workflow_entry_words >= 4000 )); then
    boundary_failures+=("workflow boundary closure $workflow_entry_words is not below 4000")
fi
if [[ ! "$review_entry_words" =~ ^[0-9]+$ ]]; then
    boundary_failures+=("review validator did not report an entry closure")
elif (( review_entry_words >= 5000 )); then
    boundary_failures+=("review boundary closure $review_entry_words is not below 5000")
fi
if [[ "${#boundary_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${boundary_failures[*]}"
fi

markdown_references_from_loader_lines() {
    awk '
        {
            line = $0
            while (match(line, /`[^`]+[.]md`/)) {
                ref = substr(line, RSTART + 1, RLENGTH - 2)
                if (ref !~ /^references\//) ref = "references/" ref
                print ref
                line = substr(line, RSTART + RLENGTH)
            }
            line = $0
            while (match(line, /\]\(references\/[^)]+[.]md\)/)) {
                print substr(line, RSTART + 2, RLENGTH - 3)
                line = substr(line, RSTART + RLENGTH)
            }
        }
    '
}

first_review_mandatory_reference_paths() {
    local skill_dir="$1"
    local root_refs
    local ref

    root_refs="$(
        awk '
            {
                low = tolower($0)
                if (low ~ /load/ && low ~ /(before the first review|before the first batch|before each review|before declaring clean)/) print
            }
        ' "$skill_dir/SKILL.md" | markdown_references_from_loader_lines | sort -u
    )"

    {
        printf '%s\n' "$root_refs"
        while IFS= read -r ref; do
            [[ -n "$ref" && -f "$skill_dir/$ref" ]] || continue
            awk '
                /^  1[.] REVIEW[[:space:]]*$/ { in_first_review = 1; next }
                /^  2[.] EVALUATE[[:space:]]*$/ { in_first_review = 0 }
                in_first_review && tolower($0) ~ /load/ { print }
            ' "$skill_dir/$ref" | markdown_references_from_loader_lines
        done <<< "$root_refs"
    } | awk 'NF && !seen[$0]++' | sort
}

review_skill_dir="$FRAMEWORK_DIR/skills/assistant-review"
first_review_refs="$(first_review_mandatory_reference_paths "$review_skill_dir")"
first_review_reference_words=0
first_review_reference_failures=()
while IFS= read -r reference_path; do
    [[ -n "$reference_path" ]] || continue
    if [[ ! -f "$review_skill_dir/$reference_path" ]]; then
        first_review_reference_failures+=("mandatory loader target is missing: $reference_path")
        continue
    fi
    first_review_reference_words=$(( first_review_reference_words + $(wc -w < "$review_skill_dir/$reference_path" | tr -d ' ') ))
done <<< "$first_review_refs"
first_review_total_words=$(( review_entry_words + first_review_reference_words ))
first_review_ref_labels="$(printf '%s' "$first_review_refs" | tr '\n' ',' | sed 's/,$//')"

test_start "orchestrator first-review stays below 5000 words and fresh Reviewer bundle stays below 5653 words (orchestrator=$first_review_total_words reviewer=$reviewer_bundle_words refs=$first_review_ref_labels)"
if [[ -z "$first_review_refs" ]]; then
    first_review_reference_failures+=("no mandatory first-review loader references were derived")
fi
if ! printf '%s\n' "$first_review_refs" | grep -Fqx 'references/review-loop.md'; then
    first_review_reference_failures+=("root does not expose a first-review loop loader")
fi
if (( first_review_total_words >= 5000 )); then
    first_review_reference_failures+=("orchestrator first-review boundary $first_review_total_words is not below 5000")
fi
if [[ ! "$reviewer_bundle_words" =~ ^[0-9]+$ ]]; then
    first_review_reference_failures+=("validator did not report the reviewer_context worker bundle closure")
elif (( reviewer_bundle_words >= 5653 )); then
    first_review_reference_failures+=("fresh Reviewer bundle $reviewer_bundle_words is not below 5653")
fi
if ! grep -Fq 'resolve `reviewer_context` from `contracts/index.yaml`' "$review_skill_dir/references/review-loop.md"; then
    first_review_reference_failures+=("review loop does not route first-pass worker context through reviewer_context")
fi
if [[ "${#first_review_reference_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${first_review_reference_failures[*]}"
fi

test_start "reviewer context keeps one strict 5653-word budget authority"
reviewer_budget_authority_failures=()
review_index="$FRAMEWORK_DIR/skills/assistant-review/contracts/index.yaml"
review_handoffs="$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml"
review_gates="$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml"
review_loop="$FRAMEWORK_DIR/skills/assistant-review/references/review-loop.md"
if ! ruby -ryaml -e '
    index = YAML.load_file(ARGV.fetch(0))
    handoffs = YAML.load_file(ARGV.fetch(1))
    reviewer_context = handoffs.fetch("dispatch_context_bundles").find { |bundle| bundle["name"] == "fresh_reviewer_context" }
    index_budget = index.fetch("load_sets").fetch("reviewer_context").fetch("budget_words")
    valid = index_budget == 5653 && reviewer_context.fetch("budget_words") == 5653 &&
      reviewer_context.fetch("budget_validation") == "SKILL plus index plus this selected bundle and its declared worst-case reference closure is strictly below 5653 words."
    exit valid ? 0 : 1
' "$review_index" "$review_handoffs"; then
    reviewer_budget_authority_failures+=("index and fresh_reviewer_context budget_words/budget_validation must equal 5653")
fi
for file_and_term in \
    "$review_gates::strictly below 5653 words" \
    "$review_gates::below 5653 words" \
    "$review_loop::below 5653 words" \
    "$BASH_SOURCE::fresh Reviewer bundle stays below 5653 words" \
    "$BASH_SOURCE::reviewer_bundle_words >= 5653"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! grep -Fq -- "$term" "$file"; then
        reviewer_budget_authority_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
if rg -n '5600' "$FRAMEWORK_DIR/skills/assistant-review" >/dev/null; then
    reviewer_budget_authority_failures+=("active assistant-review canonical budget wording still contains 5600")
fi
if [[ ${#reviewer_budget_authority_failures[@]} -eq 0 ]]; then
    pass
else
    fail "${reviewer_budget_authority_failures[*]}"
fi

test_start "standalone audit prepares Spec Review and scoped verification evidence before Reviewer dispatch"
standalone_failures=()
review_root="$FRAMEWORK_DIR/skills/assistant-review/SKILL.md"
review_loop="$FRAMEWORK_DIR/skills/assistant-review/references/review-loop.md"
review_input="$FRAMEWORK_DIR/skills/assistant-review/contracts/input.yaml"
review_handoffs="$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml"
review_output="$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml"
review_gates="$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml"
standalone_routing_text="$(tr '\n\t' '  ' < "$review_root"; tr '\n\t' '  ' < "$review_loop"; tr '\n\t' '  ' < "$review_gates")"
standalone_handoff_text="$(tr '\n\t' '  ' < "$review_handoffs" | tr -s '[:space:]' ' ')"

if ! grep -Fq 'review this' "$review_root"; then
    standalone_failures+=("review this invocation is not routed")
fi
if ! printf '%s\n' "$standalone_routing_text" | rg -qi 'standalone.{0,500}spec review|spec review.{0,500}standalone'; then
    standalone_failures+=("standalone review has no explicit Spec Review preparation path")
fi
if ! printf '%s\n' "$standalone_handoff_text" | rg -qi 'spec_review_pass_ref.{0,400}user request/review scope before batch planning'; then
    standalone_failures+=("standalone Spec Review is not recorded against user scope before Reviewer dispatch")
fi
if ! printf '%s\n' "$standalone_handoff_text" | rg -qi 'build_test_verification_ref.{0,500}not[_ -]?applicable'; then
    standalone_failures+=("handoff does not admit a not-applicable build_test_verification_ref")
fi
if ! printf '%s\n' "$standalone_handoff_text" | rg -qi 'enum_values.{0,240}(audit_only_or_no_build_scope|audit[_ -]?only|no[_ -]?build[_ -]?scope|read[_ -]?only[_ -]?scope)'; then
    standalone_failures+=("handoff lacks an enumerated audit/no-build/read-only not-applicable reason")
fi
if ! ruby -ryaml -e '
  handoffs, output, gates = ARGV.map { |path| YAML.load_file(path) }
  reviewer = handoffs.fetch("handoffs").find { |item| item.fetch("name") == "orchestrator_to_reviewer" }
  spec_ref = reviewer.fetch("context_fields").find { |field| field.fetch("name") == "spec_review_pass_ref" }
  verification_ref = reviewer.fetch("context_fields").find { |field| field.fetch("name") == "build_test_verification_ref" }
  ref_fields = verification_ref.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  assertions = gates.fetch("gates").flat_map { |gate| gate.fetch("exit_assertions", []) }
  e9 = assertions.find { |gate| gate.fetch("id") == "E9" }.fetch("check")
  rs2a = assertions.find { |gate| gate.fetch("id") == "RS2A" }.fetch("check")
  build_verification = output.fetch("artifacts").find { |item| item.fetch("name") == "build_verification" }
  build_fields = build_verification.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  test_summary = build_fields.fetch("test_summary")
  evidence_condition = ref_fields.fetch("evidence_ref").fetch("condition")
  build_evidence_ref = build_fields.fetch("evidence_ref")
  build_evidence_condition = build_evidence_ref.fetch("condition")
  build_evidence_validation = build_evidence_ref.fetch("validation")
  no_build_condition = ref_fields.fetch("not_applicable").fetch("condition")
  build_validation = build_verification.fetch("validation")
  test_condition = test_summary.fetch("condition")
  valid = spec_ref.fetch("required") == true &&
    spec_ref.fetch("description").include?("user request/review scope before batch planning") &&
    spec_ref.fetch("validation").include?("Standalone points to Spec Review against user request/review scope") &&
    spec_ref.fetch("validation").include?("workflow_composed points to the final acceptance batch\u0027s spec obligations (missing acceptance criteria, extra scope, changed-files mismatch, verification mismatch), with no separate Spec agent") &&
    e9.include?("Workflow-composed review needs no separate Spec PASS; the final acceptance batch (review_subject acceptance) assigns coverage obligations for missing acceptance criteria, extra scope, changed-files mismatch and verification mismatch") &&
    verification_ref.fetch("required") == true &&
    ref_fields.fetch("evidence_ref").fetch("required") == "conditional" &&
    evidence_condition.include?("due selected check") &&
    evidence_condition.include?("applicable due/executable binding check") &&
    evidence_condition.include?("required/occurred source fix") &&
    verification_ref.fetch("validation").include?("every due selected check and applicable due/executable binding result") &&
    verification_ref.fetch("validation").include?("Each due check and every source fix require current passed evidence") &&
    verification_ref.fetch("validation").include?("a fix invalidates the batch and forbids not_applicable") &&
    verification_ref.fetch("validation").include?("Standalone review-fix requires build/tests") &&
    build_evidence_condition == "review_preparation_mode == workflow_composed and (a due selected check or applicable due/executable binding check applies, or a source fix is required or occurred)" &&
    build_evidence_validation.include?("Equals build_test_verification_ref.evidence_ref unchanged") &&
    no_build_condition.include?("no required/occurred source fix") &&
    no_build_condition.include?("no due selected or applicable due/executable binding check") &&
    ref_fields.fetch("not_applicable").fetch("enum_values").include?("no_build_scope") &&
    e9.include?("current evidence_ref bound to the canonical decision, assessment, every due selected check and applicable due/executable binding result, exclusions, and source") &&
    e9.include?("no_build_scope is allowed only when no fix is required/occurred and no due selected or applicable due/executable binding check applies") &&
    rs2a.include?("after every source fix") && rs2a.include?("fixes invalidate the batch and forbid not_applicable") &&
    rs2a.include?("Standalone review-fix requires build/tests") &&
    build_verification.fetch("condition") == "mode == review-fix" &&
    build_validation.include?("Standalone review-fix must show successful build and test results after its fixes") &&
    build_validation.include?("Workflow-composed review requires evidence_ref equal to build_test_verification_ref.evidence_ref when any due selected check or applicable due/executable binding check applies, or a source fix is required or occurred") &&
    build_validation.include?("not_applicable build_result is permitted only when no due selected or applicable due/executable binding build check applies and no build was executed") &&
    build_fields.fetch("build_result").fetch("enum_values").include?("not_applicable") &&
    test_summary.fetch("required") == "conditional" &&
    test_condition.include?("due selected check") &&
    test_condition.include?("applicable due/executable binding obligation requires an automated test") &&
    build_validation.include?("test_summary is required when") &&
    test_summary.fetch("description").include?("Zero counts mean no tests were executed, not that tests passed")
  exit valid ? 0 : 1
' "$review_handoffs" "$review_output" "$review_gates"; then
    standalone_failures+=("composed/standalone verification evidence conditions or test-summary applicability are mis-scoped")
fi
if ! awk '
    $0 == "  - name: task_journal_path" { in_field = 1; next }
    in_field && /^  - name: / { exit }
    in_field && /required: false/ { optional = 1 }
    END { exit optional ? 0 : 1 }
' "$review_input"; then
    standalone_failures+=("task_journal_path is not optional")
fi
if ! printf '%s\n' "$standalone_routing_text" | rg -qi 'standalone.{0,500}(does not require|without|no required).{0,120}task journal|task journal.{0,200}(optional|not required).{0,500}standalone|standalone.{0,500}task journal.{0,120}(optional|not required)'; then
    standalone_failures+=("standalone review is not explicitly journal-free")
fi

if [[ "${#standalone_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${standalone_failures[*]}"
fi

test_start "review mode infers clear authority and asks only for genuine ambiguity"
if ruby -ryaml -rjson -e '
  input = YAML.load_file(ARGV.fetch(0))
  cases = JSON.parse(File.read(ARGV.fetch(1))).fetch("cases")
  mode = input.fetch("fields").find { |field| field["name"] == "mode" }
  ids = %w[audit-one-pass review-fix-loop-handles-findings workflow-carried-authorization-allows-bounded-review-fix ambiguous-standalone-review-asks-before-review-or-mutation]
  ambiguous = cases.find { |entry| entry["id"] == ids.last }
  valid = mode["required"] == true && mode["on_missing"] == "infer" &&
    mode.fetch("infer_from").include?("Clear report-only intent") &&
    mode.fetch("infer_from").include?("Clear authorization to modify source") &&
    mode.fetch("infer_from").include?("carried active approved implementation workflow") &&
    mode.fetch("infer_from").include?("If neither outcome is unambiguous") &&
    ids.all? { |id| cases.any? { |entry| entry["id"] == id } } &&
    ambiguous.fetch("expected_behavior").join(" ").include?("exactly") &&
    ambiguous.fetch("fail_signals").join(" ").include?("Starts reviewing or editing before asking")
  exit valid ? 0 : 1
' "$FRAMEWORK_DIR/skills/assistant-review/contracts/input.yaml" "$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json"; then
    pass
else
    fail "review mode still asks before inferring clear audit, review-fix, or carried workflow authority"
fi

test_start "review batches require all independent responses before aggregation"
if ruby -ryaml -e '
  handoffs = YAML.load_file(ARGV.fetch(0))
  gates = YAML.load_file(ARGV.fetch(1))
  reviewer = handoffs.fetch("handoffs").find { |entry| entry["name"] == "orchestrator_to_reviewer" }
  context = reviewer.fetch("context_fields").to_h { |field| [field["name"], field] }
  returns = reviewer.fetch("return_fields").to_h { |field| [field["name"], field] }
  review = gates.fetch("gates").find { |gate| gate["phase"] == "REVIEW_STEP" }
  assertions = review.fetch("exit_assertions").to_h { |assertion| [assertion["id"], assertion] }
  valid = reviewer.fetch("context_fields").any? { |field| field["name"] == "review_batch" } && context.key?("batch_id") && context.key?("review_pass_id") && context.key?("review_perspective") &&
    returns.key?("coverage_entries") && assertions.key?("RS_BATCH_BARRIER") &&
    assertions.fetch("RS_BATCH_BARRIER").fetch("check").include?("all expected passes reach terminal accounting")
  exit valid ? 0 : 1
' "$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml" "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml"; then
    pass
else
    fail "assistant-review does not require an all-response independent review batch barrier"
fi

test_start "standalone Spec Review FAIL repairs only in review-fix and remains read-only in audit"
if ruby -ryaml -rjson -e '
  gates = YAML.load_file(ARGV.fetch(0))
  cases = JSON.parse(File.read(ARGV.fetch(1))).fetch("cases")
  entry = gates.fetch("gates").find { |gate| gate["phase"] == "ENTRY" }
  e8 = entry.fetch("exit_assertions").find { |assertion| assertion["id"] == "E8" }
  audit = cases.find { |item| item["id"] == "audit-spec-review-fail-is-read-only" }
  valid = e8.fetch("check").include?("review-fix") &&
    e8.fetch("check").include?("audit") &&
    e8.fetch("check").include?("exits repair/Build/source-mutation dispatch") &&
    e8.fetch("check").include?("dispatches every planned read-only Reviewer pass") &&
    e8.fetch("on_fail").include?("mode=review-fix") &&
    !audit.nil? &&
    audit.fetch("setup_context").join(" ").include?("Spec Review FAIL") &&
    audit.fetch("expected_behavior").join(" ").include?("Dispatches every planned read-only Reviewer pass") &&
    audit.fetch("fail_signals").join(" ").include?("Changes source")
  exit valid ? 0 : 1
' "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml" "$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json"; then
    pass
else
    fail "Spec Review FAIL does not yet distinguish authorized review-fix repair from audit read-only exit"
fi

write_index_validator_fixture() {
    local skill_dir="$1"
    local skill_name

    skill_name="$(basename "$skill_dir")"
    mkdir -p "$skill_dir/contracts"
    cat > "$skill_dir/SKILL.md" <<EOF
---
name: $skill_name
description: "Indexed validator review regression fixture."
---

# Indexed Validator Fixture

| \`contracts/input.yaml\` | fixture input |
| \`contracts/output.yaml\` | fixture output |
EOF
    cat > "$skill_dir/contracts/input.yaml" <<EOF
schema_version: "1.0"
contract: input
skill: $skill_name

fields:
  - name: request
    type: string
    required: true
    description: "Entry request selected by fixture"
    validation: "Non-empty request"
    on_missing: ask
EOF
    cat > "$skill_dir/contracts/output.yaml" <<EOF
schema_version: "1.0"
contract: output
skill: $skill_name

artifacts:
  - name: result
    type: string
    required: true
    description: "Fixture result"
    validation: "Non-empty result"
    on_fail: "Re-run the fixture and provide the result"
EOF
}

write_index_file() {
    local skill_dir="$1"
    local authoritative_type="$2"
    local section="$3"
    local key="$4"
    local names="$5"
    local budget="$6"
    local prose_match="${7:-}"
    local skill_name
    local match_line=""

    skill_name="$(basename "$skill_dir")"
    if [[ -n "$prose_match" ]]; then
        match_line="        match: \"$prose_match\""
    fi
    cat > "$skill_dir/contracts/index.yaml" <<EOF
schema_version: "1.0"
contract: index
skill: $skill_name

authoritative_contracts:
  - path: contracts/input.yaml
    contract: $authoritative_type
  - path: contracts/output.yaml
    contract: output

load_sets:
  entry:
    selectors:
      - id: fixture-entry-fields
        path: contracts/input.yaml
        section: $section
        key: $key
        names: [$names]
$match_line
    budget_words: $budget

fallback:
  on_missing_selector: load_full_authoritative_file
  on_invalid_selector: load_full_authoritative_file
EOF
}

test_start "contract-index validator rejects wrong type, section, key, name, duplicate, prose, and budget cases"
INDEX_VALIDATOR_ROOT="$(mktemp -d)"
p0p4_register_cleanup "$INDEX_VALIDATOR_ROOT"
index_validation_failures=()

wrong_type_dir="$INDEX_VALIDATOR_ROOT/wrong-authoritative-type"
write_index_validator_fixture "$wrong_type_dir"
write_index_file "$wrong_type_dir" output fields name request 500
wrong_type_err="$INDEX_VALIDATOR_ROOT/wrong-type.err"
if "$skill_validator" --skill "$wrong_type_dir" >/dev/null 2>"$wrong_type_err" \
    || ! grep -Fq 'CONTRACT_INDEX_AUTHORITATIVE_CONTRACT' "$wrong_type_err"; then
    index_validation_failures+=("wrong authoritative contract type was not rejected with CONTRACT_INDEX_AUTHORITATIVE_CONTRACT")
fi

section_dir="$INDEX_VALIDATOR_ROOT/unresolved-section"
write_index_validator_fixture "$section_dir"
write_index_file "$section_dir" input absent_fields name request 500
section_err="$INDEX_VALIDATOR_ROOT/section.err"
if "$skill_validator" --skill "$section_dir" >/dev/null 2>"$section_err" \
    || ! grep -Fq 'CONTRACT_INDEX_SELECTOR_SECTION_UNRESOLVED' "$section_err"; then
    index_validation_failures+=("unresolved section was not rejected with CONTRACT_INDEX_SELECTOR_SECTION_UNRESOLVED")
fi

key_dir="$INDEX_VALIDATOR_ROOT/unresolved-key"
write_index_validator_fixture "$key_dir"
write_index_file "$key_dir" input fields absent_key request 500
key_err="$INDEX_VALIDATOR_ROOT/key.err"
if "$skill_validator" --skill "$key_dir" >/dev/null 2>"$key_err" \
    || ! grep -Fq 'CONTRACT_INDEX_SELECTOR_KEY_UNRESOLVED' "$key_err"; then
    index_validation_failures+=("unresolved key was not rejected with CONTRACT_INDEX_SELECTOR_KEY_UNRESOLVED")
fi

name_dir="$INDEX_VALIDATOR_ROOT/unresolved-name"
write_index_validator_fixture "$name_dir"
write_index_file "$name_dir" input fields name missing_request 500
name_err="$INDEX_VALIDATOR_ROOT/name.err"
if "$skill_validator" --skill "$name_dir" >/dev/null 2>"$name_err" \
    || ! grep -Fq 'CONTRACT_INDEX_SELECTOR_NAME_UNRESOLVED' "$name_err"; then
    index_validation_failures+=("unresolved name was not rejected with CONTRACT_INDEX_SELECTOR_NAME_UNRESOLVED")
fi

duplicate_dir="$INDEX_VALIDATOR_ROOT/duplicate-name"
write_index_validator_fixture "$duplicate_dir"
write_index_file "$duplicate_dir" input fields name 'request, request' 500
duplicate_err="$INDEX_VALIDATOR_ROOT/duplicate.err"
if "$skill_validator" --skill "$duplicate_dir" >/dev/null 2>"$duplicate_err" \
    || ! grep -Fq 'CONTRACT_INDEX_SELECTOR_NAME_DUPLICATE' "$duplicate_err"; then
    index_validation_failures+=("duplicate selected name was not rejected with CONTRACT_INDEX_SELECTOR_NAME_DUPLICATE")
fi

prose_dir="$INDEX_VALIDATOR_ROOT/prose-match"
write_index_validator_fixture "$prose_dir"
write_index_file "$prose_dir" input fields name request 500 'Fields applicable at entry'
prose_err="$INDEX_VALIDATOR_ROOT/prose.err"
if "$skill_validator" --skill "$prose_dir" >/dev/null 2>"$prose_err" \
    || ! grep -Fq 'CONTRACT_INDEX_SELECTOR_PROSE_MATCH' "$prose_err"; then
    index_validation_failures+=("prose match selector was not rejected with CONTRACT_INDEX_SELECTOR_PROSE_MATCH")
fi

over_budget_dir="$INDEX_VALIDATOR_ROOT/selected-content-over-budget"
write_index_validator_fixture "$over_budget_dir"
write_index_file "$over_budget_dir" input fields name request 1
over_budget_err="$INDEX_VALIDATOR_ROOT/over-budget.err"
if "$skill_validator" --skill "$over_budget_dir" >/dev/null 2>"$over_budget_err" \
    || ! grep -Fq 'CONTRACT_INDEX_SELECTOR_BUDGET_EXCEEDED' "$over_budget_err"; then
    index_validation_failures+=("selected content over budget was not rejected with CONTRACT_INDEX_SELECTOR_BUDGET_EXCEEDED")
fi

if [[ "${#index_validation_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${index_validation_failures[*]}"
fi

test_start "native workflow contracts preserve adaptive intensity and role separation"
intensity_failures=()
workflow_input="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/input.yaml"
workflow_output="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"
workflow_gates="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"
workflow_controller="$FRAMEWORK_DIR/skills/assistant-workflow/references/workflow-controller.md"

if ! grep -Fq 'direct_main is permitted at every size/risk' "$workflow_input"; then
    intensity_failures+=("light input routing no longer permits native inline execution")
fi
if ! grep -Fq 'formal review retains fresh independent' "$workflow_controller" \
    || ! grep -Fq 'subagent_execution_mode=not_applicable' "$workflow_controller"; then
    intensity_failures+=("light controller routing lost native fresh independent review/direct execution behavior")
fi
for role in 'Code Writer' 'Builder/Tester' 'Code Reviewer'; do
    if ! grep -Fq "$role" "$workflow_gates" || ! grep -Fq "$role" "$workflow_output"; then
        intensity_failures+=("standard/strict native contracts lost $role evidence")
    fi
done
if ! grep -Fq 'controller_intensity in [standard, strict]' "$workflow_gates"; then
    intensity_failures+=("standard/strict role gate is missing from native phase contracts")
fi
if [[ "${#intensity_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${intensity_failures[*]}"
fi

test_start "explicit phase markers are required only by strict intensity or explicit project policy"
marker_text="$(printf '%s\n' \
    "$(cat "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md")" \
    "$(cat "$FRAMEWORK_DIR/skills/assistant-workflow/references/workflow-controller.md")" \
    "$(cat "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md")")"
if printf '%s\n' "$marker_text" | rg -qi 'phase (checkpoints|markers).*(required only|only required).*(strict|project policy)' \
    && ! printf '%s\n' "$marker_text" | rg -qi 'print checkpoints at every phase transition|these examples are mandatory'; then
    pass
else
    fail "workflow guidance still makes explicit phase markers universal instead of strict/project-policy only"
fi

test_start "workflow contracts retire Learning Controller persistence while retaining non-blocking metrics"
learning_failures=()
if rg -n -i -e 'Learning Controller' -e 'learning_capture_mode' -e 'memory_(reflect|signal|trend)' \
    "$workflow_input" "$workflow_output" "$workflow_gates" "$workflow_controller" >/tmp/p0p4-workflow-retired-learning.out; then
    learning_failures+=("workflow contracts retain retired learning-controller persistence")
fi
completion_controller="$FRAMEWORK_DIR/skills/assistant-workflow/references/completion-controller.md"
if ! rg -qi 'metrics.*(optional|non-blocking|never a reason to block)|does not make metrics blocking' "$completion_controller"; then
    learning_failures+=("controller no longer keeps metrics optional and non-blocking")
fi
if [[ "${#learning_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${learning_failures[*]}"
fi

test_start "README and contract design guide define metrics as optional non-blocking observability"
metrics_doc_failures=()
for doc in "$FRAMEWORK_DIR/README.md" "$FRAMEWORK_DIR/docs/skill-contract-design-guide.md"; do
    metrics_doc_text="$(tr '\n\t' '  ' < "$doc" | tr -s '[:space:]' ' ')"
    if ! printf '%s\n' "$metrics_doc_text" | rg -qi 'metrics.{0,120}(optional|non-blocking|not a completion blocker|must not block)'; then
        metrics_doc_failures+=("$(basename "$doc") lacks optional/non-blocking metrics guidance")
    fi
    if printf '%s\n' "$metrics_doc_text" | rg -qi '(strict stop gate|before task handoff).{0,120}metrics|metrics.{0,120}(strict stop gate|before task handoff)'; then
        metrics_doc_failures+=("$(basename "$doc") still describes metrics as a completion gate")
    fi
done
if [[ "${#metrics_doc_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${metrics_doc_failures[*]}"
fi

test_start "independent discovery preserves invariant traces, original scope and role mirrors"
if ruby -rjson - "$FRAMEWORK_DIR" <<'RUBY'
root=ARGV.fetch(0)
prompts=%w[agents/codex/code-reviewer.toml agents/codex/reviewer.toml agents/claude/code-reviewer.md agents/claude/reviewer.md].map{|p|File.read(File.join(root,p))}
terms=['identify the invariant','trace its producer and consumers','violating input/event sequence','supporting or rejecting','original requirements/full proposed change','carried mapping only orients','findings=[] and verdict=not_assessed']
ids=JSON.parse(File.read(File.join(root,'skills/assistant-review/evals/cases.json'))).fetch('cases').map{|c|c.fetch('id')}
expected=%w[discovery-cross-file-producer-consumer discovery-temporal-late-event discovery-compatibility-consumer discovery-authority-boundary discovery-clean-control-no-invented-finding]
exit(prompts.all?{|p|terms.all?{|t|p.include?(t)}} && (expected-ids).empty? ? 0 : 1)
RUBY
then pass; else fail "discovery scope/procedure or role mirrors drifted"; fi

test_start "acceptance review owns spec reconciliation and light review is compact and explicitly gated"
if ruby -ryaml -rjson - "$FRAMEWORK_DIR" <<'RUBY'
root=ARGV.fetch(0); review=File.join(root,'skills/assistant-review')
text=->(path){File.read(File.join(review,path)).gsub(/\s+/,' ')}
skill=text.('SKILL.md'); loop_text=text.('references/review-loop.md')
input,handoffs,output,index=%w[input handoffs output index].map{|n|YAML.load_file(File.join(review,"contracts/#{n}.yaml"))}
failures=[]
need=->(label,ok){failures << label unless ok}
# U1: the final acceptance review is the single reconciliation owner and carries the spec obligations.
need.('SKILL acceptance owner',skill.include?('Final acceptance review solely owns request/plan/delivery reconciliation, including task-wide work and spec obligations: missing criteria, extra scope, changed-files or verification mismatch.'))
need.('SKILL composed review drops carried Spec PASS',skill.include?('Workflow-composed review consumes current due-check evidence; acceptance review owns spec checks.') && !skill.include?('consumes carried Spec PASS'))
need.('review-loop acceptance owner',loop_text.include?('no separate Spec agent runs (historical Spec PASS records stay readable). The final fresh acceptance review (`review_subject=acceptance`) solely owns request/plan/delivery reconciliation: its frozen batch assigns the spec obligations (missing acceptance criteria, extra scope, changed-files mismatch, verification mismatch)'))
subject=input.fetch('fields').find{|f|f['name']=='review_subject'}
need.('input review_subject owner',subject.fetch('description').include?('The final acceptance review is the single owner of request, plan and delivery reconciliation; its batch carries the spec obligations (missing acceptance criteria, extra scope, changed-files mismatch, verification mismatch) and no separate Spec agent runs.'))
# U2: ordinary light review records a compact result; the structured path stays valid when required.
need.('SKILL compact light',skill.include?('trivial/small light review (controller_intensity light) uses one newly created reviewer covering both concerns (another after a fix); light review records the compact result unless admission, a Pack or expanded impact requires structure (plan review: persisted/executable admission only)'))
need.('review-loop compact light',loop_text.include?('records a compact result: fresh actor ID, native invocation ID, lowercase runtime (codex requires fork_turns=none), PASS or findings (stable id such as `light-1`, file/line, description), evidence refs and reviewed scope; its post-fix re-review by a different newly created reviewer receives the fixed findings as `{aggregate_finding_id, description}` rows and returns `closure_results` (`verified_closed`, `regressed` or `incomplete`) per `aggregate_finding_id`. It needs no batch plan, ledgers, 13-key fresh_dispatch or review-tools validation unless persisted/executable admission, an Architecture Pack or expanded impact requires the structured path'))
artifacts=output.fetch('artifacts').to_h{|a|[a['name'],a]}
structured='structured review path; an ordinary compact light review records only its compact result'
output_text=File.read(File.join(review,'contracts/output.yaml')).gsub(/\s*#\s*/,' ')
need.('output compact result runtime and re-review',output_text.include?('records only a compact result: fresh reviewer actor_id, native_invocation_id, lowercase runtime (codex requires fork_turns=none), PASS or findings (each with a stable id such as light-1, file/line and description), evidence refs and reviewed scope') && output_text.include?('A compact re-review after a fix uses a different newly created reviewer, receives the fixed findings as {aggregate_finding_id, description} rows and records closure_results (verified_closed, regressed or incomplete) for each aggregate_finding_id.'))
# Y2: one closure vocabulary; the round-7 compact names are gone.
retired=['fixed_finding_ids','fixed_finding_closures','`closure_status` `closed` or `open`','closure_status closed or open','as `closed` or `open`']
%w[SKILL.md references/review-loop.md references/review-batch.md contracts/output.yaml contracts/handoffs.yaml contracts/input.yaml].each{|p|t=File.read(File.join(review,p));retired.each{|w|need.("#{p} retired #{w}",!t.include?(w))}}
%w[agents/claude/reviewer.md agents/claude/code-reviewer.md agents/codex/reviewer.toml agents/codex/code-reviewer.toml].each{|p|t=File.read(File.join(root,p));retired.each{|w|need.("#{p} retired #{w}",!t.include?(w))}}
# Y3: the medium minimum names the canonical final-batch count.
need.('review-loop medium minimum',loop_text.include?('Medium minimum is plan review plus a final batch at the canonical per-size count (medium 3).') && !loop_text.include?('>=2 quality passes'))
need.('output structured-path conditions',%w[final_summary review_delegation_path].all?{|n|artifacts.fetch(n)['condition']==structured})
# K4: explicit light indicator and caller intensity.
intensity=input.fetch('fields').find{|f|f['name']=='controller_intensity'}
need.('input controller_intensity enum',intensity && intensity['type']=='enum' && intensity['enum_values']==%w[light standard strict] && intensity['on_missing']=='infer' && intensity['infer_from'].include?('Absent from review-tools authority is not light.'))
need.('entry loads controller_intensity',index.dig('load_sets','entry','selectors',0,'names').include?('controller_intensity'))
batch=handoffs.fetch('handoffs').find{|h|h['name']=='orchestrator_to_reviewer'}.fetch('context_fields').find{|f|f['name']=='review_batch'}
topologies=[batch.fetch('object_fields').find{|f|f['name']=='topology'}, artifacts.fetch('final_summary').fetch('object_fields').find{|f|f['name']=='final_batch_plan'}.fetch('object_fields').find{|f|f['name']=='topology'}]
need.('topology.light_review optional boolean',topologies.all?{|t|(f=t.fetch('object_fields').find{|x|x['name']=='light_review'}) && f['type']=='boolean' && f['required']==false})
# W1: the light re-review receives the closure ledger and returns closure_results in every reviewer role.
roles=%w[agents/claude/reviewer.md agents/claude/code-reviewer.md agents/codex/reviewer.toml agents/codex/code-reviewer.toml]
need.('role light closure bullets',roles.all?{|r|t=File.read(File.join(root,r)); t.include?('Also include them for a `light_contract_and_runtime` re-review with non-empty `previously_fixed`.') && t.include?('or for a `light_contract_and_runtime` re-review with non-empty `previously_fixed`, use the supplied closure ledger, return `closure_results` for every fixed ID')})
# E4/E5: current light eval controls, medium+ audit expectation and v10 discovery wording.
cases=JSON.parse(File.read(File.join(review,'evals/cases.json'))).fetch('cases').to_h{|c|[c['id'],c]}
need.('light eval compact runtime',cases.fetch('light-review-records-compact-fresh-result')['expected_behavior'].include?('Records a compact result: reviewer actor ID, native invocation ID, lowercase runtime, PASS or findings, evidence refs and reviewed scope.'))
need.('light eval positive/negative',cases.key?('light-review-records-compact-fresh-result') && cases.key?('light-review-standard-small-keeps-two-passes') && cases['light-review-standard-small-keeps-two-passes']['setup_context'].join(' ').include?('controller_intensity is standard'))
need.('audit-one-pass medium+',cases.fetch('audit-one-pass')['expected_behavior'].include?('For this medium+ scope, freezes one review snapshot and plans at least two independent narrow review passes.'))
need.('discovery v10 schema wording',!File.read(File.join(review,'evals/cases.json')).include?('unchanged v9 return schema'))
abort failures.join('; ') unless failures.empty?
RUBY
then pass; else fail "acceptance spec ownership, compact light review, light indicator, closure bullets or light evals drifted"; fi

test_start "plan review is one fresh pass, compact light reviewers skip the batch schema, and review contracts stay aligned"
if ruby -ryaml -rjson - "$FRAMEWORK_DIR" <<'RUBY'
root=ARGV.fetch(0); review=File.join(root,'skills/assistant-review')
text=->(path){File.read(File.join(review,path)).gsub(/\s+/,' ')}
skill=text.('SKILL.md'); loop_text=text.('references/review-loop.md'); batch_text=text.('references/review-batch.md')
input,handoffs,output=%w[input handoffs output].map{|n|YAML.load_file(File.join(review,"contracts/#{n}.yaml"))}
failures=[]
need=->(label,ok){failures << label unless ok}
plan_p='plan_coverage_and_feasibility'
# U4: plan review topology and its post-fix closure re-review.
reviewer=handoffs.fetch('handoffs').find{|h|h['name']=='orchestrator_to_reviewer'}
context=reviewer.fetch('context_fields').to_h{|f|[f['name'],f]}; returns=reviewer.fetch('return_fields').to_h{|f|[f['name'],f]}
final_plan=output.fetch('artifacts').find{|a|a['name']=='final_summary'}.fetch('object_fields').find{|f|f['name']=='final_batch_plan'}
plans=[context.fetch('review_batch'),final_plan]
topologies=plans.map{|b|b.fetch('object_fields').find{|f|f['name']=='topology'}}
need.('topology.plan_review optional boolean',topologies.all?{|t|(f=t.fetch('object_fields').find{|x|x['name']=='plan_review'}) && f['type']=='boolean' && f['required']==false && f['validation'].include?('plan_coverage_and_feasibility')})
need.('handoff plan_review rule',topologies[0].fetch('object_fields').find{|x|x['name']=='plan_review'}['validation'].start_with?('true only when review_subject is plan; required true for a plan_coverage_and_feasibility pass. True requires exactly one plan_coverage_and_feasibility discovery pass, discovery_pass_count 1 and closure_verification_required false'))
perspectives=plans.flat_map{|b|[b.fetch('object_fields').find{|f|f['name']=='expected_passes'},b.fetch('object_fields').find{|f|f['name']=='required_coverage_tuples'}].map{|f|f.fetch('object_fields').find{|x|%w[perspective review_perspective].include?(x['name'])}}}+[context.fetch('review_perspective'),returns.fetch('review_perspective')]
need.('plan perspective enum',perspectives.length==6 && perspectives.all?{|f|f.fetch('enum_values').last==plan_p})
need.('plan closure_results condition',returns.fetch('closure_results')['condition']=='review_perspective == closure_verification, or (review_perspective in [light_contract_and_runtime, plan_coverage_and_feasibility] and previously_fixed is non-empty)')
# R1: the structured previously_fixed ledger no longer names the compact re-review (Workflow owns its rows).
need.('previously_fixed structured-only condition',context.fetch('previously_fixed')['condition']=='review_perspective == closure_verification, or a post-fix re-review with review_perspective in [light_contract_and_runtime, plan_coverage_and_feasibility]' && !context.fetch('previously_fixed')['description'].include?('compact'))
need.('topology plan text',topologies[0]['validation'].include?('plan review (review_subject plan, plan_review true)=1 fresh plan_coverage_and_feasibility pass at any scope size') && topologies[0]['validation'].include?('(historical multi-pass plan reviews stay readable; new plan reviews use exactly one pass)') && topologies[0].fetch('object_fields').find{|x|x['name']=='plan_review'}['validation'].include?('Absent or false keeps the canonical topology; historical multi-pass plan reviews stay readable; new plan reviews use exactly one pass.'))
need.('input review_subject plan topology',input.fetch('fields').find{|f|f['name']=='review_subject'}['description'].include?('Plan review uses one fresh plan_coverage_and_feasibility pass with topology.plan_review true; historical multi-pass plan reviews stay readable; new plan reviews use exactly one pass.'))
need.('SKILL plan review',skill.include?('One fresh `plan_coverage_and_feasibility` plan-review pass checks original requirements') && skill.include?('Corrections receive fresh closure review before approval'))
need.('review-loop plan review',loop_text.include?('Plan review (`review_subject` plan) is one fresh `plan_coverage_and_feasibility` pass at any size and records the compact result unless the structured path is required: reviewer identity, PASS or findings rows `{aggregate_finding_id, file_line, description}`, `reviewed_scope`, request/plan coverage (`request_plan_reconciliation` field names) and, after a material plan fix, `closure_results` from a new fresh re-reviewer. Its structured path is one `topology.plan_review` pass; post-fix, one new pass with the closure ledger (historical multi-pass plan reviews stay readable).') && loop_text.include?('only closure or a light/plan re-review gets ledger'))
need.('review-batch plan review',batch_text.include?('structured plan review (`topology.plan_review` true) is one `plan_coverage_and_feasibility` pass (post-fix: one new pass with the closure ledger)'))
# U5: plan review is compact unless structured; one-pass plan batches expect one response; the multi-pass label names v10 acceptance.
rc=output.fetch('artifacts').find{|a|a['name']=='final_summary'}.fetch('object_fields').find{|f|f['name']=='batch_summaries'}
rc=rc && rc.fetch('object_fields').find{|f|f['name']=='expected_response_count'}
need.('output expected_response_count plan',rc && rc['validation']=='1 to 6; 1 only for trivial/small light review or plan review (topology.plan_review true)')
need.('output plan compact header',File.read(File.join(review,'contracts/output.yaml')).gsub(/\s*#\s*/,' ').include?('Plan review (review_subject plan) records the compact result unless the structured path is required: reviewer identity, PASS or findings rows {aggregate_finding_id, file_line, description}, reviewed scope, request/plan coverage using the request_plan_reconciliation field names, and closure_results after a material plan fix by a new fresh re-reviewer.'))
tools_test=File.read(File.join(root,'tests/p0-p4/review-tools-contracts.sh'))
need.('review-tools multi-pass plan label',tools_test.include?("'v10 multi-pass plan batch accepted; one-pass is prose-enforced'") && !tools_test.include?('historical multi-pass plan reviews stay readable'))
# N1/N2/Y4: the pre-10.0 migration header and the current one-pass plan review label.
handoffs_raw=File.read(File.join(review,'contracts/handoffs.yaml')); tools_raw=File.read(File.join(review,'scripts/review-tools.py'))
need.('handoffs pre-10.0 migration header',handoffs_raw.include?("\n# pre-10.0 migration: persisted 6.0 and incompatible 7.0/7.1/7.2/8.0 packets") && !handoffs_raw.include?('v9.0 migration'))
need.('review-tools HELP and comment plan label',tools_raw.include?("\nHistorical multi-pass plan reviews stay readable; new plan reviews use exactly one pass.\n") && tools_raw.include?("Historical multi-pass plan reviews stay\n    # readable; new plan reviews use exactly one pass.\n"))
need.('retired plan-review label',[tools_raw,handoffs_raw,File.read(File.join(review,'contracts/input.yaml')),File.read(File.join(review,'references/review-batch.md')),File.read(File.join(review,'references/review-loop.md'))].none?{|t|t.downcase.include?('plan review remains acceptable')})
roles=%w[agents/claude/reviewer.md agents/claude/code-reviewer.md agents/codex/reviewer.toml agents/codex/code-reviewer.toml].map{|r|File.read(File.join(root,r))}
need.('role plan pass and closure',roles.all?{|t|t.include?('Plan review uses one newly created fresh `plan_coverage_and_feasibility` pass') && t.include?('Also include them for a `plan_coverage_and_feasibility` re-review with non-empty `previously_fixed`.') && t.include?('A `plan_coverage_and_feasibility` re-review with non-empty `previously_fixed` follows the same closure rule.')})
# M2: a compact light reviewer without a frozen batch skips worker_return_schema; the Review root loads the loop only for structured batches.
compact='When no frozen batch is supplied (compact light or plan review), return only `status`, PASS or findings each with a stable id (for example `light-1`) plus file/line and description, `reviewed_scope` and evidence refs; skip `worker_return_schema` resolution and do not invent batch identity. A compact re-review after a fix is a different newly created agent from the first reviewer; it receives the fixed findings as `{aggregate_finding_id, description}` rows and returns `closure_results` (`verified_closed`, `regressed` or `incomplete`) for each `aggregate_finding_id`. Plan review records the compact result unless the structured path is required: reviewer identity, PASS or findings rows `{aggregate_finding_id, file_line, description}`, `reviewed_scope`, request/plan coverage using the `request_plan_reconciliation` field names, and, after a material plan fix, `closure_results` from a different newly created re-reviewer. A structured frozen batch keeps the canonical return below.'
need.('role compact light return',roles.all?{|t|(i=t.index(compact)) && (j=t.index('Before first response, resolve `worker_return_schema`')) && i<j && !t.include?('fixed_finding_ids') && !t.include?('closure_status')})
need.('SKILL structured-only loop load',skill.include?('Structured batches load [review-loop.md](references/review-loop.md) before the first batch; v10 rules:') && !skill.include?('Load [review-loop.md](references/review-loop.md) before the first batch.'))
# L5: spec_review_pass_ref description matches its workflow-composed validation.
need.('spec_review_pass_ref description',context.fetch('spec_review_pass_ref')['description']=="Standalone: pointer to the current Spec Review result recorded against the user request/review scope before batch planning. Workflow-composed: pointer to the final acceptance batch's spec obligations; it needs no separate Spec PASS.")
# L7: processing comments appear once, after the last input field.
lines=File.readlines(File.join(review,'contracts/input.yaml'),chomp:true)
steps=lines.each_index.select{|i|lines[i].start_with?('# 1. Resolve review_scope')}
need.('input processing comments at end',steps.length==1 && lines[steps[0]..].all?{|l|l.empty? || l.start_with?('#')})
# L8: the compact light eval expects fork_turns=none on Codex.
light_case=JSON.parse(File.read(File.join(review,'evals/cases.json'))).fetch('cases').find{|c|c['id']=='light-review-records-compact-fresh-result'}
need.('light eval fork_turns',light_case.fetch('expected_behavior').include?('On Codex, creates the fresh reviewer with fork_turns=none so no parent turns are inherited.'))
abort failures.join('; ') unless failures.empty?
RUBY
then pass; else fail "plan review topology, compact plan or light reviewer return, plan response count, spec ref wording, input comment placement or light eval drifted"; fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
