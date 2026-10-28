#!/usr/bin/env python3
"""Pure v16 packet admission with authenticated v15/v14/v12/v13 reconciliation.

See references/plan-template.md, Packet admission wire boundary. CLI reads one JSON
request from stdin and writes one result. It cannot attest the caller's runtime facts.

Caller-trust boundary: caller-resolved values, such as historical attestation,
current digests and actor ids, are trusted inputs; the helper checks their
consistency, not their truth. Independence comes from fresh reviewers, not from
this script. For example, a caller that attests a migrated plan and relabels a
current-snapshot acceptance as a historical v9 direct_fallback is outside it.
"""

import sys

if sys.version_info < (3, 9):
    raise SystemExit("Python 3.9+ is required for Workflow packet admission. Install a supported interpreter and rerun before continuing.")

from copy import deepcopy
from dataclasses import dataclass, replace
from enum import Enum
import hashlib
import json
import math
import re
import importlib.util
from pathlib import Path


_progress_spec = importlib.util.spec_from_file_location(
    "assistant_shared_progress", Path(__file__).resolve().parents[3] / "tools/progress/stagnation.py")
PROGRESS = importlib.util.module_from_spec(_progress_spec)
sys.modules[_progress_spec.name] = PROGRESS
_progress_spec.loader.exec_module(PROGRESS)


MAX_BYTES = 2 * 1024 * 1024
MAX_PACKETS = 256
class PacketExecutionState(str, Enum):
    PENDING = "PENDING"
    RUNNING = "RUNNING"
    VERIFIED = "VERIFIED"
    BLOCKED = "BLOCKED"
    INVALIDATED = "INVALIDATED"


STATES = {state.value for state in PacketExecutionState}
BOUNDARIES = {"plan", "resume", "dispatch", "verification", "completion"}
ID_PATTERN = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z", re.ASCII)


class AdmissionError(ValueError):
    def __init__(self, code, path, details):
        super().__init__(details)
        self.code, self.path, self.details = code, path, details


def require(condition, code, path, details):
    if not condition:
        raise AdmissionError(code, path, details)


def text(value, path):
    require(isinstance(value, str) and bool(value.strip()), "malformed", path, "Expected nonblank string")
    return value


def object_value(value, path):
    require(isinstance(value, dict), "malformed", path, "Expected object")
    return value


def array(value, path):
    require(isinstance(value, list), "malformed", path, "Expected array")
    return value


def strings(value, path, nonempty=False):
    values = array(value, path)
    for item in values:
        text(item, path)
    require(len(values) == len(set(values)), "duplicate", path, "Entries must be unique")
    require(not nonempty or bool(values), "malformed", path, "Expected nonempty array")
    return values


def digest(value):
    """One canonical JSON encoding; rejects non-finite numbers and invalid Unicode."""
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                                    ensure_ascii=False, allow_nan=False).encode("utf-8")).hexdigest()


@dataclass(frozen=True)
class ExecutionPacketId:
    value: str

    @classmethod
    def parse(cls, value, path):
        text(value, path)
        require(bool(ID_PATTERN.fullmatch(value)) and len(value) <= 128
                and not re.fullmatch(r"(?:s|slice-|step-|packet-)?\d+", value),
                "invalid_packet_id", path, "Use a safe descriptive stable identifier; never normalize it")
        return cls(value)


@dataclass(frozen=True)
class CanonicalVerificationRef:
    artifact_ref: str
    sha256: str

    @classmethod
    def parse(cls, value, path):
        obj = object_value(value, path)
        require(set(obj) == {"artifact_ref", "sha256"}, "decision_identity", path, "Expected artifact_ref and sha256")
        text(obj["artifact_ref"], path)
        require(isinstance(obj["sha256"], str) and re.fullmatch(r"[0-9a-f]{64}", obj["sha256"]),
                "decision_identity", path, "Expected SHA-256 of the full unchanged specialist object")
        return cls(**obj)


@dataclass(frozen=True)
class ApprovedPlanIdentity:
    task_identity: str
    plan_version: str
    approval_ref: str
    definition_digest: str

    @classmethod
    def parse(cls, value, path):
        obj = object_value(value, path)
        require(set(obj) == {"task_identity", "plan_version", "approval_ref", "definition_digest"},
                "approval_identity", path, "Incomplete or unknown approval identity fields")
        for item in obj.values():
            text(item, path)
        require(bool(re.fullmatch(r"[0-9a-f]{64}", obj["definition_digest"])),
                "approval_identity", path, "Expected approved definition SHA-256")
        return cls(**obj)



@dataclass(frozen=True)
class EvidenceIdentity:
    approved_plan_identity: ApprovedPlanIdentity
    packet_definition_digest: str
    input_identity: dict

    @classmethod
    def parse(cls, value, path):
        obj = object_value(value, path)
        return cls(ApprovedPlanIdentity.parse(obj.get("approved_plan_identity"), path),
                   text(obj.get("packet_definition_digest"), path),
                   object_value(obj.get("input_identity"), path))


@dataclass(frozen=True)
class PacketTestApplicability:
    """Caller-owned semantic resolution; validate its current binding, not policy truth."""
    status: str
    resolution_ref: str
    rationale: str

    @classmethod
    def parse(cls, packet, plan, context):
        pid = packet["packet_id"]
        rows = object_value(context.get("test_applicability"), "context.test_applicability")
        row = object_value(rows.get(pid), pid + ".test_applicability")
        require(set(row) == {"approved_plan_identity", "packet_definition_digest", "input_identity",
                             "build_execution_lane", "verification_decision_ref", "selected_check_ids",
                             "binding_obligation_refs", "status", "resolution_ref", "rationale"},
                "test_applicability", pid, "Exact resolved applicability projection required")
        identity = EvidenceIdentity.parse(row, pid + ".test_applicability")
        require(identity.approved_plan_identity == ApprovedPlanIdentity.parse(plan["approved_plan_identity"], pid)
                and identity.packet_definition_digest == digest(packet_definition(packet))
                and digest(identity.input_identity) == digest(context["current_input_identities"][pid])
                and row["build_execution_lane"] == context.get("build_execution_lane")
                and row["build_execution_lane"] in {"direct_main", "bounded_executor", "separated_workers"}
                and CanonicalVerificationRef.parse(row["verification_decision_ref"], pid)
                    == CanonicalVerificationRef.parse(context["verification_decision_ref"], pid)
                and strings(row["selected_check_ids"], pid) == packet["selected_check_ids"]
                and bindings(row["binding_obligation_refs"], pid) == bindings(packet["binding_obligation_refs"], pid),
                "test_applicability", pid, "Applicability must bind current identity, lane, decision and exact due scope")
        require(row["status"] in {"required", "not_applicable"},
                "test_applicability", pid, "Missing or unresolved test applicability blocks execution")
        require(row["status"] != "not_applicable" or not packet["tdd_applies"],
                "test_applicability", pid, "Active local TDD requires tests")
        return cls(row["status"], text(row["resolution_ref"], pid + ".resolution_ref"),
                   text(row["rationale"], pid + ".rationale"))

    def assertion_source(self, evidence, actor, pid, actor_field="writer_actor_id"):
        if self.status == "not_applicable":
            require("tests" not in evidence, "test_applicability", pid,
                    "No-tests resolution requires omitted assertion-source evidence")
            return None
        tests = object_value(evidence.get("tests"), pid + ".tests")
        require(tests.get("mode") in {"authored", "reuse"}, "test_ownership", pid, "Resolve selected assertion source")
        text(tests.get("evidence_ref"), pid + ".tests.evidence_ref")
        if tests["mode"] == "authored":
            require(actor is not None and tests.get(actor_field) == actor,
                    "writer_lineage", pid, "Retain the actual native test author")
        return tests


@dataclass(frozen=True)
class LegacyPacketMapping:
    source_packet_index: int
    slice_id: str
    packet_id: ExecutionPacketId

    @classmethod
    def parse(cls, value, source_packets):
        require(isinstance(value, dict) and set(value) == {"source_packet_index", "slice_id", "packet_id"},
                "legacy_mapping", "legacy.packet_mapping", "Exact source position, slice and target identity required")
        index = value["source_packet_index"]
        require(type(index) is int and 0 <= index < len(source_packets)
                and source_packets[index]["slice_id"] == value["slice_id"],
                "legacy_mapping", "legacy.packet_mapping", "Unknown or conflicting source binding")
        return cls(index, value["slice_id"], ExecutionPacketId.parse(value["packet_id"], "legacy.packet_mapping.packet_id"))


def definition(plan):
    """Exclude only top-level approval identity/provenance and each packet's execution.

    All remaining fields, including plan version, decision ref and completion
    allocation, are approved definition. Progress cannot silently redefine work.
    """
    result = {key: deepcopy(value) for key, value in plan.items()
              if key not in {"approved_plan_identity", "reconciliation_provenance"}}
    result["implementation_steps"] = [{key: deepcopy(value) for key, value in packet.items()
                                       if key != "execution"}
                                      for packet in plan["implementation_steps"]]
    return result


def packet_definition(packet):
    return {key: deepcopy(value) for key, value in packet.items() if key != "execution"}


def bindings(value, path):
    result = []
    for entry in array(value, path):
        require(isinstance(entry, dict) and set(entry) == {"kind", "value", "source_ref"},
                "binding_mismatch", path, "Binding must be exact {kind,value,source_ref}")
        for item in entry.values():
            text(item, path)
        require(entry["kind"] in {"required_scope", "prohibited_scope", "required_tdd", "required_check", "resource_constraint"},
                "binding_mismatch", path, "Unknown binding kind")
        result.append(digest(entry))
    require(len(result) == len(set(result)), "duplicate", path, "Duplicate binding tuple")
    return set(result)


def check_specs(decision):
    checks = {}
    for check in array(decision.get("checks"), "context.verification_decision.checks"):
        object_value(check, "CheckSpec")
        key = text(check.get("check_id"), "CheckSpec.check_id")
        require(key not in checks, "duplicate", "CheckSpec.check_id", "CheckSpec ID must resolve exactly once")
        if "command" in check:
            command = object_value(check["command"], key + ".command")
            require(bool(array(command.get("argv"), key + ".argv")), "malformed", key, "Empty argv")
            for arg in command["argv"]:
                require(isinstance(arg, str), "malformed", key, "argv entries must be literal strings")
            text(command["argv"][0], key + ".argv[0]")
            text(command.get("cwd"), key + ".cwd")
        else:
            text(object_value(check.get("check_ref_or_method"), key).get("reference_or_procedure"), key)
        checks[key] = check
    choice = object_value(decision.get("tdd_choice"), "verification_decision.tdd_choice")
    require(type(choice.get("mode")) is bool, "tdd_mismatch", "tdd_choice.mode", "Expected boolean")
    active = strings(choice.get("applicable_check_ids"), "tdd_choice.applicable_check_ids")
    require(set(active) <= checks.keys() and (choice["mode"] or not active),
            "tdd_mismatch", "tdd_choice", "TDD IDs must resolve in the unchanged decision")
    return checks, set(active)


def graph(packets):
    ids = {packet["packet_id"] for packet in packets}
    visited = set()
    for packet in packets:
        deps = strings(packet.get("depends_on"), packet["packet_id"] + ".depends_on")
        require(set(deps) <= ids and packet["packet_id"] not in deps,
                "invalid_dependency", packet["packet_id"], "Unknown or self prerequisite")
        require(set(deps) <= visited, "dependency_order", packet["packet_id"],
                "Prerequisites must precede dependents; cycles are forbidden")
        visited.add(packet["packet_id"])


def legacy_record(record, path, packet=False, producer_version="12.0", runtime=None, separated=False):
    """Validate the original v12 direct record before dropping legacy fields."""
    object_value(record, path)
    for field in ("name", "observable_increment", "expected_success_signal", "deviation_rollback_rule"):
        text(record.get(field), path + "." + field)
    require(record.get("deliverable_type") in {"behavior", "artifact", "contract", "docs", "eval", "config", "migration", "refactor"},
            "legacy_schema", path, "Unknown original v12 deliverable type")
    for field in ("files_to_create", "files_to_modify", "files_to_test", "enabling_changes_included",
                  "selected_check_ids", "depends_on"):
        strings(record.get(field), path + "." + field)
    for field in ("acceptance_criteria", "evidence_to_record"):
        strings(record.get(field), path + "." + field, True)
    for field in ("files_to_create", "files_to_modify", "files_to_test"):
        require(all("\x00" not in value for value in record[field]), "unsafe_path", path + "." + field,
                "Original file or target strings cannot contain NUL")
    bindings(record.get("binding_obligation_refs"), path + ".binding_obligation_refs")
    object_value(record.get("verification_decision"), path + ".verification_decision")
    require(type(record.get("tdd_applies")) is bool, "tdd_mismatch", path, "Original v12 TDD flag must be boolean")
    if producer_version == "13.0":
        require("worker_stage" in record or not (record["tdd_applies"] and separated),
                "legacy_schema", path + ".worker_stage", "Original active separated v13 stage required")
        if "worker_stage" in record:
            require(record["worker_stage"] in {"test_authoring", "production", "refactor"},
                    "legacy_schema", path + ".worker_stage", "Unknown original writer stage")
        require(runtime == "gemini" or "writer_selection" in record,
                "legacy_schema", path + ".writer_selection", "Original Claude/Codex v13 writer selection required")
        if "writer_selection" in record:
            selection = object_value(record["writer_selection"], path + ".writer_selection")
            require(selection.get("agent") in {"intelligent-writer", "mechanical-writer"},
                    "legacy_schema", path, "Unknown original writer selection")
            text(selection.get("rationale"), path + ".writer_selection.rationale")
            if selection["agent"] == "mechanical-writer":
                eligibility = object_value(selection.get("mechanical_eligibility"), path)
                for field in ("recipe_or_example_ref", "resolved_decisions_ref", "scope_and_dependencies_ref", "correctness_expectations_ref"):
                    text(eligibility.get(field), path + ".writer_selection." + field)
    if packet:
        require(type(record.get("order")) is int, "legacy_schema", path + ".order", "Original v12 packet order must be an integer")
        for field in ("slice_name", "description"):
            text(record.get(field), path + "." + field)
        for field in ("requirement_ids", "test_criteria"):
            strings(record.get(field), path + "." + field, True)
        strings(record.get("implementation_notes"), path + ".implementation_notes")
        object_value(record.get("reuse_search"), path + ".reuse_search")
        object_value(record.get("evidence_assessment"), path + ".evidence_assessment")


