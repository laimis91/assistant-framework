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
    printf 'Summary: total=%s passed=%s failed=%s missing=%s empty=%s fail_signal_hits=%s missing_required_substrings=%s forbidden_substring_hits=%s skills=%s\n' \
        "$total" "$passed" "$failed" "$missing" "$empty" "$signal_failures" "$missing_required_failures" "$forbidden_substring_failures" "${#FIXTURE_FILES[@]}"

    [[ "$failed" -eq 0 ]]
}
