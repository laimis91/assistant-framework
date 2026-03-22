#!/usr/bin/env bash
# install.sh — Installs all Assistant Framework skills for any supported AI agent.
#
# Auto-discovers skills from the skills/ directory (any subdirectory with SKILL.md).
# Also installs hooks + memory seed data.
#
# Also installs hooks for automated:
#   - Context injection on session start/resume
#   - State preservation before context compression
#   - Self-review enforcement before task handoff
#   - Session end reminders
#
# Usage:
#   ./install.sh --agent claude     # → ~/.claude/skills/assistant-*/
#   ./install.sh --agent codex      # → ~/.codex/skills/assistant-*/
#   ./install.sh --agent gemini     # → ~/.gemini/skills/assistant-*/
#   ./install.sh --agent claude --dry-run
#   ./install.sh --agent claude --skill assistant-workflow  # single skill only
#   ./install.sh --agent claude --no-hooks                  # skip hook installation
#
# Memory data (user preferences, insights) is installed to ~/.{agent}/memory/
# only if it doesn't already exist — existing memory is never overwritten.

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────

AGENT=""
DRY_RUN=false
SINGLE_SKILL=""
INSTALL_HOOKS=true
TEST_HOOKS=false
FRAMEWORK_DIR=""
toml_files=()

# Skills are auto-discovered from the skills/ directory.
# Any subdirectory containing a SKILL.md is treated as an installable skill.
SKILLS=()

# ── Parse args ────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Installs the Assistant Framework skills for an AI agent.

Options:
  --agent NAME       Target agent: claude, codex, gemini (required)
  --skill NAME       Install only one skill (default: all)
  --no-hooks         Skip hook installation
  --test-hooks       Run hook integration tests (requires --agent)
  --dry-run          Show what would be done without doing it
  -h, --help         Show this help

Note: skill installation uses rsync --delete, which removes any files you
added manually to installed skill directories. Back up customizations first.

Skills installed:
  Auto-discovered from skills/ directory (any subdirectory with SKILL.md).

Memory data:
  Installed to ~/.{agent}/memory/ on first install only.
  Existing memory is never overwritten.

Examples:
  $(basename "$0") --agent claude
  $(basename "$0") --agent codex --dry-run
  $(basename "$0") --agent claude --skill assistant-thinking
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --agent)    [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; AGENT="$2"; shift 2 ;;
        --skill)    [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; SINGLE_SKILL="$2"; shift 2 ;;
        --no-hooks)   INSTALL_HOOKS=false; shift ;;
        --test-hooks) TEST_HOOKS=true; shift ;;
        --dry-run)    DRY_RUN=true; shift ;;
        -h|--help)  usage ;;
        *)          echo "Unknown option: $1"; usage ;;
    esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────

fail() { echo "Error: $1" >&2; exit 1; }
info() { echo "  $1"; }
ok()   { echo "  OK: $1"; }
dry()  { echo "  [dry-run] $1"; }

# ── Validate ──────────────────────────────────────────────────────────────────

[[ -n "$AGENT" ]] || fail "Missing --agent. Supported: claude, codex, gemini"
[[ "$AGENT" =~ ^(claude|codex|gemini)$ ]] || fail "Unknown agent: $AGENT. Supported: claude, codex, gemini"

FRAMEWORK_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_SOURCE="$FRAMEWORK_DIR/skills"
MEMORY_SOURCE="$FRAMEWORK_DIR/memory-seed"
HOOKS_SOURCE="$FRAMEWORK_DIR/hooks"

[[ -d "$SKILLS_SOURCE" ]] || fail "Skills directory not found at $SKILLS_SOURCE"

# Auto-discover skills: any subdirectory of skills/ containing a SKILL.md
while IFS= read -r skill_md; do
    skill_dir="$(dirname "$skill_md")"
    skill_name="$(basename "$skill_dir")"
    SKILLS+=("$skill_name")
