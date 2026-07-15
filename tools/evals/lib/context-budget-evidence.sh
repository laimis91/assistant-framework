#!/usr/bin/env bash
# Canonical, content-free context-budget evidence shared by the eval runner and finalizer.

context_budget_build_evidence() {
    local reporter="$1" baseline_overlay="$2" candidate_overlay="$3"
    local baseline_instruction_hash="$4" candidate_instruction_hash="$5" destination="$6"
    local temporary baseline_report candidate_report
    CONTEXT_BUDGET_STANDING_COMPONENT_DIAGNOSTIC=""
    [[ -x "$reporter" ]] || return 1
    temporary="$(mktemp -d "${TMPDIR:-/tmp}/framework-context-evidence.XXXXXX")" || return 1
    baseline_report="$temporary/baseline.json"
    candidate_report="$temporary/candidate.json"
    if ! LC_ALL=C "$reporter" --agent codex --skill assistant-workflow \
        --skill-overlay "$baseline_overlay" --format json >"$baseline_report" \
        || ! LC_ALL=C "$reporter" --agent codex --skill assistant-workflow \
        --skill-overlay "$candidate_overlay" --format json >"$candidate_report"; then
        rm -rf "$temporary"
        return 1
    fi
    CONTEXT_BUDGET_STANDING_COMPONENT_DIAGNOSTIC="$(jq -cn \
      --slurpfile baseline "$baseline_report" \
      --slurpfile candidate "$candidate_report" '
      def standing_components($report): {
        project_agents:$report.components.project_agents,
        generated_global_agents:$report.components.generated_global_agents,
        generated_memory_protocol:$report.components.generated_memory_protocol,
        native_skill_catalog_descriptions:$report.components.native_skill_catalog_descriptions
      };
      standing_components($baseline[0]) as $baseline_components
      | standing_components($candidate[0]) as $candidate_components
      | {
          baseline:$baseline_components,
          candidate_matches_baseline:($candidate_components == $baseline_components)
        }
      + if $candidate_components == $baseline_components
        then {}
        else {candidate:$candidate_components}
        end
    ')" || {
        rm -rf "$temporary"
        return 1
    }
    jq -cnS \
      --arg reporter_sha256 "$(hash_file "$reporter")" \
      --arg baseline_instruction_sha256 "$baseline_instruction_hash" \
      --arg candidate_instruction_sha256 "$candidate_instruction_hash" \
      --slurpfile baseline "$baseline_report" \
      --slurpfile candidate "$candidate_report" '
      def counts($report): {
        selected_initial_words:$report.components.selected_skill_initial.words,
        selected_entry_words:$report.components.selected_skill_entry_boundary.words,
        total_initial_words:$report.totals.initial_words,
        total_entry_words:$report.totals.entry_boundary_words,
        standing_initial_words:($report.totals.initial_words - $report.components.selected_skill_initial.words),
        standing_entry_words:($report.totals.entry_boundary_words - $report.components.selected_skill_entry_boundary.words)
      };
      counts($baseline[0]) as $b
      | counts($candidate[0]) as $c
      | {
          schema_version:"1.0",
          reporter_sha256:$reporter_sha256,
          baseline_instruction_sha256:$baseline_instruction_sha256,
          candidate_instruction_sha256:$candidate_instruction_sha256,
          policy_caps:{
            selected_initial_words_max:1000,
            selected_entry_words_max:2600,
            standing_context_growth_allowed:false
          },
          baseline:$b,
          candidate:$c,
          deltas:{
            selected_initial_words:($c.selected_initial_words - $b.selected_initial_words),
            selected_entry_words:($c.selected_entry_words - $b.selected_entry_words),
            standing_initial_words:($c.standing_initial_words - $b.standing_initial_words),
            standing_entry_words:($c.standing_entry_words - $b.standing_entry_words)
          }
        }
    ' >"$destination"
    local status=$?
    rm -rf "$temporary"
    return "$status"
}

