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
return_authorities=contexts.to_h{|id,context|[id,{'producer_version'=>'9.0','historical_dispatch_binding'=>binding.merge(context.slice('batch_id','review_snapshot_id','review_pass_id','review_attempt_id')).merge('native_invocation_id'=>'native-'+id),'context'=>context,'required_coverage_tuples'=>tuples.select{|t|t['review_pass_id']==id}}]}
replies=contexts.to_h do |id,context|
 [id, context.slice('round','batch_id','review_snapshot_id','snapshot_identity','review_pass_id','review_attempt_id','review_perspective').merge('status'=>'DONE','pass_completion_state'=>'completed','reviewed_scope'=>['scope'],'findings'=>[],'coverage_entries'=>[tuples.find{|t|t['review_pass_id']==id}.reject{|k,v|k=='review_pass_id'}.merge('status'=>'inspected_no_risk','evidence'=>'inspected source invariant')],'summary'=>'No material findings within the reviewed scope and available evidence','evidence'=>[{'source'=>'source','detail'=>'traced producer and consumer'}],'reuse_search'=>{'applicability'=>'not_applicable','applicability_reason'=>'fixture has no new capability'},'verdict'=>'clean')]
end
# Current v10 authority is separate from the candidate return and original v9 reader.
current=copy(return_authorities['p1']);current['producer_version']='10.0';current.delete('historical_dispatch_binding')
current['context'].merge!('reviewer_actor_id'=>'fresh-reviewer','native_invocation_id'=>'native:fresh-review','handoff_digest'=>'sha256:frozen-handoff','review_subject'=>'implementation')
current['fresh_dispatch']={'actor_id'=>'fresh-reviewer','root_actor_id'=>'root','author_actor_ids'=>['author'],'prior_reviewer_actor_ids'=>['prior-reviewer'],'native_invocation_id'=>'native:fresh-review','creation_evidence_ref'=>'native:create-fresh','runtime_evidence_ref'=>'native:observed','runtime'=>'codex','fork_turns'=>'none','context_isolation'=>'fresh_self_contained','handoff_digest'=>'sha256:frozen-handoff','source_digest'=>snapshot['value'],'review_subject'=>'implementation'}
check.call('validate_return',current,replies['p1'],true,'v10 fresh independent native review')
{'missing_version'=>'review_version_unsupported','missing_fresh'=>'fresh_review_authority_invalid','self_review'=>'review_actor_not_fresh','old_reviewer'=>'review_actor_not_fresh','inherited_context'=>'review_context_inherited','wrong_handoff'=>'fresh_review_binding_mismatch','relabel_v9'=>'historical_review_authority_missing',
 'context_actor'=>'fresh_review_binding_mismatch','context_native'=>'fresh_review_binding_mismatch','fact_source'=>'fresh_review_binding_mismatch','context_subject'=>'fresh_review_binding_mismatch',
 'empty_authors'=>'fresh_review_authority_invalid','unknown_fact_key'=>'fresh_review_authority_invalid','codex_without_fork'=>'fresh_review_authority_invalid','fork_without_codex'=>'fresh_review_authority_invalid','blank_creation'=>'fresh_review_authority_invalid','duplicate_authors'=>'fresh_review_authority_invalid',
 'root_reviewer'=>'review_actor_not_fresh','isolation_not_fresh'=>'fresh_review_authority_invalid','unknown_subject'=>'fresh_review_authority_invalid'}.each do |mutation,code|
 a=copy(current)
 case mutation
 when 'missing_version' then a.delete('producer_version')
 when 'missing_fresh' then a.delete('fresh_dispatch')
 when 'self_review' then a['fresh_dispatch']['actor_id']='author';a['context']['reviewer_actor_id']='author'
 when 'old_reviewer' then a['fresh_dispatch']['actor_id']='prior-reviewer';a['context']['reviewer_actor_id']='prior-reviewer'
 when 'inherited_context' then a['fresh_dispatch']['fork_turns']='all'
 when 'wrong_handoff' then a['fresh_dispatch']['handoff_digest']='changed'
 when 'relabel_v9' then a['producer_version']='9.0'
 when 'context_actor' then a['context']['reviewer_actor_id']='other-reviewer'
 when 'context_native' then a['context']['native_invocation_id']='native:other'
 when 'fact_source' then a['fresh_dispatch']['source_digest']='sha256:other-source'
 when 'context_subject' then a['context']['review_subject']='plan'
 when 'empty_authors' then a['fresh_dispatch']['author_actor_ids']=[]
 when 'unknown_fact_key' then a['fresh_dispatch']['payload_claim']='self-attested'
 when 'codex_without_fork' then a['fresh_dispatch'].delete('fork_turns')
 when 'fork_without_codex' then a['fresh_dispatch']['runtime']='claude'
 when 'blank_creation' then a['fresh_dispatch']['creation_evidence_ref']=' '
 when 'duplicate_authors' then a['fresh_dispatch']['author_actor_ids']=['author','author']
 # The orchestrating root is never its own fresh reviewer.
 when 'root_reviewer' then a['fresh_dispatch']['actor_id']='root';a['context']['reviewer_actor_id']='root'
 # context_isolation and review_subject are declared enums in contracts/input.yaml.
 when 'isolation_not_fresh' then a['fresh_dispatch']['context_isolation']='inherited'
 when 'unknown_subject' then a['fresh_dispatch']['review_subject']='other';a['context']['review_subject']='other'
 end
 result=check.call('validate_return',a,replies['p1'],false,'v10 rejects '+mutation)
 assert(result['diagnostics']==[code],mutation+' failed for wrong reason: '+result['diagnostics'].inspect)
end
# L2/Y1: a Codex context with any fork_turns other than none is inherited; runtime must equal its stripped
# lowercase form, so padded or cased codex is rejected with or without fork_turns.
[['inherited fork_turns','review_context_inherited',->(f){f['fork_turns']='None'}],
 ['capitalized Codex runtime with fork_turns','fresh_review_authority_invalid',->(f){f['runtime']='Codex'}],
 ['capitalized Codex runtime without fork_turns','fresh_review_authority_invalid',->(f){f['runtime']='Codex';f.delete('fork_turns')}],
 ['uppercase CODEX runtime without fork_turns','fresh_review_authority_invalid',->(f){f['runtime']='CODEX';f.delete('fork_turns')}],
 ['leading-space codex runtime with fork_turns','fresh_review_authority_invalid',->(f){f['runtime']=' codex'}],
 ['trailing-space codex runtime without fork_turns','fresh_review_authority_invalid',->(f){f['runtime']='codex ';f.delete('fork_turns')}],
 ['newline-padded codex runtime with fork_turns','fresh_review_authority_invalid',->(f){f['runtime']="codex\n"}],
 ['newline-padded codex runtime without fork_turns','fresh_review_authority_invalid',->(f){f['runtime']="codex\n";f.delete('fork_turns')}],
 # Non-codex runtimes are held to the same stripped lowercase form.
 ['leading-space claude runtime without fork_turns','fresh_review_authority_invalid',->(f){f['runtime']=' claude';f.delete('fork_turns')}],
 ['capitalized Claude runtime without fork_turns','fresh_review_authority_invalid',->(f){f['runtime']='Claude';f.delete('fork_turns')}],
 ['trailing-space claude runtime without fork_turns','fresh_review_authority_invalid',->(f){f['runtime']='claude ';f.delete('fork_turns')}]
].each do |label,code,mutate|
 a=copy(current);mutate.call(a['fresh_dispatch'])
 result=check.call('validate_return',a,replies['p1'],false,'v10 rejects '+label)
 assert(result['diagnostics']==[code],label+' failed for wrong reason: '+result['diagnostics'].inspect)
