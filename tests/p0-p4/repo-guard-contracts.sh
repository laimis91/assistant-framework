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
