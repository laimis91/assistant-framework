#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

context_report="$FRAMEWORK_DIR/tools/context-budget-report.sh"
eval_readme="$FRAMEWORK_DIR/docs/evals/README.md"

test_start "context budget reporter exists and is executable"
if [[ -x "$context_report" ]]; then
    pass
else
    fail "context budget reporter is missing or not executable: $context_report"
fi

test_start "context budget reporter documents required CLI modes"
context_help=""
if [[ -x "$context_report" ]]; then
    context_help="$("$context_report" --help 2>&1 || true)"
fi
if printf '%s\n' "$context_help" | grep -Fq -- "--agent AGENT" \
    && printf '%s\n' "$context_help" | grep -Fq -- "codex only" \
    && printf '%s\n' "$context_help" | grep -Fq -- "--skill SKILL" \
    && printf '%s\n' "$context_help" | grep -Fq -- "--format json" \
    && printf '%s\n' "$context_help" | grep -Fq -- "--baseline FILE" \
    && ! printf '%s\n' "$context_help" | grep -Fq -- "hook-profile"; then
    pass
else
    fail "context budget reporter help is missing a required option or still documents hook profiles"
fi

test_start "eval README documents the reproducible context budget command"
if grep -Fq -- "tools/context-budget-report.sh" "$eval_readme" \
    && grep -Fq -- "--agent codex --skill assistant-workflow --format json" "$eval_readme" \
    && ! grep -Fq -- "hook-output semantics" "$eval_readme" \
    && ! grep -Fq -- "hook-benchmark" "$eval_readme"; then
    pass
else
    fail "docs/evals/README.md does not document the hookless native Codex context budget command"
fi

report_home="$(mktemp -d "${TMPDIR:-/tmp}/context-budget-home.XXXXXX")"
report_output="$(mktemp "${TMPDIR:-/tmp}/context-budget-report.XXXXXX")"
report_error="$(mktemp "${TMPDIR:-/tmp}/context-budget-report-error.XXXXXX")"
baseline_report="$(mktemp "${TMPDIR:-/tmp}/context-budget-baseline.XXXXXX")"
comparison_output="$(mktemp "${TMPDIR:-/tmp}/context-budget-comparison.XXXXXX")"
failure_output="$(mktemp "${TMPDIR:-/tmp}/context-budget-failure.XXXXXX")"
failure_error="$(mktemp "${TMPDIR:-/tmp}/context-budget-failure-error.XXXXXX")"
claude_report_home="$(mktemp -d "${TMPDIR:-/tmp}/context-budget-claude-home.XXXXXX")"
claude_report_output="$(mktemp "${TMPDIR:-/tmp}/context-budget-claude-report.XXXXXX")"
claude_report_error="$(mktemp "${TMPDIR:-/tmp}/context-budget-claude-error.XXXXXX")"
no_index_report_home="$(mktemp -d "${TMPDIR:-/tmp}/context-budget-no-index-home.XXXXXX")"
no_index_report_output="$(mktemp "${TMPDIR:-/tmp}/context-budget-no-index-report.XXXXXX")"
no_index_report_error="$(mktemp "${TMPDIR:-/tmp}/context-budget-no-index-error.XXXXXX")"
bash_interceptor_dir="$(mktemp -d "${TMPDIR:-/tmp}/context-budget-bash-interceptor.XXXXXX")"
p0p4_register_cleanup \
    "$report_home" \
    "$report_output" \
    "$report_error" \
    "$baseline_report" \
    "$comparison_output" \
    "$failure_output" \
    "$failure_error" \
    "$claude_report_home" \
    "$claude_report_output" \
    "$claude_report_error" \
    "$no_index_report_home" \
    "$no_index_report_output" \
    "$no_index_report_error" \
    "$bash_interceptor_dir"

cat >"$bash_interceptor_dir/bash" <<'EOF'
#!/bin/bash

case "${CONTEXT_BUDGET_TEST_BASH_MODE:-}" in
    install-failure)
        if [[ "${1:-}" == */install.sh ]]; then
            echo "induced install.sh failure" >&2
            exit 97
        fi
        ;;
esac

