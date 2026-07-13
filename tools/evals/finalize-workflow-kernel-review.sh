#!/usr/bin/env bash
# Deterministically bind a human synthetic-review verdict to workflow-kernel eval evidence.

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/context-budget-evidence.sh"
CASE_FIXTURE="$REPO_ROOT/docs/evals/framework-instruction-cases.json"
SYNTHETIC_FIXTURE_REF="docs/evals/fixtures/seeded-code-review-regressions"
SYNTHETIC_FIXTURE_DIR="$REPO_ROOT/$SYNTHETIC_FIXTURE_REF"
RESULTS_DIR=""
BASELINE_VARIANT=""
CANDIDATE_VARIANT=""
VERDICT_FILE=""
TEMPLATE_FILE=""
TRACE_VALIDATOR="$REPO_ROOT/tools/evals/run-framework-instruction-evals.sh"
COMPARISON_PROGRAM="$SCRIPT_DIR/lib/framework-comparison.jq"
CODEX_EVAL_RUNNER="$SCRIPT_DIR/run-codex-framework-evals.sh"
EXPECTED_ADAPTER_VERSION="codex-framework-eval-v5"
CURRENT_BASELINE_INSTRUCTION_HASH=""
CURRENT_CANDIDATE_INSTRUCTION_HASH=""
CURRENT_CONTEXT_BUDGET_EVIDENCE_HASH=""
CURRENT_CANDIDATE_MANIFEST=""
CURRENT_CANDIDATE_MANIFEST_HASH=""

usage() {
    cat <<'EOF'
Usage:
  finalize-workflow-kernel-review.sh --results DIR --baseline-variant DIR --candidate-variant DIR --write-verdict-template FILE
  finalize-workflow-kernel-review.sh --results DIR --baseline-variant DIR --candidate-variant DIR --verdict FILE

The template contains only bounded packet identifiers and pending enum values.
Finalization invokes no model. It writes a canonical human verdict and a
fail-closed promotion decision into the results directory.
EOF
}

die() { echo "Error: $1" >&2; exit 1; }

valid_utc_timestamp() {
    local value="$1" roundtrip=""
    [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 1
    if roundtrip="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$value" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"; then
        [[ "$roundtrip" == "$value" ]]
        return
    fi
    roundtrip="$(date -u -d "$value" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" || return 1
    [[ "$roundtrip" == "$value" ]]
}

hash_stream() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
    else shasum -a 256 | awk '{print $1}'; fi
}

hash_file() {
    local path="$1"
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$path" | awk '{print $1}'
    else shasum -a 256 "$path" | awk '{print $1}'; fi
}

hash_text() { printf '%s' "$1" | hash_stream; }

read_selected_model_catalog_entry() {
    local codex_path="$1" requested_model="$2" timeout_seconds="$3"
    command -v python3 >/dev/null 2>&1 || return 1
    python3 - "$codex_path" "$requested_model" "$timeout_seconds" <<'PY'
import json
import os
import select
import signal
import subprocess
import sys
import time

codex_path, requested_model, timeout_text = sys.argv[1:]
process = None

def stop_process_group():
    if process is None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    grace_deadline = time.monotonic() + 0.5
    try:
        process.wait(timeout=0.5)
    except subprocess.TimeoutExpired:
        pass
    remaining_grace = grace_deadline - time.monotonic()
    if remaining_grace > 0:
        time.sleep(remaining_grace)
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=0.5)
    except subprocess.TimeoutExpired:
        pass

def handle_signal(_signum, _frame):
    raise InterruptedError("catalog watchdog interrupted")

signal.signal(signal.SIGINT, handle_signal)
signal.signal(signal.SIGTERM, handle_signal)

