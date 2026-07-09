#!/usr/bin/env bash
# subagent-evidence.sh -- Subagent role inference and lifecycle evidence helpers.

assistant_phase_is_codex_task() {
    local file="$1"
    [[ "$file" == */.codex/task.md || "$file" == .codex/task.md ]]
}

assistant_phase_subagent_project_dir() {
    local file="$1"
    local project_dir

    project_dir="$(dirname "$(dirname "$file")")"
    assistant_hook_canonical_existing_dir "$project_dir"
}

assistant_phase_subagent_events_file() {
    local file="$1"
    local project_dir task_identity

    if assistant_phase_is_codex_task "$file"; then
        project_dir="$(assistant_phase_subagent_project_dir "$file")" || return 1
        task_identity="$(assistant_hook_task_identity_from_file "$file")" || return 1
        assistant_hook_codex_subagent_events_file_for_project "$project_dir" "$task_identity"
        return $?
    fi

    printf '%s/subagent-events.jsonl\n' "$(dirname "$file")"
}

assistant_phase_role_agent_pattern() {
    case "$1" in
        "Code Mapper") printf 'code-mapper|codemapper|Code Mapper' ;;
        "Explorer") printf 'explorer|Explorer' ;;
        "Architect") printf 'architect|Architect' ;;
        "Code Writer") printf 'code-writer|codewriter|Code Writer' ;;
        "Builder/Tester") printf 'builder-tester|builder/tester|Builder/Tester' ;;
        "Code Reviewer") printf 'code-reviewer|codereviewer|Code Reviewer|reviewer|Reviewer' ;;
        "QA Evaluator") printf 'qa-evaluator|qaevaluator|QA Evaluator' ;;
        "Reviewer") printf 'reviewer|Reviewer|code-reviewer|codereviewer|Code Reviewer' ;;
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
    local pattern agent_type agent_name name
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
    local events_file task_identity line id event_task_identity
    task_identity="$(assistant_hook_task_identity_from_file "$file")" || return 1
    events_file="$(assistant_phase_subagent_events_file "$file")" || return 1
    [[ -f "$events_file" ]] || return 1
    while IFS= read -r line; do
        [[ "$line" == *"\"event\":\"$event\""* ]] || continue
        event_task_identity="$(assistant_phase_json_field_value "$line" "task_identity")"
        [[ "$event_task_identity" == "$task_identity" ]] || continue
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
    printf '%s\n' "$combined" | assistant_phase_text_mentions_agent_id_token "$agent_id"
}

assistant_phase_text_mentions_agent_id_token() {
    local agent_id="$1"
    [[ -n "$agent_id" ]] || return 1
    awk -v needle="$agent_id" '
        function is_token_char(ch) {
            return ch ~ /^[[:alnum:]_-]$/
        }
        {
            start = 1
            while ((relative = index(substr($0, start), needle)) > 0) {
                absolute = start + relative - 1
                before = absolute > 1 ? substr($0, absolute - 1, 1) : ""
                after_pos = absolute + length(needle)
                after = after_pos <= length($0) ? substr($0, after_pos, 1) : ""
                if (!is_token_char(before) && !is_token_char(after)) {
                    found = 1
                    exit
                }
                start = absolute + length(needle)
            }
        }
        END {
            exit found ? 0 : 1
        }
    '
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

assistant_phase_role_evidence_labels() {
    case "$1" in
        "Code Reviewer")
            printf 'Code Reviewer\nReviewer\n'
            ;;
        "Reviewer")
            printf 'Code Reviewer\nReviewer\n'
            ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
}

