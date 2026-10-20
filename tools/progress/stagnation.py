"""Pure shared stagnation transitions. Callers own evidence truth and persistence.

JSON dictionaries are converted at this boundary into frozen semantic values.
No dispatch, storage, clock, CLI or external dependency is involved.
"""

from dataclasses import dataclass, replace
import json
from typing import Mapping, Optional, Tuple


class ProgressError(ValueError):
    def __init__(self, code, detail):
        super().__init__(detail)
        self.code = code


def require(condition, detail, code="progress_mismatch"):
    if not condition:
        raise ProgressError(code, detail)


def text(value):
    require(isinstance(value, str) and bool(value.strip()), "Expected a stable nonblank reference")
    return value


def integer(value):
    require(type(value) is int and value >= 0, "Expected nonnegative integer, never boolean")
    return value


def refs(value):
    require(isinstance(value, list), "Expected reference array")
    result = tuple(text(item) for item in value)
    require(len(set(result)) == len(result), "Duplicate evidence reference")
    return result


def resolved(sources, ref):
    value = sources.get(text(ref))
    require(isinstance(value, dict), "Unresolved progress source: " + ref, "progress_history_missing")
    return value


@dataclass(frozen=True)
class GuardIdentity:
    guard_id: str
    outcome_ref: str


@dataclass(frozen=True)
class ProgressPolicy:
    policy_id: str
    stagnation_window: int
    source_ref: str

    @classmethod
    def from_wire(cls, value):
        require(isinstance(value, dict), "Missing progress policy")
        result = cls(text(value.get("policy_id")), integer(value.get("stagnation_window")), text(value.get("source_ref")))
        require(result.stagnation_window > 0, "The policy window must be positive")
        return result

    @classmethod
    def parse(cls, value, sources):
        result = cls.from_wire(value)
        source = resolved(sources, result.source_ref)
        require(source.get("policy_id") == result.policy_id and type(source.get("stagnation_window")) is int
                and source["stagnation_window"] == result.stagnation_window, "Policy differs from independent authority")
        text(source.get("authority_ref"))
        return result

    def wire(self):
        return dict(policy_id=self.policy_id, stagnation_window=self.stagnation_window, source_ref=self.source_ref)


@dataclass(frozen=True)
class RelevantInputIdentity:
    canonical_json: str

    @classmethod
    def parse(cls, value):
        require(isinstance(value, dict) and bool(value), "Current input identity object required")
        return cls(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False))

    def wire(self):
        return json.loads(self.canonical_json)


@dataclass(frozen=True)
class ActionMemberBinding:
    packet_id: str
    packet_definition_digest: str
    input_identity: RelevantInputIdentity

    @classmethod
    def parse(cls, value):
        require(isinstance(value, dict), "Expected coordinator member binding")
        return cls(text(value.get("packet_id")), text(value.get("packet_definition_digest")),
                   RelevantInputIdentity.parse(value.get("input_identity")))

    def wire(self):
        return dict(packet_id=self.packet_id, packet_definition_digest=self.packet_definition_digest,
                    input_identity=self.input_identity.wire())


@dataclass(frozen=True)
class CoordinatorMemberScope:
    source_ref: str
    members: Tuple[ActionMemberBinding, ...]

    @classmethod
    def parse(cls, value):
        require(isinstance(value, dict) and isinstance(value.get("members"), list), "Expected coordinator scope")
        members = tuple(ActionMemberBinding.parse(row) for row in value["members"])
        require(bool(members) and len({row.packet_id for row in members}) == len(members),
                "Coordinator membership must be nonempty and unique")
        return cls(text(value.get("source_ref")), members)

    def wire(self):
        return dict(source_ref=self.source_ref, members=[row.wire() for row in self.members])

    def authority(self, sources, guard, action_ref):
        source = resolved(sources, self.source_ref)
        require(source.get("kind") == "coordinator_action_scope" and source.get("guard_id") == guard.guard_id
                and source.get("outcome_ref") == guard.outcome_ref and source.get("action_ref") == action_ref
                and CoordinatorMemberScope.parse(dict(source_ref=self.source_ref, members=source.get("members"))) == self,
                "Coordinator membership differs from independent grouping authority")
        approval = source.get("approved_plan_identity")
        require(isinstance(approval, dict) and bool(approval), "Grouping needs approved Plan identity")
        decision = resolved(sources, source.get("grouping_decision_ref"))
        require(decision.get("approved_plan_identity") == approval, "Grouping decision changed approved Plan")
        text(decision.get("reason"))
        return source


