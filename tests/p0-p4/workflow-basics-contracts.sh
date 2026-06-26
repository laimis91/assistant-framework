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

test_start "agentic loop safety review requires low-confidence escalation evidence"
missing_loop_safety_terms=()
for file in \
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml"; do
    if ! grep -Fq "low-confidence escalation" "$file" && ! grep -Fq "low_confidence_escalation" "$file"; then
        missing_loop_safety_terms+=("$file")
    fi
done
if [[ "${#missing_loop_safety_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "agentic loop safety lacks low-confidence escalation in: ${missing_loop_safety_terms[*]}"
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

test_start "workflow triage rubric defines structured metadata and task gate packs"
missing_triage_terms=()
triage_file="$FRAMEWORK_DIR/skills/assistant-workflow/references/triage-rubric.md"
for term in \
    "Required Triage Output" \
    "Task type" \
    "Risk tier" \
    "Required gates" \
    "Required agents" \
    "Subagent policy state" \
    "Subagent execution mode" \
    "Subagent authorization scope" \
    "Candidate scope scan" \
    "Bugfix" \
    "Feature" \
    "Refactor / Migration / Rewrite" \
    "Config / Infra" \
    "Security / Input" \
    "Docs-Only"; do
    if [[ ! -f "$triage_file" ]] || ! grep -Fq "$term" "$triage_file"; then
        missing_triage_terms+=("triage-rubric.md: $term")
    fi
done
for term in \
    "references/triage-rubric.md" \
    "Triage metadata"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md"; then
        missing_triage_terms+=("SKILL.md: $term")
    fi
done
for term in \
    "risk_tier" \
    "required_gates" \
    "required_agents" \
    "subagent_policy_state" \
    "subagent_execution_mode" \
    "subagent_authorization_scope"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/input.yaml"; then
        missing_triage_terms+=("input.yaml: $term")
    fi
done
for term in \
    "T4" \
    "T9" \
    "T10" \
    "risk_tier is set" \
    "required_gates includes common gates" \
    "required_agents or fallback execution roles are populated" \
    "subagent_policy_state, subagent_execution_mode, and subagent_authorization_scope are initialized" \
    "candidate_scope_scan is populated from a quick read-only scan"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"; then
        missing_triage_terms+=("phase-gates.yaml: $term")
    fi
done
for term in \
    "Task type:" \
    "Risk tier:" \
    "Required gates:" \
    "Required agents:" \
    "Subagent policy state:" \
    "Subagent execution mode:" \
    "Subagent authorization scope:" \
    "Candidate scope scan:"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md"; then
        missing_triage_terms+=("task-journal-template.md: $term")
    fi
done
if [[ "${#missing_triage_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow triage rubric missing terms: ${missing_triage_terms[*]}"
fi

test_start "workflow discovery maps behaviorally relevant references"
missing_reference_mapping_terms=()
for term in \
    "references_checked" \
    "caller, consumer, test, docs, contract, config, mirror, hook, runtime" \
    "candidate_scope_scan"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml"; then
        missing_reference_mapping_terms+=("handoffs.yaml: $term")
    fi
done
for term in \
    "D8A" \
    "context map includes references_checked" \
    "behaviorally relevant callers, consumers, tests, docs, contracts, config, generated mirrors, hooks, and runtime surfaces"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"; then
        missing_reference_mapping_terms+=("phase-gates.yaml: $term")
    fi
done
for term in \
    "References Checked" \
    "\"All references\" means behaviorally relevant references inside the accepted task scope"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/context-map-template.md"; then
        missing_reference_mapping_terms+=("context-map-template.md: $term")
    fi
done
if [[ "${#missing_reference_mapping_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow reference mapping guard missing terms: ${missing_reference_mapping_terms[*]}"
fi

test_start "workflow candidate-search phase 1 contracts are present and company-safe"
missing_candidate_terms=()
for term in \
    "search_mode" \
    "none, lightweight, candidate_search" \
    "candidate_search triggers"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/input.yaml"; then
        missing_candidate_terms+=("input.yaml: $term")
    fi
done
for term in \
    "candidate_search_result" \
    "goal_tree" \
    "candidate_archive" \
    "selected_candidate" \
    "search_exit_summary" \
    "empty_result_handling" \
    "plan_deviation"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"; then
        missing_candidate_terms+=("output.yaml: $term")
    fi
done
for term in \
    "CS1" \
    "candidate archive exists at {agent_state_dir}/candidate-search.md when local state artifacts are configured and policy-allowed" \
    "CS5" \
    "candidate_search_result includes search_exit_summary" \
    "Post-approval candidate pivots are recorded as plan deviations"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"; then
        missing_candidate_terms+=("phase-gates.yaml: $term")
    fi
done
for term in \
    "references/candidate-search.md" \
    "Candidate Search"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md"; then
        missing_candidate_terms+=("SKILL.md: $term")
    fi
    if [[ ! -f "$FRAMEWORK_DIR/skills/assistant-workflow/references/candidate-search.md" ]] || ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/candidate-search.md"; then
        missing_candidate_terms+=("candidate-search.md: $term")
    fi
done
for term in \
    "Search mode:" \
    "Candidate search summary:" \
    "Candidate archive:"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/plan-template.md"; then
        missing_candidate_terms+=("plan-template.md: $term")
    fi
done
for term in \
    "docs/plans/bes-candidate-search-phase-2.md" \
    "docs/plans/bes-candidate-search-phase-3.md"; do
    if [[ ! -f "$FRAMEWORK_DIR/$term" ]]; then
        missing_candidate_terms+=("future plan missing: $term")
    fi
done
if [[ "${#missing_candidate_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow candidate-search phase 1 contract missing terms: ${missing_candidate_terms[*]}"
fi

test_start "workflow candidate-search root and assistant-dev plugin copies stay in sync"
if [[ -d "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow" ]] \
    && diff -qr "$FRAMEWORK_DIR/skills/assistant-workflow" "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow" >/tmp/p0p4-candidate-plugin-parity.out; then
    pass
else
    fail "assistant-workflow plugin copy is not in sync; see /tmp/p0p4-candidate-plugin-parity.out"
fi

test_start "workflow state artifacts are orchestrator-owned and ignored"
missing_state_terms=()
for term in \
    "framework-owned, ignored state" \
    "The orchestrator may create and update them directly" \
    "This exception never applies to project source" \
    "The Code Mapper returns context map markdown" \
    "persists that markdown"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"; then
        missing_state_terms+=("phases.md: $term")
    fi
done
for term in \
    "orchestrator-owned {agent_state_dir}/task.md state artifact" \
    "persist the context map to {agent_state_dir}/context-map.md when allowed"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"; then
        missing_state_terms+=("phase-gates.yaml: $term")
    fi
done
for term in \
    "context_map_markdown" \
    "orchestrator to persist to {agent_state_dir}/context-map.md when local state artifacts are configured and policy-allowed"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml"; then
        missing_state_terms+=("handoffs.yaml: $term")
    fi
done
for term in \
    "This framework-owned state artifact may be written directly by the orchestrator" \
    "workflow-guard.sh"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/hooks/scripts/pre-compress.sh" "$FRAMEWORK_DIR/hooks/scripts/workflow-guard.sh"; then
        missing_state_terms+=("hooks: $term")
    fi
done
if ! grep -Fq ".codex/" "$FRAMEWORK_DIR/.gitignore"; then
    missing_state_terms+=(".gitignore: .codex/")
fi
if [[ "${#missing_state_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow state artifact ownership missing terms: ${missing_state_terms[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
