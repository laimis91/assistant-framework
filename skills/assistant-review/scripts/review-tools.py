#!/usr/bin/env python3
"""Bounded, deterministic review validation. Caller authority stays with the caller."""
import sys
sys.dont_write_bytecode = True
import hashlib
import importlib.util
import json
import math
import re
from decimal import Decimal, ROUND_HALF_UP
from functools import lru_cache
from pathlib import Path

MAX_BYTES = 8 * 1024 * 1024
BINDING_KEYS = 'task_id native_invocation_id batch_id review_snapshot_id review_pass_id review_attempt_id producer_id producer_version source_digest'.split()
TUPLE_KEYS = 'review_pass_id scope_item_id applicable_concern review_perspective coverage_obligation'.split()
LIGHT_PERSPECTIVE = 'light_contract_and_runtime'
PLAN_PERSPECTIVE = 'plan_coverage_and_feasibility'
SINGLE_PASS_PERSPECTIVES = (LIGHT_PERSPECTIVE, PLAN_PERSPECTIVE)
OPERATIONS = ('identify_return', 'validate_return', 'validate_terminal_barrier', 'validate_aggregate_accounting')

class Invalid(ValueError):
    pass

def require_fact(condition, code):
    if not condition:
        raise Invalid(code)

def nonblank(value):
    return type(value) is str and bool(value.strip())

def encoded(value):
    return json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(',', ':')).encode('utf-8')

def digest(raw):
    return hashlib.sha256(raw.encode('utf-8') if type(raw) is str else raw).hexdigest()

def receipt(value):
    raw = encoded(value)
    return {'sha256': digest(raw), 'bytes': len(raw)}

def object(value):
    require_fact(type(value) is dict, 'object_required')
    return value

def structural(value):
    if type(value) is dict:
        return ('object', frozenset((key, structural(item)) for key, item in value.items()))
    if type(value) is list:
        return ('array', tuple(structural(item) for item in value))
    return (type(value).__name__, value)

def equal(left, right):
    return structural(left) == structural(right)

def distinct(values):
    result = []
    seen = set()
    for value in values:
        key = structural(value)
        if key not in seen:
            seen.add(key)
            result.append(value)
    return result

def unique(values, code):
    require_fact(len(distinct(values)) == len(values), code)

def same_set(actual, expected, code):
    unique(actual, code)
    unique(expected, 'authority_duplicate')
    require_fact({structural(x) for x in actual} == {structural(x) for x in expected}, code)

def tuple_key(entry, pass_id=None):
    return [pass_id if key == 'review_pass_id' and pass_id is not None else entry.get(key) for key in TUPLE_KEYS]

def strict_object(pairs):
    result = {}
    for key, value in pairs:
        require_fact(key not in result, 'duplicate_json_key')
        result[key] = value
    return result

def finite_float(text):
    value = float(text)
    require_fact(math.isfinite(value), 'primitive_json_required')
    return value

def parse_json(raw):
    if type(raw) is bytes:
        raw = raw.decode('utf-8', errors='strict')
    return json.loads(raw, object_pairs_hook=strict_object, parse_float=finite_float,
                      parse_constant=lambda _: (_ for _ in ()).throw(Invalid('primitive_json_required')))

def primitive_copy(value, depth=0, count=None):
    count = [0, 0] if count is None else count
    count[0] += 1
    require_fact(depth <= 64 and count[0] <= 100000, 'input_bounds_exceeded')
    kind = type(value)
    if kind is dict:
        require_fact(all(type(key) is str for key in value), 'primitive_json_required')
        return {primitive_copy(key, depth + 1, count): primitive_copy(item, depth + 1, count) for key, item in value.items()}
    if kind is list:
        return [primitive_copy(item, depth + 1, count) for item in value]
    if kind is str:
        count[1] += len(value.encode('utf-8', errors='strict'))
        require_fact(count[1] <= MAX_BYTES, 'input_too_large')
        return value
    if kind in (int, bool, type(None)):
        return value
    if kind is float:
        require_fact(math.isfinite(value), 'primitive_json_required')
        return value
    raise Invalid('primitive_json_required')

@lru_cache(maxsize=1)
def private_yaml():
    """Load only the pinned skill-owned pure parser; never search ambient yaml."""
    root = Path(__file__).resolve().parent / '_vendor' / 'pyyaml'
    try:
        manifest = parse_json((root / 'UPSTREAM.json').read_bytes())
        names = '__init__ composer constructor dumper emitter error events loader nodes parser reader representer resolver scanner serializer tokens'.split()
        expected = {'yaml/' + name + '.py' for name in names} | {'LICENSE'}
        package = root / 'yaml'
        require_fact({path.name for path in root.iterdir()} == {'yaml', 'LICENSE', 'UPSTREAM.json'} and {path.name for path in package.iterdir()} == {name + '.py' for name in names}, 'bundled_parser_unavailable')
        require_fact(manifest['version'] == '6.0.3' and manifest['source_sha256'] == 'd76623373421df22fb4cf8817020cbb7ef15c725b9d5e45f17e189bfc384190f', 'bundled_parser_unavailable')
        require_fact({row['path'] for row in manifest['files']} == expected and len(manifest['files']) == len(expected), 'bundled_parser_unavailable')
        for row in manifest['files']:
            path = root / row['path']
            require_fact(path.resolve() == path and not path.is_symlink(), 'bundled_parser_unavailable')
            raw = path.read_bytes()
            require_fact(len(raw) == row['bytes'] and digest(raw) == row['sha256'], 'bundled_parser_unavailable')
        identity = '_assistant_review_private_yaml'
        package = root / 'yaml'
        spec = importlib.util.spec_from_file_location(identity, str(package / '__init__.py'), submodule_search_locations=[str(package)])
        module = importlib.util.module_from_spec(spec)
        sys.modules[identity] = module
        spec.loader.exec_module(module)
        require_fact(module.__version__ == '6.0.3' and not module.__with_libyaml__, 'bundled_parser_unavailable')
        for name, loaded in list(sys.modules.items()):
            if name == identity or name.startswith(identity + '.'):
                require_fact(Path(loaded.__file__).resolve().parent == package, 'bundled_parser_unavailable')
        return module
    except Invalid:
        raise
    except (OSError, ValueError, KeyError, TypeError, ImportError, AttributeError):
        raise Invalid('bundled_parser_unavailable') from None

def passive_yaml(raw):
    yaml = private_yaml()
    class RestrictedLoader(yaml.SafeLoader):
        def compose_node(self, parent, index):
            if self.check_event(yaml.AliasEvent):
                raise Invalid('passive_yaml_required')
            node = super().compose_node(parent, index)
            allowed = {'tag:yaml.org,2002:' + name for name in ('null', 'bool', 'int', 'float', 'str', 'seq', 'map')}
            require_fact(node.tag in allowed, 'passive_yaml_required')
            return node
    require_fact(type(raw) in (str, bytes) and len(raw.encode('utf-8') if type(raw) is str else raw) <= MAX_BYTES, 'input_too_large')
    try:
        return primitive_copy(yaml.load(raw, Loader=RestrictedLoader))
    except yaml.YAMLError:
        raise Invalid('passive_yaml_required') from None

@lru_cache(maxsize=3)
def load_contract(name):
    require_fact(name in ('handoffs', 'output', 'input'), 'contract_name_invalid')
    try:
        return passive_yaml((Path(__file__).resolve().parent.parent / 'contracts' / (name + '.yaml')).read_bytes())
    except OSError:
        raise Invalid('runtime_or_contract_unavailable') from None

def condition(text, context):
    # "A, or (B and C)" spells out the precedence the ' or ' split applies.
    text = text.rstrip(',')
    if text.startswith('(') and text.endswith(')'):
        text = text[1:-1]
    if ' or ' in text and not text.startswith('the shared'):
        return any(condition(part, context) for part in text.split(' or '))
    if ' and ' in text:
        return all(condition(part, context) for part in text.split(' and '))
    match = re.fullmatch(r'(\w+) == (\w+)', text)
    if match:
        return context.get(match[1]) == match[2]
    match = re.fullmatch(r'(\w+) >= (\d+)', text)
    if match:
        return type(context.get(match[1])) is int and context[match[1]] >= int(match[2])
    match = re.fullmatch(r'(\w+) is (false|true|non-empty|empty)', text)
    if match:
        value = context.get(match[1]); rule = match[2]
        return value is False if rule == 'false' else value is True if rule == 'true' else type(value) is list and (bool(value) if rule == 'non-empty' else not value)
    match = re.fullmatch(r'(\w+) in \[([^\]]+)\]', text)
    if match:
        return context.get(match[1]) in match[2].split(', ')
    if text == 'terminal barrier':
        return context.get('terminal_barrier') is True
    if text == 'the shared task guard reports genuine semantic stagnation or a material change needs a decision':
        return context.get('pivot_restart_required') is True
    raise Invalid('unsupported_contract_condition')

