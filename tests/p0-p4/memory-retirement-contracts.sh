#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"
p0p4_enable_codex_semantic_fixture

cleanup_bash="$FRAMEWORK_DIR/tools/cleanup-memory-graph.sh"
cleanup_powershell="$FRAMEWORK_DIR/tools/cleanup-memory-graph.ps1"

skip() {
    printf 'skipped: %s\n' "$*"
}

test_start "released skill inventory retires custom memory and reflexion skills"
first_class_skill_count="$(find "$FRAMEWORK_DIR/skills"/assistant-* -mindepth 1 -maxdepth 1 -type f -name SKILL.md | wc -l | tr -d ' ')"
if [[ -e "$FRAMEWORK_DIR/skills/assistant-memory" || -e "$FRAMEWORK_DIR/skills/assistant-reflexion" \
    || -e "$FRAMEWORK_DIR/plugins/assistant-core/skills/assistant-memory" || -e "$FRAMEWORK_DIR/plugins/assistant-core/skills/assistant-reflexion" ]]; then
    fail "released framework must not retain canonical or generated assistant-memory/assistant-reflexion skill directories"
elif [[ "$first_class_skill_count" != "14" ]]; then
    fail "released framework must expose exactly 14 first-class skills; found $first_class_skill_count"
else
    pass
fi

test_start "workflow contracts retire learning-controller persistence and Memory Graph routing"
workflow_retirement_candidates=(
    "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md"
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts"
    "$FRAMEWORK_DIR/skills/assistant-workflow/references"
    "$FRAMEWORK_DIR/skills/assistant-workflow/templates"
    "$FRAMEWORK_DIR/skills/assistant-workflow/scripts"
)
workflow_retirement_paths=()
for workflow_retirement_candidate in "${workflow_retirement_candidates[@]}"; do
    [[ -e "$workflow_retirement_candidate" ]] && workflow_retirement_paths+=("$workflow_retirement_candidate")
done
if rg -n -i -e 'Learning Controller' -e 'learning_capture_mode' -e 'memory_(signal|trend|reflect)' \
    -e 'validate-learning-state\\.sh' -e 'memory_(context|search|add_insight)' \
    "${workflow_retirement_paths[@]}" >/tmp/p0p4-workflow-retirement.out; then
    workflow_retirement_status=0
else
    workflow_retirement_status=$?
fi
if [[ "$workflow_retirement_status" == "0" ]]; then
    fail "workflow source, contracts, references, templates, and scripts must not route or persist retired learning/Memory Graph capabilities"
elif [[ "$workflow_retirement_status" == "1" ]]; then
    pass
else
    fail "workflow retirement scan could not inspect the declared workflow surface"
fi

test_start "research and onboarding retire Memory Graph calls and durable-memory outputs"
if rg -n -i -e 'Memory Graph' -e 'memory_(context|search|add_insight|reflect)' \
    "$FRAMEWORK_DIR/skills/assistant-research" "$FRAMEWORK_DIR/skills/assistant-onboard" >/tmp/p0p4-research-onboard-retirement.out; then
    fail "assistant-research and assistant-onboard must not route to Memory Graph or promise durable-memory output"
elif rg -n -e 'durable_memory_updated' -e 'memory_add_insight' \
    "$FRAMEWORK_DIR/skills/assistant-research/contracts/output.yaml" "$FRAMEWORK_DIR/skills/assistant-onboard/contracts/output.yaml" >/tmp/p0p4-research-onboard-retirement.out; then
    fail "assistant-research and assistant-onboard output contracts must not retain durable-memory fields"
else
    pass
fi

test_start "assistant-core manifest and generated mirrors contain only clarify and Telos"
core_expected="$(mktemp "${TMPDIR:-/tmp}/assistant-core-retirement-expected.XXXXXX")"
core_actual="$(mktemp "${TMPDIR:-/tmp}/assistant-core-retirement-actual.XXXXXX")"
p0p4_register_cleanup "$core_expected" "$core_actual"
printf '%s\n' assistant-clarify assistant-telos >"$core_expected"
find "$FRAMEWORK_DIR/plugins/assistant-core/skills" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print \
    | while IFS= read -r skill_file; do basename "$(dirname "$skill_file")"; done | sort >"$core_actual"
if ! jq -e '
    .name == "assistant-core"
    and .description == "Foundation skills for clarification and Telos context."
    and (.keywords == ["assistant-framework", "clarification", "telos"])
    and (.interface.defaultPrompt | length == 2)
' "$FRAMEWORK_DIR/plugins/assistant-core/.codex-plugin/plugin.json" >/dev/null; then
    fail "assistant-core manifest must retire memory/reflexion metadata and describe clarify plus Telos only"
elif ! cmp -s "$core_expected" "$core_actual"; then
    fail "assistant-core generated mirror surface must contain exactly assistant-clarify and assistant-telos"
elif ! "$FRAMEWORK_DIR/tools/plugins/sync-plugin-skills.sh" --check >/tmp/p0p4-retired-core-mirror-sync.out 2>/tmp/p0p4-retired-core-mirror-sync.err; then
    fail "assistant-core retirement mirrors must be generated and pass sync parity validation"
else
    pass
fi

p0p4_memory_retirement_file_mode_octal() {
    local path="$1"
    case "$(uname -s)" in
        Darwin|FreeBSD) stat -f "%Lp" "$path" ;;
        *) stat -c "%a" "$path" ;;
    esac
}

test_start "PowerShell cleanup preserves restrictive Unix config mode after successful Codex retirement"
if ! command -v pwsh >/dev/null 2>&1; then
    skip "pwsh is unavailable for PowerShell mode-preservation verification"
else
    ps_mode_home="$(mktemp -d)"
    ps_mode_bin="$(mktemp -d)"
    p0p4_register_cleanup "$ps_mode_home" "$ps_mode_bin"
    mkdir -p "$ps_mode_home/.codex/tools/memory-graph" "$ps_mode_home/.codex/memory"
    printf '%s\n' runtime >"$ps_mode_home/.codex/tools/memory-graph/run-memory-graph.ps1"
    printf '%s\n' provider >"$ps_mode_home/.codex/memory/graph.db"
    printf '%s\n' '[mcp_servers.memory-graph]' 'command = "retire"' '' '[mcp_servers.keep]' 'command = "keep"' >"$ps_mode_home/.codex/config.toml"
    chmod 600 "$ps_mode_home/.codex/config.toml"
    printf '%s\n' '#!/bin/sh' \
        'if [ "$1" = "mcp" ] && [ "$2" = "list" ] && [ "$3" = "--json" ]; then' \
        '  if grep -Fxq "[mcp_servers.memory-graph]" "$HOME/config.toml"; then printf "[{\\\"name\\\":\\\"memory-graph\\\"}]\\n"; else printf "[]\\n"; fi' \
        '  exit 0' \
        'fi' \
        'exit 64' >"$ps_mode_bin/codex"
    chmod +x "$ps_mode_bin/codex"
    if USERPROFILE="$ps_mode_home" HOME="$ps_mode_home" PATH="$ps_mode_bin:$PATH" pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent codex >/tmp/p0p4-ps-mode.out 2>/tmp/p0p4-ps-mode.err; then
        ps_mode_status=0
    else
        ps_mode_status=$?
    fi
    if [[ "$ps_mode_status" -ne 0 ]] \
        || [[ "$(p0p4_memory_retirement_file_mode_octal "$ps_mode_home/.codex/config.toml")" != "600" ]] \
        || grep -Fq '[mcp_servers.memory-graph]' "$ps_mode_home/.codex/config.toml" \
        || ! grep -Fq '[mcp_servers.keep]' "$ps_mode_home/.codex/config.toml" \
        || [[ -e "$ps_mode_home/.codex/tools/memory-graph" || ! -f "$ps_mode_home/.codex/memory/graph.db" ]]; then
        fail "PowerShell cleanup did not preserve restrictive Unix config mode during successful retirement"
    else
        pass
    fi
fi

test_start "PowerShell applies destination-equivalent Unix mode before the first temporary content byte"
atomic_writer_body="$(sed -n '/^function Write-AtomicUtf8 {/,/^function /p' "$cleanup_powershell")"
mode_apply_index="$(printf '%s\n' "$atomic_writer_body" | grep -n -F 'Set-UnixFileModeExact -LiteralPath $temp -Mode $originalMode' | head -n 1 | cut -d: -f1)"
content_write_index="$(printf '%s\n' "$atomic_writer_body" | grep -n -E 'WriteAllBytes\(\$temp|\$tempStream\.Write\(' | head -n 1 | cut -d: -f1)"
if [[ -z "$mode_apply_index" || -z "$content_write_index" || "$mode_apply_index" -ge "$content_write_index" ]]; then
    fail "PowerShell atomic cleanup writes temporary content before applying destination-equivalent Unix mode"
else
    pass
fi

test_start "Bash Codex cleanup retires native and configured legacy skill roots independently"
native_codex_home="$(mktemp -d)"
native_codex_legacy="$native_codex_home/custom-codex-home"
p0p4_register_cleanup "$native_codex_home"
mkdir -p "$native_codex_home/.agents/skills/assistant-memory" "$native_codex_home/.agents/skills/assistant-reflexion" \
    "$native_codex_home/.agents/skills/unrelated-native-skill" "$native_codex_legacy/skills/assistant-memory" \
    "$native_codex_legacy/skills/assistant-reflexion" "$native_codex_legacy/tools/memory-graph" "$native_codex_legacy/memory"
printf '%s\n' native >"$native_codex_home/.agents/skills/assistant-memory/SKILL.md"
printf '%s\n' native >"$native_codex_home/.agents/skills/assistant-reflexion/SKILL.md"
printf '%s\n' preserve >"$native_codex_home/.agents/skills/unrelated-native-skill/SKILL.md"
printf '%s\n' legacy >"$native_codex_legacy/skills/assistant-memory/SKILL.md"
printf '%s\n' legacy >"$native_codex_legacy/skills/assistant-reflexion/SKILL.md"
printf '%s\n' runtime >"$native_codex_legacy/tools/memory-graph/run-memory-graph.sh"
printf '%s\n' provider >"$native_codex_legacy/memory/graph.db"
if ! HOME="$native_codex_home" CODEX_HOME="$native_codex_legacy" bash "$cleanup_bash" --agent codex >/tmp/p0p4-native-codex.out 2>/tmp/p0p4-native-codex.err; then
    fail "Bash Codex cleanup failed while retiring independent native and legacy skill roots"
elif [[ -e "$native_codex_home/.agents/skills/assistant-memory" || -e "$native_codex_home/.agents/skills/assistant-reflexion" \
    || -e "$native_codex_legacy/skills/assistant-memory" || -e "$native_codex_legacy/skills/assistant-reflexion" \
    || -e "$native_codex_legacy/tools/memory-graph" || ! -f "$native_codex_home/.agents/skills/unrelated-native-skill/SKILL.md" \
    || ! -f "$native_codex_legacy/memory/graph.db" ]]; then
    fail "Bash Codex cleanup did not retire both native and legacy exact skills while preserving unrelated native state and provider data"
else
    pass
fi

test_start "standalone Bash Memory Graph cleanup is dry-run safe and purges only on request"
if [[ ! -x "$cleanup_bash" ]]; then
    fail "missing executable tools/cleanup-memory-graph.sh"
else
    cleanup_home="$(mktemp -d)"
    p0p4_register_cleanup "$cleanup_home"
    mkdir -p "$cleanup_home/.codex/skills/assistant-memory" \
        "$cleanup_home/.codex/skills/assistant-reflexion" \
        "$cleanup_home/.codex/tools/memory-graph" \
        "$cleanup_home/.codex/memory" \
        "$cleanup_home/.claude/skills/assistant-memory" \
        "$cleanup_home/.claude/skills/assistant-reflexion" \
        "$cleanup_home/.claude/tools/memory-graph" \
        "$cleanup_home/.claude/memory" \
        "$cleanup_home/.gemini/skills/assistant-memory" \
        "$cleanup_home/.gemini/skills/assistant-reflexion" \
        "$cleanup_home/.gemini/tools/memory-graph" \
        "$cleanup_home/.gemini/memory"
    printf '%s\n' 'keep-memory-data' >"$cleanup_home/.codex/memory/graph.db"
    printf '%s\n' 'keep-memory-data' >"$cleanup_home/.claude/memory/graph.db"
    printf '%s\n' 'keep-memory-data' >"$cleanup_home/.gemini/memory/graph.db"
    printf '%s\n' 'framework tool' >"$cleanup_home/.codex/tools/memory-graph/run-memory-graph.sh"
    printf '%s\n' 'keep similar tool' >"$cleanup_home/.codex/tools/memory-graphical"
    cat >"$cleanup_home/.codex/config.toml" <<'TOML'
model = "keep-model"

[mcp_servers.memory-graph]
command = "/framework/tools/memory-graph/run-memory-graph.sh"

[mcp_servers.memory-graph.tools.memory_search]
approval_mode = "approve"

[mcp_servers.memory-graphical]
command = "keep-similar"
TOML
    chmod 600 "$cleanup_home/.codex/config.toml"
    for agent_file in "$cleanup_home/.codex/AGENTS.md" "$cleanup_home/.claude/CLAUDE.md" "$cleanup_home/.gemini/GEMINI.md"; do
        cat >"$agent_file" <<'INSTRUCTIONS'
User-authored instructions must remain.
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->
Framework-owned Memory Graph protocol.
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->
INSTRUCTIONS
    done
    cat >"$cleanup_home/.claude/settings.json" <<'JSON'
{"mcpServers":{"memory-graph":{"command":"framework-memory"},"custom":{"command":"keep-custom"}}}
JSON
    cp "$cleanup_home/.claude/settings.json" "$cleanup_home/.gemini/settings.json"
    cp "$cleanup_home/.codex/config.toml" "$cleanup_home/.codex/config.before"

    if ! HOME="$cleanup_home" bash "$cleanup_bash" --dry-run >/tmp/p0p4-memory-cleanup-dry.out 2>/tmp/p0p4-memory-cleanup-dry.err; then
        fail "Memory Graph cleanup dry-run failed"
    elif ! cmp -s "$cleanup_home/.codex/config.before" "$cleanup_home/.codex/config.toml" \
        || [[ "$(p0p4_memory_retirement_file_mode_octal "$cleanup_home/.codex/config.toml")" != "600" ]] \
        || [[ ! -d "$cleanup_home/.codex/tools/memory-graph" ]] \
        || [[ ! -f "$cleanup_home/.codex/memory/graph.db" ]]; then
        fail "Memory Graph cleanup dry-run changed framework files, mode, or retained data"
    elif ! HOME="$cleanup_home" bash "$cleanup_bash" >/tmp/p0p4-memory-cleanup.out 2>/tmp/p0p4-memory-cleanup.err; then
        fail "Memory Graph cleanup failed"
    elif grep -Fq '[mcp_servers.memory-graph]' "$cleanup_home/.codex/config.toml" \
        || grep -Fq 'ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START' "$cleanup_home/.codex/AGENTS.md" \
        || grep -Fq 'ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START' "$cleanup_home/.claude/CLAUDE.md" \
        || grep -Fq 'ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START' "$cleanup_home/.gemini/GEMINI.md" \
        || [[ -e "$cleanup_home/.codex/skills/assistant-memory" || -e "$cleanup_home/.codex/skills/assistant-reflexion" || -e "$cleanup_home/.codex/tools/memory-graph" || -e "$cleanup_home/.claude/tools/memory-graph" || -e "$cleanup_home/.gemini/tools/memory-graph" ]] \
        || ! grep -Fq '[mcp_servers.memory-graphical]' "$cleanup_home/.codex/config.toml" \
        || ! grep -Fq 'User-authored instructions must remain.' "$cleanup_home/.claude/CLAUDE.md" \
        || ! jq -e '.mcpServers.custom.command == "keep-custom" and (.mcpServers | has("memory-graph") | not)' "$cleanup_home/.claude/settings.json" >/dev/null \
        || [[ ! -f "$cleanup_home/.codex/memory/graph.db" || ! -f "$cleanup_home/.claude/memory/graph.db" || ! -f "$cleanup_home/.gemini/memory/graph.db" ]] \
        || [[ "$(p0p4_memory_retirement_file_mode_octal "$cleanup_home/.codex/config.toml")" != "600" ]]; then
        fail "default cleanup did not precisely retire framework-owned registrations while preserving unrelated files and memory data"
    elif ! HOME="$cleanup_home" bash "$cleanup_bash" --purge-data >/tmp/p0p4-memory-cleanup-purge.out 2>/tmp/p0p4-memory-cleanup-purge.err; then
        fail "Memory Graph cleanup with --purge-data failed"
    elif [[ -e "$cleanup_home/.codex/memory" || -e "$cleanup_home/.claude/memory" || -e "$cleanup_home/.gemini/memory" ]]; then
        fail "cleanup did not require --purge-data before removing provider memory data"
    elif HOME=/ bash "$cleanup_bash" --dry-run >/tmp/p0p4-memory-cleanup-root.out 2>/tmp/p0p4-memory-cleanup-root.err; then
        fail "cleanup accepted broad root home target"
    else
        pass
    fi