try:
    timeout_seconds = int(timeout_text)
    deadline = time.monotonic() + timeout_seconds
    process = subprocess.Popen(
        [codex_path, "debug", "models"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    catalog_bytes = bytearray()
    max_catalog_bytes = 4 * 1024 * 1024
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise subprocess.TimeoutExpired(process.args, timeout_seconds)
        ready, _, _ = select.select([process.stdout], [], [], remaining)
        if not ready:
            raise subprocess.TimeoutExpired(process.args, timeout_seconds)
        chunk = os.read(process.stdout.fileno(), 65536)
        if not chunk:
            break
        catalog_bytes.extend(chunk)
        if len(catalog_bytes) > max_catalog_bytes:
            raise ValueError("model catalog exceeded byte cap")
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise subprocess.TimeoutExpired(process.args, timeout_seconds)
    returncode = process.wait(timeout=remaining)
    if returncode != 0:
        raise ValueError("catalog command failed")
    catalog = json.loads(catalog_bytes)
    models = catalog.get("models") if isinstance(catalog, dict) else None
    if not isinstance(models, list):
        raise ValueError("malformed model catalog")
    matches = [entry for entry in models if isinstance(entry, dict) and entry.get("slug") == requested_model]
    if len(matches) != 1:
        raise ValueError("requested model catalog identity is not unique")
    sys.stdout.write(json.dumps(matches[0], sort_keys=True, separators=(",", ":"), ensure_ascii=True))
except (OSError, ValueError, json.JSONDecodeError, subprocess.TimeoutExpired):
    stop_process_group()
    sys.exit(1)
PY
}

atomic_write_json() {
    local destination="$1" directory base temporary
    directory="$(dirname "$destination")"
    base="$(basename "$destination")"
    temporary="$(mktemp "$directory/.$base.tmp.XXXXXX")" || return 1
    if ! tee "$temporary" >/dev/null || ! jq empty "$temporary" >/dev/null 2>&1; then
        rm -f "$temporary"
        return 1
    fi
    mv -f "$temporary" "$destination"
}

case_hash() {
    jq -cS --arg id "$1" '.cases[] | select(.id == $id)' "$CASE_FIXTURE" | hash_stream
}

grader_hash() {
    local contract_hash runner_hash
    contract_hash="$(jq -cS --arg id "$1" \
        '.cases[] | select(.id == $id) | {fail_signals, machine_expectations, semantic_review}' \
        "$CASE_FIXTURE" | hash_stream)"
    runner_hash="$(hash_file "$CODEX_EVAL_RUNNER")"
    printf 'contract_sha256=%s\nrunner_sha256=%s\n' "$contract_hash" "$runner_hash" | hash_stream
}

resolve_overlay_file() {
    local supplied="$1" resolved overlay
    if [[ -f "$supplied/SKILL.md" ]]; then
        resolved="$(cd "$supplied" && pwd)"; overlay="$resolved/SKILL.md"
    elif [[ -f "$supplied/skills/assistant-workflow/SKILL.md" ]]; then
        resolved="$(cd "$supplied/skills/assistant-workflow" && pwd)"; overlay="$resolved/SKILL.md"
    else
        die "Variant must contain SKILL.md directly or under skills/assistant-workflow."
    fi
    find "$resolved" ! -type d ! -type f -print -quit | grep -q . \
        && die "Variant may contain only regular files and directories."
    printf '%s\n' "$overlay"
}

hash_directory() {
    local directory="$1" inventory="" file relative digest
    while IFS= read -r file; do
        relative="${file#"$directory"/}"; digest="$(hash_file "$file")"
        inventory+="$relative $digest"$'\n'
    done < <(find "$directory" -type f -print | LC_ALL=C sort)
    hash_text "$inventory"
}

trace_set_sha256() {
    local directory="$1" inventory="" file name digest count=0
    [[ -d "$directory" && ! -L "$directory" ]] || return 1
    if find "$directory" -mindepth 1 -maxdepth 1 ! -type f -print -quit | grep -q .; then
        return 1
    fi
    while IFS= read -r file; do
        name="$(basename "$file")"
        [[ "$name" == *.json ]] || return 1
        digest="$(hash_file "$file")"
        inventory+="$name $digest"$'\n'
        count=$((count + 1))
    done < <(find "$directory" -mindepth 1 -maxdepth 1 -type f -name '*.json' -print | LC_ALL=C sort)
    [[ "$count" -gt 0 ]] || return 1
    hash_text "$inventory"
}

validate_synthetic_fixture() {
    [[ -d "$SYNTHETIC_FIXTURE_DIR" ]] || die "Synthetic seeded-review fixture is missing."
    if find "$SYNTHETIC_FIXTURE_DIR" ! -type d ! -type f -print -quit | grep -q .; then
        die "Synthetic seeded-review fixture may contain only regular files and directories."
    fi
    local inventory
    inventory="$(find "$SYNTHETIC_FIXTURE_DIR" -type f -print \
        | sed "s#^$SYNTHETIC_FIXTURE_DIR/##" | LC_ALL=C sort)"
    [[ "$inventory" == $'REQUIREMENTS.md\nsrc/order.js\ntests/order.test.js' ]] \
        || die "Synthetic seeded-review fixture has an unexpected file inventory."
}

materialize_variant() {
    local overlay="$1" destination="$2" entry instruction_file
    mkdir -p "$destination"
    while IFS= read -r entry; do cp -R "$entry" "$destination/"; done \
        < <(find "$REPO_ROOT/skills/assistant-workflow" -mindepth 1 -maxdepth 1 ! -name evals -print | LC_ALL=C sort)
    cp "$overlay" "$destination/SKILL.md"
    if [[ -f "$destination/agents/codex.conf" ]]; then
        cp "$destination/agents/codex.conf" "$destination/agent.conf"
    fi
    while IFS= read -r instruction_file; do
        sed -i.bak -e 's|{agent_state_dir}|.codex|g' "$instruction_file"
        rm -f "${instruction_file}.bak"
    done < <(find "$destination" -type f \( \
        -name '*.md' -o -name '*.yaml' -o -name '*.yml' -o -name '*.json' \
        -o -name '*.conf' -o -name '*.toml' \))
}

materialized_variant_hash() {
    local overlay="$1" temporary result
    temporary="$(mktemp -d "${TMPDIR:-/tmp}/workflow-kernel-finalizer.XXXXXX")"
    trap 'rm -rf "$temporary"' RETURN
    materialize_variant "$overlay" "$temporary"
    result="$(hash_directory "$temporary")"
    rm -rf "$temporary"; trap - RETURN
    printf '%s\n' "$result"
}

# Source-compatible name retained for focused contract tests and downstream callers.
materialized_candidate_hash() { materialized_variant_hash "$1"; }

validate_current_context_evidence() {
    local plan="$1" baseline_overlay candidate_overlay fresh embedded_hash fresh_hash materialized_root
    local fresh_file baseline_dir candidate_dir
    baseline_overlay="$(resolve_overlay_file "$BASELINE_VARIANT")"
    candidate_overlay="$(resolve_overlay_file "$CANDIDATE_VARIANT")"
    CURRENT_CANDIDATE_MANIFEST="$(dirname "$candidate_overlay")/manifest.json"
    [[ -f "$CURRENT_CANDIDATE_MANIFEST" ]] || die "Candidate manifest is missing."
    CURRENT_CANDIDATE_MANIFEST_HASH="$(hash_file "$CURRENT_CANDIDATE_MANIFEST")"
    materialized_root="$(mktemp -d "${TMPDIR:-/tmp}/workflow-kernel-current-variants.XXXXXX")"
    baseline_dir="$materialized_root/baseline"
    candidate_dir="$materialized_root/candidate"
    materialize_variant "$baseline_overlay" "$baseline_dir"
    materialize_variant "$candidate_overlay" "$candidate_dir"
    CURRENT_BASELINE_INSTRUCTION_HASH="$(hash_directory "$baseline_dir")"
    CURRENT_CANDIDATE_INSTRUCTION_HASH="$(hash_directory "$candidate_dir")"
    fresh_file="$(mktemp "${TMPDIR:-/tmp}/workflow-kernel-context-evidence.XXXXXX")"
    context_budget_build_evidence \
        "$REPO_ROOT/tools/context-budget-report.sh" \
        "$baseline_dir/SKILL.md" "$candidate_dir/SKILL.md" \
        "$CURRENT_BASELINE_INSTRUCTION_HASH" "$CURRENT_CANDIDATE_INSTRUCTION_HASH" \
        "$fresh_file" \
        || { rm -rf "$materialized_root"; rm -f "$fresh_file"; die "Could not recompute fresh context-budget evidence."; }
    context_budget_validate_evidence_structure "$fresh_file" \
        || { rm -rf "$materialized_root"; rm -f "$fresh_file"; die "Fresh context-budget evidence is structurally invalid."; }
    context_budget_validate_promotion_policy "$fresh_file" \
        || { rm -rf "$materialized_root"; rm -f "$fresh_file"; die "Fresh context-budget evidence violates workflow-kernel promotion caps or standing-context policy."; }
    context_budget_validate_manifest "$CURRENT_CANDIDATE_MANIFEST" "$fresh_file" \
        || { rm -rf "$materialized_root"; rm -f "$fresh_file"; die "Candidate manifest does not match fresh context-budget evidence."; }
    fresh="$(jq -cS . "$fresh_file")"
    fresh_hash="$(printf '%s\n' "$fresh" | hash_stream)"
    embedded_hash="$(jq -cS '.context_budget_evidence' "$plan" | hash_stream)"
    if [[ "$fresh" != "$(jq -cS '.context_budget_evidence' "$plan")" \
        || "$fresh_hash" != "$embedded_hash" \
        || "$fresh_hash" != "$(jq -r '.context_budget_evidence_sha256 // ""' "$plan")" \
        || "$CURRENT_BASELINE_INSTRUCTION_HASH" != "$(jq -r '.baseline_variant.instruction_sha256 // ""' "$plan")" \
        || "$CURRENT_CANDIDATE_INSTRUCTION_HASH" != "$(jq -r '.candidate_variant.instruction_sha256 // ""' "$plan")" \
        || "$CURRENT_CANDIDATE_MANIFEST_HASH" != "$(jq -r '.candidate_manifest_sha256 // ""' "$plan")" ]]; then
        rm -rf "$materialized_root"
        rm -f "$fresh_file"
        die "Baseline, candidate, reporter, manifest, or context-budget evidence drifted from the run plan."
    fi
    CURRENT_CONTEXT_BUDGET_EVIDENCE_HASH="$fresh_hash"
    rm -rf "$materialized_root"
    rm -f "$fresh_file"
}

validate_ready_packet() {
    local packet="$1"
    jq -e '
      (keys_unsorted | sort) == (["bindings","diagnostics","pairs","review_kind","reviewability","schema_version","scope"] | sort)
      and .schema_version == "1.0"
      and .review_kind == "workflow_kernel_semantic_false_positive"
      and (.scope | keys_unsorted | sort) == (["case_category","case_ids","data_classification","raw_artifacts_retained","synthetic_fixture_ref","synthetic_fixture_sha256"] | sort)
      and .scope.data_classification == "synthetic"
      and .scope.case_category == "seeded_review"
      and .scope.case_ids == ["seeded-code-review-regressions"]
      and .scope.synthetic_fixture_ref == "docs/evals/fixtures/seeded-code-review-regressions"
      and (.scope.synthetic_fixture_sha256 | test("^[0-9a-f]{64}$"))
      and .scope.raw_artifacts_retained == false
      and (.bindings | keys_unsorted | sort) == (["baseline_instruction_sha256","candidate_instruction_sha256","candidate_manifest_sha256","comparison_sha256","context_budget_evidence_sha256","fixture_sha256","run_plan_sha256"] | sort)
      and .reviewability == {status:"ready",reason_codes:[]}
      and .diagnostics == []
      and (.pairs | type == "array" and length > 0)
      and all(.bindings[]; type == "string" and test("^[0-9a-f]{64}$"))
      and all(.pairs[];
        (.pair_sha256 | test("^[0-9a-f]{64}$"))
        and .case_id == "seeded-code-review-regressions"
        and (.candidate.findings | type == "array" and length <= 8)
        and all(.candidate.findings[];
          (keys_unsorted | sort) == (["claim_code","finding_id","line","normalized_claim","review_summary","severity","source"] | sort)
          and (.finding_id | test("^candidate-[0-9]{2}$"))
          and (.source == "REQUIREMENTS.md" or .source == "src/order.js" or .source == "tests/order.test.js")
          and (.review_summary | type == "string" and length >= 1 and length <= 240 and (test("[\\r\\n]") | not))
          and (.review_summary | explode | all(. >= 32 and . <= 126 and . != 47 and . != 92))
          and (.review_summary | test("(^|[^[:alnum:]])(sk-[[:alnum:]_-]{8,}|ghp_[[:alnum:]_]{8,}|AKIA[[:alnum:]]{8,}|api[_-]?key|password|secret|bearer[[:space:]]+[[:alnum:]_.-]+|https?://|file://|/Users/|/home/|[A-Za-z]:\\\\|[[:alnum:]._%+-]+@[[:alnum:].-]+\\.[A-Za-z]{2,})([^[:alnum:]]|$)"; "i") | not)))
    ' "$packet" >/dev/null
}

write_template() {
    local packet="$1" destination="$2" trace_set_hash
    validate_current_context_evidence "$RESULTS_DIR/run-plan.json"
    validate_ready_packet "$packet" || die "Semantic review packet is not safely reviewable."
    [[ "$(hash_file "$RESULTS_DIR/run-plan.json")" == "$(jq -r '.bindings.run_plan_sha256' "$packet")" \
        && "$CURRENT_CONTEXT_BUDGET_EVIDENCE_HASH" == "$(jq -r '.bindings.context_budget_evidence_sha256' "$packet")" \
        && "$CURRENT_BASELINE_INSTRUCTION_HASH" == "$(jq -r '.bindings.baseline_instruction_sha256' "$packet")" \
        && "$CURRENT_CANDIDATE_INSTRUCTION_HASH" == "$(jq -r '.bindings.candidate_instruction_sha256' "$packet")" \
        && "$CURRENT_CANDIDATE_MANIFEST_HASH" == "$(jq -r '.bindings.candidate_manifest_sha256' "$packet")" ]] \
        || die "Semantic review packet bindings drifted from the current variants or run plan."
    [[ ! -e "$destination" ]] || die "Verdict template destination already exists."
    trace_set_hash="$(trace_set_sha256 "$RESULTS_DIR/traces")" \
        || die "Trace directory must contain only a non-empty canonical set of regular JSON files."
    jq --arg packet_sha256 "$(hash_file "$packet")" --arg trace_set_sha256 "$trace_set_hash" '
      {
        schema_version:"1.0",
        review_kind:"workflow_kernel_semantic_false_positive",
        reviewer:{kind:"pending",attestation:"pending"},
        reviewed_at:"pending",
        bindings:{
          review_packet_sha256:$packet_sha256,
          comparison_sha256:.bindings.comparison_sha256,
          candidate_manifest_sha256:.bindings.candidate_manifest_sha256,
          baseline_instruction_sha256:.bindings.baseline_instruction_sha256,
          candidate_instruction_sha256:.bindings.candidate_instruction_sha256,
          context_budget_evidence_sha256:.bindings.context_budget_evidence_sha256,
          trace_set_sha256:$trace_set_sha256,
          pair_sha256:[.pairs[].pair_sha256]
        },
        pair_verdicts:[.pairs[] | {
          pair_id:.pair_id,
          pair_sha256:.pair_sha256,
          candidate_findings:[.candidate.findings[] | {finding_id:.finding_id,verdict:"pending",reason_code:"pending"}],
          verdict:"pending"
        }],
        overall_verdict:"pending"
      }
    ' "$packet" | atomic_write_json "$destination"
}

validate_verdict() {
    local verdict="$1" packet="$2"
    jq -e --slurpfile packet "$packet" '
      . as $v | $packet[0] as $p
      | (keys_unsorted | sort) == (["bindings","overall_verdict","pair_verdicts","review_kind","reviewed_at","reviewer","schema_version"] | sort)
      and .schema_version == "1.0"
      and .review_kind == "workflow_kernel_semantic_false_positive"
      and .reviewer == {kind:"human",attestation:"reviewed_all_candidate_findings_against_synthetic_fixture"}
      and (.reviewed_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
      and (.overall_verdict == "approved" or .overall_verdict == "rejected")
      and (.bindings | keys_unsorted | sort) == (["baseline_instruction_sha256","candidate_instruction_sha256","candidate_manifest_sha256","comparison_sha256","context_budget_evidence_sha256","pair_sha256","review_packet_sha256","trace_set_sha256"] | sort)
      and (.bindings.trace_set_sha256 | test("^[0-9a-f]{64}$"))
      and ([.bindings.pair_sha256[]] | sort) == ([$p.pairs[].pair_sha256] | sort)
      and ([.pair_verdicts[].pair_id] | sort) == ([$p.pairs[].pair_id] | sort)
      and ([.pair_verdicts[] as $pv
        | ($p.pairs[] | select(.pair_id == $pv.pair_id)) as $pair
        | (($pv | keys_unsorted | sort) == (["candidate_findings","pair_id","pair_sha256","verdict"] | sort)
          and $pv.pair_sha256 == $pair.pair_sha256
          and ([$pv.candidate_findings[].finding_id] | sort) == ([$pair.candidate.findings[].finding_id] | sort)
          and all($pv.candidate_findings[];
            (keys_unsorted | sort) == (["finding_id","reason_code","verdict"] | sort)
            and ((.verdict == "supported" and .reason_code == "supported_by_synthetic_fixture")
              or (.verdict == "false_positive" and .reason_code == "not_supported_by_synthetic_fixture")
              or (.verdict == "unverifiable" and .reason_code == "insufficient_packet_evidence")))
          and (($pv.verdict == "approved" and all($pv.candidate_findings[]; .verdict == "supported"))
            or ($pv.verdict == "rejected" and any($pv.candidate_findings[]; .verdict != "supported"))))
      ] | all)
      and ((.overall_verdict == "approved" and all(.pair_verdicts[]; .verdict == "approved"))
        or (.overall_verdict == "rejected" and any(.pair_verdicts[]; .verdict == "rejected")))
    ' "$verdict" >/dev/null \
        && valid_utc_timestamp "$(jq -r '.reviewed_at' "$verdict")"
}

validate_plan_trace_contract() {
    local plan="$1" traces_dir="$2"
    local expected_count actual_count pair_id case_id trial_index variant instruction_sha256 trace_path current_case_hash current_grader_hash
    expected_count="$(jq '.planned_runs' "$plan")"
    actual_count="$(find "$traces_dir" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
    [[ "$actual_count" == "$expected_count" ]] || return 1
    while IFS=$'\t' read -r pair_id case_id trial_index variant instruction_sha256; do
        trace_path="$traces_dir/$pair_id-$variant.json"
        [[ -f "$trace_path" ]] || return 1
        current_case_hash="$(case_hash "$case_id")"
        current_grader_hash="$(grader_hash "$case_id")"
        jq -e \
          --arg pair_id "$pair_id" \
          --arg case_id "$case_id" \
          --argjson trial_index "$trial_index" \
          --arg variant "$variant" \
          --arg instruction_sha256 "$instruction_sha256" \
          --arg fixture_sha256 "$(jq -r '.fixture_sha256' "$plan")" \
          --arg requested_model "$(jq -r '.requested_model' "$plan")" \
          --arg requested_model_catalog_entry_sha256 "$(jq -r '.requested_model_catalog_entry_sha256 // ""' "$plan")" \
          --arg codex_executable_sha256 "$(jq -r '.codex_executable_sha256 // ""' "$plan")" \
          --arg cli_version "$(jq -r '.cli_version // ""' "$plan")" \
          --arg model_selection_evidence "$(jq -r 'if .model_selection_evidence.method == "codex_debug_models_requested_entry" then "catalog_entry_and_explicit_model_argument" else "explicit_model_argument_only" end' "$plan")" \
          --arg case_sha256 "$current_case_hash" \
          --arg grader_sha256 "$current_grader_hash" \
          --arg adapter_version "$EXPECTED_ADAPTER_VERSION" '
          .pair_id == $pair_id
          and .case_id == $case_id
          and .trial_index == $trial_index
          and .variant == $variant
          and .provenance.instruction_sha256 == $instruction_sha256
          and .provenance.fixture_sha256 == $fixture_sha256
          and .provenance.case_sha256 == $case_sha256
          and .provenance.grader_sha256 == $grader_sha256
          and .provenance.adapter_version == $adapter_version
          and .model == $requested_model
          and .provenance.requested_model == $requested_model
          and .provenance.runtime_model_attestation == "not_exposed_by_codex_jsonl"
          and .provenance.model_selection_evidence == $model_selection_evidence
          and .provenance.requested_model_catalog_entry_sha256 == (if $requested_model_catalog_entry_sha256 == "" then null else $requested_model_catalog_entry_sha256 end)
          and .provenance.codex_executable_sha256 == (if $codex_executable_sha256 == "" then null else $codex_executable_sha256 end)
          and .provenance.cli_version == $cli_version
          and (.provenance | has("resolved_model") | not)
        ' "$trace_path" >/dev/null || return 1
    done < <(jq -r '.runs[] | [.pair_id,.case_id,.trial_index,.variant,.instruction_sha256] | @tsv' "$plan")
}

recompute_and_validate_comparison() {
    local plan="$1" comparison="$2" manifest="$3" manifest_hash="$4"
    local traces_dir="$RESULTS_DIR/traces" recomputed persisted_canonical recomputed_canonical
    [[ -x "$TRACE_VALIDATOR" && -f "$COMPARISON_PROGRAM" && -d "$traces_dir" ]] || return 1
    "$TRACE_VALIDATOR" --validate-traces "$traces_dir" >/dev/null || return 1
    validate_plan_trace_contract "$plan" "$traces_dir" || return 1
    recomputed="$(mktemp "${TMPDIR:-/tmp}/workflow-kernel-comparison.XXXXXX")"
    jq -s \
      --argjson manifest "$(jq -c . "$manifest")" \
      --arg candidate_manifest_sha256 "$manifest_hash" \
      -f "$COMPARISON_PROGRAM" \
      "$traces_dir"/*.json >"$recomputed" || { rm -f "$recomputed"; return 1; }
    persisted_canonical="$(jq -cS . "$comparison")" || { rm -f "$recomputed"; return 1; }
    recomputed_canonical="$(jq -cS . "$recomputed")" || { rm -f "$recomputed"; return 1; }
    rm -f "$recomputed"
    [[ "$persisted_canonical" == "$recomputed_canonical" ]]
}

validate_exact_pilot_evidence() {
    local plan="$1" comparison="$2" packet="$3" manifest="$4"
    jq -e \
      --slurpfile plan "$plan" \
      --slurpfile comparison "$comparison" \
      --slurpfile packet "$packet" '
      . as $manifest
      | $plan[0] as $plan
      | $comparison[0] as $comparison
      | $packet[0] as $packet
      | (["small-fix-stays-lightweight","stale-journal-yields-to-current-evidence","requirements-map-through-completion","ordinary-medium-bounded-executor","seeded-code-review-regressions","medium-final-handoff-is-reconstructable"] | sort) as $pilot_cases
      | 3 as $pilot_repeats
      | ($pilot_cases | length) as $case_count
      | ($case_count * $pilot_repeats) as $expected_pairs
      | ($manifest.smoke_cases == ["small-fix-stays-lightweight","seeded-code-review-regressions"])
      and ($manifest.pilot_cases == ["small-fix-stays-lightweight","stale-journal-yields-to-current-evidence","requirements-map-through-completion","ordinary-medium-bounded-executor","seeded-code-review-regressions","medium-final-handoff-is-reconstructable"])
      and ($manifest.smoke_repeats == 1)
      and ($manifest.pilot_repeats == 3)
      and ($plan.repeats == $pilot_repeats)
      and ($plan.fixture_sha256 == $packet.bindings.fixture_sha256)
      and ($plan.candidate_manifest_sha256 == $packet.bindings.candidate_manifest_sha256)
      and ($plan.baseline_variant.instruction_sha256 == $packet.bindings.baseline_instruction_sha256)
      and ($plan.candidate_variant.instruction_sha256 == $packet.bindings.candidate_instruction_sha256)
      and ($plan.context_budget_evidence_sha256 == $packet.bindings.context_budget_evidence_sha256)
      and ($comparison.candidate_manifest_sha256 == $packet.bindings.candidate_manifest_sha256)
      and ($plan.planned_pairs == $expected_pairs)
      and ($plan.planned_runs == ($expected_pairs * 2))
      and (([$plan.runs[].case_id] | unique | sort) == $pilot_cases)
      and all($pilot_cases[] as $case_id
        | range(1; $pilot_repeats + 1) as $trial
        | ([$plan.runs[] | select(.case_id == $case_id and .trial_index == $trial)]) as $runs
        | ($runs | length) == 2
        and ([$runs[].variant] | sort) == ["baseline","candidate"]
        and ([$runs[].pair_id] | unique | length) == 1
        and ([$runs[].execution_position] | sort) == [1,2])
      and ($comparison.pilot_coverage_complete == true)
      and ($comparison.automatic_behavioral_gates_passed == true)
      and ($comparison.complete_pairs == $expected_pairs)
      and ($comparison.excluded_incomplete_pairs == 0)
      and (([$comparison.paired_results[].pair_id] | unique | length) == $expected_pairs)
      and (([$packet.pairs[].pair_id] | sort)
        == ([$plan.runs[] | select(.case_id == "seeded-code-review-regressions") | .pair_id] | unique | sort))
      and (($packet.pairs | length) == $pilot_repeats)
      and (([$packet.pairs[].trial_index] | sort) == [range(1; $pilot_repeats + 1)])
    ' "$manifest" >/dev/null
}

current_model_selection_evidence_matches() {
    local plan="$1" codex_path cli_version executable_hash requested_model entry_hash selected_entry catalog_timeout
    command -v codex >/dev/null 2>&1 || return 1
    codex_path="$(command -v codex)"
    cli_version="$($codex_path --version 2>/dev/null || true)"
    [[ -n "$cli_version" ]] || return 1
    executable_hash="$(hash_file "$codex_path")"
    requested_model="$(jq -r '.requested_model' "$plan")"
    catalog_timeout="$(jq -r '.model_catalog_timeout_seconds // 0' "$plan")"
    [[ "$catalog_timeout" =~ ^[0-9]+$ && "$catalog_timeout" -ge 1 && "$catalog_timeout" -le 120 ]] || return 1
    selected_entry="$(read_selected_model_catalog_entry "$codex_path" "$requested_model" "$catalog_timeout")" || return 1
    entry_hash="$(printf '%s' "$selected_entry" | hash_stream)"
    selected_entry=""
    jq -e \
      --arg cli_version "$cli_version" \
      --arg executable_hash "$executable_hash" \
      --arg entry_hash "$entry_hash" '
      .cli_version == $cli_version
      and .codex_executable_sha256 == $executable_hash
      and .requested_model_catalog_entry_sha256 == $entry_hash
    ' "$plan" >/dev/null
}

trusted_execution_profile_passes() {
    local plan="$1" traces_dir="$2"
    jq -e '
      .mode == "execute"
      and .requested_model == "gpt-5.6-terra"
      and .model_selection_evidence == {
        method:"codex_debug_models_requested_entry",
        catalog_source:"active",
        runtime_model_attestation:"not_exposed_by_codex_jsonl",
        requested_model_catalog_status:"present"
      }
      and (.requested_model_catalog_entry_sha256 | type == "string" and test("^[0-9a-f]{64}$"))
      and (.codex_executable_sha256 | type == "string" and test("^[0-9a-f]{64}$"))
      and (.cli_version | type == "string" and length > 0)
      and (.model_catalog_timeout_seconds | type == "number" and . >= 1 and . <= 120 and . == floor)
      and .execution_profile == {
        mode:"execute",
        codex_binary_source:"default",
        required_promotion_model:"gpt-5.6-terra",
        promotion_profile_eligible:true
      }
    ' "$plan" >/dev/null \
        && jq -s -e '
          length > 0
          and all(.[];
            .status == "completed"
            and .model == "gpt-5.6-terra"
            and .provenance.requested_model == "gpt-5.6-terra"
            and .provenance.runtime_model_attestation == "not_exposed_by_codex_jsonl"
            and .provenance.model_selection_evidence == "catalog_entry_and_explicit_model_argument"
            and (.provenance.requested_model_catalog_entry_sha256 | type == "string" and test("^[0-9a-f]{64}$"))
            and (.provenance.codex_executable_sha256 | type == "string" and test("^[0-9a-f]{64}$"))
            and (.provenance | has("resolved_model") | not)
            and .provenance.adapter_version == "codex-framework-eval-v5")
        ' "$traces_dir"/*.json >/dev/null \
        && current_model_selection_evidence_matches "$plan"
}

finalize() {
    local packet="$RESULTS_DIR/semantic-review-packet.json" comparison="$RESULTS_DIR/comparison.json"
    local plan="$RESULTS_DIR/run-plan.json" manifest current_manifest_hash current_instruction_hash current_baseline_hash
    local current_fixture_hash current_case_hash current_grader_hash current_synthetic_fixture_hash current_trace_set_hash
    [[ -f "$packet" && -f "$comparison" && -f "$plan" ]] || die "Results are missing packet, comparison, or run plan."
    local semantic_artifact="$RESULTS_DIR/semantic-review-verdict.json"
    local decision_artifact="$RESULTS_DIR/promotion-decision.json"
    if [[ -e "$semantic_artifact" && -e "$decision_artifact" ]]; then
        die "Results already contain a finalized semantic decision."
    fi
    if [[ -e "$semantic_artifact" ]] \
        && [[ "$(jq -cS . "$semantic_artifact" 2>/dev/null || true)" != "$(jq -cS . "$VERDICT_FILE")" ]]; then
        die "Interrupted semantic verdict does not match the supplied verdict."
    fi
    validate_ready_packet "$packet" || die "Semantic review packet is not safely reviewable."

    validate_current_context_evidence "$plan"
    manifest="$CURRENT_CANDIDATE_MANIFEST"
    validate_synthetic_fixture
    current_manifest_hash="$CURRENT_CANDIDATE_MANIFEST_HASH"
    current_instruction_hash="$CURRENT_CANDIDATE_INSTRUCTION_HASH"
    current_baseline_hash="$CURRENT_BASELINE_INSTRUCTION_HASH"
    current_fixture_hash="$(hash_file "$CASE_FIXTURE")"
    current_case_hash="$(case_hash seeded-code-review-regressions)"
    current_grader_hash="$(grader_hash seeded-code-review-regressions)"
    current_synthetic_fixture_hash="$(hash_directory "$SYNTHETIC_FIXTURE_DIR")"
    current_trace_set_hash="$(trace_set_sha256 "$RESULTS_DIR/traces")" \
        || die "Trace directory must contain only a non-empty canonical set of regular JSON files."

    recompute_and_validate_comparison "$plan" "$comparison" "$manifest" "$current_manifest_hash" \
        || die "Persisted comparison does not exactly match strict current traces, plan identities, and manifest gates."
    validate_verdict "$VERDICT_FILE" "$packet" || die "Human verdict is invalid, incomplete, or not enum-only."

    [[ "$(hash_file "$packet")" == "$(jq -r '.bindings.review_packet_sha256' "$VERDICT_FILE")" \
        && "$(hash_file "$plan")" == "$(jq -r '.bindings.run_plan_sha256' "$packet")" \
        && "$(hash_file "$comparison")" == "$(jq -r '.bindings.comparison_sha256' "$packet")" \
        && "$(hash_file "$comparison")" == "$(jq -r '.bindings.comparison_sha256' "$VERDICT_FILE")" \
        && "$current_trace_set_hash" == "$(jq -r '.bindings.trace_set_sha256' "$VERDICT_FILE")" \
        && "$(jq -r '.bindings.baseline_instruction_sha256' "$packet")" == "$(jq -r '.bindings.baseline_instruction_sha256' "$VERDICT_FILE")" \
        && "$current_baseline_hash" == "$(jq -r '.bindings.baseline_instruction_sha256' "$packet")" \
        && "$current_manifest_hash" == "$(jq -r '.bindings.candidate_manifest_sha256' "$packet")" \
        && "$current_manifest_hash" == "$(jq -r '.bindings.candidate_manifest_sha256' "$VERDICT_FILE")" \
        && "$current_instruction_hash" == "$(jq -r '.bindings.candidate_instruction_sha256' "$packet")" \
        && "$current_instruction_hash" == "$(jq -r '.bindings.candidate_instruction_sha256' "$VERDICT_FILE")" \
        && "$CURRENT_CONTEXT_BUDGET_EVIDENCE_HASH" == "$(jq -r '.bindings.context_budget_evidence_sha256' "$packet")" \
        && "$CURRENT_CONTEXT_BUDGET_EVIDENCE_HASH" == "$(jq -r '.bindings.context_budget_evidence_sha256' "$VERDICT_FILE")" ]] \
        || die "Semantic verdict bindings are stale or do not match the current candidate."

    jq -e \
      --arg fixture_sha256 "$current_fixture_hash" \
      --arg case_sha256 "$current_case_hash" \
      --arg grader_sha256 "$current_grader_hash" \
      --arg synthetic_fixture_sha256 "$current_synthetic_fixture_hash" '
      .bindings.fixture_sha256 == $fixture_sha256
      and .scope.synthetic_fixture_sha256 == $synthetic_fixture_sha256
      and all(.pairs[];
        .case_sha256 == $case_sha256
        and .grader_sha256 == $grader_sha256
        and .seed_workspace_sha256 == $synthetic_fixture_sha256)
    ' "$packet" >/dev/null \
        || die "Semantic review evidence no longer matches the current case, grader, or synthetic fixture."

    if [[ "$(jq -r '.automatic_behavioral_gates_passed == true' "$comparison")" == true ]]; then
        validate_exact_pilot_evidence "$plan" "$comparison" "$packet" "$manifest" \
            || die "Automatic gates are not backed by the exact manifest pilot case, repeat, and pair identities."
    fi

    local pair_id expected actual trace_path variant
    while IFS=$'\t' read -r pair_id expected; do
        actual="$(jq -cS --arg id "$pair_id" '.pairs[] | select(.pair_id == $id) | del(.pair_sha256)' "$packet" | hash_stream)"
        [[ "$actual" == "$expected" ]] || die "Pair hash mismatch: $pair_id"
        for variant in baseline candidate; do
            trace_path="$RESULTS_DIR/traces/$pair_id-$variant.json"
            [[ -f "$trace_path" ]] || die "Pair trace is missing: $pair_id-$variant"
            [[ "$(hash_file "$trace_path")" == "$(jq -r --arg id "$pair_id" --arg variant "$variant" '.pairs[] | select(.pair_id == $id) | .[$variant].trace_sha256' "$packet")" ]] \
                || die "Pair trace hash mismatch: $pair_id-$variant"
            jq -e --arg id "$pair_id" --arg variant "$variant" --slurpfile packet "$packet" '
              ($packet[0].pairs[] | select(.pair_id == $id)) as $pair
              | .pair_id == $pair.pair_id
              and .case_id == $pair.case_id
              and .trial_index == $pair.trial_index
              and .variant == $variant
              and .provenance.fixture_sha256 == $packet[0].bindings.fixture_sha256
              and .provenance.case_sha256 == $pair.case_sha256
              and .provenance.grader_sha256 == $pair.grader_sha256
              and .provenance.seed_workspace_sha256 == $pair.seed_workspace_sha256
              and .provenance.instruction_sha256 == (
                if $variant == "baseline" then $pair.bindings.baseline_instruction_sha256
                else $pair.bindings.candidate_instruction_sha256 end)
            ' "$trace_path" >/dev/null || die "Pair trace provenance mismatch: $pair_id-$variant"
        done
    done < <(jq -r '.pairs[] | [.pair_id,.pair_sha256] | @tsv' "$packet")

    local automatic semantic_approved trusted_profile eligible failed='[]'
    automatic="$(jq -r '.automatic_behavioral_gates_passed == true' "$comparison")"
    semantic_approved="$(jq -r '.overall_verdict == "approved" and all(.pair_verdicts[]; .verdict == "approved") and all(.pair_verdicts[].candidate_findings[]; .verdict == "supported")' "$VERDICT_FILE")"
    if trusted_execution_profile_passes "$plan" "$RESULTS_DIR/traces"; then trusted_profile=true; else trusted_profile=false; fi
    [[ "$automatic" == true ]] || failed="$(jq -c '. + ["pilot_coverage_or_automatic_gates"]' <<<"$failed")"
    [[ "$semantic_approved" == true ]] || failed="$(jq -c '. + ["semantic_review_not_approved"]' <<<"$failed")"
    [[ "$trusted_profile" == true ]] || failed="$(jq -c '. + ["untrusted_execution_profile"]' <<<"$failed")"
    if [[ "$automatic" == true && "$semantic_approved" == true && "$trusted_profile" == true ]]; then eligible=true; else eligible=false; fi

    jq -cS . "$VERDICT_FILE" | atomic_write_json "$semantic_artifact"
    jq -n \
      --arg candidate_manifest_sha256 "$current_manifest_hash" \
      --arg candidate_instruction_sha256 "$current_instruction_hash" \
      --arg context_budget_evidence_sha256 "$CURRENT_CONTEXT_BUDGET_EVIDENCE_HASH" \
      --arg review_packet_sha256 "$(hash_file "$packet")" \
      --arg semantic_verdict_sha256 "$(hash_file "$semantic_artifact")" \
      --arg trace_set_sha256 "$current_trace_set_hash" \
      --arg semantic_status "$(if [[ "$semantic_approved" == true ]]; then echo approved; else echo rejected; fi)" \
      --argjson automatic "$automatic" --argjson trusted_profile "$trusted_profile" --argjson eligible "$eligible" --argjson failed "$failed" \
      --argjson pair_hashes "$(jq '[.pairs[].pair_sha256]' "$packet")" \
      --argjson reviewed_pairs "$(jq '.pair_verdicts | length' "$VERDICT_FILE")" \
      --argjson reviewed_findings "$(jq '[.pair_verdicts[].candidate_findings[]] | length' "$VERDICT_FILE")" '
      {
        schema_version:"1.0",decision_kind:"workflow_kernel_behavioral_promotion",
        bindings:{candidate_manifest_sha256:$candidate_manifest_sha256,candidate_instruction_sha256:$candidate_instruction_sha256,context_budget_evidence_sha256:$context_budget_evidence_sha256,review_packet_sha256:$review_packet_sha256,semantic_verdict_sha256:$semantic_verdict_sha256,trace_set_sha256:$trace_set_sha256,pair_sha256:$pair_hashes},
        automatic_behavioral_gates_passed:$automatic,
        trusted_execution_profile_passed:$trusted_profile,
        semantic_false_positive_review:{status:$semantic_status,reviewed_pairs:$reviewed_pairs,reviewed_candidate_findings:$reviewed_findings},
        failed_gates:$failed,behavioral_promotion_eligible:$eligible
      }
    ' | atomic_write_json "$decision_artifact"
    [[ "$eligible" == true ]] || exit 2
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --results) RESULTS_DIR="$2"; shift 2 ;;
        --baseline-variant) BASELINE_VARIANT="$2"; shift 2 ;;
        --candidate-variant) CANDIDATE_VARIANT="$2"; shift 2 ;;
        --verdict) VERDICT_FILE="$2"; shift 2 ;;
        --write-verdict-template) TEMPLATE_FILE="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
done

command -v jq >/dev/null 2>&1 || die "jq is required."
[[ -d "$RESULTS_DIR" && ! -L "$RESULTS_DIR" ]] || die "--results must be a real directory."
[[ -n "$BASELINE_VARIANT" ]] || BASELINE_VARIANT="$REPO_ROOT/skills/assistant-workflow"
[[ -n "$CANDIDATE_VARIANT" ]] || CANDIDATE_VARIANT="$REPO_ROOT/docs/evals/variants/workflow-kernel-v1"
packet="$RESULTS_DIR/semantic-review-packet.json"
if [[ -n "$TEMPLATE_FILE" ]]; then
    [[ -z "$VERDICT_FILE" ]] || die "Template mode does not accept --verdict."
    write_template "$packet" "$TEMPLATE_FILE"
else
    [[ -n "$VERDICT_FILE" && -f "$VERDICT_FILE" ]] || die "Finalization requires --verdict."
    finalize
fi
