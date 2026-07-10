#!/usr/bin/env bash
# learning-controller.sh -- Learning controller gate helpers.

assistant_phase_learning_capture_mode() {
    local file="$1"
    local mode

    mode="$(assistant_phase_scalar_field "$file" "Learning capture mode" || true)"
    if [[ -z "$mode" ]]; then
        mode="$(assistant_phase_scalar_field "$file" "learning_capture_mode" || true)"
    fi
    printf '%s' "$mode" | tr '[:upper:]' '[:lower:]' | xargs 2>/dev/null || true
}

assistant_phase_has_lesson_bearing_evidence() {
    local file="$1"

    awk '
        function trim(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            return s
        }
        function absence_phrase(value, low) {
            low = tolower(trim(value))
            sub(/[.!]+$/, "", low)
            low = trim(low)
            return low ~ /^(none|n\/a|not[_ -]?applicable|not[_ -]?required|todo|tbd|placeholder|no corrections?|no changes?|none recorded)$/
        }
        function concrete(value) {
            value = trim(value)
            if (value == "" || value ~ /^\[[^]]+\]$/) {
                return 0
            }
            return !absence_phrase(value)
        }
        {
            line = $0
            low = tolower(line)

            if (low ~ /found( this round)?:/ &&
                (low ~ /[1-9][0-9]*[[:space:]]+must-fix/ || low ~ /[1-9][0-9]*[[:space:]]+should-fix/)) {
                found = 1
            }
            if (low ~ /^[[:space:]]*-[[:space:]]*result:[[:space:]]*fail([[:space:]]|$)/ ||
                low ~ /build:[[:space:]]*failed/ ||
                low ~ /tests?:[^\n]*[1-9][0-9]*[[:space:]]+failed/ ||
                low ~ /build[_ ]failures:[[:space:]]*[1-9][0-9]*/) {
                found = 1
            }
            if (low ~ /^[[:space:]]*[-*]?[[:space:]]*(user correction|user_correction|memory trend signal|memory_trend)[[:space:]]*:/) {
                value = line
                sub(/^[^:]*:[[:space:]]*/, "", value)
                if (concrete(value)) {
                    found = 1
                }
            }
        }
        END { exit found ? 0 : 1 }
    ' "$file" 2>/dev/null
}

assistant_phase_has_learning_controller() {
    local file="$1"
    grep -qE "^### Learning Controller[[:space:]]*$" "$file" 2>/dev/null
}

assistant_phase_learning_controller_block() {
    local file="$1"
    awk '
        /^### Learning Controller[[:space:]]*$/ {
            found = 1
            in_block = 1
            next
        }
        in_block && /^### / { exit }
        in_block { print }
        END { exit found ? 0 : 1 }
    ' "$file" 2>/dev/null
}

assistant_phase_has_learning_controller_after_line() {
    local file="$1"
    local minimum_line="$2"
    [[ -n "$minimum_line" ]] || return 1
    awk -v minimum_line="$minimum_line" '
        BEGIN { minimum_line += 0 }
        NR <= minimum_line { next }
        /^### Learning Controller[[:space:]]*$/ {
            found = 1
            exit
        }
        END { exit found ? 0 : 1 }
    ' "$file" 2>/dev/null
}

assistant_phase_learning_controller_block_after_line() {
    local file="$1"
    local minimum_line="$2"
    [[ -n "$minimum_line" ]] || return 1
    awk -v minimum_line="$minimum_line" '
        BEGIN { minimum_line += 0 }
        NR <= minimum_line { next }
        /^### Learning Controller[[:space:]]*$/ {
            found = 1
            in_block = 1
            next
        }
        in_block && /^### / { exit }
        in_block { print }
        END { exit found ? 0 : 1 }
    ' "$file" 2>/dev/null
}