@dataclass(frozen=True)
class ActionIdentity:
    action_ref: str
    packet_id: str
    input_identity: RelevantInputIdentity
    member_scope: Optional[CoordinatorMemberScope] = None

    @classmethod
    def parse(cls, value):
        require(isinstance(value, dict), "Action must bind current input identity")
        result = cls(text(value.get("action_ref")), text(value.get("packet_id")),
                     RelevantInputIdentity.parse(value.get("input_identity")),
                     CoordinatorMemberScope.parse(value["member_scope"]) if "member_scope" in value else None)
        if result.member_scope:
            anchor = next((row for row in result.member_scope.members if row.packet_id == result.packet_id), None)
            require(anchor is not None and anchor.input_identity == result.input_identity,
                    "Coordinator anchor must occur once with the same input")
        return result

    def wire(self):
        result = dict(action_ref=self.action_ref, packet_id=self.packet_id, input_identity=self.input_identity.wire())
        if self.member_scope:
            result["member_scope"] = self.member_scope.wire()
        return result


@dataclass(frozen=True)
class ActionAdmission:
    admission_ref: str
    guard_id: str
    action: ActionIdentity
    unblock_event_id: Optional[str] = None

    @classmethod
    def parse(cls, value):
        if value is None:
            return None
        require(isinstance(value, dict), "Malformed action admission")
        unblock = value.get("unblock_event_id")
        return cls(text(value.get("admission_ref")), text(value.get("guard_id")), ActionIdentity.parse(value),
                   text(unblock) if unblock is not None else None)

    def wire(self):
        result = dict(admission_ref=self.admission_ref, guard_id=self.guard_id, **self.action.wire())
        if self.unblock_event_id is not None:
            result["unblock_event_id"] = self.unblock_event_id
        return result


@dataclass(frozen=True)
class ProgressEvent:
    """An immutable JSON event; nested wire values are copied on both boundaries."""
    kind: str
    event_id: str
    guard: GuardIdentity
    predecessor_event_id: Optional[str]
    work_ordinal: int
    action_ref: str
    assessment_ref: str
    evidence_refs: Tuple[str, ...]
    disposition: Optional[str]
    frontier_ref: Optional[str]
    resolved_blocker_ref: Optional[str] = None
    changed_ref: Optional[str] = None
    admission_ref: Optional[str] = None
    previous_policy: Optional[ProgressPolicy] = None
    new_policy: Optional[ProgressPolicy] = None
    authority_ref: Optional[str] = None
    coordinator_barrier_ref: Optional[str] = None
    action_scope_ref: Optional[str] = None

    @classmethod
    def parse(cls, value):
        require(isinstance(value, dict), "Missing progress event")
        require(value.get("kind") in {"work_checkpoint", "material_unblock", "policy_change"}, "Unknown progress event kind")
        kind = value["kind"]
        previous = value.get("predecessor_event_id")
        evidence = refs(value.get("evidence_refs"))
        require(bool(evidence), "Completed work or material unblock needs observed evidence")
        disposition = value.get("disposition")
        if kind == "work_checkpoint":
            require(disposition in {"verified_gain", "useful_new_evidence", "no_progress"}, "Unknown progress disposition")
        return cls(kind, text(value.get("event_id")),
                   GuardIdentity(text(value.get("guard_id")), text(value.get("outcome_ref"))),
                   text(previous) if previous is not None else None, integer(value.get("work_ordinal")),
                   text(value.get("action_ref")), text(value.get("assessment_ref")), evidence, disposition,
                   text(value.get("frontier_ref")) if kind == "work_checkpoint" else None,
                   text(value.get("resolved_blocker_ref")) if kind == "material_unblock" else None,
                   text(value.get("changed_ref")) if kind == "material_unblock" else None,
                   text(value["admission_ref"]) if "admission_ref" in value else None,
                   ProgressPolicy.from_wire(value.get("previous_policy")) if kind == "policy_change" else None,
                   ProgressPolicy.from_wire(value.get("new_policy")) if kind == "policy_change" else None,
                   text(value.get("authority_ref")) if kind == "policy_change" else None,
                   text(value["coordinator_barrier_ref"]) if "coordinator_barrier_ref" in value else None,
                   text(value["action_scope_ref"]) if "action_scope_ref" in value else None)

    def wire(self):
        result = dict(kind=self.kind, event_id=self.event_id, guard_id=self.guard.guard_id,
                      outcome_ref=self.guard.outcome_ref, predecessor_event_id=self.predecessor_event_id,
                      work_ordinal=self.work_ordinal, action_ref=self.action_ref, assessment_ref=self.assessment_ref,
                      evidence_refs=list(self.evidence_refs))
        if self.kind == "work_checkpoint":
            result.update(disposition=self.disposition, frontier_ref=self.frontier_ref)
        elif self.kind == "material_unblock":
            result.update(resolved_blocker_ref=self.resolved_blocker_ref, changed_ref=self.changed_ref)
        else:
            result.update(previous_policy=self.previous_policy.wire(), new_policy=self.new_policy.wire(),
                          authority_ref=self.authority_ref)
        if self.admission_ref is not None:
            result["admission_ref"] = self.admission_ref
        if self.coordinator_barrier_ref is not None:
            require(self.kind == "work_checkpoint", "Only work checkpoints carry coordinator barriers")
            result["coordinator_barrier_ref"] = self.coordinator_barrier_ref
        if self.action_scope_ref is not None:
            require(self.kind == "material_unblock", "Only material unblocks carry action scope")
            result["action_scope_ref"] = self.action_scope_ref
        return result


