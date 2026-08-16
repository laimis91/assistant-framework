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

        def normalized_activation_request:
          gsub("^[[:space:]]+|[[:space:]]+$"; "")
          | gsub("[[:space:]]+"; " ")
          | ascii_downcase;

        def activation_case_error($index):
          if type != "object" then
            "activation_cases[\($index)] must be an object"
          elif (keys | sort) != ["should_activate", "user_request"] then
            "activation_cases[\($index)] must contain exactly user_request and should_activate"
          elif (.user_request? | type) != "string" then
            "activation_cases[\($index)].user_request must be a nonblank string"
          elif (.user_request | test("[^[:space:]]") | not) then
            "activation_cases[\($index)].user_request must be a nonblank string"
          elif (.should_activate? | type != "boolean") then
            "activation_cases[\($index)].should_activate must be boolean"
          else
            empty
          end;

        def validate_activation_cases:
          if .schema_version == "1.0" and (has("activation_cases") | not) then
            empty
          elif (.activation_cases? | type != "array") then
            "top-level field activation_cases must be an array"
          elif (.activation_cases | length < 3) then
            "top-level field activation_cases must contain at least three entries"
          else
            [ .activation_cases | to_entries[] | .key as $index | .value | activation_case_error($index) ] as $item_errors
            | if ($item_errors | length > 0) then
                $item_errors[]
              else
                ([.activation_cases[] | select(.should_activate == true) | .user_request | normalized_activation_request] | unique) as $positive_requests
                | ([.activation_cases[] | select(.should_activate == false) | .user_request | normalized_activation_request] | unique) as $negative_requests
                | if ($positive_requests | length < 2) then
                    "activation_cases must contain at least two normalized-distinct positive requests"
                  elif ($negative_requests | length < 1) then
                    "activation_cases must contain at least one normalized-disjoint nearby negative request"
                  elif (($positive_requests - $negative_requests | length) != ($positive_requests | length)) then
                    "activation_cases positive and negative requests must be normalized-disjoint"
                  else
                    empty
                  end
              end
          end;

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

        def json_path:
          type == "array" and length > 0
          and all(.[]; (type == "string" and length > 0) or (type == "number" and . >= 0 and (. % 1) == 0));

        def scalar:
          type == "string" or type == "number" or type == "boolean" or type == "null";

        def structured_assertion_error($index; $assertion_index):
          if type != "object" then
            "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] must be an object"
          elif (.operator? | nonempty_string | not) then
            "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] missing or invalid operator"
          elif .operator == "equals" then
            if (.path? | json_path | not) or (has("expected") | not) or (.expected | scalar | not) then
              "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] invalid equals assertion"
            else empty end
          elif .operator == "nonempty_string" or .operator == "nonempty_array" or .operator == "empty_array" then
            if (.path? | json_path | not) then
              "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] invalid \(.operator) path"
            else empty end
          elif .operator == "equals_path" then
            if (.path? | json_path | not) or (.other_path? | json_path | not) then
              "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] invalid equals_path assertion"
            else empty end
          elif .operator == "required_when_equals" then
            .expected_type as $expected_type |
            if (.when_path? | json_path | not) or (has("value") | not) or (.value | scalar | not) or (.path? | json_path | not) or (has("expected_type") and (($expected_type | type) != "string" or (["null", "boolean", "number", "string", "array", "object"] | index($expected_type) | not))) then
              "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] invalid required_when_equals assertion"
            else empty end
          elif .operator == "array_field_values_exact" then
            if (.path? | json_path | not) or (.field? | nonempty_string | not) or (.expected_values? | nonempty_string_array | not) then
              "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] invalid array_field_values_exact assertion"
            else empty end
          elif .operator == "array_items_nonempty_fields" then
            if (.path? | json_path | not) or (.fields? | nonempty_string_array | not) then
              "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] invalid array_items_nonempty_fields assertion"
            else empty end
          else
            "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] unsupported operator: \(.operator)"
          end;

        def case_structured_json_assertions($index):
          if has("structured_json_assertions") then
            if (.structured_json_assertions | type != "array") or (.structured_json_assertions | length == 0) then
              "case[\($index)].machine_expectations.structured_json_assertions must be a non-empty array when present"
            else
              .structured_json_assertions | to_entries[] | .key as $assertion_index | .value |
                structured_assertion_error($index; $assertion_index)
            end
          else empty end;

        def case_machine_expectations($index):
          if (.machine_expectations? | type == "object") then
            case_machine_expectation_array($index; "required_substrings"),
            case_machine_expectation_array($index; "forbidden_substrings"),
            (.machine_expectations | case_structured_json_assertions($index))
          else
            "case[\($index)] missing or invalid object field: machine_expectations"
          end;

        def optional_bool($value):
          if $value == null then true else ($value | type == "boolean") end;

        def optional_nonnegative_int($value):
          if $value == null then true else (($value | type == "number") and ($value >= 0) and (($value % 1) == 0)) end;

        def case_seeded_defects($index):
          if has("false_positive_budget") and (optional_nonnegative_int(.false_positive_budget) | not) then
            "case[\($index)] false_positive_budget must be a non-negative integer when present"
          elif has("false_positive_markers") and (.false_positive_markers | nonempty_string_array | not) then
            "case[\($index)] false_positive_markers must be a non-empty string array when present"
          elif has("seeded_defects") then
            if (.seeded_defects | type != "array") or (.seeded_defects | length == 0) then
              "case[\($index)] seeded_defects must be a non-empty array when present"
            else
              .seeded_defects | to_entries[] | .key as $defect_index | .value |
                if type != "object" then
                  "case[\($index)].seeded_defects[\($defect_index)] must be an object"
                elif (.id? | nonempty_string | not) then
                  "case[\($index)].seeded_defects[\($defect_index)] missing or invalid string field: id"
                elif (.description? | nonempty_string | not) then
                  "case[\($index)].seeded_defects[\($defect_index)] missing or invalid string field: description"
                elif (optional_bool(.must_detect? // null) | not) then
                  "case[\($index)].seeded_defects[\($defect_index)] must_detect must be boolean when present"
                elif (.detection_anchors? | nonempty_string_array | not) then
                  "case[\($index)].seeded_defects[\($defect_index)] missing or invalid non-empty string array field: detection_anchors"
                elif (.evidence_anchors? | nonempty_string_array | not) then
                  "case[\($index)].seeded_defects[\($defect_index)] missing or invalid non-empty string array field: evidence_anchors"
                elif has("acceptable_severities") and (.acceptable_severities | nonempty_string_array | not) then
                  "case[\($index)].seeded_defects[\($defect_index)] acceptable_severities must be a non-empty string array when present"
                elif has("finding_markers") and (.finding_markers | nonempty_string_array | not) then
                  "case[\($index)].seeded_defects[\($defect_index)] finding_markers must be a non-empty string array when present"
                else
                  empty
                end
            end
          else
            empty
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
          validate_activation_cases,
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
                 case_machine_expectations($index),
                 case_seeded_defects($index)
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
