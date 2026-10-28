# Emit the fixed tool-owned companion schema policy for fixture and grade readers.
skill_eval_companion_contracts_ruby() {
    cat <<'RUBY'
# Repository-only bridge: independent Ruby fixtures call the Python library.
# The installed helper has no bridge operation and never spawns this child.
require 'json'
require 'open3'
require 'timeout'
module ReviewTools
  MAX_BYTES = 8 * 1024 * 1024
  class Invalid < StandardError; end
  module_function
  def use(path)
    path = File.realpath(path)
    raise Invalid, 'helper_identity_changed' if @path && @path != path
    @path = path
  end
  def normalize(value)
    case value
    when Hash then value.to_h { |key, item| [normalize(key), normalize(item)] }
    when Array then value.map { |item| normalize(item) }
    when String
      text = value.dup.force_encoding(Encoding::UTF_8)
      raise Invalid, 'primitive_json_required' unless text.valid_encoding?
      text
    when Integer, TrueClass, FalseClass, NilClass then value
    when Numeric
      raise Invalid, 'primitive_json_required' unless value.finite?
      value.to_f
    else raise Invalid, 'primitive_json_required'
    end
  end
  def close
    @input.close rescue nil
    if @wait && !@wait.join(2)
      Process.kill('TERM', @wait.pid) rescue nil
      unless @wait.join(2)
        Process.kill('KILL', @wait.pid) rescue nil
        @wait.join
      end
    end
    @output.close rescue nil
    @errors.close rescue nil
    @drain.join(2) if @drain
    @input = nil
  end
  def invoke(method, *arguments)
    raise Invalid, 'helper_unselected' unless @path
    unless @input
      program = <<~'PYTHON'
        import importlib.util,json,sys
        spec=importlib.util.spec_from_file_location('review_tools',sys.argv[1])
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        names=('call','parse_json','shape_valid','snapshot_identity_valid','summary_projection_valid','validate_return','same_set','primitive_copy')
        methods={name:getattr(module,name) for name in names}
        for line in sys.stdin.buffer:
            try:
                module.require_fact(len(line)<=module.MAX_BYTES,'input_too_large')
                request=module.primitive_copy(module.parse_json(line))
                result=methods[request['method']](*request['arguments'])
                reply={'ok':True,'result':result}
            except Exception as error:
                reply={'ok':False,'diagnostic':str(error) if type(error) is module.Invalid else 'adapter_input_invalid'}
            output=module.encoded(reply)
            if len(output)>module.MAX_BYTES:output=module.encoded({'ok':False,'diagnostic':'output_too_large'})
            sys.stdout.buffer.write(output+b'\n');sys.stdout.buffer.flush()
      PYTHON
      @input, @output, @errors, @wait = Open3.popen3(ENV.fetch('REVIEW_TOOLS_PYTHON', 'python3'), '-I', '-S', '-B', '-c', program, @path)
      @error_prefix = ''.b
      @drain = Thread.new do
        begin
          loop do
            chunk = @errors.readpartial(4096)
            @error_prefix << chunk if @error_prefix.bytesize < 16384
          end
        rescue EOFError, IOError
        end
      end
    end
    raw = JSON.generate({'method'=>method,'arguments'=>normalize(arguments)})
    raise Invalid, 'input_too_large' if raw.bytesize > MAX_BYTES
    line = Timeout.timeout(10) do
      @input.write(raw + "\n"); @input.flush
      @output.gets(MAX_BYTES + 1)
    end
    raise Invalid, 'adapter_response_unavailable' unless line && line.bytesize <= MAX_BYTES && line.end_with?("\n")
    reply = JSON.parse(line)
    raise Invalid, reply.fetch('diagnostic') unless reply['ok']
    reply['result']
  rescue IOError, Errno::EPIPE, JSON::ParserError, Timeout::Error
    close
    raise Invalid, 'adapter_response_unavailable'
  end
  def call(request)
    invoke('call', request)
  rescue Invalid => error
    {'valid'=>false,'diagnostics'=>[error.message],'input_receipts'=>{}}
  end
  def parse_json(value); invoke('parse_json', value); end
  def shape_valid?(value, field, context=nil); invoke('shape_valid', value, field, context); end
  def snapshot_identity_valid?(value); invoke('snapshot_identity_valid', value); end
  def summary_projection_valid?(authority, summary); invoke('summary_projection_valid', authority, summary); end
  def validate_return(authority, reply); invoke('validate_return', authority, reply); end
  def same_set(actual, expected, code); invoke('same_set', actual, expected, code); end
  def primitive_copy(value); invoke('primitive_copy', value); end
end
at_exit { ReviewTools.close }

class SkillEvalCompanionContracts
  def initialize(repo_root, fixture_file, skill_name = nil)
    contracts_dir = File.expand_path("../contracts", File.dirname(fixture_file))
    skill_name ||= File.basename(File.dirname(contracts_dir))
    runner_root = File.realpath(repo_root)
    consumer_contracts = File.directory?(contracts_dir) ? File.realpath(contracts_dir) : nil
    contained = ->(child, parent) { child && (child == parent || child.start_with?(parent + File::SEPARATOR)) }
    trusted_roots = [[File.join(runner_root, "skills"), runner_root, false]]
    profile_text = %w[USERPROFILE HOME].map { |name| ENV[name] }.find { |value| value.is_a?(String) && !value.strip.empty? }
    if profile_text && File.directory?(profile_text)
      profile = File.realpath(profile_text)
      configured = ENV["CODEX_HOME"]
      codex_home = File.expand_path(configured.is_a?(String) && !configured.strip.empty? ? configured : File.join(profile, ".codex"))
      codex_home = File.realpath(codex_home) if File.exist?(codex_home)
      trusted_roots << [File.join(profile, ".agents", "skills"), profile, true] if runner_root == codex_home
    end
    skills_owner, owner_boundary = trusted_roots.first
    trusted_roots.each do |base, boundary, split|
      expected_consumer = File.join(base, skill_name, "contracts")
      expected_parent = File.dirname(expected_consumer)
      logical_match = File.directory?(expected_parent) &&
        File.join(File.realpath(File.dirname(contracts_dir)), File.basename(contracts_dir)) == File.join(File.realpath(expected_parent), File.basename(expected_consumer))
      physical_match = File.directory?(base) && consumer_contracts == File.join(File.realpath(base), skill_name, "contracts")
      # Co-located symlinked/external consumer contracts remain custom data.
      # A recognized split path must instead reject escape, never fall back.
      next unless physical_match || (split && logical_match)

      physical_base = File.realpath(base)
      consumer_skill = File.realpath(File.join(base, skill_name))
      unless contained.call(physical_base, boundary) && consumer_skill == File.join(physical_base, skill_name) && contained.call(consumer_contracts, consumer_skill)
        raise "consumer contracts escape the trusted skills owner"
      end
      skills_owner, owner_boundary = physical_base, boundary
      break
    end
    @skills_owner, @owner_boundary, @contained = skills_owner, owner_boundary, contained
  end

  def path(producer_skill, contract_file, required = true)
    registered = (producer_skill == "assistant-verification" && contract_file == "output.yaml") ||
      (producer_skill == "assistant-review" && %w[index.yaml output.yaml handoffs.yaml review-tools.py].include?(contract_file))
    raise "unregistered fixed producer contract" unless registered
    base = File.realpath(@skills_owner)
    raise "producer skills base escapes its owner" unless @contained.call(base, @owner_boundary)
    producer = File.join(base, producer_skill)
    output = File.join(producer, contract_file == "review-tools.py" ? "scripts" : "contracts", contract_file)
    return output unless required || File.exist?(output) || File.symlink?(output)

    physical_producer = File.realpath(producer)
    physical_output = File.realpath(output)
    unless physical_producer == producer && @contained.call(physical_output, physical_producer) && File.file?(physical_output)
      raise "fixed producer schema escapes its owner"
    end
    physical_output
  end
end
RUBY
}

validate_assertion_contract_paths() {
    local fixture_file="$1"
    local skill_name="$2"
    local contracts_dir
    local contract_error

    contracts_dir="$(cd "$(dirname "$fixture_file")/.." && pwd)/contracts"
    [[ -d "$contracts_dir" ]] || return 0

    contract_error="$({
        skill_eval_companion_contracts_ruby
        cat <<'RUBY'
fixture = JSON.parse(File.read(ARGV.fetch(0)))
skill_name = ARGV.fetch(1)
contracts_dir = ARGV.fetch(2)
repo_root = ARGV.fetch(3)

companion_contracts = SkillEvalCompanionContracts.new(repo_root, ARGV.fetch(0), skill_name)
fixed_producer_output = lambda do |producer_skill, required|
  companion_contracts.path(producer_skill, "output.yaml", required)
end

load_contract_yaml = lambda do |path|
  YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false)
