if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

skill_eval_runner="$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh"
clarify_fixture="$FRAMEWORK_DIR/skills/assistant-clarify/evals/cases.json"
telos_fixture="$FRAMEWORK_DIR/skills/assistant-telos/evals/cases.json"

p0p4_skill_eval_default_fixtures() {
    find "$FRAMEWORK_DIR/skills" \
        -mindepth 3 \
        -maxdepth 3 \
        -type f \
        -path "$FRAMEWORK_DIR/skills/assistant-*/evals/cases.json" \
        -print | sort
}

p0p4_skill_eval_default_case_count() {
    local fixture_file
    local fixture_count
    local total=0

    while IFS= read -r fixture_file; do
        fixture_count="$(jq '.cases | length' "$fixture_file")"
        total=$((total + fixture_count))
    done < <(p0p4_skill_eval_default_fixtures)

    printf '%s\n' "$total"
}

p0p4_write_skill_eval_fixture() {
    local skill_dir="$1"
    local skill_name

    skill_name="$(basename "$skill_dir")"
    mkdir -p "$skill_dir/evals"
    cat >"$skill_dir/SKILL.md" <<EOF
---
name: $skill_name
description: "Fixture skill used by the per-skill eval contract tests."
effort: low
triggers:
  - pattern: "fixture skill eval"
    priority: 50
---

# Fixture Skill
EOF

    cat >"$skill_dir/evals/cases.json" <<EOF
{
  "schema_version": "1.0",
  "suite_id": "$skill_name-behavior",
  "skill": "$skill_name",
  "title": "$skill_name Behavior Eval Fixtures",
  "description": "Provider-neutral offline fixture for per-skill eval contract tests.",
  "eval_type": "skill_prompt_fixture",
  "provider_neutral": true,
  "model_specific_api_calls": false,
  "recommended_use": [
    "Run this case with the fixture skill instructions loaded."
  ],
  "cases": [
    {
      "id": "fixture-case",
      "title": "Fixture case",
      "category": "fixture",
      "purpose": "Checks generated fixture handling.",
      "prompt": "Use the fixture skill.",
      "setup_context": [
        "The fixture skill instructions are active."
      ],
      "expected_behavior": [
        "The response follows fixture expectations."
      ],
      "pass_criteria": [
        "The response includes the required fixture substring."
      ],
      "fail_signals": [
        "The response ignores fixture expectations."
      ],
      "machine_expectations": {
        "required_substrings": [
          "fixture required"
        ],
        "forbidden_substrings": [
          "fixture forbidden"
        ]
      }
    }
  ]
}
EOF
}