def shape_valid(value, field, context=None):
    kind = field['type']
    valid = (nonblank(value) if kind in ('string', 'file', 'jsonl_line') else
             type(value) is int if kind == 'int' else
             type(value) in (int, float) and math.isfinite(value) if kind == 'float' else
             type(value) is bool if kind == 'boolean' else
             type(value) is str and value in field['enum_values'] if kind == 'enum' else
             type(value) is list and all(nonblank(x) for x in value) if kind == 'string[]' else
             type(value) is dict if kind == 'object' else
             type(value) is list and all(type(x) is dict for x in value) if kind == 'object[]' else False)
    if not valid:
        return False
    if 'min_items' in field and len(value) < field['min_items'] or 'max_items' in field and len(value) > field['max_items']:
        return False
    children = field.get('object_fields')
    if children is None:
        return True
    def check(item):
        if set(item) - {child['name'] for child in children}:
            return False
        local = None if context is None else dict(context, **item)
        for child in children:
            name = child['name']
            required = child.get('required') is True or (context is not None and child.get('required') == 'conditional' and condition(child['condition'], local))
            if required and name not in item or name in item and not shape_valid(item[name], child, local):
                return False
        return True
    return check(value) if kind == 'object' else all(check(item) for item in value)

def binding(value):
    object(value)
    require_fact(set(value) == set(BINDING_KEYS) and all(nonblank(value[key]) for key in BINDING_KEYS), 'binding_invalid')
    return [value[key] for key in BINDING_KEYS]

def payload(value):
    require_fact(type(value) is str, 'complete_utf8_payload_required')
    try:
        require_fact(len(value.encode('utf-8', errors='strict')) <= MAX_BYTES, 'complete_utf8_payload_required')
    except UnicodeError:
        raise Invalid('complete_utf8_payload_required') from None
    return value

def identify_return(authority, candidate):
    current = binding(authority['dispatch_binding'])
    require_fact(authority.get('history_known') is True, 'history_unknown')
    require_fact(candidate.get('complete') is True, 'complete_utf8_payload_required')
    raw = payload(candidate['payload']); candidate_binding = binding(candidate['binding']); event_id = candidate['event_id']
    require_fact(nonblank(event_id) and nonblank(candidate.get('payload_ref')), 'occurrence_binding_required')
    hash_value = digest(raw); records = authority['records']; archives = authority['archives']
    require_fact(type(records) is list and type(archives) is dict, 'history_unknown')
    seen_events = {}; retained = []
    for record in records:
        key = binding(record['binding']); archived = archives.get(record['payload_ref'])
        require_fact(type(archived) is str, 'payload_archive_missing')
        require_fact(digest(payload(archived)) == record['payload_sha256'], 'payload_archive_changed')
        occurrences = record['event_ids']
        require_fact(type(occurrences) is list and bool(occurrences) and all(nonblank(x) for x in occurrences), 'occurrence_binding_required')
        for occurrence in occurrences:
            require_fact(occurrence not in seen_events, 'retained_event_collision')
            seen_events[occurrence] = [key, record['payload_sha256']]
        retained.append((key, record))
    if event_id in seen_events:
        require_fact(seen_events[event_id] == [candidate_binding, hash_value], 'event_payload_conflict')
        classification = 'exact_replay'
    else:
        require_fact(candidate_binding == current, 'stale_or_foreign_binding')
        previous = [record for key, record in retained if key == candidate_binding]
        require_fact(not any(record['payload_sha256'] != hash_value for record in previous), 'changed_payload_conflict')
        classification = 'duplicate' if previous else 'new_evidence'
    require_fact(candidate_binding == current, 'stale_or_foreign_binding')
    canonical = next((record for key, record in retained if key == candidate_binding and record['payload_sha256'] == hash_value), candidate)
    return {'classification': classification, 'payload_sha256': hash_value, 'payload_bytes': len(raw.encode('utf-8')), 'payload_ref': candidate['payload_ref'], 'event_id': event_id, 'binding': candidate['binding'], 'canonical_payload_ref': canonical['payload_ref'], 'closes_coverage': False, 'advances_progress': False}

def return_context(authority, handoff):
    context = object(authority['context']).copy(); fields = handoff['context_fields']
    scope = next(field for field in fields if field['name'] == 'scope_size')
    require_fact(shape_valid(context.get('scope_size'), scope), 'context_scope_invalid')
    for field in fields:
        if field['type'] != 'boolean':
            continue
        name = field['name']
        if name not in context:
            if type(field.get('default')) is bool:
                context[name] = field['default']
            elif name == 'rubric_required':
                context[name] = context['scope_size'] in ('medium', 'large')
            else:
                raise Invalid('context_applicability_unknown')
        require_fact(type(context[name]) is bool, 'context_applicability_invalid')
    require_fact(context['scope_size'] not in ('medium', 'large') or context['rubric_required'], 'context_rubric_exemption_invalid')
    return context

def validate_rubric(scores, authority):
    weights = {'correctness': '0.30', 'code_quality': '0.20', 'architecture': '0.20', 'security': '0.15', 'test_coverage': '0.15'}
    total = Decimal(0)
    for key, weight in weights.items():
        value = Decimal(str(scores[key]))
        require_fact(1 <= value <= 5 and value * 2 == (value * 2).to_integral_value(), 'rubric_dimension_invalid')
        total += value * Decimal(weight)
    overridden = 'critical_override' in scores
    require_fact(overridden == ('critical_override_cap' in authority), 'rubric_override_authority_mismatch')
    if overridden:
        cap = authority['critical_override_cap']
        require_fact(type(cap) in (int, float) and cap in (1, 2, 2.5), 'rubric_override_cap_invalid')
        total = min(total, Decimal(str(cap)))
    require_fact(Decimal(str(scores['weighted_score'])) == total.quantize(Decimal('.01'), rounding=ROUND_HALF_UP), 'rubric_arithmetic_invalid')
    require_fact(scores['action'] == ('PASS' if total >= 4 else 'REFINE' if total >= 3 else 'PIVOT'), 'rubric_action_invalid')

class FreshReviewDispatchAuthority:
    """Convert retained native dispatch facts; payloads and receipts cannot supply them."""
    @classmethod
    def validate(cls, authority, context):
        version = authority.get('producer_version')
        require_fact(version in ('9.0', '10.0'), 'review_version_unsupported')
        if version == '9.0':
            original = authority.get('historical_dispatch_binding')
            require_fact(type(original) is dict, 'historical_review_authority_missing')
            binding(original)
            require_fact(original['producer_version'] in ('9.0', 'v9')
                         and all(original[key] == context[key] for key in
                                 ('batch_id', 'review_snapshot_id', 'review_pass_id', 'review_attempt_id'))
                         and original['source_digest'] == context['snapshot_identity']['value'],
                         'historical_review_authority_missing')
            return None

        fact = authority.get('fresh_dispatch')
        # Shape (keys, nonblank strings, non-empty authors, the context_isolation
        # and review_subject enums) comes from the fresh_dispatch declaration in
        # contracts/input.yaml; no second schema.
        declared = next(x for x in load_contract('input')['fields'] if x['name'] == 'fresh_dispatch')
        # runtime must equal its stripped lowercase form, so padded or cased
        # spellings of codex are rejected; the Codex rule compares
        # runtime.strip().lower() == 'codex'. An inherited Codex context keeps
        # its specific diagnostic before the fork_turns enum.
        require_fact(type(fact) is not dict or fact.get('runtime') != 'codex' or fact.get('fork_turns', 'none') == 'none', 'review_context_inherited')
        require_fact(type(fact) is dict and shape_valid(fact, declared, {})
                     and fact['runtime'] == fact['runtime'].strip().lower()
                     and ('fork_turns' in fact) == (fact['runtime'].strip().lower() == 'codex'), 'fresh_review_authority_invalid')
        for key in ('author_actor_ids', 'prior_reviewer_actor_ids'):
            unique(fact[key], 'fresh_review_authority_invalid')
        require_fact(fact['actor_id'] not in [fact['root_actor_id']] + fact['author_actor_ids'] + fact['prior_reviewer_actor_ids'],
                     'review_actor_not_fresh')
        require_fact(context.get('reviewer_actor_id') == fact['actor_id']
                     and context.get('native_invocation_id') == fact['native_invocation_id']
                     and context.get('handoff_digest') == fact['handoff_digest']
                     and context['snapshot_identity']['value'] == fact['source_digest']
                     and context.get('review_subject') == fact['review_subject'], 'fresh_review_binding_mismatch')
        return fact