end
a=copy(current);a['fresh_dispatch']['runtime']='claude';a['fresh_dispatch'].delete('fork_turns')
check.call('validate_return',a,replies['p1'],true,'a non-codex runtime without fork_turns stays valid')
check.call('validate_return',return_authorities['p1'],replies['p1'],true,'current valid clean return')
# Historical v9 reading binds the original native source_digest to the frozen snapshot.
v9_source=copy(return_authorities['p1']);v9_source['historical_dispatch_binding']['source_digest']='sha256:other-source'
result=check.call('validate_return',v9_source,replies['p1'],false,'v9 binding with a foreign source_digest')
assert(result['diagnostics']==['historical_review_authority_missing'],'v9 source_digest failed for wrong reason: '+result['diagnostics'].inspect)
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
batch_authority={'producer_version'=>'9.0','plan'=>plan,'active_attempts'=>contexts.transform_values{|c|c['review_attempt_id']},'responses'=>responses,'return_authorities'=>return_authorities,'unresolved_conflicts'=>[],'source_current'=>true,'producer_current'=>true,'source_findings'=>[],'previously_fixed'=>[],'snapshot_identity'=>snapshot,'terminal_barrier'=>barrier,'canonical_response_events'=>{'p1'=>'event:p1','p2'=>'event:p2'}}
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
# Existing historical-failure controls do not cover current native creation
# failure before an actor exists. Keep the real failure and frozen assignment;
# neither the barrier nor aggregate may invent coverage or a clean result.
creation_failure=copy(batch_authority);creation_failure.merge!('producer_version'=>'10.0','review_subject'=>'implementation','responses'=>{})
creation_failure['return_authorities'].each_value{|a|a['producer_version']='10.0';a.delete('historical_dispatch_binding');a.delete('fresh_dispatch')}
creation_failure['canonical_response_events'].transform_values!{|_|nil}
creation_summary=copy(summary);creation_summary.delete('evidence_bounded_claim');creation_summary.merge!('reviewed_scope'=>[],'coverage_complete'=>false,'result'=>'HAS_REMAINING_ITEMS','coverage_gaps'=>['Native reviewer creation unavailable'])
creation_summary['batch_summaries'][0].merge!('batch_status'=>'incomplete','terminal_response_count'=>0,'aggregate_rubric_recomputed'=>false)
creation_failure['terminal_barrier']['pass_attempt_ledger'].each do |entry|
 id=entry['review_pass_id'];failure='native creation unavailable:'+id
 entry['attempts'][0].merge!('terminal_state'=>'failed','failure_kind'=>'transport','failure_evidence'=>failure,'response_events'=>[])
 row=creation_summary['coverage_ledger'].find{|r|r['review_pass_id']==id}
 row.merge!('terminal_state'=>'failed','coverage_status'=>'incomplete','coverage_disposition'=>'incomplete','coverage_gap_id'=>'creation-gap:'+id,'evidence'=>failure)
 creation_summary['aggregation_ledger']<<{'source_provenance'=>[{'source_kind'=>'review_pass','source_id'=>id}],'disposition'=>'coverage_gap','source_coverage_gap_ids'=>['creation-gap:'+id],'rationale'=>failure}
