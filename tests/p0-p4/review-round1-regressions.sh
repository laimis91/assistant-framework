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
                if (low ~ /load/ && low ~ /(before the first review|before each review|before declaring clean)/) print
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
review_gates="$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml"
standalone_routing_text="$(tr '\n\t' '  ' < "$review_root"; tr '\n\t' '  ' < "$review_loop"; tr '\n\t' '  ' < "$review_gates")"
standalone_handoff_text="$(tr '\n\t' '  ' < "$review_handoffs"; tr -s '[:space:]' ' ')"

if ! grep -Fq 'review this' "$review_root"; then
    standalone_failures+=("review this invocation is not routed")
fi
if ! printf '%s\n' "$standalone_routing_text" | rg -qi 'standalone.{0,500}spec review|spec review.{0,500}standalone'; then
    standalone_failures+=("standalone review has no explicit Spec Review preparation path")
fi
if ! printf '%s\n' "$standalone_routing_text" | rg -qi 'spec review.{0,500}(user scope|user request).{0,500}(before|prior to).{0,120}reviewer|user (scope|request).{0,500}spec review.{0,500}(before|prior to).{0,120}reviewer'; then
    standalone_failures+=("standalone Spec Review is not recorded against user scope before Reviewer dispatch")
fi
if ! printf '%s\n' "$standalone_handoff_text" | rg -qi 'build_test_verification_ref.{0,500}not[_ -]?applicable'; then
    standalone_failures+=("handoff does not admit a not-applicable build_test_verification_ref")
fi
if ! printf '%s\n' "$standalone_handoff_text" | rg -qi 'enum_values.{0,240}(audit_only_or_no_build_scope|audit[_ -]?only|no[_ -]?build[_ -]?scope|read[_ -]?only[_ -]?scope)'; then
    standalone_failures+=("handoff lacks an enumerated audit/no-build/read-only not-applicable reason")
fi
if ! printf '%s\n' "$standalone_routing_text" | rg -qi '(source|production) fix(es|ed)?.{0,600}(subsequent|next).{0,160}review(er)? (round|dispatch).{0,600}(real|current|passed).{0,160}(build/test|build and test|test/build) evidence'; then
    standalone_failures+=("post-fix Reviewer rounds do not require real current build/test evidence")
fi
if ! printf '%s\n' "$standalone_routing_text $standalone_handoff_text" | rg -qi 'workflow[_ -]?composed.{0,700}carried.{0,300}spec review.{0,700}(build/test|build and test) evidence'; then
    standalone_failures+=("workflow-composed review does not explicitly consume carried Spec PASS and build/test evidence")
fi
if ! awk '
    $0 == "  - name: task_journal_path" { in_field = 1; next }
    in_field && /^  - name: / { exit }
    in_field && /required: false/ { optional = 1 }
    END { exit optional ? 0 : 1 }
' "$review_input"; then
    standalone_failures+=("task_journal_path is not optional")
fi
if ! printf '%s\n' "$standalone_routing_text" | rg -qi 'standalone.{0,500}(does not require|without|no required).{0,120}task journal|task journal.{0,200}(optional|not required).{0,500}standalone'; then
    standalone_failures+=("standalone review is not explicitly journal-free")
fi

if [[ "${#standalone_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${standalone_failures[*]}"
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
effort: low
triggers:
  - pattern: "indexed validator fixture"
    priority: 50
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

if ! grep -Fq 'For controller_intensity=light small low-risk localized source changes, use not_applicable' "$workflow_input"; then
    intensity_failures+=("light input routing no longer permits native inline execution")
fi
if ! grep -Fq 'fresh self-review' "$workflow_controller" \
    || ! grep -Fq 'subagent_execution_mode=not_applicable' "$workflow_controller"; then
    intensity_failures+=("light controller routing lost native fresh-self-review/not-applicable behavior")
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
    if ! rg -qi 'metrics.{0,120}(optional|non-blocking|not a completion blocker|must not block)' "$doc"; then
        metrics_doc_failures+=("$(basename "$doc") lacks optional/non-blocking metrics guidance")
    fi
    if rg -qi '(strict stop gate|before task handoff).{0,120}metrics|metrics.{0,120}(strict stop gate|before task handoff)' "$doc"; then
        metrics_doc_failures+=("$(basename "$doc") still describes metrics as a completion gate")
    fi
done
if [[ "${#metrics_doc_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${metrics_doc_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