def normalize_legacy(source, context):
    """Read old/write new with explicit source-bound mapping, never guessed provenance."""
    legacy = object_value(context.get("legacy"), "context.legacy")
    producer = object_value(legacy.get("producer"), "context.legacy.producer")
    require(producer.get("schema_version") in {"12.0", "13.0"} and producer.get("verified") is True,
            "legacy_provenance", "context.legacy.producer", "Verified v12/v13 slice producer/version provenance required")
    text(producer.get("producer_ref"), "context.legacy.producer_ref")
    version = producer["schema_version"]
    runtime = producer.get("runtime")
    require(version != "13.0" or runtime in {"claude", "codex", "gemini"},
            "legacy_provenance", "context.legacy.producer.runtime", "Verified v13 producer runtime required")
    text(legacy.get("source_identity"), "legacy.source_identity")
    text(legacy.get("approved_source_identity"), "legacy.approved_source_identity")
    require(legacy.get("source_sha256") == digest(source)
            and legacy.get("source_identity") == legacy.get("approved_source_identity")
            and bool(legacy.get("source_identity")), "legacy_source_identity", "context.legacy",
            "Original immutable bytes/object and approved source identity must match")
    require("schema_version" not in source or source["schema_version"] == version,
            "legacy_provenance", "schema_version", "Embedded legacy tag must agree with verified slice producer")
    require("plan_schema_version" not in source and "approved_plan_identity" not in source and "completion_allocation" not in source,
            "mixed_schema", "plan", "Mixed canonical and legacy ownership is forbidden")
    slices = array(source.get("slice_manifest"), "slice_manifest")
    old_packets = array(source.get("implementation_steps"), "implementation_steps")
    require(0 < len(slices) <= MAX_PACKETS and 0 < len(old_packets) <= MAX_PACKETS,
            "legacy_mapping", "plan", "Bounded nonempty legacy manifest and packets required")
    checks, active = check_specs(object_value(context.get("verification_decision"), "context.verification_decision"))
    by_slice, seen = {}, set()
    for entry in slices:
        legacy_record(entry, "slice_manifest", producer_version=version, runtime=runtime, separated=context.get("build_execution_lane") == "separated_workers")
        sid = ExecutionPacketId.parse(entry.get("slice_id"), "slice_manifest.slice_id").value
        require(sid not in by_slice, "duplicate", "slice_manifest", "Duplicate source slice")
        require(set(strings(entry.get("depends_on"), sid + ".depends_on")) <= seen,
                "dependency_order", sid, "Legacy prerequisite order/cycle is invalid")
        by_slice[sid], seen = entry, seen | {sid}
    groups = {sid: [] for sid in by_slice}
    for index, packet in enumerate(old_packets):
        legacy_record(packet, "implementation_steps", packet=True, producer_version=version, runtime=runtime, separated=context.get("build_execution_lane") == "separated_workers")
        require("packet_id" not in packet and packet.get("slice_id") in groups,
                "legacy_mapping", "implementation_steps", "Mixed or unknown source slice")
        groups[packet["slice_id"]].append(index)
    require(all(groups.values()), "legacy_mapping", "slice_manifest", "Every source slice needs executable work")
    explicit = legacy.get("packet_mapping", [])
    mapping = {}
    for entry in array(explicit, "legacy.packet_mapping"):
        binding = LegacyPacketMapping.parse(entry, old_packets)
        require(binding.source_packet_index not in mapping, "legacy_mapping", "legacy.packet_mapping", "Duplicate source binding")
        mapping[binding.source_packet_index] = binding.packet_id.value
    if explicit:
        require(set(mapping) == set(range(len(old_packets))), "legacy_mapping", "legacy.packet_mapping", "Exact-once mapping required")
    else:
        for sid, indexes in groups.items():
            for index in indexes:
                mapping[index] = ExecutionPacketId.parse(sid if len(indexes) == 1 else old_packets[index].get("task_id"),
                                                 "implementation_steps.task_id").value
    require(len(set(mapping.values())) == len(old_packets), "legacy_mapping", "packet_id", "Mapped IDs must be unique")
    if "verification_decision" in source:
        require(digest(source["verification_decision"]) == digest(context["verification_decision"]),
                "decision_mismatch", "verification_decision", "Legacy specialist decision must remain unchanged")
    plan = {key: deepcopy(value) for key, value in source.items()
            if key not in {"schema_version", "slice_manifest", "single_slice_rationale", "decomposition_plan_review",
                           "slice_verification_summary", "implementation_steps", "verification_decision"}}
    plan["plan_schema_version"] = "14.0"
    plan["verification_decision_ref"] = deepcopy(context["verification_decision_ref"])
    plan["completion_allocation"] = deepcopy(legacy.get("completion_allocation"))
    plan["implementation_steps"] = []
    all_source_refs = list(strings(legacy.get("source_evidence_refs"), "legacy.source_evidence_refs"))
    # Old results: immutable provenance, never live state or verification.
    source_results = deepcopy(source.get("slice_verification_summary", []))
    array(source_results, "slice_verification_summary")
    for sid, indexes in groups.items():
        manifest = by_slice[sid]
        for field in ("requirement_ids", "acceptance_criteria", "selected_check_ids", "binding_obligation_refs"):
            if field == "requirement_ids" and field not in manifest:
                continue  # v12 requirements belong to packets.
            required = manifest.get(field)
            require(isinstance(required, list), "legacy_allocation", sid + "." + field, "Original slice allocation required")
            allocated = [value for index in indexes for value in old_packets[index].get(field, [])]
            allocated += array(object_value(legacy.get("completion_allocation"), "legacy.completion_allocation").get(field), "legacy.completion_allocation." + field)
            require(all(value in allocated for value in required), "legacy_allocation", sid + "." + field,
                    "Slice-wide obligations must be explicitly allocated; never dropped or guessed")
        # No completion field exists; retain explicit packet owners before retirement.
        for field in ("evidence_to_record", "enabling_changes_included"):
            allocated = {value for index in indexes for value in old_packets[index][field]}
            require(set(manifest[field]) <= allocated, "legacy_allocation", sid + "." + field,
                    "Original slice instructions need explicit packet owners; never infer allocation")
        require(any(old_packets[index]["expected_success_signal"] == manifest["expected_success_signal"] for index in indexes),
                "legacy_allocation", sid + ".expected_success_signal", "Original slice success signal needs an explicit packet owner")
        require(all(old_packets[index]["deviation_rollback_rule"] == manifest["deviation_rollback_rule"] for index in indexes),
                "legacy_allocation", sid + ".deviation_rollback_rule", "Every source packet must retain the slice rollback rule; conflicting rules need refresh")
        if "writer_selection" in manifest:
            selection = object_value(manifest["writer_selection"], sid + ".writer_selection")
            require(all(digest(old_packets[index].get("writer_selection")) == digest(selection) for index in indexes),
                    "legacy_allocation", sid + ".writer_selection", "Explicit slice writer selection must remain unchanged on every source packet")
        for field in ("files_to_create", "files_to_modify", "files_to_test"):
            allocated = {value for index in indexes for value in old_packets[index][field]}
            require(set(manifest[field]) == allocated, "legacy_allocation", sid + "." + field,
                    "Original slice file/target scope must exactly match mapped packet allocation")
        manifest_ids = set(manifest["selected_check_ids"])
        require(manifest_ids <= checks.keys() and manifest["tdd_applies"] == bool(manifest_ids & active),
                "tdd_mismatch", sid, "Original slice TDD choice must match the unchanged decision")
        commands = [checks[cid]["command"]["argv"] for cid in manifest["selected_check_ids"] if "command" in checks[cid]]
        if "verification_command" in manifest:
            require(len(commands) == 1 and manifest["verification_command"] == commands[0],
                    "command_mismatch", sid, "Original slice compatibility command must remain exact")
        for position, index in enumerate(indexes):
            old = old_packets[index]
            require(digest(old["verification_decision"]) == digest(context["verification_decision"])
                    and digest(manifest["verification_decision"]) == digest(context["verification_decision"]),
                    "decision_mismatch", sid, "Legacy specialist decision must remain unchanged")
            packet = {key: deepcopy(value) for key, value in old.items()
                      if key not in {"slice_id", "slice_name", "task_id", "order", "verification_decision", "evidence_assessment", "depends_on", "execution", "worker_stage"}}
            packet["packet_id"] = mapping[index]
            packet["verification_decision_ref"] = deepcopy(context["verification_decision_ref"])
            intersection = set(old["selected_check_ids"]) & active
            require(old["tdd_applies"] == bool(intersection) and len(intersection) <= 1,
                    "tdd_mismatch", sid, "Legacy packet needs at most one selected/applicable TDD check")
            planned = {}
            if intersection:
                cid = next(iter(intersection))
                check = checks[cid]
                require(check.get("method") == "automated_test" and "command" in check,
                        "tdd_mismatch", sid, "Planned RED needs one executable automated-test CheckSpec")
                oracle = text(object_value(check.get("check_ref_or_method"), cid).get("meaningful_failure"), cid)
                planned = {"red_check_id": cid, "red_command": check["command"]["argv"],
                           "red_cwd": check["command"]["cwd"], "expected_red_failure": oracle}
            for field in ("red_check_id", "red_command", "red_cwd", "expected_red_failure"):
                require(field not in old or (field in planned and digest(old[field]) == digest(planned[field])),
                        "tdd_mismatch", sid + "." + field, "Supplied planned RED must match the sole unchanged CheckSpec")
            packet.update(deepcopy(planned))  # Planned invocation only; never invent actual RED.
            deps = list(manifest["depends_on"])
            for dep in old.get("depends_on", []):
                require(dep in by_slice, "legacy_mapping", sid + ".depends_on", "Original dependency must name source slice")
                if dep not in deps:
                    deps.append(dep)
            packet["depends_on"] = [mapping[i] for dep in deps for i in groups[dep]]
            if position:
                packet["depends_on"].append(mapping[indexes[position - 1]])
            packet["boundary_reason"] = {"kind": "prerequisite", "reason": "Preserved legacy execution barrier and source-bound work allocation"}
            old_execution = object_value(old.get("execution", {}), sid + ".execution")
            # Retain history; old worker status cannot verify v14.
            refs = strings(old_execution.get("evidence_refs", []), sid + ".evidence_refs")
            all_source_refs.extend(refs)
            packet["execution"] = {"state": "PENDING", "evidence_refs": refs,
                                   "input_identity": deepcopy(context.get("current_input_identities", {}).get(mapping[index])),
                                   "recovery": deepcopy(old_execution.get("recovery", {"attempt_count": 0, "no_progress_count": 0})),
                                   "history": deepcopy(old_execution.get("history", []))}
            plan["implementation_steps"].append(packet)
    plan["approved_plan_identity"] = deepcopy(context["approved_plan_identity"])
    plan["reconciliation_provenance"] = {"source_sha256": legacy["source_sha256"], "source_identity": legacy["source_identity"],
                                         "producer": deepcopy(producer), "packet_mapping": [
                                             {"source_packet_index": i, "slice_id": old_packets[i]["slice_id"], "packet_id": mapping[i]}
                                             for i in range(len(old_packets))],
                                         "source_evidence_refs": list(dict.fromkeys(all_source_refs))}
    plan["reconciliation_provenance"]["original_result_allocation"] = source_results
    if version == "13.0":
        plan["reconciliation_provenance"]["original_writer_context"] = {
            "slices": [{"slice_id": item["slice_id"], **{key: deepcopy(item[key]) for key in ("worker_stage", "writer_selection") if key in item}} for item in slices],
            "packets": [{"source_packet_index": index, **{key: deepcopy(item[key]) for key in ("worker_stage", "writer_selection") if key in item}} for index, item in enumerate(old_packets)]}

    return plan


def allocation(owner, checks, canonical_bindings, requirements, path):
    ids = set(strings(owner.get("selected_check_ids"), path + ".selected_check_ids"))
    require(ids <= checks.keys(), "unknown_check", path, "Unknown selected CheckSpec")
    tuples = bindings(owner.get("binding_obligation_refs"), path + ".binding_obligation_refs")
    require(tuples <= canonical_bindings, "binding_mismatch", path, "Unknown or modified canonical tuple")
    reqs = set(strings(owner.get("requirement_ids"), path + ".requirement_ids"))
    require(reqs <= requirements.keys(), "unknown_requirement", path, "Unknown accepted requirement")
    return ids, tuples, reqs