end
result=check.call('validate_terminal_barrier',creation_failure,creation_failure['terminal_barrier'],true,'v10 typed creation failure needs no fabricated actor')
assert(result['result']['coverage_complete']==false,'native creation failure became complete coverage')
check.call('validate_aggregate_accounting',creation_failure,creation_summary,true,'v10 creation failure retains truthful incomplete aggregate')
historical_failure=copy(creation_failure);historical_failure['producer_version']='9.0'
# Every return authority carries the top-level label; mixing 9.0 with 10.0 returns is relabelling.
historical_failure['return_authorities'].each_value{|a|a['producer_version']='9.0'}
historical_summary=copy(creation_summary);historical_summary['reviewed_scope']=copy(summary['reviewed_scope'])
check.call('validate_aggregate_accounting',historical_failure,historical_summary,true,'historical v9 failure retains original nonempty scope verdict')
check.call('validate_aggregate_accounting',historical_failure,creation_summary,false,'historical v9 does not acquire current zero-inspection allowance')
bad=copy(creation_summary);bad['reviewed_scope']=['never-inspected.rb']
check.call('validate_aggregate_accounting',creation_failure,bad,false,'v10 no-response failure cannot invent inspected scope')
bad=copy(summary);bad['reviewed_scope']=[]
check.call('validate_aggregate_accounting',batch_authority,bad,false,'complete review cannot erase inspected scope')
assert(!ReviewTools.summary_projection_valid?({'plan'=>plan,'review_snapshot_id'=>'snapshot','snapshot_identity'=>snapshot,'producer_version'=>'10.0'},bad),'current v10 complete projection accepted empty inspected scope')
# Retain the real first response while only the other actor creation fails.
# This is distinct from the all-failed/no-response case above.
mixed_failure=copy(batch_authority);mixed_failure.merge!('producer_version'=>'10.0','review_subject'=>'implementation')
mixed_failure['return_authorities']['p1']=copy(current)
mixed_failure['return_authorities']['p2']=copy(creation_failure['return_authorities']['p2'])
retained= mixed_failure['responses']['event:p1']
native=copy(retained['identity_authority']['dispatch_binding']);native.merge!('producer_version'=>'10.0','native_invocation_id'=>current['fresh_dispatch']['native_invocation_id'])
retained['identity_authority']['dispatch_binding']=copy(native);retained['delivery']['binding']=copy(native)
mixed_failure['responses'].delete(mixed_failure['canonical_response_events']['p2'])
mixed_failure['canonical_response_events']['p2']=nil
mixed_failure['terminal_barrier']['pass_attempt_ledger'][1]=copy(creation_failure['terminal_barrier']['pass_attempt_ledger'][1])
mixed_summary=copy(creation_summary);mixed_summary['reviewed_scope']=copy(replies['p1']['reviewed_scope'])
mixed_summary['batch_summaries'][0]['terminal_response_count']=1
mixed_summary['coverage_ledger'][0]=copy(summary['coverage_ledger'][0])
mixed_summary['aggregation_ledger'].reject!{|row|row['source_provenance'][0]['source_id']=='p1'}
check.call('validate_aggregate_accounting',mixed_failure,mixed_summary,true,'mixed partial review retains known inspection')
bad=copy(mixed_summary);bad['reviewed_scope']=[]
check.call('validate_aggregate_accounting',mixed_failure,bad,false,'mixed partial review cannot erase inspected scope')
# A validated inactive same-snapshot return remains inspection evidence even
# when its active retry and the other pass both fail before any response.
# Original fresh actor authority remains independent of the failed active retry.
retained_failure=copy(creation_failure)
prior=copy(mixed_failure['responses']['event:p1']);prior['return_authority']=copy(current)
retained_failure['responses']['event:p1']=prior
next_attempt='p1:creation-failed-retry'
retained_failure['active_attempts']['p1']=next_attempt
retained_failure['return_authorities']['p1']['context']['review_attempt_id']=next_attempt
retained_failure['return_authorities']['p1']['context']['review_subject']='implementation'
prior_attempt=copy(barrier['pass_attempt_ledger'][0]['attempts'][0])
prior_attempt['response_events'][0]['disposition']='stale'
failed_attempt=copy(creation_failure['terminal_barrier']['pass_attempt_ledger'][0]['attempts'][0])
failed_attempt.merge!('review_attempt_id'=>next_attempt,'attempt_count'=>2)
retained_failure['terminal_barrier']['pass_attempt_ledger'][0].merge!('active_terminal_attempt_id'=>next_attempt,'attempts'=>[prior_attempt,failed_attempt])
retained_summary=copy(creation_summary);retained_summary['reviewed_scope']=copy(replies['p1']['reviewed_scope'])
check.call('validate_aggregate_accounting',retained_failure,retained_summary,true,'inactive validated inspection survives active creation failure')
assert(retained_summary['coverage_complete']==false && retained_summary['batch_summaries'][0]['terminal_response_count']==0,'retained scope changed active coverage or counts')
assert(ReviewTools.summary_projection_valid?({'plan'=>plan,'review_snapshot_id'=>'snapshot','snapshot_identity'=>snapshot},retained_summary),'offline incomplete projection assumed absent inactive inspection history')
bad=copy(retained_summary);bad['reviewed_scope']=[]
check.call('validate_aggregate_accounting',retained_failure,bad,false,'active zero-response count cannot erase retained inspection')
bad=copy(retained_summary);bad['reviewed_scope']=['unrelated-boundary']
check.call('validate_aggregate_accounting',retained_failure,bad,false,'nonempty substitute cannot erase known retained scope')
bad=copy(retained_failure);bad['responses']['event:p1'].delete('return_authority')
check.call('validate_aggregate_accounting',bad,retained_summary,false,'inactive current actor needs its independently retained original authority')
bad=copy(retained_failure);original=bad['responses']['event:p1']['return_authority']
original['context']['native_invocation_id']='other-native';original['fresh_dispatch']['native_invocation_id']='other-native'
check.call('validate_aggregate_accounting',bad,retained_summary,false,'retained original fresh authority must match original native invocation')
bad=copy(creation_summary);bad.merge!('coverage_complete'=>true,'result'=>'CLEAN','evidence_bounded_claim'=>'No material findings within the reviewed scope and available evidence')
check.call('validate_aggregate_accounting',creation_failure,bad,false,'v10 no-actor failure cannot certify CLEAN')
bad=copy(creation_failure['terminal_barrier']);bad['pass_attempt_ledger'][0]['attempts'][0].delete('failure_evidence')
check.call('validate_terminal_barrier',creation_failure,bad,false,'v10 creation failure retains real failure evidence')
bad=copy(creation_failure['terminal_barrier']);bad['pass_attempt_ledger'][0]['attempts'][0]['terminal_state']='completed'
check.call('validate_terminal_barrier',creation_failure,bad,false,'v10 response-free judgment cannot become completed')
bad=copy(creation_failure);bad['return_authorities']['p1'].delete('required_coverage_tuples')
check.call('validate_terminal_barrier',bad,bad['terminal_barrier'],false,'v10 no-actor failure still needs frozen coverage authority')
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
closure_authority['return_authorities']['pc']={'producer_version'=>'9.0','historical_dispatch_binding'=>binding.merge(cc.slice('batch_id','review_snapshot_id','review_pass_id','review_attempt_id')).merge('native_invocation_id'=>'native-pc'),'context'=>cc,'required_coverage_tuples'=>[ct]}
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
repaired['return_authorities']['p1']['historical_dispatch_binding']=copy(new_response['identity_authority']['dispatch_binding'])
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

# Complete two-pass v10 barrier: every pass is a newly created actor under one root.
v10_fact=->(id,actor,subject){{'actor_id'=>actor,'root_actor_id'=>'root','author_actor_ids'=>['author'],'prior_reviewer_actor_ids'=>[],'native_invocation_id'=>'native:'+actor,'creation_evidence_ref'=>'native:create-'+actor,'runtime_evidence_ref'=>'native:observed-'+actor,'runtime'=>'codex','fork_turns'=>'none','context_isolation'=>'fresh_self_contained','handoff_digest'=>'sha256:handoff-'+id,'source_digest'=>snapshot['value'],'review_subject'=>subject}}
set_fact=->(a,id,fact){ra=a['return_authorities'][id];ra['fresh_dispatch']=fact;ra['context'].merge!('reviewer_actor_id'=>fact['actor_id'],'native_invocation_id'=>fact['native_invocation_id'],'handoff_digest'=>fact['handoff_digest'],'review_subject'=>fact['review_subject'])}
set_native=->(response,changes){nb=response['identity_authority']['dispatch_binding'];nb.merge!(changes);response['delivery']['binding']=copy(nb)}
build_v10=lambda do |subject|
 a=copy(batch_authority);a.merge!('producer_version'=>'10.0','review_subject'=>subject)
 {'p1'=>'reviewer-1','p2'=>'reviewer-2'}.each do |id,actor|
  a['return_authorities'][id]['producer_version']='10.0';a['return_authorities'][id].delete('historical_dispatch_binding')
  fact=v10_fact.(id,actor,subject);set_fact.(a,id,fact)
  set_native.(a['responses']['event:'+id],'producer_version'=>'10.0','native_invocation_id'=>fact['native_invocation_id'])
 end
 a