fi

test_start "standalone Bash cleanup rejects symlinked owned paths and ambiguous config before mutation"
if [[ ! -x "$cleanup_bash" ]]; then
    fail "missing executable tools/cleanup-memory-graph.sh"
else
    hostile_home="$(mktemp -d)"
    external_tool_dir="$(mktemp -d)"
    p0p4_register_cleanup "$hostile_home" "$external_tool_dir"
    mkdir -p "$hostile_home/.codex/tools" "$hostile_home/.codex/memory"
    printf '%s\n' 'external sentinel' >"$external_tool_dir/sentinel.txt"
    ln -s "$external_tool_dir" "$hostile_home/.codex/tools/memory-graph"
    cat >"$hostile_home/.codex/config.toml" <<'TOML'
[mcp_servers.memory-graph]
command = "one"

[mcp_servers.keep]
command = "keep"
invalid = [1,
TOML
    cp "$hostile_home/.codex/config.toml" "$hostile_home/.codex/config.before"
    if HOME="$hostile_home" bash "$cleanup_bash" >/tmp/p0p4-memory-cleanup-hostile.out 2>/tmp/p0p4-memory-cleanup-hostile.err; then
        fail "cleanup accepted a symlinked owned path or ambiguous Memory Graph config"
    elif ! cmp -s "$hostile_home/.codex/config.before" "$hostile_home/.codex/config.toml" \
        || [[ ! -L "$hostile_home/.codex/tools/memory-graph" ]] \
        || [[ "$(cat "$external_tool_dir/sentinel.txt")" != "external sentinel" ]]; then
        fail "cleanup mutated an ambiguous config or symlink target before failing safely"
    else
        pass
    fi
fi

test_start "Bash cleanup rejects external CODEX_HOME ancestor symlinks before deletion"
codex_symlink_home="$(mktemp -d)"
codex_symlink_external="$(mktemp -d)"
p0p4_register_cleanup "$codex_symlink_home" "$codex_symlink_external"
mkdir -p "$codex_symlink_external/real-codex/codex-home/tools/memory-graph"
printf '%s\n' keep >"$codex_symlink_external/real-codex/codex-home/tools/memory-graph/sentinel"
ln -s "$codex_symlink_external/real-codex" "$codex_symlink_external/intermediate"
if HOME="$codex_symlink_home" CODEX_HOME="$codex_symlink_external/intermediate/codex-home" bash "$cleanup_bash" --agent codex >/tmp/p0p4-external-codex-home.out 2>/tmp/p0p4-external-codex-home.err; then
    fail "Bash cleanup accepted external CODEX_HOME through an intermediate symlink"
elif [[ ! -f "$codex_symlink_external/real-codex/codex-home/tools/memory-graph/sentinel" ]]; then
    fail "Bash cleanup deleted through an external CODEX_HOME intermediate symlink"
else
    pass
fi

test_start "Bash cleanup accepts macOS /var compatibility paths but rejects managed-boundary symlinks"
if [[ ! -L /var || ! -d /private/var ]]; then
    echo "skipped: macOS /var compatibility alias is unavailable"
else
    var_alias_home="$(mktemp -d "${TMPDIR:-/var/tmp}/assistant-framework-memory-alias.XXXXXX")"
    var_physical_home="$(cd "$var_alias_home" && pwd -P)"
    p0p4_register_cleanup "$var_alias_home"
    if [[ "$var_alias_home" != /var/* || "$var_physical_home" != /private/var/* ]]; then
        skip "temporary directory is not reached through the macOS /var compatibility alias"
    else
        mkdir -p "$var_alias_home/codex-home/tools/memory-graph"
        printf '%s\n' 'safe compatibility sentinel' >"$var_alias_home/codex-home/tools/memory-graph/sentinel"
        if ! HOME="$var_alias_home" CODEX_HOME="$var_alias_home/codex-home" bash "$cleanup_bash" --agent codex >/tmp/p0p4-memory-cleanup-var-alias.out 2>/tmp/p0p4-memory-cleanup-var-alias.err; then
            fail "cleanup rejected a safe CODEX_HOME reached only through macOS /var compatibility alias"
        elif [[ -e "$var_alias_home/codex-home/tools/memory-graph" ]]; then
            fail "cleanup did not retire the safe compatibility-path runtime"
        else
            mkdir -p "$var_alias_home/codex-home" "$var_alias_home/external-memory-graph"
            printf '%s\n' 'malicious-boundary sentinel' >"$var_alias_home/external-memory-graph/sentinel"
            ln -s "$var_alias_home/external-memory-graph" "$var_alias_home/codex-home/tools"
            if HOME="$var_alias_home" CODEX_HOME="$var_alias_home/codex-home" bash "$cleanup_bash" --agent codex >/tmp/p0p4-memory-cleanup-var-alias-hostile.out 2>/tmp/p0p4-memory-cleanup-var-alias-hostile.err; then
                fail "cleanup accepted a symlink inside a compatibility-path CODEX_HOME boundary"
            elif [[ ! -f "$var_alias_home/external-memory-graph/sentinel" ]]; then
                fail "cleanup deleted through a managed-boundary symlink after accepting macOS /var alias"
            else
                pass
            fi
        fi
    fi
fi

test_start "Bash cleanup preserves BOM TOML and unrelated JSON number lexemes"
lexeme_home="$(mktemp -d)"
p0p4_register_cleanup "$lexeme_home"
mkdir -p "$lexeme_home/.codex/tools/memory-graph" "$lexeme_home/.claude"
printf '\357\273\277%s\n' '[mcp_servers.memory-graph]' 'command = "retire"' '[mcp_servers.keep]' 'command = "keep"' >"$lexeme_home/.codex/config.toml"
printf '%s\n' '{"mcpServers":{"memory-graph":{"command":"retire"},"keep":{"decimal":1.234567890123456789,"integer":123456789012345678901234567890,"scientific":1.2e+30}}}' >"$lexeme_home/.claude/settings.json"
cp "$lexeme_home/.claude/settings.json" "$lexeme_home/.claude/settings.before"
lexeme_failures=()
if ! HOME="$lexeme_home" bash "$cleanup_bash" --agent codex >/tmp/p0p4-bom.out 2>/tmp/p0p4-bom.err; then
    lexeme_failures+=("Bash cleanup failed to retire BOM-prefixed Codex TOML")
elif grep -Fq 'memory-graph' "$lexeme_home/.codex/config.toml" || [[ -e "$lexeme_home/.codex/tools/memory-graph" ]]; then
    lexeme_failures+=("Bash cleanup retained BOM-prefixed registration or deleted runtime inconsistently")
fi
if ! HOME="$lexeme_home" bash "$cleanup_bash" --agent claude >/tmp/p0p4-lexeme.out 2>/tmp/p0p4-lexeme.err; then
    lexeme_failures+=("Bash cleanup failed to retire JSON registration")
elif ! grep -Fq '1.234567890123456789' "$lexeme_home/.claude/settings.json" \
    || ! grep -Fq '123456789012345678901234567890' "$lexeme_home/.claude/settings.json" \
    || ! grep -Fq '1.2e+30' "$lexeme_home/.claude/settings.json"; then
    lexeme_failures+=("Bash cleanup rewrote unrelated JSON number lexemes")
fi
if [[ "${#lexeme_failures[@]}" -ne 0 ]]; then
    fail "${lexeme_failures[*]}"
else
    pass
fi

test_start "standalone Bash cleanup fails closed for interleaved managed instruction markers"
interleaved_home="$(mktemp -d)"
p0p4_register_cleanup "$interleaved_home"
mkdir -p "$interleaved_home/.codex"
cat >"$interleaved_home/.codex/AGENTS.md" <<'INSTRUCTIONS'
<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_START -->
agent guidance
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->
retired protocol
<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_END -->
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->
User-authored instructions must remain.
INSTRUCTIONS
cp "$interleaved_home/.codex/AGENTS.md" "$interleaved_home/.codex/AGENTS.before"
if HOME="$interleaved_home" bash "$cleanup_bash" --agent codex >/tmp/p0p4-memory-cleanup-interleaved.out 2>/tmp/p0p4-memory-cleanup-interleaved.err; then
    fail "Bash cleanup accepted interleaved managed instruction markers"
elif ! cmp -s "$interleaved_home/.codex/AGENTS.before" "$interleaved_home/.codex/AGENTS.md"; then
    fail "Bash cleanup changed interleaved managed instruction markers before failing"
else
    pass
fi

test_start "standalone PowerShell cleanup rejects root CODEX_HOME before mutation"
ps_root_home="$(mktemp -d)"
p0p4_register_cleanup "$ps_root_home"
mkdir -p "$ps_root_home/.agents/skills/assistant-memory"
printf '%s\n' 'native skill sentinel' >"$ps_root_home/.agents/skills/assistant-memory/SKILL.md"
if ! command -v pwsh >/dev/null 2>&1; then
    skip "pwsh is unavailable for PowerShell cleanup behavior verification"
elif USERPROFILE="$ps_root_home" CODEX_HOME=/ pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent codex -DryRun >/tmp/p0p4-memory-cleanup-ps-root.out 2>/tmp/p0p4-memory-cleanup-ps-root.err; then
    fail "PowerShell cleanup accepted filesystem-root CODEX_HOME"
elif [[ ! -f "$ps_root_home/.agents/skills/assistant-memory/SKILL.md" ]]; then
    fail "PowerShell cleanup mutated native skills before rejecting filesystem-root CODEX_HOME"
else
    pass
fi

test_start "Bash and PowerShell reject raw relative CODEX_HOME before mutation"
relative_failures=()
relative_runners=(bash)
command -v pwsh >/dev/null 2>&1 && relative_runners+=(powershell)
for relative_runner in "${relative_runners[@]}"; do
    relative_home="$(mktemp -d)"
    p0p4_register_cleanup "$relative_home"
    mkdir -p "$relative_home/.agents/skills/assistant-memory"
    printf '%s\n' 'native sentinel' >"$relative_home/.agents/skills/assistant-memory/SKILL.md"
    if [[ "$relative_runner" == bash ]]; then
        if HOME="$relative_home" CODEX_HOME=relative-codex-home bash "$cleanup_bash" --agent codex --dry-run >/tmp/p0p4-memory-cleanup-relative-bash.out 2>/tmp/p0p4-memory-cleanup-relative-bash.err; then
            relative_failures+=("Bash cleanup accepted raw relative CODEX_HOME")
        fi
    elif USERPROFILE="$relative_home" CODEX_HOME=relative-codex-home pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent codex -DryRun >/tmp/p0p4-memory-cleanup-relative-powershell.out 2>/tmp/p0p4-memory-cleanup-relative-powershell.err; then
        relative_failures+=("PowerShell cleanup accepted raw relative CODEX_HOME")
    fi
    [[ -f "$relative_home/.agents/skills/assistant-memory/SKILL.md" ]] || relative_failures+=("$relative_runner cleanup mutated native skills before rejecting raw relative CODEX_HOME")
done
if [[ "${#relative_failures[@]}" -ne 0 ]]; then
    fail "${relative_failures[*]}"
else
    pass
fi

test_start "macOS logical HOME and physical-equivalent CODEX_HOME reject purge before deletion"
if [[ ! -L /var || ! -d /private/var ]]; then
    skip "macOS /var compatibility alias is unavailable"
else
    alias_equivalence_home="$(mktemp -d "${TMPDIR:-/var/tmp}/assistant-framework-memory-equivalence.XXXXXX")"
    physical_equivalence_home="$(cd "$alias_equivalence_home" && pwd -P)"
    p0p4_register_cleanup "$alias_equivalence_home"
    if [[ "$alias_equivalence_home" != /var/* || "$physical_equivalence_home" != /private/var/* ]]; then
        skip "temporary directory is not reached through the macOS /var compatibility alias"
    else
        equivalence_failures=()
        equivalence_runners=(bash)
        command -v pwsh >/dev/null 2>&1 && equivalence_runners+=(powershell)
        for equivalence_runner in "${equivalence_runners[@]}"; do
            mkdir -p "$alias_equivalence_home/codex-home/memory"
            printf '%s\n' 'provider data sentinel' >"$alias_equivalence_home/codex-home/memory/graph.db"
            if [[ "$equivalence_runner" == bash ]]; then
                if HOME="$alias_equivalence_home" CODEX_HOME="$physical_equivalence_home/codex-home" bash "$cleanup_bash" --agent codex --purge-data >/tmp/p0p4-memory-cleanup-equivalence-bash.out 2>/tmp/p0p4-memory-cleanup-equivalence-bash.err; then
                    equivalence_failures+=("Bash cleanup accepted physical-equivalent CODEX_HOME")
                fi
            elif USERPROFILE="$alias_equivalence_home" CODEX_HOME="$physical_equivalence_home/codex-home" pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent codex -PurgeData >/tmp/p0p4-memory-cleanup-equivalence-powershell.out 2>/tmp/p0p4-memory-cleanup-equivalence-powershell.err; then
                equivalence_failures+=("PowerShell cleanup accepted physical-equivalent CODEX_HOME")
            fi
            [[ -f "$alias_equivalence_home/codex-home/memory/graph.db" ]] || equivalence_failures+=("$equivalence_runner cleanup deleted provider data through physical-equivalent CODEX_HOME")
        done
        if [[ "${#equivalence_failures[@]}" -ne 0 ]]; then
            fail "${equivalence_failures[*]}"
        else
            pass
        fi
    fi
fi

test_start "PowerShell cleanup preserves BOM TOML and retires runtime only after configuration succeeds"
ps_bom_home="$(mktemp -d)"
p0p4_register_cleanup "$ps_bom_home"
mkdir -p "$ps_bom_home/.codex/tools/memory-graph"
printf '%s\n' 'retired runtime sentinel' >"$ps_bom_home/.codex/tools/memory-graph/run-memory-graph.ps1"
printf '\357\273\277%s\r\n' '[mcp_servers.memory-graph]' 'command = "retire"' '' '[mcp_servers.keep]' 'command = "keep"' >"$ps_bom_home/.codex/config.toml"
if ! command -v pwsh >/dev/null 2>&1; then
    skip "pwsh is unavailable for PowerShell cleanup behavior verification"
elif ! USERPROFILE="$ps_bom_home" pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent codex >/tmp/p0p4-memory-cleanup-ps-bom.out 2>/tmp/p0p4-memory-cleanup-ps-bom.err; then
    fail "PowerShell cleanup failed to retire a BOM-prefixed Codex configuration"
elif [[ "$(od -An -t x1 -N 3 "$ps_bom_home/.codex/config.toml" | tr -d '[:space:]')" != "efbbbf" ]] \
    || grep -Fq '[mcp_servers.memory-graph]' "$ps_bom_home/.codex/config.toml" \
    || ! grep -Fq '[mcp_servers.keep]' "$ps_bom_home/.codex/config.toml" \
    || [[ -e "$ps_bom_home/.codex/tools/memory-graph" ]]; then
    fail "PowerShell cleanup did not preserve UTF-8 BOM while retiring config before runtime deletion"
else
    pass
fi

test_start "PowerShell cleanup preserves unrelated JSON number lexemes"
ps_lexeme_home="$(mktemp -d)"
p0p4_register_cleanup "$ps_lexeme_home"
mkdir -p "$ps_lexeme_home/.claude/tools/memory-graph"
printf '%s\n' 'retired runtime sentinel' >"$ps_lexeme_home/.claude/tools/memory-graph/run-memory-graph.ps1"
printf '%s\n' '{"mcpServers":{"memory-graph":{"command":"retire"},"keep":{"decimal":1.234567890123456789,"integer":123456789012345678901234567890,"scientific":1.2e+30}}}' >"$ps_lexeme_home/.claude/settings.json"
if ! command -v pwsh >/dev/null 2>&1; then
    skip "pwsh is unavailable for PowerShell cleanup behavior verification"
elif ! USERPROFILE="$ps_lexeme_home" pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent claude >/tmp/p0p4-memory-cleanup-ps-lexeme.out 2>/tmp/p0p4-memory-cleanup-ps-lexeme.err; then
    fail "PowerShell cleanup failed to retire JSON Memory Graph registration"
elif grep -Fq '"memory-graph"' "$ps_lexeme_home/.claude/settings.json" \
    || ! grep -Fq '1.234567890123456789' "$ps_lexeme_home/.claude/settings.json" \
    || ! grep -Fq '123456789012345678901234567890' "$ps_lexeme_home/.claude/settings.json" \
    || ! grep -Fq '1.2e+30' "$ps_lexeme_home/.claude/settings.json" \
    || [[ -e "$ps_lexeme_home/.claude/tools/memory-graph" ]]; then
    fail "PowerShell cleanup rewrote unrelated JSON number lexemes or deleted runtime inconsistently"
else
    pass
fi

test_start "Bash and PowerShell preserve multiline TOML bytes and delete proven-absent stale runtime"
toml_string_failures=()
toml_string_runners=(bash)
command -v pwsh >/dev/null 2>&1 && toml_string_runners+=(powershell)
for toml_string_runner in "${toml_string_runners[@]}"; do
    toml_string_home="$(mktemp -d)"
    p0p4_register_cleanup "$toml_string_home"
    mkdir -p "$toml_string_home/.codex/tools/memory-graph"
    printf '%s\n' 'retired runtime sentinel' >"$toml_string_home/.codex/tools/memory-graph/run-memory-graph.sh"
    cat >"$toml_string_home/.codex/config.toml" <<'TOML'
# [mcp_servers.memory-graph] is only a comment
basic = "[mcp_servers.memory-graph]"
multiline_basic = """
[mcp_servers.memory-graph]
"""
multiline_literal = '''
[mcp_servers.memory-graph]
'''
[mcp_servers."memory-graphical"]
command = "keep quoted unrelated table"
TOML
    cp "$toml_string_home/.codex/config.toml" "$toml_string_home/.codex/config.before"
    if [[ "$toml_string_runner" == bash ]]; then
        if HOME="$toml_string_home" P0P4_CODEX_SEMANTIC_FIXTURE_MODE=absent bash "$cleanup_bash" --agent codex >/tmp/p0p4-memory-cleanup-toml-string-bash.out 2>/tmp/p0p4-memory-cleanup-toml-string-bash.err; then toml_string_status=0; else toml_string_status=$?; fi
    elif USERPROFILE="$toml_string_home" P0P4_CODEX_SEMANTIC_FIXTURE_MODE=absent pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent codex >/tmp/p0p4-memory-cleanup-toml-string-powershell.out 2>/tmp/p0p4-memory-cleanup-toml-string-powershell.err; then
        toml_string_status=0
    else
        toml_string_status=$?
    fi
    if [[ "$toml_string_status" -ne 0 ]] \
        || ! cmp -s "$toml_string_home/.codex/config.before" "$toml_string_home/.codex/config.toml" \
        || [[ -e "$toml_string_home/.codex/tools/memory-graph" ]]; then
        toml_string_failures+=("$toml_string_runner cleanup did not preserve multiline TOML bytes while deleting proven-absent stale runtime")
    fi
done
if [[ "${#toml_string_failures[@]}" -ne 0 ]]; then
    fail "${toml_string_failures[*]}"
else
    pass
fi

test_start "Bash JSON invalid escapes and raw controls fail closed before runtime deletion"
invalid_json_failures=()
for invalid_json_kind in illegal_escape raw_control; do
    invalid_json_home="$(mktemp -d)"
    p0p4_register_cleanup "$invalid_json_home"
    mkdir -p "$invalid_json_home/.claude/tools/memory-graph"
    printf '%s\n' 'retired runtime sentinel' >"$invalid_json_home/.claude/tools/memory-graph/run-memory-graph.sh"
    if [[ "$invalid_json_kind" == illegal_escape ]]; then
        printf '%s\n' '{"mcpServers":{"memory-graph":{"command":"retire"},"keep":"\q"}}' >"$invalid_json_home/.claude/settings.json"
    else
        printf '{"mcpServers":{"memory-graph":{"command":"retire"},"keep":"bad\001control"}}\n' >"$invalid_json_home/.claude/settings.json"
    fi
    cp "$invalid_json_home/.claude/settings.json" "$invalid_json_home/.claude/settings.before"
    if HOME="$invalid_json_home" bash "$cleanup_bash" --agent claude >/tmp/p0p4-memory-cleanup-invalid-json-${invalid_json_kind}.out 2>/tmp/p0p4-memory-cleanup-invalid-json-${invalid_json_kind}.err; then
        invalid_json_failures+=("Bash cleanup accepted $invalid_json_kind JSON")
    elif ! cmp -s "$invalid_json_home/.claude/settings.before" "$invalid_json_home/.claude/settings.json" \
        || [[ ! -f "$invalid_json_home/.claude/tools/memory-graph/run-memory-graph.sh" ]]; then
        invalid_json_failures+=("Bash cleanup mutated $invalid_json_kind JSON or deleted runtime before failing")
    fi
done
if [[ "${#invalid_json_failures[@]}" -ne 0 ]]; then
    fail "${invalid_json_failures[*]}"
else
    pass
fi

test_start "Bash and PowerShell cleanup retain runtime when TOML retirement fails closed"
coupling_failures=()
for cleanup_runner in bash powershell; do
    coupling_home="$(mktemp -d)"
    p0p4_register_cleanup "$coupling_home"
    mkdir -p "$coupling_home/.codex/tools/memory-graph"
    printf '%s\n' 'retired runtime sentinel' >"$coupling_home/.codex/tools/memory-graph/run-memory-graph.sh"
    cat >"$coupling_home/.codex/config.toml" <<'TOML'
[mcp_servers.memory-graph]
command = "one"

[mcp_servers.keep]
command = "keep"
invalid = [1,
TOML
    cp "$coupling_home/.codex/config.toml" "$coupling_home/.codex/config.before"
    if [[ "$cleanup_runner" == bash ]]; then
        if HOME="$coupling_home" P0P4_CODEX_SEMANTIC_FIXTURE_MODE=reject bash "$cleanup_bash" --agent codex >/tmp/p0p4-memory-cleanup-coupling-bash.out 2>/tmp/p0p4-memory-cleanup-coupling-bash.err; then
            cleanup_status=0
        else
            cleanup_status=$?
        fi
    elif command -v pwsh >/dev/null 2>&1; then
        if USERPROFILE="$coupling_home" P0P4_CODEX_SEMANTIC_FIXTURE_MODE=reject pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent codex >/tmp/p0p4-memory-cleanup-coupling-powershell.out 2>/tmp/p0p4-memory-cleanup-coupling-powershell.err; then
            cleanup_status=0
        else
            cleanup_status=$?
        fi
    else
        continue
    fi
    if [[ "$cleanup_status" -eq 0 ]] \
        || ! cmp -s "$coupling_home/.codex/config.before" "$coupling_home/.codex/config.toml" \
        || [[ ! -f "$coupling_home/.codex/tools/memory-graph/run-memory-graph.sh" ]]; then
        coupling_failures+=("$cleanup_runner cleanup did not preserve config and runtime after ambiguous TOML retirement")
    fi
done
if [[ "${#coupling_failures[@]}" -ne 0 ]]; then
    fail "${coupling_failures[*]}"
else
    pass
fi

test_start "PowerShell cleanup help documents every supported agent filter"
if ! command -v pwsh >/dev/null 2>&1; then
    skip "pwsh is unavailable for PowerShell cleanup behavior verification"
else
    ps_help="$(pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Help 2>&1 || true)"
    if ! printf '%s\n' "$ps_help" | grep -Fq -- '-Agent' \
        || ! printf '%s\n' "$ps_help" | grep -Fq -- 'claude, codex, gemini'; then
        fail "PowerShell cleanup help must document -Agent and its supported values"
    else
        pass
    fi
fi

p0p4_make_no_python_path() {
    local target="$1"
    local command_name command_path
    mkdir -p "$target"
    for command_name in awk basename bash cat chmod cp dirname env find grep ln mkdir mktemp pwd readlink rm rsync sed sort stat tr uname; do
        command_path="$(command -v "$command_name" 2>/dev/null || true)"
        [[ -n "$command_path" ]] && ln -s "$command_path" "$target/$command_name"
    done
}

test_start "no-Python escaped retired JSON identity fails closed before runtime deletion"
escaped_no_python_home="$(mktemp -d)"
escaped_no_python_bin="$(mktemp -d)"
p0p4_register_cleanup "$escaped_no_python_home" "$escaped_no_python_bin"
p0p4_make_no_python_path "$escaped_no_python_bin"
mkdir -p "$escaped_no_python_home/.claude/tools/memory-graph"
printf '%s\n' '{"mcpServers":{"memory\\u002dgraph":{"command":"retire"}}}' >"$escaped_no_python_home/.claude/settings.json"
printf '%s\n' 'retired runtime sentinel' >"$escaped_no_python_home/.claude/tools/memory-graph/run-memory-graph.sh"
cp "$escaped_no_python_home/.claude/settings.json" "$escaped_no_python_home/.claude/settings.before"
if PATH="$escaped_no_python_bin" HOME="$escaped_no_python_home" /bin/bash "$cleanup_bash" --agent claude >/tmp/p0p4-memory-cleanup-escaped-no-python.out 2>/tmp/p0p4-memory-cleanup-escaped-no-python.err; then
    fail "cleanup accepted escaped retired JSON identity without Python"
elif ! cmp -s "$escaped_no_python_home/.claude/settings.before" "$escaped_no_python_home/.claude/settings.json" \
    || [[ ! -f "$escaped_no_python_home/.claude/tools/memory-graph/run-memory-graph.sh" ]]; then
    fail "cleanup without Python mutated escaped retired JSON identity or deleted runtime"
else
    pass
fi

test_start "Bash and PowerShell preserve unrelated sibling symlinks while retiring exact targets"
sibling_symlink_failures=()
sibling_symlink_runners=(bash)
command -v pwsh >/dev/null 2>&1 && sibling_symlink_runners+=(powershell)
for sibling_symlink_runner in "${sibling_symlink_runners[@]}"; do
    sibling_symlink_home="$(mktemp -d)"
    p0p4_register_cleanup "$sibling_symlink_home"
    mkdir -p "$sibling_symlink_home/.codex/skills/assistant-memory" \
        "$sibling_symlink_home/.codex/skills/assistant-reflexion" \
        "$sibling_symlink_home/.codex/tools/memory-graph" \
        "$sibling_symlink_home/external-skill" \
        "$sibling_symlink_home/external-tool"
    printf '%s\n' 'external skill sentinel' >"$sibling_symlink_home/external-skill/sentinel"
    printf '%s\n' 'external tool sentinel' >"$sibling_symlink_home/external-tool/sentinel"
    ln -s "$sibling_symlink_home/external-skill" "$sibling_symlink_home/.codex/skills/custom-sibling"
    ln -s "$sibling_symlink_home/external-tool" "$sibling_symlink_home/.codex/tools/custom-sibling"
    if [[ "$sibling_symlink_runner" == bash ]]; then
        if HOME="$sibling_symlink_home" bash "$cleanup_bash" --agent codex >/tmp/p0p4-memory-cleanup-sibling-bash.out 2>/tmp/p0p4-memory-cleanup-sibling-bash.err; then sibling_symlink_status=0; else sibling_symlink_status=$?; fi
    elif USERPROFILE="$sibling_symlink_home" pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent codex >/tmp/p0p4-memory-cleanup-sibling-powershell.out 2>/tmp/p0p4-memory-cleanup-sibling-powershell.err; then
        sibling_symlink_status=0
    else
        sibling_symlink_status=$?
    fi
    if [[ "$sibling_symlink_status" -ne 0 ]] \
        || [[ -e "$sibling_symlink_home/.codex/skills/assistant-memory" || -e "$sibling_symlink_home/.codex/skills/assistant-reflexion" || -e "$sibling_symlink_home/.codex/tools/memory-graph" ]] \
        || [[ ! -L "$sibling_symlink_home/.codex/skills/custom-sibling" || ! -L "$sibling_symlink_home/.codex/tools/custom-sibling" ]] \
        || [[ ! -f "$sibling_symlink_home/external-skill/sentinel" || ! -f "$sibling_symlink_home/external-tool/sentinel" ]]; then
        sibling_symlink_failures+=("$sibling_symlink_runner cleanup rejected siblings or did not retire exact targets safely")
    fi
done
if [[ "${#sibling_symlink_failures[@]}" -ne 0 ]]; then
    fail "${sibling_symlink_failures[*]}"
else
    pass
fi

test_start "Bash cleanup and fresh install do not require Python without legacy structured configuration"
no_python_bin="$(mktemp -d)"
no_python_home="$(mktemp -d)"
p0p4_register_cleanup "$no_python_bin" "$no_python_home"
p0p4_make_no_python_path "$no_python_bin"
if PATH="$no_python_bin" HOME="$no_python_home" /bin/bash "$cleanup_bash" --agent codex >/tmp/p0p4-memory-cleanup-no-python.out 2>/tmp/p0p4-memory-cleanup-no-python.err; then
    if ! PATH="$no_python_bin" HOME="$no_python_home" /bin/bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-memory-install-no-python.out 2>/tmp/p0p4-memory-install-no-python.err; then
        fail "fresh Codex install without legacy structured configuration must not require Python"
    elif [[ ! -f "$no_python_home/.codex/skills/assistant-workflow/SKILL.md" ]]; then
        fail "fresh Codex install without Python reported success without installing the requested skill"
    else
        pass
    fi
else
    fail "cleanup without legacy structured configuration must not require Python"
fi

test_start "no-Python cleanup validates every target before deleting an earlier safe runtime"
no_python_order_home="$(mktemp -d)"
no_python_order_bin="$(mktemp -d)"
no_python_order_paths_before="$(mktemp)"
no_python_order_bytes_before="$(mktemp)"
no_python_order_paths_after="$(mktemp)"
no_python_order_bytes_after="$(mktemp)"
p0p4_register_cleanup "$no_python_order_home" "$no_python_order_bin" "$no_python_order_paths_before" "$no_python_order_bytes_before" "$no_python_order_paths_after" "$no_python_order_bytes_after"
p0p4_make_no_python_path "$no_python_order_bin"
mkdir -p "$no_python_order_home/.claude/tools/memory-graph" "$no_python_order_home/.codex/tools" "$no_python_order_home/external-codex-runtime"
printf '%s\n' 'safe earlier runtime bytes' >"$no_python_order_home/.claude/tools/memory-graph/run-memory-graph.sh"
printf '%s\n' 'unsafe later target bytes' >"$no_python_order_home/external-codex-runtime/sentinel"
ln -s "$no_python_order_home/external-codex-runtime" "$no_python_order_home/.codex/tools/memory-graph"
find "$no_python_order_home" -print | sort >"$no_python_order_paths_before"
find "$no_python_order_home" -type f -exec shasum {} + | sort >"$no_python_order_bytes_before"
if PATH="$no_python_order_bin" HOME="$no_python_order_home" /bin/bash "$cleanup_bash" >/tmp/p0p4-memory-cleanup-no-python-order.out 2>/tmp/p0p4-memory-cleanup-no-python-order.err; then
    fail "no-Python cleanup accepted an unsafe later target after planning a safe earlier runtime"
else
    find "$no_python_order_home" -print | sort >"$no_python_order_paths_after"
    find "$no_python_order_home" -type f -exec shasum {} + | sort >"$no_python_order_bytes_after"
    if ! cmp -s "$no_python_order_paths_before" "$no_python_order_paths_after" \
        || ! cmp -s "$no_python_order_bytes_before" "$no_python_order_bytes_after" \
        || [[ ! -d "$no_python_order_home/.claude/tools/memory-graph" || ! -f "$no_python_order_home/.claude/tools/memory-graph/run-memory-graph.sh" \
            || ! -L "$no_python_order_home/.codex/tools/memory-graph" || ! -f "$no_python_order_home/external-codex-runtime/sentinel" ]]; then
        fail "no-Python cleanup mutated the safe earlier installation/runtime tree before rejecting the unsafe later target"
    else
        pass
    fi
fi

test_start "Bash cleanup without Python fails closed only when legacy JSON requires structured retirement"
no_python_legacy_home="$(mktemp -d)"
no_python_legacy_bin="$(mktemp -d)"
p0p4_register_cleanup "$no_python_legacy_home" "$no_python_legacy_bin"
p0p4_make_no_python_path "$no_python_legacy_bin"
mkdir -p "$no_python_legacy_home/.claude/tools/memory-graph"
printf '%s\n' '{"mcpServers":{"memory-graph":{"command":"retire"}}}' >"$no_python_legacy_home/.claude/settings.json"
printf '%s\n' 'retired runtime sentinel' >"$no_python_legacy_home/.claude/tools/memory-graph/run-memory-graph.sh"
cp "$no_python_legacy_home/.claude/settings.json" "$no_python_legacy_home/.claude/settings.before"
if PATH="$no_python_legacy_bin" HOME="$no_python_legacy_home" /bin/bash "$cleanup_bash" --agent claude >/tmp/p0p4-memory-cleanup-no-python-legacy.out 2>/tmp/p0p4-memory-cleanup-no-python-legacy.err; then
    fail "cleanup accepted legacy JSON without Python structured-edit support"
elif ! grep -Fq 'Python 3 is required' /tmp/p0p4-memory-cleanup-no-python-legacy.err \
    || ! cmp -s "$no_python_legacy_home/.claude/settings.before" "$no_python_legacy_home/.claude/settings.json" \
    || [[ ! -f "$no_python_legacy_home/.claude/tools/memory-graph/run-memory-graph.sh" ]]; then
    fail "cleanup without Python must clearly fail closed and preserve legacy JSON plus runtime"
else
    pass
fi

test_start "no-Python macOS physical HOME equivalence refuses purge before deleting configured Codex data"
if [[ ! -L /var || ! -d /private/var ]]; then
    skip "macOS /var compatibility alias is unavailable"
else
    if ! no_python_alias_home="$(mktemp -d /var/tmp/assistant-framework-memory-no-python-alias.XXXXXX 2>/dev/null)"; then
        echo "skipped: macOS /var compatibility alias is not writable in this environment"
    else
        no_python_alias_physical="$(cd "$no_python_alias_home" && pwd -P)"
        no_python_alias_bin="$(mktemp -d)"
        p0p4_register_cleanup "$no_python_alias_home" "$no_python_alias_bin"
        p0p4_make_no_python_path "$no_python_alias_bin"
        if [[ "$no_python_alias_home" != /var/* || "$no_python_alias_physical" != /private/var/* ]]; then
            echo "skipped: temporary directory is not reached through the macOS /var compatibility alias"
        else
            mkdir -p "$no_python_alias_home/codex-home/tools/memory-graph" "$no_python_alias_home/codex-home/memory"
            printf '%s\n' retired >"$no_python_alias_home/codex-home/tools/memory-graph/run-memory-graph.sh"
            printf '%s\n' provider-data >"$no_python_alias_home/codex-home/memory/graph.db"
            if PATH="$no_python_alias_bin" HOME="$no_python_alias_home" CODEX_HOME="$no_python_alias_physical/codex-home" /bin/bash "$cleanup_bash" --agent codex --purge-data >/tmp/p0p4-memory-no-python-alias.out 2>/tmp/p0p4-memory-no-python-alias.err; then
                fail "no-Python cleanup accepted physical HOME-equivalent CODEX_HOME for purge"
            elif [[ ! -f "$no_python_alias_home/codex-home/tools/memory-graph/run-memory-graph.sh" || ! -f "$no_python_alias_home/codex-home/memory/graph.db" ]]; then
                fail "no-Python cleanup deleted runtime or provider data through physical HOME-equivalent CODEX_HOME"
            else
                pass
            fi
        fi
    fi
fi

test_start "Bash and PowerShell retire every exact duplicate-equivalent quoted TOML identity"
toml_equivalent_failures=()
toml_equivalent_runners=(bash)
command -v pwsh >/dev/null 2>&1 && toml_equivalent_runners+=(powershell)
for toml_equivalent_runner in "${toml_equivalent_runners[@]}"; do
    toml_equivalent_home="$(mktemp -d)"
    p0p4_register_cleanup "$toml_equivalent_home"
    mkdir -p "$toml_equivalent_home/.codex/tools/memory-graph" "$toml_equivalent_home/.codex/memory"
    printf '%s\n' retired >"$toml_equivalent_home/.codex/tools/memory-graph/run-memory-graph.sh"
    printf '%s\n' provider >"$toml_equivalent_home/.codex/memory/graph.db"
    cat >"$toml_equivalent_home/.codex/config.toml" <<'TOML'
[mcp_servers.memory-graph]
command = "retire-one"

["mcp_servers"."memory-graph"]
command = "retire-two"

[mcp_servers.keep]
command = "keep exact bytes"
TOML
    if [[ "$toml_equivalent_runner" == bash ]]; then
        HOME="$toml_equivalent_home" bash "$cleanup_bash" --agent codex >/tmp/p0p4-memory-toml-equivalent-bash.out 2>/tmp/p0p4-memory-toml-equivalent-bash.err && toml_equivalent_status=0 || toml_equivalent_status=$?
    else
        USERPROFILE="$toml_equivalent_home" pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent codex >/tmp/p0p4-memory-toml-equivalent-powershell.out 2>/tmp/p0p4-memory-toml-equivalent-powershell.err && toml_equivalent_status=0 || toml_equivalent_status=$?
    fi
    if [[ "$toml_equivalent_status" -ne 0 ]] || grep -Fq 'memory-graph' "$toml_equivalent_home/.codex/config.toml" \
        || [[ -e "$toml_equivalent_home/.codex/tools/memory-graph" || ! -f "$toml_equivalent_home/.codex/memory/graph.db" ]] \
        || ! grep -Fq 'command = "keep exact bytes"' "$toml_equivalent_home/.codex/config.toml"; then
        toml_equivalent_failures+=("$toml_equivalent_runner did not retire every duplicate-equivalent TOML subtree safely")
    fi
done
if [[ "${#toml_equivalent_failures[@]}" -ne 0 ]]; then fail "${toml_equivalent_failures[*]}"; else pass; fi

test_start "no-Python escaped TOML key fails closed before runtime deletion"
escaped_toml_no_python_home="$(mktemp -d)"
escaped_toml_no_python_bin="$(mktemp -d)"
p0p4_register_cleanup "$escaped_toml_no_python_home" "$escaped_toml_no_python_bin"
p0p4_make_no_python_path "$escaped_toml_no_python_bin"
mkdir -p "$escaped_toml_no_python_home/.codex/tools/memory-graph"
printf '%s\n' '[mcp_servers.memory\\u002dgraph]' 'command = "retire"' >"$escaped_toml_no_python_home/.codex/config.toml"
printf '%s\n' retired >"$escaped_toml_no_python_home/.codex/tools/memory-graph/run-memory-graph.sh"
cp "$escaped_toml_no_python_home/.codex/config.toml" "$escaped_toml_no_python_home/.codex/config.before"
if PATH="$escaped_toml_no_python_bin" HOME="$escaped_toml_no_python_home" /bin/bash "$cleanup_bash" --agent codex >/tmp/p0p4-memory-escaped-toml-no-python.out 2>/tmp/p0p4-memory-escaped-toml-no-python.err; then
    fail "no-Python cleanup accepted escaped retired TOML identity"
elif ! cmp -s "$escaped_toml_no_python_home/.codex/config.before" "$escaped_toml_no_python_home/.codex/config.toml" || [[ ! -f "$escaped_toml_no_python_home/.codex/tools/memory-graph/run-memory-graph.sh" ]]; then
    fail "no-Python cleanup mutated escaped TOML identity or deleted runtime"
else
    pass
fi

test_start "Bash and PowerShell remove only Memory Protocol marker bytes"
marker_byte_failures=()
marker_byte_runners=(bash)
command -v pwsh >/dev/null 2>&1 && marker_byte_runners+=(powershell)
for marker_byte_runner in "${marker_byte_runners[@]}"; do
    marker_byte_home="$(mktemp -d)"
    p0p4_register_cleanup "$marker_byte_home"
    mkdir -p "$marker_byte_home/.codex"
    printf '  user-prefix  \r\n<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->\r\nframework protocol\r\n<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->\r\n\tuser-suffix  \r\n' >"$marker_byte_home/.codex/AGENTS.md"
    printf '  user-prefix  \r\n\tuser-suffix  \r\n' >"$marker_byte_home/expected-agents.md"
    if [[ "$marker_byte_runner" == bash ]]; then
        HOME="$marker_byte_home" bash "$cleanup_bash" --agent codex >/tmp/p0p4-memory-marker-bytes-bash.out 2>/tmp/p0p4-memory-marker-bytes-bash.err && marker_byte_status=0 || marker_byte_status=$?
    else
        USERPROFILE="$marker_byte_home" pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent codex >/tmp/p0p4-memory-marker-bytes-powershell.out 2>/tmp/p0p4-memory-marker-bytes-powershell.err && marker_byte_status=0 || marker_byte_status=$?
    fi
    if [[ "$marker_byte_status" -ne 0 ]] || ! cmp -s "$marker_byte_home/expected-agents.md" "$marker_byte_home/.codex/AGENTS.md"; then
        marker_byte_failures+=("$marker_byte_runner cleanup rewrote bytes outside the owned marker range")
    fi
done
if [[ "${#marker_byte_failures[@]}" -ne 0 ]]; then fail "${marker_byte_failures[*]}"; else pass; fi

test_start "Bash cleanup accepts valid JSON Windows paths while retiring exact Memory Graph identity"
windows_json_home="$(mktemp -d)"
p0p4_register_cleanup "$windows_json_home"
mkdir -p "$windows_json_home/.claude/tools/memory-graph"
printf '%s\n' '{"mcpServers":{"memory-graph":{"command":"retire"},"custom":{"command":"C:\\\\Users\\\\A User\\\\bin\\\\tool.exe"}}}' >"$windows_json_home/.claude/settings.json"
printf '%s\n' retired >"$windows_json_home/.claude/tools/memory-graph/run-memory-graph.sh"
if ! HOME="$windows_json_home" bash "$cleanup_bash" --agent claude >/tmp/p0p4-memory-windows-json.out 2>/tmp/p0p4-memory-windows-json.err; then
    fail "Bash cleanup rejected valid unrelated JSON Windows-path values"
elif grep -Fq 'memory-graph' "$windows_json_home/.claude/settings.json" || ! grep -Fq 'C:\\\\Users\\\\A User\\\\bin\\\\tool.exe' "$windows_json_home/.claude/settings.json" || [[ -e "$windows_json_home/.claude/tools/memory-graph" ]]; then
    fail "Bash cleanup did not retire exact JSON identity while preserving valid Windows-path value"
else
    pass
fi

test_start "Bash custom physical CODEX_HOME preserves unrelated sibling symlinks"
custom_sibling_home="$(mktemp -d)"
custom_sibling_codex="$custom_sibling_home/custom-codex"
p0p4_register_cleanup "$custom_sibling_home"
mkdir -p "$custom_sibling_codex/skills/assistant-memory" "$custom_sibling_codex/skills/assistant-reflexion" "$custom_sibling_codex/tools/memory-graph" "$custom_sibling_home/external-sibling"
printf '%s\n' preserved >"$custom_sibling_home/external-sibling/sentinel"
ln -s "$custom_sibling_home/external-sibling" "$custom_sibling_codex/tools/custom-sibling"
if ! HOME="$custom_sibling_home" CODEX_HOME="$custom_sibling_codex" bash "$cleanup_bash" --agent codex >/tmp/p0p4-memory-custom-sibling.out 2>/tmp/p0p4-memory-custom-sibling.err; then
    fail "Bash cleanup rejected custom CODEX_HOME because of an unrelated sibling symlink"
elif [[ -e "$custom_sibling_codex/skills/assistant-memory" || -e "$custom_sibling_codex/skills/assistant-reflexion" || -e "$custom_sibling_codex/tools/memory-graph" ]] || [[ ! -L "$custom_sibling_codex/tools/custom-sibling" || ! -f "$custom_sibling_home/external-sibling/sentinel" ]]; then
    fail "Bash cleanup did not preserve custom-home sibling symlink while retiring exact targets"
else
    pass
fi

test_start "normal Codex reinstall retires old Memory Graph artifacts without re-registering them"
install_home="$(mktemp -d)"
p0p4_register_cleanup "$install_home"
mkdir -p "$install_home/.codex/skills/assistant-memory" "$install_home/.codex/skills/assistant-reflexion" "$install_home/.codex/tools/memory-graph"
cat >"$install_home/.codex/config.toml" <<'TOML'
model = "keep-model"

[mcp_servers.memory-graph]
command = "/stale/framework-memory"

[mcp_servers.custom]
command = "/keep/custom"
TOML
cat >"$install_home/.codex/AGENTS.md" <<'INSTRUCTIONS'
Keep this user-authored instruction.
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->
Old framework protocol.
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->
INSTRUCTIONS
if ! HOME="$install_home" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-memory-retirement-install.out 2>/tmp/p0p4-memory-retirement-install.err; then
    fail "Codex reinstall failed while retiring Memory Graph"
elif grep -Fq '[mcp_servers.memory-graph]' "$install_home/.codex/config.toml" \
    || grep -Fq 'ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START' "$install_home/.codex/AGENTS.md" \
    || [[ -e "$install_home/.codex/skills/assistant-memory" || -e "$install_home/.codex/skills/assistant-reflexion" || -e "$install_home/.codex/tools/memory-graph" ]] \
    || ! grep -Fq '[mcp_servers.custom]' "$install_home/.codex/config.toml" \
    || ! grep -Fq 'Keep this user-authored instruction.' "$install_home/.codex/AGENTS.md"; then
    fail "Codex reinstall retained or re-registered retired Memory Graph ownership"
else
    pass
fi

test_start "repository runtime and framework CI retire Memory Graph"
framework_validation_workflow="$FRAMEWORK_DIR/.github/workflows/framework-validation.yml"
if [[ -e "$FRAMEWORK_DIR/tools/memory-graph" ]]; then
    fail "retired custom Memory Graph runtime must be absent at tools/memory-graph"
elif [[ ! -f "$framework_validation_workflow" ]]; then
    fail "missing .github/workflows/framework-validation.yml"
elif rg -n -i -e 'Memory Graph' -e 'tools/memory-graph' -e 'MemoryGraph\.Tests' "$framework_validation_workflow" >/tmp/p0p4-framework-validation-memory-retirement.out; then
    fail "framework validation must not build, test, or name retired Memory Graph runtime"
else
    pass
fi

test_start "aggregate inventory retires dedicated memory contract suites"
retired_suite_paths=(
    "$FRAMEWORK_DIR/tests/p0-p4/learning-controller-runtime-contracts.sh"
    "$FRAMEWORK_DIR/tests/p0-p4/memory-doc-contracts.sh"
)
aggregate_contracts="$FRAMEWORK_DIR/tests/test-p0-p4-contracts.sh"
retired_suite_inventory='learning-controller-runtime-contracts\.sh|memory-doc-contracts\.sh'
if [[ -e "${retired_suite_paths[0]}" || -e "${retired_suite_paths[1]}" ]]; then
    fail "retired dedicated learning and memory contract suites must be absent"
elif [[ ! -f "$aggregate_contracts" ]]; then
    fail "missing tests/test-p0-p4-contracts.sh"
elif rg -n -e "$retired_suite_inventory" "$aggregate_contracts" >/tmp/p0p4-aggregate-memory-retirement.out; then
    fail "aggregate P0-P4 inventory must not invoke retired learning or memory suites"
else
    pass
fi

test_start "Codex and framework eval inventory retire Reflexion trace behavior"
codex_eval_runner="$FRAMEWORK_DIR/tools/evals/run-codex-framework-evals.sh"
framework_eval_cases="$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json"
eval_inventory_count="$(find "$FRAMEWORK_DIR/skills"/assistant-*/evals -mindepth 1 -maxdepth 1 -type f -name cases.json | wc -l | tr -d ' ')"
if [[ "$eval_inventory_count" != "14" ]]; then
    fail "skill eval inventory must contain exactly 14 cases files; found $eval_inventory_count"
elif rg -n -i -e 'Reflexion' -e 'Learning Controller' -e 'memory_reflect' "$codex_eval_runner" "$framework_eval_cases" >/tmp/p0p4-eval-memory-retirement.out; then
    fail "Codex and framework eval cases/runners must not require retired Reflexion, Learning Controller, or memory_reflect traces"
else
    pass
fi

test_start "context-budget reporting excludes the retired memory protocol component"
context_budget_reporter="$FRAMEWORK_DIR/tools/context-budget-report.sh"
context_budget_evidence="$FRAMEWORK_DIR/tools/evals/lib/context-budget-evidence.sh"
workflow_kernel_manifest="$FRAMEWORK_DIR/docs/evals/variants/workflow-kernel-v1/manifest.json"
if rg -n -i -e 'ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_(START|END)' -e 'generated_memory_protocol' -e 'generated-memory-protocol' \
    "$context_budget_reporter" "$context_budget_evidence" "$workflow_kernel_manifest" >/tmp/p0p4-context-budget-memory-retirement.out; then
    fail "context-budget reporting and workflow-kernel manifest must not inventory retired memory protocol markers or components"
else
    pass
fi

test_start "installers retire custom memory registration and seed functions while retaining cognitive-complexity coverage"
installer_bash="$FRAMEWORK_DIR/install.sh"
installer_powershell="$FRAMEWORK_DIR/install.ps1"
cognitive_complexity_project="$FRAMEWORK_DIR/tools/cognitive-complexity/CognitiveComplexity.csproj"
if rg -n -e '^register_codex_memory_graph_mcp\(\)' "$installer_bash" \
    || rg -n -e '^function (Assert-GraphSeedInstallSafe|Install-GraphSeed|Update-CodexMemoryGraphConfig|Update-JsonMemoryGraphConfig)\b' "$installer_powershell" \
    >/tmp/p0p4-installer-memory-retirement.out; then
    fail "installers must not retain custom Memory Graph registration, build, or seed functions"
elif [[ ! -f "$cognitive_complexity_project" ]]; then
    fail "retiring Memory Graph must not remove unrelated cognitive-complexity .NET coverage"
else
    pass
fi

test_start "obsolete custom-memory design documents are removed"
obsolete_design_docs=(
    "$FRAMEWORK_DIR/docs/design-memory-v2.md"
    "$FRAMEWORK_DIR/docs/design-reflexion.md"
)
if [[ -e "${obsolete_design_docs[0]}" || -e "${obsolete_design_docs[1]}" ]]; then
    fail "obsolete Memory Graph and Reflexion design documents must be absent"
else
    pass
fi

test_start "public installation guidance does not advertise retired custom-memory capabilities"
public_guidance=(
    "$FRAMEWORK_DIR/README.md"
    "$FRAMEWORK_DIR/AGENTS.md"
    "$FRAMEWORK_DIR/CLAUDE.md"
)
if rg -n -i \
    -e 'Memory Graph' \
    -e 'assistant-memory' \
    -e 'assistant-reflexion' \
    -e 'memory protocol' \
    -e 'graph-seed' \
    -e 'Learning Controller' \
    -e 'memory_context' \
    -e '16 first-class' \
    -e 'four core skills' \
    "${public_guidance[@]}" >/tmp/p0p4-public-memory-retirement.out; then
    fail "README and agent guidance must not advertise, build, install, or register retired custom-memory capabilities"
else
    pass
fi

test_start "evaluation documentation and contract guides enumerate the 14-skill retired topology"
eval_documentation="$FRAMEWORK_DIR/docs/evals/README.md"
contract_guides=(
    "$FRAMEWORK_DIR/docs/skill-contract-design-guide.md"
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-skill-creator/references/skill-contract-design-guide.md"
)
if ! grep -Fq '14 first-class' "$eval_documentation"; then
    fail "docs/evals/README.md must state the 14-skill evaluation inventory"
elif ! grep -Fq '14 first-class' "${contract_guides[0]}" \
    || ! grep -Fq '14 first-class' "${contract_guides[1]}"; then
    fail "canonical and generated skill-contract guides must state the 14-skill inventory"
elif rg -n -i \
    -e 'assistant-memory' \
    -e 'assistant-reflexion' \
    -e 'learning-evidence-activates-reflexion' \
    -e 'generated_memory_protocol' \
    "$eval_documentation" "${contract_guides[@]}" >/tmp/p0p4-eval-docs-memory-retirement.out; then
    fail "evaluation documentation and contract guides retain deleted custom-memory skills, fixtures, or components"
else
    pass
fi

test_start "current planning and presentation documents do not claim retired custom-memory capabilities"
current_documentation=(
    "$FRAMEWORK_DIR/docs/presentation.md"
    "$FRAMEWORK_DIR/docs/plans"
    "$FRAMEWORK_DIR/docs/v0.2.0-research.md"
    "$FRAMEWORK_DIR/docs/v0.3.0-research-improvements.md"
)
if rg -n -i \
    -e 'Memory Graph' \
    -e 'assistant-memory' \
    -e 'assistant-reflexion' \
    -e 'memory_(context|search|reflect|signal|trend)' \
    -e 'memory-protocol' \
    -e 'knowledge graph' \
    -e 'graph MCP' \
    -e 'self-improving' \
    -e 'never forgets' \
    -e 'persistent memory' \
    "${current_documentation[@]}" >/tmp/p0p4-current-docs-memory-retirement.out; then
    fail "current planning, presentation, and research documentation retains retired custom-memory capability claims"
else
    pass
fi

test_start "workflow canonical source and generated mirrors retire standalone Reflexion ceremony"
workflow_reflexion_surfaces=(
    "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md"
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts"
    "$FRAMEWORK_DIR/skills/assistant-workflow/references"
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/SKILL.md"
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/contracts"
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/references"
)
if rg -n -i -w 'reflexion' "${workflow_reflexion_surfaces[@]}" >/tmp/p0p4-workflow-reflexion-retirement.out; then
    fail "workflow canonical source/contracts/references and generated mirrors retain standalone Reflexion capability or ceremony"
else
    pass
fi

test_start "authoritative cleanup leaves invalid complete TOML and runtime untouched for both tools"
invalid_toml_failures=()
invalid_toml_runners=(bash)
command -v pwsh >/dev/null 2>&1 && invalid_toml_runners+=(powershell)
for invalid_toml_runner in "${invalid_toml_runners[@]}"; do
    invalid_toml_home="$(mktemp -d)"
    p0p4_register_cleanup "$invalid_toml_home"
    mkdir -p "$invalid_toml_home/.codex/tools/memory-graph" "$invalid_toml_home/.codex/memory"
    printf '%s\n' runtime >"$invalid_toml_home/.codex/tools/memory-graph/run-memory-graph.sh"
    printf '%s\n' provider >"$invalid_toml_home/.codex/memory/graph.db"
    printf '%s\n' '[mcp_servers.memory-graph]' 'command = "retire"' '' '[mcp_servers.keep]' 'secret = "do-not-echo-retirement-secret"' 'invalid = [1,' >"$invalid_toml_home/.codex/config.toml"
    cp "$invalid_toml_home/.codex/config.toml" "$invalid_toml_home/.codex/config.before"
    if [[ "$invalid_toml_runner" == bash ]]; then
        HOME="$invalid_toml_home" P0P4_CODEX_SEMANTIC_FIXTURE_MODE=reject bash "$cleanup_bash" --agent codex >/tmp/p0p4-authoritative-invalid-toml-bash.out 2>/tmp/p0p4-authoritative-invalid-toml-bash.err && invalid_toml_status=0 || invalid_toml_status=$?
        invalid_toml_output="$(cat /tmp/p0p4-authoritative-invalid-toml-bash.out /tmp/p0p4-authoritative-invalid-toml-bash.err)"
    else
        USERPROFILE="$invalid_toml_home" P0P4_CODEX_SEMANTIC_FIXTURE_MODE=reject pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent codex >/tmp/p0p4-authoritative-invalid-toml-powershell.out 2>/tmp/p0p4-authoritative-invalid-toml-powershell.err && invalid_toml_status=0 || invalid_toml_status=$?
        invalid_toml_output="$(cat /tmp/p0p4-authoritative-invalid-toml-powershell.out /tmp/p0p4-authoritative-invalid-toml-powershell.err)"
    fi
    if [[ "$invalid_toml_status" -eq 0 ]] || ! cmp -s "$invalid_toml_home/.codex/config.before" "$invalid_toml_home/.codex/config.toml" \
        || [[ ! -f "$invalid_toml_home/.codex/tools/memory-graph/run-memory-graph.sh" || ! -f "$invalid_toml_home/.codex/memory/graph.db" ]] \
        || ! printf '%s' "$invalid_toml_output" | grep -Fq "$invalid_toml_home/.codex/config.toml" \
        || printf '%s' "$invalid_toml_output" | grep -Fq 'do-not-echo-retirement-secret'; then
        invalid_toml_failures+=("$invalid_toml_runner did not fail closed with the affected TOML path while preserving config, runtime, and provider data")
    fi
done
if [[ "${#invalid_toml_failures[@]}" -ne 0 ]]; then fail "${invalid_toml_failures[*]}"; else pass; fi

test_start "PowerShell recognizes inline-comment triple quotes as TOML syntax without corrupting unrelated tables"
if ! command -v pwsh >/dev/null 2>&1; then
    skip "pwsh is unavailable for PowerShell authoritative TOML verification"
else
    inline_comment_home="$(mktemp -d)"
    p0p4_register_cleanup "$inline_comment_home"
    mkdir -p "$inline_comment_home/.codex/tools/memory-graph"
    cat >"$inline_comment_home/.codex/config.toml" <<'TOML'
[mcp_servers.memory-graph]
command = "retire"

[mcp_servers.keep]
command = "keep" # a harmless inline comment containing """
value = "unchanged"
TOML
    if ! USERPROFILE="$inline_comment_home" pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent codex >/tmp/p0p4-inline-comment.out 2>/tmp/p0p4-inline-comment.err; then
        fail "PowerShell cleanup rejected valid TOML containing inline-comment triple quotes"
    elif grep -Fq '[mcp_servers.memory-graph]' "$inline_comment_home/.codex/config.toml" \
        || ! grep -Fq 'command = "keep" # a harmless inline comment containing """' "$inline_comment_home/.codex/config.toml" \
        || ! grep -Fq 'value = "unchanged"' "$inline_comment_home/.codex/config.toml" \
        || [[ -e "$inline_comment_home/.codex/tools/memory-graph" ]]; then
        fail "PowerShell cleanup corrupted unrelated valid TOML after inline-comment triple quotes"
    else
        pass
    fi
fi

test_start "cleanup validates TOML after removing exact retired descendant tables without creating validator artifacts"
nested_retired_failures=()
nested_retired_runners=(bash)
command -v pwsh >/dev/null 2>&1 && nested_retired_runners+=(powershell)
for nested_retired_runner in "${nested_retired_runners[@]}"; do
    nested_retired_home="$(mktemp -d)"
    p0p4_register_cleanup "$nested_retired_home"
    mkdir -p "$nested_retired_home/.codex/tools/memory-graph" "$nested_retired_home/.codex/memory"
    printf '%s\n' runtime >"$nested_retired_home/.codex/tools/memory-graph/run-memory-graph.sh"
    printf '%s\n' provider >"$nested_retired_home/.codex/memory/graph.db"
    cat >"$nested_retired_home/.codex/config.toml" <<'TOML'
[mcp_servers.memory-graph]
command = "retire"

[mcp_servers.memory-graph.tools.memory_context]
approval_mode = "deny"

[mcp_servers.keep]
command = "keep exact unrelated bytes"
TOML
    printf '%s\n' '[mcp_servers.keep]' 'command = "keep exact unrelated bytes"' >"$nested_retired_home/expected-keep.toml"
    if [[ "$nested_retired_runner" == bash ]]; then
        HOME="$nested_retired_home" bash "$cleanup_bash" --agent codex >/tmp/p0p4-nested-retired-bash.out 2>/tmp/p0p4-nested-retired-bash.err && nested_retired_status=0 || nested_retired_status=$?
    else
        nested_retired_state="$(mktemp -d)"
        p0p4_register_cleanup "$nested_retired_state"
        mkdir -p "$nested_retired_state/cache" "$nested_retired_state/config" "$nested_retired_state/data"
        USERPROFILE="$nested_retired_home" HOME="$nested_retired_home" \
            XDG_CACHE_HOME="$nested_retired_state/cache" XDG_CONFIG_HOME="$nested_retired_state/config" XDG_DATA_HOME="$nested_retired_state/data" \
            POWERSHELL_TELEMETRY_OPTOUT=1 \
            pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent codex >/tmp/p0p4-nested-retired-powershell.out 2>/tmp/p0p4-nested-retired-powershell.err && nested_retired_status=0 || nested_retired_status=$?
    fi
    tail -n 2 "$nested_retired_home/.codex/config.toml" >"$nested_retired_home/actual-keep.toml"
    if [[ "$nested_retired_status" -ne 0 ]] \
        || grep -Fq '[mcp_servers.memory-graph]' "$nested_retired_home/.codex/config.toml" \
        || ! cmp -s "$nested_retired_home/expected-keep.toml" "$nested_retired_home/actual-keep.toml" \
        || [[ -e "$nested_retired_home/.codex/tools/memory-graph" || ! -f "$nested_retired_home/.codex/memory/graph.db" ]] \
        || [[ -e "$nested_retired_home/.npm" || -e "$nested_retired_home/.cache" || -e "$nested_retired_home/.config" || -e "$nested_retired_home/.local" || -e "$nested_retired_home/.codex/.npm" || -e "$nested_retired_home/.codex/logs" ]]; then
        nested_retired_failures+=("$nested_retired_runner")
    fi
done
if [[ "${#nested_retired_failures[@]}" -ne 0 ]]; then
    fail "nested retired TOML subtree was not retired before validation or created validator artifacts: ${nested_retired_failures[*]}"
else
    pass
fi

test_start "Bash accepts valid JSON regex and Windows literals while preserving their exact bytes"
json_literal_home="$(mktemp -d)"
p0p4_register_cleanup "$json_literal_home"
mkdir -p "$json_literal_home/.claude/tools/memory-graph"
printf '%s\n' '{"mcpServers":{"memory-graph":{"command":"retire"},"keep":{"regex":"\\\\d+","windows":"C:\\\\Users\\\\A User\\\\bin\\\\tool.exe"}}}' >"$json_literal_home/.claude/settings.json"
printf '%s\n' runtime >"$json_literal_home/.claude/tools/memory-graph/run-memory-graph.sh"
if ! HOME="$json_literal_home" bash "$cleanup_bash" --agent claude >/tmp/p0p4-json-literals.out 2>/tmp/p0p4-json-literals.err; then
    fail "Bash cleanup rejected valid JSON regex or Windows literals"
elif grep -Fq 'memory-graph' "$json_literal_home/.claude/settings.json" \
    || ! grep -Fq '"regex":"\\\\d+"' "$json_literal_home/.claude/settings.json" \
    || ! grep -Fq '"windows":"C:\\\\Users\\\\A User\\\\bin\\\\tool.exe"' "$json_literal_home/.claude/settings.json" \
    || [[ -e "$json_literal_home/.claude/tools/memory-graph" ]]; then
    fail "Bash cleanup did not preserve valid unrelated JSON literal bytes while retiring exact identity"
else
    pass
fi

test_start "PowerShell rejects non-RFC JSON byte-for-byte before deleting runtime"
if ! command -v pwsh >/dev/null 2>&1; then
    skip "pwsh is unavailable for PowerShell strict JSON verification"
else
    strict_json_failures=()
    for strict_json_kind in nan infinity comment trailing-comma; do
        strict_json_home="$(mktemp -d)"
        p0p4_register_cleanup "$strict_json_home"
        mkdir -p "$strict_json_home/.claude/tools/memory-graph" "$strict_json_home/.claude/memory"
        printf '%s\n' runtime >"$strict_json_home/.claude/tools/memory-graph/run-memory-graph.sh"
        printf '%s\n' provider >"$strict_json_home/.claude/memory/graph.db"
        case "$strict_json_kind" in
            nan) printf '%s\n' '{"mcpServers":{"memory-graph":{"command":"retire"},"secret":"do-not-echo-json-secret","keep":NaN}}' ;;
            infinity) printf '%s\n' '{"mcpServers":{"memory-graph":{"command":"retire"},"secret":"do-not-echo-json-secret","keep":Infinity}}' ;;
            comment) printf '%s\n' '{"mcpServers":{"memory-graph":{"command":"retire"},"secret":"do-not-echo-json-secret" /* comment */}}' ;;
            trailing-comma) printf '%s\n' '{"mcpServers":{"memory-graph":{"command":"retire"},"secret":"do-not-echo-json-secret",}}' ;;
        esac >"$strict_json_home/.claude/settings.json"
        cp "$strict_json_home/.claude/settings.json" "$strict_json_home/.claude/settings.before"
        USERPROFILE="$strict_json_home" pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent claude >/tmp/p0p4-strict-json-${strict_json_kind}.out 2>/tmp/p0p4-strict-json-${strict_json_kind}.err && strict_json_status=0 || strict_json_status=$?
        strict_json_output="$(cat /tmp/p0p4-strict-json-${strict_json_kind}.out /tmp/p0p4-strict-json-${strict_json_kind}.err)"
        if [[ "$strict_json_status" -eq 0 ]] || ! cmp -s "$strict_json_home/.claude/settings.before" "$strict_json_home/.claude/settings.json" \
            || [[ ! -f "$strict_json_home/.claude/tools/memory-graph/run-memory-graph.sh" || ! -f "$strict_json_home/.claude/memory/graph.db" ]] \
            || ! printf '%s' "$strict_json_output" | grep -Fq "$strict_json_home/.claude/settings.json" \
            || printf '%s' "$strict_json_output" | grep -Fq 'do-not-echo-json-secret'; then
            strict_json_failures+=("$strict_json_kind")
        fi
    done
    if [[ "${#strict_json_failures[@]}" -ne 0 ]]; then fail "PowerShell accepted or mutated non-RFC JSON: ${strict_json_failures[*]}"; else pass; fi
