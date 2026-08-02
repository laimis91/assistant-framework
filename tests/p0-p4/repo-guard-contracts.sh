if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "tests tree has no .DS_Store files"
ds_store_file="$(find "$SCRIPT_DIR" -type f -name .DS_Store -print | sed -n '1p')"
if [[ -z "$ds_store_file" ]]; then
    pass
else
    fail "unexpected .DS_Store file under tests/: $ds_store_file"
fi

test_start "general CI covers framework contracts, installs, and mirrors without retired runtime jobs"
framework_validation_workflow="$FRAMEWORK_DIR/.github/workflows/framework-validation.yml"
framework_validation_failures=()
if [[ ! -f "$framework_validation_workflow" ]]; then
    framework_validation_failures+=("missing .github/workflows/framework-validation.yml")
else
    for term in \
        "pull_request:" \
        "push:" \
        "contents: read" \
        "persist-credentials: false" \
        "timeout-minutes: 30" \
        "./tests/test-p0-p4-contracts.sh" \
        "tools/skills/validate-skills.sh" \
        "tools/plugins/sync-plugin-skills.sh --check" \
        "./install.sh --agent codex --dry-run" \
        "./install.sh --agent claude --dry-run" \
        "./install.sh --agent gemini --dry-run"; do
        if ! grep -Fq -- "$term" "$framework_validation_workflow"; then
            framework_validation_failures+=("framework-validation.yml: $term")
        fi
    done

    [[ "$(grep -Ec '^[[:space:]]+uses: actions/checkout@v5[[:space:]]*$' "$framework_validation_workflow")" -eq 1 ]] \
        || framework_validation_failures+=("framework-validation.yml: expected one checkout@v5 step")
    [[ "$(grep -Ec '^[[:space:]]+persist-credentials: false[[:space:]]*$' "$framework_validation_workflow")" -eq 1 ]] \
        || framework_validation_failures+=("framework-validation.yml: the checkout must disable credential persistence")
    [[ "$(grep -Ec '^[[:space:]]+timeout-minutes: 30[[:space:]]*$' "$framework_validation_workflow")" -eq 1 ]] \
        || framework_validation_failures+=("framework-validation.yml: the framework-contract job must use the bounded timeout")
    [[ "$(grep -Ec '^permissions:[[:space:]]*$' "$framework_validation_workflow")" -eq 1 ]] \
        || framework_validation_failures+=("framework-validation.yml: expected one workflow-level permissions block")
    [[ "$(grep -Ec '^[[:space:]]+contents: read[[:space:]]*$' "$framework_validation_workflow")" -eq 1 ]] \
        || framework_validation_failures+=("framework-validation.yml: expected one read-only contents permission")
    if grep -Eq 'pull_request_target|secrets\.' "$framework_validation_workflow"; then
        framework_validation_failures+=("framework-validation.yml: privileged PR events and secret references are forbidden")
    fi
    if rg -n -i -e 'memory graph' -e 'tools/memory-graph' -e 'MemoryGraph\.Tests' "$framework_validation_workflow" >/tmp/p0p4-framework-validation-retired-runtime.out; then
        framework_validation_failures+=("framework-validation.yml: retired Memory Graph job or invocation remains")
    fi