end

# Resolve only the two explicitly carried verification producer artifacts.
# Consumer requiredness stays local; nested types come from their sole owner.
verification_producer_artifacts = nil
expand_verification_aliases = lambda do |field|
  next field unless field.is_a?(Hash)

  expanded = field.dup
  name = field["name"]
  if %w[verification_decision evidence_assessment].include?(name) &&
      field["type"] == "object" &&
      field.fetch("validation", "").include?("assistant-verification/contracts/output.yaml##{name}")
    verification_producer_artifacts ||= load_contract_yaml.call(
      fixed_producer_output.call("assistant-verification", true)
    ).fetch("artifacts")
    matches = verification_producer_artifacts.select { |artifact| artifact["name"] == name }
    unless matches.length == 1 && matches.first["type"] == "object" && matches.first["object_fields"].is_a?(Array)
      warn "verification producer alias must resolve exactly once: #{name}"
      exit 1
    end
    expanded["object_fields"] = matches.first.fetch("object_fields")
  end
  if expanded["object_fields"].is_a?(Array)
    expanded["object_fields"] = expanded["object_fields"].map { |child| expand_verification_aliases.call(child) }
  end
  expanded
end

roots = Hash.new { |hash, key| hash[key] = [] }
add_root = lambda do |field|
  roots[field.fetch("name")] << expand_verification_aliases.call(field) if field.is_a?(Hash) && field["name"].is_a?(String)
end

load_contract_roots = lambda do |directory, include_non_output_roots|
  output_path = File.join(directory, "output.yaml")
  load_contract_yaml.call(output_path).fetch("artifacts", []).each { |artifact| add_root.call(artifact) } if File.file?(output_path)
  next unless include_non_output_roots

  input_path = File.join(directory, "input.yaml")
  load_contract_yaml.call(input_path).fetch("fields", []).each { |field| add_root.call(field) } if File.file?(input_path)

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
  walk_handoffs.call(load_contract_yaml.call(handoffs_path))
end

load_contract_roots.call(contracts_dir, skill_name == "assistant-review")

# Explicitly bounded roots that eval fixtures may project outside their output
# artifacts. This is deliberately not a pool of every input or handoff field.
# The collaborative progressive fixture also requests singleton projections of
# these two canonical arrays; derive each item view from the owning schema.
eval_only_root_registry = {
  "assistant-docs" => [
    { "kind" => "input_field", "name" => "architecture_decision_pack_status" },
    { "kind" => "input_field", "name" => "architecture_design_mode" },
    { "kind" => "input_field", "name" => "feature_preparation_evidence_status" },
    { "kind" => "input_field", "name" => "feature_preparation_scope" }
  ],
  "assistant-workflow" => [
    { "kind" => "input_field", "name" => "approved_feature_preparation_evidence_ref" },
    { "kind" => "input_field", "name" => "approved_feature_preparation_result" },
    { "kind" => "input_field", "name" => "approved_feature_preparation_harness_obligation" },
    { "kind" => "input_field", "name" => "approved_feature_preparation_qa_acceptance_obligation" },
    { "kind" => "input_field", "name" => "architecture_design_mode" },
    { "kind" => "input_field", "name" => "execution_intent" },
    { "kind" => "input_field", "name" => "feature_preparation_scope" },
    { "kind" => "handoff_field", "name" => "architecture_mapping_evidence" },
    { "kind" => "handoff_field", "name" => "current_task_packet", "handoff" => "orchestrator_to_code_writer" },
    { "kind" => "output_child", "artifact" => "triage_result", "name" => "size" },
    { "kind" => "output_array_item", "artifact" => "decision_item" },
    { "kind" => "output_array_item", "artifact" => "decision_resolution" }
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
               input = load_contract_yaml.call(File.join(contracts_dir, "input.yaml"))
               input.fetch("fields", []).select { |field| field["name"] == selector.fetch("name") }
             when "handoff_field"
               matches = []
               document = load_contract_yaml.call(File.join(contracts_dir, "handoffs.yaml"))
               document = document.fetch("handoffs").find { |handoff| handoff["name"] == selector["handoff"] }.fetch("context_fields") if selector["handoff"]
               find_named_fields.call(document, selector.fetch("name"), matches)
               matches
             when "output_child"
               output = load_contract_yaml.call(File.join(contracts_dir, "output.yaml"))
               artifact = output.fetch("artifacts", []).find { |field| field["name"] == selector.fetch("artifact") }
               artifact ? artifact.fetch("object_fields", []).select { |field| field["name"] == selector.fetch("name") } : []
             when "output_array_item"
               output = load_contract_yaml.call(File.join(contracts_dir, "output.yaml"))
               artifact = output.fetch("artifacts", []).find { |field| field["name"] == selector.fetch("artifact") }
               if artifact.is_a?(Hash) && artifact["type"] == "object[]" && artifact["object_fields"].is_a?(Array)
                 [artifact.dup.merge("type" => "object")]
               else
                 []
               end
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
    # Synthetic writer-response projections; real artifacts remain adapter-owned.
    { "name" => "actual_output", "type" => "string", "required" => false },
    { "name" => "dependent_output", "type" => "string", "required" => false },
    { "name" => "status", "type" => "enum", "required" => false, "enum_values" => %w[DONE NEEDS_CONTEXT BLOCKED DEVIATED] },
    { "name" => "failure_class", "type" => "string", "required" => false },
    { "name" => "next_action", "type" => "enum", "required" => false, "enum_values" => %w[review orchestrator] },
    { "name" => "current_assistant_review_contract", "type" => "object", "required" => false, "object_fields" => [{ "name" => "schema_version", "type" => "enum", "required" => true, "enum_values" => ["10.0"] }] },
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
    # Retired execution roots remain recognizable only as preparation absences.
    { "name" => "slice_manifest", "type" => "object[]", "required" => false },
    { "name" => "slice_verification_summary", "type" => "object[]", "required" => false },
    { "name" => "single_slice_rationale", "type" => "string", "required" => false },
    { "name" => "decomposition_plan_review", "type" => "object", "required" => false },
    { "name" => "packet_admission", "type" => "object", "required" => false },
    { "name" => "canonical_plan", "type" => "object", "required" => false },
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
    {
      "name" => "decisions", "type" => "object[]", "required" => false,
      "object_fields" => [
        { "name" => "id", "type" => "string", "required" => true },
        { "name" => "action", "type" => "enum", "required" => true, "enum_values" => %w[reuse rerun] },
        { "name" => "original_run_ref", "type" => "string", "required" => true },
        { "name" => "current_comparison_ref", "type" => "string", "required" => true },
        { "name" => "independent_review_status", "type" => "enum", "required" => true, "enum_values" => ["required"] }
      ]
    },
    {
      "name" => "execution_policy", "type" => "object", "required" => false,
      "object_fields" => [
        { "name" => "source_writer_policy", "type" => "enum", "required" => true, "enum_values" => %w[sequential_shared_or_unknown isolated_A_B_overlap_permitted] },
        { "name" => "read_only_analysis_policy", "type" => "enum", "required" => true, "enum_values" => %w[parallel_permitted sequential_only] },
        { "name" => "isolation_evidence_ref", "type" => "string", "required" => true },
        {
          "name" => "c_start_decisions", "type" => "object[]", "required" => true,
          "object_fields" => [
            { "name" => "a_status", "type" => "enum", "required" => true, "enum_values" => %w[PENDING RUNNING VERIFIED] },
            { "name" => "c_decision", "type" => "enum", "required" => true, "enum_values" => %w[blocked ready] }
          ]
        },
        { "name" => "per_slice_verification", "type" => "enum", "required" => true, "enum_values" => %w[required deferred_to_integration] },
        { "name" => "integration_validation", "type" => "enum", "required" => true, "enum_values" => %w[required per_slice_only] },
        { "name" => "integration_checks", "type" => "string[]", "required" => true },
        { "name" => "fresh_review", "type" => "enum", "required" => true, "enum_values" => %w[required not_required] },
        { "name" => "fresh_review_after", "type" => "enum", "required" => true, "enum_values" => %w[integration_validation per_slice_verification] }
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
  producer_output = fixed_producer_output.call(producer_skill, false)
  next unless File.file?(producer_output)

  artifact = load_contract_yaml.call(producer_output).fetch("artifacts", []).find { |item| item["name"] == artifact_name }
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
        field_type = field["type"]
        field_type.is_a?(String) && field_type.end_with?("[]") ? [field.dup.merge("type" => field_type.delete_suffix("[]"))] : []
      elsif segment.is_a?(String)
        field["type"] == "object" ? field.fetch("object_fields", []).select { |child| child["name"] == segment } : []
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
  if assertion["operator"] != "object_keys_exact" && assertion["fields"].is_a?(Array) && assertion["path"].is_a?(Array)
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
      if assertion["operator"] == "object_keys_exact" && operand == "path" && path == []
        next
      end
      unless path.is_a?(Array) && path.first.is_a?(String)
        warn "case #{test_case.fetch("id")}.machine_expectations.structured_json_assertions[#{index}] invalid assertion path #{operand}: #{path.to_json}"
        exit 1
      end
      if skill_name == "assistant-workflow" && %w[slice_manifest slice_verification_summary single_slice_rationale decomposition_plan_review].include?(path.first) && assertion["operator"] != "path_absent"
        warn "retired execution roots support absence assertions only"
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

    if assertion["operator"] == "object_keys_exact"
      path = assertion["path"]
      fields = assertion["fields"]
      if path.empty?
        unknown_fields = fields.reject { |field| roots.key?(field) }
        unless unknown_fields.empty?
          warn "case #{test_case.fetch("id")}.machine_expectations.structured_json_assertions[#{index}] unknown assertion root object key: #{unknown_fields.first.to_json}"
          exit 1
        end
      else
        target = resolve.call(path)
        target_field = target.length == 1 ? target.first : nil
        unless target_field && target_field["type"] == "object" && target_field["object_fields"].is_a?(Array)
          warn "case #{test_case.fetch("id")}.machine_expectations.structured_json_assertions[#{index}] object_keys_exact target must be a declared object: #{path.to_json}"
          exit 1
        end
        declared_fields = target_field.fetch("object_fields").map { |field| field["name"] }.sort
        required_fields = target_field.fetch("object_fields").select do |field|
          field["required"] == true && !field["condition"].is_a?(String)
        end.map { |field| field["name"] }
        undeclared_fields = fields - declared_fields
        missing_required_fields = required_fields - fields
        unless undeclared_fields.empty? && missing_required_fields.empty?
          if undeclared_fields.empty?
            warn "case #{test_case.fetch("id")}.machine_expectations.structured_json_assertions[#{index}] object_keys_exact fields must include every unconditional required field: #{missing_required_fields.to_json}"
          else
            warn "case #{test_case.fetch("id")}.machine_expectations.structured_json_assertions[#{index}] undeclared assertion path fields: #{undeclared_fields.to_json}"
          end
          exit 1
        end
      end
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
    } | ruby -rjson -ryaml - "$fixture_file" "$skill_name" "$contracts_dir" "$REPO_ROOT" 2>&1)" || true

    if [[ -n "$contract_error" ]]; then
        echo "$(display_path "$fixture_file"): $contract_error" >&2
        exit 1
    fi
}

validate_canonical_review_batch_authority() {
    local fixture_file="$1"
    local skill_name="$2"
    local authority_error

    case "$skill_name" in
        assistant-review|assistant-workflow) ;;
        *) return 0 ;;
    esac

    authority_error="$(ruby -rjson - "$fixture_file" "$skill_name" 2>&1 <<'RUBY'
