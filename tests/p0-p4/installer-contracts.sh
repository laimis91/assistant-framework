if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

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
cat > "$INSTALL_HOME_FIVE/.codex/hooks.json" <<'JSON'
{
  "hooks": {
    "PostCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.codex/hooks/assistant/post-compact.sh"
          },
          {
            "type": "command",
            "command": "/tmp/user-custom-hook.sh"
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
            "command": "$HOME/.codex/hooks/assistant/pre-compress.sh"
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
            "command": "$HOME/.codex/hooks/assistant/workflow-guard.sh"
          },
          {
            "type": "command",
            "command": "/tmp/user-pretool-hook.sh"
          }
        ]
      }
    ]
  }
}
JSON
if HOME="$INSTALL_HOME_FIVE" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow >/tmp/p0p4-install-codex-hooks.out 2>/tmp/p0p4-install-codex-hooks.err; then
    if jq -e . "$INSTALL_HOME_FIVE/.codex/hooks.json" >/dev/null && jq -e '
        [.. | objects | .command? // empty] as $commands
        | [$commands[] | select(startswith("$HOME/.codex/hooks/assistant/"))] as $frameworkCommands
        | {
            stale: ($commands | any(. == "$HOME/.codex/hooks/assistant/post-compact.sh"
                or . == "$HOME/.codex/hooks/assistant/pre-compress.sh"
                or . == "$HOME/.codex/hooks/assistant/session-end.sh"
                or . == "$HOME/.codex/hooks/assistant/task-completed.sh")),
            custom: ($commands | any(. == "/tmp/user-custom-hook.sh")),
            preToolCustom: ($commands | any(. == "/tmp/user-pretool-hook.sh")),
            uniqueFramework: (($frameworkCommands | length) == ($frameworkCommands | unique | length)),
            sessionStart: ([.hooks.SessionStart[]?.hooks[]?.command?] | any(. == "$HOME/.codex/hooks/assistant/session-start.sh")),
            workflowGuard: ([.hooks.PreToolUse[]?.hooks[]?.command?] | any(. == "$HOME/.codex/hooks/assistant/workflow-guard.sh"))
        }
        | (.stale | not) and .custom and .preToolCustom and .uniqueFramework and .sessionStart and .workflowGuard
    ' "$INSTALL_HOME_FIVE/.codex/hooks.json" >/dev/null; then
        pass
    else
        fail "Codex hook reinstall did not remove stale framework hooks, preserve custom hooks, or dedupe framework commands"
    fi
else
    fail "codex hook reinstall failed; see /tmp/p0p4-install-codex-hooks.err"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