def validate_plan(plan, context, version="16.0"):
    require(plan.get("plan_schema_version") == version, "unsupported_version", "plan_schema_version", "Only canonical v16 is writable; authenticate historical definitions before migration")
    require(not any(key in plan for key in ("slice_manifest", "single_slice_rationale", "slice_verification_summary",
                                           "decomposition_plan_review", "current_task_packet", "verification_decision", "red_evidence", "red_phase", "worker_stage", "test_applicability")),
            "mixed_schema", "plan", "Plan has one packet collection and one specialist reference")
    identity = ApprovedPlanIdentity.parse(plan.get("approved_plan_identity"), "plan.approved_plan_identity")
    authority = ApprovedPlanIdentity.parse(context.get("approved_plan_identity"), "context.approved_plan_identity")
    require(identity == authority and identity.task_identity == context.get("task_identity") == plan.get("task_identity")
            and identity.plan_version == plan.get("plan_version"), "approval_identity", "plan", "Current task/plan/approval identity mismatch")
    decision = object_value(context.get("verification_decision"), "context.verification_decision")
    ref = CanonicalVerificationRef.parse(context.get("verification_decision_ref"), "context.verification_decision_ref")
    require(ref.sha256 == digest(decision) and CanonicalVerificationRef.parse(plan.get("verification_decision_ref"), "plan.verification_decision_ref") == ref,
            "decision_mismatch", "plan.verification_decision_ref", "Full unchanged specialist object digest/ref mismatch")
    checks, active = check_specs(decision)
    canonical_bindings = bindings(object_value(decision.get("policy_basis"), "policy_basis").get("binding_constraints"), "binding_constraints")
    requirements = {}
    for requirement in array(context.get("requirements"), "context.requirements"):
        key = text(requirement.get("requirement_id"), "requirement_id")
        require(key not in requirements, "duplicate", "context.requirements", "Requirement must resolve exactly once")
        requirements[key] = text(requirement.get("acceptance_criterion"), key)
    packets = array(plan.get("implementation_steps"), "plan.implementation_steps")
    require(0 < len(packets) <= MAX_PACKETS, "malformed", "implementation_steps", "Expected 1..256 executable packets")
    seen, allocated_checks, allocated_bindings, allocated_requirements = set(), set(), set(), set()
    for packet in packets:
        object_value(packet, "implementation_steps[]")
        pid = ExecutionPacketId.parse(packet.get("packet_id"), "packet_id").value
        require(pid not in seen, "duplicate", pid, "Duplicate canonical packet ID")
        seen.add(pid)
        if context.get("build_execution_lane") in {"bounded_executor", "separated_workers"}:
            ExecutionActorBinding.validate_delegated(context, pid)
        require(not any(key in packet for key in ("slice_id", "slice_name", "task_id", "verification_decision", "evidence_assessment", "tdd_cycle_log_ref", "red_evidence", "red_phase", "worker_stage", "test_applicability")),
                "mixed_schema", pid, "Stored packets cannot contain legacy keys or mutable specialist copies")
        for field in ("name", "description", "observable_increment", "expected_success_signal", "deviation_rollback_rule"):
            text(packet.get(field), pid + "." + field)
        require(packet.get("deliverable_type") in {"behavior", "artifact", "contract", "docs", "eval", "config", "migration", "refactor"},
                "malformed", pid, "Unknown deliverable_type")
        for field in ("files_to_create", "files_to_modify", "files_to_test", "enabling_changes_included"):
            strings(packet.get(field), pid + "." + field)
        for field in ("files_to_create", "files_to_modify", "files_to_test"):
            for path in packet[field]:
                require("\x00" not in path, "unsafe_path", pid + "." + field,
                        "File or verification-target strings cannot contain NUL")
        object_value(packet.get("reuse_search"), pid + ".reuse_search")
        strings(packet.get("test_criteria"), pid + ".test_criteria", True)
        strings(packet.get("implementation_notes"), pid + ".implementation_notes")
        strings(packet.get("evidence_to_record"), pid + ".evidence_to_record", True)
        criteria = strings(packet.get("acceptance_criteria"), pid + ".acceptance_criteria", True)
        require(CanonicalVerificationRef.parse(packet.get("verification_decision_ref"), pid) == ref,
                "decision_mismatch", pid, "Packet specialist reference mismatch")
        ids, tuples, reqs = allocation(packet, checks, canonical_bindings, requirements, pid)
        require(bool(reqs), "acceptance_allocation", pid, "Executable packet needs an accepted requirement")
        require(all(requirements[key] in criteria for key in reqs), "acceptance_allocation", pid, "Every allocated requirement criterion must remain explicit")
        allocated_checks |= ids
        allocated_bindings |= tuples
        allocated_requirements |= reqs
        intersection = ids & active
        require(type(packet.get("tdd_applies")) is bool and packet["tdd_applies"] == bool(intersection) and len(intersection) <= 1,
                "tdd_mismatch", pid, "Keep unchanged task choice and exactly one applicable selected TDD check per active packet")
        if intersection:
            cid = next(iter(intersection))
            spec = checks[cid]
            require(spec.get("method") == "automated_test" and "command" in spec and packet.get("red_check_id") == cid
                    and packet.get("red_command") == spec["command"]["argv"]
                    and packet.get("red_cwd") == spec["command"]["cwd"]
                    and packet.get("expected_red_failure") == spec["check_ref_or_method"].get("meaningful_failure"),
                    "tdd_mismatch", pid, "RED tuple must exactly bind the selected executable meaningful oracle")
        commands = [checks[key]["command"]["argv"] for key in packet["selected_check_ids"] if "command" in checks[key]]
        if len(commands) == 1 or "verification_command" in packet:
            require(len(commands) == 1 and packet.get("verification_command") == commands[0], "command_mismatch", pid,
                    "Singular compatibility command must match exactly one due command")
        if len(packets) > 1:
            reason = object_value(packet.get("boundary_reason"), pid + ".boundary_reason")
            require(reason.get("kind") in {"acceptance", "ownership_context", "prerequisite", "recovery_rollout", "binding_protocol"},
                    "boundary_purpose", pid, "Extra packets require an execution purpose")
            text(reason.get("reason"), pid + ".boundary_reason.reason")
        execution = object_value(packet.get("execution"), pid + ".execution")
        require(execution.get("state") in STATES, "invalid_state", pid, "Unknown coordinator state")
        strings(execution.get("evidence_refs"), pid + ".evidence_refs")
        require("build_execution_lane" not in execution or (isinstance(execution["build_execution_lane"], str)
                and execution["build_execution_lane"] in {"direct_main", "bounded_executor", "separated_workers"}),
                "malformed", pid + ".build_execution_lane", "Unknown dispatch lane stamp")
        if "execution_actor_id" in execution:
            actor = text(execution["execution_actor_id"], pid + ".execution_actor_id")
            require(actor == actor.strip(), "malformed", pid + ".execution_actor_id", "Actor stamps compare exactly")
        if "tdd_cycle_log_ref" in execution:
            text(execution["tdd_cycle_log_ref"], pid + ".execution.tdd_cycle_log_ref")
        object_value(execution.get("input_identity"), pid + ".input_identity")
        for entry in array(execution.get("history"), pid + ".history"):
            object_value(entry, pid + ".history[]")
            if "stamp_baseline" in entry:
                baseline = object_value(entry["stamp_baseline"], pid + ".history[].stamp_baseline")
                strings(baseline.get("evidence_refs"), pid + ".history[].stamp_baseline.evidence_refs")
                require("tdd_cycle_log_ref" not in baseline or isinstance(baseline["tdd_cycle_log_ref"], str), "malformed",
                        pid + ".history[].stamp_baseline.tdd_cycle_log_ref", "Expected string")
        if version == "14.0" or "recovery" in execution:
            recovery = object_value(execution.get("recovery"), pid + ".recovery")
            for field in ("attempt_count", "no_progress_count"):
                require(type(recovery.get(field)) is int and recovery[field] >= 0, "recovery_mismatch", pid, "Historical counters must be retained nonnegative integers")
            require(recovery["no_progress_count"] <= recovery["attempt_count"], "recovery_mismatch", pid, "Invalid historical counters")
    graph(packets)
    completion = object_value(plan.get("completion_allocation"), "completion_allocation")
    ids, tuples, reqs = allocation(completion, checks, canonical_bindings, requirements, "completion_allocation")
    completion_criteria = strings(completion.get("acceptance_criteria"), "completion_allocation.acceptance_criteria")
    require(all(requirements[key] in completion_criteria for key in reqs), "acceptance_allocation", "completion_allocation", "Deferred criteria must remain explicit")
    require(allocated_checks | ids == checks.keys() and allocated_bindings | tuples == canonical_bindings
            and allocated_requirements | reqs == requirements.keys(), "obligation_conservation", "plan",
            "Every accepted requirement, selected check and binding tuple must retain a packet or task-wide owner")
    # Local checks may still require integration coverage.
    required_completion = object_value(context.get("required_completion_allocation"), "context.required_completion_allocation")
    required_ids, required_tuples, required_reqs = allocation(required_completion, checks, canonical_bindings, requirements, "required_completion_allocation")
    require(required_ids <= ids and required_tuples <= tuples and required_reqs <= reqs,
            "integration_allocation", "completion_allocation", "Packet checks cannot remove due task-wide obligations")
    require(active <= allocated_checks, "tdd_mismatch", "plan.implementation_steps",
            "Every applicable TDD check needs an executable packet owner; completion-only allocation cannot replace its cycle")
    require(identity.definition_digest == digest(definition(plan)), "definition_mismatch", "plan", "Approved definition changed; use existing deviation/reapproval policy")
    return checks, active


def validate_results(owner, evidence, checks, path):
    rows = array(evidence.get("validation_results"), path + ".validation_results")
    expected = set(owner["selected_check_ids"])
    observed, covered = set(), set()
    for row in rows:
        object_value(row, path + ".validation_results[]")
        ids = strings(row.get("selected_check_ids"), path + ".selected_check_ids", True)
        require(set(ids) <= expected and not observed.intersection(ids), "check_evidence", path, "Unknown, duplicate or misallocated check evidence")
        require(row.get("result") == "passed", "check_evidence", path, "Failed/partial/unavailable/omitted evidence cannot verify")
        text(row.get("evidence_ref"), path + ".evidence_ref")
        covered |= bindings(row.get("binding_obligation_refs"), path)
        for cid in ids:
            spec = checks[cid]
            if "command" in spec:
                require(len(ids) == 1 and row.get("executed_command") == {"check_id": cid, **spec["command"]},
                        "command_mismatch", path, "Executed literal argv/cwd must match the sole CheckSpec exactly")
            else:
                require(row.get("procedure") == spec["check_ref_or_method"]["reference_or_procedure"],
                        "procedure_mismatch", path, "Non-command check retains its canonical concrete procedure")
        observed.update(ids)
    require(observed == expected, "check_evidence", path, "Missing due selected-check result")
    expected_bindings = bindings(owner["binding_obligation_refs"], path)
    require(covered <= expected_bindings, "binding_mismatch", path, "Evidence cannot claim another owner's binding")
    for row in array(evidence.get("binding_results", []), path + ".binding_results"):
        require(row.get("result") == "passed", "binding_evidence", path, "Binding evidence must pass")
        text(row.get("evidence_ref"), path)
        covered |= bindings([row.get("binding_obligation_ref")], path)
    require(covered == expected_bindings, "binding_evidence", path, "Every exact due binding tuple needs current evidence")
    results = array(evidence.get("acceptance_results"), path + ".acceptance_results")
    criteria = []
    for row in results:
        require(row.get("result") == "passed", "acceptance_evidence", path, "Every acceptance criterion must pass")
        criteria.append(text(row.get("criterion"), path))
        text(row.get("evidence_ref"), path)
    require(len(criteria) == len(set(criteria)) and set(criteria) == set(owner["acceptance_criteria"]),
            "acceptance_evidence", path, "Exact current criteria coverage required")


def actual_red(packet, evidence):
    pid = packet["packet_id"]
    cycle = object_value(evidence.get("tdd_cycle"), pid + ".tdd_cycle")
    red = object_value(cycle.get("red"), pid + ".red")
    require(cycle.get("tdd_cycle_log_ref") == text(packet["execution"].get("tdd_cycle_log_ref"), pid + ".execution.tdd_cycle_log_ref")
            and red.get("check_id") == packet["red_check_id"] and red.get("command") == packet["red_command"]
            and red.get("cwd") == packet["red_cwd"], "tdd_evidence", pid, "Actual matching authorizing RED required")
    for field in ("test_file", "test_name", "failure_summary", "right_reason"):
        text(red.get(field), pid + ".red." + field)
    # Resolve unchanged phase; adjudicate the oracle, not diagnostic phrasing.
    phase = object_value(cycle.get("red_phase"), pid + ".red_phase")
    require(phase.get("verified_failing") is True and phase.get("test_file") == red["test_file"]
            and phase.get("test_name") == red["test_name"], "tdd_evidence", pid, "Current producer-verified RED target required")
    text(phase.get("failure_reason"), pid + ".red_phase.failure_reason")
    authorizers = 0
    for row in array(phase.get("command_results"), pid + ".red_phase.command_results"):
        object_value(row, pid + ".red_phase.command_results[]")
        text(row.get("target"), pid + ".red_phase.target")
        argv = array(row.get("argv"), pid + ".red_phase.argv")
        require(bool(argv) and all(isinstance(arg, str) for arg in argv),
                "tdd_evidence", pid, "Canonical RED invocation needs literal argv")
        text(argv[0], pid + ".red_phase.argv[0]")
        text(row.get("cwd"), pid + ".red_phase.cwd")
        require(row.get("result") in {"passed", "failed", "partial", "unavailable"}
                and row.get("freshness") in {"current", "stale", "unknown"},
                "tdd_evidence", pid, "Canonical RED invocation result/freshness required")
        for field in ("check_id", "test_file", "test_name"):
            if field in row:
                text(row[field], pid + ".red_phase." + field)
        if (row.get("result") == "failed" and row.get("freshness") == "current"
                and row.get("check_id") == red["check_id"] and argv == red["command"]
                and row.get("cwd") == red["cwd"] and row.get("test_file") == red["test_file"]
                and row.get("test_name") == red["test_name"]):
            authorizers += 1
    require(authorizers == 1, "tdd_evidence", pid, "Exactly one current failed matching RED invocation required")
    return cycle


@dataclass(frozen=True)
class ExecutionActorBinding:
    kind: str
    actor_id: str
    runtime_evidence_ref: str

    @classmethod
    def parse(cls, context, pid):
        value = object_value(object_value(context.get("execution_actor_bindings"),
                             "execution_actor_bindings").get(pid), pid + ".execution_actor_binding")
        require(set(value) == {"kind", "actor_id", "runtime_evidence_ref"}
                and value.get("kind") in {"main", "delegated"}, "execution_actor", pid,
                "Resolve independently retained actual execution actor")
        return cls(value["kind"], text(value.get("actor_id"), pid), text(value.get("runtime_evidence_ref"), pid))

    @classmethod
    def validate_delegated(cls, context, pid):
        if "execution_actor_bindings" not in context:
            return
        table = object_value(context["execution_actor_bindings"], "execution_actor_bindings")
        if pid not in table:
            return  # Existing delegated ownership remains sufficient.
        binding = cls.parse(context, pid)
        actor = object_value(context.get("writer_actor_ids", {}), "context.writer_actor_ids").get(pid)
        require(binding.kind == "delegated" and (actor is None or binding.actor_id == actor),
                "execution_actor", pid, "Supplied delegated binding must retain actual writer ownership")


@dataclass(frozen=True)
class RelevantVerificationInputIdentity:
    values: dict

    @classmethod
    def parse(cls, value, pid):
        fields = {"source", "tests", "configuration", "dependencies", "toolchain", "environment", "external_inputs"}
        value = object_value(value, pid + ".relevant_input_identity")
        require(set(value) == fields, "tdd_reuse", pid, "Resolve all relevant verification input categories")
        for field in fields:
            row = object_value(value[field], pid + "." + field)
            require(set(row) == {"identity", "freshness"} and row.get("freshness") == "current",
                    "tdd_reuse", pid, "Unknown, stale or mutable-unchecked inputs cannot support reuse")
            text(row.get("identity"), pid + "." + field)
        return cls(deepcopy(value))


def reuse_green_requested(packet, evidence):
    cycle = evidence.get("tdd_cycle") if isinstance(evidence, dict) else None
    refactor = cycle.get("refactor") if isinstance(cycle, dict) else None
    return bool(packet["tdd_applies"]) and isinstance(refactor, dict) and refactor.get("verification_disposition") == "reuse_green"


def reject_failed_green_reuse(packet, evidence):
    """Failed GREEN is never reused, before ordinary result validation runs."""
    pid = packet["packet_id"]
    green = evidence["tdd_cycle"].get("green")
    require(isinstance(green, dict) and green.get("all_tests_pass") is True
            and all(row.get("result") == "passed" for row in array(evidence.get("validation_results"), pid + ".validation_results")
                    if isinstance(row, dict) and row.get("invocation_ref") == green.get("invocation_ref")),
            "tdd_reuse", pid, "Failed GREEN is never reused; run the affected checks")


# Real digests only: sentinel words such as unknown, n/a or none never match.
REUSE_DIGEST_PATTERN = re.compile(r"sha256:[0-9a-f]{64}\Z", re.ASCII)


