if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "acceptance spec obligations define structured PASS FAIL compliance fields"
spec_review_file="$FRAMEWORK_DIR/skills/assistant-workflow/references/prompts/spec-review.md"
missing_spec_review_terms=()
if [[ ! -f "$spec_review_file" ]]; then
    missing_spec_review_terms+=("references/prompts/spec-review.md exists")
else
    for term in \
        "Result: PASS | FAIL" \
        "Missing acceptance criteria" \
        "Extra scope" \
        "Changed files mismatch" \
        "Verification evidence mismatch" \
        "Required fixes" \
        "Confirm every acceptance criterion is implemented or explicitly deferred with approval." \
        "Confirm changed files match the approved file list, or each mismatch has an approved deviation." \
        "Confirm verification evidence matches the required command, expected success signal, and criteria checked." \
        "Flag extra scope separately from quality issues." \
        'return `FAIL` with required fixes' \
        "# Acceptance Spec Obligations" \
        'final fresh acceptance review (`assistant-review`, `review_subject=acceptance`)' \
        "There is no separate Spec reviewer." \
        "Historical Stage 1 \`### Spec Review #N\` records stay readable"; do
        if ! grep -Fq -- "$term" "$spec_review_file"; then
            missing_spec_review_terms+=("$term")
        fi
    done
