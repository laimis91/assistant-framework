#!/usr/bin/env python3
"""Discriminating packet controls shared by the existing task-packet suite.

Synthetic authority is fixed independently of candidate mutations. These are
consistency controls, never evidence of native isolation or model effectiveness.
"""

from copy import deepcopy
import importlib.util
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("packet_admission", ROOT / "skills/assistant-workflow/scripts/task-packet-admission.py")
API = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = API
SPEC.loader.exec_module(API)


def applicability(request, packet, status="required"):
    """Synthetic independently fixed semantic resolution, not inferred from method/TDD."""
    context = request["context"]
    return {"approved_plan_identity": deepcopy(request["plan"]["approved_plan_identity"]),
            "packet_definition_digest": API.digest(API.packet_definition(packet)),
            "input_identity": deepcopy(context["current_input_identities"][packet["packet_id"]]),
            "build_execution_lane": context["build_execution_lane"],
            "verification_decision_ref": deepcopy(context["verification_decision_ref"]),
            "selected_check_ids": deepcopy(packet["selected_check_ids"]),
            "binding_obligation_refs": deepcopy(packet["binding_obligation_refs"]), "status": status,
            "resolution_ref": "assessment:synthetic-fixed-applicability",
            "rationale": ("Selected behavior assertions are required by the current oracle and resolved bindings"
                          if status == "required" else
                          "Current procedure inspects the artifact and policy binding; neither requires tests")}


def seal(request):
    plan, context = request["plan"], request["context"]
    identity = {"task_identity": plan["task_identity"], "plan_version": plan["plan_version"],
                "approval_ref": "approval:synthetic-fixed", "definition_digest": API.digest(API.definition(plan))}
    plan["approved_plan_identity"] = deepcopy(identity)
    context["approved_plan_identity"] = deepcopy(identity)
    context["test_applicability"] = {p["packet_id"]: applicability(request, p) for p in plan["implementation_steps"]}
    for packet in plan["implementation_steps"]:
        prior = context.get("packet_evidence", {}).get(packet["packet_id"])
        if prior is not None and "implementation_evidence_ref" not in prior and "tdd_cycle" not in prior:
            proof = evidence(request, packet)
            proof.pop("implementation_evidence_ref")
            context["packet_evidence"][packet["packet_id"]] = proof
    return request


def valid_request(count=1, boundary="dispatch"):
    binding = {"kind": "required_scope", "value": "Preserve accepted behavior", "source_ref": "authority:scope"}
    decision = {"scope": "synthetic packet controls", "policy_basis": {"binding_constraints": [binding]},
                "checks": [{"check_id": "focused", "method": "automated_test", "command": {"argv": ["python3", "verify.py", "literal argument"], "cwd": "/workspace"},
                            "check_ref_or_method": {"reference_or_procedure": "Check focused behavior", "meaningful_failure": "Expected behavior is absent"}},
                           {"check_id": "integrated", "method": "artifact_inspection", "check_ref_or_method": {"reference_or_procedure": "Inspect the current integrated acceptance evidence"}}],
                "tdd_choice": {"mode": False, "applicable_check_ids": [], "basis": "not_selected", "rationale": "No RED required"}}
    ref = {"artifact_ref": "verification:fixed", "sha256": API.digest(decision)}
    requirements = [{"requirement_id": "R-" + str(i), "acceptance_criterion": "Accepted outcome " + str(i)} for i in range(count)]
    packets = []
    for i, requirement in enumerate(requirements):
        pid = ["accepted-outcome", "dependent-outcome", "integrated-outcome"][i]
        packets.append({"packet_id": pid, "name": pid, "description": "Execute the accepted packet outcome",
                        "reuse_search": {"applicability": "not_applicable", "applicability_reason": "Bounded synthetic packet control"},
                        "test_criteria": ["Observe the allocated accepted behavior"], "implementation_notes": [],
                        "verification_command": ["python3", "verify.py", "literal argument"], "observable_increment": "Observable accepted result", "deliverable_type": "behavior",
                        "requirement_ids": [requirement["requirement_id"]], "acceptance_criteria": [requirement["acceptance_criterion"]],
                        "verification_decision_ref": deepcopy(ref), "selected_check_ids": ["focused"], "binding_obligation_refs": [deepcopy(binding)],
                        "tdd_applies": False, "files_to_create": [], "files_to_modify": [pid + ".py"], "files_to_test": ["verify.py"],
                        "enabling_changes_included": [], "depends_on": [] if i == 0 else [packets[i - 1]["packet_id"]],
                        "expected_success_signal": "Accepted outcome observed", "evidence_to_record": ["current focused result"],
                        "deviation_rollback_rule": "Stop changed scope and request reapproval", "boundary_reason": {"kind": "prerequisite", "reason": "Consume prior accepted outcome"},
                        "execution": {"state": "PENDING", "evidence_refs": [], "input_identity": {"source": "source-" + str(i)},
                                      "recovery": {"attempt_count": 0, "no_progress_count": 0}, "history": []}})
    completion = {"requirement_ids": [], "acceptance_criteria": [], "selected_check_ids": ["integrated"], "binding_obligation_refs": []}
    request = {"boundary": boundary, "target_packet_id": packets[0]["packet_id"],
               "plan": {"plan_schema_version": "14.0", "task_identity": "synthetic-task", "plan_version": "approved-1",
                        "verification_decision_ref": deepcopy(ref), "implementation_steps": packets, "completion_allocation": completion},
               "context": {"task_identity": "synthetic-task", "verification_decision": decision, "verification_decision_ref": deepcopy(ref),
                           "requirements": requirements, "required_completion_allocation": deepcopy(completion), "evidence_assessment": {"status": "planned", "gaps_and_limitations": []},
                           "readiness": {"execution_intent": "end_to_end", "ready": True, "route_clear": True},
                           "current_input_identities": {p["packet_id"]: deepcopy(p["execution"]["input_identity"]) for p in packets},
                           "packet_evidence": {}, "workspace": {"mode": "shared", "active_source_writer_ids": []},
                           "recovery_counters": {p["packet_id"]: deepcopy(p["execution"]["recovery"]) for p in packets},
                           "build_execution_lane": "separated_workers"}}
    seal(request)
    request["context"]["writer_actor_ids"] = {p["packet_id"]: "native-writer:" + p["packet_id"] for p in packets}
    for packet in packets:
        proof = evidence(request, packet)
        proof.pop("implementation_evidence_ref")
        request["context"]["packet_evidence"][packet["packet_id"]] = proof
    return request


def evidence(request, packet):
    context = request["context"]
    result = {"approved_plan_identity": deepcopy(request["plan"]["approved_plan_identity"]),
              "packet_definition_digest": API.digest(API.packet_definition(packet)), "input_identity": deepcopy(context["current_input_identities"][packet["packet_id"]]),
              "build_execution_lane": "separated_workers", "implementation_evidence_ref": "writer:actual", "builder_evidence_ref": "builder:actual",
              "native_evidence_ref": "runtime:actual", "writer_actor_id": "native-writer:" + packet["packet_id"],
              "tests": {"mode": "reuse", "evidence_ref": "tests:existing"}, "self_check": {"result": "passed", "evidence_ref": "self-check:actual"},
              "validation_results": [], "acceptance_results": [{"criterion": criterion, "result": "passed", "evidence_ref": "acceptance:actual"} for criterion in packet["acceptance_criteria"]]}
    for cid in packet["selected_check_ids"]:
        check = next(c for c in context["verification_decision"]["checks"] if c["check_id"] == cid)
        row = {"selected_check_ids": [cid], "binding_obligation_refs": deepcopy(packet["binding_obligation_refs"]), "result": "passed", "evidence_ref": "check:actual"}
        if "command" in check:
            row["executed_command"] = {"check_id": cid, **deepcopy(check["command"])}
        else:
            row["procedure"] = check["check_ref_or_method"]["reference_or_procedure"]
        result["validation_results"].append(row)
    return result


def verify_all(request):
    for packet in request["plan"]["implementation_steps"]:
        packet["execution"]["state"] = "VERIFIED"
        request["context"]["packet_evidence"][packet["packet_id"]] = evidence(request, packet)
    return request


def legacy_request(many=False, active=False, tagged=False):
    canonical = valid_request(3 if many else 1, "plan")
    if active:
        decision = canonical["context"]["verification_decision"]
        decision["tdd_choice"] = {"mode": True, "applicable_check_ids": ["focused"]}
        canonical["context"]["verification_decision_ref"]["sha256"] = API.digest(decision)
        for packet in canonical["plan"]["implementation_steps"]:
            packet["tdd_applies"] = True
    source = {"task_identity": "synthetic-task", "plan_version": "approved-1", "slice_manifest": [], "implementation_steps": []}
    if tagged:
        source["schema_version"] = "12.0"
    groups = ["source-outcome", "source-outcome", "downstream-outcome"] if many else ["source-outcome"]
    for index, packet in enumerate(canonical["plan"]["implementation_steps"]):
        old = deepcopy(packet)
        old.pop("boundary_reason")
        old.pop("verification_decision_ref")
        old["slice_id"] = groups[index]
        old.update(order=index + 1, slice_name=groups[index], description="Original v12 executable packet",
                   reuse_search={"applicability": "not_applicable", "applicability_reason": "Bounded legacy fixture"},
                   test_criteria=["Existing selected behavior"], implementation_notes=["Preserve original allocations"])
        old["task_id"] = old.pop("packet_id")
        old["verification_decision"] = deepcopy(canonical["context"]["verification_decision"])
        # Required by the actual v12 Architect packet contract. Historical
        # assessment stays in the source; current assessment is resolved separately.
        old["evidence_assessment"] = {"status": "planned", "scope_and_evidence_refs": [],
                                      "gaps_and_limitations": ["Historical selection has no current results"],
                                      "next_action": "Refresh current evidence before Build"}
        old["depends_on"] = ["source-outcome"] if many and index == 2 else []
        source["implementation_steps"].append(old)
    for sid in dict.fromkeys(groups):
        owned = [p for p in source["implementation_steps"] if p["slice_id"] == sid]
        source["slice_manifest"].append({"slice_id": sid, "depends_on": ["source-outcome"] if sid == "downstream-outcome" else [],
                                         **{field: deepcopy(owned[0][field]) for field in ("observable_increment", "deliverable_type", "tdd_applies",
                                             "expected_success_signal", "evidence_to_record", "deviation_rollback_rule", "verification_command")},
                                         "name": sid, "verification_decision": deepcopy(canonical["context"]["verification_decision"]),
                                         **{field: list({API.digest(value): value for packet in owned for value in packet[field]}.values())
                                            for field in ("acceptance_criteria", "selected_check_ids", "binding_obligation_refs",
                                                          "files_to_create", "files_to_modify", "files_to_test", "enabling_changes_included")}})
    context = canonical["context"]
    context["evidence_assessment"] = {"status": "planned", "scope_and_evidence_refs": [],
                                      "gaps_and_limitations": [], "next_action": "Run selected checks"}
    context["legacy"] = {"producer": {"schema_version": "12.0", "producer_ref": "producer:verified", "verified": True},
                         "source_sha256": API.digest(source), "source_identity": "original:immutable", "approved_source_identity": "original:immutable",
                         "completion_allocation": deepcopy(canonical["plan"]["completion_allocation"]), "source_evidence_refs": ["legacy:retained-evidence"]}
    # One-to-one maps the slice ID, not its optional local task ID.
    if not many:
        context["current_input_identities"] = {"source-outcome": {"source": "source-0"}}
        context["recovery_counters"] = {"source-outcome": {"attempt_count": 0, "no_progress_count": 0}}
    else:
        context["legacy"]["packet_mapping"] = [{"source_packet_index": i, "slice_id": p["slice_id"], "packet_id": p["task_id"]} for i, p in enumerate(source["implementation_steps"])]
    normalized = API.normalize_legacy(source, context)
    context["approved_plan_identity"]["definition_digest"] = API.digest(API.definition(normalized))
    normalized["approved_plan_identity"] = deepcopy(context["approved_plan_identity"])
    context["test_applicability"] = {p["packet_id"]: applicability({"plan": normalized, "context": context}, p)
                                     for p in normalized["implementation_steps"]}
    context["writer_actor_ids"] = {p["packet_id"]: "native-writer:" + p["packet_id"] for p in normalized["implementation_steps"]}
    context["packet_evidence"] = {}
    for packet in normalized["implementation_steps"]:
        proof = evidence({"plan": normalized, "context": context}, packet)
        proof.pop("implementation_evidence_ref")
        context["packet_evidence"][packet["packet_id"]] = proof
    return {"boundary": "plan", "plan": source, "context": context}


def sync_legacy_scope(request):
    """Only intentional valid-scope fixtures update both original owning records."""
    for manifest in request["plan"]["slice_manifest"]:
        owned = [p for p in request["plan"]["implementation_steps"] if p["slice_id"] == manifest["slice_id"]]
        for field in ("files_to_create", "files_to_modify", "files_to_test"):
            manifest[field] = list(dict.fromkeys(value for p in owned for value in p[field]))


def reseal_legacy(request):
    """Synthetic explicit approval of the changed source; scope assertions stay independent."""
    context = request["context"]
    context["legacy"]["source_sha256"] = API.digest(request["plan"])
    normalized = API.normalize_legacy(request["plan"], context)
    context["approved_plan_identity"]["definition_digest"] = API.digest(API.definition(normalized))
    normalized["approved_plan_identity"] = deepcopy(context["approved_plan_identity"])
    context["test_applicability"] = {p["packet_id"]: applicability({"plan": normalized, "context": context}, p)
                                     for p in normalized["implementation_steps"]}
    context["packet_evidence"] = {p["packet_id"]: evidence({"plan": normalized, "context": context}, p) for p in normalized["implementation_steps"]}
    return request


def released_v13_request(runtime="codex", many=False, active=False):
    request = legacy_request(many=many, active=active)
    request["plan"]["schema_version"] = "13.0"
    request["context"]["legacy"]["producer"].update(schema_version="13.0", runtime=runtime)
    for record in request["plan"]["slice_manifest"] + request["plan"]["implementation_steps"]:
        record["worker_stage"] = "test_authoring" if active else "production"
        if runtime != "gemini":
            record["writer_selection"] = {"agent": "intelligent-writer", "rationale": "Original released v13 source writer"}
    return reseal_legacy(request)



def expected_current_definition(source):
    """Independent fixed v14 -> v15 representation oracle, never candidate output.

    Keep every approved field except the specified version tag; coordinator
    execution, approval identity and migration provenance are outside definition.
    """
    assert source["plan_schema_version"] in {"14.0", "15.0"}
    expected = {key: deepcopy(value) for key, value in source.items()
                if key not in {"approved_plan_identity", "reconciliation_provenance"}}
    expected["plan_schema_version"] = "15.0"
    expected["implementation_steps"] = [
        {key: deepcopy(value) for key, value in packet.items() if key != "execution"}
        for packet in source["implementation_steps"]]
    return expected


def assert_current_approval(source, canonical):
    """Only the fixed representation digest may change, with original authority."""
    expected = expected_current_definition(source)
    identity = {**source["approved_plan_identity"], "definition_digest": API.digest(expected)}
    assert canonical["approved_plan_identity"] == identity, "Representation changed original approval authority"
    if source["plan_schema_version"] == "14.0":
        migration = canonical["reconciliation_provenance"]["workflow_migration"]
        assert migration["source_sha256"] == API.digest(source), "Original migration source identity changed"
        assert migration["original_approved_plan_identity"] == source["approved_plan_identity"]
        assert migration["normalized_definition_digest"] == identity["definition_digest"]


def current_authored_dispatch(stage="production"):
    request = valid_request()
    decision = request["context"]["verification_decision"]
    decision["tdd_choice"] = {"mode": True, "applicable_check_ids": ["focused"]}
    ref = request["context"]["verification_decision_ref"]
    ref["sha256"] = API.digest(decision)
    request["plan"]["verification_decision_ref"] = deepcopy(ref)
    packet = request["plan"]["implementation_steps"][0]
    packet.update(verification_decision_ref=deepcopy(ref), tdd_applies=True,
                  red_check_id="focused", red_command=["python3", "verify.py", "literal argument"],
                  red_cwd="/workspace", expected_red_failure="Expected behavior is absent")
    seal(request)
    packet["execution"].update(state="RUNNING", tdd_cycle_log_ref="cycle:new-owned")
    ev = evidence(request, packet)
    ev["tests"] = {"mode": "authored", "evidence_ref": "writer:test-authoring", "writer_actor_id": ev["writer_actor_id"]}
    red = {"check_id": "focused", "test_file": "verify.py", "test_name": "selected behavior",
           "command": deepcopy(packet["red_command"]), "cwd": "/workspace",
           "failure_summary": "Expected behavior absent", "right_reason": "Observed selected missing behavior"}
    phase = {"test_file": "verify.py", "test_name": "selected behavior", "failure_reason": "Observed selected missing behavior", "verified_failing": True,
             "command_results": [{"target": "verify.py :: selected behavior", "test_file": "verify.py", "test_name": "selected behavior", "check_id": "focused",
                                  "argv": deepcopy(packet["red_command"]), "cwd": "/workspace", "result": "failed", "freshness": "current"}]}
    ev["tdd_cycle"] = {"tdd_cycle_log_ref": "cycle:new-owned", "red": red, "red_phase": phase,
                       "green": {"production_file": "accepted-outcome.py", "all_tests_pass": True,
                                 "command": deepcopy(packet["red_command"]), "cwd": "/workspace", "invocation_ref": "green:new-owned"}}
    if stage == "production":
        ev["tdd_cycle"].pop("green")
    request["context"]["packet_evidence"][packet["packet_id"]] = ev
    request.update(worker_stage=stage, worker_role="code_writer")
    return request


def fixed_cases():
    """Fixture authority is frozen before candidate answers are evaluated."""
    coherent = valid_request()
    dependent = valid_request(3)
    packets = dependent["plan"]["implementation_steps"]
    packets[1]["depends_on"] = []
    packets[2]["depends_on"] = ["accepted-outcome"]
    seal(dependent)
    packets[0]["execution"]["state"] = "VERIFIED"
    dependent["context"]["packet_evidence"]["accepted-outcome"] = evidence(dependent, packets[0])
    packets[1]["execution"]["state"] = "RUNNING"
    dependent["context"]["workspace"] = {"mode": "isolated", "active_source_writer_ids": ["dependent-outcome"],
        "isolation": {p["packet_id"]: {"current": True, "input_identity": deepcopy(p["execution"]["input_identity"]),
                       "runtime_evidence_ref": "fixture-runtime-isolation:" + p["packet_id"],
                       "workspace_identity": "isolated-workspace:" + p["packet_id"]} for p in packets[1:]}}
    dependent["target_packet_id"] = "integrated-outcome"
    dependent["plan"]["implementation_steps"][2]["execution"]["state"] = "PENDING"
    unsafe = deepcopy(dependent)
    unsafe["plan"]["implementation_steps"][0]["execution"]["state"] = "RUNNING"
    return [("coherent", coherent, "accepted", "accepted"), ("isolated-verified-dependency", dependent, "accepted", "accepted"),
            ("unsafe-dependency", unsafe, "blocked", "prerequisite_unverified")]


def canonical_v14_plan_format_admission():
    # New public boundary authorizer: this must fail because format14 is missing,
    # never because setup/import or an unrelated request field failed.
    case = valid_request(boundary="plan")
    observed = API.admission(case)
    if observed["status"] == "blocked" and observed["code"] == "unsupported_version":
        raise AssertionError("Canonical v14 packet format is not admitted")
    if observed["status"] != "accepted" or observed["canonical_plan"]["plan_schema_version"] != "15.0":
        raise AssertionError(("Unexpected canonical14 admission result", observed))


def no_tests_request(command=False):
    request = valid_request(boundary="verification")
    packet = request["plan"]["implementation_steps"][0]
    packet["selected_check_ids"] = ["integrated"]
    packet["files_to_test"] = []
    packet.pop("verification_command")
    if command:
        check = request["context"]["verification_decision"]["checks"][1]
        check["command"] = {"argv": ["python3", "inspect-artifact.py"], "cwd": "/workspace"}
        packet["verification_command"] = deepcopy(check["command"]["argv"])
        ref = request["context"]["verification_decision_ref"]
        ref["sha256"] = API.digest(request["context"]["verification_decision"])
        request["plan"]["verification_decision_ref"] = deepcopy(ref)
        packet["verification_decision_ref"] = deepcopy(ref)
    request["plan"]["completion_allocation"]["selected_check_ids"] = ["focused", "integrated"]
    seal(request)
    packet["execution"]["state"] = "RUNNING"
    request["context"]["test_applicability"][packet["packet_id"]] = applicability(request, packet, "not_applicable")
    proof = evidence(request, packet)
    proof.pop("tests")
    request["context"]["packet_evidence"][packet["packet_id"]] = proof
    return request


def truthful_no_tests_verification():
    """New RED oracle: only the known absent assertion-source defect authorizes it."""
    request = no_tests_request()
    original = deepcopy(request)
    actual = API.admission(request)
    if (actual["status"] == "blocked" and actual["code"] == "malformed"
            and actual["path"] == "accepted-outcome.tests"):
        raise AssertionError("Truthful current no-tests verification is not admitted")
    if (actual["status"] != "accepted"
            or actual["canonical_plan"]["implementation_steps"][0]["execution"]["state"] != "VERIFIED"):
        raise AssertionError(("Unexpected truthful no-tests admission result", actual))
    if request != original or "tests" in request["context"]["packet_evidence"]["accepted-outcome"]:
        raise AssertionError("No-tests control fabricated or mutated assertion evidence")


def active_writer_verification_barrier():
    """New RED oracle: current otherwise-valid evidence cannot verify mutable output."""
    request = valid_request(boundary="verification")
    packet = request["plan"]["implementation_steps"][0]
    packet["execution"]["state"] = "RUNNING"
    request["context"]["packet_evidence"][packet["packet_id"]] = evidence(request, packet)
    request["context"]["workspace"]["active_source_writer_ids"] = [packet["packet_id"]]
    original = deepcopy(request)
    actual = API.admission(request)
    if (actual["status"] == "accepted"
            and actual["canonical_plan"]["implementation_steps"][0]["execution"]["state"] == "VERIFIED"):
        raise AssertionError("Independently active source Writer was accepted as VERIFIED")
    if actual["status"] != "blocked" or actual["code"] != "workspace_overlap":
        raise AssertionError(("Unexpected active-Writer verification result", actual))
    if request != original:
        raise AssertionError("Active-Writer verification mutated caller state")


def terminal_stage_and_provenance_controls():
    """Retained snapshots authenticate progress and migration independently of approval."""
    failures = []

    def check(request, status, name):
        before = deepcopy(request)
        result = API.admission(request)
        if result["status"] != status:
            failures.append((name, status, result))
        if API.digest(request) != API.digest(before):
            failures.append((name, "caller state mutated"))
        return result

    retained = verify_all(valid_request(boundary="resume"))
    retained["context"]["previous_plan"] = deepcopy(retained["plan"])
    check(retained, "accepted", "unchanged VERIFIED snapshot remains accepted")
    for state in ("PENDING", "RUNNING", "BLOCKED", "INVALIDATED"):
        for boundary in ("resume", "dispatch"):
            trial = deepcopy(retained)
            trial["boundary"] = boundary
            trial["plan"]["implementation_steps"][0]["execution"]["state"] = state
            if state == "RUNNING":
                trial.update(worker_stage="production", worker_role="code_writer")
            check(trial, "blocked", "retained VERIFIED cannot downgrade to " + state + " at " + boundary)
    for changed in ("input", "evidence", "workspace", "prerequisite"):
        trial = verify_all(valid_request(2, "resume"))
        first, dependent = trial["plan"]["implementation_steps"]
        first["execution"]["evidence_refs"] = ["retained:verification"]
        trial["context"]["previous_plan"] = deepcopy(trial["plan"])
        if changed == "input":
            trial["context"]["current_input_identities"][first["packet_id"]] = {"source": "new"}
        elif changed == "evidence":
            trial["context"]["packet_evidence"][first["packet_id"]]["validation_results"][0]["result"] = "failed"
        elif changed == "workspace":
            trial["context"]["workspace"]["active_source_writer_ids"] = [first["packet_id"]]
        else:
            # The ancestor was already unfinished in the independently retained
            # snapshot; the helper invalidates the formerly VERIFIED dependent.
            first["execution"]["state"] = "BLOCKED"
            trial["context"]["previous_plan"] = deepcopy(trial["plan"])
        result = check(trial, "accepted", "helper invalidates changed " + changed)
        if result["status"] == "accepted":
            canonical = result["canonical_plan"]
            affected = canonical["implementation_steps"][1:]
            if changed != "prerequisite":
                affected = canonical["implementation_steps"]
            if any(p["execution"]["state"] != "INVALIDATED" or not p["execution"]["history"] for p in affected):
                failures.append((changed, "helper must retain invalidation history"))
            if canonical["implementation_steps"][0]["execution"]["evidence_refs"] != ["retained:verification"]:
                failures.append((changed, "invalidation discarded retained evidence"))
            continuation = deepcopy(trial)
            continuation["plan"] = deepcopy(canonical)
            continuation["context"] = deepcopy(result["canonical_context"])
            continuation["context"]["previous_plan"] = deepcopy(canonical)
            again = check(continuation, "accepted", "helper INVALIDATED snapshot remains resumable")
            if again["status"] == "accepted" and again["canonical_plan"] != canonical:
                failures.append((changed, "repeated resume duplicated invalidation history"))

    for lane in ("bounded_executor", "separated_workers"):
        inactive = valid_request()
        packet = inactive["plan"]["implementation_steps"][0]
        packet["execution"]["state"] = "RUNNING"
        inactive["context"]["build_execution_lane"] = lane
        inactive["context"]["test_applicability"][packet["packet_id"]] = applicability(inactive, packet)
        proof = evidence(inactive, packet)
        proof["build_execution_lane"] = lane
        inactive["context"]["packet_evidence"][packet["packet_id"]] = proof
        for stage in ("production", "final_verification", "refactor"):
            trial = deepcopy(inactive)
            trial.update(worker_stage=stage, worker_role="builder_tester" if lane == "separated_workers" and stage == "final_verification" else "code_writer")
            check(trial, "blocked" if stage == "refactor" else "accepted", "inactive " + lane + " " + stage)
        inactive["plan"]["implementation_steps"][0]["execution"]["state"] = "PENDING"
        inactive.update(worker_stage="refactor", worker_role="code_writer")
        check(inactive, "blocked", "PENDING inactive refactor remains blocked")
        active = current_authored_dispatch("refactor")
        active["context"]["build_execution_lane"] = lane
        packet = active["plan"]["implementation_steps"][0]
        active["context"]["test_applicability"][packet["packet_id"]] = applicability(active, packet)
        active["context"]["packet_evidence"][packet["packet_id"]]["build_execution_lane"] = lane
        check(active, "accepted", "active " + lane + " current GREEN permits refactor")
        for mutation in ("missing", "failed", "command", "cwd"):
            trial = deepcopy(active)
            cycle = trial["context"]["packet_evidence"][packet["packet_id"]]["tdd_cycle"]
            if mutation == "missing": cycle.pop("green")
            elif mutation == "failed": cycle["green"]["all_tests_pass"] = False
            elif mutation == "command": cycle["green"]["command"] = ["wrong"]
            else: cycle["green"]["cwd"] = "/wrong"
            check(trial, "blocked", "active refactor rejects " + mutation + " GREEN")

    check(valid_request(boundary="plan"), "accepted", "fresh canonical plan has no invented provenance")
    for forged in ({"source_sha256": "invented"}, None, 42, False, []):
        trial = valid_request(boundary="plan")
        trial["plan"]["reconciliation_provenance"] = forged
        check(trial, "blocked", "fresh canonical plan cannot introduce provenance " + repr(forged))
        trial["context"]["previous_plan"] = deepcopy(valid_request(boundary="plan")["plan"])
        check(trial, "blocked", "retained fresh snapshot cannot authenticate added provenance")
    for legacy in (legacy_request(), released_v13_request()):
        result = check(legacy, "accepted", "genuine legacy normalization establishes provenance")
        if result["status"] != "accepted":
            continue
        canonical = result["canonical_plan"]
        for boundary in ("plan", "resume", "dispatch", "verification", "completion"):
            trial = deepcopy(legacy)
            trial.update(plan=deepcopy(canonical), boundary=boundary, target_packet_id=canonical["implementation_steps"][0]["packet_id"])
            trial["context"] = deepcopy(result["canonical_context"])
            trial["context"].pop("legacy")
            if boundary == "verification":
                packet = trial["plan"]["implementation_steps"][0]
                packet["execution"]["state"] = "RUNNING"
                trial["context"]["packet_evidence"][packet["packet_id"]] = evidence(trial, packet)
            if boundary == "completion":
                verify_all(trial)
                trial["context"].update(current_snapshot_identity="snapshot:migrated", required_terminal_gates=["independent_review"])
                trial["context"]["completion_evidence"] = {
                    "approved_plan_identity": deepcopy(trial["plan"]["approved_plan_identity"]), "snapshot_identity": "snapshot:migrated",
                    "acceptance_results": [], "validation_results": [{"selected_check_ids": ["integrated"], "binding_obligation_refs": [],
                        "result": "passed", "evidence_ref": "integration:migrated", "procedure": "Inspect the current integrated acceptance evidence"}],
                    "terminal_gates": {"independent_review": {"passed": True, "after_integration": True,
                        "snapshot_identity": "snapshot:migrated", "evidence_ref": "review:migrated"}}}
            trial["context"]["previous_plan"] = deepcopy(trial["plan"])
            check(trial, "accepted", "retained migrated provenance at " + boundary)
            missing = deepcopy(trial)
            missing["context"].pop("previous_plan")
            check(missing, "blocked", "migrated " + boundary + " requires retained snapshot")
            for field in ("source_sha256", "source_identity", "producer", "packet_mapping", "source_evidence_refs", "original_result_allocation", "original_writer_context", "deleted", "type"):
                if field == "original_writer_context" and field not in canonical["reconciliation_provenance"]:
                    continue
                tampered = deepcopy(trial)
                provenance = tampered["plan"]["reconciliation_provenance"]
                if field == "deleted":
                    tampered["plan"].pop("reconciliation_provenance")
                elif field == "type":
                    provenance["producer"]["verified"] = 1  # True and 1 compare equal in Python, not JSON.
                else:
                    provenance[field] = {"forged": "authority"}
                check(tampered, "blocked", "migrated provenance " + field + " altered at " + boundary)
    if failures:
        raise AssertionError(("Terminal/stage/provenance regression controls", failures))