@dataclass(frozen=True)
class ActionLineage:
    location: str
    work_ordinal: Optional[int] = None


@dataclass(frozen=True)
class ProgressState:
    guard: GuardIdentity
    policy: ProgressPolicy
    work_ordinal: int
    consecutive_no_progress: int
    status: str
    baseline_ref: str
    frontier_ref: str
    history: Tuple[ProgressEvent, ...]
    evidence_refs: Tuple[str, ...]
    action_admission: Optional[ActionAdmission] = None
    history_base_ref: Optional[str] = None

    @classmethod
    def parse(cls, value, sources):
        require(isinstance(value, dict) and value.get("schema_version") == "1.0", "Supported ProgressState v1 required")
        require(isinstance(value.get("history"), list), "Retained progress history required", "progress_history_missing")
        state = cls(GuardIdentity(text(value.get("guard_id")), text(value.get("outcome_ref"))),
                    ProgressPolicy.parse(value.get("policy"), sources), integer(value.get("work_ordinal")),
                    integer(value.get("consecutive_no_progress")), value.get("status"), text(value.get("baseline_ref")),
                    text(value.get("frontier_ref")), tuple(ProgressEvent.parse(row) for row in value["history"]),
                    refs(value.get("evidence_refs")), ActionAdmission.parse(value.get("action_admission")),
                    text(value["history_base_ref"]) if "history_base_ref" in value else None)
        require(state.status in {"active", "stagnant", "reactivated"}, "Unknown progress status")
        resolved(sources, state.guard.outcome_ref)
        resolved(sources, state.baseline_ref)
        ordinal, count, frontier, previous = 0, 0, state.baseline_ref, None
        seen, observations, frontiers = set(), set(), {frontier}
        completed_actions = set()
        resolved_uncertainties = set()
        last_kind = None
        effective_policy = next((event.previous_policy for event in state.history if event.kind == "policy_change"), state.policy)
        ProgressPolicy.parse(effective_policy.wire(), sources)
        policy_authorities = set()
        if state.history_base_ref is not None:
            # Compaction resolves a retained summary, never an empty new window.
            # Historical novelty and unresolved oscillation identities survive.
            base = resolved(sources, state.history_base_ref)
            require(base.get("guard_id") == state.guard.guard_id and base.get("outcome_ref") == state.guard.outcome_ref,
                    "Compaction changed outcome/guard")
            effective_policy = ProgressPolicy.parse(base.get("policy"), sources)
            policy_authorities = set(refs(base.get("seen_policy_authority_refs")))
            last_kind = base.get("last_semantic_kind")
            ordinal, count = integer(base.get("work_ordinal")), integer(base.get("consecutive_no_progress"))
            require(count <= ordinal, "Compacted consecutive count exceeds completed cycles")
            frontier, previous = text(base.get("frontier_ref")), text(base.get("last_event_id"))
            resolved(sources, frontier)
            seen = set(refs(base.get("seen_event_ids")))
            require(previous in seen, "Compaction lost the predecessor identity")
            observations = set(refs(base.get("seen_observation_refs")))
            frontiers = set(refs(base.get("seen_frontier_refs"))) | {frontier}
            refs(base.get("unresolved_oscillation_refs"))
            refs(base.get("seen_unblock_change_refs"))
            completed_actions = set(refs(base.get("seen_action_refs")))
            if "seen_resolved_uncertainty_refs" in base:
                resolved_uncertainties = set(refs(base["seen_resolved_uncertainty_refs"]))
            require(state.history_base_ref in state.evidence_refs, "Compacted evidence reference was discarded")
        for event in state.history:
            require(event.guard == state.guard and event.event_id not in seen
                    and event.predecessor_event_id == previous, "Replayed, reordered or different-outcome progress event")
            if event.kind == "work_checkpoint":
                require(event.action_ref not in completed_actions, "Completed action repeated in retained history", "progress_replay")
            if event.kind == "material_unblock":
                summarized_changes = set(base.get("seen_unblock_change_refs", [])) if state.history_base_ref else set()
                require(event.changed_ref not in {prior.changed_ref for prior in state.history if prior.event_id in seen} | summarized_changes,
                        "A reused circumstance is not another material unblock", "progress_replay")
            if event.kind == "policy_change":
                require(event.authority_ref not in policy_authorities, "Replayed user policy authority", "progress_replay")
                effective_policy = changed_policy(event, sources, effective_policy, ordinal, observations)
                policy_authorities.add(event.authority_ref)
            else:
                ordinal, count, frontier = assess(event, sources, ordinal, count, frontier, observations, frontiers,
                                                   effective_policy.stagnation_window)
                last_kind = event.kind
            if event.kind == "work_checkpoint":
                completed_actions.add(event.action_ref)
                if event.disposition == "useful_new_evidence":
                    uncertainty = text(resolved(sources, event.assessment_ref).get("resolved_uncertainty_ref"))
                    require(uncertainty not in resolved_uncertainties,
                            "The same uncertainty resolution is not new useful evidence", "progress_replay")
                    resolved_uncertainties.add(uncertainty)
            seen.add(event.event_id)
            observations.update(event.evidence_refs)
            if event.frontier_ref is not None:
                frontiers.add(event.frontier_ref)
            require(set(event.evidence_refs) | {event.assessment_ref} <= set(state.evidence_refs),
                    "Retained evidence was discarded")
            previous = event.event_id
        require(effective_policy == state.policy, "Current policy does not derive from retained authorized policy history")
        require((ordinal, count, frontier) == (state.work_ordinal, state.consecutive_no_progress, state.frontier_ref),
                "Candidate count/frontier does not derive from retained assessed history")
        expected = "reactivated" if last_kind == "material_unblock" else ("stagnant" if count >= state.policy.stagnation_window else "active")
        require(state.status == expected, "Candidate status does not derive from retained history")
        if state.action_admission:
            require(state.action_admission.guard_id == state.guard.guard_id, "Different guard admission")
            scope = state.action_admission.action.member_scope
            if scope:
                scope.authority(sources, state.guard, state.action_admission.action.action_ref)
            closed = {row.action_ref for row in state.history if row.kind == "work_checkpoint"}
            if state.history_base_ref:
                closed |= set(base.get("seen_action_refs", []))
            require(state.action_admission.action.action_ref not in closed, "Closed admission cannot be restored", "progress_replay")
            if state.action_admission.unblock_event_id is not None:
                require(any(e.event_id == state.action_admission.unblock_event_id and e.kind == "material_unblock"
                            and e.action_ref == state.action_admission.action.action_ref
                            and e.action_scope_ref == (scope.source_ref if scope else None) for e in state.history),
                        "Admission names an unknown unblock")
        return state

    def action_lineage(self, action: ActionIdentity, admission_ref: str, sources) -> ActionLineage:
        """Locate an execution pair without inventing order within a summary."""
        text(admission_ref)
        admission = self.action_admission
        if admission and admission.admission_ref == admission_ref and admission.action.action_ref == action.action_ref:
            scope = admission.action.member_scope
            bound = (next((member for member in scope.members if member.packet_id == action.packet_id), None)
                     if scope else admission.action if admission.action.packet_id == action.packet_id else None)
            if bound is not None and bound.input_identity == action.input_identity:
                return ActionLineage("admitted")
        for event in self.history:
            if event.kind == "work_checkpoint" and event.action_ref == action.action_ref:
                return (ActionLineage("checkpoint", event.work_ordinal) if event.admission_ref == admission_ref
                        else ActionLineage("missing"))
        if self.history_base_ref and action.action_ref in resolved(sources, self.history_base_ref)["seen_action_refs"]:
            return ActionLineage("summary")
        return ActionLineage("missing")

    def wire(self):
        result = dict(schema_version="1.0", guard_id=self.guard.guard_id, outcome_ref=self.guard.outcome_ref,
                      policy=self.policy.wire(), work_ordinal=self.work_ordinal,
                      consecutive_no_progress=self.consecutive_no_progress, status=self.status,
                      baseline_ref=self.baseline_ref, frontier_ref=self.frontier_ref,
                      history=[row.wire() for row in self.history], evidence_refs=list(self.evidence_refs))
        if self.action_admission:
            result["action_admission"] = self.action_admission.wire()
        if self.history_base_ref is not None:
            result["history_base_ref"] = self.history_base_ref
        return result



