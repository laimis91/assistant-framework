first_response_path_for_case() {
    local skill_name="$1"
    local id="$2"

    if [[ -f "$RESPONSES_DIR/$skill_name/$id.txt" ]]; then
        printf '%s\n' "$RESPONSES_DIR/$skill_name/$id.txt"
    elif [[ -f "$RESPONSES_DIR/$skill_name/$id.md" ]]; then
        printf '%s\n' "$RESPONSES_DIR/$skill_name/$id.md"
    elif [[ "${#FIXTURE_FILES[@]}" -eq 1 && -f "$RESPONSES_DIR/$id.txt" ]]; then
        printf '%s\n' "$RESPONSES_DIR/$id.txt"
    elif [[ "${#FIXTURE_FILES[@]}" -eq 1 && -f "$RESPONSES_DIR/$id.md" ]]; then
        printf '%s\n' "$RESPONSES_DIR/$id.md"
    else
        printf '\n'
    fi
}

is_file_nonempty() {
    local path="$1"
    [[ -s "$path" ]] && grep -q '[^[:space:]]' "$path"
}

count_fail_signal_hits() {
    local fixture_file="$1"
    local id="$2"
    local response_path="$3"
    local signal
    local hits=0

    while IFS= read -r signal; do
        if [[ ${#signal} -ge 12 ]] && grep -Fqi -- "$signal" "$response_path"; then
            hits=$((hits + 1))
        fi
    done < <(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .fail_signals[]' "$fixture_file")

    printf '%s\n' "$hits"
}

count_missing_required_substrings() {
    local fixture_file="$1"
    local id="$2"
    local response_path="$3"
    local expected
    local misses=0

    while IFS= read -r expected; do
        if ! grep -Fqi -- "$expected" "$response_path"; then
            misses=$((misses + 1))
        fi
    done < <(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .machine_expectations.required_substrings[]' "$fixture_file")

    printf '%s\n' "$misses"
}


count_ordered_substring_failures() {
    local fixture_file="$1"
    local id="$2"
    local response_path="$3"
    local ordered_json
    local needle
    local response_text
    local remaining
    local failures=0

    response_text="$(tr '[:upper:]' '[:lower:]' <"$response_path")"
    while IFS= read -r ordered_json; do
        remaining="$response_text"
        while IFS= read -r needle; do
            needle="$(printf '%s' "$needle" | tr '[:upper:]' '[:lower:]')"
            if [[ "$remaining" == *"$needle"* ]]; then
                remaining="${remaining#*"$needle"}"
            else
                failures=$((failures + 1))
                break
            fi
        done < <(jq -r '.[]' <<<"$ordered_json")
    done < <(jq -c --arg id "$id" '.cases[] | select(.id == $id) | .machine_expectations.ordered_substrings[]?' "$fixture_file")

    printf '%s\n' "$failures"
}

count_forbidden_substring_hits() {
    local fixture_file="$1"
    local id="$2"
    local response_path="$3"
    local forbidden
    local hits=0

    while IFS= read -r forbidden; do
        if grep -Fqi -- "$forbidden" "$response_path"; then
            hits=$((hits + 1))
        fi
    done < <(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .machine_expectations.forbidden_substrings[]' "$fixture_file")

    printf '%s\n' "$hits"
}

count_seeded_defect_failures() {
    local fixture_file="$1"
    local id="$2"
    local response_path="$3"
    local defect_json
    local defect_id
    local must_detect
    local anchor
    local detected
    local evidence_found
    local severity_found
    local failures=0

    while IFS= read -r defect_json; do
        defect_id="$(jq -r '.id' <<<"$defect_json")"
        must_detect="$(jq -r '.must_detect // true' <<<"$defect_json")"
        [[ "$must_detect" == "true" ]] || continue

        detected=1
        while IFS= read -r anchor; do
            if ! grep -Fqi -- "$anchor" "$response_path"; then
                detected=0
                break
            fi
        done < <(jq -r '.detection_anchors[]' <<<"$defect_json")

        evidence_found=1
        while IFS= read -r anchor; do
            if ! grep -Fqi -- "$anchor" "$response_path"; then
                evidence_found=0
                break
            fi
        done < <(jq -r '.evidence_anchors[]' <<<"$defect_json")

        severity_found=1
        if [[ "$(jq '(.acceptable_severities // []) | length' <<<"$defect_json")" -gt 0 ]]; then
            severity_found=0
            while IFS= read -r anchor; do
                if grep -Fqi -- "$anchor" "$response_path"; then
                    severity_found=1
                    break
                fi
            done < <(jq -r '.acceptable_severities[]' <<<"$defect_json")
        fi

        finding_markers_found=1
        while IFS= read -r anchor; do
            if ! grep -Fqi -- "$anchor" "$response_path"; then
                finding_markers_found=0
                break
            fi
        done < <(jq -r '.finding_markers[]?' <<<"$defect_json")

        if [[ "$detected" -eq 0 || "$evidence_found" -eq 0 || "$severity_found" -eq 0 || "$finding_markers_found" -eq 0 ]]; then
            failures=$((failures + 1))
            printf 'Seeded defect not satisfied for %s: detected=%s evidence=%s severity=%s finding_markers=%s\n' "$defect_id" "$detected" "$evidence_found" "$severity_found" "$finding_markers_found" >&2
        fi
    done < <(jq -c --arg id "$id" '.cases[] | select(.id == $id) | .seeded_defects[]?' "$fixture_file")

    printf '%s\n' "$failures"
}

count_false_positive_marker_failures() {
    local fixture_file="$1"
    local id="$2"
    local response_path="$3"
    local budget
    local marker
    local hits=0

    budget="$(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .false_positive_budget // 0' "$fixture_file")"
    while IFS= read -r marker; do
        if grep -Fqi -- "$marker" "$response_path"; then
            hits=$((hits + 1))
        fi
    done < <(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .false_positive_markers[]?' "$fixture_file")

    if [[ "$hits" -gt "$budget" ]]; then
        printf '%s\n' "$((hits - budget))"
    else
        printf '0\n'
    fi
}

count_structured_json_assertion_failures() {
    local fixture_file="$1"
    local id="$2"
    local response_path="$3"
    local assertion
    local failures=0

    if [[ "$(jq -r --arg id "$id" '.cases[] | select(.id == $id) | (.machine_expectations.structured_json_assertions? // []) | length' "$fixture_file")" -eq 0 ]]; then
        printf '0\n'
        return
    fi

    if ! jq -e -s 'length == 1' "$response_path" >/dev/null 2>&1; then
        printf '1\n'
        return
    fi

    while IFS= read -r assertion; do
        if ! jq -e --argjson assertion "$assertion" '
            def path_exists($path):
              reduce $path[] as $key (
                { exists: true, value: . };
                if (.exists | not) then .
                elif (($key | type) == "string") and ((.value | type) == "object") and (.value | has($key)) then
                  { exists: true, value: .value[$key] }
                elif (($key | type) == "number") and ((.value | type) == "array") and ($key >= 0) and ($key < (.value | length)) then
                  { exists: true, value: .value[$key] }
                else
                  { exists: false, value: null }
                end
              ) | .exists;
            def value_at($path): getpath($path);
            if $assertion.operator == "equals" then
              path_exists($assertion.path) and value_at($assertion.path) == $assertion.expected
            elif $assertion.operator == "nonempty_string" then
              path_exists($assertion.path) and (value_at($assertion.path) | type == "string" and test("[^[:space:]]"))
            elif $assertion.operator == "nonempty_array" then
              path_exists($assertion.path) and (value_at($assertion.path) | type == "array" and length > 0)
            elif $assertion.operator == "equals_path" then
              path_exists($assertion.path) and path_exists($assertion.other_path)
              and value_at($assertion.path) == value_at($assertion.other_path)
            elif $assertion.operator == "required_when_equals" then
              if path_exists($assertion.when_path) and value_at($assertion.when_path) == $assertion.value then
                path_exists($assertion.path) and value_at($assertion.path) != null
                and (if $assertion.expected_type? == null then true else (value_at($assertion.path) | type == $assertion.expected_type) end)
              else true end
            elif $assertion.operator == "array_field_values_exact" then
              path_exists($assertion.path)
              and (value_at($assertion.path) | type == "array")
              and ([value_at($assertion.path)[] | if type == "object" then .[$assertion.field] else null end] | sort)
                == ($assertion.expected_values | sort)
            elif $assertion.operator == "array_items_nonempty_fields" then
              path_exists($assertion.path)
              and (value_at($assertion.path) | type == "array")
              and all(value_at($assertion.path)[]; . as $item | type == "object" and all($assertion.fields[]; . as $field | ($item[$field] | type == "string" and test("[^[:space:]]"))))
            else false end
        ' "$response_path" >/dev/null; then
            failures=$((failures + 1))
        fi
    done < <(jq -c --arg id "$id" '.cases[] | select(.id == $id) | .machine_expectations.structured_json_assertions[]?' "$fixture_file")

    printf '%s\n' "$failures"
}

grade_responses() {
    validate_all_fixtures
    [[ -d "$RESPONSES_DIR" ]] || die "Response directory does not exist: $RESPONSES_DIR"

    local total=0
    local passed=0
    local failed=0
    local missing=0
    local empty=0
    local signal_failures=0
    local missing_required_failures=0
    local forbidden_substring_failures=0
    local ordered_substring_failures=0
    local seeded_defect_failures=0
    local false_positive_marker_failures=0
    local structured_json_assertion_failures=0
    local index
    local skill_name
    local fixture_file
    local id
    local category
    local title
    local response_path
    local fail_signal_hits
    local required_misses
    local forbidden_hits
    local ordered_failures
    local seeded_failures
    local false_positive_failures
    local structured_failures
    local status
    local reason

    echo "Heuristic/local grading only. Deterministic substring checks are local proxies; no provider API is invoked."
    echo ""

    for index in "${!FIXTURE_FILES[@]}"; do
        skill_name="${SKILL_NAMES[$index]}"
        fixture_file="${FIXTURE_FILES[$index]}"

        while IFS=$'\t' read -r id category title; do
            total=$((total + 1))
            response_path="$(first_response_path_for_case "$skill_name" "$id")"
            status="PASS"
            reason="non-empty response with no exact fail-signal phrase hits and no machine expectation failures"

            if [[ -z "$response_path" ]]; then
                status="FAIL"
                reason="missing response file"
                missing=$((missing + 1))
            elif ! is_file_nonempty "$response_path"; then
                status="FAIL"
                reason="empty response file"
                empty=$((empty + 1))
            else
                fail_signal_hits="$(count_fail_signal_hits "$fixture_file" "$id" "$response_path")"
                required_misses="$(count_missing_required_substrings "$fixture_file" "$id" "$response_path")"
                forbidden_hits="$(count_forbidden_substring_hits "$fixture_file" "$id" "$response_path")"
                ordered_failures="$(count_ordered_substring_failures "$fixture_file" "$id" "$response_path")"
                seeded_failures="$(count_seeded_defect_failures "$fixture_file" "$id" "$response_path")"
                false_positive_failures="$(count_false_positive_marker_failures "$fixture_file" "$id" "$response_path")"
                structured_failures="$(count_structured_json_assertion_failures "$fixture_file" "$id" "$response_path")"
                if [[ "$fail_signal_hits" -gt 0 ]]; then
                    status="FAIL"
                    reason="$fail_signal_hits exact fail-signal phrase hit(s)"
                    signal_failures=$((signal_failures + 1))
                fi
                if [[ "$required_misses" -gt 0 ]]; then
                    if [[ "$status" == "FAIL" ]]; then
                        reason="$reason; $required_misses missing required substring(s)"
                    else
                        status="FAIL"
                        reason="$required_misses missing required substring(s)"
                    fi
                    missing_required_failures=$((missing_required_failures + required_misses))
                fi
                if [[ "$forbidden_hits" -gt 0 ]]; then
                    if [[ "$status" == "FAIL" ]]; then
                        reason="$reason; $forbidden_hits forbidden substring hit(s)"
                    else
                        status="FAIL"
                        reason="$forbidden_hits forbidden substring hit(s)"
                    fi
                    forbidden_substring_failures=$((forbidden_substring_failures + forbidden_hits))
                fi
                if [[ "$ordered_failures" -gt 0 ]]; then
                    if [[ "$status" == "FAIL" ]]; then
                        reason="$reason; $ordered_failures ordered substring assertion failure(s)"
                    else
                        status="FAIL"
                        reason="$ordered_failures ordered substring assertion failure(s)"
                    fi
                    ordered_substring_failures=$((ordered_substring_failures + ordered_failures))
                fi
                if [[ "$seeded_failures" -gt 0 ]]; then
                    if [[ "$status" == "FAIL" ]]; then
                        reason="$reason; $seeded_failures seeded defect assertion failure(s)"
                    else
                        status="FAIL"
                        reason="$seeded_failures seeded defect assertion failure(s)"
                    fi
                    seeded_defect_failures=$((seeded_defect_failures + seeded_failures))
                fi
                if [[ "$false_positive_failures" -gt 0 ]]; then
                    if [[ "$status" == "FAIL" ]]; then
                        reason="$reason; $false_positive_failures false positive marker budget failure(s)"
                    else
                        status="FAIL"
                        reason="$false_positive_failures false positive marker budget failure(s)"
                    fi
                    false_positive_marker_failures=$((false_positive_marker_failures + false_positive_failures))
                fi
                if [[ "$structured_failures" -gt 0 ]]; then
                    if [[ "$status" == "FAIL" ]]; then
                        reason="$reason; $structured_failures structured JSON assertion failure(s)"
                    else
                        status="FAIL"
                        reason="$structured_failures structured JSON assertion failure(s)"
                    fi
                    structured_json_assertion_failures=$((structured_json_assertion_failures + structured_failures))
                fi
            fi

            if [[ "$status" == "PASS" ]]; then
                passed=$((passed + 1))
            else
                failed=$((failed + 1))
            fi

            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$status" "$skill_name" "$id" "$category" "$title" "$reason"
        done < <(jq -r '.cases[] | [.id, .category, .title] | @tsv' "$fixture_file")
    done

    echo ""
    printf 'Summary: total=%s passed=%s failed=%s missing=%s empty=%s fail_signal_hits=%s missing_required_substrings=%s forbidden_substring_hits=%s ordered_substring_failures=%s seeded_defect_failures=%s false_positive_marker_failures=%s structured_json_assertion_failures=%s skills=%s\n' \
        "$total" "$passed" "$failed" "$missing" "$empty" "$signal_failures" "$missing_required_failures" "$forbidden_substring_failures" "$ordered_substring_failures" "$seeded_defect_failures" "$false_positive_marker_failures" "$structured_json_assertion_failures" "${#FIXTURE_FILES[@]}"

    [[ "$failed" -eq 0 ]]
}