fi

test_start "cleanup removes stale exact runtime when every valid config proves registration absent"
proven_absent_failures=()
proven_absent_runners=(bash)
command -v pwsh >/dev/null 2>&1 && proven_absent_runners+=(powershell)
for proven_absent_runner in "${proven_absent_runners[@]}"; do
    proven_absent_home="$(mktemp -d)"
    p0p4_register_cleanup "$proven_absent_home"
    mkdir -p "$proven_absent_home/.codex/tools/memory-graph" "$proven_absent_home/.codex/memory"
    printf '%s\n' runtime >"$proven_absent_home/.codex/tools/memory-graph/run-memory-graph.sh"
    printf '%s\n' provider >"$proven_absent_home/.codex/memory/graph.db"
    printf '%s\n' '[mcp_servers.keep]' 'command = "keep"' >"$proven_absent_home/.codex/config.toml"
    if [[ "$proven_absent_runner" == bash ]]; then HOME="$proven_absent_home" bash "$cleanup_bash" --agent codex >/tmp/p0p4-proven-absent-bash.out 2>/tmp/p0p4-proven-absent-bash.err && proven_absent_status=0 || proven_absent_status=$?; else USERPROFILE="$proven_absent_home" pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent codex >/tmp/p0p4-proven-absent-powershell.out 2>/tmp/p0p4-proven-absent-powershell.err && proven_absent_status=0 || proven_absent_status=$?; fi
    if [[ "$proven_absent_status" -ne 0 ]] || [[ -e "$proven_absent_home/.codex/tools/memory-graph" || ! -f "$proven_absent_home/.codex/memory/graph.db" ]] || ! grep -Fq '[mcp_servers.keep]' "$proven_absent_home/.codex/config.toml"; then
        proven_absent_failures+=("$proven_absent_runner")
    fi