def changed_policy(event, sources, previous, ordinal, observations):
    """Apply explicit independent user authority prospectively, never as progress."""
    require(event.work_ordinal == ordinal and event.previous_policy == previous,
            "Policy change must retain ordinal and effective previous policy")
    current = ProgressPolicy.parse(event.new_policy.wire(), sources)
    require(current != previous, "Policy change must change an actual policy")
    authority = resolved(sources, event.authority_ref)
    assessment = resolved(sources, event.assessment_ref)
    require(authority.get("kind") == "user_policy_change" and authority.get("authorized") is True
            and authority.get("guard_id") == event.guard.guard_id and authority.get("outcome_ref") == event.guard.outcome_ref
            and authority.get("previous_policy") == previous.wire() and authority.get("new_policy") == current.wire(),
            "Policy change lacks independently bound explicit user authority")
    require(resolved(sources, current.source_ref).get("authority_ref") == event.authority_ref,
            "New policy authority differs from recorded user change")
    require(assessment.get("kind") == "policy_change" and assessment.get("event_id") == event.event_id
            and assessment.get("authority_ref") == event.authority_ref
            and assessment.get("observation_refs") == list(event.evidence_refs)
            and assessment.get("previous_policy") == previous.wire() and assessment.get("new_policy") == current.wire(),
            "Policy assessment differs from observed user instruction")
    require(not set(event.evidence_refs) & observations, "Replayed policy observation", "progress_replay")
    for ref in event.evidence_refs:
        require(resolved(sources, ref).get("authority_ref") == event.authority_ref, "Unbound policy observation")
    return current


