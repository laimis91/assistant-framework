if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

generator="$FRAMEWORK_DIR/tools/skills/sync-workflow-references.py"
phases_source="$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"
plans_source="$FRAMEWORK_DIR/skills/assistant-workflow/references/plan-template.md"
workflow_skill="$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md"

run_generator() {
    WORKFLOW_PHASES_SOURCE="$1/phases.md" \
    WORKFLOW_PLAN_SOURCE="$1/plan-template.md" \
    WORKFLOW_FOCUSED_REFERENCE_ROOT="$1/views" \
    python3 "$generator" "${@:2}"
}

test_start "workflow focused-reference suite is registered and committed views are current"
if grep -Fq 'workflow-reference-loading-contracts.sh' "$FRAMEWORK_DIR/tests/test-p0-p4-contracts.sh" \
    && "$generator" --check >/dev/null; then
    pass
else
    fail "workflow focused-reference suite is not registered or committed views drifted"
fi

test_start "workflow focused-reference generator produces selected lossless views"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/workflow-reference-loading.XXXXXX")"
p0p4_register_cleanup "$fixture_root"
cp "$phases_source" "$fixture_root/phases.md"
cp "$plans_source" "$fixture_root/plan-template.md"
if [[ -x "$generator" ]] \
    && run_generator "$fixture_root" --apply >/dev/null \
    && run_generator "$fixture_root" --check >/dev/null \
    && [[ ! -e "$fixture_root/views/phases/prepare-only.md" ]] \
    && grep -Fq "references/phases/<current-phase>.md" "$workflow_skill" \
    && grep -Fq "references/plans/<size>.md" "$workflow_skill" \
    && grep -Fq "Preparation Completion is \`preparation-completion\`" "$workflow_skill" \
    && ! grep -Fq "prepare_only\` uses \`preparation-completion.md" "$workflow_skill" \
    && grep -Fq "Missing or unknown view: load authoritative \`references/phases.md\`" "$workflow_skill" \
    && grep -Fq "missing or unknown view loads authoritative \`references/plan-template.md\`" "$workflow_skill" \
    && grep -Fq "references/plans/prepare-only.md" "$phases_source" \
    && grep -Fq "Then load \`references/plans/<size>.md\`" "$phases_source" \
    && ! grep -Fq "Then read \`references/plan-template.md\`" "$phases_source" \
    && grep -Fq "## Shared Controller Decisions" "$fixture_root/views/phases/build.md" \
    && grep -Fq "## Phase: Discover" "$fixture_root/views/phases/discover.md" \
    && grep -Fq "## Phase: Plan" "$fixture_root/views/phases/plan.md" \
    && grep -Fq "## Phase: Build" "$fixture_root/views/phases/build.md" \
    && grep -Fq "references/build-worker-protocol.md" "$fixture_root/views/phases/build.md" \
    && ! grep -Fq "## Phase: Review" "$fixture_root/views/phases/build.md" \
    && grep -Fq "For \`execution_intent=prepare_only\`" "$fixture_root/views/plans/prepare-only.md" \
    && grep -Fq "## Context Budget" "$fixture_root/views/plans/prepare-only.md" \
    && ! grep -Fq "## Executable Task Packet" "$fixture_root/views/plans/prepare-only.md" \
    && grep -Fq "## Small Tasks — Inline Plan" "$fixture_root/views/plans/small.md" \
    && ! grep -Fq "## Executable Task Packet" "$fixture_root/views/plans/small.md" \
    && grep -Fq "## Executable Task Packet" "$fixture_root/views/plans/medium.md" \
    && grep -Fq "## Slice Manifest" "$fixture_root/views/plans/medium.md" \
    && grep -Fq "## Large / Mega Tasks — Full Plan" "$fixture_root/views/plans/large.md"; then
    pass
else
    fail "focused workflow references did not preserve selected shared, phase, and tier content"
fi

test_start "workflow focused-reference views contain exact selected source sections"
if python3 - "$fixture_root" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])

def document(path):
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    fence = None
    headings = []
    for index, line in enumerate(lines):
        stripped = line.lstrip(" ")
        marker = stripped[:1]
        run = len(stripped) - len(stripped.lstrip(marker)) if marker in "`~" else 0
        if fence:
            if marker == fence[0] and run >= fence[1] and not stripped[run:].strip():
                fence = None
            continue
        if marker in "`~" and run >= 3:
            fence = (marker, run)
            continue
        if line.startswith("## "):
            headings.append((index, line[3:].strip()))
    assert fence is None
    preamble = "".join(lines[:headings[0][0]])
    sections = {}
    for position, (start, name) in enumerate(headings):
        end = headings[position + 1][0] if position + 1 < len(headings) else len(lines)
        sections[name] = "".join(lines[start:end])
    return preamble, sections

def expected(path, headings):
    preamble, sections = document(path)
    return preamble.rstrip() + "\n\n" + "\n\n".join(sections[name].rstrip() for name in headings) + "\n"

