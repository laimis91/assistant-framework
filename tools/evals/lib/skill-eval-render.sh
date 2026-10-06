emit_prompts() {
    local total=0
    local index
    local skill_name
    local skill_file
    local fixture_file
    local skill_output_dir
    local id
    local category
    local packet_name
    local packet_path
    local case_count
    local selected_cases
    local packet_basename
    local prompt_only

    validate_all_fixtures
    validate_selected_case_ids
    selected_cases="$(selected_case_ids_json)"
    mkdir -p "$OUTPUT_DIR"

    for index in "${!FIXTURE_FILES[@]}"; do
        skill_name="${SKILL_NAMES[$index]}"
        skill_file="${SKILL_FILES[$index]}"
        fixture_file="${FIXTURE_FILES[$index]}"
        skill_output_dir="$OUTPUT_DIR/$skill_name"
        mkdir -p "$skill_output_dir"

        while IFS=$'\t' read -r id category; do
            prompt_only=false
            if is_clarification_case "$skill_name" "$category"; then
                packet_basename="$(clarification_task_packet_basename "$fixture_file" "$skill_name" "$id")"
                [[ -n "$packet_basename" ]] || die "Could not resolve opaque prompt packet name for $skill_name case $id."
                packet_name="$packet_basename.md"
                prompt_only=true
            else
                packet_name="$id.md"
            fi
            packet_path="$skill_output_dir/$packet_name"
            jq -r --arg id "$id" --arg prompt_only "$prompt_only" --arg skill "$skill_name" --arg skill_path "$(display_path "$skill_file")" '
                def bullets($items):
                  if ($items | length) > 0 then $items | map("- " + .) | join("\n")
                  else "- (none)" end;
                def seeded_defects_section:
                  if ((.seeded_defects? // []) | length) > 0 then
                    "## Seeded Defects / Measurable Assertions\n\n"
                    + (.seeded_defects | map(
                        "- " + .id + ": " + .description + "\n"
                        + "  - Must detect: " + ((.must_detect // true) | tostring) + "\n"
                        + "  - Detection anchors: " + (.detection_anchors | join(", ")) + "\n"
                        + "  - Evidence anchors: " + (.evidence_anchors | join(", "))
                        + (if (.acceptable_severities? // [] | length) > 0 then "\n  - Acceptable severities: " + (.acceptable_severities | join(", ")) else "" end)
                        + (if (.finding_markers? // [] | length) > 0 then "\n  - Finding markers: " + (.finding_markers | join("; ")) else "" end)
                      ) | join("\n"))
                    + "\n\n"
                  else "" end;
                def structured_json_assertions_section:
                  if ((.machine_expectations.structured_json_assertions? // []) | length) > 0 then
                    "### Structured JSON Assertions\n\n"
                    + "These fixed JSON assertions are evaluated only by the local grader. Do not execute them; paths are JSON arrays.\n\n"
                    + "```json\n"
                    + (.machine_expectations.structured_json_assertions | tojson)
                    + "\n```\n\n"
                  else "" end;
                def canonical_review_batch_expectation_section($fixture; $case_id):
                  ($fixture.canonical_review_batch_expectations.case_template_refs[$case_id]? // null) as $template_ref
                  | if $template_ref != null then
                      "### Canonical Review Batch Expectation\n\n"
                      + "This exact frozen-plan oracle is part of the selected case and is evaluated by the local grader.\n\n"
                      + "```json\n"
                      + ($fixture.canonical_review_batch_expectations.templates[$template_ref] | tojson)
                      + "\n```\n\n"
                    else "" end;
                def canonical_review_snapshot_expectation_section($fixture; $case_id):
                  ($fixture.canonical_review_snapshot_expectations[$case_id]? // null) as $authority
                  | if $authority != null then
                      "### Canonical Review Snapshot Expectation\n\n"
                      + "This exact frozen snapshot authority is part of the selected case and is evaluated by the local grader.\n\n"
                      + "```json\n"
                      + ($authority | tojson)
                      + "\n```\n\n"
                    else "" end;
                def canonical_review_closure_expectation_section($fixture; $case_id):
                  ($fixture.canonical_review_closure_expectations[$case_id]? // null) as $authority
                  | if $authority != null then
                      "### Canonical Review Closure Expectation\n\n"
                      + "This exact frozen closure authority is part of the selected case and is evaluated by the local grader.\n\n"
                      + "```json\n"
                      + ($authority | tojson)
                      + "\n```\n\n"
                    else "" end;
                def canonical_review_finding_rule_distillation_expectation_section($fixture; $case_id):
                  ($fixture.canonical_review_finding_rule_distillation_expectations[$case_id]? // null) as $authority
                  | if $authority != null then
                      "### Canonical Review Finding Rule Distillation Expectation\n\n"
                      + "This immutable authority defines the exact active and fixed must-fix aggregate_finding_id values that require one deduplicated rule-distillation mapping.\n\n"
                      + "```json\n"
                      + ($authority | tojson)
                      + "\n```\n\n"
                    else "" end;
                def canonical_feature_preparation_result_expectation_section($fixture; $case_id):
                  ($fixture.canonical_feature_preparation_result_expectations[$case_id]? // null) as $authority
                  | if $authority != null then
                      "### Canonical Feature-Preparation Result Expectation\n\n"
                      + "This exact approved preparation result is immutable across the implementation input, triage, and implementation-step projections.\n\n"
                      + "```json\n"
                      + ($authority | tojson)
                      + "\n```\n\n"
                    else "" end;
                def task_only_packet:
                  "# Task Packet\n\n"
                  + "Skill: " + $skill + "\n\n"
                  + "Skill Path: " + $skill_path + "\n\n"
                  + "## Setup Context\n\n" + bullets(.setup_context) + "\n\n"
                  + "## Prompt\n\n" + .prompt + "\n";
                . as $fixture
                | .cases[]
                | select(.id == $id)
                | if $prompt_only == "true" then
                    "# User Request\n\n" + .prompt + "\n"
                  elif .prompt_packet_mode == "task_only" then
                    task_only_packet
                  else
                    "# " + .title + "\n\n"
                  + "Skill: " + $skill + "\n\n"
                  + "Skill Path: " + $skill_path + "\n\n"
                  + "Case ID: " + .id + "\n\n"
                  + "Category: " + .category + "\n\n"
                  + "Purpose: " + .purpose + "\n\n"
                  + "## Setup Context\n\n" + bullets(.setup_context) + "\n\n"
                  + "## Prompt\n\n" + .prompt + "\n\n"
                  + "## Expected Behavior\n\n" + bullets(.expected_behavior) + "\n\n"
                  + "## Pass Criteria\n\n" + bullets(.pass_criteria) + "\n\n"
                  + "## Fail Signals\n\n" + bullets(.fail_signals) + "\n\n"
                  + seeded_defects_section
                  + "## Machine Expectations\n\n"
                  + canonical_review_batch_expectation_section($fixture; .id)
                  + canonical_review_snapshot_expectation_section($fixture; .id)
                  + canonical_review_closure_expectation_section($fixture; .id)
                  + canonical_review_finding_rule_distillation_expectation_section($fixture; .id)
                  + canonical_feature_preparation_result_expectation_section($fixture; .id)
                  + "### Required Substrings\n\n"
                  + bullets(.machine_expectations.required_substrings) + "\n\n"
                  + "### Forbidden Substrings\n\n"
                  + bullets(.machine_expectations.forbidden_substrings) + "\n\n"
                  + structured_json_assertions_section
                  end
            ' "$fixture_file" >"$packet_path"
        done < <(jq -r --argjson selected_cases "$selected_cases" '
            .cases[]
            | .id as $id
            | select(($selected_cases | length) == 0 or ($selected_cases | index($id)) != null)
            | [.id, .category]
            | @tsv
        ' "$fixture_file")

        case_count="$(jq --argjson selected_cases "$selected_cases" '[
            .cases[]
            | .id as $id
            | select(($selected_cases | length) == 0 or ($selected_cases | index($id)) != null)
        ] | length' "$fixture_file")"
        total=$((total + case_count))
    done

    echo "Wrote $total prompt packets to $OUTPUT_DIR"
}