def assess(event, sources, ordinal, count, frontier, observations, frontiers, window):
    """Check independently resolved assessment binding; never infer semantic truth."""
    assessment = resolved(sources, event.assessment_ref)
    require(assessment.get("event_id") == event.event_id
            and assessment.get("observation_refs") == list(event.evidence_refs), "Assessment/observation binding changed")
    facts = [resolved(sources, ref) for ref in event.evidence_refs]
    if event.kind == "material_unblock":
        require(event.work_ordinal == ordinal and count >= window, "Unblock must retain an actual stalled count/ordinal")
        changed = resolved(sources, event.changed_ref)
        require(assessment.get("kind") == "material_unblock" and assessment.get("action_ref") == event.action_ref
                and assessment.get("changed_ref") == event.changed_ref
                and assessment.get("resolved_blocker_ref") == event.resolved_blocker_ref,
                "Unblock is not independently bound to changed circumstances and exact action")
        require(changed.get("change_kind") in {"information", "authority", "capability"}
                and changed.get("material") is True and changed.get("action_ref") == event.action_ref,
                "Generic continuation or unsupported materiality cannot reopen work")
        if event.action_scope_ref is not None:
            require(assessment.get("action_scope_ref") == event.action_scope_ref
                    and changed.get("action_scope_ref") == event.action_scope_ref, "Unblock changed coordinator scope")
            source = resolved(sources, event.action_scope_ref)
            CoordinatorMemberScope.parse(dict(source_ref=event.action_scope_ref, members=source.get("members"))).authority(
                sources, event.guard, event.action_ref)
        else:
            require("action_scope_ref" not in assessment and "action_scope_ref" not in changed,
                    "Unblock discarded its bound coordinator scope")
        resolved(sources, event.resolved_blocker_ref)
        require(not set(event.evidence_refs) & observations, "Replayed material-unblock evidence")
        return ordinal, count, frontier
    if event.coordinator_barrier_ref is not None:
        coordinator_barrier(event, sources)
    require(event.work_ordinal == ordinal + 1, "Completed cycle ordinal must advance exactly once")
    require(assessment.get("disposition") == event.disposition and assessment.get("frontier_ref") == event.frontier_ref,
            "Candidate disposition/frontier differs from independent assessment")
    after = resolved(sources, event.frontier_ref)
    before = resolved(sources, frontier)
    productive = event.disposition != "no_progress"
    if productive:
        require(not set(event.evidence_refs) & observations, "Repeated evidence is not novel progress")
    if event.disposition == "verified_gain":
        old = set(refs(before.get("accepted_obligations")))
        new = set(refs(after.get("accepted_obligations")))
        previously_accepted = set().union(*(set(refs(resolved(sources, ref).get("accepted_obligations")))
                                            for ref in frontiers))
        require(old < new and bool(new - previously_accepted) and event.frontier_ref not in frontiers,
                "Oscillation, renamed recurring acceptance or lost acceptance is not a durable gain")
        verified = [set(refs(fact.get("newly_verified_obligations", []))) for fact in facts if fact.get("result") == "passed"]
        require(any(obligations & (new - old) for obligations in verified),
                "Verified gain needs independent acceptance observations")
    elif event.disposition == "useful_new_evidence":
        require(assessment.get("changes_next_action") is True and bool(assessment.get("resolved_uncertainty_ref")),
                "Unsupported novelty is not useful evidence")
        resolved(sources, assessment["resolved_uncertainty_ref"])
    return ordinal + 1, 0 if productive else count + 1, event.frontier_ref


