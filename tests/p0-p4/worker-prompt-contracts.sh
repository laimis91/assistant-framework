if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "Codex and Claude implementation/verifier profiles preserve selected checks and conditional TDD"
tdd_profile_failures=()
for file in \
    agents/codex/code-writer.toml \
    agents/codex/intelligent-writer.toml \
    agents/codex/mechanical-writer.toml \
    agents/claude/code-writer.md \
    agents/claude/intelligent-writer.md \
    agents/claude/mechanical-writer.md; do
    for term in \
        "Preserve the canonical" \
        '`tdd_applies` is true' \
        "intersection" \
        'task-wide `tdd_mode`' \
        "selected checks" \
        "binding" \
        "intersection of due selected and unchanged applicable IDs" \
        "Split packets" \
        "with multiple intersecting IDs." \
        "Standalone/no-decision TDD does not invent a CheckSpec ID." \
        "tdd_cycle_log_ref" \
        "create the in-progress entry if needed" \
        "green.production_file" \
        "Only after the ref shows current" \
        "same Code Writer" \
        "refactor.changes_made" \
        "none needed"; do
        if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/$file"; then
            tdd_profile_failures+=("$file missing $term")
        fi
    done
done
for file in agents/codex/builder-tester.toml agents/claude/builder-tester.md; do
    for term in \
        "When TDD is active" \
        "when false," \
        "selected checks and binding project suites" \
        "verification_stage" \
        "pre_production_red" \
        "final_verification" \
        "exact typed seven-field RED evidence" \
        "only when the matching meaningful failure is observed" \
        "Otherwise omit" \
        "If that RED is observed alongside another due" \
        "while FAILED_VERIFICATION keeps precedence" \
        "omit when it was not observed" \
        "Forward valid RED evidence unchanged through Code Writer." \
        "aggregate partial" \
        "does not permit Review" \
        "tdd_cycle_log_ref" \
        "create the in-progress canonical" \
        "stage-only" \
        "pending REFACTOR" \
        "second" \
        "separate current REFACTOR invocations" \
        "omit unstarted phases"; do
        if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/$file"; then
            tdd_profile_failures+=("$file missing $term")
        fi
    done
done
if [[ "${#tdd_profile_failures[@]}" -eq 0 ]]; then pass; else fail "worker profile TDD/verification policy diverged: ${tdd_profile_failures[*]}"; fi

test_start "Claude and Codex core prompts include worker status packets"
missing_prompt_packet_terms=()
for file in \
    agents/codex/code-writer.toml \
    agents/codex/intelligent-writer.toml \
    agents/codex/mechanical-writer.toml \
    agents/claude/code-writer.md \
    agents/claude/intelligent-writer.md \
    agents/claude/mechanical-writer.md; do
    for term in \
        "## What you return" \
        '`status`: one of `DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, `BLOCKED`, `DEVIATED`, or `FAILED_VERIFICATION`' \
        '`changed_files`: files created, modified, or deleted with brief descriptions' \
        '`evidence`: concrete implementation evidence, usually file paths plus behavior changed' \
        "## Status meanings"; do
        if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/$file"; then
            missing_prompt_packet_terms+=("$file: $term")
        fi
    done
done
for file in \
    agents/codex/builder-tester.toml \
    agents/claude/builder-tester.md; do
    for term in \
        "## What you return (CONCISE format)" \
        '**Status**: `DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, `BLOCKED`, `DEVIATED`, or `FAILED_VERIFICATION`' \
        '**Verification**: commands/checks run plus concise success signals or failure messages' \
        '`FAILED_VERIFICATION`: build, tests, or required checks ran and failed'; do
        if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/$file"; then
            missing_prompt_packet_terms+=("$file: $term")
        fi
    done
done
for file in \
    agents/codex/reviewer.toml \
    agents/claude/reviewer.md; do
    for term in \
        "Start with a status packet:" \
        '`status`: `DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, or `BLOCKED`' \
        '`evidence`: review material, files, searches, or checks supporting the verdict' \
        "## Status meanings"; do
        if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/$file"; then
            missing_prompt_packet_terms+=("$file: $term")
        fi
    done
