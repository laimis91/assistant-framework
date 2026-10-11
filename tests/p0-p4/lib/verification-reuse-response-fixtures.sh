#!/usr/bin/env bash

write_verification_reuse_response() {
    local case_id="$1" response_path="$2" summary="$3" ids
    case "$case_id" in
        verification-reuse-current-scenario-matrix)
            ids='["unchanged-complete","unrelated-doc-input-boundary","changed-production","changed-tests","changed-config","changed-dependency","changed-argv","changed-cwd","changed-toolchain","changed-environment","prior-failed","prior-partial","prior-skipped","unknown-basis","explicit-fresh-run","mutable-external-state","new-integration-coverage","post-fix-source"]'
            ;;
        verification-reuse-preserves-independent-review)
            ids='["spec-review-required","independent-code-review-required","final-review-snapshot-current"]'
            ;;
        *) return 1 ;;
    esac
    jq -n --arg summary "$summary" --arg case_id "$case_id" --argjson ids "$ids" '
      {summary:$summary,decisions:[$ids[] | {
        id:.,
        action:(if $case_id == "verification-reuse-preserves-independent-review"
                   or . == "unchanged-complete" or . == "unrelated-doc-input-boundary"
                then "reuse" else "rerun" end),
        original_run_ref:("run/" + .),
        current_comparison_ref:("comparison/" + .),
        independent_review_status:"required"
      }]}
    ' >"$response_path"
}

write_tdd_slice_projection_response() {
    local response_path="$1" summary="$2"
    jq -n --arg summary "$summary" '
      def decision: {
        scope:"Fix the integer-cent calculation and document the resulting behavior.",
        policy_basis:{binding_constraints:[{kind:"required_tdd",value:"true",source_ref:"testing-policy.md#required-tdd"}],preferences_applied:[],capability_limits:[]},
        test_change:"add_new",
        checks:[
          {check_id:"calculation-boundary",claim_or_risk:"The percentage calculation truncates 10 percent of 199 cents to 19 cents.",action:"add",method:"automated_test",test_scope:"unit",technique:"example",check_ref_or_method:{reference_or_procedure:"Write and run the 199-cent calculation boundary test before the production fix.",prerequisites:["The calculation can be called with integer-cent inputs."],exclusions:["Does not require unrelated full-suite execution."],expected_success:"The calculation returns 19 cents for 10 percent of 199 cents.",meaningful_failure:"Before the fix, the 199-cent case returns a value other than 19 cents."},rationale:"The 199-cent case is the selected meaningful RED oracle.",method_refs:["skills/assistant-verification/references/methods/unit.md"]},
          {check_id:"docs-content-inspection",claim_or_risk:"The documentation describes the integer-cent truncation behavior accurately.",action:"inspect",method:"artifact_inspection",technique:"exploratory",check_ref_or_method:{reference_or_procedure:"Inspect the updated documentation against the accepted calculation behavior.",prerequisites:["The documentation change is available."],exclusions:["Does not replace the calculation boundary test."],expected_success:"The documented example matches the accepted calculation behavior.",meaningful_failure:"The documentation example or explanation contradicts the calculation behavior."},rationale:"Directly checks the docs deliverable without applying TDD to an unrelated inspection.",method_refs:["skills/assistant-verification/references/methods/artifact-validation.md"]}
        ],
        tdd_choice:{mode:true,applicable_check_ids:["calculation-boundary"],basis:"user_requirement",rationale:"The required TDD choice applies to the selected calculation boundary check."},
        omitted_checks_and_rationale:[],
        stop_rule:"Run the calculation RED before its fix, inspect the updated documentation, then reassess both selected checks."
      };
      decision as $decision |
      {
        summary:$summary,
        verification_decision:$decision,
        evidence_assessment:{status:"planned",scope_and_evidence_refs:[],gaps_and_limitations:["The calculation RED and documentation inspection have not yet run."],next_action:"Run the selected calculation RED before repair and inspect the documentation deliverable."},
        slice_manifest:[
          {slice_id:"calculation-fix",name:"Repair calculation boundary",observable_increment:"The 199-cent calculation boundary is fixed",deliverable_type:"behavior",acceptance_criteria:["10 percent of 199 cents returns 19 cents."],verification_decision:$decision,selected_check_ids:["calculation-boundary"],binding_obligation_refs:[],tdd_applies:true,files_to_create:[],files_to_modify:["src/calculation"],files_to_test:["tests/calculation"],enabling_changes_included:[],depends_on:[],expected_success_signal:"The focused boundary test passes after meaningful RED",evidence_to_record:["Pre-fix RED and post-fix GREEN result refs"],deviation_rollback_rule:"Stop and refresh the plan if the selected boundary or oracle changes."},
          {slice_id:"documentation-update",name:"Document calculation behavior",observable_increment:"The docs describe integer-cent truncation",deliverable_type:"docs",acceptance_criteria:["The documented example matches the accepted calculation behavior."],verification_decision:$decision,selected_check_ids:["docs-content-inspection"],binding_obligation_refs:[],tdd_applies:false,files_to_create:[],files_to_modify:["docs/calculation.md"],files_to_test:[],enabling_changes_included:[],depends_on:["calculation-fix"],expected_success_signal:"The doc inspection matches the accepted calculation behavior",evidence_to_record:["Documentation inspection result"],deviation_rollback_rule:"Stop and refresh the plan if the documented behavior changes."}
        ]
      }
    ' >"$response_path"
}