def coordinator_barrier(event, sources, scope=None):
    """Bind one lead event to domain-owned terminal cycle evidence, not packet verification."""
    barrier = resolved(sources, event.coordinator_barrier_ref)
    require(barrier.get("kind") == "coordinator_barrier" and barrier.get("guard_id") == event.guard.guard_id
            and barrier.get("outcome_ref") == event.guard.outcome_ref and barrier.get("action_ref") == event.action_ref
            and barrier.get("admission_ref") == event.admission_ref, "Coordinator barrier changed action/admission")
    source_ref = text(barrier.get("action_scope_ref"))
    source = resolved(sources, source_ref)
    bound = CoordinatorMemberScope.parse(dict(source_ref=source_ref, members=source.get("members")))
    bound.authority(sources, event.guard, event.action_ref)
    require(scope is None or bound == scope, "Barrier changed admitted membership")
    results = barrier.get("member_results")
    require(isinstance(results, list) and len(results) == len(bound.members), "Unfinished coordinator members cannot close a cycle")
    observed = set()
    for row in results:
        require(isinstance(row, dict) and row.get("packet_id") not in observed
                and row.get("packet_id") in {member.packet_id for member in bound.members}, "Duplicate or undeclared barrier member")
        observed.add(row["packet_id"])
        require(row.get("result") in {"passed", "failed", "blocked", "cancelled"}, "Member cycle is not terminal")
        evidence = refs(row.get("evidence_refs"))
        require(bool(evidence), "Terminal member needs independently retained evidence")
        for ref in evidence:
            fact = resolved(sources, ref)
            require(fact.get("packet_id") == row["packet_id"] and fact.get("result") == row["result"]
                    and fact.get("lifecycle") == "terminal_cycle", "Member result lacks bound terminal lifecycle evidence")
            text(fact.get("invocation_ref") or fact.get("lifecycle_evidence_ref"))


@dataclass(frozen=True)
class ProgressTransitionRequest:
    state: ProgressState
    resolved_sources: Mapping[str, dict]
    event: Optional[ProgressEvent] = None
    action: Optional[ActionIdentity] = None
    admit: bool = False
    continuing: bool = False


@dataclass(frozen=True)
class ProgressTransitionResult:
    state: ProgressState
    admitted: bool = False


