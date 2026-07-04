# Shell write-target parser helpers for workflow-guard.sh.

assistant_shell_clean_write_target_path() {
    local candidate="${1:-}"
    local quote

    candidate="$(printf '%s' "$candidate" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$candidate" ]] || return 1

    quote="${candidate:0:1}"
    if [[ "$quote" == "\"" && "${candidate: -1}" == "\"" ]]; then
        candidate="${candidate#\"}"
        candidate="${candidate%\"}"
    elif [[ "$quote" == "'" && "${candidate: -1}" == "'" ]]; then
        candidate="${candidate#\'}"
        candidate="${candidate%\'}"
    elif [[ "$quote" == "\"" || "$quote" == "'" ]]; then
        printf '%s\n' "__assistant_unproven_shell_write_target__"
        return 0
    fi

    case "$candidate" in
        ""|/dev/null)
            return 1
            ;;
        *'$'*|*'`'*|*'('*|*')'*|*'{'*|*'}'*|*'['*|*']'*|*'*'*|*'?'*|*'<'*|*'>'*)
            printf '%s\n' "__assistant_unproven_shell_write_target__"
            return 0
            ;;
    esac

    printf '%s\n' "$candidate"
}

assistant_shell_emit_write_target_path() {
    assistant_shell_clean_write_target_path "$1" || true
}

assistant_shell_emit_unproven_write_target() {
    printf '%s\n' "__assistant_unproven_shell_write_target__"
}

assistant_shell_pop_word() {
    local text="${1:-}"
    local word_var="${2:-}"
    local rest_var="${3:-}"
    local parsed_word=""
    local parsed_rest
    local quote=""
    local c
    local i=0
    local length

    text="$(printf '%s' "$text" | sed 's/^[[:space:]]*//')"
    [[ -n "$text" ]] || return 1

    length="${#text}"
    while (( i < length )); do
        c="${text:$i:1}"
        if [[ -z "$quote" ]]; then
            case "$c" in
                [[:space:]])
                    break
                    ;;
                "'")
                    quote="'"
                    ((i += 1))
                    continue
                    ;;
                '"')
                    quote='"'
                    ((i += 1))
                    continue
                    ;;
                "\\")
                    if (( i + 1 < length )); then
                        ((i += 1))
                        c="${text:$i:1}"
                    fi
                    ;;
            esac
            parsed_word+="$c"
        elif [[ "$quote" == "'" ]]; then
            if [[ "$c" == "'" ]]; then
                quote=""
            else
                parsed_word+="$c"
            fi
        else
            if [[ "$c" == '"' ]]; then
                quote=""
            elif [[ "$c" == "\\" ]]; then
                if (( i + 1 < length )); then
                    ((i += 1))
                    parsed_word+="${text:$i:1}"
                else
                    parsed_word+="$c"
                fi
            else
                parsed_word+="$c"
            fi
        fi
        ((i += 1))
    done

    if [[ -n "$quote" ]]; then
        return 2
    fi

    parsed_rest="${text:$i}"
    parsed_rest="$(printf '%s' "$parsed_rest" | sed 's/^[[:space:]]*//')"
    printf -v "$word_var" '%s' "$parsed_word"
    printf -v "$rest_var" '%s' "$parsed_rest"
}

assistant_shell_word_is_dynamic() {
    local word="${1:-}"

    [[ "$word" == *'$'* || "$word" == *'`'* ]]
}

assistant_shell_word_is_assignment_prefix() {
    local word="${1:-}"

    [[ "$word" =~ ^[A-Za-z_][A-Za-z0-9_]*(\+)?= ]]
}

