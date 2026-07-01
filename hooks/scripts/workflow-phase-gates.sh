#!/usr/bin/env bash
# workflow-phase-gates.sh — Shared task-journal phase gate helpers.
#
# Callers are responsible for resolving the active task journal first. In
# particular, completed-journal suppression remains owned by
# task-journal-resolver.sh so these helpers do not accidentally revive stale
# workflow state.

assistant_phase_scalar_field() {
    local file="$1"
    local label="$2"
    awk -v label="$label" '
        $0 ~ "^(#+[[:space:]]*)?" label ":" {
            sub("^(#+[[:space:]]*)?" label ":[[:space:]]*", "", $0)
            print
            exit
        }
    ' "$file" 2>/dev/null
}

assistant_phase_status() {
    assistant_phase_scalar_field "$1" "Status"
}

assistant_phase_is_medium_plus() {
    local file="$1"
    grep -qE "^(#+[[:space:]]*)?Triaged as:[[:space:]]*(medium|large|mega)([[:space:]]|$)" "$file" 2>/dev/null
}

assistant_phase_status_is_lifecycle_active() {
    local status="$1"
    [[ "$status" == *"BUILDING"* || "$status" == *"VERIFYING"* || "$status" == *"REVIEWING"* || "$status" == *"DOCUMENTING"* ]]
}

assistant_phase_has_plan_approval() {
    local file="$1"
    grep -qE "(^Plan approval:.*yes|PLAN COMPLETE \(approved\))" "$file" 2>/dev/null
}

assistant_phase_has_spec_review_entry() {
    local file="$1"
    grep -qE "^### Spec Review #[0-9]+" "$file" 2>/dev/null
}

assistant_phase_latest_spec_review_pass_line() {
    local file="$1"
    awk '
        function finish_spec() {
            active_field = ""
            latest_pass = current_pass && current_scope_reviewed && resolved["Missing acceptance criteria"] && resolved["Extra scope"] && resolved["Changed files mismatch"] && resolved["Verification evidence mismatch"] && resolved["Required fixes"]
            if (latest_pass) {
                latest_pass_line = current_spec_line
            } else {
                latest_pass_line = ""
            }
        }
        function field_value(line, prefix, value) {
            value = line
            sub("^[[:space:]]*-[[:space:]]" prefix ":[[:space:]]*", "", value)
            sub(/[[:space:]]*$/, "", value)
            return value
        }
        function resolved_value(value) {
            return value == "" || value == "none" || value == "None" || value == "NONE" || value == "[]"
        }
        function start_resolution_field(line, prefix, value) {
            value = field_value(line, prefix)
            resolved[prefix] = resolved_value(value)
            active_field = prefix
        }
        /^### Spec Review #[0-9]+/ {
            if (in_spec) {
                finish_spec()
            }
            seen = 1
            in_spec = 1
            current_spec_line = NR
            current_pass = 0
            current_scope_reviewed = 0
            active_field = ""
            resolved["Missing acceptance criteria"] = 0
            resolved["Extra scope"] = 0
            resolved["Changed files mismatch"] = 0
            resolved["Verification evidence mismatch"] = 0
            resolved["Required fixes"] = 0
            next
        }
        /^### / && in_spec {
            finish_spec()
            in_spec = 0
            next
        }
        in_spec && /^-[[:space:]][^:]+:/ {
            active_field = ""
        }
        in_spec && active_field != "" && $0 !~ /^[[:space:]]*$/ {
            resolved[active_field] = 0
            active_field = ""
        }
        in_spec && /^[[:space:]]*-[[:space:]]Result:[[:space:]]PASS[[:space:]]*$/ {
            current_pass = 1
        }
        in_spec && /^[[:space:]]*-[[:space:]]Scope reviewed:/ {
            current_scope_reviewed = 1
        }
        in_spec && /^-[[:space:]]Missing acceptance criteria:/ {
            start_resolution_field($0, "Missing acceptance criteria")
        }
        in_spec && /^-[[:space:]]Extra scope:/ {
            start_resolution_field($0, "Extra scope")
        }
        in_spec && /^-[[:space:]]Changed files mismatch:/ {
            start_resolution_field($0, "Changed files mismatch")
        }
        in_spec && /^-[[:space:]]Verification evidence mismatch:/ {
            start_resolution_field($0, "Verification evidence mismatch")
        }
        in_spec && /^-[[:space:]]Required fixes:/ {
            start_resolution_field($0, "Required fixes")
        }
        END {
            if (in_spec) {
                finish_spec()
            }
            if (seen && latest_pass_line != "") {
                print latest_pass_line
                exit 0
            }
            exit 1
        }
    ' "$file" 2>/dev/null
}

assistant_phase_quality_review_after_line() {
    local file="$1"
    local spec_pass_line="$2"
    [[ -n "$spec_pass_line" ]] || return 1
    awk -v spec_pass_line="$spec_pass_line" '
        BEGIN {
            spec_pass_line += 0
        }
        spec_pass_line > 0 && NR > spec_pass_line && /^### Quality Review #[0-9]+/ {
            latest = NR
            found = 1
        }
        END {
            if (found) {
                print latest
            }
            exit found ? 0 : 1
        }
    ' "$file" 2>/dev/null
}