end
v10=build_v10.('implementation')
v10_summary=copy(summary);v10_summary['reviewed_scope']=['scope']
result=check.call('validate_terminal_barrier',v10,v10['terminal_barrier'],true,'complete two-pass v10 barrier')
assert(result['result']=={'terminal_pass_count'=>2,'coverage_complete'=>true},'complete v10 barrier result changed')
result=check.call('validate_aggregate_accounting',v10,v10_summary,true,'complete two-pass v10 aggregate')
assert(result.dig('result','result')=='CLEAN' && !result['result'].key?('request_plan_reconciliation'),'implementation review acquired reconciliation')
assert(result['result']=={'producer_version'=>'10.0','coverage_complete'=>true,'result'=>'CLEAN','source_finding_count'=>0},'aggregate result does not echo producer_version: '+result['result'].inspect)
lost_scope=copy(v10_summary);lost_scope['reviewed_scope']=['unrelated-scope']
result=check.call('validate_aggregate_accounting',v10,lost_scope,false,'v10 aggregate cannot drop retained inspected scope')
assert(result['diagnostics']==['aggregate_scope_lost'],'lost scope failed for wrong reason: '+result['diagnostics'].inspect)
[
 ['two passes share one actor','review_actor_reused',->(a){set_fact.(a,'p2',v10_fact.('p2','reviewer-1','implementation'))}],
 ['passes under different roots','review_root_mismatch',->(a){f=v10_fact.('p2','reviewer-2','implementation');f['root_actor_id']='other-root';set_fact.(a,'p2',f)}],
 ['pass bound to another review subject','review_subject_mismatch',->(a){set_fact.(a,'p2',v10_fact.('p2','reviewer-2','plan'))}],
 ['current authority relabelled with fabricated v9 binding','review_version_relabelled',->(a){ra=a['return_authorities']['p1'];ra.delete('fresh_dispatch');ra['producer_version']='9.0';ra['historical_dispatch_binding']=a['responses']['event:p1']['identity_authority']['dispatch_binding'].merge('producer_version'=>'9.0')}],
 ['top-level 9.0 label over current v10 returns','review_version_relabelled',->(a){a['producer_version']='9.0'}],
 ['top-level 9.0 label over one current v10 return','review_version_relabelled',->(a){a['producer_version']='9.0';ra=a['return_authorities']['p2'];ra.delete('fresh_dispatch');ra['producer_version']='9.0';ra['historical_dispatch_binding']=a['responses']['event:p2']['identity_authority']['dispatch_binding'].merge('producer_version'=>'9.0')}]
].each do |label,code,mutate|
 a=copy(v10);mutate.call(a)
 result=check.call('validate_terminal_barrier',a,a['terminal_barrier'],false,'v10 barrier rejects '+label)
 assert(result['diagnostics']==[code],label+' failed for wrong reason: '+result['diagnostics'].inspect)
end
# A v9 reader cannot accept a fabricated v9 binding for a native v10 invocation.
[['9.0','v9 label'],['10.0','copied v10 label']].each do |label_version,label|
 a=copy(batch_authority);native=a['responses']['event:p1']
 set_native.(native,'producer_version'=>'10.0')
 a['return_authorities']['p1']['historical_dispatch_binding']=native['identity_authority']['dispatch_binding'].merge('producer_version'=>label_version)
 result=check.call('validate_terminal_barrier',a,a['terminal_barrier'],false,'fabricated historical binding with '+label+' over native v10')
 assert(result['diagnostics']==['historical_review_authority_missing'],'fabricated v9 binding failed for wrong reason: '+result['diagnostics'].inspect)
end
# A retry is a new actor; the retained stale attempt actor stays in the comparison.
stale=copy(v10);retry_attempt='p1:retry-8';retry_event='event:p1:retry-8'
stale['responses']['event:p1']['return_authority']=copy(v10['return_authorities']['p1'])
retry_fact=v10_fact.('p1','reviewer-3','implementation');retry_fact['prior_reviewer_actor_ids']=['reviewer-1']
set_fact.(stale,'p1',retry_fact);stale['return_authorities']['p1']['context']['review_attempt_id']=retry_attempt
stale['active_attempts']['p1']=retry_attempt;stale['canonical_response_events']['p1']=retry_event
retry_reply=copy(replies['p1']);retry_reply['review_attempt_id']=retry_attempt
retry_response=copy(stale['responses']['event:p1']);retry_response.delete('return_authority')
set_native.(retry_response,'review_attempt_id'=>retry_attempt,'native_invocation_id'=>retry_fact['native_invocation_id'])
retry_response['delivery'].merge!('event_id'=>retry_event,'payload_ref'=>'raw:p1:retry-8','payload'=>JSON.generate(retry_reply))
stale['responses'][retry_event]=retry_response
stale_ledger=stale['terminal_barrier']['pass_attempt_ledger'][0];stale_ledger['attempts'][0]['response_events'][0]['disposition']='stale'
retry_entry=copy(stale_ledger['attempts'][0]);retry_entry.merge!('attempt_count'=>2,'review_attempt_id'=>retry_attempt)
retry_entry['response_events']=[{'response_event_id'=>retry_event,'dispatch_attempt_id'=>retry_attempt,'disposition'=>'active_terminal'}]
stale_ledger['attempts']<<retry_entry;stale_ledger['active_terminal_attempt_id']=retry_attempt
check.call('validate_aggregate_accounting',stale,v10_summary,true,'v10 retry by a new actor retains stale attempt evidence')
[
 ['retry reuses stale attempt actor','review_actor_reused',->(a){f=v10_fact.('p1','reviewer-1','implementation');set_fact.(a,'p1',f);a['responses']['event:p1:retry-8']['identity_authority']['dispatch_binding']['native_invocation_id']=f['native_invocation_id'];set_native.(a['responses']['event:p1:retry-8'],{})}],
 ['other pass reuses stale attempt actor','review_actor_reused',->(a){f=v10_fact.('p2','reviewer-1','implementation');set_fact.(a,'p2',f);set_native.(a['responses']['event:p2'],'native_invocation_id'=>f['native_invocation_id'])}],
 ['retry omits earlier attempt actor from prior reviewers','review_prior_actor_missing',->(a){a['return_authorities']['p1']['fresh_dispatch']['prior_reviewer_actor_ids']=[]}],
 ['stale attempt under another root','review_root_mismatch',->(a){a['responses']['event:p1']['return_authority']['fresh_dispatch']['root_actor_id']='other-root'}],
 ['stale v10 attempt without its retained return authority','retained_review_authority_missing',->(a){a['responses']['event:p1'].delete('return_authority')}],
 ['retained inactive authority relabelled 9.0 under a 10.0 aggregate','review_version_relabelled',->(a){a['responses']['event:p1']['return_authority']['producer_version']='9.0'}],
 ['retained authority binds another actor to the active attempt','review_actor_mismatch',->(a){ra=copy(a['return_authorities']['p1']);ra['fresh_dispatch']['actor_id']='reviewer-9';ra['context']['reviewer_actor_id']='reviewer-9';a['responses']['event:p1:retry-8']['return_authority']=ra}]
].each do |label,code,mutate|
 a=copy(stale);mutate.call(a)
 result=check.call('validate_aggregate_accounting',a,v10_summary,false,'v10 aggregate rejects '+label)
 assert(result['diagnostics']==[code],label+' failed for wrong reason: '+result['diagnostics'].inspect)