assistant_shell_command_word_basename() {
    local word="${1:-}"
    local basename

    [[ -n "$word" ]] || return 1
    basename="${word##*/}"
    [[ -n "$basename" ]] || return 1

    printf '%s\n' "$basename"
    case "$word" in
        */*)
            case "$word" in
                *'$'*|*'`'*|*'*'*|*'?'*|*'['*|*']'*|*'{'*|*'}'*|*'('*|*')'*)
                    return 2
                    ;;
            esac
            ;;
    esac

    return 0
}

assistant_shell_command_word_matches() {
    local word="${1:-}"
    local expected="${2:-}"
    local basename basename_status

    [[ -n "$expected" ]] || return 1

    basename_status=0
    basename="$(assistant_shell_command_word_basename "$word")" || basename_status=$?
    if [[ "$basename" != "$expected" ]]; then
        return 1
    fi
    if (( basename_status == 2 )); then
        return 2
    fi
    return 0
}

assistant_shell_command_position_tail() {
    local text="${1:-}"
    local rest word after_word status

    rest="$(printf '%s' "$text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    while true; do
        status=0
        assistant_shell_pop_word "$rest" word after_word || status=$?
        if (( status == 1 )); then
            return 1
        fi
        if (( status == 2 )); then
            assistant_shell_emit_unproven_write_target
            return 0
        fi
        if assistant_shell_word_is_assignment_prefix "$word"; then
            rest="$after_word"
            continue
        fi
        if [[ -n "$after_word" ]]; then
            printf '%s %s\n' "$word" "$after_word"
        else
            printf '%s\n' "$word"
        fi
        return 0
    done
}

assistant_shell_has_command_substitution() {
    local command="${1:-}"
    local quote=""
    local c next
    local i=0
    local length

    length="${#command}"
    while (( i < length )); do
        c="${command:$i:1}"
        if [[ "$quote" == "'" ]]; then
            if [[ "$c" == "'" ]]; then
                quote=""
            fi
        else
            if [[ "$c" == "'" && -z "$quote" ]]; then
                quote="'"
            elif [[ "$c" == '"' ]]; then
                if [[ -z "$quote" ]]; then
                    quote='"'
                else
                    quote=""
                fi
            elif [[ "$c" == "\\" ]]; then
                if (( i + 1 < length )); then
                    ((i += 1))
                fi
            elif [[ "$c" == '`' ]]; then
                return 0
            elif [[ "$c" == '$' ]]; then
                next="${command:$((i + 1)):1}"
                if [[ "$next" == "(" ]]; then
                    return 0
                fi
            fi
        fi
        ((i += 1))
    done

    return 1
}

assistant_shell_segment_is_unproven() {
    [[ "${1:-}" == "__assistant_unproven_shell_write_target__" ]]
}

assistant_shell_is_apply_patch_heredoc_command() {
    local command="${1:-}"
    local word rest status
    local header body delimiter_part delimiter after_delimiter
    local strip_tabs=false
    local remaining line compare

    status=0
    assistant_shell_pop_word "$command" word rest || status=$?
    [[ "$status" -eq 0 && "$word" == "apply_patch" ]] || return 1
    [[ "$rest" == *$'\n'* ]] || return 1

    header="${rest%%$'\n'*}"
    body="${rest#*$'\n'}"
    header="$(printf '%s' "$header" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    case "$header" in
        '<<<'*)
            return 1
            ;;
        '<<-'*)
            strip_tabs=true
            delimiter_part="${header#<<-}"
            ;;
        '<<'*)
            delimiter_part="${header#<<}"
            ;;
        *)
            return 1
            ;;
    esac

    status=0
    assistant_shell_pop_word "$delimiter_part" delimiter after_delimiter || status=$?
    [[ "$status" -eq 0 && -n "$delimiter" && -z "$after_delimiter" ]] || return 1

    remaining="$body"
    while [[ "$remaining" == *$'\n'* ]]; do
        line="${remaining%%$'\n'*}"
        remaining="${remaining#*$'\n'}"
        compare="$line"
        if [[ "$strip_tabs" == "true" ]]; then
            while [[ "${compare:0:1}" == $'\t' ]]; do
                compare="${compare:1}"
            done
        fi
        if [[ "$compare" == "$delimiter" ]]; then
            [[ "$remaining" =~ ^[[:space:]]*$ ]]
            return $?
        fi
    done

    compare="$remaining"
    if [[ "$strip_tabs" == "true" ]]; then
        while [[ "${compare:0:1}" == $'\t' ]]; do
            compare="${compare:1}"
        done
    fi
    [[ "$compare" == "$delimiter" ]]
}

assistant_shell_token_is_unsupported_syntax() {
    local token="${1:-}"
    local expect_command="${2:-false}"
    local in_find_command="${3:-false}"
    local command_name

    if [[ "$in_find_command" == "true" ]]; then
        case "$token" in
            -exec|-execdir|-delete|-ok|-okdir|-fprint|-fprint0|-fprintf|-fls)
                return 0
                ;;
        esac
    fi

    if [[ "$expect_command" == "true" ]]; then
        command_name="$(assistant_shell_command_word_basename "$token" || true)"
        case "$command_name" in
            !|coproc|function|for|while|until|case|select|if|alias|eval|source|xargs|.)
                return 0
                ;;
            command|exec|builtin|time|nice|nohup|timeout|stdbuf|flock)
                return 0
                ;;
        esac
    fi

    return 1
}

assistant_shell_has_unsupported_syntax() {
    local command="${1:-}"
    local quote=""
    local token=""
    local expect_command=true
    local in_find_command=false
    local token_is_find=false
    local c next
    local i=0
    local length

    length="${#command}"
    while (( i < length )); do
        c="${command:$i:1}"
        if [[ -z "$quote" ]]; then
            case "$c" in
                "'")
                    quote="'"
                    ;;
                '"')
                    quote='"'
                    ;;
                "\\")
                    if (( i + 1 < length )); then
                        ((i += 1))
                        token+="${command:$i:1}"
                    fi
                    ;;
                '$')
                    next="${command:$((i + 1)):1}"
                    if [[ "$next" == "(" ]]; then
                        return 0
                    fi
                    token+="$c"
                    ;;
                '`')
                    return 0
                    ;;
                $'\n')
                    if [[ -n "$token" ]]; then
                        if assistant_shell_token_is_unsupported_syntax "$token" "$expect_command" "$in_find_command"; then
                            return 0
                        fi
                        token_is_find=false
                        if assistant_shell_command_word_matches "$token" "find"; then
                            token_is_find=true
                        fi
                        if [[ "$token_is_find" == "true" && "$expect_command" == "true" ]]; then
                            in_find_command=true
                        fi
                        token=""
                    fi
                    expect_command=true
                    in_find_command=false
                    ;;
                [[:space:]])
                    if [[ -n "$token" ]]; then
                        if assistant_shell_token_is_unsupported_syntax "$token" "$expect_command" "$in_find_command"; then
                            return 0
                        fi
                        token_is_find=false
                        if assistant_shell_command_word_matches "$token" "find"; then
                            token_is_find=true
                        fi
                        if [[ "$token_is_find" == "true" && "$expect_command" == "true" ]]; then
                            in_find_command=true
                        fi
                        if [[ "$expect_command" != "true" ]] || ! assistant_shell_word_is_assignment_prefix "$token"; then
                            expect_command=false
                        fi
                        token=""
                    fi
                    ;;
                ';'|'|')
                    if [[ -n "$token" ]]; then
                        if assistant_shell_token_is_unsupported_syntax "$token" "$expect_command" "$in_find_command"; then
                            return 0
                        fi
                        token_is_find=false
                        if assistant_shell_command_word_matches "$token" "find"; then
                            token_is_find=true
                        fi
                        if [[ "$token_is_find" == "true" && "$expect_command" == "true" ]]; then
                            in_find_command=true
                        fi
                        token=""
                    fi
                    expect_command=true
                    in_find_command=false
                    next="${command:$((i + 1)):1}"
                    if [[ "$c" == "|" && "$next" == "|" ]]; then
                        ((i += 1))
                    fi
                    ;;
                '&')
                    next="${command:$((i + 1)):1}"
                    if [[ "$next" == ">" ]]; then
                        if [[ -n "$token" ]]; then
                            if assistant_shell_token_is_unsupported_syntax "$token" "$expect_command" "$in_find_command"; then
                                return 0
                            fi
                            token_is_find=false
                            if assistant_shell_command_word_matches "$token" "find"; then
                                token_is_find=true
                            fi
                            if [[ "$token_is_find" == "true" && "$expect_command" == "true" ]]; then
                                in_find_command=true
                            fi
                            expect_command=false
                            token=""
                        fi
                    else
                        if [[ -n "$token" ]]; then
                            if assistant_shell_token_is_unsupported_syntax "$token" "$expect_command" "$in_find_command"; then
                                return 0
                            fi
                            token=""
                        fi
                        expect_command=true
                        in_find_command=false
                        if [[ "$next" == "&" ]]; then
                            ((i += 1))
                        fi
                    fi
                    ;;
                '<')
                    next="${command:$((i + 1)):1}"
                    if [[ "$next" == "(" || "$next" == "<" || "$next" == ">" ]]; then
                        return 0
                    fi
                    if [[ -n "$token" ]]; then
                        if assistant_shell_token_is_unsupported_syntax "$token" "$expect_command" "$in_find_command"; then
                            return 0
                        fi
                        token_is_find=false
                        if assistant_shell_command_word_matches "$token" "find"; then
                            token_is_find=true
                        fi
                        if [[ "$token_is_find" == "true" && "$expect_command" == "true" ]]; then
                            in_find_command=true
                        fi
                        expect_command=false
                        token=""
                    fi
                    ;;
                '>')
                    next="${command:$((i + 1)):1}"
                    if [[ "$next" == "(" ]]; then
                        return 0
                    fi
                    if [[ -n "$token" ]]; then
                        if assistant_shell_token_is_unsupported_syntax "$token" "$expect_command" "$in_find_command"; then
                            return 0
                        fi
                        token_is_find=false
                        if assistant_shell_command_word_matches "$token" "find"; then
                            token_is_find=true
                        fi
                        if [[ "$token_is_find" == "true" && "$expect_command" == "true" ]]; then
                            in_find_command=true
                        fi
                        expect_command=false
                        token=""
                    fi
                    ;;
                '('|')'|'{'|'}')
                    return 0
                    ;;
                *)
                    token+="$c"
                    ;;
            esac
        elif [[ "$quote" == "'" ]]; then
            if [[ "$c" == "'" ]]; then
                quote=""
            fi
        else
            if [[ "$c" == '"' ]]; then
                quote=""
            elif [[ "$c" == "\\" ]] && (( i + 1 < length )); then
                ((i += 1))
            elif [[ "$c" == '$' ]]; then
                next="${command:$((i + 1)):1}"
                if [[ "$next" == "(" ]]; then
                    return 0
                fi
            elif [[ "$c" == '`' ]]; then
                return 0
            fi
        fi
        ((i += 1))
    done

    if [[ -n "$quote" ]]; then
        return 0
    fi

    if [[ -n "$token" ]]; then
        if assistant_shell_token_is_unsupported_syntax "$token" "$expect_command" "$in_find_command"; then
            return 0
        fi
    fi

    return 1
}

assistant_shell_emit_unproven_if_unsupported_syntax() {
    local command="${1:-}"

    if assistant_shell_has_unsupported_syntax "$command"; then
        assistant_shell_emit_unproven_write_target
        return 0
    fi

    return 1
}

assistant_shell_emit_segment_if_command() {
    local segment="${1:-}"
    local command_name="${2:-}"
    local trimmed command_tail word rest status matches_status

    trimmed="$(printf '%s' "$segment" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$trimmed" ]] || return 0

    command_tail="$(assistant_shell_command_position_tail "$trimmed" || true)"
    [[ -n "$command_tail" ]] || return 0
    if assistant_shell_segment_is_unproven "$command_tail"; then
        assistant_shell_emit_unproven_write_target
        return 0
    fi

    status=0
    assistant_shell_pop_word "$command_tail" word rest || status=$?
    if (( status == 2 )); then
        assistant_shell_emit_unproven_write_target
        return 0
    fi
    if (( status == 0 )); then
        matches_status=0
        assistant_shell_command_word_matches "$word" "$command_name" || matches_status=$?
        if (( matches_status == 2 )); then
            assistant_shell_emit_unproven_write_target
            return 0
        fi
        if (( matches_status == 0 )); then
            printf '%s\n' "$command_tail"
        fi
    fi
}

assistant_shell_python_command_word_matches() {
    local word="${1:-}"
    local basename basename_status

    basename_status=0
    basename="$(assistant_shell_command_word_basename "$word")" || basename_status=$?
    case "$basename" in
        python|python[0-9]*)
            if (( basename_status == 2 )); then
                return 2
            fi
            return 0
            ;;
    esac

    return 1
}

assistant_shell_node_command_is_present() {
    local command="${1:-}"
    local segment command_tail word rest status matches_status

    while IFS= read -r segment; do
        if assistant_shell_segment_is_unproven "$segment"; then
            assistant_shell_emit_unproven_write_target
            return 0
        fi
        command_tail="$(assistant_shell_command_position_tail "$segment" || true)"
        [[ -n "$command_tail" ]] || continue
        if assistant_shell_segment_is_unproven "$command_tail"; then
            assistant_shell_emit_unproven_write_target
            return 0
        fi
        status=0
        assistant_shell_pop_word "$command_tail" word rest || status=$?
        if (( status == 2 )); then
            assistant_shell_emit_unproven_write_target
            return 0
        fi
        if (( status == 0 )); then
            matches_status=0
            assistant_shell_command_word_matches "$word" "node" || matches_status=$?
            if (( matches_status == 2 )); then
                assistant_shell_emit_unproven_write_target
                return 0
            fi
            if (( matches_status == 0 )); then
                return 0
            fi
        fi
    done < <(assistant_shell_command_segments "$command" "node")

    return 1
}

assistant_shell_python_command_is_present() {
    local command="${1:-}"
    local segment

    while IFS= read -r segment; do
        [[ -n "$segment" ]] || continue
        return 0
    done < <(assistant_shell_python_command_segments "$command")

    return 1
}

assistant_shell_emit_python_segment_if_command() {
    local segment="${1:-}"
    local trimmed command_tail word rest status matches_status

    trimmed="$(printf '%s' "$segment" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$trimmed" ]] || return 0

    command_tail="$(assistant_shell_command_position_tail "$trimmed" || true)"
    [[ -n "$command_tail" ]] || return 0
    if assistant_shell_segment_is_unproven "$command_tail"; then
        assistant_shell_emit_unproven_write_target
        return 0
    fi

    status=0
    assistant_shell_pop_word "$command_tail" word rest || status=$?
    if (( status == 2 )); then
        assistant_shell_emit_unproven_write_target
        return 0
    fi
    if (( status == 0 )); then
        matches_status=0
        assistant_shell_python_command_word_matches "$word" || matches_status=$?
        if (( matches_status == 2 )); then
            assistant_shell_emit_unproven_write_target
            return 0
        fi
        if (( matches_status == 0 )); then
            printf '%s\n' "$command_tail"
        fi
    fi
}

assistant_shell_command_segments() {
    local command="${1:-}"
    local command_name="${2:-}"
    local segment=""
    local quote=""
    local c next
    local i=0
    local length

    [[ -n "$command_name" ]] || return 0
    command="${command//$'\n'/;}"
    length="${#command}"

    while (( i < length )); do
        c="${command:$i:1}"
        if [[ -z "$quote" ]]; then
            case "$c" in
                "'")
                    quote="'"
                    segment+="$c"
                    ;;
                '"')
                    quote='"'
                    segment+="$c"
                    ;;
                "\\")
                    segment+="$c"
                    if (( i + 1 < length )); then
                        ((i += 1))
                        segment+="${command:$i:1}"
                    fi
                    ;;
                ';'|'|'|'&')
                    assistant_shell_emit_segment_if_command "$segment" "$command_name"
                    segment=""
                    next="${command:$((i + 1)):1}"
                    if [[ ( "$c" == "|" || "$c" == "&" ) && "$next" == "$c" ]]; then
                        ((i += 1))
                    fi
                    ;;
                *)
                    segment+="$c"
                    ;;
            esac
        elif [[ "$quote" == "'" ]]; then
            segment+="$c"
            if [[ "$c" == "'" ]]; then
                quote=""
            fi
        else
            segment+="$c"
            if [[ "$c" == '"' ]]; then
                quote=""
            elif [[ "$c" == "\\" ]] && (( i + 1 < length )); then
                ((i += 1))
                segment+="${command:$i:1}"
            fi
        fi
        ((i += 1))
    done

    if [[ -n "$quote" ]]; then
        assistant_shell_emit_unproven_write_target
        return 0
    fi

    assistant_shell_emit_segment_if_command "$segment" "$command_name"
}

assistant_shell_tokens_from_segment() {
    local segment="${1:-}"
    local rest word status

    rest="$segment"
    while true; do
        status=0
        assistant_shell_pop_word "$rest" word rest || status=$?
        if (( status == 1 )); then
            return 0
        fi
        if (( status == 2 )); then
            assistant_shell_emit_unproven_write_target
            return 0
        fi
        printf '%s\n' "$word"
    done
}

assistant_shell_sed_target_paths_from_segment() {
    local segment="${1:-}"
    local tokens=()
    local token next_token
    local target_operands=()
    local i count
    local inplace=false
    local script_seen=false
    local saw_target=false

    while IFS= read -r token; do
        if assistant_shell_segment_is_unproven "$token"; then
            assistant_shell_emit_unproven_write_target
            return 0
        fi
        tokens+=("$token")
    done < <(assistant_shell_tokens_from_segment "$segment")

    count="${#tokens[@]}"
    (( count > 1 )) || return 0

    i=1
    while (( i < count )); do
        token="${tokens[$i]}"
        case "$token" in
            -i|--in-place)
                inplace=true
                next_token="${tokens[$((i + 1))]:-}"
                if [[ -z "$next_token" || "$next_token" == "''" || "$next_token" == '""' ]]; then
                    ((i += 2))
                else
                    ((i += 1))
                fi
                continue
                ;;
            -i?*|--in-place=*)
                inplace=true
                ((i += 1))
                continue
                ;;
            -e|--expression|-f|--file)
                script_seen=true
                ((i += 2))
                continue
                ;;
            --expression=*|--file=*)
                script_seen=true
                ((i += 1))
                continue
                ;;
            -*)
                ((i += 1))
                continue
                ;;
        esac

        if [[ "$script_seen" != "true" ]]; then
            script_seen=true
        else
            target_operands+=("$token")
            saw_target=true
        fi
        ((i += 1))
    done

    if [[ "$inplace" == "true" ]]; then
        if [[ "$saw_target" == "true" ]]; then
            for token in "${target_operands[@]}"; do
                assistant_shell_emit_write_target_path "$token"
            done
        else
            assistant_shell_emit_unproven_write_target
        fi
    fi
}

assistant_shell_sed_target_paths() {
    local command="${1:-}"
    local segment

    while IFS= read -r segment; do
        if assistant_shell_segment_is_unproven "$segment"; then
            assistant_shell_emit_unproven_write_target
            continue
        fi
        assistant_shell_sed_target_paths_from_segment "$segment"
    done < <(assistant_shell_command_segments "$command" "sed")
}

assistant_shell_perl_target_paths_from_segment() {
    local segment="${1:-}"
    local tokens=()
    local token
    local target_operands=()
    local i count
    local inplace=false
    local saw_target=false

    while IFS= read -r token; do
        if assistant_shell_segment_is_unproven "$token"; then
            assistant_shell_emit_unproven_write_target
            return 0
        fi
        tokens+=("$token")
    done < <(assistant_shell_tokens_from_segment "$segment")

    count="${#tokens[@]}"
    (( count > 1 )) || return 0

    i=1
    while (( i < count )); do
        token="${tokens[$i]}"
        case "$token" in
            --)
                ((i += 1))
                break
                ;;
            -e|-E)
                ((i += 2))
                continue
                ;;
            -i|-i?*)
                inplace=true
                ((i += 1))
                continue
                ;;
            -?*i*)
                inplace=true
                ((i += 1))
                continue
                ;;
            -*)
                ((i += 1))
                continue
                ;;
        esac

        target_operands+=("$token")
        saw_target=true
        ((i += 1))
    done

    while (( i < count )); do
        target_operands+=("${tokens[$i]}")
        saw_target=true
        ((i += 1))
    done

    if [[ "$inplace" == "true" ]]; then
        if [[ "$saw_target" == "true" ]]; then
            for token in "${target_operands[@]}"; do
                assistant_shell_emit_write_target_path "$token"
            done
        else
            assistant_shell_emit_unproven_write_target
        fi
    fi
}

assistant_shell_perl_target_paths() {
    local command="${1:-}"
    local segment

    while IFS= read -r segment; do
        if assistant_shell_segment_is_unproven "$segment"; then
            assistant_shell_emit_unproven_write_target
            continue
        fi
        assistant_shell_perl_target_paths_from_segment "$segment"
    done < <(assistant_shell_command_segments "$command" "perl")
}

assistant_shell_last_operand_target_paths_from_segment() {
    local segment="${1:-}"
    local command_name="${2:-}"
    local tokens=()
    local token last_operand option_arg
    local i count
    local saw_operand=false
    local install_directory_mode=false
    local target_directory_mode=false

    while IFS= read -r token; do
        if assistant_shell_segment_is_unproven "$token"; then
            assistant_shell_emit_unproven_write_target
            return 0
        fi
        tokens+=("$token")
    done < <(assistant_shell_tokens_from_segment "$segment")

    count="${#tokens[@]}"
    if (( count <= 1 )); then
        assistant_shell_emit_unproven_write_target
        return 0
    fi

    i=1
    while (( i < count )); do
        token="${tokens[$i]}"
        if [[ -n "${option_arg:-}" ]]; then
            if [[ "$option_arg" == "target-directory" ]]; then
                assistant_shell_emit_write_target_path "$token"
                saw_operand=true
                target_directory_mode=true
            fi
            option_arg=""
            ((i += 1))
            continue
        fi

        case "$token" in
            --)
                ((i += 1))
                break
                ;;
            -t|--target-directory)
                option_arg="target-directory"
                ((i += 1))
                continue
                ;;
            --target-directory=*)
                assistant_shell_emit_write_target_path "${token#--target-directory=}"
                saw_operand=true
                target_directory_mode=true
                ((i += 1))
                continue
                ;;
        esac

        if [[ "$command_name" == "install" ]]; then
            case "$token" in
                -d|--directory)
                    install_directory_mode=true
                    ((i += 1))
                    continue
                    ;;
                -m|-o|-g|-S|--mode|--owner|--group|--suffix)
                    option_arg="skip"
                    ((i += 1))
                    continue
                    ;;
                --mode=*|--owner=*|--group=*|--suffix=*)
                    ((i += 1))
                    continue
                    ;;
            esac
        fi

        case "$token" in
            -*)
                ((i += 1))
                continue
                ;;
        esac

        last_operand="$token"
        saw_operand=true
        if [[ "$command_name" == "mv" ]]; then
            assistant_shell_emit_write_target_path "$token"
        fi
        if [[ "$install_directory_mode" == "true" && "$target_directory_mode" != "true" ]]; then
            assistant_shell_emit_write_target_path "$token"
        fi
        ((i += 1))
    done

    while (( i < count )); do
        last_operand="${tokens[$i]}"
        saw_operand=true
        if [[ "$command_name" == "mv" ]]; then
            assistant_shell_emit_write_target_path "${tokens[$i]}"
        fi
        if [[ "$install_directory_mode" == "true" && "$target_directory_mode" != "true" ]]; then
            assistant_shell_emit_write_target_path "${tokens[$i]}"
        fi
        ((i += 1))
    done

    if [[ "$command_name" == "mv" ]]; then
        [[ "$saw_operand" == "true" ]] || assistant_shell_emit_unproven_write_target
        return 0
    fi

    if [[ "$target_directory_mode" == "true" || "$install_directory_mode" == "true" ]]; then
        [[ "$saw_operand" == "true" ]] || assistant_shell_emit_unproven_write_target
        return 0
    fi

    if [[ -n "${last_operand:-}" ]]; then
        assistant_shell_emit_write_target_path "$last_operand"
    else
        assistant_shell_emit_unproven_write_target
    fi
}

assistant_shell_last_operand_target_paths() {
    local command="${1:-}"
    local command_name
    local segment

    for command_name in cp mv install; do
        while IFS= read -r segment; do
            if assistant_shell_segment_is_unproven "$segment"; then
                assistant_shell_emit_unproven_write_target
                continue
            fi
            assistant_shell_last_operand_target_paths_from_segment "$segment" "$command_name"
        done < <(assistant_shell_command_segments "$command" "$command_name")
    done
}

assistant_shell_operand_target_paths_from_segment() {
    local segment="${1:-}"
    local command_name="${2:-}"
    local tokens=()
    local token option_arg
    local i count
    local saw_target=false

    while IFS= read -r token; do
        if assistant_shell_segment_is_unproven "$token"; then
            assistant_shell_emit_unproven_write_target
            return 0
        fi
        tokens+=("$token")
    done < <(assistant_shell_tokens_from_segment "$segment")

    count="${#tokens[@]}"
    if (( count <= 1 )); then
        assistant_shell_emit_unproven_write_target
        return 0
    fi

    i=1
    while (( i < count )); do
        token="${tokens[$i]}"
        if [[ -n "${option_arg:-}" ]]; then
            option_arg=""
            ((i += 1))
            continue
        fi

        case "$token" in
            --)
                ((i += 1))
                break
                ;;
        esac

        if [[ "$command_name" == "touch" ]]; then
            case "$token" in
                -d|-r|-t|--date|--reference|--time)
                    option_arg="skip"
                    ((i += 1))
                    continue
                    ;;
                --date=*|--reference=*|--time=*)
                    ((i += 1))
                    continue
                    ;;
            esac
        fi

        if [[ "$command_name" == "truncate" ]]; then
            case "$token" in
                -s|-r|--size|--reference)
                    option_arg="skip"
                    ((i += 1))
                    continue
                    ;;
                --size=*|--reference=*)
                    ((i += 1))
                    continue
                    ;;
            esac
        fi

        case "$token" in
            -*)
                ((i += 1))
                continue
                ;;
        esac

        assistant_shell_emit_write_target_path "$token"
        saw_target=true
        ((i += 1))
    done

    while (( i < count )); do
        assistant_shell_emit_write_target_path "${tokens[$i]}"
        saw_target=true
        ((i += 1))
    done

    if [[ "$saw_target" != "true" ]]; then
        assistant_shell_emit_unproven_write_target
    fi
}

assistant_shell_operand_target_paths() {
    local command="${1:-}"
    local command_name
    local segment

    for command_name in rm touch truncate; do
        while IFS= read -r segment; do
            if assistant_shell_segment_is_unproven "$segment"; then
                assistant_shell_emit_unproven_write_target
                continue
            fi
            assistant_shell_operand_target_paths_from_segment "$segment" "$command_name"
        done < <(assistant_shell_command_segments "$command" "$command_name")
    done
}

assistant_shell_dd_target_paths() {
    local command="${1:-}"
    local segment token
    local saw_of

    while IFS= read -r segment; do
        if assistant_shell_segment_is_unproven "$segment"; then
            assistant_shell_emit_unproven_write_target
            continue
        fi
        saw_of=false
        while IFS= read -r token; do
            if assistant_shell_segment_is_unproven "$token"; then
                assistant_shell_emit_unproven_write_target
                return 0
            fi
            case "$token" in
                of=*)
                    saw_of=true
                    if [[ -n "${token#of=}" ]]; then
                        assistant_shell_emit_write_target_path "${token#of=}"
                    else
                        assistant_shell_emit_unproven_write_target
                    fi
                    ;;
            esac
        done < <(assistant_shell_tokens_from_segment "$segment")
    done < <(assistant_shell_command_segments "$command" "dd")
}

assistant_shell_node_write_target_paths() {
    local command="${1:-}"
    local primitive rest after path
    local saw_path=false
    local single_quote="'"

    [[ "$command" == *"writeFileSync("* || "$command" == *"appendFileSync("* || "$command" == *"createWriteStream("* ]] || return 0
    assistant_shell_node_command_is_present "$command" || return 0

    for primitive in "writeFileSync(" "appendFileSync(" "createWriteStream("; do
        rest="$command"
        while [[ "$rest" == *"$primitive"* ]]; do
            after="${rest#*"$primitive"}"
            after="$(printf '%s' "$after" | sed 's/^[[:space:]]*//')"
            if [[ "$after" == \"* && "${after#\"}" == *\"* ]]; then
                after="${after#\"}"
                path="${after%%\"*}"
                assistant_shell_emit_write_target_path "$path"
                saw_path=true
            elif [[ "$after" == "$single_quote"* && "${after#"$single_quote"}" == *"$single_quote"* ]]; then
                after="${after#"$single_quote"}"
                path="${after%%"$single_quote"*}"
                assistant_shell_emit_write_target_path "$path"
                saw_path=true
            else
                assistant_shell_emit_unproven_write_target
                saw_path=true
            fi
            rest="$after"
        done
    done

    if [[ "$saw_path" != "true" ]]; then
        assistant_shell_emit_unproven_write_target
    fi
}

assistant_shell_python_command_segments() {
    local command="${1:-}"
    local segment=""
    local quote=""
    local c next
    local i=0
    local length

    command="${command//$'\n'/;}"
    length="${#command}"

    while (( i < length )); do
        c="${command:$i:1}"
        if [[ -z "$quote" ]]; then
            case "$c" in
                "'")
                    quote="'"
                    segment+="$c"
                    ;;
                '"')
                    quote='"'
                    segment+="$c"
                    ;;
                "\\")
                    segment+="$c"
                    if (( i + 1 < length )); then
                        ((i += 1))
                        segment+="${command:$i:1}"
                    fi
                    ;;
                ';'|'|'|'&')
                    assistant_shell_emit_python_segment_if_command "$segment"
                    segment=""
                    next="${command:$((i + 1)):1}"
                    if [[ ( "$c" == "|" || "$c" == "&" ) && "$next" == "$c" ]]; then
                        ((i += 1))
                    fi
                    ;;
                *)
                    segment+="$c"
                    ;;
            esac
        elif [[ "$quote" == "'" ]]; then
            segment+="$c"
            if [[ "$c" == "'" ]]; then
                quote=""
            fi
        else
            segment+="$c"
            if [[ "$c" == '"' ]]; then
                quote=""
            elif [[ "$c" == "\\" ]] && (( i + 1 < length )); then
                ((i += 1))
                segment+="${command:$i:1}"
            fi
        fi
        ((i += 1))
    done

    if [[ -n "$quote" ]]; then
        assistant_shell_emit_unproven_write_target
        return 0
    fi

    assistant_shell_emit_python_segment_if_command "$segment"
}

