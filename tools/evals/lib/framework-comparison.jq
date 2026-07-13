def mean($values): if ($values | length) == 0 then null else ($values | add) / ($values | length) end;
def median($values):
  ($values | sort) as $sorted
  | ($sorted | length) as $n
  | if $n == 0 then null
    elif ($n % 2) == 1 then $sorted[($n / 2 | floor)]
    else (($sorted[$n / 2 - 1] + $sorted[$n / 2]) / 2) end;
def at_most_twenty_percent_worse($baseline; $candidate):
  if $baseline == null or $candidate == null then false
  elif $baseline == 0 then $candidate == 0
  else $candidate <= ($baseline * 1.2) end;
def sha256_string: type == "string" and test("^[0-9a-f]{64}$");
def nonempty_string: type == "string" and length > 0;
def sha256_or_null: . == null or sha256_string;
def full_provenance_pair:
  length == 2
  and all(.[];
    .model == .provenance.requested_model
    and
    (.provenance.fixture_sha256 | sha256_string)
    and (.provenance.case_sha256 | sha256_string)
    and (.provenance.grader_sha256 | sha256_string)
    and (.provenance.seed_workspace_sha256 | sha256_string)
    and (.provenance.adapter_version | nonempty_string)
    and (.provenance.cli_version | nonempty_string)
    and (.provenance.requested_model | nonempty_string)
    and (.provenance.runtime_model_attestation == "not_exposed_by_codex_jsonl")
    and (.provenance.model_selection_evidence | nonempty_string)
    and (.provenance.requested_model_catalog_entry_sha256 | sha256_or_null)
    and (.provenance.codex_executable_sha256 | sha256_or_null)
    and (if .provenance.model_selection_evidence == "catalog_entry_and_explicit_model_argument" then
           (.provenance.requested_model_catalog_entry_sha256 | sha256_string)
           and (.provenance.codex_executable_sha256 | sha256_string)
         elif .provenance.model_selection_evidence == "explicit_model_argument_only" then
           .provenance.requested_model_catalog_entry_sha256 == null
         else false end)
    and (.provenance | has("resolved_model") | not))
  and ([.[].provenance.fixture_sha256] | unique | length) == 1
  and ([.[].provenance.case_sha256] | unique | length) == 1
  and ([.[].provenance.grader_sha256] | unique | length) == 1
  and ([.[].provenance.seed_workspace_sha256] | unique | length) == 1
  and ([.[].provenance.adapter_version] | unique | length) == 1
  and ([.[].provenance.cli_version] | unique | length) == 1
  and ([.[].provenance.requested_model] | unique | length) == 1
  and ([.[].provenance.runtime_model_attestation] | unique | length) == 1
  and ([.[].provenance.model_selection_evidence] | unique | length) == 1
  and ([.[].provenance.requested_model_catalog_entry_sha256] | unique | length) == 1
  and ([.[].provenance.codex_executable_sha256] | unique | length) == 1;
def exact_coverage($groups; $cases; $repeats):
  ($cases | type) == "array" and ($cases | length) > 0
  and ($repeats | type) == "number" and $repeats >= 1
  and ([$cases[] as $case_id | ([$groups[] | select(.[0].case_id == $case_id)] | length) == $repeats] | all)
  and ($groups | length) == (($cases | length) * $repeats);