assistant_phase_final_result_after_line() {
    local file="$1"
    local quality_review_line="$2"
    [[ -n "$quality_review_line" ]] || return 1
    awk -v quality_review_line="$quality_review_line" '
        BEGIN {
            quality_review_line += 0
        }
        quality_review_line > 0 && NR > quality_review_line && /^[[:space:]]*-[[:space:]]Result:[[:space:]](CLEAN|ISSUES_FIXED|HAS_REMAINING_ITEMS)[[:space:]]*$/ {
            found = 1
            exit
        }
        END {
            exit found ? 0 : 1
        }
    ' "$file" 2>/dev/null
}

assistant_phase_review_block_after_line() {
    local file="$1"
    local start_line="$2"
    [[ -n "$start_line" ]] || return 1
    awk -v start_line="$start_line" '
        BEGIN { start_line += 0 }
        NR == start_line { in_block = 1; next }
        in_block && /^### / { exit }
        in_block { print }
    ' "$file" 2>/dev/null
}

assistant_phase_final_result_block_after_line() {
    local file="$1"
    local quality_review_line="$2"
    [[ -n "$quality_review_line" ]] || return 1
    awk -v quality_review_line="$quality_review_line" '
        BEGIN { quality_review_line += 0 }
        NR <= quality_review_line { next }
        tolower($0) ~ /^### final result/ { in_final = 1; next }
        in_final && /^### / { exit }
        in_final { print }
    ' "$file" 2>/dev/null
}

assistant_phase_final_result_heading_line_after_line() {
    local file="$1"
    local quality_review_line="$2"
    [[ -n "$quality_review_line" ]] || return 1
    awk -v quality_review_line="$quality_review_line" '
        BEGIN { quality_review_line += 0 }
        NR <= quality_review_line { next }
        tolower($0) ~ /^### final result/ {
            print NR
            found = 1
            exit
        }
        END { exit found ? 0 : 1 }
    ' "$file" 2>/dev/null
}

assistant_phase_quality_review_heading_round() {
    local file="$1"
    local quality_review_line="$2"
    [[ -n "$quality_review_line" ]] || return 1
    awk -v quality_review_line="$quality_review_line" '
        BEGIN { quality_review_line += 0 }
        NR == quality_review_line && /^### Quality Review #[0-9]+/ {
            sub(/^### Quality Review #/, "", $0)
            print $0 + 0
            found = 1
        }
        END { exit found ? 0 : 1 }
    ' "$file" 2>/dev/null
}

assistant_phase_previous_quality_review_line_before_line() {
    local file="$1"
    local quality_review_line="$2"
    local minimum_line="${3:-0}"
    [[ -n "$quality_review_line" ]] || return 1
    awk -v quality_review_line="$quality_review_line" -v minimum_line="$minimum_line" '
        BEGIN {
            quality_review_line += 0
            minimum_line += 0
        }
        NR > minimum_line && NR < quality_review_line && /^### Quality Review #[0-9]+/ {
            latest = NR
            found = 1
        }
        END {
            if (found) {
                print latest
            }
            exit found ? 0 : 1
        }
    ' "$file" 2>/dev/null
}

assistant_phase_quality_review_lines_after_line_until_line() {
    local file="$1"
    local minimum_line="$2"
    local maximum_line="$3"
    [[ -n "$minimum_line" && -n "$maximum_line" ]] || return 1
    awk -v minimum_line="$minimum_line" -v maximum_line="$maximum_line" '
        BEGIN {
            minimum_line += 0
            maximum_line += 0
        }
        NR > minimum_line && NR <= maximum_line && /^### Quality Review #[0-9]+/ {
            print NR
            found = 1
        }
        END { exit found ? 0 : 1 }
    ' "$file" 2>/dev/null
}

assistant_phase_quality_review_observed_weighted_sequence() {
    local file="$1"
    local minimum_line="$2"
    local maximum_line="$3"
    local expected_round_count="$4"
    local review_line heading_round block weighted findings
    local expected_round=1
    local found=0
    local sequence=""

    while IFS= read -r review_line; do
        [[ -n "$review_line" ]] || continue
        found=1

        heading_round="$(assistant_phase_quality_review_heading_round "$file" "$review_line" || true)"
        if [[ -z "$heading_round" || "$heading_round" -ne "$expected_round" ]]; then
            return 1
        fi

        block="$(assistant_phase_review_block_after_line "$file" "$review_line" || true)"
        weighted="$(assistant_phase_review_weighted_from_block "$block" || true)"
        findings="$(assistant_phase_review_findings_count_from_block "$block" || true)"
        if [[ -z "$weighted" || -z "$findings" ]]; then
            return 1
        fi

        if [[ -z "$sequence" ]]; then
            sequence="$weighted"
        else
            sequence="${sequence}->${weighted}"
        fi
        expected_round=$((expected_round + 1))
    done < <(assistant_phase_quality_review_lines_after_line_until_line "$file" "$minimum_line" "$maximum_line" || true)

    [[ "$found" -eq 1 ]] || return 1
    [[ $((expected_round - 1)) -eq "$expected_round_count" ]] || return 1
    printf '%s\n' "$sequence"
}

assistant_phase_value_is_noneish() {
    local value="$1"
    value="$(printf '%s' "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -z "$value" ]] && return 0
    [[ "$value" =~ ^(\[\]|\.\.\.|placeholder|PLACEHOLDER|none|None|NONE|n/a|N/A|not_applicable|not[[:space:]]applicable|missing|todo|TODO|tbd|TBD)([[:space:]]|$) ]]
}

assistant_phase_value_is_bracket_placeholder() {
    local value="$1"
    value="$(assistant_phase_trim_value "$value")"
    [[ -n "$value" ]] || return 1
    awk -v value="$value" '
        BEGIN {
            offset = 1
            while (match(substr(value, offset), /\[[^][]+\]/)) {
                close_index = offset + RSTART + RLENGTH - 2
                after = substr(value, close_index + 1, 1)
                if (after != "(") {
                    exit 0
                }
                offset = close_index + 2
            }
            exit 1
        }
    '
}

