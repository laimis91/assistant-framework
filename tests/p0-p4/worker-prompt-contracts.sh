if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "Claude and Codex core prompts include worker status packets"
missing_prompt_packet_terms=()
for file in \
    agents/codex/code-writer.toml \
    agents/claude/code-writer.md; do
    for term in \
        "## What you return" \
        '`status`: one of `DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, `BLOCKED`, or `DEVIATED`' \
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
        "code defects, security, architecture, test coverage, and structural code issues" \
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
    "test/TDD expectation" \
    "verification command" \
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
    "test/TDD expectation" \
    "verification command" \
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

p0p4_finish_suite "${BASH_SOURCE[0]}"
