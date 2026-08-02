#!/usr/bin/env bash
# Retires only the former Assistant Framework Memory Graph installation.
# The tombstone is intentionally retained for one release so machines that
# skip a framework reinstall can remove stale framework-owned artifacts.

set -euo pipefail

dry_run=false
purge_data=false
agent_filter=""

usage() {
    cat <<'EOF'
Usage: cleanup-memory-graph.sh [--agent <claude|codex|gemini>] [--dry-run] [--purge-data]

  --agent accepts claude, codex, or gemini.

Remove retired Assistant Framework Memory Graph registrations, tools, skills,
and instruction blocks. Existing provider memory data is preserved unless
--purge-data is supplied explicitly.

Editing a potentially relevant existing Codex config.toml requires the Codex CLI.
If its semantic check is unavailable or ambiguous, config, runtime, and
provider data are preserved and cleanup stops.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) dry_run=true ;;
        --purge-data) purge_data=true ;;
        --agent)
            [[ $# -ge 2 ]] || { echo "Error: Missing value for --agent" >&2; exit 1; }
            agent_filter="$2"
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Error: Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

case "$agent_filter" in
    ""|claude|codex|gemini) ;;
    *) echo "Error: --agent must be claude, codex, or gemini" >&2; exit 2 ;;
esac

shell_normalize_absolute_path() {
    local path="$1" part
    local IFS='/'
    local -a parts normalized=()
    [[ "$path" = /* ]] || return 1
    read -r -a parts <<<"$path"
    for part in "${parts[@]}"; do
        case "$part" in
            ""|.) ;;
            ..)
                if [[ "${#normalized[@]}" -gt 0 ]]; then
                    normalized=("${normalized[@]:0:${#normalized[@]}-1}")
                fi
                ;;
            *) normalized+=("$part") ;;
        esac
    done
    if [[ "${#normalized[@]}" -eq 0 ]]; then
        printf '/\n'
    else
        local joined
        joined="$(IFS=/; printf '%s' "${normalized[*]}")"
        printf '/%s\n' "$joined"
    fi
}

shell_physical_path() {
    local candidate="$1" suffix="" leaf
    while [[ ! -d "$candidate" ]]; do
        [[ ! -L "$candidate" && "$candidate" != / ]] || return 1
        leaf="${candidate##*/}"
        suffix="/$leaf$suffix"
        candidate="${candidate%/*}"
        [[ -n "$candidate" ]] || candidate=/
    done
    (cd -P -- "$candidate" && printf '%s%s\n' "$PWD" "$suffix")
}

shell_is_macos_var_alias() {
    [[ "$1" = /var ]] && (cd -P -- /var 2>/dev/null && [[ "$PWD" = /private/var ]])
}

shell_assert_no_symlink_ancestors() {
    local path="$1" purpose="$2" base="${3:-/}" current part relative
    local IFS='/'
    if [[ "$base" = / ]]; then
        current=/
        relative="${path#/}"
    else
        current="$base"
        relative="${path#"$base"}"
        [[ ! -L "$current" ]] || { echo "Error: Refusing $purpose through symlink: $current" >&2; exit 1; }
    fi
    local -a shell_parts
    read -r -a shell_parts <<<"${relative#/}"
    for part in "${shell_parts[@]}"; do
        [[ -n "$part" ]] || continue
        current="${current%/}/$part"
        if [[ -L "$current" ]]; then
            shell_is_macos_var_alias "$current" || {
                echo "Error: Refusing $purpose through symlink: $current" >&2
                exit 1
            }
        fi
    done
}

shell_is_child_path() {
    [[ "$1" = "${2%/}/"* ]]
}

[[ -n "${HOME:-}" ]] || { echo "Error: HOME must be a non-root absolute path." >&2; exit 1; }
cleanup_home="$(shell_normalize_absolute_path "$HOME")" || { echo "Error: HOME must be a non-root absolute path." >&2; exit 1; }
[[ "$cleanup_home" != / && -d "$cleanup_home" && ! -L "$cleanup_home" ]] || {
    echo "Error: HOME must resolve to an existing non-root directory." >&2
    exit 1
}
cleanup_home_physical="$(cd -P -- "$cleanup_home" && pwd -P)"
[[ "$cleanup_home_physical" != / ]] || { echo "Error: HOME must resolve to an existing non-root directory." >&2; exit 1; }
HOME="$cleanup_home"

cleanup_codex_home=""
if [[ -z "$agent_filter" || "$agent_filter" = codex ]] && [[ -n "${CODEX_HOME:-}" ]]; then
    cleanup_codex_home="$(shell_normalize_absolute_path "$CODEX_HOME")" || { echo "Error: CODEX_HOME must be a non-root absolute path." >&2; exit 1; }
    [[ "$cleanup_codex_home" != / ]] || { echo "Error: CODEX_HOME must be a non-root absolute path." >&2; exit 1; }
    shell_assert_no_symlink_ancestors "$cleanup_codex_home" "CODEX_HOME"
    cleanup_codex_home_physical="$(shell_physical_path "$cleanup_codex_home")" || {
        echo "Error: Refusing unresolved or unsafe CODEX_HOME: $cleanup_codex_home" >&2
        exit 1
    }
    [[ "$cleanup_codex_home_physical" != / && "$cleanup_codex_home_physical" != "$cleanup_home_physical" ]] || {
        echo "Error: Refusing CODEX_HOME with unsafe root or HOME identity: $cleanup_codex_home" >&2
        exit 1
    }
    if [[ "$cleanup_codex_home_physical" = "${cleanup_home_physical%/}/"* ]] && ! shell_is_child_path "$cleanup_codex_home" "$cleanup_home"; then
        echo "Error: Refusing CODEX_HOME with ambiguous physical identity: $cleanup_codex_home" >&2
        exit 1
    fi
fi

python_bin=""
if command -v python3 >/dev/null 2>&1; then
    python_bin=python3
elif command -v python >/dev/null 2>&1 && python -c 'import sys; raise SystemExit(sys.version_info[0] != 3)' >/dev/null 2>&1; then
    python_bin=python
else
    # Directory-only retirement is deliberately available without Python. A
    # structured file may proceed only when a conservative byte-level check
    # proves it cannot contain the retired identity; Python remains the only
    # authority for structured edits. Managed instruction markers still fail
    # closed before changing anything.
    shell_require_python() {
        echo "Error: Python 3 is required before retiring legacy TOML, JSON, or managed instruction markers; preserved unchanged." >&2
        exit 1
    }

    shell_regular_file_identity() {
        local path="$1"
        [[ -f "$path" && ! -L "$path" ]] || return 1
        case "$(uname -s)" in
            Darwin|FreeBSD) stat -f '%d:%i:%p:%z:%m:%c' "$path" ;;
            *) stat -c '%d:%i:%f:%s:%Y:%Z' "$path" ;;
        esac
    }

    shell_directory_identity() {
        local path="$1"
        [[ -d "$path" && ! -L "$path" ]] || return 1
        case "$(uname -s)" in
            Darwin|FreeBSD) stat -f '%d:%i' "$path" ;;
            *) stat -c '%d:%i' "$path" ;;
        esac
    }

    shell_snapshot_directory_is_safe() {
        [[ "$shell_snapshot_dir" = /tmp/assistant-framework-memory-cleanup.* \
            && "$shell_snapshot_dir" != / \
            && -d "$shell_snapshot_dir" \
            && ! -L "$shell_snapshot_dir" ]]
    }

    shell_prepare_snapshot_directory() {
        [[ -z "$shell_snapshot_dir" ]] || return 0
        shell_snapshot_dir="$(mktemp -d /tmp/assistant-framework-memory-cleanup.XXXXXX)" || return 1
        trap shell_cleanup_snapshots EXIT
        shell_snapshot_directory_identity="$(shell_directory_identity "$shell_snapshot_dir" 2>/dev/null)" || return 1
        shell_snapshot_directory_is_safe || return 1
    }

    shell_cleanup_snapshots() {
        local status=$? current_identity
        trap - EXIT
        if shell_snapshot_directory_is_safe; then
            current_identity="$(shell_directory_identity "$shell_snapshot_dir" 2>/dev/null || true)"
            if [[ -z "$shell_snapshot_directory_identity" ]]; then
                rm -rf -- "$shell_snapshot_dir" >/dev/null 2>&1 || true
            elif [[ -n "$current_identity" && "$current_identity" = "$shell_snapshot_directory_identity" ]]; then
                rm -rf -- "$shell_snapshot_dir" >/dev/null 2>&1 || true
            fi
        fi
        exit "$status"
    }

    shell_relevant_path_is_safe() {
        local path="$1" traversal_root="$2" current part relative
        local IFS='/'
        if [[ "$traversal_root" = / ]]; then
            current=/
            relative="${path#/}"
        else
            [[ "$path" = "${traversal_root%/}/"* && ! -L "$traversal_root" ]] || return 1
            current="$traversal_root"
            relative="${path#"$traversal_root"}"
        fi
        local -a parts
        read -r -a parts <<<"${relative#/}"
        for part in "${parts[@]}"; do
            [[ -n "$part" ]] || continue
            current="${current%/}/$part"
            if [[ -L "$current" ]] && ! shell_is_macos_var_alias "$current"; then
                return 1
            fi
        done
        [[ ! -L "$path" && ( ! -e "$path" || -f "$path" ) ]]
    }

    shell_capture_relevant_file() {
        local path="$1" traversal_root="$2" index identity_before identity_after snapshot
        shell_relevant_path_is_safe "$path" "$traversal_root" || return 1

        index="${#shell_relevant_paths[@]}"
        shell_relevant_paths+=("$path")
        shell_relevant_roots+=("$traversal_root")
        if [[ ! -e "$path" ]]; then
            shell_relevant_present+=(false)
            shell_relevant_identities+=("")
            shell_relevant_snapshots+=("")
            return 0
        fi

        shell_prepare_snapshot_directory || return 1
        identity_before="$(shell_regular_file_identity "$path" 2>/dev/null)" || return 1
        snapshot="$shell_snapshot_dir/$index"
        cp "$path" "$snapshot" || return 1
        identity_after="$(shell_regular_file_identity "$path" 2>/dev/null)" || return 1
        [[ "$identity_before" = "$identity_after" ]] || return 1
        cmp -s "$path" "$snapshot" || return 1

        shell_relevant_present+=(true)
        shell_relevant_identities+=("$identity_after")
        shell_relevant_snapshots+=("$snapshot")
    }

    shell_revalidate_relevant_files() {
        local index path traversal_root identity
        for index in "${!shell_relevant_paths[@]}"; do
            path="${shell_relevant_paths[$index]}"
            traversal_root="${shell_relevant_roots[$index]}"
            shell_relevant_path_is_safe "$path" "$traversal_root" || return 1
            if [[ "${shell_relevant_present[$index]}" = false ]]; then
                [[ ! -e "$path" && ! -L "$path" ]] || return 1
                continue
            fi
            [[ -e "$path" && -f "$path" && ! -L "$path" ]] || return 1
            identity="$(shell_regular_file_identity "$path" 2>/dev/null)" || return 1
            [[ "$identity" = "${shell_relevant_identities[$index]}" ]] || return 1
            cmp -s "$path" "${shell_relevant_snapshots[$index]}" || return 1
        done
    }

    shell_assert_agent_home() {
        local agent="$1" agent_home="$2" external="$3" home_physical agent_physical
        [[ "$agent_home" = /* && "$agent_home" != / && "$agent_home" != "$HOME" ]] || {
            echo "Error: Refusing unsafe agent home: $agent_home" >&2
            exit 1
        }
        [[ ! -L "$HOME" ]] || { echo "Error: Refusing symlinked HOME." >&2; exit 1; }
        if [[ "$external" = true ]]; then
            home_physical="$(shell_physical_path "$HOME")" || { echo "Error: Refusing unresolved HOME physical path." >&2; exit 1; }
            agent_physical="$(shell_physical_path "$agent_home")" || { echo "Error: Refusing unresolved CODEX_HOME physical path." >&2; exit 1; }
            if [[ "$agent_physical" = "$home_physical" ]] || { [[ "$agent_physical" = "${home_physical%/}/"* ]] && ! shell_is_child_path "$agent_home" "$HOME"; }; then
                echo "Error: Refusing CODEX_HOME with ambiguous physical identity: $agent_home" >&2
                exit 1
            fi
            shell_assert_no_symlink_ancestors "$agent_home" "$agent agent home"
        else
            shell_assert_no_symlink_ancestors "$agent_home" "$agent agent home" "$HOME"
        fi
    }

    shell_structured_config_requires_python() {
        local path="$1" scan_path="$2" byte_count disallowed_byte_count scan_status
        [[ -f "$scan_path" ]] || return 0

        byte_count="$(LC_ALL=C wc -c < "$scan_path")" || return 0
        case "$byte_count" in
            ""|*[!0-9\ ]*) return 0 ;;
        esac
        byte_count="${byte_count// /}"
        [[ -n "$byte_count" ]] || return 0
        (( 10#$byte_count <= 4194304 )) || return 0

        if LC_ALL=C grep -Fi 'memory-graph' "$scan_path" >/dev/null; then
            return 0
        else
            scan_status=$?
        fi
        [[ "$scan_status" -eq 1 ]] || return 0

        if LC_ALL=C grep -F $'\\' "$scan_path" >/dev/null; then
            return 0
        else
            scan_status=$?
        fi
        [[ "$scan_status" -eq 1 ]] || return 0

        disallowed_byte_count="$(LC_ALL=C tr -d '\011\012\015\040-\176' < "$scan_path" | LC_ALL=C wc -c)" || return 0
        case "$disallowed_byte_count" in
            ""|*[!0-9\ ]*) return 0 ;;
        esac
        disallowed_byte_count="${disallowed_byte_count// /}"
        [[ "$disallowed_byte_count" = 0 ]] || return 0

        return 1
    }

    shell_requires_structured_edit() {
        local path="$1" scan_path="$2" scan_status
        [[ -f "$scan_path" ]] || return 0
        case "$path" in
            *.json|*.toml) shell_structured_config_requires_python "$path" "$scan_path" ;;
            *)
                if grep -F 'ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_' "$scan_path" >/dev/null; then
                    return 0
                else
                    scan_status=$?
                fi
                [[ "$scan_status" -eq 1 ]] || return 0
                return 1
                ;;
        esac
    }

    shell_validate_retire_directory() {
        local target="$1" purpose="$2" traversal_root="$3"
        shell_assert_no_symlink_ancestors "$target" "$purpose" "$traversal_root"
        if [[ -e "$target" || -L "$target" ]]; then
            [[ -d "$target" && ! -L "$target" ]] || {
                echo "Error: Refusing unsafe retired $purpose target: $target" >&2
                exit 1
            }
        fi
    }

    shell_target_path_is_safe() {
        local path="$1" traversal_root="$2" current part relative
        local IFS='/'
        if [[ "$traversal_root" = / ]]; then
            current=/
            relative="${path#/}"
        else
            [[ "$path" = "${traversal_root%/}/"* && ! -L "$traversal_root" ]] || return 1
            current="$traversal_root"
            relative="${path#"$traversal_root"}"
        fi
        local -a parts
        read -r -a parts <<<"${relative#/}"
        for part in "${parts[@]}"; do
            [[ -n "$part" ]] || continue
            current="${current%/}/$part"
            if [[ -L "$current" ]] && ! shell_is_macos_var_alias "$current"; then
                return 1
            fi
        done
        [[ ! -L "$path" ]]
    }

    shell_revalidate_retirement_targets() {
        local index target traversal_root parent physical_identity parent_identity target_identity
        for index in "${!planned_targets[@]}"; do
            target="${planned_targets[$index]}"
            traversal_root="${planned_target_roots[$index]}"
            parent="${planned_target_parents[$index]}"
            shell_target_path_is_safe "$target" "$traversal_root" || return 1
            physical_identity="$(shell_physical_path "$target")" || return 1
            [[ "$physical_identity" = "${planned_target_identities[$index]}" ]] || return 1
            if [[ "${planned_target_parent_present[$index]}" = true ]]; then
                [[ -d "$parent" && ! -L "$parent" ]] || return 1
                parent_identity="$(shell_directory_identity "$parent" 2>/dev/null)" || return 1
                [[ "$parent_identity" = "${planned_target_parent_identities[$index]}" ]] || return 1
            else
                [[ ! -e "$parent" && ! -L "$parent" ]] || return 1
            fi
            if [[ "${planned_target_present[$index]}" = true ]]; then
                [[ -d "$target" && ! -L "$target" ]] || return 1
                target_identity="$(shell_directory_identity "$target" 2>/dev/null)" || return 1
                [[ "$target_identity" = "${planned_target_directory_identities[$index]}" ]] || return 1
            else
                [[ ! -e "$target" && ! -L "$target" ]] || return 1
            fi
        done
    }

    shell_retire_directory() {
        local index="$1" parent="${planned_target_parents[$1]}" basename="${planned_target_basenames[$1]}"
        local parent_identity="${planned_target_parent_identities[$1]}" target_identity="${planned_target_directory_identities[$1]}" original_dir retire_status
        shell_retire_guard_failed=false
        [[ "${planned_target_present[$index]}" = true ]] || return 0
        $dry_run && return 0
        original_dir="$(pwd -P)" || { shell_retire_guard_failed=true; return 1; }
        if ! cd -P -- "$parent"; then
            shell_retire_guard_failed=true
            return 1
        fi
        if [[ "$(shell_directory_identity . 2>/dev/null)" != "$parent_identity" ]] \
            || [[ ! -d "$basename" || -L "$basename" ]] \
            || [[ "$(shell_directory_identity "$basename" 2>/dev/null)" != "$target_identity" ]]; then
            shell_retire_guard_failed=true
            cd -P -- "$original_dir" || true
            return 1
        fi
        if ! shell_revalidate_relevant_files; then
            shell_retire_guard_failed=true
            cd -P -- "$original_dir" || true
            return 1
        fi
        if rm -rf -- "$basename"; then
            retire_status=0
        else
            retire_status=$?
        fi
        cd -P -- "$original_dir" || [[ "$retire_status" -ne 0 ]] || return 1
        return "$retire_status"
    }

    shell_append_retirement_target() {
        local target="$1" purpose="$2" traversal_root="$3" identity index parent target_present parent_present parent_identity target_identity
        shell_validate_retire_directory "$target" "$purpose" "$traversal_root"
        identity="$(shell_physical_path "$target")" || {
            echo "Error: Refusing unresolved retired $purpose target: $target" >&2
            exit 1
        }
        for index in "${!planned_target_identities[@]}"; do
            [[ "${planned_target_identities[$index]}" = "$identity" ]] && return
        done
        parent="${target%/*}"
        target_present=false
        parent_present=false
        parent_identity=""
        target_identity=""
        if [[ -e "$target" || -L "$target" ]]; then
            target_present=true
            target_identity="$(shell_directory_identity "$target" 2>/dev/null)" || shell_require_python
        fi
        if [[ -e "$parent" || -L "$parent" ]]; then
            [[ -d "$parent" && ! -L "$parent" ]] || shell_require_python
            parent_present=true
            parent_identity="$(shell_directory_identity "$parent" 2>/dev/null)" || shell_require_python
        fi
        planned_targets+=("$target")
        planned_target_identities+=("$identity")
        planned_target_roots+=("$traversal_root")
        planned_target_purposes+=("$purpose")
        planned_target_parents+=("$parent")
        planned_target_basenames+=("${target##*/}")
        planned_target_present+=("$target_present")
        planned_target_parent_present+=("$parent_present")
        planned_target_parent_identities+=("$parent_identity")
        planned_target_directory_identities+=("$target_identity")
    }

    agents=("$agent_filter")
    [[ -n "$agent_filter" ]] || agents=(claude codex gemini)
    shell_snapshot_dir=""
    shell_snapshot_directory_identity=""
    shell_relevant_paths=()
    shell_relevant_roots=()
    shell_relevant_present=()
    shell_relevant_identities=()
    shell_relevant_snapshots=()
    for agent in "${agents[@]}"; do
        external=false
        if [[ "$agent" = codex && -n "$cleanup_codex_home" ]]; then
            agent_home="$cleanup_codex_home"
            external=true
        else
            agent_home="$HOME/.$agent"
        fi
        shell_assert_agent_home "$agent" "$agent_home" "$external"
        instruction_name=GEMINI.md
        [[ "$agent" = claude ]] && instruction_name=CLAUDE.md
        [[ "$agent" = codex ]] && instruction_name=AGENTS.md
        config_paths=("$agent_home/$instruction_name")
        if [[ "$agent" = codex ]]; then
            config_paths+=("$agent_home/config.toml")
        else
            config_paths+=("$agent_home/settings.json")
            [[ "$agent" = claude ]] && config_paths+=("$HOME/.claude.json")
        fi
        for config_path in "${config_paths[@]}"; do
            if [[ "$config_path" = "$HOME/"* && "$config_path" != "$agent_home/"* ]]; then
                config_traversal_root="$HOME"
            elif [[ "$external" = true ]]; then
                config_traversal_root=/
            else
                config_traversal_root="$agent_home"
            fi
            if ! shell_relevant_path_is_safe "$config_path" "$config_traversal_root"; then
                echo "Error: Refusing unsafe relevant configuration or instructions file: $config_path" >&2
                exit 1
            fi
            shell_capture_relevant_file "$config_path" "$config_traversal_root" || shell_require_python
            config_index=$((${#shell_relevant_paths[@]} - 1))
            if [[ "${shell_relevant_present[$config_index]}" = true ]] \
                && shell_requires_structured_edit "$config_path" "${shell_relevant_snapshots[$config_index]}"; then
                shell_require_python
            fi
        done
    done

    planned_targets=()
    planned_target_identities=()
    planned_target_roots=()
    planned_target_purposes=()
    planned_target_parents=()
    planned_target_basenames=()
    planned_target_present=()
    planned_target_parent_present=()
    planned_target_parent_identities=()
    planned_target_directory_identities=()
    # Plan every exact deletion before mutating any selected agent. In
    # particular, a later unsafe target must not permit partial retirement of
    # an earlier otherwise-safe agent installation.
    for agent in "${agents[@]}"; do
        if [[ "$agent" = codex && -n "$cleanup_codex_home" ]]; then
            agent_home="$cleanup_codex_home"
            traversal_root=/
        else
            agent_home="$HOME/.$agent"
            traversal_root="$agent_home"
        fi
        if [[ "$agent" = codex ]]; then
            native_anchor="$HOME/.agents"
            if [[ -L "$native_anchor" ]]; then
                native_identity="$(shell_physical_path "$native_anchor/skills")" || {
                    echo "Error: Refusing unresolved Codex native skills root: $native_anchor" >&2
                    exit 1
                }
                legacy_identity="$(shell_physical_path "$agent_home/skills")" || {
                    echo "Error: Refusing unresolved Codex legacy skills root: $agent_home/skills" >&2
                    exit 1
                }
                [[ "$native_identity" = "$legacy_identity" ]] || {
                    echo "Error: Refusing Codex native skills root through symlink: $native_anchor" >&2
                    exit 1
                }
                native_skills_root="$agent_home/skills"
                native_traversal_root="$agent_home"
            else
                native_skills_root="$native_anchor/skills"
                native_traversal_root="$HOME"
            fi
            shell_append_retirement_target "$native_skills_root/assistant-memory" "Codex native skill" "$native_traversal_root"
            shell_append_retirement_target "$native_skills_root/assistant-reflexion" "Codex native skill" "$native_traversal_root"
        fi
        shell_append_retirement_target "$agent_home/skills/assistant-memory" "skill" "$traversal_root"
        shell_append_retirement_target "$agent_home/skills/assistant-reflexion" "skill" "$traversal_root"
        shell_append_retirement_target "$agent_home/tools/memory-graph" "tool" "$traversal_root"
        if $purge_data; then shell_append_retirement_target "$agent_home/memory" "memory data" "$traversal_root"; fi
    done

    shell_revalidate_relevant_files || shell_require_python
    shell_revalidate_retirement_targets || shell_require_python
    for target_index in "${!planned_targets[@]}"; do
        if shell_retire_directory "$target_index"; then
            :
        else
            retire_status=$?
            $shell_retire_guard_failed && shell_require_python
            exit "$retire_status"
        fi
    done
    for agent in "${agents[@]}"; do
        if $dry_run; then echo "[dry-run] Retire Memory Graph artifacts for $agent"; fi
    done
    echo "Retired Assistant Framework Memory Graph artifacts."
    exit 0
fi

"$python_bin" - "$HOME" "$cleanup_codex_home" "$agent_filter" "$dry_run" "$purge_data" <<'PY'
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile

home_text, codex_home_text, agent_filter, dry_run_text, purge_text = sys.argv[1:]
dry_run = dry_run_text == "true"
purge_data = purge_text == "true"
MAX_STRUCTURED_BYTES = 4 * 1024 * 1024


class CleanupError(RuntimeError):
    pass


class SourceSnapshot:
    def __init__(self, raw, stat_result, structured=False):
        self.raw = raw
        self.structured = structured
        self.identity = (
            stat_result.st_dev,
            stat_result.st_ino,
            stat_result.st_mode,
            stat_result.st_size,
            stat_result.st_mtime_ns,
            stat_result.st_ctime_ns,
        )


def fail(message):
    raise CleanupError(message)


def concise_cleanup_error(error_type, error, traceback):
    if issubclass(error_type, CleanupError):
        print("Error: %s" % error, file=sys.stderr)
        return
    sys.__excepthook__(error_type, error, traceback)


sys.excepthook = concise_cleanup_error


def full(path):
    return os.path.abspath(path)


if codex_home_text and (not os.path.isabs(codex_home_text) or codex_home_text == os.path.sep or codex_home_text.startswith("//")):
    fail("CODEX_HOME must be a non-root absolute path.")


home = full(home_text)
if home == os.path.sep or not os.path.isabs(home):
    fail("HOME must be a non-root absolute path.")
if os.path.lexists(home) and stat.S_ISLNK(os.lstat(home).st_mode):
    fail("Refusing symlinked HOME.")


def assert_no_symlink(path, purpose, all_ancestors=False):
    path = full(path)
    # System prefixes such as /var may themselves be compatibility symlinks on
    # macOS. The owned boundary starts at HOME; inspect every component below it.
    if all_ancestors:
        current = os.path.sep
        components = [part for part in path.split(os.path.sep) if part]
    elif os.path.commonpath([home, path]) == home:
        current = home
        relative = os.path.relpath(path, home)
        components = [] if relative == "." else relative.split(os.path.sep)
    else:
        current = os.path.dirname(path)
        components = [os.path.basename(path)]
    for component in components:
        current = os.path.join(current, component)
        if os.path.lexists(current) and stat.S_ISLNK(os.lstat(current).st_mode):
            if current == "/var" and os.path.realpath(current) == "/private/var":
                continue
            fail("Refusing %s through symlink: %s" % (purpose, current))
    return path


def assert_child(root, target, purpose):
    root, target = full(root), full(target)
    try:
        is_child = os.path.commonpath([root, target]) == root and target != root
    except ValueError:
        is_child = False
    if not is_child or target == os.path.sep or target == home:
        fail("Refusing unsafe %s target: %s" % (purpose, target))
    assert_no_symlink(target, purpose, os.path.commonpath([home, target]) != home)
    return target


def unique_safe_paths(paths):
    unique, identities = [], set()
    for path in paths:
        identity = os.path.realpath(path)
        if identity in identities:
            continue
        identities.add(identity)
        unique.append(path)
    return unique


def codex_native_skills_root(agent_home):
    native_anchor = os.path.join(home, ".agents")
    native_root = os.path.join(native_anchor, "skills")
    if os.path.lexists(native_anchor) and stat.S_ISLNK(os.lstat(native_anchor).st_mode):
        expected = os.path.join(os.path.realpath(agent_home), "skills")
        if os.path.realpath(native_root) != expected:
            fail("Refusing Codex native skills root through symlink: %s" % native_anchor)
        return assert_child(agent_home, os.path.join(agent_home, "skills"), "Codex native skills root")
    return assert_child(home, native_root, "Codex native skills root")


def read_regular_source(path, structured=False):
    try:
        before = os.lstat(path)
    except OSError:
        fail("Unable to read expected source file %s; preserved unchanged." % path)
    if stat.S_ISLNK(before.st_mode) or not stat.S_ISREG(before.st_mode):
        fail("Refusing unsafe source file: %s" % path)
    if structured and before.st_size > MAX_STRUCTURED_BYTES:
        fail("Structured configuration in %s exceeds the 4 MiB safety limit; preserved unchanged." % path)
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
        with os.fdopen(descriptor, "rb") as handle:
            opened = os.fstat(handle.fileno())
            if not stat.S_ISREG(opened.st_mode) or (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino):
                fail("Source file identity changed while reading %s; preserved unchanged." % path)
            raw = handle.read()
            after_open = os.fstat(handle.fileno())
    except OSError:
        fail("Unable to read expected source file %s; preserved unchanged." % path)
    try:
        after_path = os.lstat(path)
    except OSError:
        fail("Source file identity changed while reading %s; preserved unchanged." % path)
    snapshot = SourceSnapshot(raw, after_open, structured)
    if stat.S_ISLNK(after_path.st_mode) or snapshot.identity != SourceSnapshot(raw, after_path).identity:
        fail("Source file identity changed while reading %s; preserved unchanged." % path)
    return snapshot


def assert_expected_source(path, expected, purpose="source", ignore_ctime=False):
    actual = read_regular_source(path, expected.structured)
    actual_identity = actual.identity[:-1] if ignore_ctime else actual.identity
    expected_identity = expected.identity[:-1] if ignore_ctime else expected.identity
    if actual_identity != expected_identity or actual.raw != expected.raw:
        fail("%s changed after planning in %s; preserved unchanged." % (purpose.capitalize(), path))


def read_utf8(path, structured=False):
    source = read_regular_source(path, structured)
    raw = source.raw
    bom = raw.startswith(b"\xef\xbb\xbf")
    try:
        return bom, raw[3 if bom else 0:].decode("utf-8", "strict"), source
    except UnicodeDecodeError:
        fail("Invalid UTF-8 in %s; preserved unchanged." % path)


def encode_utf8(bom, content):
    return (b"\xef\xbb\xbf" if bom else b"") + content.encode("utf-8", "strict")


def write_atomic(path, content, expected):
    assert_expected_source(path, expected)
    mode = stat.S_IMODE(os.stat(path).st_mode)
    directory = os.path.dirname(path)
    fd, temp = tempfile.mkstemp(prefix=".assistant-framework-retire-", dir=directory)
    backup = None
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(content)
        os.chmod(temp, mode)
        assert_expected_source(path, expected, "source immediately before commit")
        backup_fd, backup = tempfile.mkstemp(prefix=".assistant-framework-retire-backup-", dir=directory)
        os.close(backup_fd)
        os.unlink(backup)
        os.link(path, backup)
        assert_expected_source(backup, expected, "displaced backup", ignore_ctime=True)
        os.replace(temp, path)
        temp = None
    except BaseException:
        try:
            if temp is not None:
                os.unlink(temp)
        except OSError:
            pass
        raise
    finally:
        if backup is not None:
            try:
                os.unlink(backup)
            except OSError:
                pass


def strict_json_document(text, path):
    try:
        root = JsonScanner(text).document()
        json.loads(
            text,
            parse_constant=lambda value: fail(
                "Invalid JSON constant in %s; preserved unchanged." % path
            ),
        )
        return root
    except (RuntimeError, ValueError, json.JSONDecodeError):
        fail("Invalid or ambiguous JSON in %s; preserved unchanged." % path)


def toml_validation_text(text):
    # Earlier installers wrote a UTF-8 BOM at every physical line when their
    # format string was repeated. Treat that exact legacy transport artifact as
    # line-leading encoding metadata while preserving original output bytes.
    return text.replace("\n\ufeff", "\n")


def codex_mcp_names(text, path):
    # Codex is the semantic authority for existing Codex configuration. Stage
    # each read-only query in an isolated home; it is never used as an editor.
    codex = shutil.which("codex")
    if not codex:
        fail("Codex CLI semantic validation is unavailable for %s; preserved unchanged." % path)
    with tempfile.TemporaryDirectory(prefix="assistant-framework-toml-") as isolated_root:
        staged_home = os.path.join(isolated_root, "home")
        staged_config = os.path.join(staged_home, "config.toml")
        staged_cache = os.path.join(isolated_root, "cache")
        staged_state = os.path.join(isolated_root, "state")
        staged_temp = os.path.join(isolated_root, "tmp")
        os.makedirs(staged_home)
        os.makedirs(staged_cache)
        os.makedirs(staged_state)
        os.makedirs(staged_temp)
        with open(staged_config, "w", encoding="utf-8", newline="") as handle:
            handle.write(toml_validation_text(text))
        environment = os.environ.copy()
        environment.update({
            "CODEX_HOME": staged_home,
            "HOME": staged_home,
            "XDG_CACHE_HOME": staged_cache,
            "XDG_CONFIG_HOME": staged_cache,
            "XDG_DATA_HOME": staged_state,
            "XDG_STATE_HOME": staged_state,
            "NPM_CONFIG_CACHE": staged_cache,
            "TMPDIR": staged_temp,
            "TEMP": staged_temp,
            "TMP": staged_temp,
        })
        result = subprocess.run(
            [codex, "mcp", "list", "--json"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
            cwd=staged_home,
            timeout=10,
            check=False,
        )
    if result.returncode != 0:
        return None
    try:
        if len(result.stdout) > MAX_STRUCTURED_BYTES:
            fail("Codex CLI JSON output for %s exceeds the 4 MiB safety limit; preserved unchanged." % path)
        payload_text = result.stdout.decode("utf-8", "strict")
    except UnicodeDecodeError:
        fail("Invalid Codex CLI JSON output for %s; preserved unchanged." % path)
    return strict_authority_names(payload_text, path)


def toml_string_state(line, active):
    quote = None
    escaped = False
    index = 0
    while index < len(line):
        if active:
            delimiter = '\"\"\"' if active == 'basic' else "'''"
            if line.startswith(delimiter, index):
                backslashes = 0
                previous = index - 1
                while active == 'basic' and previous >= 0 and line[previous] == '\\':
                    backslashes += 1
                    previous -= 1
                if active != 'basic' or backslashes % 2 == 0:
                    active = None
                    index += 3
                    continue
            index += 1
            continue
        char = line[index]
        if quote:
            if quote == 'basic' and char == '\\' and not escaped:
                escaped = True
            elif char == ('\"' if quote == 'basic' else "'") and not escaped:
                quote = None
            else:
                escaped = False
            index += 1
            continue
        if char == '#':
            break
        if line.startswith('\"\"\"', index):
            active = 'basic'
            index += 3
        elif line.startswith("'''", index):
            active = 'literal'
            index += 3
        elif char == '\"':
            quote = 'basic'
            index += 1
        elif char == "'":
            quote = 'literal'
            index += 1
        else:
            index += 1
    if quote:
        fail("Ambiguous TOML string syntax; preserved unchanged.")
    return active


def toml_basic_key(raw):
    value, index = [], 0
    escapes = {"b": "\b", "t": "\t", "n": "\n", "f": "\f", "r": "\r", '"': '"', "\\": "\\"}
    while index < len(raw):
        char = raw[index]
        if char != "\\":
            value.append(char)
            index += 1
            continue
        index += 1
        if index >= len(raw):
            fail("Ambiguous TOML basic key escape; preserved unchanged.")
        escape = raw[index]
        index += 1
        if escape in escapes:
            value.append(escapes[escape])
        elif escape in ("u", "U"):
            width = 4 if escape == "u" else 8
            digits = raw[index:index + width]
            if len(digits) != width or not re.fullmatch(r"[0-9A-Fa-f]{%d}" % width, digits):
                fail("Ambiguous TOML basic key escape; preserved unchanged.")
            value.append(chr(int(digits, 16)))
            index += width
        else:
            fail("Ambiguous TOML basic key escape; preserved unchanged.")
    return "".join(value)


def toml_table_path(body):
    index, segments = 0, []
    while True:
        while index < len(body) and body[index].isspace():
            index += 1
        if index >= len(body):
            fail("Ambiguous TOML table identity; preserved unchanged.")
        if body[index] == '"':
            index += 1
            start, escaped = index, False
            while index < len(body):
                char = body[index]
                if char == '"' and not escaped:
                    break
                if char == "\\" and not escaped:
                    escaped = True
                else:
                    escaped = False
                index += 1
            if index >= len(body):
                fail("Ambiguous TOML table identity; preserved unchanged.")
            segments.append(toml_basic_key(body[start:index]))
            index += 1
        elif body[index] == "'":
            index += 1
            end = body.find("'", index)
            if end < 0:
                fail("Ambiguous TOML table identity; preserved unchanged.")
            segments.append(body[index:end])
            index = end + 1
        else:
            match = re.match(r"[A-Za-z0-9_-]+", body[index:])
            if not match:
                fail("Ambiguous TOML table identity; preserved unchanged.")
            segments.append(match.group(0))
            index += len(match.group(0))
        while index < len(body) and body[index].isspace():
            index += 1
        if index == len(body):
            return ".".join(segments)
        if body[index] != ".":
            fail("Ambiguous TOML table identity; preserved unchanged.")
        index += 1


def table_name(line):
    line = line.lstrip("\ufeff").rstrip("\r\n")
    match = re.match(r"^\s*(\[\[?|\[)(.*?)(\]\]|\])\s*(?:#.*)?$", line)
    if not match or (match.group(1) == "[[") != (match.group(3) == "]]" ):
        return None
    return toml_table_path(match.group(2))


def remove_toml_memory_graph(path):
    bom, text, source = read_utf8(path, structured=True)
    lines = text.splitlines(keepends=True)
    active = None
    parsed = []
    for line in lines:
        name = None if active else table_name(line)
        parsed.append(name)
        active = toml_string_state(line, active)
    if active:
        fail("Ambiguous TOML multiline string in %s; preserved unchanged." % path)

    offsets, position = [], 0
    for line in lines:
        offsets.append(position)
        position += len(line)
    headers = [index for index, name in enumerate(parsed) if name is not None]
    spans = []
    for header_position, line_index in enumerate(headers):
        name = parsed[line_index]
        if name == "mcp_servers.memory-graph" or name.startswith("mcp_servers.memory-graph."):
            end_line = headers[header_position + 1] if header_position + 1 < len(headers) else len(lines)
            spans.append((offsets[line_index], offsets[end_line] if end_line < len(lines) else len(text)))

    source_names = codex_mcp_names(text, path)
    if source_names is not None and "memory-graph" not in source_names:
        if spans:
            fail("Codex semantic authority disagrees with the local Memory Graph edit span in %s; preserved unchanged." % path)
        return "proven_absent", None, source
    if not spans:
        if source_names is None:
            fail("Invalid or ambiguous TOML in %s; preserved unchanged." % path)
        fail("Codex semantic authority found Memory Graph without a safe exact edit span in %s; preserved unchanged." % path)

    fragments, cursor = [], 0
    for start, end in spans:
        fragments.append(text[cursor:start])
        cursor = end
    updated = "".join(fragments) + text[cursor:]
    candidate_names = codex_mcp_names(updated, path)
    if candidate_names is None:
        fail("Invalid or ambiguous TOML in %s after removing exact retired spans; preserved unchanged." % path)
    if "memory-graph" in candidate_names:
        fail("Memory Graph registration remains in %s; preserved unchanged." % path)
    return "removed", encode_utf8(bom, updated), source


class JsonScanner:
    scalar = re.compile(r'(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)')

    def __init__(self, text):
        self.text, self.index, self.properties, self.values = text, 0, 0, 0

    def whitespace(self):
        while self.index < len(self.text) and self.text[self.index] in ' \t\r\n':
            self.index += 1

    def string(self, decode=False):
        if self.index >= len(self.text) or self.text[self.index] != '"':
            fail('Invalid JSON identity scan: expected a string.')
        start = self.index
        self.index += 1
        escaped = False
        while self.index < len(self.text):
            char = self.text[self.index]
            self.index += 1
            if escaped:
                escaped = False
            elif char == '\\':
                escaped = True
            elif char == '"':
                raw = self.text[start:self.index]
                try:
                    value = json.loads(raw)
                except json.JSONDecodeError:
                    fail('Invalid JSON identity scan: invalid string escape.')
                return value if decode else None
        fail('Invalid JSON identity scan: unterminated string.')

    def value(self, depth=0):
        if depth > 64:
            fail('Unsafe JSON complexity: nesting exceeds 64 levels.')
        self.values += 1
        if self.values > 10000:
            fail('Unsafe JSON complexity: value count exceeds 10000.')
        self.whitespace()
        start = self.index
        if start >= len(self.text):
            fail('Invalid JSON identity scan: missing value.')
        char = self.text[start]
        if char == '{': return self.object(depth)
        if char == '[': return self.array(depth)
        if char == '"':
            self.string()
            return {'kind': 'string', 'start': start, 'end': self.index}
        match = self.scalar.match(self.text, self.index)
        if match is None:
            fail('Invalid JSON identity scan: invalid value.')
        self.index = match.end()
        if self.index < len(self.text) and self.text[self.index] not in ',}] \t\r\n':
            fail('Invalid JSON identity scan: invalid value.')
        return {'kind': 'scalar', 'start': start, 'end': self.index}

    def object(self, depth):
        start = self.index
        self.index += 1
        self.whitespace()
        props, exact, folded = [], set(), set()
        if self.index < len(self.text) and self.text[self.index] == '}':
            self.index += 1
            return {'kind': 'object', 'start': start, 'end': self.index, 'props': props}
        while True:
            prop_start = self.index
            key = self.string(True)
            self.properties += 1
            if self.properties > 10000:
                fail('Unsafe JSON complexity: property count exceeds 10000.')
            if key in exact:
                fail("Unsafe JSON property identity: duplicate member '%s'." % key)
            folded_key = key.casefold()
            if folded_key in folded:
                fail("Unsafe JSON property identity: case-colliding member '%s'." % key)
            exact.add(key); folded.add(folded_key)
            self.whitespace()
            if self.index >= len(self.text) or self.text[self.index] != ':':
                fail('Invalid JSON identity scan: expected a colon.')
            self.index += 1
            value = self.value(depth + 1)
            self.whitespace()
            prop = {'key': key, 'start': prop_start, 'end': value['end'], 'value': value, 'comma': None}
            props.append(prop)
            if self.index >= len(self.text):
                fail('Invalid JSON identity scan: unterminated object.')
            if self.text[self.index] == '}':
                self.index += 1
                return {'kind': 'object', 'start': start, 'end': self.index, 'props': props}
            if self.text[self.index] != ',':
                fail('Invalid JSON identity scan: expected an object separator.')
            prop['comma'] = self.index
            self.index += 1
            self.whitespace()

    def array(self, depth):
        start = self.index
        self.index += 1
        self.whitespace()
        if self.index < len(self.text) and self.text[self.index] == ']':
            self.index += 1
            return {'kind': 'array', 'start': start, 'end': self.index, 'values': []}
        values = []
        while True:
            values.append(self.value(depth + 1))
            self.whitespace()
            if self.index >= len(self.text):
                fail('Invalid JSON identity scan: unterminated array.')
            if self.text[self.index] == ']':
                self.index += 1
                return {'kind': 'array', 'start': start, 'end': self.index, 'values': values}
            if self.text[self.index] != ',':
                fail('Invalid JSON identity scan: expected an array separator.')
            self.index += 1
            self.whitespace()

    def document(self):
        root = self.value()
        self.whitespace()
        if self.index != len(self.text):
            fail('Invalid JSON identity scan: trailing content.')
        return root


def strict_authority_names(text, path):
    root = strict_json_document(text, path)
    if root["kind"] != "array":
        fail("Invalid Codex CLI JSON output for %s; preserved unchanged." % path)
    names = set()
    folded_names = set()
    for item in root["values"]:
        if item["kind"] != "object":
            fail("Invalid Codex CLI JSON output for %s; preserved unchanged." % path)
        name_props = [prop for prop in item["props"] if prop["key"] == "name"]
        if len(name_props) != 1 or name_props[0]["value"]["kind"] != "string":
            fail("Invalid Codex CLI JSON output for %s; preserved unchanged." % path)
        name = json.loads(text[name_props[0]["value"]["start"]:name_props[0]["value"]["end"]])
        if not name or name.strip() != name or any(ord(char) < 0x20 or ord(char) == 0x7f for char in name):
            fail("Invalid Codex CLI MCP identity for %s; preserved unchanged." % path)
        folded_name = name.casefold()
        if name in names or folded_name in folded_names:
            fail("Ambiguous Codex CLI MCP identity for %s; preserved unchanged." % path)
        names.add(name)
        folded_names.add(folded_name)
    return names


def remove_json_memory_graph(path):
    bom, text, source = read_utf8(path, structured=True)
    root = strict_json_document(text, path)
    if root['kind'] != 'object':
        fail('JSON root in %s is not an object; preserved unchanged.' % path)
    servers = next((prop for prop in root['props'] if prop['key'] == 'mcpServers'), None)
    if servers is None:
        return "proven_absent", None, source
    if servers['value']['kind'] != 'object':
        fail('mcpServers in %s is not an object; preserved unchanged.' % path)
    props = servers['value']['props']
    entry_index = next((index for index, prop in enumerate(props) if prop['key'] == 'memory-graph'), None)
    if entry_index is None:
        return "proven_absent", None, source
    entry = props[entry_index]
    if len(props) == 1:
        delete_start, delete_end = entry['start'], entry['end']
    elif entry_index:
        delete_start, delete_end = props[entry_index - 1]['comma'], entry['end']
    else:
        delete_start, delete_end = entry['start'], entry['comma'] + 1
    updated = text[:delete_start] + text[delete_end:]
    strict_json_document(updated, path)
    return "removed", encode_utf8(bom, updated), source


def validate_marker_state(lines, path):
    markers = {
        "<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_START -->": ("agents", "start"),
        "<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_END -->": ("agents", "end"),
        "<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->": ("memory", "start"),
        "<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->": ("memory", "end"),
    }
    counts = {"agents": 0, "memory": 0}
    open_kind = None
    for line in lines:
        marker = markers.get(line.strip())
        if marker is None:
            continue
        kind, action = marker
        if action == "start":
            counts[kind] += 1
            if counts[kind] != 1 or open_kind is not None:
                fail("Ambiguous, duplicate, or unbalanced Assistant Framework markers in %s; preserved unchanged." % path)
            open_kind = kind
        elif open_kind != kind:
            fail("Ambiguous, duplicate, or unbalanced Assistant Framework markers in %s; preserved unchanged." % path)
        else:
            open_kind = None
    if open_kind is not None:
        fail("Ambiguous, duplicate, or unbalanced Assistant Framework markers in %s; preserved unchanged." % path)


def remove_protocol(path):
    bom, text, source = read_utf8(path)
    lines = text.splitlines(keepends=True)
    validate_marker_state(lines, path)
    start, end = "<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->", "<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->"
    starts = [index for index, line in enumerate(lines) if line.strip() == start]
    ends = [index for index, line in enumerate(lines) if line.strip() == end]
    if not starts and not ends:
        return None, source
    if len(starts) != 1 or len(ends) != 1 or starts[0] > ends[0]:
        fail("Ambiguous Memory Graph instruction markers in %s; preserved unchanged." % path)

    def is_legacy_protocol_preamble_line(raw_line):
        line = raw_line.rstrip("\r\n")
        return (
            line == ""
            or line == "# Assistant Framework — Memory Protocol"
            or line == "## Role"
            or (
                line.startswith("You are an orchestrator for memory-aware workflow.")
                and "The orchestrator may create and update framework-owned state artifacts such as ." in line
                and "/task.md, ." in line
                and "/context-map.md, ." in line
                and "/session.md, and ." in line
                and "/working-buffer.md; it does not edit project source files directly." in line
            )
            or line == "You are an orchestrator for memory-aware workflow. Coordinate specialized agents and preserve workflow state while memory_context supplies project rules, preferences, and recent insights. File edits, code implementation, builds/tests, and independent review remain owned by the appropriate specialized agent; your role is dispatch, phase gates, progress tracking, communication, and memory protocol enforcement. The orchestrator does not edit files or write code directly. When a skill matches your task, invoke it and follow its instructions."
            or (
                line.startswith("You are an orchestrator. You delegate ALL file editing")
                and "code implementation, and phase execution" in line
            )
            or re.match(r"^<!-- This is a template\. Paths like ~/\.(claude|codex|gemini)/", line) is not None
            or line.startswith("<!-- Appended by Assistant Framework install.")
        )

    preamble_start = starts[0]
    while preamble_start > 0 and is_legacy_protocol_preamble_line(lines[preamble_start - 1]):
        preamble_start -= 1
    if any(line.rstrip("\r\n") == "# Assistant Framework — Memory Protocol" for line in lines[preamble_start:starts[0]]):
        starts[0] = preamble_start
    return encode_utf8(bom, "".join(lines[:starts[0]] + lines[ends[0] + 1:])), source


agents = [agent_filter] if agent_filter else ["claude", "codex", "gemini"]
plans = []
for agent in agents:
    agent_home = full(codex_home_text) if agent == "codex" and codex_home_text else os.path.join(home, "." + agent)
    if agent_home in (home, os.path.sep):
        fail("Refusing unsafe agent home: %s" % agent_home)
    if agent == "codex" and codex_home_text:
        home_physical = os.path.realpath(home)
        agent_physical = os.path.realpath(agent_home)
        if agent_physical == home_physical or (agent_physical.startswith(home_physical.rstrip(os.path.sep) + os.path.sep) and not agent_home.startswith(home.rstrip(os.path.sep) + os.path.sep)):
            fail("Refusing CODEX_HOME with ambiguous physical identity: %s" % agent_home)
    assert_no_symlink(agent_home, "%s agent home" % agent, agent == "codex" and bool(codex_home_text))
    if agent == "codex":
        skill_roots = unique_safe_paths([
            codex_native_skills_root(agent_home),
            assert_child(agent_home, os.path.join(agent_home, "skills"), "Codex legacy skills root"),
        ])
    else:
        skill_roots = [assert_child(agent_home, os.path.join(agent_home, "skills"), "agent skills root")]
    targets = []
    for skill_root in skill_roots:
        targets.extend([
            assert_child(skill_root, os.path.join(skill_root, "assistant-memory"), "retired skill"),
            assert_child(skill_root, os.path.join(skill_root, "assistant-reflexion"), "retired skill"),
        ])
    runtime_target = assert_child(agent_home, os.path.join(agent_home, "tools", "memory-graph"), "retired tool")
    targets.append(runtime_target)
    if purge_data:
        targets.append(assert_child(agent_home, os.path.join(agent_home, "memory"), "explicitly purged memory data"))
    targets = unique_safe_paths(targets)
    instructions = {"claude": "CLAUDE.md", "codex": "AGENTS.md", "gemini": "GEMINI.md"}[agent]
    instruction_path = assert_child(agent_home, os.path.join(agent_home, instructions), "instructions")
    configs = []
    if agent == "codex":
        configs.append((assert_child(agent_home, os.path.join(agent_home, "config.toml"), "Codex configuration"), remove_toml_memory_graph))
    else:
        configs.append((assert_child(agent_home, os.path.join(agent_home, "settings.json"), "agent settings"), remove_json_memory_graph))
        if agent == "claude":
            configs.append((assert_child(home, os.path.join(home, ".claude.json"), "Claude configuration"), remove_json_memory_graph))
    tool_parent = os.path.dirname(runtime_target)
    # Retire the now-empty framework-owned tools container only when the exact
    # retired target was its sole entry. This prevents a later reinstall from
    # treating a replacement tools symlink as an ordinary sibling, while any
    # user-owned sibling keeps the parent in place unchanged.
    prune_tool_parent = (
        os.path.isdir(tool_parent)
        and not os.path.islink(tool_parent)
        and os.path.lexists(runtime_target)
        and os.listdir(tool_parent) == ["memory-graph"]
    )
    managed_boundaries = unique_safe_paths(skill_roots + [tool_parent])
    plans.append((agent, agent_home, targets, instruction_path, configs, prune_tool_parent, managed_boundaries))

# Validate every affected artifact before changing any configuration or file.
updates = []
for agent, agent_home, targets, instruction_path, configs, prune_tool_parent, managed_boundaries in plans:
    for boundary in managed_boundaries:
        if os.path.lexists(boundary) and stat.S_ISLNK(os.lstat(boundary).st_mode):
            fail("Refusing configured managed boundary symlink: %s" % boundary)
    for target in targets:
        if os.path.lexists(target):
            item = os.lstat(target)
            if stat.S_ISLNK(item.st_mode) or not stat.S_ISDIR(item.st_mode):
                fail("Refusing unsafe retired %s target: %s" % (agent, target))
    if os.path.lexists(instruction_path):
        if stat.S_ISLNK(os.lstat(instruction_path).st_mode) or not stat.S_ISREG(os.lstat(instruction_path).st_mode):
            fail("Refusing unsafe instructions file: %s" % instruction_path)
        content, source = remove_protocol(instruction_path)
        if content is not None:
            updates.append((instruction_path, content, source))
    for path, remover in configs:
        if os.path.lexists(path):
            if stat.S_ISLNK(os.lstat(path).st_mode) or not stat.S_ISREG(os.lstat(path).st_mode):
                fail("Refusing unsafe configuration file: %s" % path)
            outcome, content, source = remover(path)
            if outcome == "removed":
                updates.append((path, content, source))
            elif outcome != "proven_absent":
                fail("Ambiguous configuration outcome for %s; preserved unchanged." % path)

if dry_run:
    for agent, agent_home, targets, instruction_path, configs, prune_tool_parent, managed_boundaries in plans:
        print("[dry-run] Retire Memory Graph artifacts for %s" % agent)
    sys.exit(0)

for path, content, source in updates:
    assert_expected_source(path, source, "source before writes")
for path, content, source in updates:
    write_atomic(path, content, source)
for agent, agent_home, targets, instruction_path, configs, prune_tool_parent, managed_boundaries in plans:
    for target in targets:
        if os.path.lexists(target):
            shutil.rmtree(target)
    if prune_tool_parent and os.path.isdir(os.path.join(agent_home, "tools")):
        os.rmdir(os.path.join(agent_home, "tools"))
print("Retired Assistant Framework Memory Graph artifacts.")
PY
