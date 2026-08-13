#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

context_report="$FRAMEWORK_DIR/tools/context-budget-report.sh"
eval_readme="$FRAMEWORK_DIR/docs/evals/README.md"
context_evidence_lib="$FRAMEWORK_DIR/tools/evals/lib/context-budget-evidence.sh"

test_start "context budget reporter exists and is executable"
if [[ -x "$context_report" ]]; then
    pass
else
    fail "context budget reporter is missing or not executable: $context_report"
fi

test_start "context budget reporter rejects the non-portable awk quote escape"
nonportable_quote_trim='gsub(/^[[:space:]\"\047]+|[[:space:]\"\047]+$/, "", value)'
if grep -Fq -- "$nonportable_quote_trim" "$context_report"; then
    fail "context budget reporter escapes a double quote inside an awk regex"
else
    pass
fi

test_start "context reporter anchors catalog discovery below the skills root"
catalog_path_fixture="$(mktemp -d "${TMPDIR:-/tmp}/assistant-framework.XXXXXX")"
p0p4_register_cleanup "$catalog_path_fixture"
mkdir -p \
    "$catalog_path_fixture/skills/assistant-real" \
    "$catalog_path_fixture/skills/unity-temporary"
printf '%s\n' '---' 'name: assistant-real' 'description: "Real"' '---' \
    >"$catalog_path_fixture/skills/assistant-real/SKILL.md"
printf '%s\n' '---' 'name: unity-temporary' 'description: "Temporary"' '---' \
    >"$catalog_path_fixture/skills/unity-temporary/SKILL.md"
unsafe_catalog_match_count="$(find "$catalog_path_fixture/skills" \
    -mindepth 2 -maxdepth 2 -type f -path '*/assistant-*/SKILL.md' -print \
    | wc -l | tr -d '[:space:]')"
safe_catalog_matches="$(cd "$catalog_path_fixture" \
    && find skills -mindepth 2 -maxdepth 2 -type f \
        -path 'skills/assistant-*/SKILL.md' -print | LC_ALL=C sort)"
if [[ "$unsafe_catalog_match_count" -eq 2 ]] \
    && [[ "$safe_catalog_matches" == "skills/assistant-real/SKILL.md" ]] \
    && ! grep -Fq -- "-path '*/assistant-*/SKILL.md'" "$context_report" \
    && grep -Fq -- "-path 'skills/assistant-*/SKILL.md'" "$context_report"; then
    pass
else
    fail "context reporter catalog discovery is sensitive to an assistant-prefixed repository path"
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
    && printf '%s\n' "$context_help" | grep -Fq -- "--skill-overlay FILE" \
    && ! printf '%s\n' "$context_help" | grep -Fq -- "hook-profile"; then
    pass
else
    fail "context budget reporter help is missing a required option or still documents hook profiles"
fi

test_start "eval README documents the reproducible context budget command"
if grep -Fq -- "tools/context-budget-report.sh" "$eval_readme" \
    && grep -Fq -- "--agent codex --skill assistant-workflow --format json" "$eval_readme" \
    && grep -Fq -- "source-repository-only" "$eval_readme" \
    && ! grep -Fq -- "hook-output semantics" "$eval_readme" \
    && ! grep -Fq -- "hook-benchmark" "$eval_readme"; then
    pass
else
    fail "docs/evals/README.md does not document the hookless native Codex context budget command"
fi

test_start "eval README documents workflow-kernel promotion caps"
if grep -Fq -- "fixed selected-skill caps of 1050 initial" "$eval_readme" \
    && grep -Fq -- "words and 3000 entry-boundary words" "$eval_readme" \
    && ! grep -Fq -- "1000 initial words" "$eval_readme" \
    && ! grep -Fq -- "2600 entry-boundary words" "$eval_readme"; then
    pass
else
    fail "docs/evals/README.md does not document the current workflow-kernel promotion caps"
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
wc_interceptor_dir="$(mktemp -d "${TMPDIR:-/tmp}/context-budget-wc-interceptor.XXXXXX")"
wc_interceptor_marker="$wc_interceptor_dir/word-count-called"
wc_interceptor_report="$(mktemp "${TMPDIR:-/tmp}/context-budget-wc-report.XXXXXX")"
overlay_skill="$(mktemp "${TMPDIR:-/tmp}/context-budget-overlay.XXXXXX")"
overlay_report="$(mktemp "${TMPDIR:-/tmp}/context-budget-overlay-report.XXXXXX")"
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
    "$bash_interceptor_dir" \
    "$wc_interceptor_dir" \
    "$wc_interceptor_report" \
    "$overlay_skill" \
    "$overlay_report"

