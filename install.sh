#!/usr/bin/env bash
# install.sh — Installs all Assistant Framework skills for any supported AI agent.
#
# Auto-discovers first-class release skills from skills/assistant-*/SKILL.md.
# Also installs hooks + legacy graph seed/import compatibility.
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
# Legacy graph seed compatibility data is installed to ~/.{agent}/memory/graph.jsonl
# only if it doesn't already exist — existing legacy data is never overwritten.

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────

AGENT=""
DRY_RUN=false
SINGLE_SKILL=""
INSTALL_HOOKS=true
TEST_HOOKS=false
FRAMEWORK_DIR=""
toml_files=()

# Skills are auto-discovered from first-class assistant-* release directories.
SKILLS=()
STALE_FRAMEWORK_UNITY_SKILLS=(
    unity-game-design
    unity-iterate
    unity-multiplayer
    unity-playtest
    unity-procedural-art
    unity-scene-builder
)

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
  Auto-discovered from skills/assistant-*/SKILL.md.

Memory data:
  memory-graph MCP is registered against ~/.{agent}/memory.
  Legacy graph seed/import compatibility data is installed on first install only.
  Existing legacy graph data is never overwritten.

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

substitute_agent_paths_in_stream() {
    if [[ "$AGENT" == "claude" ]]; then
        cat
    else
        sed \
            -e "s|\`~/\.claude/|\`~/.${AGENT}/|g" \
            -e "s|\`\.claude/|\`.${AGENT}/|g" \
            -e "s|\"~/\.claude/|\"~/.${AGENT}/|g" \
            -e "s|\"\.claude/|\".${AGENT}/|g" \
            -e "s|'~/\.claude/|'~/.${AGENT}/|g" \
            -e "s|'\.claude/|'.${AGENT}/|g" \
            -e "s|(\~/\.claude/|(~/.${AGENT}/|g" \
            -e "s|(\.claude/|(.${AGENT}/|g" \
            -e "s|\[~/\.claude/|[~/.${AGENT}/|g" \
            -e "s|\[\.claude/|[.${AGENT}/|g" \
            -e "s|~~/\.claude/|~~/.${AGENT}/|g" \
            -e "s|^~/\.claude/|~/.${AGENT}/|g" \
            -e "s| ~/\.claude/| ~/.${AGENT}/|g" \
            -e "s| \.claude/| .${AGENT}/|g" \
            -e "s| at \.claude/| at .${AGENT}/|g" \
            -e "s| to \.claude/| to .${AGENT}/|g" \
            -e "s|: \.claude/|: .${AGENT}/|g"
    fi
}

substitute_agent_paths_in_file() {
    local target_file="$1"

    [[ "$AGENT" != "claude" ]] || return 0

    sed -i.bak \
        -e "s|\`~/\.claude/|\`~/.${AGENT}/|g" \
        -e "s|\`\.claude/|\`.${AGENT}/|g" \
        -e "s|\"~/\.claude/|\"~/.${AGENT}/|g" \
        -e "s|\"\.claude/|\".${AGENT}/|g" \
        -e "s|'~/\.claude/|'~/.${AGENT}/|g" \
        -e "s|'\.claude/|'.${AGENT}/|g" \
        -e "s|(\~/\.claude/|(~/.${AGENT}/|g" \
        -e "s|(\.claude/|(.${AGENT}/|g" \
        -e "s|\[~/\.claude/|[~/.${AGENT}/|g" \
        -e "s|\[\.claude/|[.${AGENT}/|g" \
        -e "s|~~/\.claude/|~~/.${AGENT}/|g" \
        -e "s|^~/\.claude/|~/.${AGENT}/|g" \
        -e "s| ~/\.claude/| ~/.${AGENT}/|g" \
        -e "s| \.claude/| .${AGENT}/|g" \
        -e "s| at \.claude/| at .${AGENT}/|g" \
        -e "s| to \.claude/| to .${AGENT}/|g" \
        -e "s|: \.claude/|: .${AGENT}/|g" \
        "$target_file"
    rm -f "${target_file}.bak"
}