assistant_shell_python_inline_code_payloads_from_segment() {
    local segment="${1:-}"
    local tokens=()
    local token
    local i count

    while IFS= read -r token; do
        if assistant_shell_segment_is_unproven "$token"; then
            assistant_shell_emit_unproven_write_target
            return 0
        fi
        tokens+=("$token")
    done < <(assistant_shell_tokens_from_segment "$segment")

    count="${#tokens[@]}"
    (( count > 1 )) || return 0

    i=1
    while (( i < count )); do
        token="${tokens[$i]}"
        case "$token" in
            --)
                return 0
                ;;
        esac

        if [[ "$token" == -* ]]; then
            if [[ "$token" == "-c" ]] || [[ "$token" == -[!-]* && "$token" == *c* ]]; then
                if (( i + 1 < count )); then
                    printf '%s\n' "${tokens[$((i + 1))]}"
                else
                    assistant_shell_emit_unproven_write_target
                fi
                return 0
            fi
            ((i += 1))
            continue
        fi

        return 0
    done
}

assistant_shell_python_code_has_unqualified_call() {
    local code="${1:-}"
    local function_name="${2:-}"
    local call_regex

    [[ -n "$function_name" ]] || return 1

    call_regex="(^|[^[:alnum:]_.])${function_name}[[:space:]]*\\("
    [[ "$code" =~ $call_regex ]]
}

