if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "canonical workflow phase lists do not inject standalone TEST/VERIFY phases"
if rg -n "TRIAGE -> DISCOVER -> PLAN -> BUILD -> TEST|BUILD -> TEST -> VERIFY|TEST -> VERIFY" \
    "$FRAMEWORK_DIR/install.sh" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml" >/tmp/p0p4-stale-phases.out; then
    fail "found stale TEST/VERIFY phase list; see /tmp/p0p4-stale-phases.out"
else
    pass
fi

test_start "Codex AGENTS delegates phase detail to native skill routing"
if grep -Fq 'Codex uses installed skills through native skill routing. When a skill matches, read its \`SKILL.md\` and load only the references or contracts relevant to the current phase.' \
    "$FRAMEWORK_DIR/install.sh" \
    && grep -Fq "Get plan approval before medium+ or risky edits." \
    "$FRAMEWORK_DIR/install.sh" \
    && ! grep -Fq "The orchestrator owns framework state files" "$FRAMEWORK_DIR/install.sh" \
    && ! grep -Fq "use direct fallback only after" "$FRAMEWORK_DIR/install.sh" \
    && ! grep -Fq "TRIAGE -> DISCOVER -> DECOMPOSE when needed -> PLAN -> DESIGN when needed -> BUILD -> REVIEW -> DOCUMENT" \
    "$FRAMEWORK_DIR/install.sh"; then
    pass
else
    fail "generated Codex AGENTS guidance must stay lean and defer phase mechanics to the matched skill"
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

test_start "review delegation dispatches from applicable instruction triggers"
review_trigger_failures=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md::assistant-review contracts are v3" \
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md::load \`contracts/input.yaml\` review-entry fields selected by \`review-entry-fields\` in \`contracts/index.yaml\`" \
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md::v4 can consume the producer packet" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/index.yaml::subagent_trigger_scope" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/index.yaml::policy_blocking_source" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/index.yaml::qa_evaluation_mode" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/input.yaml::delegation_triggered" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/input.yaml::delegation_opted_out" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/input.yaml::direct user request or applicable AGENTS.md or active skill instruction" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/input.yaml::subagent_trigger_scope" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml::subagent_trigger_scope" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml::without a separate permission question"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        review_trigger_failures+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#review_trigger_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review trigger delegation contract missing: ${review_trigger_failures[*]}"
fi

test_start "review delegation outputs require exact policy-block evidence"
review_policy_block_failures=()
for artifact in review_delegation_path qa_evaluation_delegation_path; do
    artifact_block="$(awk -v artifact="$artifact" '
        $0 == "  - name: " artifact { inside = 1 }
        inside { print }
        inside && NR > 1 && $0 ~ /^  - name: / && $0 != "  - name: " artifact { exit }
    ' "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml")"
    if ! grep -Fq -- '- name: policy_blocking_source' <<<"$artifact_block"; then
        review_policy_block_failures+=("$artifact: missing policy_blocking_source")
    elif ! grep -Fq -- 'required: conditional' <<<"$artifact_block"; then
        review_policy_block_failures+=("$artifact: policy_blocking_source is not conditional")
    elif ! grep -Fq -- 'subagent_policy_state == policy_disallowed' <<<"$artifact_block"; then
        review_policy_block_failures+=("$artifact: missing policy_disallowed condition")
    elif ! grep -Fq -- 'Exact active blocking rule' <<<"$artifact_block" \
        || ! grep -Fq -- 'no applicable direct-user, AGENTS.md, or active-skill trigger exception' <<<"$artifact_block"; then
        review_policy_block_failures+=("$artifact: missing exact blocking-rule validation")
    fi