done < <(find "$SKILLS_SOURCE" -maxdepth 2 -name "SKILL.md" -type f | sort)
command -v rsync >/dev/null 2>&1 || fail "rsync is required but not installed. Install with: apt install rsync / dnf install rsync / brew install rsync"

# ── Test hooks (if requested) ────────────────────────────────────────────────

if $TEST_HOOKS; then
    if $DRY_RUN; then
        info "[dry-run] Would run hook integration tests"
        exit 0
    fi
    TEST_SCRIPT="$FRAMEWORK_DIR/tests/test-hooks.sh"
    if [[ -f "$TEST_SCRIPT" ]]; then
        echo "Running hook integration tests..."
        echo ""
        bash "$TEST_SCRIPT"
        exit $?
    else
        fail "Test script not found at $TEST_SCRIPT"
    fi
fi

# Determine target base
AGENT_HOME="$HOME/.${AGENT}"
SKILLS_TARGET="$AGENT_HOME/skills"
MEMORY_TARGET="$AGENT_HOME/memory"

# Filter to single skill if requested
if [[ -n "$SINGLE_SKILL" ]]; then
    [[ -f "$SKILLS_SOURCE/$SINGLE_SKILL/SKILL.md" ]] || fail "Unknown skill: $SINGLE_SKILL. Available: ${SKILLS[*]}"
    SKILLS=("$SINGLE_SKILL")
fi

HOOKS_TARGET="$AGENT_HOME/hooks/assistant"
SETTINGS_FILE="$AGENT_HOME/settings.json"

echo "Installing Assistant Framework for: $AGENT"
echo "  Source: $FRAMEWORK_DIR"
echo "  Skills target: $SKILLS_TARGET"
echo "  Hooks target: $HOOKS_TARGET"
echo "  Memory target: $MEMORY_TARGET"
echo ""

# ── Install skills ────────────────────────────────────────────────────────────

for skill in "${SKILLS[@]}"; do
    source_dir="$SKILLS_SOURCE/$skill"
    target_dir="$SKILLS_TARGET/$skill"

    if [[ ! -d "$source_dir" ]]; then
        info "SKIP: $skill (source not found)"
        continue
    fi

    if $DRY_RUN; then
        dry "rsync $source_dir/ -> $target_dir/"
        if [[ "$AGENT" != "claude" ]]; then
            dry "Substitute .claude/ paths with .${AGENT}/ in $skill/SKILL.md"
        fi
    else
        mkdir -p "$target_dir"
        rsync -a --delete \
            --exclude='.DS_Store' \
            "$source_dir/" "$target_dir/"

        # Substitute agent-specific state directory paths in all .md files
        # Replaces .claude/ paths in: backtick-quoted inline refs, code blocks,
        # and standalone path references. Avoids prose like "Claude's .claude/ directory"
        # by targeting patterns that look like actual paths (preceded by backtick, ~/, or line start).
        if [[ "$AGENT" != "claude" ]]; then
            while IFS= read -r md_file; do
                sed -i.bak \
                    -e "s|\`~/\.claude/|\`~/.${AGENT}/|g" \
                    -e "s|\`\.claude/|\`.${AGENT}/|g" \
                    -e "s|~~/\.claude/|~~/.${AGENT}/|g" \
                    -e "s|^~/\.claude/|~/.${AGENT}/|g" \
                    -e "s| ~/\.claude/| ~/.${AGENT}/|g" \
                    -e "s| \.claude/| .${AGENT}/|g" \
                    "$md_file"
                rm -f "${md_file}.bak"
            done < <(find "$target_dir" -name "*.md" -type f)
        fi

        ok "$skill -> $target_dir"
    fi
done

# ── Check skill dependencies ─────────────────────────────────────────────────

