#!/usr/bin/env bash
# metrics.sh -- Workflow metrics gate helpers.

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

assistant_phase_metrics_status() {
    if assistant_phase_has_metrics_today; then
        printf 'recorded\n'
    else
        # Metrics are optional observability. Missing configuration, policy
        # permission, directory, or today's entry never blocks completion.
        printf 'missing_optional\n'
    fi
}