context_budget_validate_evidence_structure() {
    local evidence="$1"
    jq -e '
      (keys_unsorted | sort) == (["baseline","baseline_instruction_sha256","candidate","candidate_instruction_sha256","deltas","policy_caps","reporter_sha256","schema_version"] | sort)
      and .schema_version == "1.0"
      and (.reporter_sha256 | test("^[0-9a-f]{64}$"))
      and (.baseline_instruction_sha256 | test("^[0-9a-f]{64}$"))
      and (.candidate_instruction_sha256 | test("^[0-9a-f]{64}$"))
      and .policy_caps == {selected_initial_words_max:1000,selected_entry_words_max:2600,standing_context_growth_allowed:false}
      and all(.baseline[],.candidate[]; type == "number" and . >= 0 and . == floor)
      and .baseline.total_initial_words == (.baseline.selected_initial_words + .baseline.standing_initial_words)
      and .candidate.total_initial_words == (.candidate.selected_initial_words + .candidate.standing_initial_words)
      and .baseline.total_entry_words == (.baseline.selected_entry_words + .baseline.standing_entry_words)
      and .candidate.total_entry_words == (.candidate.selected_entry_words + .candidate.standing_entry_words)
      and .deltas.selected_initial_words == (.candidate.selected_initial_words - .baseline.selected_initial_words)
      and .deltas.selected_entry_words == (.candidate.selected_entry_words - .baseline.selected_entry_words)
      and .deltas.standing_initial_words == (.candidate.standing_initial_words - .baseline.standing_initial_words)
      and .deltas.standing_entry_words == (.candidate.standing_entry_words - .baseline.standing_entry_words)
    ' "$evidence" >/dev/null
}

context_budget_validate_promotion_policy() {
    local evidence="$1"
    jq -e '
      .policy_caps == {selected_initial_words_max:1000,selected_entry_words_max:2600,standing_context_growth_allowed:false}
      and .candidate.selected_initial_words <= .policy_caps.selected_initial_words_max
      and .candidate.selected_entry_words <= .policy_caps.selected_entry_words_max
      and .deltas.standing_initial_words == 0
      and .deltas.standing_entry_words == 0
    ' "$evidence" >/dev/null
}

context_budget_validate_manifest() {
    local manifest="$1" evidence="$2"
    local mismatch
    mismatch="$(jq -c --slurpfile evidence "$evidence" '
      . as $manifest | $evidence[0] as $e
      | {
          selected_initial_words_max:{manifest:.promotion_gates.selected_initial_words_max,evidence:1000},
          selected_entry_words_max:{manifest:.promotion_gates.selected_entry_words_max,evidence:2600},
          standing_context_growth_allowed:{manifest:.promotion_gates.standing_context_growth_allowed,evidence:false},
          baseline_selected_initial_words:{manifest:.static_measurement.baseline_selected_initial_words,evidence:$e.baseline.selected_initial_words},
          candidate_selected_initial_words:{manifest:.static_measurement.candidate_selected_initial_words,evidence:$e.candidate.selected_initial_words},
          baseline_total_initial_words:{manifest:.static_measurement.baseline_total_initial_words,evidence:$e.baseline.total_initial_words},
          candidate_total_initial_words:{manifest:.static_measurement.candidate_total_initial_words,evidence:$e.candidate.total_initial_words},
          baseline_selected_entry_words:{manifest:.static_measurement.baseline_selected_entry_words,evidence:$e.baseline.selected_entry_words},
          candidate_selected_entry_words:{manifest:.static_measurement.candidate_selected_entry_words,evidence:$e.candidate.selected_entry_words},
          selected_initial_word_delta:{manifest:.static_measurement.selected_initial_word_delta,evidence:$e.deltas.selected_initial_words},
          selected_entry_word_delta:{manifest:.static_measurement.selected_entry_word_delta,evidence:$e.deltas.selected_entry_words},
          standing_context_growth:{manifest:.static_measurement.standing_context_growth,evidence:$e.deltas.standing_initial_words}
        }
      | with_entries(select(.value.manifest != .value.evidence))
    ' "$manifest")" || return 1
    [[ "$mismatch" != "{}" ]] || return 0
    printf 'Context budget manifest mismatch: %s\n' "$mismatch" >&2
    if [[ -n "${CONTEXT_BUDGET_STANDING_COMPONENT_DIAGNOSTIC:-}" ]]; then
        printf 'Context budget standing components: %s\n' \
            "$CONTEXT_BUDGET_STANDING_COMPONENT_DIAGNOSTIC" >&2
    fi
    return 1
}
