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
    p0p4_normalize_packet_projection "$response_path"
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
        implementation_steps:[
          {packet_id:"calculation-fix",name:"Repair calculation boundary",observable_increment:"The 199-cent calculation boundary is fixed",deliverable_type:"behavior",acceptance_criteria:["10 percent of 199 cents returns 19 cents."],verification_decision:$decision,selected_check_ids:["calculation-boundary"],binding_obligation_refs:[],tdd_applies:true,files_to_create:[],files_to_modify:["src/calculation"],files_to_test:["tests/calculation"],enabling_changes_included:[],depends_on:[],expected_success_signal:"The focused boundary test passes after meaningful RED",evidence_to_record:["Pre-fix RED and post-fix GREEN result refs"],deviation_rollback_rule:"Stop and refresh the plan if the selected boundary or oracle changes."},
          {packet_id:"documentation-update",name:"Document calculation behavior",observable_increment:"The docs describe integer-cent truncation",deliverable_type:"docs",acceptance_criteria:["The documented example matches the accepted calculation behavior."],verification_decision:$decision,selected_check_ids:["docs-content-inspection"],binding_obligation_refs:[],tdd_applies:false,files_to_create:[],files_to_modify:["docs/calculation.md"],files_to_test:[],enabling_changes_included:[],depends_on:["calculation-fix"],expected_success_signal:"The doc inspection matches the accepted calculation behavior",evidence_to_record:["Documentation inspection result"],deviation_rollback_rule:"Stop and refresh the plan if the documented behavior changes."}
        ]
      }
    ' >"$response_path"
    p0p4_normalize_packet_projection "$response_path"
}

