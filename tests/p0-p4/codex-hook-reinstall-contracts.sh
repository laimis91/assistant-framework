#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "Codex hook reinstall merges hooks sanely"
INSTALL_HOME_FIVE="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_FIVE"
mkdir -p "$INSTALL_HOME_FIVE/.codex"
cat > "$INSTALL_HOME_FIVE/.codex/hooks.json" <<JSON
{
  "hooks": {
    "PostCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "\$HOME/.codex/hooks/assistant/post-compact.sh"
          },
          {
            "type": "command",
            "command": "/tmp/user-custom-hook.sh"
          },
          {
            "type": "command",
            "command": "\$HOME/.codex/hooks/assistant/custom-user.sh"
          },
          {
            "type": "command",
            "command": "$INSTALL_HOME_FIVE/.codex/hooks/assistant/session-end.sh --legacy"
          },
          {
            "type": "command",
            "command": "$INSTALL_HOME_FIVE/.codex/hooks/assistant/custom-absolute.sh --keep"
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "\$HOME/.codex/hooks/assistant/pre-compress.sh"
          },
          {
            "type": "command",
            "command": "$FRAMEWORK_DIR/hooks/scripts/task-completed.sh --legacy"
          },
          {
            "type": "command",
            "command": "$FRAMEWORK_DIR/hooks/scripts/task-journal-resolver.sh --legacy"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "\$HOME/.codex/hooks/assistant/workflow-guard.sh"
          },
          {
            "type": "command",
            "command": "$INSTALL_HOME_FIVE/.codex/hooks/assistant/workflow-guard.sh --absolute-stale"
          },
          {
            "type": "command",
            "command": "$FRAMEWORK_DIR/hooks/scripts/workflow-guard.sh --repo-stale"
          },
          {
            "type": "command",
            "command": "/tmp/user-pretool-hook.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "\$HOME/.codex/hooks/assistant/tool-failure-advisor.sh --stale"
          },
          {
            "type": "command",
            "command": "$FRAMEWORK_DIR/hooks/scripts/post-tool-context.sh --stale"
          }
        ]
      }
    ]
  }
}
JSON
if HOME="$INSTALL_HOME_FIVE" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow >/tmp/p0p4-install-codex-hooks.out 2>/tmp/p0p4-install-codex-hooks.err; then
    if jq -e . "$INSTALL_HOME_FIVE/.codex/hooks.json" >/dev/null && jq -e --arg install_home "$INSTALL_HOME_FIVE" --arg framework_dir "$FRAMEWORK_DIR" '
        def first_shell_token:
            (gsub("^\\s+"; "") | gsub("\\s+"; " ") | split(" ") | .[0] // "");
        def current_framework_hook_names:
            [
                "session-start.sh",
                "skill-router.sh",
                "learning-signals.sh",
                "workflow-enforcer.sh",
                "workflow-guard.sh",
                "stop-review.sh",
                "harness-gate.sh"
            ];
        [.. | objects | .command? // empty] as $commands
        | [$commands[] | first_shell_token] as $tokens
        | [$commands[] | select(. as $command | any(current_framework_hook_names[]; . as $hook_name | $command == ("$HOME/.codex/hooks/assistant/" + $hook_name)))] as $frameworkCommands
        | {
            stale: ($tokens | any(. == "$HOME/.codex/hooks/assistant/post-compact.sh"
                or . == "$HOME/.codex/hooks/assistant/pre-compress.sh"
                or . == ($install_home + "/.codex/hooks/assistant/session-end.sh")
                or . == ($install_home + "/.codex/hooks/assistant/workflow-guard.sh")
                or . == "$HOME/.codex/hooks/assistant/tool-failure-advisor.sh"
                or . == ($framework_dir + "/hooks/scripts/task-completed.sh")
                or . == ($framework_dir + "/hooks/scripts/task-journal-resolver.sh")
                or . == ($framework_dir + "/hooks/scripts/workflow-guard.sh")
                or . == ($framework_dir + "/hooks/scripts/post-tool-context.sh"))),
            custom: ($commands | any(. == "/tmp/user-custom-hook.sh")),
            homeAssistantCustom: ($commands | any(. == "$HOME/.codex/hooks/assistant/custom-user.sh")),
            absoluteAssistantCustom: ($commands | any(. == ($install_home + "/.codex/hooks/assistant/custom-absolute.sh --keep"))),
            preToolCustom: ($commands | any(. == "/tmp/user-pretool-hook.sh")),
            uniqueFramework: (($frameworkCommands | length) == ($frameworkCommands | unique | length)),
            sessionStart: ([.hooks.SessionStart[]?.hooks[]?.command?] | any(. == "$HOME/.codex/hooks/assistant/session-start.sh")),
            workflowGuard: ([.hooks.PreToolUse[]?.hooks[]?.command?] | any(. == "$HOME/.codex/hooks/assistant/workflow-guard.sh"))
        }
        | (.stale | not) and .custom and .homeAssistantCustom and .absoluteAssistantCustom and .preToolCustom and .uniqueFramework and .sessionStart and .workflowGuard
    ' "$INSTALL_HOME_FIVE/.codex/hooks.json" >/dev/null; then
        pass
    else
        fail "Codex hook reinstall did not remove stale framework hooks, preserve custom hooks, or dedupe framework commands"
    fi
else
    fail "codex hook reinstall failed; see /tmp/p0p4-install-codex-hooks.err"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