def validate_return(authority, reply):
    return validated_return(authority, reply, FreshReviewDispatchAuthority.validate(authority, object(authority['context'])))

def validated_return(authority, reply, fact):
    """Validate a return against the fresh fact the caller already validated (None for v9)."""
    require_fact((fact is None) == (authority.get('producer_version') == '9.0'), 'fresh_review_authority_invalid')
    handoff = next(entry for entry in load_contract('handoffs')['handoffs'] if entry['name'] == 'orchestrator_to_reviewer')
    context = return_context(authority, handoff)
    require_fact(shape_valid(reply, {'type': 'object', 'object_fields': handoff['return_fields']}, context), 'return_schema_invalid')
    for key in 'round batch_id review_snapshot_id snapshot_identity review_pass_id review_attempt_id review_perspective'.split():
        require_fact(key in context and equal(reply[key], context[key]), 'dispatch_identity_mismatch')
    require_fact(reply['round'] > 0, 'round_invalid')
    required = authority['required_coverage_tuples']
    require_fact(type(required) is list and bool(required) and all(row['review_pass_id'] == context['review_pass_id'] for row in required), 'authority_coverage_invalid')
    same_set([tuple_key(row, reply['review_pass_id']) for row in reply['coverage_entries']], [tuple_key(row) for row in required], 'coverage_tuple_mismatch')
    findings = reply['findings']; ids = [finding['finding_id'] for finding in findings]
    unique(ids, 'duplicate_finding_id')
    prefixes = ('review_pass:' + reply['review_pass_id'] + ':', reply['review_pass_id'] + ':')
    require_fact(all(finding['finding_id'].startswith(prefixes) and 0 <= finding['confidence_pct'] <= 100 and ('line' not in finding or finding['line'] > 0) for finding in findings), 'finding_provenance_invalid')
    for entry in reply['coverage_entries']:
        if entry['status'] == 'finding':
            require_fact(all(item in ids for item in entry['finding_ids']), 'coverage_finding_unbound')
            unique(entry['finding_ids'], 'coverage_finding_duplicate')
        else:
            require_fact('finding_ids' not in entry, 'coverage_finding_unbound')
    same_set(distinct([item for row in reply['coverage_entries'] for item in row.get('finding_ids', [])]), ids, 'finding_coverage_missing')
    states = {'DONE': ['completed', 'clean'], 'NEEDS_CONTEXT': ['needs_context', 'not_assessed'], 'BLOCKED': ['blocked', 'not_assessed']}
    if reply['status'] == 'DONE_WITH_CONCERNS':
        verdict = 'has_must_fix' if any(x['severity'] == 'must-fix' for x in findings) else 'has_should_fix' if any(x['severity'] == 'should-fix' for x in findings) else 'has_nits_only'
        require_fact(bool(findings) and reply['pass_completion_state'] == 'completed' and reply['verdict'] == verdict, 'status_truth_table')
    else:
        require_fact([reply['pass_completion_state'], reply['verdict']] == states.get(reply['status']) and not findings, 'status_truth_table')
    completed = reply['pass_completion_state'] == 'completed'
    require_fact(all(entry['status'] in ('inspected_no_risk', 'finding') if completed else entry['status'] == 'blocked' for entry in reply['coverage_entries']), 'coverage_state_invalid')
    require_fact('open_questions' not in reply if completed else bool(reply['open_questions']), 'questions_truth_table')
    if closure_context(context):
        fixed_ids = [x['aggregate_finding_id'] for x in context['previously_fixed']]
        same_set([x['aggregate_finding_id'] for x in reply['closure_results']], fixed_ids, 'closure_identity_mismatch')
        require_fact(all((row['status'] == 'verified_closed' or bool(findings)) if completed else row['status'] == 'incomplete' for row in reply['closure_results']), 'closure_finding_missing')
    require_fact(not context['rubric_required'] or 'rubric_scores' in reply, 'rubric_missing')
    if 'rubric_scores' in reply:
        validate_rubric(reply['rubric_scores'], authority)
    return {'pass_completion_state': reply['pass_completion_state'], 'finding_count': len(findings)}

def closure_context(context):
    """Closure is a separate pass, or the single light or plan re-review after a fix."""
    return context['review_perspective'] == 'closure_verification' or (context['review_perspective'] in SINGLE_PASS_PERSPECTIVES and bool(context.get('previously_fixed')))

def validate_plan(plan, controller_intensity=None, review_subject=None):
    fields = next(x for x in load_contract('output')['artifacts'] if x['name'] == 'final_summary')['object_fields']
    schema = next(x for x in fields if x['name'] == 'final_batch_plan')
    require_fact(shape_valid(plan, schema), 'plan_schema_invalid')
    topology = plan['topology']; topology_fields = next(x for x in schema['object_fields'] if x['name'] == 'topology')['object_fields']
    declared = {x['name']: x['enum_values'] for x in next(x for x in topology_fields if x['name'] == 'canonical_discovery_perspectives')['object_fields']}
    require_fact(equal(topology['canonical_discovery_perspectives'], declared), 'topology_canonical_mismatch')
    size = 'trivial_small' if plan['scope_size'] in ('trivial', 'small') else plan['scope_size']; discoveries = declared[size]
    # Light trivial/small review is one fresh pass covering both trivial_small
    # concerns, and its post-fix re-review folds closure into that one pass.
    # Historical two-pass trivial/small batches remain valid and readable.
    # Plan review (review_subject plan, topology.plan_review true) is one fresh
    # plan_coverage_and_feasibility pass at any scope size; its post-fix re-review
    # folds closure into one new pass. Historical multi-pass plan reviews stay
    # readable; new plan reviews use exactly one pass.
    plan_review = topology.get('plan_review') is True
    require_fact(plan_review or PLAN_PERSPECTIVE not in [x['perspective'] for x in plan['expected_passes']], 'topology_plan_review_missing')
    require_fact(not plan_review or review_subject == 'plan', 'topology_plan_review_invalid')
    light = not plan_review and size == 'trivial_small' and topology['discovery_pass_count'] == 1
    if plan_review:
        discoveries = [PLAN_PERSPECTIVE]
        require_fact(not topology['closure_verification_required'], 'topology_plan_closure_invalid')
    if light:
        discoveries = [LIGHT_PERSPECTIVE]
        require_fact(not topology['closure_verification_required'], 'topology_light_closure_invalid')
    expected = discoveries + (['risk_selected_specialist'] if topology['security_specialist_triggered'] else []) + (['closure_verification'] if topology['closure_verification_required'] else [])
    same_set([x['perspective'] for x in plan['expected_passes']], expected, 'topology_pass_mismatch')
    require_fact(topology['discovery_pass_count'] == len(discoveries) and topology['max_required_responses'] == len(expected), 'topology_count_mismatch')
    # The one-pass light topology needs the explicit light_review indicator and the
    # caller's light controller_intensity; absent/false keeps the canonical >=2 passes.
    intensity = next(x for x in load_contract('input')['fields'] if x['name'] == 'controller_intensity')
    require_fact(controller_intensity is None or shape_valid(controller_intensity, intensity), 'controller_intensity_invalid')
    flagged = topology.get('light_review') is True
    require_fact(flagged or not light, 'topology_light_review_missing')
    require_fact(light or not flagged, 'topology_light_review_invalid')
    require_fact(not flagged or controller_intensity == 'light', 'topology_light_intensity_mismatch')
    unique([x['review_pass_id'] for x in plan['expected_passes']], 'plan_pass_duplicate')
    for item in plan['expected_passes']:
        visibility = ('closure_ledger',) if item['perspective'] == 'closure_verification' else ('none', 'closure_ledger') if item['perspective'] in SINGLE_PASS_PERSPECTIVES else ('none',)
        require_fact(item['prior_finding_visibility'] in visibility, 'plan_visibility_mismatch')
        unique(item['assigned_scope'], 'assignment_duplicate'); unique(item['coverage_obligations'], 'obligation_duplicate')
    unique([tuple_key(row) for row in plan['required_coverage_tuples']], 'plan_tuple_duplicate')
    for row in plan['required_coverage_tuples']:
        item = next((x for x in plan['expected_passes'] if x['review_pass_id'] == row['review_pass_id']), None)
        require_fact(item is not None and row['scope_item_id'] in item['assigned_scope'] and item['perspective'] == row['review_perspective'] and row['coverage_obligation'] in item['coverage_obligations'], 'plan_tuple_assignment_mismatch')

