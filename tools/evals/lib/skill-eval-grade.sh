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
    local repository_root="${REPO_ROOT:-${FRAMEWORK_DIR:?FRAMEWORK_DIR or REPO_ROOT is required}}"
    local fixture_file="${5:-$repository_root/skills/assistant-review/evals/cases.json}"

    ruby -rjson -ryaml - "$repository_root/skills/assistant-review/contracts/output.yaml" "$fixture_file" "$response_path" "$id" "$explicit_artifact_name" "$response_root" <<'RUBY'
contract = YAML.load_file(ARGV.fetch(0))
fixture = JSON.parse(File.read(ARGV.fetch(1)))
response = JSON.parse(File.read(ARGV.fetch(2)))
case_id = ARGV.fetch(3)
explicit_artifact_name = ARGV.fetch(4)
response_root = ARGV.fetch(5)
artifacts = contract.fetch("artifacts").to_h { |artifact| [artifact.fetch("name"), artifact] }

qa_case_requirements = fixture.fetch("canonical_qa_case_requirements", {})
case_requirement = fixture.dig("canonical_review_batch_expectations", "case_requirements", case_id)
artifact_names = if !explicit_artifact_name.empty?
  [explicit_artifact_name]
elsif case_requirement.is_a?(Hash)
  case_requirement.fetch("required_artifacts")
elsif qa_case_requirements.key?(case_id)
  qa_case_requirements.fetch(case_id).fetch("required_artifacts")
else
  ["final_summary"]
end

valid = nil
valid = lambda do |value, field|
  type = field.fetch("type")
  type_valid = case type
               when "string", "file", "jsonl_line" then value.is_a?(String) && !value.strip.empty?
               when "int" then value.is_a?(Integer)
               when "float" then value.is_a?(Numeric)
               when "boolean" then value == true || value == false
               when "enum" then value.is_a?(String) && field.fetch("enum_values").include?(value)
               when "string[]" then value.is_a?(Array) && value.all? { |item| item.is_a?(String) && !item.strip.empty? }
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
    local fixture_file="${5:-$repository_root/skills/assistant-review/evals/cases.json}"

    ruby -rjson -ryaml -rbigdecimal - "$repository_root/skills/assistant-review/contracts/output.yaml" "$fixture_file" "$response_path" "$id" "$explicit_artifact_name" "$response_root" <<'RUBY'
contract = YAML.load_file(ARGV.fetch(0))
fixture = JSON.parse(File.read(ARGV.fetch(1)))
response = JSON.parse(File.read(ARGV.fetch(2)), decimal_class: BigDecimal)
case_id = ARGV.fetch(3)
explicit_artifact_name = ARGV.fetch(4)
response_root = ARGV.fetch(5)
outer_response = response
if !explicit_artifact_name.empty?
  response = { explicit_artifact_name => response.dig(response_root, "artifact") }
end

qa_case_requirements = fixture.fetch("canonical_qa_case_requirements", {})
qa_cases = qa_case_requirements.keys + ["not-applicable-binding-unit"]
case_requirement = fixture.dig("canonical_review_batch_expectations", "case_requirements", case_id)
audit_required = case_requirement.is_a?(Hash) && case_requirement.fetch("required_artifacts", []).include?("audit_report")
nonblank = ->(value) { value.is_a?(String) && !value.strip.empty? }
nonblank_strings = ->(value) { value.is_a?(Array) && !value.empty? && value.all? { |item| nonblank.call(item) } }
integer_in = ->(value, range) { value.is_a?(Integer) && range.cover?(value) }
decimal = ->(value) { value.is_a?(Numeric) ? BigDecimal(value.to_s) : nil }
identity_valid = lambda do |identity|
  identity.is_a?(Hash) && %w[basis value captured_at scope_manifest_digest].all? { |key| nonblank.call(identity[key]) } &&
    %w[git_revision diff_digest content_digest task_or_pr_revision].include?(identity["basis"])
end
snapshot_projection = lambda do |batch|
  batch.is_a?(Hash) ? batch.slice("batch_id", "review_snapshot_id", "snapshot_identity") : nil
end
snapshot_authority_valid = lambda do |authority|
  authority.is_a?(Hash) && authority.keys.sort == %w[batch_projections final_review_snapshot_id final_snapshot_identity] &&
    nonblank.call(authority["final_review_snapshot_id"]) && identity_valid.call(authority["final_snapshot_identity"]) &&
    authority["batch_projections"].is_a?(Array) && !authority["batch_projections"].empty? &&
    authority["batch_projections"].all? do |projection|
      projection.is_a?(Hash) && projection.keys.sort == %w[batch_id review_snapshot_id snapshot_identity] &&
        nonblank.call(projection["batch_id"]) && nonblank.call(projection["review_snapshot_id"]) && identity_valid.call(projection["snapshot_identity"])
    end
end
deferred_qa_obligation_authority_valid = lambda do |authority|
  return false unless authority.is_a?(Hash)
  required = %w[requested_scope execution_prerequisite feature_preparation_scope]
  bindings = %w[source_feature_preparation_evidence_ref source_preparation_basis]
  return false unless (authority.keys - (required + bindings)).empty? && required.all? { |field| nonblank.call(authority[field]) }
  return false unless %w[existing_system not_applicable].include?(authority["feature_preparation_scope"])
  present_bindings = bindings.select { |field| authority.key?(field) }
  return false unless present_bindings.length == 1 && nonblank.call(authority[present_bindings.first])
  authority["feature_preparation_scope"] == "existing_system" ? present_bindings == ["source_feature_preparation_evidence_ref"] : present_bindings == ["source_preparation_basis"] && authority["source_preparation_basis"] == "not_applicable"
end
expected_obligation_value = lambda do |field|
  path = ["qa_evaluation_result", "approved_feature_preparation_qa_acceptance_obligation_result", field]
  fixture.fetch("cases").find { |test_case| test_case["id"] == case_id }
    &.dig("machine_expectations", "structured_json_assertions")
    &.find { |assertion| assertion["operator"] == "equals" && assertion["path"] == path }
    &.fetch("expected", nil)
end
batch_expectations = fixture["canonical_review_batch_expectations"]
template_ref = batch_expectations.is_a?(Hash) ? batch_expectations.fetch("case_template_refs", {})[case_id] : nil
frozen_final_batch_plan = template_ref ? batch_expectations.fetch("templates", {})[template_ref] : nil
frozen_scope_manifest = template_ref ? batch_expectations.fetch("scope_manifests", {})[template_ref] : nil
frozen_closure_authority = fixture.fetch("canonical_review_closure_expectations", {})[case_id]
frozen_snapshot_authority = fixture.fetch("canonical_review_snapshot_expectations", {})[case_id]
frozen_deferred_qa_obligation_authority = fixture.fetch("canonical_deferred_qa_obligation_expectations", {})[case_id]
valid = true