assistant_shell_python_code_has_qualified_call() {
    local code="${1:-}"
    local qualifier="${2:-}"
    local function_name="${3:-}"
    local call_regex

    [[ -n "$qualifier" && -n "$function_name" ]] || return 1

    call_regex="(^|[^[:alnum:]_])${qualifier}[[:space:]]*\\.[[:space:]]*${function_name}[[:space:]]*\\("
    [[ "$code" =~ $call_regex ]]
}

assistant_shell_python_code_has_method_call() {
    local code="${1:-}"
    local method_name="${2:-}"
    local method_regex

    [[ -n "$method_name" ]] || return 1

    method_regex="\\.[[:space:]]*${method_name}[[:space:]]*\\("
    [[ "$code" =~ $method_regex ]]
}

assistant_shell_python_code_has_path_constructor_mutation_call() {
    local code="${1:-}"
    local method_name path_regex

    for method_name in touch mkdir rmdir unlink rename replace symlink_to hardlink_to chmod; do
        path_regex="(^|[^[:alnum:]_.])(Path|pathlib[[:space:]]*\\.[[:space:]]*Path)[[:space:]]*\\([^)]*\\)[[:space:]]*\\.[[:space:]]*${method_name}[[:space:]]*\\("
        if [[ "$code" =~ $path_regex ]]; then
            return 0
        fi
    done

    return 1
}