cat >"$overlay_skill" <<'EOF'
---
name: assistant-workflow
description: "Overlay fixture"
---
# Small overlay
Use canonical contracts.
EOF

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

cat >"$wc_interceptor_dir/wc" <<'EOF'
#!/bin/bash

if [[ "${1:-}" == "-w" ]]; then
    : >"${CONTEXT_BUDGET_WC_MARKER:?}"
    printf '999\n'
    exit 0
fi

exec /usr/bin/wc "$@"
EOF
chmod +x "$wc_interceptor_dir/wc"

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

test_start "context reporter word counts are independent of platform wc"
rm -f "$wc_interceptor_marker"
if HOME="$report_home" \
    PATH="$wc_interceptor_dir:$PATH" \
    CONTEXT_BUDGET_WC_MARKER="$wc_interceptor_marker" \
    "$context_report" \
        --agent codex \
        --skill assistant-workflow \
        --format json \
        >"$wc_interceptor_report" 2>"$report_error" \
    && [[ ! -e "$wc_interceptor_marker" ]] \
    && jq -e --slurpfile canonical "$report_output" '
        .components.project_agents.words == $canonical[0].components.project_agents.words
        and .components.generated_global_agents.words == $canonical[0].components.generated_global_agents.words
        and .components.native_skill_catalog_descriptions.words == $canonical[0].components.native_skill_catalog_descriptions.words
        and .components.selected_skill_initial.words == $canonical[0].components.selected_skill_initial.words
        and .components.selected_skill_entry_boundary.words == $canonical[0].components.selected_skill_entry_boundary.words
        and .totals.initial_words == $canonical[0].totals.initial_words
        and .totals.entry_boundary_words == $canonical[0].totals.entry_boundary_words
    ' "$wc_interceptor_report" >/dev/null; then
    pass