if explicit_artifact_name == "final_summary" || (explicit_artifact_name.empty? && !template_ref.nil?)
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
          batch["terminal_response_count"] <= batch["expected_response_count"] && batch["aggregate_rubric_recomputed"] == false
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
    if snapshot_authority_valid.call(frozen_snapshot_authority)
      valid &&= summary["final_review_snapshot_id"] == frozen_snapshot_authority["final_review_snapshot_id"]
      valid &&= identity == frozen_snapshot_authority["final_snapshot_identity"]
      valid &&= batches.map { |batch| snapshot_projection.call(batch) } == frozen_snapshot_authority["batch_projections"]
      if outer_response["audit_report"]
        audit_batches = outer_response.dig("audit_report", "batch_summaries")
        valid &&= audit_batches.is_a?(Array) && audit_batches.map { |batch| snapshot_projection.call(batch) } == frozen_snapshot_authority["batch_projections"]
      end
    else
      valid = false
    end
    final_plan = summary["final_batch_plan"]
    valid &&= final_plan.is_a?(Hash)
    final_plan = {} unless final_plan.is_a?(Hash)
    valid &&= frozen_final_batch_plan.is_a?(Hash) && frozen_scope_manifest.is_a?(Array) && final_plan == frozen_final_batch_plan
    expected_passes = final_plan["expected_passes"]
    required_tuples = final_plan["required_coverage_tuples"]
    topology = final_plan["topology"]
    valid &&= expected_passes.is_a?(Array) && required_tuples.is_a?(Array) && topology.is_a?(Hash)
    expected_passes = [] unless expected_passes.is_a?(Array)
    required_tuples = [] unless required_tuples.is_a?(Array)
    topology = {} unless topology.is_a?(Hash)
    valid &&= final_plan.is_a?(Hash) && final_plan["batch_id"] == current_batch["batch_id"] && final_plan["review_snapshot_id"] == current_batch["review_snapshot_id"]
    scope_size = final_plan.is_a?(Hash) ? final_plan["scope_size"] : nil
    canonical_perspectives = {
      "trivial" => %w[contract_and_test_oracle runtime_lifecycle_and_failure_paths],
      "small" => %w[contract_and_test_oracle runtime_lifecycle_and_failure_paths],
      "medium" => %w[contract_and_test_oracle runtime_lifecycle_and_failure_paths integration_compatibility_and_consumers],
      "large" => %w[contract_and_test_oracle runtime_lifecycle_and_failure_paths integration_compatibility_and_consumers architecture_maintainability_and_reuse]
    }
    valid &&= canonical_perspectives.key?(scope_size)
    expected_discovery = canonical_perspectives.fetch(scope_size, [])
    valid &&= topology.is_a?(Hash) && topology["discovery_pass_count"] == expected_discovery.length && integer_in.call(topology["max_required_responses"], 2..6) && topology["max_repair_attempts_per_pass"] == 1
    valid &&= [true, false].include?(topology["security_specialist_triggered"]) && [true, false].include?(topology["closure_verification_required"])
    canonical_lists = topology.is_a?(Hash) ? topology["canonical_discovery_perspectives"] : nil
    valid &&= canonical_lists.is_a?(Hash) && canonical_lists.keys.sort == %w[large medium trivial_small]
    valid &&= canonical_lists && canonical_lists["trivial_small"] == canonical_perspectives["small"] && canonical_lists["medium"] == canonical_perspectives["medium"] && canonical_lists["large"] == canonical_perspectives["large"]
    valid &&= expected_passes.length == current_batch["expected_response_count"] && expected_passes.length == topology["max_required_responses"] && expected_passes.length.between?(2, 6)
    valid &&= expected_passes.all? do |pass|
      pass.is_a?(Hash) && nonblank.call(pass["review_pass_id"]) &&
        %w[contract_and_test_oracle runtime_lifecycle_and_failure_paths integration_compatibility_and_consumers architecture_maintainability_and_reuse risk_selected_specialist closure_verification].include?(pass["perspective"]) &&
        nonblank_strings.call(pass["assigned_scope"]) && nonblank_strings.call(pass["coverage_obligations"]) &&
        pass["assigned_scope"].uniq.length == pass["assigned_scope"].length &&
        pass["coverage_obligations"].uniq.length == pass["coverage_obligations"].length &&
        %w[none closure_ledger].include?(pass["prior_finding_visibility"])
    end
    expected_passes = expected_passes.select { |pass| pass.is_a?(Hash) }
    valid &&= expected_passes.map { |pass| pass["review_pass_id"] }.uniq.length == expected_passes.length
    expected_discovery_passes = expected_passes.select { |pass| expected_discovery.include?(pass["perspective"]) }
    valid &&= expected_discovery_passes.length == expected_discovery.length && expected_discovery_passes.map { |pass| pass["perspective"] }.sort == expected_discovery.sort
    valid &&= expected_passes.none? { |pass| (%w[integration_compatibility_and_consumers architecture_maintainability_and_reuse] - expected_discovery).include?(pass["perspective"]) }
    specialist_passes = expected_passes.select { |pass| pass["perspective"] == "risk_selected_specialist" }
    closure_passes = expected_passes.select { |pass| pass["perspective"] == "closure_verification" }
    valid &&= (topology["security_specialist_triggered"] ? specialist_passes.length == 1 : specialist_passes.empty?)
    valid &&= (topology["closure_verification_required"] ? closure_passes.length == 1 : closure_passes.empty?)
    valid &&= expected_passes.all? do |pass|
      pass["perspective"] == "closure_verification" ? pass["prior_finding_visibility"] == "closure_ledger" : pass["prior_finding_visibility"] == "none"
    end
    valid &&= nonblank_strings.call(summary["reviewed_scope"])
    valid &&= ledger.is_a?(Array) && !ledger.empty?
    valid &&= ledger.all? do |entry|
      entry.is_a?(Hash) && %w[batch_id review_snapshot_id review_pass_id perspective coverage_obligation scope_item_id applicable_concern evidence].all? { |key| nonblank.call(entry[key]) } &&
        nonblank_strings.call(entry["assigned_scope"]) &&
        case entry["coverage_disposition"]
        when "inspected_no_risk"
          entry["coverage_status"] == "complete" && !entry.key?("finding_ids")
        when "finding"
          entry["coverage_status"] == "complete" && nonblank_strings.call(entry["finding_ids"]) && entry["finding_ids"].uniq.length == entry["finding_ids"].length
        when "incomplete"
          %w[incomplete invalidated].include?(entry["coverage_status"]) && !entry.key?("finding_ids")
        else
          false
        end &&
        if %w[incomplete invalidated].include?(entry["coverage_status"])
          nonblank.call(entry["coverage_gap_id"])
        else
          !entry.key?("coverage_gap_id")
        end
    end
    batch_identity_pairs = batches.map { |batch| [batch["batch_id"], batch["review_snapshot_id"]] }
    valid &&= ledger.all? { |entry| batch_identity_pairs.include?([entry["batch_id"], entry["review_snapshot_id"]]) }
    valid &&= batches.all? do |batch|
      batch_entries = ledger.select { |entry| entry["batch_id"] == batch["batch_id"] && entry["review_snapshot_id"] == batch["review_snapshot_id"] }
      !batch_entries.empty? && case batch["batch_status"]
      when "complete"
        batch_entries.all? { |entry| entry["terminal_state"] == "completed" && entry["coverage_status"] == "complete" && %w[inspected_no_risk finding].include?(entry["coverage_disposition"]) }
      when "incomplete"
        batch_entries.any? { |entry| entry["terminal_state"] != "completed" || entry["coverage_status"] != "complete" }
      when "invalidated"
        batch_entries.any? { |entry| entry["terminal_state"] == "invalidated" || entry["coverage_status"] == "invalidated" }
      else
        false
      end
    end
    current_ledger = ledger.select { |entry| entry["review_snapshot_id"] == summary["final_review_snapshot_id"] }
    valid &&= !current_ledger.empty? && current_ledger.all? { |entry| entry["batch_id"] == current_batch["batch_id"] }
    valid &&= batches.all? do |batch|
      batch_entries = ledger.select { |entry| entry["batch_id"] == batch["batch_id"] && entry["review_snapshot_id"] == batch["review_snapshot_id"] }
      pass_terminal_states = batch_entries.group_by { |entry| entry["review_pass_id"] }.values.map do |pass_entries|
        pass_entries.map { |entry| entry["terminal_state"] }.uniq
      end
      response_backed_count = pass_terminal_states.count do |states|
        states.length == 1 && %w[completed needs_context blocked].include?(states.first)
      end
      invalidated_pass_count = pass_terminal_states.count do |states|
        states.length == 1 && states.first == "invalidated"
      end
      pass_terminal_states.length == batch["expected_response_count"] && pass_terminal_states.all? { |states| states.length == 1 } &&
        batch["terminal_response_count"].between?(response_backed_count, response_backed_count + invalidated_pass_count)
    end
    coverage_tuples = current_ledger.map do |entry|
      [entry["review_pass_id"], entry["scope_item_id"], entry["applicable_concern"], entry["perspective"], entry["coverage_obligation"]]
    end
    valid &&= coverage_tuples.uniq.length == coverage_tuples.length
    plan_tuples = required_tuples.map do |tuple|
      tuple.is_a?(Hash) ? [tuple["review_pass_id"], tuple["scope_item_id"], tuple["applicable_concern"], tuple["review_perspective"], tuple["coverage_obligation"]] : nil
    end
    valid &&= !required_tuples.empty? && !plan_tuples.include?(nil) && plan_tuples.uniq.length == plan_tuples.length && plan_tuples.sort == coverage_tuples.sort
    plan_tuples = plan_tuples.compact
    manifest_by_scope_item = Array(frozen_scope_manifest).select { |item| item.is_a?(Hash) }.to_h { |item| [item["scope_item_id"], item] }
    manifest_tuples = expected_passes.flat_map do |pass|
      Array(pass["assigned_scope"]).flat_map do |scope_item|
        Array(manifest_by_scope_item.dig(scope_item, "applicable_concerns")).flat_map do |concern|
          Array(pass["coverage_obligations"]).map do |obligation|
            [pass["review_pass_id"], scope_item, concern, pass["perspective"], obligation]
          end
        end
      end
    end
    valid &&= !manifest_tuples.empty? && manifest_tuples.uniq.length == manifest_tuples.length && plan_tuples.sort == manifest_tuples.sort
    valid &&= expected_passes.all? do |pass|
      pass_tuples = plan_tuples.select { |tuple| tuple[0] == pass["review_pass_id"] }
      expected_matrix = pass["assigned_scope"].flat_map do |scope_item|
        Array(manifest_by_scope_item.dig(scope_item, "applicable_concerns")).flat_map do |concern|
          pass["coverage_obligations"].map do |obligation|
            [pass["review_pass_id"], scope_item, concern, pass["perspective"], obligation]
          end
        end
      end
      pass["assigned_scope"].all? { |scope_item| pass_tuples.any? { |tuple| tuple[1] == scope_item } } &&
        expected_matrix.sort == pass_tuples.sort
    end
    planned_pass_ids = expected_passes.map { |pass| pass["review_pass_id"] }
    valid &&= current_ledger.map { |entry| entry["review_pass_id"] }.uniq.sort == planned_pass_ids.sort
    valid &&= expected_passes.all? do |pass|
      pass_entries = current_ledger.select { |entry| entry["review_pass_id"] == pass["review_pass_id"] }
      !pass_entries.empty? && pass_entries.all? do |entry|
        Array(pass["assigned_scope"]).include?(entry["scope_item_id"]) && Array(pass["coverage_obligations"]).include?(entry["coverage_obligation"]) && pass["perspective"] == entry["perspective"]
      end && Array(pass["assigned_scope"]).all? { |scope_item| plan_tuples.any? { |tuple| tuple[0] == pass["review_pass_id"] && tuple[1] == scope_item } } && Array(pass["coverage_obligations"]).all? { |obligation| plan_tuples.any? { |tuple| tuple[0] == pass["review_pass_id"] && tuple[4] == obligation } }
    end
    complete_current_coverage = current_ledger.all? { |entry| entry["terminal_state"] == "completed" && entry["coverage_status"] == "complete" && %w[inspected_no_risk finding].include?(entry["coverage_disposition"]) }
    current_gap_entries = current_ledger.reject { |entry| entry["terminal_state"] == "completed" && entry["coverage_status"] == "complete" }
    current_gap_ids = current_gap_entries.map { |entry| entry["coverage_gap_id"] }
    valid &&= current_ledger.all? do |entry|
      complete = entry["terminal_state"] == "completed" && entry["coverage_status"] == "complete"
      complete ? !entry.key?("coverage_gap_id") : (%w[incomplete invalidated].include?(entry["coverage_status"]) && nonblank.call(entry["coverage_gap_id"]))
    end
    all_gap_ids = ledger.select { |entry| %w[incomplete invalidated].include?(entry["coverage_status"]) }.map { |entry| entry["coverage_gap_id"] }
    valid &&= current_gap_ids.all? { |gap_id| nonblank.call(gap_id) } && current_gap_ids.uniq.length == current_gap_ids.length && all_gap_ids.all? { |gap_id| nonblank.call(gap_id) } && all_gap_ids.uniq.length == all_gap_ids.length
    if summary["coverage_complete"] == true
      valid &&= current_batch["batch_status"] == "complete" && complete_current_coverage
    else
      valid &&= %w[incomplete invalidated].include?(current_batch["batch_status"])
      valid &&= summary["coverage_gaps"].is_a?(Array) && summary["coverage_gaps"].any? { |gap| nonblank.call(gap) }
    end
    findings = summary["aggregated_findings"]
    fixed = summary["fixed_items"]
    closure_results = summary["closure_results"]
    aggregation = summary["aggregation_ledger"]
    remaining = summary["remaining_items"]
    material_findings = findings.is_a?(Array) ? findings.select { |finding| finding.is_a?(Hash) && %w[must-fix should-fix].include?(finding["severity"]) } : []
    material_remaining = remaining.is_a?(Array) ? remaining.select { |item| item.is_a?(Hash) && %w[must-fix should-fix].include?(item["severity"]) } : []
    normalized_provenance = lambda do |sources|
      Array(sources).map do |source|
        source.is_a?(Hash) ? source.slice("source_kind", "source_id") : {}
      end.sort_by { |source| [source["source_kind"].to_s, source["source_id"].to_s] }
    end
    review_pass_ids_from_provenance = lambda do |sources|
      Array(sources).select { |source| source.is_a?(Hash) && source["source_kind"] == "review_pass" }
        .map { |source| source["source_id"] }
    end
    review_pass_id_from_finding = lambda do |finding_id|
      match = finding_id.is_a?(String) ? /\Areview_pass:([^:]+):.+\z/.match(finding_id) : nil
      match && match[1]
    end
    namespaced_finding_id = lambda do |finding_id|
      finding_id.is_a?(String) && /\A(?:review_pass:[^:]+:.+|spec_review:.+)\z/.match?(finding_id)
    end
    review_pass_ids_from_findings = lambda do |source_ids|
      Array(source_ids).map { |finding_id| review_pass_id_from_finding.call(finding_id) }.compact
    end
    source_pass_alias_valid = lambda do |entry|
      next true unless entry.key?("source_pass_ids")
      aliases = entry["source_pass_ids"]
      expected = review_pass_ids_from_provenance.call(entry["source_provenance"])
      aliases.is_a?(Array) && aliases.all? { |source_id| nonblank.call(source_id) } && aliases.uniq.length == aliases.length && aliases.sort == expected.uniq.sort
    end
    if aggregation.is_a?(Array)
      finding_dispositions = %w[retained merged fixed_closed]
      nonfinding_dispositions = %w[observation rejected_invalid]
      finding_backed_entries = aggregation.select { |entry| entry.is_a?(Hash) && finding_dispositions.include?(entry["disposition"]) }
      valid &&= aggregation.all? do |entry|
        next false unless entry.is_a?(Hash)
        disposition = entry["disposition"]
        if finding_dispositions.include?(disposition)
          source_ids = entry["source_finding_ids"]
          source_ids.is_a?(Array) && !source_ids.empty? && source_ids.all? { |finding_id| namespaced_finding_id.call(finding_id) } &&
            source_ids.uniq.length == source_ids.length && nonblank.call(entry["aggregate_finding_id"]) && !entry.key?("source_coverage_gap_ids")
        elsif disposition == "coverage_gap"
          gap_ids = entry["source_coverage_gap_ids"]
          gap_ids.is_a?(Array) && !gap_ids.empty? && gap_ids.all? { |gap_id| nonblank.call(gap_id) } &&
            gap_ids.uniq.length == gap_ids.length && !entry.key?("source_finding_ids") && !entry.key?("aggregate_finding_id")
        elsif nonfinding_dispositions.include?(disposition)
          !entry.key?("source_finding_ids") && !entry.key?("source_coverage_gap_ids") && !entry.key?("aggregate_finding_id")
        else
          false
        end
      end
      finding_source_ids = finding_backed_entries.flat_map { |entry| entry["source_finding_ids"] }
      valid &&= finding_source_ids.uniq.length == finding_source_ids.length
    else
      valid = false
    end
    if fixed.is_a?(Array) && !fixed.empty?
      valid &&= topology["closure_verification_required"] == true && closure_passes.length == 1
      closure_pass_ids = closure_passes.map { |pass| pass["review_pass_id"] }
      closure_entries = current_ledger.select { |entry| closure_pass_ids.include?(entry["review_pass_id"]) }
      valid &&= !closure_entries.empty? && closure_entries.all? do |entry|
        entry["terminal_state"] == "completed" && entry["coverage_status"] == "complete" &&
          %w[inspected_no_risk finding].include?(entry["coverage_disposition"])
      end
      fixed_ids = fixed.map { |item| item.is_a?(Hash) ? item["aggregate_finding_id"] : nil }
      closure_ids = closure_results.is_a?(Array) ? closure_results.map { |item| item.is_a?(Hash) ? item["aggregate_finding_id"] : nil } : []
      fixed_ledger = aggregation.is_a?(Array) ? aggregation.select { |entry| entry.is_a?(Hash) && entry["disposition"] == "fixed_closed" } : []
      fixed_ledger_ids = fixed_ledger.map { |entry| entry["aggregate_finding_id"] }
      valid &&= fixed_ids.all? { |finding_id| nonblank.call(finding_id) } && fixed_ids.uniq.length == fixed_ids.length
      valid &&= closure_results.is_a?(Array) && !closure_results.empty? && closure_ids.all? { |finding_id| nonblank.call(finding_id) } && closure_ids.uniq.length == closure_ids.length
      valid &&= fixed_ledger_ids.all? { |finding_id| nonblank.call(finding_id) } && fixed_ledger_ids.uniq.length == fixed_ledger_ids.length
      valid &&= fixed_ledger.all? do |entry|
        source_ids = entry["source_finding_ids"]
        source_ids.is_a?(Array) && !source_ids.empty? && source_ids.all? { |finding_id| namespaced_finding_id.call(finding_id) } && source_ids.uniq.length == source_ids.length && source_pass_alias_valid.call(entry)
      end
      normalize_authority = lambda do |entries|
        Array(entries).map do |entry|
          {
            "aggregate_finding_id" => entry["aggregate_finding_id"],
            "source_finding_ids" => Array(entry["source_finding_ids"]).sort,
            "source_provenance" => Array(entry["source_provenance"]).map { |source| source.slice("source_kind", "source_id") }.sort_by { |source| [source["source_kind"].to_s, source["source_id"].to_s] }
          }
        end.sort_by { |entry| entry["aggregate_finding_id"].to_s }
      end
      valid &&= frozen_closure_authority.is_a?(Array) && !frozen_closure_authority.empty? && normalize_authority.call(fixed_ledger) == normalize_authority.call(frozen_closure_authority)
      valid &&= fixed_ids.sort == closure_ids.sort && fixed_ids.sort == fixed_ledger_ids.sort && closure_results.all? do |item|
        item.is_a?(Hash) && %w[verified_closed regressed incomplete].include?(item["status"]) && nonblank.call(item["evidence"])
      end
      finding_rows = findings.is_a?(Array) ? findings.select { |finding| finding.is_a?(Hash) } : []
      retained_ledger = aggregation.is_a?(Array) ? aggregation.select { |entry| entry.is_a?(Hash) && entry["disposition"] == "retained" } : []
      verified_ids = closure_results.select { |item| item["status"] == "verified_closed" }.map { |item| item["aggregate_finding_id"] }
      unclosed_ids = closure_results.select { |item| %w[regressed incomplete].include?(item["status"]) }.map { |item| item["aggregate_finding_id"] }
      valid &&= unclosed_ids.all? do |finding_id|
        matching_findings = finding_rows.select { |finding| finding["aggregate_finding_id"] == finding_id }
        matching_retained = retained_ledger.select { |entry| entry["aggregate_finding_id"] == finding_id }
        current_source_pass_ids = matching_findings.length == 1 ? review_pass_ids_from_findings.call(matching_findings.first["source_finding_ids"]) : []
        matching_findings.length == 1 && %w[must-fix should-fix].include?(matching_findings.first["severity"]) && matching_retained.length == 1 &&
          !(current_source_pass_ids & closure_pass_ids).empty?
      end
      valid &&= verified_ids.all? do |finding_id|
        finding_rows.none? { |finding| finding["aggregate_finding_id"] == finding_id } &&
          retained_ledger.none? { |entry| entry["aggregate_finding_id"] == finding_id }
      end
      if summary["result"] == "ISSUES_FIXED"
        valid &&= unclosed_ids.empty?
      elsif summary["result"] != "HAS_REMAINING_ITEMS"
        valid = false
      end
    else
      valid &&= !summary.key?("closure_results") || summary["closure_results"] == []
      valid &&= !aggregation.is_a?(Array) || aggregation.none? { |entry| entry.is_a?(Hash) && entry["disposition"] == "fixed_closed" }
    end
    case summary["result"]
    when "CLEAN"
      valid &&= summary["coverage_complete"] == true && current_batch["batch_status"] == "complete"
      valid &&= findings.is_a?(Array) && material_findings.empty? && fixed.is_a?(Array) && fixed.empty?
      valid &&= material_remaining.empty? && (!summary.key?("coverage_gaps") || summary["coverage_gaps"] == [])
      valid &&= summary["evidence_bounded_claim"] == "No material findings within the reviewed scope and available evidence"
    when "ISSUES_FIXED"
      valid &&= summary["coverage_complete"] == true && current_batch["batch_status"] == "complete"
      valid &&= findings.is_a?(Array) && material_findings.empty? && fixed.is_a?(Array) && !fixed.empty?
      valid &&= material_remaining.empty? && (!summary.key?("coverage_gaps") || summary["coverage_gaps"] == [])
      valid &&= summary["evidence_bounded_claim"] == "No material findings within the reviewed scope and available evidence"
    when "HAS_REMAINING_ITEMS"
      valid &&= summary["coverage_complete"] == false || !material_findings.empty? || !material_remaining.empty?
      valid &&= !summary.key?("evidence_bounded_claim")
    else
      valid = false
    end
    if findings.is_a?(Array) && aggregation.is_a?(Array)
      aggregate_ids = findings.map { |finding| finding["aggregate_finding_id"] }
      retained = aggregation.select { |entry| %w[retained merged].include?(entry["disposition"]) }
      retained_ids = retained.map { |entry| entry["aggregate_finding_id"] }
      valid &&= aggregate_ids.all? { |aggregate_id| nonblank.call(aggregate_id) } && aggregate_ids.uniq.length == aggregate_ids.length
      valid &&= retained_ids.all? { |aggregate_id| nonblank.call(aggregate_id) } && retained_ids.uniq.length == retained_ids.length && retained_ids.sort == aggregate_ids.sort
      valid &&= findings.all? do |finding|
        source_ids = finding["source_finding_ids"]
        matching_ledger = retained.select { |entry| entry["aggregate_finding_id"] == finding["aggregate_finding_id"] }
        ledger_entry = matching_ledger.first
        ledger_source_ids = ledger_entry ? Array(ledger_entry["source_finding_ids"]) : []
        review_source_pass_ids = review_pass_ids_from_findings.call(source_ids)
        provenance_pass_ids = review_pass_ids_from_provenance.call(finding["source_provenance"])
        review_source_ids_resolve = Array(source_ids).all? do |source_id|
          pass_id = review_pass_id_from_finding.call(source_id)
          !pass_id || current_ledger.any? { |entry| entry["review_pass_id"] == pass_id && Array(entry["finding_ids"]).include?(source_id) }
        end
        source_ids.is_a?(Array) && !source_ids.empty? && source_ids.all? { |source_id| namespaced_finding_id.call(source_id) } && source_ids.uniq.length == source_ids.length && namespaced_finding_id.call(finding["finding_id"]) && source_ids.include?(finding["finding_id"]) && matching_ledger.length == 1 &&
          ledger_source_ids.sort == source_ids.sort && normalized_provenance.call(ledger_entry["source_provenance"]) == normalized_provenance.call(finding["source_provenance"]) &&
          review_source_pass_ids.uniq.sort == provenance_pass_ids.uniq.sort && review_source_ids_resolve &&
          source_pass_alias_valid.call(finding) && source_pass_alias_valid.call(ledger_entry)
      end
      coverage_finding_ids = ledger.select { |entry| entry["coverage_disposition"] == "finding" }.flat_map { |entry| entry["finding_ids"] || [] }
      aggregate_source_ids = findings.flat_map { |finding| finding["source_finding_ids"] || [] }
      valid &&= coverage_finding_ids.all? { |finding_id| aggregate_source_ids.include?(finding_id) }
      review_pass_aggregate_source_ids = retained.select do |entry|
        (entry["source_provenance"] || []).any? { |source| source.is_a?(Hash) && source["source_kind"] == "review_pass" }
      end.flat_map { |entry| entry["source_finding_ids"] || [] }
      valid &&= review_pass_aggregate_source_ids.all? { |finding_id| coverage_finding_ids.include?(finding_id) }
      coverage_gap_dispositions = aggregation.select { |entry| entry["disposition"] == "coverage_gap" }
      aggregated_gap_ids = coverage_gap_dispositions.flat_map { |entry| entry["source_coverage_gap_ids"] || [] }
      valid &&= aggregation.all? { |entry| entry.is_a?(Hash) && source_pass_alias_valid.call(entry) }
      valid &&= coverage_gap_dispositions.all? do |entry|
        ids = entry["source_coverage_gap_ids"]
        gap_rows = ids.is_a?(Array) ? current_gap_entries.select { |gap| ids.include?(gap["coverage_gap_id"]) } : []
        gap_owner_ids = gap_rows.map { |gap| gap["review_pass_id"] }
        provenance = Array(entry["source_provenance"])
        provenance_pass_ids = review_pass_ids_from_provenance.call(provenance)
        ids.is_a?(Array) && !ids.empty? && ids.all? { |gap_id| nonblank.call(gap_id) } && ids.uniq.length == ids.length &&
          gap_rows.length == ids.length && gap_owner_ids.all? { |pass_id| nonblank.call(pass_id) } && gap_owner_ids.uniq.sort == provenance_pass_ids.uniq.sort &&
          provenance.all? { |source| source.is_a?(Hash) && source["source_kind"] == "review_pass" }
      end
      valid &&= aggregated_gap_ids.uniq.length == aggregated_gap_ids.length && aggregated_gap_ids.sort == current_gap_ids.sort

      required_distillation_ids = (
        findings.select { |finding| finding["severity"] == "must-fix" }.map { |finding| finding["aggregate_finding_id"] } +
        fixed.select { |item| item.is_a?(Hash) && item["severity"] == "must-fix" }.map { |item| item["aggregate_finding_id"] }
      ).uniq
      canonical_distillation_ids = (
        findings.map { |finding| finding["aggregate_finding_id"] } +
        fixed.select { |item| item.is_a?(Hash) }.map { |item| item["aggregate_finding_id"] }
      ).uniq
      if explicit_artifact_name.empty?
        distillation_authority = fixture.dig("canonical_review_finding_rule_distillation_expectations", case_id)
        if distillation_authority
          expected_active_ids = distillation_authority["active_must_fix_aggregate_finding_ids"]
          expected_fixed_ids = distillation_authority["fixed_must_fix_aggregate_finding_ids"]
          actual_active_ids = findings.select { |finding| finding["severity"] == "must-fix" }.map { |finding| finding["aggregate_finding_id"] }
          actual_fixed_ids = fixed.select { |item| item.is_a?(Hash) && item["severity"] == "must-fix" }.map { |item| item["aggregate_finding_id"] }
          valid &&= expected_active_ids.is_a?(Array) && expected_fixed_ids.is_a?(Array) &&
            actual_active_ids.sort == expected_active_ids.sort && actual_fixed_ids.sort == expected_fixed_ids.sort &&
            required_distillation_ids.sort == (expected_active_ids + expected_fixed_ids).uniq.sort
        end
        distillation = outer_response["review_finding_rule_distillation"]
        required_fields = %w[finding evidence failure_pattern classification rule_target proposed_rule verification_eval_update scope_and_exclusions promotion_decision]
        if distillation
          valid &&= distillation.is_a?(Array) && distillation.all? do |entry|
            entry.is_a?(Hash) && entry.keys.sort == required_fields.sort &&
              required_fields.select { |field| !%w[classification rule_target promotion_decision].include?(field) }.all? { |field| nonblank.call(entry[field]) } &&
              %w[one_off_fix permanent_rule_candidate no_action].include?(entry["classification"]) &&
              %w[checklist input_contract output_contract phase_gate handoff eval template skill_reference none].include?(entry["rule_target"]) &&
              %w[promote defer reject].include?(entry["promotion_decision"])
          end
          distillation_ids = distillation.is_a?(Array) ? distillation.map { |entry| entry["finding"] } : []
          valid &&= distillation_ids.all? { |finding_id| canonical_distillation_ids.include?(finding_id) } &&
            distillation_ids.uniq.length == distillation_ids.length &&
            required_distillation_ids.all? { |finding_id| distillation_ids.include?(finding_id) }
        else
          valid &&= required_distillation_ids.empty?
        end
      end
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
    if explicit_artifact_name.empty? && audit_required
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
    expected_obligation_present = frozen_deferred_qa_obligation_authority || %w[requested_scope execution_prerequisite feature_preparation_scope source_feature_preparation_evidence_ref source_preparation_basis].any? { |field| !expected_obligation_value.call(field).nil? }
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
      if frozen_deferred_qa_obligation_authority
        authority_fields = %w[requested_scope execution_prerequisite feature_preparation_scope source_feature_preparation_evidence_ref source_preparation_basis]
        carried_obligation = outer_response["approved_feature_preparation_qa_acceptance_obligation"]
        if deferred_qa_obligation_authority_valid.call(frozen_deferred_qa_obligation_authority)
          valid &&= carried_obligation == frozen_deferred_qa_obligation_authority
          valid &&= authority_fields.all? do |field|
            obligation.key?(field) == frozen_deferred_qa_obligation_authority.key?(field) && obligation[field] == frozen_deferred_qa_obligation_authority[field]
          end
        else
          valid = false
        end
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