done
if [[ "${#review_policy_block_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review delegation outputs omit policy-block evidence: ${review_policy_block_failures[*]}"
fi

test_start "agentic loop safety review requires low-confidence escalation evidence"
missing_loop_safety_terms=()
for file in \
    "$FRAMEWORK_DIR/skills/assistant-review/references/review-checklists.md" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml"; do
    if ! grep -Fq "low-confidence escalation" "$file" && ! grep -Fq "low_confidence_escalation" "$file"; then
        missing_loop_safety_terms+=("$file")
    fi
done
if ! grep -Fq 'Agentic loop flag -> Agentic Loop Safety Checklist' "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md" \
    || ! grep -Fq 'references/review-checklists.md' "$FRAMEWORK_DIR/skills/assistant-review/contracts/index.yaml"; then
    missing_loop_safety_terms+=("assistant-review root/index worker-bundle routing")
fi
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
    "Controller intensity" \
    "Required gates" \
    "Required agents" \
    "Subagent policy state" \
    "Subagent execution mode" \
    "Subagent trigger scope" \
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
    "Triage metadata" \
    "intensity=[controller_intensity]"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md"; then
        missing_triage_terms+=("SKILL.md: $term")
    fi
done
for term in \
    "risk_tier" \
    "controller_intensity" \
    "required_gates" \
    "required_agents" \
    "subagent_policy_state" \
    "subagent_execution_mode" \
    "subagent_trigger_scope"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/input.yaml"; then
        missing_triage_terms+=("input.yaml: $term")
    fi
done
for term in \
    "T4" \
    "T_CONTROLLER_INTENSITY" \
    "T9" \
    "T10" \
    "risk_tier is set" \
    "controller_intensity is set" \
    "required_gates includes common gates" \
    "build_execution_lane and required_agents/fallback roles are populated" \
    "subagent_policy_state, subagent_execution_mode, and subagent_trigger_scope are initialized" \
    "candidate_scope_scan is populated from a quick read-only scan"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"; then
        missing_triage_terms+=("phase-gates.yaml: $term")
    fi
done
for term in \
    "Task type:" \
    "Risk tier:" \
    "Controller intensity:" \
    "Required gates:" \
    "Required agents:" \
    "Subagent policy state:" \
    "Subagent execution mode:" \
    "Subagent trigger scope:" \
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
    "caller, consumer, test, docs, contract, config, mirror, runtime" \
    "candidate_scope_scan"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml"; then
        missing_reference_mapping_terms+=("handoffs.yaml: $term")
    fi
done
for term in \
    "D8A" \
    "When a context map is required: it includes references_checked" \
    "behaviorally relevant callers, consumers, tests, docs, contracts, config, generated mirrors, and runtime surfaces"; do
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

test_start "workflow records bounded reuse-search evidence for rule-like changes"
reuse_search_workflow_failures=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml::reuse_search" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml::business rules, validation, calculations/conversions, mappings, schema/config semantics, permissions, or protocol details" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml::before implementation" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/context-map-template.md::## Reuse Search" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/context-map-template.md::applicability_reason: [concrete reason]" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/plan-template.md::- Reuse search:" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/plan-template.md::decision_rationale"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        reuse_search_workflow_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
if [[ "${#reuse_search_workflow_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow reuse-search evidence gate/template is incomplete: ${reuse_search_workflow_failures[*]}"
fi

test_start "internal workflow controller reference exists and is linked"
workflow_controller_ref="$FRAMEWORK_DIR/skills/assistant-workflow/references/workflow-controller.md"
controller_link_failures=()
if [[ ! -f "$workflow_controller_ref" ]]; then
    controller_link_failures+=("missing skills/assistant-workflow/references/workflow-controller.md")
fi
for file in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"; do
    if ! grep -Fq "references/workflow-controller.md" "$file"; then
        controller_link_failures+=("${file#$FRAMEWORK_DIR/}: missing references/workflow-controller.md")
    fi
done
public_controller_dirs=()
while IFS= read -r public_controller_dir; do
    public_controller_dirs+=("$public_controller_dir")
done < <(find "$FRAMEWORK_DIR/skills" -mindepth 1 -maxdepth 1 -type d -name '*workflow-controller*' -print)
if [[ "${#public_controller_dirs[@]}" -ne 0 ]]; then
    controller_link_failures+=("public workflow-controller skill dirs: ${public_controller_dirs[*]}")
fi
for ref in \
    build-worker-protocol \
    review-qa-router \
    harness-runtime-artifacts \
    completion-controller; do
    if [[ ! -f "$FRAMEWORK_DIR/skills/assistant-workflow/references/$ref.md" ]]; then
        controller_link_failures+=("missing skills/assistant-workflow/references/$ref.md")
    fi
done
public_boundary_dirs=()
while IFS= read -r public_boundary_dir; do
    public_boundary_dirs+=("$public_boundary_dir")
done < <(find "$FRAMEWORK_DIR/skills" -mindepth 1 -maxdepth 1 -type d \( \
    -name '*build-worker-protocol*' -o \
    -name '*review-qa-router*' -o \
    -name '*harness-runtime-artifacts*' -o \
    -name '*completion-controller*' \
\) -print)
if [[ "${#public_boundary_dirs[@]}" -ne 0 ]]; then
    controller_link_failures+=("public workflow boundary skill dirs: ${public_boundary_dirs[*]}")
fi
phases_ref="$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"
for copied_matrix_phrase in \
    "light for small low-risk work" \
    "strict only for high/critical" \
    "Treat \`harness_capable\` as false unless" \
    "Treat harness_capable as false unless" \
    "Treat \`qa_evaluation_mode=not_required\` unless" \
    "Treat qa_evaluation_mode=not_required unless"; do
    if grep -Fq "$copied_matrix_phrase" "$phases_ref"; then
        controller_link_failures+=("phases.md copied controller routing matrix phrase: $copied_matrix_phrase")
    fi
done
for term in \
    "Apply \`references/workflow-controller.md\` for shared routing/default decisions." \
    "When \`harness_capable=true\`, load \`references/harness-controller.md\` plus \`references/plan-harness-appendix.md\`" \
    "Done Contract, Harness Recipe, Harness Run State, Trace Ledger, Replay Packet, and Artifact Reference Ledger refs before task packets" \
    "Load \`references/build-worker-protocol.md\` for source-changing Build work" \
    "Load \`references/review-qa-router.md\`" \
    "Load \`references/completion-controller.md\`"; do
    if ! grep -Fq "$term" "$phases_ref"; then
        controller_link_failures+=("phases.md missing controller handoff term: $term")
    fi
done
if ! grep -Fq "references/harness-runtime-artifacts.md" "$phases_ref" \
    || ! grep -Fq "references/harness-runtime-artifacts.md" "$FRAMEWORK_DIR/skills/assistant-workflow/references/harness-controller.md"; then
    controller_link_failures+=("harness runtime artifact reference is not linked from phases.md and harness-controller.md")
fi
skill_entrypoint="$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md"
for term in \
    "Load \`references/workflow-controller.md\` only when resolving shared routing/default, movement, harness, review, QA, or subagent-separation decisions." \
    "\`references/workflow-controller.md\` is the canonical source for controller intensity, workflow state, manual verification, harness/QA routing, and review-role separation."; do
    if ! grep -Fq "$term" "$skill_entrypoint"; then
        controller_link_failures+=("SKILL.md missing lean controller term: $term")
    fi
done
for entrypoint_bloat_phrase in \
    "## Internal Workflow Controller" \
    "Load \`references/workflow-controller.md\` for shared routing/default decisions, then load \`references/phases.md\`" \
    "Shared routing/default decisions come from the internal \`references/workflow-controller.md\` reference"; do
    if grep -Fq "$entrypoint_bloat_phrase" "$skill_entrypoint"; then
        controller_link_failures+=("SKILL.md reintroduced controller bloat phrase: $entrypoint_bloat_phrase")
    fi
done
if [[ "${#controller_link_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow controller reference/linkage guard failed: ${controller_link_failures[*]}"
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

test_start "workflow loop experiment artifacts stay conditional and non-harness"
missing_loop_artifact_terms=()
for term in \
    "workflow_experiment_ledger" \
    "explicit workflow experiment" \
    "loop_readiness_assessment" \
    "explicit repeat or optimization loop" \
    "retry_or_empty_result_handling" \
    "tool_error_handling" \
    "low_confidence_escalation" \
    "loop artifacts alone do not require"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"; then
        missing_loop_artifact_terms+=("output.yaml: $term")
    fi
done
for term in \
    "P_WORKFLOW_EXPERIMENT_LEDGER" \
    "P_LOOP_READINESS" \
    "retry_or_empty_result_handling" \
    "tool_error_handling" \
    "low_confidence_escalation" \
    "Keep harness_routing=not_required unless harness_capable == true"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"; then
        missing_loop_artifact_terms+=("phase-gates.yaml: $term")
    fi
done
for term in \
    "Loop / Experiment Routing" \
    "harness_capable=false" \
    "retry_or_empty_result_handling" \
    "tool_error_handling" \
    "low_confidence_escalation" \
    "loop artifacts alone do not"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/plan-template.md"; then
        missing_loop_artifact_terms+=("plan-template.md: $term")
    fi
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md"; then
        missing_loop_artifact_terms+=("task-journal-template.md: $term")
    fi
done
for term in \
    "loop-experiment-artifacts-stay-conditional" \
    "workflow_experiment_ledger" \
    "loop_readiness_assessment" \
    "retry_or_empty_result_handling" \
    "tool_error_handling" \
    "low_confidence_escalation" \
    "harness_capable=false"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json"; then
        missing_loop_artifact_terms+=("workflow eval: $term")
    fi
done
if [[ "${#missing_loop_artifact_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow loop experiment contract missing terms: ${missing_loop_artifact_terms[*]}"
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
    "If state files are unavailable, carry the equivalent state in the response/plan packet."; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"; then
        missing_state_terms+=("phases.md: $term")
    fi
done
for term in \
    "orchestrator-owned {agent_state_dir}/task.md state artifact" \
    "a compact context map exists at {agent_state_dir}/context-map.md when local state artifacts are configured and policy-allowed, or context map content is included in the task/plan packet when state files are unavailable"; do
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
if ! grep -Fq ".codex/" "$FRAMEWORK_DIR/.gitignore"; then
    missing_state_terms+=(".gitignore: .codex/")
fi
if [[ "${#missing_state_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow state artifact ownership missing terms: ${missing_state_terms[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