def validate_native_review_binding(authority, native, fact):
    """Bind native identity to authority whose fact FreshReviewDispatchAuthority already validated."""
    if authority['producer_version'] == '9.0':
        require_fact(fact is None and equal(authority.get('historical_dispatch_binding'), native), 'historical_review_authority_missing')
    else:
        require_fact(fact is not None and native['producer_version'] in ('10.0', 'v10')
                     and native['native_invocation_id'] == fact['native_invocation_id']
                     and native['source_digest'] == fact['source_digest'], 'fresh_review_native_mismatch')


def validate_terminal_barrier(authority, candidate):
    return terminal_barrier(authority, candidate)[0]

def terminal_barrier(authority, candidate):
    """Return the public barrier result plus active facts, each validated once in this barrier."""
    plan = object(authority['plan']); validate_plan(plan, authority.get('controller_intensity'), authority.get('review_subject'))
    version = authority.get('producer_version')
    require_fact(version in ('9.0', '10.0'), 'review_version_unsupported')
    facts = {}
    # Every return authority carries the top-level label; a 9.0 top-level label
    # cannot hide any current 10.0 return from the v10 checks below.
    for return_authority in authority['return_authorities'].values():
        require_fact(return_authority.get('producer_version') == version, 'review_version_relabelled')
    if version == '10.0':
        require_fact(authority.get('review_subject') in ('plan', 'implementation', 'closure', 'acceptance'), 'review_subject_invalid')
        for pass_id, return_authority in authority['return_authorities'].items():
            # Frozen context/tuples exist before native creation. No-response typed
            # failures carry no invented actor; response-backed paths below still
            # require and bind real fresh dispatch authority.
            if 'fresh_dispatch' not in return_authority:
                continue
            fact = FreshReviewDispatchAuthority.validate(return_authority, return_authority['context'])
            require_fact(fact['review_subject'] == authority['review_subject'], 'review_subject_mismatch')
            facts[pass_id] = fact
        unique([fact['actor_id'] for fact in facts.values()], 'review_actor_reused')
        unique_root(facts.values())
    handoff = next(x for x in load_contract('handoffs')['handoffs'] if x['name'] == 'orchestrator_to_reviewer')
    batch_schema = next(x for x in handoff['context_fields'] if x['name'] == 'review_batch')
    ledger_schema = next(x for x in batch_schema['object_fields'] if x['name'] == 'pass_attempt_ledger')
    require_fact(shape_valid(candidate['pass_attempt_ledger'], ledger_schema, {'terminal_barrier': True}), 'terminal_ledger_schema_invalid')
    require_fact(not authority['unresolved_conflicts'], 'unresolved_response_conflicts')
    require_fact(authority.get('source_current') is True and authority.get('producer_current') is True, 'source_or_producer_changed')
    passes = plan['expected_passes']; require_fact(1 <= len(passes) <= 6, 'pass_count_invalid')
    pass_ids = [x['review_pass_id'] for x in passes]
    same_set([x['review_pass_id'] for x in candidate['pass_attempt_ledger']], pass_ids, 'terminal_pass_mismatch')
    for key, code in (('active_attempts', 'active_authority_pass_mismatch'), ('return_authorities', 'return_authority_pass_mismatch'), ('canonical_response_events', 'canonical_authority_pass_mismatch')):
        same_set(list(authority[key]), pass_ids, code)
    for item in passes:
        pass_id = item['review_pass_id']; context = authority['return_authorities'][pass_id]['context']
        require_fact(context['batch_id'] == plan['batch_id'] and context['review_snapshot_id'] == plan['review_snapshot_id'] and context['review_pass_id'] == pass_id and context['review_perspective'] == item['perspective'] and equal(context['assigned_scope'], item['assigned_scope']) and context['review_attempt_id'] == authority['active_attempts'][pass_id] and equal(context['snapshot_identity'], authority['snapshot_identity']), 'plan_context_mismatch')
        same_set(authority['return_authorities'][pass_id]['required_coverage_tuples'], [row for row in plan['required_coverage_tuples'] if row['review_pass_id'] == pass_id], 'plan_context_coverage_mismatch')
        if item['perspective'] in SINGLE_PASS_PERSPECTIVES:
            require_fact(item['prior_finding_visibility'] == ('closure_ledger' if context.get('previously_fixed') else 'none'), 'plan_visibility_mismatch')
    responses = authority['responses']; seen_events = []; pass_states = {}
    for ledger in candidate['pass_attempt_ledger']:
        pass_id = ledger['review_pass_id']; attempts = ledger['attempts']
        require_fact(bool(attempts) and [x['attempt_count'] for x in attempts] == list(range(1, len(attempts) + 1)), 'attempt_order_invalid')
        unique([x['review_attempt_id'] for x in attempts], 'attempt_identity_duplicate')
        active = authority['active_attempts'][pass_id]
        require_fact(ledger['active_terminal_attempt_id'] == active and attempts[-1]['review_attempt_id'] == active, 'active_attempt_mismatch')
        for attempt in attempts:
            events = attempt['response_events']
            for event in events:
                require_fact(event['dispatch_attempt_id'] == attempt['review_attempt_id'] and event['disposition'] in ('active_terminal', 'stale', 'duplicate'), 'event_binding_invalid')
                event_id = event['response_event_id']; require_fact(event_id in responses, 'response_history_missing')
                retained = responses[event_id]; native = retained['identity_authority']['dispatch_binding']; context = authority['return_authorities'][pass_id]['context']
                require_fact(retained['delivery']['event_id'] == event_id and native['review_attempt_id'] == attempt['review_attempt_id'] and all(native[key] == context[key] for key in ('batch_id', 'review_snapshot_id', 'review_pass_id')) and native['source_digest'] == context['snapshot_identity']['value'], 'event_binding_invalid')
                identify_return(retained['identity_authority'], retained['delivery']); seen_events.append(event_id)
            terminals = [event for event in events if event['disposition'] == 'active_terminal']
            if attempt['review_attempt_id'] != active:
                require_fact(not terminals, 'inactive_attempt_terminal'); continue
            require_fact(attempt['record_state'] == 'terminal' and attempt['repair_disposition'] in ('not_needed', 'repaired', 'exhausted'), 'terminal_record_invalid')
            state = attempt['terminal_state']
            if state in ('completed', 'needs_context', 'blocked'):
                require_fact(len(terminals) == 1, 'active_response_count_invalid')
                event_id = terminals[0]['response_event_id']; retained = responses[event_id]; native = retained['identity_authority']['dispatch_binding']; context = authority['return_authorities'][pass_id]['context']
                require_fact(all(native[key] == context[key] for key in ('batch_id', 'review_snapshot_id', 'review_pass_id', 'review_attempt_id')) and native['source_digest'] == context['snapshot_identity']['value'], 'native_context_mismatch')
                identified = identify_return(retained['identity_authority'], retained['delivery'])
                require_fact(authority['canonical_response_events'][pass_id] == event_id and identified['classification'] in ('new_evidence', 'exact_replay'), 'nonactive_delivery_cannot_close')
                return_authority = authority['return_authorities'][pass_id]
                # Missing v10 fresh_dispatch fails here; facts validated above are reused within this barrier.
                fact = facts[pass_id] if pass_id in facts else FreshReviewDispatchAuthority.validate(return_authority, return_authority['context'])
                validate_native_review_binding(return_authority, native, fact)
                reply = parse_json(retained['delivery']['payload']); validated_return(return_authority, reply, fact)
                require_fact(reply['pass_completion_state'] == state and reply['review_attempt_id'] == active and retained['delivery']['event_id'] == event_id, 'terminal_response_mismatch')
            else:
                require_fact(state in ('timed_out', 'failed', 'invalidated') and not terminals and attempt.get('failure_kind') in ('timeout', 'transport', 'schema_invalid', 'source_mutation') and nonblank(attempt.get('failure_evidence')), 'terminal_failure_evidence_missing')
            pass_states[pass_id] = state
    unique(seen_events, 'response_event_duplicate')
    return {'terminal_pass_count': len(pass_states), 'coverage_complete': all(state == 'completed' for state in pass_states.values())}, facts

def unique_root(facts):
    require_fact(len({fact['root_actor_id'] for fact in facts}) <= 1, 'review_root_mismatch')