def released_v14_productive_fourth_attempt():
    """Retain released source and independent progress, never invent a v15 plan.

    The task-level context is the progress authority. Execution carries only
    guard/action references; it cannot supply its own reset or assessment. The
    resolved source rows are synthetic observations fixed before mutations,
    rather than evidence of a native check or model run.
    """
    request = valid_request()
    packet = request["plan"]["implementation_steps"][0]
    guard_id = "guard:synthetic-task:accepted-outcome"
    baseline_ref = "frontier:productive:0"
    sources = {baseline_ref: {"accepted_obligations": [], "unresolved": ["scope", "focused", "integration"]}}
    history = []
    evidence_refs = []
    for ordinal, obligation in enumerate(("scope", "focused", "integration"), 1):
        event_id = "checkpoint:productive:" + str(ordinal)
        prior_ref = "frontier:productive:" + str(ordinal - 1)
        frontier_ref = "frontier:productive:" + str(ordinal)
        observation_ref = "observation:productive:" + str(ordinal)
        assessment_ref = "assessment:productive:" + str(ordinal)
        accepted = ["scope", "focused", "integration"][:ordinal]
        sources[frontier_ref] = {"accepted_obligations": accepted,
                                 "unresolved": ["scope", "focused", "integration"][ordinal:]}
        sources[observation_ref] = {"before_frontier_ref": prior_ref, "after_frontier_ref": frontier_ref,
                                    "newly_verified_obligations": [obligation], "result": "passed"}
        sources[assessment_ref] = {"event_id": event_id, "disposition": "verified_gain",
                                  "observation_refs": [observation_ref], "frontier_ref": frontier_ref}
        history.append({"kind": "work_checkpoint", "event_id": event_id, "guard_id": guard_id,
                        "outcome_ref": "outcome:synthetic-task", "predecessor_event_id": history[-1]["event_id"] if history else None,
                        "work_ordinal": ordinal, "action_ref": "action:productive:" + str(ordinal),
                        "assessment_ref": assessment_ref, "evidence_refs": [observation_ref],
                        "disposition": "verified_gain", "frontier_ref": frontier_ref})
        evidence_refs.extend((observation_ref, assessment_ref))
    state = {"schema_version": "1.0", "guard_id": guard_id, "outcome_ref": "outcome:synthetic-task",
             "policy": {"policy_id": "shared-stagnation-v1", "stagnation_window": 3,
                        "source_ref": "policy:approved-shared"},
             "work_ordinal": 3, "consecutive_no_progress": 0, "status": "active",
             "baseline_ref": baseline_ref, "frontier_ref": "frontier:productive:3",
             "history": history, "evidence_refs": evidence_refs}
    sources["policy:approved-shared"] = {"policy_id": "shared-stagnation-v1", "stagnation_window": 3,
                                         "authority_ref": "approval:synthetic-fixed"}
    sources["outcome:synthetic-task"] = {"task_identity": "synthetic-task",
                                         "intended_outcome": "Preserve accepted behavior"}
    action = {"action_ref": "action:productive:4", "packet_id": packet["packet_id"],
              "input_identity": deepcopy(packet["execution"]["input_identity"])}
    request["context"]["progress"] = {"state": state, "resolved_sources": sources, "action": action}
    packet["execution"].update(recovery={"attempt_count": 3, "no_progress_count": 0},
        progress_guard_ref=guard_id, action_ref=action["action_ref"],
        history=[{"kind": "work_checkpoint", "event_id": entry["event_id"], "evidence_ref": entry["assessment_ref"]} for entry in history],
        evidence_refs=deepcopy(evidence_refs))
    request["context"]["recovery_counters"][packet["packet_id"]] = deepcopy(packet["execution"]["recovery"])
    request["context"]["previous_plan"] = deepcopy(request["plan"])
    return request


def productive_fourth_attempt_admission():
    """OG-GUARD-ADMISSION: the released-v14 cumulative ceiling is the RED oracle."""
    request = released_v14_productive_fourth_attempt()
    original = deepcopy(request)
    packet = request["plan"]["implementation_steps"][0]
    retained = request["context"]["progress"]["state"]
    assert request["plan"]["plan_schema_version"] == "14.0"
    assert packet["execution"]["state"] == "PENDING"
    assert packet["execution"]["recovery"]["attempt_count"] == 3
    assert retained["work_ordinal"] == 3 and retained["consecutive_no_progress"] == 0
    assert [entry["disposition"] for entry in retained["history"]] == ["verified_gain"] * 3
    observed = API.admission(request)
    assert request == original, "Productive admission mutated released source or independent progress"
    if observed["status"] == "blocked" and observed["code"] == "recovery_exhausted":
        raise AssertionError("Productive fourth-attempt admission rejected: recovery_exhausted at spent attempt_count=3")
    if observed["status"] != "accepted":
        raise AssertionError(("Productive fourth-attempt failed for an unrelated reason; this is not authorizing RED", observed))
    # Migration may change representation, but must preserve the original
    # approved work, decision, current inputs and historical observations.
    canonical = observed["canonical_plan"]
    assert canonical["task_identity"] == request["plan"]["task_identity"]
    assert canonical["plan_version"] == request["plan"]["plan_version"]
    current = observed["current_task_packet"]
    for field in ("files_to_create", "files_to_modify", "files_to_test", "depends_on",
                  "selected_check_ids", "binding_obligation_refs", "tdd_applies", "verification_decision_ref"):
        assert current[field] == packet[field], ("Migration changed approved allocation", field)
    assert current["verification_decision"] == request["context"]["verification_decision"]
    for field in ("input_identity", "history", "evidence_refs", "recovery"):
        assert current["execution"][field] == packet["execution"][field], ("Migration lost original execution", field)
    progress = observed["canonical_progress_state"]
    for field in ("guard_id", "outcome_ref", "policy", "work_ordinal", "consecutive_no_progress",
                  "status", "baseline_ref", "frontier_ref", "history", "evidence_refs"):
        assert progress[field] == retained[field], ("Admission reset or changed retained progress", field)
    admission = progress["action_admission"]
    assert admission["action_ref"] == "action:productive:4"
    assert admission["packet_id"] == packet["packet_id"]
    assert admission["input_identity"] == packet["execution"]["input_identity"]
    assert admission["guard_id"] == retained["guard_id"]
    assert isinstance(admission["admission_ref"], str) and admission["admission_ref"]


def retained_progress_request(result):
    """The caller commits one accepted snapshot/context, never a candidate reset."""
    return {"boundary": "dispatch", "target_packet_id": "accepted-outcome",
            "plan": deepcopy(result["canonical_plan"]), "context": deepcopy(result["canonical_context"])}


def completed_progress_cycle(request, disposition="no_progress", phase="Build"):
    trial = deepcopy(request)
    carrier = trial["context"]["progress"]
    state, action = carrier["state"], carrier["state"]["action_admission"]
    ordinal = state["work_ordinal"] + 1
    event_id = "checkpoint:cycle:" + str(ordinal)
    observation_ref, assessment_ref = "observation:cycle:" + str(ordinal), "assessment:cycle:" + str(ordinal)
    frontier = state["frontier_ref"]
    observation = {"phase": phase, "result": "failed", "state": "A" if ordinal % 2 else "B",
                   "fresh_verification": True, "fresh_review": True}
    assessment = {"event_id": event_id, "disposition": disposition, "observation_refs": [observation_ref],
                  "frontier_ref": frontier}
    if disposition == "useful_new_evidence":
        uncertainty = "uncertainty:ruled-out:" + str(ordinal)
        carrier["resolved_sources"][uncertainty] = {"result": "plausible cause ruled out", "next_action": "investigate remaining cause"}
        assessment.update(changes_next_action=True, resolved_uncertainty_ref=uncertainty)
    carrier["resolved_sources"].update({observation_ref: observation, assessment_ref: assessment})
    carrier["event"] = {"kind": "work_checkpoint", "event_id": event_id, "guard_id": state["guard_id"],
        "outcome_ref": state["outcome_ref"], "predecessor_event_id": state["history"][-1]["event_id"] if state["history"] else None,
        "work_ordinal": ordinal, "action_ref": action["action_ref"], "admission_ref": action["admission_ref"],
        "assessment_ref": assessment_ref, "evidence_refs": [observation_ref], "disposition": disposition, "frontier_ref": frontier}
    next_action = "action:cycle:" + str(ordinal + 1)
    carrier["action"]["action_ref"] = next_action
    packet = trial["plan"]["implementation_steps"][0]
    packet["execution"].update(state="PENDING", action_ref=next_action)
    return trial



def failed_green_running_next_action_admission():
    """A new semantic correction is distinct from stages of a RUNNING action."""
    request = current_authored_dispatch("refactor")
    request.update(worker_stage="production", worker_role="code_writer")
    packet = request["plan"]["implementation_steps"][0]
    pid = packet["packet_id"]
    cycle = request["context"]["packet_evidence"][pid]["tdd_cycle"]
    cycle["green"].update(all_tests_pass=False, invocation_ref="green:observed-failure")
    guard, action = "guard:failed-green", "action:failed-green-production"
    baseline, policy, outcome = "frontier:failed-green:initial", "policy:failed-green:approved", "outcome:failed-green"
    admission_ref = "admission:observed-first-production"
    input_identity = deepcopy(packet["execution"]["input_identity"])
    identity = {"action_ref": action, "packet_id": pid, "input_identity": input_identity,
                "packet_definition_digest": API.digest(API.packet_definition(packet))}
    packet["execution"].update(progress_guard_ref=guard, action_ref=action, action_admission_ref=admission_ref)
    request["context"]["progress"] = {
        "state": {"schema_version": "1.0", "guard_id": guard, "outcome_ref": outcome,
            "policy": {"policy_id": "shared-stagnation-v1", "stagnation_window": 3, "source_ref": policy},
            "work_ordinal": 0, "consecutive_no_progress": 0, "status": "active",
            "baseline_ref": baseline, "frontier_ref": baseline, "history": [], "evidence_refs": [],
            "action_admission": {"admission_ref": admission_ref, "guard_id": guard, **deepcopy(identity)}},
        "resolved_sources": {
            baseline: {"accepted_obligations": [], "unresolved": ["selected behavior"]},
            policy: {"policy_id": "shared-stagnation-v1", "stagnation_window": 3, "authority_ref": "approval:synthetic-fixed"},
            outcome: {"task_identity": "synthetic-task", "intended_outcome": "Preserve accepted behavior"}},
        "action": deepcopy(identity)}
    initial = API.admission(request)
    assert initial["status"] == "accepted", ("Failed-GREEN lifecycle fixture must pass existing stage/actor/RED/input gates", initial)
    current = retained_progress_request(initial)
    # Retained history is initially empty; unlike the earlier productive fixture,
    # the first checkpoint has no predecessor. Waiting created no completed cycle.
    completed = completed_progress_cycle(current, "useful_new_evidence")
    completed.update(worker_stage="production", worker_role="code_writer")
    packet = completed["plan"]["implementation_steps"][0]
    packet["execution"]["state"] = "RUNNING"
    carrier = completed["context"]["progress"]
    original_cycle = deepcopy(completed["context"]["packet_evidence"][pid]["tdd_cycle"])
    observed = API.admission(completed)
    assert completed["plan"]["implementation_steps"][0]["execution"]["state"] == "RUNNING"
    if observed["status"] == "blocked" and observed["code"] == "progress_replay":
        progress = observed["canonical_progress_state"]
        assert progress["work_ordinal"] == 1 and progress["consecutive_no_progress"] == 0
        assert "action_admission" not in progress
        # Replaying the now closed original action must also remain blocked;
        # fixing the lifecycle must not permit missing-admission replay.
        replay = deepcopy(completed)
        replay["context"]["progress"]["state"] = deepcopy(progress)
        replay["context"]["progress"].pop("event")
        replay["context"]["progress"]["action"] = deepcopy(identity)
        replay["plan"]["implementation_steps"][0]["execution"].update(action_ref=action, action_admission_ref=admission_ref)
        rejected = API.admission(replay)
        assert rejected["status"] == "blocked" and rejected["code"] == "progress_replay", ("Closed action/admission replay was accepted", rejected)
        raise AssertionError("Failed-GREEN same-packet correction rejected: progress_replay after completed action while packet stays RUNNING")
    assert observed["status"] == "accepted", ("Failed-GREEN lifecycle discriminator failed for an unrelated reason; not supplemental RED", observed)
    actual = observed["current_task_packet"]
    assert actual["execution"]["state"] == "RUNNING"
    assert actual["execution"]["input_identity"] == input_identity
    assert actual["execution"]["history"] == packet["execution"]["history"]
    assert actual["red_evidence"] == original_cycle["red"]
    assert observed["canonical_context"]["packet_evidence"][pid]["tdd_cycle"] == original_cycle
    assert observed["canonical_context"]["writer_actor_ids"][pid] == "native-writer:" + pid
    progress = observed["canonical_progress_state"]
    assert progress["work_ordinal"] == 1 and progress["consecutive_no_progress"] == 0
    assert progress["action_admission"]["action_ref"] == carrier["action"]["action_ref"] != action
    assert progress["action_admission"]["admission_ref"] != admission_ref
    replay = retained_progress_request(observed)
    replay.update(worker_stage="production", worker_role="code_writer")
    replay["context"]["progress"]["action"] = deepcopy(identity)
    replay["plan"]["implementation_steps"][0]["execution"].update(action_ref=action, action_admission_ref=admission_ref)
    rejected = API.admission(replay)
    assert rejected["status"] == "blocked" and rejected["code"] == "progress_replay", ("Closed action/admission replay was accepted", rejected)


def policy_history_controls(pending_unblock, consumed_unblock):
    """User policy changes are history, never progress or a reset window."""
    def policy_change(request):
        trial = deepcopy(request)
        carrier = trial["context"]["progress"]
        state = carrier["state"]
        previous_policy = deepcopy(state["policy"])
        next_policy = {"policy_id": "shared-stagnation-v1", "stagnation_window": 5, "source_ref": "policy:explicit-user:5"}
        authority, observation, assessment = "authority:user-window5", "observation:user-window5", "assessment:user-window5"
        event = {"kind": "policy_change", "event_id": "policy-change:3-to-5", "guard_id": state["guard_id"],
            "outcome_ref": state["outcome_ref"], "predecessor_event_id": state["history"][-1]["event_id"],
            "work_ordinal": state["work_ordinal"], "action_ref": carrier["action"]["action_ref"],
            "assessment_ref": assessment, "evidence_refs": [observation], "authority_ref": authority,
            "previous_policy": previous_policy, "new_policy": next_policy}
        carrier["resolved_sources"].update({
            "policy:explicit-user:5": {"policy_id": next_policy["policy_id"], "stagnation_window": 5, "authority_ref": authority},
            authority: {"kind": "user_policy_change", "authorized": True, "guard_id": state["guard_id"],
                        "outcome_ref": state["outcome_ref"], "previous_policy": previous_policy, "new_policy": next_policy},
            observation: {"result": "Explicit user instruction changes shared window from 3 to 5", "authority_ref": authority},
            assessment: {"kind": "policy_change", "event_id": event["event_id"], "observation_refs": [observation],
                         "authority_ref": authority, "previous_policy": previous_policy, "new_policy": next_policy}})
        carrier["event"] = event
        return trial

    def accepted_without_reset(request, before):
        result = API.admission(request)
        assert result["status"] == "accepted", ("Explicit policy change must preserve historical effective policy/unblock validity", result)
        state = result["canonical_progress_state"]
        for name in ("guard_id", "outcome_ref", "work_ordinal", "consecutive_no_progress", "baseline_ref", "frontier_ref"):
            assert state[name] == before[name], ("Policy change reset semantic history", name)
        assert state["history"][:-1] == before["history"]
        assert set(before["evidence_refs"]) <= set(state["evidence_refs"])
        assert state["policy"]["stagnation_window"] == 5
        assert state["history"][-1]["kind"] == "policy_change"
        assert state["action_admission"]["unblock_event_id"] == "event:unblock"
        return result

    # A policy record after the material unblock must not hide its bound action.
    pending = policy_change(pending_unblock)
    before = pending_unblock["context"]["progress"]["state"]
    accepted = accepted_without_reset(pending, before)
    assert before["consecutive_no_progress"] == 3 and "action_admission" not in before
    assert accepted["canonical_progress_state"]["action_admission"]["action_ref"] == pending["context"]["progress"]["action"]["action_ref"]
    # A previously consumed unblock/current admission stays consumed, including
    # subsequent stages of its RUNNING action after the policy-change record.
    consumed = policy_change(retained_progress_request(consumed_unblock))
    consumed.update(worker_stage="production", worker_role="code_writer")
    consumed["plan"]["implementation_steps"][0]["execution"]["state"] = "RUNNING"
    consumed["context"]["packet_evidence"]["accepted-outcome"]["implementation_evidence_ref"] = "writer:observed-unblock-production"
    prior = consumed_unblock["canonical_progress_state"]
    continued = accepted_without_reset(consumed, prior)
    assert continued["canonical_progress_state"]["action_admission"] == prior["action_admission"]
    for mutation in ("unauthorized", "wrong_guard", "self_raise", "replay"):
        trial = deepcopy(pending)
        if mutation == "unauthorized":
            trial["context"]["progress"]["resolved_sources"]["authority:user-window5"]["authorized"] = False
        elif mutation == "wrong_guard":
            trial["context"]["progress"]["resolved_sources"]["authority:user-window5"]["guard_id"] = "different-guard"
        elif mutation == "self_raise":
            trial["context"]["progress"]["state"]["policy"] = deepcopy(trial["context"]["progress"]["event"]["new_policy"])
            trial["context"]["progress"].pop("event")
        else:
            trial = retained_progress_request(accepted)
            trial["context"]["progress"]["event"] = deepcopy(pending["context"]["progress"]["event"])
        result = API.admission(trial)
        assert result["status"] == "blocked", ("Policy cannot authorize its own raise/reset or replay", mutation, result)
        if mutation == "replay": assert result["code"] == "progress_replay"
    # An old-policy compacted base and old count3 unblock remain valid when the
    # prospective current policy is 5. Retain replay/novelty/oscillation lineage.
    compacted = retained_progress_request(continued)
    compacted.update(worker_stage="production", worker_role="code_writer")
    carrier = compacted["context"]["progress"]
    state = carrier["state"]
    historical = before["history"][:-1]  # Keep pending unblock then policy in tail.
    last = historical[-1]
    summary_ref = "history:old-policy3:compacted"
    carrier["resolved_sources"][summary_ref] = {
        "guard_id": state["guard_id"], "outcome_ref": state["outcome_ref"], "policy": deepcopy(before["policy"]),
        "work_ordinal": before["work_ordinal"], "consecutive_no_progress": 3,
        "frontier_ref": before["frontier_ref"], "last_event_id": last["event_id"],
        "seen_event_ids": [row["event_id"] for row in historical],
        "seen_action_refs": list(dict.fromkeys(row["action_ref"] for row in historical if row["kind"] == "work_checkpoint")),
        "seen_policy_authority_refs": [],
        "seen_observation_refs": list(dict.fromkeys(ref for row in historical for ref in row["evidence_refs"])),
        "seen_frontier_refs": list(dict.fromkeys(row["frontier_ref"] for row in historical if "frontier_ref" in row)),
        "seen_unblock_change_refs": [], "unresolved_oscillation_refs": ["observation:cycle:4", "observation:cycle:5", "observation:cycle:6"]}
    state.update(history=state["history"][-2:], history_base_ref=summary_ref)
    state["evidence_refs"].append(summary_ref)
    result = API.admission(compacted)
    assert result["status"] == "accepted", ("Compacted historical policy must be replayed at its original window", result)
    retained = result["canonical_progress_state"]
    assert retained["consecutive_no_progress"] == 3 and retained["work_ordinal"] == before["work_ordinal"]
    assert retained["history_base_ref"] == summary_ref and retained["action_admission"] == prior["action_admission"]
    # Raising policy leaves the spent count at3: one failure reaches4; the next
    # reaches5 and stops. It never grants five extra cycles or policy progress.
    next_cycle = completed_progress_cycle(retained_progress_request(accepted))
    result = API.admission(next_cycle)
    assert result["status"] == "accepted" and result["canonical_progress_state"]["consecutive_no_progress"] == 4, result
    final_cycle = completed_progress_cycle(retained_progress_request(result))
    result = API.admission(final_cycle)
    assert result["status"] == "blocked" and result["code"] == "progress_stagnant", result
    assert result["canonical_progress_state"]["consecutive_no_progress"] == 5


def guarded_parallel_member_request():
    """Fixed grouping authority plus an actual committed first-member admission."""
    request = valid_request(2, "plan")
    request["plan"]["implementation_steps"][1]["depends_on"] = []
    seal(request)  # Independence is approved before any group or candidate exists.
    normalized = API.admission(request)
    assert normalized["status"] == "accepted", ("Parallel Plan fixture is invalid", normalized)
    request = retained_progress_request(normalized)
    packets = request["plan"]["implementation_steps"]
    guard, outcome = "guard:coordinator", "outcome:coordinator"
    action_ref, scope_ref = "action:coordinated-cycle", "scope:coordinated-cycle"
    members = [{"packet_id": p["packet_id"], "packet_definition_digest": API.digest(API.packet_definition(p)),
                "input_identity": deepcopy(request["context"]["current_input_identities"][p["packet_id"]])} for p in packets]
    scope = {"source_ref": scope_ref, "members": members}
    action = {"action_ref": action_ref, "packet_id": members[0]["packet_id"],
              "input_identity": deepcopy(members[0]["input_identity"]), "member_scope": deepcopy(scope)}
    request["context"]["progress"] = {
        "state": {"schema_version": "1.0", "guard_id": guard, "outcome_ref": outcome,
            "policy": {"policy_id": "shared-stagnation-v1", "stagnation_window": 3, "source_ref": "policy:coordinator"},
            "work_ordinal": 0, "consecutive_no_progress": 0, "status": "active",
            "baseline_ref": "frontier:coordinator", "frontier_ref": "frontier:coordinator", "history": [], "evidence_refs": []},
        "resolved_sources": {
            "frontier:coordinator": {"accepted_obligations": [], "unresolved": ["both packet outcomes"]},
            "policy:coordinator": {"policy_id": "shared-stagnation-v1", "stagnation_window": 3, "authority_ref": "approval:synthetic-fixed"},
            outcome: {"task_identity": "synthetic-task", "intended_outcome": "Preserve accepted behavior"},
            scope_ref: {"kind": "coordinator_action_scope", "guard_id": guard, "outcome_ref": outcome,
                "action_ref": action_ref, "approved_plan_identity": deepcopy(request["plan"]["approved_plan_identity"]),
                "members": deepcopy(members), "grouping_decision_ref": "decision:independent-isolated-packets"},
            "decision:independent-isolated-packets": {"approved_plan_identity": deepcopy(request["plan"]["approved_plan_identity"]),
                "reason": "Independent approved outcomes can run in witnessed isolated workspaces"}},
        "action": action}
    for packet in packets:
        packet["execution"].update(progress_guard_ref=guard, action_ref=action_ref)
    request["context"]["previous_plan"] = deepcopy(request["plan"])
    first = API.admission(request)
    assert first["status"] == "accepted", ("First guarded member must pass existing admission gates", first)
    second = retained_progress_request(first)
    carrier = second["context"]["progress"]
    # Released singleton parsing drops unknown optional membership. Preserve the
    # EXACT fixed scope, rather than making parser support the authorizing RED.
    retained = carrier["state"]["action_admission"]
    for field in ("action_ref", "packet_id", "input_identity"):
        assert retained[field] == action[field], ("First admission changed anchor", field)
    retained["member_scope"] = deepcopy(scope)
    carrier["action"] = deepcopy(action)
    packets = second["plan"]["implementation_steps"]
    packets[0]["execution"]["state"] = "RUNNING"  # Independently observed A dispatch.
    second["context"]["previous_plan"] = deepcopy(second["plan"])
    second["target_packet_id"] = packets[1]["packet_id"]
    second["context"]["workspace"] = {"mode": "isolated", "active_source_writer_ids": [packets[0]["packet_id"]],
        "isolation": {p["packet_id"]: {"current": True,
            "input_identity": deepcopy(second["context"]["current_input_identities"][p["packet_id"]]),
            "runtime_evidence_ref": "runtime:coordinator:" + p["packet_id"],
            "workspace_identity": "workspace:coordinator:" + p["packet_id"]} for p in packets}}
    return second


def guarded_parallel_barrier_request(joined, complete=True):
    """One lead checkpoint consumes independently recorded terminal member results."""
    request = completed_progress_cycle(joined)
    request["boundary"] = "plan"  # Close the cycle without inventing a next dispatch.
    request["plan"] = deepcopy(joined["plan"])
    carrier = request["context"]["progress"]
    carrier["action"] = deepcopy(joined["context"]["progress"]["action"])
    event = carrier["event"]
    admission = carrier["state"]["action_admission"]
    identity = admission["action_ref"] + ":" + admission["admission_ref"]
    barrier_ref = "barrier:coordinated-cycle:" + identity
    event["coordinator_barrier_ref"] = barrier_ref
    members = admission["member_scope"]["members"]
    results = []
    for member in members[:len(members) if complete else 1]:
        ref = "observation:member-terminal:" + identity + ":" + member["packet_id"]
        carrier["resolved_sources"][ref] = {"packet_id": member["packet_id"], "result": "failed",
            "lifecycle": "terminal_cycle", "invocation_ref": "green:observed:" + identity + ":" + member["packet_id"],
            "action_ref": admission["action_ref"], "admission_ref": admission["admission_ref"]}
        results.append({"packet_id": member["packet_id"], "result": "failed", "evidence_refs": [ref]})
    carrier["resolved_sources"][barrier_ref] = {"kind": "coordinator_barrier",
        "guard_id": carrier["state"]["guard_id"], "outcome_ref": carrier["state"]["outcome_ref"],
        "action_ref": admission["action_ref"], "admission_ref": admission["admission_ref"],
        "action_scope_ref": admission["member_scope"]["source_ref"], "member_results": results}
    return request


def guarded_parallel_second_member_admission():
    """A second isolated member shares one coordinator admission and semantic count."""
    request = guarded_parallel_member_request()
    before = deepcopy(request)
    observed = API.admission(request)
    assert request == before, "Grouped admission mutated caller-owned authority or retained A state"
    if observed["status"] == "blocked" and observed["code"] == "progress_mismatch":
        assert observed["path"] == "dependent-outcome"
        assert observed["details"] == "Action/guard must bind independently current packet and inputs"
        assert observed["canonical_progress_state"]["work_ordinal"] == 0
        assert observed["canonical_plan"]["implementation_steps"][0]["execution"]["state"] == "RUNNING"
        raise AssertionError("Legitimate second isolated PENDING member rejected progress_mismatch at packet/action target binding")
    assert observed["status"] == "accepted", ("Grouped second member failed for an unrelated reason; not supplemental RED", observed)
    expected = request["context"]["progress"]["state"]
    assert observed["canonical_progress_state"] == expected, "Joining B spent another action/unblock or changed history/count"
    admission = expected["action_admission"]
    assert observed["current_task_packet"]["execution"]["action_admission_ref"] == admission["admission_ref"]
    joined = retained_progress_request(observed)
    joined["target_packet_id"] = "dependent-outcome"
    guarded_parallel_member_controls(request, joined)


def guarded_parallel_member_controls(second, joined):
    """Membership grants neither dispatch authority nor permission to close early."""
    def reject(request, code=None):
        before = deepcopy(request)
        result = API.admission(request)
        assert result["status"] == "blocked" and (code is None or result["code"] == code), result
        assert request == before, "Negative grouped admission mutated supplied state"
        if "canonical_progress_state" in result:
            assert result["canonical_progress_state"]["work_ordinal"] == 0, "Rejected member/barrier consumed a cycle"
        return result

    for mutation in ("shared", "unknown", "stale_isolation", "active_target", "actor", "role", "stage", "stale_input", "stale_digest", "authority", "expanded_scope"):
        trial = deepcopy(second)
        carrier = trial["context"]["progress"]
        if mutation in {"shared", "unknown"}: trial["context"]["workspace"]["mode"] = mutation
        elif mutation == "stale_isolation": trial["context"]["workspace"]["isolation"]["accepted-outcome"]["current"] = False
        elif mutation == "active_target": trial["context"]["workspace"]["active_source_writer_ids"].append("dependent-outcome")
        elif mutation == "actor": trial["context"]["writer_actor_ids"]["dependent-outcome"] = "native-writer:substitute"
        elif mutation == "role": trial["worker_role"] = "builder_tester"
        elif mutation == "stage": trial["worker_stage"] = "refactor"
        elif mutation == "stale_input": carrier["action"]["member_scope"]["members"][1]["input_identity"] = {"source": "stale"}
        elif mutation == "stale_digest": carrier["action"]["member_scope"]["members"][1]["packet_definition_digest"] = "0" * 64
        elif mutation == "authority": carrier["resolved_sources"]["scope:coordinated-cycle"]["approved_plan_identity"]["approval_ref"] = "forged"
        else: carrier["action"]["member_scope"]["members"].append({"packet_id": "undeclared", "packet_definition_digest": "0" * 64, "input_identity": {"source": "extra"}})
        reject(trial, "workspace_overlap" if mutation in {"shared", "unknown", "stale_isolation", "active_target"} else None)
    sibling_erased = deepcopy(second)
    sibling_erased["plan"]["implementation_steps"][0]["execution"].pop("action_admission_ref")
    reject(sibling_erased, "progress_replay")  # Dispatching B cannot erase A's committed join.
    reject(joined, "progress_replay")  # A committed PENDING join cannot join twice.
    erased = deepcopy(joined)
    erased["plan"]["implementation_steps"][1]["execution"].pop("action_admission_ref")
    reject(erased)  # Retained previous_plan prevents erasing a committed join.
    continuing = deepcopy(joined)
    continuing.update(worker_stage="production", worker_role="code_writer")
    continuing["plan"]["implementation_steps"][1]["execution"]["state"] = "RUNNING"
    continuing["context"]["packet_evidence"]["dependent-outcome"]["implementation_evidence_ref"] = "writer:observed-member"
    continued = API.admission(continuing)
    assert continued["status"] == "accepted", ("Member stage continuation lost its admission", continued)
    assert continued["canonical_progress_state"] == joined["context"]["progress"]["state"]
    child_only = guarded_parallel_barrier_request(joined)
    child_only["context"]["progress"]["event"].pop("coordinator_barrier_ref")
    reject(child_only)  # Child evidence cannot independently spend a parent cycle.
    partial = guarded_parallel_barrier_request(joined, complete=False)
    blocked = reject(partial)
    assert blocked["canonical_progress_state"] == joined["context"]["progress"]["state"], "Incomplete barrier erased partial member evidence or admission"
    assert len(partial["context"]["progress"]["resolved_sources"][partial["context"]["progress"]["event"]["coordinator_barrier_ref"]]["member_results"]) == 1
    complete = guarded_parallel_barrier_request(joined)
    closed = API.admission(complete)
    assert closed["status"] == "accepted", ("Complete independent member barrier rejected", closed)
    state = closed["canonical_progress_state"]
    assert state["work_ordinal"] == 1 and state["consecutive_no_progress"] == 1 and len(state["history"]) == 1
    assert "action_admission" not in state
    duplicate = deepcopy(complete)
    duplicate["context"]["progress"]["resolved_sources"][duplicate["context"]["progress"]["event"]["coordinator_barrier_ref"]]["member_results"].append(
        deepcopy(duplicate["context"]["progress"]["resolved_sources"][duplicate["context"]["progress"]["event"]["coordinator_barrier_ref"]]["member_results"][0]))
    reject(duplicate)
    guarded_parallel_unblock_and_compaction_controls(second, closed)
    # Closed parent and stale child stage cannot reopen a completed coordinator.
    for pid in ("accepted-outcome", "dependent-outcome"):
        replay = retained_progress_request(closed)
        replay.update(target_packet_id=pid, worker_stage="production", worker_role="code_writer")
        packet = next(p for p in replay["plan"]["implementation_steps"] if p["packet_id"] == pid)
        packet["execution"]["state"] = "RUNNING"
        replay["context"]["workspace"]["active_source_writer_ids"] = []
        replay["context"]["packet_evidence"][pid]["implementation_evidence_ref"] = "writer:observed-closed-member"
        result = API.admission(replay)
        assert result["status"] == "blocked" and result["code"] == "progress_replay", result
        assert result["canonical_progress_state"] == state


