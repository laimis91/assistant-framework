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

assistant_phase_has_component_approval() {
    local file="$1"
    awk '
        {
            line = tolower($0)
        }
        line ~ /^component decomposition approval:[[:space:]]*yes([[:space:]]|$)/ {
            found = 1
        }
        line ~ /^component approval:[[:space:]]*yes([[:space:]]|$)/ {
            found = 1
        }
        line ~ /^approval status:/ && line ~ /approved/ && line !~ /(not approved|unapproved|pending)/ {
            found = 1
        }
        line ~ /decompose complete \(approved\)/ {
            found = 1
        }
        END {
            exit found ? 0 : 1
        }
    ' "$file" 2>/dev/null
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