def validate_green_reuse(packet, evidence, context):
    """Validate a reference to original runs, never append or count a new result.

    Default digest mode: no edit after GREEN and green.reuse_digest equals the
    caller's independently resolved current_input_identities[pid].reuse_digest.
    Detailed mode (explicit opt-in) keeps the seven-category identity and assessment.
    """
    pid = packet["packet_id"]
    cycle = evidence["tdd_cycle"]
    green, refactor = cycle["green"], cycle["refactor"]
    require(cycle.get("schema_version") == "3.0" and refactor.get("changes_made") == "none needed"
            and refactor.get("command_results") == [], "tdd_reuse", pid,
            "Only explicit no-change v3 reuse has zero new invocations")
    require(refactor["invocation_ref"] == green["invocation_ref"], "tdd_reuse", pid,
            "Reuse retains the original GREEN invocation")
    mode = cycle.get("reuse_identity_mode", "digest")
    require(mode in {"digest", "detailed"}, "tdd_reuse", pid, "Unknown reuse identity mode")
    require(any(row.get("selected_check_ids") == [packet["red_check_id"]]
                and row.get("invocation_ref") == green["invocation_ref"] for row in evidence["validation_results"]),
            "tdd_reuse", pid, "The singular compatibility reference identifies the actual GREEN target")
    if mode == "detailed":
        validate_detailed_reuse(packet, evidence, context)
        return
    resolved = object_value(context["current_input_identities"].get(pid), "current_input_identities." + pid)
    current = resolved.get("reuse_digest")
    original = green.get("reuse_digest")
    require(isinstance(current, str) and bool(REUSE_DIGEST_PATTERN.fullmatch(current)), "tdd_reuse", pid,
            "Missing, unknown or non-digest current snapshot digest cannot support reuse; use lowercase sha256:<64 hex>")
    require(isinstance(original, str) and original == current, "tdd_reuse", pid,
            "Snapshot changed after GREEN; run the affected checks")
    if "green_invocation_refs" in refactor:
        refs = strings(refactor["green_invocation_refs"], pid, True)
        observed = {row["invocation_ref"] for row in evidence["validation_results"] + evidence.get("binding_results", [])
                    if "invocation_ref" in row}
        require(green["invocation_ref"] in refs and observed == set(refs), "tdd_reuse", pid,
                "Reuse references exactly the real original due run set")


def validate_detailed_reuse(packet, evidence, context):
    """Opt-in detailed identity: seven categories plus a canonical reuse assessment."""
    pid = packet["packet_id"]
    green, refactor = evidence["tdd_cycle"]["green"], evidence["tdd_cycle"]["refactor"]
    require(isinstance(refactor.get("green_invocation_refs"), list), "tdd_reuse", pid,
            "Detailed reuse needs the retained original GREEN run set")
    refs = strings(refactor["green_invocation_refs"], pid, True)
    require(green["invocation_ref"] in refs, "tdd_reuse", pid, "Reuse retains the original GREEN invocation")
    ref = text(refactor.get("reuse_assessment_ref"), pid)
    table = object_value(context.get("verification_reuse_authority"), "context.verification_reuse_authority")
    require(ref in table, "tdd_reuse", pid, "Resolve the referenced current canonical reuse assessment")
    authority = object_value(table[ref], pid + ".reuse_authority")
    require(authority.get("result") == "sufficient" and authority.get("evidence_ref") == ref
            and authority.get("packet_id") == pid and authority.get("green_invocation_refs") == refs
            and authority.get("verification_decision_ref") == context["verification_decision_ref"]
            and authority.get("check_id") == packet["red_check_id"]
            and authority.get("command") == packet["red_command"] and authority.get("cwd") == packet["red_cwd"]
            and authority.get("oracle") == packet["expected_red_failure"]
            and authority.get("post_green_changes") == [] and authority.get("fresh_run_obligations") == [],
            "tdd_reuse", pid, "Current canonical assessment must resolve original runs and unchanged decision/oracle without fresh-run mandates")
    original = RelevantVerificationInputIdentity.parse(green.get("relevant_input_identity"), pid)
    # The assessment's current identity is self-attested; bind it to the
    # independently resolved current packet inputs, never to the assessment alone.
    resolved = object_value(context["current_input_identities"].get(pid), "current_input_identities." + pid)
    require("relevant_input_identity" in resolved, "tdd_reuse", pid,
            "Unknown current relevant verification inputs cannot support reuse")
    current = RelevantVerificationInputIdentity.parse(resolved["relevant_input_identity"], pid)
    require(original == RelevantVerificationInputIdentity.parse(authority.get("green_input_identity"), pid)
            == RelevantVerificationInputIdentity.parse(authority.get("current_input_identity"), pid) == current,
            "tdd_reuse", pid, "Relevant source/tests/commands/environment/external identity changed")
    # Existing result rows remain the sole owners of each original invocation.
    original_rows = evidence["validation_results"] + evidence.get("binding_results", [])
    observed_refs = set()
    commands = {}
    for row in original_rows:
        invocation = text(row.get("invocation_ref"), pid + ".invocation_ref")
        require(invocation in refs, "tdd_reuse", pid,
                "Every due target/regression/binding result must resolve to an original GREEN run")
        observed_refs.add(invocation)
        if "executed_command" in row:
            command = row["executed_command"]
            prior = commands.setdefault(invocation, command)
            require(prior == command, "tdd_reuse", pid, "One retained invocation cannot identify different commands")
    require(observed_refs == set(refs), "tdd_reuse", pid, "Reuse references exactly the real original due run set")


def verified_packet(packet, evidence, plan, context, checks):
    pid = packet["packet_id"]
    workspace = object_value(context.get("workspace"), "context.workspace")
    active_ids = set(strings(workspace.get("active_source_writer_ids"), "workspace.active_source_writer_ids"))
    require(active_ids <= {item["packet_id"] for item in plan["implementation_steps"]},
            "workspace_overlap", pid, "Resolve current source-writer activity independently")
    require(pid not in active_ids, "workspace_overlap", pid,
            "The source Writer must be terminal before verification")
    object_value(evidence, pid + ".evidence")
    identity = EvidenceIdentity.parse(evidence, pid + ".evidence")
    require(identity.approved_plan_identity == ApprovedPlanIdentity.parse(plan["approved_plan_identity"], pid)
            and identity.packet_definition_digest == digest(packet_definition(packet))
            and digest(identity.input_identity) == digest(context["current_input_identities"][pid]),
            "stale_evidence", pid, "Evidence must bind current approved definition and relevant input identity")
    require(evidence.get("build_execution_lane") == context.get("build_execution_lane")
            and context.get("build_execution_lane") in {"direct_main", "bounded_executor", "separated_workers"},
            "lane_evidence", pid, "Evidence must match the selected Build lane")
    text(evidence.get("implementation_evidence_ref"), pid)
    text(evidence.get("native_evidence_ref"), pid)
    if context["build_execution_lane"] == "separated_workers":
        text(evidence.get("builder_evidence_ref"), pid)
        require(evidence["builder_evidence_ref"] != evidence["implementation_evidence_ref"], "lane_evidence", pid, "Independent verification owner required")
    direct = context["build_execution_lane"] == "direct_main"
    actor_binding = ExecutionActorBinding.parse(context, pid) if direct else None
    if direct:
        require(actor_binding.kind == "main" and not any(key in evidence for key in
                ("writer_actor_id", "builder_evidence_ref", "worker_role", "worker_stage")),
                "execution_actor", pid, "Direct work retains actual main identity without child fields")
        require(evidence.get("native_evidence_ref") == actor_binding.runtime_evidence_ref,
                "execution_actor", pid, "Bind actual native main evidence")
        require(not context.get("writer_actor_ids") and not context.get("builder_actor_ids"),
                "execution_actor", pid, "Direct main context cannot claim child worker actors")
    actor = actor_binding.actor_id if direct else object_value(context.get("writer_actor_ids", {}), "context.writer_actor_ids").get(pid)
    require(actor is not None and evidence.get("execution_actor_id" if direct else "writer_actor_id") == actor,
            "writer_lineage", pid, "Verification retains the independently resolved native producer")
    text(actor, "writer_actor_ids." + pid)
    # Dispatch stamps record the admitted lane/actor; verification and
    # reconciliation cannot certify the packet under another lane or actor.
    stamps = packet["execution"]
    require(stamps.get("build_execution_lane", context["build_execution_lane"]) == context["build_execution_lane"],
            "lane_evidence", pid, "Verification lane must match the admitted dispatch lane stamp")
    require(stamps.get("execution_actor_id", actor) == actor, "execution_actor", pid,
            "Verification actor must match the admitted dispatch actor stamp")
    PacketTestApplicability.parse(packet, plan, context).assertion_source(evidence, actor, pid, "execution_actor_id" if direct else "writer_actor_id")
    self_check = object_value(evidence.get("self_check"), pid + ".self_check")
    require(self_check.get("result") == "passed", "self_check", pid, "Current self-check must pass")
    text(self_check.get("evidence_ref"), pid)
    if reuse_green_requested(packet, evidence):
        reject_failed_green_reuse(packet, evidence)
    validate_results(packet, evidence, checks, pid)
    if packet["tdd_applies"]:
        cycle = actual_red(packet, evidence)
        for phase in ("green", "refactor"):
            entry = object_value(cycle.get(phase), pid + "." + phase)
            require(entry.get("all_tests_pass") is True, "tdd_evidence", pid, "Distinct observed GREEN and REFACTOR passes required")
            require(entry.get("command") == packet["red_command"] and entry.get("cwd") == packet["red_cwd"],
                    "tdd_evidence", pid, "TDD phases must retain the authorizing invocation")
            text(entry.get("invocation_ref"), pid)
        if cycle["refactor"].get("verification_disposition") == "reuse_green":
            validate_green_reuse(packet, evidence, context)
        else:
            require(cycle["refactor"].get("verification_disposition", "executed") == "executed",
                    "tdd_evidence", pid, "Unknown REFACTOR verification disposition")
            require(cycle["green"]["invocation_ref"] != cycle["refactor"]["invocation_ref"], "tdd_evidence", pid, "REFACTOR rerun must be distinct")
        text(cycle["green"].get("production_file"), pid)
        text(cycle["refactor"].get("changes_made"), pid)


def worker_stage(request, packet, context, plan):
    """Materialize the same packet through existing bounded/separated role stages."""
    pid = packet["packet_id"]
    lane = context.get("build_execution_lane")
    require(lane in {"direct_main", "bounded_executor", "separated_workers"}, "lane_evidence", pid, "Resolve selected Build lane")
    applicability = PacketTestApplicability.parse(packet, plan, context)
    direct = lane == "direct_main"
    actor_field = "execution_actor_id" if direct else "writer_actor_id"
    if direct:
        require(not any(key in request for key in ("worker_stage", "worker_role", "current_task_packet", "inline_worker_stage")),
                "execution_actor", pid, "Direct execution has no worker projection")
        require(ExecutionActorBinding.parse(context, pid).kind == "main", "execution_actor", pid, "Direct main binding required")
        require(not context.get("writer_actor_ids") and not context.get("builder_actor_ids"),
                "execution_actor", pid, "Direct main context cannot claim child worker actors")
    else:
        require("execution_stage" not in request, "worker_stage", pid,
                "Delegated lanes select worker_stage; execution_stage belongs to direct_main")
    stage = request.get("execution_stage" if direct else "worker_stage", "implementation")
    tdd = packet["tdd_applies"]
    require(stage not in {"test_authoring", "pre_production_red"} or applicability.status == "required",
            "test_applicability", pid, "Test authoring/RED requires applicable tests")
    allowed = {"test_authoring", "pre_production_red", "production", "green", "refactor", "refactor_verification"} if tdd else {"test_authoring", "implementation", "production", "final_verification"}
    require(stage in allowed, "worker_stage", pid, "Select a concrete existing role/protocol stage")
    role = "builder_tester" if lane == "separated_workers" and stage in {"pre_production_red", "green", "refactor_verification", "final_verification"} else "code_writer"
    require(request.get("worker_role", role) == role, "worker_stage", pid, "Stage must retain selected-lane role ownership")
    # Resolve native actors, never configured role names.
    actors = object_value(context.get("writer_actor_ids", {}), "context.writer_actor_ids")
    actor = ExecutionActorBinding.parse(context, pid).actor_id if direct else actors.get(pid)
    if actor is not None:
        text(actor, "writer_actor_ids." + pid)
    evidence = context.get("packet_evidence", {}).get(pid)
    if evidence is not None:
        object_value(evidence, pid + ".evidence")
        if applicability.status == "not_applicable":
            applicability.assertion_source(evidence, actor, pid, actor_field)
    cycle_progress = evidence.get("tdd_cycle") if isinstance(evidence, dict) else None
    if tdd and stage in {"test_authoring", "pre_production_red"}:
        require(cycle_progress is None and packet["execution"].get("tdd_cycle_log_ref") is None,
                "worker_stage", pid, "New tests/RED cannot replay an existing cycle")
    if tdd and isinstance(cycle_progress, dict):
        prior_green = cycle_progress.get("green", {})
        prior_refactor = cycle_progress.get("refactor", {})
        require(not (isinstance(prior_refactor, dict) and prior_refactor.get("all_tests_pass") is True),
                "worker_stage", pid, "Completed cycle cannot authorize another stage")
        if stage == "production":
            require(not (isinstance(prior_green, dict) and prior_green.get("all_tests_pass") is True)
                    and not prior_refactor, "worker_stage", pid, "Production cannot replay passed GREEN or REFACTOR")
    if stage in {"test_authoring", "implementation"} or (stage == "production" and packet["execution"]["state"] == "PENDING" and (not tdd or lane in {"direct_main", "bounded_executor"})):
        # Record actual actor; never force bootstrap or fabricate identity.
        if evidence is not None and evidence.get(actor_field) is not None:
            require(actor is not None and evidence[actor_field] == actor,
                    "writer_lineage", pid, "Observed prior writer must match current native actor")
        return
    if stage == "pre_production_red":
        source = object_value(evidence, pid + ".test_source")
        identity = EvidenceIdentity.parse(source, pid)
        require(identity.approved_plan_identity == ApprovedPlanIdentity.parse(plan["approved_plan_identity"], pid)
                and identity.packet_definition_digest == digest(packet_definition(packet))
                and digest(identity.input_identity) == digest(context["current_input_identities"][pid])
                and source.get("build_execution_lane") == lane, "stale_evidence", pid, "Current test-source proof required")
        tests = object_value(source.get("tests"), pid + ".tests")
        require(tests.get("mode") in {"authored", "reuse"}, "test_ownership", pid, "Resolve selected assertion source")
        text(tests.get("evidence_ref"), pid + ".tests.evidence_ref")
        if tests["mode"] == "authored":
            require(actor is not None and tests.get(actor_field) == actor == source.get(actor_field),
                    "writer_lineage", pid, "Selected tests must belong to the same actual writer")
        return
    require(packet["execution"]["state"] == "RUNNING", "worker_stage", pid, "Later stages materialize the same started packet")
    evidence = object_value(context["packet_evidence"].get(pid), pid + ".evidence")
    identity = EvidenceIdentity.parse(evidence, pid)
    require(identity.approved_plan_identity == ApprovedPlanIdentity.parse(plan["approved_plan_identity"], pid)
            and identity.packet_definition_digest == digest(packet_definition(packet))
            and digest(identity.input_identity) == digest(context["current_input_identities"][pid])
            and evidence.get("build_execution_lane") == lane, "stale_evidence", pid, "Stage evidence must bind current packet, inputs and lane")
    text(evidence.get("native_evidence_ref"), pid)
    tests = applicability.assertion_source(evidence, actor, pid, actor_field)
    first_unobserved_production = (stage == "production" and (tests is None or tests["mode"] == "reuse")
                                  and evidence.get(actor_field) is None)
    require(first_unobserved_production or (actor is not None and evidence.get(actor_field) == actor),
            "writer_lineage", pid, "Later stages require the same observed native writer")
    if not tdd:
        text(evidence.get("implementation_evidence_ref"), pid)
        return
    cycle = actual_red(packet, evidence)
    if stage in {"green", "refactor", "refactor_verification"}:
        text(evidence.get("implementation_evidence_ref"), pid)
        text(object_value(cycle.get("green"), pid + ".green").get("production_file"), pid)
    if stage in {"refactor", "refactor_verification"}:
        green = cycle["green"]
        require(green.get("all_tests_pass") is True and green.get("command") == packet["red_command"]
                and green.get("cwd") == packet["red_cwd"], "tdd_evidence", pid, "Actual current GREEN must pass before refactor")
        text(green.get("invocation_ref"), pid)
    if stage == "refactor_verification":
        text(object_value(cycle.get("refactor"), pid + ".refactor").get("changes_made"), pid)