done
if [[ "${#missing_prompt_packet_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "Claude/Codex prompts missing worker status packet terms: ${missing_prompt_packet_terms[*]}"
fi

test_start "Code Reviewer prompts are canonical read-only code review role"
missing_code_reviewer_terms=()
for file in \
    agents/codex/code-reviewer.toml \
    agents/claude/code-reviewer.md; do
    for term in \
        "canonical code reviewer" \
        "selected verification methods" \
        "absence of tests alone is not a finding" \
        "Start with a status packet:" \
        '`status`: `DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, or `BLOCKED`' \
        '`evidence`: review material, files, searches, or checks supporting the verdict' \
        "Do NOT edit any files" \
        "Stay in the code-review lane"; do
        if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/$file"; then
            missing_code_reviewer_terms+=("$file: $term")
        fi
    done
done
if ! grep -Fq 'sandbox_mode = "read-only"' "$FRAMEWORK_DIR/agents/codex/code-reviewer.toml"; then
    missing_code_reviewer_terms+=("agents/codex/code-reviewer.toml: read-only sandbox")
fi
if ! grep -Fq 'tools: Read, Grep, Glob, LS' "$FRAMEWORK_DIR/agents/claude/code-reviewer.md"; then
    missing_code_reviewer_terms+=("agents/claude/code-reviewer.md: read-only tools")
fi
if grep -Eq '^tools: .*Edit|^tools: .*Write|^tools: .*Bash' "$FRAMEWORK_DIR/agents/claude/code-reviewer.md"; then
    missing_code_reviewer_terms+=("agents/claude/code-reviewer.md: unexpected write/shell tools")
fi
if [[ "${#missing_code_reviewer_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "Code Reviewer prompts missing canonical read-only role terms: ${missing_code_reviewer_terms[*]}"
fi

test_start "Codex mapper explorer architect prompts include status packet guidance"
missing_codex_discovery_status_terms=()
for file in \
    agents/codex/code-mapper.toml \
    agents/codex/explorer.toml; do
    for term in \
        "## Status packet" \
        "DONE_WITH_CONCERNS" \
        "NEEDS_CONTEXT" \
        "BLOCKED" \
        "evidence" \
        "open_questions"; do
        if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/$file"; then
            missing_codex_discovery_status_terms+=("$file: $term")
        fi
    done
done
for term in \
    "## Status packet" \
    "DONE_WITH_CONCERNS" \
    "NEEDS_CONTEXT" \
    "BLOCKED" \
    "DEVIATED" \
    "evidence" \
    "open_questions" \
    "deviation_details"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/agents/codex/architect.toml"; then
        missing_codex_discovery_status_terms+=("agents/codex/architect.toml: $term")
    fi
done
if [[ "${#missing_codex_discovery_status_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "Codex code-mapper/explorer/architect prompts missing status packet guidance: ${missing_codex_discovery_status_terms[*]}"
fi

test_start "Claude mapper explorer architect prompts include status packet guidance"
missing_claude_discovery_status_terms=()
for file in \
    agents/claude/code-mapper.md \
    agents/claude/explorer.md; do
    for term in \
        "## Status packet" \
        "DONE_WITH_CONCERNS" \
        "NEEDS_CONTEXT" \
        "BLOCKED" \
        "evidence" \
        "open_questions"; do
        if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/$file"; then
            missing_claude_discovery_status_terms+=("$file: $term")
        fi
    done
done
for term in \
    "## Status packet" \
    "DONE_WITH_CONCERNS" \
    "NEEDS_CONTEXT" \
    "BLOCKED" \
    "DEVIATED" \
    "evidence" \
    "open_questions" \
    "deviation_details"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/agents/claude/architect.md"; then
        missing_claude_discovery_status_terms+=("agents/claude/architect.md: $term")
    fi
done
if [[ "${#missing_claude_discovery_status_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "Claude code-mapper/explorer/architect prompts missing status packet guidance: ${missing_claude_discovery_status_terms[*]}"
fi

test_start "Codex architect requires executable task packet fields"
missing_codex_architect_packet_terms=()
for term in \
    "executable task packets" \
    "slice_id/slice_name" \
    "observable increment" \
    "deliverable type" \
    "exact files" \
    "acceptance criteria" \
    "carried verification_decision and current evidence_assessment" \
    "conditional TDD expectation" \
    "exact argv/cwd or concrete selected-check procedure" \
    "expected success signal" \
    "evidence to record" \
    "deviation/rollback rule"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/agents/codex/architect.toml"; then
        missing_codex_architect_packet_terms+=("$term")
    fi
done
if [[ "${#missing_codex_architect_packet_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "Codex architect prompt missing executable task packet terms: ${missing_codex_architect_packet_terms[*]}"
fi

test_start "Claude architect requires executable task packet fields"
missing_claude_architect_packet_terms=()
for term in \
    "executable task packets" \
    "slice_id/slice_name" \
    "observable increment" \
    "deliverable type" \
    "exact files" \
    "acceptance criteria" \
    "carried verification_decision and current evidence_assessment" \
    "conditional TDD expectation" \
    "exact argv/cwd or concrete selected-check procedure" \
    "expected success signal" \
    "evidence to record" \
    "deviation/rollback rule"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/agents/claude/architect.md"; then
        missing_claude_architect_packet_terms+=("$term")
    fi
done
if [[ "${#missing_claude_architect_packet_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "Claude architect prompt missing executable task packet terms: ${missing_claude_architect_packet_terms[*]}"
fi


test_start "all concrete Codex writers retain the shared implementation and truthful partial-work contract"
if ruby - "$FRAMEWORK_DIR" <<'RUBY'
root=ARGV.fetch(0)
texts=%w[code-writer intelligent-writer mechanical-writer].map { |role| File.read("#{root}/agents/codex/#{role}.toml") }
shared=texts.map { |s| s[s.index('## What you do')..-1] }
raise 'common writer contract drift' unless shared.uniq.length == 1
texts.each do |text|
  ['current_task_packet','inline context','conflict blocks','mechanical_eligibility','changed_files','files_changed','FAILED_VERIFICATION','stop dependent mutations','Do NOT review your own code'].each do |term|
    # Case/wording-neutral static contract coverage; outcome controls are separate.
    next if term == 'conflict blocks' && text.include?('conflict blocks dispatch')
    next if term == 'mechanical_eligibility' && text.include?('four eligibility')
    raise "missing writer guarantee #{term}" unless text.downcase.include?(term.downcase)
  end
end
raise 'intelligent boundary missing' unless texts[1].include?('Never invent desired behavior') && texts[1].include?('NEEDS_CONTEXT')
raise 'mechanical judgment not constrained' unless texts[2].include?('Do not choose policy') && texts[2].include?('stale evidence stops dependent mutations')
raise 'legacy definition not deprecated' unless texts[0].include?('Deprecated standalone intelligent compatibility')
RUBY
then pass; else fail "writer definitions dropped shared guarantees or judgment boundaries"; fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
