if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

p0p4_file_mode_octal() {
    local path="$1"
    case "$(uname -s)" in
        Darwin|FreeBSD)
            stat -f "%Lp" "$path"
            ;;
        *)
            stat -c "%a" "$path"
            ;;
    esac
}

test_start "installer reinstall keeps one memory protocol block and one legacy preamble"
INSTALL_HOME="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME"
if HOME="$INSTALL_HOME" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-1.out 2>/tmp/p0p4-install-1.err; then
    if HOME="$INSTALL_HOME" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-2.out 2>/tmp/p0p4-install-2.err; then
        agents_file="$INSTALL_HOME/.codex/AGENTS.md"
        starts="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START" "$agents_file")"
        ends="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END" "$agents_file")"
        preambles="$(count_occurrences "^# Assistant Framework — Memory Protocol$" "$agents_file")"
        if [[ "$starts" == "1" && "$ends" == "1" && "$preambles" == "1" ]]; then
            pass
        else
            fail "expected one protocol start/end/preamble, got start=$starts end=$ends preamble=$preambles"
        fi
    else
        fail "second install failed; see /tmp/p0p4-install-2.err"
    fi
else
    fail "first install failed; see /tmp/p0p4-install-1.err"
fi

test_start "installer replaces interrupted memory protocol install without duplicating blocks"
INSTALL_HOME_THREE="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_THREE"
mkdir -p "$INSTALL_HOME_THREE/.codex"
cat > "$INSTALL_HOME_THREE/.codex/AGENTS.md" <<'TRUNCATED'
User-managed heading before installer content.

# Assistant Framework — Memory Protocol

## Role

You are an orchestrator. You delegate ALL file editing, code implementation, and phase execution to specialized agents.
<!-- This is a template. Paths like ~/.codex/ are substituted during install.sh for non-Claude agents. -->
<!-- Appended by Assistant Framework install. Do not remove this marker. -->
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->

Interrupted installer-owned memory content that should be removed.
TRUNCATED
if HOME="$INSTALL_HOME_THREE" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-truncated.out 2>/tmp/p0p4-install-truncated.err; then
    agents_file="$INSTALL_HOME_THREE/.codex/AGENTS.md"
    starts="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START" "$agents_file")"
    ends="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END" "$agents_file")"
    preambles="$(count_occurrences "^# Assistant Framework — Memory Protocol$" "$agents_file")"
    if [[ "$starts" == "1" && "$ends" == "1" && "$preambles" == "1" ]] \
        && grep -q "User-managed heading before installer content." "$agents_file" \
        && ! grep -q "Interrupted installer-owned memory content" "$agents_file"; then
        pass
    else
        fail "expected truncated installer block to be replaced once while preserving user content"
    fi
else
    fail "install after truncated memory protocol failed; see /tmp/p0p4-install-truncated.err"
fi

test_start "Codex reinstall collapses duplicate and interrupted memory protocol blocks while preserving user content"
INSTALL_HOME_SIX="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_SIX"
mkdir -p "$INSTALL_HOME_SIX/.codex"
cat > "$INSTALL_HOME_SIX/.codex/AGENTS.md" <<'DUPLICATE_CODEX'
User-managed content before old installer blocks.

<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_START -->
# Old Codex installer section
<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_END -->

User-managed content before first memory block.

<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->
# Assistant Framework — Memory Protocol

Old complete memory content A.
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->

User-managed content between complete memory blocks.

# Assistant Framework — Memory Protocol

## Role

You are an orchestrator. You delegate ALL file editing, code implementation, and phase execution to specialized agents.
<!-- This is a template. Paths like ~/.codex/ are substituted during install.sh for non-Claude agents. -->
<!-- Appended by Assistant Framework install. Do not remove this marker. -->
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->

Old complete memory content B.
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->

User-managed content before interrupted memory block.

# Assistant Framework — Memory Protocol

## Role