fixture = JSON.parse(File.read(ARGV.fetch(0)))
skill_name = ARGV.fetch(1)
expectations = fixture["canonical_review_batch_expectations"]
fail_with = lambda { |message| warn "#{skill_name} canonical_review_batch_expectations: #{message}"; exit 1 }
nonblank = ->(value) { value.is_a?(String) && !value.strip.empty? }
nonblank_strings = ->(value) { value.is_a?(Array) && !value.empty? && value.all? { |item| nonblank.call(item) } && value.uniq.length == value.length }
tuple_projection = ->(tuple) { [tuple["review_pass_id"], tuple["scope_item_id"], tuple["applicable_concern"], tuple["review_perspective"], tuple["coverage_obligation"]] }
identity_valid = lambda do |identity|
  identity.is_a?(Hash) && identity.keys.sort == %w[basis captured_at scope_manifest_digest value] &&
    %w[git_revision diff_digest content_digest task_or_pr_revision].include?(identity["basis"]) &&
    %w[value captured_at scope_manifest_digest].all? { |field| nonblank.call(identity[field]) }
end
snapshot_authority_valid = lambda do |authority|
  authority.is_a?(Hash) && authority.keys.sort == %w[batch_projections final_review_snapshot_id final_snapshot_identity] &&
    nonblank.call(authority["final_review_snapshot_id"]) && identity_valid.call(authority["final_snapshot_identity"]) &&
    authority["batch_projections"].is_a?(Array) && !authority["batch_projections"].empty? &&
    authority["batch_projections"].all? do |projection|
      projection.is_a?(Hash) && projection.keys.sort == %w[batch_id review_snapshot_id snapshot_identity] &&
        nonblank.call(projection["batch_id"]) && nonblank.call(projection["review_snapshot_id"]) && identity_valid.call(projection["snapshot_identity"])
    end && authority["batch_projections"].map { |projection| projection["batch_id"] }.uniq.length == authority["batch_projections"].length &&
    authority["batch_projections"].map { |projection| projection["review_snapshot_id"] }.uniq.length == authority["batch_projections"].length &&
    authority["batch_projections"].last["review_snapshot_id"] == authority["final_review_snapshot_id"] &&
    authority["batch_projections"].last["snapshot_identity"] == authority["final_snapshot_identity"]
end
closure_authority_valid = lambda do |authority|
  authority.is_a?(Array) && !authority.empty? && authority.all? do |entry|
    next false unless entry.is_a?(Hash) && entry.keys.sort == %w[aggregate_finding_id source_finding_ids source_provenance] &&
      nonblank.call(entry["aggregate_finding_id"]) && nonblank_strings.call(entry["source_finding_ids"])
    sources = entry["source_provenance"]
    next false unless sources.is_a?(Array) && !sources.empty? && sources.all? do |source|
      source.is_a?(Hash) && source.keys.sort == %w[source_id source_kind] &&
        %w[spec_review review_pass].include?(source["source_kind"]) && nonblank.call(source["source_id"])
    end
    source_pairs = sources.map { |source| [source["source_kind"], source["source_id"]] }
    next false unless source_pairs.uniq.length == source_pairs.length
    entry["source_finding_ids"].all? do |finding_id|
      if finding_id.start_with?("review_pass:")
        sources.any? do |source|
          source["source_kind"] == "review_pass" && finding_id.start_with?("review_pass:#{source["source_id"]}:")
        end
      else
        finding_id.start_with?("spec_review:") && finding_id.length > "spec_review:".length && sources.any? { |source| source["source_kind"] == "spec_review" }
      end
    end
  end && authority.map { |entry| entry["aggregate_finding_id"] }.uniq.length == authority.length
end
# light_contract_and_runtime (trivial/small light) and plan_coverage_and_feasibility
# (plan review) are single fresh passes outside the canonical discovery matrix (take(n) below).
perspectives = %w[contract_and_test_oracle runtime_lifecycle_and_failure_paths integration_compatibility_and_consumers architecture_maintainability_and_reuse risk_selected_specialist closure_verification light_contract_and_runtime plan_coverage_and_feasibility]
canonical_perspectives = {
  "trivial_small" => perspectives.take(2),
  "medium" => perspectives.take(3),
  "large" => perspectives.take(4)
}

review_case_ids = Array(fixture["cases"]).map do |test_case|
  test_case["id"] if test_case.is_a?(Hash) && test_case["category"] == "multi_pass_review_batch"
end.compact
required_qa_case_ids = Array(fixture["cases"]).map do |test_case|
  test_case["id"] if test_case.is_a?(Hash) && test_case["category"] == "deferred_qa_obligation"
end.compact
qa_case_requirements = fixture["canonical_qa_case_requirements"]
if skill_name == "assistant-review"
  fail_with.call("canonical_qa_case_requirements must be an object keyed exactly to deferred_qa_obligation cases") unless qa_case_requirements.is_a?(Hash) && qa_case_requirements.keys.sort == required_qa_case_ids.sort
  qa_case_requirements.each do |case_id, requirement|
    fail_with.call("canonical_qa_case_requirements #{case_id.inspect} must contain exactly required_artifacts") unless requirement.is_a?(Hash) && requirement.keys == ["required_artifacts"]
    fail_with.call("canonical_qa_case_requirements #{case_id.inspect} must require exactly qa_evaluation_result and qa_evaluation_delegation_path") unless requirement["required_artifacts"] == %w[qa_evaluation_result qa_evaluation_delegation_path]
  end
elsif !qa_case_requirements.nil?
  fail_with.call("canonical_qa_case_requirements is supported only for assistant-review")
end
if expectations.nil?
  %w[canonical_review_snapshot_expectations canonical_review_closure_expectations].each do |sibling_name|
    sibling = fixture[sibling_name]
    fail_with.call("#{sibling_name} must be absent or empty when canonical_review_batch_expectations is absent") unless sibling.nil? || (sibling.is_a?(Hash) && sibling.empty?)
  end
  fail_with.call("is required whenever assistant-review has multi_pass_review_batch cases") if skill_name == "assistant-review" && !review_case_ids.empty?
  exit 0