end
# Plan and final acceptance reconcile the original request and approved plan.
remaining_summary=copy(v10_summary);remaining_summary.delete('evidence_bounded_claim');remaining_summary['result']='HAS_REMAINING_ITEMS'
full={'original_request_ref'=>'request:original','approved_plan_ref'=>'plan:approved','required_requirement_ids'=>%w[R1 R2],'observed_requirement_ids'=>%w[R1 R2],'unresolved_requirement_ids'=>[],'unfinished_task_wide_work'=>[],'unresolved_finding_ids'=>[]}
%w[plan acceptance].each do |subject|
 a=build_v10.(subject);a['request_plan_reconciliation']=copy(full)
 result=check.call('validate_aggregate_accounting',a,v10_summary,true,subject+' review with full request/plan coverage is CLEAN')
 assert(result.dig('result','result')=='CLEAN' && result.dig('result','request_plan_reconciliation')==full,subject+' reconciliation not echoed unchanged')
 check.call('validate_aggregate_accounting',a,remaining_summary,false,subject+' full coverage cannot report remaining items')
 [
  ['missing requirement','request_coverage_missing',->(r){r['observed_requirement_ids']=['R1']}],
  ['absent observed list','request_coverage_missing',->(r){r.delete('observed_requirement_ids')}],
  ['unresolved requirement','request_plan_incomplete',->(r){r['unresolved_requirement_ids']=['R2']}],
  ['unresolved finding','request_plan_incomplete',->(r){r['unresolved_finding_ids']=['aggregate:open']}],
  ['unknown unresolved requirement list','request_plan_incomplete',->(r){r.delete('unresolved_requirement_ids')}],
  ['unknown unresolved finding list','request_plan_incomplete',->(r){r.delete('unresolved_finding_ids')}]
 ].concat(subject=='acceptance' ? [
  ['unfinished task-wide work','request_plan_incomplete',->(r){r['unfinished_task_wide_work']=['documentation update']}],
  ['unknown unfinished work list','request_plan_incomplete',->(r){r.delete('unfinished_task_wide_work')}]
 ] : []).each do |label,code,mutate|
  b=copy(a);mutate.call(b['request_plan_reconciliation'])
  result=check.call('validate_aggregate_accounting',b,v10_summary,false,subject+' '+label+' cannot be CLEAN')
  assert(result['diagnostics']==[code],label+' failed for wrong reason: '+result['diagnostics'].inspect)
  result=check.call('validate_aggregate_accounting',b,remaining_summary,true,subject+' '+label+' remains HAS_REMAINING_ITEMS')
  assert(result.dig('result','request_plan_reconciliation')==b['request_plan_reconciliation'],label+' reconciliation not echoed')
 end
 [
  ['foreign observed requirement','request_coverage_foreign',->(r){r['observed_requirement_ids']=%w[R1 R2 R9]}],
  ['foreign unresolved requirement','request_coverage_foreign',->(r){r['unresolved_requirement_ids']=['R9']}],
  ['duplicate observed requirement','request_coverage_duplicate',->(r){r['observed_requirement_ids']=%w[R1 R1 R2]}],
  ['duplicate required requirement','request_coverage_duplicate',->(r){r['required_requirement_ids']=%w[R1 R1 R2]}],
  ['empty required requirements','request_coverage_unknown',->(r){r['required_requirement_ids']=[]}],
  ['blank unfinished work','request_coverage_unknown',->(r){r['unfinished_task_wide_work']=['']}],
  ['undeclared field','request_coverage_unknown',->(r){r['checked_boxes']=['R1']}],
  ['missing approved plan','request_plan_binding_missing',->(r){r.delete('approved_plan_ref')}]
 ].each do |label,code,mutate|
  b=copy(a);mutate.call(b['request_plan_reconciliation'])
  [v10_summary,remaining_summary].each do |s|
   result=check.call('validate_aggregate_accounting',b,s,false,subject+' rejects '+label)
   assert(result['diagnostics']==[code],label+' failed for wrong reason: '+result['diagnostics'].inspect)
  end
 end
 # Plan review observes allocation: planned unfinished task-wide work is not gated.
 if subject=='plan'
  [['planned unfinished work',->(r){r['unfinished_task_wide_work']=['documentation update']}],['absent unfinished work',->(r){r.delete('unfinished_task_wide_work')}]].each do |label,mutate|
   b=copy(a);mutate.call(b['request_plan_reconciliation'])
   result=check.call('validate_aggregate_accounting',b,v10_summary,true,'plan review with '+label+' is CLEAN')
   assert(result.dig('result','result')=='CLEAN' && result.dig('result','request_plan_reconciliation')==b['request_plan_reconciliation'],'plan '+label+' not CLEAN/echoed')
   check.call('validate_aggregate_accounting',b,remaining_summary,false,'plan review with '+label+' cannot report remaining items')
  end
 end
 b=copy(a);b.delete('request_plan_reconciliation')
 result=check.call('validate_aggregate_accounting',b,remaining_summary,false,subject+' review needs request/plan reconciliation')
 assert(result['diagnostics']==['request_plan_binding_missing'],'missing reconciliation failed for wrong reason')
 b=copy(a);set_fact.(b,'p2',v10_fact.('p2','reviewer-2','implementation'))
 result=check.call('validate_aggregate_accounting',b,v10_summary,false,subject+' aggregate rejects implementation-bound pass')
 assert(result['diagnostics']==['review_subject_mismatch'],'subject mismatch failed for wrong reason')
end

