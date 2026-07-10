#!/usr/bin/env bash
# qa-controller.sh -- QA and review completion gate helpers.

assistant_phase_requires_qa_evaluator() {
    local file="$1"
    awk '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        function explicit_not_required(value, low) {
            low = tolower(trim(value))
            return low ~ /^(n\/a|na|not_required|not required|not-required|not-applicable|not_applicable|not applicable)([[:space:][:punct:]]|$)/
        }
        function explicit_optional(value, low) {
            low = tolower(trim(value))
            return low ~ /^optional([[:space:][:punct:]]|$)/
        }
        function bracket_placeholder(value) {
            value = trim(value)
            return value ~ /^\[[^]]*\]$/
        }
        function has_concrete_positive_clause(value, low, n, parts, i, clause) {
            low = tolower(trim(value))
            gsub(/`/, "", low)
            n = split(low, parts, /[;,()]|[[:space:]]but[[:space:]]/)
            for (i = 1; i <= n; i++) {
                clause = trim(parts[i])
                if (clause == "" ||
                    clause ~ /(^|[[:space:][:punct:]])(no|without|not|n\/a|na|not_required|not required|not-required|not-applicable|not_applicable|not applicable|optional)([[:space:][:punct:]]|$)/ ||
                    clause ~ /(template|placeholder|generic acceptance criteria)/) {
                    continue
                }
                if (clause ~ /^required([[:space:][:punct:]]|$)/ ||
                    clause ~ /qa[ _-]?evaluation[ _-]?mode[[:space:]]*[:=][[:space:]]*required([[:space:][:punct:]]|$)/ ||
                    clause ~ /(explicit|requested|user[^[:alnum:]]+asks)[^.\n]*(qa|acceptance[ _-]?evaluation)/ ||
                    clause ~ /(qa|acceptance[ _-]?evaluation)[^.\n]*(explicit|requested|required)/ ||
                    clause ~ /(accepted[ _-]?done[ _-]?contract|done[ _-]?contract[^.\n]*(accepted|accepted_by))/ ||
                    clause ~ /(harness[ _-]?capable|harness_capable|harness)[^.\n]*(acceptance[ _-]?(scope|evaluation)|acceptance)/ ||
                    clause ~ /(domain[ _-]?scored|domain[ _-]?quality|domain[ _-]?context|domain[ _-]?rubric|rubric_refs)/ ||
                    (clause ~ /(^|[[:space:][:punct:]])(ui|visual|product|ux|docs|dx)([[:space:][:punct:]]|$)/ && clause ~ /(acceptance|quality|rubric|domain)/) ||
                    clause ~ /(multi_agent|agent_id|final[ _-]?verdict|qa[ _-]?result)/) {
                    return 1
                }
            }
            return 0
        }
        function non_trigger_text(value, low) {
            low = tolower(trim(value))
            gsub(/`/, "", low)
            return low == "" ||
                low ~ /\|/ ||
                low ~ /^\[[^]]*\]$/ ||
                explicit_not_required(low) ||
                explicit_optional(low) ||
                low ~ /(^|[[:space:][:punct:]])(n\/a|not_required|not required|not-required|not-applicable|not_applicable|not applicable|optional)([[:space:][:punct:]]|$)/ ||
                (!has_concrete_positive_clause(low) && low ~ /(^|[[:space:][:punct:]])(no|without)[[:space:]]+(explicit qa|qa request|accepted done contract|done contract|harness-capable acceptance|harness capable acceptance|domain-scored|domain scored|ui|visual|product|ux|docs|dx)/) ||
                low ~ /(^|[[:space:][:punct:]])(pending|waiting|todo|tbd|not yet)([[:space:][:punct:]]|$)/ ||
                low ~ /(when|if|unless|only when)[^.\n]*(required|qa_evaluation_mode|qa evaluation mode)/ ||
                low ~ /(template|placeholder|generic acceptance criteria)/
        }
        function positive_required_trigger(value, low) {
            low = tolower(trim(value))
            gsub(/`/, "", low)
            if (non_trigger_text(low)) {
                return 0
            }
            return low ~ /^required([[:space:][:punct:]]|$)/ ||
                low ~ /qa[ _-]?evaluation[ _-]?mode[[:space:]]*[:=][[:space:]]*required([[:space:][:punct:]]|$)/ ||
                low ~ /(^|[[:space:][:punct:]])qa[ _-]?evaluator([[:space:][:punct:]]|$)/ ||
                low ~ /(explicit|requested|user[^[:alnum:]]+asks)[^.\n]*(qa|acceptance[ _-]?evaluation)/ ||
                low ~ /(qa|acceptance[ _-]?evaluation)[^.\n]*(explicit|requested|required)/ ||
                low ~ /(accepted[ _-]?done[ _-]?contract|done[ _-]?contract[^.\n]*(accepted|accepted_by))/ ||
                low ~ /(harness[ _-]?capable|harness_capable|harness)[^.\n]*(acceptance[ _-]?(scope|evaluation)|acceptance)/ ||
                low ~ /(domain[ _-]?scored|domain[ _-]?quality|domain[ _-]?context|domain[ _-]?rubric|rubric_refs)/ ||
                (low ~ /(^|[[:space:][:punct:]])(ui|visual|product|ux|docs|dx)([[:space:][:punct:]]|$)/ && low ~ /(acceptance|quality|rubric|domain)/) ||
                low ~ /(multi_agent|agent_id|final[ _-]?verdict|qa[ _-]?result)/
        }
        function concrete_positive_trigger(value, low) {
            low = tolower(trim(value))
            gsub(/`/, "", low)
            if (non_trigger_text(low)) {
                return 0
            }
            return low ~ /^required([[:space:][:punct:]]|$)/ ||
                low ~ /qa[ _-]?evaluation[ _-]?mode[[:space:]]*[:=][[:space:]]*required([[:space:][:punct:]]|$)/ ||
                low ~ /(explicit|requested|user[^[:alnum:]]+asks)[^.\n]*(qa|acceptance[ _-]?evaluation)/ ||
                low ~ /(qa|acceptance[ _-]?evaluation)[^.\n]*(explicit|requested|required)/ ||
                low ~ /(accepted[ _-]?done[ _-]?contract|done[ _-]?contract[^.\n]*(accepted|accepted_by))/ ||
                low ~ /(harness[ _-]?capable|harness_capable|harness)[^.\n]*(acceptance[ _-]?(scope|evaluation)|acceptance)/ ||
                low ~ /(domain[ _-]?scored|domain[ _-]?quality|domain[ _-]?context|domain[ _-]?rubric|rubric_refs)/ ||
                (low ~ /(^|[[:space:][:punct:]])(ui|visual|product|ux|docs|dx)([[:space:][:punct:]]|$)/ && low ~ /(acceptance|quality|rubric|domain)/) ||
                low ~ /(multi_agent|agent_id|final[ _-]?verdict|qa[ _-]?result)/
        }
        function qa_mode_required_line(line, low) {
            low = tolower(trim(line))
            sub(/^[[:space:]]*[-*][[:space:]]*/, "", low)
            return low ~ /^(qa_evaluation_mode|qa[ _-]?evaluation[ _-]?mode)[[:space:]]*[:=][[:space:]]*required([[:space:][:punct:]]|$)/ ||
                low ~ /^(qa_evaluation_mode|qa[ _-]?evaluation[ _-]?mode)[[:space:]]+required([[:space:][:punct:]]|$)/
        }
        function qa_mode_not_required_line(line, low) {
            low = tolower(trim(line))
            sub(/^[[:space:]]*[-*][[:space:]]*/, "", low)
            return low ~ /^(qa_evaluation_mode|qa[ _-]?evaluation[ _-]?mode)[[:space:]]*[:=][[:space:]]*(n\/a|na|not_required|not required|not-required|not_applicable|not applicable|not-applicable)([[:space:][:punct:]]|$)/ ||
                low ~ /^(qa_evaluation_mode|qa[ _-]?evaluation[ _-]?mode)[[:space:]]+(n\/a|na|not_required|not required|not-required|not_applicable|not applicable|not-applicable)([[:space:][:punct:]]|$)/
        }
        function qa_mode_optional_line(line, low) {
            low = tolower(trim(line))
            sub(/^[[:space:]]*[-*][[:space:]]*/, "", low)
            return low ~ /^(qa_evaluation_mode|qa[ _-]?evaluation[ _-]?mode)[[:space:]]*[:=][[:space:]]*optional([[:space:][:punct:]]|$)/ ||
                low ~ /^(qa_evaluation_mode|qa[ _-]?evaluation[ _-]?mode)[[:space:]]+optional([[:space:][:punct:]]|$)/
        }
        function qa_section_mode_required_line(line, value, low) {
            line = trim(line)
            sub(/^[[:space:]]*[-*][[:space:]]*/, "", line)
            low = tolower(line)
            if (low !~ /^mode[[:space:]]*:/) {
                return 0
            }
            value = line
            sub(/^[^:]*:[[:space:]]*/, "", value)
            value = trim(value)
            if (value ~ /\|/ || bracket_placeholder(value)) {
                return 0
            }
            low = tolower(value)
            return low ~ /^required([[:space:][:punct:]]|$)/
        }
        function qa_section_mode_not_required_line(line, value, low) {
            line = trim(line)
            sub(/^[[:space:]]*[-*][[:space:]]*/, "", line)
            low = tolower(line)
            if (low !~ /^mode[[:space:]]*:/) {
                return 0
            }
            value = line
            sub(/^[^:]*:[[:space:]]*/, "", value)
            value = trim(value)
            if (value ~ /\|/ || bracket_placeholder(value)) {
                return 0
            }
            low = tolower(value)
            return low ~ /^(n\/a|na|not_required|not required|not-required|not_applicable|not applicable|not-applicable)([[:space:][:punct:]]|$)/
        }
        function qa_section_mode_optional_line(line, value, low) {
            line = trim(line)
            sub(/^[[:space:]]*[-*][[:space:]]*/, "", line)
            low = tolower(line)
            if (low !~ /^mode[[:space:]]*:/) {
                return 0
            }
            value = line
            sub(/^[^:]*:[[:space:]]*/, "", value)
            value = trim(value)
            if (value ~ /\|/ || bracket_placeholder(value)) {
                return 0
            }
            low = tolower(value)
            return low ~ /^optional([[:space:][:punct:]]|$)/
        }
        function line_marks_not_required(line, low) {
            low = tolower(line)
            return low ~ /(^|[[:space:][:punct:]])(n\/a|not_required|not required|not-required|not-applicable|not_applicable|not applicable|optional)([[:space:][:punct:]]|$)/ ||
                low ~ /(when|if|unless|only when)[^.\n]*(required|qa_evaluation_mode|qa evaluation mode)/
        }
        function qa_marker(line, low) {
            low = tolower(line)
            return low ~ /(qa[ _-]?evaluator|qaevaluator|qa[ _-]?evaluation|qa_evaluation_mode|qa[ _-]?loop)/
        }
        function scan_required_line(line, section) {
            if (!qa_marker(line) || line_marks_not_required(line) || !positive_required_trigger(line)) {
                return
            }
            if (section == "gates" && !concrete_positive_trigger(line)) {
                generic_found = 1
            } else {
                found = 1
            }
        }
        function scan_qa_label(line, value, low) {
            sub(/^[[:space:]]*[-*]?[[:space:]]*/, "", line)
            low = tolower(line)
            if (low ~ /^(qa evaluator dispatch|qa evaluator result|qa evaluator direct evidence):/) {
                value = line
                sub(/^[^:]*:[[:space:]]*/, "", value)
                if (!non_trigger_text(value) && (positive_required_trigger(value) || positive_required_trigger(line))) {
                    found = 1
                }
            } else if (low ~ /^qa evaluator dispatch\/result\/direct evidence:/) {
                value = line
                sub(/^[^:]*:[[:space:]]*/, "", value)
                if (!non_trigger_text(value) && (positive_required_trigger(value) || positive_required_trigger(line))) {
                    found = 1
                }
            }
        }
        function scan_trigger_label(line, value, low) {
            sub(/^[[:space:]]*[-*]?[[:space:]]*/, "", line)
            low = tolower(line)
            if (low ~ /^(qa trigger reason|qa_trigger_reason|done contract|done_contract|done_contract_ref|harness routing|harness_routing|harness_capable|acceptance scope|qa evaluation scope|qa scope|domain_context|domain context|rubric_refs|rubric refs)[[:space:]]*:/) {
                value = line
                sub(/^[^:]*:[[:space:]]*/, "", value)
                if (!non_trigger_text(value) && (positive_required_trigger(value) || positive_required_trigger(line))) {
                    found = 1
                }
            }
        }
        {
            line = $0
            low = tolower(line)
            if (low ~ /^###[[:space:]]*qa evaluation([[:space:]#]|$)/) {
                in_qa_evaluation = 1
                in_required_agents = 0
                in_required_gates = 0
                next
            }
            if (in_qa_evaluation && low ~ /^#+[[:space:]]+/) {
                in_qa_evaluation = 0
            }
            if (in_qa_evaluation) {
                if (qa_section_mode_required_line(line)) {
                    required_mode = 1
                    found = 1
                    next
                }
                if (qa_section_mode_not_required_line(line)) {
                    not_required_mode = 1
                    next
                }
                if (qa_section_mode_optional_line(line)) {
                    optional_mode = 1
                    next
                }
            }
            if (qa_mode_required_line(line)) {
                required_mode = 1
                found = 1
                next
            }
            if (qa_mode_not_required_line(line)) {
                not_required_mode = 1
                next
            }
            if (qa_mode_optional_line(line)) {
                optional_mode = 1
                next
            }

            scan_qa_label(line)
            scan_trigger_label(line)

            if (low ~ /^required agents:[[:space:]]*$/) {
                in_required_agents = 1
                in_required_gates = 0
                next
            }
            if (low ~ /^required gates:[[:space:]]*$/) {
                in_required_gates = 1
                in_required_agents = 0
                next
            }
            if (low ~ /^required agents:[[:space:]]*.+$/ ||
                low ~ /^required gates:[[:space:]]*.+$/) {
                scan_required_line(line, low ~ /^required gates:/ ? "gates" : "agents")
                next
            }
            if ((in_required_agents || in_required_gates) && line ~ /^[[:space:]]*-[[:space:]]+/) {
                scan_required_line(line, in_required_gates ? "gates" : "agents")
                next
            }
            if ((in_required_agents || in_required_gates) && line ~ /^[^[:space:]-]/) {
                in_required_agents = 0
                in_required_gates = 0
            }
        }
        END {
            if (found) {
                exit 0
            }
            if ((not_required_mode || optional_mode) && !required_mode) {
                exit 1
            }
            if (generic_found) {
                exit 0
            }
            exit 1
        }
    ' "$file" 2>/dev/null
}