strip_memory_protocol_from_file() {
    local instructions_file="$1"
    local marker_start="$2"
    local marker_end="$3"

    awk -v marker_start="$marker_start" -v marker_end="$marker_end" '
        function is_legacy_protocol_preamble_line(line) {
            return line == "" \
                || line == "# Assistant Framework — Memory Protocol" \
                || line == "## Role" \
                || is_orchestrator_role_line(line) \
                || line ~ /^<!-- This is a template\. Paths like ~\/\.(claude|codex|gemini)\// \
                || index(line, "<!-- Appended by Assistant Framework install.") == 1
        }

        function is_orchestrator_role_line(line) {
            return line == "You are an orchestrator for memory-aware workflow. Coordinate specialized agents and preserve workflow state while memory_context supplies project rules, preferences, and recent insights. File edits, code implementation, builds/tests, and independent review remain owned by the appropriate specialized agent; your role is dispatch, phase gates, progress tracking, communication, and memory protocol enforcement. The orchestrator does not edit files or write code directly. When a skill matches your task, invoke it and follow its instructions." \
                || (index(line, "You are an orchestrator. You " "delegate ALL " "file editing") == 1 \
                    && index(line, "code implementation, and " "phase execution") > 0)
        }

        function has_legacy_protocol_preamble(from, to,    k) {
            for (k = from; k <= to; k++) {
                if (lines[k] == "# Assistant Framework — Memory Protocol") {
                    return 1
                }
            }
            return 0
        }

        { lines[NR] = $0 }

        END {
            for (i = 1; i <= NR; i++) {
                if (index(lines[i], marker_start) == 0) {
                    continue
                }

                start = i
                for (j = i - 1; j >= 1; j--) {
                    if (!is_legacy_protocol_preamble_line(lines[j])) {
                        break
                    }
                }
                if (has_legacy_protocol_preamble(j + 1, i - 1)) {
                    start = j + 1
                }

                end = i
                while (end <= NR && index(lines[end], marker_end) == 0) {
                    end++
                }
                if (end > NR) {
                    for (j = start; j <= NR; j++) {
                        skip[j] = 1
                    }
                    break
                }

                for (j = start; j <= end; j++) {
                    skip[j] = 1
                }
                i = end
            }

            for (i = 1; i <= NR; i++) {
                if (!(i in skip)) {
                    print lines[i]
                }
            }
        }
    ' "$instructions_file" > "${instructions_file}.tmp" && mv "${instructions_file}.tmp" "$instructions_file"
}

cleanup_installed_tool_build_artifacts() {
    local tools_target="$1"
    local artifact_dir
    local found=false

    if [[ ! -d "$tools_target" ]]; then
        if $DRY_RUN; then
            dry "Would remove stale tool build artifacts under $tools_target/*/: .publish, bin, obj"
        fi
        return 0
    fi

    while IFS= read -r artifact_dir; do
        found=true
        if $DRY_RUN; then
            dry "Remove stale tool build artifact: $artifact_dir"
        else
            rm -rf "$artifact_dir"
        fi
    done < <(find "$tools_target" -mindepth 2 -type d \( -name ".publish" -o -name "bin" -o -name "obj" \) -prune -print)

    if $DRY_RUN && ! $found; then
        dry "No stale tool build artifacts found under $tools_target"
    fi
}

cleanup_stale_framework_unity_skills() {
    local skills_target="$1"
    local stale_skill
    local stale_dir
    local found=false

    if [[ ! -d "$skills_target" ]]; then
        if $DRY_RUN; then
            dry "Would remove known stale framework-owned Unity skills if present under $skills_target"
        fi
        return 0
    fi

    for stale_skill in "${STALE_FRAMEWORK_UNITY_SKILLS[@]}"; do
        stale_dir="$skills_target/$stale_skill"
        if [[ -d "$stale_dir" ]]; then
            found=true
            if $DRY_RUN; then
                dry "Remove stale framework-owned Unity skill: $stale_dir"
            else
                rm -rf "$stale_dir"
            fi
        fi
    done

    if $DRY_RUN && ! $found; then
        dry "No known stale framework-owned Unity skills found under $skills_target"
    fi
}

codex_skill_table_trigger() {
    case "$1" in
        assistant-workflow) printf '%s\n' "build, implement, fix, refactor, plan" ;;
        assistant-clarify) printf '%s\n' "ambiguous, multi-intent, underspecified prompts" ;;
        assistant-diagrams) printf '%s\n' "diagram, draw, visualize, flow" ;;
        assistant-docs) printf '%s\n' "document, docs, README, changelog" ;;
        assistant-ideate) printf '%s\n' "brainstorm, ideas, options, alternatives" ;;
        assistant-memory) printf '%s\n' "remember, save insight, preferences" ;;
        assistant-onboard) printf '%s\n' "learn codebase, onboard, map project" ;;
        assistant-reflexion) printf '%s\n' "reflect, lessons, retrospective" ;;
        assistant-research) printf '%s\n' "research, investigate, compare options" ;;
        assistant-review) printf '%s\n' "review, check the code" ;;
        assistant-security) printf '%s\n' "security, threat model, audit" ;;
        assistant-skill-creator) printf '%s\n' "create skill, scaffold skill, contracts" ;;
        assistant-tdd) printf '%s\n' "tests first, test-driven, red green" ;;
        assistant-telos) printf '%s\n' "telos, purpose, mission, strategy" ;;
        assistant-thinking) printf '%s\n' "think through, stress test, debate" ;;
        *) printf '%s\n' "explicit install" ;;
    esac
}