assistant_phase_trim_value() {
    printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

assistant_phase_value_after_colon() {
    local line="$1"
    line="${line#*:}"
    assistant_phase_trim_value "$line"
}

assistant_phase_unsigned_decimal_is_valid() {
    local value="$1"
    value="$(assistant_phase_trim_value "$value")"
    [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

assistant_phase_signed_decimal_is_valid() {
    local value="$1"
    value="$(assistant_phase_trim_value "$value")"
    [[ "$value" =~ ^[+-]?[0-9]+([.][0-9]+)?$ ]]
}

assistant_phase_decimal_in_range() {
    local value="$1"
    local minimum="$2"
    local maximum="$3"

    assistant_phase_unsigned_decimal_is_valid "$value" || return 1
    awk -v value="$value" -v minimum="$minimum" -v maximum="$maximum" '
        BEGIN { exit (value >= minimum && value <= maximum ? 0 : 1) }
    '
}

assistant_phase_rubric_score_values() {
    local line="$1"
    local rubric

    rubric="$(assistant_phase_value_after_colon "$line")"
    [[ -n "$rubric" ]] || return 1

    awk -v rubric="$rubric" '
        function trim(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            gsub(/^[,;]+/, "", s)
            gsub(/[,;]+$/, "", s)
            return s
        }
        function score_is_valid(score) {
            score = trim(score)
            return score ~ /^[0-9]+([.][0-9]+)?$/ && score >= 0 && score <= 5
        }
        function mark_dimension(key, score) {
            key = tolower(trim(key))
            if (!score_is_valid(score)) {
                return
            }
            score = trim(score)
            if (key == "correctness") {
                correctness_score = score
                correctness = 1
            } else if (key == "code_quality" || key == "quality") {
                quality_score = score
                quality = 1
            } else if (key == "architecture") {
                architecture_score = score
                architecture = 1
            } else if (key == "security") {
                security_score = score
                security = 1
            } else if (key == "test_coverage" || key == "coverage") {
                coverage_score = score
                coverage = 1
            }
        }
        BEGIN {
            gsub(/[,;]/, " ", rubric)
            count = split(rubric, tokens, /[[:space:]]+/)
            for (i = 1; i <= count; i++) {
                token = trim(tokens[i])
                if (token == "" || token == "=" || token == ":") {
                    continue
                }

                if (token ~ /^[[:alpha:]_][[:alnum:]_]*[=:][0-9]+([.][0-9]+)?$/) {
                    split(token, pair, /[=:]/)
                    mark_dimension(pair[1], pair[2])
                    continue
                }

                if (token ~ /^[[:alpha:]_][[:alnum:]_]*[=:]$/) {
                    key = substr(token, 1, length(token) - 1)
                    if (i < count) {
                        i++
                        mark_dimension(key, tokens[i])
                    }
                    continue
                }

                if (token ~ /^[[:alpha:]_][[:alnum:]_]*$/) {
                    next_index = i + 1
                    if (next_index <= count && (tokens[next_index] == "=" || tokens[next_index] == ":")) {
                        next_index++
                    }
                    if (next_index <= count) {
                        mark_dimension(token, tokens[next_index])
                        i = next_index
                    }
                }
            }

            if (correctness && quality && architecture && security && coverage) {
                printf "%s\t%s\t%s\t%s\t%s\n", correctness_score, quality_score, architecture_score, security_score, coverage_score
                exit 0
            }
            exit 1
        }
    '
}

assistant_phase_rubric_scores_are_valid() {
    assistant_phase_rubric_score_values "$1" >/dev/null
}

assistant_phase_rubric_weighted_score_matches() {
    local rubric_line="$1"
    local weighted="$2"
    local scores

    scores="$(assistant_phase_rubric_score_values "$rubric_line")" || return 1
    assistant_phase_decimal_in_range "$weighted" "0" "5" || return 1

    awk -v scores="$scores" -v weighted="$weighted" '
        BEGIN {
            count = split(scores, parts, /\t/)
            if (count != 5) {
                exit 1
            }
            expected = (parts[1] * 0.30) + (parts[2] * 0.20) + (parts[3] * 0.20) + (parts[4] * 0.15) + (parts[5] * 0.15)
            diff = weighted - expected
            if (diff < 0) {
                diff = -diff
            }
            exit (diff <= 0.0051 ? 0 : 1)
        }
    '
}

assistant_phase_review_weighted_from_block() {
    local block="$1"
    local weighted_line weighted

    weighted_line="$(printf '%s\n' "$block" | grep -E "^[[:space:]]*-[[:space:]]Weighted:" | tail -1 || true)"
    weighted="$(assistant_phase_value_after_colon "$weighted_line")"
    if [[ -n "$weighted_line" ]] && assistant_phase_decimal_in_range "$weighted" "0" "5"; then
        printf '%s\n' "$weighted"
        return 0
    fi

    return 1
}

assistant_phase_review_findings_count_from_block() {
    local block="$1"
    local findings_line must_fix should_fix

    findings_line="$(printf '%s\n' "$block" | grep -m1 -Ei "^[[:space:]]*-[[:space:]]Found([[:space:]]this[[:space:]]round)?:" || true)"
    if [[ "$findings_line" =~ ([0-9]+)[[:space:]]+must-fix ]]; then
        must_fix="${BASH_REMATCH[1]}"
    else
        return 1
    fi
    if [[ "$findings_line" =~ ([0-9]+)[[:space:]]+should-fix ]]; then
        should_fix="${BASH_REMATCH[1]}"
    else
        return 1
    fi

    printf '%d\n' "$((must_fix + should_fix))"
}

assistant_phase_score_progression_is_valid() {
    local value="$1"
    local latest_weighted="${2:-}"
    local round="${3:-1}"

    value="$(assistant_phase_trim_value "$value")"
    latest_weighted="$(assistant_phase_trim_value "$latest_weighted")"
    value="${value//→/->}"

    awk -v value="$value" -v latest_weighted="$latest_weighted" -v round="$round" '
        function trim(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            return s
        }
        function decimal_is_valid(s) {
            return s ~ /^[0-9]+([.][0-9]+)?$/
        }
        BEGIN {
            value = trim(value)
            latest_weighted = trim(latest_weighted)
            round += 0
            if (value == "" || round < 1 || !decimal_is_valid(latest_weighted) || latest_weighted < 0 || latest_weighted > 5) {
                exit 1
            }

            count = split(value, scores, /[[:space:]]*->[[:space:]]*/)
            if (count < 1 || (round > 1 && count < round)) {
                exit 1
            }

            for (i = 1; i <= count; i++) {
                score = trim(scores[i])
                if (!decimal_is_valid(score) || score < 0 || score > 5) {
                    exit 1
                }
                final_score = score
            }

            exit ((final_score + 0) == (latest_weighted + 0) ? 0 : 1)
        }
    '
}

assistant_phase_score_progression_previous_score() {
    local value="$1"

    value="$(assistant_phase_trim_value "$value")"
    value="${value//→/->}"

    awk -v value="$value" '
        function trim(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            return s
        }
        function decimal_is_valid(s) {
            return s ~ /^[0-9]+([.][0-9]+)?$/
        }
        BEGIN {
            count = split(value, scores, /[[:space:]]*->[[:space:]]*/)
            if (count < 2) {
                exit 1
            }
            previous = trim(scores[count - 1])
            if (!decimal_is_valid(previous) || previous < 0 || previous > 5) {
                exit 1
            }
            print previous
        }
    '
}

assistant_phase_score_progression_matches_observed_sequence() {
    local value="$1"
    local observed_sequence="$2"

    value="$(assistant_phase_trim_value "$value")"
    value="${value//→/->}"
    observed_sequence="$(assistant_phase_trim_value "$observed_sequence")"
    observed_sequence="${observed_sequence//→/->}"

    awk -v value="$value" -v observed_sequence="$observed_sequence" '
        function trim(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            return s
        }
        function decimal_is_valid(s) {
            return s ~ /^[0-9]+([.][0-9]+)?$/
        }
        BEGIN {
            value = trim(value)
            observed_sequence = trim(observed_sequence)
            if (value == "" || observed_sequence == "") {
                exit 1
            }

            progression_count = split(value, progression, /[[:space:]]*->[[:space:]]*/)
            observed_count = split(observed_sequence, observed, /[[:space:]]*->[[:space:]]*/)
            if (progression_count != observed_count) {
                exit 1
            }

            for (i = 1; i <= observed_count; i++) {
                score = trim(progression[i])
                expected = trim(observed[i])
                if (!decimal_is_valid(score) || !decimal_is_valid(expected) || score + 0 != expected + 0) {
                    exit 1
                }
            }

            exit 0
        }
    '
}

assistant_phase_delta_matches_scores() {
    local declared_delta="$1"
    local previous_score="$2"
    local latest_score="$3"

    assistant_phase_signed_decimal_is_valid "$declared_delta" || return 1
    assistant_phase_decimal_in_range "$previous_score" "0" "5" || return 1
    assistant_phase_decimal_in_range "$latest_score" "0" "5" || return 1

    awk -v declared_delta="$declared_delta" -v previous_score="$previous_score" -v latest_score="$latest_score" '
        BEGIN {
            expected = latest_score - previous_score
            diff = declared_delta - expected
            if (diff < 0) {
                diff = -diff
            }
            exit (diff < 0.005 ? 0 : 1)
        }
    '
}

assistant_phase_drift_check_is_valid() {
    local value="$1"

    value="$(assistant_phase_trim_value "$value")"
    if assistant_phase_value_is_noneish "$value"; then
        return 1
    fi

    [[ "$value" =~ ^(GENUINE|SUSPICIOUS|DRIFT|REGRESSION|STAGNATION|NEUTRAL)([[:space:]]+.*)?$ ]]
}

assistant_phase_drift_check_matches_movement() {
    local value="$1"
    local delta="$2"
    local previous_findings="$3"
    local current_findings="$4"
    local drift

    value="$(assistant_phase_trim_value "$value")"
    drift="${value%% *}"
    assistant_phase_drift_check_is_valid "$value" || return 1

    awk -v drift="$drift" -v delta="$delta" -v previous_findings="$previous_findings" -v current_findings="$current_findings" '
        BEGIN {
            d = delta + 0
            current = current_findings + 0
            previous_known = previous_findings ~ /^[0-9]+$/
            epsilon = 0.005

            if (d < -epsilon) {
                exit (drift == "REGRESSION" ? 0 : 1)
            }
            if (d > 1.0) {
                exit (drift == "SUSPICIOUS" ? 0 : 1)
            }
            if (d > epsilon) {
                if (!previous_known) {
                    exit 0
                }
                if (current < (previous_findings + 0)) {
                    exit (drift == "GENUINE" ? 0 : 1)
                }
                exit (drift == "DRIFT" ? 0 : 1)
            }
            if (d >= -epsilon && d <= epsilon) {
                if (current > 0) {
                    exit ((drift == "NEUTRAL" || drift == "STAGNATION") ? 0 : 1)
                }
                exit 0
            }

            exit 0
        }
    '
}

assistant_phase_final_result_has_remaining_rationale() {
    local final_block="$1"
    local line value

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]](Remaining[[:space:]]items|Blocker):[[:space:]]*(.*)$ ]]; then
            value="${BASH_REMATCH[2]}"
            if ! assistant_phase_value_is_noneish "$value" && ! assistant_phase_value_is_bracket_placeholder "$value"; then
                return 0
            fi
        fi
    done <<< "$final_block"

    return 1
}

