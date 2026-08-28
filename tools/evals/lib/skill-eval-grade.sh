first_response_path_for_case() {
    local skill_name="$1"
    local id="$2"

    if [[ -f "$RESPONSES_DIR/$skill_name/$id.txt" ]]; then
        printf '%s\n' "$RESPONSES_DIR/$skill_name/$id.txt"
    elif [[ -f "$RESPONSES_DIR/$skill_name/$id.md" ]]; then
        printf '%s\n' "$RESPONSES_DIR/$skill_name/$id.md"
    elif [[ "${#FIXTURE_FILES[@]}" -eq 1 && -f "$RESPONSES_DIR/$id.txt" ]]; then
        printf '%s\n' "$RESPONSES_DIR/$id.txt"
    elif [[ "${#FIXTURE_FILES[@]}" -eq 1 && -f "$RESPONSES_DIR/$id.md" ]]; then
        printf '%s\n' "$RESPONSES_DIR/$id.md"
    else
        printf '\n'
    fi
}

is_file_nonempty() {
    local path="$1"
    [[ -s "$path" ]] && grep -q '[^[:space:]]' "$path"
}

count_fail_signal_hits() {
    local fixture_file="$1"
    local id="$2"
    local response_path="$3"
    local signal
    local hits=0

    while IFS= read -r signal; do
        if [[ ${#signal} -ge 12 ]] && grep -Fqi -- "$signal" "$response_path"; then
            hits=$((hits + 1))
        fi
    done < <(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .fail_signals[]' "$fixture_file")

    printf '%s\n' "$hits"
}

count_missing_required_substrings() {
    local fixture_file="$1"
    local id="$2"
    local response_path="$3"
    local expected
    local misses=0

    while IFS= read -r expected; do
        if ! grep -Fqi -- "$expected" "$response_path"; then
            misses=$((misses + 1))
        fi
    done < <(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .machine_expectations.required_substrings[]' "$fixture_file")

    printf '%s\n' "$misses"
}


count_ordered_substring_failures() {
    local fixture_file="$1"
    local id="$2"
    local response_path="$3"
    local ordered_json
    local needle
    local response_text
    local remaining
    local failures=0

    response_text="$(tr '[:upper:]' '[:lower:]' <"$response_path")"
    while IFS= read -r ordered_json; do
        remaining="$response_text"
        while IFS= read -r needle; do
            needle="$(printf '%s' "$needle" | tr '[:upper:]' '[:lower:]')"
            if [[ "$remaining" == *"$needle"* ]]; then
                remaining="${remaining#*"$needle"}"
            else
                failures=$((failures + 1))
                break
            fi
        done < <(jq -r '.[]' <<<"$ordered_json")
    done < <(jq -c --arg id "$id" '.cases[] | select(.id == $id) | .machine_expectations.ordered_substrings[]?' "$fixture_file")

    printf '%s\n' "$failures"
}

count_forbidden_substring_hits() {
    local fixture_file="$1"
    local id="$2"
    local response_path="$3"
    local forbidden
    local hits=0

    while IFS= read -r forbidden; do
        if grep -Fqi -- "$forbidden" "$response_path"; then
            hits=$((hits + 1))
        fi
    done < <(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .machine_expectations.forbidden_substrings[]' "$fixture_file")

    printf '%s\n' "$hits"
}

count_seeded_defect_failures() {
    local fixture_file="$1"
    local id="$2"
    local response_path="$3"
    local defect_json
    local defect_id
    local must_detect
    local anchor
    local detected
    local evidence_found
    local severity_found
    local failures=0

    while IFS= read -r defect_json; do
        defect_id="$(jq -r '.id' <<<"$defect_json")"
        must_detect="$(jq -r '.must_detect // true' <<<"$defect_json")"
        [[ "$must_detect" == "true" ]] || continue

        detected=1
        while IFS= read -r anchor; do
            if ! grep -Fqi -- "$anchor" "$response_path"; then
                detected=0
                break
            fi
        done < <(jq -r '.detection_anchors[]' <<<"$defect_json")

        evidence_found=1
        while IFS= read -r anchor; do
            if ! grep -Fqi -- "$anchor" "$response_path"; then
                evidence_found=0
                break
            fi
        done < <(jq -r '.evidence_anchors[]' <<<"$defect_json")

        severity_found=1
        if [[ "$(jq '(.acceptable_severities // []) | length' <<<"$defect_json")" -gt 0 ]]; then
            severity_found=0
            while IFS= read -r anchor; do
                if grep -Fqi -- "$anchor" "$response_path"; then
                    severity_found=1
                    break
                fi
            done < <(jq -r '.acceptable_severities[]' <<<"$defect_json")
        fi

        finding_markers_found=1
        while IFS= read -r anchor; do
            if ! grep -Fqi -- "$anchor" "$response_path"; then
                finding_markers_found=0
                break
            fi
        done < <(jq -r '.finding_markers[]?' <<<"$defect_json")

        if [[ "$detected" -eq 0 || "$evidence_found" -eq 0 || "$severity_found" -eq 0 || "$finding_markers_found" -eq 0 ]]; then
            failures=$((failures + 1))
            printf 'Seeded defect not satisfied for %s: detected=%s evidence=%s severity=%s finding_markers=%s\n' "$defect_id" "$detected" "$evidence_found" "$severity_found" "$finding_markers_found" >&2
        fi
    done < <(jq -c --arg id "$id" '.cases[] | select(.id == $id) | .seeded_defects[]?' "$fixture_file")

    printf '%s\n' "$failures"
}

count_false_positive_marker_failures() {
    local fixture_file="$1"
    local id="$2"
    local response_path="$3"
    local budget
    local marker
    local hits=0

    budget="$(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .false_positive_budget // 0' "$fixture_file")"
    while IFS= read -r marker; do
        if grep -Fqi -- "$marker" "$response_path"; then
            hits=$((hits + 1))
        fi
    done < <(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .false_positive_markers[]?' "$fixture_file")

    if [[ "$hits" -gt "$budget" ]]; then
        printf '%s\n' "$((hits - budget))"
    else
        printf '0\n'
    fi
}

assistant_review_artifact_schema_valid() {
    local id="$1"
    local response_path="$2"
    local explicit_artifact_name="${3:-}"
    local response_root="${4:-}"

    ruby -rjson -ryaml - "$REPO_ROOT/skills/assistant-review/contracts/output.yaml" "$response_path" "$id" "$explicit_artifact_name" "$response_root" <<'RUBY'
contract = YAML.load_file(ARGV.fetch(0))
response = JSON.parse(File.read(ARGV.fetch(1)))
case_id = ARGV.fetch(2)
explicit_artifact_name = ARGV.fetch(3)
response_root = ARGV.fetch(4)
artifacts = contract.fetch("artifacts").to_h { |artifact| [artifact.fetch("name"), artifact] }

qa_cases = %w[
  qa-obligation-echo-fulfills-exact-binding
  qa-obligation-blocks-missing-or-mismatched-binding
  qa-obligation-blocked-when-required-evidence-is-unavailable
]
audit_cases = %w[
  audit-batch-waits-for-all-pass-results
  audit-spec-review-fail-continues-complete-batch
]
artifact_names = if !explicit_artifact_name.empty?
  [explicit_artifact_name]
elsif qa_cases.include?(case_id)
  ["qa_evaluation_result"]
else
  names = ["final_summary"]
  names << "audit_report" if audit_cases.include?(case_id)
  names << "review_delegation_path" if case_id == "trivial-audit-uses-two-isolated-passes"
  names
end

valid = nil
valid = lambda do |value, field|
  type = field.fetch("type")
  type_valid = case type
               when "string", "file", "jsonl_line" then value.is_a?(String)
               when "int" then value.is_a?(Integer)
               when "float" then value.is_a?(Numeric)
               when "boolean" then value == true || value == false
               when "enum" then value.is_a?(String) && field.fetch("enum_values").include?(value)
               when "string[]" then value.is_a?(Array) && value.all? { |item| item.is_a?(String) }
               when "object" then value.is_a?(Hash)
               when "object[]" then value.is_a?(Array) && value.all? { |item| item.is_a?(Hash) }
               else false
               end
  return false unless type_valid
  return false if field["min_items"] && value.length < field["min_items"]

  children = field["object_fields"]
  return true unless children
  validate_object = lambda do |object|
    allowed = children.map { |child| child.fetch("name") }
    return false unless (object.keys - allowed).empty?
    children.all? do |child|
      name = child.fetch("name")
      next false if child["required"] == true && !object.key?(name)
      !object.key?(name) || valid.call(object[name], child)
    end
  end
  type == "object" ? validate_object.call(value) : value.all? { |item| validate_object.call(item) }
end

valid_packet = artifact_names.all? do |name|
  value = response_root.empty? ? response[name] : response.dig(response_root, "artifact")
  value && valid.call(value, artifacts.fetch(name))
end
exit valid_packet ? 0 : 1
RUBY
}

assistant_review_lifecycle_semantics_valid() {
    local id="$1"
    local response_path="$2"
    local explicit_artifact_name="${3:-}"
    local response_root="${4:-}"
    local repository_root="${REPO_ROOT:-${FRAMEWORK_DIR:?FRAMEWORK_DIR or REPO_ROOT is required}}"

    ruby -rjson -ryaml -rbigdecimal - "$repository_root/skills/assistant-review/contracts/output.yaml" "$repository_root/skills/assistant-review/evals/cases.json" "$response_path" "$id" "$explicit_artifact_name" "$response_root" <<'RUBY'
contract = YAML.load_file(ARGV.fetch(0))
fixture = JSON.parse(File.read(ARGV.fetch(1)))
response = JSON.parse(File.read(ARGV.fetch(2)), decimal_class: BigDecimal)
case_id = ARGV.fetch(3)
explicit_artifact_name = ARGV.fetch(4)
response_root = ARGV.fetch(5)
if !explicit_artifact_name.empty?
  response = { explicit_artifact_name => response.dig(response_root, "artifact") }
end

qa_cases = %w[
  qa-obligation-echo-fulfills-exact-binding
  qa-obligation-blocks-missing-or-mismatched-binding
  qa-obligation-blocked-when-required-evidence-is-unavailable
  not-applicable-binding-unit
]
audit_cases = %w[
  audit-batch-waits-for-all-pass-results
  audit-spec-review-fail-continues-complete-batch
]
final_cases = %w[
  audit-batch-waits-for-all-pass-results
  incomplete-review-batch-never-cleans
  post-fix-review-uses-fresh-snapshot-batch
  audit-spec-review-fail-continues-complete-batch
  in-flight-mutation-invalidates-review-batch
  trivial-audit-uses-two-isolated-passes
]

nonblank = ->(value) { value.is_a?(String) && !value.strip.empty? }
nonblank_strings = ->(value) { value.is_a?(Array) && !value.empty? && value.all? { |item| nonblank.call(item) } }
integer_in = ->(value, range) { value.is_a?(Integer) && range.cover?(value) }
decimal = ->(value) { value.is_a?(Numeric) ? BigDecimal(value.to_s) : nil }
identity_valid = lambda do |identity|
  identity.is_a?(Hash) && %w[basis value captured_at scope_manifest_digest].all? { |key| nonblank.call(identity[key]) } &&
    %w[git_revision diff_digest content_digest task_or_pr_revision].include?(identity["basis"])
end
expected_obligation_value = lambda do |field|
  path = ["qa_evaluation_result", "approved_feature_preparation_qa_acceptance_obligation_result", field]
  fixture.fetch("cases").find { |test_case| test_case["id"] == case_id }
    &.dig("machine_expectations", "structured_json_assertions")
    &.find { |assertion| assertion["operator"] == "equals" && assertion["path"] == path }
    &.fetch("expected", nil)
end
valid = true

if explicit_artifact_name == "final_summary" || (explicit_artifact_name.empty? && final_cases.include?(case_id))
  summary = response["final_summary"]
  valid &&= summary.is_a?(Hash)
  if valid
    rounds = summary["rounds"]
    batches = summary["batch_summaries"]
    ledger = summary["coverage_ledger"]
    valid &&= integer_in.call(rounds, 1..10) && batches.is_a?(Array) && batches.length == rounds
    valid &&= batches.each_with_index.all? do |batch, index|
      batch.is_a?(Hash) && batch["started_batch_ordinal"] == index + 1 &&
        nonblank.call(batch["batch_id"]) && nonblank.call(batch["review_snapshot_id"]) &&
        identity_valid.call(batch["snapshot_identity"]) &&
        integer_in.call(batch["expected_response_count"], 2..6) &&
        batch["terminal_response_count"].is_a?(Integer) && batch["terminal_response_count"].between?(0, batch["expected_response_count"]) &&
        case batch["batch_status"]
        when "complete"
          batch["terminal_response_count"] == batch["expected_response_count"] && batch["aggregate_rubric_recomputed"] == true
        when "incomplete"
          batch["terminal_response_count"] < batch["expected_response_count"] && batch["aggregate_rubric_recomputed"] == false
        when "invalidated"
          batch["aggregate_rubric_recomputed"] == false
        else
          false
        end
    end
    valid &&= batches.map { |batch| batch["batch_id"] }.uniq.length == batches.length
    valid &&= batches.map { |batch| batch["review_snapshot_id"] }.uniq.length == batches.length
    current_batch = batches.last
    identity = summary["final_snapshot_identity"]
    valid &&= nonblank.call(summary["final_review_snapshot_id"]) && identity_valid.call(identity)
    valid &&= summary["final_review_snapshot_id"] == current_batch["review_snapshot_id"]
    valid &&= identity == current_batch["snapshot_identity"]
    valid &&= nonblank_strings.call(summary["reviewed_scope"])
    valid &&= ledger.is_a?(Array) && !ledger.empty?
    valid &&= ledger.all? do |entry|
      entry.is_a?(Hash) && %w[batch_id review_snapshot_id review_pass_id perspective coverage_obligation scope_item_id applicable_concern evidence].all? { |key| nonblank.call(entry[key]) } &&
        nonblank_strings.call(entry["assigned_scope"])
    end
    current_ledger = ledger.select { |entry| entry["review_snapshot_id"] == summary["final_review_snapshot_id"] }
    valid &&= !current_ledger.empty? && current_ledger.all? { |entry| entry["batch_id"] == current_batch["batch_id"] }
    coverage_tuples = current_ledger.map do |entry|
      [entry["review_pass_id"], entry["scope_item_id"], entry["applicable_concern"], entry["perspective"], entry["coverage_obligation"]]
    end
    valid &&= coverage_tuples.uniq.length == coverage_tuples.length
    valid &&= current_ledger.map { |entry| entry["review_pass_id"] }.uniq.length == current_batch["expected_response_count"]
    complete_current_coverage = current_ledger.all? { |entry| entry["terminal_state"] == "completed" && entry["coverage_status"] == "complete" }
    current_gap_entries = current_ledger.reject { |entry| entry["terminal_state"] == "completed" && entry["coverage_status"] == "complete" }
    current_gap_ids = current_gap_entries.map { |entry| entry["coverage_gap_id"] }
    valid &&= current_ledger.all? do |entry|
      complete = entry["terminal_state"] == "completed" && entry["coverage_status"] == "complete"
      complete ? !entry.key?("coverage_gap_id") : (%w[incomplete invalidated].include?(entry["coverage_status"]) && nonblank.call(entry["coverage_gap_id"]))
    end
    valid &&= current_gap_ids.all? { |gap_id| nonblank.call(gap_id) } && current_gap_ids.uniq.length == current_gap_ids.length
    if summary["coverage_complete"] == true
      valid &&= current_batch["batch_status"] == "complete" && complete_current_coverage
    else
      valid &&= %w[incomplete invalidated].include?(current_batch["batch_status"])
      valid &&= summary["coverage_gaps"].is_a?(Array) && summary["coverage_gaps"].any? { |gap| nonblank.call(gap) }
    end
    findings = summary["aggregated_findings"]
    fixed = summary["fixed_items"]
    remaining = summary["remaining_items"]
    material_findings = findings.is_a?(Array) ? findings.select { |finding| finding.is_a?(Hash) && %w[must-fix should-fix].include?(finding["severity"]) } : []
    material_remaining = remaining.is_a?(Array) ? remaining.select { |item| item.is_a?(Hash) && %w[must-fix should-fix].include?(item["severity"]) } : []
    case summary["result"]
    when "CLEAN"
      valid &&= summary["coverage_complete"] == true && current_batch["batch_status"] == "complete"
      valid &&= findings.is_a?(Array) && material_findings.empty? && fixed.is_a?(Array) && fixed.empty?
      valid &&= material_remaining.empty? && (!summary.key?("coverage_gaps") || summary["coverage_gaps"] == [])
    when "ISSUES_FIXED"
      valid &&= summary["coverage_complete"] == true && current_batch["batch_status"] == "complete"
      valid &&= findings.is_a?(Array) && material_findings.empty? && fixed.is_a?(Array) && !fixed.empty?
      valid &&= material_remaining.empty? && (!summary.key?("coverage_gaps") || summary["coverage_gaps"] == [])
    when "HAS_REMAINING_ITEMS"
      valid &&= summary["coverage_complete"] == false || !material_findings.empty? || !material_remaining.empty?
      valid &&= !summary.key?("evidence_bounded_claim")
    else
      valid = false
    end
    aggregation = summary["aggregation_ledger"]
    if findings.is_a?(Array) && aggregation.is_a?(Array)
      aggregate_ids = findings.map { |finding| finding["aggregate_finding_id"] }
      retained = aggregation.select { |entry| %w[retained merged].include?(entry["disposition"]) }
      retained_ids = retained.map { |entry| entry["aggregate_finding_id"] }
      valid &&= aggregate_ids.all? { |aggregate_id| nonblank.call(aggregate_id) } && aggregate_ids.uniq.length == aggregate_ids.length
      valid &&= retained_ids.all? { |aggregate_id| nonblank.call(aggregate_id) } && retained_ids.uniq.sort == aggregate_ids.sort
      valid &&= findings.all? do |finding|
        source_ids = finding["source_finding_ids"]
        ledger_source_ids = retained.select { |entry| entry["aggregate_finding_id"] == finding["aggregate_finding_id"] }.flat_map { |entry| entry["source_finding_ids"] || [] }
        source_ids.is_a?(Array) && !source_ids.empty? && source_ids.uniq.length == source_ids.length && ledger_source_ids.sort == source_ids.sort
      end
      coverage_gap_dispositions = aggregation.select { |entry| entry["disposition"] == "coverage_gap" }
      aggregated_gap_ids = coverage_gap_dispositions.flat_map { |entry| entry["source_coverage_gap_ids"] || [] }
      valid &&= coverage_gap_dispositions.all? do |entry|
        ids = entry["source_coverage_gap_ids"]
        ids.is_a?(Array) && !ids.empty? && ids.all? { |gap_id| nonblank.call(gap_id) } && ids.uniq.length == ids.length
      end
      valid &&= aggregated_gap_ids.uniq.length == aggregated_gap_ids.length && aggregated_gap_ids.sort == current_gap_ids.sort
    else
      valid = false
    end
    if rounds > 1
      reasons = summary["additional_round_reasons"]
      valid &&= reasons.is_a?(Array) && reasons.length == rounds - 1
      valid &&= reasons.each_with_index.all? do |reason, index|
        reason.is_a?(Hash) && reason["round"] == index + 2 &&
          %w[changed_files unresolved_finding validation_failure regression_or_drift changed_hypothesis].include?(reason["reason"]) &&
          (index > 0 || reason["reason"] == "changed_files") &&
          nonblank.call(reason["evidence_ref"]) && nonblank.call(reason["detail"])
      end
    else
      valid &&= !summary.key?("additional_round_reasons") || summary["additional_round_reasons"] == []
    end
    if explicit_artifact_name.empty? && audit_cases.include?(case_id)
      audit = response["audit_report"]
      valid &&= audit.is_a?(Hash) && audit["coverage_complete"] == summary["coverage_complete"] && audit["batch_summaries"] == batches && audit["coverage_ledger_ref"] == "final_summary.coverage_ledger"
      valid &&= audit && audit["findings"].is_a?(Array) && audit["findings"].all? { |finding| nonblank.call(finding["evidence"]) }
      if audit && audit["findings"].is_a?(Array) && findings.is_a?(Array)
        audit_projection = %w[severity file line description aggregate_finding_id finding_id source_finding_ids source_pass_ids source_provenance confidence_pct locus invariant failure_mechanism evidence smallest_useful_fix]
        project = ->(finding) { audit_projection.each_with_object({}) { |key, result| result[key] = finding[key] if finding.key?(key) } }
        valid &&= audit["findings"].map { |finding| project.call(finding) } == findings.map { |finding| project.call(finding) }
      end
    end
  end
elsif explicit_artifact_name == "qa_evaluation_result" || (explicit_artifact_name.empty? && qa_cases.include?(case_id))
  qa = response["qa_evaluation_result"]
  valid &&= qa.is_a?(Hash)
  if valid
    valid &&= integer_in.call(qa["rounds"], 1..10)
    verdict_result = {
      "accepted" => %w[CLEAN ISSUES_FIXED],
      "accepted_with_concerns" => %w[CLEAN ISSUES_FIXED],
      "rejected" => ["HAS_REMAINING_ITEMS"],
      "blocked" => ["BLOCKED"]
    }
    valid &&= verdict_result.fetch(qa["final_verdict"], []).include?(qa["result"])
    obligation = qa["approved_feature_preparation_qa_acceptance_obligation_result"]
    expected_obligation_present = %w[requested_scope execution_prerequisite feature_preparation_scope source_feature_preparation_evidence_ref source_preparation_basis].any? { |field| !expected_obligation_value.call(field).nil? }
    if obligation || expected_obligation_present
      valid &&= obligation.is_a?(Hash)
      valid &&= obligation && %w[requested_scope_evidence execution_prerequisite_evidence requested_scope execution_prerequisite].all? { |key| nonblank.call(obligation[key]) }
      %w[requested_scope execution_prerequisite feature_preparation_scope source_feature_preparation_evidence_ref source_preparation_basis].each do |field|
        expected = expected_obligation_value.call(field)
        valid &&= obligation[field] == expected unless expected.nil?
      end
      if obligation && obligation["feature_preparation_scope"] == "existing_system"
        valid &&= nonblank.call(obligation["source_feature_preparation_evidence_ref"]) && !obligation.key?("source_preparation_basis")
      elsif obligation && obligation["feature_preparation_scope"] == "not_applicable"
        valid &&= obligation["source_preparation_basis"] == "not_applicable" && !obligation.key?("source_feature_preparation_evidence_ref")
      else
        valid = false
      end
      if %w[accepted accepted_with_concerns].include?(qa["final_verdict"])
        valid &&= obligation["requested_scope_status"] == "fulfilled" && obligation["execution_prerequisite_status"] == "met"
      end
    end
    if qa["final_verdict"] == "blocked"
      valid &&= nonblank_strings.call(qa["open_questions"])
    end
    scorecard = qa["qa_scorecard"]
    valid &&= scorecard.is_a?(Hash)
    if scorecard
      dimensions = %w[acceptance_coverage evidence_strength domain_quality final_readiness]
      units = dimensions.map do |name|
        value = decimal.call(scorecard[name])
        value && (value * 2).frac.zero? ? (value * 2).to_i : nil
      end
      valid &&= units.all? { |unit| unit && unit.between?(2, 10) }
      if valid
        weights = [30, 25, 20, 25]
        weighted_half_units = units.zip(weights).sum { |unit, weight| unit * weight }
        rounded_scaled = (weighted_half_units + 1) / 2
        expected = BigDecimal(rounded_scaled) / 100
        valid &&= decimal.call(scorecard["weighted_score"]) == expected
      end
    end
    acceptance_findings = qa["acceptance_findings"]
    remaining_acceptance = acceptance_findings.is_a?(Array) ? acceptance_findings.select { |finding| finding["disposition"] == "remaining" } : []
    selected_rubrics = qa["selected_domain_rubrics"]
    domain_scores = qa["domain_quality_scores"]
    allowed_rubrics = %w[ui_visual_design ux_product_acceptance documentation_quality developer_experience domain_specific_craft]
    if selected_rubrics.nil? || selected_rubrics == []
      valid &&= domain_scores.nil? || domain_scores == []
      valid &&= scorecard && decimal.call(scorecard["domain_quality"]) == BigDecimal("5")
      valid &&= scorecard && scorecard["rationale"].is_a?(Hash) && scorecard["rationale"]["domain_quality"].to_s.include?("not_applicable")
    else
      valid &&= nonblank_strings.call(selected_rubrics) && selected_rubrics.uniq.length == selected_rubrics.length && selected_rubrics.all? { |rubric| allowed_rubrics.include?(rubric) }
      valid &&= domain_scores.is_a?(Array) && !domain_scores.empty? && domain_scores.all? do |score|
        if score.is_a?(Hash)
          value = decimal.call(score["score"])
          base_valid = selected_rubrics.include?(score["rubric_ref"]) && nonblank.call(score["dimension"]) &&
            value && value >= 1 && value <= 5 && (value * 2).frac.zero? &&
            %w[accepted accepted_with_concerns refine rejected pivot not_applicable].include?(score["action"]) &&
            nonblank.call(score["evidence"])
          if score["action"] == "not_applicable"
            base_valid && value == BigDecimal("5") && score["evidence"].downcase.match?(/not_applicable|unscoped/)
          else
            base_valid
          end
        else
          false
        end
      end
      valid &&= domain_scores.map { |score| score["rubric_ref"] }.uniq.sort == selected_rubrics.sort if domain_scores.is_a?(Array)
    end
    progression = qa["score_progression"]
    valid &&= progression.is_a?(Array) && progression.length == qa["rounds"]
    valid &&= progression.each_with_index.all? do |entry, index|
      score = entry.is_a?(Hash) ? decimal.call(entry["weighted_score"]) : nil
      entry.is_a?(Hash) && entry["round"] == index + 1 && score && score.between?(BigDecimal("1"), BigDecimal("5")) &&
        entry["failed_acceptance_count"].is_a?(Integer) && entry["failed_acceptance_count"] >= 0 &&
        nonblank.call(entry["delta"]) &&
        %w[GENUINE SUSPICIOUS DRIFT REGRESSION STAGNATION NEUTRAL NOT_APPLICABLE].include?(entry["drift_status"])
    end
    if progression.is_a?(Array) && progression.length == qa["rounds"]
      valid &&= progression.each_with_index.all? do |entry, index|
        if index.zero?
          entry["delta"] == "initial" && %w[NEUTRAL NOT_APPLICABLE].include?(entry["drift_status"])
        else
          current_score = decimal.call(entry["weighted_score"])
          previous_score = decimal.call(progression[index - 1]["weighted_score"])
          next false unless current_score && previous_score

          score_delta = current_score - previous_score
          expected_delta = format("%+.2f", score_delta)
          expected_status = if score_delta < 0
            "REGRESSION"
          elsif score_delta > 0 && entry["failed_acceptance_count"] < progression[index - 1]["failed_acceptance_count"]
            score_delta > 1 ? "SUSPICIOUS" : "GENUINE"
          elsif score_delta > 0
            "DRIFT"
          elsif index >= 2 && previous_score == decimal.call(progression[index - 2]["weighted_score"]) &&
              entry["failed_acceptance_count"] > 0 &&
              entry["failed_acceptance_count"] == progression[index - 1]["failed_acceptance_count"] &&
              progression[index - 1]["failed_acceptance_count"] == progression[index - 2]["failed_acceptance_count"]
            "STAGNATION"
          else
            "NEUTRAL"
          end
          entry["delta"] == expected_delta && entry["drift_status"] == expected_status
        end
      end
    end
    valid &&= progression && scorecard && decimal.call(progression.last["weighted_score"]) == decimal.call(scorecard["weighted_score"])
    if progression.is_a?(Array) && !progression.empty?
      final_failed_count = progression.last["failed_acceptance_count"]
      case qa["final_verdict"]
      when "accepted"
        valid &&= final_failed_count == 0 && remaining_acceptance.empty?
      when "accepted_with_concerns"
        valid &&= final_failed_count == 0 && !remaining_acceptance.empty? && remaining_acceptance.none? { |finding| finding["severity"] == "blocker" }
      when "rejected"
        valid &&= final_failed_count.is_a?(Integer) && final_failed_count > 0
        valid &&= remaining_acceptance.any? { |finding| %w[blocker concern].include?(finding["severity"]) }
      end
      drift_statuses = progression.map { |entry| entry["drift_status"] }
      domain_pivot = domain_scores.is_a?(Array) && domain_scores.any? { |score| score["action"] == "pivot" }
      repeated_drift = drift_statuses.last(2) == ["DRIFT", "DRIFT"]
      repeated_regression = drift_statuses.last(2) == ["REGRESSION", "REGRESSION"]
      pivot_triggered = drift_statuses.last == "STAGNATION" || repeated_drift || repeated_regression || domain_pivot
      signal = qa["pivot_restart_signal"]
      if pivot_triggered
        expected_triggers = []
        expected_triggers << "STAGNATION" if drift_statuses.last == "STAGNATION"
        expected_triggers << "repeated_DRIFT" if repeated_drift
        expected_triggers << "repeated_REGRESSION" if repeated_regression
        expected_triggers << "pivot" if domain_pivot
        valid &&= signal.is_a?(Hash) && signal["affected_round"] == qa["rounds"] && nonblank.call(signal["recommended_recovery_focus"])
        valid &&= signal && expected_triggers.include?(signal["trigger"])
        valid &&= signal && signal["evidence"].is_a?(Array) && !signal["evidence"].empty? && signal["evidence"].all? { |entry| entry.is_a?(Hash) && nonblank.call(entry["source"]) && nonblank.call(entry["detail"]) }
      else
        valid &&= signal.nil?
      end
    end
    valid &&= qa["evidence"].is_a?(Array) && qa["evidence"].any? && qa["evidence"].all? { |entry| entry.is_a?(Hash) && nonblank.call(entry["source"]) && nonblank.call(entry["detail"]) }
  end
end

exit valid ? 0 : 1
RUBY
}

assistant_review_external_alias_envelopes_valid() {
    local response_path="$1"
    local alias_name
    local artifact_name
    local expected_contract

    # Only structured responses that actually project an assistant-review
    # producer envelope are in this validator's domain.
    jq -e 'type == "object"' "$response_path" >/dev/null 2>&1 || return 0
    jq -e '. as $response | ["canonical_final_summary", "fresh_canonical_final_summary", "canonical_qa_result", "current_canonical_qa_result", "prior_canonical_qa_result", "current_qa_delegation_path"] | any(.[]; . as $name | $response | has($name))' "$response_path" >/dev/null || return 0

    jq -e '
      def nonblank: type == "string" and test("[^[:space:]]");
      def wrapper_valid($name; $contract):
        if has($name) then
          .[$name] as $wrapper
          | ($wrapper | type == "object" and (keys | sort) == ["artifact", "contract", "ref"])
          and ($wrapper.ref | nonblank)
          and $wrapper.contract == $contract
          and ($wrapper.artifact | type == "object")
        else true end;
      wrapper_valid("canonical_final_summary"; "assistant-review/contracts/output.yaml#final_summary")
      and wrapper_valid("fresh_canonical_final_summary"; "assistant-review/contracts/output.yaml#final_summary")
      and wrapper_valid("canonical_qa_result"; "assistant-review/contracts/output.yaml#qa_evaluation_result")
      and wrapper_valid("current_canonical_qa_result"; "assistant-review/contracts/output.yaml#qa_evaluation_result")
      and wrapper_valid("prior_canonical_qa_result"; "assistant-review/contracts/output.yaml#qa_evaluation_result")
      and wrapper_valid("current_qa_delegation_path"; "assistant-review/contracts/output.yaml#qa_evaluation_delegation_path")
    ' "$response_path" >/dev/null || return 1

    while IFS='|' read -r alias_name artifact_name; do
        jq -e --arg alias_name "$alias_name" 'has($alias_name)' "$response_path" >/dev/null || continue
        expected_contract="assistant-review/contracts/output.yaml#$artifact_name"
        jq -e --arg alias_name "$alias_name" --arg expected_contract "$expected_contract" '.[$alias_name].contract == $expected_contract' "$response_path" >/dev/null || return 1
        assistant_review_artifact_schema_valid "external-producer-envelope" "$response_path" "$artifact_name" "$alias_name" || return 1
        case "$artifact_name" in
            final_summary|qa_evaluation_result)
                assistant_review_lifecycle_semantics_valid "external-producer-envelope" "$response_path" "$artifact_name" "$alias_name" || return 1
                ;;
        esac
    done <<'EOF_ASSISTANT_REVIEW_EXTERNAL_ALIASES'
canonical_final_summary|final_summary
fresh_canonical_final_summary|final_summary
canonical_qa_result|qa_evaluation_result
current_canonical_qa_result|qa_evaluation_result
prior_canonical_qa_result|qa_evaluation_result
current_qa_delegation_path|qa_evaluation_delegation_path
EOF_ASSISTANT_REVIEW_EXTERNAL_ALIASES
}

count_assistant_review_canonical_envelope_failures() {
    local skill_name="$1"
    local id="$2"
    local response_path="$3"

    if [[ "$skill_name" == "assistant-workflow" ]]; then
        if assistant_review_external_alias_envelopes_valid "$response_path"; then
            printf '0\n'
        else
            printf '1\n'
        fi
        return
    fi

    [[ "$skill_name" == "assistant-review" ]] || { printf '0\n'; return; }

    case "$id" in
        audit-batch-waits-for-all-pass-results|incomplete-review-batch-never-cleans|post-fix-review-uses-fresh-snapshot-batch|audit-spec-review-fail-continues-complete-batch|in-flight-mutation-invalidates-review-batch|trivial-audit-uses-two-isolated-passes|qa-obligation-echo-fulfills-exact-binding|qa-obligation-blocks-missing-or-mismatched-binding|qa-obligation-blocked-when-required-evidence-is-unavailable)
            ;;
        *)
            printf '0\n'
            return
            ;;
    esac

    if jq -e --arg id "$id" '
        def required_fields($fields):
          . as $object | type == "object" and (($fields - ($object | keys)) | length == 0);
        def final_summary_valid:
          . as $response
          | (.final_summary | required_fields(["reviewed_scope", "rounds", "final_review_snapshot_id", "final_snapshot_identity", "coverage_complete", "coverage_ledger", "batch_summaries", "aggregation_ledger", "aggregated_findings", "result", "fixed_items", "nits"]))
          and (.final_summary.reviewed_scope | type == "array" and length > 0)
          and (.final_summary.rounds | type == "number")
          and (.final_summary.final_review_snapshot_id | type == "string")
          and (.final_summary.final_snapshot_identity | required_fields(["basis", "value", "captured_at", "scope_manifest_digest"])
            and (.basis as $basis | ["git_revision", "diff_digest", "content_digest", "task_or_pr_revision"] | index($basis)))
          and (.final_summary.coverage_complete | type == "boolean")
          and (.final_summary.coverage_ledger | type == "array" and length > 0)
          and all(.final_summary.coverage_ledger[]; required_fields(["batch_id", "review_snapshot_id", "review_pass_id", "perspective", "coverage_obligation", "assigned_scope", "scope_item_id", "applicable_concern", "terminal_state", "coverage_status", "evidence"])
            and (.terminal_state as $terminal_state | ["completed", "needs_context", "blocked", "timed_out", "failed", "invalidated"] | index($terminal_state))
            and (.coverage_status as $coverage_status | ["complete", "incomplete", "invalidated"] | index($coverage_status)))
          and (.final_summary.batch_summaries | type == "array" and length > 0)
          and all(.final_summary.batch_summaries[]; required_fields(["started_batch_ordinal", "batch_id", "review_snapshot_id", "batch_status", "expected_response_count", "terminal_response_count", "aggregate_rubric_recomputed"])
            and (.batch_status as $batch_status | ["complete", "incomplete", "invalidated"] | index($batch_status)))
          and (.final_summary.aggregation_ledger | type == "array")
          and all(.final_summary.aggregation_ledger[]; required_fields(["source_provenance", "disposition", "rationale"])
            and (.disposition as $disposition | ["retained", "merged", "observation", "rejected_invalid", "coverage_gap"] | index($disposition)))
          and (.final_summary.aggregated_findings | type == "array")
          and all(.final_summary.aggregated_findings[]; required_fields(["aggregate_finding_id", "finding_id", "source_finding_ids", "source_provenance", "locus", "file", "invariant", "failure_mechanism", "severity", "description", "evidence", "smallest_useful_fix", "confidence_pct"])
            and (.severity as $severity | ["must-fix", "should-fix", "nit"] | index($severity)))
          and (.final_summary.result as $result | ["CLEAN", "ISSUES_FIXED", "HAS_REMAINING_ITEMS"] | index($result))
          and (.final_summary.fixed_items | type == "array")
          and (.final_summary.nits | type == "array")
          and (if $response.final_summary.result == "HAS_REMAINING_ITEMS" then ($response.final_summary.remaining_items | type == "array") else true end)
          and (if $response.final_summary.coverage_complete then true else ($response.final_summary.coverage_gaps | type == "array" and length > 0) end)
          and (if ($response.final_summary.result == "CLEAN" or $response.final_summary.result == "ISSUES_FIXED") and $response.final_summary.coverage_complete then $response.final_summary.evidence_bounded_claim == "No material findings within the reviewed scope and available evidence" else true end);
        def audit_report_valid:
          (.audit_report | required_fields(["coverage_complete", "batch_summaries", "coverage_ledger_ref", "findings", "summary"])
            and (.coverage_complete | type == "boolean")
            and (.batch_summaries | type == "array" and length > 0)
            and (.coverage_ledger_ref | type == "string")
            and (.findings | type == "array")
            and all(.findings[]; required_fields(["severity", "file", "description", "aggregate_finding_id", "finding_id", "source_finding_ids", "source_provenance", "confidence_pct", "locus", "invariant", "failure_mechanism", "evidence", "smallest_useful_fix"])
              and (.severity as $severity | ["must-fix", "should-fix", "nit"] | index($severity))));
        def qa_result_valid:
          . as $response
          | (.qa_evaluation_result | required_fields(["rounds", "final_verdict", "result", "acceptance_findings", "approved_feature_preparation_qa_acceptance_obligation_result", "qa_scorecard", "score_progression", "evidence"]))
          and (.qa_evaluation_result.rounds | type == "number")
          and (.qa_evaluation_result.final_verdict as $verdict | ["accepted", "accepted_with_concerns", "rejected", "blocked"] | index($verdict))
          and (.qa_evaluation_result.result as $result | ["CLEAN", "ISSUES_FIXED", "HAS_REMAINING_ITEMS", "BLOCKED"] | index($result))
          and (.qa_evaluation_result.acceptance_findings | type == "array")
          and all(.qa_evaluation_result.acceptance_findings[]; required_fields(["severity", "criterion", "evidence", "impact", "disposition"])
            and (.severity as $severity | ["blocker", "concern", "observation"] | index($severity))
            and (.disposition as $disposition | ["resolved", "remaining", "not_applicable"] | index($disposition)))
          and (.qa_evaluation_result.approved_feature_preparation_qa_acceptance_obligation_result | required_fields(["requested_scope_status", "requested_scope_evidence", "execution_prerequisite_status", "execution_prerequisite_evidence", "requested_scope", "execution_prerequisite", "feature_preparation_scope", "source_feature_preparation_evidence_ref"])
            and (.requested_scope_status as $scope_status | ["fulfilled", "blocked", "failed"] | index($scope_status))
            and (.execution_prerequisite_status as $prerequisite_status | ["met", "missing", "blocked"] | index($prerequisite_status))
            and (.feature_preparation_scope == "existing_system"))
          and (.qa_evaluation_result.qa_scorecard | required_fields(["acceptance_coverage", "evidence_strength", "domain_quality", "final_readiness", "weighted_score", "rationale"])
            and ([.acceptance_coverage, .evidence_strength, .domain_quality, .final_readiness, .weighted_score] | all(.[]; type == "number"))
            and (.rationale | required_fields(["acceptance_coverage", "evidence_strength", "domain_quality", "final_readiness"])))
          and (.qa_evaluation_result.score_progression | type == "array" and length > 0)
          and all(.qa_evaluation_result.score_progression[]; required_fields(["round", "weighted_score", "failed_acceptance_count", "drift_status"])
            and (.drift_status as $drift_status | ["GENUINE", "SUSPICIOUS", "DRIFT", "REGRESSION", "STAGNATION", "NEUTRAL", "NOT_APPLICABLE"] | index($drift_status)))
          and (.qa_evaluation_result.score_progression[-1].weighted_score == .qa_evaluation_result.qa_scorecard.weighted_score)
          and (.qa_evaluation_result.evidence | type == "array" and length > 0)
          and all(.qa_evaluation_result.evidence[]; required_fields(["source", "detail"]))
          and (if $response.qa_evaluation_result.final_verdict == "blocked" then ($response.qa_evaluation_result.open_questions | type == "array" and length > 0) else true end);
        if $id == "qa-obligation-echo-fulfills-exact-binding" or $id == "qa-obligation-blocks-missing-or-mismatched-binding" or $id == "qa-obligation-blocked-when-required-evidence-is-unavailable" then qa_result_valid
        elif $id == "audit-batch-waits-for-all-pass-results" or $id == "audit-spec-review-fail-continues-complete-batch" then final_summary_valid and audit_report_valid and (.final_summary.fixed_items == [])
        else final_summary_valid end
    ' "$response_path" >/dev/null \
        && assistant_review_artifact_schema_valid "$id" "$response_path" \
        && assistant_review_lifecycle_semantics_valid "$id" "$response_path"; then
        printf '0\n'
    else
        printf '1\n'
    fi
}

count_structured_json_assertion_failures() {
    local fixture_file="$1"
    local id="$2"
    local response_path="$3"
    local assertion
    local structured_assertion_count
    local failures=0

    structured_assertion_count="$(jq -r --arg id "$id" '.cases[] | select(.id == $id) | (.machine_expectations.structured_json_assertions? // []) | length' "$fixture_file")"

    if ! jq -e -s 'length == 1' "$response_path" >/dev/null 2>&1; then
        if [[ "$structured_assertion_count" -gt 0 ]]; then
            printf '1\n'
        else
            printf '0\n'
        fi
        return
    fi

    while [[ "$structured_assertion_count" -gt 0 ]] && IFS= read -r assertion; do
        if ! jq -e --argjson assertion "$assertion" '
            def path_exists($path):
              reduce $path[] as $key (
                { exists: true, value: . };
                if (.exists | not) then .
                elif (($key | type) == "string") and ((.value | type) == "object") and (.value | has($key)) then
                  { exists: true, value: .value[$key] }
                elif (($key | type) == "number") and ((.value | type) == "array") and ($key >= 0) and ($key < (.value | length)) then
                  { exists: true, value: .value[$key] }
                else
                  { exists: false, value: null }
                end
              ) | .exists;
            def value_at($path): getpath($path);
            def object_field_tuples($items; $fields):
              [$items[] | . as $item | [$fields[] as $field | $item[$field]]];
            if $assertion.operator == "equals" then
              path_exists($assertion.path) and value_at($assertion.path) == $assertion.expected
            elif $assertion.operator == "one_of" then
              path_exists($assertion.path)
              and (value_at($assertion.path) as $actual | ($assertion.expected_values | index($actual)) != null)
            elif $assertion.operator == "nonempty_string" then
              path_exists($assertion.path) and (value_at($assertion.path) | type == "string" and test("[^[:space:]]"))
            elif $assertion.operator == "nonempty_array" then
              path_exists($assertion.path) and (value_at($assertion.path) | type == "array" and length > 0)
            elif $assertion.operator == "empty_array" then
              path_exists($assertion.path) and (value_at($assertion.path) | type == "array" and length == 0)
            elif $assertion.operator == "array_type" then
              path_exists($assertion.path) and (value_at($assertion.path) | type == "array")
            elif $assertion.operator == "array_nonblank_strings" then
              path_exists($assertion.path)
              and (value_at($assertion.path) | type == "array")
              and ($assertion.allow_empty or (value_at($assertion.path) | length > 0))
              and all(value_at($assertion.path)[]; type == "string" and test("[^[:space:]]"))
            elif $assertion.operator == "path_absent" then
              path_exists($assertion.path) | not
            elif $assertion.operator == "absent_or_empty_array" then
              if path_exists($assertion.path) then
                value_at($assertion.path) | type == "array" and length == 0
              else true end
            elif $assertion.operator == "equals_path" then
              path_exists($assertion.path) and path_exists($assertion.other_path)
              and value_at($assertion.path) == value_at($assertion.other_path)
            elif $assertion.operator == "required_when_equals" then
              if path_exists($assertion.when_path) and value_at($assertion.when_path) == $assertion.value then
                path_exists($assertion.path) and value_at($assertion.path) != null
                and (if $assertion.expected_type? == null then true else (value_at($assertion.path) | type == $assertion.expected_type) end)
              else true end
            elif $assertion.operator == "array_field_values_exact" then
              path_exists($assertion.path)
              and (value_at($assertion.path) | type == "array")
              and ([value_at($assertion.path)[] | if type == "object" then .[$assertion.field] else null end] | sort)
                == ($assertion.expected_values | sort)
            elif $assertion.operator == "array_items_nonempty_fields" then
              path_exists($assertion.path)
              and (value_at($assertion.path) | type == "array")
              and (value_at($assertion.path) | length > 0)
              and all(value_at($assertion.path)[]; . as $item | type == "object" and all($assertion.fields[]; . as $field | ($item[$field] | type == "string" and test("[^[:space:]]"))))
            elif $assertion.operator == "array_items_nonempty_array_fields" then
              path_exists($assertion.path)
              and (value_at($assertion.path) | type == "array")
              and (value_at($assertion.path) | length > 0)
              and all(value_at($assertion.path)[]; . as $item | type == "object" and all($assertion.fields[]; . as $field | ($item[$field] | type == "array" and length > 0 and all(.[]; type == "string" and test("[^[:space:]]")))))
            elif $assertion.operator == "array_object_values_exact" then
              path_exists($assertion.path)
              and (value_at($assertion.path) | type == "array")
              and all(value_at($assertion.path)[]; . as $item | type == "object" and all($assertion.fields[]; . as $field | $item | has($field)))
              and (object_field_tuples(value_at($assertion.path); $assertion.fields) | sort)
                == (object_field_tuples($assertion.expected_objects; $assertion.fields) | sort)
            else false end
        ' "$response_path" >/dev/null; then
            failures=$((failures + 1))
        fi
    done < <(jq -c --arg id "$id" '.cases[] | select(.id == $id) | .machine_expectations.structured_json_assertions[]?' "$fixture_file")

    # Preparation-only responses have a fixed no-execution boundary. Keep this
    # structural guard independent of prose anchors so every declared response
    # path is rejected, including paths that never appear in rendered text.
    if ! jq -e '
        def path_exists($path):
          reduce $path[] as $key (
            { exists: true, value: . };
            if (.exists | not) then .
            elif (($key | type) == "string") and ((.value | type) == "object") and (.value | has($key)) then { exists: true, value: .value[$key] }
            elif (($key | type) == "number") and ((.value | type) == "array") and ($key >= 0) and ($key < (.value | length)) then { exists: true, value: .value[$key] }
            else { exists: false, value: null } end
          ) | .exists;
        def execution_paths: [
          ["artifact_contract"], ["task_packet"], ["task_packets"], ["decomposition_plan_review"], ["slice_manifest"], ["single_slice_rationale"], ["slice_verification_summary"], ["changed_files"], ["test_results"], ["spec_review_result"], ["review_result"], ["qa_evaluation_result"], ["fresh_review_result"], ["manual_test_steps"], ["manual_verification_result"], ["subagent_evidence"], ["build_repair_state"], ["artifact_reference_ledger"], ["done_contract"], ["harness_recipe"], ["harness_run_state"], ["trace_ledger"], ["replay_packet"], ["final_handoff"], ["user_approval"]
        ];
        . as $response
        | if $response.execution_intent != "prepare_only" then true
        else
          (all(execution_paths[]; . as $path | $response | path_exists($path) | not))
          and (if $response.completion_policy.plan_mode == "none" then ($response | path_exists(["plan_document"]) | not) and ($response | path_exists(["feature_preparation_result","readiness_plan"]) | not) else true end)
          and (if $response.feature_preparation_scope == "not_applicable" then ($response | path_exists(["feature_preparation_evidence"]) | not) and ($response | path_exists(["feature_preparation_result","feature_preparation_evidence_ref"]) | not) and ($response | path_exists(["feature_preparation_result","readiness_plan","evidence_ref"]) | not) else $response | path_exists(["feature_preparation_result","readiness_plan","preparation_basis"]) | not end)
        end
    ' "$response_path" >/dev/null; then
        failures=$((failures + 1))
    fi

    printf '%s\n' "$failures"
}

grade_responses() {
    validate_all_fixtures
    [[ -d "$RESPONSES_DIR" ]] || die "Response directory does not exist: $RESPONSES_DIR"

    local total=0
    local passed=0
    local failed=0
    local missing=0
    local empty=0
    local signal_failures=0
    local missing_required_failures=0
    local forbidden_substring_failures=0
    local ordered_substring_failures=0
    local seeded_defect_failures=0
    local false_positive_marker_failures=0
    local structured_json_assertion_failures=0
    local index
    local skill_name
    local fixture_file
    local id
    local category
    local title
    local response_path
    local fail_signal_hits
    local required_misses
    local forbidden_hits
    local ordered_failures
    local seeded_failures
    local false_positive_failures
    local structured_failures
    local canonical_envelope_failures
    local status
    local reason

    echo "Heuristic/local grading only. Deterministic substring checks are local proxies; no provider API is invoked."
    echo ""

    for index in "${!FIXTURE_FILES[@]}"; do
        skill_name="${SKILL_NAMES[$index]}"
        fixture_file="${FIXTURE_FILES[$index]}"

        while IFS=$'\t' read -r id category title; do
            total=$((total + 1))
            response_path="$(first_response_path_for_case "$skill_name" "$id")"
            status="PASS"
            reason="non-empty response with no exact fail-signal phrase hits and no machine expectation failures"

            if [[ -z "$response_path" ]]; then
                status="FAIL"
                reason="missing response file"
                missing=$((missing + 1))
            elif ! is_file_nonempty "$response_path"; then
                status="FAIL"
                reason="empty response file"
                empty=$((empty + 1))
            else
                fail_signal_hits="$(count_fail_signal_hits "$fixture_file" "$id" "$response_path")"
                required_misses="$(count_missing_required_substrings "$fixture_file" "$id" "$response_path")"
                forbidden_hits="$(count_forbidden_substring_hits "$fixture_file" "$id" "$response_path")"
                ordered_failures="$(count_ordered_substring_failures "$fixture_file" "$id" "$response_path")"
                seeded_failures="$(count_seeded_defect_failures "$fixture_file" "$id" "$response_path")"
                false_positive_failures="$(count_false_positive_marker_failures "$fixture_file" "$id" "$response_path")"
                structured_failures="$(count_structured_json_assertion_failures "$fixture_file" "$id" "$response_path")"
                canonical_envelope_failures="$(count_assistant_review_canonical_envelope_failures "$skill_name" "$id" "$response_path")"
                structured_failures=$((structured_failures + canonical_envelope_failures))
                if [[ "$fail_signal_hits" -gt 0 ]]; then
                    status="FAIL"
                    reason="$fail_signal_hits exact fail-signal phrase hit(s)"
                    signal_failures=$((signal_failures + 1))
                fi
                if [[ "$required_misses" -gt 0 ]]; then
                    if [[ "$status" == "FAIL" ]]; then
                        reason="$reason; $required_misses missing required substring(s)"
                    else
                        status="FAIL"
                        reason="$required_misses missing required substring(s)"
                    fi
                    missing_required_failures=$((missing_required_failures + required_misses))
                fi
                if [[ "$forbidden_hits" -gt 0 ]]; then
                    if [[ "$status" == "FAIL" ]]; then
                        reason="$reason; $forbidden_hits forbidden substring hit(s)"
                    else
                        status="FAIL"
                        reason="$forbidden_hits forbidden substring hit(s)"
                    fi
                    forbidden_substring_failures=$((forbidden_substring_failures + forbidden_hits))
                fi
                if [[ "$ordered_failures" -gt 0 ]]; then
                    if [[ "$status" == "FAIL" ]]; then
                        reason="$reason; $ordered_failures ordered substring assertion failure(s)"
                    else
                        status="FAIL"
                        reason="$ordered_failures ordered substring assertion failure(s)"
                    fi
                    ordered_substring_failures=$((ordered_substring_failures + ordered_failures))
                fi
                if [[ "$seeded_failures" -gt 0 ]]; then
                    if [[ "$status" == "FAIL" ]]; then
                        reason="$reason; $seeded_failures seeded defect assertion failure(s)"
                    else
                        status="FAIL"
                        reason="$seeded_failures seeded defect assertion failure(s)"
                    fi
                    seeded_defect_failures=$((seeded_defect_failures + seeded_failures))
                fi
                if [[ "$false_positive_failures" -gt 0 ]]; then
                    if [[ "$status" == "FAIL" ]]; then
                        reason="$reason; $false_positive_failures false positive marker budget failure(s)"
                    else
                        status="FAIL"
                        reason="$false_positive_failures false positive marker budget failure(s)"
                    fi
                    false_positive_marker_failures=$((false_positive_marker_failures + false_positive_failures))
                fi
                if [[ "$structured_failures" -gt 0 ]]; then
                    if [[ "$status" == "FAIL" ]]; then
                        reason="$reason; $structured_failures structured JSON assertion failure(s)"
                    else
                        status="FAIL"
                        reason="$structured_failures structured JSON assertion failure(s)"
                    fi
                    structured_json_assertion_failures=$((structured_json_assertion_failures + structured_failures))
                fi
            fi

            if [[ "$status" == "PASS" ]]; then
                passed=$((passed + 1))
            else
                failed=$((failed + 1))
            fi

            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$status" "$skill_name" "$id" "$category" "$title" "$reason"
        done < <(jq -r '.cases[] | [.id, .category, .title] | @tsv' "$fixture_file")
    done

    echo ""
    printf 'Summary: total=%s passed=%s failed=%s missing=%s empty=%s fail_signal_hits=%s missing_required_substrings=%s forbidden_substring_hits=%s ordered_substring_failures=%s seeded_defect_failures=%s false_positive_marker_failures=%s structured_json_assertion_failures=%s skills=%s\n' \
        "$total" "$passed" "$failed" "$missing" "$empty" "$signal_failures" "$missing_required_failures" "$forbidden_substring_failures" "$ordered_substring_failures" "$seeded_defect_failures" "$false_positive_marker_failures" "$structured_json_assertion_failures" "${#FIXTURE_FILES[@]}"

    [[ "$failed" -eq 0 ]]
}
