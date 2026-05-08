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

    validate_all_fixtures
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
                .cases[]
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
                  + "## Machine Expectations\n\n"
                  + "### Required Substrings\n\n"
                  + bullets(.machine_expectations.required_substrings) + "\n\n"
                  + "### Forbidden Substrings\n\n"
                  + bullets(.machine_expectations.forbidden_substrings) + "\n"
            ' "$fixture_file" >"$packet_path"
        done < <(jq -r '.cases[].id' "$fixture_file")

        case_count="$(jq '.cases | length' "$fixture_file")"
        total=$((total + case_count))
    done

    echo "Wrote $total prompt packets to $OUTPUT_DIR"
}