assistant_phase_review_controller_missing_reason_key() {
    local file="$1"
    local quality_review_line="$2"
    local minimum_review_line="${3:-0}"
    local quality_block final_block round_line findings_line rubric_line weighted_line delta_line drift_line score_progression_line
    local round max_round heading_round must_fix should_fix current_findings weighted delta drift_value score_progression final_result_line final_result score_x100
    local previous_quality_review_line previous_quality_block previous_weighted previous_findings previous_score observed_weighted_sequence

    quality_block="$(assistant_phase_review_block_after_line "$file" "$quality_review_line" || true)"
    final_block="$(assistant_phase_final_result_block_after_line "$file" "$quality_review_line" || true)"

    round_line="$(printf '%s\n' "$quality_block" | grep -m1 -E "^[[:space:]]*-[[:space:]]Round:" || true)"
    if [[ ! "$round_line" =~ Round:[[:space:]]*([0-9]+)[[:space:]]+of[[:space:]]+([0-9]+) ]]; then
        printf 'missing_review_round\n'
        return 0
    fi
    round="${BASH_REMATCH[1]}"
    max_round="${BASH_REMATCH[2]}"
    if [[ "$max_round" -ne 10 || "$round" -lt 1 || "$round" -gt 10 ]]; then
        printf 'round_overflow\n'
        return 0
    fi
    heading_round="$(assistant_phase_quality_review_heading_round "$file" "$quality_review_line" || true)"
    if [[ -z "$heading_round" || "$heading_round" -ne "$round" ]]; then
        printf 'round_overflow\n'
        return 0
    fi

    findings_line="$(printf '%s\n' "$quality_block" | grep -m1 -Ei "^[[:space:]]*-[[:space:]]Found([[:space:]]this[[:space:]]round)?:" || true)"
    if [[ -z "$findings_line" ]]; then
        printf 'missing_findings_summary\n'
        return 0
    fi
    if [[ "$findings_line" =~ ([0-9]+)[[:space:]]+must-fix ]]; then
        must_fix="${BASH_REMATCH[1]}"
    else
        printf 'missing_findings_summary\n'
        return 0
    fi
    if [[ "$findings_line" =~ ([0-9]+)[[:space:]]+should-fix ]]; then
        should_fix="${BASH_REMATCH[1]}"
    else
        printf 'missing_findings_summary\n'
        return 0
    fi
    current_findings="$((must_fix + should_fix))"

    rubric_line="$(printf '%s\n' "$quality_block" | grep -E "^[[:space:]]*-[[:space:]]Rubric:" | tail -1 || true)"
    if [[ -z "$rubric_line" ]] || ! assistant_phase_rubric_scores_are_valid "$rubric_line"; then
        printf 'missing_rubric_scores\n'
        return 0
    fi

    weighted_line="$(printf '%s\n' "$quality_block" | grep -E "^[[:space:]]*-[[:space:]]Weighted:" | tail -1 || true)"
    weighted="$(assistant_phase_value_after_colon "$weighted_line")"
    if [[ -z "$weighted_line" ]] || ! assistant_phase_decimal_in_range "$weighted" "0" "5" \
        || ! assistant_phase_rubric_weighted_score_matches "$rubric_line" "$weighted"; then
        printf 'missing_weighted_score\n'
        return 0
    fi

    if [[ "$round" -gt 1 ]]; then
        delta_line="$(printf '%s\n' "$quality_block" | grep -m1 -E "^[[:space:]]*-[[:space:]]Delta from previous:" || true)"
        delta="$(assistant_phase_value_after_colon "$delta_line")"
        if [[ -z "$delta_line" ]] || ! assistant_phase_signed_decimal_is_valid "$delta"; then
            printf 'missing_delta_from_previous\n'
            return 0
        fi
        drift_line="$(printf '%s\n' "$quality_block" | grep -m1 -E "^[[:space:]]*-[[:space:]]Drift check:" || true)"
        drift_value="$(assistant_phase_value_after_colon "$drift_line")"
        if [[ -z "$drift_line" ]] || ! assistant_phase_drift_check_is_valid "$drift_value"; then
            printf 'missing_drift_check\n'
            return 0
        fi
    fi

    final_result_line="$(printf '%s\n' "$final_block" | grep -m1 -E "^[[:space:]]*-[[:space:]]Result:[[:space:]]*(CLEAN|ISSUES_FIXED|HAS_REMAINING_ITEMS)[[:space:]]*$" || true)"
    if [[ ! "$final_result_line" =~ Result:[[:space:]]*(CLEAN|ISSUES_FIXED|HAS_REMAINING_ITEMS)[[:space:]]*$ ]]; then
        printf 'no_final_result\n'
        return 0
    fi
    final_result="${BASH_REMATCH[1]}"

    score_progression_line="$(printf '%s\n' "$final_block" | grep -m1 -E "^[[:space:]]*-[[:space:]]Score progression:" || true)"
    score_progression="$(assistant_phase_value_after_colon "$score_progression_line")"
    if [[ -z "$score_progression_line" ]] || ! assistant_phase_score_progression_is_valid "$score_progression" "$weighted" "$round"; then
        printf 'missing_score_progression\n'
        return 0
    fi

    if ! observed_weighted_sequence="$(assistant_phase_quality_review_observed_weighted_sequence "$file" "$minimum_review_line" "$quality_review_line" "$round")"; then
        if [[ "$round" -gt 1 ]]; then
            printf 'missing_delta_from_previous\n'
        else
            printf 'missing_score_progression\n'
        fi
        return 0
    fi

    if ! assistant_phase_score_progression_matches_observed_sequence "$score_progression" "$observed_weighted_sequence"; then
        printf 'missing_score_progression\n'
        return 0
    fi

    if [[ "$round" -gt 1 ]]; then
        previous_quality_review_line="$(assistant_phase_previous_quality_review_line_before_line "$file" "$quality_review_line" "$minimum_review_line" || true)"
        if [[ -z "$previous_quality_review_line" ]]; then
            printf 'missing_delta_from_previous\n'
            return 0
        fi
        previous_quality_block="$(assistant_phase_review_block_after_line "$file" "$previous_quality_review_line" || true)"
        previous_weighted="$(assistant_phase_review_weighted_from_block "$previous_quality_block" || true)"
        previous_findings="$(assistant_phase_review_findings_count_from_block "$previous_quality_block" || true)"
        if [[ -z "$previous_weighted" || -z "$previous_findings" ]]; then
            printf 'missing_delta_from_previous\n'
            return 0
        fi
        previous_score="$previous_weighted"
        if [[ -z "$previous_score" ]] || ! assistant_phase_delta_matches_scores "$delta" "$previous_score" "$weighted"; then
            printf 'missing_delta_from_previous\n'
            return 0
        fi
        if ! assistant_phase_drift_check_matches_movement "$drift_value" "$delta" "$previous_findings" "$current_findings"; then
            printf 'missing_drift_check\n'
            return 0
        fi
    fi

    if [[ "$final_result" == "CLEAN" || "$final_result" == "ISSUES_FIXED" ]]; then
        score_x100="$(awk -v score="$weighted" 'BEGIN { printf "%d", score * 100 }')"
        if [[ "$score_x100" -lt 400 ]]; then
            printf 'weighted_score_below_pass\n'
            return 0
        fi
        if [[ "$must_fix" -ne 0 || "$should_fix" -ne 0 ]]; then
            printf 'unresolved_findings\n'
            return 0
        fi
    elif [[ "$final_result" == "HAS_REMAINING_ITEMS" ]]; then
        if ! assistant_phase_final_result_has_remaining_rationale "$final_block"; then
            printf 'missing_remaining_rationale\n'
            return 0
        fi
    fi

    printf 'complete\n'
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
    local status block trend decision persistence no_save_rationale
    local spec_pass_line quality_review_line final_result_line

    if ! assistant_phase_is_medium_plus "$file"; then
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

assistant_phase_review_complete() {
    local file="$1"
    [[ "$(assistant_phase_review_missing_reason_key "$file")" == "complete" ]]
}

assistant_phase_review_missing_reason_key() {
    local file="$1"
    local spec_pass_line
    local quality_review_line

    if ! assistant_phase_has_spec_review_entry "$file"; then
        printf 'no_spec_review\n'
        return 0
    fi

    spec_pass_line="$(assistant_phase_latest_spec_review_pass_line "$file" || true)"
    if [[ -z "$spec_pass_line" ]]; then
        printf 'spec_not_pass\n'
        return 0
    fi

    quality_review_line="$(assistant_phase_quality_review_after_line "$file" "$spec_pass_line" || true)"
    if [[ -z "$quality_review_line" ]]; then
        printf 'no_quality_review\n'
        return 0
    fi

    if assistant_phase_is_medium_plus "$file"; then
        assistant_phase_review_controller_missing_reason_key "$file" "$quality_review_line" "$spec_pass_line"
        return 0
    fi

    if ! assistant_phase_final_result_after_line "$file" "$quality_review_line" >/dev/null; then
        printf 'no_final_result\n'
        return 0
    fi

    printf 'complete\n'
}

assistant_phase_agent_home() {
    if [[ -n "${CODEX_PROJECT_DIR:-}" ]]; then
        printf '%s/.codex\n' "$HOME"
    elif [[ -n "${GEMINI_PROJECT_DIR:-}" ]]; then
        printf '%s/.gemini\n' "$HOME"
    else
        printf '%s/.claude\n' "$HOME"
    fi
}

assistant_phase_metrics_file() {
    printf '%s/memory/metrics/workflow-metrics.jsonl\n' "$(assistant_phase_agent_home)"
}

assistant_phase_has_metrics_today() {
    local metrics_file
    local today
    metrics_file="$(assistant_phase_metrics_file)"
    today="$(date +%Y-%m-%d)"

    [[ -f "$metrics_file" ]] || return 1
    grep -q "\"date\":\"$today\"" "$metrics_file" 2>/dev/null
}

assistant_phase_subagent_mode() {
    assistant_phase_scalar_field "$1" "Subagent execution mode"
}

assistant_phase_subagent_policy_state() {
    assistant_phase_scalar_field "$1" "Subagent policy state"
}

assistant_phase_labeled_evidence_value() {
    local file="$1"
    local label="$2"
    awk -v label="$label" '
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
    ' "$file" 2>/dev/null
}

assistant_phase_has_labeled_evidence() {
    local file="$1"
    local label="$2"
    local value
    value="$(assistant_phase_labeled_evidence_value "$file" "$label")"

    [[ -n "$value" ]] || return 1
    [[ ! "$value" =~ ^(\[.*\]|none|None|NONE|n/a|N/A|missing|todo|TODO|tbd|TBD)$ ]]
}

assistant_phase_is_codex_task() {
    local file="$1"
    [[ "$file" == */.codex/task.md || "$file" == .codex/task.md ]]
}

assistant_phase_subagent_events_file() {
    local file="$1"
    printf '%s/subagent-events.jsonl\n' "$(dirname "$file")"
}

assistant_phase_role_agent_pattern() {
    case "$1" in
        "Code Mapper") printf 'code-mapper|codemapper|Code Mapper' ;;
        "Explorer") printf 'explorer|Explorer' ;;
        "Architect") printf 'architect|Architect' ;;
        "Code Writer") printf 'code-writer|codewriter|Code Writer' ;;
        "Builder/Tester") printf 'builder-tester|builder/tester|Builder/Tester' ;;
        "Reviewer") printf 'reviewer|Reviewer' ;;
        *) printf '%s' "$1" ;;
    esac
}

