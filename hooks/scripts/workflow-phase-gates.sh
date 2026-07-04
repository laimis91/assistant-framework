#!/usr/bin/env bash
# workflow-phase-gates.sh — Shared task-journal phase gate helpers.
#
# Callers are responsible for resolving the active task journal first. In
# particular, completed-journal suppression remains owned by
# task-journal-resolver.sh so these helpers do not accidentally revive stale
# workflow state.

ASSISTANT_PHASE_GATES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$ASSISTANT_PHASE_GATES_DIR/hook-runtime.sh" ]]; then
    . "$ASSISTANT_PHASE_GATES_DIR/hook-runtime.sh"
fi

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
    local file="$1"
    awk '
        function is_task_heading(line) {
            return line ~ /^##+[[:space:]]*Task([[:space:]]*:|[[:space:]]*$)/
        }
        function is_nested_section(line) {
            return line ~ /^##+[[:space:]]+/ && !is_task_heading(line)
        }
        is_nested_section($0) {
            exit
        }
        $0 ~ "^(#[[:space:]]*)?Status:" {
            sub("^(#[[:space:]]*)?Status:[[:space:]]*", "", $0)
            print
            exit
        }
    ' "$file" 2>/dev/null
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

assistant_phase_plan_missing_reason_key() {
    local file="$1"
    local has_plan

    has_plan="$(grep -m1 -E "^(Plan approval:|## Plan)" "$file" 2>/dev/null || true)"
    if [[ -z "$has_plan" ]]; then
        printf 'no_plan\n'
    elif ! assistant_phase_has_plan_approval "$file"; then
        printf 'plan_not_approved\n'
    else
        printf 'complete\n'
    fi
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

assistant_phase_subagent_mode() {
    assistant_phase_scalar_field "$1" "Subagent execution mode"
}

assistant_phase_subagent_policy_state() {
    assistant_phase_scalar_field "$1" "Subagent policy state"
}

assistant_phase_exact_labeled_evidence_value() {
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

assistant_phase_compact_labeled_evidence_value() {
    local file="$1"
    local label="$2"
    local role

    case "$label" in
        *" dispatch") role="${label% dispatch}" ;;
        *" result") role="${label% result}" ;;
        *" direct evidence") role="${label% direct evidence}" ;;
        *) return 1 ;;
    esac

    assistant_phase_exact_labeled_evidence_value "$file" "$role dispatch/result/direct evidence"
}

assistant_phase_labeled_evidence_value() {
    local file="$1"
    local label="$2"
    local value

    value="$(assistant_phase_exact_labeled_evidence_value "$file" "$label")"
    if [[ -n "$value" ]]; then
        printf '%s\n' "$value"
        return 0
    fi

    assistant_phase_compact_labeled_evidence_value "$file" "$label"
}

assistant_phase_has_labeled_evidence() {
    local file="$1"
    local label="$2"
    local value
    value="$(assistant_phase_labeled_evidence_value "$file" "$label")"

    [[ -n "$value" ]] || return 1
    ! assistant_phase_labeled_evidence_value_is_placeholder "$value"
}

assistant_phase_labeled_evidence_value_is_placeholder() {
    local value="$1"
    local low

    value="$(assistant_phase_trim_value "$value")"
    [[ -n "$value" ]] || return 0
    assistant_phase_value_is_noneish "$value" && return 0
    [[ "$value" =~ ^\[.*\]$ ]] && return 0

    low="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
    [[ "$low" =~ ^(pending|waiting|missing|todo|tbd|none)([[:space:][:punct:]]|$) ]] && return 0
    [[ "$low" =~ ^n[/.]?a([[:space:][:punct:]]|$) ]] && return 0
    [[ "$low" =~ ^in[[:space:]_-]?progress([[:space:][:punct:]]|$) ]] && return 0
    [[ "$low" =~ ^not[[:space:]_-]?yet([[:space:][:punct:]]|$) ]] && return 0
    [[ "$low" =~ ^not[[:space:]_-]?(required|applicable)([[:space:][:punct:]]|$) ]] && return 0
    return 1
}

assistant_phase_source_gate_module() {
    local module="$ASSISTANT_PHASE_GATES_DIR/workflow-phase-gates.d/$1"
    if [[ -f "$module" ]]; then
        . "$module"
    fi
}

assistant_phase_source_gate_module "review-controller.sh"
assistant_phase_source_gate_module "qa-controller.sh"
assistant_phase_source_gate_module "learning-controller.sh"
assistant_phase_source_gate_module "metrics.sh"
assistant_phase_source_gate_module "subagent-evidence.sh"
assistant_phase_source_gate_module "subagent-orchestration.sh"