p0p4_write_skill_eval_responses() {
    local output_dir="$1"
    local omit_skill="${2:-}"
    local omit_case="${3:-}"
    local omit_required="${4:-}"
    local fixture_file
    local skill_name
    local id
    local response_path
    local required

    while IFS= read -r fixture_file; do
        skill_name="$(basename "$(dirname "$(dirname "$fixture_file")")")"
        mkdir -p "$output_dir/$skill_name"
        while IFS= read -r id; do
            response_path="$output_dir/$skill_name/$id.txt"
            {
                printf 'Local grading response for %s/%s.\n' "$skill_name" "$id"
                while IFS= read -r required; do
                    if [[ "$skill_name" == "$omit_skill" && "$id" == "$omit_case" && "$required" == "$omit_required" ]]; then
                        continue
                    fi
                    printf '%s\n' "$required"
                done < <(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .machine_expectations.required_substrings[]' "$fixture_file")
            } >"$response_path"
        done < <(jq -r '.cases[].id' "$fixture_file")
    done < <(p0p4_skill_eval_default_fixtures)
}

p0p4_write_skill_eval_flat_responses() {
    local output_dir="$1"
    local fixture_file="$2"
    local id
    local required

    while IFS= read -r id; do
        {
            printf 'Local flat grading response for %s.\n' "$id"
            while IFS= read -r required; do
                printf '%s\n' "$required"
            done < <(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .machine_expectations.required_substrings[]' "$fixture_file")
        } >"$output_dir/$id.txt"
    done < <(jq -r '.cases[].id' "$fixture_file")
}

test_start "skill eval runner exists and is executable"
if [[ -x "$skill_eval_runner" ]]; then
    pass
else
    fail "missing or non-executable runner: $skill_eval_runner"
fi

test_start "skill eval runner validates default fixture inventory"
if validation_output="$("$skill_eval_runner" --validate-fixture 2>&1)" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-clarify/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-diagrams/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-docs/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-ideate/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-memory/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-onboard/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-reflexion/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-research/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-review/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-security/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-skill-creator/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-tdd/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-telos/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-thinking/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-workflow/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "OK skill eval fixtures:"; then
    pass
else
    fail "skill eval runner --validate-fixture did not validate default assistant fixture inventory"
fi

test_start "skill eval runner validates targeted skill by name"
if targeted_name_output="$("$skill_eval_runner" --validate-fixture --skill assistant-clarify 2>&1)" \
    && printf '%s\n' "$targeted_name_output" | grep -Fq "skills/assistant-clarify/evals/cases.json" \
    && ! printf '%s\n' "$targeted_name_output" | grep -Fq "skills/assistant-thinking/evals/cases.json"; then
    pass
else
    fail "skill eval runner did not validate targeted assistant-clarify skill by name"
fi

test_start "skill eval runner validates targeted skill by directory"
if targeted_dir_output="$("$skill_eval_runner" --validate-fixture --skill skills/assistant-thinking 2>&1)" \
    && printf '%s\n' "$targeted_dir_output" | grep -Fq "skills/assistant-thinking/evals/cases.json" \
    && ! printf '%s\n' "$targeted_dir_output" | grep -Fq "skills/assistant-clarify/evals/cases.json"; then
    pass
else
    fail "skill eval runner did not validate targeted assistant-thinking skill by directory"
fi

test_start "skill eval runner validates targeted skill by SKILL.md path"
if targeted_path_output="$("$skill_eval_runner" --validate-fixture --skill skills/assistant-thinking/SKILL.md 2>&1)" \
    && printf '%s\n' "$targeted_path_output" | grep -Fq "skills/assistant-thinking/evals/cases.json" \
    && ! printf '%s\n' "$targeted_path_output" | grep -Fq "skills/assistant-clarify/evals/cases.json"; then
    pass
else
    fail "skill eval runner did not validate targeted assistant-thinking skill by SKILL.md path"
fi

test_start "skill eval runner list includes covered skill case rows"
default_case_count="$(p0p4_skill_eval_default_case_count)"
if list_output="$("$skill_eval_runner" --list)" \
    && [[ "$(printf '%s\n' "$list_output" | grep -c .)" -eq "$default_case_count" ]] \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-clarify\tmulti-intent-prompt-asks-bounded-clarification\tambiguous_multi_intent\tMulti-intent prompt asks bounded clarification' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-thinking\tarchitecture-decision-selects-perspectives\ttool_selection_methodology\tArchitecture decision selects perspectives' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-workflow\tmedium-task-plans-before-build\tphase_gate_approval\tMedium task plans before build' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-workflow\tworkflow-trigger-routes-dev-verbs-not-raw-code\ttrigger_routing\tWorkflow trigger routes dev verbs not raw code' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-workflow\tclarification-cap-is-not-question-quota\tclarification_admissibility\tClarification cap is not question quota' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-review\treview-fix-loop-handles-findings\tautonomous_review_loop\tReview-fix loop handles findings' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-tdd\tbugfix-starts-with-red-evidence\tred_gate_enforcement\tBugfix starts with RED evidence' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-security\tfindings-include-severity-impact-remediation\tsecurity_report_contract\tFindings include severity impact remediation' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-diagrams\tarchitecture-diagram-derived-from-code\tcode_derived_architecture\tArchitecture diagram derived from code' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-docs\tarchitecture-doc-uses-code-evidence\tcode_derived_architecture_docs\tArchitecture doc uses code evidence' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-ideate\tbrainstorm-diverges-before-ranking\tdiverge_converge_gate\tBrainstorm diverges before ranking' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-reflexion\tpost-task-reflection-records-lessons\treflection_storage_contract\tPost-task reflection records lessons' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-telos\tcreate-personal-tcf-core-sections\ttcf_creation_contract\tCreate personal TCF core sections' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-skill-creator\tnew-process-skill-designs-contracts-before-build\tcontract_design_gate\tNew process skill designs contracts before build' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-memory\tsave-preference-uses-memory-graph\tmemory_save_contract\tSave preference uses memory graph' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-research\ttechnology-comparison-uses-standard-tier\ttier_and_synthesis\tTechnology comparison uses standard tier' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-onboard\tnew-repo-onboarding-produces-orientation\tsystematic_onboarding\tNew repo onboarding produces orientation'; then
    pass
else
    fail "skill eval runner --list did not include expected covered assistant case rows"
fi

test_start "skill eval runner list honors targeted skill selection"
clarify_case_count="$(jq '.cases | length' "$clarify_fixture")"
if targeted_list_output="$("$skill_eval_runner" --list --skill assistant-clarify)" \
    && [[ "$(printf '%s\n' "$targeted_list_output" | grep -c .)" -eq "$clarify_case_count" ]] \
    && printf '%s\n' "$targeted_list_output" | grep -Fq $'assistant-clarify\tmulti-intent-prompt-asks-bounded-clarification\tambiguous_multi_intent\tMulti-intent prompt asks bounded clarification' \
    && printf '%s\n' "$targeted_list_output" | grep -Fq $'assistant-clarify\tcompressed-request-produces-structured-brief\tstructured_brief\tCompressed request produces structured brief' \
    && ! printf '%s\n' "$targeted_list_output" | grep -Fq "assistant-thinking" \
    && ! printf '%s\n' "$targeted_list_output" | grep -Fq "architecture-decision-selects-perspectives"; then
    pass
else
    fail "skill eval runner --list --skill assistant-clarify did not list only assistant-clarify cases"
fi

test_start "skill eval runner list honors targeted expanded skill selection"
telos_case_count="$(jq '.cases | length' "$telos_fixture")"
if targeted_telos_list_output="$("$skill_eval_runner" --list --skill assistant-telos)" \
    && [[ "$(printf '%s\n' "$targeted_telos_list_output" | grep -c .)" -eq "$telos_case_count" ]] \
    && printf '%s\n' "$targeted_telos_list_output" | grep -Fq $'assistant-telos\tcreate-personal-tcf-core-sections\ttcf_creation_contract\tCreate personal TCF core sections' \
    && printf '%s\n' "$targeted_telos_list_output" | grep -Fq $'assistant-telos\treview-existing-tcf-finds-chain-gaps\ttcf_review_contract\tReview existing TCF finds chain gaps' \
    && ! printf '%s\n' "$targeted_telos_list_output" | grep -Fq "assistant-clarify" \
    && ! printf '%s\n' "$targeted_telos_list_output" | grep -Fq "assistant-security"; then
    pass
else
    fail "skill eval runner --list --skill assistant-telos did not list only assistant-telos cases"
fi

test_start "skill eval runner emits skill-specific prompt packets with machine expectations"
prompt_dir="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-prompts.XXXXXX")"
p0p4_register_cleanup "$prompt_dir"
if "$skill_eval_runner" --emit-prompts "$prompt_dir" >/dev/null \
    && [[ "$(find "$prompt_dir" -type f -name '*.md' | wc -l | tr -d ' ')" -eq "$default_case_count" ]] \
    && grep -Fq "Skill: assistant-clarify" "$prompt_dir/assistant-clarify/multi-intent-prompt-asks-bounded-clarification.md" \
    && grep -Fq "Case ID: multi-intent-prompt-asks-bounded-clarification" "$prompt_dir/assistant-clarify/multi-intent-prompt-asks-bounded-clarification.md" \
    && grep -Fq "## Machine Expectations" "$prompt_dir/assistant-clarify/multi-intent-prompt-asks-bounded-clarification.md" \
    && grep -Fq "### Required Substrings" "$prompt_dir/assistant-clarify/multi-intent-prompt-asks-bounded-clarification.md" \
    && grep -Fq "### Forbidden Substrings" "$prompt_dir/assistant-clarify/multi-intent-prompt-asks-bounded-clarification.md" \
    && grep -Fq "Skill: assistant-diagrams" "$prompt_dir/assistant-diagrams/architecture-diagram-derived-from-code.md" \
    && grep -Fq "Skill: assistant-docs" "$prompt_dir/assistant-docs/architecture-doc-uses-code-evidence.md" \
    && grep -Fq "Skill: assistant-ideate" "$prompt_dir/assistant-ideate/brainstorm-diverges-before-ranking.md" \
    && grep -Fq "Skill: assistant-thinking" "$prompt_dir/assistant-thinking/architecture-decision-selects-perspectives.md" \
    && grep -Fq "Skill: assistant-skill-creator" "$prompt_dir/assistant-skill-creator/new-process-skill-designs-contracts-before-build.md" \
    && grep -Fq "Skill: assistant-memory" "$prompt_dir/assistant-memory/save-preference-uses-memory-graph.md" \
    && grep -Fq "Skill: assistant-reflexion" "$prompt_dir/assistant-reflexion/post-task-reflection-records-lessons.md" \
    && grep -Fq "Skill: assistant-research" "$prompt_dir/assistant-research/technology-comparison-uses-standard-tier.md" \
    && grep -Fq "Skill: assistant-onboard" "$prompt_dir/assistant-onboard/new-repo-onboarding-produces-orientation.md" \
    && grep -Fq "Skill: assistant-telos" "$prompt_dir/assistant-telos/create-personal-tcf-core-sections.md" \
    && grep -Fq "Skill: assistant-workflow" "$prompt_dir/assistant-workflow/medium-task-plans-before-build.md" \
    && grep -Fq "Skill: assistant-review" "$prompt_dir/assistant-review/review-fix-loop-handles-findings.md" \
    && grep -Fq "Skill: assistant-tdd" "$prompt_dir/assistant-tdd/bugfix-starts-with-red-evidence.md" \
    && grep -Fq "Skill: assistant-security" "$prompt_dir/assistant-security/findings-include-severity-impact-remediation.md" \
    && grep -Fq "## Machine Expectations" "$prompt_dir/assistant-thinking/architecture-decision-selects-perspectives.md"; then
    pass
else
    fail "skill eval runner --emit-prompts did not create recognizable skill/case prompt packets"
fi

test_start "skill eval runner emits prompts only for targeted skill selection"
targeted_prompt_dir="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-targeted-prompts.XXXXXX")"
p0p4_register_cleanup "$targeted_prompt_dir"
if "$skill_eval_runner" --emit-prompts "$targeted_prompt_dir" --skill assistant-clarify >/dev/null \
    && [[ "$(find "$targeted_prompt_dir" -type f -name '*.md' | wc -l | tr -d ' ')" -eq "$clarify_case_count" ]] \
    && [[ -f "$targeted_prompt_dir/assistant-clarify/multi-intent-prompt-asks-bounded-clarification.md" ]] \
    && [[ -f "$targeted_prompt_dir/assistant-clarify/compressed-request-produces-structured-brief.md" ]] \
    && [[ ! -d "$targeted_prompt_dir/assistant-thinking" ]] \
    && grep -Fq "Skill: assistant-clarify" "$targeted_prompt_dir/assistant-clarify/multi-intent-prompt-asks-bounded-clarification.md"; then
    pass