done
if [[ "${#proven_absent_failures[@]}" -ne 0 ]]; then fail "valid proven-absent state did not retire only stale runtime: ${proven_absent_failures[*]}"; else pass; fi

test_start "multi-config ambiguity prevents every planned write and deletion"
multi_config_failures=()
multi_config_runners=(bash)
command -v pwsh >/dev/null 2>&1 && multi_config_runners+=(powershell)
for multi_config_runner in "${multi_config_runners[@]}"; do
    multi_config_home="$(mktemp -d)"
    p0p4_register_cleanup "$multi_config_home"
    mkdir -p "$multi_config_home/.claude/tools/memory-graph" "$multi_config_home/.claude/memory"
    printf '%s\n' runtime >"$multi_config_home/.claude/tools/memory-graph/run-memory-graph.sh"
    printf '%s\n' provider >"$multi_config_home/.claude/memory/graph.db"
    printf '%s\n' '{"mcpServers":{"memory-graph":{"command":"retire"},"keep":{"command":"keep"}}}' >"$multi_config_home/.claude/settings.json"
    printf '%s\n' '{"mcpServers":{"memory-graph":{"command":"retire"},"secret":"do-not-echo-multi-secret",}}' >"$multi_config_home/.claude.json"
    cp "$multi_config_home/.claude/settings.json" "$multi_config_home/.claude/settings.before"
    cp "$multi_config_home/.claude.json" "$multi_config_home/.claude.before"
    if [[ "$multi_config_runner" == bash ]]; then HOME="$multi_config_home" bash "$cleanup_bash" --agent claude >/tmp/p0p4-multi-config-bash.out 2>/tmp/p0p4-multi-config-bash.err && multi_config_status=0 || multi_config_status=$?; multi_config_output="$(cat /tmp/p0p4-multi-config-bash.out /tmp/p0p4-multi-config-bash.err)"; else USERPROFILE="$multi_config_home" pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent claude >/tmp/p0p4-multi-config-powershell.out 2>/tmp/p0p4-multi-config-powershell.err && multi_config_status=0 || multi_config_status=$?; multi_config_output="$(cat /tmp/p0p4-multi-config-powershell.out /tmp/p0p4-multi-config-powershell.err)"; fi
    if [[ "$multi_config_status" -eq 0 ]] || ! cmp -s "$multi_config_home/.claude/settings.before" "$multi_config_home/.claude/settings.json" || ! cmp -s "$multi_config_home/.claude.before" "$multi_config_home/.claude.json" \
        || [[ ! -f "$multi_config_home/.claude/tools/memory-graph/run-memory-graph.sh" || ! -f "$multi_config_home/.claude/memory/graph.db" ]] \
        || ! printf '%s' "$multi_config_output" | grep -Fq "$multi_config_home/.claude.json" \
        || printf '%s' "$multi_config_output" | grep -Fq 'do-not-echo-multi-secret'; then
        multi_config_failures+=("$multi_config_runner")
    fi
