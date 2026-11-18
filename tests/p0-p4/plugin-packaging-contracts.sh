#!/usr/bin/env bash
# Plugin marketplace packaging: docs/specs/plugin-marketplace-packaging.md slices B-D.

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

plugin_sync_tool="$FRAMEWORK_DIR/tools/skills/sync-plugin.py"
chat_zip_tool="$FRAMEWORK_DIR/tools/skills/build-chat-zips.py"
containment_tool="$FRAMEWORK_DIR/tools/skills/check-skill-containment.py"
plugin_dir="$FRAMEWORK_DIR/plugins/assistant-framework"

test_start "plugin copy, manifests and both marketplace files match skills/ and version.txt (R-MP-5 to R-MP-8)"
if python3 "$plugin_sync_tool" --check >/dev/null 2>&1; then
    pass
else
    fail "plugin drifted from skills/; run tools/skills/sync-plugin.py --apply"
fi

test_start "root plugin.json is an Agent Plugins manifest Codex accepts (R-MP-5)"
# Codex reads a root plugin.json only when $schema names the Agent Plugins 1.0.0 schema
# (openai/codex codex-rs/utils/plugins/src/plugin_namespace.rs, core-plugins/src/agent_plugin_manifest.rs); without it the add fails as an invalid manifest.
if python3 - "$plugin_dir/plugin.json" <<'PY'
import json, re, sys
data = json.load(open(sys.argv[1]))
known = {"$schema", "name", "version", "description", "author", "homepage", "repository", "license", "keywords", "extensions"}
problems = []
if data.get("$schema") != "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json":
    problems.append("missing or wrong $schema")
if not re.fullmatch(r"[a-z0-9.-]+", data.get("name", "")):
    problems.append("name is not lowercase letters, numbers, dots or hyphens")
if set(data) - known:
    problems.append(f"unknown fields {sorted(set(data) - known)}")
if any(value is None for value in data.values()):
    problems.append("a field is null")
sys.exit(f"{'; '.join(problems)}" if problems else 0)
PY
then
    pass
else
    fail "plugins/assistant-framework/plugin.json would be rejected by Codex"
fi