else
    fail "skill eval runner --emit-prompts --skill assistant-clarify did not emit only assistant-clarify prompt packets"
fi

test_start "skill eval runner fails for empty and missing response files"
response_dir="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-responses.XXXXXX")"
response_output="$(mktemp "${TMPDIR:-/tmp}/skill-eval-response-output.XXXXXX")"
p0p4_register_cleanup "$response_dir" "$response_output"
mkdir -p "$response_dir/assistant-clarify"
: >"$response_dir/assistant-clarify/multi-intent-prompt-asks-bounded-clarification.txt"
if "$skill_eval_runner" --responses "$response_dir" >"$response_output" 2>&1; then
    fail "skill eval runner --responses unexpectedly passed with empty or missing responses"
elif grep -Fq "Heuristic/local grading only" "$response_output" \
    && grep -Fq $'FAIL\tassistant-clarify\tmulti-intent-prompt-asks-bounded-clarification' "$response_output" \
    && grep -Fq "empty response file" "$response_output" \
    && grep -Fq "missing response file" "$response_output"; then
    pass
else
    fail "skill eval runner --responses did not report empty and missing responses clearly"
fi

test_start "skill eval runner fails for missing required substrings"
missing_required_dir="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-missing-required.XXXXXX")"
missing_required_output="$(mktemp "${TMPDIR:-/tmp}/skill-eval-missing-required-output.XXXXXX")"
p0p4_register_cleanup "$missing_required_dir" "$missing_required_output"
omitted_required="$(jq -r '.cases[] | select(.id == "multi-intent-prompt-asks-bounded-clarification") | .machine_expectations.required_substrings[0]' "$clarify_fixture")"
p0p4_write_skill_eval_responses "$missing_required_dir" "assistant-clarify" "multi-intent-prompt-asks-bounded-clarification" "$omitted_required"
if "$skill_eval_runner" --responses "$missing_required_dir" >"$missing_required_output" 2>&1; then
    fail "skill eval runner --responses unexpectedly passed with a missing required substring"