def validate_review_actors(authority, active_facts, retained_facts):
    """Every v10 attempt is a distinct new actor under one root; later attempts exclude earlier ones."""
    by_attempt = dict(retained_facts)
    for pass_id, fact in active_facts.items():
        key = (pass_id, authority['active_attempts'][pass_id])
        require_fact(key not in by_attempt or by_attempt[key]['actor_id'] == fact['actor_id'], 'review_actor_mismatch')
        by_attempt[key] = fact
    unique([fact['actor_id'] for fact in by_attempt.values()], 'review_actor_reused')
    unique_root(by_attempt.values())
    require_fact(all(fact['review_subject'] == authority['review_subject'] for fact in by_attempt.values()), 'review_subject_mismatch')
    for entry in authority['terminal_barrier']['pass_attempt_ledger']:
        earlier = []
        for attempt in entry['attempts']:
            fact = by_attempt.get((entry['review_pass_id'], attempt['review_attempt_id']))
            if fact is None:
                continue
            require_fact(set(earlier) <= set(fact['prior_reviewer_actor_ids']), 'review_prior_actor_missing')
            earlier.append(fact['actor_id'])

def snapshot_identity_valid(identity):
    return type(identity) is dict and all(nonblank(identity.get(key)) for key in ('basis', 'value', 'captured_at', 'scope_manifest_digest')) and identity['basis'] in ('git_revision', 'diff_digest', 'content_digest', 'task_or_pr_revision')

def summary_projection_valid(authority, summary):
    """Offline projection cannot certify closure, actual zero inspection or absent history."""
    try:
        object(summary); plan = authority['plan']
        schema = next(x for x in load_contract('output')['artifacts'] if x['name'] == 'final_summary')
        require_fact(shape_valid(summary, schema), 'aggregate_schema_invalid')
        require_fact(equal(summary['final_batch_plan'], plan) and summary['final_review_snapshot_id'] == authority['review_snapshot_id'] and equal(summary['final_snapshot_identity'], authority['snapshot_identity']), 'aggregate_identity_mismatch')
        batches = summary['batch_summaries']
        inspected = (any(batch['terminal_response_count'] > 0 for batch in batches)
                     or any(row['coverage_disposition'] in ('inspected_no_risk', 'finding') for row in summary['coverage_ledger'])
                     or bool(summary['aggregated_findings']) or bool(summary['fixed_items'])
                     or bool(authority.get('retained_reviewed_scope', [])))
        if authority.get('producer_version') == '9.0':
            require_fact(bool(summary['reviewed_scope']), 'aggregate_scope_invalid')
        elif 'retained_reviewed_scope' not in authority:
            # Offline projections lack retained-history truth. Nonempty scope may
            # come from an inactive inspection; empty scope is provisional only.
            require_fact(bool(summary['reviewed_scope']) or (not inspected
                         and summary['coverage_complete'] is False
                         and summary['result'] == 'HAS_REMAINING_ITEMS'), 'aggregate_scope_invalid')
        else:
            require_fact(bool(summary['reviewed_scope']) if inspected else
                         summary['reviewed_scope'] == [] and summary['coverage_complete'] is False
                         and summary['result'] == 'HAS_REMAINING_ITEMS', 'aggregate_scope_invalid')
        require_fact(summary['rounds'] > 0 and len(batches) == summary['rounds'] and [x['started_batch_ordinal'] for x in batches] == list(range(1, summary['rounds'] + 1)), 'batch_history_mismatch')
        unique([x['batch_id'] for x in batches], 'batch_identity_duplicate'); unique([x['review_snapshot_id'] for x in batches], 'snapshot_identity_duplicate')
        for batch in batches:
            count = batch['expected_response_count']
            require_fact(snapshot_identity_valid(batch['snapshot_identity']) and 1 <= count <= 6 and 0 <= batch['terminal_response_count'] <= count, 'batch_arithmetic_mismatch')
            if batch['batch_status'] == 'complete':
                require_fact(batch['terminal_response_count'] == count and batch['aggregate_rubric_recomputed'] is True, 'batch_arithmetic_mismatch')
            elif batch['batch_status'] in ('incomplete', 'invalidated'):
                require_fact(batch['aggregate_rubric_recomputed'] is False, 'batch_arithmetic_mismatch')
            else:
                raise Invalid('batch_status_invalid')
        last = batches[-1]
        require_fact(last['review_snapshot_id'] == summary['final_review_snapshot_id'] and equal(last['snapshot_identity'], summary['final_snapshot_identity']) and last['batch_id'] == plan['batch_id'], 'batch_history_mismatch')
        current = [row for row in summary['coverage_ledger'] if row['batch_id'] == plan['batch_id'] and row['review_snapshot_id'] == plan['review_snapshot_id']]
        same_set([tuple_key(dict(row, review_perspective=row['perspective'])) for row in current], [tuple_key(row) for row in plan['required_coverage_tuples']], 'aggregate_coverage_mismatch')
        return True
    except (Invalid, KeyError, TypeError, AttributeError, IndexError):
        return False

def validated_retained_evidence(authority):
    sources = []; reviewed_scope = []; facts = {}
    for event_id, retained in authority['responses'].items():
        native = retained['identity_authority']['dispatch_binding']; pass_id = native['review_pass_id']; current = authority['return_authorities'].get(pass_id)
        if current is None or native['batch_id'] != authority['plan']['batch_id'] or native['review_snapshot_id'] != authority['plan']['review_snapshot_id']:
            continue
        context = current['context']
        require_fact(native['source_digest'] == context['snapshot_identity']['value'], 'native_context_mismatch')
        require_fact(retained['delivery']['event_id'] == event_id, 'retained_event_mismatch')
        identify_return(retained['identity_authority'], retained['delivery'])
        original_context = dict(context, review_attempt_id=native['review_attempt_id'])
        if native['producer_version'] in ('10.0', 'v10') and native['review_attempt_id'] != context['review_attempt_id']:
            require_fact('return_authority' in retained, 'retained_review_authority_missing')
        original = retained.get('return_authority', dict(current, context=original_context, historical_dispatch_binding=native))
        require_fact(original.get('producer_version') == authority.get('producer_version'), 'review_version_relabelled')
        if original.get('producer_version') == '10.0':
            native_fields = {'reviewer_actor_id', 'native_invocation_id', 'handoff_digest'}
            expected_context = {key: value for key, value in original_context.items() if key not in native_fields}
            retained_context = {key: value for key, value in original['context'].items() if key not in native_fields}
            require_fact(equal(retained_context, expected_context), 'historical_dispatch_mismatch')
        else:
            require_fact(equal(original['context'], original_context), 'historical_dispatch_mismatch')
        require_fact(equal(original['required_coverage_tuples'], current['required_coverage_tuples']), 'historical_dispatch_mismatch')
        fact = FreshReviewDispatchAuthority.validate(original, original['context'])
        validate_native_review_binding(original, native, fact)
        if fact is not None:
            key = (pass_id, native['review_attempt_id'])
            require_fact(key not in facts or equal(facts[key], fact), 'review_actor_mismatch')
            facts[key] = fact
        try:
            reply = parse_json(retained['delivery']['payload'])
        except (Invalid, ValueError, UnicodeError):
            continue
        if type(reply) is dict and type(reply.get('rubric_scores')) is dict and 'critical_override' in reply['rubric_scores']:
            require_fact('return_authority' in retained or native['review_attempt_id'] == context['review_attempt_id'], 'historical_override_authority_missing')
        try:
            validated_return(original, reply, fact)
        except (Invalid, KeyError, TypeError, AttributeError, IndexError):
            continue
        sources.extend({'source_kind': 'review_pass', 'source_id': pass_id, 'finding': finding} for finding in reply['findings'])
        reviewed_scope.extend(reply['reviewed_scope'])
    return {'source_findings': sources, 'reviewed_scope': distinct(reviewed_scope), 'facts': facts}

def unique_source_findings(sources):
    by_id = {}
    for source in sources:
        finding_id = source['finding']['finding_id']
        require_fact(finding_id not in by_id or equal(by_id[finding_id], source), 'source_finding_conflict')
        by_id[finding_id] = source
    return list(by_id.values())