assistant_phase_has_single_role_dispatch_result_evidence() {
    local file="$1"
    local role="$2"

    assistant_phase_has_labeled_evidence "$file" "$role dispatch" \
        && assistant_phase_has_labeled_evidence "$file" "$role result" \
        || return 1

    # Codex task journals are not sufficient proof by themselves: Codex can write
    # fake dispatch text after doing work inline. Require protected lifecycle
    # evidence captured by SubagentStart/SubagentStop hooks for delegated roles.
    if assistant_phase_is_codex_task "$file"; then
        assistant_phase_has_role_start_event_evidence "$file" "$role" \
            && assistant_phase_has_role_stop_event_evidence "$file" "$role"
        return $?
    fi

    return 0
}

assistant_phase_has_role_dispatch_result_evidence() {
    local file="$1"
    local role="$2"
    local evidence_role

    while IFS= read -r evidence_role; do
        [[ -n "$evidence_role" ]] || continue
        assistant_phase_has_single_role_dispatch_result_evidence "$file" "$evidence_role" && return 0
    done < <(assistant_phase_role_evidence_labels "$role")

    return 1
}

assistant_phase_direct_fallback_reason_valid() {
    local file="$1"
    grep -qiE "^[[:space:]]*[-*]?[[:space:]]*Direct fallback reason:[[:space:]]*(authorization_denied|subagents_unavailable|policy_disallowed)([[:space:]]|$)" "$file" 2>/dev/null
}

assistant_phase_has_single_role_equivalent_evidence() {
    local file="$1"
    local role="$2"
    assistant_phase_has_labeled_evidence "$file" "$role direct evidence"
}

assistant_phase_has_role_equivalent_evidence() {
    local file="$1"
    local role="$2"
    local evidence_role

    while IFS= read -r evidence_role; do
        [[ -n "$evidence_role" ]] || continue
        assistant_phase_has_single_role_equivalent_evidence "$file" "$evidence_role" && return 0
    done < <(assistant_phase_role_evidence_labels "$role")

    return 1
}

assistant_phase_has_per_slice_dispatch_evidence() {
    local file="$1"
    ! assistant_phase_is_medium_plus "$file" && return 0
    assistant_phase_has_labeled_evidence "$file" "Per-slice dispatch evidence"
}

assistant_phase_has_explicit_no_source_changes() {
    local file="$1"
    awk '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        function value_after_colon(line, value) {
            value = line
            sub(/^[^:]*:[[:space:]]*/, "", value)
            return trim(value)
        }
        {
            line = $0
            sub(/^[[:space:]]*[-*]?[[:space:]]*/, "", line)
            low = tolower(line)
            if (low ~ /^(source changes|source change|source-changing|project source changes|production source changes|source files changed|source-changing work)[[:space:]]*:/) {
                value = tolower(value_after_colon(line))
                if (value ~ /^(no|none)([[:space:][:punct:]]|$)/) {
                    found = 1
                }
            }
            if (low ~ /^no source changes[[:space:]]*:/) {
                value = tolower(value_after_colon(line))
                if (value ~ /^(yes|true)([[:space:][:punct:]]|$)/) {
                    found = 1
                }
            }
        }
        END {
            exit found ? 0 : 1
        }
    ' "$file" 2>/dev/null
}

assistant_phase_task_type_is_development_work() {
    local file="$1"
    local task_type
    task_type="$(assistant_phase_scalar_field "$file" "Task type" | tr '[:upper:]' '[:lower:]' | xargs 2>/dev/null || true)"
    [[ "$task_type" =~ ^(feature|bugfix|refactor|migration|rewrite|config|infra|security|docs|test|tests|tooling|dev|development|code)$ ]]
}