def variant_summary($runs; $variant):
  [$runs[] | select(.variant == $variant)] as $selected
  | ([$selected[].metrics.seeded_defects_detected] | add // 0) as $detected
  | ([$selected[].metrics.seeded_defects_total] | add // 0) as $defects
  | {
      completed_runs: ($selected | length),
      acceptance: {
        passed: ([$selected[] | select(.metrics.acceptance_passed)] | length),
        failed: ([$selected[] | select(.metrics.acceptance_passed | not)] | length),
        rate: (if ($selected | length) == 0 then null else ([$selected[] | select(.metrics.acceptance_passed)] | length) / ($selected | length) end)
      },
      metrics: {
        input_tokens_mean: mean([$selected[].metrics.input_tokens]),
        output_tokens_mean: mean([$selected[].metrics.output_tokens]),
        latency_ms_mean: mean([$selected[].metrics.latency_ms]),
        tool_calls_mean: mean([$selected[].metrics.tool_calls]),
        tool_calls_median: median([$selected[].metrics.tool_calls]),
        question_mark_count_proxy_mean: mean([$selected[].metrics.question_mark_count_proxy]),
        rework_count_mean: mean([$selected[].metrics.rework_count]),
        rework_count_median: median([$selected[].metrics.rework_count]),
        seeded_defects_detected: $detected,
        seeded_defects_total: $defects,
        seeded_defect_recall: (if $defects == 0 then null else $detected / $defects end),
        false_positive_marker_hits_total: ([$selected[].metrics.false_positive_marker_hits] | add // 0),
        scope_deviations_total: ([$selected[].metrics.scope_deviations] | add // 0),
        overall_verifier_failures: ([$selected[] | select(.execution.verifier.status != "passed")] | length),
        workspace_verifier_failures: ([$selected[] | select(.execution.verifier.workspace_status == "failed")] | length)
      }
    };

sort_by(.pair_id, .variant)
| group_by(.pair_id) as $groups
| [$groups[]
    | select(length == 2)
    | select((map(.variant) | sort) == ["baseline", "candidate"])
    | select(all(.[]; .status == "completed"))
    | select((map(.case_id) | unique | length) == 1)
    | select((map(.trial_index) | unique | length) == 1)
    | select(full_provenance_pair)
  ] as $complete_groups
| ([$complete_groups[][]]) as $complete_runs
| variant_summary($complete_runs; "baseline") as $baseline
| variant_summary($complete_runs; "candidate") as $candidate
| exact_coverage($complete_groups; ($manifest.smoke_cases // []); ($manifest.smoke_repeats // 0)) as $smoke_coverage
| exact_coverage($complete_groups; ($manifest.pilot_cases // []); ($manifest.pilot_repeats // 0)) as $pilot_coverage
| [$complete_groups[]
    | select((map(select(.variant == "candidate"))[0].metrics.acceptance_passed | not))
  ] as $candidate_failed_groups
| [$complete_groups[]
    | select((map(select(.variant == "baseline"))[0].metrics.acceptance_passed)
      and ((map(select(.variant == "candidate"))[0].metrics.acceptance_passed | not)))
  ] as $regression_groups
| [$complete_groups[]
    | select(((map(select(.variant == "baseline"))[0].metrics.acceptance_passed | not))
      and ((map(select(.variant == "candidate"))[0].metrics.acceptance_passed | not)))
  ] as $shared_failed_groups
| {
    evidence_complete: (($complete_groups | length) > 0 and $baseline.metrics.seeded_defects_total > 0 and $candidate.metrics.seeded_defects_total > 0),
    must_pass_pairwise_regressions: ($regression_groups | length),
    candidate_must_pass_failed_runs: ($candidate_failed_groups | length),
    candidate_must_pass_failed_cases: ([$candidate_failed_groups[][0].case_id] | unique | length),
    shared_must_pass_failed_runs: ($shared_failed_groups | length),
    shared_must_pass_failed_cases: ([$shared_failed_groups[][0].case_id] | unique | length),
    seeded_defect_recall_not_lower: ($baseline.metrics.seeded_defect_recall != null and $candidate.metrics.seeded_defect_recall >= $baseline.metrics.seeded_defect_recall),
    false_positive_marker_hits_not_higher: ($candidate.metrics.false_positive_marker_hits_total <= $baseline.metrics.false_positive_marker_hits_total),
    question_mark_count_proxy_not_higher: ($candidate.metrics.question_mark_count_proxy_mean <= $baseline.metrics.question_mark_count_proxy_mean),
    scope_deviations_not_higher: ($candidate.metrics.scope_deviations_total <= $baseline.metrics.scope_deviations_total),
    overall_verifier_failures_not_higher: ($candidate.metrics.overall_verifier_failures <= $baseline.metrics.overall_verifier_failures),
    workspace_verifier_failures_not_higher: ($candidate.metrics.workspace_verifier_failures <= $baseline.metrics.workspace_verifier_failures),
    tool_calls_median_within_20_percent: at_most_twenty_percent_worse($baseline.metrics.tool_calls_median; $candidate.metrics.tool_calls_median),
    rework_median_within_20_percent: at_most_twenty_percent_worse($baseline.metrics.rework_count_median; $candidate.metrics.rework_count_median)
  } as $gates
| [$groups[]
    | select((map(.pair_id)[0]) as $id | any($complete_groups[]; .[0].pair_id == $id) | not)
    | {
        pair_id: .[0].pair_id,
        case_id: .[0].case_id,
        trial_index: .[0].trial_index,
        baseline_status: ((map(select(.variant == "baseline"))[0].status) // "missing"),
        candidate_status: ((map(select(.variant == "candidate"))[0].status) // "missing"),
        baseline_error_code: ((map(select(.variant == "baseline"))[0].error.code) // null),
        candidate_error_code: ((map(select(.variant == "candidate"))[0].error.code) // null),
        exclusion_reason: (
          if length != 2 then "missing_or_duplicate_variant"
          elif any(.[]; .status != "completed") then "adapter_unavailable"
          elif (map(.variant) | sort) != ["baseline", "candidate"]
            or (map(.case_id) | unique | length) != 1
            or (map(.trial_index) | unique | length) != 1 then "pair_identity_mismatch"
          elif (full_provenance_pair | not) then "provenance_mismatch"
          else "pair_identity_mismatch" end
        )
      }
  ] as $incomplete
| {
    schema_version: "1.0",
    candidate_manifest_sha256: (if $candidate_manifest_sha256 == "" then null else $candidate_manifest_sha256 end),
    complete_pairs: ($complete_groups | length),
    excluded_incomplete_pairs: ($incomplete | length),
    variants: {baseline: $baseline, candidate: $candidate},
    paired_results: [
      $complete_groups[]
      | (map(select(.variant == "baseline"))[0]) as $b
      | (map(select(.variant == "candidate"))[0]) as $c
      | {
          pair_id: $b.pair_id,
          case_id: $b.case_id,
          trial_index: $b.trial_index,
          baseline_passed: $b.metrics.acceptance_passed,
          candidate_passed: $c.metrics.acceptance_passed,
          seeded_defect_recall_delta: (
            if $b.metrics.seeded_defects_total == 0 then null
            else ($c.metrics.seeded_defects_detected / $c.metrics.seeded_defects_total)
              - ($b.metrics.seeded_defects_detected / $b.metrics.seeded_defects_total) end),
          false_positive_marker_hit_delta: ($c.metrics.false_positive_marker_hits - $b.metrics.false_positive_marker_hits),
          scope_deviation_delta: ($c.metrics.scope_deviations - $b.metrics.scope_deviations)
        }
    ],
    promotion_gate_results: $gates,
    smoke_passed: (
      $smoke_coverage
      and ($incomplete | length) == 0
      and $gates.evidence_complete
      and $gates.candidate_must_pass_failed_runs == 0
      and $gates.seeded_defect_recall_not_lower
      and $gates.false_positive_marker_hits_not_higher
      and $gates.scope_deviations_not_higher),
    pilot_coverage_complete: $pilot_coverage,
    automatic_behavioral_gates_passed: (
      $pilot_coverage
      and ($incomplete | length) == 0
      and $gates.evidence_complete
      and $gates.must_pass_pairwise_regressions == 0
      and $gates.candidate_must_pass_failed_runs == 0
      and $gates.seeded_defect_recall_not_lower
      and $gates.false_positive_marker_hits_not_higher
      and $gates.question_mark_count_proxy_not_higher
      and $gates.scope_deviations_not_higher
      and $gates.overall_verifier_failures_not_higher
      and $gates.workspace_verifier_failures_not_higher
      and $gates.tool_calls_median_within_20_percent
      and $gates.rework_median_within_20_percent),
    semantic_false_positive_review_required: true,
    behavioral_promotion_eligible: false,
    incomplete_pairs: $incomplete
  }