done
if [[ "${#multi_config_failures[@]}" -ne 0 ]]; then fail "ambiguous multi-config state permitted a mutation or omitted its affected path: ${multi_config_failures[*]}"; else pass; fi

test_start "retired target deletion ignores suffix-matching custom-memory-graph siblings"
suffix_sibling_failures=()
suffix_sibling_runners=(bash)
command -v pwsh >/dev/null 2>&1 && suffix_sibling_runners+=(powershell)
for suffix_sibling_runner in "${suffix_sibling_runners[@]}"; do
    suffix_sibling_home="$(mktemp -d)"
    p0p4_register_cleanup "$suffix_sibling_home"
    mkdir -p "$suffix_sibling_home/.codex/tools/memory-graph" "$suffix_sibling_home/external-custom-memory-graph"
    printf '%s\n' preserved >"$suffix_sibling_home/external-custom-memory-graph/sentinel"
    ln -s "$suffix_sibling_home/external-custom-memory-graph" "$suffix_sibling_home/.codex/tools/custom-memory-graph"
    if [[ "$suffix_sibling_runner" == bash ]]; then HOME="$suffix_sibling_home" bash "$cleanup_bash" --agent codex >/tmp/p0p4-suffix-sibling-bash.out 2>/tmp/p0p4-suffix-sibling-bash.err && suffix_sibling_status=0 || suffix_sibling_status=$?; else USERPROFILE="$suffix_sibling_home" pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent codex >/tmp/p0p4-suffix-sibling-powershell.out 2>/tmp/p0p4-suffix-sibling-powershell.err && suffix_sibling_status=0 || suffix_sibling_status=$?; fi
    if [[ "$suffix_sibling_status" -ne 0 ]] || [[ -e "$suffix_sibling_home/.codex/tools/memory-graph" || ! -L "$suffix_sibling_home/.codex/tools/custom-memory-graph" || ! -f "$suffix_sibling_home/external-custom-memory-graph/sentinel" ]]; then suffix_sibling_failures+=("$suffix_sibling_runner"); fi
