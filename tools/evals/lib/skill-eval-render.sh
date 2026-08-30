emit_prompts() {
    local total=0
    local index
    local skill_name
    local skill_file
    local fixture_file
    local skill_output_dir
    local id
    local packet_path
    local case_count
    local selected_cases

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

        while IFS= read -r id; do
            packet_path="$skill_output_dir/$id.md"
            jq -r --arg id "$id" --arg skill "$skill_name" --arg skill_path "$(display_path "$skill_file")" '
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
                . as $fixture
                | .cases[]
                | select(.id == $id)
                | "# " + .title + "\n\n"
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
                  + "### Required Substrings\n\n"
                  + bullets(.machine_expectations.required_substrings) + "\n\n"
                  + "### Forbidden Substrings\n\n"
                  + bullets(.machine_expectations.forbidden_substrings) + "\n\n"
                  + structured_json_assertions_section
            ' "$fixture_file" >"$packet_path"
        done < <(jq -r --argjson selected_cases "$selected_cases" '
            .cases[]
            | .id as $id
            | select(($selected_cases | length) == 0 or ($selected_cases | index($id)) != null)
            | .id
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
