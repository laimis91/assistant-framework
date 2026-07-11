#!/usr/bin/env bash
# install.sh — Installs all Assistant Framework skills for any supported AI agent.
#
# Auto-discovers first-class release skills from skills/assistant-*/SKILL.md.
# Also installs legacy graph seed/import compatibility data and performs one
# release of cleanup for retired Assistant Framework hook registrations.
#
# Usage:
#   ./install.sh --agent claude     # → ~/.claude/skills/assistant-*/
#   ./install.sh --agent codex      # → ~/.codex/skills/assistant-*/
#   ./install.sh --agent gemini     # → ~/.gemini/skills/assistant-*/
#   ./install.sh --agent claude --dry-run
#   ./install.sh --agent claude --skill assistant-workflow  # single skill only
#   ./install.sh --agent codex --plugin assistant-core      # core profile only
#   ./install.sh --agent codex --plugin assistant-research  # research profile only
#   ./install.sh --agent codex --plugin assistant-dev       # development profile only
#   ./install.sh --agent codex                              # native, hookless behavior
#   ./install.sh --agent claude --no-hooks                  # deprecated compatibility no-op
#
# Legacy graph seed compatibility data is installed to ~/.{agent}/memory/graph.jsonl
# only if it doesn't already exist — existing legacy data is never overwritten.

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────

AGENT=""
DRY_RUN=false
SINGLE_SKILL=""
PLUGIN_PROFILE=""
FRAMEWORK_DIR=""
toml_files=()

# Skills are auto-discovered from first-class assistant-* release directories.
SKILLS=()

# ── Parse args ────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Installs the Assistant Framework skills for an AI agent.

Options:
  --agent NAME       Target agent: claude, codex, gemini (required)
  --skill NAME       Install only one skill (default: all)
  --plugin NAME      Install a planned plugin profile such as assistant-core, assistant-research, or assistant-dev
  --no-hooks         Deprecated compatibility no-op; all installs are hookless
  --dry-run          Show what would be done without doing it
  -h, --help         Show this help

Note: skill installation uses rsync --delete, which removes any files you
added manually to installed skill directories. Back up customizations first.

Skills installed:
  Auto-discovered from skills/assistant-*/SKILL.md.
  Use --plugin assistant-core, --plugin assistant-research, or --plugin assistant-dev to install a focused profile.

Memory data:
  memory-graph MCP is registered against ~/.{agent}/memory.
  Legacy graph seed/import compatibility data is installed on first install only.
  Existing legacy graph data is never overwritten.

Examples:
  $(basename "$0") --agent claude
  $(basename "$0") --agent codex --dry-run
  $(basename "$0") --agent claude --skill assistant-thinking
  $(basename "$0") --agent claude --no-hooks
  $(basename "$0") --agent codex --plugin assistant-core
  $(basename "$0") --agent codex --plugin assistant-research
  $(basename "$0") --agent codex --plugin assistant-dev
EOF
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --agent)    [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; AGENT="$2"; shift 2 ;;
        --skill)    [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; SINGLE_SKILL="$2"; shift 2 ;;
        --plugin)   [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; PLUGIN_PROFILE="$2"; shift 2 ;;
        --no-hooks)   echo "WARNING: --no-hooks is deprecated; all Assistant Framework installs are hookless." >&2; shift ;;
        --dry-run)    DRY_RUN=true; shift ;;
        -h|--help)  usage 0 ;;
        *)          echo "Unknown option: $1" >&2; usage 2 ;;
    esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────

fail() { echo "Error: $1" >&2; exit 1; }
info() { echo "  $1"; }
ok()   { echo "  OK: $1"; }
dry()  { echo "  [dry-run] $1"; }

metadata_preserving_temp() {
    local source_file="$1"
    local temp_file

    temp_file="$(mktemp "${source_file}.tmp.XXXXXX")" || return 1
    if ! cp -p "$source_file" "$temp_file"; then
        rm -f "$temp_file"
        return 1
    fi
    printf '%s\n' "$temp_file"
}

