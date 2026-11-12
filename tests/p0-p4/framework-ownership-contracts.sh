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

test_start "cleanup removes byte-identical S10-retired skills, keeps a user-extended one, and leaves purpose files alone"
# R-S11-25-style seeds for the skills S10 retired, from the S10 base revision, plus R-S10-11.
s10_cleanup_home="$(mktemp -d)"
p0p4_register_cleanup "$s10_cleanup_home"
s10_cleanup_failures=()
if (cd "$FRAMEWORK_DIR" && python3 -B - "$s10_cleanup_home/.claude/skills" <<'SEED'
import os, subprocess, sys
target_root = sys.argv[1]
rev = "68da3fd9c653d02ed58561fde66d057d0e5f16dc"
for name in ("assistant-telos", "assistant-diagrams", "assistant-ideate"):
    source = "skills/" + name
    for path in subprocess.run(["git", "ls-tree", "-r", "--name-only", rev, source], check=True, capture_output=True, text=True).stdout.split():
        data = subprocess.run(["git", "show", f"{rev}:{path}"], check=True, capture_output=True).stdout
        if os.path.splitext(path)[1] in (".md", ".yaml", ".yml", ".json", ".conf", ".toml"):
            data = data.replace(b"{agent_state_dir}", b".claude")
        out = os.path.join(target_root, name, os.path.relpath(path, source))
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, "wb") as handle:
            handle.write(data)
SEED
); then
    printf 'my notes\n' >"$s10_cleanup_home/.claude/skills/assistant-ideate/notes.md"
    mkdir -p "$s10_cleanup_home/purpose" "$s10_cleanup_home/project/docs"
    printf '# Telos\nMission: user-authored.\n' >"$s10_cleanup_home/purpose/TELOS.md"
    printf '# Project telos\nGoals: user-authored.\n' >"$s10_cleanup_home/project/docs/telos.md"
    s10_purpose_before="$(cat "$s10_cleanup_home/purpose/TELOS.md" "$s10_cleanup_home/project/docs/telos.md")"
    s10_dry_out="$(cd "$FRAMEWORK_DIR" && env -u CODEX_HOME HOME="$s10_cleanup_home" python3 -B tools/framework-ownership/ownership.py dry-run --agent claude --manifest-out "$s10_cleanup_home/manifest.json" 2>&1)" \
        || s10_cleanup_failures+=("dry run failed")
    grep -Fq 'skill_directory: skills/assistant-telos' <<<"$s10_dry_out" || s10_cleanup_failures+=("assistant-telos not offered")
    grep -Fq 'skill_directory: skills/assistant-diagrams' <<<"$s10_dry_out" || s10_cleanup_failures+=("assistant-diagrams not offered")
    grep -Fq 'skills/assistant-ideate: file does not match framework content: notes.md' <<<"$s10_dry_out" || s10_cleanup_failures+=("user-extended assistant-ideate not reported ambiguous")
    s10_digest="$(sed -n 's/^Manifest digest: \([0-9a-f]\{64\}\)$/\1/p' <<<"$s10_dry_out")"
    if [[ -n "$s10_digest" ]] && (cd "$FRAMEWORK_DIR" && env -u CODEX_HOME HOME="$s10_cleanup_home" python3 -B tools/framework-ownership/ownership.py apply --agent claude --manifest "$s10_cleanup_home/manifest.json" --manifest-digest "$s10_digest" --yes) >/dev/null 2>&1; then
        [[ ! -e "$s10_cleanup_home/.claude/skills/assistant-telos" && ! -e "$s10_cleanup_home/.claude/skills/assistant-diagrams" ]] || s10_cleanup_failures+=("byte-identical S10-retired skill kept")
        [[ -f "$s10_cleanup_home/.claude/skills/assistant-ideate/notes.md" ]] || s10_cleanup_failures+=("user-extended assistant-ideate removed")
    else
        s10_cleanup_failures+=("apply failed")
    fi
    [[ "$(cat "$s10_cleanup_home/purpose/TELOS.md" "$s10_cleanup_home/project/docs/telos.md")" == "$s10_purpose_before" ]] || s10_cleanup_failures+=("a user purpose file changed")
else
    s10_cleanup_failures+=("seeding from the S10 base revision failed")
fi
if [[ "${#s10_cleanup_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${s10_cleanup_failures[*]}"
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