def validate_aggregate_accounting(authority, summary):
    plan = authority['plan']; barrier, active_facts = terminal_barrier(authority, authority['terminal_barrier'])
    schema = next(x for x in load_contract('output')['artifacts'] if x['name'] == 'final_summary')
    require_fact(shape_valid(summary, schema, {}), 'aggregate_schema_invalid')
    claim = next(field for field in schema['object_fields'] if field['name'] == 'evidence_bounded_claim')['validation'].removeprefix('Exactly: ')
    clean_claim = summary['result'] in ('CLEAN', 'ISSUES_FIXED') and summary['coverage_complete']
    require_fact(summary.get('evidence_bounded_claim') == claim if clean_claim else 'evidence_bounded_claim' not in summary, 'aggregate_claim_invalid')
    reasons = summary.get('additional_round_reasons', [])
    require_fact([reason['round'] for reason in reasons] == list(range(2, summary['rounds'] + 1)) and (not reasons or reasons[0]['reason'] == 'changed_files'), 'additional_round_reasons_invalid')
    retained_evidence = validated_retained_evidence(authority)
    if authority.get('producer_version') == '10.0':
        validate_review_actors(authority, active_facts, retained_evidence['facts'])
    require_fact(summary_projection_valid({'plan': plan, 'review_snapshot_id': plan['review_snapshot_id'], 'snapshot_identity': authority['snapshot_identity'], 'producer_version': authority.get('producer_version'), 'retained_reviewed_scope': retained_evidence['reviewed_scope']}, summary), 'aggregate_projection_invalid')
    require_fact(equal(summary['final_batch_plan'], plan) and summary['final_review_snapshot_id'] == plan['review_snapshot_id'] and equal(summary['final_snapshot_identity'], authority['snapshot_identity']), 'aggregate_identity_mismatch')
    ledger = [row for row in summary['coverage_ledger'] if row['batch_id'] == plan['batch_id'] and row['review_snapshot_id'] == plan['review_snapshot_id']]
    for row in ledger:
        event_id = authority['canonical_response_events'].get(row['review_pass_id']); retained = authority['responses'].get(event_id)
        if retained is not None:
            reply = parse_json(retained['delivery']['payload'])
            original = next((entry for entry in reply['coverage_entries'] if tuple_key(entry, reply['review_pass_id']) == tuple_key(dict(row, review_perspective=row['perspective']))), None)
            require_fact(original is not None, 'coverage_response_missing')
            expected_disposition = original['status'] if original['status'] in ('inspected_no_risk', 'finding') else 'incomplete'
            require_fact(row['terminal_state'] == reply['pass_completion_state'] and (row['coverage_status'] == 'complete' if reply['pass_completion_state'] == 'completed' else row['coverage_status'] in ('incomplete', 'invalidated')) and row['coverage_disposition'] == expected_disposition and row.get('finding_ids') == original.get('finding_ids'), 'coverage_response_mismatch')
        else:
            entry = next(item for item in authority['terminal_barrier']['pass_attempt_ledger'] if item['review_pass_id'] == row['review_pass_id'])
            attempt = next(item for item in entry['attempts'] if item['review_attempt_id'] == entry['active_terminal_attempt_id'])
            require_fact(attempt['terminal_state'] in ('timed_out', 'failed', 'invalidated') and row['terminal_state'] == attempt['terminal_state'] and row['evidence'] == attempt['failure_evidence'] and row['coverage_status'] in ('incomplete', 'invalidated') and row['coverage_disposition'] == 'incomplete' and 'finding_ids' not in row, 'coverage_response_missing')
    same_set([tuple_key(dict(row, review_perspective=row['perspective'])) for row in ledger], [tuple_key(row) for row in plan['required_coverage_tuples']], 'aggregate_coverage_mismatch')
    complete = barrier['coverage_complete'] and all(row['terminal_state'] == 'completed' and row['coverage_status'] == 'complete' and row['coverage_disposition'] in ('inspected_no_risk', 'finding') for row in ledger)
    require_fact(summary['coverage_complete'] is complete, 'aggregate_false_coverage')
    require_fact(not summary.get('coverage_gaps', []) or (not complete and summary['result'] == 'HAS_REMAINING_ITEMS'), 'aggregate_explicit_coverage_gaps')
    if authority.get('producer_version') == '10.0':
        require_fact(set(retained_evidence['reviewed_scope']) <= set(summary['reviewed_scope']), 'aggregate_scope_lost')
    sources = unique_source_findings(authority['source_findings'])
    expected_sources = unique_source_findings(retained_evidence['source_findings'] + authority.get('pre_batch_findings', []) + authority.get('historical_fixed_findings', []))
    same_set(sources, expected_sources, 'source_findings_mismatch')
    aggregates = summary['aggregated_findings']; unique([x['aggregate_finding_id'] for x in aggregates], 'aggregate_finding_duplicate')
    accounting = summary['aggregation_ledger']; rows = [x for x in accounting if x['disposition'] in ('retained', 'merged', 'fixed_closed')]
    same_set([item for row in rows for item in row['source_finding_ids']], [x['finding']['finding_id'] for x in sources], 'lossy_finding_accounting')
    for finding in aggregates:
        row = next((x for x in rows if x['disposition'] in ('retained', 'merged') and x['aggregate_finding_id'] == finding['aggregate_finding_id']), None)
        require_fact(row is not None and row['source_finding_ids'] == finding['source_finding_ids'], 'aggregate_source_mismatch')
        require_fact(equal(row['source_provenance'], finding['source_provenance']), 'aggregate_row_provenance_mismatch')
        expected_alias = distinct([x['source_id'] for x in finding['source_provenance'] if x['source_kind'] == 'review_pass'])
        require_fact('source_pass_ids' not in finding or sorted(finding['source_pass_ids']) == sorted(expected_alias), 'aggregate_alias_mismatch')
        original = [x for x in sources if x['finding']['finding_id'] in finding['source_finding_ids']]
        same_set(finding['source_provenance'], distinct([{key: x[key] for key in ('source_kind', 'source_id')} for x in original]), 'aggregate_provenance_mismatch')
        require_fact(all(all(x['finding'].get(key) == finding.get(key) for key in ('locus', 'invariant', 'failure_mechanism')) for x in original), 'aggregate_merge_mismatch')
        rank = {'must-fix': 3, 'should-fix': 2, 'nit': 1}
        require_fact(finding['severity'] == max(original, key=lambda x: rank[x['finding']['severity']])['finding']['severity'] and finding['confidence_pct'] == min(x['finding']['confidence_pct'] for x in original), 'aggregate_strength_mismatch')
    same_set([x['aggregate_finding_id'] for x in rows if x['disposition'] != 'fixed_closed'], [x['aggregate_finding_id'] for x in aggregates], 'aggregate_row_mismatch')
    previously_fixed = authority['previously_fixed']; fixed = summary['fixed_items']
    same_set([x['aggregate_finding_id'] for x in fixed], [x['aggregate_finding_id'] for x in previously_fixed], 'fixed_identity_mismatch')
    closure = summary.get('closure_results', [])
    same_set([x['aggregate_finding_id'] for x in closure], [x['aggregate_finding_id'] for x in fixed], 'closure_identity_mismatch')
    fresh_closure_finding_ids = []; actual_closure = []
    for pass_id, event_id in authority['canonical_response_events'].items():
        if not closure_context(authority['return_authorities'][pass_id]['context']):
            continue
        retained = authority['responses'].get(event_id)
        if retained is not None:
            reply = parse_json(retained['delivery']['payload'])
            fresh_closure_finding_ids.extend(finding['finding_id'] for finding in reply['findings']); actual_closure.extend(reply['closure_results'])
        else:
            entry = next(item for item in authority['terminal_barrier']['pass_attempt_ledger'] if item['review_pass_id'] == pass_id)
            attempt = next(item for item in entry['attempts'] if item['review_attempt_id'] == entry['active_terminal_attempt_id'])
            require_fact(attempt['terminal_state'] in ('timed_out', 'failed', 'invalidated'), 'closure_failure_missing')
            actual_closure.extend({'aggregate_finding_id': item['aggregate_finding_id'], 'status': 'incomplete', 'evidence': attempt['failure_evidence']} for item in authority['return_authorities'][pass_id]['context']['previously_fixed'])
    same_set(closure, actual_closure, 'closure_response_mismatch')
    same_set([x['aggregate_finding_id'] for x in rows if x['disposition'] == 'fixed_closed'], [x['aggregate_finding_id'] for x in fixed], 'closed_accounting_mismatch')
    for original in previously_fixed:
        row = next((x for x in rows if x['disposition'] == 'fixed_closed' and x['aggregate_finding_id'] == original['aggregate_finding_id']), None)
        require_fact(row is not None and row['source_finding_ids'] == original['source_finding_ids'] and equal(row['source_provenance'], original['source_provenance']), 'immutable_fixed_provenance_mismatch')
        outcome = next(x for x in closure if x['aggregate_finding_id'] == original['aggregate_finding_id']); current = next((x for x in aggregates if x['aggregate_finding_id'] == original['aggregate_finding_id']), None)
        if outcome['status'] == 'verified_closed':
            require_fact(current is None, 'closed_finding_retained')
        elif outcome['status'] == 'incomplete' and any(closure_context(authority['return_authorities'][entry['review_pass_id']]['context']) and entry['terminal_state'] != 'completed' for entry in ledger):
            require_fact(current is None, 'unassessed_closure_finding_invented')
        else:
            require_fact(current is not None and current['severity'] in ('must-fix', 'should-fix') and not any(item in original['source_finding_ids'] for item in current['source_finding_ids']), 'regressed_closure_finding_missing')
            require_fact(any(item in fresh_closure_finding_ids for item in current['source_finding_ids']), 'regressed_closure_source_missing')
    gap_ids = [x['coverage_gap_id'] for x in ledger if x['coverage_status'] in ('incomplete', 'invalidated')]
    same_set([item for x in accounting if x['disposition'] == 'coverage_gap' for item in x['source_coverage_gap_ids']], gap_ids, 'coverage_gap_accounting_mismatch')
    batches = summary['batch_summaries']
    require_fact(summary['rounds'] > 0 and len(batches) == summary['rounds'] and [x['started_batch_ordinal'] for x in batches] == list(range(1, summary['rounds'] + 1)), 'batch_history_mismatch')
    unique([x['batch_id'] for x in batches], 'batch_identity_duplicate'); last = batches[-1]
    require_fact(last['batch_id'] == plan['batch_id'] and last['review_snapshot_id'] == plan['review_snapshot_id'] and equal(last['snapshot_identity'], authority['snapshot_identity']) and last['expected_response_count'] == len(plan['expected_passes']), 'batch_history_mismatch')
    response_count = sum(next(x for x in entry['attempts'] if x['review_attempt_id'] == entry['active_terminal_attempt_id'])['terminal_state'] in ('completed', 'needs_context', 'blocked') for entry in authority['terminal_barrier']['pass_attempt_ledger'])
    require_fact(last['terminal_response_count'] == response_count and last['aggregate_rubric_recomputed'] is complete and (last['batch_status'] == 'complete' if complete else last['batch_status'] in ('incomplete', 'invalidated')), 'batch_arithmetic_mismatch')
    reconciliation = None
    if authority.get('producer_version') == '10.0' and authority.get('review_subject') in ('plan', 'acceptance'):
        reconciliation = validate_request_plan_reconciliation(authority.get('request_plan_reconciliation'))
    incomplete = reconciliation is not None and not reconciliation_complete(reconciliation, authority['review_subject'])
    if incomplete:
        missing = set(reconciliation.get('observed_requirement_ids', [])) != set(reconciliation['required_requirement_ids'])
        require_fact(summary['result'] == 'HAS_REMAINING_ITEMS', 'request_coverage_missing' if missing else 'request_plan_incomplete')
    material = any(x['severity'] in ('must-fix', 'should-fix') for x in aggregates) or bool(summary.get('remaining_items')) or incomplete
    expected = 'HAS_REMAINING_ITEMS' if not complete or material or any(x['status'] != 'verified_closed' for x in closure) else 'ISSUES_FIXED' if fixed else 'CLEAN'
    require_fact(summary['result'] == expected, 'aggregate_false_clean')
    result = {'producer_version': authority['producer_version'], 'coverage_complete': complete, 'result': expected, 'source_finding_count': len(sources)}
    if reconciliation is not None:
        result['request_plan_reconciliation'] = reconciliation
    return result

