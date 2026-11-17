#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

skill_validator="$FRAMEWORK_DIR/tools/skills/validate-skills.sh"

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
    local prose_match="${6:-}"
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

fallback:
  on_missing_selector: load_full_authoritative_file
  on_invalid_selector: load_full_authoritative_file
EOF
}

test_start "contract-index validator rejects wrong type, section, key, name, duplicate, and prose cases"
INDEX_VALIDATOR_ROOT="$(mktemp -d)"
p0p4_register_cleanup "$INDEX_VALIDATOR_ROOT"
index_validation_failures=()

wrong_type_dir="$INDEX_VALIDATOR_ROOT/wrong-authoritative-type"
write_index_validator_fixture "$wrong_type_dir"
write_index_file "$wrong_type_dir" output fields name request
wrong_type_err="$INDEX_VALIDATOR_ROOT/wrong-type.err"
if "$skill_validator" --skill "$wrong_type_dir" >/dev/null 2>"$wrong_type_err" \
    || ! grep -Fq 'CONTRACT_INDEX_AUTHORITATIVE_CONTRACT' "$wrong_type_err"; then
    index_validation_failures+=("wrong authoritative contract type was not rejected with CONTRACT_INDEX_AUTHORITATIVE_CONTRACT")
fi

section_dir="$INDEX_VALIDATOR_ROOT/unresolved-section"
write_index_validator_fixture "$section_dir"
write_index_file "$section_dir" input absent_fields name request
section_err="$INDEX_VALIDATOR_ROOT/section.err"
if "$skill_validator" --skill "$section_dir" >/dev/null 2>"$section_err" \
    || ! grep -Fq 'CONTRACT_INDEX_SELECTOR_SECTION_UNRESOLVED' "$section_err"; then
    index_validation_failures+=("unresolved section was not rejected with CONTRACT_INDEX_SELECTOR_SECTION_UNRESOLVED")
fi

key_dir="$INDEX_VALIDATOR_ROOT/unresolved-key"
write_index_validator_fixture "$key_dir"
write_index_file "$key_dir" input fields absent_key request
key_err="$INDEX_VALIDATOR_ROOT/key.err"
if "$skill_validator" --skill "$key_dir" >/dev/null 2>"$key_err" \
    || ! grep -Fq 'CONTRACT_INDEX_SELECTOR_KEY_UNRESOLVED' "$key_err"; then
    index_validation_failures+=("unresolved key was not rejected with CONTRACT_INDEX_SELECTOR_KEY_UNRESOLVED")
fi

name_dir="$INDEX_VALIDATOR_ROOT/unresolved-name"
write_index_validator_fixture "$name_dir"
write_index_file "$name_dir" input fields name missing_request
name_err="$INDEX_VALIDATOR_ROOT/name.err"
if "$skill_validator" --skill "$name_dir" >/dev/null 2>"$name_err" \
    || ! grep -Fq 'CONTRACT_INDEX_SELECTOR_NAME_UNRESOLVED' "$name_err"; then
    index_validation_failures+=("unresolved name was not rejected with CONTRACT_INDEX_SELECTOR_NAME_UNRESOLVED")
fi

duplicate_dir="$INDEX_VALIDATOR_ROOT/duplicate-name"
write_index_validator_fixture "$duplicate_dir"
write_index_file "$duplicate_dir" input fields name 'request, request'
duplicate_err="$INDEX_VALIDATOR_ROOT/duplicate.err"
if "$skill_validator" --skill "$duplicate_dir" >/dev/null 2>"$duplicate_err" \
    || ! grep -Fq 'CONTRACT_INDEX_SELECTOR_NAME_DUPLICATE' "$duplicate_err"; then
    index_validation_failures+=("duplicate selected name was not rejected with CONTRACT_INDEX_SELECTOR_NAME_DUPLICATE")
fi

prose_dir="$INDEX_VALIDATOR_ROOT/prose-match"
write_index_validator_fixture "$prose_dir"
write_index_file "$prose_dir" input fields name request 'Fields applicable at entry'
prose_err="$INDEX_VALIDATOR_ROOT/prose.err"
if "$skill_validator" --skill "$prose_dir" >/dev/null 2>"$prose_err" \
    || ! grep -Fq 'CONTRACT_INDEX_SELECTOR_PROSE_MATCH' "$prose_err"; then
    index_validation_failures+=("prose match selector was not rejected with CONTRACT_INDEX_SELECTOR_PROSE_MATCH")
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
# N1/N2/Y4: the pre-10.0 migration header and the current one-pass plan review label.
handoffs_raw=File.read(File.join(review,'contracts/handoffs.yaml'))
need.('handoffs pre-10.0 migration header',handoffs_raw.include?("\n# pre-10.0 migration: persisted 6.0 and incompatible 7.0/7.1/7.2/8.0 packets") && !handoffs_raw.include?('v9.0 migration'))
need.('retired plan-review label',[handoffs_raw,File.read(File.join(review,'contracts/input.yaml')),File.read(File.join(review,'references/review-batch.md')),File.read(File.join(review,'references/review-loop.md'))].none?{|t|t.downcase.include?('plan review remains acceptable')})
roles=%w[agents/claude/reviewer.md agents/claude/code-reviewer.md agents/codex/reviewer.toml agents/codex/code-reviewer.toml].map{|r|File.read(File.join(root,r))}
need.('role plan pass and closure',roles.all?{|t|t.include?('Plan review uses one newly created fresh `plan_coverage_and_feasibility` pass') && t.include?('Also include them for a `plan_coverage_and_feasibility` re-review with non-empty `previously_fixed`.') && t.include?('A `plan_coverage_and_feasibility` re-review with non-empty `previously_fixed` follows the same closure rule.')})
# M2: a compact light reviewer without a frozen batch skips worker_return_schema; the Review root loads the loop only for structured batches.
compact='When no frozen batch is supplied (compact light or plan review), return only `status`, PASS or findings each with a stable id (for example `light-1`) plus file/line and description, `reviewed_scope` and evidence refs; skip `worker_return_schema` resolution and do not invent batch identity. A compact re-review after a fix is a different newly created agent from the first reviewer; it receives the fixed findings as `{aggregate_finding_id, description}` rows and returns `closure_results` (`verified_closed`, `regressed` or `incomplete`) for each `aggregate_finding_id`. Plan review records the compact result unless the structured path is required: reviewer identity, PASS or findings rows `{aggregate_finding_id, file_line, description}`, `reviewed_scope`, request/plan coverage using the `request_plan_reconciliation` field names, and, after a material plan fix, `closure_results` from a different newly created re-reviewer. A structured frozen batch keeps the canonical return below.'
need.('role compact light return',roles.all?{|t|(i=t.index(compact)) && (j=t.index('Before first response, resolve `worker_return_schema`')) && i<j && !t.include?('fixed_finding_ids') && !t.include?('closure_status')})
need.('SKILL structured-only loop load',skill.include?('Structured batches load [review-loop.md](references/review-loop.md) before the first batch; v10 rules:') && !skill.include?('Load [review-loop.md](references/review-loop.md) before the first batch.'))
# L5: spec_review_pass_ref description matches its workflow-composed validation.
need.('spec_review_pass_ref description',context.fetch('spec_review_pass_ref')['description']=="Standalone: pointer to the current Spec Review result recorded against the user request/review scope before batch planning. Workflow-composed: pointer to the final acceptance batch's spec obligations (for a plan subject, the plan coverage obligations); it needs no separate Spec PASS.")
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