done
if [[ "${#suffix_sibling_failures[@]}" -ne 0 ]]; then fail "suffix-matching sibling symlink blocked or escaped exact-target retirement: ${suffix_sibling_failures[*]}"; else pass; fi

test_start "normal installers stop before installation and omit success when retirement is incomplete"
installer_incomplete_home="$(mktemp -d)"
p0p4_register_cleanup "$installer_incomplete_home"
mkdir -p "$installer_incomplete_home/.codex/tools/memory-graph"
printf '%s\n' runtime >"$installer_incomplete_home/.codex/tools/memory-graph/run-memory-graph.sh"
printf '%s\n' '[mcp_servers.memory-graph]' 'command = "retire"' '' '[mcp_servers.keep]' 'invalid = [1,' >"$installer_incomplete_home/.codex/config.toml"
if HOME="$installer_incomplete_home" P0P4_CODEX_SEMANTIC_FIXTURE_MODE=reject bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-installer-incomplete-bash.out 2>/tmp/p0p4-installer-incomplete-bash.err; then
    fail "Bash installer reported success despite incomplete retirement"
elif [[ -e "$installer_incomplete_home/.codex/skills/assistant-workflow" || ! -f "$installer_incomplete_home/.codex/tools/memory-graph/run-memory-graph.sh" ]] \
    || grep -Fq 'Installation complete' /tmp/p0p4-installer-incomplete-bash.out; then
    fail "Bash installer installed or printed success after incomplete retirement"
else
    pass
fi

test_start "Codex semantic authority disagreement fails closed before runtime retirement"
authority_failures=()
authority_runners=(bash)
command -v pwsh >/dev/null 2>&1 && authority_runners+=(powershell)
for authority_runner in "${authority_runners[@]}"; do
    authority_home="$(mktemp -d)"
    authority_bin="$(mktemp -d)"
    p0p4_register_cleanup "$authority_home" "$authority_bin"
    mkdir -p "$authority_home/.codex/tools/memory-graph" "$authority_home/.codex/memory"
    printf '%s\n' runtime >"$authority_home/.codex/tools/memory-graph/run-memory-graph.sh"
    printf '%s\n' provider >"$authority_home/.codex/memory/graph.db"
    printf '%s\n' 'mcp_servers.memory-graph = { command = "retire" }' '[mcp_servers.keep]' 'command = "keep"' >"$authority_home/.codex/config.toml"
    cp "$authority_home/.codex/config.toml" "$authority_home/.codex/config.before"
    printf '%s\n' '#!/bin/sh' 'if [ "$1" = "mcp" ] && [ "$2" = "list" ] && [ "$3" = "--json" ]; then printf "[{\\"name\\":\\"memory-graph\\"}]\\n"; exit 0; fi' 'exit 0' >"$authority_bin/codex"
    chmod +x "$authority_bin/codex"
    if [[ "$authority_runner" == bash ]]; then
        HOME="$authority_home" PATH="$authority_bin:$PATH" bash "$cleanup_bash" --agent codex >/tmp/p0p4-authority-bash.out 2>/tmp/p0p4-authority-bash.err && authority_status=0 || authority_status=$?
        authority_output="$(cat /tmp/p0p4-authority-bash.out /tmp/p0p4-authority-bash.err)"
    else
        USERPROFILE="$authority_home" HOME="$authority_home" PATH="$authority_bin:$PATH" pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent codex >/tmp/p0p4-authority-powershell.out 2>/tmp/p0p4-authority-powershell.err && authority_status=0 || authority_status=$?
        authority_output="$(cat /tmp/p0p4-authority-powershell.out /tmp/p0p4-authority-powershell.err)"
    fi
    if [[ "$authority_status" -eq 0 ]] || ! cmp -s "$authority_home/.codex/config.before" "$authority_home/.codex/config.toml" \
        || [[ ! -f "$authority_home/.codex/tools/memory-graph/run-memory-graph.sh" || ! -f "$authority_home/.codex/memory/graph.db" ]] \
        || ! printf '%s' "$authority_output" | grep -Fq "$authority_home/.codex/config.toml"; then
        authority_failures+=("$authority_runner")
    fi
