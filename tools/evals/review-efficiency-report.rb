#!/usr/bin/env ruby
# frozen_string_literal: true
# Source-only, read-only importer for normalized native captures. It does not
# invoke a model, infer missing children or turn requested models into observations.
require 'json'
require 'digest'
require 'bigdecimal'
require 'date'

module ReviewEfficiencyReport
  MAX_BYTES = 16 * 1024 * 1024
  METRICS = %w[repeated_processing_bytes repeated_retrieval_bytes validation_calls schema_repair_calls coordination_turns latency_ms repair_work_units].freeze
  MATCH_KEYS = %w[task_snapshot models_efforts tools concurrency stopping_conditions acceptance_state oracle_ref].freeze
  class StrictObject < Hash
    def []=(key, value)
      raise ArgumentError, 'duplicate_json_key' if key?(key)
      super
    end
  end
  module_function

  def parse_json(bytes)
    JSON.parse(bytes, max_nesting: 64, object_class: StrictObject, create_additions: false)
  end

  def expect(condition, message)
    raise ArgumentError, message unless condition
  end

  def text?(value)
    value.is_a?(String) && !value.strip.empty?
  end

  def unique(values, label)
    expect(values.uniq.length == values.length, label)
  end

  # The shipped schema owns field/type constraints; no second control schema.
  def schema_value?(value, schema)
    types = {'object'=>Hash,'array'=>Array,'string'=>String,'integer'=>Integer,'number'=>Numeric}
    type = schema.fetch('type')
    return false unless types.key?(type) && value.is_a?(types[type])
    return false if schema.key?('minimum') && value < schema['minimum']
    return false if schema.key?('minLength') && value.length < schema['minLength']
    return false if schema.key?('pattern') && !Regexp.new(schema['pattern']).match?(value)
    return false if schema.key?('minItems') && value.length < schema['minItems']
    if type == 'object'
      properties = schema.fetch('properties')
      return false unless (schema.fetch('required', []) - value.keys).empty?
      return false if schema['additionalProperties'] == false && !(value.keys - properties.keys).empty?
      return value.all? { |key, item| properties.key?(key) && schema_value?(item, properties[key]) }
    end
    type != 'array' || value.all? { |item| schema_value?(item, schema.fetch('items')) }
  end

  def frozen_schema
    @frozen_schema ||= ReviewEfficiencyReport.parse_json(File.read(File.expand_path('../../docs/evals/review-efficiency-result.schema.json', __dir__))).fetch('$defs').fetch('capture_input').fetch('properties').fetch('runs').fetch('items').fetch('properties').fetch('frozen')
  end

  # Evidence references identify each observation, not the controlled treatment.
  def controlled_frozen(frozen)
    identities = frozen.fetch('models_efforts')
    expect(identities.is_a?(Array) && !identities.empty?, 'model_inventory_invalid')
    models = identities.map do |identity|
      expect(%w[requested_model observed_model reasoning_effort identity_evidence_ref].all? { |key| text?(identity[key]) }, 'model_inventory_invalid')
      identity.slice('requested_model', 'observed_model', 'reasoning_effort')
    end
    unique(models, 'model_inventory_duplicate')
    frozen.slice(*MATCH_KEYS).merge('models_efforts'=>models.sort_by { |identity| JSON.generate(identity) })
  end

  # Anonymous observations may be replays of each other or of any known ID,
  # including IDs in other runs. Never assume they are independent consumption.
  def observed_token_lower_bound(responses)
    known = {}
    anonymous_max = 0
    responses.each do |response|
      amount = %w[input_tokens output_tokens].sum do |field|
        value = response[field]
        value.is_a?(Integer) && value >= 0 ? value : 0
      end
      id = response['native_response_id']
      if text?(id)
        if known.key?(id)
          expect(known[id] == response, 'native_response_identity_conflict')
        else
          known[id] = response
        end
      else
        anonymous_max = [anonymous_max, amount].max
      end
    end
    known_sum = known.values.sum do |response|
      %w[input_tokens output_tokens].sum { |field| response[field].is_a?(Integer) && response[field] >= 0 ? response[field] : 0 }
    end
    [known_sum, anonymous_max].max
  end

  def usage_for(run, rates)
    reasons = []
    nodes = run.fetch('native_tree')
    expect(nodes.is_a?(Array) && !nodes.empty?, 'native_tree_invalid')
    unique(nodes.map { |n| n.fetch('invocation_id') }, 'invocation_identity_duplicate')
    ids = nodes.map { |n| n.fetch('invocation_id') }
    expect(nodes.all? { |node| node.key?('parent_id') && (node['parent_id'].nil? || text?(node['parent_id'])) }, 'parent_identity_invalid')
    roots = nodes.select { |n| n['parent_id'].nil? }
    reasons << 'parent_tree_incomplete' unless roots.length == 1
    nodes.each do |node|
      expect(text?(node['invocation_id']) && node['children'].is_a?(Array), 'invocation_identity_invalid')
      reasons << 'children_inventory_unknown' unless node['inventory_complete'] == true && text?(node['inventory_evidence_ref'])
      children = nodes.select { |n| n['parent_id'] == node['invocation_id'] }.map { |n| n['invocation_id'] }
      reasons << 'children_inventory_incomplete' unless node['children'].sort == children.sort && node['children'].uniq.length == node['children'].length
      reasons << 'parent_tree_incomplete' unless node['parent_id'].nil? || ids.include?(node['parent_id'])
      visited = []
      current = node
      while current && current['parent_id']
        expect(!visited.include?(current['invocation_id']), 'native_tree_cycle')
        visited << current['invocation_id']
        current = nodes.find { |n| n['invocation_id'] == current['parent_id'] }
      end
    end
    seen = {}
    sums = {'input_tokens'=>0,'cached_input_tokens'=>0,'output_tokens'=>0,'reasoning_output_tokens'=>0}
    cost = BigDecimal('0')
    nodes.each do |node|
      reasons << 'response_inventory_unknown' unless node['responses_complete'] == true
      node.fetch('responses').each do |response|
        id = response['native_response_id']
        unless text?(id)
          reasons << 'response_identity_unknown'
          next
        end
        if seen.key?(id)
          expect(seen[id] == response, 'native_response_identity_conflict')
          next
        end
        seen[id] = response
        unless %w[usage_evidence_ref observed_model model_evidence_ref observed_effort effort_evidence_ref].all? { |field| text?(response[field]) }
          reasons << 'response_usage_or_model_identity_unknown'
          next
        end
        valid = sums.keys.all? { |field| response[field].is_a?(Integer) && response[field] >= 0 }
        valid &&= response['cached_input_tokens'] <= response['input_tokens'] && response['reasoning_output_tokens'] <= response['output_tokens']
        unless valid
          reasons << 'usage_missing_or_subset_invalid'
          next
        end
        actual = run.fetch('frozen').fetch('models_efforts')
        expect(actual.is_a?(Array) && actual.any? { |identity| identity['observed_model'] == response['observed_model'] && identity['reasoning_effort'] == response['observed_effort'] && text?(identity['identity_evidence_ref']) }, 'actual_model_effort_mismatch')
        rate = rates.find { |r| r['model'] == response['observed_model'] }
        reasons << 'actual_model_rate_missing' unless rate
        sums.each_key { |field| sums[field] += response[field] }
        if rate
          cost += (BigDecimal((response['input_tokens'] - response['cached_input_tokens']).to_s) * BigDecimal(rate.fetch('input_per_million').to_s) + BigDecimal(response['cached_input_tokens'].to_s) * BigDecimal(rate.fetch('cached_input_per_million').to_s) + BigDecimal(response['output_tokens'].to_s) * BigDecimal(rate.fetch('output_per_million').to_s)) / 1_000_000
        end
      end
    end
    reasons << 'native_response_inventory_empty' if seen.empty?
    if reasons.empty?
      observed = seen.values.map { |response| [response['observed_model'], response['observed_effort']] }.uniq.sort
      declared = run.fetch('frozen').fetch('models_efforts').map { |identity| [identity['observed_model'], identity['reasoning_effort']] }.uniq.sort
      expect(observed == declared, 'observed_model_inventory_mismatch')
    end
    {'complete'=>reasons.empty?,'reasons'=>reasons.uniq.sort,'unique_response_count'=>seen.length,'observed_token_lower_bound'=>observed_token_lower_bound(nodes.flat_map { |node| node.fetch('responses') }),'usage'=>reasons.empty? ? sums : nil,'normalized_cost'=>reasons.empty? ? cost.to_s('F') : nil}
  end

  def quality_for(run)
    q=run.fetch('adjudication')
    expect(q['variant_blind']==true && %w[adjudicator_ref oracle_ref evidence_ref].all?{|k|text?(q[k])}, 'independent_variant_blind_adjudication_required')
    %w[required_material_finding_ids found_material_finding_ids first_batch_found_ids later_only_ids false_positive_ids lost_finding_ids].each do |key|
      expect(q[key].is_a?(Array) && q[key].all?{|v|text?(v)}, 'adjudication_ids_invalid')
      unique(q[key], 'adjudication_ids_duplicate')
    end
    expect([true,false].include?(q['false_clean']) && [true,false].include?(q['broken_closure']), 'adjudication_state_invalid')
    expect(q['oracle_ref']==run.dig('frozen','oracle_ref'), 'oracle_identity_mismatch')
    expect((q['first_batch_found_ids']-q['found_material_finding_ids']).empty? && (q['later_only_ids']-q['found_material_finding_ids']).empty? && (q['first_batch_found_ids'] & q['later_only_ids']).empty? && (q['first_batch_found_ids']+q['later_only_ids']).sort==q['found_material_finding_ids'].sort, 'finding_timing_invalid')
    material=q['required_material_finding_ids'];found=q['found_material_finding_ids']
    {'material_misses'=>material-found,'first_batch_recall'=>material.empty? ? nil : (q['first_batch_found_ids'] & material).length.to_f/material.length,'false_positives'=>q['false_positive_ids'],'later_only_findings'=>q['later_only_ids'],'lost_findings'=>q['lost_finding_ids'],'false_clean'=>q['false_clean'],'broken_closure'=>q['broken_closure']}
  end

  def report(input)
    expect(input['schema_version']=='1.0','schema_version_invalid')
    budget=input.fetch('workload_ceiling')
    %w[max_runs max_tokens max_elapsed_ms].each{|k|expect(budget[k].is_a?(Integer)&&budget[k]>0,'workload_ceiling_invalid')}
    table=input.fetch('rate_table')
    expect(Date.iso8601(table.fetch('as_of')).to_s==table['as_of'] && text?(table['source_ref']) && table['currency']=='USD','dated_rate_table_required')
    rates=table.fetch('rates');unique(rates.map{|r|r['model']},'rate_model_duplicate')
    rates.each{|r|expect(text?(r['model']) && %w[input_per_million cached_input_per_million output_per_million].all?{|k|r[k].is_a?(Numeric)&&r[k].finite?&&r[k]>=0},'rate_invalid')}
    runs=input.fetch('runs');expect(runs.is_a?(Array)&&runs.length<=budget['max_runs'],'workload_ceiling_exceeded')
    unique(runs.map{|r|r['run_id']},'run_identity_duplicate')
    response_owners = {}
    runs.each do |run|
      run.fetch('native_tree').each do |node|
        node.fetch('responses').each do |response|
          id = response['native_response_id']
          next unless text?(id)
          expect(!response_owners.key?(id) || response_owners[id] == run['run_id'], 'native_response_reused_across_runs')
          response_owners[id] = run['run_id']
        end
      end
    end
    summaries=runs.map do |run|
      expect(%w[canary development cross_file temporal compatibility authority_boundary clean_control].include?(run['case_class']) && [true,false].include?(run['held_out']), 'case_class_invalid')
      expect(%w[A B C].include?(run['variant']) && text?(run['run_id']) && text?(run['case_id']) && run['repetition'].is_a?(Integer)&&run['repetition']>0 && run['run_order'].is_a?(Integer)&&run['run_order']>0,'run_identity_invalid')
      frozen=run.fetch('frozen')
      expect((MATCH_KEYS+%w[source_snapshot loaded_skill_digest cache_observation]).all?{|k|frozen.key?(k)},'frozen_identity_incomplete')
      expect(%w[source_snapshot loaded_skill_digest task_snapshot oracle_ref acceptance_state].all?{|k|text?(frozen[k])},'frozen_identity_incomplete')
      expect(schema_value?(frozen, frozen_schema),'frozen_controls_invalid')
      controlled_frozen(frozen)
      metrics=run.fetch('metrics');expect(METRICS.all?{|k|metrics[k].is_a?(Integer)&&metrics[k]>=0},'metrics_incomplete')
      {'run_id'=>run['run_id'],'variant'=>run['variant'],'case_id'=>run['case_id'],'repetition'=>run['repetition'],'run_order'=>run['run_order'],'case_class'=>run['case_class'],'held_out'=>run['held_out'],'frozen'=>frozen,'capture'=>usage_for(run,rates),'quality'=>quality_for(run),'metrics'=>metrics}
    end
    unique(summaries.map{|r|[r['variant'],r['case_id'],r['repetition']]},'trial_identity_duplicate')
    summaries.group_by{|r|r['variant']}.each_value do |trials|
      expect(trials.map{|r|r['frozen'].slice('source_snapshot','loaded_skill_digest')}.uniq.length==1,'variant_source_drift')
    end
    summaries.group_by{|r|[r['variant'],r['case_id']]}.each_value do |trials|
      pinned=trials.map{|r|controlled_frozen(r['frozen']).merge(r['frozen'].slice('source_snapshot','loaded_skill_digest'))}
      expect(pinned.uniq.length==1,'variant_source_or_control_drift')
    end
    unique(summaries.map{|r|r['run_order']},'run_order_duplicate')
    expect(summaries.sum{|r|r['metrics']['latency_ms']}<=budget['max_elapsed_ms'],'workload_ceiling_exceeded')
    token_sum=observed_token_lower_bound(runs.flat_map{|run|run.fetch('native_tree').flat_map{|node|node.fetch('responses')}})
    expect(token_sum<=budget['max_tokens'],'workload_ceiling_exceeded')
    comparisons=[['A','B'],['B','C']].map do |base,candidate|
      pairs=[]
      summaries.select{|r|r['variant']==base}.each do |left|
        matches=summaries.select{|r|r['variant']==candidate && r['case_id']==left['case_id'] && r['repetition']==left['repetition']}
        expect(matches.length<=1,'pair_identity_duplicate')
        next if matches.empty?
        right=matches.first
        expect(controlled_frozen(left['frozen'])==controlled_frozen(right['frozen']),'unmatched_comparison')
        expect(left['frozen']['source_snapshot']!=right['frozen']['source_snapshot'],'source_variants_not_frozen')
        expect(left['case_class']==right['case_class'] && left['held_out']==right['held_out'],'unmatched_case_class')
        reasons=[]
        q=right['quality'];bq=left['quality']
        original_left=runs.find{|r|r['run_id']==left['run_id']}
        original_right=runs.find{|r|r['run_id']==right['run_id']}
        expect(original_left['adjudication']['required_material_finding_ids'].sort==original_right['adjudication']['required_material_finding_ids'].sort,'unmatched_quality_oracle')
        reasons << 'candidate_only_material_miss' unless (q['material_misses']-bq['material_misses']).empty?
        reasons << 'false_clean' if q['false_clean']
        reasons << 'lost_finding' unless q['lost_findings'].empty?
        reasons << 'broken_closure' if q['broken_closure']
        reasons << 'increased_false_positives' if q['false_positives'].length>bq['false_positives'].length
        reasons << 'incomplete_native_usage' unless left['capture']['complete']&&right['capture']['complete']
        delta=reasons.include?('incomplete_native_usage') ? nil : BigDecimal(left['capture']['normalized_cost'])-BigDecimal(right['capture']['normalized_cost'])
        pairs << {'baseline_run_id'=>left['run_id'],'candidate_run_id'=>right['run_id'],'case_id'=>left['case_id'],'repetition'=>left['repetition'],'case_class'=>left['case_class'],'held_out'=>left['held_out'],'baseline_first'=>left['run_order']<right['run_order'],'rejection_reasons'=>reasons,'normalized_cost_saving'=>delta&.to_s('F'),'metric_reductions'=>METRICS.to_h{|k|[k,left['metrics'][k]-right['metrics'][k]]}}
      end
      unique(pairs.map{|p|p['candidate_run_id']},'candidate_trial_reused')
      reasons=pairs.flat_map{|p|p['rejection_reasons']}.uniq
      costs=summaries.select{|r|r['variant']==base&&r['capture']['complete']}.group_by{|r|r['case_id']}.values.map{|rs|v=rs.map{|r|BigDecimal(r['capture']['normalized_cost'])};v.max-v.min}
      variation=costs.max||BigDecimal('0')
      deltas=pairs.map{|p|p['normalized_cost_saving']&&BigDecimal(p['normalized_cost_saving'])}.compact
      candidate_ranges=summaries.select{|r|r['variant']==candidate&&r['capture']['complete']}.group_by{|r|r['case_id']}.values.map{|rs|v=rs.map{|r|BigDecimal(r['capture']['normalized_cost'])};v.max-v.min}
      paired_ranges=pairs.group_by{|p|p['case_id']}.values.map do |ps|
        values=ps.map{|p|p['normalized_cost_saving']&&BigDecimal(p['normalized_cost_saving'])}.compact
        values.empty? ? BigDecimal('0') : values.max-values.min
      end
      effective_variation=([variation]+candidate_ranges+paired_ranges).max
      mean=deltas.empty? ? nil : deltas.sum/deltas.length
      eligible=pairs.length>=2 && pairs.map{|p|p['baseline_first']}.uniq.length==2 && pairs.group_by{|p|p['case_id']}.values.all?{|ps|ps.map{|p|p['repetition']}.uniq.length>=2}
      decision=if !reasons.empty? then 'rejected' elsif !eligible || mean.nil? || mean<=effective_variation then 'inconclusive' else 'observed_saving_within_workload' end
      quality_classes = pairs.select { |p| p['held_out'] }.map { |p| p['case_class'] }.uniq
      quality_evidence = (%w[cross_file temporal compatibility authority_boundary clean_control]-quality_classes).empty? && reasons.empty? ? 'bounded_held_out_evidence' : 'incomplete_held_out_workload'
      {'quality_evidence'=>quality_evidence,'baseline'=>base,'candidate'=>candidate,'pairs'=>pairs,'actual_pair_count'=>pairs.length,'observed_baseline_cost_range'=>variation.to_s('F'),'effective_cost_variation_bound'=>effective_variation.to_s('F'),'mean_normalized_cost_saving'=>mean&.to_s('F'),'decision'=>decision,'limitations'=>['Native completeness and semantic adjudication are caller-attested evidence, not inferred by this importer.','Savings at or below observed variation are inconclusive; no universal quality or subscription-limit claim.']}
    end
    {'schema_version'=>'1.0','input_sha256'=>Digest::SHA256.hexdigest(JSON.generate(input)),'rate_table'=>table,'actual_run_count'=>summaries.length,'runs'=>summaries,'comparisons'=>comparisons,'claims'=>{'universal_non_regression'=>false,'subscription_limit_percentage'=>nil}}
  end
end

if $PROGRAM_NAME==__FILE__
  begin
    raise ArgumentError,'stdin_only' unless ARGV.empty?
    bytes=STDIN.read(ReviewEfficiencyReport::MAX_BYTES+1)
    raise ArgumentError,'input_too_large' if bytes.bytesize>ReviewEfficiencyReport::MAX_BYTES
    result=ReviewEfficiencyReport.report(ReviewEfficiencyReport.parse_json(bytes))
    puts JSON.pretty_generate(result)
  rescue ArgumentError, KeyError, TypeError, NoMethodError, JSON::ParserError, ArgumentError
    puts JSON.generate('valid'=>false,'diagnostics'=>['invalid_or_incomplete_measurement_input'])
    exit 1
  end
end