assistant_shell_python_code_has_pathlib_mutation_call() {
    local code="${1:-}"
    local method_name

    if assistant_shell_python_code_has_path_constructor_mutation_call "$code"; then
        return 0
    fi

    for method_name in touch mkdir rmdir unlink symlink_to hardlink_to chmod; do
        if assistant_shell_python_code_has_method_call "$code" "$method_name"; then
            return 0
        fi
    done

    case "$code" in
        *"from pathlib import"*|*"import pathlib"*)
            for method_name in rename replace; do
                if assistant_shell_python_code_has_method_call "$code" "$method_name"; then
                    return 0
                fi
            done
            ;;
    esac

    return 1
}

assistant_shell_python_code_has_module_alias_mutation_call() {
    local code="${1:-}"
    local module_name="${2:-}"
    local alias_regex alias function_name
    shift 2 || return 1

    alias_regex="(^|[;[:space:]])import[[:space:]]+([^;]*[,[:space:]])?${module_name}[[:space:]]+as[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)"
    if [[ "$code" =~ $alias_regex ]]; then
        alias="${BASH_REMATCH[3]}"
        for function_name in "$@"; do
            if assistant_shell_python_code_has_qualified_call "$code" "$alias" "$function_name"; then
                return 0
            fi
        done
    fi

    return 1
}

assistant_shell_python_code_has_imported_module_mutation_call() {
    local code="${1:-}"
    local module_name="${2:-}"
    local import_regex alias_regex function_name alias
    shift 2 || return 1

    import_regex="(^|[;[:space:]])from[[:space:]]+${module_name}[[:space:]]+import[[:space:]]+"
    [[ "$code" =~ $import_regex ]] || return 1

    for function_name in "$@"; do
        if assistant_shell_python_code_has_unqualified_call "$code" "$function_name"; then
            return 0
        fi
        alias_regex="(^|[;[:space:]])from[[:space:]]+${module_name}[[:space:]]+import[[:space:]]+([^;]*[,[:space:]])?${function_name}[[:space:]]+as[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)"
        if [[ "$code" =~ $alias_regex ]]; then
            alias="${BASH_REMATCH[3]}"
            if assistant_shell_python_code_has_unqualified_call "$code" "$alias"; then
                return 0
            fi
        fi
    done

    return 1
}