elif grep -Fq $'FAIL\tassistant-clarify\tmulti-intent-prompt-asks-bounded-clarification' "$missing_required_output" \
    && grep -Fq "missing required substring" "$missing_required_output" \
    && grep -Fq "missing_required_substrings=" "$missing_required_output"; then
    pass
else
    fail "skill eval runner --responses did not report missing required substrings clearly"
fi

test_start "skill eval runner fails for forbidden substrings"
forbidden_dir="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-forbidden.XXXXXX")"
forbidden_output="$(mktemp "${TMPDIR:-/tmp}/skill-eval-forbidden-output.XXXXXX")"
p0p4_register_cleanup "$forbidden_dir" "$forbidden_output"
forbidden_substring="$(jq -r '.cases[] | select(.id == "multi-intent-prompt-asks-bounded-clarification") | .machine_expectations.forbidden_substrings[0]' "$clarify_fixture")"
p0p4_write_skill_eval_responses "$forbidden_dir"
printf '%s\n' "$forbidden_substring" >>"$forbidden_dir/assistant-clarify/multi-intent-prompt-asks-bounded-clarification.txt"
if "$skill_eval_runner" --responses "$forbidden_dir" >"$forbidden_output" 2>&1; then
    fail "skill eval runner --responses unexpectedly passed with a forbidden substring"