def transition(request: ProgressTransitionRequest) -> ProgressTransitionResult:
    """Apply one completed checkpoint first; admission is a separate gated call.

    Commit the returned state before spawning. Rejected external gates call only
    the checkpoint half, leaving any bound unblock unconsumed. Waiting has no event.
    """
    state = ProgressState.parse(request.state.wire(), request.resolved_sources)
    event = request.event
    if event is not None:
        base = resolved(request.resolved_sources, state.history_base_ref) if state.history_base_ref else {}
        seen_ids = {row.event_id for row in state.history} | set(base.get("seen_event_ids", []))
        predecessor = state.history[-1].event_id if state.history else base.get("last_event_id")
        require(event.guard == state.guard and event.event_id not in seen_ids
                and event.predecessor_event_id == predecessor,
                "Replayed, reordered or changed-identity checkpoint", "progress_replay")
        if event.kind == "work_checkpoint":
            admission = state.action_admission
            require(admission is not None and event.action_ref == admission.action.action_ref
                    and event.admission_ref == admission.admission_ref, "Completed cycle must bind its admitted action")
            if admission.action.member_scope:
                require(event.coordinator_barrier_ref is not None, "Grouped cycle needs one complete coordinator barrier")
                coordinator_barrier(event, request.resolved_sources, admission.action.member_scope)
            else:
                require(event.coordinator_barrier_ref is None, "Singleton cycle cannot claim coordinator membership")
            if event.disposition == "useful_new_evidence" and state.history_base_ref:
                require("seen_resolved_uncertainty_refs" in base,
                        "Reconstruct the compacted uncertainty inventory before claiming new useful evidence",
                        "progress_history_missing")
        wire = state.wire()
        wire["history"].append(event.wire())
        wire["evidence_refs"] = list(dict.fromkeys(wire["evidence_refs"] + list(event.evidence_refs) + [event.assessment_ref]))
        if event.kind == "work_checkpoint":
            wire.update(work_ordinal=state.work_ordinal + 1,
                        consecutive_no_progress=0 if event.disposition != "no_progress" else state.consecutive_no_progress + 1,
                        frontier_ref=event.frontier_ref)
            wire["status"] = "stagnant" if wire["consecutive_no_progress"] >= state.policy.stagnation_window else "active"
            wire.pop("action_admission", None)
        elif event.kind == "material_unblock":
            require(state.status == "stagnant", "Only a genuine stalled guard may reactivate")
            wire["status"] = "reactivated"
        else:
            wire["policy"] = event.new_policy.wire()
            wire["status"] = ("reactivated" if state.status == "reactivated" else
                              "stagnant" if state.consecutive_no_progress >= event.new_policy.stagnation_window else "active")
        state = ProgressState.parse(wire, request.resolved_sources)
    if not request.admit:
        return ProgressTransitionResult(state)
    action = request.action
    require(action is not None, "Admission needs current packet/input/action identity")
    if action.member_scope:
        action.member_scope.authority(request.resolved_sources, state.guard, action.action_ref)
    if request.continuing:
        require(state.action_admission is not None and state.action_admission.action == action,
                "RUNNING stages must reuse their existing action admission", "progress_replay")
        return ProgressTransitionResult(state, True)
    require(state.action_admission is None,
            "Complete/reconcile the admitted action before admitting another; no replay or hidden private loop", "progress_replay")
    base = resolved(request.resolved_sources, state.history_base_ref) if state.history_base_ref else {}
    closed_actions = {row.action_ref for row in state.history if row.kind == "work_checkpoint"} | set(base.get("seen_action_refs", []))
    require(action.action_ref not in closed_actions, "Completed semantic action cannot be admitted again", "progress_replay")
    require(state.status in {"active", "reactivated"}, "Effective stagnation window exhausted; retain evidence and resolve the stall",
            "progress_stagnant")
    unblock_id = None
    if state.status == "reactivated":
        unblock = next((row for row in reversed(state.history) if row.kind != "policy_change"), None)
        require(unblock is not None and unblock.kind == "material_unblock" and unblock.action_ref == action.action_ref,
                "Material unblock permits only its exact newly feasible action", "progress_stagnant")
        require(unblock.action_scope_ref == (action.member_scope.source_ref if action.member_scope else None),
                "Material unblock permits only its exact coordinator scope", "progress_stagnant")
        unblock_id = unblock.event_id
        require(state.action_admission is None or state.action_admission.unblock_event_id != unblock_id,
                "Material unblock already consumed", "progress_replay")
    admission = ActionAdmission("admission:" + state.guard.guard_id + ":" + action.action_ref,
                                state.guard.guard_id, action, unblock_id)
    return ProgressTransitionResult(replace(state, action_admission=admission), True)