assistant_phase_latest_qa_final_result() {
    local file="$1"
    local minimum_line="${2:-0}"
    awk -v minimum_line="$minimum_line" '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        function template_placeholder(value, low) {
            low = tolower(trim(value))
            gsub(/`/, "", low)
            return low ~ /^\[[^]]*\]$/ || low ~ /\|/
        }
        function normalize_result(value, low) {
            if (template_placeholder(value)) return ""
            low = tolower(trim(value))
            gsub(/`/, "", low)
            if (low ~ /(^|[^[:alnum:]_])not[ _-]?accepted([^[:alnum:]_]|$)/) return "not_accepted"
            if (low ~ /(^|[^[:alnum:]_])accepted[ _-]?with[ _-]?concerns([^[:alnum:]_]|$)/) return "accepted_with_concerns"
            if (low ~ /(^|[^[:alnum:]_])accepted([^[:alnum:]_]|$)/) return "accepted"
            if (low ~ /(^|[^[:alnum:]_])rejected([^[:alnum:]_]|$)/) return "rejected"
            if (low ~ /(^|[^[:alnum:]_])blocked([^[:alnum:]_]|$)/) return "blocked"
            if (low ~ /(^|[^[:alnum:]_])not[ _-]?required([^[:alnum:]_]|$)/) return "not_required"
            return ""
        }
        function record_result(value) {
            latest = normalize_result(value)
        }
        function compact_final_marker(value, low) {
            low = tolower(value)
            return low ~ /(final[ _-]?verdict|qa[ _-]?result)/
        }
        BEGIN {
            minimum_line += 0
        }
        NR <= minimum_line {
            next
        }
        /^### QA Evaluation #[0-9]+/ {
            latest = ""
            next
        }
        {
            line = $0
            sub(/^[[:space:]]*[-*]?[[:space:]]*/, "", line)
            low = tolower(line)
            if (low ~ /^final verdict[[:space:]]*:/) {
                value = line
                sub(/^[^:]*:[[:space:]]*/, "", value)
                record_result(value)
                next
            }
            if (low ~ /^qa result[[:space:]]*:/) {
                value = line
                sub(/^[^:]*:[[:space:]]*/, "", value)
                record_result(value)
                next
            }
            if (low ~ /^qa evaluator result[[:space:]]*:/) {
                value = line
                sub(/^[^:]*:[[:space:]]*/, "", value)
                if (compact_final_marker(value) || normalize_result(value) != "") {
                    record_result(value)
                }
            }
        }
        END {
            if (latest != "") {
                print latest
                exit 0
            }
            exit 1
        }
    ' "$file" 2>/dev/null
}