assistant_shell_python_code_has_module_mutation_call() {
    local code="${1:-}"
    local module_name="${2:-}"
    local function_name
    shift 2 || return 1

    for function_name in "$@"; do
        if assistant_shell_python_code_has_qualified_call "$code" "$module_name" "$function_name"; then
            return 0
        fi
    done

    if assistant_shell_python_code_has_module_alias_mutation_call "$code" "$module_name" "$@"; then
        return 0
    fi

    assistant_shell_python_code_has_imported_module_mutation_call "$code" "$module_name" "$@"
}

assistant_shell_python_code_has_opaque_mutation_primitive() {
    local code="${1:-}"

    if assistant_shell_python_code_has_pathlib_mutation_call "$code"; then
        return 0
    fi

    if assistant_shell_python_code_has_module_mutation_call "$code" "os" \
        remove unlink rmdir rename replace mkdir makedirs; then
        return 0
    fi

    if assistant_shell_python_code_has_module_mutation_call "$code" "shutil" \
        copyfile copy copy2 copytree move rmtree; then
        return 0
    fi

    return 1
}

assistant_shell_python_opaque_mutation_target_paths() {
    local command="${1:-}"
    local segment payload

    while IFS= read -r segment; do
        if assistant_shell_segment_is_unproven "$segment"; then
            assistant_shell_emit_unproven_write_target
            continue
        fi
        while IFS= read -r payload; do
            if assistant_shell_segment_is_unproven "$payload"; then
                assistant_shell_emit_unproven_write_target
            elif assistant_shell_python_code_has_opaque_mutation_primitive "$payload"; then
                assistant_shell_emit_unproven_write_target
            fi
        done < <(assistant_shell_python_inline_code_payloads_from_segment "$segment")
    done < <(assistant_shell_python_command_segments "$command")
}

assistant_shell_inline_eval_target_paths_from_segment() {
    local segment="${1:-}"
    local command_name="${2:-}"
    local tokens=()
    local token
    local i count
    local saw_inline_eval=false
    local inplace=false

    while IFS= read -r token; do
        if assistant_shell_segment_is_unproven "$token"; then
            assistant_shell_emit_unproven_write_target
            return 0
        fi
        tokens+=("$token")
    done < <(assistant_shell_tokens_from_segment "$segment")

    count="${#tokens[@]}"
    (( count > 1 )) || return 0

    i=1
    while (( i < count )); do
        token="${tokens[$i]}"
        case "$token" in
            --)
                break
                ;;
        esac

        case "$command_name" in
            ruby)
                case "$token" in
                    -e|-e?*|-[!-]*e*)
                        assistant_shell_emit_unproven_write_target
                        return 0
                        ;;
                esac
                ;;
            php)
                case "$token" in
                    -r|-r?*)
                        assistant_shell_emit_unproven_write_target
                        return 0
                        ;;
                esac
                ;;
            perl)
                case "$token" in
                    -i|-i?*|-?*i*)
                        inplace=true
                        ;;
                    -e|-E|-e?*|-E?*|-[!-]*e*|-[!-]*E*)
                        saw_inline_eval=true
                        ((i += 2))
                        continue
                        ;;
                esac
                ;;
        esac

        ((i += 1))
    done

    if [[ "$command_name" == "perl" && "$saw_inline_eval" == "true" && "$inplace" != "true" ]]; then
        assistant_shell_emit_unproven_write_target
    fi
}

assistant_shell_awk_inline_eval_target_paths_from_segment() {
    local segment="${1:-}"
    local tokens=()
    local token option_arg
    local i count

    while IFS= read -r token; do
        if assistant_shell_segment_is_unproven "$token"; then
            assistant_shell_emit_unproven_write_target
            return 0
        fi
        tokens+=("$token")
    done < <(assistant_shell_tokens_from_segment "$segment")

    count="${#tokens[@]}"
    (( count > 1 )) || return 0

    i=1
    while (( i < count )); do
        token="${tokens[$i]}"
        if [[ -n "${option_arg:-}" ]]; then
            option_arg=""
            ((i += 1))
            continue
        fi

        case "$token" in
            --)
                ((i += 1))
                break
                ;;
            -f|--file|-F|-v|-W)
                option_arg="skip"
                ((i += 1))
                continue
                ;;
            -f?*|--file=*|-F?*|-v?*|-W?*)
                ((i += 1))
                continue
                ;;
            -*)
                ((i += 1))
                continue
                ;;
        esac

        assistant_shell_emit_unproven_write_target
        return 0
    done
}

assistant_shell_inline_eval_target_paths() {
    local command="${1:-}"
    local segment command_name

    for command_name in ruby php perl; do
        while IFS= read -r segment; do
            if assistant_shell_segment_is_unproven "$segment"; then
                assistant_shell_emit_unproven_write_target
                continue
            fi
            assistant_shell_inline_eval_target_paths_from_segment "$segment" "$command_name"
        done < <(assistant_shell_command_segments "$command" "$command_name")
    done

    while IFS= read -r segment; do
        if assistant_shell_segment_is_unproven "$segment"; then
            assistant_shell_emit_unproven_write_target
            continue
        fi
        assistant_shell_awk_inline_eval_target_paths_from_segment "$segment"
    done < <(assistant_shell_command_segments "$command" "awk")
}

assistant_shell_emit_redirection_target_from_text() {
    local text="${1:-}"
    local target rest status

    text="$(printf '%s' "$text" | sed 's/^[[:space:]]*//')"
    [[ -n "$text" ]] || {
        assistant_shell_emit_unproven_write_target
        return 0
    }

    case "$text" in
        '&'[0-9]*|'&-')
            return 0
            ;;
    esac

    status=0
    assistant_shell_pop_word "$text" target rest || status=$?
    if (( status != 0 )); then
        assistant_shell_emit_unproven_write_target
        return 0
    fi

    case "$target" in
        '&'[0-9]*|'&-')
            return 0
            ;;
    esac

    assistant_shell_emit_write_target_path "$target"
}

assistant_shell_redirection_target_paths() {
    local command="${1:-}"
    local quote=""
    local c next rest
    local i=0
    local length
    local target_offset

    command="${command//$'\n'/ }"
    length="${#command}"

    while (( i < length )); do
        c="${command:$i:1}"
        if [[ -z "$quote" ]]; then
            case "$c" in
                "'")
                    quote="'"
                    ;;
                '"')
                    quote='"'
                    ;;
                "\\")
                    if (( i + 1 < length )); then
                        ((i += 1))
                    fi
                    ;;
                '&')
                    next="${command:$((i + 1)):1}"
                    if [[ "$next" == ">" ]]; then
                        target_offset=$((i + 2))
                        if [[ "${command:$target_offset:1}" == ">" ]]; then
                            target_offset=$((target_offset + 1))
                        fi
                        rest="${command:$target_offset}"
                        assistant_shell_emit_redirection_target_from_text "$rest"
                    fi
                    ;;
                '>')
                    target_offset=$((i + 1))
                    next="${command:$target_offset:1}"
                    if [[ "$next" == ">" || "$next" == "|" ]]; then
                        target_offset=$((target_offset + 1))
                    fi
                    rest="${command:$target_offset}"
                    assistant_shell_emit_redirection_target_from_text "$rest"
                    ;;
            esac
        elif [[ "$quote" == "'" ]]; then
            if [[ "$c" == "'" ]]; then
                quote=""
            fi
        else
            if [[ "$c" == '"' ]]; then
                quote=""
            elif [[ "$c" == "\\" ]] && (( i + 1 < length )); then
                ((i += 1))
            fi
        fi
        ((i += 1))
    done

    if [[ -n "$quote" ]]; then
        assistant_shell_emit_unproven_write_target
    fi
}

