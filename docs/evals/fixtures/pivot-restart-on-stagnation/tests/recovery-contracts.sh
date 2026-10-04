#!/usr/bin/env bash
set -euo pipefail

fixture_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$fixture_root"

grep -Fqx 'terminal_completed=false' RECOVERY.md
grep -Fqx 'next_action=assistant-debugging' RECOVERY.md
grep -Fqx 'recovery_pointer=fixture-owned-recovery-artifacts' RECOVERY.md
[[ -d .assistant-eval && ! -L .assistant-eval && ! -L .assistant-eval/stagnation-failure-receipt.json && ! -L .assistant-eval/stagnation-recovery.json ]]
[[ -f .assistant-eval/stagnation-failure-receipt.json ]]
jq -e '
  . == {
    schema_version:"1.0",
    terminal_completed:false,
    next_action:"assistant-debugging",
    recovery_pointer:"fixture-owned-recovery-artifacts"
  }
' .assistant-eval/stagnation-failure-receipt.json >/dev/null
mkdir -p .assistant-eval
[[ ! -L .assistant-eval && ! -L .assistant-eval/stagnation-recovery.json ]] || exit 1
jq -cnS '
  {
    schema_version:"1.0",
    trusted_failure:"observed",
    recovery:"applied",
    fresh_check:"pending",
    terminal_completed:false
  }
' >.assistant-eval/stagnation-recovery.json

printf '%s\n' 'RECOVERY_APPLIED'