assistant_phase_qa_final_result_missing_reason_key() {
    local file="$1"
    local minimum_line="${2:-0}"
    local qa_result

    if ! assistant_phase_requires_qa_evaluator "$file"; then
        printf 'complete\n'
        return 0
    fi

    qa_result="$(assistant_phase_latest_qa_final_result "$file" "$minimum_line" || true)"
    case "$qa_result" in
        accepted|accepted_with_concerns)
            printf 'complete\n'
            ;;
        rejected)
            printf 'qa_rejected\n'
            ;;
        blocked)
            printf 'qa_blocked\n'
            ;;
        "")
            printf 'qa_final_result_missing\n'
            ;;
        not_accepted)
            printf 'qa_not_accepted\n'
            ;;
        *)
            printf 'qa_not_accepted\n'
            ;;
    esac
}

assistant_phase_review_missing_reason_key() {
    local file="$1"
    local spec_pass_line
    local quality_review_line
    local review_controller_reason
    local qa_reason

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
        review_controller_reason="$(assistant_phase_review_controller_missing_reason_key "$file" "$quality_review_line" "$spec_pass_line")"
        if [[ "$review_controller_reason" != "complete" ]]; then
            printf '%s\n' "$review_controller_reason"
            return 0
        fi
        assistant_phase_qa_final_result_missing_reason_key "$file" "$quality_review_line"
        return 0
    fi

    if ! assistant_phase_final_result_after_line "$file" "$quality_review_line" >/dev/null; then
        printf 'no_final_result\n'
        return 0
    fi

    qa_reason="$(assistant_phase_qa_final_result_missing_reason_key "$file" "$quality_review_line")"
    if [[ "$qa_reason" != "complete" ]]; then
        printf '%s\n' "$qa_reason"
        return 0
    fi

    printf 'complete\n'
}

assistant_phase_review_complete() {
    local file="$1"
    [[ "$(assistant_phase_review_missing_reason_key "$file")" == "complete" ]]
}