end

fail_with.call("must be an object") unless expectations.is_a?(Hash)
expected_keys = %w[case_requirements case_template_refs scope_manifests templates]
fail_with.call("must contain exactly #{expected_keys.join(', ')}") unless expectations.keys.sort == expected_keys
templates, manifests, case_refs, case_requirements = expectations.values_at("templates", "scope_manifests", "case_template_refs", "case_requirements")
fail_with.call("templates must be a non-empty object") unless templates.is_a?(Hash) && !templates.empty?
fail_with.call("scope_manifests must be a non-empty object") unless manifests.is_a?(Hash) && !manifests.empty?
fail_with.call("template and scope-manifest keys must match exactly") unless templates.keys.sort == manifests.keys.sort
case_ids = Array(fixture["cases"]).map { |test_case| test_case["id"] if test_case.is_a?(Hash) }.compact
fail_with.call("case_template_refs must be a non-empty object") unless case_refs.is_a?(Hash) && !case_refs.empty?
fail_with.call("case_requirements must be a non-empty object") unless case_requirements.is_a?(Hash) && !case_requirements.empty?
fail_with.call("case_template_refs and case_requirements keys must match exactly") unless case_refs.keys.sort == case_requirements.keys.sort
fail_with.call("case_template_refs values must be nonblank template ids") unless case_refs.values.all? { |template_ref| nonblank.call(template_ref) }
fail_with.call("templates must be keyed exactly to case_template_refs values") unless templates.keys.sort == case_refs.values.uniq.sort
fail_with.call("assistant-review authority must cover every multi_pass_review_batch case") if skill_name == "assistant-review" && case_refs.keys.sort != review_case_ids.sort
snapshot_expectations = fixture["canonical_review_snapshot_expectations"]
fail_with.call("canonical_review_snapshot_expectations must be an object keyed exactly to mapped cases") unless snapshot_expectations.is_a?(Hash) && snapshot_expectations.keys.sort == case_refs.keys.sort
snapshot_expectations.each do |case_id, authority|
  fail_with.call("canonical_review_snapshot_expectations #{case_id.inspect} has an invalid bounded snapshot authority") unless snapshot_authority_valid.call(authority)
end
case_refs.each do |case_id, template_ref|
  fail_with.call("case_template_refs contains unknown case #{case_id.inspect}") unless case_ids.include?(case_id)
  fail_with.call("case_template_refs #{case_id.inspect} has unknown template #{template_ref.inspect}") unless nonblank.call(template_ref) && templates.key?(template_ref)
  snapshot_authority = snapshot_expectations.fetch(case_id)
  current_projection = snapshot_authority.fetch("batch_projections").last
  mapped_template = templates.fetch(template_ref)
  fail_with.call("canonical_review_snapshot_expectations #{case_id.inspect} current batch_id must match its mapped template") unless current_projection["batch_id"] == mapped_template["batch_id"]
  fail_with.call("canonical_review_snapshot_expectations #{case_id.inspect} current review snapshot must match its mapped template") unless current_projection["review_snapshot_id"] == mapped_template["review_snapshot_id"] && snapshot_authority["final_review_snapshot_id"] == mapped_template["review_snapshot_id"]
  requirement = case_requirements.fetch(case_id)
  fail_with.call("case_requirements #{case_id.inspect} must contain exactly mode, required_artifacts, required_envelope_alias") unless requirement.is_a?(Hash) && requirement.keys.sort == %w[mode required_artifacts required_envelope_alias]
  fail_with.call("case_requirements #{case_id.inspect}.mode must be audit or review") unless %w[audit review].include?(requirement["mode"])
  fail_with.call("case_requirements #{case_id.inspect}.required_artifacts must be a non-empty unique artifact array") unless nonblank_strings.call(requirement["required_artifacts"])
  fail_with.call("case_requirements #{case_id.inspect}.required_artifacts contains an unsupported artifact") unless (requirement["required_artifacts"] - %w[final_summary audit_report review_delegation_path]).empty?
  fail_with.call("case_requirements #{case_id.inspect} must require final_summary") unless requirement["required_artifacts"].include?("final_summary")
  fail_with.call("case_requirements #{case_id.inspect} audit applicability must exactly require audit_report") unless (requirement["mode"] == "audit") == requirement["required_artifacts"].include?("audit_report")
  allowed_aliases = skill_name == "assistant-review" ? ["final_summary"] : %w[canonical_final_summary fresh_canonical_final_summary]
  fail_with.call("case_requirements #{case_id.inspect}.required_envelope_alias is invalid") unless allowed_aliases.include?(requirement["required_envelope_alias"])
  if skill_name == "assistant-workflow"
    fail_with.call("assistant-workflow case_requirements #{case_id.inspect}.mode must be review") unless requirement["mode"] == "review"
    fail_with.call("assistant-workflow case_requirements #{case_id.inspect}.required_artifacts must exactly equal final_summary") unless requirement["required_artifacts"] == ["final_summary"]
  else
    fail_with.call("assistant-review case_requirements #{case_id.inspect} must require review_delegation_path") unless requirement["required_artifacts"].include?("review_delegation_path")
  end
end

manifests.each do |template_ref, manifest|
  fail_with.call("scope_manifests.#{template_ref} must be a non-empty array") unless manifest.is_a?(Array) && !manifest.empty?
  ids = manifest.map.with_index do |item, index|
    fail_with.call("scope_manifests.#{template_ref}[#{index}] must contain exactly scope_item_id, locator, content_digest, applicable_concerns") unless item.is_a?(Hash) && item.keys.sort == %w[applicable_concerns content_digest locator scope_item_id]
    %w[scope_item_id locator content_digest].each { |field| fail_with.call("scope_manifests.#{template_ref}[#{index}].#{field} must be a nonblank string") unless nonblank.call(item[field]) }
    fail_with.call("scope_manifests.#{template_ref}[#{index}].applicable_concerns must be a non-empty unique string array") unless nonblank_strings.call(item["applicable_concerns"])
    item["scope_item_id"]
  end
  fail_with.call("scope_manifests.#{template_ref} has duplicate scope_item_id") unless ids.uniq.length == ids.length
end

