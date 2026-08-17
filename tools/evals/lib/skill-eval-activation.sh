validate_activation_results() {
    local expected_results
    local validation_error
    local index

    require_jq
    [[ -f "$ACTIVATION_RESULTS_FILE" ]] || die "Activation results file does not exist: $ACTIVATION_RESULTS_FILE"

    expected_results="$({
        for index in "${!FIXTURE_FILES[@]}"; do
            jq -c --arg skill "${SKILL_NAMES[$index]}" '
                .activation_cases[]?
                | { skill: $skill, user_request, should_activate }
            ' "${FIXTURE_FILES[$index]}"
        done
    } | jq -s '.')"

    validation_error="$(jq -r --argjson expected "$expected_results" '
        def nonempty_string:
          type == "string" and test("[^[:space:]]");
        def result_key_exists($items; $entry):
          any($items[]; .skill == $entry.skill and .user_request == $entry.user_request);
        def valid_selected_skills:
          type == "array"
          and all(.[]; nonempty_string)
          and (. as $skills | ($skills | unique | length) == ($skills | length));
        def result_shape_error($index):
          if type != "object" then
            "activation result[\($index)] must be an object"
          elif (keys | sort) != ["selected_skills", "skill", "user_request"] then
            "activation result[\($index)] must contain exactly skill, user_request, and selected_skills"
          elif (.skill | nonempty_string | not) then
            "activation result[\($index)].skill must be a nonblank string"
          elif (.user_request | nonempty_string | not) then
            "activation result[\($index)].user_request must be a nonblank string"
          elif (.selected_skills | valid_selected_skills | not) then
            "activation result[\($index)].selected_skills must be a unique array of nonblank strings"
          else empty end;
        if type != "object" then
          "activation results root must be a JSON object"
        elif (keys | sort) != ["results", "schema_version"] then
          "activation results root must contain exactly schema_version and results"
        elif .schema_version != "1.0" then
          "activation results schema_version must be 1.0"
        elif (.results | type) != "array" then
          "activation results results must be an array"
        else
          [ .results | to_entries[] | .key as $index | .value | result_shape_error($index) ] as $shape_errors
          | if ($shape_errors | length > 0) then
              $shape_errors[]
            else
              [.results[] | {skill, user_request}] as $observed
              | [ $observed | group_by([.skill, .user_request])[] | select(length > 1) | .[0] ] as $duplicates
              | [ $expected[] | select(result_key_exists($observed; .) | not) ] as $missing
              | [ $observed[] | select(result_key_exists($expected; .) | not) ] as $unexpected
              | if ($duplicates | length > 0) then
                  $duplicates[] | "duplicate activation result for skill \(.skill | @json) and user_request \(.user_request | @json)"
                elif ($missing | length > 0) then
                  $missing[] | "missing activation result for skill \(.skill | @json) and user_request \(.user_request | @json)"
                elif ($unexpected | length > 0) then
                  $unexpected[] | "unexpected activation result for skill \(.skill | @json) and user_request \(.user_request | @json)"
                else empty end
            end
        end
    ' "$ACTIVATION_RESULTS_FILE")" || die "Activation results are not valid JSON: $ACTIVATION_RESULTS_FILE"

    [[ -z "$validation_error" ]] || die "Activation results are invalid: $validation_error"
    printf '%s\n' "$expected_results"
}

evaluate_activation_results() {
    local expected_results expected_result skill_name should_activate request_json
    local result observed_selected total=0 passed=0 failed=0

    validate_all_fixtures
    expected_results="$(validate_activation_results)"

    echo "Activation selection evaluation compares externally observed results only; it does not invoke native routing, provider APIs, SDKs, or network services."
    echo ""
    while IFS= read -r expected_result; do
        skill_name="$(jq -r '.skill' <<<"$expected_result")"
        should_activate="$(jq -r '.should_activate' <<<"$expected_result")"
        request_json="$(jq -c '.user_request' <<<"$expected_result")"
        result="$(jq -c --argjson expected "$expected_result" '
            .results[]
            | select(.skill == $expected.skill and .user_request == $expected.user_request)
        ' "$ACTIVATION_RESULTS_FILE")"
        observed_selected="$(jq -r --arg skill "$skill_name" '.selected_skills | index($skill) != null' <<<"$result")"
        total=$((total + 1))
        if [[ "$should_activate" == "$observed_selected" ]]; then
            passed=$((passed + 1))
            printf 'PASS\t%s\t%s\texpected should_activate=%s observed selected=%s\n' "$skill_name" "$request_json" "$should_activate" "$observed_selected"
        else
            failed=$((failed + 1))
            printf 'FAIL\t%s\t%s\texpected should_activate=%s observed selected=%s\n' "$skill_name" "$request_json" "$should_activate" "$observed_selected"
        fi
    done < <(jq -c '.[]' <<<"$expected_results")

    echo ""
    echo "Summary: total=$total passed=$passed failed=$failed"
    [[ "$failed" -eq 0 ]]
}