assistant_phase_learning_field_value() {
    local block="$1"
    local label="$2"
    printf '%s\n' "$block" | awk -v label="$label" '
        BEGIN { wanted = tolower(label) ":" }
        {
            line = $0
            sub(/^[[:space:]]*[-*]?[[:space:]]*/, "", line)
            low = tolower(line)
            if (index(low, wanted) == 1) {
                sub(/^[^:]*:[[:space:]]*/, "", line)
                sub(/[[:space:]]*$/, "", line)
                print line
                exit
            }
        }
    '
}

assistant_phase_learning_evidence_item_is_valid() {
    local value="$1"
    local label item_value

    value="$(assistant_phase_trim_value "$value")"
    if [[ ! "$value" =~ ^([^:]+):[[:space:]]*(.*)$ ]]; then
        return 1
    fi

    label="$(assistant_phase_trim_value "${BASH_REMATCH[1]}")"
    label="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:space:]-]+/_/g')"
    case "$label" in
        none|review_finding|build_test_failure|user_correction|memory_trend) ;;
        *)
            return 1
            ;;
    esac

    item_value="$(assistant_phase_trim_value "${BASH_REMATCH[2]}")"
    ! assistant_phase_value_is_noneish "$item_value" && ! assistant_phase_value_is_bracket_placeholder "$item_value"
}

assistant_phase_learning_considered_item_is_valid() {
    local value="$1"
    local item_value

    value="$(assistant_phase_trim_value "$value")"
    if assistant_phase_value_is_noneish "$value" || assistant_phase_value_is_bracket_placeholder "$value"; then
        return 1
    fi

    if [[ "$value" =~ ^[^:]+:[[:space:]]*(.*)$ ]]; then
        item_value="$(assistant_phase_trim_value "${BASH_REMATCH[1]}")"
        ! assistant_phase_value_is_noneish "$item_value" && ! assistant_phase_value_is_bracket_placeholder "$item_value"
        return $?
    fi

    return 0
}

assistant_phase_learning_section_has_item() {
    local block="$1"
    local label="$2"
    local validator="${3:-learning_evidence}"
    local item
    local found=0
    local invalid=0

    while IFS= read -r item; do
        found=1
        case "$validator" in
            learning_evidence)
                assistant_phase_learning_evidence_item_is_valid "$item" || invalid=1
                ;;
            considered)
                assistant_phase_learning_considered_item_is_valid "$item" || invalid=1
                ;;
        esac
    done < <(
        printf '%s\n' "$block" | awk -v label="$label" '
            function is_learning_field(line, clean) {
                clean = line
                sub(/^[[:space:]]*[-*]?[[:space:]]*/, "", clean)
                return clean ~ /^(Memory trend checked|Learning evidence reviewed|Review findings considered|Build\/test failures considered|User corrections considered|Durable lesson decision|Persistence evidence|No-save rationale):/
            }
            BEGIN { wanted = tolower(label) ":" }
            {
                line = $0
                clean = line
                sub(/^[[:space:]]*[-*]?[[:space:]]*/, "", clean)
                if (index(tolower(clean), wanted) == 1) {
                    in_section = 1
                    next
                }
                if (in_section && is_learning_field($0)) {
                    exit
                }
                if (in_section && $0 ~ /^[[:space:]]+[-*][[:space:]]+/) {
                    item = $0
                    sub(/^[[:space:]]*[-*][[:space:]]+/, "", item)
                    sub(/[[:space:]]*$/, "", item)
                    print item
                }
            }
        '
    )

    [[ "$found" -eq 1 && "$invalid" -eq 0 ]]
}