done
if [[ "${#authority_failures[@]}" -ne 0 ]]; then fail "semantic authority present but locator disagreement did not fail closed: ${authority_failures[*]}"; else pass; fi

test_start "Codex semantic absence cannot authorize removal from a local owned TOML span"
semantic_absent_failures=()
semantic_absent_runners=(bash)
command -v pwsh >/dev/null 2>&1 && semantic_absent_runners+=(powershell)
for semantic_absent_runner in "${semantic_absent_runners[@]}"; do
    semantic_absent_home="$(mktemp -d)"
    semantic_absent_bin="$(mktemp -d)"
    p0p4_register_cleanup "$semantic_absent_home" "$semantic_absent_bin"
    mkdir -p "$semantic_absent_home/.codex/tools/memory-graph" "$semantic_absent_home/.codex/memory"
    printf '%s\n' runtime >"$semantic_absent_home/.codex/tools/memory-graph/run-memory-graph.sh"
    printf '%s\n' provider >"$semantic_absent_home/.codex/memory/graph.db"
    printf '%s\n' '[mcp_servers.memory-graph]' 'command = "retire"' >"$semantic_absent_home/.codex/config.toml"
    cp "$semantic_absent_home/.codex/config.toml" "$semantic_absent_home/.codex/config.before"
    printf '%s\n' '#!/bin/sh' "printf '%s|%s|%s\\n' \"\$1\" \"\$2\" \"\$3\" >>'$semantic_absent_home/codex.args'" 'if [ "$1" = "mcp" ] && [ "$2" = "list" ] && [ "$3" = "--json" ]; then printf "[]\n"; exit 0; fi' 'exit 64' >"$semantic_absent_bin/codex"
    chmod +x "$semantic_absent_bin/codex"
    if [[ "$semantic_absent_runner" == bash ]]; then
        HOME="$semantic_absent_home" PATH="$semantic_absent_bin:$PATH" bash "$cleanup_bash" --agent codex >/tmp/p0p4-semantic-absent-bash.out 2>/tmp/p0p4-semantic-absent-bash.err && semantic_absent_status=0 || semantic_absent_status=$?
        semantic_absent_output="$(cat /tmp/p0p4-semantic-absent-bash.out /tmp/p0p4-semantic-absent-bash.err)"
    else
        USERPROFILE="$semantic_absent_home" HOME="$semantic_absent_home" PATH="$semantic_absent_bin:$PATH" pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent codex >/tmp/p0p4-semantic-absent-powershell.out 2>/tmp/p0p4-semantic-absent-powershell.err && semantic_absent_status=0 || semantic_absent_status=$?
        semantic_absent_output="$(cat /tmp/p0p4-semantic-absent-powershell.out /tmp/p0p4-semantic-absent-powershell.err)"
    fi
    if [[ "$semantic_absent_status" -eq 0 ]] || ! cmp -s "$semantic_absent_home/.codex/config.before" "$semantic_absent_home/.codex/config.toml" \
        || [[ ! -f "$semantic_absent_home/.codex/tools/memory-graph/run-memory-graph.sh" || ! -f "$semantic_absent_home/.codex/memory/graph.db" ]] \
        || ! grep -Fxq 'mcp|list|--json' "$semantic_absent_home/codex.args" \
        || ! printf '%s' "$semantic_absent_output" | grep -Fq "$semantic_absent_home/.codex/config.toml"; then
        semantic_absent_failures+=("$semantic_absent_runner")
    fi
done
if [[ "${#semantic_absent_failures[@]}" -ne 0 ]]; then fail "semantic absence/local owned span disagreement did not fail closed: ${semantic_absent_failures[*]}"; else pass; fi

test_start "valid quoted-hash TOML and invalid retired-only subtrees retire without touching unrelated bytes"
toml_candidate_failures=()
toml_candidate_runners=(bash)
command -v pwsh >/dev/null 2>&1 && toml_candidate_runners+=(powershell)
for toml_candidate_runner in "${toml_candidate_runners[@]}"; do
    for toml_candidate_kind in quoted-hash retired-invalid; do
        toml_candidate_home="$(mktemp -d)"
        p0p4_register_cleanup "$toml_candidate_home"
        mkdir -p "$toml_candidate_home/.codex/tools/memory-graph" "$toml_candidate_home/.codex/memory"
        printf '%s\n' runtime >"$toml_candidate_home/.codex/tools/memory-graph/run-memory-graph.sh"
        printf '%s\n' provider >"$toml_candidate_home/.codex/memory/graph.db"
        if [[ "$toml_candidate_kind" == quoted-hash ]]; then
            printf '%s\n' '[mcp_servers.memory-graph]' 'command = "retire"' '' '[mcp_servers.keep]' 'command = "keep # literal"' 'value = "unchanged" # comment' >"$toml_candidate_home/.codex/config.toml"
        else
            printf '%s\n' '[mcp_servers.memory-graph]' 'command = "retire"' 'duplicate = "one"' 'duplicate = "two"' 'invalid = [1,' '' '[mcp_servers.keep]' 'command = "keep exact bytes"' >"$toml_candidate_home/.codex/config.toml"
        fi
        cp "$toml_candidate_home/.codex/config.toml" "$toml_candidate_home/.codex/config.before"
        if [[ "$toml_candidate_runner" == bash ]]; then
            HOME="$toml_candidate_home" bash "$cleanup_bash" --agent codex >/tmp/p0p4-toml-candidate-bash.out 2>/tmp/p0p4-toml-candidate-bash.err && toml_candidate_status=0 || toml_candidate_status=$?
        else
            USERPROFILE="$toml_candidate_home" HOME="$toml_candidate_home" pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent codex >/tmp/p0p4-toml-candidate-powershell.out 2>/tmp/p0p4-toml-candidate-powershell.err && toml_candidate_status=0 || toml_candidate_status=$?
        fi
        if [[ "$toml_candidate_status" -ne 0 ]] || grep -Fq 'memory-graph' "$toml_candidate_home/.codex/config.toml" \
            || [[ -e "$toml_candidate_home/.codex/tools/memory-graph" || ! -f "$toml_candidate_home/.codex/memory/graph.db" ]] \
            || { [[ "$toml_candidate_kind" == quoted-hash ]] && { ! grep -Fq 'command = "keep # literal"' "$toml_candidate_home/.codex/config.toml" || ! grep -Fq 'value = "unchanged" # comment' "$toml_candidate_home/.codex/config.toml"; }; } \
            || { [[ "$toml_candidate_kind" == retired-invalid ]] && ! grep -Fq 'command = "keep exact bytes"' "$toml_candidate_home/.codex/config.toml"; }; then
            toml_candidate_failures+=("$toml_candidate_runner/$toml_candidate_kind")
        fi
    done
done
if [[ "${#toml_candidate_failures[@]}" -ne 0 ]]; then fail "valid quoted-hash or quarantined retired-only TOML did not retire safely: ${toml_candidate_failures[*]}"; else pass; fi

test_start "existing Codex TOML without the Codex validator remains untouched while fresh homes stay dependency-free"
validator_home="$(mktemp -d)"
validator_bin="$(mktemp -d)"
p0p4_register_cleanup "$validator_home" "$validator_bin"
mkdir -p "$validator_home/.codex/tools/memory-graph" "$validator_home/.codex/memory"
printf '%s\n' runtime >"$validator_home/.codex/tools/memory-graph/run-memory-graph.sh"
printf '%s\n' provider >"$validator_home/.codex/memory/graph.db"
printf '%s\n' '[mcp_servers.memory-graph]' 'command = "retire"' >"$validator_home/.codex/config.toml"
cp "$validator_home/.codex/config.toml" "$validator_home/.codex/config.before"
if HOME="$validator_home" PATH="$validator_bin:/usr/bin:/bin" /bin/bash "$cleanup_bash" --agent codex >/tmp/p0p4-validator-unavailable.out 2>/tmp/p0p4-validator-unavailable.err; then
    fail "existing Codex TOML reported retirement success without the Codex validator"
elif ! cmp -s "$validator_home/.codex/config.before" "$validator_home/.codex/config.toml" \
    || [[ ! -f "$validator_home/.codex/tools/memory-graph/run-memory-graph.sh" || ! -f "$validator_home/.codex/memory/graph.db" ]] \
    || ! cat /tmp/p0p4-validator-unavailable.out /tmp/p0p4-validator-unavailable.err | grep -Fq "$validator_home/.codex/config.toml"; then
    fail "validator-unavailable cleanup mutated existing Codex state or omitted the affected path"
else
    fresh_validator_home="$(mktemp -d)"
    p0p4_register_cleanup "$fresh_validator_home"
    if ! HOME="$fresh_validator_home" PATH="$validator_bin:/usr/bin:/bin" /bin/bash "$cleanup_bash" --agent codex >/tmp/p0p4-validator-fresh.out 2>/tmp/p0p4-validator-fresh.err; then
        fail "fresh/no-config Codex cleanup gained a validator dependency"
    else
        pass
    fi
fi

test_start "malformed duplicate authority JSON cannot authorize dotted-key Codex retirement"
authority_json_home="$(mktemp -d)"
authority_json_bin="$(mktemp -d)"
p0p4_register_cleanup "$authority_json_home" "$authority_json_bin"
mkdir -p "$authority_json_home/.codex/tools/memory-graph" "$authority_json_home/.codex/memory"
printf '%s\n' runtime >"$authority_json_home/.codex/tools/memory-graph/run-memory-graph.sh"
printf '%s\n' provider >"$authority_json_home/.codex/memory/graph.db"
printf '%s\n' 'mcp_servers.memory-graph = { command = "retire" }' '[mcp_servers.keep]' 'command = "keep"' >"$authority_json_home/.codex/config.toml"
cp "$authority_json_home/.codex/config.toml" "$authority_json_home/.codex/config.before"
printf '%s\n' '#!/bin/sh' \
    "printf '%s|%s|%s\\n' \"\$1\" \"\$2\" \"\$3\" >>'$authority_json_home/codex.args'" \
    'if [ "$1" = "mcp" ] && [ "$2" = "list" ] && [ "$3" = "--json" ]; then printf "[{\\\"name\\\":\\\"memory-graph\\\",\\\"name\\\":\\\"MEMORY-GRAPH\\\"}]\\n"; exit 0; fi' \
    'exit 64' >"$authority_json_bin/codex"
chmod +x "$authority_json_bin/codex"
HOME="$authority_json_home" PATH="$authority_json_bin:$PATH" bash "$cleanup_bash" --agent codex >/tmp/p0p4-authority-json.out 2>/tmp/p0p4-authority-json.err && authority_json_status=0 || authority_json_status=$?
authority_json_output="$(cat /tmp/p0p4-authority-json.out /tmp/p0p4-authority-json.err)"
if [[ "$authority_json_status" -eq 0 ]] \
    || ! cmp -s "$authority_json_home/.codex/config.before" "$authority_json_home/.codex/config.toml" \
    || [[ ! -f "$authority_json_home/.codex/tools/memory-graph/run-memory-graph.sh" || ! -f "$authority_json_home/.codex/memory/graph.db" ]] \
    || ! grep -Fxq 'mcp|list|--json' "$authority_json_home/codex.args" \
    || ! printf '%s' "$authority_json_output" | grep -Fq "$authority_json_home/.codex/config.toml" \
    || printf '%s' "$authority_json_output" | grep -Fq 'command = "retire"'; then
    fail "malformed duplicate/case-colliding authority JSON permitted or obscured dotted-key Codex retirement"
else
    pass
fi

test_start "separate case-colliding Codex authority objects fail closed before candidate retirement"
authority_collision_failures=()
authority_collision_runners=(bash)
command -v pwsh >/dev/null 2>&1 && authority_collision_runners+=(powershell)
for authority_collision_runner in "${authority_collision_runners[@]}"; do
    authority_collision_home="$(mktemp -d)"
    authority_collision_bin="$(mktemp -d)"
    p0p4_register_cleanup "$authority_collision_home" "$authority_collision_bin"
    mkdir -p "$authority_collision_home/.codex/tools/memory-graph" "$authority_collision_home/.codex/memory"
    printf '%s\n' runtime >"$authority_collision_home/.codex/tools/memory-graph/run-memory-graph.sh"
    printf '%s\n' provider >"$authority_collision_home/.codex/memory/graph.db"
    printf '%s\n' '[mcp_servers.memory-graph]' 'command = "retire-lowercase"' '' '[mcp_servers.MEMORY-GRAPH]' 'command = "retain-uppercase"' '' '[mcp_servers.keep]' 'command = "keep"' >"$authority_collision_home/.codex/config.toml"
    cp "$authority_collision_home/.codex/config.toml" "$authority_collision_home/.codex/config.before"
    printf '%s\n' '#!/bin/sh' \
        "printf '%s|%s|%s\\n' \"\$1\" \"\$2\" \"\$3\" >>'$authority_collision_home/codex.args'" \
        'if [ "$1" = "mcp" ] && [ "$2" = "list" ] && [ "$3" = "--json" ]; then' \
        '  first=true; printf "["' \
        '  if grep -Fxq "[mcp_servers.memory-graph]" "$HOME/config.toml"; then printf "{\\\"name\\\":\\\"memory-graph\\\"}"; first=false; fi' \
        '  if grep -Fxq "[mcp_servers.MEMORY-GRAPH]" "$HOME/config.toml"; then $first || printf ","; printf "{\\\"name\\\":\\\"MEMORY-GRAPH\\\"}"; fi' \
        '  printf "]\\n"; exit 0' \
        'fi' \
        'exit 64' >"$authority_collision_bin/codex"
    chmod +x "$authority_collision_bin/codex"
    if [[ "$authority_collision_runner" == bash ]]; then
        HOME="$authority_collision_home" PATH="$authority_collision_bin:$PATH" bash "$cleanup_bash" --agent codex >/tmp/p0p4-authority-collision-bash.out 2>/tmp/p0p4-authority-collision-bash.err && authority_collision_status=0 || authority_collision_status=$?
        authority_collision_output="$(cat /tmp/p0p4-authority-collision-bash.out /tmp/p0p4-authority-collision-bash.err)"
    else
        USERPROFILE="$authority_collision_home" HOME="$authority_collision_home" PATH="$authority_collision_bin:$PATH" pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent codex >/tmp/p0p4-authority-collision-powershell.out 2>/tmp/p0p4-authority-collision-powershell.err && authority_collision_status=0 || authority_collision_status=$?
        authority_collision_output="$(cat /tmp/p0p4-authority-collision-powershell.out /tmp/p0p4-authority-collision-powershell.err)"
    fi
    if [[ "$authority_collision_status" -eq 0 ]] \
        || ! cmp -s "$authority_collision_home/.codex/config.before" "$authority_collision_home/.codex/config.toml" \
        || [[ ! -f "$authority_collision_home/.codex/tools/memory-graph/run-memory-graph.sh" || ! -f "$authority_collision_home/.codex/memory/graph.db" ]] \
        || ! grep -Fxq '[mcp_servers.memory-graph]' "$authority_collision_home/.codex/config.toml" \
        || ! grep -Fxq '[mcp_servers.MEMORY-GRAPH]' "$authority_collision_home/.codex/config.toml" \
        || ! grep -Fxq 'mcp|list|--json' "$authority_collision_home/codex.args" \
        || ! printf '%s' "$authority_collision_output" | grep -Fq "$authority_collision_home/.codex/config.toml" \
        || printf '%s' "$authority_collision_output" | grep -Fq 'command = "retire"'; then
        authority_collision_failures+=("$authority_collision_runner")
    fi
