#!/usr/bin/env python3
"""Pure v15 packet admission with authenticated v14/v12/v13 reconciliation.

See references/plan-template.md, Packet admission wire boundary. CLI reads one JSON
request from stdin and writes one result. It cannot attest the caller's runtime facts.
"""

import sys

if sys.version_info < (3, 9):
    raise SystemExit("Python 3.9+ is required for Workflow packet admission. Install a supported interpreter and rerun before continuing.")

from copy import deepcopy
from dataclasses import dataclass
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
                and row["build_execution_lane"] in {"bounded_executor", "separated_workers"}
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

    def assertion_source(self, evidence, actor, pid):
        if self.status == "not_applicable":
            require("tests" not in evidence, "test_applicability", pid,
                    "No-tests resolution requires omitted assertion-source evidence")
            return None
        tests = object_value(evidence.get("tests"), pid + ".tests")
        require(tests.get("mode") in {"authored", "reuse"}, "test_ownership", pid, "Resolve selected assertion source")
        text(tests.get("evidence_ref"), pid + ".tests.evidence_ref")
        if tests["mode"] == "authored":
            require(actor is not None and tests.get("writer_actor_id") == actor,
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
            # Repeated literal arguments are valid; do not apply unique-string validation.
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
    # Retain the immutable old result allocation as provenance, never as a second
    # live state collection or an automatic VERIFIED claim.
    source_results = deepcopy(source.get("slice_verification_summary", []))
    array(source_results, "slice_verification_summary")
    for sid, indexes in groups.items():
        manifest = by_slice[sid]
        for field in ("requirement_ids", "acceptance_criteria", "selected_check_ids", "binding_obligation_refs"):
            if field == "requirement_ids" and field not in manifest:
                continue  # v12 allocates requirements on packets, not the manifest.
            required = manifest.get(field)
            require(isinstance(required, list), "legacy_allocation", sid + "." + field, "Original slice allocation required")
            allocated = [value for index in indexes for value in old_packets[index].get(field, [])]
            allocated += array(object_value(legacy.get("completion_allocation"), "legacy.completion_allocation").get(field), "legacy.completion_allocation." + field)
            require(all(value in allocated for value in required), "legacy_allocation", sid + "." + field,
                    "Slice-wide obligations must be explicitly allocated; never dropped or guessed")
        # These instructions have no task-wide completion field: source packets
        # must already name their owners before the manifest can be retired.
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
            # Historical evidence is retained, but old worker status cannot attest v14 verification.
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


def validate_plan(plan, context, version="15.0"):
    require(plan.get("plan_schema_version") == version, "unsupported_version", "plan_schema_version", "Only canonical v15 is writable; validate original v14 before migration")
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
        object_value(execution.get("input_identity"), pid + ".input_identity")
        for entry in array(execution.get("history"), pid + ".history"):
            object_value(entry, pid + ".history[]")
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
    # Some checks/bindings remain mandatory at integration even if exercised locally.
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
    # Resolve the unchanged canonical phase; producer/resolver adjudicates the
    # oracle without copying its prose into diagnostics.
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
            and context.get("build_execution_lane") in {"bounded_executor", "separated_workers"},
            "lane_evidence", pid, "Evidence must match the selected Build lane")
    text(evidence.get("implementation_evidence_ref"), pid)
    text(evidence.get("native_evidence_ref"), pid)
    if context["build_execution_lane"] == "separated_workers":
        text(evidence.get("builder_evidence_ref"), pid)
        require(evidence["builder_evidence_ref"] != evidence["implementation_evidence_ref"], "lane_evidence", pid, "Independent verification owner required")
    actor = object_value(context.get("writer_actor_ids", {}), "context.writer_actor_ids").get(pid)
    require(actor is not None and evidence.get("writer_actor_id") == actor,
            "writer_lineage", pid, "Verification retains the independently resolved native producer")
    text(actor, "writer_actor_ids." + pid)
    PacketTestApplicability.parse(packet, plan, context).assertion_source(evidence, actor, pid)
    self_check = object_value(evidence.get("self_check"), pid + ".self_check")
    require(self_check.get("result") == "passed", "self_check", pid, "Current self-check must pass")
    text(self_check.get("evidence_ref"), pid)
    validate_results(packet, evidence, checks, pid)
    if packet["tdd_applies"]:
        cycle = actual_red(packet, evidence)
        for phase in ("green", "refactor"):
            entry = object_value(cycle.get(phase), pid + "." + phase)
            require(entry.get("all_tests_pass") is True, "tdd_evidence", pid, "Distinct observed GREEN and REFACTOR passes required")
            require(entry.get("command") == packet["red_command"] and entry.get("cwd") == packet["red_cwd"],
                    "tdd_evidence", pid, "TDD phases must retain the authorizing invocation")
            text(entry.get("invocation_ref"), pid)
        require(cycle["green"]["invocation_ref"] != cycle["refactor"]["invocation_ref"], "tdd_evidence", pid, "REFRACTOR rerun must be distinct")
        text(cycle["green"].get("production_file"), pid)
        text(cycle["refactor"].get("changes_made"), pid)