def guarded_parallel_unblock_and_compaction_controls(second, closed):
    """One material unblock covers only the fixed group; compaction cannot reopen it."""
    stalled = deepcopy(second)
    stalled["target_packet_id"] = "accepted-outcome"
    carrier = stalled["context"]["progress"]
    state = carrier["state"]
    state.pop("action_admission")
    for packet in stalled["plan"]["implementation_steps"]:
        packet["execution"]["state"] = "PENDING"
        packet["execution"].pop("action_admission_ref", None)
    stalled["context"]["previous_plan"] = deepcopy(stalled["plan"])
    stalled["context"]["workspace"]["active_source_writer_ids"] = []
    for ordinal in range(1, 4):
        ref, assessment = "observation:group-stall:" + str(ordinal), "assessment:group-stall:" + str(ordinal)
        event = {"kind": "work_checkpoint", "event_id": "checkpoint:group-stall:" + str(ordinal),
            "guard_id": state["guard_id"], "outcome_ref": state["outcome_ref"],
            "predecessor_event_id": state["history"][-1]["event_id"] if state["history"] else None,
            "work_ordinal": ordinal, "action_ref": "action:prior-singleton:" + str(ordinal),
            "assessment_ref": assessment, "evidence_refs": [ref], "disposition": "no_progress", "frontier_ref": state["frontier_ref"]}
        carrier["resolved_sources"][ref] = {"result": "failed", "invocation_ref": "green:prior:" + str(ordinal)}
        carrier["resolved_sources"][assessment] = {"event_id": event["event_id"], "disposition": "no_progress",
            "observation_refs": [ref], "frontier_ref": state["frontier_ref"]}
        state["history"].append(event)
        state["evidence_refs"].extend([ref, assessment])
    state.update(work_ordinal=3, consecutive_no_progress=3, status="stagnant")
    scope_ref = carrier["action"]["member_scope"]["source_ref"]
    carrier["resolved_sources"].update({
        "blocker:coordinator": {"blocked_action": carrier["action"]["action_ref"]},
        "change:coordinator": {"change_kind": "capability", "material": True,
            "action_ref": carrier["action"]["action_ref"], "action_scope_ref": scope_ref},
        "observation:group-unblock": {"result": "isolated capability became available"},
        "assessment:group-unblock": {"event_id": "event:group-unblock", "kind": "material_unblock",
            "action_ref": carrier["action"]["action_ref"], "action_scope_ref": scope_ref,
            "changed_ref": "change:coordinator", "resolved_blocker_ref": "blocker:coordinator",
            "observation_refs": ["observation:group-unblock"]}})
    carrier["event"] = {"kind": "material_unblock", "event_id": "event:group-unblock", "guard_id": state["guard_id"],
        "outcome_ref": state["outcome_ref"], "predecessor_event_id": state["history"][-1]["event_id"],
        "work_ordinal": 3, "action_ref": carrier["action"]["action_ref"], "action_scope_ref": scope_ref,
        "assessment_ref": "assessment:group-unblock", "evidence_refs": ["observation:group-unblock"],
        "changed_ref": "change:coordinator", "resolved_blocker_ref": "blocker:coordinator"}
    # A real dispatch gate leaves the independently validated unblock unspent.
    blocked = deepcopy(stalled)
    blocked["context"]["readiness"]["ready"] = False
    result = API.admission(blocked)
    assert result["status"] == "blocked" and result["code"] == "not_ready", result
    assert result["canonical_progress_state"]["status"] == "reactivated"
    assert "action_admission" not in result["canonical_progress_state"]
    for location in ("event", "assessment", "change"):
        trial = deepcopy(stalled)
        progress = trial["context"]["progress"]
        row = (progress["event"] if location == "event" else
               progress["resolved_sources"]["assessment:group-unblock" if location == "assessment" else "change:coordinator"])
        row.pop("action_scope_ref")
        result = API.admission(trial)
        assert result["status"] == "blocked", ("Group unblock lost its fixed scope", location, result)
    first = API.admission(stalled)
    assert first["status"] == "accepted", ("Bound grouped unblock rejected", first)
    admitted = first["canonical_progress_state"]["action_admission"]
    assert admitted["unblock_event_id"] == "event:group-unblock"
    next_member = retained_progress_request(first)
    next_member["target_packet_id"] = "dependent-outcome"
    next_member["plan"]["implementation_steps"][0]["execution"]["state"] = "RUNNING"
    next_member["context"]["previous_plan"] = deepcopy(next_member["plan"])
    next_member["context"]["workspace"]["active_source_writer_ids"] = ["accepted-outcome"]
    joined = API.admission(next_member)
    assert joined["status"] == "accepted", ("Bound sibling attempted second unblock consumption", joined)
    assert joined["canonical_progress_state"] == first["canonical_progress_state"]
    assert joined["canonical_progress_state"]["work_ordinal"] == 3
    assert joined["canonical_progress_state"]["consecutive_no_progress"] == 3
    # Compact the already CLOSED coordinator, retaining its action identity.
    compacted = retained_progress_request(closed)
    compacted.update(worker_stage="production", worker_role="code_writer")
    compacted["plan"]["implementation_steps"][0]["execution"]["state"] = "RUNNING"
    compacted["context"]["workspace"]["active_source_writer_ids"] = []
    compacted["context"]["packet_evidence"]["accepted-outcome"]["implementation_evidence_ref"] = "writer:closed-coordinator"
    progress = compacted["context"]["progress"]
    retained = progress["state"]
    history = deepcopy(retained["history"])
    summary = "history:closed-coordinator"
    progress["resolved_sources"][summary] = {"guard_id": retained["guard_id"], "outcome_ref": retained["outcome_ref"],
        "policy": deepcopy(retained["policy"]), "work_ordinal": 1, "consecutive_no_progress": 1,
        "frontier_ref": retained["frontier_ref"], "last_event_id": history[-1]["event_id"],
        "seen_event_ids": [history[-1]["event_id"]], "seen_action_refs": [history[-1]["action_ref"]],
        "seen_policy_authority_refs": [], "seen_observation_refs": deepcopy(history[-1]["evidence_refs"]),
        "seen_frontier_refs": [retained["frontier_ref"]], "seen_unblock_change_refs": [], "unresolved_oscillation_refs": []}
    retained.update(history=[], history_base_ref=summary)
    retained["evidence_refs"].append(summary)
    result = API.admission(compacted)
    assert result["status"] == "blocked" and result["code"] == "progress_replay", ("Compaction reopened closed coordinator", result)
    assert result["canonical_progress_state"] == retained


def shared_progress_controls():
    """One guard rejects unsafe continuation and preserves productive evidence."""
    total = 0

    def check(request, status, code=None):
        nonlocal total
        before = deepcopy(request)
        result = API.admission(request)
        assert result["status"] == status and (code is None or result["code"] == code), result
        assert request == before, "Shared progress mutated caller state"
        total += 1
        return result

    admitted = check(released_v14_productive_fourth_attempt(), "accepted")
    # A singleton admits approved work, not just a reusable packet/input name.
    definition_failures = []
    # Start a genuinely native v15 branch before admission. Mutating an accepted
    # migrated v14 snapshot would instead exercise its provenance gate.
    native_source = released_v14_productive_fourth_attempt()
    native_source["plan"]["plan_schema_version"] = "15.0"
    seal(native_source)
    native_source["context"]["previous_plan"] = deepcopy(native_source["plan"])
    native_admitted = check(native_source, "accepted")
    approved_packet = native_admitted["canonical_plan"]["implementation_steps"][0]
    approved_digest = API.digest(API.packet_definition(approved_packet))
    for owner, action in (("carrier", native_admitted["canonical_context"]["progress"]["action"]),
                          ("admission", native_admitted["canonical_progress_state"]["action_admission"])):
        if action.get("packet_definition_digest") != approved_digest:
            definition_failures.append(("new canonical " + owner + " lacks approved definition", action))
    # Keep the original migrated-v14 admission independently exercised above;
    # representation normalization changes no approved packet definition.
    assert approved_digest == API.digest(API.packet_definition(admitted["canonical_plan"]["implementation_steps"][0]))
    assert approved_digest == API.digest(API.packet_definition(released_v14_productive_fourth_attempt()["plan"]["implementation_steps"][0]))

    def definition_check(request, status, name, code=None):
        nonlocal total
        before = deepcopy(request)
        result = API.admission(request)
        print("Singleton definition control: " + name + "; observed=" + result["status"] + "/" + result["code"])
        if result["status"] != status or (code is not None and result["code"] != code):
            definition_failures.append((name, status, code, result))
        assert request == before, (name, "Definition admission mutated caller-owned authority")
        total += 1
        return result

    # Construct both versions before normalization: neither approval identity
    # nor the old authority is recovered from the candidate migration output.
    def original_group(version):
        request = valid_request(2)
        request["plan"]["plan_schema_version"] = version
        request["plan"]["implementation_steps"][1]["depends_on"] = []
        seal(request)
        guard, outcome = "guard:original-group", "outcome:original-group"
        action_ref, scope_ref = "action:original-group", "scope:original-group"
        members = [{"packet_id": p["packet_id"], "packet_definition_digest": API.digest(API.packet_definition(p)),
                    "input_identity": deepcopy(p["execution"]["input_identity"])}
                   for p in request["plan"]["implementation_steps"]]
        identity = deepcopy(request["plan"]["approved_plan_identity"])
        request["context"]["progress"] = {
            "state": {"schema_version": "1.0", "guard_id": guard, "outcome_ref": outcome,
                "policy": {"policy_id": "shared-stagnation-v1", "stagnation_window": 3, "source_ref": "policy:original-group"},
                "work_ordinal": 0, "consecutive_no_progress": 0, "status": "active",
                "baseline_ref": "frontier:original-group", "frontier_ref": "frontier:original-group", "history": [], "evidence_refs": []},
            "action": {"action_ref": action_ref, "packet_id": members[0]["packet_id"],
                "input_identity": deepcopy(members[0]["input_identity"]),
                "member_scope": {"source_ref": scope_ref, "members": deepcopy(members)}},
            "resolved_sources": {
                "frontier:original-group": {"accepted_obligations": [], "unresolved": ["both outcomes"]},
                "policy:original-group": {"policy_id": "shared-stagnation-v1", "stagnation_window": 3,
                    "authority_ref": identity["approval_ref"]},
                outcome: {"task_identity": request["plan"]["task_identity"], "intended_outcome": "Preserve accepted behavior"},
                scope_ref: {"kind": "coordinator_action_scope", "guard_id": guard, "outcome_ref": outcome,
                    "action_ref": action_ref, "approved_plan_identity": deepcopy(identity), "members": deepcopy(members),
                    "grouping_decision_ref": "decision:original-group"},
                "decision:original-group": {"approved_plan_identity": deepcopy(identity),
                    "reason": "Independently approved packets form one coordinator cycle"},
                "unrelated:original-group": {"approved_plan_identity": deepcopy(identity), "note": "Not grouping authority"}}}
        for packet in request["plan"]["implementation_steps"]:
            packet["execution"].update(progress_guard_ref=guard, action_ref=action_ref)
        request["context"]["previous_plan"] = deepcopy(request["plan"])
        return request

    for version in ("14.0", "15.0"):
        original = original_group(version)
        expected_identity = {**original["plan"]["approved_plan_identity"],
                             "definition_digest": API.digest(expected_current_definition(original["plan"]))}
        carrier = original["context"]["progress"]
        source_refs = ("scope:original-group", "decision:original-group")
        result = definition_check(original, "accepted", version + " independently approved grouped dispatch")
        if result["status"] == "accepted":
            canonical = result["canonical_plan"]
            assert_current_approval(original["plan"], canonical)
            assert API.definition(canonical) == expected_current_definition(original["plan"])
            current = result["canonical_context"]["progress"]
            for ref in source_refs:
                expected = {**deepcopy(carrier["resolved_sources"][ref]), "approved_plan_identity": expected_identity}
                assert current["resolved_sources"][ref] == expected, (version, ref, "Only approved representation identity may change")
            assert current["resolved_sources"]["unrelated:original-group"] == carrier["resolved_sources"]["unrelated:original-group"]
            assert current["action"] == carrier["action"]
            expected_state = deepcopy(carrier["state"])
            expected_state["action_admission"] = deepcopy(result["canonical_progress_state"]["action_admission"])
            assert result["canonical_progress_state"] == expected_state
            for old, new in zip(original["plan"]["implementation_steps"], canonical["implementation_steps"]):
                expected_execution = deepcopy(old["execution"])
                if old["packet_id"] == original["target_packet_id"]:
                    expected_execution["action_admission_ref"] = expected_state["action_admission"]["admission_ref"]
                assert new["execution"] == expected_execution
            assert result["canonical_context"]["current_input_identities"] == original["context"]["current_input_identities"]
        for mutation in ("scope-identity", "decision-identity", "both-identities", "member", "input", "unapproved"):
            changed = deepcopy(original)
            sources = changed["context"]["progress"]["resolved_sources"]
            for ref in source_refs:
                if mutation == "both-identities" or mutation == ("scope-identity" if ref == source_refs[0] else "decision-identity"):
                    sources[ref]["approved_plan_identity"]["approval_ref"] = "approval:foreign-group"
            if mutation == "member":
                sources[source_refs[0]]["members"][1]["packet_definition_digest"] = "foreign-member-definition"
            elif mutation == "input":
                changed["context"]["progress"]["action"]["member_scope"]["members"][1]["input_identity"] = {"source": "foreign-input"}
            elif mutation == "unapproved":
                changed["plan"]["implementation_steps"][0]["acceptance_criteria"].append("Unapproved outcome")
            definition_check(changed, "blocked", version + " group rejects " + mutation,
                             "definition_mismatch" if mutation == "unapproved" else "progress_mismatch")

        # These arbitrary objects are literal history, despite pair-shaped
        # fields. Keep live migration and generic-history defects in the same
        # deferred assertion owner so the RED observation reaches both.
        generic = deepcopy(released_v14_productive_fourth_attempt() if version == "14.0" else native_source)
        rows = [{"event_id": "note:bare", "evidence_ref": "evidence:bare"},
                {"kind": "note", "event_id": "note:kind", "evidence_ref": "evidence:kind"},
                {"kind": "worker_stage_result", "event_id": "note:worker-kind", "evidence_ref": "evidence:worker-kind"},
                {"worker_stage": "production", "state": "RUNNING", "event_id": "note:stage", "evidence_ref": "evidence:stage"}]
        for plan in (generic["plan"], generic["context"]["previous_plan"]):
            plan["implementation_steps"][0]["execution"]["history"].extend(deepcopy(rows))
        result = definition_check(generic, "accepted", version + " guarded dispatch preserves generic history literally")
        if result["status"] == "accepted":
            for plan in (result["canonical_plan"], result["canonical_context"]["previous_plan"]):
                assert plan["implementation_steps"][0]["execution"]["history"] == generic["plan"]["implementation_steps"][0]["execution"]["history"]
        for field in ("event_id", "evidence_ref"):
            for malformed in (None, "", " "):
                marked = deepcopy(released_v14_productive_fourth_attempt() if version == "14.0" else native_source)
                row = {"kind": "work_checkpoint", "event_id": "checkpoint:malformed", "evidence_ref": "assessment:malformed"}
                if malformed is None:
                    row.pop(field)
                else:
                    row[field] = malformed
                marked["plan"]["implementation_steps"][0]["execution"]["history"].append(row)
                marked["context"]["previous_plan"] = deepcopy(marked["plan"])
                definition_check(marked, "blocked", version + " explicit checkpoint rejects " + field + "=" + repr(malformed))

    running = retained_progress_request(native_admitted)
    running.update(worker_stage="production", worker_role="code_writer")
    packet = running["plan"]["implementation_steps"][0]
    packet["execution"]["state"] = "RUNNING"
    running["context"]["packet_evidence"][packet["packet_id"]] = evidence(running, packet)
    for retained_previous in (True, False):
        unchanged = deepcopy(running)
        if not retained_previous:
            unchanged["context"].pop("previous_plan")
        result = definition_check(unchanged, "accepted", "unchanged RUNNING definition previous=" + str(retained_previous))
        if result["status"] == "accepted":
            assert result["canonical_progress_state"] == native_admitted["canonical_progress_state"]
    for mutation in ("scope", "specification", "verification", "plan-version", "approval", "plan-metadata"):
        changed = deepcopy(running)
        changed["context"].pop("previous_plan")
        packet = changed["plan"]["implementation_steps"][0]
        if mutation == "scope":
            packet["files_to_modify"].append("independently-reapproved.py")
        elif mutation == "specification":
            packet["description"] = "Independently reapproved different packet result"
        elif mutation == "verification":
            decision = changed["context"]["verification_decision"]
            decision["checks"][0]["command"]["argv"][-1] = "independently reapproved check"
            ref = changed["context"]["verification_decision_ref"]
            ref["sha256"] = API.digest(decision)
            changed["plan"]["verification_decision_ref"] = deepcopy(ref)
            packet["verification_decision_ref"] = deepcopy(ref)
            packet["verification_command"] = deepcopy(decision["checks"][0]["command"]["argv"])
        elif mutation == "plan-version":
            changed["plan"]["plan_version"] = "independently-reapproved-version"
        elif mutation == "plan-metadata":
            changed["plan"]["description"] = "Unrelated approved plan metadata"
        seal(changed)
        if mutation == "approval":
            for owner in (changed["plan"], changed["context"]):
                owner["approved_plan_identity"]["approval_ref"] = "approval:independent-metadata-change"
            changed["context"]["test_applicability"] = {packet["packet_id"]: applicability(changed, packet)}
        changed["context"]["packet_evidence"][packet["packet_id"]] = evidence(changed, packet)
        material = mutation in {"scope", "specification", "verification"}
        assert (API.digest(API.packet_definition(packet)) != approved_digest) == material
        result = definition_check(changed, "blocked" if material else "accepted",
                                  "reapproved " + mutation + " cannot change admitted work" if material else "metadata-only " + mutation,
                                  "progress_mismatch" if material else None)
        if not material and result["status"] == "accepted":
            assert result["canonical_progress_state"] == native_admitted["canonical_progress_state"]
    explicit = deepcopy(native_source)
    explicit["context"]["progress"]["action"]["packet_definition_digest"] = approved_digest
    definition_check(explicit, "accepted", "matching explicit definition admits unchanged work")
    contradictory = deepcopy(native_source)
    contradictory["context"]["progress"]["action"]["packet_definition_digest"] = "0" * 64
    definition_check(contradictory, "blocked", "explicit new-action definition cannot contradict approved work", "progress_mismatch")
    # A readable legacy live admission has unknown historical definition. Only
    # the independently retained original packet can reconstruct that authority.
    unknown = deepcopy(running)
    for action in (unknown["context"]["progress"]["action"], unknown["context"]["progress"]["state"]["action_admission"]):
        action.pop("packet_definition_digest", None)
    unknown["context"]["previous_plan"] = deepcopy(unknown["plan"])
    read = deepcopy(unknown)
    read["boundary"] = "plan"
    definition_check(read, "accepted", "unbound legacy live admission remains readable")
    definition_check(unknown, "blocked", "legacy live continuation cannot infer missing definition", "progress_history_missing")
    reconstructed = deepcopy(unknown)
    for action in (reconstructed["context"]["progress"]["action"], reconstructed["context"]["progress"]["state"]["action_admission"]):
        action["packet_definition_digest"] = approved_digest
    recovered = definition_check(reconstructed, "accepted", "independently archived live definition reconstruction")
    if recovered["status"] == "accepted":
        for field in ("guard_id", "work_ordinal", "consecutive_no_progress", "history", "frontier_ref"):
            assert recovered["canonical_progress_state"][field] == native_admitted["canonical_progress_state"][field]
    current = retained_progress_request(admitted)
    # Productive evidence survives ALL subsequent blockers; none consumes an
    # action or creates a checkpoint for waiting/unfinished asynchronous work.
    for productive in (False, True):
        completed = completed_progress_cycle(current, "useful_new_evidence" if productive else "no_progress")
        for blocker in ("readiness", "authority", "workspace", "stage", "projection"):
            trial = deepcopy(completed)
            if blocker == "readiness": trial["context"]["readiness"]["ready"] = False
            elif blocker == "authority": trial["context"]["approved_plan_identity"]["approval_ref"] = "forged"
            elif blocker == "workspace": trial["context"]["workspace"]["active_source_writer_ids"] = ["accepted-outcome"]
            elif blocker == "stage": trial.update(worker_stage="refactor", worker_role="code_writer")
            else: trial["current_task_packet"] = {"forged": True}
            result = check(trial, "blocked")
            progress = result["canonical_progress_state"]
            assert progress["work_ordinal"] == 4 and progress["consecutive_no_progress"] == (0 if productive else 1)
            assert progress["history"][-1]["event_id"] == completed["context"]["progress"]["event"]["event_id"]
            assert "action_admission" not in progress
    for mutation in ("count", "boolean", "policy", "history", "assessment", "novelty"):
        trial = deepcopy(current)
        carrier = trial["context"]["progress"]
        if mutation == "count": carrier["state"]["consecutive_no_progress"] = 2
        elif mutation == "boolean": carrier["state"]["work_ordinal"] = True
        elif mutation == "policy": carrier["state"]["policy"]["stagnation_window"] = 100
        elif mutation == "history": carrier["state"]["history"].pop(0)
        elif mutation == "assessment": carrier["resolved_sources"].pop("assessment:productive:2")
        else:
            # Candidate prose cannot turn a recurring frontier into a gain.
            trial = completed_progress_cycle(current)
            trial["context"]["progress"]["event"]["disposition"] = "verified_gain"
        check(trial, "blocked")
    # Fresh observation/frontier names cannot turn a restored old acceptance
    # state into new progress. The simpler recurring-ref case cannot catch this.
    lost = completed_progress_cycle(current)
    carrier = lost["context"]["progress"]
    event = carrier["event"]
    carrier["resolved_sources"]["frontier:lost"] = {"accepted_obligations": ["scope", "focused"]}
    event["frontier_ref"] = "frontier:lost"
    carrier["resolved_sources"][event["assessment_ref"]]["frontier_ref"] = "frontier:lost"
    restored = completed_progress_cycle(retained_progress_request(check(lost, "accepted")))
    carrier = restored["context"]["progress"]
    event = carrier["event"]
    carrier["resolved_sources"]["frontier:renamed-restoration"] = {"accepted_obligations": ["scope", "focused", "integration"]}
    event.update(disposition="verified_gain", frontier_ref="frontier:renamed-restoration")
    carrier["resolved_sources"][event["assessment_ref"]].update(disposition="verified_gain", frontier_ref=event["frontier_ref"])
    carrier["resolved_sources"][event["evidence_refs"][0]].update(result="passed", newly_verified_obligations=["integration"])
    check(restored, "blocked")
    replay = deepcopy(current)
    replay["context"]["progress"]["event"] = deepcopy(replay["context"]["progress"]["state"]["history"][-1])
    check(replay, "blocked", "progress_replay")
    # Three net-unproductive A/B cycles include mandatory fresh rechecks. They
    # cross phase boundaries and are NOT six separate verification/reset cycles.
    for index, phase in enumerate(("Build", "Review", "QA"), 1):
        completed = completed_progress_cycle(current, phase=phase)
        result = check(completed, "accepted" if index < 3 else "blocked", None if index < 3 else "progress_stagnant")
        assert result["canonical_progress_state"]["consecutive_no_progress"] == index
        if index < 3:
            current = retained_progress_request(result)
    stalled = deepcopy(completed)
    stalled["context"]["progress"]["state"] = deepcopy(result["canonical_progress_state"])
    stalled["context"]["progress"].pop("event")
    check(stalled, "blocked", "progress_stagnant")  # Generic continuation cannot reopen it.
    # Genuine new information permits only its bound action, never a new window.
    carrier = stalled["context"]["progress"]
    state = carrier["state"]
    carrier["resolved_sources"].update({
        "blocker:missing-capability": {"blocked_action": carrier["action"]["action_ref"]},
        "change:capability": {"change_kind": "capability", "material": True, "action_ref": carrier["action"]["action_ref"]},
        "observation:capability": {"result": "capability now available"},
        "assessment:unblock": {"event_id": "event:unblock", "kind": "material_unblock",
            "action_ref": carrier["action"]["action_ref"], "changed_ref": "change:capability",
            "resolved_blocker_ref": "blocker:missing-capability", "observation_refs": ["observation:capability"]}})
    carrier["event"] = {"kind": "material_unblock", "event_id": "event:unblock", "guard_id": state["guard_id"],
        "outcome_ref": state["outcome_ref"], "predecessor_event_id": state["history"][-1]["event_id"],
        "work_ordinal": state["work_ordinal"], "action_ref": carrier["action"]["action_ref"],
        "assessment_ref": "assessment:unblock", "evidence_refs": ["observation:capability"],
        "changed_ref": "change:capability", "resolved_blocker_ref": "blocker:missing-capability"}
    for blocker in ("readiness", "workspace", "projection"):
        trial = deepcopy(stalled)
        if blocker == "readiness": trial["context"]["readiness"]["route_clear"] = False
        elif blocker == "workspace": trial["context"]["workspace"]["active_source_writer_ids"] = ["accepted-outcome"]
        else: trial["current_task_packet"] = {"forged": True}
        result = check(trial, "blocked")
        progress = result["canonical_progress_state"]
        assert progress["status"] == "reactivated" and progress["consecutive_no_progress"] == 3
        assert "action_admission" not in progress
        pending_unblock = deepcopy(stalled)
        pending_unblock["context"]["progress"]["state"] = deepcopy(progress)
        pending_unblock["context"]["progress"].pop("event")
    changed = deepcopy(stalled)
    changed["context"]["progress"]["resolved_sources"]["change:capability"]["material"] = False
    check(changed, "blocked")
    result = check(stalled, "accepted")
    progress = result["canonical_progress_state"]
    assert progress["consecutive_no_progress"] == 3 and progress["work_ordinal"] == state["work_ordinal"]
    assert progress["action_admission"]["unblock_event_id"] == "event:unblock"
    policy_history_controls(pending_unblock, result)
    committed = retained_progress_request(result)
    check(committed, "blocked", "progress_replay")  # Same NEW action cannot spend it again.
    continuing = deepcopy(committed)
    continuing["plan"]["implementation_steps"][0]["execution"]["state"] = "RUNNING"
    continuing.update(worker_stage="production", worker_role="code_writer")
    continuing["context"]["packet_evidence"]["accepted-outcome"]["implementation_evidence_ref"] = "writer:observed-unblock-production"
    continued = check(continuing, "accepted")
    assert continued["canonical_progress_state"] == progress  # No second consumption/checkpoint.
    unproductive = completed_progress_cycle(committed)
    stopped = check(unproductive, "blocked", "progress_stagnant")
    assert stopped["canonical_progress_state"]["consecutive_no_progress"] == 4
    productive = completed_progress_cycle(committed, "useful_new_evidence", "debugging")
    continued = check(productive, "accepted")
    assert continued["canonical_progress_state"]["consecutive_no_progress"] == 0
    assert continued["canonical_progress_state"]["status"] == "active"
    # Productive work beyond ten rounds retains the same guard and no cap.
    current = retained_progress_request(continued)
    for _ in range(12):
        current = retained_progress_request(check(completed_progress_cycle(current, "useful_new_evidence", "research"), "accepted"))
    assert current["context"]["progress"]["state"]["guard_id"] == state["guard_id"]
    assert current["context"]["progress"]["state"]["consecutive_no_progress"] == 0
    # Compaction retains independently resolved semantic history, novelty and
    # unresolved oscillation refs; it never creates a fresh window or quota.
    compacted = deepcopy(current)
    carrier = compacted["context"]["progress"]
    retained = carrier["state"]
    prior_event = deepcopy(retained["history"][-1])
    summary_ref = "history:compacted:retained"
    carrier["resolved_sources"][summary_ref] = {
        "guard_id": retained["guard_id"], "outcome_ref": retained["outcome_ref"], "policy": deepcopy(retained["policy"]),
        "work_ordinal": retained["work_ordinal"], "consecutive_no_progress": retained["consecutive_no_progress"],
        "frontier_ref": retained["frontier_ref"], "last_event_id": prior_event["event_id"],
        "seen_event_ids": [row["event_id"] for row in retained["history"]],
        "seen_action_refs": list(dict.fromkeys(row["action_ref"] for row in retained["history"] if row["kind"] == "work_checkpoint")),
        "seen_policy_authority_refs": [],
        "seen_observation_refs": list(dict.fromkeys(ref for row in retained["history"] for ref in row["evidence_refs"])),
        "seen_frontier_refs": list(dict.fromkeys(row["frontier_ref"] for row in retained["history"] if "frontier_ref" in row)),
        "seen_unblock_change_refs": [row["changed_ref"] for row in retained["history"] if row["kind"] == "material_unblock"],
        "unresolved_oscillation_refs": ["observation:cycle:4", "observation:cycle:5", "observation:cycle:6"]}
    retained.update(history=[], history_base_ref=summary_ref)
    retained["evidence_refs"].append(summary_ref)
    compacted["plan"]["implementation_steps"][0]["execution"]["state"] = "RUNNING"
    compacted.update(worker_stage="production", worker_role="code_writer")
    compacted["context"]["packet_evidence"]["accepted-outcome"]["implementation_evidence_ref"] = "writer:observed-research-production"
    compact = check(compacted, "accepted")
    assert compact["canonical_progress_state"]["work_ordinal"] == retained["work_ordinal"]
    assert compact["canonical_progress_state"]["history_base_ref"] == summary_ref
    compacted["context"]["progress"]["event"] = prior_event
    check(compacted, "blocked", "progress_replay")
    assert not definition_failures, ("Singleton admitted-definition controls", definition_failures)
    return total


