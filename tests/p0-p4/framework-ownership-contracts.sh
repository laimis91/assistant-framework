if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

# S11 framework ownership: retired-item inventory, content proof, cleanup helper,
# installer mode and uninstall. Destructive cases run only on disposable homes
# and on a temporary committed clone (tests/framework-ownership/test_ownership.py).

framework_ownership_dir="$FRAMEWORK_DIR/tools/framework-ownership"

test_start "framework ownership inventory and generated data exist"
if [[ -f "$framework_ownership_dir/retired-items.json" \
    && -f "$framework_ownership_dir/content-proof.json" \
    && -f "$framework_ownership_dir/installer-exact-removal.tsv" ]]; then
    pass
else
    fail "inventory missing: tools/framework-ownership/retired-items.json (or its generated data)"
fi

test_start "Python unit tests pass"
framework_ownership_log="$(mktemp)"
p0p4_register_cleanup "$framework_ownership_log"
if (cd "$FRAMEWORK_DIR" && env -u CODEX_HOME PYTHONDONTWRITEBYTECODE=1 python3 -B tests/framework-ownership/test_ownership.py) >"$framework_ownership_log" 2>&1; then
    pass
else
    tail -n 40 "$framework_ownership_log"
    fail "tests/framework-ownership/test_ownership.py failed"
fi

test_start "inventory validates and data is complete and sound"
if (cd "$FRAMEWORK_DIR" && python3 tools/framework-ownership/ownership-checkout.py build-data --check) >"$framework_ownership_log" 2>&1; then
    pass
else
    cat "$framework_ownership_log"
    fail "ownership-checkout.py build-data --check failed"
fi

test_start "framework ownership helpers import only the standard library and write no bytecode"
framework_ownership_imports="$(grep -hE '^(import|from) ' "$framework_ownership_dir/ownership.py" "$framework_ownership_dir/ownership-checkout.py" | sort -u)"
framework_ownership_unexpected="$(printf '%s\n' "$framework_ownership_imports" | grep -vE '^import (hashlib|json|os|re|stat|sys|tempfile|unicodedata|importlib\.util|subprocess)$' || true)"
if [[ -z "$framework_ownership_unexpected" ]] \
    && grep -Fq 'sys.dont_write_bytecode = True' "$framework_ownership_dir/ownership-checkout.py" \
    && [[ -z "$(find "$framework_ownership_dir" -name __pycache__ -print -quit)" ]]; then
    pass
else
    fail "unexpected imports or bytecode: $framework_ownership_unexpected"
fi

test_start "install.sh holds no content hashing"
if ! grep -nE 'sha256|shasum|hashlib' "$FRAMEWORK_DIR/install.sh" >/dev/null; then
    pass
else
    fail "install.sh must call the ownership helper instead of hashing (R-S11-26)"
fi

test_start "Codex rules cover every documented destructive form"
framework_rules_base="$(mktemp)"
p0p4_register_cleanup "$framework_rules_base"
if git -C "$FRAMEWORK_DIR" show 1c83719:codex-rules/workflow.rules >"$framework_rules_base" 2>/dev/null \
    && framework_rules_problems="$(python3 -B "$FRAMEWORK_DIR/tests/framework-ownership/check_codex_rules.py" "$FRAMEWORK_DIR" "$framework_rules_base")" && [[ -z "$framework_rules_problems" ]]; then
    pass
else
    fail "Codex rules coverage: ${framework_rules_problems:-could not read the base rule set}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