def generated(path):
    return path.read_text(encoding="utf-8").split("\n\n", 1)[1]

phases = root / "phases.md"
plans = root / "plan-template.md"
shared = ("Shared Controller Decisions", "Progress Updates")
def assert_view(path, source, headings):
    if generated(path) != expected(source, headings):
        raise AssertionError(path)

for filename, heading in {
    "discover": "Phase: Discover",
    "plan": "Phase: Plan",
    "design": "Phase: Design (UI/UX only, skip for backend)",
    "decompose": "Phase: Decompose",
    "build": "Phase: Build",
    "review": "Phase: Review",
    "document": "Phase: Document",
    "preparation-completion": "Phase: Preparation Completion",
}.items():
    assert_view(root / f"views/phases/{filename}.md", phases, shared + (heading,))
assert "## Slice Manifest" in document(phases)[1]["Phase: Decompose"]
common = ("Which tier to use", "Context Budget", "Pattern Retrieval")
assert_view(root / "views/plans/prepare-only.md", plans, common)
assert_view(root / "views/plans/small.md", plans, ("Small Tasks — Inline Plan (`plan_mode=inline`, `execution_intent != prepare_only`)",) + common)
medium = ("Executable Task Packet (`execution_intent != prepare_only`)", "Slice Manifest (`execution_intent != prepare_only`)", "Medium Tasks — Standard Plan (`execution_intent != prepare_only`)")
assert_view(root / "views/plans/medium.md", plans, medium + common)
assert_view(root / "views/plans/large.md", plans, medium + ("Large / Mega Tasks — Full Plan (`execution_intent != prepare_only`)",) + common)
PY
then
    pass
else
    fail "focused workflow references do not exactly contain their selected source sections"
fi

test_start "workflow focused-reference generator rejects drift and malformed source structure"
failure_cases=()
committed_fixture="$(mktemp -d "${TMPDIR:-/tmp}/workflow-reference-committed.XXXXXX")"
p0p4_register_cleanup "$committed_fixture"
cp "$phases_source" "$committed_fixture/phases.md"
cp "$plans_source" "$committed_fixture/plan-template.md"
mkdir -p "$committed_fixture/views"
cp -R "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases" "$committed_fixture/views/phases"
cp -R "$FRAMEWORK_DIR/skills/assistant-workflow/references/plans" "$committed_fixture/views/plans"
printf '\nDRIFT\n' >>"$committed_fixture/views/phases/build.md"
if run_generator "$committed_fixture" --check >/dev/null 2>&1; then
    failure_cases+=("committed view corruption")
fi

printf '\nDRIFT\n' >>"$fixture_root/views/phases/build.md"
if run_generator "$fixture_root" --check >/dev/null 2>&1; then
    failure_cases+=("stale view")
fi
run_generator "$fixture_root" --apply >/dev/null || failure_cases+=("reset after drift")

cp "$phases_source" "$fixture_root/phases.md"
printf '\n## Phase: Build\n' >>"$fixture_root/phases.md"
if run_generator "$fixture_root" --check >/dev/null 2>&1; then
    failure_cases+=("duplicate phase")
fi

cp "$phases_source" "$fixture_root/phases.md"
sed '/^## Phase: Review$/d' "$fixture_root/phases.md" >"$fixture_root/phases.next"
mv "$fixture_root/phases.next" "$fixture_root/phases.md"
if run_generator "$fixture_root" --check >/dev/null 2>&1; then
    failure_cases+=("missing phase")
fi

cp "$phases_source" "$fixture_root/phases.md"
printf '\n## Unexpected Phase\n' >>"$fixture_root/phases.md"
if run_generator "$fixture_root" --check >/dev/null 2>&1; then
    failure_cases+=("unexpected phase")
fi

cp "$phases_source" "$fixture_root/phases.md"
printf '\n```markdown\n' >>"$fixture_root/phases.md"
if run_generator "$fixture_root" --check >/dev/null 2>&1; then
    failure_cases+=("unclosed fence")
fi

cp "$phases_source" "$fixture_root/phases.md"
cp "$plans_source" "$fixture_root/plan-template.md"
awk '
    /^```$/ && !changed { print "```markdown"; changed = 1; next }
    { print }
' "$fixture_root/plan-template.md" >"$fixture_root/plan-template.next"
mv "$fixture_root/plan-template.next" "$fixture_root/plan-template.md"
if run_generator "$fixture_root" --check >/dev/null 2>&1; then
    failure_cases+=("malformed fence close")
fi

cp "$plans_source" "$fixture_root/plan-template.md"
printf '\n## Unexpected Plan\n' >>"$fixture_root/plan-template.md"
if run_generator "$fixture_root" --check >/dev/null 2>&1; then
    failure_cases+=("unexpected plan")
fi

if [[ "${#failure_cases[@]}" -eq 0 ]]; then
    pass
else
    fail "focused workflow references accepted invalid state: ${failure_cases[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