for skill in "${SKILLS[@]}"; do
    skill_md="$SKILLS_SOURCE/$skill/SKILL.md"
    [[ -f "$skill_md" ]] || continue

    # Parse requires: from YAML frontmatter (simple grep, no YAML parser needed)
    in_frontmatter=false
    in_requires=false
    while IFS= read -r line; do
        # Track frontmatter boundaries (opening and closing ---)
        if [[ "$line" == "---" ]]; then
            if $in_frontmatter; then
                break  # closing delimiter — done
            else
                in_frontmatter=true
                continue  # opening delimiter — skip
            fi
        fi
        $in_frontmatter || continue
        if [[ "$line" == "requires:" ]]; then
            in_requires=true
            continue
        fi
        if $in_requires; then
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(.+) ]]; then
                dep="${BASH_REMATCH[1]}"
                dep_installed=false
                for s in "${SKILLS[@]}"; do
                    [[ "$s" == "$dep" ]] && dep_installed=true
                done
                if ! $dep_installed && [[ ! -d "$SKILLS_TARGET/$dep" ]]; then
                    info "NOTE: $skill requires '$dep' which is not being installed and not found at $SKILLS_TARGET/$dep"
                fi
            else
                in_requires=false
            fi
        fi
    done < "$skill_md"
done

# ── Install tools ────────────────────────────────────────────────────────────

TOOLS_SOURCE="$FRAMEWORK_DIR/tools"
TOOLS_TARGET="$AGENT_HOME/tools"

if [[ -d "$TOOLS_SOURCE" ]]; then
    echo ""
    if $DRY_RUN; then
        dry "rsync $TOOLS_SOURCE/ -> $TOOLS_TARGET/"
    else
        mkdir -p "$TOOLS_TARGET"
        rsync -a --delete \
            --exclude='.DS_Store' \
            --exclude='.publish' \
            --exclude='bin' \
            --exclude='obj' \
            "$TOOLS_SOURCE/" "$TOOLS_TARGET/"

        # Make scripts executable
        if compgen -G "$TOOLS_TARGET"/*/*.sh >/dev/null 2>&1; then
            chmod +x "$TOOLS_TARGET"/*/*.sh
        fi

        ok "Tools -> $TOOLS_TARGET/"
    fi
fi

# ── Register MCP servers ─────────────────────────────────────────────────────