def restored_completed_action_history_uniqueness():
    """OG-GUARD-HISTORY: distinct event IDs cannot complete one action twice."""
    failures = []
    for compacted in (False, True):
        # Reuse independently fixed released-v14 history. The approved Plan and
        # all original observations/frontiers remain unchanged by the mutation.
        unique = released_v14_productive_fourth_attempt()
        unique["boundary"] = "plan"
        carrier = unique["context"]["progress"]
        state = carrier["state"]
        first = deepcopy(state["history"][0])
        if compacted:
            summary_ref = "history:completed-action:base"
            carrier["resolved_sources"][summary_ref] = {
                "guard_id": state["guard_id"], "outcome_ref": state["outcome_ref"],
                "policy": deepcopy(state["policy"]), "work_ordinal": 1, "consecutive_no_progress": 0,
                "frontier_ref": first["frontier_ref"], "last_event_id": first["event_id"],
                "last_semantic_kind": "work_checkpoint", "seen_event_ids": [first["event_id"]],
                "seen_action_refs": [first["action_ref"]], "seen_policy_authority_refs": [],
                "seen_observation_refs": deepcopy(first["evidence_refs"]),
                "seen_frontier_refs": [state["baseline_ref"], first["frontier_ref"]],
                "seen_unblock_change_refs": [], "unresolved_oscillation_refs": []}
            state.update(history=state["history"][1:], history_base_ref=summary_ref)
            state["evidence_refs"].append(summary_ref)
        before = deepcopy(unique)
        positive = API.admission(unique)
        assert unique == before, "Unique restoration mutated independent input"
        assert positive["status"] == "accepted", (
            "Unique-action restoration fixture failed; not authorizing RED", compacted,
            {"expected_status": "accepted", "status": positive["status"], "code": positive.get("code")})
        restored = positive["canonical_progress_state"]
        assert restored["work_ordinal"] == 3 and restored["consecutive_no_progress"] == 0
        assert restored["frontier_ref"] == "frontier:productive:3"

        repeated = deepcopy(unique)
        history = repeated["context"]["progress"]["state"]["history"]
        duplicate = history[0 if compacted else 1]
        assert duplicate["event_id"] != first["event_id"]
        assert duplicate["evidence_refs"] != first["evidence_refs"]
        assert duplicate["action_ref"] != first["action_ref"]
        duplicate["action_ref"] = first["action_ref"]  # The ONLY negative mutation.
        before = deepcopy(repeated)
        observed = API.admission(repeated)
        assert repeated == before, "Duplicate restoration mutated caller-owned history"
        if observed["status"] == "accepted" or observed.get("code") == "progress_stagnant":
            failures.append({"history": "compacted_base_collision" if compacted else "distinct_event_collision",
                             "expected_code": "progress_replay", "status": observed["status"], "code": observed.get("code"),
                             "work_ordinal": observed.get("canonical_progress_state", {}).get("work_ordinal"),
                             "consecutive_no_progress": observed.get("canonical_progress_state", {}).get("consecutive_no_progress")})
        else:
            assert observed["status"] == "blocked" and observed["code"] == "progress_replay", (
                "Completed-action uniqueness failed for an unrelated reason; not authorizing RED", compacted,
                {"expected_status": "blocked", "expected_code": "progress_replay",
                 "status": observed["status"], "code": observed.get("code")})
    assert not failures, ("Restored completed action counted twice instead of rejected as progress_replay", failures)