You are an orchestrator. You delegate ALL file editing, code implementation, and phase execution to specialized agents.
<!-- This is a template. Paths like ~/.codex/ are substituted during install.sh for non-Claude agents. -->
<!-- Appended by Assistant Framework install. Do not remove this marker. -->
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->

Interrupted installer-owned memory content that should be removed.
DUPLICATE_CODEX
if HOME="$INSTALL_HOME_SIX" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-duplicate-codex.out 2>/tmp/p0p4-install-duplicate-codex.err; then
    agents_file="$INSTALL_HOME_SIX/.codex/AGENTS.md"
    starts="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START" "$agents_file")"
    ends="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END" "$agents_file")"
    preambles="$(count_occurrences "^# Assistant Framework — Memory Protocol$" "$agents_file")"
    agents_starts="$(count_occurrences "ASSISTANT_FRAMEWORK_AGENTS_MD_START" "$agents_file")"
    agents_ends="$(count_occurrences "ASSISTANT_FRAMEWORK_AGENTS_MD_END" "$agents_file")"
    if [[ "$starts" == "1" && "$ends" == "1" && "$preambles" == "1" ]] \
        && [[ "$agents_starts" == "1" && "$agents_ends" == "1" ]] \
        && grep -q "User-managed content before old installer blocks." "$agents_file" \
        && grep -q "User-managed content before first memory block." "$agents_file" \
        && grep -q "User-managed content between complete memory blocks." "$agents_file" \
        && grep -q "User-managed content before interrupted memory block." "$agents_file" \
        && ! grep -q "Old complete memory content A" "$agents_file" \
        && ! grep -q "Old complete memory content B" "$agents_file" \
        && ! grep -q "Interrupted installer-owned memory content" "$agents_file"; then
        pass
    else
        fail "expected duplicate and interrupted Codex memory protocol blocks to be replaced once while preserving user content"
    fi
else
    fail "Codex install with duplicate memory protocols failed; see /tmp/p0p4-install-duplicate-codex.err"
fi

test_start "installer strips substituted Gemini legacy memory preamble"
INSTALL_HOME_FOUR="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_FOUR"
mkdir -p "$INSTALL_HOME_FOUR/.gemini"
cat > "$INSTALL_HOME_FOUR/.gemini/GEMINI.md" <<'TRUNCATED_GEMINI'
User-managed Gemini heading before installer content.

# Assistant Framework — Memory Protocol

## Role

You are an orchestrator. You delegate ALL file editing, code implementation, and phase execution to specialized agents.
<!-- This is a template. Paths like ~/.gemini/ are substituted during install.sh for non-Claude agents. -->
<!-- Appended by Assistant Framework install. Do not remove this marker. -->
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->

Interrupted installer-owned Gemini memory content that should be removed.
TRUNCATED_GEMINI
if HOME="$INSTALL_HOME_FOUR" bash "$FRAMEWORK_DIR/install.sh" --agent gemini --skill assistant-workflow --no-hooks >/tmp/p0p4-install-gemini-truncated.out 2>/tmp/p0p4-install-gemini-truncated.err; then
    gemini_file="$INSTALL_HOME_FOUR/.gemini/GEMINI.md"
    starts="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START" "$gemini_file")"
    ends="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END" "$gemini_file")"
    preambles="$(count_occurrences "^# Assistant Framework — Memory Protocol$" "$gemini_file")"
    if [[ "$starts" == "1" && "$ends" == "1" && "$preambles" == "1" ]] \
        && grep -q "User-managed Gemini heading before installer content." "$gemini_file" \
        && ! grep -q "Interrupted installer-owned Gemini memory content" "$gemini_file"; then
        pass
    else
        fail "expected substituted Gemini installer block to be replaced once while preserving user content"
    fi
else
    fail "Gemini install after truncated memory protocol failed; see /tmp/p0p4-install-gemini-truncated.err"
fi