assistant_review_delegation_path_semantics_valid() {
    local response_path="$1"
    local artifact_name="$2"
    local response_root="${3:-}"

    jq -e --arg artifact_name "$artifact_name" --arg response_root "$response_root" '
      def nonblank: type == "string" and test("[^[:space:]]");
      def delegation_valid($artifact_name):
        . as $artifact
        | ($artifact | type == "object")
        and ($artifact.fresh_context_evidence | nonblank)
        and ($artifact.subagent_trigger_scope | type == "array" and all(.[]; nonblank) and length == (unique | length))
        and (if $artifact.subagent_policy_state == "delegation_triggered" then
               ($artifact.subagent_trigger_scope | length > 0) and $artifact.subagent_execution_mode == "delegated" and ($artifact | has("policy_blocking_source") | not)
             elif ($artifact.subagent_policy_state == "delegation_opted_out" or $artifact.subagent_policy_state == "subagents_unavailable") then
               ($artifact.subagent_trigger_scope | length > 0) and $artifact.subagent_execution_mode == "direct_fallback" and ($artifact | has("policy_blocking_source") | not)
             elif $artifact.subagent_policy_state == "policy_disallowed" then
               ($artifact.subagent_trigger_scope | length > 0) and $artifact.subagent_execution_mode == "direct_fallback" and ($artifact.policy_blocking_source | nonblank)
             elif $artifact.subagent_policy_state == "not_required" then
               (if $artifact_name == "review_delegation_path" then
                  $artifact.subagent_execution_mode == "direct_fallback" and ($artifact.subagent_trigger_scope | length == 0)
                else
                  $artifact.subagent_execution_mode == "not_applicable" and ($artifact.subagent_trigger_scope | length == 0)
                end) and ($artifact | has("policy_blocking_source") | not)
             else false end);
      if $response_root == "" then .[$artifact_name] else .[$response_root].artifact end | delegation_valid($artifact_name)
    ' "$response_path" >/dev/null
}