# Canonical union of commands directly registered by released Assistant
# Framework hook settings. Keep this cleanup inventory for one compatibility
# release after hook retirement so plain installs can remove stale registrations.
legacy_framework_hook_entrypoints() {
    printf '%s\n' \
        session-start.sh \
        skill-router.sh \
        learning-signals.sh \
        workflow-enforcer.sh \
        workflow-guard.sh \
        stop-review.sh \
        harness-gate.sh \
        subagent-monitor.sh \
        pre-compress.sh \
        post-compact.sh \
        session-end.sh \
        post-tool-context.sh \
        tool-failure-advisor.sh \
        task-completed.sh
}

# Internal helpers were never direct lifecycle entrypoints and must not receive
# cached shims. They are still recognized as retired framework commands.
legacy_framework_hook_helpers() {
    printf '%s\n' \
        task-journal-resolver.sh \
        workflow-phase-gates.sh \
        hook-runtime.sh
}

legacy_framework_hook_modules() {
    printf '%s\n' \
        workflow-phase-gates.d/learning-controller.sh \
        workflow-phase-gates.d/metrics.sh \
        workflow-phase-gates.d/qa-controller.sh \
        workflow-phase-gates.d/review-controller.sh \
        workflow-phase-gates.d/subagent-evidence.sh \
        workflow-phase-gates.d/subagent-orchestration.sh \
        workflow-guard.d/path-policy.sh \
        workflow-guard.d/shell-write-parser.sh \
        workflow-guard.d/workflow-state-artifacts.sh
}

legacy_framework_hook_files_exist() {
    local hooks_target="$1"
    local relative_path

    while IFS= read -r relative_path; do
        [[ -n "$relative_path" ]] || continue
        [[ -e "$hooks_target/$relative_path" ]] && return 0
    done < <({ legacy_framework_hook_entrypoints; legacy_framework_hook_helpers; legacy_framework_hook_modules; })

    return 1
}

remove_legacy_framework_hook_helpers() {
    local hooks_target="$1"
    local relative_path

    while IFS= read -r relative_path; do
        [[ -n "$relative_path" ]] || continue
        rm -f "$hooks_target/$relative_path"
    done < <({ legacy_framework_hook_helpers; legacy_framework_hook_modules; })

    rmdir "$hooks_target/workflow-phase-gates.d" "$hooks_target/workflow-guard.d" 2>/dev/null || true
}

write_legacy_framework_hook_shims() {
    local hooks_target="$1"
    local entrypoint

    mkdir -p "$hooks_target"
    while IFS= read -r entrypoint; do
        [[ -n "$entrypoint" ]] || continue
        printf '%s\n' \
            '#!/usr/bin/env bash' \
            '# Assistant Framework retired-hook compatibility shim.' \
            'exit 0' > "$hooks_target/$entrypoint"
        chmod +x "$hooks_target/$entrypoint"
    done < <(legacy_framework_hook_entrypoints)
}