test_start "plugin sync check fails closed on drift, a skill with no source, a stale version and a changed marketplace"
plugin_fixture="$(mktemp -d)"
p0p4_register_cleanup "$plugin_fixture"
plugin_failures=()
reset_plugin_fixture() {
    rm -rf "${plugin_fixture:?}"/*  "$plugin_fixture"/.claude-plugin "$plugin_fixture"/.agents
    cp -R "$FRAMEWORK_DIR/skills" "$FRAMEWORK_DIR/version.txt" "$plugin_fixture/"
    SYNC_PLUGIN_REPO_ROOT="$plugin_fixture" python3 "$plugin_sync_tool" --apply >/dev/null 2>&1
}
plugin_check() { SYNC_PLUGIN_REPO_ROOT="$plugin_fixture" python3 "$plugin_sync_tool" --check >/dev/null 2>&1; }
reset_plugin_fixture
plugin_check || plugin_failures+=("check failed right after apply")
printf 'drift\n' >>"$plugin_fixture/plugins/assistant-framework/skills/assistant-review/SKILL.md"
plugin_check && plugin_failures+=("accepted a drifted skill copy")
reset_plugin_fixture
cp -R "$plugin_fixture/skills/assistant-review" "$plugin_fixture/plugins/assistant-framework/skills/assistant-orphan"
plugin_check && plugin_failures+=("accepted a plugin skill with no source in skills/")
reset_plugin_fixture
printf '9.9.9\n' >"$plugin_fixture/version.txt"
plugin_check && plugin_failures+=("accepted manifests behind version.txt")
reset_plugin_fixture
sed -i.bak 's|"./plugins/assistant-framework"|"./plugins/other"|' "$plugin_fixture/.agents/plugins/marketplace.json"
plugin_check && plugin_failures+=("accepted a Codex marketplace with another source")
reset_plugin_fixture
mkdir -p "$plugin_fixture/plugins/assistant-framework/agents"
plugin_check && plugin_failures+=("accepted an agents/ folder in the plugin")
if [[ "${#plugin_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${plugin_failures[*]}"
fi

test_start "plugin skills are self-contained inside the plugin folder and ship no evals (R-MP-4, R-MP-8)"
plugin_shape_failures=()
python3 "$containment_tool" --skills-dir "$plugin_dir/skills" >/dev/null 2>&1 \
    || plugin_shape_failures+=("a plugin skill links outside the plugin folder")
[[ -z "$(find "$plugin_dir/skills" -type d -name evals -print -quit)" ]] \
    || plugin_shape_failures+=("plugin carries an evals/ folder")
for required in assistant-review assistant-verification assistant-tdd assistant-workflow; do
    [[ -f "$plugin_dir/skills/$required/SKILL.md" ]] || plugin_shape_failures+=("requires target $required is missing")
done
if [[ "${#plugin_shape_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${plugin_shape_failures[*]}"
fi

test_start "plugin version moves whenever shipped skills change (R-MP-8 warning)"
if git -C "$FRAMEWORK_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    last_version_commit="$(git -C "$FRAMEWORK_DIR" log -1 --format=%H -- version.txt 2>/dev/null)"
    if [[ -n "$last_version_commit" ]] \
        && [[ -n "$(git -C "$FRAMEWORK_DIR" diff --name-only "$last_version_commit" -- plugins/assistant-framework/skills 2>/dev/null)" ]]; then
        echo "warning: plugins/assistant-framework/skills changed since version.txt last changed; plugin users get no update until the version moves" >&2
    fi
fi
pass

test_start "claude plugin validate accepts the marketplace when the Claude CLI is present"
if command -v claude >/dev/null 2>&1; then
    validate_out="$(mktemp)"
    p0p4_register_cleanup "$validate_out"
    if (cd "$FRAMEWORK_DIR" && claude plugin validate . >"$validate_out" 2>&1); then
        pass
    else
        fail "claude plugin validate failed: $(tail -3 "$validate_out" | tr '\n' ' ')"
    fi
else
    echo "(claude CLI not installed; skipped)" >&2
    pass
fi

test_start "chat ZIPs carry exactly the three suitable skills, one folder each, without evals (R-MP-10, R-MP-11)"
zip_out="$(mktemp -d)"
p0p4_register_cleanup "$zip_out"
zip_failures=()
python3 "$chat_zip_tool" --check >/dev/null 2>&1 || zip_failures+=("the chat set failed validation")
python3 "$chat_zip_tool" --check assistant-workflow >/dev/null 2>&1 && zip_failures+=("accepted assistant-workflow, which declares requires")
python3 "$chat_zip_tool" --out "$zip_out" >/dev/null 2>&1 || zip_failures+=("build failed")
for skill in assistant-clarify assistant-research assistant-thinking; do
    archive="$zip_out/$skill.zip"
    if [[ ! -f "$archive" ]]; then
        zip_failures+=("$skill.zip missing")
        continue
    fi
    tops="$(python3 -c 'import sys,zipfile; print(" ".join(sorted({n.split("/",1)[0] for n in zipfile.ZipFile(sys.argv[1]).namelist()})))' "$archive")"
    [[ "$tops" == "$skill" ]] || zip_failures+=("$skill.zip has top-level entries: $tops")
    python3 -c 'import sys,zipfile; sys.exit(any("/evals/" in n for n in zipfile.ZipFile(sys.argv[1]).namelist()))' "$archive" \
        || zip_failures+=("$skill.zip ships evals/")
done
[[ "$(find "$zip_out" -name '*.zip' | wc -l | tr -d ' ')" == 3 ]] || zip_failures+=("expected exactly three ZIPs")
if [[ "${#zip_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${zip_failures[*]}"
fi

test_start "instruction block is one agent-neutral file with the four sections and no installed path (R-MP-14, R-MP-15)"
block_file="$FRAMEWORK_DIR/docs/instruction-block.md"
block_failures=()
block_text="$(sed -n '/<!-- instruction-block:start -->/,/<!-- instruction-block:end -->/p' "$block_file" 2>/dev/null)"
[[ -n "$block_text" ]] || block_failures+=("docs/instruction-block.md lacks the marked block")
grep -Fq '# Assistant Framework instructions' <<<"$block_text" || block_failures+=("block heading is not agent-neutral")
for section in '## Skills' '## Involving the user' '## Operating stance' '## Boundaries'; do
    grep -Fxq "$section" <<<"$block_text" || block_failures+=("block lacks $section")
done
grep -Eq '\$[A-Z_]|\{\{|tools/progress/' <<<"$block_text" && block_failures+=("block keeps a placeholder or installed path")
grep -Fq 'ASSISTANT_FRAMEWORK_AGENTS_MD_START' <<<"$block_text" || block_failures+=("block lacks its start marker")
grep -Fq 'docs/instruction-block.md' "$FRAMEWORK_DIR/README.md" || block_failures+=("README does not point at the canonical block")
if [[ "${#block_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${block_failures[*]}"
fi

test_start "no skill depends on the instruction block (R-MP-17)"
if grep -rlE 'ASSISTANT_FRAMEWORK_AGENTS_MD_START|docs/instruction-block\.md|Assistant Framework instructions' "$FRAMEWORK_DIR/skills" >/dev/null 2>&1; then
    fail "a skill file refers to the instruction block: $(grep -rlE 'ASSISTANT_FRAMEWORK_AGENTS_MD_START|docs/instruction-block\.md|Assistant Framework instructions' "$FRAMEWORK_DIR/skills" | head -3 | tr '\n' ' ')"
else
    pass
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
