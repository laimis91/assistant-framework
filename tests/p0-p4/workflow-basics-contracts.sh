if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "canonical workflow phase lists do not inject standalone TEST/VERIFY phases"
if rg -n "TRIAGE -> DISCOVER -> PLAN -> BUILD -> TEST|BUILD -> TEST -> VERIFY|TEST -> VERIFY" \
    "$FRAMEWORK_DIR/install.sh" \
    "$FRAMEWORK_DIR/hooks/scripts/workflow-enforcer.sh" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml" >/tmp/p0p4-stale-phases.out; then
    fail "found stale TEST/VERIFY phase list; see /tmp/p0p4-stale-phases.out"
else
    pass
fi

test_start "Codex AGENTS generated phase list includes conditional decompose and design"
if grep -q "TRIAGE -> DISCOVER -> DECOMPOSE when needed -> PLAN -> DESIGN when needed -> BUILD -> REVIEW -> DOCUMENT" \
    "$FRAMEWORK_DIR/install.sh"; then
    pass
else
    fail "generated Codex AGENTS phase list is missing canonical conditional DECOMPOSE/DESIGN wording"
fi

test_start "review contracts support review_material_snapshot without diff-only gates"
if rg -n "diff_content|Reviewer received: diff|current diff|from the diff|review_scope is resolved to one of: files, diff" \
    "$FRAMEWORK_DIR/skills/assistant-review" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/review-rubric.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml" >/tmp/p0p4-review-diff-only.out; then
    fail "found diff-only review contract wording; see /tmp/p0p4-review-diff-only.out"
else
    pass
fi

test_start "reviewer handoff rejects diff-only material fields and finding gates"
if rg -n "name: diff|Full diff|exists in the diff" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml" >/tmp/p0p4-review-handoff-diff-only.out; then
    fail "found diff-only reviewer handoff wording; see /tmp/p0p4-review-handoff-diff-only.out"
else
    pass
fi

test_start "workflow templates and scripts do not use stale Build & Test or VERIFYING labels"
if rg -n "Build & Test|VERIFYING" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/decompose.sh" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/generate-agents-md.sh" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/context-handoff-templates.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/sub-task-brief-template.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/mega-and-patterns.md" >/tmp/p0p4-stale-workflow-labels.out; then
    fail "found stale workflow template/script labels; see /tmp/p0p4-stale-workflow-labels.out"
else
    pass
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