assistant_review_external_alias_envelopes_valid() {
    local response_path="$1"
    local fixture_file="$2"
    local id="$3"
    local alias_name
    local artifact_name
    local expected_contract
    local producer_schema_version
    local producer_contract_root
    local required_alias

    required_alias="$(jq -r --arg id "$id" '.canonical_review_batch_expectations.case_requirements?[$id].required_envelope_alias? // empty' "$fixture_file")"
    if [[ -n "$required_alias" ]]; then
        jq -e --arg alias_name "$required_alias" 'type == "object" and has($alias_name)' "$response_path" >/dev/null 2>&1 || return 1
    fi

    # Only structured responses that actually project an assistant-review
    # producer envelope are in this validator's domain.
    jq -e 'type == "object"' "$response_path" >/dev/null 2>&1 || return 0
    jq -e '. as $response | ["canonical_final_summary", "fresh_canonical_final_summary", "canonical_qa_result", "current_canonical_qa_result", "prior_canonical_qa_result", "current_qa_delegation_path", "current_review_delegation_path"] | any(.[]; . as $name | $response | has($name))' "$response_path" >/dev/null || return 0

    producer_contract_root="${REPO_ROOT:-${FRAMEWORK_DIR:-}}"
    [[ -n "$producer_contract_root" ]] || return 1
    producer_schema_version="$(ruby -ryaml -e 'value = YAML.load_file(ARGV.fetch(0)).fetch("schema_version"); abort unless value.is_a?(String) && !value.strip.empty?; print value' "$producer_contract_root/skills/assistant-review/contracts/index.yaml")" || return 1

    jq -e --arg producer_schema_version "$producer_schema_version" '
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
      and wrapper_valid("current_review_delegation_path"; "assistant-review/contracts/output.yaml#review_delegation_path")
      and (.current_assistant_review_contract | type == "object" and .schema_version == $producer_schema_version)
      and ([.review_result?, .fresh_review_result?, .qa_evaluation_result?]
        | all(.[]; if type == "object" then .producer_schema_version == $producer_schema_version else true end))
      and (if (.final_handoff.review_completion? | type) == "object" then
          (.final_handoff.review_completion.review_producer_schema_version == $producer_schema_version)
          and (if .final_handoff.review_completion | has("qa_producer_schema_version") then
            .final_handoff.review_completion.qa_producer_schema_version == $producer_schema_version
          else true end)
        else true end)
      and (. as $response | [ $response.review_result?, $response.fresh_review_result? ]
        | all(.[]; if type == "object" and has("delegation_path_ref") then
            ($response | has("current_review_delegation_path"))
            and (.delegation_path_ref == $response.current_review_delegation_path.ref)
            and (.delegation_contract == $response.current_review_delegation_path.contract)
          else true end))
    ' "$response_path" >/dev/null || return 1

    while IFS='|' read -r alias_name artifact_name; do
        jq -e --arg alias_name "$alias_name" 'has($alias_name)' "$response_path" >/dev/null || continue
        expected_contract="assistant-review/contracts/output.yaml#$artifact_name"
        jq -e --arg alias_name "$alias_name" --arg expected_contract "$expected_contract" '.[$alias_name].contract == $expected_contract' "$response_path" >/dev/null || return 1
        assistant_review_artifact_schema_valid "external-producer-envelope" "$response_path" "$artifact_name" "$alias_name" "$fixture_file" || return 1
        case "$artifact_name" in
            final_summary|qa_evaluation_result)
                assistant_review_lifecycle_semantics_valid "$id" "$response_path" "$artifact_name" "$alias_name" "$fixture_file" || return 1
                ;;
            review_delegation_path|qa_evaluation_delegation_path)
                assistant_review_delegation_path_semantics_valid "$response_path" "$artifact_name" "$alias_name" || return 1
                ;;
        esac
    done <<'EOF_ASSISTANT_REVIEW_EXTERNAL_ALIASES'
