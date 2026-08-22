#!/usr/bin/env bash
# install.sh — Installs all Assistant Framework skills for any supported AI agent.
#
# Auto-discovers first-class release skills from skills/assistant-*/SKILL.md.
# Performs bounded cleanup for retired framework registrations on reinstall.
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
        skill_in_active_profile "$plugin_skill" \
            || fail "Plugin manifest $plugin_name includes skill outside profile boundary: $plugin_skill"
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

cleanup_installed_tool_build_artifacts() {
    local tools_target="$1"
    local tools_source="$2"
    local artifact_dir source_directory target_directory
    local found=false

    if [[ ! -d "$tools_target" || ! -d "$tools_source" ]]; then
        if $DRY_RUN; then
            dry "Would remove stale build artifacts from managed tool directories under $tools_target"
        fi
        return 0
    fi

    while IFS= read -r source_directory; do
        target_directory="$tools_target/${source_directory##*/}"
        [[ -d "$target_directory" ]] || continue
        while IFS= read -r artifact_dir; do
            found=true
            if $DRY_RUN; then
                dry "Remove stale tool build artifact: $artifact_dir"
            else
                rm -rf "$artifact_dir"
            fi
        done < <(find "$target_directory" -mindepth 1 -type d \( -name ".publish" -o -name "bin" -o -name "obj" \) -prune -print)
    done < <(find "$tools_source" -mindepth 1 -maxdepth 1 -type d -print)

    if $DRY_RUN && ! $found; then
        dry "No stale tool build artifacts found under $tools_target"
    fi
}

remove_source_only_promotion_tools() {
    local tools_target="$1" relative_path
    while IFS= read -r relative_path; do
        [[ -n "$relative_path" ]] || continue
        if $DRY_RUN; then
            dry "Remove source-repository-only promotion tool: $tools_target/$relative_path"
        elif [[ "$relative_path" == "evals/node_modules" ]]; then
            rm -rf -- "$tools_target/$relative_path"
        else
            rm -f -- "$tools_target/$relative_path"
        fi
    done <<'EOF'
context-budget-report.sh
evals/run-codex-framework-evals.sh
evals/finalize-workflow-kernel-review.sh
evals/lib/context-budget-evidence.sh
evals/validate-promotion-decision-schema.cjs
evals/package.json
evals/package-lock.json
evals/node_modules
EOF
}

# ── Validate ──────────────────────────────────────────────────────────────────

[[ -n "$AGENT" ]] || fail "Missing --agent. Supported: claude, codex, gemini"
[[ "$AGENT" =~ ^(claude|codex|gemini)$ ]] || fail "Unknown agent: $AGENT. Supported: claude, codex, gemini"
[[ -z "$SINGLE_SKILL" || -z "$PLUGIN_PROFILE" ]] || fail "Use either --skill or --plugin, not both."

FRAMEWORK_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_SOURCE="$FRAMEWORK_DIR/skills"
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
        remove_source_only_promotion_tools "$TOOLS_TARGET"
        cleanup_installed_tool_build_artifacts "$TOOLS_TARGET" "$TOOLS_SOURCE"
    else
        mkdir -p "$TOOLS_TARGET"
        rsync -a --delete \
            --exclude='.DS_Store' \
            --exclude='.publish' \
            --exclude='bin' \
            --exclude='obj' \
            --exclude='/memory-graph' \
            --exclude='/context-budget-report.sh' \
            --exclude='/evals/run-codex-framework-evals.sh' \
            --exclude='/evals/finalize-workflow-kernel-review.sh' \
            --exclude='/evals/lib/context-budget-evidence.sh' \
            --exclude='/evals/validate-promotion-decision-schema.cjs' \
            --exclude='/evals/package.json' \
            --exclude='/evals/package-lock.json' \
            --exclude='/evals/node_modules' \
            "$TOOLS_SOURCE/" "$TOOLS_TARGET/"
        remove_source_only_promotion_tools "$TOOLS_TARGET"
        cleanup_installed_tool_build_artifacts "$TOOLS_TARGET" "$TOOLS_SOURCE"

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
# Generate the current managed AGENTS.md section after legacy cleanup.

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

## Operating stance

- For small, low-risk, localized work, act as a hands-on worker: complete it directly with proportionate validation and a fresh self-review.
- For medium+ or elevated-risk development work, remain the orchestrator: own user communication, task state, scope, decisions, delegation, and final integration; route implementation and independent review through the matching workflow roles when required.
- Keep orchestration proportional—do not introduce delegation or ceremony when direct lightweight execution is sufficient.

## Boundaries

- Get plan approval before medium+ or risky edits.
- Use subagents when requested by the user or required by applicable project or skill instructions; do not ask for separate spawn consent.
- Preserve user-authored files and existing dirty work.
- Verify changes with repository commands and review the approved scope before handoff.
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
if [[ -n "$SINGLE_SKILL" ]]; then
    echo "To install all skills: ./install.sh --agent $AGENT"
else
    echo "To install a single skill: ./install.sh --agent $AGENT --skill <name>"
fi