# Independent fixed captures for lifecycle/MCP fixture facts. These are grading
# controls, not model/native/client/provider observations. Never infer them from
# machine_expectations or the grader oracle.
write_lifecycle_mcp_response() {
    local case_id="$1" response_path="$2"
    case "$case_id" in
        lifecycle-finalization-and-owned-recovery)
            cat >"$response_path" <<'LIFECYCLE_MCP_CAPTURE'
{
  "evidence_assessment": {
    "status": "insufficient",
    "scope_and_evidence_refs": [
      {
        "evidence_ref": "trace:finalize",
        "claim_kind": "task_behavior",
        "claim_scope": [
          "Finalization marker reached before cancel; result R and primary A failure retained, abort reason recorded, operation settled."
        ],
        "selected_check_ids": [
          "boundary"
        ],
        "binding_obligation_refs": [],
        "result_state": "passed",
        "freshness": "current",
        "exclusions": []
      },
      {
        "evidence_ref": "trace:recovery",
        "claim_kind": "task_behavior",
        "claim_scope": [
          "A owned handle unresolved; B cleanup retained; attached C untouched; retry only A; disconnect and leader exit do not prove descendant release."
        ],
        "selected_check_ids": [
          "release"
        ],
        "binding_obligation_refs": [],
        "result_state": "partial",
        "freshness": "current",
        "exclusions": []
      },
      {
        "evidence_ref": "trace:success",
        "claim_kind": "task_behavior",
        "claim_scope": [
          "Matched successful control retains R and releases its owned resources."
        ],
        "selected_check_ids": [
          "boundary"
        ],
        "binding_obligation_refs": [],
        "result_state": "passed",
        "freshness": "current",
        "exclusions": []
      },
      {
        "evidence_ref": "scope:label",
        "claim_kind": "task_behavior",
        "claim_scope": [
          "Synchronous calculation and cosmetic label change require no lifecycle guide or new gate; shared-work/publication cases apply only when present."
        ],
        "selected_check_ids": [],
        "binding_obligation_refs": [],
        "result_state": "not_applicable",
        "freshness": "current",
        "exclusions": []
      }
    ],
    "gaps_and_limitations": [
      "A release remains unresolved; no provider/native or efficiency observation."
    ],
    "next_action": "Reuse boundary evidence; select an owned-handle release observation, without rerunning successful B cleanup or terminating attached C."
  }
}
LIFECYCLE_MCP_CAPTURE
            ;;
        mcp-stateless-manifest-contract)
            cat >"$response_path" <<'LIFECYCLE_MCP_CAPTURE'
{
  "verification_decision": {
    "scope": "Reuse inspect_manifest for declared operations in this manifest version. operation_names absent=all; []=none; null=invalid. One authorized filesystem read; no process/network/UI effects; no retention store. Return manifest identity/digest and declared-only coverage; runtime health unknown. Malformed/unreadable is failure, not empty success. Inspect installed SDK/client transports without migration. SDK-converted advertised schema and intended-client calls are required for corresponding claims; source types are insufficient. Keyword match is a discovery proxy; native selection needs actual selected tools/arguments and host/source identity. No native/provider/efficiency result claimed.",
    "policy_basis": {
      "binding_constraints": [],
      "preferences_applied": [
        "Reuse adequate checks; select only important uncovered boundaries."
      ],
      "capability_limits": [
        "No real provider/client/native execution is supplied."
      ]
    },
    "test_change": "none",
    "checks": [
      {
        "check_id": "manifest-inputs",
        "claim_or_risk": "Optional inputs and malformed reads retain truthful semantics.",
        "action": "inspect",
        "method": "artifact_inspection",
        "technique": "exploratory",
        "check_ref_or_method": {
          "reference_or_procedure": "Compare absent, [], null and unreadable manifest calls at the designed public boundary.",
          "prerequisites": [
            "The designed tool boundary is available for inspection."
          ],
          "exclusions": [
            "No real provider/native observation is supplied."
          ],
          "expected_success": "Absent selects all, [] none, null rejects; unreadable reports a diagnostic.",
          "meaningful_failure": "Null is ignored or unreadable input returns an empty success list."
        },
        "rationale": "Distinct important truthful tool-contract boundary; reuse adequate existing evidence.",
        "method_refs": ["assistant-verification/references/methods/artifact-validation.md"]
      },
      {
        "check_id": "manifest-consumer",
        "claim_or_risk": "Advertised schema and intended-client behavior match the source contract.",
        "action": "inspect",
        "method": "artifact_inspection",
        "technique": "exploratory",
        "check_ref_or_method": {
          "reference_or_procedure": "Inspect SDK-converted schema and intended-client calls; qualify provider and native-selection gaps.",
          "prerequisites": [
            "The designed tool boundary is available for inspection."
          ],
          "exclusions": [
            "No real provider/native observation is supplied."
          ],
          "expected_success": "Converted optionality and client calls preserve semantics; native selection remains unverified.",
          "meaningful_failure": "Source types or keyword matches alone are used to claim client usability or native selection."
        },
        "rationale": "Distinct important truthful tool-contract boundary; reuse adequate existing evidence.",
        "method_refs": ["assistant-verification/references/methods/artifact-validation.md"]
      }
    ],
    "tdd_choice": {
      "mode": false,
      "applicable_check_ids": [],
      "basis": "not_selected",
      "rationale": "Design/evidence selection only; no meaningful executable RED selected."
    },
    "omitted_checks_and_rationale": [
      "No universal matrix, required taxonomy or mandatory small-tool retention."
    ],
    "stop_rule": "Stop once the named claims have credible current evidence; preserve the shared source-bound three-consecutive-unproductive-cycle guard."
  },
  "evidence_assessment": {
    "status": "planned",
    "scope_and_evidence_refs": [],
    "gaps_and_limitations": [
      "Actual SDK-converted schema, intended-client and real-provider/native observations remain unverified."
    ],
    "next_action": "Inspect the selected actual boundaries before claiming their behavior."
  }
}
LIFECYCLE_MCP_CAPTURE
            ;;
        mcp-capture-partial-complete-source)
            cat >"$response_path" <<'LIFECYCLE_MCP_CAPTURE'
{
  "verification_decision": {
    "scope": "Reuse inspect_capture for stored inspection; add capture_workers only for acquisition, not a mega-tool. Facets absent=default; []=none; null=invalid; unsupported facets are unavailable. Declare launch process/connections/temporary files and retention expiry; attach owns connection only, attached target remains running. Cap expanded bytes/concurrency/retention from measured or protocol constraints before allocation. Return capture ID and source version/digest, stable paging to complete source without capture rerun; page exhaustion is not completeness. Preserve primary diagnostic and partial per-target events; missing health remains unknown, no source-wide absence claim. A finalization marker plus successful control observes retained results/settlement; disconnect/leader exit leaves descendant release unresolved. Select local lifecycle guidance via existing verification. Distinguish configured provider, session capability, advertised schema and observed behavior. SDK-converted schema/intended-client checks are planned; injected provider cannot prove real-provider behavior. Keyword discovery is proxy; native choice requires actual selected tools/arguments and host/source identity. No real/native/efficiency result claimed.",
    "policy_basis": {
      "binding_constraints": [],
      "preferences_applied": [
        "Reuse adequate checks; select only important uncovered boundaries."
      ],
      "capability_limits": [
        "No real provider/client/native execution is supplied."
      ]
    },
    "test_change": "none",
    "checks": [
      {
        "check_id": "capture-coverage",
        "claim_or_risk": "Partial failure and cleanup retain truthful ownership and outcomes.",
        "action": "inspect",
        "method": "artifact_inspection",
        "technique": "exploratory",
        "check_ref_or_method": {
          "reference_or_procedure": "Observe one controlled collection failure and marked finalization cancellation with success control, retaining per-target outcomes and owner settlement.",
          "prerequisites": [
            "The designed tool boundary is available for inspection."
          ],
          "exclusions": [
            "No real provider/native observation is supplied."
          ],
          "expected_success": "Partial data and primary diagnostic survive; unknown facets stay unknown; attached target remains running.",
          "meaningful_failure": "Missing health becomes healthy, cleanup replaces primary failure or attach terminates its target."
        },
        "rationale": "Distinct important truthful tool-contract boundary; reuse adequate existing evidence.",
        "method_refs": ["assistant-verification/references/methods/artifact-validation.md"]
      },
      {
        "check_id": "capture-source",
        "claim_or_risk": "Large output retains complete-source access and stable identity.",
        "action": "inspect",
        "method": "artifact_inspection",
        "technique": "exploratory",
        "check_ref_or_method": {
          "reference_or_procedure": "Follow supported pages/reference for one retained capture and compare source identity across all pages.",
          "prerequisites": [
            "The designed tool boundary is available for inspection."
          ],
          "exclusions": [
            "No real provider/native observation is supplied."
          ],
          "expected_success": "All collected events remain accessible under one source identity without capture rerun.",
          "meaningful_failure": "Truncated output reruns acquisition or page exhaustion is misreported as complete source coverage."
        },
        "rationale": "Distinct important truthful tool-contract boundary; reuse adequate existing evidence.",
        "method_refs": ["assistant-verification/references/methods/artifact-validation.md"]
      }
    ],
    "tdd_choice": {
      "mode": false,
      "applicable_check_ids": [],
      "basis": "not_selected",
      "rationale": "Design/evidence selection only; no meaningful executable RED selected."
    },
    "omitted_checks_and_rationale": [
      "No universal matrix, required taxonomy or mandatory small-tool retention."
    ],
    "stop_rule": "Stop once the named claims have credible current evidence; preserve the shared source-bound three-consecutive-unproductive-cycle guard."
  },
  "evidence_assessment": {
    "status": "planned",
    "scope_and_evidence_refs": [],
    "gaps_and_limitations": [
      "Actual SDK-converted schema, intended-client and real-provider/native observations remain unverified."
    ],
    "next_action": "Inspect the selected actual boundaries before claiming their behavior."
  }
}
LIFECYCLE_MCP_CAPTURE
            ;;
        *) return 1 ;;
    esac
}