# D2: trivial/small light review is one newly created fresh pass covering both
# trivial_small concerns; its post-fix re-review folds closure into one new pass.
light_p='light_contract_and_runtime'
light_of=lambda do |base,base_summary|
 a=copy(base);s=copy(base_summary)
 lp={'review_pass_id'=>'p1','perspective'=>light_p,'assigned_scope'=>['scope'],'coverage_obligations'=>['contract','runtime'],'prior_finding_visibility'=>'none'}
 lt=lp['coverage_obligations'].map{|o|{'review_pass_id'=>'p1','scope_item_id'=>'scope','applicable_concern'=>'contract','review_perspective'=>light_p,'coverage_obligation'=>o}}
 a['plan']['expected_passes']=[lp];a['plan']['required_coverage_tuples']=lt
 a['plan']['topology'].merge!('discovery_pass_count'=>1,'max_required_responses'=>1,'light_review'=>true);a['controller_intensity']='light'
 %w[active_attempts return_authorities canonical_response_events].each{|k|a[k].delete('p2')}
 a['responses'].delete('event:p2');a['terminal_barrier']['pass_attempt_ledger'].reject!{|e|e['review_pass_id']=='p2'}
 ra=a['return_authorities']['p1'];ra['context']['review_perspective']=light_p;ra['required_coverage_tuples']=lt
 reply=JSON.parse(a['responses']['event:p1']['delivery']['payload'])
 reply['review_perspective']=light_p;reply['coverage_entries']=lt.map{|t|t.reject{|k,_|k=='review_pass_id'}.merge('status'=>'inspected_no_risk','evidence'=>'inspected both concerns')}
 a['responses']['event:p1']['delivery']['payload']=JSON.generate(reply)
 s['final_batch_plan']=copy(a['plan'])
 s['coverage_ledger']=lt.map{|t|t.reject{|k,_|k=='review_perspective'}.merge('perspective'=>light_p,'batch_id'=>'batch','review_snapshot_id'=>'snapshot','assigned_scope'=>['scope'],'terminal_state'=>'completed','coverage_status'=>'complete','coverage_disposition'=>'inspected_no_risk','evidence'=>'source inspected')}
 s['batch_summaries'][0].merge!('expected_response_count'=>1,'terminal_response_count'=>1)
 [a,s]
end
light_reply=->(a){JSON.parse(a['responses']['event:p1']['delivery']['payload'])}
set_light_reply=->(a,r){a['responses']['event:p1']['delivery']['payload']=JSON.generate(r)}
light,light_summary=light_of.(batch_authority,summary)
result=check.call('validate_terminal_barrier',light,light['terminal_barrier'],true,'historical-label one-pass light trivial/small barrier')
assert(result['result']=={'terminal_pass_count'=>1,'coverage_complete'=>true},'light barrier result changed')
result=check.call('validate_aggregate_accounting',light,light_summary,true,'one-pass light trivial/small aggregate')
assert(result['result']=={'producer_version'=>'9.0','coverage_complete'=>true,'result'=>'CLEAN','source_finding_count'=>0},'light aggregate result did not echo producer_version: '+result['result'].inspect)
v10_light,v10_light_summary=light_of.(v10,v10_summary)
result=check.call('validate_aggregate_accounting',v10_light,v10_light_summary,true,'current v10 one-pass light aggregate')
assert(result.dig('result','producer_version')=='10.0' && result.dig('result','result')=='CLEAN','v10 light aggregate result did not echo producer_version')
trivial=copy(v10_light);trivial['plan']['scope_size']='trivial';trivial_summary=copy(v10_light_summary);trivial_summary['final_batch_plan']=copy(trivial['plan'])
check.call('validate_aggregate_accounting',trivial,trivial_summary,true,'trivial scope also uses one light pass')
# Historical two-pass small batches stay valid (batch_authority above); light topology is exact.
[
 ['light review with separate closure pass','topology_light_closure_invalid',->(a){a['plan']['topology']['closure_verification_required']=true}],
 ['light pass at medium scope','topology_pass_mismatch',->(a){a['plan']['scope_size']='medium'}],
 ['one-pass trivial/small with a narrow perspective','topology_pass_mismatch',->(a){a['plan']['expected_passes'][0]['perspective']='contract_and_test_oracle'}],
 ['two-pass count with one light pass','topology_pass_mismatch',->(a){a['plan']['topology']['discovery_pass_count']=2}],
 ['light count mismatch','topology_count_mismatch',->(a){a['plan']['topology']['max_required_responses']=2}],
 ['first light review cannot receive prior findings','plan_visibility_mismatch',->(a){a['plan']['expected_passes'][0]['prior_finding_visibility']='closure_ledger'}]
].each do |label,code,mutate|
 a=copy(v10_light);mutate.call(a)
 result=check.call('validate_terminal_barrier',a,a['terminal_barrier'],false,'light topology rejects '+label)
 assert(result['diagnostics']==[code],label+' failed for wrong reason: '+result['diagnostics'].inspect)
end
# K4: the one-pass light topology requires the explicit indicator and the caller's light intensity.
[
 ['one pass without light_review','topology_light_review_missing',->(a){a['plan']['topology'].delete('light_review')}],
 ['one pass with light_review false','topology_light_review_missing',->(a){a['plan']['topology']['light_review']=false}],
 ['light_review under standard intensity','topology_light_intensity_mismatch',->(a){a['controller_intensity']='standard'}],
 ['light_review under strict intensity','topology_light_intensity_mismatch',->(a){a['controller_intensity']='strict'}],
 ['light_review without caller intensity','topology_light_intensity_mismatch',->(a){a.delete('controller_intensity')}],
 ['unknown controller intensity','controller_intensity_invalid',->(a){a['controller_intensity']='heavy'}],
 ['non-boolean light_review','plan_schema_invalid',->(a){a['plan']['topology']['light_review']='light'}]
].each do |label,code,mutate|
 a=copy(v10_light);mutate.call(a)
 result=check.call('validate_terminal_barrier',a,a['terminal_barrier'],false,'light indicator rejects '+label)
 assert(result['diagnostics']==[code],label+' failed for wrong reason: '+result['diagnostics'].inspect)
end
%w[standard strict].each do |intensity|
 a=copy(batch_authority);a['controller_intensity']=intensity
 check.call('validate_terminal_barrier',a,a['terminal_barrier'],true,'small '+intensity+' keeps the two-pass topology')
 a['plan']['topology']['light_review']=true
 result=check.call('validate_terminal_barrier',a,a['terminal_barrier'],false,'light_review on a two-pass small '+intensity+' batch')
 assert(result['diagnostics']==['topology_light_review_invalid'],'two-pass light_review failed for wrong reason: '+result['diagnostics'].inspect)