assistant_phase_json_field_value() {
    local json_line="$1"
    local field="$2"
    printf '%s\n' "$json_line" | sed -n 's/.*"'"$field"'":"\([^"]*\)".*/\1/p'
}

assistant_phase_event_role_matches() {
    local json_line="$1"
    local role="$2"
    local pattern name agent_type agent_name
    pattern="$(assistant_phase_role_agent_pattern "$role")"
    agent_type="$(assistant_phase_json_field_value "$json_line" "agent_type" | tr '[:upper:]' '[:lower:]')"
    agent_name="$(assistant_phase_json_field_value "$json_line" "agent_name" | tr '[:upper:]' '[:lower:]')"
    IFS='|' read -r -a names <<< "$pattern"
    for name in "${names[@]}"; do
        name="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
        [[ "$agent_type" == "$name" || "$agent_name" == "$name" ]] && return 0
    done
    return 1
}

assistant_phase_codex_role_event_ids() {
    local file="$1"
    local role="$2"
    local event="$3"
    local events_file line id
    events_file="$(assistant_phase_subagent_events_file "$file")"
    [[ -f "$events_file" ]] || return 1
    while IFS= read -r line; do
        [[ "$line" == *"\"event\":\"$event\""* ]] || continue
        assistant_phase_event_role_matches "$line" "$role" || continue
        id="$(assistant_phase_json_field_value "$line" "agent_id")"
        [[ -n "$id" ]] || continue
        printf '%s\n' "$id"
    done < "$events_file"
}