STAMP_CODES = {"build_execution_lane": "lane_evidence", "execution_actor_id": "execution_actor"}


STARTED_STATES = {"RUNNING", "BLOCKED", "VERIFIED"}
STARTED_MARKER_REASONS = ("started packet returned to PENDING", "started packet left started state")
STARTED_UNDER_STAMP_REASON = "started under current stamp"


def retained_execution(packet, context):
    """The packet's execution in the retained previous_plan, or None when absent."""
    return next((row["execution"] for row in (context.get("previous_plan") or {}).get("implementation_steps", [])
                 if row["packet_id"] == packet["packet_id"]), None)


def retained_start(packet, context):
    """Whether the packet started under its current stamp.

    A retained started state counts, as does a started history row after the
    latest stamp_baseline row (every row for a stamp without one). Rows before the
    current stamp, such as carried legacy history, do not. Reconciliation records
    a started row whenever a packet leaves a started state, and history rows cannot
    be dropped, so the start marker is durable. Reconciliation already proved the
    retained history is a prefix of the current one, so the current history suffices."""
    old = retained_execution(packet, context)
    history = packet["execution"]["history"]
    marks = [index for index, row in enumerate(history) if "stamp_baseline" in row]
    rows = history[marks[-1] + 1:] if marks else history
    return (old is not None and old["state"] in STARTED_STATES) or any(row.get("state") in STARTED_STATES for row in rows)


def stamp_baseline(execution):
    """The evidence baseline recorded when the current stamp was written, or None for older stamps."""
    rows = [row for row in execution["history"] if "stamp_baseline" in row]
    if not rows:
        return None
    baseline = object_value(rows[-1]["stamp_baseline"], "execution.history[].stamp_baseline")
    strings(baseline.get("evidence_refs"), "execution.history[].stamp_baseline.evidence_refs")
    return baseline


def stage_evidence_actors(proof):
    """The packet evidence records and the actors they name."""
    source = proof.get("test_source")
    records = [proof] + [row for row in (proof.get("tests"), source, source.get("tests") if isinstance(source, dict) else None)
                         if isinstance(row, dict)]
    return records, {row.get(field) for row in records for field in ("writer_actor_id", "execution_actor_id")} - {None}


def old_actor_stage_evidence(packet, context, old_lane, old_actor):
    """Whether the stamped actor already left stage evidence on this packet.

    Refs and the TDD log in the stamp baseline predate the stamp; only newer ones
    are the old actor's. Stamps without a baseline row fall back to the retained
    previous_plan; without either, attribution is unknown, so any of them count."""
    execution = packet["execution"]
    old = stamp_baseline(execution) or retained_execution(packet, context) or {}
    if (set(execution["evidence_refs"]) - set(old.get("evidence_refs", []))
            or ("tdd_cycle_log_ref" in execution and execution["tdd_cycle_log_ref"] != old.get("tdd_cycle_log_ref"))):
        return True
    proof = context.get("packet_evidence", {}).get(packet["packet_id"])
    if not isinstance(proof, dict):
        return False
    records, actors = stage_evidence_actors(proof)
    if old_actor is not None:
        return old_actor in actors
    # A lane-only stamp cannot attribute evidence; any stage output under that lane is the old actor's.
    return (old_lane in {row.get("build_execution_lane") for row in records}
            and bool(actors or {"implementation_evidence_ref", "builder_evidence_ref", "tdd_cycle", "test_source"} & proof.keys()))


def dispatch_execution_stamps(packet, context, stage_call=False):
    """Lane/actor stamps a dispatch writes only after every dispatch gate passes.

    Returns the stamps, the replaced prior stamps (empty when none differ) and
    whether this call fills the actor of a lane-only stamp."""
    target, execution = packet["packet_id"], packet["execution"]
    lane = context.get("build_execution_lane")
    actual_actor = (ExecutionActorBinding.parse(context, target).actor_id if lane == "direct_main"
                    else context.get("writer_actor_ids", {}).get(target))
    stamps = {"build_execution_lane": lane}
    if actual_actor is not None:
        stamps["execution_actor_id"] = actual_actor
    old = {field: execution[field] for field in STAMP_CODES if field in execution}
    differing = [field for field in STAMP_CODES if field in old and old[field] != stamps.get(field)]
    # A stamp lacking a field this dispatch writes is replaced too, under the same gate.
    added = [field for field in STAMP_CODES if old and field not in old and field in stamps]
    if not differing and not added:
        return stamps, {}, False
    # A lane-owned stage of the RUNNING packet fills a lane-only stamp's actor once.
    if not differing and added == ["execution_actor_id"] and execution["state"] == "RUNNING" and stage_call:
        require(retained_execution(packet, context) is not None, "execution_actor", target,
                "stamp replacement needs the retained previous_plan")
        require(not any("filled_stamps" in row for row in execution["history"]), "execution_actor", target,
                "A lane-only stamp fills its actor once")
        proof = context.get("packet_evidence", {}).get(target)
        require(not isinstance(proof, dict) or stage_evidence_actors(proof)[1] <= {actual_actor}, "execution_actor", target,
                "Stage evidence names another actor than the one filling the lane-only stamp")
        return stamps, {}, True
    # Only the retained previous_plan proves the packet never started under the
    # current stamp; without it a RUNNING->PENDING regression is indistinguishable.
    require(retained_execution(packet, context) is not None,
            "lane_evidence" if "build_execution_lane" in differing else "execution_actor", target,
            "stamp replacement needs the retained previous_plan")
    # A newly admitted dispatch may replace the stamp of a packet that is not RUNNING,
    # never started (a retained started state or any started history row; a
    # RUNNING->PENDING regression cannot unlock it) and has no stage evidence from
    # the old actor beyond the stamp baseline; otherwise stamps are immutable.
    replaceable = (execution["state"] != "RUNNING" and not retained_start(packet, context)
                   and not old_actor_stage_evidence(packet, context, old.get("build_execution_lane"), old.get("execution_actor_id")))
    require(replaceable or "build_execution_lane" not in differing, "lane_evidence", target,
            "A started packet or one with old-actor evidence cannot relabel its execution lane")
    require(replaceable, "execution_actor", target,
            "Retain the actual execution actor of a started packet or one with old-actor evidence")
    return stamps, old, False


def reconcile_execution(plan, context, checks):
    current = object_value(context.get("current_input_identities"), "context.current_input_identities")
    evidence = object_value(context.get("packet_evidence"), "context.packet_evidence")
    counters = object_value(context.get("recovery_counters", {}), "context.recovery_counters")
    previous = context.get("previous_plan")
    previous_packets = {}
    if previous is not None:
        object_value(previous, "context.previous_plan")
        require(previous.get("approved_plan_identity") == plan["approved_plan_identity"], "resume_identity", "previous_plan", "Resume must bind same approved plan")
        previous_packets = {p["packet_id"]: p for p in previous["implementation_steps"]}
    invalid = set()
    packets = {packet["packet_id"]: packet for packet in plan["implementation_steps"]}
    for packet in plan["implementation_steps"]:
        pid, execution = packet["packet_id"], packet["execution"]
        if "recovery" in execution and pid in counters:
            require(digest(execution["recovery"]) == digest(counters[pid]), "recovery_mismatch", pid,
                    "Historical counters must match independently retained observations")
        object_value(current.get(pid), "current_input_identities." + pid)
        require(bool(current[pid]), "input_identity", pid, "Current relevant-input identity required")
        if pid in previous_packets:
            old = previous_packets[pid]["execution"]
            require(isinstance(old, dict) and old.get("state") in STATES, "malformed", "previous_plan." + pid + ".execution.state",
                    "Retained execution state must be a known coordinator state")
            if "progress_guard_ref" in old:
                require("progress_guard_ref" in execution and execution["progress_guard_ref"] == old["progress_guard_ref"],
                        "progress_mismatch", pid, "Retain the independently recorded task guard across canonical snapshots")
            require(old["state"] != "VERIFIED" or execution["state"] == "VERIFIED",
                    "invalid_state", pid, "Caller cannot downgrade retained VERIFIED work; only helper reconciliation invalidates it")
            # Dispatch stamps persist (dispatch may leave PENDING); only a newly admitted
            # dispatch replaces them, and stripping them cannot relabel lane or actor.
            for field, code in STAMP_CODES.items():
                require(field not in old or execution.get(field) == old[field], code, pid,
                        "Retain the admitted dispatch " + field + " stamp")
                require(field in old or field not in execution, code, pid,
                        "Only an admitted dispatch writes the " + field + " stamp")
            # Recovery owner attests progress resets; spent attempts never reset.
            require(("recovery" not in old or ("recovery" in execution and execution["recovery"]["attempt_count"] >= old["recovery"]["attempt_count"]))
                    and digest(execution["history"][:len(old["history"])]) == digest(old["history"])
                    and set(old["evidence_refs"]) <= set(execution["evidence_refs"]), "recovery_mismatch", pid, "Resume cannot reset spent attempts or discard history/evidence")
            # Only admission writes stamp-baseline and started-marker rows; rows appended
            # beyond the retained prefix are the caller's and cannot carry them.
            require(not any("stamp_baseline" in row or "filled_stamps" in row or row.get("reason") in STARTED_MARKER_REASONS
                            for row in execution["history"][len(old["history"]):]), "recovery_mismatch", pid,
                    "Only admission writes stamp_baseline / started-marker rows")
            # A started packet that leaves its started state keeps a durable started marker.
            if old["state"] in STARTED_STATES and execution["state"] not in STARTED_STATES:
                reason = STARTED_MARKER_REASONS[0] if execution["state"] == "PENDING" else STARTED_MARKER_REASONS[1]
                execution["history"].append({"state": old["state"], "input_identity": deepcopy(old.get("input_identity")),
                                             "evidence_refs": deepcopy(old["evidence_refs"]), "reason": reason})
        # Committing a stamped packet to RUNNING records, once per stamp, a durable started row.
        if execution["state"] == "RUNNING" and any(field in execution for field in STAMP_CODES):
            marks = [index for index, row in enumerate(execution["history"]) if "stamp_baseline" in row]
            if not any(row.get("state") in STARTED_STATES for row in execution["history"][marks[-1] + 1 if marks else 0:]):
                execution["history"].append({"state": "RUNNING", "input_identity": deepcopy(execution.get("input_identity")),
                                             "evidence_refs": deepcopy(execution["evidence_refs"]), "reason": STARTED_UNDER_STAMP_REASON})
        if digest(execution.get("input_identity")) != digest(current[pid]):
            invalid.add(pid)
        if execution["state"] == "INVALIDATED" or set(packet["depends_on"]) & invalid:
            invalid.add(pid)
        if execution["state"] == "VERIFIED" and any(
                packets[dep]["execution"]["state"] != "VERIFIED" for dep in packet["depends_on"]):
            invalid.add(pid)
        if execution["state"] == "VERIFIED" and pid not in invalid:
            try:
                verified_packet(packet, evidence.get(pid), plan, context, checks)
            except AdmissionError:
                invalid.add(pid)
        if pid in invalid:
            if execution["state"] != "INVALIDATED":
                execution["history"].append({"state": execution["state"], "input_identity": deepcopy(execution.get("input_identity")),
                                             "evidence_refs": deepcopy(execution["evidence_refs"]), "reason": "relevant inputs or prerequisite/evidence changed"})
            execution["state"] = "INVALIDATED"
    return invalid


def historical_attestation(source, context, version):
    """Caller-attested historical producer of an approved v14/v15 definition.

    A version label alone is not provenance. Absent attestation stays unknown
    (current plan review remains due); a supplied contradicting one blocks.
    """
    value = context.get("historical_plan_attestation")
    if value is None:
        return None
    path = "context.historical_plan_attestation"
    obj = object_value(value, path)
    require(set(obj) == {"schema_version", "verified", "producer_ref", "definition_sha256"}
            and obj.get("schema_version") == version and obj.get("verified") is True
            and obj.get("definition_sha256") == source["approved_plan_identity"]["definition_digest"] == digest(definition(source)),
            "legacy_provenance", path, "Attestation must verify this historical version and approved definition")
    text(obj.get("producer_ref"), path + ".producer_ref")
    return deepcopy(obj)


