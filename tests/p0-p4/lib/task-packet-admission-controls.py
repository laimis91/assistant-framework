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
    if observed["status"] != "accepted" or observed["canonical_plan"]["plan_schema_version"] != "14.0":
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


def run_controls():
    total = 0

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
    original_definition = API.digest(API.definition(case["plan"]))
    case.update(worker_stage="test_authoring", inline_worker_stage="test_authoring")
    case["context"]["writer_actor_ids"] = {}
    case["context"]["packet_evidence"] = {}
    result = expect(case, "accepted", name="first new writer actor is not fabricated")
    if result["worker_stage"] != result["current_task_packet"]["worker_stage"] or API.digest(API.definition(result["canonical_plan"])) != original_definition:
        raise AssertionError("Stage overlay changed approved work or inline agreement")
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
        definition_before = API.digest(API.definition(case["plan"]))
        result = expect(case, "accepted", name="same actual writer " + stage)
        if result["worker_stage"] != stage or result["current_task_packet"]["worker_stage"] != stage or API.digest(API.definition(result["canonical_plan"])) != definition_before:
            raise AssertionError("Valid stage lost overlay or stable approval")
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
                case["context"]["previous_plan"] = deepcopy(case["plan"])
                first, middle, last = case["plan"]["implementation_steps"]
                first["execution"]["state"] = ancestor_state
                last["execution"]["state"] = "PENDING"
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
    for count, no_progress, status in ((1, 0, "accepted"), (2, 0, "accepted"), (3, 0, "accepted"),
                                       (4, 0, "blocked"), (3, 2, "blocked")):
        trial = deepcopy(case)
        counters = {"attempt_count": count, "no_progress_count": no_progress}
        trial["plan"]["implementation_steps"][0]["execution"]["recovery"] = deepcopy(counters)
        trial["context"]["recovery_counters"][packet["packet_id"]] = deepcopy(counters)
        expect(trial, status, "accepted" if status == "accepted" else "recovery_exhausted")
    for state in ("PENDING", "RUNNING"):
        trial = deepcopy(case)
        trial.update(worker_stage="implementation", worker_role="code_writer")
        trial["plan"]["implementation_steps"][0]["execution"].update(state=state, recovery={"attempt_count": 3, "no_progress_count": 0})
        trial["context"]["recovery_counters"][packet["packet_id"]] = {"attempt_count": 3, "no_progress_count": 0}
        expect(trial, "blocked", "recovery_exhausted")
    # Caller-resolved applicability preserves truthful no-tests evidence across all consumers.
    for command in (False, True):
        case = no_tests_request(command)
        before_definition = API.digest(API.definition(case["plan"]))
        accepted = expect(case, "accepted")
        packet = case["plan"]["implementation_steps"][0]
        proof = case["context"]["packet_evidence"][packet["packet_id"]]
        if API.digest(API.definition(accepted["canonical_plan"])) != before_definition or "tests" in proof:
            raise AssertionError("Applicability changed approved work or invented test provenance")
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
        for count, status in ((3, "accepted"), (4, "blocked")):
            trial = deepcopy(case)
            trial["context"]["build_execution_lane"] = lane
            trial["context"]["test_applicability"] = {p["packet_id"]: applicability(trial, p) for p in trial["plan"]["implementation_steps"]}
            if lane == "bounded_executor": trial["worker_role"] = "code_writer"
            trial["context"]["packet_evidence"][packet["packet_id"]]["build_execution_lane"] = lane
            trial["plan"]["implementation_steps"][0]["execution"]["recovery"] = {"attempt_count": count, "no_progress_count": 0}
            trial["context"]["recovery_counters"][packet["packet_id"]] = {"attempt_count": count, "no_progress_count": 0}
            expect(trial, status, "accepted" if status == "accepted" else "recovery_exhausted")
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
        for count, status in ((3, "accepted"), (4, "blocked")):
            trial = deepcopy(case)
            trial["context"]["build_execution_lane"] = lane
            trial["context"]["test_applicability"] = {p["packet_id"]: applicability(trial, p) for p in trial["plan"]["implementation_steps"]}
            if lane == "bounded_executor": trial["worker_role"] = "code_writer"
            trial["context"]["packet_evidence"][packet["packet_id"]]["build_execution_lane"] = lane
            trial["plan"]["implementation_steps"][0]["execution"]["recovery"] = {"attempt_count": count, "no_progress_count": 0}
            trial["context"]["recovery_counters"][packet["packet_id"]] = {"attempt_count": count, "no_progress_count": 0}
            expect(trial, status, "accepted" if status == "accepted" else "recovery_exhausted")
    active = deepcopy(case)
    active["context"]["workspace"]["active_source_writer_ids"] = [packet["packet_id"]]
    expect(active, "blocked", "workspace_overlap")
    case.update(worker_stage="refactor", worker_role="code_writer")
    expect(case, "blocked", "tdd_evidence")  # GREEN must actually pass first.
    ev["tdd_cycle"]["green"].update(all_tests_pass=True, command=packet["red_command"], cwd="/workspace", invocation_ref="green:actual")
    expect(case, "accepted")
    for lane in ("separated_workers", "bounded_executor"):
        for count, status in ((3, "accepted"), (4, "blocked")):
            trial = deepcopy(case)
            trial["context"]["build_execution_lane"] = lane
            trial["context"]["test_applicability"] = {p["packet_id"]: applicability(trial, p) for p in trial["plan"]["implementation_steps"]}
            if lane == "bounded_executor": trial["worker_role"] = "code_writer"
            trial["context"]["packet_evidence"][packet["packet_id"]]["build_execution_lane"] = lane
            trial["plan"]["implementation_steps"][0]["execution"]["recovery"] = {"attempt_count": count, "no_progress_count": 0}
            trial["context"]["recovery_counters"][packet["packet_id"]] = {"attempt_count": count, "no_progress_count": 0}
            expect(trial, status, "accepted" if status == "accepted" else "recovery_exhausted")
    active = deepcopy(case)
    active["context"]["workspace"]["active_source_writer_ids"] = [packet["packet_id"]]
    expect(active, "blocked", "workspace_overlap")
    case.update(worker_stage="refactor_verification", worker_role="builder_tester")
    expect(case, "blocked")
    ev["tdd_cycle"]["refactor"] = {"changes_made": "none needed"}
    expect(case, "accepted")
    for lane in ("separated_workers", "bounded_executor"):
        for count, status in ((3, "accepted"), (4, "blocked")):
            trial = deepcopy(case)
            trial["context"]["build_execution_lane"] = lane
            trial["context"]["test_applicability"] = {p["packet_id"]: applicability(trial, p) for p in trial["plan"]["implementation_steps"]}
            if lane == "bounded_executor": trial["worker_role"] = "code_writer"
            trial["context"]["packet_evidence"][packet["packet_id"]]["build_execution_lane"] = lane
            trial["plan"]["implementation_steps"][0]["execution"]["recovery"] = {"attempt_count": count, "no_progress_count": 0}
            trial["context"]["recovery_counters"][packet["packet_id"]] = {"attempt_count": count, "no_progress_count": 0}
            expect(trial, status, "accepted" if status == "accepted" else "recovery_exhausted")
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