test_start "non-Claude skill install substitutes .claude paths in instruction/config files"
INSTALL_HOME_TWO="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_TWO"
if HOME="$INSTALL_HOME_TWO" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-subst.out 2>/tmp/p0p4-install-subst.err; then
    if find "$INSTALL_HOME_TWO/.codex/skills/assistant-workflow" -type f \( -name "*.md" -o -name "*.yaml" -o -name "*.yml" -o -name "*.conf" -o -name "*.toml" \) -print0 \
        | xargs -0 grep -n "\.claude/" >/tmp/p0p4-claude-paths.out 2>/dev/null; then
        fail "found unsubstituted .claude paths in installed codex skill; see /tmp/p0p4-claude-paths.out"
    else
        pass
    fi
else
    fail "codex skill install failed; see /tmp/p0p4-install-subst.err"
fi

test_start "installer reinstall removes stale installed tool build artifacts"
INSTALL_HOME_SEVEN="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_SEVEN"
if HOME="$INSTALL_HOME_SEVEN" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-tools-1.out 2>/tmp/p0p4-install-tools-1.err; then
    stale_publish="$INSTALL_HOME_SEVEN/.codex/tools/memory-graph/.publish"
    stale_bin="$INSTALL_HOME_SEVEN/.codex/tools/memory-graph/src/MemoryGraph/bin"
    stale_obj="$INSTALL_HOME_SEVEN/.codex/tools/memory-graph/src/MemoryGraph/obj"
    mkdir -p "$stale_publish" "$stale_bin" "$stale_obj"
    touch "$stale_publish/MemoryGraph" "$stale_bin/stale.dll" "$stale_obj/stale.dll"
    if HOME="$INSTALL_HOME_SEVEN" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-tools-2.out 2>/tmp/p0p4-install-tools-2.err; then
        if [[ ! -e "$stale_publish" && ! -e "$stale_bin" && ! -e "$stale_obj" ]]; then
            pass
        else
            fail "expected stale memory-graph .publish, bin, and obj artifacts to be removed after reinstall"
        fi
    else
        fail "second install for stale tool cleanup failed; see /tmp/p0p4-install-tools-2.err"
    fi
else
    fail "first install for stale tool cleanup failed; see /tmp/p0p4-install-tools-1.err"
fi

test_start "Codex reinstall refreshes stale memory-graph MCP config, tool approvals, and file mode"
INSTALL_HOME_NINE="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_NINE"
mkdir -p "$INSTALL_HOME_NINE/.codex"
cat > "$INSTALL_HOME_NINE/.codex/config.toml" <<'STALE_CODEX_MCP'
model = "test-model"

[mcp_servers.other-server]
command = "/tmp/other-server"
args = ["--keep"]

[mcp_servers.memory-graph]
command = "/stale/memory-graph"
args = ["--old-memory-dir", "/stale/memory"]

[mcp_servers.memory-graph.tools.memory_context]
approval_mode = "deny"

[mcp_servers.memory-graph.tools.memory_search]
approval_mode = "approve"

[mcp_servers.memory-graph.tools.memory_search]
approval_mode = "approve"

