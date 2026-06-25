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
            print NR
            found = 1
            exit
        }
        END {
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

assistant_phase_review_complete() {
    local file="$1"
    local spec_pass_line
    local quality_review_line

    spec_pass_line="$(assistant_phase_latest_spec_review_pass_line "$file" || true)"
    [[ -n "$spec_pass_line" ]] || return 1

    quality_review_line="$(assistant_phase_quality_review_after_line "$file" "$spec_pass_line" || true)"
    [[ -n "$quality_review_line" ]] || return 1

    assistant_phase_final_result_after_line "$file" "$quality_review_line" >/dev/null
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