def _normalize_version(source, context, source_version, target_version, provenance_key, mapping_ref,
                       attestation=None, resolved=False):
    """Normalize independently approved v14 representation and matching authority.

    Preserve original approval provenance; return canonical context for caller retention.
    """
    validate_plan(source, context, source_version)
    if not resolved:
        attestation = historical_attestation(source, context, source_version)
    original_identity = deepcopy(source["approved_plan_identity"])
    plan, current = deepcopy(source), deepcopy(context)
    plan["plan_schema_version"] = target_version
    normalized_identity = {**original_identity, "definition_digest": digest(definition(plan))}
    plan["approved_plan_identity"] = deepcopy(normalized_identity)
    provenance = plan.setdefault("reconciliation_provenance", {})
    provenance[provenance_key] = {
        "producer_schema_version": source_version, "consumer_schema_version": target_version,
        "source_sha256": digest(source), "original_approved_plan_identity": original_identity,
        "normalized_definition_digest": normalized_identity["definition_digest"],
        "mapping_ref": mapping_ref, "historical_attestation": deepcopy(attestation),
        "packet_mapping": [{"source_packet_id": p["packet_id"], "packet_id": p["packet_id"],
                            "packet_definition_digest": digest(packet_definition(p))} for p in source["implementation_steps"]]}
    # Identity-only migration; preserve execution facts literally.
    for rows in (current.get("packet_evidence", {}), current.get("test_applicability", {})):
        for row in rows.values():
            if row.get("approved_plan_identity") == original_identity:
                row["approved_plan_identity"] = deepcopy(normalized_identity)
    sources = (current.get("progress") or {}).get("resolved_sources", {})
    for scope in sources.values():
        if (isinstance(scope, dict) and scope.get("kind") == "coordinator_action_scope"
                and scope.get("approved_plan_identity") == original_identity):
            scope["approved_plan_identity"] = deepcopy(normalized_identity)
            ref = scope.get("grouping_decision_ref")
            decision = sources.get(ref) if isinstance(ref, str) else None
            if isinstance(decision, dict) and decision.get("approved_plan_identity") == original_identity:
                decision["approved_plan_identity"] = deepcopy(normalized_identity)
    if isinstance(current.get("completion_evidence"), dict) and current["completion_evidence"].get("approved_plan_identity") == original_identity:
        current["completion_evidence"]["approved_plan_identity"] = deepcopy(normalized_identity)
    if isinstance(current.get("previous_plan"), dict):
        prior = current["previous_plan"]
        require(prior.get("approved_plan_identity") == original_identity, "resume_identity", "previous_plan", "Original migration snapshot must bind original approval")
        require(digest(definition(prior)) == original_identity["definition_digest"], "resume_identity", "previous_plan", "Original retained definition changed")
        prior["plan_schema_version"] = target_version
        prior["approved_plan_identity"] = deepcopy(normalized_identity)
        prior["reconciliation_provenance"] = deepcopy(provenance)
    current["approved_plan_identity"] = deepcopy(normalized_identity)
    return plan, current


def normalize_v14(source, context, attestation=None, resolved=False):
    return _normalize_version(source, context, "14.0", "15.0", "workflow_migration",
                              "task-packet-admission.py#normalize_v14", attestation, resolved)


def normalize_v15(source, context, attestation=None, resolved=False):
    """Authenticate original v15 approval before identity-only representation migration."""
    return _normalize_version(source, context, "15.0", "16.0", "workflow_v16_migration",
                              "task-packet-admission.py#normalize_v15", attestation, resolved)


def progress_checkpoint(context):
    carrier = context.get("progress")
    if carrier is None:
        return None
    object_value(carrier, "context.progress")
    sources = object_value(carrier.get("resolved_sources"), "context.progress.resolved_sources")
    state = PROGRESS.ProgressState.parse(carrier.get("state"), sources)
    outcome = PROGRESS.resolved(sources, state.guard.outcome_ref)
    require(outcome.get("task_identity") == context.get("task_identity"), "progress_mismatch", "context.progress", "Guard must retain the intended task outcome")
    return state


def _validate_progress_witnesses(plan, context, state):
    """Reconcile retained execution checkpoints without changing progress."""
    checkpoints = {event.event_id: event.assessment_ref for event in state.history if event.kind == "work_checkpoint"}
    summarized = set(PROGRESS.resolved(context["progress"]["resolved_sources"], state.history_base_ref)["seen_event_ids"]) if state.history_base_ref else set()
    for retained_plan in (plan, context.get("previous_plan") or {}):
        for retained_packet in retained_plan.get("implementation_steps", []):
            retained_execution = retained_packet["execution"]
            if retained_execution.get("progress_guard_ref") != state.guard.guard_id:
                continue
            for row in retained_execution["history"]:
                if row.get("kind") != "work_checkpoint":
                    continue
                require(all(isinstance(row.get(key), str) and bool(row[key].strip()) for key in ("event_id", "evidence_ref")),
                        "progress_history_missing", retained_packet["packet_id"], "Explicit checkpoints require event and assessment references")
                require(row["event_id"] in summarized or checkpoints.get(row["event_id"]) == row["evidence_ref"],
                        "progress_history_missing", retained_packet["packet_id"], "Retain explicitly observed semantic checkpoints in progress history")


def progress_admission(packet, context, state, plan):
    execution = packet["execution"]
    if state is None:
        require(not execution.get("recovery", {}).get("attempt_count", 0)
                and not execution.get("progress_guard_ref"), "progress_history_missing", packet["packet_id"],
                "Repeated work requires retained progress observations; old totals do not prove a stall or fresh window")
        return None
    carrier = context["progress"]
    action = PROGRESS.ActionIdentity.parse(carrier.get("action"))
    pid = packet["packet_id"]
    scope = action.member_scope
    retained = state.action_admission
    if scope is None:
        definition = digest(packet_definition(packet))
        if retained is not None and retained.action.action_ref == action.action_ref:
            require(retained.action.packet_definition_digest is not None, "progress_history_missing", pid,
                    "Reconstruct the original admitted definition")
            require(retained.action.packet_definition_digest == definition, "progress_mismatch", pid,
                    "Current work differs from its admitted definition")
        require(action.packet_definition_digest is None or action.packet_definition_digest == definition,
                "progress_mismatch", pid, "Proposed action differs from approved definition")
        action = replace(action, packet_definition_digest=definition)
    matching = retained is not None and retained.action == action
    if scope:
        source = scope.authority(carrier["resolved_sources"], state.guard, action.action_ref)
        require(digest(source["approved_plan_identity"]) == digest(plan["approved_plan_identity"]),
                "progress_mismatch", pid, "Grouping must bind current approved Plan")
        packets = {row["packet_id"]: row for row in plan["implementation_steps"]}
        previous_members = {row["packet_id"]: row["execution"] for row in context.get("previous_plan", {}).get("implementation_steps", [])}
        for member in scope.members:
            require(member.packet_id in packets and member.packet_definition_digest == digest(packet_definition(packets[member.packet_id]))
                    and digest(member.input_identity.wire()) == digest(context["current_input_identities"][member.packet_id]),
                    "progress_mismatch", pid, "Group member must bind canonical definition and current input")
            if matching and previous_members.get(member.packet_id, {}).get("action_admission_ref") == retained.admission_ref:
                require(packets[member.packet_id]["execution"].get("action_admission_ref") == retained.admission_ref,
                        "progress_replay", pid, "Cannot erase any committed member join")
        bound = next((row for row in scope.members if row.packet_id == pid), None)
    else:
        bound = action if action.packet_id == pid else None
    require(execution.get("progress_guard_ref") == state.guard.guard_id
            and execution.get("action_ref") == action.action_ref and bound is not None
            and digest(bound.input_identity.wire()) == digest(context["current_input_identities"][pid]),
            "progress_mismatch", pid, "Action/guard must bind independently current packet and inputs")
    continuing = execution["state"] == "RUNNING" and matching
    if scope and retained is not None:
        require(matching, "progress_replay", pid, "Retain complete admitted coordinator scope")
        previous = next((row["execution"] for row in context.get("previous_plan", {}).get("implementation_steps", [])
                         if row["packet_id"] == pid), {})
        joined = execution.get("action_admission_ref") == retained.admission_ref
        was_joined = previous.get("action_admission_ref") == retained.admission_ref
        require(not was_joined or joined, "progress_replay", pid, "Cannot erase a committed coordinator join")
        if execution["state"] == "PENDING":
            require(not joined and not was_joined, "progress_replay", pid, "Member already joined this coordinator")
            continuing = True
    if execution["state"] == "RUNNING" and retained is not None:
        require(continuing and execution.get("action_admission_ref") == retained.admission_ref,
                "progress_replay", pid, "Retain original admitted action for later RUNNING stages")
    result = PROGRESS.transition(PROGRESS.ProgressTransitionRequest(
        state, carrier["resolved_sources"], action=action, admit=True, continuing=continuing))
    return result.state


def _execution_lineage(packet, execution, context, progress):
    pid = packet["packet_id"]
    require(progress is not None, "progress_history_missing", pid, "Certification needs retained admission binding")
    require(execution.get("progress_guard_ref") == progress.guard.guard_id,
            "progress_mismatch", pid, "Execution must retain its task guard")
    action = PROGRESS.ActionIdentity.parse({"action_ref": execution.get("action_ref"),
        "packet_id": pid, "input_identity": execution["input_identity"],
        "packet_definition_digest": digest(packet_definition(packet))})
    lineage = progress.action_lineage(action, execution["action_admission_ref"], context["progress"]["resolved_sources"])
    require(lineage.location != "unknown", "progress_history_missing", pid, "Reconstruct the admitted packet/member/input/definition binding")
    require(lineage.location != "missing", "progress_mismatch", pid, "Execution differs from its admitted binding")
    return lineage


def preserve_execution_pairs(plan, context, progress):
    """Validate the final snapshot before it replaces independently retained pairs."""
    previous = {p["packet_id"]: p["execution"] for p in (context.get("previous_plan") or {}).get("implementation_steps", [])}
    for packet in plan["implementation_steps"]:
        pid, execution = packet["packet_id"], packet["execution"]
        old = previous.get(pid, {})
        if "action_admission_ref" not in old:
            continue
        require("action_ref" in execution and "action_admission_ref" in execution,
                "progress_mismatch", pid, "Retain the committed action/admission pair")
        if all(execution[field] == old.get(field) for field in ("action_ref", "action_admission_ref")):
            if execution["state"] in {"RUNNING", "VERIFIED"} and (
                    execution["state"] != old["state"] or execution["input_identity"] != old["input_identity"]):
                _execution_lineage(packet, execution, context, progress)
            continue
        require(progress is not None, "progress_history_missing", pid, "Changed pairs need retained progress proof")
        sources = context["progress"]["resolved_sources"]
        before = progress.predecessor_lineage(PROGRESS.ActionIdentity.parse({"action_ref": old.get("action_ref"),
            "packet_id": pid, "input_identity": old["input_identity"]}), old["action_admission_ref"], sources)
        after = _execution_lineage(packet, execution, context, progress)
        require(before.location != "unknown", "progress_history_missing", pid, "Reconstruct the predecessor admission binding")
        require(not (before.location == after.location == "summary"),
                "progress_history_missing", pid, "Reconstruct ordering between summarized pairs")
        require(before.location in {"checkpoint", "summary"} and
                (after.location == "admitted" or (after.location == "checkpoint" and
                 (before.location == "summary" or after.work_ordinal > before.work_ordinal))),
                "progress_mismatch", pid, "A changed pair must genuinely succeed its closed predecessor")


def authenticate_provenance(plan, context):
    """Only trusted normalization creates provenance; later calls retain it exactly."""
    previous = context.get("previous_plan")
    present = "reconciliation_provenance" in plan
    previous_present = isinstance(previous, dict) and "reconciliation_provenance" in previous
    if not present and not previous_present:
        return
    require(isinstance(previous, dict), "legacy_provenance", "context.previous_plan",
            "Canonical migration provenance requires an independently retained accepted snapshot")
    require(digest(previous.get("approved_plan_identity")) == digest(plan.get("approved_plan_identity")),
            "resume_identity", "previous_plan", "Retained migration snapshot must bind the same approved plan")
    require(present == previous_present and
            digest(plan.get("reconciliation_provenance")) == digest(previous.get("reconciliation_provenance")),
            "legacy_provenance", "reconciliation_provenance", "Canonical calls cannot add, alter or discard retained migration provenance")


def unchanged_migrated_approval(plan):
    """Only an attested historical producer grandfathers its unchanged original approval.

    Retained provenance is re-derived, never trusted by shape: each migration row
    must bind the current definition relabelled to its producer version, and the
    attestation must pass the historical_attestation shape/digest checks against
    that original identity. Callers still own the attestation itself (U3).
    """
    provenance = plan.get("reconciliation_provenance")
    identity = plan["approved_plan_identity"]
    current = definition(plan)
    if not isinstance(provenance, dict) or identity["definition_digest"] != digest(current):
        return False

    def original_digest(version):
        return digest({**current, "plan_schema_version": version})

    def bound(row, producer, consumer, normalized):
        return (isinstance(row, dict) and row.get("producer_schema_version") == producer
                and row.get("consumer_schema_version") == consumer
                and row.get("normalized_definition_digest") == normalized
                and row.get("original_approved_plan_identity") == {**identity, "definition_digest": original_digest(producer)})

    v16 = provenance.get("workflow_v16_migration")
    if not bound(v16, "15.0", "16.0", identity["definition_digest"]):
        return False
    attestation = v16.get("historical_attestation")
    if not isinstance(attestation, dict):
        return False
    if "workflow_migration" not in provenance:
        version = "15.0"
    else:
        v15 = provenance["workflow_migration"]
        if not (bound(v15, "14.0", "15.0", original_digest("15.0"))
                and digest(v15.get("historical_attestation")) == digest(attestation)):
            return False
        version = "14.0"
        if attestation.get("schema_version") in {"12.0", "13.0"}:
            # Verified v12/v13 producer provenance attests its own normalized v14 plan.
            producer = provenance.get("producer")
            return (isinstance(producer, dict) and producer.get("verified") is True
                    and attestation == {"schema_version": producer.get("schema_version"), "verified": True,
                                        "producer_ref": producer.get("producer_ref"),
                                        "source_sha256": provenance.get("source_sha256")}
                    and isinstance(attestation["producer_ref"], str) and bool(attestation["producer_ref"].strip()))
    return (set(attestation) == {"schema_version", "verified", "producer_ref", "definition_sha256"}
            and attestation.get("schema_version") == version and attestation.get("verified") is True
            and isinstance(attestation.get("producer_ref"), str) and bool(attestation["producer_ref"].strip())
            and attestation.get("definition_sha256") == original_digest(version))


def current_review_required(plan, context):
    """Grandfather only the authenticated unchanged original approval/definition."""
    unchanged = unchanged_migrated_approval(plan)
    required = context["readiness"].get("plan_review_required")
    if required is not None:
        require(type(required) is bool, "review_authority", "readiness", "Review applicability must resolve independently")
        if not required and not unchanged:
            ref = text(context["readiness"].get("plan_review_applicability_ref"), "plan_review_applicability_ref")
            fact = object_value(context.get("plan_review_applicability_authority", {}).get(ref), ref)
            require(fact.get("approved_plan_identity") == plan["approved_plan_identity"]
                    and fact.get("reason") in {"no_plan_required", "unchanged_already_running_approved_plan"},
                    "review_authority", ref, "Resolve the exact current plan-review applicability exception")
            if fact["reason"] == "unchanged_already_running_approved_plan":
                previous = context.get("previous_plan")
                require(isinstance(previous, dict) and previous.get("approved_plan_identity") == plan["approved_plan_identity"]
                        and any(isinstance(p, dict) and isinstance(p.get("execution"), dict)
                                and p["execution"].get("state") != "PENDING"
                                for p in previous.get("implementation_steps") or []),
                        "review_authority", ref,
                        "An already-running exception needs the retained previous_plan of the same approval with started work")
        return required
    return not unchanged