elif grep -Fq $'FAIL\tassistant-clarify\tmulti-intent-prompt-asks-bounded-clarification' "$forbidden_output" \
    && grep -Fq "forbidden substring hit" "$forbidden_output" \
    && grep -Fq "forbidden_substring_hits=" "$forbidden_output"; then
    pass
else
    fail "skill eval runner --responses did not report forbidden substrings clearly"
fi

test_start "skill eval runner passes generated responses with all required substrings"
passing_response_dir="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-passing.XXXXXX")"
passing_response_output="$(mktemp "${TMPDIR:-/tmp}/skill-eval-passing-output.XXXXXX")"
p0p4_register_cleanup "$passing_response_dir" "$passing_response_output"
p0p4_write_skill_eval_responses "$passing_response_dir"
if "$skill_eval_runner" --responses "$passing_response_dir" >"$passing_response_output" 2>&1 \
    && grep -Fq "Summary: total=$default_case_count passed=$default_case_count failed=0" "$passing_response_output" \
    && grep -Fq "missing_required_substrings=0" "$passing_response_output" \
    && grep -Fq "forbidden_substring_hits=0" "$passing_response_output"; then
    pass
else
    fail "skill eval runner --responses did not pass generated all-required response set"
fi

test_start "skill eval runner grades flat targeted single-skill responses"
flat_response_dir="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-flat-targeted.XXXXXX")"
flat_response_output="$(mktemp "${TMPDIR:-/tmp}/skill-eval-flat-targeted-output.XXXXXX")"
p0p4_register_cleanup "$flat_response_dir" "$flat_response_output"
p0p4_write_skill_eval_flat_responses "$flat_response_dir" "$clarify_fixture"
if "$skill_eval_runner" --responses "$flat_response_dir" --skill assistant-clarify >"$flat_response_output" 2>&1 \
    && grep -Fq "Summary: total=$clarify_case_count passed=$clarify_case_count failed=0" "$flat_response_output" \
    && grep -Fq "skills=1" "$flat_response_output" \
    && grep -Fq $'PASS\tassistant-clarify\tmulti-intent-prompt-asks-bounded-clarification' "$flat_response_output" \
    && grep -Fq $'PASS\tassistant-clarify\tcompressed-request-produces-structured-brief' "$flat_response_output" \
    && ! grep -Fq "assistant-thinking" "$flat_response_output" \
    && [[ ! -d "$flat_response_dir/assistant-clarify" ]]; then
    pass