assistant_phase_journal_mentions_source_change_path() {
    local file="$1"
    awk '
        function source_path(line, low) {
            low = tolower(line)
            if (low ~ /\.(codex|claude|gemini)\//) {
                return 0
            }
            return low ~ /(^|[[:space:]`"'\''(|])(\.?\/)?(agents|codex-rules|docs|hooks|skills|tests|tools)\// ||
                low ~ /(^|[[:space:]`"'\''(|])(agents\.md|claude\.md|readme\.md|install\.sh)([[:space:]`"'\'')]|$)/ ||
                low ~ /\.(bash|cs|csproj|json|md|props|sh|sln|targets|toml|yaml|yml)([[:space:]`"'\'')]|$)/
        }
        {
            line = $0
            low = tolower(line)
            if (low ~ /(likely touched paths|changed files|modified files|files changed|artifact registry)/) {
                in_paths = 1
                if (source_path(line)) {
                    found = 1
                }
                next
            }
            if (in_paths && line ~ /^[[:space:]]*([-*]|\|)/) {
                if (source_path(line)) {
                    found = 1
                }
                next
            }
            if (in_paths && line ~ /^[^[:space:]-|]/) {
                in_paths = 0
            }
        }
        END {
            exit found ? 0 : 1
        }
    ' "$file" 2>/dev/null
}

assistant_phase_journal_declares_source_changes() {
    local file="$1"
    grep -qiE "^[[:space:]]*[-*]?[[:space:]]*(Source changes|Source change|Source-changing|Project source changes|Production source changes|Source files changed|Source-changing work):[[:space:]]*(yes|true|required|will|planned|expected|source-changing)([[:space:][:punct:]]|$)" "$file" 2>/dev/null
}

assistant_phase_source_changing_work() {
    local file="$1"
    local status="$2"
    local status_lc

    assistant_phase_has_explicit_no_source_changes "$file" && return 1
    assistant_phase_journal_declares_source_changes "$file" && return 0
    assistant_phase_journal_mentions_source_change_path "$file" && return 0

    status_lc="$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')"
    if [[ "$status_lc" =~ (building|verifying) ]] && assistant_phase_task_type_is_development_work "$file"; then
        return 0
    fi

    return 1
}

assistant_phase_required_subagent_roles() {
    local file="$1"
    local status mode qa_required source_changing
    status="$(assistant_phase_status "$file" | tr '[:upper:]' '[:lower:]' || true)"
    mode="$(assistant_phase_subagent_mode "$file" | tr '[:upper:]' '[:lower:]' | xargs 2>/dev/null || true)"
    qa_required="$(assistant_phase_requires_qa_evaluator "$file" && printf yes || printf no)"
    source_changing="$(assistant_phase_source_changing_work "$file" "$status" && printf yes || printf no)"
    awk -v is_medium_plus="$(assistant_phase_is_medium_plus "$file" && printf yes || printf no)" -v status="$status" -v mode="$mode" -v qa_required="$qa_required" -v source_changing="$source_changing" '
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
            if (qa_required == "yes" && low ~ /qa[ _-]?evaluator|qaevaluator/) emit("QA Evaluator")
            if (low ~ /code[ _-]?reviewer|codereviewer/) {
                emit("Code Reviewer")
            } else if (low ~ /(^|[^[:alnum:]_-])reviewer([^[:alnum:]_-]|$)/) {
                emit("Code Reviewer")
            }
        }
        BEGIN {
            if (source_changing == "yes") {
                emit("Code Writer")
                emit("Builder/Tester")
                emit("Code Reviewer")
            }
            # Medium+ discovery always requires a Code Mapper context map once
            # subagent execution mode has been resolved. Add the role from task
            # size even if the journal forgot to list it.
            if (mode ~ /^(delegated|direct_fallback)$/ && is_medium_plus == "yes") emit("Code Mapper")
            # Once a delegated/fallback task is in Review/Document, the review
            # role is required even for no-op/no-code-change outcomes; otherwise
            # "review phase" can be satisfied inline while claiming delegated mode.
            if (mode ~ /^(delegated|direct_fallback)$/ && status ~ /(reviewing|documenting)/) emit("Code Reviewer")
            if (qa_required == "yes") emit("QA Evaluator")
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

assistant_phase_qa_evaluator_subagent_evidence_is_actionable() {
    [[ "$(assistant_phase_review_missing_reason_key "$1")" == "complete" ]]
}