# Register memory-graph MCP server in the correct config file per agent.
# Claude Code reads MCP servers from ~/.claude.json (user scope), NOT settings.json.
# Other agents may use their own config files.
if [[ -f "$TOOLS_TARGET/memory-graph/run-memory-graph.sh" ]] || { $DRY_RUN && [[ -f "$TOOLS_SOURCE/memory-graph/run-memory-graph.sh" ]]; }; then
    echo ""
    MCP_COMMAND="$TOOLS_TARGET/memory-graph/run-memory-graph.sh"
    MCP_MEMORY_DIR="$MEMORY_TARGET"

    if [[ "$AGENT" == "claude" ]]; then
        # Claude Code: use `claude mcp add` if available, else write ~/.claude.json
        if $DRY_RUN; then
            dry "Register memory-graph MCP server (claude mcp add --scope user)"
        elif command -v claude &>/dev/null; then
            # Check if already registered
            if claude mcp list 2>/dev/null | grep -q "memory-graph"; then
                info "MCP server memory-graph already registered in Claude"
            else
                if claude mcp add --scope user --transport stdio memory-graph -- \
                    "$MCP_COMMAND" --memory-dir "$MCP_MEMORY_DIR" 2>/dev/null; then
                    ok "MCP server memory-graph registered via 'claude mcp add' (user scope)"
                else
                    info "WARNING: 'claude mcp add' failed. Falling back to manual registration."
                    register_mcp_claude_json=true
                fi
            fi
        else
            register_mcp_claude_json=true
        fi

        # Fallback: write directly to ~/.claude.json
        if [[ "${register_mcp_claude_json:-}" == "true" ]]; then
            MCP_CONFIG_FILE="$HOME/.claude.json"
            if command -v jq &>/dev/null; then
                if [[ ! -f "$MCP_CONFIG_FILE" ]]; then
                    echo '{}' > "$MCP_CONFIG_FILE"
                fi
                if jq -e '.mcpServers["memory-graph"]' "$MCP_CONFIG_FILE" &>/dev/null; then
                    info "MCP server memory-graph already registered in $MCP_CONFIG_FILE"
                else
                    # Backup before modifying
                    cp "$MCP_CONFIG_FILE" "${MCP_CONFIG_FILE}.bak"
                    if jq --arg cmd "$MCP_COMMAND" --arg dir "$MCP_MEMORY_DIR" \
                        '.mcpServers["memory-graph"] = {"command": $cmd, "args": ["--memory-dir", $dir]}' \
                        "$MCP_CONFIG_FILE" > "${MCP_CONFIG_FILE}.tmp" \
                        && jq . "${MCP_CONFIG_FILE}.tmp" > /dev/null 2>&1 \
                        && mv "${MCP_CONFIG_FILE}.tmp" "$MCP_CONFIG_FILE"; then
                        rm -f "${MCP_CONFIG_FILE}.bak"
                        ok "MCP server memory-graph registered in $MCP_CONFIG_FILE"
                    else
                        rm -f "${MCP_CONFIG_FILE}.tmp"
                        # Restore backup on failure
                        mv "${MCP_CONFIG_FILE}.bak" "$MCP_CONFIG_FILE" 2>/dev/null || true
                        info "WARNING: Failed to register MCP server in $MCP_CONFIG_FILE"
                    fi
                fi
            else
                info "NOTE: Neither 'claude' CLI nor 'jq' found — MCP server not auto-registered."
                info "Register manually by running:"
                info "  claude mcp add --scope user --transport stdio memory-graph -- \\"
                info "    $MCP_COMMAND --memory-dir $MCP_MEMORY_DIR"
            fi
        fi

        # Clean up stale mcpServers from settings.json (wrong location from older installs)
        if [[ -f "$SETTINGS_FILE" ]] && command -v jq &>/dev/null; then
            if jq -e '.mcpServers["memory-graph"]' "$SETTINGS_FILE" &>/dev/null; then
                if jq 'del(.mcpServers["memory-graph"]) | if .mcpServers == {} then del(.mcpServers) else . end' \
                    "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" \
                    && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"; then
                    info "Cleaned up stale MCP config from $SETTINGS_FILE (moved to correct location)"
                else
                    rm -f "${SETTINGS_FILE}.tmp"
                fi
            fi
        fi
    elif [[ "$AGENT" == "codex" ]]; then
        # Codex: register in ~/.codex/config.toml using [mcp_servers.name] TOML syntax
        CODEX_CONFIG="$AGENT_HOME/config.toml"
        if $DRY_RUN; then
            dry "Register memory-graph MCP server in $CODEX_CONFIG"
        else
            if [[ -f "$CODEX_CONFIG" ]] && grep -q '\[mcp_servers\.memory-graph\]' "$CODEX_CONFIG" 2>/dev/null; then
                info "MCP server memory-graph already registered in $CODEX_CONFIG"
            else
                # Append TOML block
                {
                    echo ""
                    echo "[mcp_servers.memory-graph]"
                    echo "command = \"$MCP_COMMAND\""
                    echo "args = [\"--memory-dir\", \"$MCP_MEMORY_DIR\"]"
                } >> "$CODEX_CONFIG"
                ok "MCP server memory-graph registered in $CODEX_CONFIG"
            fi
        fi
    else
        # Gemini and other agents: register in settings.json with JSON mcpServers format
        if $DRY_RUN; then
            dry "Register memory-graph MCP server in $SETTINGS_FILE"
        elif command -v jq &>/dev/null; then
            if [[ ! -f "$SETTINGS_FILE" ]]; then
                echo '{}' > "$SETTINGS_FILE"
            fi
            if jq -e '.mcpServers["memory-graph"]' "$SETTINGS_FILE" &>/dev/null; then
                info "MCP server memory-graph already registered in $SETTINGS_FILE"
            else
                if jq --arg cmd "$MCP_COMMAND" --arg dir "$MCP_MEMORY_DIR" \
                    '.mcpServers["memory-graph"] = {"command": $cmd, "args": ["--memory-dir", $dir]}' \
                    "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" \
                    && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"; then
                    ok "MCP server memory-graph registered in $SETTINGS_FILE"
                else
                    rm -f "${SETTINGS_FILE}.tmp"
                    info "WARNING: Failed to register MCP server in $SETTINGS_FILE"
                fi
            fi
        else
            info "NOTE: jq not found — memory-graph MCP server not auto-registered."
            info "Add manually to $SETTINGS_FILE:"
            info "  \"mcpServers\": { \"memory-graph\": { \"command\": \"$MCP_COMMAND\", \"args\": [\"--memory-dir\", \"$MCP_MEMORY_DIR\"] } }"
        fi
    fi