def completion_progress_closure_controls():
    """Final completion closes admitted cycles; intermediate verification need not."""
    failures = []
    total = 0

    def check(request, status, name, code=None):
        nonlocal total
        before = deepcopy(request)
        result = API.admission(request)
        print("Completion progress control: " + name + "; observed=" + result["status"] + "/" + result["code"]
              + "; required=" + status + ("/" + code if code else ""))
        if result["status"] != status or (code is not None and result["code"] != code):
            failures.append((name, status, code, result))
        assert request == before, (name, "Admission mutated caller-owned progress or execution")
        total += 1
        return result

    def completion(request):
        trial = verify_all(deepcopy(request))
        trial["boundary"] = "completion"
        context = trial["context"]
        context.update(current_snapshot_identity="snapshot:completion", required_terminal_gates=["independent_review"])
        context["workspace"]["active_source_writer_ids"] = []
        context["completion_evidence"] = {
            "approved_plan_identity": deepcopy(trial["plan"]["approved_plan_identity"]),
            "snapshot_identity": "snapshot:completion", "acceptance_results": [],
            "validation_results": [{"selected_check_ids": ["integrated"], "binding_obligation_refs": [],
                "result": "passed", "evidence_ref": "integration:completion",
                "procedure": "Inspect the current integrated acceptance evidence"}],
            "terminal_gates": {"independent_review": {"passed": True, "after_integration": True,
                "snapshot_identity": "snapshot:completion", "evidence_ref": "review:completion"}}}
        return trial

    def compact(request, inventory=None):
        trial = deepcopy(request)
        carrier = trial["context"]["progress"]
        state = carrier["state"]
        history = state["history"]
        base = carrier["resolved_sources"].get(state.get("history_base_ref"), {})
        summary_ref = "history:completion:compacted:" + str(state["work_ordinal"])
        summary = {"guard_id": state["guard_id"], "outcome_ref": state["outcome_ref"],
            "policy": deepcopy(state["policy"]), "work_ordinal": state["work_ordinal"],
            "consecutive_no_progress": state["consecutive_no_progress"], "frontier_ref": state["frontier_ref"],
            "last_event_id": history[-1]["event_id"], "last_semantic_kind": history[-1]["kind"],
            "seen_event_ids": [row["event_id"] for row in history],
            "seen_action_refs": [row["action_ref"] for row in history if row["kind"] == "work_checkpoint"],
            "seen_policy_authority_refs": [],
            "seen_observation_refs": list(dict.fromkeys(ref for row in history for ref in row["evidence_refs"])),
            "seen_frontier_refs": list(dict.fromkeys([state["baseline_ref"]] + [row["frontier_ref"] for row in history])),
            "seen_unblock_change_refs": [], "unresolved_oscillation_refs": []}
        for field in ("seen_event_ids", "seen_action_refs", "seen_policy_authority_refs", "seen_observation_refs",
                      "seen_frontier_refs", "seen_unblock_change_refs", "unresolved_oscillation_refs"):
            summary[field] = list(dict.fromkeys(base.get(field, []) + summary[field]))
        bindings = {row["action_ref"]: deepcopy(row) for row in base.get("closed_admissions", [])}
        for row in history:
            if "closed_admission" in row:
                binding = deepcopy(row["closed_admission"])
                bindings[binding["action_ref"]] = binding
        if bindings or "closed_admissions" in base:
            summary["closed_admissions"] = list(bindings.values())
        if inventory is not None:
            summary["seen_resolved_uncertainty_refs"] = list(inventory)
        carrier["resolved_sources"][summary_ref] = summary
        state.update(history=[], history_base_ref=summary_ref)
        state["evidence_refs"].append(summary_ref)
        return trial

    def cycle(request, disposition="no_progress"):
        trial = completed_progress_cycle(request, disposition)
        carrier = trial["context"]["progress"]
        state = carrier["state"]
        if not state["history"] and "history_base_ref" in state:
            carrier["event"]["predecessor_event_id"] = carrier["resolved_sources"][state["history_base_ref"]]["last_event_id"]
        return trial

    def resolve_again(request, uncertainty):
        trial = cycle(request, "useful_new_evidence")
        carrier = trial["context"]["progress"]
        carrier["resolved_sources"][carrier["event"]["assessment_ref"]]["resolved_uncertainty_ref"] = uncertainty
        return trial

    def incomplete_assessment(event_id, form):
        return {"empty": {}, "event-only": {"event_id": event_id},
                "mismatched": {"event_id": "foreign:" + event_id, "disposition": "no_progress"},
                "unknown": {"event_id": event_id, "disposition": "unknown"}}[form]

    def check_lineage(request, identity, admission_ref, location, name):
        nonlocal total
        carrier = request["context"]["progress"]
        state = API.PROGRESS.ProgressState.parse(carrier["state"], carrier["resolved_sources"])
        found = state.action_lineage(API.PROGRESS.ActionIdentity.parse(identity), admission_ref, carrier["resolved_sources"])
        print("Closed binding control: " + name + "; observed=" + found.location + "; required=" + location)
        if found.location != location:
            failures.append((name, location, found))
        total += 1

    predispatch = released_v14_productive_fourth_attempt()
    legacy_completion = completion(predispatch)
    closed_legacy_action = predispatch["context"]["progress"]["state"]["history"][-1]["action_ref"]
    legacy_completion["plan"]["implementation_steps"][0]["execution"]["action_ref"] = closed_legacy_action
    assert legacy_completion["context"]["previous_plan"]["implementation_steps"][0]["execution"]["state"] == "PENDING"
    assert legacy_completion["context"]["previous_plan"]["implementation_steps"][0]["execution"]["action_ref"] == predispatch["context"]["progress"]["action"]["action_ref"] != closed_legacy_action
    for plan in (legacy_completion["plan"], legacy_completion["context"]["previous_plan"]):
        assert all("action_admission_ref" not in packet["execution"] for packet in plan["implementation_steps"])
    # These synthetic checkpoints prove action history, but never recorded an
    # admission identity or packet/input binding for the declared old action.
    assert all("admission_ref" not in row and "closed_admission" not in row
               for row in predispatch["context"]["progress"]["state"]["history"])
    check(legacy_completion, "blocked", "synthetic legacy marked completion needs actual historical admission authority",
          "progress_history_missing")
    for form in ("full", "compacted"):
        unrecorded = completion(predispatch)
        unmarked = deepcopy(legacy_completion)
        for plan in (unmarked["plan"], unmarked["context"]["previous_plan"]):
            for packet in plan["implementation_steps"]:
                for field in ("progress_guard_ref", "action_ref"):
                    packet["execution"].pop(field, None)
        if form == "compacted":
            unrecorded, unmarked = compact(unrecorded), compact(unmarked)
        check(unrecorded, "blocked", form + " VERIFIED no-pair action must have recorded closure", "progress_history_missing")
        accepted = check(unmarked, "accepted", form + " genuinely unmarked legacy completion remains valid")
        assert accepted["status"] == "accepted", "Unmarked legacy history must not acquire a synthetic admission requirement"
    # Explicit resolved checkpoint witnesses, unlike legacy totals, cannot be
    # discarded by supplying an internally valid but incomplete progress state.
    for retained_count in (0, 1, 2):
        omitted = deepcopy(predispatch)
        state = omitted["context"]["progress"]["state"]
        state["history"] = state["history"][:retained_count]
        state.update(work_ordinal=retained_count,
                     frontier_ref=state["history"][-1]["frontier_ref"] if retained_count else state["baseline_ref"],
                     evidence_refs=[ref for row in state["history"] for ref in row["evidence_refs"] + [row["assessment_ref"]]])
        assert omitted["plan"] == predispatch["plan"]
        assert omitted["context"]["previous_plan"] == predispatch["context"]["previous_plan"]
        check(omitted, "blocked", "retained checkpoint witnesses reject lineage retaining " + str(retained_count),
              "progress_history_missing")
        omitted_completion = completion(omitted)
        omitted_completion["plan"]["implementation_steps"][0]["execution"]["action_ref"] = closed_legacy_action
        assert omitted_completion["plan"] == legacy_completion["plan"]
        assert omitted_completion["context"]["previous_plan"] == legacy_completion["context"]["previous_plan"]
        assert omitted_completion["context"]["progress"]["resolved_sources"] == legacy_completion["context"]["progress"]["resolved_sources"]
        check(omitted_completion, "blocked", "legacy completion cannot omit retained checkpoints after " + str(retained_count),
              "progress_history_missing")
        for resolution in ("missing", "unresolved", "empty", "event-only", "mismatched", "unknown"):
            unavailable = deepcopy(omitted)
            sources = unavailable["context"]["progress"]["resolved_sources"]
            for checkpoint in predispatch["context"]["progress"]["state"]["history"][retained_count:]:
                if resolution == "missing":
                    sources.pop(checkpoint["assessment_ref"])
                elif resolution == "unresolved":
                    sources[checkpoint["assessment_ref"]] = None
                else:
                    sources[checkpoint["assessment_ref"]] = incomplete_assessment(checkpoint["event_id"], resolution)
            assert unavailable["plan"] == predispatch["plan"]
            assert unavailable["context"]["previous_plan"] == predispatch["context"]["previous_plan"]
            check(unavailable, "blocked", resolution + " assessment cannot hide uncovered witnesses after " + str(retained_count),
                  "progress_history_missing")
            unavailable_completion = completion(unavailable)
            unavailable_completion["plan"]["implementation_steps"][0]["execution"]["action_ref"] = closed_legacy_action
            check(unavailable_completion, "blocked", resolution + " assessment cannot hide completion witnesses after " + str(retained_count),
                  "progress_history_missing")
        if retained_count == 0:
            initial_baseline = deepcopy(omitted)
    # No explicit checkpoint witness remains in this independently supplied
    # baseline. A historical total alone does not establish completed cycles.
    for plan in (initial_baseline["plan"], initial_baseline["context"]["previous_plan"]):
        execution = plan["implementation_steps"][0]["execution"]
        execution.update(history=[], evidence_refs=[])
    totals_only = check(initial_baseline, "accepted", "legacy totals alone do not invent semantic cycles")
    assert totals_only["canonical_progress_state"]["work_ordinal"] == 0
    for plan in (initial_baseline["plan"], initial_baseline["context"]["previous_plan"]):
        plan["implementation_steps"][0]["execution"]["recovery"] = {"attempt_count": 0, "no_progress_count": 0}
    initial_baseline["context"]["recovery_counters"]["accepted-outcome"] = {"attempt_count": 0, "no_progress_count": 0}
    baseline = check(initial_baseline, "accepted", "known initial baseline admits without invented checkpoints")
    assert baseline["canonical_progress_state"]["work_ordinal"] == 0
    # Generic producer notes carry evidence/invalidation fields, without
    # manufacturing a completed-event witness or a private classifier protocol.
    informational = valid_request()
    execution = informational["plan"]["implementation_steps"][0]["execution"]
    execution["history"].append({"state": execution["state"], "input_identity": deepcopy(execution["input_identity"]),
                                 "evidence_refs": ["runtime:status-note"], "reason": "Runtime status recorded before work starts"})
    execution["evidence_refs"].append("runtime:status-note")
    informational["context"]["previous_plan"] = deepcopy(informational["plan"])
    nonsemantic = check(informational, "accepted", "generic history note requires no invented semantic checkpoint")
    assert "canonical_progress_state" not in nonsemantic
    covered = check(compact(predispatch), "accepted", "compacted event inventory covers retained checkpoint witnesses")
    assert covered["canonical_progress_state"]["work_ordinal"] == 3
    archived = compact(predispatch)
    for checkpoint in predispatch["context"]["progress"]["state"]["history"]:
        archived["context"]["progress"]["resolved_sources"].pop(checkpoint["assessment_ref"])
    covered = check(archived, "accepted", "validated compacted membership needs no archived assessment reload")
    assert covered["canonical_progress_state"]["work_ordinal"] == 3
    archived_completion = completion(archived)
    archived_completion["plan"]["implementation_steps"][0]["execution"]["action_ref"] = closed_legacy_action
    check(archived_completion, "blocked", "compacted synthetic action membership alone cannot certify marked completion",
          "progress_history_missing")
    # Fix no-progress observations before evaluating either carrier; the
    # negative retains those same explicit current/previous checkpoint records.
    stalled = deepcopy(predispatch)
    carrier = stalled["context"]["progress"]
    state = carrier["state"]
    state.update(frontier_ref=state["baseline_ref"], consecutive_no_progress=3, status="stagnant")
    for checkpoint in state["history"]:
        checkpoint.update(disposition="no_progress", frontier_ref=state["baseline_ref"])
        carrier["resolved_sources"][checkpoint["assessment_ref"]].update(disposition="no_progress", frontier_ref=state["baseline_ref"])
        for ref in checkpoint["evidence_refs"]:
            carrier["resolved_sources"][ref] = {"result": "failed", "before_frontier_ref": state["baseline_ref"],
                                               "after_frontier_ref": state["baseline_ref"]}
    retained_stall = check(stalled, "blocked", "three retained no-progress cycles block corrective admission", "progress_stagnant")
    assert retained_stall["canonical_progress_state"]["work_ordinal"] == 3
    assert retained_stall["canonical_progress_state"]["consecutive_no_progress"] == 3
    unknown_stall = deepcopy(stalled)
    carrier = unknown_stall["context"]["progress"]
    for checkpoint in carrier["state"]["history"]:
        carrier["resolved_sources"].pop(checkpoint["assessment_ref"])
    carrier["state"].update(history=[], evidence_refs=[], work_ordinal=0, consecutive_no_progress=0, status="active")
    assert unknown_stall["plan"] == stalled["plan"]
    assert unknown_stall["context"]["previous_plan"] == stalled["context"]["previous_plan"]
    check(unknown_stall, "blocked", "unavailable stalled-history witnesses cannot authorize a fresh zero-count window",
          "progress_history_missing")
    for form in ("empty", "event-only", "mismatched", "unknown"):
        partial_stall = deepcopy(unknown_stall)
        for checkpoint in stalled["context"]["progress"]["state"]["history"]:
            partial_stall["context"]["progress"]["resolved_sources"][checkpoint["assessment_ref"]] = incomplete_assessment(checkpoint["event_id"], form)
        assert partial_stall["plan"] == stalled["plan"]
        assert partial_stall["context"]["previous_plan"] == stalled["context"]["previous_plan"]
        check(partial_stall, "blocked", form + " stalled-history bodies cannot authorize a fresh zero-count window",
              "progress_history_missing")
    initial = check(predispatch, "accepted", "singleton admission fixture")
    assert initial["status"] == "accepted", "Invalid singleton fixture is not authorizing RED"
    unfinished = retained_progress_request(initial)
    unfinished.update(worker_stage="production", worker_role="code_writer")
    packet = unfinished["plan"]["implementation_steps"][0]
    packet["execution"]["state"] = "RUNNING"
    packet["execution"]["history"].append({"state": "RUNNING", "input_identity": deepcopy(packet["execution"]["input_identity"]),
        "evidence_refs": ["runtime:unfinished-action"], "reason": "Started action is still running"})
    packet["execution"]["evidence_refs"].append("runtime:unfinished-action")
    unfinished["context"]["packet_evidence"][packet["packet_id"]] = evidence(unfinished, packet)
    continuing = check(unfinished, "accepted", "unfinished RUNNING work retains its admission without another checkpoint")
    assert continuing["canonical_progress_state"] == initial["canonical_progress_state"]
    assert continuing["canonical_plan"]["implementation_steps"][0]["execution"]["state"] == "RUNNING"
    gain_parent = check(cycle(retained_progress_request(initial)), "accepted", "completed cycle before typed acceptance gain")
    assert gain_parent["status"] == "accepted", "Acceptance-gain fixture must have an actual admitted predecessor"
    assert gain_parent["canonical_progress_state"]["consecutive_no_progress"] == 1
    typed_gain = cycle(retained_progress_request(gain_parent), "verified_gain")
    typed_gain.update(boundary="plan", plan=deepcopy(gain_parent["canonical_plan"]))
    carrier = typed_gain["context"]["progress"]
    event = carrier["event"]
    frontier = "frontier:typed-obligation:A"
    carrier["resolved_sources"][frontier] = {"accepted_obligations": ["scope", "focused", "integration", "A"]}
    event["frontier_ref"] = frontier
    carrier["resolved_sources"][event["assessment_ref"]]["frontier_ref"] = frontier
    observation_ref = event["evidence_refs"][0]
    carrier["resolved_sources"][observation_ref].update(result="passed", newly_verified_obligations=["A"])
    valid_gain = check(typed_gain, "accepted", "unique obligation reference array certifies a genuine gain")
    assert valid_gain["status"] == "accepted", "Typed acceptance observation must remain valid"
    assert valid_gain["canonical_progress_state"]["consecutive_no_progress"] == 0
    for label, malformed in (("string", "A"), ("object", {"A": True}), ("duplicate array", ["A", "A"])):
        for later_row in (False, True):
            malformed_gain = deepcopy(typed_gain)
            carrier = malformed_gain["context"]["progress"]
            event = carrier["event"]
            ref = observation_ref
            if later_row:
                ref = "observation:typed-obligation:later"
                carrier["resolved_sources"][ref] = deepcopy(carrier["resolved_sources"][observation_ref])
                event["evidence_refs"].append(ref)
                carrier["resolved_sources"][event["assessment_ref"]]["observation_refs"].append(ref)
            carrier["resolved_sources"][ref]["newly_verified_obligations"] = deepcopy(malformed)
            check(malformed_gain, "blocked", label + (" after valid supporting row" if later_row else " obligation evidence"),
                  "progress_mismatch")
    singleton = retained_progress_request(initial)
    singleton["boundary"] = "verification"
    packet = singleton["plan"]["implementation_steps"][0]
    packet["execution"]["state"] = "RUNNING"
    singleton["context"]["packet_evidence"][packet["packet_id"]] = evidence(singleton, packet)
    singleton["context"]["required_terminal_gates"] = ["independent_review"]
    verified = check(singleton, "accepted", "singleton verification before due Review")
    assert verified["status"] == "accepted", "Intermediate verification must remain valid"
    assert verified["canonical_progress_state"] == singleton["context"]["progress"]["state"]
    singleton = retained_progress_request(verified)
    stale = completion(singleton)
    stale["context"]["progress"]["state"] = deepcopy(predispatch["context"]["progress"]["state"])
    assert stale["plan"] == singleton["plan"] and stale["context"]["previous_plan"] == singleton["context"]["previous_plan"]
    check(stale, "blocked", "older pre-dispatch state cannot close genuinely verified execution", "progress_mismatch")
    for form in ("full", "compacted"):
        unpaired = deepcopy(stale)
        for plan in (unpaired["plan"], unpaired["context"]["previous_plan"]):
            execution = plan["implementation_steps"][0]["execution"]
            assert execution["state"] == "VERIFIED"
            execution.pop("action_admission_ref")
            assert execution["action_ref"] == verified["canonical_progress_state"]["action_admission"]["action_ref"]
        if form == "compacted":
            unpaired = compact(unpaired)
        check(unpaired, "blocked", form + " admitted then VERIFIED action without pair still needs recorded closure", "progress_history_missing")
    for stage, retained_request in (("RUNNING", retained_progress_request(initial)), ("VERIFIED", singleton)):
        for erased in (("action_admission_ref",), ("action_ref", "action_admission_ref")):
            lost = deepcopy(retained_request)
            lost["boundary"] = "resume"
            lost["plan"]["implementation_steps"][0]["execution"]["state"] = stage
            for field in erased:
                lost["plan"]["implementation_steps"][0]["execution"].pop(field)
            name = stage + " resume erases " + "+".join(erased)
            promoted = check(lost, "blocked", name, "progress_mismatch")
            if promoted["status"] == "accepted":
                if stage == "RUNNING":
                    verify = retained_progress_request(promoted)
                    verify["boundary"] = "verification"
                    packet = verify["plan"]["implementation_steps"][0]
                    verify["context"]["packet_evidence"][packet["packet_id"]] = evidence(verify, packet)
                    promoted = check(verify, "accepted", name + " actually verifies after canonical promotion")
                if promoted["status"] == "accepted":
                    stale = completion(retained_progress_request(promoted))
                    stale["context"]["progress"]["state"] = deepcopy(predispatch["context"]["progress"]["state"])
                    check(stale, "blocked", name + " cannot launder stale completion", "progress_mismatch")

    joined = check(guarded_parallel_member_request(), "accepted", "grouped admission fixture")
    assert joined["status"] == "accepted", "Invalid grouped fixture is not authorizing RED"
    grouped = retained_progress_request(joined)
    grouped["context"]["workspace"]["active_source_writer_ids"] = []
    for packet in grouped["plan"]["implementation_steps"]:
        packet["execution"]["state"] = "RUNNING"
        grouped["context"]["packet_evidence"][packet["packet_id"]] = evidence(grouped, packet)
    for index, pid in enumerate(("accepted-outcome", "dependent-outcome")):
        grouped.update(boundary="verification", target_packet_id=pid)
        verified = check(grouped, "accepted", "group member verification before coordinator barrier: " + pid)
        assert verified["status"] == "accepted", "Intermediate member verification must remain valid"
        assert verified["canonical_progress_state"] == grouped["context"]["progress"]["state"]
        if index == 0:
            assert verified["canonical_plan"]["implementation_steps"][1]["execution"]["state"] == "RUNNING"
        grouped = retained_progress_request(verified)

    for name, request in (("singleton", singleton), ("grouped", grouped)):
        resume = deepcopy(request)
        resume["boundary"] = "resume"
        resumed = check(resume, "accepted", name + " retained resume with progress")
        assert resumed["status"] == "accepted", "Valid retained resume must remain accepted"
        assert resumed["canonical_progress_state"] == request["context"]["progress"]["state"]
        without_carrier = deepcopy(resume)
        without_carrier["context"].pop("progress")
        resumed = check(without_carrier, "accepted", name + " retained resume safely omits carrier")
        assert resumed["status"] == "accepted", "Resume may retain guard provenance without the carrier"
        for before, after in zip(request["plan"]["implementation_steps"], resumed["canonical_plan"]["implementation_steps"]):
            assert after["execution"]["progress_guard_ref"] == before["execution"]["progress_guard_ref"]
        check(completion(retained_progress_request(resumed)), "blocked",
              name + " retained canonical handoff still requires completion carrier", "progress_history_missing")
        for mutation in ("erase", "rebind"):
            lost = deepcopy(without_carrier)
            for packet in lost["plan"]["implementation_steps"]:
                if mutation == "erase":
                    for field in ("progress_guard_ref", "action_ref", "action_admission_ref"):
                        packet["execution"].pop(field)
                else:
                    packet["execution"]["progress_guard_ref"] = "guard:substituted-on-resume"
            observed = check(lost, "blocked", name + " resume cannot " + mutation + " retained guard",
                             "progress_mismatch")
            if observed["status"] == "accepted":
                # Exercise the actual accepted canonical promotion, not a
                # synthetic previous_plan stripped independently by the test.
                check(completion(retained_progress_request(observed)), "blocked",
                      name + " " + mutation + " resume canonical handoff cannot bypass completion",
                      "progress_history_missing")
        live = completion(request)
        check(live, "blocked", name + " completion retains a live admission", "progress_mismatch")
        if name == "grouped":
            closed_now = completion(guarded_parallel_barrier_request(request))
        else:
            closed_now = completion(completed_progress_cycle(request))
            # Historical execution actions need not equal the carrier's next
            # proposed action after the completed admission has been closed.
            closed_now["plan"] = deepcopy(request["plan"])
        closed = check(closed_now, "accepted", name + " completion closes the cycle now")
        assert closed["status"] == "accepted", "Valid closing checkpoint must permit completion"
        state = closed["canonical_progress_state"]
        prior = request["context"]["progress"]["state"]
        assert state["work_ordinal"] == prior["work_ordinal"] + 1
        assert state["consecutive_no_progress"] == prior["consecutive_no_progress"] + 1
        assert "action_admission" not in state
        # Passing completion evidence does not invent a productive disposition.
        assert state["history"][-1]["disposition"] == "no_progress"
        already_closed = completion(retained_progress_request(closed))
        retained = check(already_closed, "accepted", name + " completion retains a previously closed cycle")
        assert retained["canonical_progress_state"] == state
        wrong_pair = deepcopy(already_closed)
        wrong_pair["context"]["progress"]["state"]["history"][-1]["admission_ref"] = "admission:unrelated-history"
        check(wrong_pair, "blocked", name + " full checkpoint must match the completed action and admission", "progress_mismatch")
        check(compact(already_closed), "accepted", name + " compacted closed action lineage permits completion")
        blocked = deepcopy(closed_now)
        blocked["context"]["readiness"]["ready"] = False
        observed = check(blocked, "blocked", name + " completed checkpoint precedes a later blocker", "not_ready")
        assert observed["canonical_progress_state"] == state

        for owner in ("current", "previous"):
            wrong_guard = deepcopy(already_closed)
            plan = wrong_guard["plan"] if owner == "current" else wrong_guard["context"]["previous_plan"]
            plan["implementation_steps"][-1]["execution"]["progress_guard_ref"] = "guard:wrong-outcome"
            check(wrong_guard, "blocked", name + " wrong " + owner + " guard binding", "progress_mismatch")

        # Each marker independently retains the carrier requirement, including
        # committed markers deleted from the current execution by a candidate.
        for owner in ("current", "previous"):
            for marker in ("progress_guard_ref", "action_ref", "action_admission_ref"):
                omitted = deepcopy(already_closed)
                omitted["context"].pop("progress")
                retained_plan = omitted["context"]["previous_plan"]
                value = retained_plan["implementation_steps"][-1]["execution"][marker]
                for plan in (omitted["plan"], retained_plan):
                    for packet in plan["implementation_steps"]:
                        for field in ("progress_guard_ref", "action_ref", "action_admission_ref"):
                            packet["execution"].pop(field, None)
                marked = omitted["plan"] if owner == "current" else retained_plan
                marked["implementation_steps"][-1]["execution"][marker] = value
                # A retained guard cannot first be deleted during reconciliation;
                # other omitted-carrier cases still reach the completion gate.
                code = "progress_mismatch" if owner == "previous" and marker == "progress_guard_ref" else "progress_history_missing"
                check(omitted, "blocked", name + " omitted carrier with only " + owner + " " + marker,
                      code)

    check(completion(valid_request()), "accepted", "single-pass completion without progress")
    later_action = check(completed_progress_cycle(retained_progress_request(initial)), "accepted",
                         "legitimate later action retains the task guard")
    assert later_action["status"] == "accepted", "Valid later-action fixture must remain accepted"
    later_resume = retained_progress_request(later_action)
    later_resume["boundary"] = "resume"
    later_resume["context"]["previous_plan"] = deepcopy(initial["canonical_plan"])
    old = initial["canonical_plan"]["implementation_steps"][0]["execution"]
    current_execution = later_resume["plan"]["implementation_steps"][0]["execution"]
    assert current_execution["progress_guard_ref"] == old["progress_guard_ref"]
    assert current_execution["action_ref"] != old["action_ref"]
    assert current_execution["action_admission_ref"] != old["action_admission_ref"]
    check(later_resume, "accepted", "resume accepts changed action and admission refs under the same guard")
    closed_request = cycle(retained_progress_request(initial))
    closed_request.update(boundary="plan", plan=deepcopy(initial["canonical_plan"]))
    closed = check(closed_request, "accepted", "actual closure before the successor dispatch")
    assert closed["status"] == "accepted", "Completed predecessor fixture must remain valid"
    original_admission = deepcopy(initial["canonical_progress_state"]["action_admission"])
    original_identity = {field: deepcopy(original_admission[field]) for field in ("action_ref", "packet_id", "input_identity")}
    original_identity["packet_definition_digest"] = API.digest(API.packet_definition(initial["canonical_plan"]["implementation_steps"][0]))
    contradictory = deepcopy(closed_request)
    contradictory["context"]["progress"]["event"]["closed_admission"] = deepcopy(original_admission)
    contradictory["context"]["progress"]["event"]["closed_admission"]["input_identity"] = {"source": "contradicts-real-admission"}
    check(contradictory, "blocked", "checkpoint cannot replace its real admitted input with supplied close metadata", "progress_mismatch")

    # Reconstruction uses the independently retained real admission, never the
    # packet's current identity. Canonical transitions supply it automatically.
    known_closed = retained_progress_request(closed)
    known_closed["context"]["progress"]["state"]["history"][-1]["closed_admission"] = deepcopy(original_admission)
    # Freeze the historical definition before changing any candidate packet.
    # Missing canonical retention is recorded without hiding the stale-work
    # reproductions below; no historical authority is backfilled from a mutant.
    native_source = released_v14_productive_fourth_attempt()
    native_source["plan"]["plan_schema_version"] = "15.0"
    seal(native_source)
    native_source["context"]["previous_plan"] = deepcopy(native_source["plan"])
    native_initial = check(native_source, "accepted", "native v15 singleton actually admits before definition mutations")
    assert native_initial["status"] == "accepted", "Native singleton prerequisite failure is not authorizing RED"
    native_close = cycle(retained_progress_request(native_initial))
    native_close.update(boundary="plan", plan=deepcopy(native_initial["canonical_plan"]))
    native_closed = check(native_close, "accepted", "native v15 singleton actually closes before definition mutations")
    assert native_closed["status"] == "accepted", "Native singleton closure prerequisite failure is not authorizing RED"
    native_known_closed = retained_progress_request(native_closed)
    native_admission = deepcopy(native_initial["canonical_progress_state"]["action_admission"])
    native_identity = {field: deepcopy(native_admission[field]) for field in ("action_ref", "packet_id", "input_identity")}
    original_digest = API.digest(API.packet_definition(native_initial["canonical_plan"]["implementation_steps"][0]))
    native_identity["packet_definition_digest"] = original_digest
    if native_admission.get("packet_definition_digest") != original_digest:
        failures.append(("new singleton admission lacks canonical definition", native_admission))
    canonical_closed = native_known_closed["context"]["progress"]["state"]["history"][-1]["closed_admission"]
    if canonical_closed.get("packet_definition_digest") != original_digest:
        failures.append(("actual singleton closure loses admitted definition", canonical_closed))

    # Keep an independently approved released-format source, carrying the
    # actual closed execution just observed above. This is not a migrated
    # candidate with its accepted provenance removed or its authority resealed.
    original_closed = deepcopy(predispatch)
    original_closed["context"]["progress"] = deepcopy(known_closed["context"]["progress"])
    original_closed["plan"]["implementation_steps"][0]["execution"] = deepcopy(known_closed["plan"]["implementation_steps"][0]["execution"])
    original_closed["context"]["previous_plan"] = deepcopy(original_closed["plan"])
    for version, original in (("14.0", original_closed), ("15.0", native_known_closed)):
        for form in ("full", "compacted"):
            retained = deepcopy(original) if form == "full" else compact(original)
            if form == "compacted":
                # Coverage uses the validated archive inventory, without
                # requiring old assessment bodies to classify generic rows.
                for checkpoint in original["context"]["progress"]["state"]["history"]:
                    retained["context"]["progress"]["resolved_sources"].pop(checkpoint["assessment_ref"], None)
            positive = check(completion(retained), "accepted", version + " " + form + " genuinely closed completion baseline")
            assert positive["status"] == "accepted", "Generic completion must start with actual closed authority"
            rows = [{"event_id": "completion:bare", "evidence_ref": "evidence:completion-bare"},
                    {"kind": "note", "event_id": "completion:note", "evidence_ref": "evidence:completion-note"},
                    {"kind": "worker_stage_result", "event_id": "completion:worker", "evidence_ref": "evidence:completion-worker"},
                    {"worker_stage": "production", "state": "VERIFIED", "event_id": "completion:stage", "evidence_ref": "evidence:completion-stage"}]
            generic = completion(retained)
            for plan in (generic["plan"], generic["context"]["previous_plan"]):
                plan["implementation_steps"][0]["execution"]["history"].extend(deepcopy(rows))
            accepted = check(generic, "accepted", version + " " + form + " completion preserves generic history literally")
            if accepted["status"] == "accepted":
                for actual, expected in ((accepted["canonical_plan"], generic["plan"]),
                                         (accepted["canonical_context"]["previous_plan"], generic["context"]["previous_plan"])):
                    assert actual["implementation_steps"][0]["execution"]["history"] == expected["implementation_steps"][0]["execution"]["history"]
            for field in ("event_id", "evidence_ref"):
                for malformed in (None, "", " "):
                    marked = completion(retained)
                    row = {"kind": "work_checkpoint", "event_id": "checkpoint:malformed-completion", "evidence_ref": "assessment:malformed-completion"}
                    if malformed is None:
                        row.pop(field)
                    else:
                        row[field] = malformed
                    marked["plan"]["implementation_steps"][0]["execution"]["history"].append(row)
                    marked["context"]["previous_plan"] = deepcopy(marked["plan"])
                    check(marked, "blocked", version + " " + form + " completion rejects explicit checkpoint " + field + "=" + repr(malformed))
            if form == "compacted":
                # Preserve genuine action/admission closure while omitting
                # only an independently witnessed historical checkpoint.
                checkpoint = original["context"]["progress"]["state"]["history"][0]
                for resolution in ("present", "missing", "null", "empty", "event-only", "mismatched", "unknown"):
                    omitted = completion(retained)
                    carrier = omitted["context"]["progress"]
                    summary = carrier["resolved_sources"][carrier["state"]["history_base_ref"]]
                    summary["seen_event_ids"].remove(checkpoint["event_id"])
                    sources = carrier["resolved_sources"]
                    if resolution == "present":
                        sources[checkpoint["assessment_ref"]] = deepcopy(original["context"]["progress"]["resolved_sources"][checkpoint["assessment_ref"]])
                    elif resolution == "missing":
                        sources.pop(checkpoint["assessment_ref"], None)
                    elif resolution == "null":
                        sources[checkpoint["assessment_ref"]] = None
                    else:
                        sources[checkpoint["assessment_ref"]] = incomplete_assessment(checkpoint["event_id"], resolution)
                    check(omitted, "blocked", version + " compacted completion cannot omit marked witness with " + resolution + " assessment",
                          "progress_history_missing")

    def reapproved_definition(request, mutation):
        trial = deepcopy(request)
        trial["context"].pop("previous_plan", None)
        packet = trial["plan"]["implementation_steps"][0]
        if mutation == "scope":
            packet["files_to_modify"].append("independently-reapproved-closed-work.py")
        elif mutation == "specification":
            packet["description"] = "Independently reapproved replacement packet result"
        else:
            decision = trial["context"]["verification_decision"]
            decision["checks"][0]["command"]["argv"][-1] = "independently reapproved closed-work check"
            ref = trial["context"]["verification_decision_ref"]
            ref["sha256"] = API.digest(decision)
            trial["plan"]["verification_decision_ref"] = deepcopy(ref)
            packet["verification_decision_ref"] = deepcopy(ref)
            packet["verification_command"] = deepcopy(decision["checks"][0]["command"]["argv"])
        seal(trial)
        trial["context"]["packet_evidence"][packet["packet_id"]] = evidence(trial, packet)
        assert API.digest(API.packet_definition(packet)) != original_digest
        return trial

    for form, retained in (("full", native_known_closed), ("compacted", compact(native_known_closed))):
        carrier = retained["context"]["progress"]
        binding = (carrier["state"]["history"][-1]["closed_admission"] if form == "full" else
                   carrier["resolved_sources"][carrier["state"]["history_base_ref"]]["closed_admissions"][-1])
        if binding.get("packet_definition_digest") != original_digest:
            failures.append((form + " retained definition missing", binding))
        check(completion(retained), "accepted", form + " unchanged definition certifies actual closure")
        for mutation in ("scope", "specification", "verification"):
            changed = reapproved_definition(retained, mutation)
            for paired in (True, False):
                terminal = completion(changed)
                if not paired:
                    terminal["plan"]["implementation_steps"][0]["execution"].pop("action_admission_ref")
                check(terminal, "blocked", form + " reapproved " + mutation + (" paired" if paired else " no-pair") +
                      " cannot certify old closed definition", "progress_mismatch")
            active = deepcopy(changed)
            packet = active["plan"]["implementation_steps"][0]
            packet["execution"]["state"] = "RUNNING"
            active["context"]["packet_evidence"][packet["packet_id"]] = evidence(active, packet)
            active["boundary"] = "verification"
            check(active, "blocked", form + " reapproved " + mutation + " old definition cannot verify", "progress_mismatch")
            # An accepted INVALIDATED representation retains the genuine old
            # pair; promotion of that representation needs current authority.
            active["context"]["previous_plan"] = deepcopy(active["plan"])
            active["context"]["previous_plan"]["implementation_steps"][0]["execution"]["state"] = "INVALIDATED"
            active["boundary"] = "resume"
            check(active, "blocked", form + " reapproved " + mutation + " cannot promote obsolete definition", "progress_mismatch")
        # These records know their exact pair and input but predate the optional
        # definition field. Reading is compatible; certification is UNKNOWN.
        unknown_definition = deepcopy(retained)
        carrier = unknown_definition["context"]["progress"]
        old_binding = (carrier["state"]["history"][-1]["closed_admission"] if form == "full" else
                       carrier["resolved_sources"][carrier["state"]["history_base_ref"]]["closed_admissions"][-1])
        old_binding.pop("packet_definition_digest", None)
        unknown_definition["boundary"] = "plan"
        check(unknown_definition, "accepted", form + " known-pair unknown-definition legacy read")
        for paired in (True, False):
            terminal = completion(unknown_definition)
            if not paired:
                for plan in (terminal["plan"], terminal["context"]["previous_plan"]):
                    plan["implementation_steps"][0]["execution"].pop("action_admission_ref")
            check(terminal, "blocked", form + " unknown historical definition cannot certify " + str(paired), "progress_history_missing")
        reconstructed = deepcopy(unknown_definition)
        carrier = reconstructed["context"]["progress"]
        archive_binding = (carrier["state"]["history"][-1]["closed_admission"] if form == "full" else
                           carrier["resolved_sources"][carrier["state"]["history_base_ref"]]["closed_admissions"][-1])
        archive_binding["packet_definition_digest"] = original_digest
        result = check(completion(reconstructed), "accepted", form + " original archived definition reconstruction certifies")
        if result["status"] == "accepted":
            for field in ("guard_id", "work_ordinal", "consecutive_no_progress", "frontier_ref"):
                assert result["canonical_progress_state"][field] == retained["context"]["progress"]["state"][field]
        # Retirement asks whether this same genuine pair/member closed, not
        # whether its obsolete definition could certify the successor's work.
        successor = reapproved_definition(retained, "scope")
        carrier = successor["context"]["progress"]
        state = API.PROGRESS.ProgressState.parse(carrier["state"], carrier["resolved_sources"])
        old_query = {**deepcopy(native_identity), "packet_definition_digest": API.digest(API.packet_definition(successor["plan"]["implementation_steps"][0]))}
        retired = state.predecessor_lineage(API.PROGRESS.ActionIdentity.parse(old_query), native_admission["admission_ref"], carrier["resolved_sources"])
        assert retired.location == ("checkpoint" if form == "full" else "summary"), "Obsolete definition must not prevent genuine predecessor retirement"
        packet = successor["plan"]["implementation_steps"][0]
        packet["execution"]["state"] = "INVALIDATED"
        successor["context"]["previous_plan"] = deepcopy(successor["plan"])
        packet["execution"].update(state="PENDING", action_ref=carrier["action"]["action_ref"])
        carrier["action"].pop("packet_definition_digest", None)
        successor["boundary"] = "dispatch"
        fresh = check(successor, "accepted", form + " changed work obtains genuinely new bound successor")
        if fresh["status"] == "accepted":
            actual = fresh["canonical_progress_state"]["action_admission"]
            assert actual["admission_ref"] != native_admission["admission_ref"]
            if actual.get("packet_definition_digest") != old_query["packet_definition_digest"]:
                failures.append((form + " fresh successor lacks its approved definition", actual))
            assert fresh["canonical_progress_state"]["work_ordinal"] == retained["context"]["progress"]["state"]["work_ordinal"]
    # Marker subsets retain actual admission/action values from this closed
    # fixture. Readability never supplies a missing completed action identity.
    marker_fields = ("progress_guard_ref", "action_ref", "action_admission_ref")
    for form, retained in (("full", known_closed), ("compacted", compact(known_closed))):
        for mask in range(8):
            shape = "".join(letter for bit, letter in enumerate("GAD") if mask & (1 << bit)) or "unmarked"
            marked = completion(retained)
            for plan in (marked["plan"], marked["context"]["previous_plan"]):
                execution = plan["implementation_steps"][0]["execution"]
                execution["state"] = "VERIFIED"
                for bit, field in enumerate(marker_fields):
                    if not mask & (1 << bit):
                        execution.pop(field, None)
            for boundary in ("plan", "resume", "carrier-free resume"):
                read = deepcopy(marked)
                read["boundary"] = "plan" if boundary == "plan" else "resume"
                if boundary == "carrier-free resume":
                    read["context"].pop("progress")
                status = "blocked" if mask in (4, 5) else "accepted"
                check(read, status, form + " " + shape + " historical " + boundary,
                      "progress_mismatch" if status == "blocked" else None)
            status = "accepted" if mask in (0, 3, 7) else "blocked"
            code = "progress_history_missing" if mask == 1 else "progress_mismatch" if status == "blocked" else None
            check(marked, status, form + " " + shape + " VERIFIED completion marker subset", code)
        for historical_state in ("PENDING", "RUNNING", "BLOCKED", "INVALIDATED", "VERIFIED"):
            historical = deepcopy(retained)
            for plan in (historical["plan"], historical["context"]["previous_plan"]):
                execution = plan["implementation_steps"][0]["execution"]
                execution["state"] = historical_state
                for field in ("action_ref", "action_admission_ref"):
                    execution.pop(field)
            historical["boundary"] = "resume"
            check(historical, "accepted", form + " guard-only " + historical_state + " historical resume")
            current = completion(retained)
            current["context"]["previous_plan"] = deepcopy(historical["context"]["previous_plan"])
            check(current, "blocked" if historical_state == "VERIFIED" else "accepted",
                  form + " genuine closed GAD with retained guard-only " + historical_state,
                  "progress_history_missing" if historical_state == "VERIFIED" else None)
    empty_initial = deepcopy(initial_baseline)
    empty_initial["boundary"] = "plan"
    empty_read = check(empty_initial, "accepted", "valid empty initial progress is read before dispatch")
    assert empty_read["status"] == "accepted", "Empty initial fixture must precede action admission"
    empty_guard = completion(retained_progress_request(empty_read))
    assert empty_guard["context"]["progress"]["state"]["history"] == []
    assert empty_guard["context"]["progress"]["state"]["work_ordinal"] == 0
    assert empty_guard["context"]["progress"]["state"].get("action_admission") is None
    for plan in (empty_guard["plan"], empty_guard["context"]["previous_plan"]):
        execution = plan["implementation_steps"][0]["execution"]
        execution["state"] = "VERIFIED"
        for field in ("action_ref", "action_admission_ref"):
            execution.pop(field, None)
    check(empty_guard, "blocked", "valid empty initial progress cannot certify guard-only VERIFIED work", "progress_history_missing")
    for form, retained in (("full", known_closed), ("compacted", compact(known_closed))):
        expected_location = "checkpoint" if form == "full" else "summary"
        check_lineage(retained, original_identity, original_admission["admission_ref"], expected_location,
                      form + " original closed packet/input binding")
        for field, value in (("packet_id", "foreign-packet"), ("input_identity", {"source": "different-input"})):
            wrong = deepcopy(original_identity)
            wrong[field] = value
            check_lineage(retained, wrong, original_admission["admission_ref"], "missing", form + " closed binding rejects wrong " + field)
        check_lineage(retained, original_identity, "admission:foreign", "missing", form + " closed binding rejects wrong admission")
        check(completion(retained), "accepted", form + " independently retained closed binding certifies its original execution")
        unknown = deepcopy(retained)
        carrier = unknown["context"]["progress"]
        if form == "full":
            for row in carrier["state"]["history"]:
                row.pop("closed_admission", None)
        else:
            carrier["resolved_sources"][carrier["state"]["history_base_ref"]].pop("closed_admissions", None)
        unknown["boundary"] = "plan"
        check(unknown, "accepted", form + " old unknown closed binding remains readable")
        check_lineage(unknown, original_identity, original_admission["admission_ref"], "unknown", form + " absent historical binding is unknown")
        check(completion(unknown), "blocked", form + " unknown closed binding needs reconstruction for certification", "progress_history_missing")
        restored = deepcopy(unknown)
        carrier = restored["context"]["progress"]
        if form == "full":
            carrier["state"]["history"][-1]["closed_admission"] = deepcopy(original_admission)
        else:
            carrier["resolved_sources"][carrier["state"]["history_base_ref"]]["closed_admissions"] = [deepcopy(original_admission)]
        check(completion(restored), "accepted", form + " authoritative old admission reconstruction preserves completion")
        # Missing execution markers do not erase known historical bindings.
        # Reconstruction uses that same actual archive admission, without
        # promoting a recovered marker into either stored execution snapshot.
        for binding, source in (("known", retained), ("unknown", unknown), ("restored", restored)):
            no_pair = deepcopy(source)
            for plan in (no_pair["plan"], no_pair["context"]["previous_plan"]):
                plan["implementation_steps"][0]["execution"].pop("action_admission_ref")
            read = deepcopy(no_pair)
            read["boundary"] = "resume"
            readable = check(read, "accepted", form + " " + binding + " no-pair closed history remains readable")
            assert readable["status"] == "accepted", "Historical readability must not depend on certification authority"
            before = deepcopy(no_pair["context"]["progress"]["state"])
            result = check(completion(no_pair), "blocked" if binding == "unknown" else "accepted",
                           form + " " + binding + " no-pair closure certifies only actual historical authority",
                           "progress_history_missing" if binding == "unknown" else None)
            if result["status"] == "accepted":
                assert result["canonical_progress_state"] == before, "Reconstruction must not reset history, ordinal or counters"
                for plan in (result["canonical_plan"], result["canonical_context"]["previous_plan"]):
                    assert "action_admission_ref" not in plan["implementation_steps"][0]["execution"], "Recovered identity is local certification only"

    siblings = valid_request(2)
    seed = released_v14_productive_fourth_attempt()
    siblings["context"]["progress"] = deepcopy(seed["context"]["progress"])
    siblings["plan"]["implementation_steps"][0]["execution"] = deepcopy(seed["plan"]["implementation_steps"][0]["execution"])
    siblings["context"]["recovery_counters"]["accepted-outcome"] = deepcopy(seed["context"]["recovery_counters"]["accepted-outcome"])
    siblings["context"]["previous_plan"] = deepcopy(siblings["plan"])
    first = check(siblings, "accepted", "two-packet task actually admits its guarded first packet")
    assert first["status"] == "accepted", "Shared-carrier fixture must admit its first action"
    verify_first = retained_progress_request(first)
    verify_first["boundary"] = "verification"
    packet = verify_first["plan"]["implementation_steps"][0]
    packet["execution"]["state"] = "RUNNING"
    verify_first["context"]["packet_evidence"][packet["packet_id"]] = evidence(verify_first, packet)
    verified_first = check(verify_first, "accepted", "first guarded packet actually verifies before its checkpoint")
    assert verified_first["status"] == "accepted", "Shared-carrier fixture verification must remain valid"
    close_first = cycle(retained_progress_request(verified_first))
    close_first.update(boundary="plan", plan=deepcopy(verified_first["canonical_plan"]))
    closed_first = check(close_first, "accepted", "first guarded packet actually closes before sibling dispatch")
    assert closed_first["status"] == "accepted", "Shared-carrier fixture closure must remain valid"
    # The fixed approved two-packet plan actually admitted and closed A alone.
    # Reusing its old action for B cannot turn scalar membership into binding.
    for form in ("full", "compacted"):
        foreign = retained_progress_request(closed_first)
        old_action = closed_first["canonical_progress_state"]["history"][-1]["action_ref"]
        for plan in (foreign["plan"], foreign["context"]["previous_plan"]):
            for packet in plan["implementation_steps"]:
                packet["execution"].pop("action_admission_ref", None)
            packet = plan["implementation_steps"][1]
            packet["execution"].update(progress_guard_ref=foreign["context"]["progress"]["state"]["guard_id"],
                                       action_ref=old_action)
        if form == "compacted":
            foreign = compact(foreign)
        check(completion(foreign), "blocked", form + " no-pair B cannot complete under actually closed singleton A", "progress_mismatch")
    sibling = retained_progress_request(closed_first)
    sibling["target_packet_id"] = "dependent-outcome"
    assert not any(field in sibling["plan"]["implementation_steps"][1]["execution"]
                   for field in ("progress_guard_ref", "action_ref", "action_admission_ref"))
    without_carrier = deepcopy(sibling)
    without_carrier["context"].pop("progress")
    check(without_carrier, "blocked", "unmarked sibling dispatch cannot omit the established task carrier", "progress_history_missing")
    carrier = sibling["context"]["progress"]
    packet = sibling["plan"]["implementation_steps"][1]
    carrier["action"] = {"action_ref": "action:guarded-sibling", "packet_id": packet["packet_id"],
                         "input_identity": deepcopy(packet["execution"]["input_identity"])}
    packet["execution"].update(progress_guard_ref=carrier["state"]["guard_id"], action_ref=carrier["action"]["action_ref"])
    sibling_admitted = check(sibling, "accepted", "sibling retains shared history with its genuinely bound fresh action")
    assert sibling_admitted["status"] == "accepted", "Shared carrier must permit lawful sibling work"
    assert sibling_admitted["canonical_progress_state"]["work_ordinal"] == closed_first["canonical_progress_state"]["work_ordinal"]
    successor = retained_progress_request(closed)
    successor["plan"]["implementation_steps"][0]["execution"]["action_ref"] = successor["context"]["progress"]["action"]["action_ref"]
    admitted = check(successor, "accepted", "real successor dispatch materializes a new admission after predecessor closure")
    assert admitted["status"] == "accepted", "Genuine successor dispatch must remain valid"
    running = retained_progress_request(admitted)
    running["boundary"] = "resume"
    running["plan"]["implementation_steps"][0]["execution"]["state"] = "RUNNING"
    running["context"]["previous_plan"] = deepcopy(initial["canonical_plan"])
    check(running, "accepted", "resume preserves a genuine later live action under the same guard")
    verify = retained_progress_request(admitted)
    verify["boundary"] = "verification"
    packet = verify["plan"]["implementation_steps"][0]
    packet["execution"]["state"] = "RUNNING"
    verify["context"]["packet_evidence"][packet["packet_id"]] = evidence(verify, packet)
    verified_successor = check(verify, "accepted", "actual successor verification retains its committed pair")
    assert verified_successor["status"] == "accepted", "Successor verification fixture must remain valid"
    close_successor = cycle(retained_progress_request(verified_successor))
    close_successor.update(boundary="plan", plan=deepcopy(verified_successor["canonical_plan"]))
    completed_successor = check(close_successor, "accepted", "actual API closes the later admitted action")
    assert completed_successor["status"] == "accepted", "Completed successor fixture must remain valid"
    completed_resume = retained_progress_request(completed_successor)
    completed_resume.update(boundary="resume")
    completed_resume["context"]["previous_plan"] = deepcopy(initial["canonical_plan"])
    check(completed_resume, "accepted", "resume proves a strictly later completed action from full checkpoints")
    for name, observed in (("live", verified_successor), ("completed", completed_successor)):
        rewind = retained_progress_request(observed)
        rewind["boundary"] = "resume"
        execution = rewind["plan"]["implementation_steps"][0]["execution"]
        for field in ("action_ref", "action_admission_ref"):
            execution[field] = initial["canonical_plan"]["implementation_steps"][0]["execution"][field]
        promoted = check(rewind, "blocked", name + " successor cannot rewind to its genuinely closed predecessor",
                         "progress_mismatch")
        if promoted["status"] == "accepted":
            stale = completion(retained_progress_request(promoted))
            stale["context"]["progress"]["state"] = deepcopy(closed["canonical_progress_state"])
            check(stale, "blocked", name + " rewind canonical handoff cannot close with predecessor-only history",
                  "progress_mismatch")

    old_base = compact(retained_progress_request(closed))
    summary_ref = old_base["context"]["progress"]["state"]["history_base_ref"]
    ordered = deepcopy(completed_resume)
    carrier = ordered["context"]["progress"]
    carrier["resolved_sources"][summary_ref] = deepcopy(old_base["context"]["progress"]["resolved_sources"][summary_ref])
    carrier["state"].update(history=carrier["state"]["history"][-1:], history_base_ref=summary_ref)
    carrier["state"]["evidence_refs"].append(summary_ref)
    check(ordered, "accepted", "old compacted action followed by a genuine later tail checkpoint remains ordered")
    check(compact(completed_resume), "blocked", "different pairs summarized without ordering remain an explicit evidence gap",
          "progress_history_missing")

    invalidation = retained_progress_request(completed_successor)
    invalidation["boundary"] = "resume"
    invalidation["context"]["current_input_identities"]["accepted-outcome"] = {"source": "independently-observed-new-input"}
    invalidated = check(invalidation, "accepted", "helper invalidates changed inputs while retaining the committed pair")
    assert invalidated["status"] == "accepted", "Helper invalidation must remain available"
    invalid_execution = invalidated["canonical_plan"]["implementation_steps"][0]["execution"]
    assert invalid_execution["state"] == "INVALIDATED"
    assert invalid_execution["action_admission_ref"] == completed_successor["canonical_plan"]["implementation_steps"][0]["execution"]["action_admission_ref"]
    refresh = retained_progress_request(invalidated)
    refresh["boundary"] = "resume"
    packet = refresh["plan"]["implementation_steps"][0]
    packet["execution"]["input_identity"] = deepcopy(refresh["context"]["current_input_identities"][packet["packet_id"]])
    refresh["context"]["packet_evidence"][packet["packet_id"]] = evidence(refresh, packet)
    refresh["context"]["test_applicability"][packet["packet_id"]] = applicability(refresh, packet)
    refreshed = check(refresh, "accepted", "INVALIDATED snapshot may refresh input while retaining its obsolete pair")
    assert refreshed["status"] == "accepted", "Input refresh of invalidated work must remain lawful"
    assert refreshed["canonical_plan"]["implementation_steps"][0]["execution"]["state"] == "INVALIDATED"
    # Use the helper's accepted invalidation and refresh, never rewrite the
    # retained admission input to make the new candidate appear historical.
    for form in ("full", "compacted"):
        no_pair = retained_progress_request(refreshed)
        for plan in (no_pair["plan"], no_pair["context"]["previous_plan"]):
            execution = plan["implementation_steps"][0]["execution"]
            execution.pop("action_admission_ref")
            assert execution["action_ref"] == invalid_execution["action_ref"]
            assert execution["input_identity"] == no_pair["context"]["current_input_identities"]["accepted-outcome"]
        if form == "compacted":
            no_pair = compact(no_pair)
        check(completion(no_pair), "blocked", form + " no-pair old action cannot certify helper-refreshed input", "progress_mismatch")
    for origin, retained in (("initial invalidation", invalidated), ("refreshed invalidation", refreshed)):
        for form in ("full", "compacted"):
            rebound = retained_progress_request(retained)
            if form == "compacted":
                rebound = compact(rebound)
            rebound["boundary"] = "verification"
            packet = rebound["plan"]["implementation_steps"][0]
            packet["execution"].update(state="RUNNING", input_identity=deepcopy(rebound["context"]["current_input_identities"][packet["packet_id"]]))
            rebound["context"]["packet_evidence"][packet["packet_id"]] = evidence(rebound, packet)
            rebound["context"]["test_applicability"][packet["packet_id"]] = applicability(rebound, packet)
            activation = deepcopy(rebound)
            activation["boundary"] = "resume"
            check(activation, "blocked", form + " " + origin + " cannot promote new-input RUNNING work under the old pair", "progress_mismatch")
            check(rebound, "blocked", form + " " + origin + " old pair cannot verify new input", "progress_mismatch")
            check(completion(rebound), "blocked", form + " " + origin + " old pair cannot complete new input", "progress_mismatch")
    redispatch = retained_progress_request(invalidated)
    packet = redispatch["plan"]["implementation_steps"][0]
    current_input = redispatch["context"]["current_input_identities"][packet["packet_id"]]
    packet["execution"].update(state="PENDING", input_identity=deepcopy(current_input),
        action_ref=redispatch["context"]["progress"]["action"]["action_ref"])
    redispatch["context"]["progress"]["action"]["input_identity"] = deepcopy(current_input)
    redispatch["context"]["packet_evidence"][packet["packet_id"]] = evidence(redispatch, packet)
    redispatch["context"]["test_applicability"][packet["packet_id"]] = applicability(redispatch, packet)
    check(redispatch, "accepted", "legitimate dispatch after helper invalidation creates the genuinely bound new pair")
    refreshed_dispatch = retained_progress_request(refreshed)
    packet = refreshed_dispatch["plan"]["implementation_steps"][0]
    current_input = refreshed_dispatch["context"]["current_input_identities"][packet["packet_id"]]
    packet["execution"].update(state="PENDING", action_ref=refreshed_dispatch["context"]["progress"]["action"]["action_ref"])
    refreshed_dispatch["context"]["progress"]["action"]["input_identity"] = deepcopy(current_input)
    refreshed_dispatch["context"]["packet_evidence"][packet["packet_id"]] = evidence(refreshed_dispatch, packet)
    refreshed_dispatch["context"]["test_applicability"][packet["packet_id"]] = applicability(refreshed_dispatch, packet)
    check(refreshed_dispatch, "accepted", "genuine redispatch retires the old admission after an INVALIDATED input refresh")

    group_closed = check(guarded_parallel_barrier_request(retained_progress_request(joined)), "accepted",
                         "actual grouped predecessor closes before a successor coordinator")
    assert group_closed["status"] == "accepted", "Grouped predecessor fixture must remain valid"
    known_group = retained_progress_request(group_closed)
    group_admission = deepcopy(joined["canonical_progress_state"]["action_admission"])
    known_group["context"]["progress"]["state"]["history"][-1]["closed_admission"] = deepcopy(group_admission)
    fallback_group = deepcopy(known_group)
    fallback_group["context"]["progress"]["state"]["history"][-1].pop("closed_admission")
    for form, retained in (("full", known_group), ("compacted", compact(known_group)), ("barrier fallback", fallback_group)):
        location = "summary" if form == "compacted" else "checkpoint"
        for member in group_admission["member_scope"]["members"]:
            identity = {"action_ref": group_admission["action_ref"], "packet_id": member["packet_id"],
                        "input_identity": deepcopy(member["input_identity"]),
                        "packet_definition_digest": member["packet_definition_digest"]}
            check_lineage(retained, identity, group_admission["admission_ref"], location, form + " closed group binds declared member " + member["packet_id"])
            identity["input_identity"] = {"source": "different-member-input"}
            check_lineage(retained, identity, group_admission["admission_ref"], "missing", form + " closed group rejects changed member input " + member["packet_id"])
        identity = {"action_ref": group_admission["action_ref"], "packet_id": "undeclared-member", "input_identity": {"source": "source-0"}}
        check_lineage(retained, identity, group_admission["admission_ref"], "missing", form + " closed group rejects undeclared member")
        no_pair = deepcopy(retained)
        for plan in (no_pair["plan"], no_pair["context"]["previous_plan"]):
            for packet in plan["implementation_steps"]:
                packet["execution"].pop("action_admission_ref")
        before = deepcopy(no_pair["context"]["progress"]["state"])
        completed = check(completion(no_pair), "accepted", form + " known no-pair group certifies declared members and inputs")
        assert completed["status"] == "accepted", "Actual group closure and full historical barrier fallback must remain valid"
        assert completed["canonical_progress_state"] == before
        for packet in completed["canonical_plan"]["implementation_steps"]:
            assert "action_admission_ref" not in packet["execution"], "Group certification must not store recovered markers"
        if form == "compacted":
            unknown = deepcopy(no_pair)
            carrier = unknown["context"]["progress"]
            carrier["resolved_sources"][carrier["state"]["history_base_ref"]].pop("closed_admissions")
            read = deepcopy(unknown)
            read["boundary"] = "resume"
            check(read, "accepted", "compacted unknown no-pair group remains readable")
            check(completion(unknown), "blocked", "compacted group action inventory cannot recover member/input binding",
                  "progress_history_missing")
    group_invalidation = deepcopy(known_group)
    group_invalidation["boundary"] = "resume"
    group_invalidation["context"]["current_input_identities"]["dependent-outcome"] = {"source": "independently-observed-new-member-input"}
    invalidated_group = check(group_invalidation, "accepted", "helper actually invalidates changed closed group member input")
    assert invalidated_group["status"] == "accepted", "Group input invalidation must remain lawful"
    group_refresh = retained_progress_request(invalidated_group)
    group_refresh["boundary"] = "resume"
    packet = group_refresh["plan"]["implementation_steps"][1]
    assert packet["execution"]["state"] == "INVALIDATED"
    packet["execution"]["input_identity"] = deepcopy(group_refresh["context"]["current_input_identities"][packet["packet_id"]])
    group_refresh["context"]["packet_evidence"][packet["packet_id"]] = evidence(group_refresh, packet)
    group_refresh["context"]["test_applicability"][packet["packet_id"]] = applicability(group_refresh, packet)
    refreshed_group = check(group_refresh, "accepted", "helper accepts INVALIDATED group member input refresh")
    assert refreshed_group["status"] == "accepted", "Group refresh fixture must use accepted helper output"
    for form in ("full", "compacted"):
        no_pair = retained_progress_request(refreshed_group)
        for plan in (no_pair["plan"], no_pair["context"]["previous_plan"]):
            for packet in plan["implementation_steps"]:
                packet["execution"].pop("action_admission_ref")
        if form == "compacted":
            no_pair = compact(no_pair)
        check(completion(no_pair), "blocked", form + " no-pair group cannot certify a changed declared member input", "progress_mismatch")
    group_successor = retained_progress_request(group_closed)
    carrier = group_successor["context"]["progress"]
    action_ref, scope_ref = "action:coordinator-successor", "scope:coordinator-successor"
    members = deepcopy(carrier["action"]["member_scope"]["members"])
    carrier["action"].update(action_ref=action_ref, member_scope={"source_ref": scope_ref, "members": members})
    carrier["resolved_sources"].update({
        scope_ref: {"kind": "coordinator_action_scope", "guard_id": carrier["state"]["guard_id"],
            "outcome_ref": carrier["state"]["outcome_ref"], "action_ref": action_ref,
            "approved_plan_identity": deepcopy(group_successor["plan"]["approved_plan_identity"]),
            "members": members, "grouping_decision_ref": "decision:coordinator-successor"},
        "decision:coordinator-successor": {"approved_plan_identity": deepcopy(group_successor["plan"]["approved_plan_identity"]),
            "reason": "The same independent isolated packets need a subsequent coordinated correction"}})
    group_successor.update(worker_stage="production", worker_role="code_writer")
    group_successor["context"]["workspace"]["active_source_writer_ids"] = []
    group_successor["plan"]["implementation_steps"][0]["execution"]["action_ref"] = action_ref
    group_successor["context"]["packet_evidence"]["accepted-outcome"]["implementation_evidence_ref"] = "writer:coordinator-successor"
    witnessed_group = deepcopy(group_successor)
    checkpoint = witnessed_group["context"]["progress"]["state"]["history"][-1]
    for plan in (witnessed_group["plan"], witnessed_group["context"]["previous_plan"]):
        for packet in plan["implementation_steps"]:
            packet["execution"]["history"].append({"kind": "work_checkpoint", "event_id": checkpoint["event_id"], "evidence_ref": checkpoint["assessment_ref"]})
            packet["execution"]["evidence_refs"] = list(dict.fromkeys(packet["execution"]["evidence_refs"] +
                checkpoint["evidence_refs"] + [checkpoint["assessment_ref"]]))
    deduplicated = check(witnessed_group, "accepted", "two member checkpoint witnesses retain one coordinator cycle")
    assert deduplicated["status"] == "accepted", "Shared group witnesses must not become separate semantic cycles"
    assert deduplicated["canonical_progress_state"]["work_ordinal"] == 1
    first_member = check(group_successor, "accepted", "genuine grouped successor binds its anchor after old closure")
    assert first_member["status"] == "accepted", "Grouped successor anchor must remain valid"
    second_member = retained_progress_request(first_member)
    second_member["target_packet_id"] = "dependent-outcome"
    second_member["plan"]["implementation_steps"][1]["execution"]["action_ref"] = action_ref
    second_member["context"]["workspace"]["active_source_writer_ids"] = ["accepted-outcome"]
    member = check(second_member, "accepted", "genuine later coordinator admission binds its non-anchor member")
    assert member["status"] == "accepted", "Declared member must join the successor admission"

    predecessor = group_closed["canonical_progress_state"]["history"][-1]
    prior_sources = group_closed["canonical_context"]["progress"]["resolved_sources"]
    prior_barrier = prior_sources[predecessor["coordinator_barrier_ref"]]
    prior_terminal_ref = prior_barrier["member_results"][0]["evidence_refs"][0]
    for form in ("full", "compacted"):
        historical = retained_progress_request(group_closed)
        historical["boundary"] = "plan"
        for row in prior_barrier["member_results"]:
            for ref in row["evidence_refs"]:
                for field in ("action_ref", "admission_ref"):
                    historical["context"]["progress"]["resolved_sources"][ref].pop(field)
        if form == "compacted":
            historical = compact(historical)
        read = check(historical, "accepted", form + " historical unbound member facts remain readable")
        assert read["status"] == "accepted", "Legacy member facts are not new current-cycle certification"

        successor = retained_progress_request(member)
        if form == "compacted":
            successor = compact(successor)
        fresh = guarded_parallel_barrier_request(successor)
        carrier = fresh["context"]["progress"]
        if form == "compacted":
            carrier["event"]["predecessor_event_id"] = carrier["resolved_sources"][carrier["state"]["history_base_ref"]]["last_event_id"]
        assert all(carrier["resolved_sources"][ref] == source for ref, source in prior_sources.items()), "Successor overwrote genuine predecessor sources"
        before = deepcopy(carrier["state"])
        current_barrier_ref = carrier["event"]["coordinator_barrier_ref"]
        assert current_barrier_ref != predecessor["coordinator_barrier_ref"]
        current_barrier = carrier["resolved_sources"][current_barrier_ref]
        for row in current_barrier["member_results"]:
            for ref in row["evidence_refs"]:
                fact = carrier["resolved_sources"][ref]
                assert fact["action_ref"] == before["action_admission"]["action_ref"]
                assert fact["admission_ref"] == before["action_admission"]["admission_ref"]
                assert ref not in prior_sources
        closed = check(fresh, "accepted", form + " fresh current-bound member facts close the actual successor once")
        assert closed["status"] == "accepted", "Fresh successor lifecycle facts must remain valid"
        assert closed["canonical_progress_state"]["work_ordinal"] == before["work_ordinal"] + 1
        assert closed["canonical_progress_state"]["consecutive_no_progress"] == before["consecutive_no_progress"] + 1
        assert "action_admission" not in closed["canonical_progress_state"]

        supported = deepcopy(fresh)
        event = supported["context"]["progress"]["event"]
        assert event["assessment_ref"] != predecessor["assessment_ref"]
        event["evidence_refs"] = deepcopy(predecessor["evidence_refs"])
        supported["context"]["progress"]["resolved_sources"][event["assessment_ref"]]["observation_refs"] = deepcopy(event["evidence_refs"])
        reused_support = check(supported, "accepted", form + " a new independently assessed no-progress cycle may reuse supporting checks")
        assert reused_support["status"] == "accepted", "Supporting evidence reuse is distinct from old terminal lifecycle certification"
        assert reused_support["canonical_progress_state"]["work_ordinal"] == before["work_ordinal"] + 1

        for mutation in ("old fact", "old-bound wrapper", "missing action", "missing admission", "missing pair"):
            stale = deepcopy(fresh)
            sources = stale["context"]["progress"]["resolved_sources"]
            row = sources[current_barrier_ref]["member_results"][0]
            if mutation == "old fact":
                row["evidence_refs"] = [prior_terminal_ref]
            elif mutation == "old-bound wrapper":
                ref = "observation:old-bound-wrapper:" + form
                sources[ref] = deepcopy(prior_sources[prior_terminal_ref])
                row["evidence_refs"] = [ref]
            else:
                fact = sources[row["evidence_refs"][0]]
                for field in (("action_ref", "admission_ref") if mutation == "missing pair" else
                              ("action_ref",) if mutation == "missing action" else ("admission_ref",)):
                    fact.pop(field)
            expected = "progress_history_missing" if mutation.startswith("missing") else "progress_mismatch"
            rejected = check(stale, "blocked", form + " successor cannot close with " + mutation, expected)
            if rejected.get("canonical_progress_state") != before:
                failures.append((form + " " + mutation + " consumed the live successor admission or changed its count", rejected))

    singleton_successor = retained_progress_request(group_closed)
    singleton_successor.update(worker_stage="production", worker_role="code_writer")
    carrier = singleton_successor["context"]["progress"]
    carrier["action"].pop("member_scope")
    carrier["action"]["action_ref"] = "action:singleton-after-group"
    singleton_successor["plan"]["implementation_steps"][0]["execution"]["action_ref"] = carrier["action"]["action_ref"]
    singleton_successor["context"]["workspace"]["active_source_writer_ids"] = []
    singleton_successor["context"]["packet_evidence"]["accepted-outcome"]["implementation_evidence_ref"] = "writer:singleton-after-group"
    anchor = check(singleton_successor, "accepted", "actual singleton successor admits only its bound packet")
    assert anchor["status"] == "accepted", "Singleton successor fixture must remain valid"
    unbound = retained_progress_request(anchor)
    unbound["boundary"] = "resume"
    anchor_execution = unbound["plan"]["implementation_steps"][0]["execution"]
    for field in ("action_ref", "action_admission_ref"):
        unbound["plan"]["implementation_steps"][1]["execution"][field] = anchor_execution[field]
    check(unbound, "blocked", "a sibling cannot adopt a live singleton pair outside its admission binding", "progress_mismatch")
    useful = check(cycle(retained_progress_request(initial), "useful_new_evidence"), "accepted",
                   "first ordinary supported uncertainty resolution")
    assert useful["status"] == "accepted", "Useful-evidence fixture must remain valid"
    useful_request = retained_progress_request(useful)
    first_resolution = "uncertainty:ruled-out:4"
    check(resolve_again(useful_request, first_resolution), "blocked", "fresh ordinary wrappers cannot resolve the same uncertainty again")
    known = compact(useful_request, [first_resolution])
    check(resolve_again(known, first_resolution), "blocked", "known compacted uncertainty cannot be resolved again")
    distinct = check(cycle(known, "useful_new_evidence"), "accepted", "known compacted inventory permits distinct supported resolution")
    assert distinct["status"] == "accepted", "Distinct uncertainty fixture must remain valid"
    check(resolve_again(retained_progress_request(distinct), "uncertainty:ruled-out:5"), "blocked",
          "known compacted inventory combines with retained tail resolutions")

    known_empty = compact(retained_progress_request(initial), [])
    first = check(cycle(known_empty, "useful_new_evidence"), "accepted", "known empty inventory permits a first supported resolution")
    assert first["status"] == "accepted", "Known-empty fixture must remain valid"
    legacy = retained_progress_request(first)
    carrier = legacy["context"]["progress"]
    carrier["resolved_sources"][carrier["state"]["history_base_ref"]].pop("seen_resolved_uncertainty_refs")
    legacy["boundary"] = "plan"
    read = check(legacy, "accepted", "unknown legacy inventory replays retained useful-evidence tail")
    assert read["status"] == "accepted", "Legacy historical replay must remain readable"
    assert read["canonical_progress_state"] == carrier["state"]
    legacy["boundary"] = "dispatch"
    no_progress = check(cycle(legacy), "accepted", "unknown legacy inventory permits an ordinary no-progress cycle")
    assert no_progress["status"] == "accepted", "Legacy no-progress cycle must remain valid"
    legacy = retained_progress_request(no_progress)
    prior = deepcopy(legacy["context"]["progress"]["state"])
    ordinary_completion = completion(cycle(legacy))
    ordinary_completion["plan"] = deepcopy(legacy["plan"])
    verify_all(ordinary_completion)
    check(ordinary_completion, "accepted", "unknown legacy inventory permits genuinely closed completion")

    gain = cycle(legacy, "verified_gain")
    gain.update(boundary="plan", plan=deepcopy(legacy["plan"]))
    carrier = gain["context"]["progress"]
    event = carrier["event"]
    frontier = "frontier:legacy:additional-gain"
    carrier["resolved_sources"][frontier] = {"accepted_obligations": ["scope", "focused", "integration", "additional-gain"]}
    event["frontier_ref"] = frontier
    carrier["resolved_sources"][event["assessment_ref"]]["frontier_ref"] = frontier
    carrier["resolved_sources"][event["evidence_refs"][0]].update(result="passed", newly_verified_obligations=["additional-gain"])
    check(gain, "accepted", "unknown legacy inventory permits independently verified acceptance gain")

    incoming = cycle(legacy, "useful_new_evidence")
    incoming["boundary"] = "plan"
    blocked = check(incoming, "blocked", "new useful event needs an authoritative inventory across unknown history",
                    "progress_history_missing")
    if blocked.get("canonical_progress_state") != prior:
        failures.append(("Rejected unknown-inventory novelty consumed or changed retained state", blocked))
    reconstructed = deepcopy(incoming)
    reconstructed["plan"] = deepcopy(legacy["plan"])
    carrier = reconstructed["context"]["progress"]
    carrier["resolved_sources"][carrier["state"]["history_base_ref"]]["seen_resolved_uncertainty_refs"] = []
    assert carrier["state"] == prior, "Archive inventory reconstruction must not reset retained progress"
    restored = check(reconstructed, "accepted", "authoritative inventory reconstruction enables new novelty without reset")
    assert restored["status"] == "accepted", "Authoritative inventory reconstruction must permit the supported distinct resolution"
    after = restored["canonical_progress_state"]
    assert after["history"][:-1] == prior["history"] and after["work_ordinal"] == prior["work_ordinal"] + 1
    assert prior["consecutive_no_progress"] == 1 and after["consecutive_no_progress"] == 0
    assert after["guard_id"] == prior["guard_id"] and after["history_base_ref"] == prior["history_base_ref"]

    current = retained_progress_request(initial)
    for _ in range(2):
        next_cycle = check(completed_progress_cycle(current), "accepted", "prepare retained no-progress cycle")
        assert next_cycle["status"] == "accepted", "Invalid stagnation fixture is not authorizing RED"
        current = retained_progress_request(next_cycle)
    # Existing policy controls cover increases. A decrease must not revoke an
    # ordinary action genuinely admitted before the changed threshold.
    lowered = deepcopy(current)
    lowered["boundary"] = "plan"
    carrier = lowered["context"]["progress"]
    state = carrier["state"]
    old_policy = deepcopy(state["policy"])
    policy = {"policy_id": "shared-stagnation-v1", "stagnation_window": 2, "source_ref": "policy:explicit-user:2"}
    authority, observation, assessment = "authority:user-window2", "observation:user-window2", "assessment:user-window2"
    event = {"kind": "policy_change", "event_id": "policy-change:3-to-2", "guard_id": state["guard_id"],
        "outcome_ref": state["outcome_ref"], "predecessor_event_id": state["history"][-1]["event_id"],
        "work_ordinal": state["work_ordinal"], "action_ref": carrier["action"]["action_ref"],
        "assessment_ref": assessment, "evidence_refs": [observation], "authority_ref": authority,
        "previous_policy": old_policy, "new_policy": policy}
    carrier["resolved_sources"].update({
        policy["source_ref"]: {"policy_id": policy["policy_id"], "stagnation_window": 2, "authority_ref": authority},
        authority: {"kind": "user_policy_change", "authorized": True, "guard_id": state["guard_id"],
            "outcome_ref": state["outcome_ref"], "previous_policy": old_policy, "new_policy": policy},
        observation: {"result": "Explicit user instruction lowers shared window to 2", "authority_ref": authority},
        assessment: {"kind": "policy_change", "event_id": event["event_id"], "observation_refs": [observation],
            "authority_ref": authority, "previous_policy": old_policy, "new_policy": policy}})
    carrier["event"] = event
    changed = check(lowered, "accepted", "authorized lower window retains its already-admitted ordinary action")
    assert changed["status"] == "accepted", "A lawful policy decrease must remain valid"
    assert changed["canonical_progress_state"]["status"] == "stagnant"
    assert changed["canonical_progress_state"]["action_admission"] == state["action_admission"]
    continuing = retained_progress_request(changed)
    continuing.update(worker_stage="production", worker_role="code_writer")
    continuing["plan"]["implementation_steps"][0]["execution"]["state"] = "RUNNING"
    continuing["context"]["packet_evidence"]["accepted-outcome"]["implementation_evidence_ref"] = "writer:observed-after-policy-decrease"
    continued = check(continuing, "accepted", "existing ordinary action continues after an authorized policy decrease")
    assert continued["canonical_progress_state"] == changed["canonical_progress_state"]
    final = completion(completed_progress_cycle(current))
    final["plan"] = deepcopy(current["plan"])
    verify_all(final)  # Retain the actual completed action, not the next proposal.
    stagnant = check(final, "accepted", "final checkpoint reaches stagnation with proven completion")
    assert stagnant["status"] == "accepted", "Stagnation alone must not refuse proven completion"
    state = stagnant["canonical_progress_state"]
    assert state["status"] == "stagnant" and state["consecutive_no_progress"] == 3
    assert state["work_ordinal"] == current["context"]["progress"]["state"]["work_ordinal"] + 1
    assert "action_admission" not in state
    retained = check(completion(retained_progress_request(stagnant)), "accepted", "previously stagnant proven completion")
    assert retained["canonical_progress_state"] == state
    if failures:
        raise AssertionError(("Final completion progress closure regression controls", failures))
    return total