fi
if [[ "${#framework_validation_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "general CI contract violations: ${framework_validation_failures[*]}"
fi

test_start "general CI installs and verifies ripgrep before repository contracts"
ripgrep_setup_failures=()
if [[ ! -f "$framework_validation_workflow" ]]; then
    ripgrep_setup_failures+=("missing .github/workflows/framework-validation.yml")
else
    ripgrep_update_line="$(grep -nF -- "sudo apt-get update" "$framework_validation_workflow" | sed -n '1s/:.*//p' || true)"
    ripgrep_install_line="$(grep -nF -- "sudo apt-get install --yes --no-install-recommends ripgrep" "$framework_validation_workflow" | sed -n '1s/:.*//p' || true)"
    ripgrep_verify_line="$(grep -nF -- "command -v rg" "$framework_validation_workflow" | sed -n '1s/:.*//p' || true)"
    aggregate_contract_line="$(grep -nF -- "run: ./tests/test-p0-p4-contracts.sh" "$framework_validation_workflow" | sed -n '1s/:.*//p' || true)"

    [[ -n "$ripgrep_update_line" ]] || ripgrep_setup_failures+=("framework-validation.yml: missing apt metadata refresh")
    [[ -n "$ripgrep_install_line" ]] || ripgrep_setup_failures+=("framework-validation.yml: missing minimal ripgrep install")
    [[ -n "$ripgrep_verify_line" ]] || ripgrep_setup_failures+=("framework-validation.yml: missing rg prerequisite check")
    [[ -n "$aggregate_contract_line" ]] || ripgrep_setup_failures+=("framework-validation.yml: missing aggregate contract step")

    if [[ -n "$ripgrep_update_line" && -n "$ripgrep_install_line" && -n "$ripgrep_verify_line" && -n "$aggregate_contract_line" ]]; then
        if ! (( ripgrep_update_line < ripgrep_install_line
            && ripgrep_install_line < ripgrep_verify_line
            && ripgrep_verify_line < aggregate_contract_line )); then
            ripgrep_setup_failures+=("framework-validation.yml: ripgrep setup and verification must precede aggregate contracts")
        fi
    fi
fi
if [[ "${#ripgrep_setup_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "general CI ripgrep setup violations: ${ripgrep_setup_failures[*]}"
fi

test_start "P0-P4 fixture installs isolate ambient CODEX_HOME and restore caller state"
ambient_codex_fixture_root="$(mktemp -d "$FRAMEWORK_DIR/.p0p4-ambient-codex-home.XXXXXX")"
ambient_codex_child="$ambient_codex_fixture_root/fixture-child.sh"
p0p4_register_cleanup "$ambient_codex_fixture_root"
cat >"$ambient_codex_child" <<'CHILD'
#!/usr/bin/env bash
set -euo pipefail

mode="$1"
harness="$2"
install_home="$3"
explicit_home="$4"
state_dir="$5"

case "$mode" in
    nonempty) export CODEX_HOME="$6" ;;
    empty) export CODEX_HOME="" ;;
    unset) unset CODEX_HOME ;;
    *) exit 64 ;;
esac

source "$harness"
trap -p EXIT >"$state_dir/cleanup-trap"
if [[ -n "${CODEX_HOME+x}" ]]; then printf "set:%s\\n" "$CODEX_HOME" >"$state_dir/ordinary-state"; else printf "unset\\n" >"$state_dir/ordinary-state"; fi

mkdir -p "$install_home" "$explicit_home"
p0p4_install_codex_fixture "$install_home" "$state_dir/ordinary.out" "$state_dir/ordinary.err" --no-hooks
if [[ -n "${CODEX_HOME+x}" ]]; then printf "set:%s\\n" "$CODEX_HOME" >"$state_dir/after-ordinary-state"; else printf "unset\\n" >"$state_dir/after-ordinary-state"; fi

p0p4_capture_command_scoped_codex_home() {
    if [[ -n "${CODEX_HOME+x}" ]]; then printf "set:%s\\n" "$CODEX_HOME" >"$state_dir/explicit-state"; else printf "unset\\n" >"$state_dir/explicit-state"; fi
}
CODEX_HOME="$explicit_home" p0p4_capture_command_scoped_codex_home
if [[ -n "${CODEX_HOME+x}" ]]; then printf "set:%s\\n" "$CODEX_HOME" >"$state_dir/after-explicit-state"; else printf "unset\\n" >"$state_dir/after-explicit-state"; fi

export CODEX_HOME="$7"
p0p4_cleanup
if [[ -n "${CODEX_HOME+x}" ]]; then printf "set:%s\\n" "$CODEX_HOME" >"$state_dir/cleanup-state"; else printf "unset\\n" >"$state_dir/cleanup-state"; fi
CHILD
chmod +x "$ambient_codex_child"

