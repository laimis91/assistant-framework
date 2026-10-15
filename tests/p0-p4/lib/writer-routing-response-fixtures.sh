#!/usr/bin/env bash

# Fixed response examples for the five writer contract cases. Expected values
# are deliberately independent of the mutable fixture assertion inventory.
# Actual file outcomes remain checked by the separate behavioral adapter.
write_writer_routing_response() {
    local case_id="$1" response_path="$2"
    local agent status implementation_status output failure_class next_action changed
    case "$case_id" in
        writer-routing-exact-pattern)
            agent=mechanical-writer
            status=DONE
            implementation_status=done
            output=$'approved exact wording\n'
            failure_class=none
            next_action=review
            changed=true
            ;;
        writer-routing-small-semantic)
            agent=intelligent-writer
            status=DONE
            implementation_status=done
            output=$'success requires exact artifact\n'
            failure_class=none
            next_action=review
            changed=true
            ;;
        writer-routing-small-grader)
            agent=intelligent-writer
            status=DONE
            implementation_status=done
            output=$'oracle rejects plausible wrong output\n'
            failure_class=none
            next_action=review
            changed=true
            ;;
        writer-routing-stale-partial)
            agent=mechanical-writer
            status=NEEDS_CONTEXT
            implementation_status=blocked
            output=$'partial approved wording\n'
            failure_class=stale_plan
            next_action=orchestrator
            changed=true
            ;;
        writer-routing-baseline-failure)
            agent=intelligent-writer
            status=BLOCKED
            implementation_status=blocked
            output=$'seed wording\n'
            failure_class=broken_baseline
            next_action=orchestrator
            changed=false
            ;;
        *) return 1 ;;
    esac
    jq -n --arg case_id "$case_id" --arg agent "$agent" --arg status "$status" \
        --arg implementation_status "$implementation_status" --arg output "$output" \
        --arg failure_class "$failure_class" --arg next_action "$next_action" \
        --argjson changed "$changed" '{
      summary:"Writer selection follows the approved recipe and remaining judgment; blocked returns retain actual partial changes and return evidence to the Orchestrator.",
      status:$status,
      actual_output:$output,
      dependent_output:"dependent must remain unchanged\n",
      failure_class:$failure_class,
      next_action:$next_action,
      slice_manifest:[{
        slice_id:$case_id,
        writer_selection:({
          agent:$agent,
          rationale:(if $agent == "mechanical-writer" then "Concrete approved recipe with resolved decisions at initial selection; stale evidence stops dependent edits." else "Semantic/grader judgment or baseline classification requires intelligent handling." end)
        } + if $agent == "mechanical-writer" then {mechanical_eligibility:{recipe_or_example_ref:"recipe.md",resolved_decisions_ref:"decisions.md",scope_and_dependencies_ref:"scope.md",correctness_expectations_ref:"expectations.md"}} else {} end),
        selected_check_ids:["CHECK-OUTPUT"],
        binding_obligation_refs:[{kind:"required_scope",value:"only output.txt",source_ref:"scope.md"}],
        tdd_applies:false
      }],
      changed_files:(if $changed then [{path:"output.txt",change_type:"modified",description:(if $status == "NEEDS_CONTEXT" then "Preserved the actual partial approved wording after eligibility became stale." else "Applied the approved independently fixed output." end)}] else [] end),
      slice_verification_summary:[{slice_id:$case_id,implementation_status:$implementation_status}]
    }' >"$response_path"
}
