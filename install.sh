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
#   ./install.sh --agent claude --skill assistant-workflow  # root skill plus bundled hard dependencies
#   ./install.sh --agent codex                              # native, hookless behavior
#   ./install.sh --agent claude --no-hooks                  # deprecated compatibility no-op
#

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────

AGENT=""
DRY_RUN=false
SINGLE_SKILL=""
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
  --skill NAME       Install one root skill plus bundled hard dependencies (default: all)
  --no-hooks         Deprecated compatibility no-op; all installs are hookless
  --dry-run          Show what would be done without doing it
  -h, --help         Show this help

Note: skill installation uses rsync --delete, which removes any files you
added manually to installed skill directories. Back up customizations first.

Skills installed:
  Auto-discovered from skills/assistant-*/SKILL.md.

Examples:
  $(basename "$0") --agent claude
  $(basename "$0") --agent codex --dry-run
  $(basename "$0") --agent claude --skill assistant-thinking
  $(basename "$0") --agent claude --no-hooks
EOF
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --agent)    [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; AGENT="$2"; shift 2 ;;
        --skill)    [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; SINGLE_SKILL="$2"; shift 2 ;;
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

array_contains() {
    local needle="$1"
    shift
    local value
    for value in "$@"; do
        [[ "$value" == "$needle" ]] && return 0
    done
    return 1
}

preflight_workflow_python() {
    array_contains assistant-workflow "${SKILLS[@]}" || return 0
    local version=""
    if ! command -v python3 >/dev/null 2>&1 \
        || ! version="$(python3 -B -c 'import sys; print("%d.%d.%d" % sys.version_info[:3]); sys.exit(0 if sys.version_info >= (3, 9) else 1)' 2>/dev/null)" \
        || [[ ! "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] \
        || ! (( 10#${BASH_REMATCH[1]} > 3 || (10#${BASH_REMATCH[1]} == 3 && 10#${BASH_REMATCH[2]} >= 9) )); then
        fail "Python 3.9+ is required when the selected skill closure includes assistant-workflow. Install a supported python3 and rerun. No installation files have been changed."
    fi
    info "Workflow Python 3.9+ invocation: python3 (Python $version)"
}

validate_managed_skill_name() {
    local skill="$1"

    [[ -n "$skill" && "$skill" != "." && "$skill" != ".." && "$skill" != */* && "$skill" != *\\* ]] \
        || fail "Unsafe skill name: $skill"
}

assert_existing_directory_or_absent() {
    local path="$1"
    local label="$2"

    [[ ! -L "$path" ]] || fail "Refusing $label symlink: $path"
    [[ ! -e "$path" || -d "$path" ]] || fail "Refusing $label that is not a directory: $path"
}

assert_directory_tree_safe() {
    local directory="$1"
    local label="$2"
    local unsafe_node=""

    unsafe_node="$(find "$directory" \( -type l -o \( ! -type d -a ! -type f \) \) -print -quit)" \
        || fail "Could not inspect $label: $directory"
    [[ -z "$unsafe_node" ]] || fail "Refusing $label containing a symlink or unsupported node: $unsafe_node"
}

assert_managed_skill_target_root_safe() {
    assert_existing_directory_or_absent "$AGENT_HOME" "agent home"
    assert_existing_directory_or_absent "$SKILLS_TARGET" "managed skills root"
}

assert_managed_skill_copy_safe() {
    local skill="$1"
    local source_dir=""
    local source_skill_md=""
    local target_dir=""

    validate_managed_skill_name "$skill"
    assert_managed_skill_target_root_safe

    source_dir="$SKILLS_SOURCE/$skill"
    source_skill_md="$source_dir/SKILL.md"
    target_dir="$SKILLS_TARGET/$skill"

    [[ ! -L "$SKILLS_SOURCE" && -d "$SKILLS_SOURCE" ]] \
        || fail "Refusing managed skills source symlink or non-directory: $SKILLS_SOURCE"
    [[ ! -L "$source_dir" && -d "$source_dir" ]] \
        || fail "Refusing $skill source symlink or non-directory: $source_dir"
    [[ ! -L "$source_skill_md" && -f "$source_skill_md" ]] \
        || fail "Refusing $skill metadata symlink or non-regular file: $source_skill_md"
    assert_directory_tree_safe "$source_dir" "$skill source"

    [[ ! -L "$target_dir" ]] || fail "Refusing $skill managed target symlink: $target_dir"
    [[ ! -e "$target_dir" || -d "$target_dir" ]] \
        || fail "Refusing $skill managed target that is not a directory: $target_dir"
    if [[ -d "$target_dir" ]]; then
        assert_directory_tree_safe "$target_dir" "$skill managed target"
    fi
}

preflight_managed_skill_closure() {
    local skill=""

    for skill in "$@"; do
        assert_managed_skill_copy_safe "$skill"
    done
}

# Read only the declared ownership compatibility surface, not general YAML.
# Unknown forms in these fields are incompatible; unrelated contract sections
# remain owned by the workflow skill. Boolean false must stay an unquoted token.
declared_workflow_contract_compatible() {
    local contract_file="$1" expected_contract="$2" expected_version="${3:-13.0}"
    LC_ALL=C awk -v expected_version="$expected_version" -v expected_contract="$expected_contract" -v bom="$(printf '\357\273\277')" '
        function reject() { invalid = 1; exit 1 }
        function trim(value) { sub(/^[ ]+/, "", value); sub(/[ ]+$/, "", value); return value }
        function scalar(value, expected) {
            return ("x" value == "x" expected || "x" value == "x\"" expected "\"" || "x" value == "x" quote expected quote)
        }
        function field(name, value) {
            if (stage < 1 || ++field_seen[stage, name] != 1) reject()
            fields[stage, name] = value; field_count[stage]++
        }
        BEGIN {
            quote = sprintf("%c", 39)
            names[1] = "test_authoring"; scopes[1] = "tests_only"; prerequisites[1] = "none"
            names[2] = "production"; scopes[2] = "tests_and_production"; prerequisites[2] = "current_matching_red"
            names[3] = "refactor"; scopes[3] = "behavior_neutral"; prerequisites[3] = "current_passing_green"
        }
        {
            line = $0
            if (NR == 1 && index(line, bom) == 1) line = substr(line, length(bom) + 1)
            sub(/\r$/, "", line)
            if (line ~ /\t/) reject()
            if (line ~ /^[ ]*(#.*)?$/) next
            sub(/[ ]+#.*$/, "", line); sub(/[ ]+$/, "", line)
            if (line !~ /^ /) {
                in_protocol = 0; section = ""
                if (line !~ /^[A-Za-z_][A-Za-z_0-9]*:[ ]*/) reject()
                key = line; sub(/:.*/, "", key)
                value = line; sub(/^[^:]+:[ ]*/, "", value)
                lower = tolower(key)
                if (lower == "schema_version" || lower == "contract" || lower == "skill") {
                    if (key != lower || ++metadata_seen[key] != 1) reject()
                    metadata[key] = value
                } else if (expected_contract == "handoffs" && lower == "worker_stage_protocol") {
                    if (key != lower || value != "" || ++protocols != 1) reject()
                    in_protocol = 1
                }
                next
            }
            if (!in_protocol) next
            if (line ~ /^  [A-Za-z_][A-Za-z_0-9]*:/) {
                key = substr(line, 3); sub(/:.*/, "", key)
                value = line; sub(/^  [^:]+:[ ]*/, "", value)
                if (++sections[key] != 1) reject()
                if (key != "description" && key != "stages" && key != "rules") reject()
                if ((key == "stages" || key == "rules") && value != "") reject()
                section = key; next
            }
            if (section == "stages") {
                if (line ~ /^    - value:[ ]*/) {
                    if (++stage > 3) reject()
                    value = line; sub(/^    - value:[ ]*/, "", value); field("value", value)
                } else if (line ~ /^      (mutation_scope|active_tdd_prerequisite|completes_build):[ ]*/) {
                    key = substr(line, 7); sub(/:.*/, "", key)
                    value = line; sub(/^      [^:]+:[ ]*/, "", value); field(key, value)
                } else reject()
            } else if (section != "rules" || line !~ /^    - /) reject()
        }
        END {
            if (invalid || metadata_seen["schema_version"] != 1 || metadata_seen["contract"] != 1 || metadata_seen["skill"] != 1) exit 1
            if (!scalar(metadata["schema_version"], expected_version) || !scalar(metadata["contract"], expected_contract) || !scalar(metadata["skill"], "assistant-workflow")) exit 1
            if (expected_contract == "handoffs") {
                if (protocols != 1 || sections["stages"] != 1 || stage != 3) exit 1
                for (i = 1; i <= 3; i++) {
                    if (field_count[i] != 4 || !scalar(fields[i, "value"], names[i]) || !scalar(fields[i, "mutation_scope"], scopes[i]) || !scalar(fields[i, "active_tdd_prerequisite"], prerequisites[i]) || fields[i, "completes_build"] != "false") exit 1
                }
            }
        }
    ' "$contract_file"
}

preflight_workflow_role_compatibility() {
    local extension profile definition workflow="$SKILLS_TARGET/assistant-workflow" file
    if [[ "$AGENT" == codex || "$AGENT" == claude ]]; then
        extension=md; [[ "$AGENT" != codex ]] || extension=toml
        for profile in intelligent-writer mechanical-writer; do
            definition="$FRAMEWORK_DIR/agents/$AGENT/$profile.$extension"
            if [[ -L "$definition" || ! -f "$definition" || ! -r "$definition" ]]; then
                fail "Missing required writer definition for $AGENT: $definition. Restore the complete framework source and retry. No installation files have been changed."
            fi
        done
    fi
    array_contains assistant-workflow "${SKILLS[@]}" && return 0

    assert_managed_skill_target_root_safe
    assert_existing_directory_or_absent "$workflow" "retained workflow"
    [[ -d "$workflow" ]] || return 0
    assert_directory_tree_safe "$workflow" "retained workflow"
    assert_existing_directory_or_absent "$workflow/contracts" "retained workflow contracts"
    for file in SKILL.md contracts/index.yaml contracts/handoffs.yaml; do
        if [[ ! -f "$workflow/$file" || ! -r "$workflow/$file" ]]; then
            fail "INCOMPATIBLE_WORKFLOW_ROLE_UPGRADE at $workflow: missing or unreadable regular $file. No installation files have been changed. Run ./install.sh --agent $AGENT --skill assistant-workflow, then retry the original selection; or run ./install.sh --agent $AGENT for a full install."
        fi
    done
    if ! cat "$workflow/SKILL.md" >/dev/null \
        || ! declared_workflow_contract_compatible "$workflow/contracts/index.yaml" index 15.0 \
        || ! declared_workflow_contract_compatible "$workflow/contracts/handoffs.yaml" handoffs 15.0; then
        fail "INCOMPATIBLE_WORKFLOW_ROLE_UPGRADE at $workflow: retained controller does not uniquely declare matching schema 15.0 and the supported ownership stage tuples. No installation files have been changed. Run ./install.sh --agent $AGENT --skill assistant-workflow, then retry the original selection; or run ./install.sh --agent $AGENT for a full install."
    fi
}

read_canonical_skill_requires() {
    local skill_md="$1"
    local line=""
    local dependency=""
    local in_frontmatter=false
    local in_requires=false

    [[ -f "$skill_md" ]] || return 0
    while IFS= read -r line; do
        if [[ "$line" == "---" ]]; then
            if $in_frontmatter; then
                break
            fi
            in_frontmatter=true
            continue
        fi
        $in_frontmatter || continue
        if [[ "$line" == "requires:" ]]; then
            in_requires=true
            continue
        fi
        if $in_requires && [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(.*)$ ]]; then
            dependency="${BASH_REMATCH[1]}"
            dependency="${dependency#"${dependency%%[![:space:]]*}"}"
            dependency="${dependency%"${dependency##*[![:space:]]}"}"
            [[ -n "$dependency" ]] && printf '%s\n' "$dependency"
        else
            in_requires=false
        fi
    done < "$skill_md"
}

resolve_bundled_skill_closure() {
    local -a inventory=()
    local -a queue=("$@")
    local -a resolved=()
    local queue_index=0
    local skill=""
    local dependency=""

    if [[ ${#SKILLS[@]} -gt 0 ]]; then
        inventory=("${SKILLS[@]}")
    fi

    while [[ $queue_index -lt ${#queue[@]} ]]; do
        skill="${queue[$queue_index]}"
        queue_index=$((queue_index + 1))
        validate_managed_skill_name "$skill"
        if [[ ${#resolved[@]} -gt 0 ]] && array_contains "$skill" "${resolved[@]}"; then
            continue
        fi
        assert_managed_skill_copy_safe "$skill"
        resolved+=("$skill")
        while IFS= read -r dependency; do
            [[ -n "$dependency" ]] || continue
            if [[ ${#inventory[@]} -gt 0 ]] &&
                array_contains "$dependency" "${inventory[@]}" &&
                ! { [[ ${#resolved[@]} -gt 0 ]] && array_contains "$dependency" "${resolved[@]}"; } &&
                ! array_contains "$dependency" "${queue[@]}"; then
                queue+=("$dependency")
            fi
        done < <(read_canonical_skill_requires "$SKILLS_SOURCE/$skill/SKILL.md")
    done

    SKILLS=("${resolved[@]}")
}

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

validate_installed_plugin_tool_cleanup() {
    local tools_target="$1"
    local plugin_tools_directory="$tools_target/plugins"
    local retired_tool="$plugin_tools_directory/sync-plugin-skills.sh"

    if [[ -L "$plugin_tools_directory" ]]; then
        fail "Refusing retired plugin tool cleanup through a symlink: $plugin_tools_directory"
    elif [[ -e "$plugin_tools_directory" && ! -d "$plugin_tools_directory" ]]; then
        fail "Refusing retired plugin tool cleanup because the parent is not a directory: $plugin_tools_directory"
    fi

    if [[ -L "$retired_tool" ]]; then
        fail "Refusing to remove a retired plugin tool symlink: $retired_tool"
    elif [[ -e "$retired_tool" && ! -f "$retired_tool" ]]; then
        fail "Refusing to remove a retired plugin tool that is not a file: $retired_tool"
    fi
}

retire_installed_plugin_tool() {
    local tools_target="$1"
    local plugin_tools_directory="$tools_target/plugins"
    local retired_tool="$plugin_tools_directory/sync-plugin-skills.sh"
    local projected_remaining_entry=""

    validate_installed_plugin_tool_cleanup "$tools_target"

    if [[ -f "$retired_tool" ]]; then
        if $DRY_RUN; then
            dry "Remove retired managed plugin tool: $retired_tool"
        else
            rm -f -- "$retired_tool"
            ok "Removed retired managed plugin tool: $retired_tool"
        fi
    fi

    if [[ -d "$plugin_tools_directory" ]]; then
        if $DRY_RUN; then
            projected_remaining_entry="$(find "$plugin_tools_directory" -mindepth 1 -maxdepth 1 ! -name 'sync-plugin-skills.sh' -print -quit)"
            if [[ -z "$projected_remaining_entry" ]]; then
                dry "Remove empty retired plugin tools directory: $plugin_tools_directory"
            fi
        else
            rmdir -- "$plugin_tools_directory" 2>/dev/null || true
        fi
    fi
}

# ── Validate ──────────────────────────────────────────────────────────────────

[[ -n "$AGENT" ]] || fail "Missing --agent. Supported: claude, codex, gemini"
[[ "$AGENT" =~ ^(claude|codex|gemini)$ ]] || fail "Unknown agent: $AGENT. Supported: claude, codex, gemini"

FRAMEWORK_DIR="$(cd -P "$(dirname "$0")" && pwd -P)"
SKILLS_SOURCE="$FRAMEWORK_DIR/skills"
[[ ! -L "$SKILLS_SOURCE" && -d "$SKILLS_SOURCE" ]] \
    || fail "Skills directory not found or unsafe at $SKILLS_SOURCE"

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
TOOLS_SOURCE="$FRAMEWORK_DIR/tools"
TOOLS_TARGET="$AGENT_HOME/tools"

# Reject unsafe retired-tool parents before skill installation can mutate files.
if [[ -d "$TOOLS_SOURCE" ]]; then
    validate_installed_plugin_tool_cleanup "$TOOLS_TARGET"
fi

# Select one root skill and its bundled hard-dependency closure if requested.
if [[ -n "$SINGLE_SKILL" ]]; then
    validate_managed_skill_name "$SINGLE_SKILL"
    assert_managed_skill_copy_safe "$SINGLE_SKILL"
    [[ -f "$SKILLS_SOURCE/$SINGLE_SKILL/SKILL.md" ]] || fail "Unknown skill: $SINGLE_SKILL. Available: ${SKILLS[*]}"
    resolve_bundled_skill_closure "$SINGLE_SKILL"
fi

# Validate the complete selected set before any installer write. The closure
# resolver preflights each member before it reads that member's metadata; this
# second pass also covers full installs and catches changes before copying.
preflight_managed_skill_closure "${SKILLS[@]}"
preflight_workflow_python
preflight_workflow_role_compatibility

SETTINGS_FILE="$AGENT_HOME/settings.json"
HOOKS_TARGET="$AGENT_HOME/hooks/assistant"

echo "Installing Assistant Framework for: $AGENT"
echo "  Source: $FRAMEWORK_DIR"
echo "  Skills target: $SKILLS_TARGET"
echo ""

# ── Install skills ────────────────────────────────────────────────────────────

for skill in "${SKILLS[@]}"; do
    # Recheck immediately before rsync so a changed managed path is never used.
    assert_managed_skill_copy_safe "$skill"
    source_dir="$SKILLS_SOURCE/$skill"
    target_dir="$SKILLS_TARGET/$skill"

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

    while IFS= read -r dep; do
        if ! array_contains "$dep" "${SKILLS[@]}" && [[ ! -d "$SKILLS_TARGET/$dep" ]]; then
            info "NOTE: $skill requires '$dep' which is not being installed and not found at $SKILLS_TARGET/$dep"
        fi
    done < <(read_canonical_skill_requires "$skill_md")
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

if [[ -d "$TOOLS_SOURCE" ]]; then
    echo ""
    if $DRY_RUN; then
        dry "rsync $TOOLS_SOURCE/ -> $TOOLS_TARGET/"
        remove_source_only_promotion_tools "$TOOLS_TARGET"
        retire_installed_plugin_tool "$TOOLS_TARGET"
        cleanup_installed_tool_build_artifacts "$TOOLS_TARGET" "$TOOLS_SOURCE"
    else
        mkdir -p "$TOOLS_TARGET"
        retire_installed_plugin_tool "$TOOLS_TARGET"
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
            --exclude='/plugins/' \
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

# ── Generate managed instructions (AGENTS.md for Codex, CLAUDE.md for Claude) ─
# Both agents get the same ASCII guidance; only the title and guidance path differ.
# Generate the current managed section after legacy cleanup.

AGENTS_MD_MARKER_START="ASSISTANT_FRAMEWORK_AGENTS_MD_START"
AGENTS_MD_MARKER_END="ASSISTANT_FRAMEWORK_AGENTS_MD_END"

if [[ "$AGENT" == "codex" || "$AGENT" == "claude" ]]; then
    if [[ "$AGENT" == "codex" ]]; then
        AGENTS_MD="$AGENT_HOME/AGENTS.md"
        AGENTS_MD_AGENT_NAME="Codex"
        AGENTS_MD_GUIDANCE_HOME="the configured \`CODEX_HOME\` (default \`~/.codex\`)"
    else
        AGENTS_MD="$AGENT_HOME/CLAUDE.md"
        AGENTS_MD_AGENT_NAME="Claude Code"
        AGENTS_MD_GUIDANCE_HOME="\`~/.claude\`"
    fi
    echo ""

    # Keep the installer-owned standing guidance small. Installed SKILL.md files
    # are the native source of routing metadata and detailed workflow policy.
    AGENTS_MD_CONTENT="<!-- $AGENTS_MD_MARKER_START -->
# Assistant Framework - $AGENTS_MD_AGENT_NAME Instructions

Read \`tools/progress/operating-guidance.md\` under $AGENTS_MD_GUIDANCE_HOME as the common operating guidance for every activity, including when no skill matches.

## Skills

- When a skill's description matches the request, read its \`SKILL.md\` and follow it through to its handoff, loading only the references and contracts the current phase needs.
- For ordinary repository changes, use assistant-workflow when that skill is installed; use assistant-clarify for unclear or tangled intent.
- Do not skip a matched skill's gates, verification, or review to save time.

## Involving the user

Work autonomously and resolve what you can from the repository and the request. Stop for the user only to:

- decide a consequential choice about intent, scope, safety, or acceptance that is still open;
- approve a destructive, external, or hard-to-reverse action, or one beyond the granted access or cost;
- approve a plan before medium+ or elevated-risk development edits;
- hear that the shared stagnation guard stopped corrective work.

Do not ask for routine confirmation or repeat an approval already given for the same scope. Otherwise report once at the end: outcome, files changed and why, checks and results, material limits, and next action.

## Operating stance

- For small, low-risk, localized work, act as a hands-on worker: complete it directly with proportionate validation and a fresh self-review.
- For medium+ or elevated-risk development work, remain the orchestrator: own user communication, task state, scope, decisions, delegation, and final integration; route implementation and independent review through the matching workflow roles when required.
- Keep orchestration proportional - do not introduce delegation or ceremony when direct lightweight execution is sufficient.

## Boundaries

- Use subagents when the user asks or applicable project or skill instructions require them; no separate spawn consent is needed.
- Preserve user-authored files and existing dirty work.
- Verify changes with repository commands and review the approved scope before handoff.
- Keep credentials, secrets, PII, and private endpoints out of code, logs, task state, and memory.
<!-- $AGENTS_MD_MARKER_END -->"

    # Count exact marker lines; any unbalanced, nested, or duplicate marker is
    # ambiguous, so the file is preserved unchanged instead of risking user content.
    AGENTS_MD_MARKER_STATE="none"
    if [[ -f "$AGENTS_MD" ]]; then
        AGENTS_MD_MARKER_STATE="$(awk -v s="<!-- $AGENTS_MD_MARKER_START -->" -v e="<!-- $AGENTS_MD_MARKER_END -->" '
            { t = $0; gsub(/^[ \t]+|[ \t\r]+$/, "", t) }
            t == s { if (open || starts > 0) bad = 1; starts++; open = 1; next }
            t == e { if (!open) bad = 1; ends++; open = 0 }
            END {
                if (bad || open || starts > 1 || ends > 1) print "ambiguous"
                else if (starts == 1) print "block"
                else print "none"
            }' "$AGENTS_MD")"
    fi

    if $DRY_RUN; then
        dry "Would generate/update $AGENTS_MD with the managed installer section"
    elif [[ "$AGENTS_MD_MARKER_STATE" == "ambiguous" ]]; then
        info "WARNING: Ambiguous, duplicate, or unbalanced Assistant Framework markers in $AGENTS_MD; preserved unchanged."
    elif [[ "$AGENTS_MD_MARKER_STATE" == "block" ]]; then
        # Re-install: strip old installer block (exact marker lines), preserve user content
        sed -i.bak "/^[[:space:]]*<!-- $AGENTS_MD_MARKER_START -->[[:space:]]*\$/,/^[[:space:]]*<!-- $AGENTS_MD_MARKER_END -->[[:space:]]*\$/d" "$AGENTS_MD"
        rm -f "${AGENTS_MD}.bak"
        # Prepend installer block (it should come first)
        # cp -p first so the rewritten file keeps the original mode and owner
        cp -p "$AGENTS_MD" "${AGENTS_MD}.tmp" \
            && { echo "$AGENTS_MD_CONTENT"; echo ""; cat "$AGENTS_MD"; } > "${AGENTS_MD}.tmp" \
            && mv "${AGENTS_MD}.tmp" "$AGENTS_MD"
        ok "Updated installer section in $AGENTS_MD (user customizations preserved)"
    elif [[ -f "$AGENTS_MD" ]]; then
        # Existing file without markers — prepend installer block, keep user content
        # cp -p first so the rewritten file keeps the original mode and owner
        cp -p "$AGENTS_MD" "${AGENTS_MD}.tmp" \
            && { echo "$AGENTS_MD_CONTENT"; echo ""; cat "$AGENTS_MD"; } > "${AGENTS_MD}.tmp" \
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
    echo "To install one root skill and its bundled hard dependencies: ./install.sh --agent $AGENT --skill <name>"
fi
