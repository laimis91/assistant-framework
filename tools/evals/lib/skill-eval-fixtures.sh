validate_assertion_contract_paths() {
    local fixture_file="$1"
    local skill_name="$2"
    local contracts_dir
    local contract_error

    contracts_dir="$(cd "$(dirname "$fixture_file")/.." && pwd)/contracts"
    [[ -d "$contracts_dir" ]] || return 0

    contract_error="$(ruby -rjson -ryaml - "$fixture_file" "$skill_name" "$contracts_dir" "$REPO_ROOT" 2>&1 <<'RUBY'
fixture = JSON.parse(File.read(ARGV.fetch(0)))
skill_name = ARGV.fetch(1)
contracts_dir = ARGV.fetch(2)
repo_root = ARGV.fetch(3)

roots = Hash.new { |hash, key| hash[key] = [] }
add_root = lambda do |field|
  roots[field.fetch("name")] << field if field.is_a?(Hash) && field["name"].is_a?(String)
end

load_contract_roots = lambda do |directory, include_non_output_roots|
  output_path = File.join(directory, "output.yaml")
  YAML.load_file(output_path).fetch("artifacts", []).each { |artifact| add_root.call(artifact) } if File.file?(output_path)
  next unless include_non_output_roots

  input_path = File.join(directory, "input.yaml")
  YAML.load_file(input_path).fetch("fields", []).each { |field| add_root.call(field) } if File.file?(input_path)

  handoffs_path = File.join(directory, "handoffs.yaml")
  next unless File.file?(handoffs_path)

  walk_handoffs = lambda do |node|
    case node
    when Hash
      node.each do |key, value|
        if %w[context_fields return_fields].include?(key) && value.is_a?(Array)
          value.each { |field| add_root.call(field) }
        else
          walk_handoffs.call(value)
        end
      end
    when Array
      node.each { |value| walk_handoffs.call(value) }
    end
  end
  walk_handoffs.call(YAML.load_file(handoffs_path))
end

load_contract_roots.call(contracts_dir, skill_name == "assistant-review")

# Explicitly bounded roots that eval fixtures may project outside their output
# artifacts. This is deliberately not a pool of every input or handoff field.
eval_only_root_registry = {
  "assistant-docs" => [
    { "kind" => "input_field", "name" => "architecture_decision_pack_status" },
    { "kind" => "input_field", "name" => "architecture_design_mode" },
    { "kind" => "input_field", "name" => "feature_preparation_evidence_status" },
    { "kind" => "input_field", "name" => "feature_preparation_scope" }
  ],
  "assistant-workflow" => [
    { "kind" => "input_field", "name" => "approved_feature_preparation_evidence_ref" },
    { "kind" => "input_field", "name" => "approved_feature_preparation_harness_obligation" },
    { "kind" => "input_field", "name" => "approved_feature_preparation_qa_acceptance_obligation" },
    { "kind" => "input_field", "name" => "architecture_design_mode" },
    { "kind" => "input_field", "name" => "execution_intent" },
    { "kind" => "input_field", "name" => "feature_preparation_scope" },
    { "kind" => "handoff_field", "name" => "architecture_mapping_evidence" },
    { "kind" => "handoff_field", "name" => "implementation_steps" },
    { "kind" => "output_child", "artifact" => "triage_result", "name" => "size" }
  ]
}

find_named_fields = lambda do |node, name, matches|
  case node
  when Hash
    matches << node if node["name"] == name
    node.each_value { |value| find_named_fields.call(value, name, matches) }
  when Array
    node.each { |value| find_named_fields.call(value, name, matches) }
  end
end

eval_only_root_registry.fetch(skill_name, []).each do |selector|
  selected = case selector.fetch("kind")
             when "input_field"
               input = YAML.load_file(File.join(contracts_dir, "input.yaml"))
               input.fetch("fields", []).select { |field| field["name"] == selector.fetch("name") }
             when "handoff_field"
               matches = []
               find_named_fields.call(YAML.load_file(File.join(contracts_dir, "handoffs.yaml")), selector.fetch("name"), matches)
               matches
             when "output_child"
               output = YAML.load_file(File.join(contracts_dir, "output.yaml"))
               artifact = output.fetch("artifacts", []).find { |field| field["name"] == selector.fetch("artifact") }
               artifact ? artifact.fetch("object_fields", []).select { |field| field["name"] == selector.fetch("name") } : []
             else
               []
             end
  unless selected.length == 1
    warn "eval-only root registry selector must resolve exactly once: #{selector.to_json}"
    exit 1
  end
  add_root.call(selected.first)
end

final_snapshot_identity_schema = {
  "name" => "final_snapshot_identity",
  "type" => "object",
  "required" => true,
  "object_fields" => [
    { "name" => "basis", "type" => "enum", "required" => true, "enum_values" => %w[git_revision diff_digest content_digest task_or_pr_revision] },
    { "name" => "value", "type" => "string", "required" => true },
    { "name" => "captured_at", "type" => "string", "required" => true },
    { "name" => "scope_manifest_digest", "type" => "string", "required" => true }
  ]
}
inline_eval_only_roots = {
  "assistant-workflow" => [
    { "name" => "current_assistant_review_contract", "type" => "object", "required" => false, "object_fields" => [{ "name" => "schema_version", "type" => "enum", "required" => true, "enum_values" => ["7.1"] }] },
    { "name" => "current_final_batch", "type" => "object", "required" => false, "object_fields" => [{ "name" => "review_snapshot_id", "type" => "string", "required" => true }, final_snapshot_identity_schema] },
    { "name" => "harness_entry_state", "type" => "object", "required" => false },
    {
      "name" => "plan", "type" => "object", "required" => false,
      "object_fields" => [
        { "name" => "tier", "type" => "enum", "required" => true, "enum_values" => %w[small medium large mega] },
        {
          "name" => "triage_result", "type" => "object", "required" => true,
          "object_fields" => [
            { "name" => "qa_evaluation_mode", "type" => "enum", "required" => true, "enum_values" => %w[not_required required] },
            { "name" => "harness_capable", "type" => "boolean", "required" => true },
            { "name" => "build_execution_lane", "type" => "enum", "required" => true, "enum_values" => %w[bounded_executor separated_workers] },
            { "name" => "workflow_state_mode", "type" => "enum", "required" => true, "enum_values" => %w[inline journal] }
          ]
        }
      ]
    },
    {
      "name" => "post_fix_build_validation", "type" => "object", "required" => false,
      "object_fields" => [
        { "name" => "ref", "type" => "string", "required" => true },
        { "name" => "status", "type" => "enum", "required" => true, "enum_values" => ["passed"] },
        { "name" => "source_digest", "type" => "string", "required" => true },
        { "name" => "evidence", "type" => "string", "required" => true }
      ]
    },
    {
      "name" => "post_rejection_digest_evidence", "type" => "object", "required" => false,
      "object_fields" => [
        { "name" => "ref", "type" => "string", "required" => true },
        { "name" => "comparison", "type" => "enum", "required" => true, "enum_values" => %w[changed equal] },
        { "name" => "pre_fix_source_digest", "type" => "string", "required" => true },
        { "name" => "post_fix_source_digest", "type" => "string", "required" => true },
        final_snapshot_identity_schema.merge("name" => "post_fix_snapshot_identity", "required" => false)
      ]
    },
    { "name" => "task_packet", "type" => "object", "required" => false },
    { "name" => "task_packets", "type" => "object[]", "required" => false },
    {
      "name" => "validation_result", "type" => "object", "required" => false,
      "object_fields" => [
        { "name" => "status", "type" => "enum", "required" => true, "enum_values" => ["blocked"] },
        { "name" => "missing_field", "type" => "string", "required" => true },
        { "name" => "evidence_or_gap", "type" => "string", "required" => true }
      ]
    },
    { "name" => "workflow_complete", "type" => "enum", "required" => false, "enum_values" => ["--- WORKFLOW COMPLETE ---"] }
  ]
}
inline_eval_only_roots.fetch(skill_name, []).each { |field| add_root.call(field) }

external_producer_root_aliases = {
  "assistant-workflow" => {
    "canonical_final_summary" => { "producer_skill" => "assistant-review", "artifact" => "final_summary", "absent_paths" => [["artifact", "canonical_result_ref"], ["artifact", "canonical_contract"], ["artifact", "final_snapshot_identity_ref"], ["artifact", "approved_feature_preparation_qa_acceptance_obligation_result_ref"]] },
    "fresh_canonical_final_summary" => { "producer_skill" => "assistant-review", "artifact" => "final_summary", "absent_paths" => [["artifact", "canonical_result_ref"], ["artifact", "canonical_contract"], ["artifact", "final_snapshot_identity_ref"], ["artifact", "approved_feature_preparation_qa_acceptance_obligation_result_ref"]] },
    "canonical_qa_result" => { "producer_skill" => "assistant-review", "artifact" => "qa_evaluation_result", "absent_paths" => [["artifact", "canonical_result_ref"], ["artifact", "canonical_contract"], ["artifact", "final_snapshot_identity_ref"], ["artifact", "approved_feature_preparation_qa_acceptance_obligation_result_ref"]] },
    "current_canonical_qa_result" => { "producer_skill" => "assistant-review", "artifact" => "qa_evaluation_result", "absent_paths" => [["artifact", "canonical_result_ref"], ["artifact", "canonical_contract"], ["artifact", "final_snapshot_identity_ref"], ["artifact", "approved_feature_preparation_qa_acceptance_obligation_result_ref"]] },
    "prior_canonical_qa_result" => { "producer_skill" => "assistant-review", "artifact" => "qa_evaluation_result", "absent_paths" => [["artifact", "canonical_result_ref"], ["artifact", "canonical_contract"], ["artifact", "final_snapshot_identity_ref"], ["artifact", "approved_feature_preparation_qa_acceptance_obligation_result_ref"]] },
    "current_qa_delegation_path" => { "producer_skill" => "assistant-review", "artifact" => "qa_evaluation_delegation_path", "absent_paths" => [] },
    "current_review_delegation_path" => { "producer_skill" => "assistant-review", "artifact" => "review_delegation_path", "absent_paths" => [] }
  }
}
external_absent_paths = Hash.new { |hash, key| hash[key] = [] }

wrap_external_artifact = lambda do |name, artifact|
  {
    "name" => name,
    "type" => "object",
    "object_fields" => [
      { "name" => "ref", "type" => "string", "required" => true },
      { "name" => "contract", "type" => "string", "required" => true },
      {
        "name" => "artifact",
        "type" => artifact.fetch("type", "object"),
        "required" => true,
        "object_fields" => artifact.fetch("object_fields", [])
      }
    ]
  }
end

external_producer_root_aliases.fetch(skill_name, {}).each do |alias_name, alias_config|
  producer_skill = alias_config.fetch("producer_skill")
  artifact_name = alias_config.fetch("artifact")
  producer_output = File.join(repo_root, "skills", producer_skill, "contracts", "output.yaml")
  next unless File.file?(producer_output)

  artifact = YAML.load_file(producer_output).fetch("artifacts", []).find { |item| item["name"] == artifact_name }
  if artifact.is_a?(Hash)
    add_root.call(wrap_external_artifact.call(alias_name, artifact))
    external_absent_paths[alias_name] = alias_config.fetch("absent_paths")
  end
end

resolve = lambda do |path|
  candidates = roots[path.first]
  return [] if candidates.empty?

  path.drop(1).each do |segment|
    candidates = candidates.flat_map do |field|
      if segment.is_a?(Numeric)
        field["type"].is_a?(String) && field["type"].end_with?("[]") ? [field] : []
      elsif segment.is_a?(String)
        field.fetch("object_fields", []).select { |child| child["name"] == segment }
      else
        []
      end
    end
    break if candidates.empty?
  end
  candidates
end

path_operands = lambda do |assertion|
  operands = [["path", assertion["path"]]]
  operands << ["other_path", assertion["other_path"]] if assertion.key?("other_path")
  operands << ["when_path", assertion["when_path"]] if assertion.key?("when_path")
  operands << ["field", assertion["path"] + [0, assertion["field"]]] if assertion["field"].is_a?(String) && assertion["path"].is_a?(Array)
  if assertion["fields"].is_a?(Array) && assertion["path"].is_a?(Array)
    assertion["fields"].each { |field| operands << ["fields", assertion["path"] + [0, field]] if field.is_a?(String) }
  end
  if assertion["expected_objects"].is_a?(Array) && assertion["path"].is_a?(Array)
    assertion["expected_objects"].each do |object|
      object.each_key { |field| operands << ["expected_objects", assertion["path"] + [0, field]] } if object.is_a?(Hash)
    end
  end
  operands
end

literal_valid = lambda do |field, value|
  case field["type"]
  when "string", "file", "jsonl_line" then value.is_a?(String)
  when "int" then value.is_a?(Integer)
  when "float" then value.is_a?(Numeric)
  when "boolean" then value == true || value == false
  when "enum" then value.is_a?(String) && field.fetch("enum_values", []).include?(value)
  when "string[]" then value.is_a?(Array) && value.all? { |item| item.is_a?(String) }
  when "object" then value.is_a?(Hash)
  when "object[]" then value.is_a?(Array) && value.all? { |item| item.is_a?(Hash) }
  else false
  end
end

admitted_literal = lambda do |path, value|
  resolve.call(path).any? { |field| literal_valid.call(field, value) }
end

fixture.fetch("cases", []).each do |test_case|
  Array(test_case.dig("machine_expectations", "structured_json_assertions")).each_with_index do |assertion, index|
    path_operands.call(assertion).each do |operand, path|
      unless path.is_a?(Array) && path.first.is_a?(String)
        warn "case #{test_case.fetch("id")}.machine_expectations.structured_json_assertions[#{index}] invalid assertion path #{operand}: #{path.to_json}"
        exit 1
      end
      unless roots.key?(path.first)
        warn "case #{test_case.fetch("id")}.machine_expectations.structured_json_assertions[#{index}] unknown assertion root #{operand}: #{path.first.to_json}"
        exit 1
      end

      resolved = resolve.call(path)
      next if resolved.empty? && assertion["operator"] == "path_absent" && operand == "path" && external_absent_paths[path.first].include?(path.drop(1))

      absence_allowed = assertion["operator"] != "path_absent" || operand != "path" || resolved.any? { |field| field["required"] != true || field["condition"].is_a?(String) }
      next if !resolved.empty? && absence_allowed

      reason = resolved.empty? ? "undeclared" : "required field used by path_absent"
      warn "case #{test_case.fetch("id")}.machine_expectations.structured_json_assertions[#{index}] #{reason} assertion path #{operand}: #{path.to_json}"
      exit 1
    end

    literal_error = case assertion["operator"]
                    when "equals"
                      !admitted_literal.call(assertion["path"], assertion["expected"])
                    when "one_of"
                      !Array(assertion["expected_values"]).all? { |value| admitted_literal.call(assertion["path"], value) }
                    when "array_field_values_exact"
                      field_path = assertion["path"] + [0, assertion["field"]]
                      !Array(assertion["expected_values"]).all? { |value| admitted_literal.call(field_path, value) }
                    when "array_object_values_exact"
                      !Array(assertion["expected_objects"]).all? do |object|
                        object.is_a?(Hash) && object.all? { |field, value| admitted_literal.call(assertion["path"] + [0, field], value) }
                      end
                    when "required_when_equals"
                      !admitted_literal.call(assertion["when_path"], assertion["value"])
                    else
                      false
                    end
    if literal_error
      warn "case #{test_case.fetch("id")}.machine_expectations.structured_json_assertions[#{index}] assertion literal outside contract schema"
      exit 1
    end
  end
end
RUBY
)" || true

    if [[ -n "$contract_error" ]]; then
        echo "$(display_path "$fixture_file"): $contract_error" >&2
        exit 1
    fi
}

