validate_fixture() {
    local fixture_file="$1"
    local skill_name="$2"
    local validation_error

    require_jq
    [[ -f "$fixture_file" ]] || die "Fixture not found: $(display_path "$fixture_file")"

    validation_error="$(jq -r --arg skill_name "$skill_name" '
        def nonempty_string:
          if type == "string" then length > 0 else false end;

        def nonempty_string_array:
          if type != "array" or length == 0 then false
          else all(.[]; type == "string" and length > 0) end;

        def required_string($name):
          if (.[$name]? | nonempty_string) then empty
          else "missing or invalid top-level string field: \($name)" end;

        def required_bool($name; $value):
          if has($name) and .[$name] == $value then empty
          else "top-level field \($name) must be \($value)" end;

        def required_string_array($name):
          if (.[$name]? | nonempty_string_array) then empty
          else "missing or invalid non-empty string array field: \($name)" end;

        def skill_identity_name:
          (.skill? // null) as $skill
          | if ($skill | nonempty_string) then $skill
            elif ($skill | type) == "object" then
              if (($skill.name? // null) | nonempty_string) then $skill.name
              elif (.skill_name? | nonempty_string) then .skill_name
              else null end
            elif (.skill_name? | nonempty_string) then .skill_name
            else null end;

        def validate_skill_identity:
          (skill_identity_name) as $fixture_skill
          | if $fixture_skill == null then
              "missing or invalid skill identity field: skill, skill.name, or skill_name"
            elif $fixture_skill != $skill_name then
              "skill identity must match selected skill: expected \($skill_name), got \($fixture_skill)"
            else
              empty
            end;

        def validate_optional_skill_path:
          (.skill? // null) as $skill
          | if ($skill | type) == "object" then
              if ($skill | has("path")) and (($skill.path? // null) | nonempty_string | not) then
                "skill.path must be a non-empty string when present"
              else
                empty
              end
            elif has("skill_path") and ((.skill_path? // null) | nonempty_string | not) then
              "skill_path must be a non-empty string when present"
            else
              empty
            end;

        def case_string($index; $name):
          if (.[$name]? | nonempty_string) then empty
          else "case[\($index)] missing or invalid string field: \($name)" end;

        def safe_case_id($index):
          (.id? // null) as $id
          | if ($id | nonempty_string | not) then
              "case[\($index)] missing or invalid string field: id"
            elif $id == "." or $id == ".." then
              "case[\($index)] invalid case id \($id | @json): must be a unique safe filename component using only letters, digits, dot, underscore, and hyphen; not . or .."
            elif ($id | test("^[A-Za-z0-9._-]+$") | not) then
              "case[\($index)] invalid case id \($id | @json): must be a unique safe filename component using only letters, digits, dot, underscore, and hyphen"
            else
              empty
            end;

        def duplicate_case_ids:
          if (.cases? | type == "array") then
            [ .cases[]? | select(type == "object") | .id? | select(type == "string") ] as $ids
            | ($ids | group_by(.)[]? | select(length > 1) | .[0]) as $duplicate
            | "duplicate case id: \($duplicate)"
          else
            empty
          end;

        def case_string_array($index; $name):
          if (.[$name]? | nonempty_string_array) then empty
          else "case[\($index)] missing or invalid non-empty string array field: \($name)" end;

        def case_machine_expectation_array($index; $name):
          if (.machine_expectations? | type == "object")
             and (.machine_expectations[$name]? | nonempty_string_array)
          then empty
          else "case[\($index)] missing or invalid machine_expectations.\($name) non-empty string array" end;

        def case_machine_expectations($index):
          if (.machine_expectations? | type == "object") then
            case_machine_expectation_array($index; "required_substrings"),
            case_machine_expectation_array($index; "forbidden_substrings")
          else
            "case[\($index)] missing or invalid object field: machine_expectations"
          end;

        if type != "object" then
          "fixture root must be a JSON object"
        else
          required_string("schema_version"),
          required_string("suite_id"),
          required_string("title"),
          required_string("description"),
          required_string("eval_type"),
          required_bool("provider_neutral"; true),
          required_bool("model_specific_api_calls"; false),
          required_string_array("recommended_use"),
          validate_skill_identity,
          validate_optional_skill_path,
          (if (.cases? | type == "array") and (.cases | length > 0) then empty
           else "top-level field cases must be a non-empty array" end),
          duplicate_case_ids,
          (if (.cases? | type == "array") then
             .cases | to_entries[] | .key as $index | .value |
               if type != "object" then
                 "case[\($index)] must be an object"
               else
                 safe_case_id($index),
                 case_string($index; "title"),
                 case_string($index; "category"),
                 case_string($index; "purpose"),
                 case_string($index; "prompt"),
                 case_string_array($index; "setup_context"),
                 case_string_array($index; "expected_behavior"),
                 case_string_array($index; "pass_criteria"),
                 case_string_array($index; "fail_signals"),
                 case_machine_expectations($index)
               end
           else empty end)
        end
    ' "$fixture_file")" || die "Fixture is not valid JSON: $(display_path "$fixture_file")"

    if [[ -n "$validation_error" ]]; then
        echo "$(display_path "$fixture_file"): $validation_error" >&2
        exit 1
    fi
}

validate_all_fixtures() {
    local index

    for index in "${!FIXTURE_FILES[@]}"; do
        validate_fixture "${FIXTURE_FILES[$index]}" "${SKILL_NAMES[$index]}"
    done
}

list_cases() {
    local index

    validate_all_fixtures
    for index in "${!FIXTURE_FILES[@]}"; do
        jq -r --arg skill "${SKILL_NAMES[$index]}" '.cases[] | [$skill, .id, .category, .title] | @tsv' "${FIXTURE_FILES[$index]}"
    done
}