assistant_phase_learning_missing_reason_key() {
    local file="$1"
    local status mode block trend decision persistence no_save_rationale
    local spec_pass_line quality_review_line final_result_line

    mode="$(assistant_phase_learning_capture_mode "$file")"

    # Journals created before learning_capture_mode existed keep the legacy
    # medium+ requirement. New journals use explicit adaptive semantics.
    if [[ -z "$mode" ]] && ! assistant_phase_is_medium_plus "$file"; then
        printf 'complete\n'
        return 0
    fi

    if [[ "$mode" == "not_required" ]]; then
        printf 'complete\n'
        return 0
    fi

    if [[ "$mode" == "auto" ]] && ! assistant_phase_has_lesson_bearing_evidence "$file"; then
        printf 'complete\n'
        return 0
    fi

    status="$(assistant_phase_status "$file" || true)"
    if [[ "$status" != *"DOCUMENTING"* ]]; then
        printf 'complete\n'
        return 0
    fi

    spec_pass_line="$(assistant_phase_latest_spec_review_pass_line "$file" || true)"
    if [[ -n "$spec_pass_line" ]]; then
        quality_review_line="$(assistant_phase_quality_review_after_line "$file" "$spec_pass_line" || true)"
        if [[ -n "$quality_review_line" ]]; then
            final_result_line="$(assistant_phase_final_result_heading_line_after_line "$file" "$quality_review_line" || true)"
        fi
    fi

    if [[ -n "$final_result_line" ]]; then
        if ! assistant_phase_has_learning_controller_after_line "$file" "$final_result_line"; then
            printf 'no_learning_controller\n'
            return 0
        fi
        block="$(assistant_phase_learning_controller_block_after_line "$file" "$final_result_line" || true)"
    else
        if ! assistant_phase_has_learning_controller "$file"; then
            printf 'no_learning_controller\n'
            return 0
        fi
        block="$(assistant_phase_learning_controller_block "$file" || true)"
    fi

    trend="$(assistant_phase_trim_value "$(assistant_phase_learning_field_value "$block" "Memory trend checked")")"
    case "$trend" in
        checked|backend_unavailable|policy_disallowed|not_configured) ;;
        *)
            printf 'missing_memory_trend_checked\n'
            return 0
            ;;
    esac

    if ! assistant_phase_learning_section_has_item "$block" "Learning evidence reviewed" "learning_evidence"; then
        printf 'missing_learning_evidence_reviewed\n'
        return 0
    fi

    if ! assistant_phase_learning_section_has_item "$block" "Review findings considered" "considered"; then
        printf 'missing_review_findings_considered\n'
        return 0
    fi

    if ! assistant_phase_learning_section_has_item "$block" "Build/test failures considered" "considered"; then
        printf 'missing_build_test_failures_considered\n'
        return 0
    fi

    if ! assistant_phase_learning_section_has_item "$block" "User corrections considered" "considered"; then
        printf 'missing_user_corrections_considered\n'
        return 0
    fi

    decision="$(assistant_phase_trim_value "$(assistant_phase_learning_field_value "$block" "Durable lesson decision")")"
    case "$decision" in
        durable_saved|durable_updated|skipped_not_durable|backend_unavailable|policy_disallowed|refused_sensitive) ;;
        *)
            printf 'missing_durable_lesson_decision\n'
            return 0
            ;;
    esac

    persistence="$(assistant_phase_trim_value "$(assistant_phase_learning_field_value "$block" "Persistence evidence")")"
    if [[ -z "$persistence" ]]; then
        printf 'missing_persistence_evidence\n'
        return 0
    fi

    case "$decision" in
        durable_saved|durable_updated)
            if assistant_phase_value_is_noneish "$persistence" || assistant_phase_value_is_bracket_placeholder "$persistence"; then
                printf 'missing_persistence_evidence\n'
                return 0
            fi
            ;;
        skipped_not_durable|backend_unavailable|policy_disallowed|refused_sensitive)
            no_save_rationale="$(assistant_phase_trim_value "$(assistant_phase_learning_field_value "$block" "No-save rationale")")"
            if assistant_phase_value_is_noneish "$no_save_rationale" || assistant_phase_value_is_bracket_placeholder "$no_save_rationale"; then
                printf 'missing_no_save_rationale\n'
                return 0
            fi
            ;;
    esac

    printf 'complete\n'
}