assistant_shell_tee_target_paths_from_segment() {
    local segment="${1:-}"
    local tokens=()
    local token option_arg
    local i count

    while IFS= read -r token; do
        if assistant_shell_segment_is_unproven "$token"; then
            assistant_shell_emit_unproven_write_target
            return 0
        fi
        tokens+=("$token")
    done < <(assistant_shell_tokens_from_segment "$segment")

    count="${#tokens[@]}"
    (( count > 1 )) || {
        assistant_shell_emit_unproven_write_target
        return 0
    }

    i=1
    while (( i < count )); do
        token="${tokens[$i]}"
        if [[ -n "${option_arg:-}" ]]; then
            option_arg=""
            ((i += 1))
            continue
        fi
        case "$token" in
            --)
                ((i += 1))
                break
                ;;
            -a|--append|-i|--ignore-interrupts|-p|--output-error)
                ((i += 1))
                continue
                ;;
            --output-error=*)
                ((i += 1))
                continue
                ;;
            -*)
                ((i += 1))
                continue
                ;;
        esac
        if [[ "$token" =~ ^[0-9]+$ ]]; then
            ((i += 1))
            continue
        fi
        assistant_shell_emit_write_target_path "$token"
        ((i += 1))
    done

    while (( i < count )); do
        assistant_shell_emit_write_target_path "${tokens[$i]}"
        ((i += 1))
    done
}

assistant_shell_tee_target_paths() {
    local command="${1:-}"
    local segment

    while IFS= read -r segment; do
        if assistant_shell_segment_is_unproven "$segment"; then
            assistant_shell_emit_unproven_write_target
            continue
        fi
        assistant_shell_tee_target_paths_from_segment "$segment"
    done < <(assistant_shell_command_segments "$command" "tee")
}

assistant_shell_python_has_write_primitive() {
    local command="${1:-}"
    local open_positional_write_double_regex open_positional_write_single_regex
    local open_method_write_double_regex open_method_write_single_regex
    local mode_write_double_regex mode_write_single_regex

    assistant_shell_python_command_is_present "$command" || return 1
    [[ "$command" == *".write_text("* || "$command" == *".write_bytes("* ]] && return 0
    [[ "$command" == *"open("* && "$command" == *".write("* ]] && return 0

    open_positional_write_double_regex='(^|[^[:alnum:]_.])open[[:space:]]*\([^)]*,[[:space:]]*"[^"]*[wax+][^"]*"'
    open_positional_write_single_regex="(^|[^[:alnum:]_.])open[[:space:]]*\\([^)]*,[[:space:]]*'[^']*[wax+][^']*'"
    open_method_write_double_regex='\.open[[:space:]]*\([[:space:]]*"[^"]*[wax+][^"]*"'
    open_method_write_single_regex="\\.open[[:space:]]*\\([[:space:]]*'[^']*[wax+][^']*'"
    mode_write_double_regex='mode[[:space:]]*=[[:space:]]*"[^"]*[wax+][^"]*"'
    mode_write_single_regex="mode[[:space:]]*=[[:space:]]*'[^']*[wax+][^']*'"

    [[ "$command" =~ $open_positional_write_double_regex \
        || "$command" =~ $open_positional_write_single_regex \
        || "$command" =~ $open_method_write_double_regex \
        || "$command" =~ $open_method_write_single_regex \
        || ( "$command" == *"open("* && "$command" =~ $mode_write_double_regex ) \
        || ( "$command" == *"open("* && "$command" =~ $mode_write_single_regex ) ]]
}

assistant_shell_python_mode_is_write_mode() {
    local mode="${1:-}"

    [[ "$mode" == *w* || "$mode" == *a* || "$mode" == *x* || "$mode" == *+* ]]
}

