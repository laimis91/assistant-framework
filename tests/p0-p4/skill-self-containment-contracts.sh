#!/usr/bin/env bash
# Self-contained skill folders: docs/specs/self-contained-skills.md slice A (R-SC-1 to R-SC-4).

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

guidance_sync_tool="$FRAMEWORK_DIR/tools/skills/sync-operating-guidance.sh"
containment_tool="$FRAMEWORK_DIR/tools/skills/check-skill-containment.py"

test_start "every skill carries byte-identical synced operating guidance and wire boundary"
if [[ -x "$guidance_sync_tool" ]] && "$guidance_sync_tool" --check >/dev/null 2>&1; then
    pass
else
    fail "synced operating guidance is missing or drifted; run tools/skills/sync-operating-guidance.sh --apply"
fi

test_start "operating guidance sync fails closed on drift and on a missing copy, and apply restores parity"
fixture_root="$(mktemp -d)"
p0p4_register_cleanup "$fixture_root"
mkdir -p "$fixture_root/source" "$fixture_root/skills/example-skill/references"
printf 'canonical guidance\n' >"$fixture_root/source/operating-guidance.md"
printf 'canonical boundary\n' >"$fixture_root/source/wire-boundary.md"
printf -- '---\nname: example-skill\n---\n' >"$fixture_root/skills/example-skill/SKILL.md"
fixture_env=(OPERATING_GUIDANCE_SOURCE_DIR="$fixture_root/source" OPERATING_GUIDANCE_SKILLS_DIR="$fixture_root/skills")
fixture_refs="$fixture_root/skills/example-skill/references"
sync_failures=()
env "${fixture_env[@]}" "$guidance_sync_tool" --apply >/dev/null 2>&1 || sync_failures+=("apply failed for the isolated fixture")
env "${fixture_env[@]}" "$guidance_sync_tool" --check >/dev/null 2>&1 || sync_failures+=("check failed right after apply")
printf 'drifted guidance\n' >"$fixture_refs/operating-guidance.md"
if env "${fixture_env[@]}" "$guidance_sync_tool" --check >/dev/null 2>&1; then
    sync_failures+=("check accepted a drifted copy")
fi
env "${fixture_env[@]}" "$guidance_sync_tool" --apply >/dev/null 2>&1
rm -f "$fixture_refs/wire-boundary.md"
if env "${fixture_env[@]}" "$guidance_sync_tool" --check >/dev/null 2>&1; then
    sync_failures+=("check accepted a missing wire-boundary copy")
fi
env "${fixture_env[@]}" "$guidance_sync_tool" --apply >/dev/null 2>&1
if ! cmp -s "$fixture_root/source/operating-guidance.md" "$fixture_refs/operating-guidance.md" \
    || ! cmp -s "$fixture_root/source/wire-boundary.md" "$fixture_refs/wire-boundary.md"; then
    sync_failures+=("apply did not restore exact parity")