def worker_stage(request, packet, context, plan):
    """Materialize the same packet through existing bounded/separated role stages."""
    pid = packet["packet_id"]
    lane = context.get("build_execution_lane")
    require(lane in {"bounded_executor", "separated_workers"}, "lane_evidence", pid, "Resolve selected Build lane")
    applicability = PacketTestApplicability.parse(packet, plan, context)
    stage = request.get("worker_stage", "implementation")
    tdd = packet["tdd_applies"]
    require(stage not in {"test_authoring", "pre_production_red"} or applicability.status == "required",
            "test_applicability", pid, "Test authoring/RED requires applicable tests")
    allowed = {"test_authoring", "pre_production_red", "production", "green", "refactor", "refactor_verification"} if tdd else {"test_authoring", "implementation", "production", "final_verification"}
    require(stage in allowed, "worker_stage", pid, "Select a concrete existing role/protocol stage")
    role = "builder_tester" if lane == "separated_workers" and stage in {"pre_production_red", "green", "refactor_verification", "final_verification"} else "code_writer"
    require(request.get("worker_role", role) == role, "worker_stage", pid, "Stage must retain selected-lane role ownership")
    # Actor IDs are native identities resolved by the caller, never configured role names.
    actors = object_value(context.get("writer_actor_ids", {}), "context.writer_actor_ids")
    actor = actors.get(pid)
    if actor is not None:
        text(actor, "writer_actor_ids." + pid)
    evidence = context.get("packet_evidence", {}).get(pid)
    if evidence is not None:
        object_value(evidence, pid + ".evidence")
        if applicability.status == "not_applicable":
            applicability.assertion_source(evidence, actor, pid)
    # Only current-cycle evidence authorizes stages; closed cycles cannot restart.
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
    if stage in {"test_authoring", "implementation"} or (stage == "production" and packet["execution"]["state"] == "PENDING" and (not tdd or lane == "bounded_executor")):
        # Record the actual new actor; no forced bootstrap or fabricated identity.
        if evidence is not None and evidence.get("writer_actor_id") is not None:
            require(actor is not None and evidence["writer_actor_id"] == actor,
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
            require(actor is not None and tests.get("writer_actor_id") == actor == source.get("writer_actor_id"),
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
    tests = applicability.assertion_source(evidence, actor, pid)
    first_unobserved_production = (stage == "production" and (tests is None or tests["mode"] == "reuse")
                                  and evidence.get("writer_actor_id") is None)
    require(first_unobserved_production or (actor is not None and evidence.get("writer_actor_id") == actor),
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
            if "progress_guard_ref" in old:
                require("progress_guard_ref" in execution and execution["progress_guard_ref"] == old["progress_guard_ref"],
                        "progress_mismatch", pid, "Retain the independently recorded task guard across canonical snapshots")
            require(old["state"] != "VERIFIED" or execution["state"] == "VERIFIED",
                    "invalid_state", pid, "Caller cannot downgrade retained VERIFIED work; only helper reconciliation invalidates it")
            # The current recovery owner above attests measurable-progress resets
            # of no_progress_count; cumulative spent attempts never reset.
            require(("recovery" not in old or ("recovery" in execution and execution["recovery"]["attempt_count"] >= old["recovery"]["attempt_count"]))
                    and digest(execution["history"][:len(old["history"])]) == digest(old["history"])
                    and set(old["evidence_refs"]) <= set(execution["evidence_refs"]), "recovery_mismatch", pid, "Resume cannot reset spent attempts or discard history/evidence")
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


def normalize_v14(source, context):
    """Validate original approval before the fixed representation-only migration.

    The independently resolved original approval digest is the attestation. No
    candidate migration flag can approve changed scope. Return the remapped
    authority context for the caller to retain with the canonical snapshot.
    """
    validate_plan(source, context, "14.0")
    original_identity = deepcopy(source["approved_plan_identity"])
    plan, current = deepcopy(source), deepcopy(context)
    plan["plan_schema_version"] = "15.0"
    normalized_identity = {**original_identity, "definition_digest": digest(definition(plan))}
    plan["approved_plan_identity"] = deepcopy(normalized_identity)
    provenance = plan.setdefault("reconciliation_provenance", {})
    provenance["workflow_migration"] = {
        "producer_schema_version": "14.0", "consumer_schema_version": "15.0",
        "source_sha256": digest(source), "original_approved_plan_identity": original_identity,
        "normalized_definition_digest": normalized_identity["definition_digest"],
        "mapping_ref": "task-packet-admission.py#normalize_v14",
        "packet_mapping": [{"source_packet_id": p["packet_id"], "packet_id": p["packet_id"],
                            "packet_definition_digest": digest(packet_definition(p))} for p in source["implementation_steps"]]}
    # Migrate identities only; preserve commands, bindings, actors, inputs, stages and results.
    for rows in (current.get("packet_evidence", {}), current.get("test_applicability", {})):
        for row in rows.values():
            if row.get("approved_plan_identity") == original_identity:
                row["approved_plan_identity"] = deepcopy(normalized_identity)
    if isinstance(current.get("completion_evidence"), dict) and current["completion_evidence"].get("approved_plan_identity") == original_identity:
        current["completion_evidence"]["approved_plan_identity"] = deepcopy(normalized_identity)
    if isinstance(current.get("previous_plan"), dict):
        prior = current["previous_plan"]
        require(prior.get("approved_plan_identity") == original_identity, "resume_identity", "previous_plan", "Original migration snapshot must bind original approval")
        require(digest(definition(prior)) == original_identity["definition_digest"], "resume_identity", "previous_plan", "Original retained definition changed")
        prior["plan_schema_version"] = "15.0"
        prior["approved_plan_identity"] = deepcopy(normalized_identity)
        prior["reconciliation_provenance"] = deepcopy(provenance)
    current["approved_plan_identity"] = deepcopy(normalized_identity)
    return plan, current


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


def progress_admission(packet, context, state, plan):
    execution = packet["execution"]
    if state is None:
        require(not execution.get("recovery", {}).get("attempt_count", 0)
                and not execution.get("progress_guard_ref"), "progress_history_missing", packet["packet_id"],
                "Repeated work requires retained progress observations; old totals do not prove a stall or fresh window")
        return None  # Single-pass work needs no new progress envelope.
    carrier = context["progress"]
    action = PROGRESS.ActionIdentity.parse(carrier.get("action"))
    pid = packet["packet_id"]
    scope = action.member_scope
    retained = state.action_admission
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
            continue
        require(progress is not None, "progress_history_missing", pid, "Changed pairs need retained progress proof")
        require(execution.get("progress_guard_ref") == progress.guard.guard_id,
                "progress_mismatch", pid, "Pair transitions retain the same progress guard")
        sources = context["progress"]["resolved_sources"]
        before, after = [progress.action_lineage(PROGRESS.ActionIdentity.parse({"action_ref": row.get("action_ref"),
                            "packet_id": pid, "input_identity": row["input_identity"]}), row["action_admission_ref"], sources)
                         for row in (old, execution)]
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


def admission(request):
    """Calculate an admission result without mutating the request or external state."""
    snapshot, progress = None, None
    try:
        object_value(request, "request")
        boundary = request.get("boundary")
        require(boundary in BOUNDARIES, "unsupported_boundary", "boundary", "Unknown admission operation")
        context = object_value(request.get("context"), "context")
        # Retain completed progress before any subsequent admission gate.
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
        if "plan_schema_version" not in source and ("schema_version" in source or "legacy" in context):
            snapshot = normalize_legacy(source, context)
        else:
            require("schema_version" not in source, "mixed_schema", "plan", "Explicit verified legacy admission required")
            authenticate_provenance(source, context)
            snapshot = deepcopy(source)
        if snapshot.get("plan_schema_version") == "14.0":
            snapshot, context = normalize_v14(snapshot, context)
        checks, _ = validate_plan(snapshot, context)
        if boundary == "resume":
            require(context.get("previous_plan") is not None, "resume_identity", "context.previous_plan", "Resume needs independently retained last snapshot")
        invalid = reconcile_execution(snapshot, context, checks)
        packets = {packet["packet_id"]: packet for packet in snapshot["implementation_steps"]}
        target = request.get("target_packet_id")
        packet = None
        if boundary in {"dispatch", "verification"}:
            require(target in packets, "unknown_packet", "target_packet_id", "Resolve exactly one canonical packet")
            packet = packets[target]
            require(not any(packets[dep]["execution"]["state"] != "VERIFIED" for dep in packet["depends_on"]),
                    "prerequisite_unverified", target, "Every prerequisite must be evidence-bound VERIFIED")
            require(target not in invalid, "invalidated", target, "Reconcile invalidated inputs and evidence before dispatch or verification")
        if boundary == "dispatch":
            require(packet["execution"]["state"] == "PENDING" or (packet["execution"]["state"] == "RUNNING" and "worker_stage" in request),
                    "invalid_state", target, "Materialize PENDING work or an explicit stage of the same RUNNING packet")
            worker_stage(request, packet, context, snapshot)
            source_writer = bool(packet["files_to_create"] or packet["files_to_modify"])
            workspace = object_value(context.get("workspace"), "context.workspace")
            active_ids = set(strings(workspace.get("active_source_writer_ids"), "workspace.active_source_writer_ids"))
            require(active_ids <= packets.keys(), "workspace_overlap", target,
                    "Resolve current source-writer activity independently")
            require(target not in active_ids, "workspace_overlap", target,
                    "The prior source Writer must be terminal before another same-packet role dispatch")
            # Candidate state may add a conservative barrier, never remove a
            # separately observed active/unfinished source writer.
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
            verified_packet(packet, context["packet_evidence"].get(target), snapshot, context, checks)
            packet["execution"]["state"] = "VERIFIED"
        if boundary == "completion":
            require(all(p["execution"]["state"] == "VERIFIED" for p in packets.values()), "incomplete_packets", "implementation_steps", "Every canonical packet must be VERIFIED")
            marked_executions = [(p["packet_id"], p["execution"])
                                 for retained_plan in (snapshot, context.get("previous_plan") or {})
                                 for p in retained_plan.get("implementation_steps", [])
                                 if any(field in p["execution"] for field in
                                        ("progress_guard_ref", "action_ref", "action_admission_ref"))]
            require(not marked_executions or progress is not None, "progress_history_missing", "context.progress",
                    "Completion must retain progress bound by current or previous packet executions")
            for pid, execution in marked_executions:
                require(execution.get("progress_guard_ref") == progress.guard.guard_id,
                        "progress_mismatch", "context.progress", "Completed packet executions must retain the same task guard")
                if "action_admission_ref" in execution:
                    action = PROGRESS.ActionIdentity.parse({"action_ref": execution.get("action_ref"),
                        "packet_id": pid, "input_identity": execution["input_identity"]})
                    lineage = progress.action_lineage(action, execution["action_admission_ref"], context["progress"]["resolved_sources"])
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
            for gate in gates:
                fact = object_value(gate_evidence.get(gate), "completion." + gate)
                require(fact.get("passed") is True and fact.get("snapshot_identity") == current_snapshot
                        and fact.get("after_integration") is True, "terminal_gate", gate, "Current post-integration review/conditional QA/harness evidence required")
                text(fact.get("evidence_ref"), gate)
        result = {"status": "accepted", "code": "accepted", "path": "", "details": "Admission consistency validated; runtime authority remains caller-owned",
                  "canonical_plan": snapshot}
        if progress is not None:
            result["canonical_progress_state"] = progress.wire()
        if packet is not None:
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
        if boundary == "dispatch":
            # Projection/inline checks are gates too. No rejected call consumes
            # a bound unblock or writes an admission into its canonical packet.
            final_progress = progress_admission(packet, context, progress, snapshot)
            if final_progress is not None:
                admission_ref = final_progress.action_admission.admission_ref
                packet["execution"]["action_admission_ref"] = admission_ref
                result["current_task_packet"]["execution"]["action_admission_ref"] = admission_ref
                result["current_task_packet"]["progress_state"] = final_progress.wire()
        try:
            preserve_execution_pairs(snapshot, context, final_progress)
        except Exception:
            if prior_execution is not None:
                packet["execution"] = prior_execution
            raise
        progress = final_progress
        if progress is not None:
            result["canonical_progress_state"] = progress.wire()
        result["canonical_context"] = deepcopy(context)
        # Promote this snapshot; an older one could hide terminal downgrades.
        result["canonical_context"]["previous_plan"] = deepcopy(snapshot)
        if progress is not None:
            result["canonical_context"]["progress"]["state"] = progress.wire()
            result["canonical_context"]["progress"].pop("event", None)
        return result
    except AdmissionError as error:
        result = {"status": "blocked", "code": error.code, "path": error.path, "details": error.details}
        if snapshot is not None:
            result["canonical_plan"] = snapshot
        if progress is not None:
            result["canonical_progress_state"] = progress.wire()
        return result
    except PROGRESS.ProgressError as error:
        result = {"status": "blocked", "code": error.code, "path": "context.progress", "details": str(error)}
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