def validate_request_plan_reconciliation(value):
    """Shape comes from contracts/input.yaml; only cross-field set rules live here."""
    field = next(x for x in load_contract('input')['fields'] if x['name'] == 'request_plan_reconciliation')
    require_fact(type(value) is dict and nonblank(value.get('original_request_ref')) and nonblank(value.get('approved_plan_ref')), 'request_plan_binding_missing')
    require_fact(shape_valid(value, field), 'request_coverage_unknown')
    required = value['required_requirement_ids']; observed = value.get('observed_requirement_ids', [])
    unique(required, 'request_coverage_duplicate'); unique(observed, 'request_coverage_duplicate')
    unresolved = value.get('unresolved_requirement_ids', [])
    require_fact(set(observed) <= set(required) and set(unresolved) <= set(required), 'request_coverage_foreign')
    return value

def reconciliation_complete(value, subject):
    # Absent unresolved lists are unknown, never an implicit empty list. A plan
    # review observes allocation, so planned unfinished task-wide work is not gated;
    # acceptance observes delivery and requires explicit empty unfinished work.
    keys = ('unresolved_requirement_ids', 'unresolved_finding_ids') + (('unfinished_task_wide_work',) if subject == 'acceptance' else ())
    return (set(value.get('observed_requirement_ids', [])) == set(value['required_requirement_ids'])
            and all(value.get(key) == [] for key in keys))