end
two_light=copy(batch_authority);two_light['plan']['expected_passes'][1]['perspective']=light_p
result=check.call('validate_terminal_barrier',two_light,barrier,false,'two-pass small batch cannot substitute the light pass')
assert(result['diagnostics']==['topology_pass_mismatch'],'two-pass light substitution failed for wrong reason: '+result['diagnostics'].inspect)
# Post-fix light re-review: one new fresh pass also verifies closure.
fixed_light,fixed_light_summary=light_of.(batch_authority,summary)
fixed_light['plan']['expected_passes'][0]['prior_finding_visibility']='closure_ledger'
fixed_light['return_authorities']['p1']['context']['previously_fixed']=[original]
fixed_light.merge!('previously_fixed'=>[original],'historical_fixed_findings'=>[old_source],'source_findings'=>[old_source])
r=light_reply.(fixed_light);r['closure_results']=[{'aggregate_finding_id'=>'aggregate:old','status'=>'verified_closed','evidence'=>'fresh light re-review observed closure'}];set_light_reply.(fixed_light,r)
fixed_light_summary['final_batch_plan']=copy(fixed_light['plan'])
fixed_light_summary.merge!('aggregation_ledger'=>[fixed_row],'fixed_items'=>[{'aggregate_finding_id'=>'aggregate:old','severity'=>'must-fix','file'=>'source.rb','description'=>'prior finding fixed','fixed_in_round'=>1}],'closure_results'=>r['closure_results'],'result'=>'ISSUES_FIXED')
result=check.call('validate_aggregate_accounting',fixed_light,fixed_light_summary,true,'single fresh light re-review verifies closure')
assert(result.dig('result','result')=='ISSUES_FIXED','light re-review result changed')
check.call('validate_return',fixed_light['return_authorities']['p1'],r,true,'light re-review return carries closure results')
no_closure=copy(r);no_closure.delete('closure_results')
result=check.call('validate_return',fixed_light['return_authorities']['p1'],no_closure,false,'light re-review must return closure results')
assert(result['diagnostics']==['return_schema_invalid'],'missing light closure failed for wrong reason: '+result['diagnostics'].inspect)
foreign=copy(r);foreign['closure_results'][0]['aggregate_finding_id']='aggregate:other'
result=check.call('validate_return',fixed_light['return_authorities']['p1'],foreign,false,'light re-review closure IDs are exact')
assert(result['diagnostics']==['closure_identity_mismatch'],'light closure identity failed for wrong reason: '+result['diagnostics'].inspect)
regressed=copy(r);regressed['closure_results'][0]['status']='regressed'
result=check.call('validate_return',fixed_light['return_authorities']['p1'],regressed,false,'light regressed closure needs a fresh finding')
assert(result['diagnostics']==['closure_finding_missing'],'light regression failed for wrong reason: '+result['diagnostics'].inspect)
a=copy(fixed_light);a['plan']['expected_passes'][0]['prior_finding_visibility']='none'
result=check.call('validate_terminal_barrier',a,a['terminal_barrier'],false,'post-fix light re-review must receive the closure ledger')
assert(result['diagnostics']==['plan_visibility_mismatch'],'light re-review visibility failed for wrong reason: '+result['diagnostics'].inspect)
s=copy(fixed_light_summary);s['closure_results'][0]['evidence']='closure claimed without the light re-review'
result=check.call('validate_aggregate_accounting',fixed_light,s,false,'aggregate closure binds the light re-review return')
assert(result['diagnostics']==['closure_response_mismatch'],'aggregate light closure failed for wrong reason: '+result['diagnostics'].inspect)

# U4: plan review is one fresh plan_coverage_and_feasibility pass (topology.plan_review
# true, review_subject plan) at any scope size; its post-fix re-review folds closure.
plan_p='plan_coverage_and_feasibility'
plan_of=lambda do |base,base_summary|
 a,s=light_of.(base,base_summary)
 a=JSON.parse(JSON.generate(a).gsub(light_p,plan_p));s=JSON.parse(JSON.generate(s).gsub(light_p,plan_p))
 a['plan']['topology'].delete('light_review');a['plan']['topology']['plan_review']=true;a['controller_intensity']='standard'
 a['request_plan_reconciliation']=copy(full);s['final_batch_plan']=copy(a['plan'])
 [a,s]
end
plan_one,plan_one_summary=plan_of.(build_v10.('plan'),v10_summary)
result=check.call('validate_terminal_barrier',plan_one,plan_one['terminal_barrier'],true,'one-pass plan review barrier')
assert(result['result']=={'terminal_pass_count'=>1,'coverage_complete'=>true},'plan barrier result changed')
result=check.call('validate_aggregate_accounting',plan_one,plan_one_summary,true,'one-pass plan review aggregate')
assert(result.dig('result','result')=='CLEAN' && result.dig('result','request_plan_reconciliation')==full,'plan aggregate not CLEAN/echoed')
medium_plan=copy(plan_one);medium_plan['plan']['scope_size']='medium';medium_summary=copy(plan_one_summary);medium_summary['final_batch_plan']=copy(medium_plan['plan'])
check.call('validate_aggregate_accounting',medium_plan,medium_summary,true,'medium plan review also uses one plan pass')
multi_pass_plan=build_v10.('plan');multi_pass_plan['request_plan_reconciliation']=copy(full)
check.call('validate_aggregate_accounting',multi_pass_plan,v10_summary,true,'v10 multi-pass plan batch accepted; one-pass is prose-enforced')
[
 ['plan_review under implementation subject','topology_plan_review_invalid',->(a){a['review_subject']='implementation'}],
 ['plan_review under acceptance subject','topology_plan_review_invalid',->(a){a['review_subject']='acceptance'}],
 ['plan_review without review subject','topology_plan_review_invalid',->(a){a.delete('review_subject')}],
 ['plan pass without plan_review','topology_plan_review_missing',->(a){a['plan']['topology'].delete('plan_review')}],
 ['plan pass with plan_review false','topology_plan_review_missing',->(a){a['plan']['topology']['plan_review']=false}],
 ['non-boolean plan_review','plan_schema_invalid',->(a){a['plan']['topology']['plan_review']='plan'}],
 ['plan review with separate closure pass','topology_plan_closure_invalid',->(a){a['plan']['topology']['closure_verification_required']=true}],
 ['plan review with a narrow perspective','topology_pass_mismatch',->(a){a['plan']['expected_passes'][0]['perspective']='contract_and_test_oracle'}],
 ['plan review discovery count 2','topology_count_mismatch',->(a){a['plan']['topology']['discovery_pass_count']=2}],
 ['plan review also flagged light','topology_light_review_invalid',->(a){a['plan']['topology']['light_review']=true;a['controller_intensity']='light'}],
 ['first plan review cannot receive prior findings','plan_visibility_mismatch',->(a){a['plan']['expected_passes'][0]['prior_finding_visibility']='closure_ledger'}]
].each do |label,code,mutate|
 a=copy(plan_one);mutate.call(a)
 result=check.call('validate_terminal_barrier',a,a['terminal_barrier'],false,'plan topology rejects '+label)
 assert(result['diagnostics']==[code],label+' failed for wrong reason: '+result['diagnostics'].inspect)