codex_skill_table_description() {
    case "$1" in
        assistant-workflow) printf '%s\n' "Structured dev: triage through document" ;;
        assistant-clarify) printf '%s\n' "Clarify the request before execution" ;;
        assistant-diagrams) printf '%s\n' "Create Mermaid architecture and flow diagrams" ;;
        assistant-docs) printf '%s\n' "Generate and maintain project documentation" ;;
        assistant-ideate) printf '%s\n' "Structured idea generation and refinement" ;;
        assistant-memory) printf '%s\n' "Cross-session persistent memory" ;;
        assistant-onboard) printf '%s\n' "Systematic project orientation" ;;
        assistant-reflexion) printf '%s\n' "Post-task learning and calibration" ;;
        assistant-research) printf '%s\n' "Tiered research with source verification" ;;
        assistant-review) printf '%s\n' "Autonomous review-fix loop (max 5 rounds)" ;;
        assistant-security) printf '%s\n' "STRIDE, OWASP, CVE analysis" ;;
        assistant-skill-creator) printf '%s\n' "Create V1 framework skills" ;;
        assistant-tdd) printf '%s\n' "Red-Green-Refactor with verification gates" ;;
        assistant-telos) printf '%s\n' "Purpose and strategic context management" ;;
        assistant-thinking) printf '%s\n' "Structured reasoning for trade-offs" ;;
        *) printf '%s\n' "Installed custom skill; open SKILL.md for trigger guidance" ;;
    esac
}

build_codex_skill_table_rows() {
    local skill

    for skill in "${SKILLS[@]}"; do
        printf '| %s | %s | %s |\n' \
            "$skill" \
            "$(codex_skill_table_trigger "$skill")" \
            "$(codex_skill_table_description "$skill")"
    done
}

register_codex_memory_graph_mcp() {
    local config_file="$1"
    local mcp_command="$2"
    local memory_dir="$3"
    local python_bin=""

    if command -v python3 >/dev/null 2>&1; then
        python_bin="python3"
    elif command -v python >/dev/null 2>&1 && python -c 'import sys; raise SystemExit(0 if sys.version_info[0] >= 3 else 1)' >/dev/null 2>&1; then
        python_bin="python"
    fi

    if [[ -z "$python_bin" ]]; then
        info "WARNING: Python 3 not found — cannot safely refresh Codex MCP TOML automatically."
        info "Update $config_file manually with [mcp_servers.memory-graph], command/args, and memory tool approval blocks."
        info "  command = \"$mcp_command\""
        info "  args = [\"--memory-dir\", \"$memory_dir\"]"
        return 1
    fi

    if "$python_bin" - "$config_file" "$mcp_command" "$memory_dir" <<'PY'
import json
import os
import re
import stat
import sys

config_file, mcp_command, memory_dir = sys.argv[1:4]
tools = [
    "memory_context",
    "memory_search",
    "memory_stats",
    "memory_doctor",
    "memory_add_entity",
    "memory_add_insight",
    "memory_add_relation",
    "memory_remove_entity",
    "memory_remove_relation",
    "memory_graph",
    "memory_reflect",
    "memory_decide",
    "memory_pattern",
    "memory_consolidate",
    "memory_trend",
]


def table_name(line):
    stripped = line.strip()
    if stripped.startswith("[["):
        end = stripped.find("]]")
        if end == -1:
            return None
        name = stripped[2:end]
    elif stripped.startswith("["):
        end = stripped.find("]")
        if end == -1:
            return None
        name = stripped[1:end]
    else:
        return None

    name = re.sub(r"\s*\.\s*", ".", name.strip())
    name = name.replace('"memory-graph"', "memory-graph")
    name = name.replace("'memory-graph'", "memory-graph")
    return name


def is_memory_graph_table(name):
    return name == "mcp_servers.memory-graph" or name.startswith("mcp_servers.memory-graph.")


def split_sections(text):
    sections = []
    current = []
    for line in text.splitlines(keepends=True):
        if table_name(line) is not None:
            if current:
                sections.append(current)
            current = [line]
        else:
            current.append(line)
    if current:
        sections.append(current)
    return sections


original = ""
existing_mode = None
if os.path.exists(config_file):
    existing_mode = stat.S_IMODE(os.stat(config_file).st_mode)
    with open(config_file, "r", encoding="utf-8") as handle:
        original = handle.read()

kept_lines = []
for section in split_sections(original):
    name = table_name(section[0]) if section else None
    if name is not None and is_memory_graph_table(name):
        continue
    kept_lines.extend(section)

memory_graph_lines = [
    "[mcp_servers.memory-graph]\n",
    "command = {}\n".format(json.dumps(mcp_command)),
    "args = [\"--memory-dir\", {}]\n".format(json.dumps(memory_dir)),
]
for tool in tools:
    memory_graph_lines.extend([
        "\n",
        "[mcp_servers.memory-graph.tools.{}]\n".format(tool),
        "approval_mode = \"approve\"\n",
    ])

kept_text = "".join(kept_lines).rstrip()
memory_graph_text = "".join(memory_graph_lines)
updated = "{}\n\n{}".format(kept_text, memory_graph_text) if kept_text else memory_graph_text
if not updated.endswith("\n"):
    updated += "\n"

os.makedirs(os.path.dirname(config_file), exist_ok=True)
tmp_file = "{}.tmp".format(config_file)
with open(tmp_file, "w", encoding="utf-8") as handle:
    handle.write(updated)
if existing_mode is not None:
    os.chmod(tmp_file, existing_mode)
os.replace(tmp_file, config_file)
PY
    then
        ok "MCP server memory-graph refreshed in $config_file"
    else
        rm -f "${config_file}.tmp"
        info "WARNING: Failed to refresh MCP server in $config_file"
        return 1
    fi
}