assistant_phase_journal_mentions_agent_id() {
    local file="$1"
    local role="$2"
    local agent_id="$3"
    local dispatch result combined
    [[ -n "$agent_id" ]] || return 1
    dispatch="$(assistant_phase_labeled_evidence_value "$file" "$role dispatch")"
    result="$(assistant_phase_labeled_evidence_value "$file" "$role result")"
    combined="$dispatch
$result"
    printf '%s\n' "$combined" | grep -Fq -- "$agent_id"
}

assistant_phase_has_role_event_pair_evidence() {
    local file="$1"
    local role="$2"
    local start_id
    while IFS= read -r start_id; do
        [[ -n "$start_id" ]] || continue
        assistant_phase_journal_mentions_agent_id "$file" "$role" "$start_id" || continue
        if assistant_phase_codex_role_event_ids "$file" "$role" "SubagentStop" | grep -Fxq -- "$start_id"; then
            return 0
        fi
    done < <(assistant_phase_codex_role_event_ids "$file" "$role" "SubagentStart" || true)
    return 1
}

assistant_phase_has_role_start_event_evidence() {
    local file="$1"
    local role="$2"
    local start_id
    while IFS= read -r start_id; do
        [[ -n "$start_id" ]] || continue
        assistant_phase_journal_mentions_agent_id "$file" "$role" "$start_id" && return 0
    done < <(assistant_phase_codex_role_event_ids "$file" "$role" "SubagentStart" || true)
    return 1
}

