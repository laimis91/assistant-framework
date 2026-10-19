if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

handoff_context_field_has_direct_line() {
    local file="$1"
    local handoff="$2"
    local field="$3"
    local expected="$4"
    awk -v handoff="$handoff" -v field="$field" -v expected="$expected" '
        $0 == "  - name: " handoff { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && /^    context_fields:/ { in_context = 1; next }
        in_context && /^    return_fields:/ { exit }
        in_context && $0 == "      - name: " field { in_field = 1; next }
        in_field && /^        object_fields:/ { exit }
        in_field && index($0, expected) { found = 1; exit }
        in_field && /^      - name: / { exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}
handoff_object_required_fields() {
    local file="$1"
    local handoff="$2"
    local section="$3"
    local object_field="$4"

    awk -v handoff="$handoff" -v section="$section" -v object_field="$object_field" '
        $0 == "  - name: " handoff { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && $0 == "    " section ":" { in_section = 1; next }
        in_section && /^    (context_fields|return_fields):/ { exit }
        in_section && $0 == "      - name: " object_field { in_object = 1; current = ""; next }
        in_object && /^      - name: / { exit }
        in_object && /^          - name: / {
            current = $0
            sub(/^          - name: /, "", current)
            next
        }
        in_object && current != "" && /^            required: true/ {
            print current
            current = ""
        }
    ' "$file"
}
field_in_required_list() {
    local needle="$1"
    shift

    local field
    for field in "$@"; do
        if [[ "$field" == "$needle" ]]; then
            return 0
        fi
    done

    return 1
}
reuse_search_schema_signature() {
    local file="$1"
    local handoff="$2"
    local section="$3"
    local container="$4"

    awk -v handoff="$handoff" -v section="$section" -v container="$container" '
        function indent(line) { match(line, /^ */); return RLENGTH }
        $0 == "  - name: " handoff { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && $0 == "    " section ":" { in_section = 1; next }
        in_section && /^    (context_fields|return_fields):/ && $0 != "    " section ":" { exit }
        !in_section { next }
        container == "" && $0 == "      - name: reuse_search" { in_target = 1; target_indent = indent($0); next }
        container != "" && $0 == "      - name: " container { in_container = 1; next }
        in_container && /^      - name: / && $0 != "      - name: " container { exit }
        in_container && $0 == "          - name: reuse_search" { in_target = 1; target_indent = indent($0); next }
        !in_target { next }
        indent($0) == target_indent && /^ *- name: / { exit }
        /^ *- name: / {
            value = $0
            sub(/^ *- name: /, "", value)
            print "field|" (indent($0) - target_indent) "|" value
            next
        }
        /^ *(type|required|condition|enum_values|min_items): / {
            key = $0
            sub(/^ */, "", key)
            value = key
            sub(/^[^:]+: /, "", value)
            sub(/: .*/, "", key)
            print "attribute|" (indent($0) - target_indent) "|" key "|" value
        }
    ' "$file"
}

test_start "original untagged v12 packets normalize through verified producer provenance"
if python3 - "$FRAMEWORK_DIR" <<'PYORIGINAL'
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("original_v12_controls", root / "tests/p0-p4/lib/task-packet-admission-controls.py")
controls = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = controls
spec.loader.exec_module(controls)
def require(condition, message):
    if not condition:
        raise ValueError(message)
for many in (False, True):
    for active in (False, True):
        request = controls.legacy_request(many, active, tagged=False)
        original = deepcopy(request)
        require("schema_version" not in request["plan"] and "plan_schema_version" not in request["plan"], "Original v12 source was rewritten with a version tag")
        result = subprocess.run(["python3", "-B", str(root / "skills/assistant-workflow/scripts/task-packet-admission.py")], input=json.dumps(request), text=True, capture_output=True)
        answer = json.loads(result.stdout)
        require(result.returncode == 0 and answer["status"] == "accepted", "Verified original untagged v12 request was blocked instead of normalized")
        require(request == original and answer["canonical_plan"]["reconciliation_provenance"]["source_sha256"] == controls.API.digest(original["plan"]), "Original source/provenance changed during normalization")
        for packet in answer["canonical_plan"]["implementation_steps"]:
            require("red_evidence" not in packet and "tdd_cycle_log_ref" not in packet["execution"], "Planned RED was promoted to actual evidence")
PYORIGINAL
then pass; else fail "original untagged v12 public admission failed"; fi

test_start "admission CLI rejects exponent overflow with one complete structured result"
if python3 - "$FRAMEWORK_DIR" <<'PYJSON'
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
helper = root / "skills/assistant-workflow/scripts/task-packet-admission.py"
def require(condition, message):
    if not condition:
        raise ValueError(message)

for number in ("1e309", "-1e309"):
    raw = '{"boundary":"plan","context":{"readiness":{"execution_intent":"end_to_end","ready":true,"route_clear":true}},"plan":{"plan_schema_version":"15.0","extra":' + number + '}}'
    result = subprocess.run(["python3", "-B", str(helper)], input=raw, text=True, capture_output=True)
    try:
        answer = json.loads(result.stdout)
    except ValueError as error:
        raise ValueError("Admission CLI returned incomplete JSON for exponent overflow") from error
    require(result.returncode == 1 and answer["status"] == "blocked" and answer["code"] == "malformed",
            "Exponent overflow must return a structured malformed rejection")
    require(not result.stderr and result.stdout.endswith("\n"), "CLI rejection must not leak a serialization traceback")
spec = importlib.util.spec_from_file_location("cli_controls", root / "tests/p0-p4/lib/task-packet-admission-controls.py")
controls = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = controls
spec.loader.exec_module(controls)
for number, expected_status, expected_exit in (("1e309", "blocked", 1), ("-1e309", "blocked", 1), ("1e308", "accepted", 0)):
    request = controls.valid_request(boundary="plan")
    request["plan"]["implementation_steps"][0]["execution"]["history"] = [{"finite_metadata": "number-marker"}]
    raw = json.dumps(request).replace('"number-marker"', number)
    result = subprocess.run(["python3", "-B", str(helper)], input=raw, text=True, capture_output=True)
    answer = json.loads(result.stdout)
    require(result.returncode == expected_exit and answer["status"] == expected_status and not result.stderr,
            "CLI history must reject overflow while preserving finite JSON numbers")
# Deliberately exercise output encoding failure before any stdout write.
program = "import importlib.util,sys; s=importlib.util.spec_from_file_location('serialization_probe',sys.argv[1]); m=importlib.util.module_from_spec(s); sys.modules[s.name]=m; s.loader.exec_module(m); m.admission=lambda request: {'status':'accepted','retained':float('inf')}; sys.exit(m.main())"
result = subprocess.run(["python3", "-B", "-c", program, str(helper)], input="{}", text=True, capture_output=True)
answer = json.loads(result.stdout)
require(result.returncode == 1 and answer["status"] == "blocked" and answer["code"] == "malformed" and not result.stderr,
        "Output encoding failure must emit one complete blocked object")
PYJSON
then pass; else fail "JSON ingress/output did not reject exponent overflow atomically"; fi

test_start "public packet-admission prompts contain exact fixed requests without grader answers"
packet_prompt_controls="$(mktemp -d "${TMPDIR:-/tmp}/workflow-packet-prompts.XXXXXX")"
p0p4_register_cleanup "$packet_prompt_controls"
packet_prompt_cases=()
while IFS= read -r case_id; do
    packet_prompt_cases+=(--case "$case_id")
done < <(jq -r '.cases[] | select(.semantic_validator == "assistant-workflow.packet_admission_v14") | .id' "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json")
if bash "$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --emit-prompts "$packet_prompt_controls" --skill assistant-workflow \
    "${packet_prompt_cases[@]}" --case clarification-is-material-not-capped >/dev/null \
    && python3 - "$FRAMEWORK_DIR" "$packet_prompt_controls" <<'PYPROMPTS'
import json
from pathlib import Path
import re
import sys

def require(condition, message):
    if not condition:
        raise ValueError(message)


root, output = Path(sys.argv[1]), Path(sys.argv[2])
fixture = json.loads((root / "skills/assistant-workflow/evals/cases.json").read_text())
cases = [case for case in fixture["cases"] if case.get("semantic_validator") == "assistant-workflow.packet_admission_v14"]
require(cases, "No fixed packet-admission cases exercised")
requests, prompts = [], []
for case in cases:
    prompt = (output / "assistant-workflow" / (case["id"] + ".md")).read_text()
    sections = re.findall(r"^## Fixed Packet Admission Request\n\n```json\n(.*?)\n```(?:\n|$)", prompt, re.MULTILINE | re.DOTALL)
    require(len(sections) == 1, "Prompt lacks exact fixed request: " + case["id"])
    request = json.loads(sections[0])
    require(request == case["semantic_context"]["packet_admission"]["request"], "Emitted request changed fixed inputs: " + case["id"])
    require("expected_status" not in prompt and "expected_code" not in prompt, "Prompt leaked grader answers: " + case["id"])
    requests.append(json.dumps(request, sort_keys=True))
    prompts.append(prompt)
for index, request in enumerate(requests):
    for other in range(index):
        if request != requests[other]:
            require(prompts[index] != prompts[other], "Different fixed requests emitted indistinguishable prompts")
require({case["semantic_context"]["packet_admission"]["expected_status"] for case in cases} == {"accepted", "blocked"}, "Prompt controls must exercise valid and unsafe inputs")
clarification = next(case for case in fixture["cases"] if case["id"] == "clarification-is-material-not-capped")
require((output / "assistant-workflow/task-01.md").read_text() == "# User Request\n\n" + clarification["prompt"] + "\n\n", "Unrelated task-only clarification output changed")
PYPROMPTS
then pass; else fail "public prompt emission omitted or changed fixed request inputs, leaked grader answers, or changed unrelated task-only output"; fi

test_start "fixed packet requests and projections satisfy canonical direct fields"
if ruby -ryaml -rjson -ropen3 - "$FRAMEWORK_DIR" <<'RUBYDIRECT'
root = ARGV.fetch(0)
handoffs = YAML.load_file("#{root}/skills/assistant-workflow/contracts/handoffs.yaml").fetch('handoffs')
producer = handoffs.find { |h| h['name'] == 'orchestrator_to_architect' }.fetch('return_fields').find { |f| f['name'] == 'implementation_steps' }.fetch('object_fields')
output = YAML.load_file("#{root}/skills/assistant-workflow/contracts/output.yaml").fetch('artifacts').find { |f| f['name'] == 'implementation_steps' }.fetch('object_fields')
raise 'canonical packet owner drift' unless producer == output
check_direct = lambda do |packet, request|
  producer.each do |field|
    name, kind = field.values_at('name', 'type')
    required = field['required'] == true || (name == 'boundary_reason' && request.fetch('plan').fetch('implementation_steps').length > 1) || (%w[red_check_id red_command red_cwd expected_red_failure].include?(name) && packet['tdd_applies'])
    commands = request.fetch('context').fetch('verification_decision').fetch('checks').select { |c| packet.fetch('selected_check_ids').include?(c['check_id']) && c.key?('command') }
    required ||= name == 'verification_command' && commands.length == 1
    next unless required
    raise "Fixed packet lacks canonical direct field: #{name}" unless packet.key?(name)
    value = packet[name]
    valid = case kind
    when 'string' then value.is_a?(String) && !value.strip.empty?
    when 'boolean' then value == true || value == false
    when 'enum' then field.fetch('enum_values').include?(value)
    when 'object' then value.is_a?(Hash)
    when 'string[]' then value.is_a?(Array) && value.all? { |x| x.is_a?(String) }
    when 'object[]' then value.is_a?(Array) && value.all? { |x| x.is_a?(Hash) }
    else raise "Unhandled applicable direct kind: #{kind}"
    end
    raise "Invalid canonical direct field: #{name}" unless valid
    raise "Canonical direct minimum violated: #{name}" if field.key?('min_items') && value.length < field['min_items']
  end
end
fixture = JSON.parse(File.read("#{root}/skills/assistant-workflow/evals/cases.json"))
cases = fixture.fetch('cases').select { |c| c['semantic_validator'] == 'assistant-workflow.packet_admission_v14' }
raise 'no fixed packet requests' if cases.empty?
cases.each do |item|
  fixed = item.fetch('semantic_context').fetch('packet_admission'); request = fixed.fetch('request')
  request.fetch('plan').fetch('implementation_steps').each { |p| check_direct.call(p, request) }
  stdout, stderr, status = Open3.capture3('python3','-B',"#{root}/skills/assistant-workflow/scripts/task-packet-admission.py", stdin_data: JSON.generate(request))
  actual = JSON.parse(stdout)
  raise 'fixed admission outcome changed' unless actual['status'] == fixed.fetch('expected_status') && actual['code'] == fixed.fetch('expected_code') && stderr.empty? && status.exitstatus == (actual['status'] == 'accepted' ? 0 : 1)
  actual.fetch('canonical_plan').fetch('implementation_steps').each { |p| check_direct.call(p, request) }
  check_direct.call(actual.fetch('current_task_packet'), request) if actual['status'] == 'accepted'
end
RUBYDIRECT
then pass; else fail "fixed canonical packet direct shape or intended outcome changed"; fi

test_start "canonical admission accepts valid work and rejects unsafe evidence and migration"
if python3 "$FRAMEWORK_DIR/tests/p0-p4/lib/task-packet-admission-controls.py"; then
    pass
else
    fail "actual packet admission behavior controls failed"
fi

test_start "stored packets and worker materialization keep one approved definition"
if ruby -ryaml - "$FRAMEWORK_DIR" <<'RUBY'
root = ARGV.fetch(0)
h = YAML.load_file("#{root}/skills/assistant-workflow/contracts/handoffs.yaml").fetch('handoffs')
o = YAML.load_file("#{root}/skills/assistant-workflow/contracts/output.yaml")
f = ->(fields,name) { fields.find { |item| item['name'] == name } || raise("missing #{name}") }
producer = f.call(h.find { |x| x['name'] == 'orchestrator_to_architect' }.fetch('return_fields'),'implementation_steps')
fields = producer.fetch('object_fields')
raise 'stored mutable specialist copy' if fields.any? { |x| %w[verification_decision evidence_assessment slice_id slice_name task_id].include?(x['name']) }
raise 'missing reference digest' unless f.call(fields,'verification_decision_ref').fetch('object_fields').map { |x| x['name'] } == %w[artifact_ref sha256]
state = f.call(f.call(fields,'execution').fetch('object_fields'),'state')
raise 'open coordinator state vocabulary' unless state['enum_values'] == %w[PENDING RUNNING VERIFIED BLOCKED INVALIDATED]
%w[orchestrator_to_code_writer orchestrator_to_builder_tester].each do |name|
  consumer = f.call(h.find { |x| x['name'] == name }.fetch('context_fields'),'current_task_packet').fetch('object_fields')
  fields.each { |field| raise "projection drift #{name} #{field['name']}" unless f.call(consumer,field['name']) == field }
  %w[verification_decision evidence_assessment approved_plan_identity].each { |key| raise 'materialization field missing' unless f.call(consumer,key)['required'] == true }
end
raise 'duplicate live execution artifact' if o.fetch('artifacts').any? { |x| %w[slice_manifest single_slice_rationale decomposition_plan_review slice_verification_summary].include?(x['name']) }
RUBY
then pass; else fail "canonical stored/deep projection contracts drifted"; fi

test_start "public evaluator rejects type-altered accepted packet answers"
typed_answers="$(mktemp -d "${TMPDIR:-/tmp}/workflow-packet-types.XXXXXX")"
p0p4_register_cleanup "$typed_answers"
if python3 - "$FRAMEWORK_DIR" "$typed_answers" <<'PYTYPES'
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import sys
root, out = Path(sys.argv[1]), Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("typed_admission", root / "skills/assistant-workflow/scripts/task-packet-admission.py")
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
fixture = json.loads((root / "skills/assistant-workflow/evals/cases.json").read_text())
case = next(c for c in fixture["cases"] if c["id"] == "packet-admission-coherent-medium-v14")
actual = module.admission(case["semantic_context"]["packet_admission"]["request"])
for variant in ("valid", "type-altered", "missing-required"):
    answer = deepcopy(actual)
    if variant == "type-altered":
        answer["canonical_plan"]["implementation_steps"][0]["tdd_applies"] = 0
        answer["current_task_packet"]["tdd_applies"] = 0
    elif variant == "missing-required":
        for packet in (answer["canonical_plan"]["implementation_steps"][0], answer["current_task_packet"]):
            for field in ("description", "reuse_search", "test_criteria", "implementation_notes", "verification_command"):
                packet.pop(field, None)
    folder = out / variant / "assistant-workflow"
    folder.mkdir(parents=True)
    (folder / (case["id"] + ".txt")).write_text(json.dumps({"packet_admission": answer}))
PYTYPES
then
    typed_answers_failed=false
    for optimization in 0 1; do
        if ! PYTHONOPTIMIZE="$optimization" bash "$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$typed_answers/valid" --skill assistant-workflow --case packet-admission-coherent-medium-v14 >/dev/null 2>&1; then typed_answers_failed=true; fi
        for variant in type-altered missing-required; do
            if PYTHONOPTIMIZE="$optimization" bash "$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$typed_answers/$variant" --skill assistant-workflow --case packet-admission-coherent-medium-v14 >/dev/null 2>&1; then typed_answers_failed=true; fi
        done
    done
    if [[ "$typed_answers_failed" == false ]]; then pass; else fail "public grader accepted changed JSON scalar types or rejected a valid answer"; fi
else
    fail "could not construct public evaluator type controls"
fi

test_start "workflow semantic grading recomputes actual helper with fixed independent authority"
semantic_controls="$(mktemp -d "${TMPDIR:-/tmp}/workflow-packet-semantic.XXXXXX")"
p0p4_register_cleanup "$semantic_controls"
if python3 - "$FRAMEWORK_DIR" "$semantic_controls" <<'PYCONTROL'
from copy import deepcopy
import importlib.util,json,sys
from pathlib import Path
root=Path(sys.argv[1]);out=Path(sys.argv[2])
spec=importlib.util.spec_from_file_location('packet_controls',root/'tests/p0-p4/lib/task-packet-admission-controls.py')
m=importlib.util.module_from_spec(spec);sys.modules[spec.name]=m;spec.loader.exec_module(m)
fixture=json.loads((root/'skills/assistant-workflow/evals/cases.json').read_text())
controls=[]
def record(case_id,name,response,expected):
 filename=case_id+'.'+name+'.json'
 (out/filename).write_text(json.dumps(response))
 controls.append((case_id,filename,str(expected)))
for case in fixture['cases']:
 if case.get('semantic_validator')!='assistant-workflow.packet_admission_v14':continue
 actual=m.API.admission(case['semantic_context']['packet_admission']['request'])
 answer={key:value for key,value in actual.items() if key in ('status','code','canonical_plan','current_task_packet')}
 if actual['status']=='blocked':answer.pop('canonical_plan',None)
 response={'packet_admission':answer}
 record(case['id'],'correct',response,0)
 # A label-only readiness answer must fail even when its vocabulary matches.
 record(case['id'],'unsafe',{'packet_admission':{'status':'accepted','code':'accepted'}},1)
 forged=deepcopy(response)
 forged['packet_admission']['status']='blocked' if actual['status']=='accepted' else 'accepted'
 record(case['id'],'forged-status',forged,1)
 if actual['status']=='accepted':
  for field in ('description','reuse_search','test_criteria','implementation_notes','verification_command'):
   for owner in ('canonical_plan','current_task_packet','both'):
    forged=deepcopy(response)
    for target in (('canonical_plan','current_task_packet') if owner=='both' else (owner,)):
     packet=forged['packet_admission'][target]
     if target=='canonical_plan':packet=packet['implementation_steps'][0]
     packet.pop(field,None)
    record(case['id'],'missing-'+field+'-'+owner,forged,1)
  for owner in ('canonical_plan','current_task_packet','both'):
   for mutation in ('boolean-to-number','number-to-boolean'):
    forged=deepcopy(response)
    targets=('canonical_plan','current_task_packet') if owner=='both' else (owner,)
    for target in targets:
     packet=forged['packet_admission'][target]
     if target=='canonical_plan':packet=packet['implementation_steps'][0]
     if mutation=='boolean-to-number':packet['tdd_applies']=0
     else:packet['execution']['recovery']['attempt_count']=False
    record(case['id'],owner+'-'+mutation,forged,1)
  forged=deepcopy(response)
  forged['packet_admission']['canonical_plan']['implementation_steps'][0]['files_to_modify']=['/unauthorized/override.py']
  record(case['id'],'forged-scope',forged,1)
  forged=deepcopy(response)
  forged['packet_admission']['current_task_packet']['packet_id']='unapproved-outcome'
  record(case['id'],'forged-projection',forged,1)
 else:
  claims={'ready':True,'verified':True,'current_task_packet':{'packet_id':'integrated-outcome'}}
  for owner in ('root','nested'):
   for name,claim in list((key,{key:value}) for key,value in claims.items())+[('combined',claims)]:
    forged=deepcopy(response)
    (forged if owner=='root' else forged['packet_admission']).update(claim)
    record(case['id'],owner+'-'+name,forged,1)
  record(case['id'],'summary',dict(response,summary='Blocked; retain current authority.'),0)
  for invalid_summary in (None, True, 0, [], {'ready':True}):
   record(case['id'],'invalid-summary-'+repr(invalid_summary),dict(response,summary=invalid_summary),1)
  null_plan=deepcopy(response)
  null_plan['packet_admission']['canonical_plan']=None
  record(case['id'],'blocked-null-plan',null_plan,1)
  for owner in ('root','nested'):
   for container in ({'ready':True},{'verified':True},{'current_task_packet':{'packet_id':'integrated-outcome'}},[{'ready':True}],[{'layers':[{'verified':True}]}],{'unrecognized':'extra data'}):
    forged=deepcopy(response)
    (forged if owner=='root' else forged['packet_admission'])['details']=deepcopy(container)
    record(case['id'],owner+'-deep-'+str(len(controls)),forged,1)
  if 'canonical_plan' in actual:
   exact=deepcopy(response)
   exact['packet_admission']['canonical_plan']=deepcopy(actual['canonical_plan'])
   record(case['id'],'blocked-exact-plan',exact,0)
   forged=deepcopy(exact)
   forged['packet_admission']['canonical_plan']['implementation_steps'][0]['files_to_modify']=['/unauthorized/override.py']
   record(case['id'],'blocked-altered-plan',forged,1)
  else:
   forged=deepcopy(response)
   forged['packet_admission']['canonical_plan']={'implementation_steps':[]}
   record(case['id'],'blocked-added-plan',forged,1)
(out/'controls.tsv').write_text(''.join('\t'.join(row)+'\n' for row in controls))
PYCONTROL
then
    source "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-semantic-validators.sh"
    semantic_failed=false
    for optimization in 0 1; do
        while IFS=$'\t' read -r case_id response_file expected; do
            if PYTHONOPTIMIZE="$optimization" run_semantic_validator assistant-workflow.packet_admission_v14 "$semantic_controls/$response_file" "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json" "$case_id" "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md" >/dev/null 2>&1; then observed=0; else observed=1; fi
            if [[ "$observed" != "$expected" ]]; then
                semantic_failed=true
                printf 'Semantic control failed: %s PYTHONOPTIMIZE=%s expected=%s observed=%s\n' "$response_file" "$optimization" "$expected" "$observed" >&2
            fi
        done < "$semantic_controls/controls.tsv"
    done
    if [[ "$semantic_failed" == false ]]; then pass; else fail "shared helper semantic seam accepted unsafe or rejected correct answers"; fi
else
    fail "could not construct independent semantic controls"
fi

test_start "public grader rejects nested blocked readiness and substituted plan authority"
blocked_answers="$(mktemp -d "${TMPDIR:-/tmp}/workflow-blocked-envelope.XXXXXX")"
p0p4_register_cleanup "$blocked_answers"
if python3 - "$FRAMEWORK_DIR" "$blocked_answers" <<'PYBLOCKED'
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import sys
root, out = Path(sys.argv[1]), Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("blocked_envelope_controls", root / "tests/p0-p4/lib/task-packet-admission-controls.py")
controls = importlib.util.module_from_spec(spec); sys.modules[spec.name] = controls; spec.loader.exec_module(controls)
fixture = json.loads((root / "skills/assistant-workflow/evals/cases.json").read_text())
case = next(case for case in fixture["cases"] if case.get("semantic_validator") == "assistant-workflow.packet_admission_v14"
            and case["semantic_context"]["packet_admission"]["expected_status"] == "blocked"
            and "canonical_plan" in controls.API.admission(case["semantic_context"]["packet_admission"]["request"]))
actual = controls.API.admission(case["semantic_context"]["packet_admission"]["request"])
base = {"summary": "Blocked; preserve the retained authority.", "packet_admission": {"status": actual["status"], "code": actual["code"]}}
variants = {"valid": deepcopy(base), "valid-plan": deepcopy(base)}
variants["valid-plan"]["packet_admission"]["canonical_plan"] = deepcopy(actual["canonical_plan"])
for name, owner, payload in (("root-object", "root", {"ready": True}), ("nested-list", "answer", [{"layers": [{"verified": True}]}]),
                             ("nested-packet", "answer", {"current_task_packet": {"packet_id": "invented"}}),
                             ("unknown-container", "root", {"harmless": "unknown"})):
    answer = deepcopy(base)
    (answer if owner == "root" else answer["packet_admission"])["details"] = payload
    variants[name] = answer
variants["null-plan"] = deepcopy(base)
variants["null-plan"]["packet_admission"]["canonical_plan"] = None
variants["invalid-summary"] = deepcopy(base)
variants["invalid-summary"]["summary"] = {"ready": True}
variants["altered-plan"] = deepcopy(variants["valid-plan"])
variants["altered-plan"]["packet_admission"]["canonical_plan"]["implementation_steps"][0]["files_to_modify"] = ["/unauthorized/override.py"]
variants["typed-plan"] = deepcopy(variants["valid-plan"])
variants["typed-plan"]["packet_admission"]["canonical_plan"]["implementation_steps"][0]["execution"]["recovery"]["attempt_count"] = False
for name, response in variants.items():
    target = out / name; target.mkdir()
    (target / (case["id"] + ".txt")).write_text(json.dumps(response))
(out / "case-id").write_text(case["id"])
PYBLOCKED
then
    blocked_case="$(cat "$blocked_answers/case-id")"
    blocked_failed=false
    for optimization in 0 1; do
        for variant in valid valid-plan root-object nested-list nested-packet unknown-container null-plan invalid-summary altered-plan typed-plan; do
            expected=1
            [[ "$variant" != valid && "$variant" != valid-plan ]] || expected=0
            if PYTHONOPTIMIZE="$optimization" bash "$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$blocked_answers/$variant" --skill assistant-workflow --case "$blocked_case" >/dev/null 2>&1; then observed=0; else observed=1; fi
            if [[ "$observed" != "$expected" ]]; then
                blocked_failed=true
                printf 'Blocked public envelope failed: %s PYTHONOPTIMIZE=%s expected=%s observed=%s\n' "$variant" "$optimization" "$expected" "$observed" >&2
            fi
        done
    done
    if [[ "$blocked_failed" == false ]]; then pass; else fail "public grader accepted nested blocked readiness or substituted authority"; fi
else
    fail "could not construct blocked public envelope controls"
fi

test_start "selected Workflow helper identity survives trusted layouts and rejects code escapes"
layout_controls="$(mktemp -d "${TMPDIR:-/tmp}/workflow-selected-helper.XXXXXX")"
p0p4_register_cleanup "$layout_controls"
if python3 - "$FRAMEWORK_DIR" "$layout_controls" <<'PYLAYOUT'
from copy import deepcopy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
root = Path(sys.argv[1]); out = Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("layout_packet_controls", root / "tests/p0-p4/lib/task-packet-admission-controls.py")
controls = importlib.util.module_from_spec(spec); sys.modules[spec.name] = controls; spec.loader.exec_module(controls)
fixture = json.loads((root / "skills/assistant-workflow/evals/cases.json").read_text())
case = next(c for c in fixture["cases"] if c["id"] == "packet-admission-coherent-medium-v14")
actual = controls.API.admission(case["semantic_context"]["packet_admission"]["request"])
if actual["status"] != "accepted": raise ValueError("Fixed selected-helper control must be valid")
answer = {"packet_admission": {k:v for k,v in actual.items() if k in ("status", "code", "canonical_plan", "current_task_packet")}}
responses = out / "responses"; responses.mkdir(); response = responses / (case["id"] + ".txt"); response.write_text(json.dumps(answer))
# Reuse the registered review factory; no expected artifact is copied into this control.
review_case = next(c for c in fixture["cases"] if c["id"] == "standard-pack-review-result-retains-checklist")
review_requirement = fixture["canonical_review_batch_expectations"]["case_requirements"][review_case["id"]]
if review_requirement["required_envelope_alias"] != "canonical_final_summary": raise ValueError("Registered review-envelope fixture changed")
review_response = responses / (review_case["id"] + ".txt")
review_summary = " ".join(review_case["machine_expectations"]["required_substrings"])
subprocess.run(["bash", "-c", 'source "$1"; build_workflow_review_lifecycle_eval_response "$2" "$3" "$4"', "review-layout-response", str(root / "tests/p0-p4/lib/feature-preparation-response-fixtures.sh"), review_case["id"], str(review_response), review_summary], check=True, text=True, capture_output=True)
marker = out / "untrusted-imported"
evil = "from pathlib import Path\nPath(" + repr(str(marker)) + ").write_text('UNTRUSTED')\nraise RuntimeError('wrong helper imported')\n"
def require(value, message):
    if not value: raise ValueError(message)
def install_runner(target):
    shutil.copytree(root / "tools/evals", target / "tools/evals")
def install_workflow(target):
    target.mkdir(parents=True, exist_ok=True)
    for relative in ("SKILL.md", "evals/cases.json", "scripts/task-packet-admission.py"):
        destination = target / relative; destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / "skills/assistant-workflow" / relative, destination)
    shutil.copytree(root / "skills/assistant-workflow/contracts", target / "contracts", dirs_exist_ok=True)
    for companion in ("assistant-verification", "assistant-review"):
        shutil.copytree(root / "skills" / companion / "contracts", target.parent / companion / "contracts", dirs_exist_ok=True)
    return target / "SKILL.md"
def grade(runner, selected, environment):
    return subprocess.run(["bash", str(runner / "tools/evals/run-skill-evals.sh"), "--responses", str(responses), "--skill", str(selected), "--case", case["id"]], env=environment, text=True, capture_output=True)
def grade_review(runner, selected, environment):
    return subprocess.run(["bash", str(runner / "tools/evals/run-skill-evals.sh"), "--responses", str(responses), "--skill", str(selected), "--case", review_case["id"]], env=environment, text=True, capture_output=True)
def review_reader(runner, selected, environment, reader):
    commands = {
        "schema": 'source "$1"; REPO_ROOT="$2"; assistant_review_artifact_schema_valid "$3" "$4" final_summary canonical_final_summary "$5"',
        "lifecycle": 'source "$1"; REPO_ROOT="$2"; assistant_review_lifecycle_semantics_valid "$3" "$4" final_summary canonical_final_summary "$5"',
    }
    return subprocess.run(["bash", "-c", commands[reader], "review-layout-reader", str(runner / "tools/evals/lib/skill-eval-grade.sh"), str(runner), review_case["id"], str(review_response), str(selected.parent / "evals/cases.json")], env=environment, text=True, capture_output=True)
def registered_split_review_envelope_current_owner(runner, selected, environment):
    validation = subprocess.run(["bash", str(runner / "tools/evals/run-skill-evals.sh"), "--validate-fixture", "--skill", str(selected)], env=environment, text=True, capture_output=True)
    require(validation.returncode == 0, "Registered split review setup must validate before grading")
    result = grade_review(runner, selected, environment)
    if result.returncode == 0: return
    summary = next((line for line in result.stdout.splitlines() if line.startswith("Summary: ")), "")
    counts = dict(part.split("=", 1) for part in summary.removeprefix("Summary: ").split() if "=" in part)
    zero_counts = ("unavailable", "incomplete", "missing", "empty", "fail_signal_hits", "missing_required_substrings", "forbidden_substring_hits", "ordered_substring_failures", "seeded_defect_failures", "false_positive_marker_failures", "semantic_validation_failures")
    envelope_only = result.returncode == 1 and not result.stderr.strip() and ("FAIL\tassistant-workflow\t" + review_case["id"] + "\t") in result.stdout and counts.get("total") == "1" and counts.get("passed") == "0" and counts.get("failed") == "1" and counts.get("structured_json_assertion_failures") == "1" and all(counts.get(name) == "0" for name in zero_counts)
    require(not envelope_only, "Valid registered split review envelope was rejected by runner-sibling producer schemas")
    raise ValueError("Unexpected registered split review grading failure: " + result.stdout + result.stderr)
def semantic(runner, selected, environment, response_file=response, fixture_file=None, validator="assistant-workflow.packet_admission_v14", case_id=None):
    fixture_file = fixture_file or selected.parent / "evals/cases.json"
    command = 'source "$1"; run_semantic_validator "$2" "$3" "$4" "$5" "$6"'
    return subprocess.run(["bash", "-c", command, "selected-helper", str(runner / "tools/evals/lib/skill-eval-semantic-validators.sh"), validator, str(response_file), str(fixture_file), case_id or case["id"], str(selected)], env=environment, text=True, capture_output=True)
colocated = out / "co located"; install_runner(colocated); colocated_skill = install_workflow(colocated / "skills/assistant-workflow")
custom = out / "custom contract data mirror"; install_runner(custom); custom_skill = install_workflow(custom / "skills/assistant-workflow")
shutil.rmtree(custom_skill.parent / "contracts")
(custom_skill.parent / "contracts").symlink_to(root / "skills/assistant-workflow/contracts", target_is_directory=True)
profile = out / "profile with spaces"; configured = profile / "custom codex home"; install_runner(configured)
split_skill = install_workflow(profile / ".agents/skills/assistant-workflow")
default_home = profile / ".codex"; install_runner(default_home)
# A selected split helper must never be replaced by a stale tools-sibling copy.
stale = configured / "skills/assistant-workflow"; stale_skill = install_workflow(stale); (stale / "scripts/task-packet-admission.py").write_text(evil)
base = os.environ.copy(); base.pop("USERPROFILE", None); base.pop("CODEX_HOME", None)
for optimization in ("0", "1"):
    env = {**base, "PYTHONOPTIMIZE": optimization}
    require(grade(root, root / "skills/assistant-workflow/SKILL.md", env).returncode == 0, "Repository public grading failed")
    require(grade_review(root, root / "skills/assistant-workflow/SKILL.md", env).returncode == 0, "Repository registered review envelope failed")
    require(grade(colocated, colocated_skill, env).returncode == 0, "Co-located public grading failed")
    require(grade_review(colocated, colocated_skill, env).returncode == 0, "Co-located registered review envelope failed")
    require(grade(custom, custom_skill, env).returncode == 0, "Existing external consumer-contract data mirror failed")
    require(grade_review(custom, custom_skill, env).returncode == 0, "Custom consumer-contract review envelope failed")
    split_env = {**env, "USERPROFILE": str(profile), "HOME": str(out / "wrong home"), "CODEX_HOME": str(configured)}
    for companion in ("assistant-verification", "assistant-review"):
        (configured / "skills" / companion / "contracts/output.yaml").write_text("invalid: [stale schema")
    require(grade(configured, split_skill, split_env).returncode == 0, "Configured split public grading failed or selected stale sibling")
    stale_review_index = configured / "skills/assistant-review/contracts/index.yaml"
    stale_review_index_bytes = stale_review_index.read_bytes()
    stale_review_index.write_text('schema_version: "stale-tools-sibling"\n')
    registered_split_review_envelope_current_owner(configured, split_skill, split_env)
    default_env = {**env, "HOME": str(profile)}
    require(grade(default_home, split_skill, default_env).returncode == 0, "Default split public grading failed")
    require(grade_review(default_home, split_skill, default_env).returncode == 0, "Default split registered review envelope failed")
    require(not marker.exists(), "Stale helper was imported")
    # Full selected fixture validation must use split fixed schemas, never valid stale siblings.
    for companion in ("assistant-verification", "assistant-review"):
        selected_output = split_skill.parent.parent / companion / "contracts/output.yaml"
        stale_output = configured / "skills" / companion / "contracts/output.yaml"
        shutil.copy2(root / "skills" / companion / "contracts/output.yaml", stale_output)
        original_schema = selected_output.read_bytes(); selected_output.unlink()
        require(grade(configured, split_skill, split_env).returncode != 0, "Missing split producer fell back: " + companion)
        selected_output.write_bytes(original_schema)
        outside = out / (companion + "-outside.yaml"); outside.write_bytes(original_schema)
        selected_output.unlink(); selected_output.symlink_to(outside)
        require(grade(configured, split_skill, split_env).returncode != 0, "Escaping split producer schema accepted: " + companion)
        selected_output.unlink(); selected_output.write_bytes(original_schema)
    # Exercise producer readers directly so fixture rejection cannot hide a stale output reader.
    stale_review_index.write_bytes(stale_review_index_bytes)
    for reader in ("schema", "lifecycle"):
        require(review_reader(configured, split_skill, split_env, reader).returncode == 0, "Selected split review reader failed: " + reader)
    for contract_name in ("index.yaml", "output.yaml"):
        selected_contract = split_skill.parent.parent / "assistant-review/contracts" / contract_name
        original_contract = selected_contract.read_bytes(); selected_contract.unlink()
        require(grade_review(configured, split_skill, split_env).returncode != 0, "Missing split review contract fell back: " + contract_name)
        if contract_name == "output.yaml":
            for reader in ("schema", "lifecycle"):
                require(review_reader(configured, split_skill, split_env, reader).returncode != 0, "Missing split output reader fell back: " + reader)
        selected_contract.write_bytes(original_contract)
        outside_contract = out / ("review-outside-" + contract_name); outside_contract.write_bytes(original_contract)
        selected_contract.unlink(); selected_contract.symlink_to(outside_contract)
        require(grade_review(configured, split_skill, split_env).returncode != 0, "Escaping split review contract accepted: " + contract_name)
        if contract_name == "output.yaml":
            for reader in ("schema", "lifecycle"):
                require(review_reader(configured, split_skill, split_env, reader).returncode != 0, "Escaping split output reader accepted: " + reader)
        selected_contract.unlink(); selected_contract.write_bytes(original_contract)
    # A recognized split consumer cannot redirect contract data outside its owner.
    split_contracts = split_skill.parent / "contracts"
    saved_contracts = split_skill.parent / "contracts-kept"
    split_contracts.rename(saved_contracts)
    split_contracts.symlink_to(root / "skills/assistant-workflow/contracts", target_is_directory=True)
    require(grade(configured, split_skill, split_env).returncode != 0, "Escaping split consumer contracts fell back to stale schemas")
    split_contracts.unlink(); saved_contracts.rename(split_contracts)
    # Fixture validation itself must reject a selected split Workflow-parent escape.
    outside_workflow = out / "outside split workflow"; install_workflow(outside_workflow)
    selected_workflow = split_skill.parent; saved_workflow = selected_workflow.with_name("assistant-workflow-kept")
    selected_workflow.rename(saved_workflow); selected_workflow.symlink_to(outside_workflow, target_is_directory=True)
    escaped_validation = subprocess.run(["bash", str(configured / "tools/evals/run-skill-evals.sh"), "--validate-fixture", "--skill", str(split_skill)], env=split_env, text=True, capture_output=True)
    require(escaped_validation.returncode != 0 and "consumer contracts escape the trusted skills owner" in escaped_validation.stderr, "Escaping split Workflow parent bypassed fixture ownership validation")
    selected_workflow.unlink(); saved_workflow.rename(selected_workflow)
    # Explicit fixture selection outside a recognized code root is only data authority.
    external = out / "external/assistant-workflow"; external_skill = install_workflow(external)
    (external / "scripts/task-packet-admission.py").write_text(evil)
    require(semantic(configured, external_skill, split_env).returncode != 0, "Arbitrary selected helper gained code authority")
    lookalike = out / "other profile/.agents/skills/assistant-workflow"; lookalike_skill = install_workflow(lookalike)
    (lookalike / "scripts/task-packet-admission.py").write_text(evil)
    require(semantic(configured, lookalike_skill, split_env).returncode != 0, "Lookalike profile gained code authority")
    require(grade(configured, lookalike_skill, split_env).returncode != 0, "Lookalike profile passed public grading")
    # Child symlink escape is rejected before import, with no stale sibling fallback.
    helper = split_skill.parent / "scripts/task-packet-admission.py"; helper.unlink(); helper.symlink_to(external / "scripts/task-packet-admission.py")
    require(semantic(configured, split_skill, split_env).returncode != 0, "Escaping helper symlink was imported")
    helper.unlink(); shutil.copy2(root / "skills/assistant-workflow/scripts/task-packet-admission.py", helper)
    selected_bytes = split_skill.read_bytes(); split_skill.unlink(); split_skill.symlink_to(external_skill)
    require(semantic(configured, split_skill, split_env).returncode != 0, "Escaping selected SKILL identity was accepted")
    split_skill.unlink(); split_skill.write_bytes(selected_bytes)
    helper.unlink()
    require(semantic(configured, split_skill, split_env).returncode != 0, "Missing selected helper fell back to stale sibling")
    shutil.copy2(root / "skills/assistant-workflow/scripts/task-packet-admission.py", helper)
    require(semantic(configured, "", split_env, fixture_file=split_skill.parent / "evals/cases.json").returncode != 0, "Unresolved selected identity gained code authority")
    # Code-root claims stay data; a correct answer still uses the selected trusted helper.
    claimed = deepcopy(fixture)
    selected_case = next(c for c in claimed["cases"] if c["id"] == case["id"])
    selected_case["semantic_context"]["packet_admission"].update(helper_path=str(external / "scripts/task-packet-admission.py"), code_root=str(external))
    claimed_fixture = out / "claimed-fixture.json"; claimed_fixture.write_text(json.dumps(claimed))
    claimed_answer = deepcopy(answer); claimed_answer.update(helper_path=str(external / "scripts/task-packet-admission.py"), code_root=str(external))
    claimed_response = out / "claimed-response.json"; claimed_response.write_text(json.dumps(claimed_answer))
    require(semantic(configured, split_skill, split_env, claimed_response, claimed_fixture).returncode == 0, "Data code claims replaced the trusted helper")
    for validator, case_id in (("unknown.validator", case["id"]), ("assistant-workflow.packet_admission_v14", "unknown-case")):
        require(semantic(configured, split_skill, split_env, validator=validator, case_id=case_id).returncode != 0, "Unknown closed dispatch was accepted")
    require(not marker.exists(), "Untrusted helper code executed")
PYLAYOUT
then pass; else fail "selected Workflow helper identity/layout controls failed"; fi

test_start "workflow executable task packet carries conditional feature-preparation bindings in its own section"
plan_template="$FRAMEWORK_DIR/skills/assistant-workflow/references/plan-template.md"
packet_section="$(awk '/^## Executable Task Packet( |$)/{capture=1; next} capture && /^## /{exit} capture{print}' "$plan_template")"
if [[ "$packet_section" == *"- feature_preparation_scope: [not_applicable | existing_system]"* ]] \
    && [[ "$packet_section" == *"- Feature preparation evidence ref: [required unchanged evidence artifact ref when feature_preparation_scope=existing_system; otherwise N/A]"* ]]; then
    pass
else
    fail "plan-template executable task packet omits conditional feature-preparation scope or evidence bindings"
fi


test_start "workflow task journal template anchors native dispatch evidence to Created identity"
missing_task_identity_terms=()
task_journal_template_surfaces=(
    "skills/assistant-workflow/references/task-journal-template.md"
)
for surface in "${task_journal_template_surfaces[@]}"; do
    file="$FRAMEWORK_DIR/$surface"
    if [[ ! -f "$file" ]]; then
        missing_task_identity_terms+=("$surface: file missing")
        continue
    fi
    if ! awk '
        BEGIN { found_task = 0; ok = 0 }
        /^## Task:/ {
            found_task = 1
            getline
            if ($0 ~ /^Created: / && NR <= 35) ok = 1
            exit
        }
        END { exit (found_task && ok) ? 0 : 1 }
    ' "$file"; then
        missing_task_identity_terms+=("$surface: Created must immediately follow ## Task near top")
    fi
    for term in \
        "Native dispatch evidence:" \
        "agent id, task name, thread, or tool result" \
        "bind it to this journal's \`Created:\` identity"; do
        if ! grep -Fq -- "$term" "$file"; then
            missing_task_identity_terms+=("$surface: $term")
        fi
    done
done
if [[ "${#missing_task_identity_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "task-journal-template.md must anchor native dispatch evidence to Created identity: ${missing_task_identity_terms[*]}"
fi


test_start "workflow subagent policy state dispatches from instruction triggers before fallback"
missing_workflow_subagent_gate=()
workflow_subagent_gate_surfaces=(
    "skills/assistant-workflow/SKILL.md"
    "skills/assistant-workflow/contracts/index.yaml"
    "skills/assistant-workflow/contracts/input.yaml"
    "skills/assistant-workflow/contracts/output.yaml"
    "skills/assistant-workflow/contracts/phase-gates.yaml"
    "skills/assistant-workflow/references/subagent-dispatch.md"
    "skills/assistant-workflow/references/task-journal-template.md"
    "skills/assistant-workflow/references/phases.md"
)
for surface in "${workflow_subagent_gate_surfaces[@]}"; do
    if [[ ! -f "$FRAMEWORK_DIR/$surface" ]]; then
        missing_workflow_subagent_gate+=("$surface: file missing")
    fi
done
workflow_subagent_gate_terms=(
    "skills/assistant-workflow/SKILL.md|references/subagent-dispatch.md"
    "skills/assistant-workflow/SKILL.md|Required delegation follows"
    "skills/assistant-workflow/SKILL.md|without a separate spawn permission question"
    "skills/assistant-workflow/SKILL.md|permitted fallback needs actual opt-out, policy, or unavailability evidence"
    "skills/assistant-workflow/references/subagent-dispatch.md|subagent_policy_state"
    "skills/assistant-workflow/references/subagent-dispatch.md|subagent_execution_mode"
    "skills/assistant-workflow/references/subagent-dispatch.md|subagent_trigger_scope"
    "skills/assistant-workflow/references/subagent-dispatch.md|subagent_policy_state=delegation_triggered"
    "skills/assistant-workflow/contracts/index.yaml|id: workflow-delegation-fields"
    "skills/assistant-workflow/contracts/index.yaml|names: [required_agents, subagent_policy_state, subagent_execution_mode, subagent_trigger_scope, policy_blocking_source]"
    "skills/assistant-workflow/contracts/input.yaml|subagent_policy_state"
    "skills/assistant-workflow/contracts/input.yaml|delegation_triggered"
    "skills/assistant-workflow/contracts/input.yaml|delegation_opted_out"
    "skills/assistant-workflow/contracts/input.yaml|subagent_execution_mode"
    "skills/assistant-workflow/contracts/input.yaml|direct_fallback"
    "skills/assistant-workflow/contracts/input.yaml|not_applicable is invalid for Build"
    "skills/assistant-workflow/contracts/input.yaml|bounded_executor requires one implementation and selected-verification owner plus independent Code Reviewer responsibility"
    "skills/assistant-workflow/contracts/input.yaml|separated_workers requires Code Writer, Builder/Tester, and independent Code Reviewer responsibilities"
    "skills/assistant-workflow/contracts/input.yaml|Reviewer may satisfy only compatibility routing"
    "skills/assistant-workflow/contracts/input.yaml|subagent_trigger_scope"
    "skills/assistant-workflow/contracts/output.yaml|subagent_policy_state"
    "skills/assistant-workflow/contracts/output.yaml|subagent_execution_mode"
    "skills/assistant-workflow/contracts/output.yaml|subagent_trigger_scope"
    "skills/assistant-workflow/contracts/output.yaml|- name: subagent_evidence"
    "skills/assistant-workflow/contracts/output.yaml|Evidence matches build_execution_lane"
    "skills/assistant-workflow/contracts/output.yaml|per_slice_dispatch_evidence"
    "skills/assistant-workflow/contracts/output.yaml|delegation_opted_out, subagents_unavailable, or policy_disallowed"
    "skills/assistant-workflow/contracts/phase-gates.yaml|D_SUBAGENT_TRIGGER"
    "skills/assistant-workflow/contracts/phase-gates.yaml|delegated dispatch without a separate permission question"
    "skills/assistant-workflow/contracts/phase-gates.yaml|direct_fallback with delegation_opted_out"
    "skills/assistant-workflow/contracts/phase-gates.yaml|B_SUBAGENT_EVIDENCE"
    "skills/assistant-workflow/contracts/phase-gates.yaml|B_SUBAGENT_SLICE_EVIDENCE"
    "skills/assistant-workflow/references/subagent-dispatch.md|Delegation Policy State"
    "skills/assistant-workflow/references/subagent-dispatch.md|direct user request or applicable \`AGENTS.md\` or active-skill instruction"
    "skills/assistant-workflow/references/subagent-dispatch.md|without a separate permission question"
    "skills/assistant-workflow/references/subagent-dispatch.md|MUST dispatch that role"
    "skills/assistant-workflow/references/subagent-dispatch.md|MUST NOT spawn subagents"
    "skills/assistant-workflow/references/subagent-dispatch.md|direct fallback evidence"
    "skills/assistant-workflow/references/subagent-roles.md|subagent-dispatch.md#delegation-policy-state"
    "skills/assistant-workflow/references/subagent-roles.md|subagent-dispatch.md#concrete-writer-selection"
    "skills/assistant-workflow/references/subagent-dispatch.md|Evidence gate for standard/strict work"
    "skills/assistant-workflow/references/task-journal-template.md|Agent Dispatch Log"
    "skills/assistant-workflow/references/task-journal-template.md|Code Mapper dispatch"
    "skills/assistant-workflow/references/task-journal-template.md|Reviewer dispatch"
    "skills/assistant-workflow/references/task-journal-template.md|not required"
    "skills/assistant-workflow/references/task-journal-template.md|Code Writer dispatch"
    "skills/assistant-workflow/references/task-journal-template.md|Builder/Tester dispatch/result/direct evidence"
    "skills/assistant-workflow/references/task-journal-template.md|Direct fallback reason"
    "skills/assistant-workflow/references/phases.md|Before any required dispatch, resolve subagent policy/execution/trigger scope through \`references/subagent-dispatch.md\`"
    "skills/assistant-workflow/references/phases.md|Map files directly when possible"
    "skills/assistant-workflow/references/phases.md|Use Code Mapper only for unresolved scope/ownership boundaries"
    "skills/assistant-workflow/references/phases.md|Add Code Reviewer to \`Required agents\` before Stage 2"
    "skills/assistant-workflow/references/phases.md|\`assistant-review\` SKILL.md and contracts"
    "skills/assistant-workflow/references/phases.md|any Reviewer compatibility routing"
    "skills/assistant-workflow/references/subagent-dispatch.md|subagent_execution_mode=delegated"
    "skills/assistant-workflow/references/build-worker-protocol.md|Direct fallback mode"
    "skills/assistant-workflow/references/build-worker-protocol.md|Silent fallback cannot complete"
)
for pair in "${workflow_subagent_gate_terms[@]}"; do
    IFS='|' read -r root_surface term <<< "$pair"
    for surface in "$root_surface"; do
        if [[ -f "$FRAMEWORK_DIR/$surface" ]] && ! p0p4_contains_text "$FRAMEWORK_DIR/$surface" "$term"; then
            missing_workflow_subagent_gate+=("$surface: $term")
        fi
    done
done
if grep -Fq -- "Add Reviewer to \`Required agents\` before Stage 2" "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"; then
    missing_workflow_subagent_gate+=("skills/assistant-workflow/references/phases.md: stale bare Reviewer Stage 2 required-agent wording")
fi
if [[ "${#missing_workflow_subagent_gate[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-workflow must resolve subagent policy state before delegated or direct fallback execution: ${missing_workflow_subagent_gate[*]}"
fi


test_start "workflow delegation fallback requires trigger evidence or policy block"
workflow_delegation_proof_failures=()
workflow_delegation_proof_terms=(
    "skills/assistant-workflow/contracts/input.yaml|policy_blocking_source"
    "skills/assistant-workflow/contracts/input.yaml|subagent_policy_state == policy_disallowed"
    "skills/assistant-workflow/contracts/input.yaml|When required_agents is non-empty"
    "skills/assistant-workflow/contracts/input.yaml|direct user, applicable AGENTS.md, or active skill instruction"
    "skills/assistant-workflow/contracts/output.yaml|policy_blocking_source"
    "skills/assistant-workflow/contracts/output.yaml|policy_disallowed"
    "skills/assistant-workflow/contracts/phase-gates.yaml|policy_blocking_source"
    "skills/assistant-workflow/contracts/phase-gates.yaml|no applicable trigger exception"
    "skills/assistant-workflow/references/subagent-dispatch.md|direct user request or applicable \`AGENTS.md\` or active-skill instruction"
    "skills/assistant-workflow/references/subagent-dispatch.md|policy_blocking_source"
    "skills/assistant-workflow/references/subagent-dispatch.md|active skill requires subagents"
    "skills/assistant-workflow/references/task-journal-template.md|Policy blocking source"
    "skills/assistant-workflow/references/plan-template.md|Policy blocking source"
    "skills/assistant-workflow/evals/cases.json|workflow-required-roles-dispatch-from-instruction-trigger"
    "skills/assistant-workflow/evals/cases.json|delegation_triggered"
    "skills/assistant-workflow/evals/cases.json|direct user, applicable AGENTS.md, or active skill instruction"
    "skills/assistant-workflow/evals/cases.json|policy_blocking_source"
)
for pair in "${workflow_delegation_proof_terms[@]}"; do
    IFS='|' read -r root_surface term <<< "$pair"
    for surface in "$root_surface"; do
        if [[ ! -f "$FRAMEWORK_DIR/$surface" ]]; then
            workflow_delegation_proof_failures+=("$surface: file missing")
        elif ! p0p4_contains_text "$FRAMEWORK_DIR/$surface" "$term"; then
            workflow_delegation_proof_failures+=("$surface: $term")
        fi
    done
done
if [[ "${#workflow_delegation_proof_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow delegation fallback must carry trigger or policy-block evidence: ${workflow_delegation_proof_failures[*]}"
fi


test_start "workflow loads the delegation trigger invariant"
workflow_trigger_invariant_failures=()
for surface_and_term in \
    "skills/assistant-workflow/contracts/index.yaml|INV_SUBAGENT_TRIGGER_STATE" \
    "skills/assistant-workflow/contracts/phase-gates.yaml|- id: INV_SUBAGENT_TRIGGER_STATE" \
    "skills/assistant-workflow/contracts/phase-gates.yaml|direct user, applicable AGENTS.md, or active skill instruction" \
    "skills/assistant-workflow/contracts/phase-gates.yaml|direct_fallback only after delegation_opted_out, subagents_unavailable after a real spawn failure or supported configuration proof, or policy_disallowed with policy_blocking_source"; do
    IFS='|' read -r root_surface term <<< "$surface_and_term"
    for surface in "$root_surface"; do
        if [[ ! -f "$FRAMEWORK_DIR/$surface" ]]; then
            workflow_trigger_invariant_failures+=("$surface: file missing")
        elif ! p0p4_contains_text "$FRAMEWORK_DIR/$surface" "$term"; then
            workflow_trigger_invariant_failures+=("$surface: $term")
        fi
    done
done
if [[ "${#workflow_trigger_invariant_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow must load a trigger-state invariant for every phase: ${workflow_trigger_invariant_failures[*]}"
fi


test_start "delegation recovery preserves evidenced fallback and dispatches only from triggers"
delegation_recovery_failures=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml::Otherwise preserve and complete the evidenced fallback state" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml::applicable trigger exists" \
    "$FRAMEWORK_DIR/skills/assistant-thinking/contracts/phase-gates.yaml::Otherwise preserve and complete the evidenced sequential fallback state" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml::Otherwise preserve and complete the evidenced direct fallback state" \
    "$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json::active workflow instruction and its covered roles" \
    "$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json::direct-user opt-out is recorded only in subagent_policy_state=delegation_opted_out"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        delegation_recovery_failures+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#delegation_recovery_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "delegation recovery can overwrite opt-out or dispatch without a trigger: ${delegation_recovery_failures[*]}"
fi


test_start "active delegation surfaces exclude retired state identifiers"
retired_delegation_identifiers=(
    "authorization""_required"
    "subagent""_authorization_scope"
    "delegation""_authorized"
    "authorization""_denied"
)
active_delegation_surfaces=(
    "$FRAMEWORK_DIR/skills/assistant-workflow"
    "$FRAMEWORK_DIR/skills/assistant-thinking"
    "$FRAMEWORK_DIR/skills/assistant-review"
    "$FRAMEWORK_DIR/install.sh"
    "$FRAMEWORK_DIR/install.ps1"
    "$FRAMEWORK_DIR/docs/troubleshooting-subagents.md"
    "$FRAMEWORK_DIR/docs/v0.3.0-research-improvements.md"
    "$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json"
    "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json"
    "$FRAMEWORK_DIR/skills/assistant-thinking/evals/cases.json"
    "$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json"
)
retired_delegation_matches=()
for identifier in "${retired_delegation_identifiers[@]}"; do
    if matches="$(rg -n -F -- "$identifier" "${active_delegation_surfaces[@]}" 2>/dev/null)"; then
        retired_delegation_matches+=("$matches")
    fi
done
if [[ "${#retired_delegation_matches[@]}" -eq 0 ]]; then
    pass
else
    fail "retired delegation identifiers remain on active surfaces: ${retired_delegation_matches[*]}"
fi


test_start "workflow Codex subagent docs do not require stale multi_agent feature flag"
missing_codex_subagent_doc_terms=()
for term in \
    "docs/v0.3.0-research-improvements.md|native subagent workflow" \
    "docs/v0.3.0-research-improvements.md|Current Codex CLI/app releases enable native subagent workflows by default" \
    "docs/v0.3.0-research-improvements.md|optional tuning knobs, not required enablers"; do
    IFS='|' read -r surface expected <<< "$term"
    if [[ ! -f "$FRAMEWORK_DIR/$surface" ]] || ! grep -Fq -- "$expected" "$FRAMEWORK_DIR/$surface"; then
        missing_codex_subagent_doc_terms+=("$surface: $expected")
    fi
done
if grep -Fq -- "features.multi_agent = true" "$FRAMEWORK_DIR/docs/v0.3.0-research-improvements.md"; then
    missing_codex_subagent_doc_terms+=("docs/v0.3.0-research-improvements.md: stale features.multi_agent = true")
fi
if [[ "${#missing_codex_subagent_doc_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "Codex subagent docs should match current native subagent behavior: ${missing_codex_subagent_doc_terms[*]}"
fi


test_start "reuse-search schema is identical across mapper, task-packet, build, and review boundaries"
reuse_search_packet_failures=()
workflow_handoffs="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml"
review_handoffs="$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml"
canonical_reuse_search_schema="$(reuse_search_schema_signature "$workflow_handoffs" "orchestrator_to_code_mapper" "return_fields" "")"
if [[ -z "$canonical_reuse_search_schema" ]]; then
    reuse_search_packet_failures+=("CodeMapper return reuse_search schema is empty")
fi
for boundary in \
    "Architect input:$workflow_handoffs:orchestrator_to_architect:context_fields:" \
    "Architect implementation_steps:$workflow_handoffs:orchestrator_to_architect:return_fields:implementation_steps" \
    "CodeWriter current_task_packet:$workflow_handoffs:orchestrator_to_code_writer:context_fields:current_task_packet" \
    "BuilderTester current_task_packet:$workflow_handoffs:orchestrator_to_builder_tester:context_fields:current_task_packet" \
    "Reviewer return:$review_handoffs:orchestrator_to_reviewer:return_fields:"; do
    IFS=':' read -r boundary_name boundary_file boundary_handoff boundary_section boundary_container <<< "$boundary"
    boundary_schema="$(reuse_search_schema_signature "$boundary_file" "$boundary_handoff" "$boundary_section" "$boundary_container")"
    if [[ "$boundary_schema" != "$canonical_reuse_search_schema" ]]; then
        reuse_search_packet_failures+=("$boundary_name reuse_search schema differs from CodeMapper return")
    fi
done
if [[ "${#reuse_search_packet_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "reuse-search schema parity failed: ${reuse_search_packet_failures[*]}"
fi


test_start "workflow reference templates reject stale sub-task branch and brief examples"
reference_template_surfaces=(
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/sub-task-brief-template.md"
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/context-handoff-templates.md"
)
stale_reference_template_file="$(mktemp "${TMPDIR:-/tmp}/workflow-reference-template-stale.XXXXXX")"
p0p4_register_cleanup "$stale_reference_template_file"
if rg -n "sub-task|Sub-Task|briefs/sub-task-[^[:space:]]*\\.md|briefs/sub-task-\\*\\.md|feature/\\[mega-task\\]/sub-task|Sub-Task Brief from the decomposition phase|Completed sub-tasks|Merge all sub-task branches|Wire components together|Shared contracts:" \
    "${reference_template_surfaces[@]}" >"$stale_reference_template_file"; then
    fail "reference templates contain stale sub-task branch/brief examples or integration wording; see $stale_reference_template_file"
else
    pass
fi


test_start "workflow pivot restart controller records decision packets and recovery refs"
missing_pivot_restart_terms=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::- name: pivot_restart_decision" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::trigger" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::affected_slice_or_round" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::options_considered" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::selected_action" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::reapproval_required" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::next_agent" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::recovery_pointer" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::exact_next_action" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::pivot_restart_decision_ref" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::pivot_restart_decision" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml::B_CODE_WRITER_BLOCKER_ROUTING" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml::R_PIVOT_RESTART_DECISION" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml::INV_PIVOT_RESTART_REAPPROVAL" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/harness-runtime-artifacts.md::## Pivot/Restart Controller" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/harness-runtime-artifacts.md::Round 10 remains terminal" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/build-worker-protocol.md::Code Writer Unexpected Blockers" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/review-qa-router.md::STAGNATION, repeated DRIFT, repeated REGRESSION, or rubric action PIVOT" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-harness-appendix.md::## Pivot/Restart Log" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-harness-appendix.md::pivot_restart_decision"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        missing_pivot_restart_terms+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#missing_pivot_restart_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow pivot/restart controller missing decision packet terms: ${missing_pivot_restart_terms[*]}"
fi


test_start "workflow CodeWriter unexpected blockers classify and route recovery"
missing_codewriter_blocker_terms=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::blocker_type" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::blocker_evidence" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::legacy_code_bug" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::broken_baseline" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::hidden_dependency" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::missing_contract" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::stale_plan" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::scope_conflict" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::tool_environment" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::tdd_red_missing" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/build-worker-protocol.md::debugging, explorer, architect, candidate_search, replan, restart" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/sub-task-brief-template.md::Unexpected blockers must be classified" \
    "$FRAMEWORK_DIR/agents/codex/code-writer.toml::Unexpected blocker protocol" \
    "$FRAMEWORK_DIR/agents/codex/code-writer.toml::Do not widen scope" \
    "$FRAMEWORK_DIR/agents/claude/code-writer.md::Unexpected blocker protocol" \
    "$FRAMEWORK_DIR/agents/claude/code-writer.md::Do not widen scope"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        missing_codewriter_blocker_terms+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#missing_codewriter_blocker_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "CodeWriter blocker classification and orchestrator routing terms missing: ${missing_codewriter_blocker_terms[*]}"
fi


test_start "assistant-review stagnation and QA pivot escalate to pivot restart decision"
missing_review_pivot_terms=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md::references/review-loop.md" \
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md::references/score-tracking.md" \
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md::references/qa-evaluation-loop.md" \
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md::and a recorded pivot/restart decision before another pass" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/score-tracking.md::pivot_restart_signal" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/qa-evaluation-loop.md::pivot_restart_signal" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/review-loop.md::orchestrator records pivot_restart_decision" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml::pivot_restart_signal" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml::- name: pivot_restart_decision" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml::ESCALATE_PIVOT_RESTART" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml::QA STAGNATION, repeated DRIFT, repeated REGRESSION, or scoped domain action pivot" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/score-tracking.md::Pivot/Restart Decision Packet" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/score-tracking.md::repeated DRIFT triggers pivot_restart_decision" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/qa-evaluation-loop.md::Pivot/Restart Escalation" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/qa-evaluation-loop.md::QA does not silently continue"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        missing_review_pivot_terms+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#missing_review_pivot_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review pivot/restart stagnation escalation terms missing: ${missing_review_pivot_terms[*]}"
fi


test_start "assistant-review removes stale loose stagnation and drift exits"
stale_pivot_restart_terms=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-review/references/score-tracking.md::May need to PIVOT or accept current state with documented limitations" \
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md::On 3+ DRIFT occurrences: stop the loop and present findings for manual review"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ -f "$file" ]] && grep -Fq -- "$term" "$file"; then
        stale_pivot_restart_terms+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#stale_pivot_restart_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "stale loose stagnation/drift exits remain: ${stale_pivot_restart_terms[*]}"
fi


test_start "workflow Build repair is bounded persistent and routes unknown or terminal failures"
repair_output="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"
repair_gates="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"
repair_protocol="$FRAMEWORK_DIR/skills/assistant-workflow/references/build-worker-protocol.md"
missing_repair_terms=()
for file_and_term in \
    "$repair_output::- name: build_repair_state" \
    "$repair_output::- name: max_attempts" \
    "$repair_output::- name: no_progress_limit" \
    "$repair_output::- name: failure_signature" \
    "$repair_output::- name: progress_evidence" \
    "$repair_output::- name: cumulative_attempt_count" \
    "$repair_output::- name: plan_version" \
    "$repair_output::- name: terminal_route"; do
    repair_file="${file_and_term%%::*}"
    repair_term="${file_and_term#*::}"
    if ! grep -Fq -- "$repair_term" "$repair_file"; then
        missing_repair_terms+=("${repair_file#$FRAMEWORK_DIR/}: $repair_term")
    fi
done
if [[ "${#missing_repair_terms[@]}" -gt 0 ]]; then
    fail "build_repair_state contract fields missing: ${missing_repair_terms[*]}"
elif ! p0p4_contains_text_ci "$repair_output" "max_attempts 3" \
    || ! p0p4_contains_text_ci "$repair_output" "no_progress_limit 2"; then
    fail "build_repair_state does not fix max_attempts=3 and no_progress_limit=2"
elif ! p0p4_contains_text_ci "$repair_gates" "matching failure_signature" \
    || ! p0p4_contains_text_ci "$repair_gates" "two consecutive" \
    || ! p0p4_contains_text_ci "$repair_gates" "stagnation"; then
    fail "Build gates do not classify two matching no-progress signatures as stagnation"
elif ! p0p4_contains_text_ci "$repair_gates" "unknown-cause" \
    || ! p0p4_contains_text_ci "$repair_gates" "assistant-debugging"; then
    fail "Build gates do not route unknown-cause failures through assistant-debugging"
elif ! p0p4_contains_text_ci "$repair_gates" "attempt 3" \
    || ! p0p4_contains_text_ci "$repair_gates" "pivot_restart_decision" \
    || ! p0p4_contains_text_ci "$repair_gates" "blocked"; then
    fail "Build gates do not terminate attempt 3 with a pivot decision or blocked result"
elif ! p0p4_contains_text_ci "$repair_protocol" "same plan version" \
    || ! p0p4_contains_text_ci "$repair_protocol" "must not reset" \
    || ! p0p4_contains_text_ci "$repair_protocol" "cumulative_attempt_count"; then
    fail "same-scope restart can reset the cumulative Build repair budget"
else
    pass
fi



test_start "writer_selection is identical across six packet projections and inline CodeWriter context"
if ruby -ryaml - "$FRAMEWORK_DIR" <<'RUBY'
root = ARGV.fetch(0)
h = YAML.load_file("#{root}/skills/assistant-workflow/contracts/handoffs.yaml")
o = YAML.load_file("#{root}/skills/assistant-workflow/contracts/output.yaml")
packets = []
h.fetch('handoffs').each do |handoff|
  %w[context_fields return_fields].each do |direction|
    Array(handoff[direction]).each do |field|
      packets << field if %w[implementation_steps current_task_packet].include?(field['name'])
    end
  end
end
packets << o.fetch('artifacts').find { |f| f['name'] == 'implementation_steps' }
raise 'six packet projections required' unless packets.length == 6
inline = h.fetch('handoffs').find { |f| f['name'] == 'orchestrator_to_code_writer' }.fetch('context_fields').find { |f| f['name'] == 'writer_selection' }
shapes = packets.map { |f| f.fetch('object_fields').find { |x| x['name'] == 'writer_selection' } } + [inline]
raise 'selection drift/missing' if shapes.any?(&:nil?) || shapes.uniq.length != 1
shape = shapes.first
raise 'legacy omission broken' unless shape['required'] == 'conditional' && shape['condition'].include?('legacy packets')
raise 'version changed' unless [h,o].all? { |d| d['schema_version'] == '14.0' }
fields = shape.fetch('object_fields').to_h { |f| [f['name'],f] }
raise 'normal identity widened' unless fields.fetch('agent')['enum_values'] == %w[intelligent-writer mechanical-writer]
eligibility = fields.fetch('mechanical_eligibility')
raise 'eligibility no longer conditional' unless eligibility['required'] == 'conditional' && eligibility['condition'] == 'agent == mechanical-writer'
expected = %w[recipe_or_example_ref resolved_decisions_ref scope_and_dependencies_ref correctness_expectations_ref]
raise 'evidence schema weakened' unless eligibility.fetch('object_fields').map { |f| f['name'] } == expected && eligibility['object_fields'].all? { |f| f['required'] == true && f['on_missing'] == 'fail' }
# Extension-only fixture interpretation: not an executable runtime router.
# Independent evidence objects substantiate the four distinct claims.
evidence = {'recipe.md'=>'approved exact transform', 'decisions.md'=>'all semantic/edge/compatibility decisions resolved', 'scope.md'=>'owned files/dependencies/current baseline', 'expectations.md'=>'independently fixed output bytes'}
valid = {'agent'=>'mechanical-writer','rationale'=>'exact approved recipe','mechanical_eligibility'=>expected.zip(evidence.keys).to_h}
accept = lambda do |packet|
  next true unless packet.key?('writer_selection') # old packets stay valid
  selection = packet['writer_selection']
  next false unless selection.is_a?(Hash) && fields['agent']['enum_values'].include?(selection['agent']) && selection['rationale'].is_a?(String) && !selection['rationale'].strip.empty?
  next true if selection['agent'] == 'intelligent-writer'
  refs = selection['mechanical_eligibility']
  refs.is_a?(Hash) && expected.all? { |k| evidence.key?(refs[k]) }
end
raise 'old packet rejected' unless accept.call({'slice_id'=>'legacy','selected_check_ids'=>['old-check'],'tdd_applies'=>false})
raise 'eligible pattern rejected' unless accept.call({'writer_selection'=>valid})
expected.each do |key|
  [nil,'','I assert resolved','missing.md'].each do |invalid|
    mutation = Marshal.load(Marshal.dump(valid)); mutation['mechanical_eligibility'][key] = invalid
    raise "invalid evidence accepted #{key}" if accept.call({'writer_selection'=>mutation})
  end
end
raise 'mechanical without evidence accepted' if accept.call({'writer_selection'=>{'agent'=>'mechanical-writer','rationale'=>'one small file'}})
raise 'legacy runtime identity allowed as normal selection' if accept.call({'writer_selection'=>{'agent'=>'code-writer','rationale'=>'legacy'}})
raise 'default intelligent rejected' unless accept.call({'writer_selection'=>{'agent'=>'intelligent-writer','rationale'=>'grader oracle judgment'}})
RUBY
then pass; else fail "writer selection projection/compatibility/evidence contract drift"; fi


test_start "workflow mega sub-task brief uses canonical task packet contract"
sub_task_template="$FRAMEWORK_DIR/skills/assistant-workflow/references/sub-task-brief-template.md"
missing_sub_task_packet_terms=()
for term in \
    "### Strict slice packet (execution contract)" \
    "- packet_id:" \
    "- observable_increment:" \
    "- deliverable_type:" \
    "- files_to_create:" \
    "- files_to_modify:" \
    "- files_to_test:" \
    "- enabling_changes_included:" \
    "- depends_on:" \
    "- worker_stage:" \
    "- build_execution_lane:" \
    "- writer_selection: [new Claude or Codex:" \
    "- red_check_id:" \
    "- red_command:" \
    "- red_cwd:" \
    "- expected_red_failure:" \
    "- tdd_cycle_log_ref:" \
    "- acceptance_criteria:" \
    "- selected_check_procedure: [for each CheckSpec, exact argv and cwd if command-based; otherwise concrete procedure and observable result; do not invent a command]" \
    "- expected_success_signal:" \
    "- evidence_to_record:" \
    "- deviation_rollback_rule:" \
    "DEVIATED" \
    "Source-changing packets in a shared or unknown workspace run sequentially"; do
    if ! grep -Fq -- "$term" "$sub_task_template"; then
        missing_sub_task_packet_terms+=("$term")
    fi
done
strict_slice_packet="$(awk '/^### Strict slice packet \(execution contract\)$/{capture=1; next} capture && /^### Supporting context/{exit} capture{print}' "$sub_task_template")"
if [[ "$strict_slice_packet" != *"- feature_preparation_scope:"* ]] \
    || [[ "$strict_slice_packet" != *"- feature_preparation_evidence_ref:"* ]] \
    || [[ "$strict_slice_packet" != *"- feature_preparation_harness_obligation:"* ]]; then
    missing_sub_task_packet_terms+=("canonical task packet missing feature-preparation scope, evidence ref, or harness obligation")
fi
if rg -n "^### (Goal|Scope)$" "$sub_task_template" >/dev/null; then
    missing_sub_task_packet_terms+=("loose Goal/Scope execution sections must be absent")
fi
if [[ "${#missing_sub_task_packet_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "sub-task-brief-template.md missing canonical task packet contract terms: ${missing_sub_task_packet_terms[*]}"
fi

# Gap: old bounded-repair source checks did not distinguish invalid expectations
# from regressions or challenge a check/worker/session switch with spent limits.
source "$FRAMEWORK_DIR/tests/p0-p4/lib/ci-audit-response-fixtures.sh"
test_start "expectation classification and switching failures preserve spent repair limits"
s1_repair_root="$(mktemp -d)"
p0p4_register_cleanup "$s1_repair_root"
mkdir -p "$s1_repair_root/responses/assistant-workflow"
s1_repair_response="$s1_repair_root/responses/assistant-workflow/repair-expectations-switch-and-resume.txt"
write_s1_response repair-expectations-switch-and-resume "$s1_repair_root/baseline.json"
s1_repair_failures=()
for s1_repair_variant in valid reset-on-switch production-for-brittle misclassified-regression retry-after-terminal; do
    case "$s1_repair_variant" in
        valid) cp "$s1_repair_root/baseline.json" "$s1_repair_response" ;;
        reset-on-switch) jq '.build_repair_state.cumulative_attempt_count = 1 | .build_repair_state.no_progress_count = 0' "$s1_repair_root/baseline.json" >"$s1_repair_response" ;;
        production-for-brittle) jq '.changed_files = ["filter.py"]' "$s1_repair_root/baseline.json" >"$s1_repair_response" ;;
        misclassified-regression) jq '.build_repair_state.failure_signatures[1] = "deny-nonowner:obsolete expectation"' "$s1_repair_root/baseline.json" >"$s1_repair_response" ;;
        retry-after-terminal) jq '.build_repair_state.status = "repairing"' "$s1_repair_root/baseline.json" >"$s1_repair_response" ;;
    esac
    if "$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$s1_repair_root/responses" --skill assistant-workflow --case repair-expectations-switch-and-resume >"$s1_repair_root/$s1_repair_variant.out" 2>&1; then
        [[ "$s1_repair_variant" == valid ]] || s1_repair_failures+=("$s1_repair_variant accepted")
    else
        [[ "$s1_repair_variant" != valid ]] && grep -Eq 'structured_json_assertion_failures=[1-9]' "$s1_repair_root/$s1_repair_variant.out" || s1_repair_failures+=("$s1_repair_variant failed without oracle rejection")
    fi
done
if [[ ${#s1_repair_failures[@]} -eq 0 ]]; then pass; else fail "repair controls: ${s1_repair_failures[*]}"; fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
