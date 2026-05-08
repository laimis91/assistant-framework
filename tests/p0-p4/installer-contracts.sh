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

legacy_orchestrator_role="You are an orchestrator. You delegate ALL ""file editing, code implementation, and phase execution to specialized agents."
stale_generated_phrase="delegate ALL ""file editing, code implementation, and phase execution"

test_start "Codex reinstall keeps one framework block, one memory protocol block, and current wording"
INSTALL_HOME="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME"
if HOME="$INSTALL_HOME" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-1.out 2>/tmp/p0p4-install-1.err; then
    if HOME="$INSTALL_HOME" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-2.out 2>/tmp/p0p4-install-2.err; then
        agents_file="$INSTALL_HOME/.codex/AGENTS.md"
        starts="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START" "$agents_file")"
        ends="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END" "$agents_file")"
        preambles="$(count_occurrences "^# Assistant Framework — Memory Protocol$" "$agents_file")"
        agents_starts="$(count_occurrences "ASSISTANT_FRAMEWORK_AGENTS_MD_START" "$agents_file")"
        agents_ends="$(count_occurrences "ASSISTANT_FRAMEWORK_AGENTS_MD_END" "$agents_file")"
        if [[ "$starts" == "1" && "$ends" == "1" && "$preambles" == "1" ]] \
            && [[ "$agents_starts" == "1" && "$agents_ends" == "1" ]] \
            && ! grep -Fq "$stale_generated_phrase" "$agents_file" \
            && grep -Fq "File edits, code implementation, builds/tests, and independent review are owned by those specialized agents" "$agents_file" \
            && grep -Fq "The orchestrator does not edit files or write code directly." "$agents_file"; then
            pass
        else
            fail "expected one Codex framework block, one protocol block, and current generated wording"
        fi
    else
        fail "second install failed; see /tmp/p0p4-install-2.err"
    fi
else
    fail "first install failed; see /tmp/p0p4-install-1.err"
fi

test_start "Codex single-skill install generates AGENTS skill table from installed skills"
INSTALL_HOME_SKILL_TABLE="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_SKILL_TABLE"
if HOME="$INSTALL_HOME_SKILL_TABLE" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-single-skill-table.out 2>/tmp/p0p4-install-single-skill-table.err; then
    agents_file="$INSTALL_HOME_SKILL_TABLE/.codex/AGENTS.md"
    installed_skills_dir="$INSTALL_HOME_SKILL_TABLE/.codex/skills"
    assistant_skill_rows="$(count_occurrences "^| assistant-" "$agents_file")"

    if [[ ! -d "$installed_skills_dir/assistant-workflow" ]]; then
        fail "expected assistant-workflow to be installed"
    elif [[ -d "$installed_skills_dir/assistant-review" || -d "$installed_skills_dir/assistant-docs" ]]; then
        fail "expected single-skill install to avoid installing assistant-review and assistant-docs"
    elif [[ "$assistant_skill_rows" != "1" ]]; then
        fail "expected generated Codex AGENTS.md to list exactly one assistant skill; found $assistant_skill_rows"
    elif ! grep -Fq "| assistant-workflow | build, implement, fix, refactor, plan | Structured dev: triage through document |" "$agents_file"; then
        fail "expected generated Codex AGENTS.md to list assistant-workflow with first-class metadata"
    elif grep -Fq "| assistant-review |" "$agents_file" || grep -Fq "| assistant-docs |" "$agents_file"; then
        fail "expected generated Codex AGENTS.md to omit uninstalled assistant-review and assistant-docs"
    else
        pass
    fi
else
    fail "single-skill Codex install failed; see /tmp/p0p4-install-single-skill-table.err"
fi

test_start "installer replaces interrupted memory protocol install without duplicating blocks"
INSTALL_HOME_THREE="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_THREE"
mkdir -p "$INSTALL_HOME_THREE/.codex"
cat > "$INSTALL_HOME_THREE/.codex/AGENTS.md" <<TRUNCATED
User-managed heading before installer content.

# Assistant Framework — Memory Protocol

## Role

$legacy_orchestrator_role
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
cat > "$INSTALL_HOME_SIX/.codex/AGENTS.md" <<DUPLICATE_CODEX
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