assistant_phase_has_role_stop_event_evidence() {
    assistant_phase_has_role_event_pair_evidence "$1" "$2"
}

assistant_phase_has_role_dispatch_result_evidence() {
    local file="$1"
    local role="$2"

    assistant_phase_has_labeled_evidence "$file" "$role dispatch" \
        && assistant_phase_has_labeled_evidence "$file" "$role result" \
        || return 1

    # Codex task journals are not sufficient proof by themselves: Codex can write
    # fake dispatch text after doing work inline. Require real lifecycle evidence
    # captured by SubagentStart/SubagentStop hooks for delegated Codex roles.
    if assistant_phase_is_codex_task "$file"; then
        assistant_phase_has_role_start_event_evidence "$file" "$role" \
            && assistant_phase_has_role_stop_event_evidence "$file" "$role"
        return $?
    fi

    return 0
}

assistant_phase_direct_fallback_reason_valid() {
    local file="$1"
    grep -qiE "^[[:space:]]*[-*]?[[:space:]]*Direct fallback reason:[[:space:]]*(authorization_denied|subagents_unavailable|policy_disallowed)([[:space:]]|$)" "$file" 2>/dev/null
}

assistant_phase_has_role_equivalent_evidence() {
    local file="$1"
    local role="$2"
    assistant_phase_has_labeled_evidence "$file" "$role direct evidence"
}