# ── Validate ──────────────────────────────────────────────────────────────────

[[ -n "$AGENT" ]] || fail "Missing --agent. Supported: claude, codex, gemini"
[[ "$AGENT" =~ ^(claude|codex|gemini)$ ]] || fail "Unknown agent: $AGENT. Supported: claude, codex, gemini"

FRAMEWORK_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_SOURCE="$FRAMEWORK_DIR/skills"
GRAPH_SEED="$FRAMEWORK_DIR/graph-seed.jsonl"
HOOKS_SOURCE="$FRAMEWORK_DIR/hooks"

[[ -d "$SKILLS_SOURCE" ]] || fail "Skills directory not found at $SKILLS_SOURCE"

# Auto-discover first-class release skills: assistant-* directories containing SKILL.md.
while IFS= read -r skill_md; do
    skill_dir="$(dirname "$skill_md")"
    skill_name="$(basename "$skill_dir")"
    SKILLS+=("$skill_name")
done < <(find "$SKILLS_SOURCE" -maxdepth 2 -path "$SKILLS_SOURCE/assistant-*/SKILL.md" -type f | sort)
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
echo "  Legacy graph seed: $GRAPH_SEED"
echo ""

# ── Clean stale installed local-only skills ──────────────────────────────────

if [[ -z "$SINGLE_SKILL" ]]; then
    cleanup_stale_framework_unity_skills "$SKILLS_TARGET"
fi

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
            dry "Substitute .claude/ paths with .${AGENT}/ in copied $skill instruction/config files"
        fi
    else
        mkdir -p "$target_dir"
        rsync -a --delete \
            --exclude='.DS_Store' \
            "$source_dir/" "$target_dir/"

        # Swap agent.conf to the correct preset if one exists before path substitution.
        if [[ "$AGENT" != "claude" ]]; then
            agent_preset="$target_dir/agents/${AGENT}.conf"
            agent_conf="$target_dir/agent.conf"
            if [[ -f "$agent_preset" && -f "$agent_conf" ]]; then
                cp "$agent_preset" "$agent_conf"
            fi

            # Substitute agent-specific state directory paths in instruction/config files.
            # Targets values and path references, not every prose mention of Claude.
            while IFS= read -r instruction_file; do
                substitute_agent_paths_in_file "$instruction_file"
            done < <(find "$target_dir" -type f \( \
                -name "*.md" -o \
                -name "*.yaml" -o \
                -name "*.yml" -o \
                -name "*.conf" -o \
                -name "*.toml" \
            \))
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

# ── Create ~/.agents symlink for Codex (agentskills.io standard) ────────────
# Codex CLI discovers skills/agents from ~/.agents/ (agentskills.io standard).
# Create a symlink so ~/.agents/ resolves to ~/.codex/ — covers skills, agents, etc.

if [[ "$AGENT" == "codex" ]]; then
    AGENTS_SYMLINK="$HOME/.agents"
    if $DRY_RUN; then
        dry "Create symlink $AGENTS_SYMLINK -> $AGENT_HOME"
    elif [[ -L "$AGENTS_SYMLINK" ]]; then
        existing_target=$(readlink "$AGENTS_SYMLINK")
        if [[ "$existing_target" == "$AGENT_HOME" ]]; then
            info "~/.agents symlink already points to $AGENT_HOME"
        else
            info "~/.agents symlink exists but points to $existing_target — skipping"
        fi
    elif [[ -d "$AGENTS_SYMLINK" ]]; then
        info "~/.agents directory already exists — skipping symlink (check for conflicts)"
    else
        ln -s "$AGENT_HOME" "$AGENTS_SYMLINK"
        ok "Created ~/.agents -> $AGENT_HOME symlink for agentskills.io discovery"
    fi
fi

# ── Install tools ────────────────────────────────────────────────────────────

TOOLS_SOURCE="$FRAMEWORK_DIR/tools"
TOOLS_TARGET="$AGENT_HOME/tools"

if [[ -d "$TOOLS_SOURCE" ]]; then
    echo ""
    if $DRY_RUN; then
        dry "rsync $TOOLS_SOURCE/ -> $TOOLS_TARGET/"
        cleanup_installed_tool_build_artifacts "$TOOLS_TARGET"
    else
        mkdir -p "$TOOLS_TARGET"
        rsync -a --delete \
            --exclude='.DS_Store' \
            --exclude='.publish' \
            --exclude='bin' \
            --exclude='obj' \
            "$TOOLS_SOURCE/" "$TOOLS_TARGET/"
        cleanup_installed_tool_build_artifacts "$TOOLS_TARGET"

        # Make scripts executable
        if compgen -G "$TOOLS_TARGET"/*/*.sh >/dev/null 2>&1; then
            chmod +x "$TOOLS_TARGET"/*/*.sh
        fi

        ok "Tools -> $TOOLS_TARGET/"
    fi
fi

# ── Install eval fixtures/docs used by local tools ───────────────────────────

EVAL_DOCS_SOURCE="$FRAMEWORK_DIR/docs/evals"
EVAL_DOCS_TARGET="$AGENT_HOME/docs/evals"