else
    fail "context reporter word measurements changed with the host wc implementation"
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
        and (.components | has("generated_memory_protocol") | not)
        and ([
          .components.project_agents.words,
          .components.project_agents.bytes,
          .components.generated_global_agents.words,
          .components.generated_global_agents.bytes,
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
    (.components | has("generated_memory_protocol") | not)
    and ([
      .components.project_agents.words,
      .components.project_agents.bytes,
      .components.generated_global_agents.words,
      .components.generated_global_agents.bytes,
      .components.native_skill_catalog_descriptions.words,
      .components.native_skill_catalog_descriptions.bytes,
      .components.native_skill_catalog_descriptions.characters,
      .components.selected_skill_initial.words,
      .components.selected_skill_initial.bytes,
      .components.selected_skill_entry_boundary.words,
      .components.selected_skill_entry_boundary.bytes
    ] | all(.[]; type == "number" and . >= 0))
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
      + .components.native_skill_catalog_descriptions.words;
    def standing_bytes:
      .components.project_agents.bytes
      + .components.generated_global_agents.bytes
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

test_start "context reporter measures a root overlay while keeping canonical contracts"
if HOME="$report_home" \
    "$context_report" \
        --agent codex \
        --skill assistant-workflow \
        --skill-overlay "$overlay_skill" \
        --format json \
        >"$overlay_report" 2>"$report_error" \
    && jq -e --slurpfile canonical "$report_output" '
        .overlay_applied == true
        and .components.selected_skill_initial.words < $canonical[0].components.selected_skill_initial.words
        and .components.selected_skill_entry_boundary.words < $canonical[0].components.selected_skill_entry_boundary.words
        and .components.project_agents.words == $canonical[0].components.project_agents.words
        and .components.native_skill_catalog_descriptions.words == $canonical[0].components.native_skill_catalog_descriptions.words
    ' "$overlay_report" >/dev/null; then
    pass
else
    fail "skill overlay did not replace only the selected root measurement"
fi

test_start "workflow kernel candidate meets the static promotion budget"
kernel_skill="$FRAMEWORK_DIR/docs/evals/variants/workflow-kernel-v1/SKILL.md"
kernel_manifest="$FRAMEWORK_DIR/docs/evals/variants/workflow-kernel-v1/manifest.json"
if HOME="$report_home" \
    "$context_report" --agent codex --skill assistant-workflow \
        --skill-overlay "$kernel_skill" --format json >"$overlay_report" 2>"$report_error" \
    && jq -e --slurpfile baseline "$report_output" --slurpfile candidate "$overlay_report" '
        .status == "candidate"
        and .promotion_gates.selected_initial_words_max == 1050
        and .promotion_gates.selected_entry_words_max == 3000
        and .promotion_gates.standing_context_growth_allowed == false
        and .static_measurement.baseline_selected_initial_words == $baseline[0].components.selected_skill_initial.words
        and .static_measurement.candidate_selected_initial_words == $candidate[0].components.selected_skill_initial.words
        and .static_measurement.selected_initial_word_delta == ($candidate[0].components.selected_skill_initial.words - $baseline[0].components.selected_skill_initial.words)
        and .static_measurement.baseline_total_initial_words == $baseline[0].totals.initial_words
        and .static_measurement.candidate_total_initial_words == $candidate[0].totals.initial_words
        and .static_measurement.baseline_selected_entry_words == $baseline[0].components.selected_skill_entry_boundary.words
        and .static_measurement.candidate_selected_entry_words == $candidate[0].components.selected_skill_entry_boundary.words
        and .static_measurement.selected_entry_word_delta == ($candidate[0].components.selected_skill_entry_boundary.words - $baseline[0].components.selected_skill_entry_boundary.words)
        and .static_measurement.candidate_selected_initial_words <= .promotion_gates.selected_initial_words_max
        and .static_measurement.candidate_selected_entry_words <= .promotion_gates.selected_entry_words_max
        and .static_measurement.standing_context_growth == 0
        and $candidate[0].components.project_agents == $baseline[0].components.project_agents
        and $candidate[0].components.generated_global_agents == $baseline[0].components.generated_global_agents
        and $candidate[0].components.native_skill_catalog_descriptions == $baseline[0].components.native_skill_catalog_descriptions
    ' "$kernel_manifest" >/dev/null; then
    pass
else
    fail "workflow kernel candidate exceeds its static budget or lacks promotion evidence"
fi

test_start "context evidence structure is generic while promotion policy rejects standing growth"
standing_evidence="$(mktemp "${TMPDIR:-/tmp}/standing-context-evidence.XXXXXX")"
p0p4_register_cleanup "$standing_evidence"
jq -cnS '{
  schema_version:"1.0",reporter_sha256:("a"*64),
  baseline_instruction_sha256:("b"*64),candidate_instruction_sha256:("c"*64),
  policy_caps:{selected_initial_words_max:1050,selected_entry_words_max:3000,standing_context_growth_allowed:false},
  baseline:{selected_initial_words:800,selected_entry_words:2000,total_initial_words:900,total_entry_words:2100,standing_initial_words:100,standing_entry_words:100},
  candidate:{selected_initial_words:700,selected_entry_words:1900,total_initial_words:801,total_entry_words:2001,standing_initial_words:101,standing_entry_words:101},
  deltas:{selected_initial_words:-100,selected_entry_words:-100,standing_initial_words:1,standing_entry_words:1}
}' >"$standing_evidence"
if (source "$context_evidence_lib"; \
    context_budget_validate_evidence_structure "$standing_evidence" \
    && ! context_budget_validate_promotion_policy "$standing_evidence"); then
    pass
else
    fail "structural evidence validation and workflow-kernel promotion policy were not separated"
fi

test_start "manifest mismatch diagnostics expose expected and actual counts only"
diagnostic_manifest="$(mktemp "${TMPDIR:-/tmp}/context-budget-diagnostic-manifest.XXXXXX")"
diagnostic_evidence="$(mktemp "${TMPDIR:-/tmp}/context-budget-diagnostic-evidence.XXXXXX")"
diagnostic_error="$(mktemp "${TMPDIR:-/tmp}/context-budget-diagnostic-error.XXXXXX")"
p0p4_register_cleanup "$diagnostic_manifest" "$diagnostic_evidence" "$diagnostic_error"
jq '.static_measurement.candidate_selected_entry_words += 1' \
    "$kernel_manifest" >"$diagnostic_manifest"
jq -cnS --slurpfile manifest "$kernel_manifest" '
  $manifest[0].static_measurement as $m
  | {
      baseline:{
        selected_initial_words:$m.baseline_selected_initial_words,
        total_initial_words:$m.baseline_total_initial_words,
        selected_entry_words:$m.baseline_selected_entry_words
      },
      candidate:{
        selected_initial_words:$m.candidate_selected_initial_words,
        total_initial_words:$m.candidate_total_initial_words,
        selected_entry_words:$m.candidate_selected_entry_words
      },
      deltas:{
        selected_initial_words:$m.selected_initial_word_delta,
        selected_entry_words:$m.selected_entry_word_delta,
        standing_initial_words:$m.standing_context_growth
      }
    }
' >"$diagnostic_evidence"
diagnostic_manifest_value="$(jq -r '.static_measurement.candidate_selected_entry_words' "$diagnostic_manifest")"
diagnostic_evidence_value="$(jq -r '.candidate.selected_entry_words' "$diagnostic_evidence")"
expected_diagnostic="$(jq -cn \
    --argjson manifest "$diagnostic_manifest_value" \
    --argjson evidence "$diagnostic_evidence_value" \
    '{candidate_selected_entry_words:{manifest:$manifest,evidence:$evidence}}')"
if (source "$context_evidence_lib"; \
    context_budget_validate_manifest "$diagnostic_manifest" "$diagnostic_evidence" \
        2>"$diagnostic_error"); then
    fail "context budget validator accepted a mismatched candidate entry count"
elif grep -Fxq -- "Context budget manifest mismatch: $expected_diagnostic" "$diagnostic_error"; then
    pass
else
    fail "context budget mismatch did not emit a count-only expected-versus-actual diagnostic"
fi

test_start "manifest mismatch diagnostics identify the divergent standing component"
component_reporter="$(mktemp "${TMPDIR:-/tmp}/context-budget-component-reporter.XXXXXX")"
component_baseline_overlay="$(mktemp "${TMPDIR:-/tmp}/context-budget-component-baseline.XXXXXX")"
component_candidate_overlay="$(mktemp "${TMPDIR:-/tmp}/context-budget-component-candidate.XXXXXX")"
component_evidence="$(mktemp "${TMPDIR:-/tmp}/context-budget-component-evidence.XXXXXX")"
component_error="$(mktemp "${TMPDIR:-/tmp}/context-budget-component-error.XXXXXX")"
p0p4_register_cleanup \
    "$component_reporter" "$component_baseline_overlay" "$component_candidate_overlay" \
    "$component_evidence" "$component_error"
cat >"$component_reporter" <<EOF
#!/usr/bin/env bash
set -euo pipefail
overlay=""
while [[ \$# -gt 0 ]]; do
    if [[ "\$1" == "--skill-overlay" ]]; then
        overlay="\$2"
        shift 2
    else
        shift
    fi
done
if [[ "\$overlay" == "$component_baseline_overlay" ]]; then
    selected_initial=1677
    selected_entry=3224
else
    selected_initial=979
    selected_entry=2526
fi
jq -n \
    --argjson selected_initial "\$selected_initial" \
    --argjson selected_entry "\$selected_entry" '
    {
      components:{
        project_agents:{words:254,bytes:2186},
        generated_global_agents:{words:267,bytes:1900},
        native_skill_catalog_descriptions:{
          words:286,
          bytes:2101,
          characters:2101
        },
        selected_skill_initial:{words:\$selected_initial},
        selected_skill_entry_boundary:{words:\$selected_entry}
      },
      totals:{
        initial_words:(\$selected_initial + 807),
        entry_boundary_words:(\$selected_entry + 807)
      }
    }'
EOF
chmod +x "$component_reporter"
expected_components='{"baseline":{"project_agents":{"words":254,"bytes":2186},"generated_global_agents":{"words":267,"bytes":1900},"native_skill_catalog_descriptions":{"words":286,"bytes":2101,"characters":2101}},"candidate_matches_baseline":true}'
if (source "$context_evidence_lib"; \
    hash_file() { printf '%064d\n' 0; }; \
    context_budget_build_evidence \
        "$component_reporter" "$component_baseline_overlay" "$component_candidate_overlay" \
        "$(printf '%064d' 1)" "$(printf '%064d' 2)" "$component_evidence" \
    && context_budget_validate_manifest "$kernel_manifest" "$component_evidence" \
        2>"$component_error"); then
    fail "context budget validator accepted divergent standing components"
elif grep -Fxq -- "Context budget standing components: $expected_components" "$component_error"; then
    pass
else
    fail "context budget mismatch did not identify the divergent standing component"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
