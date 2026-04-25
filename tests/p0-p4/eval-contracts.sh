if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "docs eval fixture JSON has required behavior cases"
if jq -e '
    .schema_version == "1.0"
    and (.cases | type == "array")
    and ([.cases[].id] | contains([
      "ambiguous-prompt-clarify-or-default-deterministically",
      "compaction-resume-reads-task-state-first",
      "codex-role-constraints-without-subagentstart",
      "executable-task-packet-before-build",
      "medium-feature-plans-before-build",
      "per-component-verification-before-advancing",
      "review-loop-continues-after-findings",
      "small-fix-stays-lightweight",
      "spec-review-not-replaced-by-quality-review",
      "tdd-red-before-green-handoff",
      "worker-status-packet-required"
    ]))
    and (.cases | length >= 11)
' "$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json" >/dev/null; then
    pass
else
    fail "eval JSON is invalid or missing required behavior cases"
fi

test_start "docs eval fixture JSON includes six new case areas"
if jq -e '
    def case_category($id; $category):
      any(.cases[]; .id == $id and .category == $category);
    case_category("tdd-red-before-green-handoff"; "tdd_handoff")
    and case_category("executable-task-packet-before-build"; "handoff_contracts")
    and case_category("per-component-verification-before-advancing"; "component_verification")
    and case_category("spec-review-not-replaced-by-quality-review"; "review_gates")
    and case_category("worker-status-packet-required"; "subagent_handoffs")
    and case_category("codex-role-constraints-without-subagentstart"; "role_constraints")
' "$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json" >/dev/null; then
    pass
else
    fail "eval JSON missing one or more new case id/category pairs"
fi

test_start "docs eval README lists new behavior areas"
missing_eval_readme_terms=()
for term in \
    "TDD RED-before-GREEN handoff behavior" \
    "executable task packet requirements before build" \
    "per-component verification before advancing" \
    "separate spec review and quality review gates" \
    "structured worker status packets from subagents" \
    "Codex role constraints without SubagentStart reinforcement"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/docs/evals/README.md"; then
        missing_eval_readme_terms+=("$term")
    fi
done
if [[ "${#missing_eval_readme_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "docs/evals/README.md missing new behavior areas: ${missing_eval_readme_terms[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