ambient_codex_failures=()
for ambient_codex_mode in nonempty empty unset; do
    ambient_codex_state="$ambient_codex_fixture_root/$ambient_codex_mode"
    ambient_codex_install_home="$ambient_codex_state/install-home"
    ambient_codex_explicit_home="$ambient_codex_state/explicit-codex-home"
    ambient_codex_cleanup_override="$ambient_codex_state/cleanup-override"
    ambient_codex_external_home="$ambient_codex_state/external-codex-home"
    mkdir -p "$ambient_codex_state" "$ambient_codex_external_home"
    printf '%s\\n' 'external CODEX_HOME sentinel' >"$ambient_codex_external_home/sentinel"
    find "$ambient_codex_external_home" -print | sort >"$ambient_codex_state/external.paths.before"
    find "$ambient_codex_external_home" -type f -exec shasum {} + | sort >"$ambient_codex_state/external.bytes.before"

    if ! /bin/bash "$ambient_codex_child" "$ambient_codex_mode" "$P0P4_HARNESS_DIR/p0p4-harness.sh" "$ambient_codex_install_home" "$ambient_codex_explicit_home" "$ambient_codex_state" "$ambient_codex_external_home" "$ambient_codex_cleanup_override"; then
        ambient_codex_failures+=("$ambient_codex_mode child failed")
        continue
    fi

    find "$ambient_codex_external_home" -print | sort >"$ambient_codex_state/external.paths.after"
    find "$ambient_codex_external_home" -type f -exec shasum {} + | sort >"$ambient_codex_state/external.bytes.after"
    expected_cleanup_state="unset"
    [[ "$ambient_codex_mode" == nonempty ]] && expected_cleanup_state="set:$ambient_codex_external_home"
    [[ "$ambient_codex_mode" == empty ]] && expected_cleanup_state="set:"
    if [[ "$(cat "$ambient_codex_state/ordinary-state")" != "unset" ]] \
        || [[ "$(cat "$ambient_codex_state/after-ordinary-state")" != "unset" ]] \
        || [[ "$(cat "$ambient_codex_state/explicit-state")" != "set:$ambient_codex_explicit_home" ]] \
        || [[ "$(cat "$ambient_codex_state/after-explicit-state")" != "unset" ]] \
        || ! grep -Fq 'p0p4_cleanup' "$ambient_codex_state/cleanup-trap" \
        || [[ "$(cat "$ambient_codex_state/cleanup-state")" != "$expected_cleanup_state" ]] \
        || [[ ! -d "$ambient_codex_install_home/.codex/skills/assistant-workflow" ]] \
        || ! cmp -s "$ambient_codex_state/external.paths.before" "$ambient_codex_state/external.paths.after" \
        || ! cmp -s "$ambient_codex_state/external.bytes.before" "$ambient_codex_state/external.bytes.after"; then
        ambient_codex_failures+=("$ambient_codex_mode")
    fi