def run_controls():
    # Run the dedicated source-backed authorizer before later guard controls;
    # unsupported versions, missing helper APIs and setup errors are not RED.
    productive_fourth_attempt_admission()
    failed_green_running_next_action_admission()
    guarded_parallel_second_member_admission()
    restored_completed_action_history_uniqueness()
    terminal_stage_and_provenance_controls()
    total = 4 + shared_progress_controls() + completion_progress_closure_controls()

    def expect(request, status, code=None, name=None):
        nonlocal total
        before = deepcopy(request)
        result = API.admission(request)
        assert result["status"] == status and (code is None or result["code"] == code), (name, status, code, result)
        assert request == before, "Admission mutated caller state"
        total += 1
        return result

    canonical_v14_plan_format_admission()
    total += 1
    truthful_no_tests_verification()
    total += 1
    active_writer_verification_barrier()
    total += 1
    # Verification consumes only terminal same-packet Writer output in either lane.
    for lane in ("separated_workers", "bounded_executor"):
        case = valid_request(boundary="verification")
        case["context"]["build_execution_lane"] = lane
        seal(case)
        packet = case["plan"]["implementation_steps"][0]
        packet["execution"]["state"] = "RUNNING"
        proof = evidence(case, packet)
        proof["build_execution_lane"] = lane
        case["context"]["packet_evidence"][packet["packet_id"]] = proof
        result = expect(case, "accepted", name="terminal Writer verifies in " + lane)
        assert result["canonical_plan"]["implementation_steps"][0]["execution"]["state"] == "VERIFIED"
        for mode in ("shared", "unknown", "isolated"):
            active = deepcopy(case)
            active["context"]["workspace"] = {"mode": mode, "active_source_writer_ids": [packet["packet_id"]]}
            expect(active, "blocked", "workspace_overlap", name="direct active Writer in " + lane + "/" + mode)
    # Retained verification reconciles the same independent activity fact transitively.
    retained = verify_all(valid_request(2, "resume"))
    retained["context"]["previous_plan"] = deepcopy(retained["plan"])
    terminal = expect(retained, "accepted", name="retained terminal Writers remain VERIFIED")
    assert all(p["execution"]["state"] == "VERIFIED" for p in terminal["canonical_plan"]["implementation_steps"])
    retained["context"]["workspace"]["active_source_writer_ids"] = ["accepted-outcome"]
    invalidated = expect(retained, "accepted", name="active retained Writer invalidates dependents")
    assert all(p["execution"]["state"] == "INVALIDATED" and p["execution"]["history"]
               for p in invalidated["canonical_plan"]["implementation_steps"])
    # An independently isolated other packet does not block terminal target verification.
    isolated = valid_request(2, "verification")
    first, target = isolated["plan"]["implementation_steps"]
    target["depends_on"] = []
    seal(isolated)
    for packet in (first, target):
        packet["execution"]["state"] = "RUNNING"
        isolated["context"]["packet_evidence"][packet["packet_id"]] = evidence(isolated, packet)
    isolated["target_packet_id"] = target["packet_id"]
    isolated["context"]["workspace"] = {"mode": "isolated", "active_source_writer_ids": [first["packet_id"]],
        "isolation": {p["packet_id"]: {"current": True, "input_identity": deepcopy(p["execution"]["input_identity"]),
            "runtime_evidence_ref": "runtime:verification:" + p["packet_id"],
            "workspace_identity": "workspace:verification:" + p["packet_id"]} for p in (first, target)}}
    accepted = expect(isolated, "accepted", name="unrelated isolated active Writer remains valid")
    assert [p["execution"]["state"] for p in accepted["canonical_plan"]["implementation_steps"]] == ["RUNNING", "VERIFIED"]
    # Unknown/malformed activity cannot stand in for a terminal-Writer observation.
    terminal = valid_request(boundary="verification")
    packet = terminal["plan"]["implementation_steps"][0]
    packet["execution"]["state"] = "RUNNING"
    terminal["context"]["packet_evidence"][packet["packet_id"]] = evidence(terminal, packet)
    for mutation in ("missing_workspace", "missing_activity", "not_array", "non_string", "duplicate", "unknown"):
        malformed = deepcopy(terminal)
        expected_code = "malformed"
        if mutation == "missing_workspace": malformed["context"].pop("workspace")
        elif mutation == "missing_activity": malformed["context"]["workspace"].pop("active_source_writer_ids")
        elif mutation == "not_array": malformed["context"]["workspace"]["active_source_writer_ids"] = packet["packet_id"]
        elif mutation == "non_string": malformed["context"]["workspace"]["active_source_writer_ids"] = [True]
        elif mutation == "duplicate":
            malformed["context"]["workspace"]["active_source_writer_ids"] = [packet["packet_id"], packet["packet_id"]]
            expected_code = "duplicate"
        else:
            malformed["context"]["workspace"]["active_source_writer_ids"] = ["unknown-outcome"]
            expected_code = "workspace_overlap"
        expect(malformed, "blocked", expected_code, name="verification activity " + mutation)
    # Stage overlays retain approved identity; they never become stored work.
    case = valid_request()
    original_definition = expected_current_definition(case["plan"])
    case.update(worker_stage="test_authoring", inline_worker_stage="test_authoring")
    case["context"]["writer_actor_ids"] = {}
    case["context"]["packet_evidence"] = {}
    result = expect(case, "accepted", name="first new writer actor is not fabricated")
    if result["worker_stage"] != result["current_task_packet"]["worker_stage"] or API.definition(result["canonical_plan"]) != original_definition:
        raise AssertionError("Stage overlay changed approved work or inline agreement")
    assert_current_approval(case["plan"], result["canonical_plan"])
    if "worker_stage" in result["canonical_plan"]["implementation_steps"][0]:
        raise AssertionError("Runtime writer stage leaked into stored definition")
    mismatch = deepcopy(case)
    mismatch["inline_worker_stage"] = "production"
    expect(mismatch, "blocked", "projection_mismatch")
    stored = valid_request(boundary="plan")
    stored["plan"]["implementation_steps"][0]["worker_stage"] = "test_authoring"
    seal(stored)
    expect(stored, "blocked", "mixed_schema")
    for stage in ("production", "refactor"):
        case = current_authored_dispatch(stage)
        definition_before = expected_current_definition(case["plan"])
        result = expect(case, "accepted", name="same actual writer " + stage)
        if result["worker_stage"] != stage or result["current_task_packet"]["worker_stage"] != stage or API.definition(result["canonical_plan"]) != definition_before:
            raise AssertionError("Valid stage lost overlay or stable approval")
        assert_current_approval(case["plan"], result["canonical_plan"])
        for mutation in ("missing_current", "missing_prior", "different_actual", "configured_role_only", "different_test_author"):
            trial = deepcopy(case)
            ev = trial["context"]["packet_evidence"]["accepted-outcome"]
            if mutation == "missing_current": trial["context"]["writer_actor_ids"] = {}
            elif mutation == "missing_prior": ev.pop("writer_actor_id")
            elif mutation == "different_actual": ev["writer_actor_id"] = "native-writer:another"
            elif mutation == "configured_role_only": ev["writer_actor_id"] = "intelligent-writer"
            else: ev["tests"]["writer_actor_id"] = "native-writer:another-author"
            expect(trial, "blocked", "writer_lineage", name=mutation + " at " + stage)
    # Current cycle progress blocks replay without a second stage ledger.
    authored = current_authored_dispatch("production")
    authored["worker_stage"] = "test_authoring"
    authored["context"]["packet_evidence"] = {}
    authored["context"]["writer_actor_ids"] = {}
    authored["plan"]["implementation_steps"][0]["execution"].pop("tdd_cycle_log_ref")
    expect(authored, "accepted", name="active authoring has no incoming RED")
    authored["worker_stage"] = "production"
    expect(authored, "blocked", name="authored production needs actual current RED")
    for stage in ("test_authoring", "pre_production_red", "production", "refactor"):
        closed = current_authored_dispatch("refactor")
        closed["context"]["packet_evidence"]["accepted-outcome"]["tdd_cycle"]["refactor"] = {"all_tests_pass": True}
        closed.update(worker_stage=stage, worker_role="builder_tester" if stage == "pre_production_red" else "code_writer")
        expect(closed, "blocked", "worker_stage", name="closed cycle replay at " + stage)
    passed_green = current_authored_dispatch("refactor")
    passed_green["worker_stage"] = "production"
    expect(passed_green, "blocked", "worker_stage", name="passed GREEN cannot authorize new production")
    failed_green = current_authored_dispatch("production")
    failed_green["context"]["packet_evidence"]["accepted-outcome"]["tdd_cycle"]["green"] = {"all_tests_pass": False, "production_file": "accepted-outcome.py"}
    expect(failed_green, "accepted", name="same current failed GREEN permits bounded recovery")
    # Direct verification shares dispatch ownership proof, including completion reconciliation.
    for mutation in ("missing_tests", "malformed_tests", "missing_test_ref", "wrong_author", "malformed_actor_map"):
        trial = current_authored_dispatch("refactor")
        ev = trial["context"]["packet_evidence"]["accepted-outcome"]
        ev["tdd_cycle"]["refactor"] = {"changes_made": "none needed", "all_tests_pass": True,
            "command": deepcopy(ev["tdd_cycle"]["green"]["command"]), "cwd": "/workspace", "invocation_ref": "ref:new-owned"}
        trial["boundary"] = "verification"
        if mutation == "missing_tests": ev.pop("tests")
        elif mutation == "malformed_tests": ev["tests"] = []
        elif mutation == "missing_test_ref": ev["tests"].pop("evidence_ref")
        elif mutation == "wrong_author": ev["tests"]["writer_actor_id"] = "native:other"
        else: trial["context"]["writer_actor_ids"] = []
        expect(trial, "blocked", name="direct verification " + mutation)
    # Preserve upstream bounded-dispatch exception without inventing actual RED.
    bounded = current_authored_dispatch()
    bounded["context"]["build_execution_lane"] = "bounded_executor"
    bounded["context"]["test_applicability"] = {p["packet_id"]: applicability(bounded, p) for p in bounded["plan"]["implementation_steps"]}
    bounded["plan"]["implementation_steps"][0]["execution"]["state"] = "PENDING"
    bounded["context"]["packet_evidence"] = {}
    bounded["context"]["writer_actor_ids"] = {}
    bounded["plan"]["implementation_steps"][0]["execution"].pop("tdd_cycle_log_ref")
    result = expect(bounded, "accepted")
    if "red_evidence" in result["current_task_packet"]:
        raise AssertionError("Bounded initial dispatch fabricated RED")
    reused = current_authored_dispatch()
    ev = reused["context"]["packet_evidence"]["accepted-outcome"]
    ev["tests"] = {"mode": "reuse", "evidence_ref": "tests:unchanged-assertion"}
    ev.pop("writer_actor_id")
    reused["context"]["writer_actor_ids"] = {}
    expect(reused, "accepted", name="genuine reused assertion permits first unknown native writer")
    reused["worker_stage"] = "refactor"
    expect(reused, "blocked", "writer_lineage", name="refactor cannot reuse missing actor")
    for runtime in ("claude", "codex", "gemini"):
        for many in (False, True):
            case = released_v13_request(runtime, many, active=many)
            original = deepcopy(case["plan"])
            result = expect(case, "accepted", name="genuine released13 " + runtime)
            provenance = result["canonical_plan"]["reconciliation_provenance"]
            if provenance["producer"]["schema_version"] != "13.0" or provenance["producer"]["runtime"] != runtime or provenance["source_sha256"] != API.digest(original):
                raise AssertionError("Released13 provenance was relabelled")
            if any("worker_stage" in p for p in result["canonical_plan"]["implementation_steps"]):
                raise AssertionError("Historical13 stage became current canonical authority")
            if many:
                separate = deepcopy(case)
                separate["plan"]["slice_manifest"][0]["worker_stage"] = "production"
                separate = reseal_legacy(separate)
                retained = expect(separate, "accepted", name="released13 separate manifest and child stages")
                historical = retained["canonical_plan"]["reconciliation_provenance"]["original_writer_context"]
                if historical["slices"][0]["worker_stage"] != "production" or historical["packets"][0]["worker_stage"] != "test_authoring":
                    raise AssertionError("Original source stages were collapsed")
            for mutation in ("missing_runtime", "unknown_runtime", "wrong_embedded_version", "bad_stage"):
                trial = deepcopy(case)
                if mutation == "missing_runtime": trial["context"]["legacy"]["producer"].pop("runtime")
                elif mutation == "unknown_runtime": trial["context"]["legacy"]["producer"]["runtime"] = "guessed"
                elif mutation == "wrong_embedded_version": trial["plan"]["schema_version"] = "12.0"
                else: trial["plan"]["implementation_steps"][0]["worker_stage"] = "green"
                trial["context"]["legacy"]["source_sha256"] = API.digest(trial["plan"])
                expect(trial, "blocked", name="released13 " + mutation)
            if runtime != "gemini":
                for value in (None, [], {"agent": "builder-tester", "rationale": "wrong role"}, {"agent": "intelligent-writer", "rationale": ""}):
                    trial = deepcopy(case)
                    if value is None: trial["plan"]["implementation_steps"][0].pop("writer_selection")
                    else: trial["plan"]["implementation_steps"][0]["writer_selection"] = value
                    trial["context"]["legacy"]["source_sha256"] = API.digest(trial["plan"])
                    expect(trial, "blocked", name="invalid released13 writer selection")
    collision = valid_request(boundary="plan")
    collision["plan"]["plan_schema_version"] = "13.0"
    expect(collision, "blocked", "unsupported_version", name="unreleased canonical13 is not genuine slice13")
    # Stored identity shape is checked before normal staleness reconciliation.
    case = valid_request(boundary="plan")
    del case["plan"]["implementation_steps"][0]["execution"]["input_identity"]
    untouched = deepcopy(case)
    observed = API.admission(case)
    if API.digest(case) != API.digest(untouched):
        raise AssertionError("Missing input identity check mutated caller state")
    if observed["status"] == "accepted":
        execution = observed["canonical_plan"]["implementation_steps"][0]["execution"]
        if "input_identity" not in execution and execution["state"] == "INVALIDATED":
            raise AssertionError("Missing execution input identity was admitted")
    if observed["status"] != "blocked" or observed["code"] != "malformed" or observed["path"] != "accepted-outcome.input_identity":
        raise AssertionError(("Missing stored input identity was not rejected", observed))
    total += 1
    for identity in (None, False, 7, 1e308, "stored source", []):
        case = valid_request(boundary="plan")
        case["plan"]["implementation_steps"][0]["execution"]["input_identity"] = identity
        untouched = deepcopy(case)
        observed = API.admission(case)
        if observed["status"] != "blocked" or observed["code"] != "malformed" or observed["path"] != "accepted-outcome.input_identity":
            raise AssertionError(("Non-object stored input identity was not rejected", identity, observed))
        if API.digest(case) != API.digest(untouched):
            raise AssertionError("Non-object input identity check mutated caller state")
        total += 1
    for identity, state, boundary in (({"source": "source-0"}, "PENDING", "dispatch"),
                                      ({"source": "prior-source", "metadata": {"observed": False, "finite_number": 1e308}}, "INVALIDATED", "plan"),
                                      ({}, "INVALIDATED", "plan")):
        case = valid_request(boundary=boundary)
        case["plan"]["implementation_steps"][0]["execution"]["input_identity"] = deepcopy(identity)
        untouched = deepcopy(case)
        observed = API.admission(case)
        if observed["status"] != "accepted":
            raise AssertionError(("Valid stored input identity object was rejected", identity, observed))
        execution = observed["canonical_plan"]["implementation_steps"][0]["execution"]
        if execution["state"] != state or API.digest(execution["input_identity"]) != API.digest(identity):
            raise AssertionError("Valid stored input identity changed or lost staleness behavior")
        if boundary == "dispatch" and API.digest(observed["current_task_packet"]["execution"]["input_identity"]) != API.digest(identity):
            raise AssertionError("Current input identity changed in worker output")
        if API.digest(case) != API.digest(untouched):
            raise AssertionError("Valid input identity check mutated caller state")
        total += 1
    # History is object[] at both the stored-plan and worker boundaries.
    case = valid_request()
    case["plan"]["implementation_steps"][0]["execution"]["history"] = [None]
    untouched = deepcopy(case)
    observed = API.admission(case)
    if API.digest(case) != API.digest(untouched):
        raise AssertionError("History entry check mutated caller state")
    if observed["status"] == "accepted" and observed["current_task_packet"]["execution"]["history"] == [None]:
        raise AssertionError("Non-object execution history entry was admitted")
    if observed["status"] != "blocked" or observed["code"] != "malformed" or observed["path"] != "accepted-outcome.history[]":
        raise AssertionError(("History entry rejection did not enforce object shape", observed))
    total += 1
    for entry in (None, False, 7, 1e308, "retained event", []):
        case = valid_request(boundary="plan")
        case["plan"]["implementation_steps"][0]["execution"]["history"] = [{"prior": "valid event"}, entry]
        untouched = deepcopy(case)
        observed = API.admission(case)
        if observed["status"] != "blocked" or observed["code"] != "malformed" or observed["path"] != "accepted-outcome.history[]":
            raise AssertionError(("Non-object history family was not rejected", entry, observed))
        if API.digest(case) != API.digest(untouched):
            raise AssertionError("Malformed history check mutated caller state")
        total += 1
    for entry in ({}, {"attempt": 1, "metadata": {"finite_number": 1e308, "observed": False}}):
        case = valid_request()
        history = [deepcopy(entry)]
        case["plan"]["implementation_steps"][0]["execution"]["history"] = deepcopy(history)
        untouched = deepcopy(case)
        observed = API.admission(case)
        if observed["status"] != "accepted":
            raise AssertionError(("Valid history object was rejected", entry, observed))
        if (API.digest(observed["canonical_plan"]["implementation_steps"][0]["execution"]["history"]) != API.digest(history)
                or API.digest(observed["current_task_packet"]["execution"]["history"]) != API.digest(history)):
            raise AssertionError("Valid history object changed in canonical or worker output")
        if API.digest(case) != API.digest(untouched):
            raise AssertionError("Valid history check mutated caller state")
        total += 1
    # Proposed new unit RED: approved normalized work cannot lose a manifest instruction.
    case = legacy_request()
    case["plan"]["slice_manifest"][0]["evidence_to_record"].append("Retain independent migration rollback evidence")
    case["context"]["legacy"]["source_sha256"] = API.digest(case["plan"])
    untouched = deepcopy(case)
    observed = API.admission(case)
    if observed["status"] != "blocked" or observed["code"] != "legacy_allocation":
        raise AssertionError("Legacy slice-only evidence instruction was silently dropped")
    if API.digest(case) != API.digest(untouched):
        raise AssertionError("Legacy instruction check mutated original source or authority")
    total += 1
    for many in (False, True):
        active = many
        original = legacy_request(many, active, tagged=not many)
        for field in ("evidence_to_record", "enabling_changes_included", "expected_success_signal", "deviation_rollback_rule", "writer_selection"):
            trial = deepcopy(original)
            manifest = trial["plan"]["slice_manifest"][0]
            marker = "Retain original slice " + field
            if field in {"evidence_to_record", "enabling_changes_included"}:
                manifest[field].append(marker)
            elif field == "writer_selection":
                manifest[field] = {"agent": "intelligent-writer", "rationale": marker}
            else:
                manifest[field] = marker
            # The old normalized approval is deliberately unchanged: a
            # source-only constraint cannot disappear behind that digest.
            trial["context"]["legacy"]["source_sha256"] = API.digest(trial["plan"])
            expect(trial, "blocked", "legacy_allocation", name="slice-only " + field)
            # Positive: the original source explicitly assigns its work;
            # this synthetic approval now covers the actual packet fields.
            owned = [p for p in trial["plan"]["implementation_steps"] if p["slice_id"] == manifest["slice_id"]]
            if field in {"evidence_to_record", "enabling_changes_included"}:
                owned[0][field].append(marker)
            elif field in {"deviation_rollback_rule", "writer_selection"}:
                for packet in owned:
                    packet[field] = deepcopy(manifest[field])
            else:
                owned[0][field] = marker
            reseal_legacy(trial)
            trial.update(boundary="dispatch", target_packet_id="accepted-outcome" if many else "source-outcome")
            if active: trial.update(worker_stage="pre_production_red", worker_role="builder_tester")
            result = expect(trial, "accepted", name="explicit original instruction owner " + field)
            projected = result["current_task_packet"][field]
            if field in {"evidence_to_record", "enabling_changes_included"}:
                assert marker in projected
            else:
                assert projected == manifest[field]
            assert "red_evidence" not in result["current_task_packet"]
            if many and field in {"deviation_rollback_rule", "writer_selection"}:
                conflict = deepcopy(trial)
                second = conflict["plan"]["implementation_steps"][1]
                if field == "writer_selection": second.pop(field)
                else: second[field] = "Different packet rollback condition"
                conflict["context"]["legacy"]["source_sha256"] = API.digest(conflict["plan"])
                expect(conflict, "blocked", "legacy_allocation", name="partial slice constraint is unresolved " + field)
    # Metadata may summarize different child outcomes without becoming a second
    # executable obligation store. Explicit child writer choice stays intact.
    case = legacy_request(True)
    case["plan"]["slice_manifest"][0].update(name="Combined legacy result", observable_increment="Combined accepted outcomes", deliverable_type="migration")
    case["plan"]["implementation_steps"][0]["writer_selection"] = {"agent": "intelligent-writer", "rationale": "Explicit child ownership"}
    reseal_legacy(case)
    result = expect(case, "accepted", name="retired descriptive metadata preserves child-owned execution")
    assert result["canonical_plan"]["implementation_steps"][0]["writer_selection"] == case["plan"]["implementation_steps"][0]["writer_selection"]
    for many in (False, True):
        for active in (False, True):
            for tagged in (False, True):
                case = legacy_request(many, active, tagged)
                original = deepcopy(case)
                result = expect(case, "accepted", name="verified original v12 tag/no-tag entry")
                assert case == original and result["canonical_plan"]["reconciliation_provenance"]["source_sha256"] == API.digest(original["plan"])
                for mutation in ("missing_provenance", "unverified", "wrong_producer", "missing_producer_ref", "conflicting_tag", "null_tag", "canonical_marker", "stale_source"):
                    trial = deepcopy(case)
                    if mutation == "missing_provenance": del trial["context"]["legacy"]
                    elif mutation == "unverified": trial["context"]["legacy"]["producer"]["verified"] = False
                    elif mutation == "wrong_producer": trial["context"]["legacy"]["producer"]["schema_version"] = "14.0"
                    elif mutation == "missing_producer_ref": del trial["context"]["legacy"]["producer"]["producer_ref"]
                    elif mutation == "conflicting_tag": trial["plan"]["schema_version"] = "14.0"
                    elif mutation == "null_tag": trial["plan"]["schema_version"] = None
                    elif mutation == "canonical_marker": trial["plan"]["plan_schema_version"] = "14.0"
                    else: trial["context"]["legacy"]["source_sha256"] = "stale"
                    if mutation in {"conflicting_tag", "null_tag", "canonical_marker"}:
                        trial["context"]["legacy"]["source_sha256"] = API.digest(trial["plan"])
                    expect(trial, "blocked", name="legacy provenance/version contradiction " + mutation)
    for field in ("description", "reuse_search", "test_criteria", "implementation_notes", "verification_command"):
        for value in ("omitted", None, 1):
            case = valid_request()
            packet = case["plan"]["implementation_steps"][0]
            if value == "omitted": del packet[field]
            else: packet[field] = value
            seal(case)
            expect(case, "blocked", name="canonical direct field " + field)
    case = valid_request()
    case["plan"]["implementation_steps"][0]["test_criteria"] = []
    seal(case)
    expect(case, "blocked", name="nonempty canonical test criteria")
    for _, request, status, code in fixed_cases():
        expect(request, status, code)
    for many in (False, True):
        case = legacy_request(many)
        case.update(boundary="dispatch", target_packet_id="accepted-outcome" if many else "source-outcome")
        result = expect(case, "accepted", name="v12 required assessment normalizes without storing stale specialist state (" + ("one-to-many" if many else "one-to-one") + ")")
        assert all("evidence_assessment" not in p for p in result["canonical_plan"]["implementation_steps"])
        assert result["current_task_packet"]["evidence_assessment"] == case["context"]["evidence_assessment"]
        assert result["current_task_packet"]["evidence_assessment"] != case["plan"]["implementation_steps"][0]["evidence_assessment"]
        # Optional task-level decision is another supplied authority copy:
        # identical copies are valid; changed check or binding copies must block.
        case["plan"]["verification_decision"] = deepcopy(case["context"]["verification_decision"])
        reseal_legacy(case)
        expect(case, "accepted", name="matching task-level legacy decision")
        for mutation in ("check", "binding"):
            trial = deepcopy(case)
            decision = trial["plan"]["verification_decision"]
            if mutation == "check":
                decision["checks"].append({"check_id": "legacy-extra", "method": "artifact_inspection",
                    "check_ref_or_method": {"reference_or_procedure": "Inspect extra legacy obligation"}})
            else:
                decision["policy_basis"]["binding_constraints"].append({"kind": "required_check",
                    "value": "Retain original legacy obligation", "source_ref": "legacy:binding"})
            trial["context"]["legacy"]["source_sha256"] = API.digest(trial["plan"])
            expect(trial, "blocked", "decision_mismatch", name="conflicting task-level legacy " + mutation)
    # The baseline v12 manifest has no requirement_ids and active packets have
    # no planned RED tuple. Preserve those valid source shapes unchanged.
    for many in (False, True):
        case = legacy_request(many)
        assert all("requirement_ids" not in m for m in case["plan"]["slice_manifest"])
        expect(case, "accepted", name="actual baseline v12 manifest shape")
        for field in ("files_to_create", "files_to_modify", "files_to_test"):
            trial = deepcopy(case)
            trial["plan"]["slice_manifest"][0][field].append("unallocated-original-scope.py")
            trial["context"]["legacy"]["source_sha256"] = API.digest(trial["plan"])
            expect(trial, "blocked", "legacy_allocation", name="conflicting original " + field)
            missing = deepcopy(case)
            del missing["plan"]["slice_manifest"][0][field]
            missing["context"]["legacy"]["source_sha256"] = API.digest(missing["plan"])
            expect(missing, "blocked", name="missing original " + field)
        optional = deepcopy(case)
        optional["plan"]["slice_manifest"][0]["requirement_ids"] = ["unallocated-requirement"]
        optional["context"]["legacy"]["source_sha256"] = API.digest(optional["plan"])
        expect(optional, "blocked", "legacy_allocation")
        case = legacy_request(many, active=True)
        original = deepcopy(case["plan"])
        result = expect(case, "accepted", name="active baseline v12 derives planned RED only")
        planned = {"red_check_id": "focused", "red_command": ["python3", "verify.py", "literal argument"],
                   "red_cwd": "/workspace", "expected_red_failure": "Expected behavior is absent"}
        for old, packet in zip(original["implementation_steps"], result["canonical_plan"]["implementation_steps"]):
            assert all(key not in old for key in planned)
            assert all(packet[key] == value for key, value in planned.items())
            assert "red_evidence" not in packet and "tdd_cycle_log_ref" not in packet["execution"]
        supplied = deepcopy(case)
        for old in supplied["plan"]["implementation_steps"]:
            old.update(deepcopy(planned))
        supplied["context"]["legacy"]["source_sha256"] = API.digest(supplied["plan"])
        expect(supplied, "accepted", name="matching supplied planned RED is preserved")
        for mutation in ("ambiguous", "noncommand", "empty_oracle"):
            trial = deepcopy(case)
            decision = trial["context"]["verification_decision"]
            if mutation == "ambiguous":
                other = deepcopy(decision["checks"][0])
                other["check_id"] = "other-active"
                decision["checks"].append(other)
                decision["tdd_choice"]["applicable_check_ids"].append("other-active")
                for owner in trial["plan"]["slice_manifest"] + trial["plan"]["implementation_steps"]:
                    owner["selected_check_ids"].append("other-active")
            elif mutation == "noncommand":
                del decision["checks"][0]["command"]
            else:
                decision["checks"][0]["check_ref_or_method"]["meaningful_failure"] = ""
            for owner in trial["plan"]["slice_manifest"] + trial["plan"]["implementation_steps"]:
                owner["verification_decision"] = deepcopy(decision)
            trial["context"]["verification_decision_ref"]["sha256"] = API.digest(decision)
            trial["context"]["legacy"]["source_sha256"] = API.digest(trial["plan"])
            expect(trial, "blocked", name="planned legacy RED rejects " + mutation)
        for key in planned:
            trial = deepcopy(case)
            trial["plan"]["implementation_steps"][0][key] = "conflicting"
            trial["context"]["legacy"]["source_sha256"] = API.digest(trial["plan"])
            expect(trial, "blocked", "tdd_mismatch", name="conflicting supplied planned " + key)
        case.update(boundary="dispatch", target_packet_id="accepted-outcome" if many else "source-outcome",
                    worker_stage="pre_production_red", worker_role="builder_tester")
        expect(case, "accepted")
        case["plan"]["implementation_steps"][0]["execution"]["state"] = "RUNNING"
        case.update(worker_stage="production", worker_role="code_writer")
        expect(case, "blocked", name="planned legacy tuple is not actual RED")
    # JSON scalar types are part of current authority and historical identity.
    for flag, number in ((False, 0), (True, 1)):
        case = legacy_request(active=True) if flag else valid_request()
        if flag:
            case.update(boundary="dispatch", target_packet_id="source-outcome", worker_stage="pre_production_red", worker_role="builder_tester")
        case["current_task_packet"] = expect(case, "accepted")["current_task_packet"]
        case["current_task_packet"]["tdd_applies"] = number
        expect(case, "blocked", "projection_mismatch", name="boolean projection cannot become number")
        case = valid_request()
        case["plan"]["implementation_steps"][0]["execution"]["recovery"]["attempt_count"] = number
        case["context"]["recovery_counters"]["accepted-outcome"] = {"attempt_count": flag, "no_progress_count": 0}
        expect(case, "blocked", "recovery_mismatch", name="counter authority keeps integer types")
        case = valid_request(boundary="resume")
        case["plan"]["implementation_steps"][0]["execution"]["history"] = [{"observed": flag}]
        case["context"]["previous_plan"] = deepcopy(case["plan"])
        case["plan"]["implementation_steps"][0]["execution"]["history"][0]["observed"] = number
        expect(case, "blocked", "recovery_mismatch", name="historical evidence types cannot change")
        case = valid_request(2)
        case["plan"]["implementation_steps"][0]["execution"]["input_identity"]["generation"] = flag
        case["context"]["current_input_identities"]["accepted-outcome"]["generation"] = flag
        case["context"]["test_applicability"]["accepted-outcome"] = applicability(case, case["plan"]["implementation_steps"][0])
        verify_all(case)
        case["plan"]["implementation_steps"][1]["execution"]["state"] = "PENDING"
        case["target_packet_id"] = "dependent-outcome"
        case["context"]["current_input_identities"]["accepted-outcome"]["generation"] = number
        expect(case, "blocked", "prerequisite_unverified", name="typed relevant input change invalidates dependent result")
        for boundary in ("verification", "dispatch"):
            case = valid_request(boundary=boundary)
            packet = case["plan"]["implementation_steps"][0]
            packet["execution"]["state"] = "RUNNING"
            packet["execution"]["input_identity"]["generation"] = flag
            case["context"]["current_input_identities"][packet["packet_id"]]["generation"] = flag
            case["context"]["test_applicability"][packet["packet_id"]] = applicability(case, packet)
            ev = evidence(case, packet)
            ev["input_identity"]["generation"] = number
            case["context"]["packet_evidence"][packet["packet_id"]] = ev
            if boundary == "dispatch": case.update(worker_stage="final_verification", worker_role="builder_tester")
            expect(case, "blocked", "stale_evidence", name="typed current evidence identity at " + boundary)
        case = valid_request(2)
        first, second = case["plan"]["implementation_steps"]
        second["depends_on"] = []
        first["execution"]["state"] = "RUNNING"
        first["execution"]["input_identity"]["generation"] = flag
        case["context"]["current_input_identities"][first["packet_id"]]["generation"] = flag
        seal(case)
        case["target_packet_id"] = second["packet_id"]
        case["context"]["workspace"] = {"mode": "isolated", "active_source_writer_ids": [first["packet_id"]],
            "isolation": {p["packet_id"]: {"current": True, "input_identity": deepcopy(p["execution"]["input_identity"]),
                "runtime_evidence_ref": "runtime:typed:" + p["packet_id"], "workspace_identity": "workspace:typed:" + p["packet_id"]}
                for p in (first, second)}}
        case["context"]["workspace"]["isolation"][first["packet_id"]]["input_identity"]["generation"] = number
        expect(case, "blocked", "workspace_overlap", name="typed runtime isolation input identity")
        for owner in ("task", "manifest", "packet"):
            case = legacy_request(active=flag)
            case["plan"]["verification_decision"] = deepcopy(case["context"]["verification_decision"])
            target = case["plan"] if owner == "task" else case["plan"]["slice_manifest" if owner == "manifest" else "implementation_steps"][0]
            target["verification_decision"]["tdd_choice"]["mode"] = number
            case["context"]["legacy"]["source_sha256"] = API.digest(case["plan"])
            expect(case, "blocked", "decision_mismatch", name="legacy specialist decision retains boolean types in " + owner)
    case = legacy_request()
    case["context"]["legacy"].update(source_identity={"version": False}, approved_source_identity={"version": 0})
    expect(case, "blocked", name="original source identity is a literal string")
    one = valid_request()
    projection = expect(one, "accepted")["current_task_packet"]
    assert projection["verification_decision"] == one["context"]["verification_decision"]
    for key in ("name", "packet_id", "verification_decision"):
        changed = deepcopy(one)
        changed["current_task_packet"] = deepcopy(projection)
        changed["current_task_packet"][key] = "changed"
        expect(changed, "blocked", "projection_mismatch")
    for state in ("PENDING", "RUNNING", "BLOCKED", "INVALIDATED", "VERIFIED"):
        case = verify_all(valid_request(2))
        case["target_packet_id"] = "dependent-outcome"
        case["plan"]["implementation_steps"][1]["execution"]["state"] = "PENDING"
        case["plan"]["implementation_steps"][0]["execution"]["state"] = state
        expect(case, "accepted" if state == "VERIFIED" else "blocked", "accepted" if state == "VERIFIED" else "prerequisite_unverified")
    for state in ("PENDING", "RUNNING", "VERIFIED"):
        case = valid_request()
        case["plan"]["implementation_steps"][0]["execution"]["state"] = state
        if state == "VERIFIED":
            expect(case, "blocked", "invalidated")
        else:
            case["boundary"] = "verification"
            expect(case, "blocked")  # Worker DONE or a started packet without evidence is insufficient.
    for field, value in (("target_packet_id", "missing-outcome"), ("boundary", "scheduler")):
        case = deepcopy(one)
        case[field] = value
        expect(case, "blocked")
    for field in ("name", "acceptance_criteria", "files_to_create", "files_to_modify", "files_to_test", "selected_check_ids"):
        case = deepcopy(one)
        case["plan"]["implementation_steps"][0][field] = ["changed"] if isinstance(case["plan"]["implementation_steps"][0][field], list) else "changed"
        expect(case, "blocked")
    for field in ("sha256", "artifact_ref"):
        case = deepcopy(one)
        case["plan"]["verification_decision_ref"][field] = "changed"
        expect(case, "blocked")
    for field in ("ready", "route_clear"):
        case = deepcopy(one)
        case["context"]["readiness"][field] = False
        expect(case, "blocked", "not_ready")
    for mutation in ("mixed", "unsafe_id", "unsafe_path", "cycle", "no_purpose", "lost_integration"):
        case = valid_request(2, "plan")
        packet = case["plan"]["implementation_steps"][0]
        if mutation == "mixed": case["plan"]["slice_manifest"] = []
        elif mutation == "unsafe_id":
            packet["packet_id"] = "../escape"
            case["context"]["current_input_identities"][packet["packet_id"]] = deepcopy(packet["execution"]["input_identity"])
        elif mutation == "unsafe_path": packet["files_to_modify"] = ["bad\x00target.py"]
        elif mutation == "cycle": packet["depends_on"] = ["dependent-outcome"]
        elif mutation == "no_purpose": del packet["boundary_reason"]
        else: case["plan"]["completion_allocation"]["selected_check_ids"] = []
        seal(case)  # Even approval cannot waive a mandatory structural control.
        expect(case, "blocked")
    # Preserve the existing exact authorized file/target string domain.
    path_scopes = [
        {"files_to_create": ["/workspace/new.py"], "files_to_modify": [r"C:\repo\source.py"],
         "files_to_test": ["../Shared/check.py"]},
        {"files_to_create": [r"src\new.py"], "files_to_modify": ["C:/repo/source.py"],
         "files_to_test": ["/workspace/check.py"]},
    ]
    for scope in path_scopes:
        for legacy in (False, True):
            case = legacy_request() if legacy else valid_request()
            case["plan"]["implementation_steps"][0].update(deepcopy(scope))
            if legacy:
                sync_legacy_scope(case)
                reseal_legacy(case)
                case.update(boundary="dispatch", target_packet_id="source-outcome")
            else:
                seal(case)
            result = expect(case, "accepted")
            for field, expected in scope.items():
                assert result["canonical_plan"]["implementation_steps"][0][field] == expected
                assert result["current_task_packet"][field] == expected
    case = legacy_request(True)
    expected_scopes = []
    for index, packet in enumerate(case["plan"]["implementation_steps"]):
        scope = deepcopy(path_scopes[index % len(path_scopes)])
        packet.update(scope)
        expected_scopes.append(scope)
    sync_legacy_scope(case)
    reseal_legacy(case)
    result = expect(case, "accepted")
    for packet, scope in zip(result["canonical_plan"]["implementation_steps"], expected_scopes):
        for field, expected in scope.items():
            assert packet[field] == expected
    case = deepcopy(one)
    case["context"]["readiness"]["execution_intent"] = "prepare_only"
    expect(case, "blocked", "no_execution")
    for mutation in ("command", "cwd", "failed", "partial", "missing", "acceptance", "binding", "lane", "self_check", "stale", "native"):
        case = valid_request(boundary="verification")
        packet = case["plan"]["implementation_steps"][0]
        packet["execution"]["state"] = "RUNNING"
        result = evidence(case, packet)
        case["context"]["packet_evidence"][packet["packet_id"]] = result
        if mutation in {"command", "cwd"}:
            result["validation_results"][0]["executed_command"]["argv" if mutation == "command" else "cwd"] = ["wrong"] if mutation == "command" else "/wrong"
        elif mutation in {"failed", "partial"}:
            result["validation_results"][0]["result"] = mutation
        elif mutation == "missing":
            result["validation_results"] = []
        elif mutation == "acceptance":
            result["acceptance_results"] = []
        elif mutation == "binding":
            result["validation_results"][0]["binding_obligation_refs"] = []
        elif mutation == "lane":
            result["build_execution_lane"] = "bounded_executor"
        elif mutation == "self_check":
            result["self_check"]["result"] = "partial"
        elif mutation == "stale":
            result["input_identity"] = {"source": "old"}
        else:
            del result["native_evidence_ref"]
        expect(case, "blocked")
    # Current evidence verifies; relevant edits invalidate transitive dependents while retaining history.
    case = valid_request(boundary="verification")
    packet = case["plan"]["implementation_steps"][0]
    packet["execution"]["state"] = "RUNNING"
    case["context"]["packet_evidence"][packet["packet_id"]] = evidence(case, packet)
    assert expect(case, "accepted")["canonical_plan"]["implementation_steps"][0]["execution"]["state"] == "VERIFIED"
    case = verify_all(valid_request(3, "resume"))
    case["context"]["previous_plan"] = deepcopy(case["plan"])
    case["context"]["current_input_identities"]["accepted-outcome"] = {"source": "changed"}
    result = expect(case, "accepted")
    assert all(p["execution"]["state"] == "INVALIDATED" and p["execution"]["history"] for p in result["canonical_plan"]["implementation_steps"])
    case = valid_request(boundary="resume")
    case["plan"]["implementation_steps"][0]["execution"]["recovery"] = {"attempt_count": 1, "no_progress_count": 1}
    case["context"]["previous_plan"] = deepcopy(case["plan"])
    case["plan"]["implementation_steps"][0]["execution"]["recovery"]["attempt_count"] = 0
    expect(case, "blocked", "recovery_mismatch")
    # Current recovery-owner evidence may reset consecutive no-progress, while
    # cumulative attempts and retained history/evidence remain nondecreasing.
    case = valid_request(boundary="resume")
    packet = case["plan"]["implementation_steps"][0]
    packet["execution"].update(recovery={"attempt_count": 1, "no_progress_count": 1},
        history=[{"reason": "Prior failed check", "evidence_ref": "repair:prior"}], evidence_refs=["repair:prior"])
    case["context"]["previous_plan"] = deepcopy(case["plan"])
    packet["execution"]["recovery"] = {"attempt_count": 2, "no_progress_count": 0}
    packet["execution"]["history"].append({"reason": "Measurable progress: focused check now passes", "evidence_ref": "repair:progress"})
    packet["execution"]["evidence_refs"].append("repair:progress")
    case["context"]["recovery_counters"][packet["packet_id"]] = deepcopy(packet["execution"]["recovery"])
    result = expect(case, "accepted", name="current recovery owner attests measurable-progress reset")
    assert result["canonical_plan"]["implementation_steps"][0]["execution"] == packet["execution"]
    for mutation in ("owner_mismatch", "cumulative_reset", "lost_history", "lost_evidence"):
        trial = deepcopy(case)
        execution = trial["plan"]["implementation_steps"][0]["execution"]
        if mutation == "owner_mismatch": trial["context"]["recovery_counters"][packet["packet_id"]]["no_progress_count"] = 1
        elif mutation == "cumulative_reset":
            execution["recovery"]["attempt_count"] = 0
            trial["context"]["recovery_counters"][packet["packet_id"]] = deepcopy(execution["recovery"])
        elif mutation == "lost_history": execution["history"] = execution["history"][1:]
        else: execution["evidence_refs"].remove("repair:prior")
        expect(trial, "blocked", "recovery_mismatch", name=mutation)
    # Persisted ancestor states cannot hide behind a retained VERIFIED middle
    # result. Independent workspace witnesses remove unrelated overlap barriers.
    for ancestor_state in ("PENDING", "RUNNING", "BLOCKED", "INVALIDATED"):
        for writer in (False, True):
            for failed_evidence in (False, True):
                case = valid_request(3, "resume")
                if not writer:
                    case["plan"]["implementation_steps"][0]["files_to_modify"] = []
                    seal(case)
                verify_all(case)
                first, middle, last = case["plan"]["implementation_steps"]
                first["execution"]["state"] = ancestor_state
                last["execution"]["state"] = "PENDING"
                # These states were persisted before resume, not caller downgrades
                # from a different independently retained VERIFIED snapshot.
                case["context"]["previous_plan"] = deepcopy(case["plan"])
                if failed_evidence:
                    case["context"]["packet_evidence"][first["packet_id"]]["validation_results"][0]["result"] = "failed"
                if writer:
                    case["context"]["workspace"] = {"mode": "isolated", "active_source_writer_ids": [first["packet_id"]],
                        "isolation": {p["packet_id"]: {"current": True, "input_identity": deepcopy(p["execution"]["input_identity"]),
                            "runtime_evidence_ref": "runtime:ancestor:" + p["packet_id"],
                            "workspace_identity": "isolated:ancestor:" + p["packet_id"]} for p in case["plan"]["implementation_steps"]}}
                result = expect(case, "accepted", name="reconcile persisted " + ancestor_state)
                reconciled = result["canonical_plan"]["implementation_steps"]
                assert all(p["execution"]["state"] == "INVALIDATED" and p["execution"]["history"] for p in reconciled[1:]), (ancestor_state, writer, failed_evidence, result)
                assert reconciled[0]["execution"]["state"] == ancestor_state
                for before, after in zip(case["plan"]["implementation_steps"], reconciled):
                    assert after["execution"]["evidence_refs"] == before["execution"]["evidence_refs"]
                case.update(boundary="dispatch", target_packet_id=last["packet_id"])
                expect(case, "blocked", "prerequisite_unverified", name="persisted ancestor blocks downstream dispatch")
    # Independent overlap needs distinct, current runtime isolation, not a label.
    case = valid_request(2)
    case["plan"]["implementation_steps"][1]["depends_on"] = []
    case["plan"]["implementation_steps"][0]["execution"]["state"] = "RUNNING"
    case["target_packet_id"] = "dependent-outcome"
    seal(case)
    for mode in ("shared", "unknown", "isolated"):
        trial = deepcopy(case)
        trial["context"]["workspace"] = {"mode": mode, "active_source_writer_ids": ["accepted-outcome"]}
        expect(trial, "blocked")
    case["context"]["workspace"] = {"mode": "isolated", "active_source_writer_ids": ["accepted-outcome"], "isolation": {p["packet_id"]: {"current": True, "input_identity": p["execution"]["input_identity"],
             "runtime_evidence_ref": "runtime:" + p["packet_id"], "workspace_identity": "workspace:" + p["packet_id"]} for p in case["plan"]["implementation_steps"]}}
    expect(case, "accepted")
    case["context"]["workspace"]["isolation"]["dependent-outcome"]["workspace_identity"] = "workspace:accepted-outcome"
    expect(case, "blocked", "workspace_overlap")
    # Candidate state cannot hide independently observed active writers.
    case["context"]["workspace"]["mode"] = "shared"
    case["plan"]["implementation_steps"][0]["execution"]["state"] = "PENDING"
    expect(case, "blocked", "workspace_overlap")
    # Independently active same-packet Writers block another Writer or Builder,
    # even if a candidate calls the redispatch a stage or labels the workspace isolated.
    case = valid_request()
    packet = case["plan"]["implementation_steps"][0]
    packet["execution"]["state"] = "RUNNING"
    case["context"]["packet_evidence"][packet["packet_id"]] = evidence(case, packet)
    for mode in ("shared", "unknown", "isolated"):
        case["context"]["workspace"] = {"mode": mode, "active_source_writer_ids": [packet["packet_id"]]}
        for stage, role in (("implementation", "code_writer"), ("final_verification", "builder_tester")):
            case.update(worker_stage=stage, worker_role=role)
            expect(case, "blocked", "workspace_overlap")
    case["context"]["workspace"]["active_source_writer_ids"] = []  # Actual Writer is terminal.
    case.update(worker_stage="final_verification", worker_role="builder_tester")
    for count, no_progress, status in ((1, 0, "blocked"), (2, 0, "blocked"), (3, 0, "blocked"),
                                       (4, 0, "blocked"), (3, 2, "blocked")):
        trial = deepcopy(case)
        counters = {"attempt_count": count, "no_progress_count": no_progress}
        trial["plan"]["implementation_steps"][0]["execution"]["recovery"] = deepcopy(counters)
        trial["context"]["recovery_counters"][packet["packet_id"]] = deepcopy(counters)
        expect(trial, status, "accepted" if status == "accepted" else "progress_history_missing")
    for state in ("PENDING", "RUNNING"):
        trial = deepcopy(case)
        trial.update(worker_stage="implementation", worker_role="code_writer")
        trial["plan"]["implementation_steps"][0]["execution"].update(state=state, recovery={"attempt_count": 3, "no_progress_count": 0})
        trial["context"]["recovery_counters"][packet["packet_id"]] = {"attempt_count": 3, "no_progress_count": 0}
        expect(trial, "blocked", "progress_history_missing")
    # Caller-resolved applicability preserves truthful no-tests evidence across all consumers.
    for command in (False, True):
        case = no_tests_request(command)
        before_definition = expected_current_definition(case["plan"])
        accepted = expect(case, "accepted")
        packet = case["plan"]["implementation_steps"][0]
        proof = case["context"]["packet_evidence"][packet["packet_id"]]
        if API.definition(accepted["canonical_plan"]) != before_definition or "tests" in proof:
            raise AssertionError("Applicability changed approved work or invented test provenance")
        assert_current_approval(case["plan"], accepted["canonical_plan"])
        dispatched = deepcopy(case)
        dispatched.update(boundary="dispatch", worker_stage="final_verification", worker_role="builder_tester")
        expect(dispatched, "accepted")
        # Initial inactive Writer may be unknown; later verifier may not.
        initial = deepcopy(case)
        initial.update(boundary="dispatch", worker_stage="production", worker_role="code_writer")
        initial["context"]["writer_actor_ids"] = {}
        initial["context"]["packet_evidence"][packet["packet_id"]].pop("writer_actor_id")
        expect(initial, "accepted")
        initial.update(worker_stage="final_verification", worker_role="builder_tester")
        expect(initial, "blocked", "writer_lineage")
        completed = deepcopy(case)
        completed["plan"] = deepcopy(accepted["canonical_plan"])
        completed["context"] = deepcopy(accepted["canonical_context"])
        completed["boundary"] = "completion"
        completed["context"].update(current_snapshot_identity="snapshot:no-tests", required_terminal_gates=["independent_review"])
        completed["context"]["completion_evidence"] = {
            "approved_plan_identity": deepcopy(completed["plan"]["approved_plan_identity"]),
            "snapshot_identity": "snapshot:no-tests", "acceptance_results": [],
            "validation_results": [{"selected_check_ids": ["focused"], "binding_obligation_refs": [], "result": "passed",
                "evidence_ref": "completion:focused", "executed_command": {"check_id": "focused", **deepcopy(case["context"]["verification_decision"]["checks"][0]["command"])}},
                {"selected_check_ids": ["integrated"], "binding_obligation_refs": [], "result": "passed", "evidence_ref": "completion:integrated",
                 **({"executed_command": {"check_id": "integrated", **deepcopy(case["context"]["verification_decision"]["checks"][1]["command"])}}
                    if command else {"procedure": "Inspect the current integrated acceptance evidence"})}],
            "terminal_gates": {"independent_review": {"passed": True, "after_integration": True,
                "snapshot_identity": "snapshot:no-tests", "evidence_ref": "review:actual"}}}
        expect(completed, "accepted")
    case = no_tests_request()
    for mutation in ("missing_map", "missing_row", "unknown_status", "unresolved", "approval", "packet", "input",
                     "lane", "decision", "checks", "binding", "resolution_ref", "rationale", "contradictory_tests"):
        trial = deepcopy(case)
        row = trial["context"]["test_applicability"]["accepted-outcome"]
        if mutation == "missing_map": trial["context"].pop("test_applicability")
        elif mutation == "missing_row": trial["context"]["test_applicability"] = {}
        elif mutation in {"unknown_status", "unresolved"}: row["status"] = "unknown" if mutation == "unknown_status" else "unresolved"
        elif mutation == "approval": row["approved_plan_identity"]["approval_ref"] = "approval:stale"
        elif mutation == "packet": row["packet_definition_digest"] = "stale"
        elif mutation == "input": row["input_identity"] = {"source": "stale"}
        elif mutation == "lane": row["build_execution_lane"] = "bounded_executor"
        elif mutation == "decision": row["verification_decision_ref"]["artifact_ref"] = "decision:stale"
        elif mutation == "checks": row["selected_check_ids"] = []
        elif mutation == "binding": row["binding_obligation_refs"] = []
        elif mutation in {"resolution_ref", "rationale"}: row[mutation] = ""
        else: trial["context"]["packet_evidence"]["accepted-outcome"]["tests"] = {"mode": "reuse", "evidence_ref": "tests:invented"}
        expect(trial, "blocked", name="no-tests applicability " + mutation)
    for mutation in ("actor", "current_actor", "self_check", "acceptance", "selected", "binding", "implementation", "native", "builder"):
        trial = no_tests_request()
        ev = trial["context"]["packet_evidence"]["accepted-outcome"]
        if mutation == "actor": ev["writer_actor_id"] = "native:wrong"
        elif mutation == "current_actor": trial["context"]["writer_actor_ids"] = {}
        elif mutation == "self_check": ev["self_check"]["result"] = "partial"
        elif mutation == "acceptance": ev["acceptance_results"] = []
        elif mutation == "selected": ev["validation_results"] = []
        elif mutation == "binding": ev["validation_results"][0]["binding_obligation_refs"] = []
        else: ev.pop({"implementation": "implementation_evidence_ref", "native": "native_evidence_ref", "builder": "builder_evidence_ref"}[mutation])
        expect(trial, "blocked", name="no-tests retains " + mutation)
    for stage in ("test_authoring", "pre_production_red"):
        trial = no_tests_request()
        trial.update(boundary="dispatch", worker_stage=stage,
                     worker_role="builder_tester" if stage == "pre_production_red" else "code_writer")
        expect(trial, "blocked", "test_applicability")
    active = current_authored_dispatch()
    active["context"]["test_applicability"]["accepted-outcome"]["status"] = "not_applicable"
    expect(active, "blocked", "test_applicability")
    # A non-command procedure may still semantically require tests; method never overrides the owner.
    required = no_tests_request()
    required["context"]["test_applicability"]["accepted-outcome"] = applicability(required, required["plan"]["implementation_steps"][0])
    for mode in (None, "not_applicable"):
        trial = deepcopy(required)
        if mode is not None: trial["context"]["packet_evidence"]["accepted-outcome"]["tests"] = {"mode": mode, "evidence_ref": "tests:forged"}
        expect(trial, "blocked")
    # Pending Plan construction needs no fabricated applicability resolution.
    pending = valid_request(boundary="plan")
    pending["context"].pop("test_applicability")
    expect(pending, "accepted")
    pending["boundary"] = "dispatch"
    expect(pending, "blocked")
    # A selected non-command check is valid without inventing an executable.
    case = valid_request(boundary="verification")
    packet = case["plan"]["implementation_steps"][0]
    packet["selected_check_ids"] = ["integrated"]
    packet.pop("verification_command")
    case["plan"]["completion_allocation"]["selected_check_ids"] = ["focused", "integrated"]
    seal(case)
    packet["execution"]["state"] = "RUNNING"
    case["context"]["packet_evidence"][packet["packet_id"]] = evidence(case, packet)
    expect(case, "accepted")
    case["context"]["packet_evidence"][packet["packet_id"]]["validation_results"][0]["procedure"] = "Read any old artifact"
    expect(case, "blocked", "procedure_mismatch")
    # Same approved packet materializes through every real separated TDD stage.
    case = valid_request(boundary="plan")
    decision = case["context"]["verification_decision"]
    decision["tdd_choice"] = {"mode": True, "applicable_check_ids": ["focused"]}
    ref = {"artifact_ref": "verification:tdd", "sha256": API.digest(decision)}
    case["context"]["verification_decision_ref"] = case["plan"]["verification_decision_ref"] = deepcopy(ref)
    packet = case["plan"]["implementation_steps"][0]
    packet.update({"verification_decision_ref": deepcopy(ref), "tdd_applies": True, "red_check_id": "focused", "red_command": decision["checks"][0]["command"]["argv"],
                   "red_cwd": "/workspace", "expected_red_failure": "Expected behavior is absent"})
    seal(case)
    approved = deepcopy(case["plan"]["approved_plan_identity"])
    expect(case, "accepted")  # No actual cycle or fabricated ref exists before RED.
    # Completion cannot be the only owner of an applicable TDD check.
    completion_only = deepcopy(case)
    inactive = completion_only["plan"]["implementation_steps"][0]
    inactive.update(selected_check_ids=["integrated"], tdd_applies=False)
    inactive.pop("verification_command")
    for field in ("red_check_id", "red_command", "red_cwd", "expected_red_failure"):
        inactive.pop(field)
    completion_only["plan"]["completion_allocation"]["selected_check_ids"] = ["focused", "integrated"]
    seal(completion_only)
    expect(completion_only, "blocked", "tdd_mismatch")
    # One allocated active check cannot hide another applicable orphan.
    orphan = deepcopy(case)
    choice = orphan["context"]["verification_decision"]
    other = deepcopy(choice["checks"][0])
    other.update(check_id="other-active", command={"argv": ["python3", "other.py"], "cwd": "/workspace"})
    other["check_ref_or_method"]["meaningful_failure"] = "Other expected behavior is absent"
    choice["checks"].append(other)
    choice["tdd_choice"]["applicable_check_ids"].append("other-active")
    orphan_ref = {"artifact_ref": "verification:tdd-orphan", "sha256": API.digest(choice)}
    orphan["context"]["verification_decision_ref"] = deepcopy(orphan_ref)
    orphan["plan"]["verification_decision_ref"] = deepcopy(orphan_ref)
    orphan["plan"]["implementation_steps"][0]["verification_decision_ref"] = deepcopy(orphan_ref)
    orphan["plan"]["completion_allocation"]["selected_check_ids"].append("other-active")
    seal(orphan)
    expect(orphan, "blocked", "tdd_mismatch")
    # Repeated active packet owners and completion remain legal beside inactive work.
    repeated = valid_request(3, "plan")
    repeated["context"]["verification_decision"] = deepcopy(decision)
    repeated["context"]["verification_decision_ref"] = deepcopy(ref)
    repeated["plan"]["verification_decision_ref"] = deepcopy(ref)
    for index, owner in enumerate(repeated["plan"]["implementation_steps"]):
        owner["verification_decision_ref"] = deepcopy(ref)
        if index < 2:
            owner.update(tdd_applies=True, red_check_id="focused", red_command=deepcopy(packet["red_command"]),
                         red_cwd=packet["red_cwd"], expected_red_failure=packet["expected_red_failure"])
        else:
            owner["selected_check_ids"] = ["integrated"]
            owner.pop("verification_command")
    repeated["plan"]["completion_allocation"]["selected_check_ids"] = ["focused", "integrated"]
    seal(repeated)
    admitted = expect(repeated, "accepted")
    assert [owner["tdd_applies"] for owner in admitted["canonical_plan"]["implementation_steps"]] == [True, True, False]
    case.update(boundary="dispatch", worker_stage="pre_production_red", worker_role="builder_tester")
    first = expect(case, "accepted")
    assert "tdd_cycle_log_ref" not in first["current_task_packet"]
    assert "red_evidence" not in first["current_task_packet"]
    packet["execution"]["state"] = "RUNNING"
    # The RED owner is terminal; no source Writer is still active at transition.
    case["context"]["workspace"]["active_source_writer_ids"] = []
    case.update(worker_stage="production", worker_role="code_writer")
    expect(case, "blocked")  # No actual RED yet.
    packet["execution"]["tdd_cycle_log_ref"] = "cycle:actual"
    ev = evidence(case, packet)
    ev.pop("implementation_evidence_ref")
    case["context"]["packet_evidence"][packet["packet_id"]] = ev
    ev["tdd_cycle"] = {"tdd_cycle_log_ref": "cycle:actual", "red": {
        "check_id": "focused", "test_file": "verify.py", "test_name": "Expected behavior",
        "command": deepcopy(packet["red_command"]), "cwd": "/workspace",
        "failure_summary": "AssertionError: expected [accepted], observed [] at verify.py:17",
        "right_reason": "The target assertion ran and demonstrated that the accepted behavior is absent."},
        "red_phase": {"test_file": "verify.py", "test_name": "Expected behavior", "verified_failing": True,
            "failure_reason": "The behavior assertion failed because the accepted outcome has not been implemented.",
            "command_results": [{"target": "verify.py :: Expected behavior", "test_file": "verify.py",
                "test_name": "Expected behavior", "check_id": "focused", "argv": deepcopy(packet["red_command"]),
                "cwd": "/workspace", "result": "failed", "freshness": "current"}]}}
    current = expect(case, "accepted")
    assert current["current_task_packet"]["tdd_cycle_log_ref"] == "cycle:actual"
    # Required fields do not forbid metadata supplied by the canonical producer.
    metadata = deepcopy(case)
    metadata_red = metadata["context"]["packet_evidence"][packet["packet_id"]]["tdd_cycle"]["red"]
    metadata_red["producer_metadata"] = {"diagnostic_ref": "actual-red-diagnostic:17"}
    retained_red = deepcopy(metadata_red)
    with_metadata = expect(metadata, "accepted")
    assert metadata_red == retained_red
    assert with_metadata["current_task_packet"]["red_evidence"] == retained_red
    # The actual diagnostic and producer explanation need not copy oracle prose.
    for mutation in ("omitted", "unverified", "blank_reason", "phase_file", "phase_name", "missing_invocation",
                     "stale", "passed", "wrong_check", "wrong_file", "wrong_name", "wrong_command", "wrong_cwd", "duplicate"):
        trial = deepcopy(case)
        cycle = trial["context"]["packet_evidence"][packet["packet_id"]]["tdd_cycle"]
        phase = cycle["red_phase"]
        row = phase["command_results"][0]
        if mutation == "omitted": del cycle["red_phase"]
        elif mutation == "unverified": phase["verified_failing"] = False
        elif mutation == "blank_reason": phase["failure_reason"] = ""
        elif mutation == "phase_file": phase["test_file"] = "other.py"
        elif mutation == "phase_name": phase["test_name"] = "Other behavior"
        elif mutation == "missing_invocation": phase["command_results"] = []
        elif mutation == "stale": row["freshness"] = "stale"
        elif mutation == "passed": row["result"] = "passed"
        elif mutation == "wrong_check": row["check_id"] = "integrated"
        elif mutation == "wrong_file": row["test_file"] = "other.py"
        elif mutation == "wrong_name": row["test_name"] = "Other behavior"
        elif mutation == "wrong_command": row["argv"] = ["python3", "other.py"]
        elif mutation == "wrong_cwd": row["cwd"] = "/other"
        else: phase["command_results"].append(deepcopy(row))
        expect(trial, "blocked")
    # Retain other invocations unchanged; only a matching current failed one authorizes.
    unrelated = deepcopy(case)
    retained_phase = unrelated["context"]["packet_evidence"][packet["packet_id"]]["tdd_cycle"]["red_phase"]
    retained_phase["command_results"].append({"target": "other.py :: retained failed check", "test_file": "other.py",
        "test_name": "Unrelated behavior", "argv": ["python3", "other.py"], "cwd": "/workspace",
        "result": "failed", "freshness": "current"})
    retained = deepcopy(retained_phase)
    admitted = expect(unrelated, "accepted")
    assert retained_phase == retained
    assert admitted["current_task_packet"]["red_evidence"] == ev["tdd_cycle"]["red"]
    assert "red_phase" not in admitted["current_task_packet"]
    for field, value in (("target", ""), ("argv", []), ("cwd", ""), ("result", "syntax_error"), ("freshness", "guessed")):
        trial = deepcopy(unrelated)
        trial["context"]["packet_evidence"][packet["packet_id"]]["tdd_cycle"]["red_phase"]["command_results"][1][field] = value
        expect(trial, "blocked")
    assert current["current_task_packet"]["red_evidence"] == ev["tdd_cycle"]["red"]
    assert "red_evidence" not in current["canonical_plan"]["implementation_steps"][0]
    current["current_task_packet"]["red_evidence"]["command"].append("mutated-copy")
    assert ev["tdd_cycle"]["red"]["command"] == packet["red_command"]
    for mutation in ("omit", "change"):
        trial = deepcopy(case)
        trial["current_task_packet"] = expect(case, "accepted")["current_task_packet"]
        if mutation == "omit":
            trial["current_task_packet"].pop("red_evidence")
        else:
            trial["current_task_packet"]["red_evidence"]["failure_summary"] = "different failure"
        expect(trial, "blocked", "projection_mismatch")
    for owner in ("packet", "plan"):
        for field, observed in (("red_evidence", ev["tdd_cycle"]["red"]), ("red_phase", ev["tdd_cycle"]["red_phase"]),
                                ("test_applicability", {"status": "not_applicable"})):
            stored = deepcopy(case)
            target = stored["plan"]["implementation_steps"][0] if owner == "packet" else stored["plan"]
            target[field] = deepcopy(observed)
            seal(stored)
            expect(stored, "blocked", "mixed_schema")
    bounded = deepcopy(case)
    bounded["context"]["build_execution_lane"] = "bounded_executor"
    bounded["context"]["test_applicability"] = {p["packet_id"]: applicability(bounded, p) for p in bounded["plan"]["implementation_steps"]}
    bounded["context"]["packet_evidence"][packet["packet_id"]]["build_execution_lane"] = "bounded_executor"
    assert "red_evidence" not in expect(bounded, "accepted")["current_task_packet"]
    refactor = deepcopy(case)
    refactor["worker_stage"] = "refactor"
    refactor_evidence = refactor["context"]["packet_evidence"][packet["packet_id"]]
    refactor_evidence["implementation_evidence_ref"] = "writer:actual"
    refactor_evidence["tdd_cycle"]["green"] = {"all_tests_pass": True, "command": deepcopy(packet["red_command"]),
        "cwd": packet["red_cwd"], "production_file": "src/result.py", "invocation_ref": "green:actual"}
    assert expect(refactor, "accepted")["current_task_packet"]["red_evidence"] == ev["tdd_cycle"]["red"]
    for lane in ("separated_workers", "bounded_executor"):
        for count, status in ((3, "blocked"), (4, "blocked")):
            trial = deepcopy(case)
            trial["context"]["build_execution_lane"] = lane
            trial["context"]["test_applicability"] = {p["packet_id"]: applicability(trial, p) for p in trial["plan"]["implementation_steps"]}
            if lane == "bounded_executor": trial["worker_role"] = "code_writer"
            trial["context"]["packet_evidence"][packet["packet_id"]]["build_execution_lane"] = lane
            trial["plan"]["implementation_steps"][0]["execution"]["recovery"] = {"attempt_count": count, "no_progress_count": 0}
            trial["context"]["recovery_counters"][packet["packet_id"]] = {"attempt_count": count, "no_progress_count": 0}
            expect(trial, status, "accepted" if status == "accepted" else "progress_history_missing")
    active = deepcopy(case)
    active["context"]["workspace"]["active_source_writer_ids"] = [packet["packet_id"]]
    expect(active, "blocked", "workspace_overlap")
    for field, value in (("right_reason", True), ("right_reason", ""), ("command", ["python3", "wrong.py"]),
                         ("cwd", "/wrong"), ("check_id", "integrated"), ("failure_summary", "")):
        mismatch = deepcopy(case)
        mismatch["context"]["packet_evidence"][packet["packet_id"]]["tdd_cycle"]["red"][field] = value
        expect(mismatch, "blocked")
    case.update(worker_stage="green", worker_role="builder_tester")
    expect(case, "blocked")  # Production has not been recorded.
    ev["implementation_evidence_ref"] = "writer:actual-production"
    ev["tdd_cycle"]["green"] = {"production_file": "accepted-outcome.py"}
    expect(case, "accepted")
    for lane in ("separated_workers", "bounded_executor"):
        for count, status in ((3, "blocked"), (4, "blocked")):
            trial = deepcopy(case)
            trial["context"]["build_execution_lane"] = lane
            trial["context"]["test_applicability"] = {p["packet_id"]: applicability(trial, p) for p in trial["plan"]["implementation_steps"]}
            if lane == "bounded_executor": trial["worker_role"] = "code_writer"
            trial["context"]["packet_evidence"][packet["packet_id"]]["build_execution_lane"] = lane
            trial["plan"]["implementation_steps"][0]["execution"]["recovery"] = {"attempt_count": count, "no_progress_count": 0}
            trial["context"]["recovery_counters"][packet["packet_id"]] = {"attempt_count": count, "no_progress_count": 0}
            expect(trial, status, "accepted" if status == "accepted" else "progress_history_missing")
    active = deepcopy(case)
    active["context"]["workspace"]["active_source_writer_ids"] = [packet["packet_id"]]
    expect(active, "blocked", "workspace_overlap")
    case.update(worker_stage="refactor", worker_role="code_writer")
    expect(case, "blocked", "tdd_evidence")  # GREEN must actually pass first.
    ev["tdd_cycle"]["green"].update(all_tests_pass=True, command=packet["red_command"], cwd="/workspace", invocation_ref="green:actual")
    expect(case, "accepted")
    for lane in ("separated_workers", "bounded_executor"):
        for count, status in ((3, "blocked"), (4, "blocked")):
            trial = deepcopy(case)
            trial["context"]["build_execution_lane"] = lane
            trial["context"]["test_applicability"] = {p["packet_id"]: applicability(trial, p) for p in trial["plan"]["implementation_steps"]}
            if lane == "bounded_executor": trial["worker_role"] = "code_writer"
            trial["context"]["packet_evidence"][packet["packet_id"]]["build_execution_lane"] = lane
            trial["plan"]["implementation_steps"][0]["execution"]["recovery"] = {"attempt_count": count, "no_progress_count": 0}
            trial["context"]["recovery_counters"][packet["packet_id"]] = {"attempt_count": count, "no_progress_count": 0}
            expect(trial, status, "accepted" if status == "accepted" else "progress_history_missing")
    active = deepcopy(case)
    active["context"]["workspace"]["active_source_writer_ids"] = [packet["packet_id"]]
    expect(active, "blocked", "workspace_overlap")
    case.update(worker_stage="refactor_verification", worker_role="builder_tester")
    expect(case, "blocked")
    ev["tdd_cycle"]["refactor"] = {"changes_made": "none needed"}
    expect(case, "accepted")
    for lane in ("separated_workers", "bounded_executor"):
        for count, status in ((3, "blocked"), (4, "blocked")):
            trial = deepcopy(case)
            trial["context"]["build_execution_lane"] = lane
            trial["context"]["test_applicability"] = {p["packet_id"]: applicability(trial, p) for p in trial["plan"]["implementation_steps"]}
            if lane == "bounded_executor": trial["worker_role"] = "code_writer"
            trial["context"]["packet_evidence"][packet["packet_id"]]["build_execution_lane"] = lane
            trial["plan"]["implementation_steps"][0]["execution"]["recovery"] = {"attempt_count": count, "no_progress_count": 0}
            trial["context"]["recovery_counters"][packet["packet_id"]] = {"attempt_count": count, "no_progress_count": 0}
            expect(trial, status, "accepted" if status == "accepted" else "progress_history_missing")
    active = deepcopy(case)
    active["context"]["workspace"]["active_source_writer_ids"] = [packet["packet_id"]]
    expect(active, "blocked", "workspace_overlap")
    case["boundary"] = "verification"
    expect(case, "blocked", "tdd_evidence")  # A recorded refactor is not its rerun.
    ev["tdd_cycle"]["refactor"].update(all_tests_pass=True, command=packet["red_command"], cwd="/workspace", invocation_ref="refactor:actual")
    expect(case, "accepted")
    assert case["plan"]["approved_plan_identity"] == approved and API.digest(API.definition(case["plan"])) == approved["definition_digest"]
    ev["tdd_cycle"]["refactor"]["invocation_ref"] = "green:actual"
    expect(case, "blocked", "tdd_evidence")
    wrong_role = deepcopy(case)
    wrong_role.update(boundary="dispatch", worker_stage="production", worker_role="builder_tester")
    expect(wrong_role, "blocked", "worker_stage")
    # Inactive TDD keeps Writer -> Builder on the same packet, with no cycle.
    case = valid_request()
    expect(case, "accepted")
    packet = case["plan"]["implementation_steps"][0]
    packet["execution"]["state"] = "RUNNING"
    case.update(worker_stage="final_verification", worker_role="builder_tester")
    expect(case, "blocked")
    case["context"]["packet_evidence"][packet["packet_id"]] = evidence(case, packet)
    current = expect(case, "accepted")
    assert "tdd_cycle_log_ref" not in current["current_task_packet"]
    # Full integration is due with one packet as well as multiple packets.
    for count in (1, 3):
        case = verify_all(valid_request(count, "completion"))
        case["context"].update({"current_snapshot_identity": "snapshot:current", "required_terminal_gates": ["independent_review", "qa"]})
        comp = {"approved_plan_identity": deepcopy(case["plan"]["approved_plan_identity"]), "snapshot_identity": "snapshot:current", "acceptance_results": [],
                "validation_results": [{"selected_check_ids": ["integrated"], "binding_obligation_refs": [], "result": "passed", "evidence_ref": "integration:actual", "procedure": "Inspect the current integrated acceptance evidence"}],
                "terminal_gates": {key: {"passed": True, "after_integration": True, "snapshot_identity": "snapshot:current", "evidence_ref": key + ":actual"} for key in ("independent_review", "qa")}}
        case["context"]["completion_evidence"] = comp
        expect(case, "accepted")
        active = deepcopy(case)
        active["context"]["workspace"]["active_source_writer_ids"] = ["accepted-outcome"]
        refused = expect(active, "blocked", "incomplete_packets", name="active Writer refuses otherwise-valid completion")
        assert all(p["execution"]["state"] == "INVALIDATED" and p["execution"]["history"]
                   for p in refused["canonical_plan"]["implementation_steps"])
        for mutation in ("qa", "snapshot", "review_order"):
            trial = deepcopy(case)
            if mutation == "qa": del trial["context"]["completion_evidence"]["terminal_gates"]["qa"]
            elif mutation == "snapshot": trial["context"]["completion_evidence"]["snapshot_identity"] = "snapshot:old"
            else: trial["context"]["completion_evidence"]["terminal_gates"]["independent_review"]["after_integration"] = False
            expect(trial, "blocked")
        comp["validation_results"] = []
        expect(case, "blocked", "check_evidence")
    for many in (False, True):
        case = legacy_request(many)
        original = deepcopy(case["plan"])
        result = expect(case, "accepted")
        assert case["plan"] == original
        if many:
            packets = result["canonical_plan"]["implementation_steps"]
            assert packets[2]["depends_on"] == ["accepted-outcome", "dependent-outcome"]
            assert packets[1]["depends_on"] == ["accepted-outcome"]
        for mutation in ("version", "source", "allocation", "mapping", "mixed", "cycle"):
            trial = deepcopy(case)
            if mutation == "version": trial["context"]["legacy"]["producer"]["schema_version"] = "unknown"
            elif mutation == "source": trial["context"]["legacy"]["source_sha256"] = "stale"
            elif mutation == "allocation":
                trial["plan"]["slice_manifest"][0]["selected_check_ids"].append("lost-check")
                trial["context"]["legacy"]["source_sha256"] = API.digest(trial["plan"])
            elif mutation == "mapping": trial["context"]["legacy"]["packet_mapping"] = [{"source_packet_index": 999, "slice_id": "source-outcome", "packet_id": "unknown-outcome"}]
            elif mutation == "mixed": trial["plan"]["plan_schema_version"] = "14.0"
            else:
                trial["plan"]["slice_manifest"][0]["depends_on"] = ["source-outcome"]
                trial["context"]["legacy"]["source_sha256"] = API.digest(trial["plan"])
            expect(trial, "blocked")
    case = legacy_request(True)
    context = case["context"]
    criterion = "All source outcomes integrate without aggregate regression"
    aggregate_binding = {"kind": "required_scope", "value": "Verify combined source outcomes", "source_ref": "authority:aggregate"}
    decision = context["verification_decision"]
    decision["checks"].append({"check_id": "aggregate", "method": "artifact_inspection",
                               "check_ref_or_method": {"reference_or_procedure": "Inspect combined source outcomes at completion"}})
    decision["policy_basis"]["binding_constraints"].append(aggregate_binding)
    context["verification_decision_ref"]["sha256"] = API.digest(decision)
    # Legacy records carried the full specialist object, but their original local
    # allocations must survive normalization without absorbing aggregate work.
    for owner in case["plan"]["slice_manifest"] + case["plan"]["implementation_steps"]:
        owner["verification_decision"] = deepcopy(decision)
    original_packets = deepcopy(case["plan"]["implementation_steps"])
    context["requirements"].append({"requirement_id": "R-aggregate", "acceptance_criterion": criterion})
    manifest = case["plan"]["slice_manifest"][0]
    manifest["requirement_ids"] = [rid for p in original_packets if p["slice_id"] == manifest["slice_id"] for rid in p["requirement_ids"]]
    aggregate = {"requirement_ids": "R-aggregate", "acceptance_criteria": criterion,
                 "selected_check_ids": "aggregate", "binding_obligation_refs": aggregate_binding}
    allocation = context["legacy"]["completion_allocation"]
    for field, value in aggregate.items():
        manifest[field].append(deepcopy(value))
        allocation[field].append(deepcopy(value))
    context["required_completion_allocation"] = deepcopy(allocation)
    context["legacy"]["source_sha256"] = API.digest(case["plan"])
    baseline = API.normalize_legacy(case["plan"], context)
    context["approved_plan_identity"]["definition_digest"] = API.digest(API.definition(baseline))
    admitted = expect(case, "accepted")
    assert case["plan"]["implementation_steps"] == original_packets
    assert admitted["canonical_plan"]["completion_allocation"] == allocation
    for original, normalized in zip(original_packets, admitted["canonical_plan"]["implementation_steps"]):
        for field in aggregate:
            assert normalized[field] == original[field], "Task-wide allocation changed original local work"
    for field, value in aggregate.items():
        missing = deepcopy(case)
        missing["context"]["legacy"]["completion_allocation"][field].remove(value)
        expect(missing, "blocked", "legacy_allocation")
    print(str(total) + " packet admission behavior controls passed")


if __name__ == "__main__":
    run_controls()