canonical_final_summary|final_summary
fresh_canonical_final_summary|final_summary
canonical_qa_result|qa_evaluation_result
current_canonical_qa_result|qa_evaluation_result
prior_canonical_qa_result|qa_evaluation_result
current_qa_delegation_path|qa_evaluation_delegation_path
current_review_delegation_path|review_delegation_path
EOF_ASSISTANT_REVIEW_EXTERNAL_ALIASES
}

count_assistant_review_canonical_envelope_failures() {
    local skill_name="$1"
    local id="$2"
    local response_path="$3"
    local fixture_file="$4"

    if [[ "$skill_name" == "assistant-workflow" ]]; then
        if assistant_review_external_alias_envelopes_valid "$response_path" "$fixture_file" "$id"; then
            printf '0\n'
        else
            printf '1\n'
        fi
        return
    fi

    [[ "$skill_name" == "assistant-review" ]] || { printf '0\n'; return; }

    local mapped_final_case
    local required_audit_report
    local required_qa_case
    local required_qa_delegation
    mapped_final_case="$(jq -r --arg id "$id" '(.canonical_review_batch_expectations.case_template_refs? // {}) | has($id)' "$fixture_file")"
    required_audit_report="$(jq -r --arg id "$id" '(.canonical_review_batch_expectations.case_requirements?[$id].required_artifacts? // []) | index("audit_report") != null' "$fixture_file")"
    required_qa_case="$(jq -r --arg id "$id" '(.canonical_qa_case_requirements? // {}) | has($id)' "$fixture_file")"
    required_qa_delegation="$(jq -r --arg id "$id" '(.canonical_qa_case_requirements?[$id].required_artifacts? // []) | index("qa_evaluation_delegation_path") != null' "$fixture_file")"
    [[ "$mapped_final_case" == true || "$required_qa_case" == true ]] || { printf '0\n'; return; }

    if jq -e --arg id "$id" --argjson mapped_final_case "$mapped_final_case" --argjson required_audit_report "$required_audit_report" --argjson required_qa_case "$required_qa_case" '
        def required_fields($fields):
          . as $object | type == "object" and (($fields - ($object | keys)) | length == 0);
        def final_summary_valid:
          . as $response
          | (.final_summary | required_fields(["reviewed_scope", "rounds", "final_review_snapshot_id", "final_snapshot_identity", "coverage_complete", "final_batch_plan", "coverage_ledger", "batch_summaries", "aggregation_ledger", "aggregated_findings", "result", "fixed_items", "nits"]))
          and (.final_summary.reviewed_scope | type == "array" and length > 0)
          and (.final_summary.rounds | type == "number")
          and (.final_summary.final_review_snapshot_id | type == "string")
          and (.final_summary.final_snapshot_identity | required_fields(["basis", "value", "captured_at", "scope_manifest_digest"])
            and (.basis as $basis | ["git_revision", "diff_digest", "content_digest", "task_or_pr_revision"] | index($basis)))
          and (.final_summary.coverage_complete | type == "boolean")
          and (.final_summary.final_batch_plan | required_fields(["batch_id", "review_snapshot_id", "topology", "expected_passes"])
            and (.topology | required_fields(["discovery_pass_count", "canonical_discovery_perspectives", "security_specialist_triggered", "closure_verification_required", "max_required_responses", "max_repair_attempts_per_pass"]))
            and (.expected_passes | type == "array" and length >= 2 and length <= 6)
            and all(.expected_passes[]; required_fields(["review_pass_id", "perspective", "assigned_scope", "coverage_obligations", "prior_finding_visibility"])))
          and (.final_summary.coverage_ledger | type == "array" and length > 0)
          and all(.final_summary.coverage_ledger[]; required_fields(["batch_id", "review_snapshot_id", "review_pass_id", "perspective", "coverage_obligation", "assigned_scope", "scope_item_id", "applicable_concern", "terminal_state", "coverage_status", "coverage_disposition", "evidence"])
            and (.terminal_state as $terminal_state | ["completed", "needs_context", "blocked", "timed_out", "failed", "invalidated"] | index($terminal_state))
            and (.coverage_status as $coverage_status | ["complete", "incomplete", "invalidated"] | index($coverage_status))
            and (.coverage_disposition as $coverage_disposition | ["inspected_no_risk", "finding", "incomplete"] | index($coverage_disposition))
            and (if .coverage_disposition == "finding" then (.finding_ids | type == "array" and length > 0) else has("finding_ids") | not end)
            and (if (.coverage_status == "incomplete" or .coverage_status == "invalidated") then (.coverage_gap_id | type == "string" and length > 0) else has("coverage_gap_id") | not end))
          and (.final_summary.batch_summaries | type == "array" and length > 0)
          and all(.final_summary.batch_summaries[]; required_fields(["started_batch_ordinal", "batch_id", "review_snapshot_id", "batch_status", "expected_response_count", "terminal_response_count", "aggregate_rubric_recomputed"])
            and (.batch_status as $batch_status | ["complete", "incomplete", "invalidated"] | index($batch_status)))
          and (.final_summary.aggregation_ledger | type == "array")
          and all(.final_summary.aggregation_ledger[]; required_fields(["source_provenance", "disposition", "rationale"])
            and (.disposition as $disposition | ["retained", "merged", "fixed_closed", "observation", "rejected_invalid", "coverage_gap"] | index($disposition)))
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
        if $required_qa_case then qa_result_valid
        elif $mapped_final_case then
          final_summary_valid
          and (if $required_audit_report then audit_report_valid and (.final_summary.fixed_items == []) else true end)
        else false end
    ' "$response_path" >/dev/null \
        && assistant_review_artifact_schema_valid "$id" "$response_path" "" "" "$fixture_file" \
        && assistant_review_lifecycle_semantics_valid "$id" "$response_path" "" "" "$fixture_file" \
        && { ! jq -e 'has("review_delegation_path")' "$response_path" >/dev/null || assistant_review_delegation_path_semantics_valid "$response_path" "review_delegation_path"; } \
        && { [[ "$required_qa_delegation" != true ]] || assistant_review_delegation_path_semantics_valid "$response_path" "qa_evaluation_delegation_path"; }; then
        printf '0\n'
    else
        printf '1\n'
    fi
}