def probe():
    require_fact(sys.version_info >= (3, 9), 'runtime_capability_unavailable')
    require_fact(parse_json(encoded({'ready': [True, 1]})) == {'ready': [True, 1]}, 'runtime_capability_unavailable')
    require_fact(passive_yaml('ready: true\n') == {'ready': True}, 'runtime_capability_unavailable')
    require_fact(Decimal('2.345').quantize(Decimal('.01'), rounding=ROUND_HALF_UP) == Decimal('2.35'), 'runtime_capability_unavailable')
    require_fact(digest('abc') == 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', 'runtime_capability_unavailable')
    require_fact(not shape_valid(True, {'type': 'int'}) and shape_valid(1, {'type': 'int'}), 'runtime_capability_unavailable')
    load_contract('handoffs'); load_contract('output'); load_contract('input')
    return {'valid': True, 'capabilities': ['json', 'private_passive_yaml', 'decimal', 'sha256', 'exact_types', 'fresh_review_authority'], 'current_producer_version': '10.0', 'readable_producer_versions': ['9.0', '10.0']}

def call(request):
    receipts = {}
    try:
        request = primitive_copy(request)
        require_fact(len(encoded(request)) <= MAX_BYTES, 'input_too_large'); object(request)
        receipts = {'authority': receipt(request.get('authority')), 'candidate': receipt(request.get('candidate'))}
        operation = request['operation']; require_fact(operation in OPERATIONS, 'operation_unknown')
        authority = object(request['authority']); candidate = object(request['candidate'])
        result = globals()[operation](authority, candidate)
        return {'valid': True, 'diagnostics': [], 'input_receipts': receipts, 'result': result}
    except (Invalid, KeyError, TypeError, ValueError, AttributeError, IndexError, UnicodeError, OverflowError, RecursionError, StopIteration) as error:
        return {'valid': False, 'diagnostics': [str(error) if type(error) is Invalid else 'input_invalid'], 'input_receipts': receipts}

def main():
    try:
        require_fact(sys.version_info >= (3, 9) and sys.flags.isolated and sys.flags.no_site and sys.dont_write_bytecode, 'isolated_python_required')
        if sys.argv[1:] == ['--help']:
            print(HELP); return 0
        if sys.argv[1:] == ['--probe']:
            result = probe()
        else:
            require_fact(len(sys.argv) == 1, 'arguments_invalid')
            raw = sys.stdin.buffer.read(MAX_BYTES + 1); require_fact(len(raw) <= MAX_BYTES, 'input_too_large')
            result = call(parse_json(raw))
        output = encoded(result); require_fact(len(output) <= MAX_BYTES, 'output_too_large')
        sys.stdout.buffer.write(output + b'\n'); return 0 if result['valid'] else 1
    except (Invalid, KeyError, TypeError, ValueError, OSError, UnicodeError, RecursionError, OverflowError) as error:
        code = str(error) if type(error) is Invalid else 'input_invalid'
        sys.stdout.buffer.write(encoded({'valid': False, 'diagnostics': [code]}) + b'\n'); return 1

HELP = '## Deterministic validation and retained returns\n\nResolve `scripts/review-tools.py` from the loaded assistant-review skill directory,\nindependent of cwd or Workflow. Python3.9+ uses stdlib JSON/Decimal/SHA-256 and its private pinned\npure-Python YAML parser; run `python3 -I -S -B "<skill>/scripts/review-tools.py" --probe`. Missing runtime or\ncontracts blocks validation: restore the prerequisite and rerun, never accept an\nunchecked return. The installers probe before any writes, including dry-run.\n\nInvoke the helper with one JSON object on stdin:\n`{"operation":"identify_return","authority":{...},"candidate":{...}}`.\nThe other operations are `validate_return`, `validate_terminal_barrier`, and\n`validate_aggregate_accounting`. Exit 0 means mechanically valid, exit 1 invalid;\nstdout is a compact JSON object with `valid`, stable `diagnostics`, input receipts\nand, on success, `result`. No raw payload is echoed. Both library and CLI reject\nnon-primitive/oversize inputs (8 MiB, depth 64, library 100000 nodes). No Ruby/pip/site package or compiled YAML dependency is needed. The library\nloads only its own authoritative passive YAML; it never spawns, mutates files,\nfetches network data or resolves caller paths. No second schema is maintained.\n\nThe caller resolves independently retained authority before invoking. Candidate\nfields, receipts and matching hashes cannot establish that authority. Helper\ninputs are primitive transport representations validated on conversion:\n\n- `identify_return`: authority has `dispatch_binding`, `history_known`, `records`,\n  `archives`. A binding has nonempty `task_id`, `native_invocation_id`, `batch_id`,\n  `review_snapshot_id`, `review_pass_id`, `review_attempt_id`, `producer_id`,\n  `producer_version`, `source_digest`. Candidate has that `binding`, `event_id`,\n  `complete:true`, full opaque `payload` UTF-8 text, and `payload_ref`. Each retained\n  record has binding, payload_ref, payload_sha256 and unique event_ids; archives\n  maps resolved refs to exact raw bytes. Same native event returns `exact_replay`;\n  distinct identical delivery returns `duplicate`; first return `new_evidence`.\n  The caller independently establishes completeness from terminal native transport\n  evidence; the transported complete flag is not proof from the agent payload.\n  Whitespace differences remain changed evidence. Conflicting event identity or\n  changed payload fails with a conflict diagnostic; preserve both raw returns.\n- `validate_return`: authority `context` contains exact dispatched round, batch,\n  snapshot ID/identity, pass/active attempt/perspective, assigned_scope, scope_size\n  and applicability flags; `required_coverage_tuples` is that pass\'s independently\n  frozen tuple list. Include previously_fixed for closure. Candidate is the\n  unchanged canonical v10 return (or explicitly bound historical v9 return). The helper checks recursive canonical fields,\n  conditions, status truth tables, exact unique tuple membership, provenance,\n  closure IDs and decimal rubric arithmetic. Omitted applicability uses canonical\n  literal boolean defaults; rubric defaults true for medium/large scope. Unknown\n  flags/scope and medium+ rubric exemptions fail closed without mutating authority.\n  When rubric_scores includes a\n  critical_override, supply independent authority `critical_override_cap` as\n  1, 2 or 2.5 per the shared rubric; omit it otherwise. The caller classifies the\n  finding and verifies that the override description matches this retained cap.\n  The helper never derives a cap from prose. It cannot judge evidence truth,\n  severity, equivalence, actual inspection or semantic verdict quality.\n- `validate_terminal_barrier`: authority has frozen `plan`, `active_attempts`\n  (pass ID to actual attempt ID), `return_authorities` (pass ID to return authority),\n  `canonical_response_events` (pass ID to original canonical event ID),\n  `source_current`, `producer_current`, `unresolved_conflicts`, and `responses`.\n  Each responses event maps to retained `identity_authority` plus original\n  `delivery` as above. Candidate contains the version-bound `pass_attempt_ledger`. Canonical\n  archived event replay can support its existing active slot; a distinct duplicate\n  never creates another terminal. Lifecycle failures need typed failure evidence.\n- `validate_aggregate_accounting`: same authority plus `terminal_barrier`,\n  `snapshot_identity`, immutable `previously_fixed`, independently retained\n  `source_findings` envelopes (`source_kind`, `source_id`, `finding`), optional\n  `pre_batch_findings` and `historical_fixed_findings`. Candidate is canonical\n  final_summary. All same-snapshot validated retained returns contribute findings,\n  including inactive attempts; only active returns establish coverage. Historical\n  return identity is reconstructed from native dispatch binding and frozen pass\n  context/tuples. Retain original `return_authority` for inactive v10 actors and original rubric override caps. Identical full source findings\n  with one stable ID deduplicate; conflicting contents block accounting.\n  Validate canonical conditional fields, calibrated claim, later-round reasons,\n  the barrier, identities, exact coverage, lossless source\n  union/provenance, conservative merge arithmetic and closure accounting before\n  the caller assesses equivalence, aggregate rubric and final result. Unassessed\n  closure is incomplete: native NEEDS_CONTEXT/BLOCKED retains exact closure rows;\n  typed lifecycle failure without a response uses each immutable fixed ID with\n  status incomplete and evidence exactly equal to retained failure_evidence.\n  Coverage rows also bind that failure evidence; no finding is invented.\n\nRetain canonical payload once with occurrence bindings; do not add a result,\nfinding or global ledger. Validate source/producer freshness and resolve/rehash\nall referenced archives after compaction; absent history is unknown. Preserve\nactive attempts, unresolved conflicts and validated findings. Use native\ncompletion notifications and bounded waits; full inventories serve discovery or\nrecovery, not repeated result retrieval. Host-injected reports remain visible;\nsavings concern avoidable subsequent retrieval/processing only. Duplicate or\nstale results never constitute coverage or semantic progress.'

HELP += """

Current Review v10 authority

Return, terminal and aggregate authorities explicitly declare producer_version
10.0. No missing-version downgrade exists. validate_return authority contains
fresh_dispatch with actor_id, root_actor_id, author_actor_ids,
prior_reviewer_actor_ids, native_invocation_id, creation_evidence_ref,
runtime_evidence_ref, runtime, context_isolation=fresh_self_contained,
handoff_digest, source_digest and review_subject (plan|implementation|closure|
acceptance); runtime codex additionally requires fork_turns=none; runtime must equal
its stripped lowercase form, so padded or cased codex is invalid. The fresh_dispatch and
historical_dispatch_binding shapes are their object_fields in contracts/input.yaml,
loaded at runtime (author_actor_ids non-empty, no unknown keys). Actor disjointness,
creation and source/context facts come from retained native authority, never the
return payload. Its caller context binds reviewer_actor_id, native_invocation_id,
handoff_digest, review_subject and snapshot_identity. These authority facts stay
outside the reviewer payload and bounded worker bundle.

Terminal/aggregate authority declares the same review_subject and version; every
current and retained inactive return_authority declares exactly the top-level
producer_version (review_version_relabelled), which the aggregate result echoes, is current and each actual native invocation binds its fresh actor.
A typed terminal creation failure without a response retains frozen context/tuples
and real failure evidence; it needs no invented actor and cannot close coverage.
The terminal barrier validates each active fresh fact once and reuses it for that
pass's return. Aggregate accounting runs that barrier, then separately validates the
original authority of every retained same-snapshot return (active and inactive), and
compares every actor from active fresh_dispatch and retained inactive v10 return_authority: actor IDs are
unique across all passes and attempts (review_actor_reused), all share one
root_actor_id (review_root_mismatch) and review_subject, and each attempt's
prior_reviewer_actor_ids includes every earlier attempt actor of its pass
(review_prior_actor_missing). No author, root or prior reviewer substitutes.
Historical v9 reading explicitly declares 9.0 and historical_dispatch_binding
with the original complete native binding. It preserves original labels and
raw payload identity, and cannot certify v10 through omission or relabelling.

Trivial/small light review plans one light_contract_and_runtime pass covering
both trivial_small concerns (discovery_pass_count 1, no separate closure pass).
That one-pass topology requires topology.light_review true and terminal/aggregate
authority controller_intensity light (topology_light_review_missing,
topology_light_intensity_mismatch); light_review true on any other topology fails
(topology_light_review_invalid), and small standard/strict keeps >=2 passes;
its post-fix re-review is one new pass that receives previously_fixed with
closure_ledger visibility and returns closure_results. Historical two-pass
trivial/small batches stay valid; medium+ topology is unchanged.

Plan review (authority review_subject plan) plans one plan_coverage_and_feasibility
pass at any scope size with topology.plan_review true, discovery_pass_count 1 and
no closure pass (topology_plan_closure_invalid); that perspective without
plan_review true fails (topology_plan_review_missing) and plan_review true for any
other subject fails (topology_plan_review_invalid). Its post-fix re-review is one
new pass with the same closure_ledger/closure_results mechanics as light review.
Historical multi-pass plan reviews stay readable; new plan reviews use exactly one pass.

For plan/final acceptance, aggregate authority additionally resolves existing
request_plan_reconciliation: original_request_ref, approved_plan_ref,
required_requirement_ids, observed_requirement_ids, unresolved_requirement_ids,
unfinished_task_wide_work and unresolved_finding_ids; for plan review,
approved_plan_ref is the reviewed plan-definition ref, not an approval. Its shape is the
request_plan_reconciliation field in contracts/input.yaml, loaded at runtime.
Completed verdicts require observed == required and explicit empty unresolved
requirement and finding lists; absent lists are unknown. For plan review observed
means allocated by the plan and unfinished_task_wide_work may be non-empty; final
acceptance observes delivery and also requires explicit empty unfinished work. Truthful incomplete coverage remains
HAS_REMAINING_ITEMS. A valid result echoes the validated object unchanged as
result.request_plan_reconciliation for workflow admission. This projection consumes existing scope/acceptance evidence;
it is not another plan ledger or proof that substantive review occurred.
"""

if __name__ == '__main__':
    raise SystemExit(main())