else
    fail "skill eval runner --responses --skill assistant-clarify did not pass flat single-skill response files"
fi

test_start "skill eval runner rejects empty machine expectation arrays"
malformed_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-empty-array.XXXXXX")"
malformed_skill_dir="$malformed_root/assistant-eval-empty-array"
malformed_err="$(mktemp "${TMPDIR:-/tmp}/skill-eval-empty-array-err.XXXXXX")"
p0p4_register_cleanup "$malformed_root" "$malformed_err"
p0p4_write_skill_eval_fixture "$malformed_skill_dir"
jq '(.cases[0].machine_expectations.required_substrings) = []' "$malformed_skill_dir/evals/cases.json" >"$malformed_root/cases.tmp"
mv "$malformed_root/cases.tmp" "$malformed_skill_dir/evals/cases.json"
if "$skill_eval_runner" --validate-fixture --skill "$malformed_skill_dir" >/dev/null 2>"$malformed_err"; then
    fail "skill eval runner accepted an empty machine expectation array"
elif grep -Fq "machine_expectations.required_substrings non-empty string array" "$malformed_err"; then
    pass
else
    fail "empty machine expectation failure was not clear, stderr=$(cat "$malformed_err")"
fi

test_start "skill eval runner rejects case ids with path separators"
slash_id_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-slash-id.XXXXXX")"
slash_id_skill_dir="$slash_id_root/assistant-eval-slash-id"
slash_id_err="$(mktemp "${TMPDIR:-/tmp}/skill-eval-slash-id-err.XXXXXX")"
p0p4_register_cleanup "$slash_id_root" "$slash_id_err"
p0p4_write_skill_eval_fixture "$slash_id_skill_dir"
jq '(.cases[0].id) = "fixture/case"' "$slash_id_skill_dir/evals/cases.json" >"$slash_id_root/cases.tmp"
mv "$slash_id_root/cases.tmp" "$slash_id_skill_dir/evals/cases.json"
if "$skill_eval_runner" --validate-fixture --skill "$slash_id_skill_dir" >/dev/null 2>"$slash_id_err"; then
    fail "skill eval runner accepted a slash-containing case id"
elif grep -Fq "safe filename component" "$slash_id_err" \
    && grep -Fq "fixture/case" "$slash_id_err"; then
    pass
else
    fail "slash case id failure was not clear, stderr=$(cat "$slash_id_err")"
fi