done
if [[ "${#ambient_codex_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "ambient CODEX_HOME leaked into ordinary fixtures, command-scoped override, caller restoration, or controlled external state: ${ambient_codex_failures[*]}"
fi

test_start "P0-P4 cleanup attempts every target and restores CODEX_HOME after deletion failure"
cleanup_failure_root="$(mktemp -d "$FRAMEWORK_DIR/.p0p4-cleanup-failure.XXXXXX")"
cleanup_failure_child="$cleanup_failure_root/cleanup-failure-child.sh"
cleanup_failure_exit_child="$cleanup_failure_root/cleanup-failure-exit-child.sh"
cleanup_failure_original="$cleanup_failure_root/original-codex-home"
cleanup_failure_override="$cleanup_failure_root/override-codex-home"
cleanup_failure_targets=(
    "$cleanup_failure_root/cleanup-target-first"
    "$cleanup_failure_root/cleanup-target-second"
    "$cleanup_failure_root/cleanup-target-third"
)
p0p4_register_cleanup "$cleanup_failure_root"
mkdir -p "$cleanup_failure_original" "$cleanup_failure_override" "${cleanup_failure_targets[@]}"
cat >"$cleanup_failure_child" <<'CHILD'
#!/usr/bin/env bash
set -euo pipefail

harness="$1"
original_home="$2"
override_home="$3"
state_file="$4"
rm_log="$5"
shift 5

export CODEX_HOME="$original_home"
source "$harness"
export CODEX_HOME="$override_home"
p0p4_register_cleanup "$@"
rm_calls=0
rm() {
    local path="${!#}"
    rm_calls=$((rm_calls + 1))
    printf '%s\n' "$path" >>"$rm_log"
    [[ "$rm_calls" -ne 1 ]]
}
trap 'if [[ -n "${CODEX_HOME+x}" ]]; then printf "set:%s\\n" "$CODEX_HOME" >"$state_file"; else printf "unset\\n" >"$state_file"; fi' EXIT
p0p4_cleanup
CHILD
chmod +x "$cleanup_failure_child"
cat >"$cleanup_failure_exit_child" <<'CHILD'
#!/usr/bin/env bash
set -euo pipefail

harness="$1"
original_home="$2"
override_home="$3"
cleanup_path="$4"

export CODEX_HOME="$original_home"
source "$harness"
export CODEX_HOME="$override_home"
p0p4_register_cleanup "$cleanup_path"
rm() { return 1; }
:
CHILD
chmod +x "$cleanup_failure_exit_child"

set +e
/bin/bash "$cleanup_failure_child" "$P0P4_HARNESS_DIR/p0p4-harness.sh" "$cleanup_failure_original" "$cleanup_failure_override" "$cleanup_failure_root/exit-state" "$cleanup_failure_root/rm.log" "${cleanup_failure_targets[@]}"
cleanup_failure_status=$?
/bin/bash "$cleanup_failure_exit_child" "$P0P4_HARNESS_DIR/p0p4-harness.sh" "$cleanup_failure_original" "$cleanup_failure_override" "$cleanup_failure_root/exit-cleanup-target"
cleanup_failure_exit_status=$?
set -e
printf '%s\n' "${cleanup_failure_targets[@]}" >"$cleanup_failure_root/rm.expected"
if [[ "$cleanup_failure_status" -eq 0 ]] \
    || [[ "$cleanup_failure_exit_status" -eq 0 ]] \
    || [[ "$(cat "$cleanup_failure_root/exit-state" 2>/dev/null || true)" != "set:$cleanup_failure_original" ]]; then
    fail "cleanup failure did not return nonzero after restoring the original CODEX_HOME"
elif [[ "$(cat "$cleanup_failure_root/rm.expected")" != "$(cat "$cleanup_failure_root/rm.log")" ]]; then
    fail "cleanup target attempts differ: expected $(paste -sd ',' "$cleanup_failure_root/rm.expected"), actual $(paste -sd ',' "$cleanup_failure_root/rm.log")"
else
    pass
fi

if [[ -z "${P0P4_DIRECT_RUN_GUARD:-}" ]]; then
    test_start "top-level P0-P4 suites are directly runnable"
    direct_run_tmp="$(mktemp -d)"
    direct_run_failures=()

    for suite_file in "$P0P4_SUITE_DIR"/*.sh; do
        [[ -f "$suite_file" ]] || continue

        suite_output="$direct_run_tmp/$(basename -- "$suite_file").out"
        # Prevent this guard suite from recursively launching the full direct-run check.
        if P0P4_DIRECT_RUN_GUARD=1 bash "$suite_file" >"$suite_output" 2>&1; then
            continue
        fi

        direct_run_failures+=("$(basename -- "$suite_file")")
    done

    if [[ "${#direct_run_failures[@]}" -eq 0 ]]; then
        rm -rf "$direct_run_tmp"
        pass
    else
        fail "direct run failed for: ${direct_run_failures[*]}; output captured in $direct_run_tmp"
    fi
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
