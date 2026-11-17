#!/usr/bin/env bash
# Role prompts inside the skills: docs/specs/plugin-marketplace-packaging.md R-MP-2 (D-MP-5).

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

role_sync_tool="$FRAMEWORK_DIR/tools/skills/sync-role-prompts.sh"

test_start "role prompts match the Claude agent bodies, Codex instructions agree and no provider path is hard-coded"
role_check_out="/tmp/p0p4-role-prompt-check.out"
if [[ -x "$role_sync_tool" ]] && "$role_sync_tool" --check >"$role_check_out" 2>&1; then
    pass
else
    fail "role prompts drifted; see $role_check_out and run tools/skills/sync-role-prompts.sh --apply"
fi

test_start "role prompt exception list starts empty"
if grep -Fxq 'CODEX_PARITY_EXCEPTIONS=()' "$role_sync_tool"; then
    pass
else
    fail "sync-role-prompts.sh must start with an empty CODEX_PARITY_EXCEPTIONS list"
fi

test_start "role prompt check fails on an edited copy, a provider path literal and a diverged Codex body"
fixture_root="$(mktemp -d)"
p0p4_register_cleanup "$fixture_root"
mkdir -p "$fixture_root/skills"
cp -R "$FRAMEWORK_DIR/agents" "$fixture_root/agents"
for skill in assistant-review assistant-research assistant-workflow; do
    mkdir -p "$fixture_root/skills/$skill/references"
    cp "$FRAMEWORK_DIR/skills/$skill/SKILL.md" "$fixture_root/skills/$skill/SKILL.md"
    cp -R "$FRAMEWORK_DIR/skills/$skill/references/roles" "$fixture_root/skills/$skill/references/roles"
done
fixture_env=(ROLE_PROMPTS_AGENTS_DIR="$fixture_root/agents" ROLE_PROMPTS_SKILLS_DIR="$fixture_root/skills")
role_copy="$fixture_root/skills/assistant-review/references/roles/code-reviewer.md"
role_failures=()

env "${fixture_env[@]}" "$role_sync_tool" --check >/dev/null 2>&1 || role_failures+=("check failed on the unchanged copy")

printf 'Edited by hand.\n' >>"$role_copy"
if env "${fixture_env[@]}" "$role_sync_tool" --check >/dev/null 2>&1; then
    role_failures+=("check accepted a hand-edited role copy")
fi
env "${fixture_env[@]}" "$role_sync_tool" --apply >/dev/null 2>&1
env "${fixture_env[@]}" "$role_sync_tool" --check >/dev/null 2>&1 || role_failures+=("check failed after apply restored the copy")

rm -f "$fixture_root/skills/assistant-workflow/references/roles/explorer.md"
if env "${fixture_env[@]}" "$role_sync_tool" --check >/dev/null 2>&1; then
    role_failures+=("check accepted a missing role copy")
fi
env "${fixture_env[@]}" "$role_sync_tool" --apply >/dev/null 2>&1

printf 'Persist the map to .claude/context-map.md.\n' >>"$fixture_root/agents/claude/code-mapper.md"
printf 'Persist the map to .claude/context-map.md.\n' >"$fixture_root/codex-addition.txt"
python3 -I - "$fixture_root/agents/codex/code-mapper.toml" "$fixture_root/codex-addition.txt" <<'PYTHON'
import sys
from pathlib import Path
toml_path, addition_path = Path(sys.argv[1]), Path(sys.argv[2])
text = toml_path.read_text()
closing = text.rindex('"""')
toml_path.write_text(text[:closing] + addition_path.read_text() + text[closing:])
PYTHON
env "${fixture_env[@]}" "$role_sync_tool" --apply >/dev/null 2>&1
literal_out="$fixture_root/literal.err"
if env "${fixture_env[@]}" "$role_sync_tool" --check >/dev/null 2>"$literal_out"; then
    role_failures+=("check accepted a role prompt containing a .claude/ literal")
elif ! grep -Fq 'literal .claude/ or .codex/ path: assistant-workflow/references/roles/code-mapper.md' "$literal_out" \
    || grep -Fq 'developer_instructions differ' "$literal_out"; then
    role_failures+=("literal-path failure was not reported as the only problem")
fi

rm -rf "$fixture_root/agents"
cp -R "$FRAMEWORK_DIR/agents" "$fixture_root/agents"
env "${fixture_env[@]}" "$role_sync_tool" --apply >/dev/null 2>&1
env "${fixture_env[@]}" "$role_sync_tool" --check >/dev/null 2>&1 || role_failures+=("check failed after restoring the agent files")

python3 -I - "$fixture_root/agents/codex/qa-evaluator.toml" <<'PYTHON'
import sys
from pathlib import Path
toml_path = Path(sys.argv[1])
text = toml_path.read_text()
closing = text.rindex('"""')
toml_path.write_text(text[:closing] + "- Codex-only instruction.\n" + text[closing:])
PYTHON
codex_out="$fixture_root/codex.err"
if env "${fixture_env[@]}" "$role_sync_tool" --check >/dev/null 2>"$codex_out"; then
    role_failures+=("check accepted a diverged Codex developer_instructions body")
elif ! grep -Fq 'agents/codex/qa-evaluator.toml developer_instructions differ' "$codex_out"; then
    role_failures+=("Codex divergence was not reported for qa-evaluator")
fi

python3 -I - "$fixture_root/agents/codex/qa-evaluator.toml" <<'PYTHON'
import sys
from pathlib import Path
toml_path = Path(sys.argv[1])
text = toml_path.read_text().replace("- Codex-only instruction.\n", "")
toml_path.write_text(text.replace("\n", "   \r\n"))
PYTHON
env "${fixture_env[@]}" "$role_sync_tool" --check >/dev/null 2>&1 \
    || role_failures+=("check rejected a Codex body that differs only in CRLF and trailing whitespace")

if [[ ${#role_failures[@]} -eq 0 ]]; then pass; else fail "role prompt sync: ${role_failures[*]}"; fi

test_start "role prompt sync script and suite are registered and syntactically valid"
registration_failures=()
if [[ "$(grep -Fc 'source "$P0P4_SUITE_DIR/role-prompt-contracts.sh"' "$FRAMEWORK_DIR/tests/test-p0-p4-contracts.sh" || true)" != "1" ]]; then
    registration_failures+=("aggregate suite must source role-prompt-contracts.sh exactly once")
fi
for script in "$role_sync_tool" "$FRAMEWORK_DIR/tests/p0-p4/role-prompt-contracts.sh"; do
    bash -n "$script" || registration_failures+=("${script#$FRAMEWORK_DIR/}: bash syntax failure")
done
if [[ ${#registration_failures[@]} -eq 0 ]]; then pass; else fail "${registration_failures[*]}"; fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