exec /bin/bash "$@"
EOF
chmod +x "$bash_interceptor_dir/bash"

test_start "native Codex context report emits isolated machine-readable inventory"
if HOME="$report_home" \
    OPENAI_API_KEY="secret-fixture-value" \
    "$context_report" \
        --agent codex \
        --skill assistant-workflow \
        --format json \
        >"$report_output" 2>"$report_error" \
    && jq -e '
        .schema_version == "2.0"
        and .agent == "codex"
        and .skill == "assistant-workflow"
        and (.inventory_mode == "isolated_install" or .inventory_mode == "source_equivalent")
        and (has("hook_profile") | not)
        and (.components | has("framework_hooks") | not)
    ' "$report_output" >/dev/null; then
    pass
else
    fail "context reporter did not emit valid JSON identity/inventory metadata for native Codex"
fi

test_start "context reporter rejects unsupported non-Codex agents clearly"
if HOME="$claude_report_home" \
    "$context_report" \
        --agent claude \
        --skill assistant-workflow \
        --format json \
        </dev/null >"$claude_report_output" 2>"$claude_report_error"; then
    fail "context reporter unexpectedly accepted unsupported Claude inventory semantics"
elif [[ ! -s "$claude_report_output" ]] \
    && grep -Fq -- "--agent currently supports codex only" "$claude_report_error"; then
    pass
else
    fail "unsupported-agent failure was not clear or emitted a misleading inventory"
fi

test_start "Codex none context report supports a valid skill without contracts index"
if HOME="$no_index_report_home" \
    "$context_report" \
        --agent codex \
        --skill assistant-clarify \
        --format json \
        </dev/null >"$no_index_report_output" 2>"$no_index_report_error" \
    && jq -e '
        .schema_version == "2.0"
        and .agent == "codex"
        and .skill == "assistant-clarify"
        and .inventory_mode == "isolated_install"
        and (has("hook_profile") | not)
        and (.components | has("framework_hooks") | not)
        and ([
          .components.project_agents.words,
          .components.project_agents.bytes,
          .components.generated_global_agents.words,
          .components.generated_global_agents.bytes,
          .components.generated_memory_protocol.words,
          .components.generated_memory_protocol.bytes,
          .components.native_skill_catalog_descriptions.words,
          .components.native_skill_catalog_descriptions.bytes,
          .components.native_skill_catalog_descriptions.characters,
          .components.selected_skill_initial.words,
          .components.selected_skill_initial.bytes,
          .components.selected_skill_entry_boundary.words,
          .components.selected_skill_entry_boundary.bytes,
          .totals.initial_words,
          .totals.initial_bytes,
          .totals.entry_boundary_words,
          .totals.entry_boundary_bytes
        ] | all(.[]; type == "number" and . >= 0))
        and .components.selected_skill_initial.words > 0
        and .components.selected_skill_initial.bytes > 0
        and .components.selected_skill_entry_boundary.words >= .components.selected_skill_initial.words
        and .components.selected_skill_entry_boundary.bytes >= .components.selected_skill_initial.bytes
      ' "$no_index_report_output" >/dev/null; then
    pass
else
    fail "Codex none context report did not emit valid measurements for assistant-clarify without contracts/index.yaml"
fi

test_start "context report exposes numeric component measurements without prompt bodies or secrets"
if jq -e '
    [
      .components.project_agents.words,
      .components.project_agents.bytes,
      .components.generated_global_agents.words,
      .components.generated_global_agents.bytes,
      .components.generated_memory_protocol.words,
      .components.generated_memory_protocol.bytes,
      .components.native_skill_catalog_descriptions.words,
      .components.native_skill_catalog_descriptions.bytes,
      .components.native_skill_catalog_descriptions.characters,
      .components.selected_skill_initial.words,
      .components.selected_skill_initial.bytes,
      .components.selected_skill_entry_boundary.words,
      .components.selected_skill_entry_boundary.bytes
    ]
    | all(.[]; type == "number" and . >= 0)
  ' "$report_output" >/dev/null \
    && ! grep -Eqi 'secret-fixture-value|raw_prompt|prompt_body|api_key' "$report_output"; then
    pass
else
    fail "context report is missing numeric component fields or exposed a raw secret/prompt field"