assistant_shell_python_open_args_have_write_mode() {
    local args="${1:-}"
    local call_args positional mode
    local single_quote="'"
    local keyword_double_regex='(^|,)[[:space:]]*mode[[:space:]]*=[[:space:]]*"([^"]*)"'
    local keyword_single_regex="(^|,)[[:space:]]*mode[[:space:]]*=[[:space:]]*'([^']*)'"

    call_args="${args%%)*}"

    if [[ "$call_args" =~ $keyword_double_regex ]]; then
        mode="${BASH_REMATCH[2]}"
        assistant_shell_python_mode_is_write_mode "$mode"
        return $?
    fi
    if [[ "$call_args" =~ $keyword_single_regex ]]; then
        mode="${BASH_REMATCH[2]}"
        assistant_shell_python_mode_is_write_mode "$mode"
        return $?
    fi

    positional="$(printf '%s' "$call_args" | sed 's/^[[:space:]]*//')"
    if [[ "$positional" == ","* ]]; then
        positional="${positional#,}"
        positional="$(printf '%s' "$positional" | sed 's/^[[:space:]]*//')"
    fi

    if [[ "$positional" == \"* && "${positional#\"}" == *\"* ]]; then
        positional="${positional#\"}"
        mode="${positional%%\"*}"
        assistant_shell_python_mode_is_write_mode "$mode"
        return $?
    fi
    if [[ "$positional" == "$single_quote"* && "${positional#"$single_quote"}" == *"$single_quote"* ]]; then
        positional="${positional#"$single_quote"}"
        mode="${positional%%"$single_quote"*}"
        assistant_shell_python_mode_is_write_mode "$mode"
        return $?
    fi

    return 1
}

assistant_shell_python_write_target_paths() {
    local command="${1:-}"
    local rest before after path after_quote open_after saw_path=false
    local single_quote="'"

    assistant_shell_python_has_write_primitive "$command" || return 0

    rest="$command"
    while [[ "$rest" == *"Path("* ]]; do
        after="${rest#*"Path("}"
        if [[ "$after" == \"* && "${after#\"}" == *\"* ]]; then
            after="${after#\"}"
            path="${after%%\"*}"
            after_quote="${after#*\"}"
            if [[ "$after_quote" == *").write_text("* || "$after_quote" == *").write_bytes("* ]]; then
                assistant_shell_emit_write_target_path "$path"
                saw_path=true
            elif [[ "$after_quote" == *").open("* ]]; then
                open_after="${after_quote#*").open("}"
                if assistant_shell_python_open_args_have_write_mode "$open_after"; then
                    assistant_shell_emit_write_target_path "$path"
                    saw_path=true
                elif [[ "$open_after" == *".write("* ]]; then
                    assistant_shell_emit_unproven_write_target
                    saw_path=true
                fi
            fi
        elif [[ "$after" == "$single_quote"* && "${after#"$single_quote"}" == *"$single_quote"* ]]; then
            after="${after#"$single_quote"}"
            path="${after%%"$single_quote"*}"
            after_quote="${after#*"$single_quote"}"
            if [[ "$after_quote" == *").write_text("* || "$after_quote" == *").write_bytes("* ]]; then
                assistant_shell_emit_write_target_path "$path"
                saw_path=true
            elif [[ "$after_quote" == *").open("* ]]; then
                open_after="${after_quote#*").open("}"
                if assistant_shell_python_open_args_have_write_mode "$open_after"; then
                    assistant_shell_emit_write_target_path "$path"
                    saw_path=true
                elif [[ "$open_after" == *".write("* ]]; then
                    assistant_shell_emit_unproven_write_target
                    saw_path=true
                fi
            fi
        fi
        rest="$after"
    done

    rest="$command"
    while [[ "$rest" == *"open("* ]]; do
        before="${rest%%"open("*}"
        after="${rest#*"open("}"
        if [[ "${before: -1}" == "." ]]; then
            rest="$after"
            continue
        fi
        if [[ "$after" == \"* && "${after#\"}" == *\"* ]]; then
            after="${after#\"}"
            path="${after%%\"*}"
            after_quote="${after#*\"}"
            if assistant_shell_python_open_args_have_write_mode "$after_quote"; then
                assistant_shell_emit_write_target_path "$path"
                saw_path=true
            elif [[ "$after_quote" == *".write("* ]]; then
                assistant_shell_emit_unproven_write_target
                saw_path=true
            fi
        elif [[ "$after" == "$single_quote"* && "${after#"$single_quote"}" == *"$single_quote"* ]]; then
            after="${after#"$single_quote"}"
            path="${after%%"$single_quote"*}"
            after_quote="${after#*"$single_quote"}"
            if assistant_shell_python_open_args_have_write_mode "$after_quote"; then
                assistant_shell_emit_write_target_path "$path"
                saw_path=true
            elif [[ "$after_quote" == *".write("* ]]; then
                assistant_shell_emit_unproven_write_target
                saw_path=true
            fi
        else
            if assistant_shell_python_open_args_have_write_mode "$after" || [[ "$after" == *".write("* ]]; then
                assistant_shell_emit_unproven_write_target
                saw_path=true
            fi
        fi
        rest="$after"
    done

    if [[ "$saw_path" != "true" ]]; then
        printf '%s\n' "__assistant_unproven_shell_write_target__"
    fi
}

assistant_shell_direct_write_target_paths() {
    local command="${1:-}"

    assistant_shell_redirection_target_paths "$command"
    assistant_shell_tee_target_paths "$command"
    assistant_shell_python_opaque_mutation_target_paths "$command"
    assistant_shell_python_write_target_paths "$command"
    assistant_shell_sed_target_paths "$command"
    assistant_shell_perl_target_paths "$command"
    assistant_shell_last_operand_target_paths "$command"
    assistant_shell_operand_target_paths "$command"
    assistant_shell_dd_target_paths "$command"
    assistant_shell_node_write_target_paths "$command"
    assistant_shell_inline_eval_target_paths "$command"
}

assistant_shell_env_unwrapped_commands() {
    local command="${1:-}"
    local trimmed rest env_word word after_word status command_name_status command_name

    trimmed="$(assistant_shell_command_position_tail "$command" || true)"
    [[ -n "$trimmed" ]] || return 0
    if assistant_shell_segment_is_unproven "$trimmed"; then
        assistant_shell_emit_unproven_write_target
        return 0
    fi
    status=0
    assistant_shell_pop_word "$trimmed" env_word rest || status=$?
    if (( status == 2 )); then
        assistant_shell_emit_unproven_write_target
        return 0
    fi
    command_name_status=0
    command_name="$(assistant_shell_command_word_basename "$env_word")" || command_name_status=$?
    [[ "$command_name" == "env" ]] || return 0
    if (( command_name_status == 2 )); then
        assistant_shell_emit_unproven_write_target
        return 0
    fi

    while true; do
        status=0
        assistant_shell_pop_word "$rest" word after_word || status=$?
        if (( status == 1 )); then
            return 0
        elif (( status == 2 )); then
            assistant_shell_emit_unproven_write_target
            return 0
        fi

        case "$word" in
            -i|--ignore-environment|-0|--null)
                rest="$after_word"
                continue
                ;;
            -u|--unset|-C|--chdir)
                status=0
                assistant_shell_pop_word "$after_word" word rest || status=$?
                if (( status != 0 )); then
                    assistant_shell_emit_unproven_write_target
                    return 0
                fi
                continue
                ;;
            --unset=*|--chdir=*)
                rest="$after_word"
                continue
                ;;
            -*)
                assistant_shell_emit_unproven_write_target
                return 0
                ;;
        esac

        if [[ "$word" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            rest="$after_word"
            continue
        fi

        if assistant_shell_token_is_unsupported_syntax "$word" "true" "false"; then
            assistant_shell_emit_unproven_write_target
            return 0
        fi

        command_name_status=0
        command_name="$(assistant_shell_command_word_basename "$word")" || command_name_status=$?
        case "$command_name" in
            bash|sh|zsh|node|python|python[0-9]*|sed|perl|cp|mv|rm|touch|install|truncate|dd|tee)
                if (( command_name_status == 2 )); then
                    assistant_shell_emit_unproven_write_target
                    return 0
                fi
                if [[ -n "$after_word" ]]; then
                    printf '%s %s\n' "$word" "$after_word"
                else
                    printf '%s\n' "$word"
                fi
                ;;
            *)
                assistant_shell_emit_unproven_write_target
                ;;
        esac
        return 0
    done
}

assistant_shell_c_payloads_from_segment() {
    local segment="${1:-}"
    local shell_name="${2:-}"
    local rest shell_word word payload status matches_status

    status=0
    assistant_shell_pop_word "$segment" shell_word rest || status=$?
    if (( status != 0 )); then
        assistant_shell_emit_unproven_write_target
        return 0
    fi

    matches_status=0
    assistant_shell_command_word_matches "$shell_word" "$shell_name" || matches_status=$?
    if (( matches_status == 2 )); then
        assistant_shell_emit_unproven_write_target
        return 0
    fi
    (( matches_status == 0 )) || return 0

    while true; do
        status=0
        assistant_shell_pop_word "$rest" word rest || status=$?
        if (( status == 1 )); then
            return 0
        elif (( status == 2 )); then
            assistant_shell_emit_unproven_write_target
            return 0
        fi

        if [[ "$word" == "--" ]]; then
            return 0
        fi

        if [[ "$word" == -* ]]; then
            if [[ "$word" == "-c" ]] || [[ "$word" == -[!-]* && "$word" == *c* ]]; then
                status=0
                assistant_shell_pop_word "$rest" payload rest || status=$?
                if (( status != 0 )); then
                    assistant_shell_emit_unproven_write_target
                elif assistant_shell_word_is_dynamic "$payload"; then
                    assistant_shell_emit_unproven_write_target
                else
                    printf '%s\n' "$payload"
                fi
                return 0
            fi

            case "$word" in
                -o|-O|--init-file|--rcfile)
                    status=0
                    assistant_shell_pop_word "$rest" word rest || status=$?
                    if (( status != 0 )); then
                        assistant_shell_emit_unproven_write_target
                        return 0
                    fi
                    ;;
            esac
            continue
        fi

        return 0
    done
}

assistant_shell_c_payload_commands() {
    local command="${1:-}"
    local shell_name segment

    for shell_name in bash sh zsh; do
        while IFS= read -r segment; do
            if assistant_shell_segment_is_unproven "$segment"; then
                assistant_shell_emit_unproven_write_target
                continue
            fi
            assistant_shell_c_payloads_from_segment "$segment" "$shell_name"
        done < <(assistant_shell_command_segments "$command" "$shell_name")
    done
}

assistant_shell_indirect_command_payloads() {
    local command="${1:-}"
    local unwrapped

    if assistant_shell_has_command_substitution "$command"; then
        assistant_shell_emit_unproven_write_target
    fi

    assistant_shell_c_payload_commands "$command"

    while IFS= read -r unwrapped; do
        [[ -n "$unwrapped" ]] || continue
        if [[ "$unwrapped" == "__assistant_unproven_shell_write_target__" ]]; then
            assistant_shell_emit_unproven_write_target
            continue
        fi
        printf '%s\n' "$unwrapped"
        assistant_shell_c_payload_commands "$unwrapped"
    done < <(assistant_shell_env_unwrapped_commands "$command")
}

assistant_shell_write_target_paths() {
    local command="${1:-}"
    local payload

    if assistant_shell_is_apply_patch_heredoc_command "$command"; then
        return 0
    fi
    if assistant_shell_emit_unproven_if_unsupported_syntax "$command"; then
        return 0
    fi

    assistant_shell_direct_write_target_paths "$command"

    while IFS= read -r payload; do
        [[ -n "$payload" ]] || continue
        if [[ "$payload" == "__assistant_unproven_shell_write_target__" ]]; then
            assistant_shell_emit_unproven_write_target
        elif assistant_shell_is_apply_patch_heredoc_command "$payload"; then
            continue
        elif assistant_shell_emit_unproven_if_unsupported_syntax "$payload"; then
            continue
        else
            assistant_shell_direct_write_target_paths "$payload"
        fi
    done < <(assistant_shell_indirect_command_payloads "$command")
}

assistant_builder_tester_bash_disallowed_write_target() {
    local command="${1:-}"
    local path

    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        if [[ "$path" == "__assistant_unproven_shell_write_target__" ]]; then
            printf '%s\n' "unproven shell write target"
            return 0
        fi
        if ! assistant_builder_tester_path_allowed "$path"; then
            printf '%s\n' "$path"
            return 0
        fi
    done < <(assistant_shell_write_target_paths "$command")

    return 1
}