fi

# ── Install memory seed (only if memory doesn't exist) ───────────────────────

echo ""
if [[ -d "$MEMORY_TARGET" ]]; then
    info "Memory already exists at $MEMORY_TARGET — skipping (never overwrite)"
else
    if [[ -d "$MEMORY_SOURCE" ]]; then
        if $DRY_RUN; then
            dry "cp -r $MEMORY_SOURCE/ -> $MEMORY_TARGET/ (first install only)"
        else
            mkdir -p "$(dirname "$MEMORY_TARGET")"
            rsync -a --exclude='.DS_Store' "$MEMORY_SOURCE/" "$MEMORY_TARGET/"
            ok "Memory seed installed to $MEMORY_TARGET"
        fi
    else
        info "No memory seed found — skipping"
    fi
fi

# ── Install agents ────────────────────────────────────────────────────────

AGENTS_SOURCE="$FRAMEWORK_DIR/agents"

if [[ "$AGENT" == "codex" && -d "$AGENTS_SOURCE/codex" ]]; then
    echo ""
    AGENTS_TARGET="$AGENT_HOME/agents"

    # Collect TOML files safely (nullglob prevents literal glob on no matches)
    shopt -s nullglob
    toml_files=("$AGENTS_SOURCE/codex/"*.toml)
    shopt -u nullglob

    if [[ ${#toml_files[@]} -eq 0 ]]; then
        info "No TOML agent files found in $AGENTS_SOURCE/codex/ — skipping"
    elif $DRY_RUN; then
        for toml in "${toml_files[@]}"; do
            dry "Install agent: $(basename "$toml") -> $AGENTS_TARGET/"
        done
    else
        mkdir -p "$AGENTS_TARGET"
        for toml in "${toml_files[@]}"; do
            cp "$toml" "$AGENTS_TARGET/"
        done
        ok "Codex agents -> $AGENTS_TARGET/ (${#toml_files[@]} agents)"
    fi
fi

if [[ "$AGENT" == "claude" && -d "$AGENTS_SOURCE/claude" ]]; then
    echo ""
    AGENTS_TARGET="$AGENT_HOME/agents"

    # Collect .md agent files
    shopt -s nullglob
    md_files=("$AGENTS_SOURCE/claude/"*.md)
    shopt -u nullglob

    if [[ ${#md_files[@]} -eq 0 ]]; then
        info "No agent files found in $AGENTS_SOURCE/claude/ — skipping"
    elif $DRY_RUN; then
        for md in "${md_files[@]}"; do
            dry "Install agent: $(basename "$md") -> $AGENTS_TARGET/"
        done
    else
        mkdir -p "$AGENTS_TARGET"
        for md in "${md_files[@]}"; do
            cp "$md" "$AGENTS_TARGET/"
        done
        ok "Claude agents -> $AGENTS_TARGET/ (${#md_files[@]} agents)"
    fi
fi

# ── Install hooks ─────────────────────────────────────────────────────────

if $INSTALL_HOOKS; then
    echo ""

    # Determine which settings template to use
    HOOKS_SETTINGS=""
    case "$AGENT" in
        claude)  HOOKS_SETTINGS="$HOOKS_SOURCE/claude-settings.json" ;;
        gemini)  HOOKS_SETTINGS="$HOOKS_SOURCE/gemini-settings.json" ;;
        codex)   HOOKS_SETTINGS="$HOOKS_SOURCE/codex-settings.json" ;;
    esac

    if [[ -n "$HOOKS_SETTINGS" && -f "$HOOKS_SETTINGS" ]]; then
        if $DRY_RUN; then
            dry "Copy hook scripts to $HOOKS_TARGET/"
            dry "Merge hook configuration into $SETTINGS_FILE"
        else
            # Copy hook scripts
            mkdir -p "$HOOKS_TARGET"
            if compgen -G "$HOOKS_SOURCE/scripts/*.sh" >/dev/null; then
                for hook_script in "$HOOKS_SOURCE/scripts/"*.sh; do
                    hook_name="$(basename "$hook_script")"
                    # post-compact.sh is Claude-only (Gemini/Codex have no PostCompact event)
                    if [[ "$AGENT" != "claude" && "$hook_name" == "post-compact.sh" ]]; then
                        continue
                    fi
                    # Codex only supports SessionStart, UserPromptSubmit, Stop
                    if [[ "$AGENT" == "codex" ]]; then
                        case "$hook_name" in
                            session-start.sh|skill-router.sh|stop-review.sh) ;;  # supported
                            *) continue ;;  # skip unsupported hooks
                        esac
                    fi
                    cp "$hook_script" "$HOOKS_TARGET/"
                done
                # chmod only if files were actually copied
                if compgen -G "$HOOKS_TARGET/*.sh" >/dev/null; then
                    chmod +x "$HOOKS_TARGET/"*.sh
                fi
                ok "Hook scripts -> $HOOKS_TARGET/"
            else
                info "No hook scripts found in $HOOKS_SOURCE/scripts/"
            fi

            # Merge hooks into settings.json
            if [[ -f "$SETTINGS_FILE" ]]; then
                # Settings exists — merge hooks key
                if command -v jq &>/dev/null; then
                    # Use jq to merge (preserves existing settings)
                    existing_hooks=$(jq '.hooks // {}' "$SETTINGS_FILE" 2>/dev/null || echo '{}')
                    new_hooks=$(jq '.hooks' "$HOOKS_SETTINGS")

                    # Array-aware merge: concatenate arrays per event key, deduplicate by command
                    # Guards against non-array values (e.g., hand-edited single objects)
                    merged=$(jq -n --argjson a "$existing_hooks" --argjson b "$new_hooks" '
                        ($a | keys) + ($b | keys) | unique | map(
                            . as $k |
                            {key: $k, value: ([
                                ($a[$k] // [] | if type == "array" then . else [.] end),
                                ($b[$k] // [] | if type == "array" then . else [.] end)
                            ] | add | unique_by(.command))}
                        ) | from_entries
                    ')
                    if jq --argjson hooks "$merged" '.hooks = $hooks' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" \
                        && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"; then
                        ok "Hooks merged into existing $SETTINGS_FILE"
                    else
                        rm -f "${SETTINGS_FILE}.tmp"
                        info "WARNING: Failed to merge hooks into $SETTINGS_FILE"
                    fi
                else
                    info "WARNING: jq not found. Hook scripts installed but settings.json not updated."
                    info "Manually merge $HOOKS_SETTINGS into $SETTINGS_FILE"
                fi
            else
                # No settings — copy hook settings as new file
                cp "$HOOKS_SETTINGS" "$SETTINGS_FILE"
                ok "Created $SETTINGS_FILE with hook configuration"
            fi
        fi
    fi
fi

# ── Memory protocol in global instructions ───────────────────────────────────

MEMORY_PROTOCOL_SOURCE="$FRAMEWORK_DIR/memory-protocol.md"
MARKER="ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START"

# Determine agent's global instructions file
case "$AGENT" in
    claude)  INSTRUCTIONS_FILE="$AGENT_HOME/CLAUDE.md" ;;
    gemini)  INSTRUCTIONS_FILE="$AGENT_HOME/GEMINI.md" ;;
    codex)
        INSTRUCTIONS_FILE="$AGENT_HOME/CODEX.md"
        info "NOTE: Codex does not auto-read ~/.codex/CODEX.md."
        info "After install, add this to ~/.codex/config.toml or your --system-prompt:"
        info "  instructions_file = \"$AGENT_HOME/CODEX.md\""
        ;;
esac

if [[ -f "$MEMORY_PROTOCOL_SOURCE" ]]; then
    echo ""

    # Check if protocol is already present
    ALREADY_INSTALLED=false
    if [[ -f "$INSTRUCTIONS_FILE" ]] && grep -q "$MARKER" "$INSTRUCTIONS_FILE" 2>/dev/null; then
        ALREADY_INSTALLED=true
    elif [[ -f "$INSTRUCTIONS_FILE" ]] && grep -q "WAL Protocol\|Persistent Memory System" "$INSTRUCTIONS_FILE" 2>/dev/null; then
        ALREADY_INSTALLED=true
    fi

    if $ALREADY_INSTALLED; then
        info "Memory protocol already present in $INSTRUCTIONS_FILE — skipping"
    elif $DRY_RUN; then
        dry "Would append memory protocol to $INSTRUCTIONS_FILE"
    else
        # Read the protocol template and substitute agent paths
        protocol_content=$(cat "$MEMORY_PROTOCOL_SOURCE")
        if [[ "$AGENT" != "claude" ]]; then
            protocol_content=$(echo "$protocol_content" | sed \
                -e "s|\`~/\.claude/|\`~/.${AGENT}/|g" \
                -e "s|\`\.claude/|\`.${AGENT}/|g" \
                -e "s|~~/\.claude/|~~/.${AGENT}/|g" \
                -e "s|~/.claude/|~/.${AGENT}/|g")
        fi

        # Ask for confirmation (non-interactive mode: skip)
        if [[ -t 0 ]]; then
            echo ""
            echo "  The memory system needs a protocol section in your global instructions file."
            echo "  File: $INSTRUCTIONS_FILE"
            echo ""
            read -r -p "  Append memory protocol to $INSTRUCTIONS_FILE? [y/N] " response
            case "$response" in
                [yY]|[yY][eE][sS])
                    mkdir -p "$(dirname "$INSTRUCTIONS_FILE")"
                    echo "" >> "$INSTRUCTIONS_FILE"
                    echo "$protocol_content" >> "$INSTRUCTIONS_FILE"
                    ok "Memory protocol appended to $INSTRUCTIONS_FILE"
                    ;;
                *)
                    info "Skipped. To add manually, append the contents of memory-protocol.md to $INSTRUCTIONS_FILE"
                    ;;
            esac
        else
            info "Non-interactive mode — skipping memory protocol setup."
            info "To add manually: cat memory-protocol.md >> $INSTRUCTIONS_FILE"
        fi
    fi