fi
if [[ "${#missing_spec_review_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "spec-review.md missing required structured compliance terms: ${missing_spec_review_terms[*]}"
fi

test_start "task journal template uses structured Spec Review output"
missing_template_spec_terms=()
for term in \
    "### Spec Review #1" \
    "- Result: PASS | FAIL" \
    "- Scope reviewed: [plan step(s), task packet(s), or slice(s)]" \
    "- Missing acceptance criteria: [none, or list]" \
    "- Extra scope: [none, or list with file paths and disposition]" \
    "- Changed files mismatch: [none, or expected vs actual]" \
    "- Verification evidence mismatch: [none, or expected vs actual]" \
    "- Required fixes: [none, or ordered fix list]" \
    'Append entries from the one final acceptance review: its spec obligations (structured PASS/FAIL from `references/prompts/spec-review.md`)' \
    "historical Stage 1 Spec Review entries stay readable" \
    "- Acceptance review: [final_review_snapshot_id]" \
    "Quality Review (assistant-review quality loop)"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md"; then
        missing_template_spec_terms+=("$term")
    fi
done
if [[ "${#missing_template_spec_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "task-journal-template.md missing structured Spec Review example terms: ${missing_template_spec_terms[*]}"
fi

test_start "review producer docs use canonical HAS_REMAINING_ITEMS spelling"
review_producer_docs=(
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/prompts/pr-review.md"
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md"
)
missing_canonical_result_terms=()
if grep -n "HAS REMAINING ITEMS" "${review_producer_docs[@]}" >/tmp/p0p4-stale-final-result-spelling.out; then
    missing_canonical_result_terms+=("stale spaced spelling found; see /tmp/p0p4-stale-final-result-spelling.out")
fi
for file in "${review_producer_docs[@]}"; do
    if ! grep -Fq "HAS_REMAINING_ITEMS" "$file"; then
        missing_canonical_result_terms+=("$file: HAS_REMAINING_ITEMS")
    fi
done
if [[ "${#missing_canonical_result_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "review producer docs/templates missing canonical final result spelling: ${missing_canonical_result_terms[*]}"
fi

test_start "workflow review folds spec obligations into the final fresh acceptance review"
missing_spec_phase_terms=()
review_qa_router="$FRAMEWORK_DIR/skills/assistant-workflow/references/review-qa-router.md"
for term in \
    "## Stage 1 - Retired Spec Review" \
    "Stage 1 is no longer a separate reviewer." \
    'is the single owner of request, plan and delivery reconciliation' \
    'Assign the spec obligations of `references/prompts/spec-review.md` to a pass of that batch' \
    "Quality findings alone cannot satisfy spec obligations" \
    "### Spec Review #N" \
    "On a spec FAIL, in review-fix mode" \
    "run a fresh complete acceptance batch on the changed snapshot" \
    "## Stage 2 - Code Quality Review" \
    'with `review_subject=acceptance` and the triage `controller_intensity`' \
    'loading assistant-review SKILL.md'; do
    if ! p0p4_contains_text_ci "$review_qa_router" "$term"; then
        missing_spec_phase_terms+=("$term")
    fi
done
if ! grep -Fq -- "Load \`references/review-qa-router.md\`" "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"; then
    missing_spec_phase_terms+=("phases.md missing review-qa-router loader")
fi
for term in \
    'one final fresh acceptance review through `assistant-review` (`review_subject=acceptance`) that also owns the spec obligations' \
    'with `review_subject=plan`'; do
    if ! p0p4_contains_text_ci "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md" "$term"; then
        missing_spec_phase_terms+=("phases.md: $term")
    fi
done
if ! p0p4_contains_text_ci "$FRAMEWORK_DIR/skills/assistant-workflow/references/subagent-dispatch.md" 'Plan review dispatches with `review_subject=plan`. The final independent review uses `review_subject=acceptance`'; then
    missing_spec_phase_terms+=("subagent-dispatch.md review_subject plan/acceptance")
fi
# Negative control: no active instruction still dispatches a separate Stage 1 reviewer.
for file in \
    "$review_qa_router" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases/review.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"; do
    if grep -Fq -e '>> Stage 1: Spec Review' -e 'Dispatch a newly created fresh-context Spec reviewer' -e 'before quality review starts' "$file"; then
        missing_spec_phase_terms+=("${file#$FRAMEWORK_DIR/}: separate Stage 1 Spec reviewer remains")
    fi
done
if [[ "${#missing_spec_phase_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "review-qa-router.md missing separate spec/quality review terms: ${missing_spec_phase_terms[*]}"
fi

test_start "workflow phase gates require spec obligations PASS within the acceptance review"
missing_spec_gate_terms=()
for term in \
    "- id: R1" \
    "The final fresh acceptance review (assistant-review with review_subject=acceptance) is the single owner of request, plan and delivery reconciliation" \
    "covered the spec obligations of references/prompts/spec-review.md, reconciling the original request, requirement IDs, and approved plan against delivered results" \
    "the latest spec_review_result has Result: PASS bound to the same final batch" \
    "missing acceptance criteria, extra scope, changed files mismatch, verification evidence mismatch, and required fixes" \
    "a PASS after a FAIL fix comes from a fresh complete batch on the changed snapshot" \
    "No separate Stage 1 Spec reviewer is dispatched; historical Stage 1 records stay readable" \
    "Unavailable isolation leaves Review incomplete." \
    "- id: R1A" \
    "Quality findings do not substitute for spec obligations" \
    "Workflow passed its triage controller_intensity to assistant-review" \
    "a validated fresh independent plan review (assistant-review with review_subject=plan)" \
    "every structured light review receives controller_intensity=light and a one-pass topology carries topology.light_review=true" \
    "ordinary light review needs no batch plan, ledgers, structured fresh_dispatch, or review-tools validation" \
    "- id: R2" \
    "Quality Review completed by loading and following assistant-review SKILL.md"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"; then
        missing_spec_gate_terms+=("$term")
    fi
done
if [[ "${#missing_spec_gate_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "phase-gates.yaml missing folded spec-obligation and acceptance review gates: ${missing_spec_gate_terms[*]}"
fi

test_start "workflow output contract separates spec_review_result from quality review_result"
missing_review_output_terms=()
for term in \
    "- name: review_result" \
    "Final fresh acceptance review result (assistant-review, review_subject=acceptance, with the triage controller_intensity). Its spec obligations are recorded in spec_review_result." \
    "assistant-review/contracts/output.yaml#final_summary" \
    "canonical_result_ref" \
    "validation_status" \
    "- name: spec_review_result" \
    "Spec-obligation result of the final fresh acceptance review (assistant-review," \
    "no separate Stage 1 reviewer is dispatched." \
    "Historical Stage 1 records remain readable under their original labels." \
    "- name: reviewer_identity" \
    "native_invocation_id" \
    "enum_values: [PASS]" \
    "missing_acceptance_criteria" \
    "extra_scope" \
    "changed_files_mismatch" \
    "verification_evidence_mismatch" \
    "required_fixes" \
    "spec_review_result.status == PASS"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"; then
        missing_review_output_terms+=("$term")
    fi
done
for artifact in review_result spec_review_result; do
    if [[ "$artifact" == "review_result" ]]; then
        expected_condition="controller_intensity in [standard, strict] or risk_tier in [high, critical]"
    else
        expected_condition="size in [medium, large, mega] or risk_tier in [high, critical]"
    fi
    if ! awk -v artifact="$artifact" -v expected_condition="$expected_condition" '
        $0 == "  - name: " artifact { in_artifact = 1; next }
        in_artifact && /^  - name: / { exit }
        in_artifact && /required: conditional/ { found_required = 1 }
        in_artifact && index($0, expected_condition) { found_condition = 1 }
        END { exit (found_required && found_condition) ? 0 : 1 }
    ' "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"; then
        missing_review_output_terms+=("$artifact conditional controller/size, high-risk, or strict requirement")
    fi
done
if [[ "${#missing_review_output_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "output.yaml missing distinct spec/quality review result contract terms: ${missing_review_output_terms[*]}"
fi

test_start "small elevated strict or required-QA work has coherent full acceptance review applicability"
small_elevated_contract_terms=()
for term in \
    'required_artifacts: [completion_policy, triage_result, phase_checkpoints, changed_files, verification_decision, evidence_assessment, validation_results, spec_review_result, review_result, final_handoff]' \
    'small strict/required-QA work selects small_elevated' \
    'Small strict/required-QA work and medium+ tasks require the full acceptance'; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml" && \
       ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/review-qa-router.md"; then
        small_elevated_contract_terms+=("$term")
    fi
done
if ! ruby -ryaml -e '
  artifacts = YAML.load_file(ARGV.fetch(0)).fetch("completion_tiers").fetch("small_elevated").fetch("conditional_artifacts")
  exit(%w[test_results subagent_evidence tdd_cycle_log_ref].all? { |name| artifacts.include?(name) } ? 0 : 1)
' "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"; then
    small_elevated_contract_terms+=("small_elevated conditional artifacts retain test results, worker evidence, and active TDD cycle reference")
fi
if ! tr '\n' ' ' < "$FRAMEWORK_DIR/skills/assistant-workflow/references/review-qa-router.md" | \
    grep -Fq 'Small strict/required-QA work and medium+ tasks require the full acceptance batch with its spec obligations'; then
    small_elevated_contract_terms+=("strict/required-QA small work requires the full acceptance batch with spec obligations")
fi
for artifact in triage_result spec_review_result; do
    if ! awk -v artifact="$artifact" '
        $0 == "  - name: " artifact { in_artifact = 1; next }
        in_artifact && /^  - name: / { exit }
        in_artifact && $0 == "    condition: \"execution_intent != prepare_only and (size in [medium, large, mega] or risk_tier in [high, critical] or controller_intensity == strict or qa_evaluation_mode == required)\"" { found = 1 }
        END { exit found ? 0 : 1 }
    ' "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"; then
        small_elevated_contract_terms+=("$artifact requires strict/required-QA small work")
    fi
done
for term in \
    'Quality Review completed by loading and following assistant-review SKILL.md' \
    'controller_intensity in [standard, strict]'; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"; then
        small_elevated_contract_terms+=("$term")
    fi
done
if [[ "${#small_elevated_contract_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "small elevated strict/required-QA contract is incomplete: ${small_elevated_contract_terms[*]}"
fi

test_start "compact light fresh_review_result reuses Review closure vocabulary and rejects non-closed PASS"
if compact_review_error="$(ruby -ryaml -rjson -e '
  wf = YAML.load_file(ARGV.fetch(0)).fetch("artifacts").find { |a| a["name"] == "fresh_review_result" } or abort "fresh_review_result missing"
  fields = wf.fetch("object_fields").to_h { |f| [f.fetch("name"), f] }
  review = YAML.load_file(ARGV.fetch(1))
  find_field = lambda do |node|
    case node
    when Hash then return node if node["name"] == "closure_results" && node["object_fields"]
      node.each_value { |v| r = find_field.(v); return r if r }
    when Array then node.each { |v| r = find_field.(v); return r if r }
    end
    nil
  end
  review_rows = find_field.(review) or abort "review closure_results missing"
  review_shape = review_rows.fetch("object_fields").map { |f| [f["name"], f["type"], f["enum_values"]] }
  # Contract shape: names, enums, conditions and on_missing.
  ident = fields["reviewer_identity"] or abort "reviewer_identity missing"
  abort "reviewer_identity not binary for Workflow 16" unless ident["required"] == "conditional" && ident["condition"] == "fresh_review_result is recorded by a Workflow 16.0 producer" && ident["on_missing"] == "fail"
  abort "uncheckable author clause retained" if ident.fetch("validation").include?("authors") || fields.fetch("prior_reviewer_actor_ids").fetch("validation").include?("authors")
  idf = ident.fetch("object_fields").to_h { |f| [f["name"], f] }
  abort "reviewer_identity fields drifted" unless idf.keys == %w[actor_id native_invocation_id runtime fork_turns] && idf["fork_turns"]["enum_values"] == ["none"] && idf["fork_turns"]["condition"] == "runtime == codex" && idf["runtime"]["on_missing"] == "fail"
  abort "runtime not compared case-sensitively" unless idf["runtime"].fetch("description").include?("lowercase") && idf["runtime"].fetch("description").include?("compared case-sensitively")
  findings = fields.fetch("findings")
  finding_keys = findings.fetch("object_fields", []).map { |f| f["name"] }
  abort "compact findings do not carry stable ids: #{findings["type"]} #{finding_keys}" unless findings["type"] == "object[]" && finding_keys == %w[aggregate_finding_id file_line description] && findings.fetch("object_fields").all? { |f| f["type"] == "string" && f["required"] == true }
  abort "findings do not hand off {aggregate_finding_id, description} rows" unless findings.fetch("validation").include?("{aggregate_finding_id, description} rows using these ids")
  abort "findings emptiness rule drifted" unless findings.fetch("validation").start_with?("Empty for a first-review PASS; on a re-review each listed finding has a closure_results row with status verified_closed.") && !findings.fetch("validation").include?("explicitly resolved findings")
  abort "finding rows not gated on Workflow 16.0 with readable v15 strings" unless findings.fetch("description").include?("recorded by a Workflow 16.0 producer") && findings.fetch("description").include?("historical Workflow 15 string[] findings list stays readable as-is and is never certified current")
  prior = fields["prior_reviewer_actor_ids"]
  abort "prior_reviewer_actor_ids shape drifted" unless prior && prior["type"] == "string[]" && prior["on_missing"] == "fail" && prior["condition"] == "The compact result is a fresh re-review after a fix"
  closure = fields["closure_results"] or abort "closure_results missing"
  abort "closure_results condition/on_missing drifted" unless closure["type"] == "object[]" && closure["condition"] == prior["condition"] && closure["on_missing"] == "fail"
  wf_shape = closure.fetch("object_fields").map { |f| [f["name"], f["type"], f["enum_values"]] }
  abort "closure_results row shape differs from assistant-review closure_results: #{wf_shape} vs #{review_shape}" unless wf_shape == review_shape
  abort "PASS rule not stated" unless closure.fetch("validation").include?("result PASS requires every row status verified_closed")
  abort "closure ids not bound to the record\u0027s own finding ids" unless closure.fetch("validation").include?("Exactly one row per findings[].aggregate_finding_id of this record, so the closure ids equal the record\u0027s own finding ids")
  abort "undeclared handoff-only closure binding retained" if closure.fetch("validation").include?("handed-off") || closure.fetch("description").include?("handed to")
  %w[fixed_finding_closures fixed_finding_ids finding_id closure_status].each { |old| abort "round-7 name #{old} retained" if fields.key?(old) || closure.fetch("object_fields").any? { |f| f["name"] == old } }
  # Fixture oracle derived from the contract.
  status_enum = closure.fetch("object_fields").find { |f| f["name"] == "status" }.fetch("enum_values")
  result_enum = fields.fetch("result").fetch("enum_values")
  violations = lambda do |c|
    r = c.fetch("record"); errs = []
    errs << "unknown_field" unless (r.keys - fields.keys).empty?
    errs << "result" unless result_enum.include?(r["result"])
    errs << "finding_row_shape" unless r["findings"].is_a?(Array) && r["findings"].all? { |row| row.is_a?(Hash) && row.keys.sort == finding_keys.sort && row.values.all? { |v| v.is_a?(String) && !v.strip.empty? } }
    finding_ids = Array(r["findings"]).map { |row| row.is_a?(Hash) ? row["aggregate_finding_id"] : row }
    errs << "finding_ids_duplicate" unless finding_ids.uniq.length == finding_ids.length
    errs << "first_pass_findings" if !c.fetch("post_fix") && !Array(r["findings"]).empty?
    id = r["reviewer_identity"]
    if id.nil? then errs << "reviewer_identity_missing"
    else
      errs << "identity_field" unless (id.keys - idf.keys).empty? && %w[actor_id native_invocation_id runtime].all? { |k| id[k].is_a?(String) && !id[k].empty? }
      errs << "runtime_not_canonical" unless id["runtime"].is_a?(String) && id["runtime"] == id["runtime"].strip.downcase
      errs << "codex_fork_turns" if id["runtime"] == "codex" && id["fork_turns"] != "none"
    end
    if c.fetch("post_fix")
      handoff = c.fetch("handoff")
      errs << "handoff_row_shape" unless handoff.all? { |row| row.keys == %w[aggregate_finding_id description] }
      errs << "handoff_ids_unknown" unless (handoff.map { |row| row["aggregate_finding_id"] } - c.fetch("first_review_findings").map { |row| row["aggregate_finding_id"] }).empty?
      errs << "record_findings_unknown" unless (Array(r["findings"]) - c.fetch("first_review_findings")).empty?
      p = r["prior_reviewer_actor_ids"]; rows = r["closure_results"]
      errs << "prior_missing" unless p.is_a?(Array) && !p.empty?
      errs << "reviewer_reused" if id && p.is_a?(Array) && p.include?(id["actor_id"])
      if rows.is_a?(Array)
        errs << "closure_row_shape" unless rows.all? { |row| row.keys.sort == %w[aggregate_finding_id evidence status] && status_enum.include?(row["status"]) }
        errs << "closure_ids" unless rows.map { |row| row["aggregate_finding_id"] }.sort == finding_ids.sort
        errs << "pass_not_closed" if r["result"] == "PASS" && !rows.all? { |row| row["status"] == "verified_closed" }
      else errs << "closure_missing"
      end
    end
    errs
  end
  first_findings = [{"aggregate_finding_id" => "light-1", "file_line" => "src/a.rb:3", "description" => "nil guard missing"}]
  base = {"result" => "PASS", "reviewed_scope" => "src/a.rb", "findings" => first_findings, "evidence" => "fresh re-review",
          "reviewer_identity" => {"actor_id" => "r2", "native_invocation_id" => "inv-2", "runtime" => "codex", "fork_turns" => "none"},
          "prior_reviewer_actor_ids" => ["r1"],
          "closure_results" => [{"aggregate_finding_id" => "light-1", "status" => "verified_closed", "evidence" => "a.rb:3 fixed"}]}
  mk = ->(&blk) { c = JSON.parse(JSON.generate({"post_fix" => true, "first_review_findings" => first_findings, "handoff" => [{"aggregate_finding_id" => "light-1", "description" => "nil guard missing"}], "record" => base})); blk&.call(c["record"], c); c }
  positive = mk.()
  abort "positive compact post-fix record rejected: #{violations.(positive)}" unless violations.(positive).empty?
  first = {"post_fix" => false, "record" => base.reject { |k, _| %w[prior_reviewer_actor_ids closure_results].include?(k) }.merge("findings" => [])}
  abort "positive first compact record rejected: #{violations.(first)}" unless violations.(first).empty?
  negatives = {
    "regressed row with PASS" => [mk.() { |r| r["closure_results"][0]["status"] = "regressed" }, "pass_not_closed"],
    "incomplete row with PASS" => [mk.() { |r| r["closure_results"][0]["status"] = "incomplete" }, "pass_not_closed"],
    "re-reviewer listed as prior reviewer" => [mk.() { |r| r["prior_reviewer_actor_ids"] = ["r1", "r2"] }, "reviewer_reused"],
    "missing closure row" => [mk.() { |r| r["closure_results"] = [] }, "closure_ids"],
    "closure id differs from record finding id" => [mk.() { |r| r["closure_results"][0]["aggregate_finding_id"] = "light-9" }, "closure_ids"],
    "re-review omits resolved finding rows" => [mk.() { |r| r["findings"] = [] }, "closure_ids"],
    "duplicate finding id" => [mk.() { |r| r["findings"] = [r["findings"][0], r["findings"][0].merge("file_line" => "src/a.rb:9")]; r["closure_results"] << r["closure_results"][0].dup }, "finding_ids_duplicate"],
    "re-review finding not from first review" => [mk.() { |r| r["findings"][0]["description"] = "other" }, "record_findings_unknown"],
    "handoff id not kept from first review" => [mk.() { |r, c| c["handoff"][0]["aggregate_finding_id"] = "F1"; r["closure_results"][0]["aggregate_finding_id"] = "F1" }, "handoff_ids_unknown"],
    "handoff row without description" => [mk.() { |_, c| c["handoff"][0].delete("description") }, "handoff_row_shape"],
    "string finding without stable id" => [mk.() { |r| r["findings"] = ["src/a.rb:3 nil guard missing (resolved)"] }, "finding_row_shape"],
    "finding row without id" => [mk.() { |r| r["findings"] = [{"file_line" => "src/a.rb:3", "description" => "nil guard missing"}] }, "finding_row_shape"],
    "padded leading runtime" => [mk.() { |r| r["reviewer_identity"] = {"actor_id" => "r2", "native_invocation_id" => "inv-2", "runtime" => " claude"} }, "runtime_not_canonical"],
    "padded trailing runtime" => [mk.() { |r| r["reviewer_identity"] = {"actor_id" => "r2", "native_invocation_id" => "inv-2", "runtime" => "claude "} }, "runtime_not_canonical"],
    "cased claude runtime" => [mk.() { |r| r["reviewer_identity"] = {"actor_id" => "r2", "native_invocation_id" => "inv-2", "runtime" => "Claude"} }, "runtime_not_canonical"],
    "cased codex runtime" => [mk.() { |r| r["reviewer_identity"]["runtime"] = "Codex" }, "runtime_not_canonical"],
    "round-7 closure name" => [mk.() { |r| r["fixed_finding_closures"] = [{"finding_id" => "light-1", "closure_status" => "closed"}]; r.delete("closure_results") }, "unknown_field"],
    "round-7 closed status" => [mk.() { |r| r["closure_results"][0]["status"] = "closed" }, "closure_row_shape"],
    "missing reviewer identity" => [mk.() { |r| r.delete("reviewer_identity") }, "reviewer_identity_missing"],
    "codex without fork_turns" => [mk.() { |r| r["reviewer_identity"].delete("fork_turns") }, "codex_fork_turns"]
  }
  negatives.each { |label, (c, want)| got = violations.(c); abort "negative #{label} not rejected as #{want}: #{got}" unless got.include?(want) }
  first_with_findings = JSON.parse(JSON.generate(first)).tap { |c| c["record"]["findings"] = first_findings }
  abort "first-review PASS with findings accepted" unless violations.(first_with_findings).include?("first_pass_findings")
  # U5 compact plan review reuses the compact rows and request_plan_reconciliation names.
  plan = YAML.load_file(ARGV.fetch(0)).fetch("artifacts").find { |a| a["name"] == "plan_review_result" } or abort "plan_review_result missing"
  pf = plan.fetch("object_fields").to_h { |f| [f.fetch("name"), f] }
  shape = ->(f) { f.fetch("object_fields").map { |x| [x["name"], x["type"], x["enum_values"]] } }
  abort "plan_review_result fields drifted: #{pf.keys}" unless pf.keys == %w[review_subject perspective result reviewed_scope findings request_plan_reconciliation evidence reviewer_identity prior_reviewer_actor_ids closure_results]
  abort "plan_review_result subject/perspective/result drifted" unless pf["review_subject"]["enum_values"] == ["plan"] && pf["perspective"]["enum_values"] == ["plan_coverage_and_feasibility"] && pf["result"]["enum_values"] == result_enum
  %w[findings reviewer_identity closure_results].each { |k| abort "plan_review_result #{k} shape differs from fresh_review_result" unless shape.(pf[k]) == shape.(fields[k]) }
  abort "plan closure condition drifted" unless pf["closure_results"]["condition"] == pf["prior_reviewer_actor_ids"]["condition"] && pf["closure_results"]["on_missing"] == "fail" && pf["closure_results"]["validation"].include?("one row per findings[].aggregate_finding_id of this record")
  input = YAML.load_file(ARGV.fetch(2)).fetch("fields").find { |f| f["name"] == "review_authorities" }.fetch("object_fields").find { |f| f["name"] == "request_plan_reconciliation" }
  plan_names = input.fetch("object_fields").map { |f| f["name"] } - ["unfinished_task_wide_work"]
  abort "plan coverage does not reuse request_plan_reconciliation names: #{shape.(pf["request_plan_reconciliation"]).map(&:first)}" unless pf["request_plan_reconciliation"].fetch("object_fields").map { |f| f["name"] } == plan_names
  abort "plan_review_result not compact-unless-admission" unless plan.fetch("condition").include?("no persisted/executable admission consumes that review") && plan.fetch("description").include?("structured plan batch and review-tools validation")
' "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml" "$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/input.yaml" 2>&1)"; then
    compact_prose_missing=()
    router_flat="$(tr -s '[:space:]' ' ' < "$FRAMEWORK_DIR/skills/assistant-workflow/references/review-qa-router.md")"
    for term in 'lowercase `runtime`' 'stable id (for example `light-1`) plus file/line and description; the lead keeps those ids' 'fixed findings as `{aggregate_finding_id, description}` rows' 'carries those resolved rows in `findings`' 'closure ids equal the record'"'"'s own finding ids' 'Plan review records `plan_review_result`' 'Stage 2 applies to standard/strict work' 'records `closure_results` (`verified_closed`, `regressed` or `incomplete`) per `aggregate_finding_id` plus `prior_reviewer_actor_ids`' 'PASS requires every row `verified_closed`'; do
        [[ "$router_flat" == *"$term"* ]] || compact_prose_missing+=("$term")
    done
    [[ "$router_flat" != *'fixed findings as `previously_fixed`'* ]] || compact_prose_missing+=("router retains previously_fixed compact handoff")
    for old in fixed_finding_ids fixed_finding_closures closure_status 'as `closed` or `open`' 'closed or open'; do
        while IFS= read -r retained_file; do
            compact_prose_missing+=("${retained_file#"$FRAMEWORK_DIR/"} retains $old")
        done < <(grep -rlF --exclude-dir=__pycache__ -- "$old" "$FRAMEWORK_DIR/skills/assistant-workflow" || true)
    done
    [[ -f "$FRAMEWORK_DIR/skills/assistant-workflow/references/subagent-roles.md" ]] || compact_prose_missing+=("subagent-roles.md missing from retired-name scan")
    if [[ "${#compact_prose_missing[@]}" -eq 0 ]]; then
        pass
    else
        fail "review-qa-router compact closure prose or workflow retired-name guard drifted: ${compact_prose_missing[*]}"
    fi
else
    fail "compact fresh_review_result contract or fixture oracle failed: $compact_review_error"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