assistant_phase_has_per_slice_dispatch_evidence() {
    local file="$1"
    ! assistant_phase_is_medium_plus "$file" && return 0
    assistant_phase_has_labeled_evidence "$file" "Per-slice dispatch evidence"
}

assistant_phase_required_subagent_roles() {
    local file="$1"
    local status mode
    status="$(assistant_phase_status "$file" | tr '[:upper:]' '[:lower:]' || true)"
    mode="$(assistant_phase_subagent_mode "$file" | tr '[:upper:]' '[:lower:]' | xargs 2>/dev/null || true)"
    awk -v is_medium_plus="$(assistant_phase_is_medium_plus "$file" && printf yes || printf no)" -v status="$status" -v mode="$mode" '
        function emit(role) {
            if (!seen[role]) {
                seen[role] = 1
                print role
            }
        }
        function scan(line, low) {
            low = tolower(line)
            if (low ~ /code mapper|code-mapper/) emit("Code Mapper")
            if (low ~ /explorer/) emit("Explorer")
            if (low ~ /architect/) emit("Architect")
            if (low ~ /code writer|code-writer/) emit("Code Writer")
            if (low ~ /builder\/tester|builder-tester/) emit("Builder/Tester")
            if (low ~ /reviewer/) emit("Reviewer")
        }
        BEGIN {
            # Medium+ discovery always requires a Code Mapper context map once
            # subagent execution mode has been resolved. Add the role from task
            # size even if the journal forgot to list it.
            if (mode ~ /^(delegated|direct_fallback)$/ && is_medium_plus == "yes") emit("Code Mapper")
            # Once a delegated/fallback task is in Review/Document, the review
            # role is required even for no-op/no-code-change outcomes; otherwise
            # "review phase" can be satisfied inline while claiming delegated mode.
            if (mode ~ /^(delegated|direct_fallback)$/ && status ~ /(reviewing|documenting)/) emit("Reviewer")
        }
        /^Required agents:[[:space:]]*$/ { in_required = 1; next }
        /^Required agents:[[:space:]]*(.+)$/ {
            scan($0)
            next
        }
        in_required && /^[[:space:]]*-[[:space:]]+/ {
            scan($0)
            next
        }
        in_required && /^[^[:space:]-]/ { in_required = 0 }
    ' "$file" 2>/dev/null
}

assistant_phase_requires_subagent_roles() {
    [[ -n "$(assistant_phase_required_subagent_roles "$1")" ]]
}

assistant_phase_role_reason_slug() {
    printf '%s' "$1" | tr '[:upper:]/ ' '[:lower:]__'
}

assistant_phase_subagent_evidence_missing_reason_key() {
    local file="$1"
    local mode policy_state role roles
    mode="$(assistant_phase_subagent_mode "$file" | tr '[:upper:]' '[:lower:]' | xargs 2>/dev/null || true)"
    policy_state="$(assistant_phase_subagent_policy_state "$file" | tr '[:upper:]' '[:lower:]' | xargs 2>/dev/null || true)"
    roles="$(assistant_phase_required_subagent_roles "$file")"

    # Authorization-required is a wait state, not an execution mode. If a task
    # has reached an active workflow phase while authorization is unresolved,
    # block before it can silently complete work inline.
    if [[ "$policy_state" == "authorization_required" ]]; then
        printf 'authorization_required_unresolved\n'
        return 0
    fi

    # Strict subagent evidence applies whenever workflow subagent roles are
    # declared, not only when source code changed. Discovery/review-only work can
    # legitimately skip Code Writer and Builder/Tester, but delegated Code Mapper,
    # Explorer, Architect, or Reviewer responsibilities still need evidence.
    if [[ -z "$roles" ]]; then
        printf 'complete\n'
        return 0
    fi

    case "$mode" in
        delegated)
            while IFS= read -r role; do
                [[ -n "$role" ]] || continue
                if ! assistant_phase_has_role_dispatch_result_evidence "$file" "$role"; then
                    printf 'delegated_missing_%s\n' "$(assistant_phase_role_reason_slug "$role")"
                    return 0
                fi
            done <<< "$roles"
            if printf '%s\n' "$roles" | grep -Eq '^(Code Writer|Builder/Tester)$' \
                && ! assistant_phase_has_per_slice_dispatch_evidence "$file"; then
                printf 'delegated_missing_per_slice\n'
                return 0
            fi
            ;;
        direct_fallback)
            if [[ "$policy_state" != "authorization_denied" && "$policy_state" != "subagents_unavailable" && "$policy_state" != "policy_disallowed" ]]; then
                printf 'direct_fallback_invalid_policy_state\n'
                return 0
            fi
            if ! assistant_phase_direct_fallback_reason_valid "$file"; then
                printf 'direct_fallback_missing_reason\n'
                return 0
            fi
            while IFS= read -r role; do
                [[ -n "$role" ]] || continue
                if ! assistant_phase_has_role_equivalent_evidence "$file" "$role"; then
                    printf 'direct_fallback_missing_%s\n' "$(assistant_phase_role_reason_slug "$role")"
                    return 0
                fi
            done <<< "$roles"
            ;;
        not_applicable|"")
            printf 'not_applicable_with_required_roles\n'
            return 0
            ;;
        *)
            printf 'unknown_execution_mode\n'
            return 0
            ;;
    esac

    printf 'complete\n'
}