fi

# ── Generate AGENTS.md for Codex (it reads AGENTS.md, not CLAUDE.md) ────────

if [[ "$AGENT" == "codex" ]]; then
    AGENTS_MD="$AGENT_HOME/AGENTS.md"
    echo ""
    if [[ -f "$AGENTS_MD" ]]; then
        info "AGENTS.md already exists at $AGENTS_MD — skipping (edit manually if needed)"
    elif $DRY_RUN; then
        dry "Would generate $AGENTS_MD from installed skills"
    else
        cat > "$AGENTS_MD" << 'AGENTS_EOF'
# AGENTS.md — Codex Agent Instructions

## Skill Routing

Before acting on any user request, check if it matches an available skill trigger.
If it does, load the matching skill from ~/.codex/skills/<name>/SKILL.md before proceeding.

## Available Skills

Skills are installed in ~/.codex/skills/. Each contains a SKILL.md with trigger patterns
and workflow instructions. Key skills:

- **assistant-workflow**: Structured development: triage, discover, plan, build, test, review, document
- **assistant-tdd**: Test-Driven Development with Red-Green-Refactor enforcement
- **assistant-review**: Autonomous code review loop (max 5 rounds)
- **assistant-security**: STRIDE threat models, OWASP code review, CVE audits
- **assistant-memory**: Cross-session learning with persistent memory
- **assistant-research**: Tiered research and investigation
- **assistant-thinking**: Structured reasoning tools (clarify, debate, brainstorm)