fi
env "${fixture_env[@]}" "$guidance_sync_tool" --check >/dev/null 2>&1 || sync_failures+=("check failed after the final apply")
if [[ ${#sync_failures[@]} -eq 0 ]]; then pass; else fail "guidance sync: ${sync_failures[*]}"; fi

test_start "no skill file names the framework tools/progress guidance path"
progress_scan_out="/tmp/p0p4-skill-tools-progress-scan.out"
if grep -rnE "tools/progress/(operating-guidance|wire-boundary)" "$FRAMEWORK_DIR/skills" \
    | grep -v "/skills/assistant-skill-creator/references/skill-contract-design-guide.md:" \
    | grep -v "/evals/cases.json:" >"$progress_scan_out"; then
    fail "skill files still name tools/progress guidance paths; see $progress_scan_out"
else
    pass
fi

test_start "skill links and runtime paths stay inside each skill and its requires"
containment_out="/tmp/p0p4-skill-containment.out"
if python3 -I "$containment_tool" >"$containment_out" 2>&1; then
    pass
else
    fail "skill containment check failed; see $containment_out"
fi

test_start "containment check rejects framework paths, undeclared cross-skill links and stale allowlist entries"
bad_root="$(mktemp -d)"
p0p4_register_cleanup "$bad_root"
mkdir -p "$bad_root/skills/needs-tools" "$bad_root/skills/other-skill/references" "$bad_root/skills/assistant-docs"
printf -- '---\nname: other-skill\n---\n' >"$bad_root/skills/other-skill/SKILL.md"
printf 'other\n' >"$bad_root/skills/other-skill/references/note.md"
printf -- '---\nname: assistant-docs\n---\n' >"$bad_root/skills/assistant-docs/SKILL.md"
printf 'No API docs directory here.\n' >"$bad_root/skills/assistant-docs/api-docs.md"
cat >"$bad_root/skills/needs-tools/SKILL.md" <<'FIXTURE'
---
name: needs-tools
---
Load [guidance](../../tools/progress/operating-guidance.md).
See [note](../other-skill/references/note.md).
Run `<framework-tools>/example/run.sh`.
Run `{agent_state_dir}/tools/example/run.sh`.
Run `tools/example/run.sh` and read `docs/example/guide.md`.
Run `~/.codex/tools/example/run.sh`.
Run `/home/alice/.claude/tools/example/run.sh` and `${HOME}/.agents/tools/example/run.sh`.
Write the reference under `docs/api/`.
Edit `tools/skills/sync-example.sh` as a maintainer.
FIXTURE
printf 'helper = Path(__file__).parents[3] / "tools/example/helper.py"\n' >"$bad_root/skills/needs-tools/helper.py"
bad_out="/tmp/p0p4-skill-containment-negative.out"
containment_failures=()
if python3 -I "$containment_tool" --skills-dir "$bad_root/skills" >"$bad_out" 2>&1; then
    containment_failures+=("accepted links and paths that leave the skill")
fi
for expected in \
    "link leaves the skill and its requires: ../../tools/progress/operating-guidance.md" \
    "link leaves the skill and its requires: ../other-skill/references/note.md" \
    "runtime path leaves the skill folder: <framework-tools>/example/run.sh" \
    "runtime path leaves the skill folder: {agent_state_dir}/tools/example/run.sh" \
    "runtime path leaves the skill folder: tools/example/run.sh" \
    "runtime path leaves the skill folder: docs/example/guide.md" \
    "runtime path leaves the skill folder: ~/.codex/tools/example/run.sh" \
    "runtime path leaves the skill folder: /home/alice/.claude/tools/example/run.sh" \
    "runtime path leaves the skill folder: \${HOME}/.agents/tools/example/run.sh" \
    "runtime path leaves the skill folder: docs/api/" \
    'runtime path leaves the skill folder: parents[3] / "tools/example/helper.py"' \
    "allowlist entry no longer matches; remove it: docs/api/"; do
    grep -Fq -- "$expected" "$bad_out" || containment_failures+=("missing report: $expected")
done
if grep -Fq "tools/skills/sync-example.sh" "$bad_out"; then
    containment_failures+=("reported a maintainer sync note")
fi
printf -- '---\nname: needs-tools\nrequires:\n  - other-skill\n---\nSee [note](../other-skill/references/note.md).\n' \
    >"$bad_root/skills/needs-tools/SKILL.md"
rm -f "$bad_root/skills/needs-tools/helper.py" "$bad_root/skills/assistant-docs/api-docs.md"
if ! python3 -I "$containment_tool" --skills-dir "$bad_root/skills" >"$bad_out" 2>&1; then
    containment_failures+=("rejected a link into a declared requires skill")
fi
if [[ ${#containment_failures[@]} -eq 0 ]]; then pass; else fail "containment check: ${containment_failures[*]}; see $bad_out"; fi

test_start "containment check resolves backtick reference paths (contract test cleanup D-TC-2)"
ref_root="$(mktemp -d)"
p0p4_register_cleanup "$ref_root"
mkdir -p "$ref_root/skills/assistant-workflow/references" "$ref_root/skills/assistant-workflow/scripts" \
    "$ref_root/skills/needs-refs/references" "$ref_root/skills/needs-refs/contracts"
printf -- '---\nname: assistant-workflow\n---\n' >"$ref_root/skills/assistant-workflow/SKILL.md"
printf 'p\n' >"$ref_root/skills/assistant-workflow/references/protocol.md"
printf 'print(1)\n' >"$ref_root/skills/assistant-workflow/scripts/helper.py"
printf 'x\n' >"$ref_root/skills/needs-refs/references/present.md"
printf 'version: 1\n' >"$ref_root/skills/needs-refs/contracts/index.yaml"
printf 'Sibling `present.md` and nested `contracts/index.yaml`.\n' >"$ref_root/skills/needs-refs/references/inner.md"
cat >"$ref_root/skills/needs-refs/SKILL.md" <<'FIXTURE'
---
name: needs-refs
---
Load `references/present.md` and `contracts/index.yaml#entry`.
Load `references/missing.md` and `evals/cases.json`.
Load workflow's `references/protocol.md` and Workflow's `scripts/helper.py`.
Load workflow's `references/absent.md`.
FIXTURE
ref_out="/tmp/p0p4-skill-containment-refs.out"
ref_failures=()
if python3 -I "$containment_tool" --skills-dir "$ref_root/skills" >"$ref_out" 2>&1; then
    ref_failures+=("accepted missing backtick reference paths")
fi
for expected in \
    "needs-refs/SKILL.md:5: reference path does not exist: references/missing.md" \
    "needs-refs/SKILL.md:5: reference path does not exist: evals/cases.json" \
    "needs-refs/SKILL.md:7: reference path does not exist: references/absent.md"; do
    grep -Fq -- "$expected" "$ref_out" || ref_failures+=("missing report: $expected")
done
for unexpected in "references/present.md" "contracts/index.yaml" "references/protocol.md" "scripts/helper.py" "inner.md"; do
    grep -Fq -- "$unexpected" "$ref_out" && ref_failures+=("reported a resolvable path: $unexpected")
done
if [[ ${#ref_failures[@]} -eq 0 ]]; then pass; else fail "backtick reference paths: ${ref_failures[*]}; see $ref_out"; fi

test_start "each skill copied alone with its requires closure resolves every link"
closure_failures=()
for skill_file in "$FRAMEWORK_DIR"/skills/*/SKILL.md; do
    skill="$(basename "$(dirname "$skill_file")")"
    isolated="$(mktemp -d)"
    p0p4_register_cleanup "$isolated"
    pending=("$skill")
    copied=" "
    while [[ ${#pending[@]} -gt 0 ]]; do
        current="${pending[0]}"
        pending=("${pending[@]:1}")
        [[ "$copied" == *" $current "* ]] && continue
        copied+="$current "
        cp -R "$FRAMEWORK_DIR/skills/$current" "$isolated/$current"
        while IFS= read -r dep; do
            [[ -n "$dep" ]] && pending+=("$dep")
        done < <(awk '/^---$/{n++; next} n==1 && /^requires:/{r=1; next} n==1 && r && /^  - /{print substr($0,5); next} {r=0}' "$FRAMEWORK_DIR/skills/$current/SKILL.md")
    done
    if ! python3 -I "$containment_tool" --skills-dir "$isolated" >/dev/null 2>&1; then
        closure_failures+=("$skill")
    fi
done
if [[ ${#closure_failures[@]} -eq 0 ]]; then
    pass
else
    fail "skills not self-contained with their requires closure: ${closure_failures[*]}"
fi

test_start "workflow admission helper loads its stagnation helper from a lone skill copy"
admission_root="$(mktemp -d)"
p0p4_register_cleanup "$admission_root"
cp -R "$FRAMEWORK_DIR/skills/assistant-workflow" "$admission_root/assistant-workflow"
admission_out="/tmp/p0p4-skill-admission-import.out"
if [[ -e "$FRAMEWORK_DIR/tools/progress/stagnation.py" ]]; then
    fail "tools/progress/stagnation.py still exists; it belongs in skills/assistant-workflow/scripts/"
elif (cd "$admission_root" && python3 -I -B -c '
import importlib.util, sys
path = "assistant-workflow/scripts/task-packet-admission.py"
spec = importlib.util.spec_from_file_location("admission_probe", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
assert hasattr(module.PROGRESS, "ProgressState"), "stagnation helper lacks ProgressState"
') >"$admission_out" 2>&1; then
    pass
else
    fail "admission helper did not load from a lone workflow copy; see $admission_out"
fi

test_start "every skill that writes {agent_state_dir} carries the guidance that defines it (plugin packaging R-MP-1)"
token_failures=()
grep -Fq '## Agent state directory' "$FRAMEWORK_DIR/tools/progress/operating-guidance.md" \
    || token_failures+=("canonical operating guidance lacks the Agent state directory definition")
grep -Fq '`.claude` on Claude Code and `.codex` on Codex' "$FRAMEWORK_DIR/tools/progress/operating-guidance.md" \
    || token_failures+=("canonical definition no longer names both runtimes")
while IFS= read -r token_skill; do
    grep -Fq '## Agent state directory' "$FRAMEWORK_DIR/skills/$token_skill/references/operating-guidance.md" 2>/dev/null \
        || token_failures+=("$token_skill uses {agent_state_dir} without the defining guidance copy")
done < <(grep -rlF '{agent_state_dir}' "$FRAMEWORK_DIR/skills" | sed -e "s|^$FRAMEWORK_DIR/skills/||" -e 's|/.*||' | LC_ALL=C sort -u)
if [[ "${#token_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${token_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