def exact_actor_id(value, path):
    """Actor ids compare exactly; surrounding whitespace is rejected, never normalized.
    Blank ids keep their existing missing/blank handling."""
    require(not isinstance(value, str) or not value.strip() or value == value.strip(), "review_authority", path,
            "Actor ids cannot carry surrounding whitespace")
    return value


def reviewed_work_actor_ids(context):
    """Writer, Builder and execution actors (including the main binding) of reviewed work."""
    actors = set()
    for key in ("writer_actor_ids", "builder_actor_ids"):
        for value in object_value(context.get(key) or {}, "context." + key).values():
            actors.update(exact_actor_id(actor, "context." + key) for actor in (value if isinstance(value, list) else [value]))
    for row in object_value(context.get("execution_actor_bindings") or {}, "context.execution_actor_bindings").values():
        actors.add(exact_actor_id(object_value(row, "context.execution_actor_bindings[]").get("actor_id"),
                                  "context.execution_actor_bindings"))
    return actors


def require_builder_actors_resolved(context, path):
    """Separated Builder evidence needs its native actor, or independence fails open."""
    if context.get("build_execution_lane") != "separated_workers":
        return
    builders = object_value(context.get("builder_actor_ids") or {}, "context.builder_actor_ids")
    for pid, proof in object_value(context.get("packet_evidence") or {}, "context.packet_evidence").items():
        if isinstance(proof, dict) and "builder_evidence_ref" in proof:
            actors = builders.get(pid)
            actors = actors if isinstance(actors, list) else [actors]
            require(bool(actors) and all(isinstance(a, str) and a.strip() for a in actors),
                    "review_authority", path, "Resolve builder_actor_ids for every packet with Builder evidence")


def require_distinct_review_authorities(facts, path):
    """Each current v10 review authority is a different native actor/invocation/dispatch."""
    for ref, fact in facts.items():
        if fact.get("producer_version") != "10.0":
            continue
        exact_actor_id(fact.get("actor_id"), path)
        for other_ref, other in facts.items():
            if other_ref == ref:
                continue
            for field in ("actor_id", "native_invocation_id", "fresh_dispatch_evidence_ref"):
                require(fact.get(field) is None or fact.get(field) != other.get(field), "review_authority", path,
                        "A current review authority cannot reuse another review's " + field)


def require_independent_reviewer(fact, context, path):
    actor = exact_actor_id(text(fact.get("actor_id"), path + ".actor_id"), path + ".actor_id")
    require(actor not in reviewed_work_actor_ids(context), "review_authority", path,
            "A review actor cannot be a writer, Builder or execution actor of the reviewed work")


def validate_plan_review_order(ref, fact, plan, context):
    """Plan review precedes approval: it binds the reviewed definition, never an approval_ref,
    and the approval authority must reference that validated plan review."""
    identity = plan["approved_plan_identity"]
    reviewed = object_value(fact.get("reviewed_plan_identity"), "plan.reviewed_plan_identity")
    require("approved_plan_identity" not in fact and set(reviewed) == {"task_identity", "plan_version", "definition_digest"}
            and all(reviewed[key] == identity[key] for key in reviewed),
            "review_authority", "plan.reviewed_plan_identity",
            "Plan review binds exactly the approved task, plan version and definition without an approval_ref")
    approvals = object_value(context.get("plan_approval_authorities"), "context.plan_approval_authorities")
    approval = object_value(approvals.get(identity["approval_ref"]), "plan_approval_authorities." + identity["approval_ref"])
    require(approval.get("approval_ref") == identity["approval_ref"]
            and approval.get("approved_plan_identity") == identity
            and approval.get("plan_review_ref") == ref,
            "review_authority", "plan_approval_authorities", "Approval must reference the validated plan review; approval before review cannot authorize Build")


def validate_review_authority(ref, subject, plan, context, snapshot=None):
    """Consume the canonical Review v10 aggregate projection, never another progress ledger.

    Only request_plan_reconciliation keeps the producer's names (review-tools.py);
    fresh_dispatch_evidence_ref is the ref to Review's retained fresh_dispatch /
    fresh_context_evidence.
    A pre-Build plan review reconciles request and plan allocation (observed means
    allocated); only final acceptance additionally proves delivered task-wide work
    is finished with an explicit empty unfinished_task_wide_work.
    """
    text(ref, subject + ".review_ref")
    require(subject in {"plan", "acceptance"}, "review_authority", subject, "Only plan or acceptance reviews reconcile the request")
    authorities = context.get("review_authorities")
    require(isinstance(authorities, dict) and ref in authorities, "review_authority", subject + ".review_ref",
            subject + "_review_missing: the referenced current review is not retained in review_authorities")
    fact = object_value(authorities[ref], subject)
    require(fact.get("review_subject") == subject and fact.get("producer_version") == "10.0"
            and fact.get("result") in {"CLEAN", "ISSUES_FIXED"} and fact.get("coverage_complete") is True
            and (subject == "plan" or fact.get("approved_plan_identity") == plan["approved_plan_identity"])
            and fact.get("canonical_review_ref") == ref,
            "review_authority", subject, "Current canonical fresh independent review must bind this approved plan")
    text(fact.get("fresh_dispatch_evidence_ref"), subject + ".fresh_dispatch_evidence_ref")
    if subject == "plan":
        require(fact.get("subagent_execution_mode") == "delegated" and fact.get("validation_status") == "validated"
                and fact.get("terminal_state") == "completed", "review_authority", subject,
                "Plan review needs completed validated fresh delegated authority; author, fallback or unvalidated review cannot substitute")
        require_independent_reviewer(fact, context, subject)
        validate_plan_review_order(ref, fact, plan, context)
    coverage = object_value(fact.get("request_plan_reconciliation"), subject + ".request_plan_reconciliation")
    for field in ("original_request_ref", "approved_plan_ref"):
        text(coverage.get(field), subject + ".request_plan_reconciliation." + field)
    # Plan review precedes approval: approved_plan_ref names the reviewed definition
    # bound by reviewed_plan_identity, never the approval recorded afterwards.
    require(subject != "plan" or coverage["approved_plan_ref"] != plan["approved_plan_identity"]["approval_ref"],
            "review_authority", subject + ".request_plan_reconciliation.approved_plan_ref",
            "Plan review references the reviewed plan definition, not a later approval")
    expected = {row["requirement_id"] for row in context["requirements"]}
    required = strings(coverage.get("required_requirement_ids"), subject + ".required_requirement_ids", True)
    observed = strings(coverage.get("observed_requirement_ids"), subject + ".observed_requirement_ids")
    require(set(required) == expected and set(observed) == expected
            and coverage.get("unresolved_requirement_ids") == [] and coverage.get("unresolved_finding_ids") == [],
            "review_authority", subject, "Original request and approved plan must reconcile without unresolved requirements or findings")
    if subject == "acceptance":
        require(coverage.get("unfinished_task_wide_work") == [], "review_authority", subject,
                "Final reconciliation requires no unfinished task-wide work in the actual outcome")
    elif "unfinished_task_wide_work" in coverage:
        # Plan review: optional, may be nonempty and is not gated; type is string[].
        for item in array(coverage["unfinished_task_wide_work"], subject + ".unfinished_task_wide_work"):
            text(item, subject + ".unfinished_task_wide_work[]")
    if snapshot is not None:
        require(fact.get("snapshot_identity") == snapshot, "snapshot_mismatch", subject,
                "Final review must bind the integrated current snapshot")
    return fact


def validate_completion_authority(gate, terminal, plan, context, snapshot):
    """Bind current or genuinely completed historical acceptance to its owner."""
    ref = text(terminal.get("canonical_review_ref"), gate + ".canonical_review_ref")
    fact = object_value(object_value(context.get("review_authorities"), "review_authorities").get(ref), ref)
    qa = gate == "qa"
    roles = {"QAEvaluator"} if qa else {"CodeReviewer", "Reviewer"}
    contract = "assistant-review/contracts/output.yaml#" + ("qa_evaluation_result" if qa else "final_summary")
    require(fact.get("review_subject") == "acceptance" and fact.get("role") in roles
            and fact.get("canonical_contract") == contract and fact.get("canonical_result_ref") == ref
            and fact.get("canonical_review_ref") == ref and fact.get("terminal_state") == "completed"
            and fact.get("coverage_complete") is True and fact.get("result") in {"CLEAN", "ISSUES_FIXED"},
            "review_authority", gate, "Resolve the actual completed canonical acceptance source and role")
    require(fact.get("snapshot_identity") == snapshot, "snapshot_mismatch", gate,
            "Acceptance source must bind the actual current snapshot")
    for field in ("actor_id", "native_invocation_id", "native_evidence_ref"):
        text(fact.get(field), gate + "." + field)
    version = fact.get("producer_version")
    if not (version == "9.0" and fact.get("subagent_execution_mode") == "direct_fallback"
            and unchanged_migrated_approval(plan)):
        # Only the attested unchanged historical v9 fallback retains its original same-session policy.
        require_independent_reviewer(fact, context, gate)
        require_builder_actors_resolved(context, gate)
    if version == "9.0":
        provenance = plan.get("reconciliation_provenance", {})
        original = [row.get("original_approved_plan_identity") for key, row in provenance.items()
                    if key in {"workflow_migration", "workflow_v16_migration"} and isinstance(row, dict)]
        require(unchanged_migrated_approval(plan) and fact.get("approved_plan_identity") in original
                and fact.get("subagent_execution_mode") in {"delegated", "direct_fallback"},
                "review_authority", gate, "Historical completion needs original approval/provenance and actual original policy")
    else:
        require(version == "10.0" and fact.get("approved_plan_identity") == plan["approved_plan_identity"]
                and fact.get("validation_status") == "validated"
                and fact.get("subagent_execution_mode") == "delegated",
                "review_authority", gate, "Current acceptance needs validated fresh native authority independently of plan review")
        text(fact.get("fresh_dispatch_evidence_ref"), gate + ".fresh_dispatch_evidence_ref")
    if qa:
        require(fact.get("final_verdict") in {"accepted", "accepted_with_concerns"},
                "review_authority", gate, "Retain the actual QAEvaluator verdict; never manufacture CLEAN")
        expected = object_value(context.get("qa_acceptance_context"), "qa_acceptance_context")
        source = text(expected.get("source_ref"), "qa_acceptance_context.source_ref")
        criteria = strings(expected.get("acceptance_criteria"), "qa_acceptance_context.acceptance_criteria", True)
        observed = strings(fact.get("covered_acceptance_criteria"), gate + ".covered_acceptance_criteria", True)
        require(len(criteria) == len(set(criteria)) and len(observed) == len(set(observed))
                and set(observed) == set(criteria) and fact.get("acceptance_source_ref") == source,
                "review_authority", gate, "Actual QA coverage must exactly match independently accepted scoped criteria")
    elif version == "10.0":
        validate_review_authority(ref, "acceptance", plan, context, snapshot)
    return fact