cleanup_legacy_framework_hooks() {
    local settings_file="$1"
    local hooks_target="$2"
    local agent="$3"
    local framework_hooks_dir="$FRAMEWORK_DIR/hooks/scripts"
    local entrypoints helpers known_names
    local legacy_detected=false
    local removed_count=0
    local python_result=""
    local temp_settings=""

    entrypoints="$(legacy_framework_hook_entrypoints)"
    helpers="$(legacy_framework_hook_helpers)"
    known_names="$(printf '%s\n%s\n' "$entrypoints" "$helpers")"

    if legacy_framework_hook_files_exist "$hooks_target"; then
        legacy_detected=true
    fi

    if [[ -f "$settings_file" ]]; then
        if command -v jq >/dev/null 2>&1; then
            if ! jq -e 'type == "object" and ((.hooks? // {}) | type == "object")' "$settings_file" >/dev/null 2>&1; then
                info "WARNING: Invalid settings JSON in $settings_file; preserved unchanged while stale hook files were neutralized."
            else
                removed_count="$(jq -r \
                    --arg agent "$agent" \
                    --arg hooks_target "$hooks_target" \
                    --arg framework_hooks_dir "$framework_hooks_dir" \
                    --arg known_names "$known_names" '
                    def as_array: if type == "array" then . else [.] end;
                    def first_shell_token:
                        if type != "string" then ""
                        else (gsub("^\\s+"; "") | gsub("\\s+"; " ") | split(" ") | .[0] // "")
                        end;
                    ($known_names | split("\n") | map(select(length > 0))) as $known
                    | (.hooks // {})
                    | [
                        to_entries[]?.value
                        | as_array[]?
                        | select(type == "object")
                        | (.hooks // [] | as_array[]?)
                        | select(type == "object")
                        | .command?
                        | first_shell_token as $token
                        | select(any($known[]; . as $name |
                            $token == ("$HOME/." + $agent + "/hooks/assistant/" + $name)
                            or $token == ($hooks_target + "/" + $name)
                            or $token == ($framework_hooks_dir + "/" + $name)
                        ))
                    ] | length
                ' "$settings_file")"

                if (( removed_count > 0 )); then
                    legacy_detected=true
                    temp_settings="$(metadata_preserving_temp "$settings_file")" \
                        || fail "Failed to create a metadata-preserving temporary file beside $settings_file"
                    if ! jq \
                        --arg agent "$agent" \
                        --arg hooks_target "$hooks_target" \
                        --arg framework_hooks_dir "$framework_hooks_dir" \
                        --arg known_names "$known_names" '
                        def as_array: if type == "array" then . else [.] end;
                        def first_shell_token:
                            if type != "string" then ""
                            else (gsub("^\\s+"; "") | gsub("\\s+"; " ") | split(" ") | .[0] // "")
                            end;
                        def assistant_framework_command:
                            (. // "") | first_shell_token as $token
                            | ($known_names | split("\n") | map(select(length > 0))) as $known
                            | any($known[]; . as $name |
                                $token == ("$HOME/." + $agent + "/hooks/assistant/" + $name)
                                or $token == ($hooks_target + "/" + $name)
                                or $token == ($framework_hooks_dir + "/" + $name)
                            );
                        .hooks = (
                            (.hooks // {})
                            | with_entries(
                                .value = (
                                    (.value | as_array)
                                    | map(
                                        if type == "object" then
                                            .hooks = (
                                                (.hooks // [] | as_array)
                                                | map(select(
                                                    type != "object"
                                                    or (((.command // "") | assistant_framework_command) | not)
                                                ))
                                            )
                                        else . end
                                    )
                                    | map(select(type != "object" or ((.hooks // []) | length > 0)))
                                )
                            )
                            | with_entries(select((.value // []) | length > 0))
                        )
                    ' "$settings_file" > "$temp_settings"; then
                        rm -f "$temp_settings"
                        fail "Failed to remove retired Assistant Framework commands from $settings_file"
                    fi
                    mv "$temp_settings" "$settings_file"
                fi
            fi
        elif command -v python3 >/dev/null 2>&1; then
            python_result="$(python3 - "$settings_file" "$agent" "$hooks_target" "$framework_hooks_dir" "$known_names" <<'PY'
import json
import os
import re
import stat
import sys
import tempfile

settings_file, agent, hooks_target, framework_hooks_dir, known_names_text = sys.argv[1:6]
known_names = set(known_names_text.splitlines())

def as_list(value):
    if value is None:
        return []
    return value if isinstance(value, list) else [value]

def first_shell_token(command):
    if not isinstance(command, str):
        return ""
    command = command.strip()
    if not command:
        return ""
    return re.sub(r"\s+", " ", command).split(" ")[0]

def is_framework_command(command):
    token = first_shell_token(command)
    return any(
        token == f"$HOME/.{agent}/hooks/assistant/{name}"
        or token == f"{hooks_target}/{name}"
        or token == f"{framework_hooks_dir}/{name}"
        for name in known_names
    )

try:
    with open(settings_file, "r", encoding="utf-8") as stream:
        output = json.load(stream)
except Exception:
    print("INVALID")
    raise SystemExit(0)

if not isinstance(output, dict):
    print("INVALID")
    raise SystemExit(0)

hooks_object = output.get("hooks", {})
if hooks_object is None:
    hooks_object = {}
elif not isinstance(hooks_object, dict):
    print("INVALID")
    raise SystemExit(0)

removed = 0
cleaned_hooks = {}
for event, groups in hooks_object.items():
    kept_groups = []
    for group in as_list(groups):
        if not isinstance(group, dict):
            kept_groups.append(group)
            continue
        kept_hooks = []
        for hook in as_list(group.get("hooks")):
            if isinstance(hook, dict) and is_framework_command(hook.get("command")):
                removed += 1
            else:
                kept_hooks.append(hook)
        if kept_hooks:
            kept_group = dict(group)
            kept_group["hooks"] = kept_hooks
            kept_groups.append(kept_group)
    if kept_groups:
        cleaned_hooks[event] = kept_groups

if removed:
    output["hooks"] = cleaned_hooks
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=os.path.dirname(settings_file),
        prefix=".assistant-framework-retire.",
        delete=False,
    ) as stream:
        temp_file = stream.name
        json.dump(output, stream, indent=2)
        stream.write("\n")
    os.chmod(temp_file, stat.S_IMODE(os.stat(settings_file).st_mode))
    os.replace(temp_file, settings_file)

print(removed)
PY
)"
            if [[ "$python_result" == "INVALID" ]]; then
                info "WARNING: Invalid settings JSON in $settings_file; preserved unchanged while stale hook files were neutralized."
            elif [[ "$python_result" =~ ^[0-9]+$ ]] && (( python_result > 0 )); then
                legacy_detected=true
            fi
        else
            info "WARNING: Cannot inspect $settings_file without jq or python3; preserved unchanged."
        fi
    fi

    if [[ "$legacy_detected" == "true" ]]; then
        remove_legacy_framework_hook_helpers "$hooks_target"
        write_legacy_framework_hook_shims "$hooks_target"
        ok "Retired hook registrations removed for $agent; cached entrypoints replaced with inert shims"
    fi
}

plugin_profile_line() {
    local plugin_name="$1"
    local plugin_doc="$FRAMEWORK_DIR/docs/plugin-architecture.md"

    [[ -f "$plugin_doc" ]] || return 1

    awk -v plugin_name="$plugin_name" '
        /^PLUGIN_BOUNDARY_START$/ { inside = 1; next }
        /^PLUGIN_BOUNDARY_END$/ { inside = 0; next }
        inside && index($0, plugin_name ":") == 1 {
            print
            found = 1
            exit
        }
        END { exit found ? 0 : 1 }
    ' "$plugin_doc"
}

plugin_manifest_path() {
    local plugin_name="$1"
    printf '%s/plugins/%s/.codex-plugin/plugin.json\n' "$FRAMEWORK_DIR" "$plugin_name"
}

skill_in_active_profile() {
    local candidate="$1"
    local selected_skill

    for selected_skill in "${SKILLS[@]}"; do
        [[ "$candidate" == "$selected_skill" ]] && return 0
    done

    return 1
}

validate_plugin_manifest_dry_run() {
    local plugin_name="$1"
    local manifest_path
    local manifest_name
    local manifest_skills
    local plugin_skills_root
    local profile_skill
    local plugin_skill_file
    local plugin_skill

    manifest_path="$(plugin_manifest_path "$plugin_name")"

    [[ -f "$manifest_path" ]] || fail "Plugin manifest $plugin_name not found at $manifest_path"
    command -v jq >/dev/null 2>&1 || fail "jq is required to validate plugin manifest dry-run for $plugin_name."

    manifest_name="$(jq -r '.name // ""' "$manifest_path")" || fail "Plugin manifest $plugin_name is not valid JSON: $manifest_path"
    manifest_skills="$(jq -r '.skills // ""' "$manifest_path")" || fail "Plugin manifest $plugin_name is not valid JSON: $manifest_path"

    [[ "$manifest_name" == "$plugin_name" ]] || fail "Plugin manifest $plugin_name must declare name: $plugin_name"
    [[ "$manifest_skills" == "./skills/" ]] || fail "Plugin manifest $plugin_name must declare skills: ./skills/"

    plugin_skills_root="$FRAMEWORK_DIR/plugins/$plugin_name/${manifest_skills#./}"
    plugin_skills_root="${plugin_skills_root%/}"
    [[ -d "$plugin_skills_root" ]] || fail "Plugin manifest $plugin_name skills directory not found: $plugin_skills_root"

    for profile_skill in "${SKILLS[@]}"; do
        [[ -f "$plugin_skills_root/$profile_skill/SKILL.md" ]] || fail "Plugin manifest $plugin_name missing skill copy: $profile_skill"
    done

    while IFS= read -r plugin_skill_file; do
        plugin_skill="$(basename "$(dirname "$plugin_skill_file")")"
        skill_in_active_profile "$plugin_skill" || fail "Plugin manifest $plugin_name includes skill outside profile boundary: $plugin_skill"
    done < <(find "$plugin_skills_root" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print | sort)

    dry "Validate plugin manifest: $plugin_name -> $manifest_skills"
    dry "Plugin manifest skills match profile boundary: ${SKILLS[*]}"
}

supported_plugin_profiles() {
    printf '%s\n' assistant-core assistant-research assistant-dev
}

is_supported_plugin_profile() {
    local plugin_name="$1"
    local supported_profile

    while IFS= read -r supported_profile; do
        [[ "$plugin_name" == "$supported_profile" ]] && return 0
    done < <(supported_plugin_profiles)

    return 1
}

apply_plugin_profile() {
    local plugin_name="$1"
    local profile_line
    local profile_payload
    local profile_skill
    local profile_skills=()

    if ! profile_line="$(plugin_profile_line "$plugin_name")"; then
        fail "Unknown plugin profile: $plugin_name. Available install profiles are defined in docs/plugin-architecture.md."
    fi

    if ! is_supported_plugin_profile "$plugin_name"; then
        fail "$plugin_name is boundary-defined but not installable yet. Supported install profiles: $(supported_plugin_profiles | tr '\n' ' ' | sed 's/[[:space:]]*$//')."
    fi

    profile_payload="${profile_line#*:}"
    for profile_skill in $profile_payload; do
        case "$profile_skill" in
            assistant-*)
                [[ -f "$SKILLS_SOURCE/$profile_skill/SKILL.md" ]] || fail "Plugin profile $plugin_name references missing skill: $profile_skill"
                profile_skills+=("$profile_skill")
                ;;
            *) ;;
        esac
    done

    [[ "${#profile_skills[@]}" -gt 0 ]] || fail "Plugin profile $plugin_name has no installable assistant skills."
    SKILLS=("${profile_skills[@]}")
}

substitute_agent_paths_in_stream() {
    sed -e "s|{agent_state_dir}|.${AGENT}|g"
}

substitute_agent_paths_in_file() {
    local target_file="$1"

    sed -i.bak -e "s|{agent_state_dir}|.${AGENT}|g" "$target_file"
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
            return (index(line, "You are an orchestrator for memory-aware workflow.") == 1 \
                    && index(line, "The orchestrator may create and update framework-owned state artifacts such as .") > 0 \
                    && index(line, "/task.md, .") > 0 \
                    && index(line, "/context-map.md, .") > 0 \
                    && index(line, "/session.md, and .") > 0 \
                    && index(line, "/working-buffer.md; it does not edit project source files directly.") > 0) \
                || line == "You are an orchestrator for memory-aware workflow. Coordinate specialized agents and preserve workflow state while memory_context supplies project rules, preferences, and recent insights. File edits, code implementation, builds/tests, and independent review remain owned by the appropriate specialized agent; your role is dispatch, phase gates, progress tracking, communication, and memory protocol enforcement. The orchestrator does not edit files or write code directly. When a skill matches your task, invoke it and follow its instructions." \
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
[[ -z "$SINGLE_SKILL" || -z "$PLUGIN_PROFILE" ]] || fail "Use either --skill or --plugin, not both."

FRAMEWORK_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_SOURCE="$FRAMEWORK_DIR/skills"
GRAPH_SEED="$FRAMEWORK_DIR/graph-seed.jsonl"
[[ -d "$SKILLS_SOURCE" ]] || fail "Skills directory not found at $SKILLS_SOURCE"

# Auto-discover first-class release skills: assistant-* directories containing SKILL.md.
while IFS= read -r skill_md; do
    skill_dir="$(dirname "$skill_md")"
    skill_name="$(basename "$skill_dir")"
    SKILLS+=("$skill_name")
done < <(find "$SKILLS_SOURCE" -maxdepth 2 -path "$SKILLS_SOURCE/assistant-*/SKILL.md" -type f | sort)
command -v rsync >/dev/null 2>&1 || fail "rsync is required but not installed. Install with: apt install rsync / dnf install rsync / brew install rsync"

# Determine target base
if [[ "$AGENT" == "codex" ]]; then
    # Codex supports CODEX_HOME for its user-level config directory. Install to
    # the same directory Codex will inspect, otherwise a CODEX_HOME-based setup
    # keeps seeing old hooks from the active Codex home while the installer writes
    # unused files under ~/.codex.
    AGENT_HOME="${CODEX_HOME:-$HOME/.codex}"
else
    AGENT_HOME="$HOME/.${AGENT}"
fi
SKILLS_TARGET="$AGENT_HOME/skills"
MEMORY_TARGET="$AGENT_HOME/memory"

# Filter to single skill if requested
if [[ -n "$SINGLE_SKILL" ]]; then
    [[ -f "$SKILLS_SOURCE/$SINGLE_SKILL/SKILL.md" ]] || fail "Unknown skill: $SINGLE_SKILL. Available: ${SKILLS[*]}"
    SKILLS=("$SINGLE_SKILL")
fi

# Filter to a planned plugin profile if requested.
if [[ -n "$PLUGIN_PROFILE" ]]; then
    apply_plugin_profile "$PLUGIN_PROFILE"
fi

SETTINGS_FILE="$AGENT_HOME/settings.json"
HOOKS_TARGET="$AGENT_HOME/hooks/assistant"

echo "Installing Assistant Framework for: $AGENT"
echo "  Source: $FRAMEWORK_DIR"
if [[ -n "$PLUGIN_PROFILE" ]]; then
    echo "  Plugin profile: $PLUGIN_PROFILE"
    if $DRY_RUN; then
        echo "  Plugin manifest: $(plugin_manifest_path "$PLUGIN_PROFILE")"
    fi
fi
echo "  Skills target: $SKILLS_TARGET"
echo "  Legacy graph seed: $GRAPH_SEED"
echo ""

# Dry-run validates plugin scaffold metadata without changing the real install path.
if [[ -n "$PLUGIN_PROFILE" ]] && $DRY_RUN; then
    validate_plugin_manifest_dry_run "$PLUGIN_PROFILE"
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
        dry "Substitute agent state path placeholders in copied $skill instruction/config files"
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

        fi

        # Substitute agent-specific state directory placeholders in instruction/config files.
        while IFS= read -r instruction_file; do
            substitute_agent_paths_in_file "$instruction_file"
        done < <(find "$target_dir" -type f \( \
            -name "*.md" -o \
            -name "*.yaml" -o \
            -name "*.yml" -o \
            -name "*.json" -o \
            -name "*.conf" -o \
            -name "*.toml" \
        \))

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
                SETTINGS_TEMP="$(metadata_preserving_temp "$SETTINGS_FILE")" || SETTINGS_TEMP=""
                if [[ -n "$SETTINGS_TEMP" ]] \
                    && jq 'del(.mcpServers["memory-graph"]) | if .mcpServers == {} then del(.mcpServers) else . end' \
                        "$SETTINGS_FILE" > "$SETTINGS_TEMP" \
                    && mv "$SETTINGS_TEMP" "$SETTINGS_FILE"; then
                    info "Cleaned up stale MCP config from $SETTINGS_FILE (moved to correct location)"
                else
                    [[ -n "${SETTINGS_TEMP:-}" ]] && rm -f "$SETTINGS_TEMP"
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
                SETTINGS_TEMP="$(metadata_preserving_temp "$SETTINGS_FILE")" || SETTINGS_TEMP=""
                if [[ -n "$SETTINGS_TEMP" ]] \
                    && jq --arg cmd "$MCP_COMMAND" --arg dir "$MCP_MEMORY_DIR" \
                    '.mcpServers["memory-graph"] = {"command": $cmd, "args": ["--memory-dir", $dir]}' \
                    "$SETTINGS_FILE" > "$SETTINGS_TEMP" \
                    && mv "$SETTINGS_TEMP" "$SETTINGS_FILE"; then
                    ok "MCP server memory-graph registered in $SETTINGS_FILE"
                else
                    [[ -n "${SETTINGS_TEMP:-}" ]] && rm -f "$SETTINGS_TEMP"
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

# ── Retire framework hook registrations (compatibility release) ────────────

# Remove this cleanup block and the deprecated --no-hooks parser branch after
# one released version has shipped with hook retirement. Until then, clean only
# exact Assistant Framework registrations and leave unrelated hook support alone.
if [[ "$AGENT" == "codex" ]]; then
    LEGACY_HOOK_SETTINGS_FILE="$AGENT_HOME/hooks.json"
else
    LEGACY_HOOK_SETTINGS_FILE="$SETTINGS_FILE"
fi

if $DRY_RUN; then
    dry "Remove retired Assistant Framework hook registrations from $LEGACY_HOOK_SETTINGS_FILE when present"
    dry "Neutralize cached framework entrypoints only when legacy hook state exists"
else
    cleanup_legacy_framework_hooks "$LEGACY_HOOK_SETTINGS_FILE" "$HOOKS_TARGET" "$AGENT"
fi

# ── Generate AGENTS.md for Codex (it reads AGENTS.md, not CLAUDE.md) ────────
# Must run before memory protocol section since protocol is appended to AGENTS.md

AGENTS_MD_MARKER_START="ASSISTANT_FRAMEWORK_AGENTS_MD_START"
AGENTS_MD_MARKER_END="ASSISTANT_FRAMEWORK_AGENTS_MD_END"

if [[ "$AGENT" == "codex" ]]; then
    AGENTS_MD="$AGENT_HOME/AGENTS.md"
    echo ""

    # Keep the installer-owned standing guidance small. Installed SKILL.md files
    # are the native source of routing metadata and detailed workflow policy.
    AGENTS_MD_CONTENT="<!-- $AGENTS_MD_MARKER_START -->
# AGENTS.md — Codex Agent Instructions

Codex uses installed skills through native skill routing. When a skill matches, read its \`SKILL.md\` and load only the references or contracts relevant to the current phase.

## Development workflow

- Follow the matching skill's workflow and scale its phases to the task. Medium and larger changes require an approved plan before project source, test, documentation, configuration, or installer edits begin.
- Resolve material unknowns before planning. State safe defaults when local evidence makes the path clear.
- The orchestrator owns framework state files such as \`.codex/task.md\`, \`.codex/context-map.md\`, \`.codex/session.md\`, and \`.codex/working-buffer.md\`. Preserve user-authored project files and existing dirty work.
- Delegation consent is required only before an actual subagent spawn. Do not ask during preparation merely because agents might be useful. Ask once immediately before the first spawn unless the user already authorized that scope. Continue safe non-spawn work while authorization is unresolved.
- After authorization, use native Codex subagents by configured name. Do not infer that subagents are unavailable from the absence of a visible tool name; use direct fallback only after denial, policy restriction, or a real unavailable-agent failure.
- Verify changes with the relevant repository commands. Review the result against the approved scope and fix material findings before handoff; use independent review when the active skill or risk requires it.
- Keep credentials, secrets, PII, and private endpoints out of code, logs, task state, and memory.
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
fi