if [[ -d "$EVAL_DOCS_SOURCE" ]]; then
    echo ""
    if $DRY_RUN; then
        dry "rsync $EVAL_DOCS_SOURCE/ -> $EVAL_DOCS_TARGET/"
    else
        mkdir -p "$EVAL_DOCS_TARGET"
        rsync -a --delete \
            --exclude='.DS_Store' \
            "$EVAL_DOCS_SOURCE/" "$EVAL_DOCS_TARGET/"

        ok "Eval docs -> $EVAL_DOCS_TARGET/"
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
            dry "Refresh memory-graph MCP server in $CODEX_CONFIG"
        else
            register_codex_memory_graph_mcp "$CODEX_CONFIG" "$MCP_COMMAND" "$MCP_MEMORY_DIR" || true
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

# ── Seed legacy graph import compatibility (only if graph.jsonl doesn't exist) ─

echo ""
GRAPH_TARGET="$MEMORY_TARGET/graph.jsonl"
if [[ -f "$GRAPH_TARGET" ]]; then
    info "Legacy graph compatibility data already exists at $GRAPH_TARGET — skipping (never overwrite)"
else
    if [[ -f "$GRAPH_SEED" ]]; then
        if $DRY_RUN; then
            dry "cp $GRAPH_SEED -> $GRAPH_TARGET (legacy import compatibility, first install only)"
        else
            mkdir -p "$MEMORY_TARGET"
            cp "$GRAPH_SEED" "$GRAPH_TARGET"
            ok "Legacy graph seed installed to $GRAPH_TARGET for import compatibility"
        fi
    else
        info "No legacy graph seed found — skipping"
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

# ── Install Codex execution policy rules ─────────────────────────────────
# Starlark .rules files provide DETERMINISTIC enforcement (system-level, not prompt-level).
# These block/prompt on dangerous commands regardless of what the LLM decides.

RULES_SOURCE="$FRAMEWORK_DIR/codex-rules"