[features]
codex_hooks = false
STALE_CODEX_MCP
chmod 600 "$INSTALL_HOME_NINE/.codex/config.toml"
if HOME="$INSTALL_HOME_NINE" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-stale-codex-mcp.out 2>/tmp/p0p4-install-stale-codex-mcp.err; then
    config_file="$INSTALL_HOME_NINE/.codex/config.toml"
    config_mode="$(p0p4_file_mode_octal "$config_file")"
    expected_command="command = \"$INSTALL_HOME_NINE/.codex/tools/memory-graph/run-memory-graph.sh\""
    expected_args="args = [\"--memory-dir\", \"$INSTALL_HOME_NINE/.codex/memory\"]"
    memory_tools=(
        memory_context
        memory_search
        memory_stats
        memory_doctor
        memory_add_entity
        memory_add_insight
        memory_add_relation
        memory_remove_entity
        memory_remove_relation
        memory_graph
        memory_reflect
        memory_decide
        memory_pattern
        memory_consolidate
        memory_trend
    )

    if [[ "$(count_occurrences "^\\[mcp_servers\\.memory-graph\\]$" "$config_file")" != "1" ]] \
        || ! grep -Fq "$expected_command" "$config_file" \
        || ! grep -Fq "$expected_args" "$config_file" \
        || grep -q "/stale/memory-graph" "$config_file" \
        || ! grep -q '^model = "test-model"$' "$config_file" \
        || ! grep -q '^\[mcp_servers\.other-server\]$' "$config_file" \
        || [[ "$config_mode" != "600" ]]; then
        fail "expected stale Codex memory-graph command/args to refresh while preserving unrelated config and file mode"
    else
        missing_tool=""
        duplicate_tool=""
        bad_approval_tool=""
        for tool in "${memory_tools[@]}"; do
            section="mcp_servers\\.memory-graph\\.tools\\.$tool"
            if [[ "$(count_occurrences "^\\[$section\\]$" "$config_file")" == "0" ]]; then
                missing_tool="$tool"
                break
            fi
            if [[ "$(count_occurrences "^\\[$section\\]$" "$config_file")" != "1" ]]; then
                duplicate_tool="$tool"
                break
            fi
            if ! awk -v section="[mcp_servers.memory-graph.tools.$tool]" '
                $0 == section { in_section = 1; next }
                in_section && /^\[/ { exit }
                in_section && $0 == "approval_mode = \"approve\"" { found = 1; exit }
                END { exit found ? 0 : 1 }
            ' "$config_file"; then
                bad_approval_tool="$tool"
                break
            fi
        done

        if [[ -n "$missing_tool" ]]; then
            fail "expected refreshed Codex MCP config to include approval block for $missing_tool"
        elif [[ -n "$duplicate_tool" ]]; then
            fail "expected refreshed Codex MCP config to avoid duplicate approval blocks for $duplicate_tool"
        elif [[ -n "$bad_approval_tool" ]]; then
            fail "expected refreshed Codex MCP config to approve $bad_approval_tool"
        else
            pass
        fi
    fi
else
    fail "Codex install with stale memory-graph MCP config failed; see /tmp/p0p4-install-stale-codex-mcp.err"
fi

test_start "installer includes eval fixture used by installed eval runner"
INSTALL_HOME_EIGHT="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_EIGHT"
if HOME="$INSTALL_HOME_EIGHT" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-evals.out 2>/tmp/p0p4-install-evals.err; then
    installed_runner="$INSTALL_HOME_EIGHT/.codex/tools/evals/run-framework-instruction-evals.sh"
    installed_fixture="$INSTALL_HOME_EIGHT/.codex/docs/evals/framework-instruction-cases.json"
    if [[ -x "$installed_runner" ]] \
        && [[ -f "$installed_fixture" ]] \
        && HOME="$INSTALL_HOME_EIGHT" "$installed_runner" --validate-fixture >/tmp/p0p4-installed-eval-runner.out 2>/tmp/p0p4-installed-eval-runner.err; then
        pass
    else
        fail "installed eval runner must validate the installed fixture; see /tmp/p0p4-installed-eval-runner.err"
    fi
else
    fail "codex install for eval runner fixture failed; see /tmp/p0p4-install-evals.err"
fi

test_start "Codex hook template is valid JSON with one PreToolUse key"
if jq -e . "$FRAMEWORK_DIR/hooks/codex-settings.json" >/dev/null \
    && [[ "$(grep -o '"PreToolUse"' "$FRAMEWORK_DIR/hooks/codex-settings.json" | wc -l | tr -d ' ')" == "1" ]]; then
    pass
else
    fail "hooks/codex-settings.json must parse and contain exactly one raw PreToolUse key"
fi

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