templates.each do |template_ref, template|
  template_fields = %w[batch_id expected_passes required_coverage_tuples review_snapshot_id scope_size topology]
  fail_with.call("templates.#{template_ref} must contain exactly #{template_fields.join(', ')}") unless template.is_a?(Hash) && template.keys.sort == template_fields
  %w[batch_id review_snapshot_id].each { |field| fail_with.call("templates.#{template_ref}.#{field} must be a nonblank string") unless nonblank.call(template[field]) }
  fail_with.call("templates.#{template_ref}.scope_size must be trivial, small, medium, or large") unless %w[trivial small medium large].include?(template["scope_size"])
  topology = template["topology"]
  topology_fields = %w[canonical_discovery_perspectives closure_verification_required discovery_pass_count max_required_responses security_specialist_triggered]
  fail_with.call("templates.#{template_ref}.topology must contain exactly #{topology_fields.join(', ')} plus optional light_review and plan_review") unless topology.is_a?(Hash) && (topology.keys - %w[light_review plan_review]).sort == topology_fields
  # Light trivial/small review: one fresh light_contract_and_runtime pass, no separate
  # closure pass, selected only by explicit topology.light_review true. Absent/false
  # keeps the canonical >=2-pass topology (historical two-pass trivial/small stays valid).
  fail_with.call("templates.#{template_ref}.topology.light_review must be boolean when present") if topology.key?("light_review") && ![true, false].include?(topology["light_review"])
  light = topology["light_review"] == true
  fail_with.call("templates.#{template_ref}.topology.light_review true requires trivial/small scope_size and discovery_pass_count 1") if light && !(%w[trivial small].include?(template["scope_size"]) && topology["discovery_pass_count"] == 1)
  # Plan review (U4): one fresh plan_coverage_and_feasibility pass at any scope size, no
  # closure pass, selected only by topology.plan_review true. Templates carry no
  # review_subject, so plan_review true is accepted only on that one-pass plan shape and
  # absent/false keeps multi-pass plan review acceptable.
  fail_with.call("templates.#{template_ref}.topology.plan_review must be boolean when present") if topology.key?("plan_review") && ![true, false].include?(topology["plan_review"])
  plan_review = topology["plan_review"] == true
  fail_with.call("templates.#{template_ref}.topology.plan_review true requires discovery_pass_count 1 and no light_review") if plan_review && (light || topology["discovery_pass_count"] != 1)
  fail_with.call("templates.#{template_ref}.topology.closure_verification_required must be false for plan review") if plan_review && topology["closure_verification_required"] != false
  single_pass = light || plan_review
  min_passes = single_pass ? 1 : 2
  fail_with.call("templates.#{template_ref}.topology.discovery_pass_count must be 1 for light_review trivial/small or plan_review, or an integer from 2 through 4") unless topology["discovery_pass_count"].is_a?(Integer) && (single_pass || (2..4).cover?(topology["discovery_pass_count"]))
  fail_with.call("templates.#{template_ref}.topology.max_required_responses must be an integer from #{min_passes} through 6") unless topology["max_required_responses"].is_a?(Integer) && (min_passes..6).cover?(topology["max_required_responses"])
  fail_with.call("templates.#{template_ref}.topology.closure_verification_required must be false for light trivial/small review") if light && topology["closure_verification_required"] != false
  %w[security_specialist_triggered closure_verification_required].each { |field| fail_with.call("templates.#{template_ref}.topology.#{field} must be boolean") unless [true, false].include?(topology[field]) }
  fail_with.call("templates.#{template_ref}.topology.canonical_discovery_perspectives must exactly match the canonical perspective matrix") unless topology["canonical_discovery_perspectives"] == canonical_perspectives
  passes, tuples = template.values_at("expected_passes", "required_coverage_tuples")
  fail_with.call("templates.#{template_ref}.expected_passes must be a non-empty array") unless passes.is_a?(Array) && !passes.empty?
  fail_with.call("templates.#{template_ref}.expected_passes must contain #{min_passes} through 6 records") unless (min_passes..6).cover?(passes.length)
  fail_with.call("templates.#{template_ref}.topology.max_required_responses must equal expected_passes length") unless topology["max_required_responses"] == passes.length
  fail_with.call("templates.#{template_ref}.required_coverage_tuples must be a non-empty array") unless tuples.is_a?(Array) && !tuples.empty?
  discovery_key = %w[trivial small].include?(template["scope_size"]) ? "trivial_small" : template["scope_size"]
  required_discovery_perspectives = plan_review ? %w[plan_coverage_and_feasibility] : light ? %w[light_contract_and_runtime] : canonical_perspectives.fetch(discovery_key)
  fail_with.call("templates.#{template_ref}.topology.discovery_pass_count must match scope_size canonical discovery count") unless topology["discovery_pass_count"] == required_discovery_perspectives.length
  pass_perspectives = passes.map { |review_pass| review_pass.is_a?(Hash) ? review_pass["perspective"] : nil }
  expected_perspectives = required_discovery_perspectives.dup
  expected_perspectives << "risk_selected_specialist" if topology["security_specialist_triggered"]
  expected_perspectives << "closure_verification" if topology["closure_verification_required"]
  fail_with.call("templates.#{template_ref}.expected_passes must exactly match the scope-sized discovery, security, and closure perspective topology") unless pass_perspectives == expected_perspectives && pass_perspectives.uniq.length == pass_perspectives.length
  manifest_by_id = manifests.fetch(template_ref).to_h { |item| [item.fetch("scope_item_id"), item] }
  pass_ids = []
  assigned_scope_ids = []
  expected = passes.flat_map.with_index do |review_pass, index|
    required_fields = %w[assigned_scope coverage_obligations perspective prior_finding_visibility review_pass_id]
    fail_with.call("templates.#{template_ref}.expected_passes[#{index}] must contain exactly #{required_fields.join(', ')}") unless review_pass.is_a?(Hash) && review_pass.keys.sort == required_fields
    fail_with.call("templates.#{template_ref}.expected_passes[#{index}] is malformed") unless nonblank.call(review_pass["review_pass_id"]) && perspectives.include?(review_pass["perspective"]) && nonblank_strings.call(review_pass["assigned_scope"]) && nonblank_strings.call(review_pass["coverage_obligations"]) && %w[none closure_ledger].include?(review_pass["prior_finding_visibility"])
    allowed_visibility = case review_pass["perspective"]
                         when "closure_verification" then %w[closure_ledger]
                         when "light_contract_and_runtime", "plan_coverage_and_feasibility" then %w[none closure_ledger]
                         else %w[none]
                         end
    fail_with.call("templates.#{template_ref}.expected_passes[#{index}].prior_finding_visibility must match its perspective") unless allowed_visibility.include?(review_pass["prior_finding_visibility"])
    fail_with.call("templates.#{template_ref}.expected_passes[#{index}] references scope outside its manifest") unless review_pass["assigned_scope"].all? { |scope_item_id| manifest_by_id.key?(scope_item_id) }
    pass_ids << review_pass["review_pass_id"]
    assigned_scope_ids.concat(review_pass["assigned_scope"])
    review_pass["assigned_scope"].flat_map do |scope_item_id|
      manifest_by_id.fetch(scope_item_id).fetch("applicable_concerns").flat_map do |concern|
        review_pass["coverage_obligations"].map { |obligation| [review_pass["review_pass_id"], scope_item_id, concern, review_pass["perspective"], obligation] }
      end
    end
  end
  fail_with.call("templates.#{template_ref}.expected_passes has duplicate review_pass_id") unless pass_ids.uniq.length == pass_ids.length
  fail_with.call("scope_manifests.#{template_ref} keys must exactly equal the union of expected_passes assigned_scope") unless manifest_by_id.keys.sort == assigned_scope_ids.uniq.sort
  actual = tuples.map.with_index do |tuple, index|
    fail_with.call("templates.#{template_ref}.required_coverage_tuples[#{index}] must contain exactly canonical tuple fields") unless tuple.is_a?(Hash) && tuple.keys.sort == %w[applicable_concern coverage_obligation review_pass_id review_perspective scope_item_id]
    fail_with.call("templates.#{template_ref}.required_coverage_tuples[#{index}] must use nonblank ids and a canonical perspective") unless %w[review_pass_id scope_item_id applicable_concern coverage_obligation].all? { |field| nonblank.call(tuple[field]) } && perspectives.include?(tuple["review_perspective"])
    tuple_projection.call(tuple)
  end
  fail_with.call("templates.#{template_ref}.required_coverage_tuples has duplicate tuples") unless actual.uniq.length == actual.length
  fail_with.call("templates.#{template_ref} must contain the exact pass x assigned item x manifest concern x perspective x obligation tuple multiset") unless actual.sort == expected.sort
end

closure_case_ids = case_refs.select do |_case_id, template_ref|
  templates.fetch(template_ref).dig("topology", "closure_verification_required") == true
end.keys
closure_expectations = fixture["canonical_review_closure_expectations"]
fail_with.call("canonical_review_closure_expectations must be an object keyed exactly to closure-required mapped cases") unless closure_expectations.is_a?(Hash) && closure_expectations.keys.sort == closure_case_ids.sort
closure_expectations.each do |case_id, authority|
  fail_with.call("canonical_review_closure_expectations #{case_id.inspect} has an invalid bounded closure authority") unless closure_authority_valid.call(authority)
end
if skill_name == "assistant-review"
  distillation_expectations = fixture["canonical_review_finding_rule_distillation_expectations"]
  fail_with.call("canonical_review_finding_rule_distillation_expectations must be an object keyed exactly to mapped final-summary cases") unless distillation_expectations.is_a?(Hash) && distillation_expectations.keys.sort == case_refs.keys.sort
  distillation_expectations.each do |case_id, authority|
    fields = %w[active_must_fix_aggregate_finding_ids fixed_must_fix_aggregate_finding_ids]
    fail_with.call("canonical_review_finding_rule_distillation_expectations #{case_id.inspect} must contain exactly active and fixed must-fix ids") unless authority.is_a?(Hash) && authority.keys.sort == fields
    fields.each do |field|
      ids = authority[field]
      fail_with.call("canonical_review_finding_rule_distillation_expectations #{case_id.inspect}.#{field} must be a unique string array") unless ids.is_a?(Array) && ids.all? { |finding_id| nonblank.call(finding_id) } && ids.uniq.length == ids.length
    end
  end
end
RUBY
)" || die "$authority_error"

    [[ -z "$authority_error" ]] || die "$authority_error"
}