$legacy_orchestrator_role
<!-- This is a template. Paths like ~/.codex/ are substituted during install.sh for non-Claude agents. -->
<!-- Appended by Assistant Framework install. Do not remove this marker. -->
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->

Old complete memory content B.
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->

User-managed content before interrupted memory block.

# Assistant Framework — Memory Protocol

## Role

$legacy_orchestrator_role
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
cat > "$INSTALL_HOME_FOUR/.gemini/GEMINI.md" <<TRUNCATED_GEMINI
User-managed Gemini heading before installer content.

# Assistant Framework — Memory Protocol

## Role

$legacy_orchestrator_role
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

test_start "default install excludes local Unity skills"
INSTALL_HOME_TEN="$(mktemp -d)"
UNITY_FIXTURE="$(mktemp -d "$FRAMEWORK_DIR/skills/unity-contract-fixture-XXXXXX")"
UNITY_FIXTURE_NAME="$(basename "$UNITY_FIXTURE")"
p0p4_register_cleanup "$INSTALL_HOME_TEN" "$UNITY_FIXTURE"
cat > "$UNITY_FIXTURE/SKILL.md" <<'UNITY_SKILL'
---
name: unity-local-contract-fixture
description: Local-only Unity fixture that must not be installed by default.
---

# Unity Local Contract Fixture
UNITY_SKILL
if HOME="$INSTALL_HOME_TEN" bash "$FRAMEWORK_DIR/install.sh" --agent codex --no-hooks >/tmp/p0p4-install-default-skills.out 2>/tmp/p0p4-install-default-skills.err; then
    installed_skills_dir="$INSTALL_HOME_TEN/.codex/skills"
    agents_file="$INSTALL_HOME_TEN/.codex/AGENTS.md"
    missing_assistant_skill=""
    missing_agents_skill=""
    unexpected_installed_skill=""
    source_assistant_skill_count=0
    agents_assistant_skill_rows="$(count_occurrences "^| assistant-" "$agents_file")"

    while IFS= read -r source_skill_md; do
        source_assistant_skill_count=$((source_assistant_skill_count + 1))
        source_skill="$(basename "$(dirname "$source_skill_md")")"
        if [[ ! -d "$installed_skills_dir/$source_skill" ]]; then
            missing_assistant_skill="$source_skill"
            break
        fi
        if ! grep -Fq "| $source_skill |" "$agents_file"; then
            missing_agents_skill="$source_skill"
            break
        fi
    done < <(find "$FRAMEWORK_DIR/skills" -maxdepth 2 -path "$FRAMEWORK_DIR/skills/assistant-*/SKILL.md" -type f | sort)

    if [[ -d "$installed_skills_dir" ]]; then
        while IFS= read -r installed_skill_dir; do
            installed_skill="$(basename "$installed_skill_dir")"
            case "$installed_skill" in
                assistant-*) ;;
                *)
                    unexpected_installed_skill="$installed_skill"
                    break
                    ;;
            esac
        done < <(find "$installed_skills_dir" -mindepth 1 -maxdepth 1 -type d | sort)
    fi

    if [[ -n "$missing_assistant_skill" ]]; then
        fail "expected default install to include first-class assistant skill $missing_assistant_skill"
    elif [[ -n "$missing_agents_skill" ]]; then
        fail "expected generated Codex AGENTS.md to include first-class assistant skill $missing_agents_skill"
    elif [[ "$source_assistant_skill_count" != "15" ]]; then
        fail "expected source inventory to contain 15 first-class assistant skills; found $source_assistant_skill_count"
    elif [[ "$agents_assistant_skill_rows" != "15" ]]; then
        fail "expected generated Codex AGENTS.md to list all 15 first-class assistant skills; found $agents_assistant_skill_rows"
    elif [[ -n "$unexpected_installed_skill" ]]; then
        fail "expected default install to exclude non-assistant skill $unexpected_installed_skill"
    elif [[ -e "$installed_skills_dir/$UNITY_FIXTURE_NAME" ]]; then
        fail "expected default install to exclude local Unity fixture"
    else
        pass
    fi
else
    fail "default install with local Unity fixture failed; see /tmp/p0p4-install-default-skills.err"
fi

