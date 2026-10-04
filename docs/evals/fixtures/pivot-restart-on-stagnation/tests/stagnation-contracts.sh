#!/usr/bin/env bash
set -euo pipefail

fixture_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$fixture_root"

if [[ "${1:-}" == "--after-recovery" ]]; then
    failure_receipt=".assistant-eval/stagnation-failure-receipt.json"
    recovery_artifact=".assistant-eval/stagnation-recovery.json"
    [[ -d .assistant-eval && ! -L .assistant-eval && ! -L "$failure_receipt" && ! -L "$recovery_artifact" ]] || exit 1
    [[ -f "$failure_receipt" && ! -L "$failure_receipt" && -f "$recovery_artifact" && ! -L "$recovery_artifact" ]] \
        && jq -e '
          . == {
            schema_version:"1.0",
            terminal_completed:false,
            next_action:"assistant-debugging",
            recovery_pointer:"fixture-owned-recovery-artifacts"
          }
        ' "$failure_receipt" >/dev/null \
        && jq -e '
          . == {
            schema_version:"1.0",
            trusted_failure:"observed",
            recovery:"applied",
            fresh_check:"pending",
            terminal_completed:false
          }
        ' "$recovery_artifact" >/dev/null \
        && grep -Fqx 'terminal_completed=false' RECOVERY.md \
        && grep -Fqx 'next_action=assistant-debugging' RECOVERY.md \
        && grep -Fqx 'recovery_pointer=fixture-owned-recovery-artifacts' RECOVERY.md \
        || exit 1
    jq -cnS '
      {schema_version:"1.0",trusted_failure:"observed",recovery:"applied",fresh_check:"passed",terminal_completed:false}
    ' >"$recovery_artifact"
    printf '%s\n' 'STAGNATION_FRESH_CHECK_PASS'
    exit 0
fi

if [[ -L .assistant-eval || ( -e .assistant-eval && ! -d .assistant-eval ) ]]; then
    exit 1
fi
mkdir -p .assistant-eval
[[ -d .assistant-eval && ! -L .assistant-eval && ! -L .assistant-eval/stagnation-failure-receipt.json ]] || exit 1
jq -cnS '
  {schema_version:"1.0",terminal_completed:false,next_action:"assistant-debugging",recovery_pointer:"fixture-owned-recovery-artifacts"}
' >.assistant-eval/stagnation-failure-receipt.json
printf '%s\n' 'STAGNATION_TRUSTED_FAILURE'
exit 1