## Available Agents

Custom agents are in ~/.codex/agents/:
- **code-mapper**: Lightweight codebase mapping (read-only)
- **explorer**: Deep execution path tracing (read-only)
- **architect**: Implementation blueprint design (read-only)
- **code-writer**: Focused code implementation (write access)
- **builder-tester**: Build, write tests, run tests (write access)
- **reviewer**: Independent code review with confidence filtering (read-only)

## Memory System

Persistent memory lives in ~/.codex/memory/:
- INDEX.md — memory index (loaded every session)
- user/ — preferences and working style
- feedback/ — corrections and rules (highest priority)
- insights/ — task learnings (date-prefixed)

Project memory lives in .codex/ at the project root:
- memory.md — project decisions and conventions
- session.md — current session state
- task.md — active task journal

## Coding Conventions

- Default to C# on modern .NET; respect existing repo conventions
- Prefer Clean Architecture with dependency inversion
- Use Microsoft.Extensions.DependencyInjection and Microsoft.Extensions.Logging
- Never hardcode secrets; never log PII
- Tests: xUnit/NUnit, Arrange-Act-Assert, descriptive naming
AGENTS_EOF
        ok "Generated $AGENTS_MD"
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "Done. Installed ${#SKILLS[@]} skill(s) for $AGENT."
echo ""
echo "Skills:"
for skill in "${SKILLS[@]}"; do
    echo "  $SKILLS_TARGET/$skill/"
