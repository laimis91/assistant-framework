#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

require_terms() {
    local label="$1"
    local file="$2"
    shift 2

    local missing=()
    local term
    for term in "$@"; do
        if ! grep -Fq -- "$term" "$file"; then
            missing+=("${file#$FRAMEWORK_DIR/}: $term")
        fi
    done

    if [[ "${#missing[@]}" -eq 0 ]]; then
        pass
    else
        fail "$label missing terms: ${missing[*]}"
    fi
}

skill_creator_patterns="$FRAMEWORK_DIR/skills/assistant-skill-creator/references/harness-patterns.md"

test_start "skill-creator harness patterns cover controller artifacts and loop safety"
require_terms "skill creator harness patterns" "$skill_creator_patterns" \
    "Done Contract" \
    "debate_record" \
    "Harness Recipe" \
    "Runtime State, Trace, And Replay" \
    "Typed Artifact References" \
    "Code Review And QA Separation" \
    "Conditional Domain Rubrics" \
    "Bounded Review / QA Loops" \
    "[common task-level stagnation guard](operating-guidance.md)" \
    "Pivot / Restart Decisions" \
    "legacy_code_bug" \
    "Agentic Loop Safety"

p0p4_finish_suite "${BASH_SOURCE[0]}"
