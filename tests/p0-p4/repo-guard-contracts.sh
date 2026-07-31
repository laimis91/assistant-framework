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