validate_fixture() {
    local fixture_file="$1"
    local skill_name="$2"
    local validation_error

    require_jq
    [[ -f "$fixture_file" ]] || die "Fixture not found: $(display_path "$fixture_file")"

    validation_error="$(jq -r --arg skill_name "$skill_name" '
        def nonempty_string:
          if type == "string" then length > 0 else false end;

        def nonempty_string_array:
          if type != "array" or length == 0 then false
          else all(.[]; type == "string" and length > 0) end;

        def required_string($name):
          if (.[$name]? | nonempty_string) then empty
          else "missing or invalid top-level string field: \($name)" end;

        def required_bool($name; $value):
          if has($name) and .[$name] == $value then empty
          else "top-level field \($name) must be \($value)" end;

        def required_string_array($name):
          if (.[$name]? | nonempty_string_array) then empty
          else "missing or invalid non-empty string array field: \($name)" end;

        def validate_schema_version:
          if (.schema_version? | type) != "string" then
            empty
          elif .schema_version == "1.0" or .schema_version == "2.0" then
            empty
          else
            "top-level field schema_version must be 1.0 or 2.0"
          end;

        def normalized_activation_request:
          gsub("^[[:space:]]+|[[:space:]]+$"; "")
          | gsub("[[:space:]]+"; " ")
          | ascii_downcase;

        def activation_case_error($index):
          if type != "object" then
            "activation_cases[\($index)] must be an object"
          elif (keys | sort) != ["should_activate", "user_request"] then
            "activation_cases[\($index)] must contain exactly user_request and should_activate"
          elif (.user_request? | type) != "string" then
            "activation_cases[\($index)].user_request must be a nonblank string"
          elif (.user_request | test("[^[:space:]]") | not) then
            "activation_cases[\($index)].user_request must be a nonblank string"
          elif (.should_activate? | type != "boolean") then
            "activation_cases[\($index)].should_activate must be boolean"
          else
            empty
          end;

        def validate_activation_cases:
          if .schema_version != "1.0" and .schema_version != "2.0" then
            empty
          elif .schema_version == "1.0" and (has("activation_cases") | not) then
            empty
          elif (.activation_cases? | type != "array") then
            "top-level field activation_cases must be an array"
          elif (.activation_cases | length < 3) then
            "top-level field activation_cases must contain at least three entries"
          else
            [ .activation_cases | to_entries[] | .key as $index | .value | activation_case_error($index) ] as $item_errors
            | if ($item_errors | length > 0) then
                $item_errors[]
              else
                ([[.activation_cases[] | .user_request] | group_by(.)[] | select(length > 1) | .[0]][0]) as $duplicate_exact_request
                | ([.activation_cases[] | select(.should_activate == true) | .user_request | normalized_activation_request] | unique) as $positive_requests
                | ([.activation_cases[] | select(.should_activate == false) | .user_request | normalized_activation_request] | unique) as $negative_requests
                | if $duplicate_exact_request != null then
                    "activation_cases must not contain duplicate exact user_request: \($duplicate_exact_request | @json)"
                  elif ($positive_requests | length < 2) then
                    "activation_cases must contain at least two normalized-distinct positive requests"
                  elif ($negative_requests | length < 1) then
                    "activation_cases must contain at least one normalized-disjoint nearby negative request"
                  elif (($positive_requests - $negative_requests | length) != ($positive_requests | length)) then
                    "activation_cases positive and negative requests must be normalized-disjoint"
                  else
                    empty
                  end
              end
          end;

        def skill_identity_name:
          (.skill? // null) as $skill
          | if ($skill | nonempty_string) then $skill
            elif ($skill | type) == "object" then
              if (($skill.name? // null) | nonempty_string) then $skill.name
              elif (.skill_name? | nonempty_string) then .skill_name
              else null end
            elif (.skill_name? | nonempty_string) then .skill_name
            else null end;

        def validate_skill_identity:
          (skill_identity_name) as $fixture_skill
          | if $fixture_skill == null then
              "missing or invalid skill identity field: skill, skill.name, or skill_name"
            elif $fixture_skill != $skill_name then
              "skill identity must match selected skill: expected \($skill_name), got \($fixture_skill)"
            else
              empty
            end;

        def validate_optional_skill_path:
          (.skill? // null) as $skill
          | if ($skill | type) == "object" then
              if ($skill | has("path")) and (($skill.path? // null) | nonempty_string | not) then
                "skill.path must be a non-empty string when present"
              else
                empty
              end
            elif has("skill_path") and ((.skill_path? // null) | nonempty_string | not) then
              "skill_path must be a non-empty string when present"
            else
              empty
            end;

        def case_string($index; $name):
          if (.[$name]? | nonempty_string) then empty
          else "case[\($index)] missing or invalid string field: \($name)" end;

        def safe_case_id($index):
          (.id? // null) as $id
          | if ($id | nonempty_string | not) then
              "case[\($index)] missing or invalid string field: id"
            elif $id == "." or $id == ".." then
              "case[\($index)] invalid case id \($id | @json): must be a unique safe filename component using only letters, digits, dot, underscore, and hyphen; not . or .."
            elif ($id | test("^[A-Za-z0-9._-]+$") | not) then
              "case[\($index)] invalid case id \($id | @json): must be a unique safe filename component using only letters, digits, dot, underscore, and hyphen"
            else
              empty
            end;

        def duplicate_case_ids:
          if (.cases? | type == "array") then
            [ .cases[]? | select(type == "object") | .id? | select(type == "string") ] as $ids
            | ($ids | group_by(.)[]? | select(length > 1) | .[0]) as $duplicate
            | "duplicate case id: \($duplicate)"
          else
            empty
          end;

        def case_string_array($index; $name):
          if (.[$name]? | nonempty_string_array) then empty
          else "case[\($index)] missing or invalid non-empty string array field: \($name)" end;

        def case_machine_expectation_array($index; $name):
          if (.machine_expectations? | type == "object")
             and (.machine_expectations[$name]? | nonempty_string_array)
          then empty
          else "case[\($index)] missing or invalid machine_expectations.\($name) non-empty string array" end;

        def json_path:
          type == "array" and length > 0
          and all(.[]; (type == "string" and length > 0) or (type == "number" and . >= 0 and (. % 1) == 0));

        def scalar:
          type == "string" or type == "number" or type == "boolean" or type == "null";

        def equality_value:
          type == "string" or type == "number" or type == "boolean"
          or (type == "array" and all(.[]; type == "string" or type == "number" or type == "boolean"));

        def object_tuple_value:
          equality_value or type == "null"
          or (type == "object" and length > 0 and length <= 16 and all(.[]; scalar));

        def scalar_array($maximum):
          type == "array" and length > 0 and length <= $maximum
          and all(.[]; scalar);

        def distinct_bounded_fields:
          type == "array" and length > 0 and length <= 16
          and all(.[]; type == "string" and length > 0)
          and (unique | length == length);

        def exact_expected_objects($fields):
          type == "array" and length > 0 and length <= 32
          and all(.[];
            type == "object"
            and (keys | sort) == ($fields | sort)
            and (. as $object | all($fields[]; . as $field | $object[$field] | object_tuple_value)));

        def structured_assertion_error($index; $assertion_index):
          if type != "object" then
            "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] must be an object"
          elif (.operator? | nonempty_string | not) then
            "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] missing or invalid operator"
          elif .operator == "equals" then
            if (.path? | json_path | not) or (has("expected") | not) or (.expected | equality_value | not) then
              "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] invalid equals assertion"
            else empty end
          elif .operator == "one_of" then
            if (.path? | json_path | not) or (.expected_values? | scalar_array(32) | not) then
              "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] invalid one_of assertion"
            else empty end
          elif .operator == "nonempty_string" or .operator == "nonempty_array" or .operator == "empty_array" or .operator == "array_type" or .operator == "path_absent" or .operator == "absent_or_empty_array" then
            if (.path? | json_path | not) then
              "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] invalid \(.operator) path"
            else empty end
          elif .operator == "array_nonblank_strings" then
            if (.path? | json_path | not) or (.allow_empty? | type != "boolean") then
              "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] invalid array_nonblank_strings assertion"
            else empty end
          elif .operator == "equals_path" then
            if (.path? | json_path | not) or (.other_path? | json_path | not) then
              "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] invalid equals_path assertion"
            else empty end
          elif .operator == "required_when_equals" then
            .expected_type as $expected_type |
            if (.when_path? | json_path | not) or (has("value") | not) or (.value | scalar | not) or (.path? | json_path | not) or (has("expected_type") and (($expected_type | type) != "string" or (["null", "boolean", "number", "string", "array", "object"] | index($expected_type) | not))) then
              "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] invalid required_when_equals assertion"
            else empty end
          elif .operator == "array_field_values_exact" then
            if (.path? | json_path | not) or (.field? | nonempty_string | not) or (.expected_values? | nonempty_string_array | not) then
              "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] invalid array_field_values_exact assertion"
            else empty end
          elif .operator == "array_items_nonempty_fields" then
            if (.path? | json_path | not) or (.fields? | nonempty_string_array | not) then
              "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] invalid array_items_nonempty_fields assertion"
            else empty end
          elif .operator == "array_items_nonempty_array_fields" then
            if (.path? | json_path | not) or (.fields? | nonempty_string_array | not) then
              "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] invalid array_items_nonempty_array_fields assertion"
            else empty end
          elif .operator == "array_object_values_exact" then
            .fields as $fields |
            if (.path? | json_path | not) or ($fields | distinct_bounded_fields | not) or (.expected_objects? | exact_expected_objects($fields) | not) then
              "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] invalid array_object_values_exact assertion"
            else empty end
          else
            "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] unsupported operator: \(.operator)"
          end;

        def case_structured_json_assertions($index):
          if has("structured_json_assertions") then
            if (.structured_json_assertions | type != "array") or (.structured_json_assertions | length == 0) then
              "case[\($index)].machine_expectations.structured_json_assertions must be a non-empty array when present"
            else
              .structured_json_assertions | to_entries[] | .key as $assertion_index | .value |
                structured_assertion_error($index; $assertion_index)
            end
          else empty end;

        def case_machine_expectations($index):
          if (.machine_expectations? | type == "object") then
            case_machine_expectation_array($index; "required_substrings"),
            case_machine_expectation_array($index; "forbidden_substrings"),
            (.machine_expectations | case_structured_json_assertions($index))
          else
            "case[\($index)] missing or invalid object field: machine_expectations"
          end;

        def optional_bool($value):
          if $value == null then true else ($value | type == "boolean") end;

        def optional_nonnegative_int($value):
          if $value == null then true else (($value | type == "number") and ($value >= 0) and (($value % 1) == 0)) end;

        def case_seeded_defects($index):
          if has("false_positive_budget") and (optional_nonnegative_int(.false_positive_budget) | not) then
            "case[\($index)] false_positive_budget must be a non-negative integer when present"
          elif has("false_positive_markers") and (.false_positive_markers | nonempty_string_array | not) then
            "case[\($index)] false_positive_markers must be a non-empty string array when present"
          elif has("seeded_defects") then
            if (.seeded_defects | type != "array") or (.seeded_defects | length == 0) then
              "case[\($index)] seeded_defects must be a non-empty array when present"
            else
              .seeded_defects | to_entries[] | .key as $defect_index | .value |
                if type != "object" then
                  "case[\($index)].seeded_defects[\($defect_index)] must be an object"
                elif (.id? | nonempty_string | not) then
                  "case[\($index)].seeded_defects[\($defect_index)] missing or invalid string field: id"
                elif (.description? | nonempty_string | not) then
                  "case[\($index)].seeded_defects[\($defect_index)] missing or invalid string field: description"
                elif (optional_bool(.must_detect? // null) | not) then
                  "case[\($index)].seeded_defects[\($defect_index)] must_detect must be boolean when present"
                elif (.detection_anchors? | nonempty_string_array | not) then
                  "case[\($index)].seeded_defects[\($defect_index)] missing or invalid non-empty string array field: detection_anchors"
                elif (.evidence_anchors? | nonempty_string_array | not) then
                  "case[\($index)].seeded_defects[\($defect_index)] missing or invalid non-empty string array field: evidence_anchors"
                elif has("acceptable_severities") and (.acceptable_severities | nonempty_string_array | not) then
                  "case[\($index)].seeded_defects[\($defect_index)] acceptable_severities must be a non-empty string array when present"
                elif has("finding_markers") and (.finding_markers | nonempty_string_array | not) then
                  "case[\($index)].seeded_defects[\($defect_index)] finding_markers must be a non-empty string array when present"
                else
                  empty
                end
            end
          else
            empty
          end;

        if type != "object" then
          "fixture root must be a JSON object"
        else
          required_string("schema_version"),
          validate_schema_version,
          required_string("suite_id"),
          required_string("title"),
          required_string("description"),
          required_string("eval_type"),
          required_bool("provider_neutral"; true),
          required_bool("model_specific_api_calls"; false),
          required_string_array("recommended_use"),
          validate_activation_cases,
          validate_skill_identity,
          validate_optional_skill_path,
          (if (.cases? | type == "array") and (.cases | length > 0) then empty
           else "top-level field cases must be a non-empty array" end),
          duplicate_case_ids,
          (if (.cases? | type == "array") then
             .cases | to_entries[] | .key as $index | .value |
               if type != "object" then
                 "case[\($index)] must be an object"
               else
                 safe_case_id($index),
                 case_string($index; "title"),
                 case_string($index; "category"),
                 case_string($index; "purpose"),
                 case_string($index; "prompt"),
                 case_string_array($index; "setup_context"),
                 case_string_array($index; "expected_behavior"),
                 case_string_array($index; "pass_criteria"),
                 case_string_array($index; "fail_signals"),
                 case_machine_expectations($index),
                 case_seeded_defects($index)
               end
           else empty end)
        end
    ' "$fixture_file")" || die "Fixture is not valid JSON: $(display_path "$fixture_file")"

    if [[ -n "$validation_error" ]]; then
        echo "$(display_path "$fixture_file"): $validation_error" >&2
        exit 1
    fi

    validate_assertion_contract_paths "$fixture_file" "$skill_name"
}

validate_all_fixtures() {
    local index

    for index in "${!FIXTURE_FILES[@]}"; do
        validate_fixture "${FIXTURE_FILES[$index]}" "${SKILL_NAMES[$index]}"
    done
}

selected_case_ids_json() {
    if [[ -z "${CASE_SELECTORS[*]-}" ]]; then
        printf '[]\n'
        return
    fi

    printf '%s\n' "${CASE_SELECTORS[@]}" | jq -Rsc 'split("\n") | map(select(length > 0)) | unique'
}

validate_selected_case_ids() {
    local requested_case
    local fixture_file
    local found

    [[ -n "${CASE_SELECTORS[*]-}" ]] || return 0
    for requested_case in "${CASE_SELECTORS[@]}"; do
        found=false
        for fixture_file in "${FIXTURE_FILES[@]}"; do
            if jq -e --arg id "$requested_case" 'any(.cases[]; .id == $id)' "$fixture_file" >/dev/null; then
                found=true
                break
            fi
        done
        [[ "$found" == true ]] || die "Selected case not found in selected fixtures: $requested_case"
    done
}

list_cases() {
    local index
    local selected_cases

    validate_all_fixtures
    validate_selected_case_ids
    selected_cases="$(selected_case_ids_json)"
    for index in "${!FIXTURE_FILES[@]}"; do
        jq -r --arg skill "${SKILL_NAMES[$index]}" --argjson selected_cases "$selected_cases" '
            .cases[]
            | .id as $id
            | select(($selected_cases | length) == 0 or ($selected_cases | index($id)) != null)
            | [$skill, .id, .category, .title]
            | @tsv
        ' "${FIXTURE_FILES[$index]}"
    done
}