if [[ "$AGENT" == "codex" && -d "$RULES_SOURCE" ]]; then
    echo ""
    RULES_TARGET="$AGENT_HOME/rules"

    shopt -s nullglob
    rules_files=("$RULES_SOURCE/"*.rules)
    shopt -u nullglob

    if [[ ${#rules_files[@]} -eq 0 ]]; then
        info "No .rules files found in $RULES_SOURCE/ — skipping"
    elif $DRY_RUN; then
        for rf in "${rules_files[@]}"; do
            dry "Install rule: $(basename "$rf") -> $RULES_TARGET/"
        done
    else
        mkdir -p "$RULES_TARGET"
        for rf in "${rules_files[@]}"; do
            cp "$rf" "$RULES_TARGET/"
        done
        ok "Execution policy rules -> $RULES_TARGET/ (${#rules_files[@]} rules)"
    fi

    # Ensure codex_hooks feature flag is enabled in config.toml
    CODEX_CONFIG="$AGENT_HOME/config.toml"
    if $DRY_RUN; then
        dry "Ensure codex_hooks = true in $CODEX_CONFIG"
    else
        if [[ ! -f "$CODEX_CONFIG" ]]; then
            mkdir -p "$(dirname "$CODEX_CONFIG")"
            cat > "$CODEX_CONFIG" <<'TOML'
# Codex CLI configuration — managed by Assistant Framework installer
[features]
codex_hooks = true
TOML
            ok "Created $CODEX_CONFIG with codex_hooks enabled"
        elif ! grep -q 'codex_hooks' "$CODEX_CONFIG" 2>/dev/null; then
            # Add codex_hooks — check if [features] section already exists
            if grep -q '^\[features\]' "$CODEX_CONFIG" 2>/dev/null; then
                # Append under existing [features] section (avoid duplicate TOML header)
                sed -i.bak '/^\[features\]/a\
codex_hooks = true' "$CODEX_CONFIG"
                rm -f "${CODEX_CONFIG}.bak"
            else
                # No [features] section yet — add one
                {
                    echo ""
                    echo "[features]"
                    echo "codex_hooks = true"
                } >> "$CODEX_CONFIG"
            fi
            ok "Enabled codex_hooks in $CODEX_CONFIG"
        elif grep -q 'codex_hooks.*=.*false' "$CODEX_CONFIG" 2>/dev/null; then
            sed -i.bak 's/codex_hooks.*=.*false/codex_hooks = true/' "$CODEX_CONFIG"
            rm -f "${CODEX_CONFIG}.bak"
            ok "Switched codex_hooks to true in $CODEX_CONFIG"
        else
            info "codex_hooks already enabled in $CODEX_CONFIG"
        fi
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
        codex)
            # Codex CLI has experimental hooks support (codex_hooks feature flag).
            # Hooks are read from hooks.json (not settings.json).
            HOOKS_SETTINGS="$HOOKS_SOURCE/codex-settings.json"
            CODEX_HOOKS=true
            ;;
    esac

    if [[ -n "$HOOKS_SETTINGS" && -f "$HOOKS_SETTINGS" ]]; then
        if $DRY_RUN; then
            dry "Copy hook scripts to $HOOKS_TARGET/"
            if [[ "${CODEX_HOOKS:-}" == "true" ]]; then
                dry "Merge hook configuration into $AGENT_HOME/hooks.json"
            else
                dry "Merge hook configuration into $SETTINGS_FILE"
            fi
        else
            # Copy hook scripts
            mkdir -p "$HOOKS_TARGET"
            if compgen -G "$HOOKS_SOURCE/scripts/*.sh" >/dev/null; then
                for hook_script in "$HOOKS_SOURCE/scripts/"*.sh; do
                    hook_name="$(basename "$hook_script")"
                    # Codex experimental hooks: SessionStart, UserPromptSubmit, Stop, PreToolUse.
                    if [[ "$AGENT" == "codex" ]]; then
                        case "$hook_name" in
                            session-start.sh|skill-router.sh|stop-review.sh|harness-gate.sh|learning-signals.sh|workflow-enforcer.sh|workflow-guard.sh|task-journal-resolver.sh) ;;  # supported + shared helper dependency
                            *) continue ;;  # skip unsupported hooks
                        esac
                    fi
                    # post-compact.sh and subagent-monitor.sh are Claude-only
                    if [[ "$AGENT" != "claude" ]]; then
                        case "$hook_name" in
                            post-compact.sh|subagent-monitor.sh) continue ;;
                        esac
                    fi
                    # task-completed.sh is Claude-only (Gemini has no TaskCompleted event)
                    if [[ "$AGENT" == "gemini" && "$hook_name" == "task-completed.sh" ]]; then
                        continue
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

            # Codex: write hooks.json (separate file, not settings.json)
            if [[ "${CODEX_HOOKS:-}" == "true" ]]; then
                CODEX_HOOKS_FILE="$AGENT_HOME/hooks.json"
                if [[ -f "$CODEX_HOOKS_FILE" ]] && command -v jq &>/dev/null; then
                    # Merge with existing hooks.json
                    existing_hooks=$(jq '
                        def assistant_framework_codex_hook_names:
                            [
                                "session-start.sh",
                                "skill-router.sh",
                                "learning-signals.sh",
                                "workflow-enforcer.sh",
                                "workflow-guard.sh",
                                "stop-review.sh",
                                "harness-gate.sh",
                                "subagent-monitor.sh",
                                "post-compact.sh",
                                "pre-compress.sh",
                                "session-end.sh",
                                "post-tool-context.sh",
                                "tool-failure-advisor.sh",
                                "task-completed.sh",
                                "task-journal-resolver.sh"
                            ];
                        def first_shell_token:
                            (gsub("^\\s+"; "") | gsub("\\s+"; " ") | split(" ") | .[0] // "");
                        def assistant_framework_codex_hook_command:
                            (. // "") as $command
                            | ($command | first_shell_token) as $token
                            | any(assistant_framework_codex_hook_names[]; . as $hook_name |
                                $token == ("$HOME/.codex/hooks/assistant/" + $hook_name)
                                or ($token | endswith("/.codex/hooks/assistant/" + $hook_name))
                                or ($token | endswith("/hooks/scripts/" + $hook_name))
                            );
                        (.hooks // {})
                        | with_entries(
                            .value = (
                                (.value | if type == "array" then . else [.] end)
                                | map(
                                    .hooks = (
                                        (.hooks // [])
                                        | map(select(((.command // "") | assistant_framework_codex_hook_command) | not))
                                    )
                                )
                                | map(select((.hooks // []) | length > 0))
                            )
                        )
                        | with_entries(select((.value // []) | length > 0))
                    ' "$CODEX_HOOKS_FILE" 2>/dev/null || echo '{}')
                    new_hooks=$(jq '.hooks' "$HOOKS_SETTINGS")
                    merged=$(jq -n --argjson a "$existing_hooks" --argjson b "$new_hooks" '
                        def arrayify:
                            if type == "array" then . else [.] end;
                        def unique_commands:
                            reduce .[] as $hook ({seen: {}, out: []};
                                ($hook.command? // "") as $command
                                | if $command == "" then
                                    .out += [$hook]
                                elif .seen[$command] then
                                    .
                                else
                                    .seen[$command] = true | .out += [$hook]
                                end
                            ) | .out;
                        def merge_matcher_groups:
                            reduce .[] as $group ({seen: {}, out: []};
                                ($group | .hooks = ((.hooks // []) | arrayify | unique_commands)) as $normalized
                                | ($normalized.matcher // "") as $matcher
                                | if (($normalized.hooks // []) | length) == 0 then
                                    .
                                elif .seen[$matcher] == null then
                                    .seen[$matcher] = (.out | length) | .out += [$normalized]
                                else
                                    .out[.seen[$matcher]].hooks = ((.out[.seen[$matcher]].hooks + $normalized.hooks) | unique_commands)
                                end
                            ) | .out;
                        ($a | keys) + ($b | keys) | unique | map(
                            . as $k |
                            {key: $k, value: ([
                                ($a[$k] // [] | if type == "array" then . else [.] end),
                                ($b[$k] // [] | if type == "array" then . else [.] end)
                            ] | add | merge_matcher_groups)}
                        ) | from_entries
                    ')
                    if jq -n --argjson hooks "$merged" '{hooks: $hooks}' > "${CODEX_HOOKS_FILE}.tmp" \
                        && mv "${CODEX_HOOKS_FILE}.tmp" "$CODEX_HOOKS_FILE"; then
                        ok "Hooks merged into $CODEX_HOOKS_FILE"
                    else
                        rm -f "${CODEX_HOOKS_FILE}.tmp"
                        info "WARNING: Failed to merge hooks into $CODEX_HOOKS_FILE"
                    fi
                else
                    cp "$HOOKS_SETTINGS" "$CODEX_HOOKS_FILE"
                    ok "Created $CODEX_HOOKS_FILE (requires codex_hooks feature flag)"
                fi
                info "NOTE: Enable experimental hooks in ~/.codex/config.toml:"
                info "  [features]"
                info "  codex_hooks = true"
            # Claude/Gemini: merge hooks into settings.json
            elif [[ -f "$SETTINGS_FILE" ]]; then
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

# ── Generate AGENTS.md for Codex (it reads AGENTS.md, not CLAUDE.md) ────────
# Must run before memory protocol section since protocol is appended to AGENTS.md

AGENTS_MD_MARKER_START="ASSISTANT_FRAMEWORK_AGENTS_MD_START"
AGENTS_MD_MARKER_END="ASSISTANT_FRAMEWORK_AGENTS_MD_END"

if [[ "$AGENT" == "codex" ]]; then
    AGENTS_MD="$AGENT_HOME/AGENTS.md"
    AGENTS_SKILL_ROWS="$(build_codex_skill_table_rows)"
    echo ""

    # Build the installer-owned content block (wrapped in markers)
    #
    # DESIGN: This AGENTS.md uses three enforcement techniques from research:
    # 1. XML behavioral_rules block — parses more reliably than markdown for rules
    # 2. Recursive self-display — rule 6 requires restating phase, keeping rules in context
    # 3. Concise structure — long instruction files get selectively ignored; stay under 4K
    #
    AGENTS_MD_CONTENT="<!-- $AGENTS_MD_MARKER_START -->
# AGENTS.md — Codex Agent Instructions

## Role

You are an orchestrator for development work. Coordinate specialized agents (code-writer, builder-tester, architect, explorer, reviewer), keep phase gates visible, and communicate progress. File edits, code implementation, builds/tests, and independent review are owned by those specialized agents; gather context, clarify requirements, decompose work, and prepare handoffs yourself when that does not modify files. Follow matching skill instructions, phase gates, and review loops exactly. When a skill matches your task, invoke it instead of replacing it with ad hoc steps.

<behavioral_rules>
These rules define the operating contract for every response.

1. SKILL ROUTING: Before acting on ANY request, check if it matches an installed skill in ~/.codex/skills/. When a skill matches, load and follow the skill's SKILL.md before proceeding; use the skill workflow as the source of truth.

2. ORCHESTRATOR OWNERSHIP: Coordinate the work; keep file edits and code implementation with code-writer, builds/tests with builder-tester, and independent review with reviewer. The orchestrator does not edit files or write code directly.

3. PHASE GATES: Development follows phases: TRIAGE -> DISCOVER -> DECOMPOSE when needed -> PLAN -> DESIGN when needed -> BUILD -> REVIEW -> DOCUMENT. You MUST NOT skip phases. Small tasks use lightweight phases, but NEVER skip entirely.

4. PLAN BEFORE BUILD: For medium+ tasks, you MUST have an approved plan before writing implementation code. Present the plan, wait for approval, THEN build.

5. TESTS WITH FEATURES: Every new component or feature MUST have tests in the SAME step. Include the test with the implementation work.

6. REVIEW IS A LOOP: After code changes, run the review cycle: review -> fix -> re-review -> fix -> re-review until clean (max 5 rounds). Continue until the review is clean or the max round is reached.

7. STATE YOUR PHASE: Before every response that involves code work, state your current workflow phase. This is mandatory — it keeps you on track.
</behavioral_rules>

## Skills (loaded from ~/.codex/skills/)

| Skill | Trigger | What it does |
|-------|---------|-------------|
$AGENTS_SKILL_ROWS

## Agents (in ~/.codex/agents/)

| Agent | Access | Role |
|-------|--------|------|
| code-mapper | read-only | Map project structure and entry points |
| explorer | read-only | Trace execution paths, understand architecture |
| architect | read-only | Design implementation blueprints |
| code-writer | write | Implement code following a plan |
| builder-tester | write | Build, write tests, run tests |
| reviewer | read-only | Independent code review, confidence-filtered |

## Memory

- Global: memory-graph MCP backed by ~/.codex/memory (local memory store)
- Project state: .codex/session.md, .codex/working-buffer.md, and .codex/task.md at project root
- Rules and preferences are retrieved at session start via memory_context; hooks do not inject rule bodies.

## Conventions

- C# on modern .NET; respect existing repo style
- Clean Architecture; dependency inversion
- Never hardcode secrets; never log PII
- Tests: Arrange-Act-Assert, descriptive naming
<!-- $AGENTS_MD_MARKER_END -->"

    if $DRY_RUN; then
        dry "Would generate/update $AGENTS_MD from installed skills"
    elif [[ -f "$AGENTS_MD" ]] && grep -q "$AGENTS_MD_MARKER_START" "$AGENTS_MD" 2>/dev/null; then
        # Re-install: strip old installer block, preserve user content
        sed -i.bak "/$AGENTS_MD_MARKER_START/,/$AGENTS_MD_MARKER_END/d" "$AGENTS_MD"
        rm -f "${AGENTS_MD}.bak"
        # Prepend installer block (it should come first)
        { echo "$AGENTS_MD_CONTENT"; echo ""; cat "$AGENTS_MD"; } > "${AGENTS_MD}.tmp" \
            && mv "${AGENTS_MD}.tmp" "$AGENTS_MD"
        ok "Updated installer section in $AGENTS_MD (user customizations preserved)"
    elif [[ -f "$AGENTS_MD" ]]; then
        # Existing file without markers — prepend installer block, keep user content
        { echo "$AGENTS_MD_CONTENT"; echo ""; cat "$AGENTS_MD"; } > "${AGENTS_MD}.tmp" \
            && mv "${AGENTS_MD}.tmp" "$AGENTS_MD"
        ok "Prepended installer section to existing $AGENTS_MD (user content preserved)"
    else
        # First install
        echo "$AGENTS_MD_CONTENT" > "$AGENTS_MD"
        ok "Generated $AGENTS_MD"
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
        # Codex reads AGENTS.md natively — memory protocol is appended there
        INSTRUCTIONS_FILE="$AGENT_HOME/AGENTS.md"
        ;;
esac

if [[ -f "$MEMORY_PROTOCOL_SOURCE" ]]; then
    echo ""

    MARKER_END="ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END"

    # Prepare substituted protocol content
    protocol_content=$(substitute_agent_paths_in_stream < "$MEMORY_PROTOCOL_SOURCE")

    # Strip old protocol if present (replace with latest version). Legacy installs
    # placed the title/role preamble before the start marker; strip that preamble
    # only when it is immediately tied to an installer-owned marker block.
    if [[ -f "$INSTRUCTIONS_FILE" ]] && grep -q "$MARKER" "$INSTRUCTIONS_FILE" 2>/dev/null; then
        if $DRY_RUN; then
            dry "Would update memory protocol in $INSTRUCTIONS_FILE"
        else
            strip_memory_protocol_from_file "$INSTRUCTIONS_FILE" "$MARKER" "$MARKER_END"
            echo "" >> "$INSTRUCTIONS_FILE"
            echo "$protocol_content" >> "$INSTRUCTIONS_FILE"
            ok "Memory protocol updated in $INSTRUCTIONS_FILE"
        fi
    elif [[ -f "$INSTRUCTIONS_FILE" ]] && grep -q "WAL Protocol\|Persistent Memory System" "$INSTRUCTIONS_FILE" 2>/dev/null; then
        info "WARNING: $INSTRUCTIONS_FILE contains a manually-added memory protocol — not replacing."
        info "Remove the 'Persistent Memory System' section manually, then re-run install to get the latest."
    elif [[ "$AGENT" == "codex" ]]; then
        # Codex: we own AGENTS.md entirely — always append without prompting
        if $DRY_RUN; then
            dry "Would append memory protocol to $INSTRUCTIONS_FILE"
        else
            echo "" >> "$INSTRUCTIONS_FILE"
            echo "$protocol_content" >> "$INSTRUCTIONS_FILE"
            ok "Memory protocol appended to $INSTRUCTIONS_FILE"
        fi
    elif $DRY_RUN; then
        dry "Would append memory protocol to $INSTRUCTIONS_FILE"
    else
        # Claude/Gemini first install — ask for confirmation (modifying user's own file)
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
if [[ "$AGENT" == "codex" && ${#toml_files[@]} -gt 0 ]]; then
    echo ""
    echo "Agents: $AGENT_HOME/agents/"
    for toml in "${toml_files[@]}"; do
        echo "  $(basename "$toml" .toml)"
    done
fi
if [[ "$AGENT" == "claude" && ${#md_files[@]} -gt 0 ]]; then
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
        echo "  (Codex: SessionStart, UserPromptSubmit, Stop, PreToolUse — 4 events, 7 hook commands)"
        echo "  Enforcement: skill-router + workflow-enforcer + workflow-guard + stop-review + harness-gate"
    fi
fi
if [[ "$AGENT" == "codex" && -d "$RULES_SOURCE" ]]; then
    echo ""
    echo "Execution rules: $AGENT_HOME/rules/"
    echo "  (Starlark policy: git push/commit guards, destructive op confirmation)"
fi
echo ""
echo "Memory store: $MEMORY_TARGET/"
echo "Legacy graph seed/import compatibility: $MEMORY_TARGET/graph.jsonl"
echo ""
if [[ -n "$SINGLE_SKILL" ]]; then
    echo "To install all skills: ./install.sh --agent $AGENT"
else
    echo "To install a single skill: ./install.sh --agent $AGENT --skill <name>"
    echo "To skip hooks: ./install.sh --agent $AGENT --no-hooks"
fi
