#!/usr/bin/env bash
# review-controller.sh -- Quality review controller gate helpers.

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
