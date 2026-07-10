#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "Codex native-default reinstall prunes framework hooks and preserves custom hooks"
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
          },
          {
            "type": "command",
            "command": "$FRAMEWORK_DIR/hooks/scripts/workflow-phase-gates.sh --legacy"
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
          },
          {
            "type": "command",
            "command": "/tmp/user-posttool-hook.sh"
          }
        ]
      }
    ]
  }
}
JSON
if HOME="$INSTALL_HOME_FIVE" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow >/tmp/p0p4-install-codex-hooks.out 2>/tmp/p0p4-install-codex-hooks.err; then
    missing_native_shim=""
    for cached_hook in session-start.sh skill-router.sh learning-signals.sh workflow-enforcer.sh workflow-guard.sh stop-review.sh subagent-monitor.sh pre-compress.sh post-compact.sh; do
        if [[ ! -x "$INSTALL_HOME_FIVE/.codex/hooks/assistant/$cached_hook" ]] \
            || ! grep -Fq "Assistant Framework native-profile migration shim" "$INSTALL_HOME_FIVE/.codex/hooks/assistant/$cached_hook"; then
            missing_native_shim="$cached_hook"
            break
        fi
    done
    if [[ -n "$missing_native_shim" ]]; then
        fail "Codex native-default reinstall did not create an inert cached entrypoint for $missing_native_shim"
    elif jq -e . "$INSTALL_HOME_FIVE/.codex/hooks.json" >/dev/null && jq -e --arg install_home "$INSTALL_HOME_FIVE" --arg framework_dir "$FRAMEWORK_DIR" --arg command_dir "$INSTALL_HOME_FIVE/.codex/hooks/assistant" '
        def first_shell_token:
            (gsub("^\\s+"; "") | gsub("\\s+"; " ") | split(" ") | .[0] // "");
        def framework_hook_names:
            [
                "session-start.sh",
                "skill-router.sh",
                "learning-signals.sh",
                "workflow-enforcer.sh",
                "workflow-guard.sh",
                "stop-review.sh",
                "subagent-monitor.sh",
                "workflow-phase-gates.sh",
                "hook-runtime.sh",
                "pre-compress.sh",
                "post-compact.sh",
                "session-end.sh",
                "post-tool-context.sh",
                "tool-failure-advisor.sh",
                "task-completed.sh"
            ];
        def framework_hook_command:
            (. // "") as $command
            | ($command | first_shell_token) as $token
            | any(framework_hook_names[]; . as $hook_name |
                $token == ("$HOME/.codex/hooks/assistant/" + $hook_name)
                or $token == ($command_dir + "/" + $hook_name)
                or ($token | endswith("/.codex/hooks/assistant/" + $hook_name))
                or ($token | endswith("/hooks/assistant/" + $hook_name))
                or ($token | endswith("/hooks/scripts/" + $hook_name))
            );
        [.. | objects | .command? // empty] as $commands
        | {
            registeredFramework: ($commands | any(framework_hook_command)),
            custom: ($commands | any(. == "/tmp/user-custom-hook.sh")),
            postToolCustom: ($commands | any(. == "/tmp/user-posttool-hook.sh")),
            homeAssistantCustom: ($commands | any(. == "$HOME/.codex/hooks/assistant/custom-user.sh")),
            absoluteAssistantCustom: ($commands | any(. == ($install_home + "/.codex/hooks/assistant/custom-absolute.sh --keep"))),
            preToolCustom: ($commands | any(. == "/tmp/user-pretool-hook.sh"))
        }
        | (.registeredFramework | not) and .custom and .postToolCustom and .homeAssistantCustom and .absoluteAssistantCustom and .preToolCustom
    ' "$INSTALL_HOME_FIVE/.codex/hooks.json" >/dev/null; then
        pass
    else
        fail "Codex native-default reinstall did not remove known framework commands or preserve custom hooks"
    fi
else
    fail "codex hook reinstall failed; see /tmp/p0p4-install-codex-hooks.err"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