test_start "skill eval runner rejects traversal case ids"
traversal_id_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-traversal-id.XXXXXX")"
traversal_id_skill_dir="$traversal_id_root/assistant-eval-traversal-id"
traversal_id_err="$(mktemp "${TMPDIR:-/tmp}/skill-eval-traversal-id-err.XXXXXX")"
p0p4_register_cleanup "$traversal_id_root" "$traversal_id_err"
p0p4_write_skill_eval_fixture "$traversal_id_skill_dir"
jq '(.cases[0].id) = ".."' "$traversal_id_skill_dir/evals/cases.json" >"$traversal_id_root/cases.tmp"
mv "$traversal_id_root/cases.tmp" "$traversal_id_skill_dir/evals/cases.json"
if "$skill_eval_runner" --validate-fixture --skill "$traversal_id_skill_dir" >/dev/null 2>"$traversal_id_err"; then
    fail "skill eval runner accepted a traversal case id"
elif grep -Fq "safe filename component" "$traversal_id_err" \
    && grep -Fq "not . or .." "$traversal_id_err"; then
    pass
else
    fail "traversal case id failure was not clear, stderr=$(cat "$traversal_id_err")"
fi

test_start "skill eval runner rejects case ids with newline control characters"
newline_id_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-newline-id.XXXXXX")"
newline_id_skill_dir="$newline_id_root/assistant-eval-newline-id"
newline_id_err="$(mktemp "${TMPDIR:-/tmp}/skill-eval-newline-id-err.XXXXXX")"
p0p4_register_cleanup "$newline_id_root" "$newline_id_err"
p0p4_write_skill_eval_fixture "$newline_id_skill_dir"
jq '(.cases[0].id) = "fixture\ncase"' "$newline_id_skill_dir/evals/cases.json" >"$newline_id_root/cases.tmp"
mv "$newline_id_root/cases.tmp" "$newline_id_skill_dir/evals/cases.json"
if "$skill_eval_runner" --validate-fixture --skill "$newline_id_skill_dir" >/dev/null 2>"$newline_id_err"; then
    fail "skill eval runner accepted a newline-containing case id"
elif grep -Fq "safe filename component" "$newline_id_err" \
    && grep -Fq "letters, digits, dot, underscore, and hyphen" "$newline_id_err"; then
    pass
else
    fail "newline case id failure was not clear, stderr=$(cat "$newline_id_err")"
fi

test_start "skill eval runner rejects case ids with tab control characters"
tab_id_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-tab-id.XXXXXX")"
tab_id_skill_dir="$tab_id_root/assistant-eval-tab-id"
tab_id_err="$(mktemp "${TMPDIR:-/tmp}/skill-eval-tab-id-err.XXXXXX")"
p0p4_register_cleanup "$tab_id_root" "$tab_id_err"
p0p4_write_skill_eval_fixture "$tab_id_skill_dir"
jq '(.cases[0].id) = "fixture\tcase"' "$tab_id_skill_dir/evals/cases.json" >"$tab_id_root/cases.tmp"
mv "$tab_id_root/cases.tmp" "$tab_id_skill_dir/evals/cases.json"
if "$skill_eval_runner" --validate-fixture --skill "$tab_id_skill_dir" >/dev/null 2>"$tab_id_err"; then
    fail "skill eval runner accepted a tab-containing case id"
elif grep -Fq "safe filename component" "$tab_id_err" \
    && grep -Fq "letters, digits, dot, underscore, and hyphen" "$tab_id_err"; then
    pass
else
    fail "tab case id failure was not clear, stderr=$(cat "$tab_id_err")"
fi

test_start "skill eval runner rejects duplicate case ids"
duplicate_id_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-duplicate-id.XXXXXX")"
duplicate_id_skill_dir="$duplicate_id_root/assistant-eval-duplicate-id"
duplicate_id_err="$(mktemp "${TMPDIR:-/tmp}/skill-eval-duplicate-id-err.XXXXXX")"
p0p4_register_cleanup "$duplicate_id_root" "$duplicate_id_err"
p0p4_write_skill_eval_fixture "$duplicate_id_skill_dir"
jq '.cases += [(.cases[0] | .title = "Duplicate fixture case")]' "$duplicate_id_skill_dir/evals/cases.json" >"$duplicate_id_root/cases.tmp"
mv "$duplicate_id_root/cases.tmp" "$duplicate_id_skill_dir/evals/cases.json"
if "$skill_eval_runner" --validate-fixture --skill "$duplicate_id_skill_dir" >/dev/null 2>"$duplicate_id_err"; then
    fail "skill eval runner accepted duplicate case ids"