validate_canonical_feature_preparation_result_authority() {
    local fixture_file="$1"
    local skill_name="$2"
    local authority_error

    [[ "$skill_name" == "assistant-workflow" ]] || return 0

    authority_error="$(ruby -rjson - "$fixture_file" 2>&1 <<'RUBY'
fixture = JSON.parse(File.read(ARGV.fetch(0)))
fail_with = lambda { |message| warn "assistant-workflow canonical_feature_preparation_result_expectations: #{message}"; exit 1 }
nonblank = ->(value) { value.is_a?(String) && !value.strip.empty? }
nonblank_strings = ->(value) { value.is_a?(Array) && value.all? { |item| nonblank.call(item) } }
result_valid = lambda do |result, scope, top_level_evidence_ref|
  required = %w[execution_status scope evidence_gaps open_decisions implementation_implications recommended_next_step]
  optional = %w[feature_preparation_evidence_ref future_harness_obligation future_qa_acceptance_obligation readiness_plan]
  next false unless result.is_a?(Hash) && (result.keys - (required + optional)).empty? && required.all? { |field| result.key?(field) }
  next false unless result["execution_status"] == "not_started" && nonblank.call(result["scope"]) && nonblank_strings.call(result["evidence_gaps"]) && nonblank_strings.call(result["open_decisions"]) && nonblank_strings.call(result["implementation_implications"]) && !result["implementation_implications"].empty? && nonblank.call(result["recommended_next_step"])
  next false if result.key?("feature_preparation_evidence_ref") && !nonblank.call(result["feature_preparation_evidence_ref"])
  if result.key?("future_harness_obligation")
    obligation = result["future_harness_obligation"]
    next false unless obligation.is_a?(Hash) && obligation.keys.sort == %w[evidence_basis execution_prerequisite requested_scope] && nonblank.call(obligation["requested_scope"]) && nonblank_strings.call(obligation["evidence_basis"]) && !obligation["evidence_basis"].empty? && nonblank.call(obligation["execution_prerequisite"])
  end
  if result.key?("future_qa_acceptance_obligation")
    obligation = result["future_qa_acceptance_obligation"]
    next false unless obligation.is_a?(Hash) && obligation.keys.sort == %w[execution_prerequisite requested_scope] && nonblank.call(obligation["requested_scope"]) && nonblank.call(obligation["execution_prerequisite"])
  end
  if result.key?("readiness_plan")
    readiness = result["readiness_plan"]
    common_fields_valid = readiness.is_a?(Hash) && readiness["execution_status"] == "not_started" && nonblank_strings.call(readiness["implementation_implications"]) && !readiness["implementation_implications"].empty? && nonblank_strings.call(readiness["open_decisions"]) && nonblank.call(readiness["recommended_next_state"])
    if scope == "existing_system"
      next false unless common_fields_valid && readiness.keys.sort == %w[evidence_ref execution_status implementation_implications open_decisions recommended_next_state] && readiness["evidence_ref"] == result["feature_preparation_evidence_ref"] && readiness["evidence_ref"] == top_level_evidence_ref
    else
      next false unless common_fields_valid && readiness.keys.sort == %w[execution_status implementation_implications open_decisions preparation_basis recommended_next_state] && readiness["preparation_basis"] == "not_applicable"
    end
  end
  true
end
carrying_categories = %w[feature_preparation_transition feature_preparation_qa_transition]
carrying_cases = Array(fixture["cases"]).select do |test_case|
  carrying_categories.include?(test_case["category"])
end
expected_case_ids = carrying_cases.map { |test_case| test_case.fetch("id") }.sort
authorities = fixture["canonical_feature_preparation_result_expectations"]
if expected_case_ids.empty?
  fail_with.call("must be absent or empty when no implementation projection carries an approved preparation result") unless authorities.nil? || (authorities.is_a?(Hash) && authorities.empty?)
  exit 0
end
fail_with.call("must be an object keyed exactly to every carrying implementation case") unless authorities.is_a?(Hash) && authorities.keys.sort == expected_case_ids
carrying_cases.each do |test_case|
  case_id = test_case.fetch("id")
  authority = authorities.fetch(case_id)
  assertions = Array(test_case.dig("machine_expectations", "structured_json_assertions"))
  execution_intent = assertions.any? do |assertion|
    assertion["operator"] == "equals" && assertion["path"] == ["execution_intent"] && assertion["expected"] == "implement_only"
  end
  fail_with.call("#{case_id.inspect} must assert execution_intent=implement_only") unless execution_intent
  scope_assertion = assertions.find { |assertion| assertion["operator"] == "equals" && assertion["path"] == ["feature_preparation_scope"] }
  scope = scope_assertion && scope_assertion["expected"]
  fail_with.call("#{case_id.inspect} must declare feature_preparation_scope") unless %w[existing_system not_applicable].include?(scope)
  root_to_triage = assertions.any? do |assertion|
    assertion["operator"] == "equals_path" && assertion["path"] == ["approved_feature_preparation_result"] && assertion["other_path"] == ["triage_result", "approved_feature_preparation_result"]
  end
  root_to_implementation_step = assertions.any? do |assertion|
    assertion["operator"] == "equals_path" && assertion["path"] == ["approved_feature_preparation_result"] && assertion["other_path"].is_a?(Array) && assertion["other_path"].length == 3 && assertion["other_path"][0] == "implementation_steps" && assertion["other_path"][1].is_a?(Integer) && assertion["other_path"][1] >= 0 && assertion["other_path"][2] == "approved_feature_preparation_result"
  end
  fail_with.call("#{case_id.inspect} must assert the exact root-to-triage preparation-result projection") unless root_to_triage
  fail_with.call("#{case_id.inspect} must assert an exact root-to-implementation-step preparation-result projection") unless root_to_implementation_step
  top_level_evidence_assertion = assertions.find { |assertion| assertion["operator"] == "equals" && assertion["path"] == ["approved_feature_preparation_evidence_ref"] }
  top_level_evidence_ref = top_level_evidence_assertion && top_level_evidence_assertion["expected"]
  if scope == "existing_system"
    fail_with.call("#{case_id.inspect} existing-system authority must carry the exact top-level evidence ref") unless nonblank.call(top_level_evidence_ref) && authority["feature_preparation_evidence_ref"] == top_level_evidence_ref
  else
    fail_with.call("#{case_id.inspect} not-applicable authority must omit its evidence ref") if authority.key?("feature_preparation_evidence_ref")
    fail_with.call("#{case_id.inspect} not-applicable case must assert no top-level evidence ref") unless assertions.any? { |assertion| assertion["operator"] == "path_absent" && assertion["path"] == ["approved_feature_preparation_evidence_ref"] }
  end
  fail_with.call("#{case_id.inspect} has an invalid bounded preparation-result authority") unless result_valid.call(authority, scope, top_level_evidence_ref)
end
RUBY
)" || die "$authority_error"

    [[ -z "$authority_error" ]] || die "$authority_error"
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

        def case_prompt_packet_mode($index):
          if has("prompt_packet_mode") then
            .prompt_packet_mode as $mode
            | if ($mode | type) != "string"
                or (["task_only", "annotated"] | index($mode)) == null then
                "case[\($index)].prompt_packet_mode must be task_only or annotated when present"
              else
                empty
              end
          else empty end;

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
          elif .operator == "object_keys_exact" then
            .fields as $fields |
            if (.path? | type != "array") or ((.path | length) > 0 and (.path | json_path | not)) or ($fields | distinct_bounded_fields | not) or (($fields | unique | length) != ($fields | length)) then
              "case[\($index)].machine_expectations.structured_json_assertions[\($assertion_index)] invalid object_keys_exact assertion"
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

        def creator_context_valid($context; $index; $case_id; $prompt):
          if ($context | type) != "object" or ($context | keys | sort) != ["creator_evidence"] then
            "case[\($index)].semantic_context must contain only creator_evidence"
          else
            $context.creator_evidence as $creator
            | (["allowed_artifacts", "artifact_checks", "assessment_criteria", "comparison_required", "design_required", "expected_outcome", "operation", "preserved_metadata", "preserved_target_files", "required_artifacts", "run_binding", "schema_version", "skill_category", "skill_name"] | sort) as $creator_fields
            | if ($creator | type) != "object" or ((($creator | keys | sort) != $creator_fields) and (($creator | keys | sort) != ($creator_fields + ["requested_body_change"] | sort))) then
                "case[\($index)].semantic_context.creator_evidence has invalid fields"
              elif $creator.schema_version != "1.0" or ($creator.operation as $operation | ["create", "update", "assess", "refresh_guidance"] | index($operation) == null) or ($creator.expected_outcome as $outcome | ["design_pending_approval", "authoring_complete", "read_only_assessment", "read_only_refresh", "comparison_assessment"] | index($outcome) == null) then
                "case[\($index)].semantic_context.creator_evidence has unsupported version, operation, or outcome"
              elif ($creator | has("requested_body_change")) and $case_id != "narrow-existing-skill-update-preserves-metadata-and-agent-policy" then
                "case[\($index)].semantic_context body changes are reserved for the fixed narrow-update case"
              elif (($creator.operation == "update") != ($creator | has("requested_body_change"))) then
                "case[\($index)].semantic_context narrow updates must freeze their requested body change"
              elif ($creator | has("requested_body_change")) and (($creator.requested_body_change | type) != "object" or ($creator.requested_body_change | keys | sort) != ["after_text", "before_text"] or ($creator.requested_body_change.before_text | nonempty_string | not) or ($creator.requested_body_change.after_text | nonempty_string | not) or $creator.requested_body_change.before_text == $creator.requested_body_change.after_text) then
                "case[\($index)].semantic_context requested body change must have distinct non-empty before_text and after_text"
              elif ($creator.skill_name | nonempty_string | not) or ($creator.skill_name | test("^[a-z0-9]+(?:-[a-z0-9]+)*$") | not) or ($creator.skill_category as $category | ["process", "analysis", "utility"] | index($category) == null) or ($creator.comparison_required | type) != "boolean" then
                "case[\($index)].semantic_context.creator_evidence has invalid target, category, or comparison flag"
              elif $creator.operation == "assess" and $creator.expected_outcome == "read_only_assessment" and ($prompt | contains($creator.skill_name) | not) then
                "case[\($index)] target skill name must appear in the prompt"
              elif ($creator.design_required | type) != "boolean" or ($creator.allowed_artifacts | type) != "array" or ($creator.required_artifacts | type) != "array" or ($creator.preserved_metadata | type) != "array" or ($creator.preserved_target_files | type) != "array" or ($creator.artifact_checks | type) != "array" or ($creator.assessment_criteria | type) != "array" then
                "case[\($index)].semantic_context.creator_evidence artifact and metadata policies must be arrays"
              elif ($creator.allowed_artifacts | any(.[]; (type != "string") or (test("^(SKILL\\.md|agents/openai\\.yaml|contracts/(input|output|phase-gates|handoffs)\\.yaml|evals/cases\\.json)$") | not))) or ($creator.required_artifacts | any(.[]; (type != "string") or (test("^(SKILL\\.md|agents/openai\\.yaml|contracts/(input|output|phase-gates|handoffs)\\.yaml|evals/cases\\.json)$") | not))) or ($creator.preserved_target_files | any(.[]; (type != "string") or (test("^(SKILL\\.md|agents/openai\\.yaml|contracts/(input|output|phase-gates|handoffs)\\.yaml|evals/cases\\.json)$") | not))) then
                "case[\($index)].semantic_context.creator_evidence contains an unsupported target path"
              elif (($creator.allowed_artifacts | length) != ($creator.allowed_artifacts | unique | length)) or (($creator.required_artifacts | length) != ($creator.required_artifacts | unique | length)) or (($creator.preserved_target_files | length) != ($creator.preserved_target_files | unique | length)) or (($creator.preserved_metadata | length) != ($creator.preserved_metadata | unique | length)) or (($creator.assessment_criteria | length) != ($creator.assessment_criteria | unique | length)) or (($creator.artifact_checks | map([.path,.name] | join("#")) | unique | length) != ($creator.artifact_checks | length)) then
                "case[\($index)].semantic_context.creator_evidence contains duplicate policy values"
              elif ($creator.required_artifacts - $creator.allowed_artifacts | length) != 0 or ($creator.preserved_target_files - $creator.allowed_artifacts | length) != 0 or ($creator.preserved_metadata - ["name", "description", "compatibility", "license", "metadata", "allowed-tools", "policy", "requires"] | length) != 0 or ($creator.assessment_criteria | any(.[]; nonempty_string | not)) then
                "case[\($index)].semantic_context.creator_evidence policy is outside its fixed allowlist"
              elif ($creator.artifact_checks | any(.[]; (type != "object") or (keys | sort) != ["name", "path", "recovery_field", "section", "type"] or (.path as $path | ["contracts/input.yaml", "contracts/output.yaml", "contracts/phase-gates.yaml", "contracts/handoffs.yaml"] | index($path) == null) or (.section as $section | ["fields", "artifacts"] | index($section) == null) or (.recovery_field as $recovery | ["on_missing", "on_fail"] | index($recovery) == null) or (.name | nonempty_string | not) or (.type | nonempty_string | not) or (.path as $path | $creator.required_artifacts | index($path) == null))) then
                "case[\($index)].semantic_context.creator_evidence content check is not bound to a required contract artifact"
              elif ($creator.comparison_required != ($creator.expected_outcome == "comparison_assessment")) then
                "case[\($index)].semantic_context.creator_evidence comparison flag must match the outcome"
              elif (["design_pending_approval", "authoring_complete"] | index($creator.expected_outcome) != null) and (["create", "update"] | index($creator.operation) == null) then
                "case[\($index)].semantic_context.creator_evidence authoring outcome requires create or update"
              elif $creator.expected_outcome == "read_only_assessment" and $creator.operation != "assess" then
                "case[\($index)].semantic_context.creator_evidence assessment outcome requires assess"
              elif $creator.expected_outcome == "read_only_refresh" and $creator.operation != "refresh_guidance" then
                "case[\($index)].semantic_context.creator_evidence refresh outcome requires refresh_guidance"
              elif $creator.expected_outcome == "comparison_assessment" and $creator.operation != "assess" then
                "case[\($index)].semantic_context.creator_evidence comparison outcome requires assess"
              elif (["design_pending_approval", "read_only_assessment", "read_only_refresh", "comparison_assessment"] | index($creator.expected_outcome) != null) and (($creator.allowed_artifacts | length) != 0 or ($creator.required_artifacts | length) != 0 or ($creator.preserved_target_files | length) != 0 or ($creator.artifact_checks | length) != 0) then
                "case[\($index)].semantic_context.creator_evidence non-writing outcome must not allow target artifacts"
              elif $creator.expected_outcome == "authoring_complete" and (($creator.required_artifacts | length) == 0 or ($creator.allowed_artifacts | length) == 0) then
                "case[\($index)].semantic_context.creator_evidence completed authoring requires fixed output paths"
              elif ($creator.operation == "update") != (($creator.preserved_metadata | length) > 0) then
                "case[\($index)].semantic_context.creator_evidence update preservation fields must be explicit"
              elif ($creator.expected_outcome == "design_pending_approval") and ($creator.design_required | not) then
                "case[\($index)].semantic_context.creator_evidence pending design must require approval"
              elif (["read_only_assessment", "read_only_refresh", "comparison_assessment"] | index($creator.expected_outcome) != null) and $creator.design_required then
                "case[\($index)].semantic_context.creator_evidence read-only operations cannot require a design gate"
              elif (($creator.operation == "assess") != (($creator.assessment_criteria | length) > 0)) then
                "case[\($index)].semantic_context.creator_evidence assessment criteria must match assess operations"
              elif $creator.run_binding != null and (($creator.run_binding | type) != "object" or ($creator.run_binding | keys | sort) != ["capture_id", "comparison_sha256", "output_root", "run_id", "source_root", "source_snapshot_sha256"] or ($creator.run_binding.capture_id | nonempty_string | not) or ($creator.run_binding.run_id | nonempty_string | not) or ($creator.run_binding.output_root | nonempty_string | not) or ($creator.run_binding.output_root | test("^/" ) | not) or ($creator.run_binding.source_root != null and (($creator.run_binding.source_root | nonempty_string | not) or ($creator.run_binding.source_root | test("^/") | not))) or ($creator.run_binding.source_snapshot_sha256 != null and ($creator.run_binding.source_snapshot_sha256 | test("^sha256:[0-9a-f]{64}$") | not)) or ($creator.run_binding.comparison_sha256 != null and ($creator.run_binding.comparison_sha256 | test("^sha256:[0-9a-f]{64}$") | not))) then
                "case[\($index)].semantic_context.creator_evidence run binding is malformed"
              elif $creator.run_binding != null and (($creator.run_binding.comparison_sha256 != null) != $creator.comparison_required) then
                "case[\($index)].semantic_context.creator_evidence run binding comparison digest must match the fixture"
              elif $creator.run_binding != null and ((["update", "assess"] | index($creator.operation) != null) != ($creator.run_binding.source_root != null and $creator.run_binding.source_snapshot_sha256 != null)) then
                "case[\($index)].semantic_context.creator_evidence run binding source identity must match the operation"
              elif ($creator.operation != "update") and (($creator.preserved_target_files | length) > 0) then
                "case[\($index)].semantic_context.creator_evidence preserved target files require update"
              else empty
              end
          end;

        def case_semantic_context($index):
          if has("semantic_context") and $skill_name == "assistant-workflow" then
            .semantic_context as $context
            | if ($context | type) != "object" or ($context | keys) != ["packet_admission"] then
                "case[\($index)].semantic_context must contain only packet_admission"
              elif ($context.packet_admission | type) != "object" or ($context.packet_admission | keys | sort) != ["expected_code", "expected_status", "request"] then
                "case[\($index)].packet_admission has invalid fields"
              elif ($context.packet_admission.request | type) != "object" or ($context.packet_admission.request.context | type) != "object" or ($context.packet_admission.request.plan | type) != "object" or ($context.packet_admission.expected_status as $status | ["accepted", "blocked"] | index($status) == null) or ($context.packet_admission.expected_code | nonempty_string | not) then
                "case[\($index)].packet_admission requires fixed authority, plan and expected admission"
              else empty end
          elif has("semantic_context") and $skill_name == "assistant-skill-creator" then
            creator_context_valid(.semantic_context; $index; .id; .prompt)
          elif has("semantic_context") and $skill_name == "assistant-research" then
            .semantic_context as $context
            | if ($context | type) != "object" or ($context | keys | sort) != ["adapter_context", "follow_up_requirements", "high_stakes_context", "packet_scope", "required_topic_terms"] then
                "case[\($index)].semantic_context must contain exactly packet_scope, follow_up_requirements, required_topic_terms, high_stakes_context, and adapter_context"
              elif ($context.packet_scope? | type) != "object" or ($context.packet_scope | keys | sort) != ["output_purpose", "question", "user_role_or_goal"] then
                "case[\($index)].semantic_context.packet_scope must contain exactly question, user_role_or_goal, and output_purpose"
              elif ($context.packet_scope | [.question, .user_role_or_goal, .output_purpose] | all(.[]; nonempty_string) | not) then
                "case[\($index)].semantic_context.packet_scope fields must be non-empty strings"
              elif ($context.required_topic_terms? | type) != "array" or ($context.required_topic_terms | all(.[]; nonempty_string) | not) then
                "case[\($index)].semantic_context.required_topic_terms must be an array of non-empty strings"
              elif ($context.required_topic_terms | unique | length) != ($context.required_topic_terms | length) then
                "case[\($index)].semantic_context.required_topic_terms values must be unique"
              elif ($context.follow_up_requirements? | type) != "array" then
                "case[\($index)].semantic_context.follow_up_requirements must be an array"
              elif ($context.follow_up_requirements | all(.[]; type == "object" and (keys | sort) == ["decision", "exact_count", "lens_kind"] and (.lens_kind as $lens | ["practitioner", "academic_or_technical_expert", "skeptic", "economist_or_incentives_analyst", "historian_or_pattern_matcher"] | index($lens) != null) and (.decision as $decision | ["follow_up", "none_needed"] | index($decision) != null) and (.exact_count | type == "number" and . > 0 and (. % 1) == 0)) | not) then
                "case[\($index)].semantic_context.follow_up_requirements rows must be exact typed requirements"
              elif ($context.follow_up_requirements | map(.lens_kind) | unique | length) != ($context.follow_up_requirements | length) then
                "case[\($index)].semantic_context.follow_up_requirements lens_kind values must be unique"
              elif ($context.adapter_context? | type) != "object" or ($context.adapter_context | keys | sort) != ["max_concurrent_lens_workers"] or ($context.adapter_context.max_concurrent_lens_workers | type != "number" or . <= 0 or . > 9007199254740991 or floor != .) then
                "case[\($index)].semantic_context.adapter_context must contain a positive integer max_concurrent_lens_workers"
              elif ($context.high_stakes_context? | type) != "object" or ($context.high_stakes_context | keys | sort) != ["applicable", "caveat_or_not_applicable_reason", "user_context_basis", "user_context_status"] then
                "case[\($index)].semantic_context.high_stakes_context must contain exactly applicable, caveat_or_not_applicable_reason, user_context_status, and user_context_basis"
              elif ($context.high_stakes_context.applicable | type) != "boolean" or ($context.high_stakes_context.caveat_or_not_applicable_reason | nonempty_string | not) or ($context.high_stakes_context.user_context_status as $status | ["explicit", "unresolved", "not_applicable"] | index($status) == null) or ($context.high_stakes_context.user_context_basis | nonempty_string | not) then
                "case[\($index)].semantic_context.high_stakes_context has invalid fields"
              elif (($context.high_stakes_context.applicable and ($context.high_stakes_context.user_context_status | IN("explicit", "unresolved"))) or ((($context.high_stakes_context.applicable | not) and $context.high_stakes_context.caveat_or_not_applicable_reason == "not_applicable" and $context.high_stakes_context.user_context_status == "not_applicable" and $context.high_stakes_context.user_context_basis == "not_applicable")) | not) then
                "case[\($index)].semantic_context.high_stakes_context violates applicability truth table"
              elif $context.high_stakes_context.user_context_status == "explicit" and (.prompt | contains($context.high_stakes_context.user_context_basis) | not) then
                "case[\($index)].semantic_context explicit user_context_basis must appear in prompt"
              else empty
              end
          elif has("semantic_validator") then
            "case[\($index)] semantic_validator requires a supported semantic_context"
          else empty
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
                 case_prompt_packet_mode($index),
                 case_machine_expectations($index),
                 case_seeded_defects($index),
                 case_semantic_context($index)
               end
           else empty end)
        end
    ' "$fixture_file")" || die "Fixture is not valid JSON: $(display_path "$fixture_file")"

    if [[ -n "$validation_error" ]]; then
        echo "$(display_path "$fixture_file"): $validation_error" >&2
        exit 1
    fi

    validate_assertion_contract_paths "$fixture_file" "$skill_name"
    validate_canonical_review_batch_authority "$fixture_file" "$skill_name"
    validate_canonical_feature_preparation_result_authority "$fixture_file" "$skill_name"

    validation_error="$(jq -r --arg skill_name "$skill_name" '
        def five_lens_case_ids:
          ["five-lens-decision-briefing-uses-storm-style-workflow", "five-lens-quick-normalizes-to-standard", "five-lens-retains-all-material-follow-ups"];
        def historical_v4_five_lens_case_ids:
          ["five-lens-decision-briefing-uses-storm-style-workflow", "five-lens-delegated-lenses-sequential-peer-fallback", "five-lens-quick-normalizes-to-standard", "five-lens-retains-all-material-follow-ups", "five-lens-sequential-fallback-preserves-process-evidence"];
        def packet_case_ids:
          ["packet-admission-coherent-medium-v14", "native-slice-execution-uses-dependencies-not-runner-topology", "isolated-independent-slices-integrate-before-review"];
        def creator_case_ids:
          ["new-process-skill-designs-contracts-before-build", "narrow-existing-skill-update-preserves-metadata-and-agent-policy", "create-minimal-utility-validates-label-to-slug-contract", "assess-existing-skill-without-authoring", "refresh-guidance-is-read-only-and-provenance-bound", "assess-skill-contracts-under-frozen-comparison"];
        [ .cases[] | .id ] as $case_ids
        | [ .cases[] | select(has("semantic_validator")) | {id, semantic_validator} ] as $declared
        | if $skill_name == "assistant-research" and (five_lens_case_ids - $case_ids | length) == 0 and ($declared | length) == 0 then "five-lens assistant-research cases must declare their semantic validator"
          elif $skill_name == "assistant-skill-creator" and (creator_case_ids - $case_ids | length) == 0 and ($declared | length) == 0 then "creator behavior cases must declare their semantic validator"
          elif $skill_name == "assistant-workflow" and (packet_case_ids - $case_ids | length) == 0 and ($declared | length) == 0 then "packet admission cases must declare their semantic validator"
          elif ($declared | length) == 0 then empty
          elif $skill_name == "assistant-research" and ($declared | map(.id) | sort) == historical_v4_five_lens_case_ids and ($declared | all(.semantic_validator == "assistant-research.five_lens_v4")) then empty
          elif $skill_name == "assistant-research" and ($declared | map(.id) | sort) != five_lens_case_ids then "semantic_validator must be declared by exactly the three current v5 five-lens assistant-research cases, or by exactly the five frozen historical v4 cases"
          elif $skill_name == "assistant-research" and ($declared | all(.semantic_validator == "assistant-research.five_lens_v5")) then empty
          elif $skill_name == "assistant-skill-creator" and ($declared | map(.id) | sort) != (creator_case_ids | sort) then "semantic_validator must be declared by exactly the six fixed assistant-skill-creator cases"
          elif $skill_name == "assistant-skill-creator" and ($declared | all(.semantic_validator == "assistant-skill-creator.behavior_v1")) then empty
          elif $skill_name == "assistant-workflow" and ($declared | map(.id) | sort) != (packet_case_ids | sort) then "semantic_validator must be declared by exactly the three fixed packet-admission cases"
          elif $skill_name == "assistant-workflow" and ($declared | all(.semantic_validator == "assistant-workflow.packet_admission_v15")) then empty
          else "semantic_validator is only supported by its exact assistant-research or assistant-skill-creator case allowlist" end
    ' "$fixture_file")" || die "Fixture is not valid JSON: $(display_path "$fixture_file")"
    [[ -z "$validation_error" ]] || die "$validation_error"
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