def admission(request):
    """Calculate an admission result without mutating the request or external state."""
    snapshot, progress, rollback = None, None, []
    try:
        object_value(request, "request")
        boundary = request.get("boundary")
        require(boundary in BOUNDARIES, "unsupported_boundary", "boundary", "Unknown admission operation")
        context = object_value(request.get("context"), "context")
        # Retain checkpoints before later gates.
        progress = progress_checkpoint(context)
        if progress is not None:
            carrier = context["progress"]
            event = PROGRESS.ProgressEvent.parse(carrier["event"]) if carrier.get("event") is not None else None
            progress = PROGRESS.transition(PROGRESS.ProgressTransitionRequest(progress, carrier["resolved_sources"], event)).state
        readiness = object_value(context.get("readiness"), "context.readiness")
        require(readiness.get("execution_intent") in {"implement_only", "end_to_end"}, "no_execution", "readiness.execution_intent", "Preparation produces no executable work")
        require(readiness.get("ready") is True and readiness.get("route_clear") is True,
                "not_ready", "readiness", "Unresolved discovery/route-clear gates block executable work")
        source = object_value(request.get("plan"), "plan")
        current_schema = source.get("plan_schema_version") == "16.0"
        attestation, resolved = None, False
        if "plan_schema_version" not in source and ("schema_version" in source or "legacy" in context):
            snapshot = normalize_legacy(source, context)
            # normalize_legacy already verified this producer and source digest.
            producer = snapshot["reconciliation_provenance"]["producer"]
            attestation = {"schema_version": producer["schema_version"], "verified": True,
                           "producer_ref": producer["producer_ref"],
                           "source_sha256": snapshot["reconciliation_provenance"]["source_sha256"]}
            resolved = True
        else:
            require("schema_version" not in source, "mixed_schema", "plan", "Explicit verified legacy admission required")
            authenticate_provenance(source, context)
            snapshot = deepcopy(source)
        if snapshot.get("plan_schema_version") == "14.0":
            snapshot, context = normalize_v14(snapshot, context, attestation, resolved)
            attestation, resolved = snapshot["reconciliation_provenance"]["workflow_migration"]["historical_attestation"], True
        if snapshot.get("plan_schema_version") == "15.0":
            snapshot, context = normalize_v15(snapshot, context, attestation, resolved)
        checks, _ = validate_plan(snapshot, context)
        if boundary == "resume":
            require(context.get("previous_plan") is not None, "resume_identity", "context.previous_plan", "Resume needs independently retained last snapshot")
        invalid = reconcile_execution(snapshot, context, checks)
        marked_executions = [(p["packet_id"], p["execution"])
                             for retained_plan in (snapshot, context.get("previous_plan") or {})
                             for p in retained_plan.get("implementation_steps", [])
                             if any(field in p["execution"] for field in
                                    ("progress_guard_ref", "action_ref", "action_admission_ref"))]
        if boundary in {"dispatch", "completion"}:
            require(not marked_executions or progress is not None, "progress_history_missing", "context.progress",
                    "Retain task progress bound by current or previous executions")
            for pid, execution in marked_executions:
                require(execution.get("progress_guard_ref") == progress.guard.guard_id,
                        "progress_mismatch", pid, "Retain the same task guard")
        if boundary in {"dispatch", "completion"} and progress is not None:
            _validate_progress_witnesses(snapshot, context, progress)
        packets = {packet["packet_id"]: packet for packet in snapshot["implementation_steps"]}
        target = request.get("target_packet_id")
        packet = None
        if boundary in {"dispatch", "verification"}:
            require(target in packets, "unknown_packet", "target_packet_id", "Resolve exactly one canonical packet")
            packet = packets[target]
            require(not any(packets[dep]["execution"]["state"] != "VERIFIED" for dep in packet["depends_on"]),
                    "prerequisite_unverified", target, "Every prerequisite must be evidence-bound VERIFIED")
            require(target not in invalid, "invalidated", target, "Reconcile invalidated inputs and evidence before dispatch or verification")
        if boundary == "completion":
            require(all(p["execution"]["state"] == "VERIFIED" for p in packets.values()), "incomplete_packets", "implementation_steps", "Every canonical packet must be VERIFIED")
            # As at verification, unstamped current-schema VERIFIED work needs the retained
            # snapshot; a historical plan normalized by this call predates stamps.
            for pid, p in packets.items():
                require(not current_schema or "build_execution_lane" in p["execution"] or context.get("previous_plan") is not None,
                        "lane_evidence", pid, "VERIFIED work needs its admission stamps or the retained previous_plan")
        plan_review = None
        if boundary in {"dispatch", "verification", "completion"} and current_review_required(snapshot, context):
            # Dispatch, verification and completion each re-evaluate the one plan-review authority.
            require(context["readiness"].get("plan_review_ref") is not None, "review_authority", "plan.review_ref",
                    "plan_review_missing: a current plan review is due; obtain it and record the approval that references it")
            plan_review = validate_review_authority(context["readiness"]["plan_review_ref"], "plan", snapshot, context)
        if boundary == "dispatch":
            lane = context.get("build_execution_lane")
            stage_key = "execution_stage" if lane == "direct_main" else "worker_stage"
            require(packet["execution"]["state"] == "PENDING" or (packet["execution"]["state"] == "RUNNING" and stage_key in request),
                    "invalid_state", target, "Materialize PENDING work or an explicit lane-owned stage of the same RUNNING packet")
            worker_stage(request, packet, context, snapshot)
            execution_stamps, replaced_stamps, filled_actor = dispatch_execution_stamps(packet, context, stage_key in request)
            source_writer = bool(packet["files_to_create"] or packet["files_to_modify"])
            workspace = object_value(context.get("workspace"), "context.workspace")
            active_ids = set(strings(workspace.get("active_source_writer_ids"), "workspace.active_source_writer_ids"))
            require(active_ids <= packets.keys(), "workspace_overlap", target,
                    "Resolve current source-writer activity independently")
            require(target not in active_ids, "workspace_overlap", target,
                    "The prior source Writer must be terminal before another same-packet role dispatch")
            # Candidate barriers cannot remove independently observed unfinished writers.
            active_ids |= {other["packet_id"] for other in packets.values() if other["packet_id"] != target
                           and other["execution"]["state"] in {"RUNNING", "BLOCKED", "INVALIDATED"}
                           and (other["files_to_create"] or other["files_to_modify"])}
            running = [packets[pid] for pid in active_ids]
            if source_writer and running:
                require(workspace.get("mode") == "isolated", "workspace_overlap", target, "Shared or unknown source writers serialize")
                isolation = object_value(workspace.get("isolation"), "workspace.isolation")
                locations = []
                for pid in [target] + [other["packet_id"] for other in running]:
                    fact = object_value(isolation.get(pid), "workspace.isolation." + pid)
                    require(fact.get("current") is True and digest(fact.get("input_identity")) == digest(context["current_input_identities"][pid]),
                            "workspace_overlap", pid, "Current independent runtime isolation evidence required")
                    text(fact.get("runtime_evidence_ref"), pid)
                    locations.append(text(fact.get("workspace_identity"), pid))
                require(len(locations) == len(set(locations)), "workspace_overlap", target, "Workspace identities must be distinct")
        if boundary == "verification":
            require(packet["execution"]["state"] in {"RUNNING", "VERIFIED"}, "invalid_state", target, "Only started work can verify")
            if "action_admission_ref" in packet["execution"]:
                _execution_lineage(packet, packet["execution"], context, progress)
            # Without a retained snapshot, stripped stamps are indistinguishable from absent ones.
            require("build_execution_lane" in packet["execution"] or context.get("previous_plan") is not None,
                    "lane_evidence", target, "Dispatched work needs its admission stamps or the retained previous_plan")
            verified_packet(packet, context["packet_evidence"].get(target), snapshot, context, checks)
            rollback.append((packet, deepcopy(packet["execution"])))
            packet["execution"]["state"] = "VERIFIED"
        if boundary == "completion":
            for pid, execution in marked_executions:
                if "action_admission_ref" in execution:
                    lineage = _execution_lineage(packets[pid], execution, context, progress)
                    require(lineage.location in {"checkpoint", "summary"},
                            "progress_mismatch", "context.progress", "Completion needs recorded closure of each admitted execution")
                elif execution["state"] == "VERIFIED":
                    require("action_ref" in execution, "progress_history_missing", pid,
                            "Completed action identity required")
                    checkpoint = next((event for event in progress.history
                                       if event.kind == "work_checkpoint" and event.action_ref == execution["action_ref"]), None)
                    admission_ref = checkpoint.admission_ref if checkpoint is not None else None
                    if checkpoint is None and progress.history_base_ref:
                        summary = PROGRESS.resolved(context["progress"]["resolved_sources"], progress.history_base_ref)
                        closed = next((row for row in summary.get("closed_admissions", [])
                                       if row["action_ref"] == execution["action_ref"]), None)
                        admission_ref = closed["admission_ref"] if closed is not None else None
                    require(admission_ref is not None, "progress_history_missing", pid,
                            "Reconstruct the declared action's historical admission")
                    lineage = _execution_lineage(packets[pid], dict(execution, action_admission_ref=admission_ref), context, progress)
                    require(lineage.location in {"checkpoint", "summary"},
                            "progress_mismatch", "context.progress", "Completion needs recorded closure of each admitted execution")
            require(progress is None or progress.action_admission is None, "progress_mismatch", "context.progress",
                    "Record the completed semantic cycle before final completion")
            completion = object_value(context.get("completion_evidence"), "context.completion_evidence")
            require(completion.get("approved_plan_identity") == snapshot["approved_plan_identity"], "stale_evidence", "completion", "Completion approval identity mismatch")
            current_snapshot = text(context.get("current_snapshot_identity"), "context.current_snapshot_identity")
            require(completion.get("snapshot_identity") == current_snapshot, "snapshot_mismatch", "completion", "Final evidence must bind current integrated snapshot")
            validate_results(snapshot["completion_allocation"], completion, checks, "completion")
            gates = strings(context.get("required_terminal_gates"), "required_terminal_gates")
            require("independent_review" in gates, "terminal_gate", "required_terminal_gates", "Packet plans retain independent review")
            gate_evidence = object_value(completion.get("terminal_gates"), "completion.terminal_gates")
            review = validate_completion_authority("independent_review",
                object_value(gate_evidence.get("independent_review"), "completion.independent_review"),
                snapshot, context, current_snapshot)
            consumed = {review["canonical_review_ref"]: review}
            if plan_review is not None:
                consumed[plan_review["canonical_review_ref"]] = plan_review
            if "qa" in gates:
                qa = validate_completion_authority("qa", object_value(gate_evidence.get("qa"), "completion.qa"),
                                                   snapshot, context, current_snapshot)
                consumed[qa["canonical_review_ref"]] = qa
            # QA and final review differ by role, so their refs differ; this also
            # covers QA versus final review actor/invocation/dispatch reuse.
            require_distinct_review_authorities(consumed, "completion.terminal_gates")
            for gate in gates:
                fact = object_value(gate_evidence.get(gate), "completion." + gate)
                require(fact.get("passed") is True and fact.get("snapshot_identity") == current_snapshot
                        and fact.get("after_integration") is True, "terminal_gate", gate, "Current post-integration review/conditional QA/harness evidence required")
                text(fact.get("evidence_ref"), gate)
        result = {"status": "accepted", "code": "accepted", "path": "", "details": "Admission consistency validated; runtime authority remains caller-owned",
                  "canonical_plan": snapshot}
        if progress is not None:
            result["canonical_progress_state"] = progress.wire()
        if packet is not None and context["build_execution_lane"] != "direct_main":
            projection = deepcopy(packet)
            projection["verification_decision"] = deepcopy(context["verification_decision"])
            projection["evidence_assessment"] = deepcopy(object_value(context.get("evidence_assessment"), "context.evidence_assessment"))
            projection["approved_plan_identity"] = deepcopy(snapshot["approved_plan_identity"])
            if progress is not None:
                projection["progress_state"] = progress.wire()
            phase = request.get("worker_stage", "implementation")
            verifier = boundary == "verification" or (context["build_execution_lane"] == "separated_workers" and phase in {"pre_production_red", "green", "refactor_verification", "final_verification"})
            if verifier:
                projection["verification_stage"] = "pre_production_red" if phase == "pre_production_red" else "final_verification"
                result["verification_stage"] = projection["verification_stage"]
            else:
                projection["worker_stage"] = {"implementation": "production", "pre_production_red": "production",
                                              "green": "production", "refactor_verification": "refactor",
                                              "final_verification": "production"}.get(phase, phase)
                require(projection["worker_stage"] in {"test_authoring", "production", "refactor"}, "worker_stage", target, "Invalid public writer stage")
                require("inline_worker_stage" not in request or request["inline_worker_stage"] == projection["worker_stage"],
                        "projection_mismatch", "inline_worker_stage", "Inline and packet writer stages must agree")
                result["worker_stage"] = projection["worker_stage"]
            if packet["tdd_applies"] and packet["execution"].get("tdd_cycle_log_ref") is not None:
                projection["tdd_cycle_log_ref"] = text(packet["execution"]["tdd_cycle_log_ref"], "execution.tdd_cycle_log_ref")
            if (boundary == "dispatch" and packet["tdd_applies"]
                    and context["build_execution_lane"] == "separated_workers"
                    and request.get("worker_stage", "implementation") in {"production", "refactor"}):
                projection["red_evidence"] = deepcopy(context["packet_evidence"][packet["packet_id"]]["tdd_cycle"]["red"])
            if "current_task_packet" in request:
                require(digest(request["current_task_packet"]) == digest(projection), "projection_mismatch", "current_task_packet", "Projection cannot redefine canonical work or specialist decision")
            result["current_task_packet"] = projection
        final_progress = progress
        prior_execution = deepcopy(packet["execution"]) if boundary == "dispatch" else None
        try:
            if boundary == "dispatch":
                # Projection gates precede unblock consumption and admission writes.
                final_progress = progress_admission(packet, context, progress, snapshot)
                writes = dict(execution_stamps)
                if final_progress is not None:
                    writes["action_admission_ref"] = final_progress.action_admission.admission_ref
                if replaced_stamps or not any(field in packet["execution"] for field in STAMP_CODES):
                    # Writing or replacing a stamp records its evidence baseline.
                    baseline = {"evidence_refs": deepcopy(packet["execution"]["evidence_refs"])}
                    if isinstance(packet["execution"].get("tdd_cycle_log_ref"), str):
                        baseline["tdd_cycle_log_ref"] = deepcopy(packet["execution"]["tdd_cycle_log_ref"])
                    row = {"state": packet["execution"]["state"], "stamp_baseline": baseline,
                           "reason": "dispatch stamp baseline"}
                    if replaced_stamps:
                        row = {"state": packet["execution"]["state"], "replaced_stamps": deepcopy(replaced_stamps),
                               "input_identity": deepcopy(packet["execution"].get("input_identity")),
                               "evidence_refs": deepcopy(packet["execution"]["evidence_refs"]), "stamp_baseline": baseline,
                               "reason": "stamp replaced by a newly admitted dispatch before start or old-actor evidence"}
                    writes["history"] = packet["execution"]["history"] + [row]
                if filled_actor:
                    writes["history"] = packet["execution"]["history"] + [{"state": "RUNNING", "filled_stamps": {"execution_actor_id": execution_stamps["execution_actor_id"]},
                                                                           "reason": "actor resolved for lane-only stamp"}]
                packet["execution"].update(writes)
                if "current_task_packet" in result:
                    result["current_task_packet"]["execution"].update(deepcopy(writes))
                    if final_progress is not None:
                        result["current_task_packet"]["progress_state"] = final_progress.wire()
                if replaced_stamps and "execution_actor_id" not in execution_stamps:
                    # The replacing dispatch resolved no actor; the old actor stamp is history only.
                    packet["execution"].pop("execution_actor_id", None)
                    result.get("current_task_packet", {}).get("execution", {}).pop("execution_actor_id", None)
            preserve_execution_pairs(snapshot, context, final_progress)
        except Exception:
            if prior_execution is not None:
                packet["execution"] = prior_execution
            raise
        progress = final_progress
        if progress is not None:
            result["canonical_progress_state"] = progress.wire()
        result["canonical_context"] = deepcopy(context)
        result["canonical_context"]["previous_plan"] = deepcopy(snapshot)
        if progress is not None:
            result["canonical_context"]["progress"]["state"] = progress.wire()
            if boundary == "dispatch":
                result["canonical_context"]["progress"]["action"] = progress.action_admission.action.wire()
            result["canonical_context"]["progress"].pop("event", None)
        return result
    except AdmissionError as error:
        result = {"status": "blocked", "code": error.code, "path": error.path, "details": error.details}
        for owner, execution in rollback:  # A blocked result never reports VERIFIED.
            owner["execution"] = execution
        if snapshot is not None:
            result["canonical_plan"] = snapshot
        if progress is not None:
            result["canonical_progress_state"] = progress.wire()
        return result
    except PROGRESS.ProgressError as error:
        result = {"status": "blocked", "code": error.code, "path": "context.progress", "details": str(error)}
        for owner, execution in rollback:
            owner["execution"] = execution
        if snapshot is not None:
            result["canonical_plan"] = snapshot
        if progress is not None:
            result["canonical_progress_state"] = progress.wire()
        return result
    except (KeyError, TypeError, ValueError, AttributeError, RecursionError, OverflowError, UnicodeError) as error:
        result = {"status": "blocked", "code": "malformed", "path": "request", "details": "Malformed or unsupported input: " + type(error).__name__}
        if progress is not None:
            result["canonical_progress_state"] = progress.wire()
        return result


def load_json(value):
    def pairs(items):
        result = {}
        for key, item in items:
            if key in result:
                raise ValueError("Duplicate JSON key")
            result[key] = item
        return result
    def finite_float(value):
        result = float(value)
        if not math.isfinite(result):
            raise ValueError("Non-finite JSON")
        return result
    return json.loads(value, object_pairs_hook=pairs, parse_float=finite_float,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError("Non-finite JSON")))


def main():
    try:
        raw = sys.stdin.buffer.read(MAX_BYTES + 1)
        require(len(raw) <= MAX_BYTES, "resource_limit", "stdin", "Admission input exceeds 2 MiB")
        result = admission(load_json(raw.decode("utf-8")))
        encoded = json.dumps(result, sort_keys=True, ensure_ascii=True, allow_nan=False)
    except (AdmissionError, TypeError, ValueError, UnicodeError, RecursionError, OverflowError) as error:
        result = {"status": "blocked", "code": getattr(error, "code", "malformed"), "path": getattr(error, "path", "stdin"),
                  "details": "Invalid JSON admission request"}
        encoded = json.dumps(result, sort_keys=True, ensure_ascii=True, allow_nan=False)
    sys.stdout.write(encoded + "\n")
    return 0 if result["status"] == "accepted" else 1


if __name__ == "__main__":
    sys.exit(main())