canonical_feature_preparation_result_authority_valid() {
    local skill_name="$1"
    local fixture_file="$2"
    local id="$3"
    local response_path="$4"
    local authority

    [[ "$skill_name" == "assistant-workflow" ]] || return 0
    authority="$(jq -c --arg id "$id" '.canonical_feature_preparation_result_expectations?[$id] // empty' "$fixture_file")"
    [[ -n "$authority" ]] || return 0

    jq -e --argjson authority "$authority" '
        .approved_feature_preparation_result == $authority
        and .triage_result.approved_feature_preparation_result == $authority
        and (.implementation_steps | type == "array" and length > 0)
        and all(.implementation_steps[]; type == "object" and .approved_feature_preparation_result == $authority)
    ' "$response_path" >/dev/null
}

count_structured_json_assertion_failures() {
    local fixture_file="$1"
    local id="$2"
    local response_path="$3"
    local skill_name="${4:-}"
    local assertion
    local structured_assertion_count
    local failures=0

    if [[ -z "$skill_name" ]]; then
        skill_name="$(jq -r 'if (.skill | type) == "string" then .skill elif (.skill | type) == "object" then .skill.name // .skill_name // empty else .skill_name // empty end' "$fixture_file")"
    fi

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

    if ! canonical_feature_preparation_result_authority_valid "$skill_name" "$fixture_file" "$id" "$response_path"; then
        failures=$((failures + 1))
    fi

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
    local semantic_validation_failures=0
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
    local semantic_validator
    local semantic_failures
    local status
    local reason
    local selected_cases

    echo "Heuristic/local grading only. Deterministic substring checks are local proxies; no provider API is invoked."
    echo ""

    validate_selected_case_ids
    selected_cases="$(selected_case_ids_json)"

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
                structured_failures="$(count_structured_json_assertion_failures "$fixture_file" "$id" "$response_path" "$skill_name")"
                canonical_envelope_failures="$(count_assistant_review_canonical_envelope_failures "$skill_name" "$id" "$response_path" "$fixture_file")"
                structured_failures=$((structured_failures + canonical_envelope_failures))
                semantic_validator="$(semantic_validator_id_for_case "$fixture_file" "$id")"
                semantic_failures=0
                if [[ -n "$semantic_validator" ]] && ! run_semantic_validator "$semantic_validator" "$response_path"; then
                    semantic_failures=1
                fi
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
                if [[ "$semantic_failures" -gt 0 ]]; then
                    if [[ "$status" == "FAIL" ]]; then
                        reason="$reason; semantic validator failed"
                    else
                        status="FAIL"
                        reason="semantic validator failed"
                    fi
                    semantic_validation_failures=$((semantic_validation_failures + semantic_failures))
                fi
            fi

            if [[ "$status" == "PASS" ]]; then
                passed=$((passed + 1))
            else
                failed=$((failed + 1))
            fi

            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$status" "$skill_name" "$id" "$category" "$title" "$reason"
        done < <(jq -r --argjson selected_cases "$selected_cases" '
            .cases[]
            | .id as $id
            | select(($selected_cases | length) == 0 or ($selected_cases | index($id)) != null)
            | [.id, .category, .title]
            | @tsv
        ' "$fixture_file")
    done

    echo ""
    printf 'Summary: total=%s passed=%s failed=%s missing=%s empty=%s fail_signal_hits=%s missing_required_substrings=%s forbidden_substring_hits=%s ordered_substring_failures=%s seeded_defect_failures=%s false_positive_marker_failures=%s structured_json_assertion_failures=%s semantic_validation_failures=%s skills=%s\n' \
        "$total" "$passed" "$failed" "$missing" "$empty" "$signal_failures" "$missing_required_failures" "$forbidden_substring_failures" "$ordered_substring_failures" "$seeded_defect_failures" "$false_positive_marker_failures" "$structured_json_assertion_failures" "$semantic_validation_failures" "${#FIXTURE_FILES[@]}"

    [[ "$failed" -eq 0 ]]
}