fi

test_start "context report totals are internally consistent for initial and entry boundaries"
if jq -e '
    def standing_words:
      .components.project_agents.words
      + .components.generated_global_agents.words
      + .components.generated_memory_protocol.words
      + .components.native_skill_catalog_descriptions.words;
    def standing_bytes:
      .components.project_agents.bytes
      + .components.generated_global_agents.bytes
      + .components.generated_memory_protocol.bytes
      + .components.native_skill_catalog_descriptions.bytes;
    .totals.initial_words == (standing_words + .components.selected_skill_initial.words)
    and .totals.initial_bytes == (standing_bytes + .components.selected_skill_initial.bytes)
    and .totals.entry_boundary_words == (standing_words + .components.selected_skill_entry_boundary.words)
    and .totals.entry_boundary_bytes == (standing_bytes + .components.selected_skill_entry_boundary.bytes)
    and .components.selected_skill_entry_boundary.words >= .components.selected_skill_initial.words
    and .components.selected_skill_entry_boundary.bytes >= .components.selected_skill_initial.bytes
  ' "$report_output" >/dev/null; then
    pass
else
    fail "context report initial/entry totals do not equal their component sums"
fi

test_start "context reporter rejects the retired hook profile option"
if "$context_report" \
    --agent codex \
    --hook-profile none \
    --skill assistant-workflow \
    --format json \
    >"$failure_output" 2>"$failure_error"; then
    fail "context reporter unexpectedly accepted the retired --hook-profile option"
elif [[ ! -s "$failure_output" ]] \
    && grep -Fq -- "Unknown option: --hook-profile" "$failure_error"; then
    pass
else
    fail "retired --hook-profile option was not rejected clearly"
fi

test_start "isolated install failure exits nonzero instead of emitting source-equivalent JSON"
if PATH="$bash_interceptor_dir:$PATH" \
    CONTEXT_BUDGET_TEST_BASH_MODE="install-failure" \
    HOME="$report_home" \
    "$context_report" \
        --agent codex \
        --skill assistant-workflow \
        --format json \
        >"$failure_output" 2>"$failure_error"; then
    fail "context report accepted an induced install.sh failure"
elif grep -Eqi 'install.*fail|fail.*install' "$failure_error" \
    && ! jq -e '.inventory_mode == "source_equivalent"' "$failure_output" >/dev/null 2>&1; then
    pass
else
    fail "install.sh failure did not exit nonzero with a clear error and without source-equivalent JSON"
fi

test_start "context report baseline comparison emits absolute and percentage deltas"
if [[ -s "$report_output" ]] \
    && jq '
        .components.project_agents.words += 100
        | .components.project_agents.bytes += 500
        | .totals.initial_words += 100
        | .totals.initial_bytes += 500
        | .totals.entry_boundary_words += 100
        | .totals.entry_boundary_bytes += 500
    ' "$report_output" >"$baseline_report" \
    && HOME="$report_home" \
        OPENAI_API_KEY="secret-fixture-value" \
        "$context_report" \
            --agent codex \
            --skill assistant-workflow \
            --format json \
            --baseline "$baseline_report" \
            >"$comparison_output" 2>"$report_error" \
    && jq -e --slurpfile baseline "$baseline_report" '
        .comparison.absolute.initial_words == (.totals.initial_words - $baseline[0].totals.initial_words)
        and .comparison.absolute.initial_words == -100
        and .comparison.absolute.entry_boundary_words == -100
        and ((
          .comparison.percent.initial_words
          - (((.totals.initial_words - $baseline[0].totals.initial_words) / $baseline[0].totals.initial_words) * 100)
        ) | fabs < 0.0001)
        and ((
          .comparison.percent.entry_boundary_words
          - (((.totals.entry_boundary_words - $baseline[0].totals.entry_boundary_words) / $baseline[0].totals.entry_boundary_words) * 100)
        ) | fabs < 0.0001)
    ' "$comparison_output" >/dev/null \
    && ! grep -Fq "secret-fixture-value" "$comparison_output"; then
    pass
else
    fail "context report baseline comparison is missing correct absolute/percentage deltas or leaked a secret"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
