#!/usr/bin/env bash
if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "review tools reject replay, authority, tuple, status and terminal/aggregate false passes"
source "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-fixtures.sh"
if {
    skill_eval_companion_contracts_ruby
    cat <<'RUBY'
ReviewTools.use(File.join(ARGV.fetch(0), 'skills/assistant-review/scripts/review-tools.py'))
def copy(value); Marshal.load(Marshal.dump(value)); end
def assert(value, label); abort "review-tools: #{label}" unless value; end
observed = []
requests = []
check = lambda do |operation, authority, candidate, expected, label|
  request = {'operation' => operation, 'authority' => authority, 'candidate' => candidate}
  requests << [copy(request), expected]
  result = ReviewTools.call(request)
  assert(result['valid'] == expected, "#{label}: #{result['diagnostics'].inspect}")
  observed << [expected, result['valid']]
  result
end
snapshot = {'basis'=>'content_digest','value'=>'sha256:source','captured_at'=>'2026-10-23T12:00:00Z','scope_manifest_digest'=>'sha256:manifest'}
binding = {'task_id'=>'task','native_invocation_id'=>'native-p1','batch_id'=>'batch','review_snapshot_id'=>'snapshot','review_pass_id'=>'p1','review_attempt_id'=>'p1:retry-7','producer_id'=>'reviewer','producer_version'=>'v9','source_digest'=>'sha256:source'}
authority = {'dispatch_binding'=>binding,'history_known'=>true,'records'=>[],'archives'=>{}}
delivery = {'binding'=>binding,'complete'=>true,'payload'=>'{"summary":"complete"}','payload_ref'=>'raw:1','event_id'=>'event:1'}
identified = check.call('identify_return',authority,delivery,true,'new complete return')
assert(identified.dig('result','classification')=='new_evidence','new evidence classification')
['complete native prose return', '{"status":', '', [0xc4,0x97].pack('C*')].each do |opaque|
 opaque_result=check.call('identify_return',authority,delivery.merge('payload'=>opaque),true,'complete opaque/schema-invalid raw receipt')
 assert(opaque_result.dig('result','payload_sha256')==Digest::SHA256.hexdigest(opaque),'opaque receipt did not hash raw bytes')
 assert(opaque.encoding==Encoding::ASCII_8BIT,'caller binary evidence was mutated') if opaque.bytes==[0xc4,0x97]
end
record = {'binding'=>copy(binding),'payload_ref'=>'raw:1','payload_sha256'=>Digest::SHA256.hexdigest(delivery['payload']),'event_ids'=>['event:1']}
retained = copy(authority);retained['records']=[record];retained['archives']={'raw:1'=>delivery['payload']}
result=check.call('identify_return',retained,delivery,true,'same native event replay')
assert(result.dig('result','classification')=='exact_replay','replay is idempotent')
result=check.call('identify_return',retained,delivery.merge('event_id'=>'event:2'),true,'distinct identical delivery')
assert(result.dig('result','classification')=='duplicate' && result.dig('result','closes_coverage')==false && result.dig('result','advances_progress')==false,'duplicate does not close/progress')
[
 ['same agent changed return', ->(a,c){c['payload']='{"summary":"changed"}';c['event_id']='event:2'}],
 ['native event reused with changed payload',->(a,c){c['payload']='{"summary":"changed"}'}],
 ['stale attempt',->(a,c){c['binding']['review_attempt_id']='p1:retry-6';c['event_id']='event:3'}],
 ['foreign producer',->(a,c){c['binding']['producer_id']='other';c['event_id']='event:3'}],
 ['source changed on resume',->(a,c){a['dispatch_binding']['source_digest']='changed'}],
 ['producer version changed',->(a,c){a['dispatch_binding']['producer_version']='v10'}],
 ['missing payload archive after compaction',->(a,c){a['archives']={}}],
 ['changed payload archive',->(a,c){a['archives']['raw:1']='{}'}],
 ['missing compacted history',->(a,c){a['history_known']=false}],
 ['partial preview',->(a,c){c['complete']=false}],
 ['invalid UTF-8 payload',->(a,c){c['payload']=[255].pack('C')}]
].each do |label,mutate|
 a=copy(retained);c=copy(delivery);mutate.call(a,c);check.call('identify_return',a,c,false,label)
end
# Actual dispatched attempt is intentionally neither attempt-1 nor ordinal-bound.
passes=[{'review_pass_id'=>'p1','perspective'=>'contract_and_test_oracle','assigned_scope'=>['scope'],'coverage_obligations'=>['contract'],'prior_finding_visibility'=>'none'}, {'review_pass_id'=>'p2','perspective'=>'runtime_lifecycle_and_failure_paths','assigned_scope'=>['scope'],'coverage_obligations'=>['runtime'],'prior_finding_visibility'=>'none'}]
tuples=passes.map{|p|{'review_pass_id'=>p['review_pass_id'],'scope_item_id'=>'scope','applicable_concern'=>'contract','review_perspective'=>p['perspective'],'coverage_obligation'=>p['coverage_obligations'][0]}}
contexts=passes.to_h do |p|
 [p['review_pass_id'], {'round'=>1,'batch_id'=>'batch','review_snapshot_id'=>'snapshot','snapshot_identity'=>snapshot,'review_pass_id'=>p['review_pass_id'],'review_attempt_id'=>p['review_pass_id']+':retry-7','review_perspective'=>p['perspective'],'assigned_scope'=>p['assigned_scope'],'scope_size'=>'small','rubric_required'=>false,'quality_principles_required'=>false}]
end
return_authorities=contexts.to_h{|id,context|[id,{'context'=>context,'required_coverage_tuples'=>tuples.select{|t|t['review_pass_id']==id}}]}
replies=contexts.to_h do |id,context|
 [id, context.slice('round','batch_id','review_snapshot_id','snapshot_identity','review_pass_id','review_attempt_id','review_perspective').merge('status'=>'DONE','pass_completion_state'=>'completed','reviewed_scope'=>['scope'],'findings'=>[],'coverage_entries'=>[tuples.find{|t|t['review_pass_id']==id}.reject{|k,v|k=='review_pass_id'}.merge('status'=>'inspected_no_risk','evidence'=>'inspected source invariant')],'summary'=>'No material findings within the reviewed scope and available evidence','evidence'=>[{'source'=>'source','detail'=>'traced producer and consumer'}],'reuse_search'=>{'applicability'=>'not_applicable','applicability_reason'=>'fixture has no new capability'},'verdict'=>'clean')]
end
check.call('validate_return',return_authorities['p1'],replies['p1'],true,'current valid clean return')
locator_reply=copy(replies['p1']);locator_reply['reviewed_scope']=['source.rb']
check.call('validate_return',return_authorities['p1'],locator_reply,true,'actual inspected path differs from assigned scope ID')
[
 ['missing tuple',->(r){r['coverage_entries']=[]}], ['duplicate tuple',->(r){r['coverage_entries']*=2}],
 ['foreign tuple',->(r){r['coverage_entries'][0]['coverage_obligation']='foreign'}],
 ['boolean round is not integer',->(r){r['round']=true}], ['wrong source',->(r){r['snapshot_identity']['value']='stale'}], ['wrong attempt',->(r){r['review_attempt_id']='p1:attempt-1'}],
 ['false clean status',->(r){r['status']='DONE_WITH_CONCERNS'}], ['contradictory blocked verdict',->(r){r['status']='BLOCKED'}],
 ['unknown wire field',->(r){r['transport_receipt']='forbidden'}], ['invalid conditional omission',->(r){r['reuse_search']={'applicability'=>'applicable','applicability_reason'=>'rules'}}]
].each{|label,mutate|r=copy(replies['p1']);mutate.call(r);check.call('validate_return',return_authorities['p1'],r,false,label)}
%w[NEEDS_CONTEXT BLOCKED].each do |status|
 r=copy(replies['p1']);r.merge!('status'=>status,'pass_completion_state'=>status.downcase,'verdict'=>'not_assessed','open_questions'=>['missing source']);r['coverage_entries'][0]['status']='blocked'
 check.call('validate_return',return_authorities['p1'],r,true,status+' truth table')
end
finding={'severity'=>'must-fix','file'=>'source.rb','description'=>'Violated invariant','confidence_pct'=>91,'finding_id'=>'review_pass:p1:f1','locus'=>'boundary','invariant'=>'exact authority','failure_mechanism'=>'stale source consumed','evidence'=>'reproduced input','smallest_useful_fix'=>'reject stale source'}
r=copy(replies['p1']);r.merge!('status'=>'DONE_WITH_CONCERNS','verdict'=>'has_must_fix','findings'=>[finding]);r['coverage_entries'][0].merge!('status'=>'finding','finding_ids'=>[finding['finding_id']])
check.call('validate_return',return_authorities['p1'],r,true,'material finding provenance')
# Arithmetic uses independently retained override authority, never free-text
# classification. The shared rubric defines different caps for these findings.
rubric_dimensions=%w[correctness code_quality architecture security test_coverage]
score=rubric_dimensions.to_h{|key|[key,4.0]}.merge('weighted_score'=>4.0,'action'=>'PASS','score_justification'=>rubric_dimensions.to_h{|key|[key,'inspected source']})
scored=copy(r);scored['rubric_scores']=score
check.call('validate_return',return_authorities['p1'],scored,true,'ordinary weighted rubric without override')
# Canonical defaults apply before conditional shape checks and arithmetic.
principles=%w[solid kiss dry yagni readability].to_h{|key|[key,'no concrete risk found']}
principled=copy(replies['p1']);principled['principle_checks']=principles
default_principles=copy(return_authorities['p1']);default_principles['context'].delete('quality_principles_required')
check.call('validate_return',default_principles,replies['p1'],false,'omitted quality principles defaults true even for small scope')
check.call('validate_return',default_principles,principled,true,'literal true default satisfied by required principle checks')
unchanged_authority=copy(default_principles);ReviewTools.validate_return(default_principles,principled)
assert(default_principles==unchanged_authority,'default normalization mutated retained caller authority')
explicit_principles=copy(return_authorities['p1']);explicit_principles['context']['quality_principles_required']=true
check.call('validate_return',explicit_principles,principled,true,'explicit true principles agrees with documented default')
small_default=copy(return_authorities['p1']);small_default['context'].delete('rubric_required')
check.call('validate_return',small_default,replies['p1'],true,'omitted small rubric defaults false with explicit principles exemption')
small_required=copy(return_authorities['p1']);small_required['context']['rubric_required']=true
check.call('validate_return',small_required,replies['p1'],false,'explicit small rubric true cannot bypass scores')
check.call('validate_return',small_required,scored,true,'explicit small rubric true satisfied by valid arithmetic')
medium_default=copy(default_principles);medium_default['context'].merge!('scope_size'=>'medium');medium_default['context'].delete('rubric_required')
medium_reply=copy(principled);medium_reply['principle_checks']['design_coherence']='affected boundaries inspected'
result=check.call('validate_return',medium_default,medium_reply,false,'omitted medium rubric defaults true')
assert(result['diagnostics']==['rubric_missing'],'defaulted medium rubric failed for wrong reason')
medium_reply['rubric_scores']=copy(score)
check.call('validate_return',medium_default,medium_reply,true,'medium default satisfied by principle and rubric evidence')
invalid_medium=copy(medium_default);invalid_medium['context']['rubric_required']=false
check.call('validate_return',invalid_medium,medium_reply,false,'medium scope cannot claim small-scope rubric exemption')
{'rubric_required'=>'false','quality_principles_required'=>nil,'semantic_contract_review_required'=>'unknown'}.each do |key,value|
 bad=copy(return_authorities['p1']);bad['context'][key]=value
 check.call('validate_return',bad,replies['p1'],false,'explicit unknown/nonboolean applicability '+key)
end
bad=copy(small_default);bad['context']['scope_size']='unknown'
check.call('validate_return',bad,replies['p1'],false,'unknown scope cannot silently default rubric applicability false')
semantic_required=copy(return_authorities['p1']);semantic_required['context']['semantic_contract_review_required']=true
check.call('validate_return',semantic_required,replies['p1'],false,'explicit true semantic checks differ from canonical false default')
[[1.0,'build-breaking change'],[2.0,'exploitable vulnerability or data loss'],[2.5,'broken test suite']].each do |cap,label|
 a=copy(return_authorities['p1']);a['critical_override_cap']=cap
 c=copy(scored);c['rubric_scores'].merge!('critical_override'=>label,'weighted_score'=>cap,'action'=>'PIVOT')
 check.call('validate_return',a,c,true,label+' correct independent cap')
 wrong=copy(c);wrong['rubric_scores']['weighted_score']=cap+0.5
 check.call('validate_return',a,wrong,false,label+' wrong capped arithmetic')
end
missing=copy(scored);missing['rubric_scores'].merge!('critical_override'=>'build-breaking change','weighted_score'=>1.0,'action'=>'PIVOT')
result=check.call('validate_return',return_authorities['p1'],missing,false,'override requires independent cap authority')
assert(result['diagnostics']==['rubric_override_authority_mismatch'],'override inferred authority from candidate prose')
a=copy(return_authorities['p1']);a['critical_override_cap']=3
check.call('validate_return',a,missing,false,'unsupported independent override cap')
a['critical_override_cap']=1
check.call('validate_return',a,scored,false,'retained override authority cannot disappear from rubric')
foreign=copy(r);foreign['findings'][0]['finding_id']='foreign';check.call('validate_return',return_authorities['p1'],foreign,false,'foreign finding ID')
plan={'batch_id'=>'batch','review_snapshot_id'=>'snapshot','scope_size'=>'small','topology'=>{'discovery_pass_count'=>2,'canonical_discovery_perspectives'=>{'trivial_small'=>passes.map{|p|p['perspective']},'medium'=>passes.map{|p|p['perspective']}+['integration_compatibility_and_consumers'],'large'=>passes.map{|p|p['perspective']}+%w[integration_compatibility_and_consumers architecture_maintainability_and_reuse]},'security_specialist_triggered'=>false,'closure_verification_required'=>false,'max_required_responses'=>2},'expected_passes'=>passes,'required_coverage_tuples'=>tuples}
barrier={'pass_attempt_ledger'=>passes.map{|p|id=p['review_pass_id'];{'review_pass_id'=>id,'active_terminal_attempt_id'=>contexts[id]['review_attempt_id'],'attempts'=>[{'review_attempt_id'=>contexts[id]['review_attempt_id'],'attempt_count'=>1,'record_state'=>'terminal','terminal_state'=>'completed','repair_disposition'=>'not_needed','response_events'=>[{'response_event_id'=>'event:'+id,'dispatch_attempt_id'=>contexts[id]['review_attempt_id'],'disposition'=>'active_terminal'}]}]}}}
responses=passes.to_h do |p|
 id=p['review_pass_id'];b=copy(binding);b.merge!('native_invocation_id'=>'native-'+id,'review_pass_id'=>id,'review_attempt_id'=>contexts[id]['review_attempt_id']);d={'binding'=>b,'complete'=>true,'payload'=>JSON.generate(replies[id]),'payload_ref'=>'raw:'+id,'event_id'=>'event:'+id}
 ['event:'+id,{'identity_authority'=>{'dispatch_binding'=>b,'history_known'=>true,'records'=>[],'archives'=>{}},'delivery'=>d}]
end
batch_authority={'plan'=>plan,'active_attempts'=>contexts.transform_values{|c|c['review_attempt_id']},'responses'=>responses,'return_authorities'=>return_authorities,'unresolved_conflicts'=>[],'source_current'=>true,'producer_current'=>true,'source_findings'=>[],'previously_fixed'=>[],'snapshot_identity'=>snapshot,'terminal_barrier'=>barrier,'canonical_response_events'=>{'p1'=>'event:p1','p2'=>'event:p2'}}
check.call('validate_terminal_barrier',batch_authority,barrier,true,'complete independent terminal barrier')
trial=copy(batch_authority);trial['plan']['expected_passes'][0]['prior_finding_visibility']='closure_ledger'
result=check.call('validate_terminal_barrier',trial,barrier,false,'discovery cannot receive prior closure findings')
assert(result['diagnostics']==['plan_visibility_mismatch'],'discovery visibility failed for wrong reason')
# JSON object order cannot change structured coverage-set equality.
permuted=copy(batch_authority)
permuted['plan']['expected_passes'].each do |pass|
 id=pass['review_pass_id'];pass['assigned_scope']=['scope','scope-b'];permuted['return_authorities'][id]['context']['assigned_scope']=['scope','scope-b']
 extra=copy(tuples.find{|tuple|tuple['review_pass_id']==id});extra.merge!('scope_item_id'=>'scope-b','applicable_concern'=>'aaa')
 permuted['plan']['required_coverage_tuples']<<extra
 required=permuted['plan']['required_coverage_tuples'].select{|tuple|tuple['review_pass_id']==id}
 permuted['return_authorities'][id]['required_coverage_tuples']=required.map{|tuple|{'applicable_concern'=>tuple['applicable_concern']}.merge(tuple.reject{|key,_|key=='applicable_concern'})}
 reply=copy(replies[id]);reply['coverage_entries']<<reply['coverage_entries'][0].merge('scope_item_id'=>'scope-b','applicable_concern'=>'aaa')
 permuted['responses']['event:'+id]['delivery']['payload']=JSON.generate(reply)
end
check.call('validate_terminal_barrier',permuted,barrier,true,'coverage objects compare independently of member insertion order')
# The same structural comparator must preserve nested sequence/duplicate semantics.
left=[{'a'=>1,'nested'=>[{'x'=>'first','y'=>'second'},'tail']},{'a'=>2,'nested'=>['other']}]
right=left.reverse.map{|row|{'nested'=>row['nested'],'a'=>row['a']}}
ReviewTools.same_set(left,right,'structural_set_failed')
bad=copy(right);bad[1]['nested'].reverse!;rejected=false
begin;ReviewTools.same_set(left,bad,'nested_order_changed');rescue ReviewTools::Invalid;rejected=true;end
assert(rejected,'nested array sequence was treated as an unordered set')
rejected=false
begin;ReviewTools.same_set(left,[copy(left[0]),copy(left[0])],'duplicate_record');rescue ReviewTools::Invalid;rejected=true;end
assert(rejected,'duplicate structural records escaped set comparator')
trial=copy(barrier);trial['pass_attempt_ledger'][0]['attempts'][0]['conflict_resolution']='silently-replaced'
result=check.call('validate_terminal_barrier',batch_authority,trial,false,'unknown attempt fields violate canonical ledger schema')
assert(result['diagnostics']==['terminal_ledger_schema_invalid'],'unknown attempt field failed for wrong reason')
ambiguous_authority=copy(batch_authority)
raw=JSON.generate(replies['p1']).sub('"findings":[]', '"findings":'+JSON.generate([finding])+',"findings":[]')
assert(JSON.parse(raw)['findings']==[], 'ambiguous raw regression precondition failed')
ambiguous_authority['responses']['event:p1']['delivery']['payload']=raw
assert(ReviewTools.call({'operation'=>'identify_return','authority'=>ambiguous_authority['responses']['event:p1']['identity_authority'],'candidate'=>ambiguous_authority['responses']['event:p1']['delivery']})['valid'], 'raw duplicate-key identity must remain retained')
ambiguous_result=check.call('validate_terminal_barrier',ambiguous_authority,barrier,false,'duplicate raw findings keys cannot certify false-clean')
assert(ambiguous_result['diagnostics']==['duplicate_json_key'],'ambiguous raw return failed for the wrong reason')

trial=copy(batch_authority);trial['plan']['review_snapshot_id']='new-snapshot'
check.call('validate_terminal_barrier',trial,barrier,false,'old contexts cannot certify new plan snapshot')
trial=copy(batch_authority);trial['active_attempts']['foreign']='foreign:attempt'
check.call('validate_terminal_barrier',trial,barrier,false,'foreign active authority rejected')
archived=copy(batch_authority)
retained_response=archived['responses']['event:p1']
d=retained_response['delivery'];a=retained_response['identity_authority']
a['records']=[{'binding'=>d['binding'],'payload_ref'=>d['payload_ref'],'payload_sha256'=>Digest::SHA256.hexdigest(d['payload']),'event_ids'=>[d['event_id']]}];a['archives']={d['payload_ref']=>d['payload']}
check.call('validate_terminal_barrier',archived,barrier,true,'archived canonical event closes after compaction')
trial=copy(archived);trial['responses']['event:p1']['delivery']['event_id']='event:duplicate'
check.call('validate_terminal_barrier',trial,barrier,false,'distinct duplicate cannot replace canonical event')
[[],nil,{'operation'=>'identify_return','authority'=>{},'candidate'=>{}},{'operation'=>'identify_return','authority'=>{},'candidate'=>{'x'=>Object.new}},{'operation'=>'identify_return','authority'=>{},'candidate'=>{'x'=>'a'*(ReviewTools::MAX_BYTES+1)}}].each do |bad|
 assert(ReviewTools.call(bad)['valid']==false,'library malformed primitive boundary')
end
%w[duplicate stale].each do |disposition|
 trial=copy(barrier);trial['pass_attempt_ledger'][0]['attempts'][0]['response_events'][0]['disposition']=disposition
 check.call('validate_terminal_barrier',batch_authority,trial,false,disposition+' cannot satisfy barrier')
end
trial=copy(barrier);trial['pass_attempt_ledger'][0]['attempts'][0]['response_events']*=2
check.call('validate_terminal_barrier',batch_authority,trial,false,'conflicting terminal replies')
trial=copy(batch_authority);trial['unresolved_conflicts']=['raw:conflict']
check.call('validate_terminal_barrier',trial,barrier,false,'unresolved conflict blocks closure')
trial=copy(batch_authority);trial['producer_current']=false
check.call('validate_terminal_barrier',trial,barrier,false,'changed producer blocks closure')
summary={'reviewed_scope'=>['source.rb'],'rounds'=>1,'final_review_snapshot_id'=>'snapshot','final_snapshot_identity'=>snapshot,'coverage_complete'=>true,'final_batch_plan'=>plan,'coverage_ledger'=>tuples.map{|t|t.reject{|k,v|k=='review_perspective'}.merge('perspective'=>t['review_perspective'],'batch_id'=>'batch','review_snapshot_id'=>'snapshot','assigned_scope'=>['scope'],'terminal_state'=>'completed','coverage_status'=>'complete','coverage_disposition'=>'inspected_no_risk','evidence'=>'source inspected')},'batch_summaries'=>[{'started_batch_ordinal'=>1,'batch_id'=>'batch','review_snapshot_id'=>'snapshot','snapshot_identity'=>snapshot,'batch_status'=>'complete','expected_response_count'=>2,'terminal_response_count'=>2,'aggregate_rubric_recomputed'=>true}],'aggregation_ledger'=>[],'aggregated_findings'=>[],'result'=>'CLEAN','fixed_items'=>[],'nits'=>[],'evidence_bounded_claim'=>'No material findings within the reviewed scope and available evidence'}
check.call('validate_aggregate_accounting',batch_authority,summary,true,'lossless complete clean aggregate')
trial=copy(summary);trial['coverage_gaps']=['Original assigned consumer has not been inspected']
result=check.call('validate_aggregate_accounting',batch_authority,trial,false,'explicit coverage gap cannot certify complete CLEAN')
assert(result['diagnostics']==['aggregate_explicit_coverage_gaps'],'explicit gap contradiction failed for wrong reason')
material_authority=copy(batch_authority);material_summary=copy(summary)
material_authority['responses']['event:p1']['delivery']['payload']=JSON.generate(r)
provenance=[{'source_kind'=>'review_pass','source_id'=>'p1'}]
material_authority['source_findings']=[{'source_kind'=>'review_pass','source_id'=>'p1','finding'=>finding}]
aggregate=finding.merge('aggregate_finding_id'=>'aggregate:1','source_finding_ids'=>[finding['finding_id']],'source_provenance'=>provenance)
material_summary.merge!('aggregated_findings'=>[aggregate],'aggregation_ledger'=>[{'aggregate_finding_id'=>'aggregate:1','source_finding_ids'=>[finding['finding_id']],'source_provenance'=>provenance,'disposition'=>'retained','rationale'=>'preserve supported finding'}],'result'=>'HAS_REMAINING_ITEMS')
material_summary.delete('evidence_bounded_claim')
material_summary['coverage_ledger'][0].merge!('coverage_disposition'=>'finding','finding_ids'=>[finding['finding_id']])
check.call('validate_aggregate_accounting',material_authority,material_summary,true,'material finding retained losslessly')
trial=copy(material_summary);trial['coverage_ledger'][0].delete('finding_ids');trial['coverage_ledger'][0]['coverage_disposition']='inspected_no_risk'
check.call('validate_aggregate_accounting',material_authority,trial,false,'aggregate cannot relabel actual finding tuple')
trial=copy(material_authority);trial['source_findings']=[]
check.call('validate_aggregate_accounting',trial,material_summary,false,'underlisted current source union rejected')
trial=copy(material_summary);trial['aggregated_findings']=[];trial['aggregation_ledger']=[];trial['result']='CLEAN'
check.call('validate_aggregate_accounting',material_authority,trial,false,'material finding cannot be silently lost')
trial=copy(batch_authority);trial['plan']['expected_passes'].pop
check.call('validate_terminal_barrier',trial,barrier,false,'topology cannot omit an independent perspective')

trial=copy(summary);trial['coverage_ledger'].pop
check.call('validate_aggregate_accounting',batch_authority,trial,false,'aggregate cannot omit tuple')
trial=copy(batch_authority);trial['source_findings']=[{'source_kind'=>'review_pass','source_id'=>'p1','finding'=>finding}]
check.call('validate_aggregate_accounting',trial,summary,false,'validated finding cannot disappear')
# Fixed history is immutable; a fresh closure pass may verify, regress or block.
original_finding=finding.merge('finding_id'=>'review_pass:old:f1')
original_provenance=[{'source_kind'=>'review_pass','source_id'=>'old'}]
original={'aggregate_finding_id'=>'aggregate:old','source_finding_ids'=>[original_finding['finding_id']],'source_provenance'=>original_provenance}
closure_authority=copy(batch_authority);closure_summary=copy(summary)
cp={'review_pass_id'=>'pc','perspective'=>'closure_verification','assigned_scope'=>['scope'],'coverage_obligations'=>['closure'],'prior_finding_visibility'=>'closure_ledger'}
ct={'review_pass_id'=>'pc','scope_item_id'=>'scope','applicable_concern'=>'contract','review_perspective'=>'closure_verification','coverage_obligation'=>'closure'}
closure_authority['plan']['expected_passes']<<cp;closure_authority['plan']['required_coverage_tuples']<<ct
closure_authority['plan']['topology'].merge!('closure_verification_required'=>true,'max_required_responses'=>3)
cc=copy(contexts['p2']);cc.merge!('review_pass_id'=>'pc','review_attempt_id'=>'pc:attempt','review_perspective'=>'closure_verification','previously_fixed'=>[original])
closure_authority['return_authorities']['pc']={'context'=>cc,'required_coverage_tuples'=>[ct]}
closure_authority['active_attempts']['pc']='pc:attempt';closure_authority['canonical_response_events']['pc']='event:pc'
cr=copy(replies['p2']);cr.merge!('review_pass_id'=>'pc','review_attempt_id'=>'pc:attempt','review_perspective'=>'closure_verification','closure_results'=>[{'aggregate_finding_id'=>'aggregate:old','status'=>'verified_closed','evidence'=>'fresh closure observed'}]);cr['coverage_entries']=[ct.reject{|k,v|k=='review_pass_id'}.merge('status'=>'inspected_no_risk','evidence'=>'fresh closure observed')]
cb=copy(binding);cb.merge!('native_invocation_id'=>'native-pc','review_pass_id'=>'pc','review_attempt_id'=>'pc:attempt')
cd={'binding'=>cb,'complete'=>true,'payload'=>JSON.generate(cr),'payload_ref'=>'raw:pc','event_id'=>'event:pc'}
closure_authority['responses']['event:pc']={'identity_authority'=>{'dispatch_binding'=>cb,'history_known'=>true,'records'=>[],'archives'=>{}},'delivery'=>cd}
closure_entry={'review_pass_id'=>'pc','active_terminal_attempt_id'=>'pc:attempt','attempts'=>[{'review_attempt_id'=>'pc:attempt','attempt_count'=>1,'record_state'=>'terminal','terminal_state'=>'completed','repair_disposition'=>'not_needed','response_events'=>[{'response_event_id'=>'event:pc','dispatch_attempt_id'=>'pc:attempt','disposition'=>'active_terminal'}]}]}
closure_authority['terminal_barrier']['pass_attempt_ledger']<<closure_entry
old_source={'source_kind'=>'review_pass','source_id'=>'old','finding'=>original_finding}
closure_authority['previously_fixed']=[original];closure_authority['historical_fixed_findings']=[old_source];closure_authority['source_findings']=[old_source]
closure_summary['final_batch_plan']=copy(closure_authority['plan']);closure_summary['coverage_ledger']<<ct.reject{|k,v|k=='review_perspective'}.merge('perspective'=>'closure_verification','batch_id'=>'batch','review_snapshot_id'=>'snapshot','assigned_scope'=>['scope'],'terminal_state'=>'completed','coverage_status'=>'complete','coverage_disposition'=>'inspected_no_risk','evidence'=>'fresh closure')
closure_summary['batch_summaries'][0].merge!('expected_response_count'=>3,'terminal_response_count'=>3)
fixed_row={'aggregate_finding_id'=>'aggregate:old','source_finding_ids'=>original['source_finding_ids'],'source_provenance'=>original_provenance,'disposition'=>'fixed_closed','rationale'=>'immutable prior identity'}
closure_summary.merge!('aggregation_ledger'=>[fixed_row],'fixed_items'=>[{'aggregate_finding_id'=>'aggregate:old','severity'=>'must-fix','file'=>'source.rb','description'=>'prior finding fixed','fixed_in_round'=>1}],'closure_results'=>cr['closure_results'],'result'=>'ISSUES_FIXED')
check.call('validate_aggregate_accounting',closure_authority,closure_summary,true,'fresh closure verifies immutable fixed history')
%w[regressed incomplete].each do |outcome|
 a=copy(closure_authority);s=copy(closure_summary);new_finding=finding.merge('finding_id'=>'review_pass:pc:regression')
 rr=copy(cr);rr.merge!('status'=>'DONE_WITH_CONCERNS','verdict'=>'has_must_fix','findings'=>[new_finding]);rr['closure_results'][0]['status']=outcome;rr['coverage_entries'][0].merge!('status'=>'finding','finding_ids'=>[new_finding['finding_id']]);a['responses']['event:pc']['delivery']['payload']=JSON.generate(rr)
 a['source_findings']<<{'source_kind'=>'review_pass','source_id'=>'pc','finding'=>new_finding}
 p=[{'source_kind'=>'review_pass','source_id'=>'pc'}];current=new_finding.merge('aggregate_finding_id'=>'aggregate:old','source_finding_ids'=>[new_finding['finding_id']],'source_provenance'=>p)
 s['aggregated_findings']=[current];s['aggregation_ledger']<<{'aggregate_finding_id'=>'aggregate:old','source_finding_ids'=>current['source_finding_ids'],'source_provenance'=>p,'disposition'=>'retained','rationale'=>'fresh material closure finding'}
 s['closure_results']=rr['closure_results'];s['coverage_ledger'][-1].merge!('coverage_disposition'=>'finding','finding_ids'=>[new_finding['finding_id']]);s['result']='HAS_REMAINING_ITEMS';s.delete('evidence_bounded_claim')
 check.call('validate_aggregate_accounting',a,s,true,outcome+' closure remains accounted and material')
 if outcome=='regressed'
  # Both current sources remain validated/lossless; only the fixed-ID binding changes.
  mixed=copy(a);mixed_summary=copy(s)
  discovery=finding.merge('finding_id'=>'review_pass:p1:unrelated','locus'=>'unrelated discovery','invariant'=>'other invariant','failure_mechanism'=>'different mechanism')
  discovery_reply=copy(r);discovery_reply['findings']=[discovery];discovery_reply['coverage_entries'][0]['finding_ids']=[discovery['finding_id']]
  mixed['responses']['event:p1']['delivery']['payload']=JSON.generate(discovery_reply)
  mixed['source_findings']<<{'source_kind'=>'review_pass','source_id'=>'p1','finding'=>discovery}
  discovery_provenance=[{'source_kind'=>'review_pass','source_id'=>'p1'}]
  mixed_summary['coverage_ledger'][0].merge!('coverage_disposition'=>'finding','finding_ids'=>[discovery['finding_id']])
  mixed_summary['aggregated_findings']<<discovery.merge('aggregate_finding_id'=>'aggregate:other','source_finding_ids'=>[discovery['finding_id']],'source_provenance'=>discovery_provenance)
  mixed_summary['aggregation_ledger']<<{'aggregate_finding_id'=>'aggregate:other','source_finding_ids'=>[discovery['finding_id']],'source_provenance'=>discovery_provenance,'disposition'=>'retained','rationale'=>'independent discovery remains retained'}
  check.call('validate_aggregate_accounting',mixed,mixed_summary,true,'fresh closure keeps fixed identity while unrelated discovery is separately retained')
  swapped=copy(mixed_summary)
  (swapped['aggregated_findings']+swapped['aggregation_ledger'].select{|row|row['disposition']=='retained'}).each do |row|
   row['aggregate_finding_id']=row['aggregate_finding_id']=='aggregate:old' ? 'aggregate:other' : 'aggregate:old'
  end
  result=check.call('validate_aggregate_accounting',mixed,swapped,false,'discovery cannot substitute for current closure source under fixed aggregate identity')
  assert(result['diagnostics']==['regressed_closure_source_missing'],'swapped closure source failed for wrong reason')
 end
 bad=copy(s);bad['closure_results'][0]['status']='verified_closed';check.call('validate_aggregate_accounting',a,bad,false,outcome+' cannot be relabeled closed')
end
# Nonassessment never requires invented semantic regression findings.
%w[timed_out failed invalidated needs_context blocked].each do |state|
 a=copy(closure_authority);s=copy(closure_summary);evidence='closure unavailable:'+state
 s.delete('evidence_bounded_claim');s.merge!('coverage_complete'=>false,'result'=>'HAS_REMAINING_ITEMS','coverage_gaps'=>['closure unavailable'])
 s['closure_results'][0].merge!('status'=>'incomplete','evidence'=>evidence)
 s['coverage_ledger'][-1].merge!('terminal_state'=>state,'coverage_status'=>'incomplete','coverage_disposition'=>'incomplete','coverage_gap_id'=>'gap:closure','evidence'=>evidence)
 s['aggregation_ledger']<<{'source_provenance'=>[{'source_kind'=>'review_pass','source_id'=>'pc'}],'disposition'=>'coverage_gap','source_coverage_gap_ids'=>['gap:closure'],'rationale'=>'closure unavailable'}
 s['batch_summaries'][0].merge!('batch_status'=>'incomplete','aggregate_rubric_recomputed'=>false)
 attempt=a['terminal_barrier']['pass_attempt_ledger'][-1]['attempts'][0];attempt['terminal_state']=state;attempt['failure_evidence']=evidence
 if %w[needs_context blocked].include?(state)
  reply=copy(cr);reply.merge!('status'=>state.upcase,'pass_completion_state'=>state,'verdict'=>'not_assessed','open_questions'=>['missing closure evidence']);reply['closure_results']=copy(s['closure_results']);reply['coverage_entries'][0].merge!('status'=>'blocked','evidence'=>evidence)
  a['responses']['event:pc']['delivery']['payload']=JSON.generate(reply)
  check.call('validate_return',a['return_authorities']['pc'],reply,true,state+' closure is unassessed without findings')
  bad=copy(reply);bad['closure_results'][0]['status']='verified_closed';check.call('validate_return',a['return_authorities']['pc'],bad,false,state+' cannot claim assessed closure')
 else
  attempt.merge!('failure_kind'=>state=='timed_out' ? 'timeout' : state=='failed' ? 'transport' : 'source_mutation','failure_evidence'=>evidence,'response_events'=>[])
  a['responses'].delete('event:pc');a['canonical_response_events']['pc']=nil;s['batch_summaries'][0]['terminal_response_count']=2
 end
 check.call('validate_aggregate_accounting',a,s,true,state+' honest incomplete fixed history retained')
 bad=copy(a['terminal_barrier']);bad['pass_attempt_ledger'][-1]['attempts'][0].delete('failure_evidence')
 result=check.call('validate_terminal_barrier',a,bad,false,state+' terminal ledger requires canonical failure evidence')
 assert(result['diagnostics']==['terminal_ledger_schema_invalid'],'missing canonical failure evidence failed for wrong reason')
 bad=copy(s);bad['coverage_ledger'][-1]['coverage_status']='complete';check.call('validate_aggregate_accounting',a,bad,false,state+' cannot relabel unassessed coverage complete')
 bad=copy(s);bad['closure_results'][0]['evidence']='invented evidence';check.call('validate_aggregate_accounting',a,bad,false,state+' closure evidence must bind actual failure')
 bad=copy(s);bad['closure_results'][0]['status']='verified_closed';check.call('validate_aggregate_accounting',a,bad,false,state+' cannot become verified closure')
end
# Production summaries apply the passive canonical conditional fields and history.
trial=copy(summary);trial['evidence_bounded_claim']='All code is proven correct'
check.call('validate_aggregate_accounting',batch_authority,trial,false,'unbounded clean claim rejected')
trial=copy(summary);trial.delete('evidence_bounded_claim')
check.call('validate_aggregate_accounting',batch_authority,trial,false,'required calibrated claim absent')
history=copy(summary);history['rounds']=3
history['batch_summaries']=(1..2).map{|i|summary['batch_summaries'][0].merge('started_batch_ordinal'=>i,'batch_id'=>"prior-#{i}",'review_snapshot_id'=>"prior-snapshot-#{i}")}+[summary['batch_summaries'][0].merge('started_batch_ordinal'=>3)]
history['additional_round_reasons']=[{'round'=>2,'reason'=>'changed_files','evidence_ref'=>'fix+verification:2','detail'=>'fix and refreshed verification'},{'round'=>3,'reason'=>'unresolved_finding','evidence_ref'=>'remaining:3','detail'=>'supported unresolved finding'}]
check.call('validate_aggregate_accounting',batch_authority,history,true,'complete later-round reasons')
{
 'missing later-round reasons'=>->(x){x.delete('additional_round_reasons')},
 'missing third-round reason'=>->(x){x['additional_round_reasons'].pop},
 'round-two trigger incorrect'=>->(x){x['additional_round_reasons'][0]['reason']='unresolved_finding'},
 'later-round detail absent'=>->(x){x['additional_round_reasons'][1].delete('detail')}
}.each{|label,mutate|trial=copy(history);mutate.call(trial);check.call('validate_aggregate_accounting',batch_authority,trial,false,label)}
# Repair changes active coverage, never erases an independently validated receipt.
repaired=copy(material_authority);repaired_summary=copy(material_summary)
repaired_summary['coverage_ledger']=copy(summary['coverage_ledger'])
old=repaired['responses']['event:p1'];d=old['delivery'];a=old['identity_authority']
a['records']=[{'binding'=>d['binding'],'payload_ref'=>d['payload_ref'],'payload_sha256'=>Digest::SHA256.hexdigest(d['payload']),'event_ids'=>[d['event_id']]}];a['archives']={d['payload_ref']=>d['payload']}
new_attempt='p1:repair-8';new_event='event:p1:repair'
repaired['active_attempts']['p1']=new_attempt;repaired['return_authorities']['p1']['context']['review_attempt_id']=new_attempt;repaired['canonical_response_events']['p1']=new_event
new_reply=copy(replies['p1']);new_reply['review_attempt_id']=new_attempt
new_response=copy(responses['event:p1']);new_response['identity_authority']['dispatch_binding'].merge!('native_invocation_id'=>'native-p1-repair','review_attempt_id'=>new_attempt);new_response['delivery'].merge!('binding'=>copy(new_response['identity_authority']['dispatch_binding']),'event_id'=>new_event,'payload_ref'=>'raw:p1:repair','payload'=>JSON.generate(new_reply))
repaired['responses'][new_event]=new_response
attempts=repaired['terminal_barrier']['pass_attempt_ledger'][0]['attempts'];attempts[0]['response_events'][0]['disposition']='stale'
next_attempt=copy(attempts[0]);next_attempt.merge!('attempt_count'=>2,'review_attempt_id'=>new_attempt,'repair_disposition'=>'repaired');next_attempt['response_events']=[{'response_event_id'=>new_event,'dispatch_attempt_id'=>new_attempt,'disposition'=>'active_terminal'}];attempts<<next_attempt
repaired['terminal_barrier']['pass_attempt_ledger'][0]['active_terminal_attempt_id']=new_attempt
check.call('validate_aggregate_accounting',repaired,repaired_summary,true,'inactive validated finding survives repair with active clean coverage')
# Every known historical occurrence must resolve independently of active coverage.
trial=copy(repaired);trial['responses'].delete('event:p1')
missing=check.call('validate_terminal_barrier',trial,trial['terminal_barrier'],false,'stale occurrence missing retained evidence')
assert(missing['diagnostics']==['response_history_missing'],'missing historical occurrence failed for wrong reason')
trial=copy(repaired);trial['responses']['event:p1']['delivery']['event_id']='foreign:event'
check.call('validate_terminal_barrier',trial,trial['terminal_barrier'],false,'stale occurrence event identity must match ledger')
trial=copy(repaired);trial['responses']['event:p1']['identity_authority']['dispatch_binding']['review_attempt_id']='foreign:attempt'
check.call('validate_terminal_barrier',trial,trial['terminal_barrier'],false,'inactive occurrence dispatch authority bound to attempt')
trial=copy(repaired);trial['source_findings']=[]
check.call('validate_aggregate_accounting',trial,summary,false,'repaired clean cannot discard earlier material finding')
trial=copy(repaired);duplicate=copy(trial['responses']['event:p1']);duplicate['delivery']['event_id']='event:p1:duplicate';trial['responses']['event:p1:duplicate']=duplicate
check.call('validate_aggregate_accounting',trial,repaired_summary,true,'duplicate retained occurrence does not duplicate stable finding')
trial=copy(repaired);conflicting=copy(responses['event:p1']);conflicting['identity_authority']['dispatch_binding']['native_invocation_id']='native-p1-other';conflicting['delivery'].merge!('binding'=>copy(conflicting['identity_authority']['dispatch_binding']),'event_id'=>'event:p1:other','payload_ref'=>'raw:other','payload'=>JSON.generate(r.merge('findings'=>[finding.merge('evidence'=>'different validated evidence')])));trial['responses']['event:p1:other']=conflicting
check.call('validate_aggregate_accounting',trial,repaired_summary,false,'different validated contents with one stable ID cannot replace older finding')
trial=copy(repaired);trial['source_findings']*=2
check.call('validate_aggregate_accounting',trial,repaired_summary,true,'identical stable finding and provenance conservatively deduplicate')
trial=copy(repaired);conflict=copy(trial['source_findings'][0]);conflict['finding']['evidence']='different retained evidence';trial['source_findings']<<conflict
check.call('validate_aggregate_accounting',trial,repaired_summary,false,'conflicting stable finding contents rejected')
trial=copy(repaired);trial['responses']['event:p1']['identity_authority']['archives']['raw:p1']='tampered'
check.call('validate_aggregate_accounting',trial,repaired_summary,false,'inactive archive rehashed on resume')
trial=copy(repaired);trial['responses']['event:p1']['delivery']['payload']=JSON.generate(r.merge('review_attempt_id'=>new_attempt));trial['responses']['event:p1']['identity_authority'].merge!('records'=>[],'archives'=>{})
check.call('validate_aggregate_accounting',trial,repaired_summary,false,'historical identity cannot come from candidate attempt')
# Projection-only grader checks keep positive ordinals without a round cap.
long_summary=copy(summary);long_summary['rounds']=11
long_summary['batch_summaries']=(1..10).map{|i|summary['batch_summaries'][0].merge('started_batch_ordinal'=>i,'batch_id'=>"historical-#{i}",'review_snapshot_id'=>"old-snapshot-#{i}")}+[summary['batch_summaries'][0].merge('started_batch_ordinal'=>11)]
projection={'plan'=>plan,'review_snapshot_id'=>'snapshot','snapshot_identity'=>snapshot}
assert(ReviewTools.summary_projection_valid?(projection,long_summary),'positive history beyond ten rejected')
long_summary['rounds']=10
assert(!ReviewTools.summary_projection_valid?(projection,long_summary),'batch count mismatch accepted')

# Independent expectations must kill a validator that simply declares all valid.
ReviewTools.define_singleton_method(:call) { |_request| {'valid'=>true} }
assert(requests.any? { |request,expected| ReviewTools.call(request)['valid'] != expected },'always-valid mutant escaped independent oracle')
puts "#{observed.length} independent behavior cases; always-valid mutant killed"
RUBY
} | ruby -rjson -rdigest - "$FRAMEWORK_DIR"
then pass; else fail "review-tools independent behavior oracle failed"; fi
test_start "Python review boundary is private passive data with exact primitive types"
if "${REVIEW_TOOLS_PYTHON:-python3}" -I -S -B - "$FRAMEWORK_DIR/skills/assistant-review/scripts/review-tools.py" <<'PYTHON_REVIEW_BOUNDARY'
import importlib.util,json,pathlib,shutil,subprocess,sys,tempfile
spec=importlib.util.spec_from_file_location('review_tools',sys.argv[1]);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
assert m.probe()['valid']
assert 'yaml' not in sys.modules, 'ambient YAML identity imported'
# Public probe must refuse an unlisted optional module before it executes.
with tempfile.TemporaryDirectory() as directory:
    skill=pathlib.Path(directory)/'review';scripts=skill/'scripts';scripts.mkdir(parents=True)
    helper=scripts/'review-tools.py';shutil.copy2(sys.argv[1],helper)
    shutil.copytree(pathlib.Path(sys.argv[1]).parent/'_vendor',scripts/'_vendor')
    shutil.copytree(pathlib.Path(sys.argv[1]).parent.parent/'contracts',skill/'contracts')
    command=[sys.executable,'-I','-S','-B',str(helper),'--probe']
    good=subprocess.run(command,capture_output=True,timeout=5)
    assert good.returncode==0 and json.loads(good.stdout)['valid'],'public bundle positive failed'
    marker=pathlib.Path(directory)/'unexpected-module-executed'
    (scripts/'_vendor/pyyaml/yaml/cyaml.py').write_text('from pathlib import Path\nPath('+repr(str(marker))+').write_text("executed")\nraise ImportError("optional bridge")\n')
    bad=subprocess.run(command,capture_output=True,timeout=5)
    assert bad.returncode==1 and json.loads(bad.stdout)['diagnostics']==['bundled_parser_unavailable'],'unlisted module did not fail closed'
    assert not marker.exists(),'unlisted optional bridge executed before refusal'