test_start "Codex hook template is valid JSON with PreToolUse and no PostToolUse key"
if jq -e . "$FRAMEWORK_DIR/hooks/codex-settings.json" >/dev/null \
    && [[ "$(grep -o '"PreToolUse"' "$FRAMEWORK_DIR/hooks/codex-settings.json" | wc -l | tr -d ' ')" == "1" ]] \
    && [[ "$(grep -o '"PostToolUse"' "$FRAMEWORK_DIR/hooks/codex-settings.json" | wc -l | tr -d ' ')" == "0" ]]; then
    pass
else
    fail "hooks/codex-settings.json must parse, contain exactly one raw PreToolUse key, and contain no PostToolUse key"
fi

test_start "Claude reinstall removes framework post-tool hooks and preserves custom hooks"
CLAUDE_HOOK_HOME="$(mktemp -d)"
p0p4_register_cleanup "$CLAUDE_HOOK_HOME"
mkdir -p "$CLAUDE_HOOK_HOME/.claude"
mkdir -p "$CLAUDE_HOOK_HOME/.claude/hooks/assistant"
touch "$CLAUDE_HOOK_HOME/.claude/hooks/assistant/post-tool-context.sh" \
    "$CLAUDE_HOOK_HOME/.claude/hooks/assistant/tool-failure-advisor.sh"
cat > "$CLAUDE_HOOK_HOME/.claude/settings.json" <<JSON
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/tmp/user-claude-pretool.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\$HOME/.claude/hooks/assistant/post-tool-context.sh"
          },
          {
            "type": "command",
            "command": "/tmp/user-claude-posttool.sh"
          }
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_HOOK_HOME/.claude/hooks/assistant/tool-failure-advisor.sh --stale"
          },
          {
            "type": "command",
            "command": "$FRAMEWORK_DIR/hooks/scripts/tool-failure-advisor.sh --repo-stale"
          },
          {
            "type": "command",
            "command": "/tmp/user-claude-failure-hook.sh"
          }
        ]
      }
    ]
  }
}
JSON
if HOME="$CLAUDE_HOOK_HOME" bash "$FRAMEWORK_DIR/install.sh" --agent claude --skill assistant-workflow >/tmp/p0p4-install-claude-hooks.out 2>/tmp/p0p4-install-claude-hooks.err; then
    if [[ ! -x "$CLAUDE_HOOK_HOME/.claude/hooks/assistant/post-tool-context.sh" \
        || ! -x "$CLAUDE_HOOK_HOME/.claude/hooks/assistant/tool-failure-advisor.sh" ]]; then
        fail "Claude install did not create executable legacy post-tool shims"
    elif [[ -n "$(HOME="$CLAUDE_HOOK_HOME" bash "$CLAUDE_HOOK_HOME/.claude/hooks/assistant/tool-failure-advisor.sh" <<< '{"tool_name":"Bash","error":"Permission denied"}')" ]]; then
        fail "Claude legacy post-tool shim should stay silent"
    elif jq -e --arg install_home "$CLAUDE_HOOK_HOME" --arg framework_dir "$FRAMEWORK_DIR" '
        def first_shell_token:
            (gsub("^\\s+"; "") | gsub("\\s+"; " ") | split(" ") | .[0] // "");
        [.. | objects | .command? // empty] as $commands
        | [$commands[] | first_shell_token] as $tokens
        | {
            stale: ($tokens | any(. == "$HOME/.claude/hooks/assistant/post-tool-context.sh"
                or . == ($install_home + "/.claude/hooks/assistant/tool-failure-advisor.sh")
                or . == ($framework_dir + "/hooks/scripts/tool-failure-advisor.sh"))),
            customPre: ($commands | any(. == "/tmp/user-claude-pretool.sh")),
            customPost: ($commands | any(. == "/tmp/user-claude-posttool.sh")),
            customFailure: ($commands | any(. == "/tmp/user-claude-failure-hook.sh")),
            workflowGuard: ([.hooks.PreToolUse[]?.hooks[]?.command?] | any(. == "$HOME/.claude/hooks/assistant/workflow-guard.sh"))
        }
        | (.stale | not) and .customPre and .customPost and .customFailure and .workflowGuard
    ' "$CLAUDE_HOOK_HOME/.claude/settings.json" >/dev/null; then
        pass
    else
        fail "Claude reinstall did not remove stale framework post-tool hooks, preserve custom hooks, or add workflow-guard"
    fi
else
    fail "Claude hook reinstall failed; see /tmp/p0p4-install-claude-hooks.err"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
