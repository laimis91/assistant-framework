#!/usr/bin/env bash

set -euo pipefail

usage() {
    printf 'Usage: %s TASK_JOURNAL\n' "$(basename "$0")" >&2
}

if [[ "$#" -ne 1 ]]; then
    usage
    exit 2
fi

journal="$1"
if [[ ! -f "$journal" ]]; then
    printf 'Learning state journal not found: %s\n' "$journal" >&2
    exit 2
fi

active_section="$(awk '
    BEGIN { capture = 0 }
    /^Learning capture mode:[[:space:]]*/ { capture = 1 }
    capture && /^---[[:space:]]*$/ { exit }
    capture { print }
' "$journal")"

if [[ -z "$active_section" ]]; then
    printf 'Missing Learning capture mode in %s\n' "$journal" >&2
    exit 1
fi

mode="$(printf '%s\n' "$active_section" | sed -n 's/^Learning capture mode:[[:space:]]*//p' | head -n 1)"
reason="$(printf '%s\n' "$active_section" | sed -n 's/^Learning capture reason:[[:space:]]*//p' | head -n 1)"
signals="$(printf '%s\n' "$active_section" | sed -n 's/^Learning evidence signals:[[:space:]]*//p' | head -n 1)"

case "$mode" in
    auto|required|not_required) ;;
    *)
        printf 'Invalid Learning capture mode: %s\n' "${mode:-<missing>}" >&2
        exit 1
        ;;
esac

if [[ -z "$reason" ]]; then
    printf 'Missing Learning capture reason for mode %s\n' "$mode" >&2
    exit 1
fi

if [[ -z "$signals" ]]; then
    printf 'Missing Learning evidence signals ledger for mode %s\n' "$mode" >&2
    exit 1
fi

signal_list=()
IFS=',' read -r -a signal_list <<<"$signals"
has_none=false
has_evidence=false
for signal in "${signal_list[@]}"; do
    signal="${signal//[[:space:]]/}"
    case "$signal" in
        none) has_none=true ;;
        review_finding|build_test_failure|user_correction|memory_trend) has_evidence=true ;;
        *)
            printf 'Invalid Learning evidence signal: %s\n' "${signal:-<empty>}" >&2
            exit 1
            ;;
    esac
done
if [[ "$has_none" == true && "$has_evidence" == true ]]; then
    printf 'Learning evidence signal none cannot be combined with evidence\n' >&2
    exit 1
fi

case "$mode" in
    auto)
        [[ "$reason" =~ ^(normal_default|explicit_request|approved_plan):[[:space:]]*[^[:space:]] ]] || {
            printf 'Auto learning mode requires normal_default:, explicit_request:, or approved_plan: reason\n' >&2
            exit 1
        }
        ;;
    required)
        [[ "$reason" =~ ^(explicit_request|approved_plan):[[:space:]]*[^[:space:]] ]] || {
            printf 'Required learning mode requires explicit_request: or approved_plan: reason\n' >&2
            exit 1
        }
        ;;
    not_required)
        [[ "$reason" =~ ^(policy_disallowed|explicit_exclusion):[[:space:]]*[^[:space:]] ]] || {
            printf 'not_required requires policy_disallowed: or explicit_exclusion: reason\n' >&2
            exit 1
        }
        ;;
esac

learning_required=false
if [[ "$mode" == required || "$has_evidence" == true ]]; then
    learning_required=true
fi

if [[ "$learning_required" == true ]]; then
    required_fields=(
        '## Learning Controller'
        'Memory trend checked:'
        'Learning evidence reviewed:'
        'Review findings considered:'
        'Build/test failures considered:'
        'User corrections considered:'
        'Durable lesson decision:'
        'Persistence evidence:'
        'No-save rationale:'
    )
    for field in "${required_fields[@]}"; do
        if ! printf '%s\n' "$active_section" | grep -Fq "$field"; then
            printf 'Activated learning state is missing: %s\n' "$field" >&2
            exit 1
        fi
    done
fi

printf 'OK learning state: mode=%s activated=%s\n' "$mode" "$learning_required"