end
two_plan=build_v10.('plan');two_plan['plan']['topology']['plan_review']=true
result=check.call('validate_terminal_barrier',two_plan,two_plan['terminal_barrier'],false,'plan_review on a two-pass batch')
assert(result['diagnostics']==['topology_pass_mismatch'],'two-pass plan_review failed for wrong reason: '+result['diagnostics'].inspect)
# Post-fix plan re-review: one new fresh pass carries the closure ledger and closure_results.
fixed_plan,fixed_plan_summary=plan_of.(build_v10.('plan'),v10_summary)
fixed_plan['plan']['expected_passes'][0]['prior_finding_visibility']='closure_ledger'
fixed_plan['return_authorities']['p1']['context']['previously_fixed']=[original]
fixed_plan.merge!('previously_fixed'=>[original],'historical_fixed_findings'=>[old_source],'source_findings'=>[old_source])
r=light_reply.(fixed_plan);r['closure_results']=[{'aggregate_finding_id'=>'aggregate:old','status'=>'verified_closed','evidence'=>'fresh plan re-review observed closure'}];set_light_reply.(fixed_plan,r)
fixed_plan_summary['final_batch_plan']=copy(fixed_plan['plan'])
fixed_plan_summary.merge!('aggregation_ledger'=>[fixed_row],'fixed_items'=>[{'aggregate_finding_id'=>'aggregate:old','severity'=>'must-fix','file'=>'source.rb','description'=>'prior finding fixed','fixed_in_round'=>1}],'closure_results'=>r['closure_results'],'result'=>'ISSUES_FIXED')
result=check.call('validate_aggregate_accounting',fixed_plan,fixed_plan_summary,true,'single fresh plan re-review verifies closure')
assert(result.dig('result','result')=='ISSUES_FIXED','plan re-review result changed')
check.call('validate_return',fixed_plan['return_authorities']['p1'],r,true,'plan re-review return carries closure results')
no_closure=copy(r);no_closure.delete('closure_results')
result=check.call('validate_return',fixed_plan['return_authorities']['p1'],no_closure,false,'plan re-review must return closure results')
assert(result['diagnostics']==['return_schema_invalid'],'missing plan closure failed for wrong reason: '+result['diagnostics'].inspect)
foreign=copy(r);foreign['closure_results'][0]['aggregate_finding_id']='aggregate:other'
result=check.call('validate_return',fixed_plan['return_authorities']['p1'],foreign,false,'plan re-review closure IDs are exact')
assert(result['diagnostics']==['closure_identity_mismatch'],'plan closure identity failed for wrong reason: '+result['diagnostics'].inspect)
a=copy(fixed_plan);a['plan']['expected_passes'][0]['prior_finding_visibility']='none'
result=check.call('validate_terminal_barrier',a,a['terminal_barrier'],false,'post-fix plan re-review must receive the closure ledger')
assert(result['diagnostics']==['plan_visibility_mismatch'],'plan re-review visibility failed for wrong reason: '+result['diagnostics'].inspect)
s=copy(fixed_plan_summary);s['closure_results'][0]['evidence']='closure claimed without the plan re-review'
result=check.call('validate_aggregate_accounting',fixed_plan,s,false,'aggregate closure binds the plan re-review return')
assert(result['diagnostics']==['closure_response_mismatch'],'aggregate plan closure failed for wrong reason: '+result['diagnostics'].inspect)

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
    (skill/'contracts/input.yaml').unlink(); (scripts/'_vendor/pyyaml/yaml/cyaml.py').unlink()
    missing=subprocess.run(command,capture_output=True,timeout=5)
    assert missing.returncode==1 and json.loads(missing.stdout)['diagnostics']==['runtime_or_contract_unavailable'],'probe ignored a missing input contract: '+missing.stdout.decode()

# Authority objects are typed in the contracts the helper loads; no second schema.
fields={x['name']:x for x in m.load_contract('input')['fields']}
fresh=fields['fresh_dispatch']; historical=fields['historical_dispatch_binding']
fresh_names=[x['name'] for x in fresh['object_fields']]
assert fresh_names==['actor_id','root_actor_id','author_actor_ids','prior_reviewer_actor_ids','native_invocation_id','creation_evidence_ref','runtime_evidence_ref','runtime','fork_turns','context_isolation','handoff_digest','source_digest','review_subject'],fresh_names
assert [x['name'] for x in historical['object_fields']]==m.BINDING_KEYS
for parent in (fresh,historical):
    assert parent['on_missing']=='fail' and parent.get('on_fail'),parent['name']+' lacks on_missing fail/on_fail'
    assert all(x['on_missing']=='fail' for x in parent['object_fields']),parent['name']+' child lacks on_missing fail'
authors=next(x for x in fresh['object_fields'] if x['name']=='author_actor_ids')
fork=next(x for x in fresh['object_fields'] if x['name']=='fork_turns')
assert authors['min_items']==1 and fork['required']=='conditional' and fork['condition']=='runtime == codex'
assert fork['type']=='enum' and fork['enum_values']==['none'] and 'absent when runtime is not codex' in fork['validation'] and 'The Codex rule compares runtime.strip().lower() == codex; padded or other-case codex is invalid' in fork['validation'],fork
runtime_field=next(x for x in fresh['object_fields'] if x['name']=='runtime')
assert runtime_field['validation']=="Equals its stripped lowercase form; ' codex', 'codex ' or 'Codex' is invalid.",runtime_field
enums={x['name']:(x['type'],x.get('enum_values')) for x in fresh['object_fields'] if x['name'] in ('context_isolation','review_subject')}
assert enums=={'context_isolation':('enum',['fresh_self_contained']),'review_subject':('enum',['plan','implementation','closure','acceptance'])},enums
intensity=fields['controller_intensity']
assert intensity['type']=='enum' and intensity['enum_values']==['light','standard','strict'] and intensity['on_missing']=='infer',intensity
reviewer=next(x for x in m.load_contract('handoffs')['handoffs'] if x['name']=='orchestrator_to_reviewer')
context={x['name']:x for x in reviewer['context_fields']}
bundle=next(x for x in m.load_contract('handoffs')['dispatch_context_bundles'] if x['name']=='fresh_reviewer_context')
for key in ('reviewer_actor_id','native_invocation_id','handoff_digest'):
    field=context[key]
    assert field['required']=='conditional' and field['on_missing']=='fail' and field.get('on_fail') and 'never dispatched to the Reviewer' in field['description'],key
    assert key not in bundle['context_fields_from_dispatch'],key+' leaked into the reviewer bundle'

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
