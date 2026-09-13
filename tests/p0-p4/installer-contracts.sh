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

p0p4_path_without_jq() {
    local tmpbin="$1"
    local d
    local f
    local name

    mkdir -p "$tmpbin"
    for d in /bin /usr/bin /usr/sbin /sbin; do
        [[ -d "$d" ]] || continue
        for f in "$d"/*; do
            name="$(basename "$f")"
            [[ "$name" == "jq" ]] && continue
            [[ -e "$tmpbin/$name" ]] || ln -s "$f" "$tmpbin/$name" 2>/dev/null || true
        done
    done
}

p0p4_extract_current_agents_suffix() {
    local agents_file="$1"
    local suffix_file="$2"

    sed '1,/<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_END -->/d' "$agents_file" \
        | sed '1{/^$/d;}' >"$suffix_file"
}

test_start "Codex reinstall keeps one lean framework block and retires the memory protocol"
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
        operating_stances="$(count_occurrences "^## Operating stance$" "$agents_file")"
        if [[ "$starts" == "0" && "$ends" == "0" && "$preambles" == "0" ]] \
            && [[ "$agents_starts" == "1" && "$agents_ends" == "1" ]] \
            && [[ "$operating_stances" == "1" ]] \
            && ! grep -Fq "$stale_generated_phrase" "$agents_file" \
            && grep -Fq "Codex uses installed skills through native skill routing." "$agents_file" \
            && grep -Fq "load only the references or contracts relevant to the current phase" "$agents_file" \
            && grep -Fq "For small, low-risk, localized work, act as a hands-on worker" "$agents_file" \
            && grep -Fq "For medium+ or elevated-risk development work, remain the orchestrator" "$agents_file" \
            && grep -Fq "Keep orchestration proportional" "$agents_file" \
            && grep -Fq "Get plan approval before medium+ or risky edits." "$agents_file" \
            && grep -Fq "Use subagents when requested by the user or required by applicable project or skill instructions; do not ask for separate spawn consent." "$agents_file" \
            && ! grep -Fq "## Skills (loaded" "$agents_file" \
            && [[ -f "$INSTALL_HOME/.codex/agents/code-reviewer.toml" ]] \
            && grep -Fq 'sandbox_mode = "read-only"' "$INSTALL_HOME/.codex/agents/code-reviewer.toml" \
            && ! grep -Fq "The orchestrator owns framework state files" "$agents_file" \
            && ! grep -Fq ".codex/context-map.md" "$agents_file" \
            && ! grep -Fq "Do not infer that subagents are unavailable from the absence of a visible tool name" "$agents_file" \
            && grep -Fq "Preserve user-authored files and existing dirty work." "$agents_file"; then
            pass
        else
            fail "expected one lean native-Codex framework block with no retired memory protocol"
        fi
    else
        fail "second install failed; see /tmp/p0p4-install-2.err"
    fi
else
    fail "first install failed; see /tmp/p0p4-install-1.err"
fi

test_start "Codex single-skill install keeps routing metadata in the installed skill"
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
    elif [[ "$assistant_skill_rows" != "0" ]]; then
        fail "expected lean Codex AGENTS.md to avoid duplicating installed skill routing tables; found $assistant_skill_rows rows"
    elif ! grep -Fq "Codex uses installed skills through native skill routing." "$agents_file"; then
        fail "expected generated Codex AGENTS.md to delegate routing to the installed SKILL.md"
    else
        pass
    fi
else
    fail "single-skill Codex install failed; see /tmp/p0p4-install-single-skill-table.err"
fi

test_start "requires fixtures stay outside the canonical skills inventory"
requires_fixture_prefix='assistant-requires-contract-fixture-'
canonical_fixture_creation='mktemp -d "$FRAMEWORK_DIR/skills/'"$requires_fixture_prefix"
if grep -Fq -- "$canonical_fixture_creation" "${BASH_SOURCE[0]}"; then
    fail "requires fixture is created inside the canonical skills inventory"
else
    pass
fi

test_start "Codex installer observes missing dependencies from canonical block requires"
INSTALL_HOME_REQUIRES="$(mktemp -d)"
REQUIRES_FRAMEWORK_ROOT="$(mktemp -d)"
REQUIRES_FIXTURE_NAME="assistant-requires-contract-fixture-$(basename "$REQUIRES_FRAMEWORK_ROOT")"
REQUIRES_FIXTURE="$REQUIRES_FRAMEWORK_ROOT/skills/$REQUIRES_FIXTURE_NAME"
p0p4_register_cleanup "$INSTALL_HOME_REQUIRES" "$REQUIRES_FRAMEWORK_ROOT"
mkdir -p "$REQUIRES_FIXTURE"
cp "$FRAMEWORK_DIR/install.sh" "$REQUIRES_FRAMEWORK_ROOT/install.sh"
cat >"$REQUIRES_FIXTURE/SKILL.md" <<EOF
---
name: $REQUIRES_FIXTURE_NAME
description: Canonical block requires installer fixture.
requires:
  - assistant-missing-dependency
---

# Canonical Requires Fixture
EOF
if [[ "$REQUIRES_FIXTURE" == "$FRAMEWORK_DIR/skills/"* ]]; then
    fail "requires fixture must not be created under canonical skills"
elif HOME="$INSTALL_HOME_REQUIRES" bash "$REQUIRES_FRAMEWORK_ROOT/install.sh" --agent codex --skill "$REQUIRES_FIXTURE_NAME" --no-hooks >/tmp/p0p4-install-requires.out 2>/tmp/p0p4-install-requires.err; then
    if grep -Fq "NOTE: $REQUIRES_FIXTURE_NAME requires 'assistant-missing-dependency'" /tmp/p0p4-install-requires.out; then
        pass
    else
        fail "canonical block requires did not produce the missing-dependency note"
    fi
else
    fail "canonical block requires fixture install failed; see /tmp/p0p4-install-requires.err"
fi

test_start "retired plugin option is rejected without filesystem mutation"
INSTALL_HOME_RETIRED_PLUGIN="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_RETIRED_PLUGIN"
printf 'preserve\n' >"$INSTALL_HOME_RETIRED_PLUGIN/sentinel.txt"
if HOME="$INSTALL_HOME_RETIRED_PLUGIN" bash "$FRAMEWORK_DIR/install.sh" --agent codex --plugin assistant-core >/tmp/p0p4-install-retired-plugin.out 2>/tmp/p0p4-install-retired-plugin.err; then
    fail "retired --plugin option should be rejected"
elif ! grep -Fq 'Unknown option: --plugin' /tmp/p0p4-install-retired-plugin.err; then
    fail "retired --plugin rejection should identify the unknown option"
elif [[ "$(cat "$INSTALL_HOME_RETIRED_PLUGIN/sentinel.txt")" != "preserve" ]] \
    || [[ -e "$INSTALL_HOME_RETIRED_PLUGIN/.codex" ]]; then
    fail "retired --plugin rejection mutated the target home"
else
    pass
fi

test_start "Claude and Gemini installs ignore hostile ambient CODEX_HOME"
installer_non_codex_home_failures=()
for installer_non_codex_agent in claude gemini; do
    installer_non_codex_home="$(mktemp -d)"
    p0p4_register_cleanup "$installer_non_codex_home"
    if ! HOME="$installer_non_codex_home" CODEX_HOME=/ bash "$FRAMEWORK_DIR/install.sh" --agent "$installer_non_codex_agent" --skill assistant-workflow --no-hooks >/tmp/p0p4-install-non-codex-home-${installer_non_codex_agent}.out 2>/tmp/p0p4-install-non-codex-home-${installer_non_codex_agent}.err \
        || [[ ! -f "$installer_non_codex_home/.${installer_non_codex_agent}/skills/assistant-workflow/SKILL.md" ]] \
        || [[ -e /skills/assistant-workflow ]]; then
        installer_non_codex_home_failures+=("$installer_non_codex_agent")
    fi
done
if [[ "${#installer_non_codex_home_failures[@]}" -ne 0 ]]; then
    fail "Claude or Gemini install forwarded hostile ambient CODEX_HOME instead of using only its selected agent home: ${installer_non_codex_home_failures[*]}"
else
    pass
fi

test_start "installer preserves an interrupted retired memory protocol while installing the current managed block"
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
cp "$INSTALL_HOME_THREE/.codex/AGENTS.md" "$INSTALL_HOME_THREE/.codex/AGENTS.before"
interrupted_codex_suffix="$(mktemp)"
interrupted_codex_mutated_suffix="$(mktemp)"
p0p4_register_cleanup "$interrupted_codex_suffix" "$interrupted_codex_mutated_suffix"
if HOME="$INSTALL_HOME_THREE" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-truncated.out 2>/tmp/p0p4-install-truncated.err \
    && [[ "$(count_occurrences "ASSISTANT_FRAMEWORK_AGENTS_MD_START" "$INSTALL_HOME_THREE/.codex/AGENTS.md")" == "1" ]] \
    && [[ "$(count_occurrences "ASSISTANT_FRAMEWORK_AGENTS_MD_END" "$INSTALL_HOME_THREE/.codex/AGENTS.md")" == "1" ]]; then
    p0p4_extract_current_agents_suffix "$INSTALL_HOME_THREE/.codex/AGENTS.md" "$interrupted_codex_suffix"
    sed '$d' "$INSTALL_HOME_THREE/.codex/AGENTS.before" >"$interrupted_codex_mutated_suffix"
    if cmp -s "$INSTALL_HOME_THREE/.codex/AGENTS.before" "$interrupted_codex_suffix" \
        && ! cmp -s "$interrupted_codex_mutated_suffix" "$interrupted_codex_suffix"; then
        pass
    else
        fail "interrupted retired memory protocol was not preserved as the exact suffix after the current managed block"
    fi
else
    fail "interrupted retired memory protocol was not preserved while installing the current managed block"
fi

test_start "Codex reinstall preserves duplicate retired memory protocol blocks while installing the current managed block"
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
cp "$INSTALL_HOME_SIX/.codex/AGENTS.md" "$INSTALL_HOME_SIX/.codex/AGENTS.before"
duplicate_codex_expected_suffix="$(mktemp)"
duplicate_codex_actual_suffix="$(mktemp)"
duplicate_codex_mutated_suffix="$(mktemp)"
p0p4_register_cleanup "$duplicate_codex_expected_suffix" "$duplicate_codex_actual_suffix" "$duplicate_codex_mutated_suffix"
sed '/<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_START -->/,/<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_END -->/d' "$INSTALL_HOME_SIX/.codex/AGENTS.before" >"$duplicate_codex_expected_suffix"
if HOME="$INSTALL_HOME_SIX" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-duplicate-codex.out 2>/tmp/p0p4-install-duplicate-codex.err \
    && [[ "$(count_occurrences "ASSISTANT_FRAMEWORK_AGENTS_MD_START" "$INSTALL_HOME_SIX/.codex/AGENTS.md")" == "1" ]] \
    && [[ "$(count_occurrences "ASSISTANT_FRAMEWORK_AGENTS_MD_END" "$INSTALL_HOME_SIX/.codex/AGENTS.md")" == "1" ]]; then
    p0p4_extract_current_agents_suffix "$INSTALL_HOME_SIX/.codex/AGENTS.md" "$duplicate_codex_actual_suffix"
    sed '$d' "$duplicate_codex_expected_suffix" >"$duplicate_codex_mutated_suffix"
    if cmp -s "$duplicate_codex_expected_suffix" "$duplicate_codex_actual_suffix" \
        && ! cmp -s "$duplicate_codex_mutated_suffix" "$duplicate_codex_actual_suffix"; then
        pass
    else
        fail "duplicate retired memory protocol blocks were not preserved as the exact current-block suffix"
    fi
else
    fail "duplicate retired memory protocol blocks were not preserved while installing the current managed block"
fi

test_start "installer preserves an interrupted Gemini retired memory protocol while installing the current managed skill"
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
cp "$INSTALL_HOME_FOUR/.gemini/GEMINI.md" "$INSTALL_HOME_FOUR/.gemini/GEMINI.before"
if HOME="$INSTALL_HOME_FOUR" bash "$FRAMEWORK_DIR/install.sh" --agent gemini --skill assistant-workflow --no-hooks >/tmp/p0p4-install-gemini-truncated.out 2>/tmp/p0p4-install-gemini-truncated.err \
    && cmp -s "$INSTALL_HOME_FOUR/.gemini/GEMINI.before" "$INSTALL_HOME_FOUR/.gemini/GEMINI.md" \
    && [[ -f "$INSTALL_HOME_FOUR/.gemini/skills/assistant-workflow/SKILL.md" ]]; then
    pass
else
    fail "interrupted Gemini retired memory protocol was not preserved while installing the current managed skill"
fi

test_start "installer removes stale build artifacts only from managed tools"
INSTALL_HOME_SEVEN="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_SEVEN"
if HOME="$INSTALL_HOME_SEVEN" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-tools-1.out 2>/tmp/p0p4-install-tools-1.err; then
    stale_publish="$INSTALL_HOME_SEVEN/.codex/tools/evals/.publish"
    stale_bin="$INSTALL_HOME_SEVEN/.codex/tools/evals/bin"
    stale_obj="$INSTALL_HOME_SEVEN/.codex/tools/evals/obj"
    legacy_publish="$INSTALL_HOME_SEVEN/.codex/tools/memory-graph/.publish"
    legacy_bin="$INSTALL_HOME_SEVEN/.codex/tools/memory-graph/src/MemoryGraph/bin"
    legacy_obj="$INSTALL_HOME_SEVEN/.codex/tools/memory-graph/src/MemoryGraph/obj"
    mkdir -p "$stale_publish" "$stale_bin" "$stale_obj" "$legacy_publish" "$legacy_bin" "$legacy_obj"
    touch "$stale_publish/managed" "$stale_bin/managed.dll" "$stale_obj/managed.dll"
    touch "$legacy_publish/MemoryGraph" "$legacy_bin/stale.dll" "$legacy_obj/stale.dll"
    if HOME="$INSTALL_HOME_SEVEN" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-tools-2.out 2>/tmp/p0p4-install-tools-2.err; then
        if [[ ! -e "$stale_publish" && ! -e "$stale_bin" && ! -e "$stale_obj" \
            && -e "$legacy_publish/MemoryGraph" && -e "$legacy_bin/stale.dll" && -e "$legacy_obj/stale.dll" ]]; then
            pass
        else
            fail "expected managed build artifacts to be removed without altering the legacy Memory Graph tool tree"
        fi
    else
        fail "second install for stale tool cleanup failed; see /tmp/p0p4-install-tools-2.err"
    fi
else
    fail "first install for stale tool cleanup failed; see /tmp/p0p4-install-tools-1.err"
fi

test_start "installer retires the exact plugin sync tool and preserves unrelated plugin tools"
INSTALL_HOME_RETIRED_PLUGIN_TOOL="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_RETIRED_PLUGIN_TOOL"
retired_plugin_tools_directory="$INSTALL_HOME_RETIRED_PLUGIN_TOOL/.codex/tools/plugins"
retired_plugin_sync_tool="$retired_plugin_tools_directory/sync-plugin-skills.sh"
custom_plugin_tool="$retired_plugin_tools_directory/custom/tool.txt"
mkdir -p "$(dirname "$custom_plugin_tool")"
printf 'legacy plugin sync tool\n' >"$retired_plugin_sync_tool"
printf 'preserve user plugin tool\n' >"$custom_plugin_tool"
cp "$custom_plugin_tool" "$INSTALL_HOME_RETIRED_PLUGIN_TOOL/custom-tool.before"
if HOME="$INSTALL_HOME_RETIRED_PLUGIN_TOOL" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks --dry-run >/tmp/p0p4-install-retired-plugin-tool-dry-run.out 2>/tmp/p0p4-install-retired-plugin-tool-dry-run.err \
    && grep -Fq 'Remove retired managed plugin tool:' /tmp/p0p4-install-retired-plugin-tool-dry-run.out \
    && [[ -f "$retired_plugin_sync_tool" ]] \
    && cmp -s "$custom_plugin_tool" "$INSTALL_HOME_RETIRED_PLUGIN_TOOL/custom-tool.before" \
    && HOME="$INSTALL_HOME_RETIRED_PLUGIN_TOOL" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-retired-plugin-tool.out 2>/tmp/p0p4-install-retired-plugin-tool.err \
    && [[ ! -e "$retired_plugin_sync_tool" && ! -L "$retired_plugin_sync_tool" ]] \
    && cmp -s "$custom_plugin_tool" "$INSTALL_HOME_RETIRED_PLUGIN_TOOL/custom-tool.before"; then
    pass
else
    fail "installer must remove only the exact retired plugin sync tool and preserve unrelated plugin tools"
fi

test_start "installer reports and prunes an otherwise empty retired plugin tools directory"
INSTALL_HOME_EMPTY_RETIRED_PLUGIN_ROOT="$(mktemp -d)"
INSTALL_HOME_EMPTY_RETIRED_PLUGIN_TOOL="$INSTALL_HOME_EMPTY_RETIRED_PLUGIN_ROOT/assistant-[x]-home"
p0p4_register_cleanup "$INSTALL_HOME_EMPTY_RETIRED_PLUGIN_ROOT"
empty_retired_plugin_tools_directory="$INSTALL_HOME_EMPTY_RETIRED_PLUGIN_TOOL/.codex/tools/plugins"
mkdir -p "$empty_retired_plugin_tools_directory"
printf 'legacy plugin sync tool\n' >"$empty_retired_plugin_tools_directory/sync-plugin-skills.sh"
if HOME="$INSTALL_HOME_EMPTY_RETIRED_PLUGIN_TOOL" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks --dry-run >/tmp/p0p4-install-empty-retired-plugin-tool-dry-run.out 2>/tmp/p0p4-install-empty-retired-plugin-tool-dry-run.err \
    && grep -Fq 'Remove retired managed plugin tool:' /tmp/p0p4-install-empty-retired-plugin-tool-dry-run.out \
    && grep -Fq 'Remove empty retired plugin tools directory:' /tmp/p0p4-install-empty-retired-plugin-tool-dry-run.out \
    && [[ -d "$empty_retired_plugin_tools_directory" ]] \
    && HOME="$INSTALL_HOME_EMPTY_RETIRED_PLUGIN_TOOL" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-empty-retired-plugin-tool.out 2>/tmp/p0p4-install-empty-retired-plugin-tool.err \
    && [[ ! -e "$empty_retired_plugin_tools_directory" && ! -L "$empty_retired_plugin_tools_directory" ]]; then
    pass
else
    fail "installer dry-run must report and reinstall must prune an otherwise empty retired plugin tools directory"
fi

test_start "installer rejects unsafe retired plugin tool parents before skill mutation"
INSTALL_HOME_UNSAFE_RETIRED_PLUGIN_ROOT="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_UNSAFE_RETIRED_PLUGIN_ROOT"
unsafe_retired_plugin_failure=""
for unsafe_parent_kind in symlink wrong-type; do
    unsafe_home="$INSTALL_HOME_UNSAFE_RETIRED_PLUGIN_ROOT/$unsafe_parent_kind"
    unsafe_skill_directory="$unsafe_home/.codex/skills/assistant-workflow"
    unsafe_plugin_parent="$unsafe_home/.codex/tools/plugins"
    mkdir -p "$unsafe_skill_directory" "$(dirname "$unsafe_plugin_parent")"
    printf 'preserve existing skill\n' >"$unsafe_skill_directory/SKILL.md"
    cp "$unsafe_skill_directory/SKILL.md" "$unsafe_home/skill.before"
    if [[ "$unsafe_parent_kind" == "symlink" ]]; then
        unsafe_external_directory="$INSTALL_HOME_UNSAFE_RETIRED_PLUGIN_ROOT/external-target"
        mkdir -p "$unsafe_external_directory"
        printf 'preserve external target\n' >"$unsafe_external_directory/sentinel.txt"
        cp "$unsafe_external_directory/sentinel.txt" "$unsafe_home/external.before"
        ln -s "$unsafe_external_directory" "$unsafe_plugin_parent"
    else
        printf 'preserve wrong-type parent\n' >"$unsafe_plugin_parent"
    fi

    if HOME="$unsafe_home" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-unsafe-retired-plugin.out 2>/tmp/p0p4-install-unsafe-retired-plugin.err; then
        unsafe_retired_plugin_failure="$unsafe_parent_kind parent was accepted"
        break
    elif ! cmp -s "$unsafe_skill_directory/SKILL.md" "$unsafe_home/skill.before"; then
        unsafe_retired_plugin_failure="$unsafe_parent_kind rejection mutated the existing skill"
        break
    elif [[ "$unsafe_parent_kind" == "symlink" ]] && ! cmp -s "$unsafe_external_directory/sentinel.txt" "$unsafe_home/external.before"; then
        unsafe_retired_plugin_failure="symlink rejection mutated the external target"
        break
    fi
done
if [[ -z "$unsafe_retired_plugin_failure" ]]; then
    pass
else
    fail "$unsafe_retired_plugin_failure"
fi

test_start "Codex reinstall preserves legacy Memory Graph MCP config without a Codex CLI"
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
startup_timeout_sec = 10

[mcp_servers.memory-graph.tools.memory_context]
approval_mode = "deny"

[mcp_servers.memory-graph.tools.memory_search]
approval_mode = "approve"

[features]
hooks = false
codex_hooks = false
STALE_CODEX_MCP
chmod 600 "$INSTALL_HOME_NINE/.codex/config.toml"
cp "$INSTALL_HOME_NINE/.codex/config.toml" "$INSTALL_HOME_NINE/original-config.toml"
if HOME="$INSTALL_HOME_NINE" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-stale-codex-mcp.out 2>/tmp/p0p4-install-stale-codex-mcp.err; then
    config_file="$INSTALL_HOME_NINE/.codex/config.toml"
    config_mode="$(p0p4_file_mode_octal "$config_file")"
    if ! cmp -s "$config_file" "$INSTALL_HOME_NINE/original-config.toml" \
        || [[ "$config_mode" != "600" ]]; then
        fail "expected legacy Codex MCP configuration to remain byte-for-byte unchanged with its file mode preserved"
    else
        pass
    fi
else
    fail "Codex install with legacy memory-graph MCP config failed; see /tmp/p0p4-install-stale-codex-mcp.err"
fi

test_start "clean install keeps legacy offline evals but excludes source-only promotion evaluators"
INSTALL_HOME_EIGHT="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_EIGHT"
mkdir -p "$INSTALL_HOME_EIGHT/.codex/tools/evals/lib"
printf 'stale\n' >"$INSTALL_HOME_EIGHT/.codex/tools/evals/run-codex-framework-evals.sh"
printf 'stale\n' >"$INSTALL_HOME_EIGHT/.codex/tools/evals/finalize-workflow-kernel-review.sh"
printf 'stale\n' >"$INSTALL_HOME_EIGHT/.codex/tools/evals/lib/context-budget-evidence.sh"
printf 'stale\n' >"$INSTALL_HOME_EIGHT/.codex/tools/evals/validate-promotion-decision-schema.cjs"
printf 'stale\n' >"$INSTALL_HOME_EIGHT/.codex/tools/evals/package.json"
printf 'stale\n' >"$INSTALL_HOME_EIGHT/.codex/tools/evals/package-lock.json"
mkdir -p "$INSTALL_HOME_EIGHT/.codex/tools/evals/node_modules/stale/nested"
printf 'stale\n' >"$INSTALL_HOME_EIGHT/.codex/tools/evals/node_modules/stale/nested/package.json"
printf 'stale\n' >"$INSTALL_HOME_EIGHT/.codex/tools/context-budget-report.sh"
if HOME="$INSTALL_HOME_EIGHT" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-evals.out 2>/tmp/p0p4-install-evals.err; then
    installed_runner="$INSTALL_HOME_EIGHT/.codex/tools/evals/run-framework-instruction-evals.sh"
    installed_fixture="$INSTALL_HOME_EIGHT/.codex/docs/evals/framework-instruction-cases.json"
    installed_codex_runner="$INSTALL_HOME_EIGHT/.codex/tools/evals/run-codex-framework-evals.sh"
    installed_finalizer="$INSTALL_HOME_EIGHT/.codex/tools/evals/finalize-workflow-kernel-review.sh"
    installed_evidence_lib="$INSTALL_HOME_EIGHT/.codex/tools/evals/lib/context-budget-evidence.sh"
    installed_promotion_validator="$INSTALL_HOME_EIGHT/.codex/tools/evals/validate-promotion-decision-schema.cjs"
    installed_eval_package="$INSTALL_HOME_EIGHT/.codex/tools/evals/package.json"
    installed_eval_package_lock="$INSTALL_HOME_EIGHT/.codex/tools/evals/package-lock.json"
    installed_eval_node_modules="$INSTALL_HOME_EIGHT/.codex/tools/evals/node_modules"
    installed_context_reporter="$INSTALL_HOME_EIGHT/.codex/tools/context-budget-report.sh"
    if [[ -x "$installed_runner" ]] \
        && [[ -f "$installed_fixture" ]] \
        && [[ ! -e "$installed_codex_runner" ]] \
        && [[ ! -e "$installed_finalizer" ]] \
        && [[ ! -e "$installed_evidence_lib" ]] \
        && [[ ! -e "$installed_promotion_validator" ]] \
        && [[ ! -e "$installed_eval_package" ]] \
        && [[ ! -e "$installed_eval_package_lock" ]] \
        && [[ ! -e "$installed_eval_node_modules" ]] \
        && [[ ! -e "$installed_context_reporter" ]] \
        && HOME="$INSTALL_HOME_EIGHT" "$installed_runner" --validate-fixture >/tmp/p0p4-installed-eval-runner.out 2>/tmp/p0p4-installed-eval-runner.err; then
        pass
    else
        fail "clean install must omit source-only promotion evaluators while preserving the legacy offline runner and fixture"
    fi
else
    fail "codex install for eval runner fixture failed; see /tmp/p0p4-install-evals.err"
fi

test_start "default install uses assistant inventory without Unity hardcoding"
INSTALL_HOME_TEN="$(mktemp -d)"
UNITY_FIXTURE="$(mktemp -d "$FRAMEWORK_DIR/skills/unity-contract-fixture-XXXXXX")"
UNITY_FIXTURE_NAME="$(basename "$UNITY_FIXTURE")"
ASSISTANT_UNITY_FIXTURE="$(mktemp -d "$FRAMEWORK_DIR/skills/assistant-unity-contract-fixture-XXXXXX")"
ASSISTANT_UNITY_FIXTURE_NAME="$(basename "$ASSISTANT_UNITY_FIXTURE")"
p0p4_register_cleanup "$INSTALL_HOME_TEN" "$UNITY_FIXTURE" "$ASSISTANT_UNITY_FIXTURE"
cat > "$UNITY_FIXTURE/SKILL.md" <<'UNITY_SKILL'
---
name: unity-local-contract-fixture
description: Local-only Unity fixture that must not be installed by default.
---

# Unity Local Contract Fixture
UNITY_SKILL
cat > "$ASSISTANT_UNITY_FIXTURE/SKILL.md" <<'ASSISTANT_UNITY_SKILL'
---
name: assistant-unity-contract-fixture
description: Assistant-named Unity fixture that should follow the normal assistant inventory rule.
---

# Assistant Unity Contract Fixture
ASSISTANT_UNITY_SKILL
if HOME="$INSTALL_HOME_TEN" bash "$FRAMEWORK_DIR/install.sh" --agent codex --no-hooks >/tmp/p0p4-install-default-skills.out 2>/tmp/p0p4-install-default-skills.err; then
    installed_skills_dir="$INSTALL_HOME_TEN/.codex/skills"
    agents_file="$INSTALL_HOME_TEN/.codex/AGENTS.md"
    missing_assistant_skill=""
    unexpected_installed_skill=""
    source_assistant_skill_count=0
    agents_assistant_skill_rows="$(count_occurrences "^| assistant-" "$agents_file")"

    while IFS= read -r source_skill_md; do
        source_assistant_skill_count=$((source_assistant_skill_count + 1))
        source_skill="$(basename "$(dirname "$source_skill_md")")"
        if [[ "$source_skill" == "assistant-memory" || "$source_skill" == "assistant-reflexion" ]]; then
            continue
        fi
        if [[ ! -d "$installed_skills_dir/$source_skill" ]]; then
            missing_assistant_skill="$source_skill"
            break
        fi
    done < <(find "$FRAMEWORK_DIR/skills" -maxdepth 2 -path "$FRAMEWORK_DIR/skills/assistant-*/SKILL.md" -type f | sort)

    rm -rf "$UNITY_FIXTURE" "$ASSISTANT_UNITY_FIXTURE"

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
    elif [[ "$source_assistant_skill_count" -lt "14" ]]; then
        fail "expected source inventory to contain at least 14 non-retired assistant skills including the assistant-named custom fixture; found $source_assistant_skill_count"
    elif [[ "$agents_assistant_skill_rows" != "0" ]] || ! grep -Fq "Codex uses installed skills through native skill routing." "$agents_file"; then
        fail "expected generated Codex AGENTS.md to stay lean and keep routing metadata in installed skills"
    elif [[ -n "$unexpected_installed_skill" ]]; then
        fail "expected default install to exclude non-assistant skill $unexpected_installed_skill"
    elif [[ -e "$installed_skills_dir/$UNITY_FIXTURE_NAME" ]]; then
        fail "expected default install to exclude non-assistant local Unity fixture"
    elif [[ ! -e "$installed_skills_dir/$ASSISTANT_UNITY_FIXTURE_NAME" ]]; then
        fail "expected default install to include assistant-named custom Unity fixture"
    else
        pass
    fi
else
    rm -rf "$UNITY_FIXTURE" "$ASSISTANT_UNITY_FIXTURE"
    fail "default install with Unity fixture coverage failed; see /tmp/p0p4-install-default-skills.err"
fi

test_start "deprecated --no-hooks remains a hookless no-op for one compatibility release"
CODEX_NO_HOOKS_HOME="$(mktemp -d)"
p0p4_register_cleanup "$CODEX_NO_HOOKS_HOME"
if HOME="$CODEX_NO_HOOKS_HOME" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-codex-no-hooks.out 2>/tmp/p0p4-install-codex-no-hooks.err; then
    if [[ ! -f "$CODEX_NO_HOOKS_HOME/.codex/hooks.json" ]] \
        && ! grep -Fq "hooks = true" "$CODEX_NO_HOOKS_HOME/.codex/config.toml" \
        && grep -Fq -- "--no-hooks is deprecated" /tmp/p0p4-install-codex-no-hooks.err; then
        pass
    else
        fail "deprecated --no-hooks should warn without creating hooks.json or enabling hooks"
    fi
else
    fail "Codex --no-hooks install failed; see /tmp/p0p4-install-codex-no-hooks.err"
fi

test_start "selective debugging and review installs ship an executable common change-impact checker"
CHANGE_IMPACT_INSTALL_ROOT="$(mktemp -d)"
p0p4_register_cleanup "$CHANGE_IMPACT_INSTALL_ROOT"
change_impact_install_failure=""
for change_impact_skill in assistant-debugging assistant-review; do
    change_impact_home="$CHANGE_IMPACT_INSTALL_ROOT/$change_impact_skill home [isolated]"
    change_impact_case="$change_impact_home/change impact fixture"
    change_impact_skill_file="$change_impact_home/.codex/skills/$change_impact_skill/SKILL.md"
    change_impact_tool="$(dirname "$change_impact_skill_file")/../../tools/change-impact/validate-change-impact.cjs"
    change_impact_protocol="$(dirname "$change_impact_skill_file")/../../tools/change-impact/protocol.v1.json"
    change_impact_example="$(dirname "$change_impact_skill_file")/../../tools/change-impact/example.completion.v1.json"
    change_impact_reference="$change_impact_home/.codex/skills/$change_impact_skill/references/change-impact.md"
    mkdir -p "$change_impact_case"
    if ! HOME="$change_impact_home" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill "$change_impact_skill" --no-hooks >/tmp/p0p4-change-impact-${change_impact_skill}.out 2>/tmp/p0p4-change-impact-${change_impact_skill}.err; then
        change_impact_install_failure="$change_impact_skill selective install failed"
        break
    elif [[ ! -f "$change_impact_skill_file" || ! -f "$change_impact_tool" || ! -f "$change_impact_protocol" || ! -f "$change_impact_example" ]]; then
        change_impact_install_failure="$change_impact_skill selective install omitted common validator resources at the path resolved from its loaded SKILL.md"
        break
    elif [[ -d "$change_impact_home/.codex/skills/assistant-workflow" || ! -f "$change_impact_reference" ]] \
        || ! grep -Fq '../../tools/change-impact/validate-change-impact.cjs' "$change_impact_reference"; then
        change_impact_install_failure="$change_impact_skill did not resolve the installed common checker without workflow"
        break
    elif ! node -e 'const fs=require("node:fs"); const source=JSON.parse(fs.readFileSync(process.argv[1], "utf8")); const target=process.argv[2]; for (const [name, value] of Object.entries(source)) fs.writeFileSync(`${target}/${name}.json`, JSON.stringify(value));' "$FRAMEWORK_DIR/tools/change-impact/example.completion.v1.json" "$change_impact_case"; then
        change_impact_install_failure="$change_impact_skill could not materialize the valid checker fixture"
        break
    elif ! node "$change_impact_tool" --phase completion --capture "$change_impact_case/capture.json" --expected "$change_impact_case/expected.json" --assessment "$change_impact_case/assessment.json" --review "$change_impact_case/review.json" >/tmp/p0p4-change-impact-${change_impact_skill}-valid.out; then
        change_impact_install_failure="$change_impact_skill installed checker rejected its valid protocol example"
        break
    elif ! node -e 'const fs=require("node:fs"); const p=process.argv[1]; const value=JSON.parse(fs.readFileSync(p,"utf8")); const edge=value.edges.pop(); value.requirements=value.requirements.filter((requirement) => requirement.edge_id !== edge.id); fs.writeFileSync(p,JSON.stringify(value));' "$change_impact_case/capture.json"; then
        change_impact_install_failure="$change_impact_skill could not materialize the consumer-omission fixture"
        break
    elif node "$change_impact_tool" --phase completion --capture "$change_impact_case/capture.json" --expected "$change_impact_case/expected.json" --assessment "$change_impact_case/assessment.json" --review "$change_impact_case/review.json" >/tmp/p0p4-change-impact-${change_impact_skill}-consumer-omission.out; then
        change_impact_install_failure="$change_impact_skill installed checker accepted a capture missing a known consumer"
        break
    elif ! grep -Fq 'CAPTURE_EXPECTED_EDGES_MISMATCH' /tmp/p0p4-change-impact-${change_impact_skill}-consumer-omission.out; then
        change_impact_install_failure="$change_impact_skill consumer omission did not fail against independent expected truth"
        break
    elif ! node -e 'const fs=require("node:fs"); const source=JSON.parse(fs.readFileSync(process.argv[1], "utf8")); fs.writeFileSync(process.argv[2],JSON.stringify(source.capture));' "$FRAMEWORK_DIR/tools/change-impact/example.completion.v1.json" "$change_impact_case/capture.json"; then
        change_impact_install_failure="$change_impact_skill could not restore the root-omission fixture"
        break
    elif ! node -e 'const fs=require("node:fs"); const p=process.argv[1]; const value=JSON.parse(fs.readFileSync(p,"utf8")); value.roots=[]; fs.writeFileSync(p,JSON.stringify(value));' "$change_impact_case/capture.json"; then
        change_impact_install_failure="$change_impact_skill could not materialize the omission fixture"
        break
    elif node "$change_impact_tool" --phase completion --capture "$change_impact_case/capture.json" --expected "$change_impact_case/expected.json" --assessment "$change_impact_case/assessment.json" --review "$change_impact_case/review.json" >/tmp/p0p4-change-impact-${change_impact_skill}-omission.out; then
        change_impact_install_failure="$change_impact_skill installed checker accepted an empty shared discovery-root capture"
        break
    elif ! grep -Fq 'CAPTURE_DISCOVERY_ROOTS_MISSING' /tmp/p0p4-change-impact-${change_impact_skill}-omission.out; then
        change_impact_install_failure="$change_impact_skill omission did not fail for the missing discovery-root reason"
        break
    fi
done
if [[ -z "$change_impact_install_failure" ]]; then
    pass
else
    fail "$change_impact_install_failure"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