done
if [[ "${#authority_collision_failures[@]}" -ne 0 ]]; then
    fail "separate case-colliding authority objects permitted or obscured candidate retirement: ${authority_collision_failures[*]}"
else
    pass
fi

test_start "Codex source-to-candidate drift fails closed before configuration commit and runtime deletion"
source_drift_failures=()
source_drift_runners=(bash)
command -v pwsh >/dev/null 2>&1 && source_drift_runners+=(powershell)
for source_drift_runner in "${source_drift_runners[@]}"; do
    source_drift_home="$(mktemp -d)"
    source_drift_bin="$(mktemp -d)"
    p0p4_register_cleanup "$source_drift_home" "$source_drift_bin"
    mkdir -p "$source_drift_home/.codex/tools/memory-graph" "$source_drift_home/.codex/memory"
    printf '%s\n' runtime >"$source_drift_home/.codex/tools/memory-graph/run-memory-graph.sh"
    printf '%s\n' provider >"$source_drift_home/.codex/memory/graph.db"
    printf '%s\n' '[mcp_servers.memory-graph]' 'command = "retire"' '' '[mcp_servers.keep]' 'command = "keep"' >"$source_drift_home/.codex/config.toml"
    printf '%s\n' '#!/bin/sh' \
        'count_file="$DRIFT_CALLS"; count=0; [ -f "$count_file" ] && count=$(cat "$count_file"); count=$((count + 1)); printf "%s" "$count" >"$count_file"' \
        'if [ "$1" = "mcp" ] && [ "$2" = "list" ] && [ "$3" = "--json" ]; then' \
        '  if [ "$count" -eq 2 ]; then printf "[mcp_servers.concurrent]\\ncommand = \\\"concurrent\\\"\\n" >"$DRIFT_TARGET"; fi' \
        '  if grep -Fxq "[mcp_servers.memory-graph]" "$HOME/config.toml"; then printf "[{\\\"name\\\":\\\"memory-graph\\\"}]\\n"; else printf "[]\\n"; fi; exit 0' \
        'fi' \
        'exit 64' >"$source_drift_bin/codex"
    chmod +x "$source_drift_bin/codex"
    if [[ "$source_drift_runner" == bash ]]; then
        DRIFT_CALLS="$source_drift_home/calls" DRIFT_TARGET="$source_drift_home/.codex/config.toml" HOME="$source_drift_home" PATH="$source_drift_bin:$PATH" bash "$cleanup_bash" --agent codex >/tmp/p0p4-source-drift-bash.out 2>/tmp/p0p4-source-drift-bash.err && source_drift_status=0 || source_drift_status=$?
    else
        DRIFT_CALLS="$source_drift_home/calls" DRIFT_TARGET="$source_drift_home/.codex/config.toml" USERPROFILE="$source_drift_home" HOME="$source_drift_home" PATH="$source_drift_bin:$PATH" pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent codex >/tmp/p0p4-source-drift-powershell.out 2>/tmp/p0p4-source-drift-powershell.err && source_drift_status=0 || source_drift_status=$?
    fi
    if [[ "$source_drift_status" -eq 0 ]] || ! grep -Fxq '[mcp_servers.concurrent]' "$source_drift_home/.codex/config.toml" \
        || [[ ! -f "$source_drift_home/.codex/tools/memory-graph/run-memory-graph.sh" || ! -f "$source_drift_home/.codex/memory/graph.db" ]] \
        || [[ "$(cat "$source_drift_home/calls")" != 2 ]]; then
        source_drift_failures+=("$source_drift_runner")
    fi
done
if [[ "${#source_drift_failures[@]}" -ne 0 ]]; then fail "source-to-candidate drift overwrote concurrent config or retired runtime: ${source_drift_failures[*]}"; else pass; fi

test_start "no-Python cleanup rejects dangling relevant config links before retiring runtime"
dangling_config_home="$(mktemp -d)"
dangling_config_bin="$(mktemp -d)"
p0p4_register_cleanup "$dangling_config_home" "$dangling_config_bin"
mkdir -p "$dangling_config_home/.codex/tools/memory-graph" "$dangling_config_home/.codex/memory"
printf '%s\n' runtime >"$dangling_config_home/.codex/tools/memory-graph/run-memory-graph.sh"
printf '%s\n' provider >"$dangling_config_home/.codex/memory/graph.db"
ln -s "$dangling_config_home/missing-config.toml" "$dangling_config_home/.codex/config.toml"
printf '%s\n' '#!/bin/sh' 'exec /bin/rm "$@"' >"$dangling_config_bin/rm"
chmod +x "$dangling_config_bin/rm"
HOME="$dangling_config_home" PATH="$dangling_config_bin" /bin/bash "$cleanup_bash" --agent codex >/tmp/p0p4-dangling-config.out 2>/tmp/p0p4-dangling-config.err && dangling_config_status=0 || dangling_config_status=$?
dangling_config_output="$(cat /tmp/p0p4-dangling-config.out /tmp/p0p4-dangling-config.err)"
if [[ "$dangling_config_status" -eq 0 ]] \
    || [[ ! -L "$dangling_config_home/.codex/config.toml" ]] \
    || [[ ! -f "$dangling_config_home/.codex/tools/memory-graph/run-memory-graph.sh" || ! -f "$dangling_config_home/.codex/memory/graph.db" ]] \
    || ! printf '%s' "$dangling_config_output" | grep -Fq "$dangling_config_home/.codex/config.toml"; then
    fail "no-Python cleanup did not fail closed on a dangling relevant config link before runtime retirement"
else
    pass
fi

test_start "PowerShell config FIFO preflight fails promptly without retiring runtime or provider data"
if ! command -v pwsh >/dev/null 2>&1 || ! command -v perl >/dev/null 2>&1; then
    skip "pwsh or bounded external deadline support is unavailable for FIFO preflight verification"
else
    fifo_home="$(mktemp -d)"
    p0p4_register_cleanup "$fifo_home"
    mkdir -p "$fifo_home/.codex/tools/memory-graph" "$fifo_home/.codex/memory"
    printf '%s\n' runtime >"$fifo_home/.codex/tools/memory-graph/run-memory-graph.sh"
    printf '%s\n' provider >"$fifo_home/.codex/memory/graph.db"
    mkfifo "$fifo_home/.codex/config.toml"
    fifo_started="$(date +%s)"
    fifo_deadline_seconds=10
    USERPROFILE="$fifo_home" HOME="$fifo_home" perl -e 'alarm shift; exec @ARGV' "$fifo_deadline_seconds" pwsh -NoLogo -NoProfile -File "$cleanup_powershell" -Agent codex >/tmp/p0p4-fifo.out 2>/tmp/p0p4-fifo.err && fifo_status=0 || fifo_status=$?
    fifo_elapsed=$(( $(date +%s) - fifo_started ))
    if [[ "$fifo_status" -eq 0 || "$fifo_elapsed" -ge "$fifo_deadline_seconds" || ! -p "$fifo_home/.codex/config.toml" \
        || ! -f "$fifo_home/.codex/tools/memory-graph/run-memory-graph.sh" || ! -f "$fifo_home/.codex/memory/graph.db" ]]; then
        fail "PowerShell FIFO preflight blocked or mutated before rejecting a non-regular config"
    else
        pass
    fi
fi

test_start "canonical root aliases are rejected before no-Python dry-run planning"
root_alias_safe_home="$(mktemp -d)"
root_alias_bin="$(mktemp -d)"
p0p4_register_cleanup "$root_alias_safe_home" "$root_alias_bin"
root_alias_failures=()
for root_alias_case in home-dot home-parent home-slashes codex-home-dot; do
    case "$root_alias_case" in
        home-dot) root_alias_home=/./; root_alias_codex_home="" ;;
        home-parent) root_alias_home=/tmp/..; root_alias_codex_home="" ;;
        home-slashes) root_alias_home=///; root_alias_codex_home="" ;;
        codex-home-dot) root_alias_home="$root_alias_safe_home"; root_alias_codex_home=/./ ;;
    esac
    if HOME="$root_alias_home" CODEX_HOME="$root_alias_codex_home" PATH="$root_alias_bin" /bin/bash "$cleanup_bash" --agent codex --dry-run >/tmp/p0p4-root-alias-"$root_alias_case".out 2>/tmp/p0p4-root-alias-"$root_alias_case".err; then
        root_alias_failures+=("$root_alias_case accepted")
        continue
    fi
    root_alias_output="$(cat /tmp/p0p4-root-alias-"$root_alias_case".out /tmp/p0p4-root-alias-"$root_alias_case".err)"
    if ! printf '%s' "$root_alias_output" | grep -Eiq 'root|HOME|boundary' || printf '%s' "$root_alias_output" | grep -Fq 'command ='; then
        root_alias_failures+=("$root_alias_case diagnostic")
    fi
done
if [[ "${#root_alias_failures[@]}" -ne 0 ]]; then
    fail "canonical root aliases reached planning or exposed config content: ${root_alias_failures[*]}"
else
    pass
fi

test_start "Bash rejects structured JSON above the shared 4 MiB input budget before mutation"
large_json_home="$(mktemp -d)"
p0p4_register_cleanup "$large_json_home"
mkdir -p "$large_json_home/.claude/tools/memory-graph" "$large_json_home/.claude/memory"
printf '%s\n' runtime >"$large_json_home/.claude/tools/memory-graph/run-memory-graph.sh"
printf '%s\n' provider >"$large_json_home/.claude/memory/graph.db"
printf '%s' '{"mcpServers":{"memory-graph":{"command":"retire"},"keep":{"padding":"' >"$large_json_home/.claude/settings.json"
dd if=/dev/zero bs=1 count=$((4 * 1024 * 1024 + 1)) 2>/dev/null | tr '\0' x >>"$large_json_home/.claude/settings.json"
printf '%s\n' '"}}}' >>"$large_json_home/.claude/settings.json"
cp "$large_json_home/.claude/settings.json" "$large_json_home/.claude/settings.before"
HOME="$large_json_home" bash "$cleanup_bash" --agent claude >/tmp/p0p4-large-json.out 2>/tmp/p0p4-large-json.err && large_json_status=0 || large_json_status=$?
large_json_output="$(cat /tmp/p0p4-large-json.out /tmp/p0p4-large-json.err)"
if [[ "$large_json_status" -eq 0 ]] \
    || ! cmp -s "$large_json_home/.claude/settings.before" "$large_json_home/.claude/settings.json" \
    || [[ ! -f "$large_json_home/.claude/tools/memory-graph/run-memory-graph.sh" || ! -f "$large_json_home/.claude/memory/graph.db" ]] \
    || ! printf '%s' "$large_json_output" | grep -Fq "$large_json_home/.claude/settings.json" \
    || printf '%s' "$large_json_output" | grep -Fq 'padding'; then
    fail "Bash accepted or mutated structured JSON above the 4 MiB budget"
else
    pass
fi

test_start "PowerShell installer stops before installation and omits success when retirement is incomplete"
if ! command -v pwsh >/dev/null 2>&1; then
    skip "pwsh is unavailable for PowerShell installer incomplete-retirement verification"
else
    ps_installer_incomplete_home="$(mktemp -d)"
    p0p4_register_cleanup "$ps_installer_incomplete_home"
    mkdir -p "$ps_installer_incomplete_home/.codex/tools/memory-graph"
    printf '%s\n' runtime >"$ps_installer_incomplete_home/.codex/tools/memory-graph/run-memory-graph.ps1"
    printf '%s\n' '[mcp_servers.memory-graph]' 'command = "retire"' '' '[mcp_servers.keep]' 'invalid = [1,' >"$ps_installer_incomplete_home/.codex/config.toml"
    if USERPROFILE="$ps_installer_incomplete_home" HOME="$ps_installer_incomplete_home" P0P4_CODEX_SEMANTIC_FIXTURE_MODE=reject pwsh -NoLogo -NoProfile -File "$FRAMEWORK_DIR/install.ps1" -Agent codex -Skill assistant-workflow -NoHooks >/tmp/p0p4-installer-incomplete-powershell.out 2>/tmp/p0p4-installer-incomplete-powershell.err; then
        fail "PowerShell installer reported success despite incomplete retirement"
    elif [[ -e "$ps_installer_incomplete_home/.codex/skills/assistant-workflow" || ! -f "$ps_installer_incomplete_home/.codex/tools/memory-graph/run-memory-graph.ps1" ]] \
        || grep -Fq 'Installation complete' /tmp/p0p4-installer-incomplete-powershell.out; then
        fail "PowerShell installer installed or printed success after incomplete retirement"
    else
        pass
    fi
fi

test_start "retired presentation generator remains absent"
presentation_generator="$FRAMEWORK_DIR/docs/create-presentation.py"
if [[ -e "$presentation_generator" ]]; then
    fail "docs/create-presentation.py must remain absent with the retired Reflexion presentation content"
else
    pass
fi

test_start "handoff and cleanup audit documents do not retain retired memory protocol inventory"
retired_memory_protocol_docs=(
    "$FRAMEWORK_DIR/docs/assistant-framework-priority-handoff-2026-07-12.md"
    "$FRAMEWORK_DIR/docs/cleanup-audit-2026-06-25.md"
)
if rg -n -i -F 'memory protocol' "${retired_memory_protocol_docs[@]}" >/tmp/p0p4-memory-protocol-doc-retirement.out; then
    fail "handoff and cleanup audit documentation retains retired memory protocol inventory lines"
else
    pass
fi

test_start "current public docs do not promise retired graph or self-improvement behavior"
current_docs=("$FRAMEWORK_DIR/README.md" "$FRAMEWORK_DIR/AGENTS.md" "$FRAMEWORK_DIR/CLAUDE.md" "$FRAMEWORK_DIR/docs/plugin-architecture.md")
if rg -n -i -e 'knowledge graph' -e 'graph MCP' -e 'persistent self-improvement' -e 'never forgets' "${current_docs[@]}" >/tmp/p0p4-public-graph-promises.out; then
    fail "current public docs retain retired graph or persistent self-improvement promises"
else
    pass
fi

test_start "cleanup help, installer completion, and presentation retirement use current wording"
cleanup_help="$($cleanup_bash --help 2>&1 || true)"
if ! printf '%s\n' "$cleanup_help" | grep -Fq -- '--agent' \
    || ! printf '%s\n' "$cleanup_help" | grep -Fq -- 'claude, codex, or gemini'; then
    fail "cleanup help must document the agent filter"
elif rg -n -i 'memory protocol' "$FRAMEWORK_DIR/install.sh" "$FRAMEWORK_DIR/install.ps1" >/tmp/p0p4-installer-completion-wording.out; then
    fail "installer comments and completion text must not retain retired memory-protocol language"
elif ! grep -Fq 'Invalid or ambiguous structured configuration is left unchanged and cleanup stops before deleting retired artifacts.' "$FRAMEWORK_DIR/README.md"; then
    fail "README must describe malformed structured configuration as fail-closed and preserved"
elif rg -n -i 'actions/setup-dotnet|dotnet-version' "$FRAMEWORK_DIR/.github/workflows/windows-installer.yml" >/tmp/p0p4-windows-dotnet-retirement.out; then
    fail "Windows installer workflow must not provision an unused .NET SDK after Memory Graph retirement"
else
    pass
fi

p0p4_disable_codex_semantic_fixture
p0p4_finish_suite "${BASH_SOURCE[0]}"