elif grep -Fq "duplicate case id: fixture-case" "$duplicate_id_err"; then
    pass
else
    fail "duplicate case id failure was not clear, stderr=$(cat "$duplicate_id_err")"
fi

test_start "skill eval runner default inventory excludes generated local-only unity fixtures"
unity_fixture_dir="$(mktemp -d "$FRAMEWORK_DIR/skills/unity-skill-eval-local.XXXXXX")"
unity_fixture_name="$(basename "$unity_fixture_dir")"
p0p4_register_cleanup "$unity_fixture_dir"
p0p4_write_skill_eval_fixture "$unity_fixture_dir"
if local_only_list_output="$("$skill_eval_runner" --list)" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-clarify" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-diagrams" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-docs" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-ideate" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-memory" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-reflexion" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-research" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-security" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-skill-creator" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-telos" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-thinking" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-workflow" \
    && ! printf '%s\n' "$local_only_list_output" | grep -Fq "$unity_fixture_name"; then
    pass
else
    fail "default skill eval inventory should include assistant fixtures and exclude local-only unity fixtures"
fi

test_start "skill eval runner include-local lists generated local-only unity fixtures"
include_local_fixture_dir="$(mktemp -d "$FRAMEWORK_DIR/skills/unity-skill-eval-include-local.XXXXXX")"
include_local_fixture_name="$(basename "$include_local_fixture_dir")"
p0p4_register_cleanup "$include_local_fixture_dir"
p0p4_write_skill_eval_fixture "$include_local_fixture_dir"
if include_local_default_output="$("$skill_eval_runner" --list)" \
    && include_local_output="$("$skill_eval_runner" --list --include-local)" \
    && ! printf '%s\n' "$include_local_default_output" | grep -Fq "$include_local_fixture_name" \
    && printf '%s\n' "$include_local_output" | grep -Fq $''"$include_local_fixture_name"$'\tfixture-case\tfixture\tFixture case'; then
    pass
else
    fail "skill eval runner --list --include-local should include generated local-only unity fixtures while default list excludes them"
fi

test_start "skill eval docs describe complete first-class coverage"
if grep -Fq "complete first-class skill coverage" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-diagrams" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-docs" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-ideate" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-reflexion" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-telos" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-skill-creator" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-memory" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-research" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-onboard" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-workflow" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-review" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-tdd" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-security" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "Local-only" "$FRAMEWORK_DIR/README.md" \
    && ! grep -Fq "5 of 15 first-class skills remain" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "all 15 first-class skills" "$FRAMEWORK_DIR/docs/skill-contract-design-guide.md" \
    && grep -Fq "complete first-class per-skill eval fixtures" "$FRAMEWORK_DIR/docs/skill-contract-design-guide.md" \
    && grep -Fq "all 15 first-class skills" "$FRAMEWORK_DIR/skills/assistant-skill-creator/references/skill-contract-design-guide.md" \
    && grep -Fq "complete first-class per-skill eval fixtures" "$FRAMEWORK_DIR/skills/assistant-skill-creator/references/skill-contract-design-guide.md" \
    && ! grep -Fq "Level 4 is future work" "$FRAMEWORK_DIR/skills/assistant-skill-creator/references/skill-contract-design-guide.md" \
    && grep -Fq "skills/assistant-diagrams/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-docs/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-ideate/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-reflexion/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-telos/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-skill-creator/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-memory/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-research/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-onboard/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-workflow/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-review/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-tdd/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-security/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md"; then
    pass
else
    fail "skill eval docs do not describe complete first-class coverage"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