done
if [[ -d "$TOOLS_SOURCE" ]]; then
    echo ""
    echo "Tools: $TOOLS_TARGET/"
fi
if [[ "$AGENT" == "codex" && ${#toml_files[@]:-0} -gt 0 ]]; then
    echo ""
    echo "Agents: $AGENT_HOME/agents/"
    for toml in "${toml_files[@]}"; do
        echo "  $(basename "$toml" .toml)"
    done
fi
if [[ "$AGENT" == "claude" && ${#md_files[@]:-0} -gt 0 ]]; then
    echo ""
    echo "Agents: $AGENT_HOME/agents/"
    for md in "${md_files[@]}"; do
        echo "  $(basename "$md" .md)"
    done
fi
if $INSTALL_HOOKS; then
    echo ""
    echo "Hooks: $HOOKS_TARGET/"
    if [[ "$AGENT" == "codex" ]]; then
        echo "  (Codex: SessionStart, UserPromptSubmit, Stop — 3 of 6 hooks)"
    fi
fi
echo ""
echo "Memory: $MEMORY_TARGET/"
echo ""
if [[ -n "$SINGLE_SKILL" ]]; then
    echo "To install all skills: ./install.sh --agent $AGENT"
else
    echo "To install a single skill: ./install.sh --agent $AGENT --skill <name>"
    echo "To skip hooks: ./install.sh --agent $AGENT --no-hooks"
fi
