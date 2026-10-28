#!/usr/bin/env bash
# Closed-world semantic validators used by provider-neutral local eval grading.

semantic_validator_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

semantic_validator_id_for_case() {
    local fixture_file="$1"
    local case_id="$2"

    jq -r --arg id "$case_id" '.cases[] | select(.id == $id) | .semantic_validator // empty' "$fixture_file"
}

assistant_research_five_lens_v4_valid() {
    local response_path="$1"
    local fixture_file="$2"
    local case_id="$3"
    if [[ -n "${RESEARCH_DISPATCH_AUTHORITY_FILE:-}" ]]; then
        node "$semantic_validator_dir/research-semantic-validator.cjs" "$response_path" "$fixture_file" "$case_id" \
            --research-dispatch-authority "$RESEARCH_DISPATCH_AUTHORITY_FILE"
    else
        node "$semantic_validator_dir/research-semantic-validator.cjs" "$response_path" "$fixture_file" "$case_id"
    fi
}

assistant_skill_creator_behavior_v1_valid() {
    local response_path="$1"
    local fixture_file="$2"
    local case_id="$3"
    if [[ -n "${CREATOR_RUN_BINDINGS_FILE:-}" ]]; then
        node "$semantic_validator_dir/skill-creator-semantic-validator.cjs" "$response_path" "$fixture_file" "$case_id" \
            --creator-run-bindings "$CREATOR_RUN_BINDINGS_FILE" "$CREATOR_RUN_BINDINGS_SHA256"
    else
        node "$semantic_validator_dir/skill-creator-semantic-validator.cjs" "$response_path" "$fixture_file" "$case_id"
    fi
}

assistant_workflow_packet_admission_v15_valid() {
    local response_path="$1"
    local fixture_file="$2"
    local case_id="$3"
    local selected_skill_file="${4:-}"
    if ! command -v python3 >/dev/null 2>&1; then
        printf '%s\n' 'Python 3.9+ is required for Workflow grading. Install a supported python3 and rerun.' >&2
        return 1
    fi
    # Fixed fixture context supplies independent authority. The response is only
    # the proposed answer; never let it replace approval/evidence/runtime facts.
    python3 - "$semantic_validator_dir" "$selected_skill_file" \
        "$response_path" "$fixture_file" "$case_id" <<'PY'
import importlib.util
import os
from pathlib import Path
import sys

if sys.version_info < (3, 9):
    print("Python 3.9+ is required for Workflow grading. Install a supported python3 and rerun.", file=sys.stderr)
    sys.exit(1)

try:
    # Code authority comes only from the runner and its inventory selection.
    # Fixture/response paths and fields remain data, even when selected explicitly.
    runner_root = Path(sys.argv[1]).resolve(strict=True).parents[2]
    if not sys.argv[2]:
        raise ValueError("Missing selected Workflow identity")
    selected = Path(sys.argv[2]).resolve(strict=True)
    roots = [(runner_root / "skills", runner_root)]
    profile_text = next((os.environ[name] for name in ("USERPROFILE", "HOME")
                         if os.environ.get(name, "").strip()), None)
    if profile_text is not None and Path(profile_text).is_dir():
        profile = Path(profile_text).resolve(strict=True)
        configured_text = os.environ.get("CODEX_HOME", "")
        codex_home = (Path(configured_text) if configured_text.strip() else profile / ".codex").resolve()
        if runner_root == codex_home:
            roots.append((profile / ".agents" / "skills", profile))
    matches = set()
    for base, owner in roots:
        # Absent recognized roots are not alternate helper candidates.
        if not base.is_dir():
            continue
        physical_base = base.resolve(strict=True)
        workflow = (base / "assistant-workflow").resolve()
        if (physical_base.is_relative_to(owner) and workflow == physical_base / "assistant-workflow"
                and workflow.is_dir() and selected.is_relative_to(workflow)
                and selected == (workflow / "SKILL.md").resolve() and selected.is_file()):
            matches.add(workflow)
    if len(matches) != 1:
        raise ValueError("Selected Workflow has no unique trusted code owner")
    workflow = matches.pop()
    helper = (workflow / "scripts" / "task-packet-admission.py").resolve(strict=True)
    if not helper.is_file() or not helper.is_relative_to(workflow):
        raise ValueError("Selected Workflow helper is missing or escapes its owner")
    spec = importlib.util.spec_from_file_location("workflow_packet_admission", helper)
    if spec is None or spec.loader is None:
        raise ValueError("Selected Workflow helper cannot be imported")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    with open(sys.argv[4], encoding="utf-8") as stream:
        fixture = module.load_json(stream.read())
    cases = [case for case in fixture["cases"] if case["id"] == sys.argv[5]]
    if len(cases) != 1:
        raise ValueError("Expected exactly one fixed case")
    fixed = cases[0]["semantic_context"]["packet_admission"]
    actual = module.admission(fixed["request"])
    if actual["status"] != fixed["expected_status"] or actual["code"] != fixed["expected_code"]:
        raise ValueError("Fixed case contradicts current authority")
    with open(sys.argv[3], encoding="utf-8") as stream:
        response = module.load_json(stream.read())
    answer = response["packet_admission"]
    if answer["status"] != actual["status"] or answer["code"] != actual["code"]:
        raise ValueError("Admission status or code contradicts current authority")
    if actual["status"] == "accepted":
        if module.digest(answer["canonical_plan"]) != module.digest(actual["canonical_plan"]):
            raise ValueError("Canonical plan contradicts current authority")
        if module.digest(answer.get("current_task_packet")) != module.digest(actual.get("current_task_packet")):
            raise ValueError("Worker projection contradicts current authority")
    else:
        # Bounded envelope leaves no unvalidated nested container for a claim.
        if not isinstance(response, dict) or set(response) - {"summary", "packet_admission"}:
            raise ValueError("Blocked response has unknown fields")
        if "summary" in response and not isinstance(response["summary"], str):
            raise ValueError("Blocked summary must be a string")
        if not isinstance(answer, dict) or set(answer) - {"status", "code", "canonical_plan"}:
            raise ValueError("Blocked admission has unknown fields")
        if "canonical_plan" in answer and ("canonical_plan" not in actual or
                module.digest(answer["canonical_plan"]) != module.digest(actual["canonical_plan"])):
            raise ValueError("Blocked plan contradicts retained authority")
except (AssertionError, KeyError, TypeError, ValueError, OSError, ImportError, SyntaxError):
    print("Packet admission answer contradicts fixed current authority", file=sys.stderr)
    sys.exit(1)
PY
}

run_semantic_validator() {
    local validator_id="$1"
    local response_path="$2"
    local fixture_file="$3"
    local case_id="$4"
    local selected_skill_file="${5:-}"

    case "$validator_id" in
        assistant-research.five_lens_v4|assistant-research.five_lens_v5) assistant_research_five_lens_v4_valid "$response_path" "$fixture_file" "$case_id" ;;
        assistant-skill-creator.behavior_v1) assistant_skill_creator_behavior_v1_valid "$response_path" "$fixture_file" "$case_id" ;;
        assistant-workflow.packet_admission_v15) assistant_workflow_packet_admission_v15_valid "$response_path" "$fixture_file" "$case_id" "$selected_skill_file" ;;
        *)
            echo "Unknown semantic validator: $validator_id" >&2
            return 1
            ;;
    esac
}