assert m.shape_valid(1,{'type':'int'}) and not m.shape_valid(True,{'type':'int'})
assert not m.shape_valid(False,{'type':'float'}) and not m.shape_valid(1,{'type':'boolean'})
for raw in ('a: &a []\nb: *a\n','!!python/object/apply:os.system [echo forbidden]','value: 2026-10-24','value: .inf'):
    try:m.passive_yaml(raw)
    except m.Invalid:pass
    else:raise AssertionError('unsafe/nonprimitive YAML accepted')
assert m.passive_yaml('key: [true, 1, plain]')=={'key':[True,1,'plain']}
for raw in (b'{"a":1,"a":2}', b'{"a":NaN}', b'{"a":1e999}', b'"\xff"'):
    try:m.parse_json(raw)
    except (m.Invalid,ValueError,UnicodeError):pass
    else:raise AssertionError('ambiguous/nonfinite/nonUTF8 JSON accepted')
for value in (set(), object(), {'x':float('inf')}, {'x':'\ud800'}):
    assert not m.call(value)['valid'],'nonprimitive library input accepted'
assert m.call([])['diagnostics']==['object_required']
assert m.call(None)['diagnostics']==['object_required']
print('private passive parser, strict JSON and exact boolean/integer boundaries passed')
PYTHON_REVIEW_BOUNDARY
then pass; else fail "Python private parser/type boundary failed"; fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
