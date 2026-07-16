#!/usr/bin/env bash
# Blind, paired Codex execution adapter for framework instruction evals.

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/context-budget-evidence.sh"
FIXTURE="$REPO_ROOT/docs/evals/framework-instruction-cases.json"
SYNTHETIC_FIXTURE_REF="docs/evals/fixtures/seeded-code-review-regressions"
SYNTHETIC_FIXTURE_DIR="$REPO_ROOT/$SYNTHETIC_FIXTURE_REF"
ADAPTER_VERSION="codex-framework-eval-v5"
MODE="plan"
RESUME=false
MODEL="gpt-5.6-sol"
BASELINE_VARIANT=""
CANDIDATE_VARIANT=""
CANDIDATE_MANIFEST=""
CANDIDATE_MANIFEST_HASH=""
CASES="all"
REPEATS=1
RUN_TIMEOUT_SECONDS=600
TOTAL_TIMEOUT_SECONDS=5400
MODEL_CATALOG_TIMEOUT_SECONDS=30
OUTPUT_DIR=""
CODEX_BIN="codex"
CODEX_BIN_OVERRIDDEN=false
CODEX_EXECUTABLE_SHA256=""
CLI_VERSION=""
MODEL_SELECTION_METHOD="not_checked_plan_mode"
MODEL_CATALOG_SOURCE="none"
MODEL_CATALOG_STATUS="not_checked"
MODEL_CATALOG_ENTRY_SHA256=""
RAW_ROOT=""
WORK_ROOT=""
CONTEXT_BUDGET_EVIDENCE_FILE=""
CONTEXT_BUDGET_EVIDENCE_HASH=""
RUN_PLAN_HASH=""
ACTIVE_CHILD_PID=""
ACTIVE_CHILD_GRACE_SECONDS=5
EVALUATION_STARTED_AT=0
MAX_INCOMPLETE_PAIRS=1
FAILURE_DIAGNOSTIC_MAX_BYTES=4194304

usage() {
    cat <<'EOF'
Usage:
  run-codex-framework-evals.sh [--execute] \
    --baseline-variant DIR --candidate-variant DIR --output DIR [options]

The default mode writes a run plan and does not invoke Codex. --execute is the
explicit opt-in for model execution. Existing local Codex authentication is
used; this runner never accepts API keys or credential values.

Required:
  --baseline-variant DIR  Baseline assistant-workflow skill directory or repo root.
  --candidate-variant DIR Candidate assistant-workflow skill directory or repo root.
  --output DIR            Empty/new directory for redacted results.

Options:
  --execute               Execute the planned paired trials with Codex.
  --resume                Resume only after exact validation; uncertain in-flight runs block.
  --model MODEL           Requested Codex model (default: gpt-5.6-sol).
  --cases IDS             Comma-separated case IDs, or all (default: all).
  --repeats N             Exact paired trials per case, 1-20 (default: 1).
  --run-timeout-seconds N Per-run Codex timeout, 1-3600 (default: 600).
  --total-timeout-seconds N Total execution cap, 1-21600 (default: 5400).
  --model-catalog-timeout-seconds N Catalog lookup cap, 1-120 (default: 30).
  --codex-bin PATH        Codex executable override, useful for offline tests.
  -h, --help              Show this help.

Execution uses an isolated temporary workspace, workspace-write sandboxing
confined to that disposable fixture, JSONL events, and a blind runtime prompt.
Raw events and final responses live only in mode-0700 temporary storage and are
deleted by default.
EOF
}

die() {
    echo "Error: $1" >&2
    exit 1
}

require_jq() {
    command -v jq >/dev/null 2>&1 || die "jq is required."
}

hash_stream() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    else
        die "sha256sum or shasum is required."
    fi
}

hash_file() {
    local path="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$path" | awk '{print $1}'
    else
        shasum -a 256 "$path" | awk '{print $1}'
    fi
}

hash_text() {
    printf '%s' "$1" | hash_stream
}

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

prepare_model_selection_evidence() {
    [[ "$MODE" == "execute" ]] || return 0

    if [[ "$CODEX_BIN" == */* ]]; then
        if [[ -x "$CODEX_BIN" ]]; then
            CODEX_BIN="$(cd "$(dirname "$CODEX_BIN")" && pwd -P)/$(basename "$CODEX_BIN")"
            CODEX_EXECUTABLE_SHA256="$(hash_file "$CODEX_BIN")"
            CLI_VERSION="$($CODEX_BIN --version 2>/dev/null || true)"
        else
            CLI_VERSION="unavailable"
        fi
    elif [[ "$CODEX_BIN_OVERRIDDEN" == true ]]; then
        if command -v "$CODEX_BIN" >/dev/null 2>&1; then
            CODEX_BIN="$(command -v "$CODEX_BIN")"
            CODEX_EXECUTABLE_SHA256="$(hash_file "$CODEX_BIN")"
            CLI_VERSION="$($CODEX_BIN --version 2>/dev/null || true)"
        else
            CLI_VERSION="unavailable"
        fi
    else
        command -v "$CODEX_BIN" >/dev/null 2>&1 \
            || die "Default Codex executable is unavailable before model-catalog attestation."
        CODEX_BIN="$(command -v "$CODEX_BIN")"
        CODEX_EXECUTABLE_SHA256="$(hash_file "$CODEX_BIN")"
        CLI_VERSION="$($CODEX_BIN --version 2>/dev/null || true)"
        [[ -n "$CLI_VERSION" && "$CLI_VERSION" != "unavailable" ]] \
            || die "Default Codex CLI version could not be attested before model execution."

        local selected_entry
        selected_entry="$(read_selected_model_catalog_entry "$CODEX_BIN" "$MODEL" "$MODEL_CATALOG_TIMEOUT_SECONDS")" \
            || die "Default Codex model catalog must contain one valid exact requested-model entry within the bounded lookup: $MODEL"
        MODEL_CATALOG_ENTRY_SHA256="$(printf '%s' "$selected_entry" | hash_stream)"
        selected_entry=""
        MODEL_SELECTION_METHOD="codex_debug_models_requested_entry"
        MODEL_CATALOG_SOURCE="active"
        MODEL_CATALOG_STATUS="present"
        return 0
    fi

    MODEL_SELECTION_METHOD="explicit_model_argument_override"
    MODEL_CATALOG_SOURCE="none"
    MODEL_CATALOG_STATUS="not_checked_override"
}

preflight_macos_seatbelt() {
    [[ "$MODE" == "execute" ]] || return 0
    [[ "$(/usr/bin/uname -s)" == "Darwin" ]] || return 0

    local candidate cli_version
    if [[ "$CODEX_BIN" == */* ]]; then
        [[ -x "$CODEX_BIN" ]] || return 0
        candidate="$CODEX_BIN"
    else
        candidate="$(command -v "$CODEX_BIN" 2>/dev/null || true)"
        [[ -n "$candidate" ]] || return 0
    fi
    cli_version="$($candidate --version 2>/dev/null || true)"
    if [[ "$cli_version" == "codex-cli 9.9.9-test" && -n "${FAKE_CODEX_CAPTURE_DIR:-}" ]]; then
        return 0
    fi

    [[ -x /usr/bin/sandbox-exec ]] \
        || die "The macOS Seatbelt capability probe is unavailable."
    /usr/bin/sandbox-exec -p '(version 1) (allow default)' /usr/bin/true >/dev/null 2>&1 \
        || die "Real Codex execute mode requires host-side execution because this process cannot create the macOS Seatbelt sandbox required by --sandbox workspace-write. No model runs were started."
}

verify_model_selection_evidence_unchanged() {
    [[ "$MODE" == "execute" && "$CODEX_BIN_OVERRIDDEN" == false ]] || return 0
    local current_cli_version current_executable_hash current_entry_hash selected_entry catalog_timeout remaining_total now
    current_cli_version="$($CODEX_BIN --version 2>/dev/null || true)"
    current_executable_hash="$(hash_file "$CODEX_BIN")"
    now="$(date +%s)"
    remaining_total=$((TOTAL_TIMEOUT_SECONDS - (now - EVALUATION_STARTED_AT)))
    [[ "$remaining_total" -gt 0 ]] || die "Total evaluation time cap was reached before model-catalog recheck."
    catalog_timeout="$MODEL_CATALOG_TIMEOUT_SECONDS"
    if [[ "$remaining_total" -lt "$catalog_timeout" ]]; then catalog_timeout="$remaining_total"; fi
    selected_entry="$(read_selected_model_catalog_entry "$CODEX_BIN" "$MODEL" "$catalog_timeout")" \
        || die "Default Codex model catalog lost exact requested-model identity within the bounded recheck: $MODEL"
    current_entry_hash="$(printf '%s' "$selected_entry" | hash_stream)"
    selected_entry=""
    [[ "$current_cli_version" == "$CLI_VERSION" \
        && "$current_executable_hash" == "$CODEX_EXECUTABLE_SHA256" \
        && "$current_entry_hash" == "$MODEL_CATALOG_ENTRY_SHA256" ]] \
        || die "Default Codex model-selection evidence drifted during execution."
}

enforce_incomplete_pair_breaker() {
    [[ -d "$OUTPUT_DIR/traces" ]] || return 0
    find "$OUTPUT_DIR/traces" -maxdepth 1 -type f -name '*.json' -print -quit | grep -q . || return 0
    local incomplete_pairs max_incomplete_pairs="$MAX_INCOMPLETE_PAIRS"
    if [[ -f "$OUTPUT_DIR/run-plan.json" ]]; then
        max_incomplete_pairs="$(jq -r '.max_incomplete_pairs' "$OUTPUT_DIR/run-plan.json")"
    fi
    incomplete_pairs="$(jq -s '
      group_by(.pair_id)
      | map(select(length == 2 and any(.[]; .status != "completed")))
      | length
    ' "$OUTPUT_DIR"/traces/*.json)"
    [[ "$max_incomplete_pairs" =~ ^[0-9]+$ && "$incomplete_pairs" -le "$max_incomplete_pairs" ]] \
        || die "Stopped after $incomplete_pairs incomplete pairs; remaining authorized runs stay not_started."
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

fsync_path() {
    local path="$1"
    command -v python3 >/dev/null 2>&1 || die "python3 is required for crash-durable execute evidence."
    python3 - "$path" <<'PY'
import os
import sys

path = sys.argv[1]
flags = os.O_RDONLY
if os.path.isdir(path) and hasattr(os, "O_DIRECTORY"):
    flags |= os.O_DIRECTORY
handle = os.open(path, flags)
try:
    os.fsync(handle)
finally:
    os.close(handle)
PY
}

durable_atomic_write_json() {
    local destination="$1" directory base temporary
    directory="$(dirname "$destination")"
    base="$(basename "$destination")"
    temporary="$(mktemp "$directory/.$base.tmp.XXXXXX")" || return 1
    if ! tee "$temporary" >/dev/null || ! jq empty "$temporary" >/dev/null 2>&1 \
        || ! fsync_path "$temporary"; then
        rm -f "$temporary"
        return 1
    fi
    mv -f "$temporary" "$destination"
    fsync_path "$directory"
}

write_run_attempt_not_started() {
    local path="$1" pair_id="$2" case_id="$3" trial_index="$4" variant="$5"
    local run_id="$pair_id-$variant"
    jq -cnS \
        --arg run_id "$run_id" --arg pair_id "$pair_id" --arg case_id "$case_id" \
        --arg variant "$variant" --arg run_plan_sha256 "$RUN_PLAN_HASH" \
        --argjson trial_index "$trial_index" '
      {
        schema_version:"1.0",run_id:$run_id,pair_id:$pair_id,case_id:$case_id,
        trial_index:$trial_index,variant:$variant,run_plan_sha256:$run_plan_sha256,
        state:"not_started",attempt_started_at:[],completed_at:null
      }
    ' | durable_atomic_write_json "$path"
}

write_run_attempt_in_flight() {
    local path="$1" started_at
    started_at="$(date +%s)"
    jq -cS --argjson started_at "$started_at" '
      .state = "in_flight"
      | .attempt_started_at += [$started_at]
      | .completed_at = null
    ' "$path" | durable_atomic_write_json "$path"
}

mark_run_attempt_completed() {
    local path="$1" completed_at
    completed_at="$(date +%s)"
    jq -cS --argjson completed_at "$completed_at" '
      .state = "completed" | .completed_at = $completed_at
    ' "$path" | durable_atomic_write_json "$path"
}

validate_run_attempt_identity() {
    local path="$1" pair_id="$2" case_id="$3" trial_index="$4" variant="$5"
    jq -e \
      --arg run_id "$pair_id-$variant" --arg pair_id "$pair_id" --arg case_id "$case_id" \
      --arg variant "$variant" --arg run_plan_sha256 "$RUN_PLAN_HASH" \
      --argjson trial_index "$trial_index" '
      . as $record
      | (keys_unsorted | sort) == (["attempt_started_at","case_id","completed_at","pair_id","run_id","run_plan_sha256","schema_version","state","trial_index","variant"] | sort)
      and .schema_version == "1.0"
      and .run_id == $run_id and .pair_id == $pair_id and .case_id == $case_id
      and .trial_index == $trial_index and .variant == $variant
      and .run_plan_sha256 == $run_plan_sha256
      and (.state == "not_started" or .state == "in_flight" or .state == "completed")
      and (.attempt_started_at | type == "array"
        and all(.[]; type == "number" and . == floor and . > 0))
      and (if .state == "not_started" then
          (.attempt_started_at | length) == 0 and .completed_at == null
        elif .state == "in_flight" then
          (.attempt_started_at | length) >= 1 and .completed_at == null
        else
          ($record.completed_at | type == "number" and . == floor and . > 0)
          and ((.attempt_started_at | length) == 0
            or $record.completed_at >= ($record.attempt_started_at | last))
        end)
    ' "$path" >/dev/null
}

initialize_run_attempts() {
    local pair_id case_id trial_index variant path
    while IFS=$'\t' read -r pair_id case_id trial_index variant; do
        path="$OUTPUT_DIR/run-attempts/$pair_id-$variant.json"
        [[ ! -e "$path" ]] || die "Run-attempt state already exists before initialization: $pair_id-$variant"
        write_run_attempt_not_started "$path" "$pair_id" "$case_id" "$trial_index" "$variant" \
            || die "Could not initialize run-attempt state for $pair_id-$variant."
    done < <(jq -r '.runs[] | [.pair_id,.case_id,.trial_index,.variant] | @tsv' "$OUTPUT_DIR/run-plan.json")
}

resolve_overlay_file() {
    local supplied="$1"
    local resolved overlay
    if [[ -f "$supplied/SKILL.md" ]]; then
        resolved="$(cd "$supplied" && pwd)"
        overlay="$resolved/SKILL.md"
    elif [[ -f "$supplied/skills/assistant-workflow/SKILL.md" ]]; then
        resolved="$(cd "$supplied/skills/assistant-workflow" && pwd)"
        overlay="$resolved/SKILL.md"
    else
        die "Variant must contain SKILL.md directly or skills/assistant-workflow/SKILL.md: $supplied"
    fi
    if find "$resolved" ! -type d ! -type f -print -quit | grep -q .; then
        die "Variant directories may contain only regular files and directories: $supplied"
    fi
    printf '%s\n' "$overlay"
}

materialize_variant() {
    local overlay_file="$1"
    local destination="$2"
    local entry
    mkdir -p "$destination"
    while IFS= read -r entry; do
        cp -R "$entry" "$destination/"
    done < <(find "$REPO_ROOT/skills/assistant-workflow" -mindepth 1 -maxdepth 1 ! -name evals -print | LC_ALL=C sort)
    cp "$overlay_file" "$destination/SKILL.md"
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

hash_directory() {
    local directory="$1"
    local inventory=""
    local file relative digest
    while IFS= read -r file; do
        relative="${file#"$directory"/}"
        digest="$(hash_file "$file")"
        inventory+="$relative $digest"$'\n'
    done < <(find "$directory" -type f -print | LC_ALL=C sort)
    hash_text "$inventory"
}

cleanup_raw_root() {
    if [[ -n "$RAW_ROOT" && -d "$RAW_ROOT" ]]; then
        rm -rf "$RAW_ROOT"
    fi
}

terminate_active_child() {
    local pid="${ACTIVE_CHILD_PID:-}" remaining
    [[ -n "$pid" ]] || return 0
    if kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null || true
        remaining=$((ACTIVE_CHILD_GRACE_SECONDS * 10))
        while [[ "$remaining" -gt 0 ]] && kill -0 "$pid" 2>/dev/null; do
            sleep 0.1
            remaining=$((remaining - 1))
        done
        if kill -0 "$pid" 2>/dev/null; then
            kill -KILL "$pid" 2>/dev/null || true
        fi
    fi
    wait "$pid" 2>/dev/null || true
    ACTIVE_CHILD_PID=""
}

cleanup_all() {
    terminate_active_child
    cleanup_raw_root
    if [[ -n "$WORK_ROOT" && -d "$WORK_ROOT" ]]; then
        rm -rf "$WORK_ROOT"
    fi
}

handle_signal() {
    local exit_code="$1"
    cleanup_all
    trap - EXIT INT TERM
    exit "$exit_code"
}

case_exists() {
    local case_id="$1"
    jq -e --arg id "$case_id" 'any(.cases[]; .id == $id)' "$FIXTURE" >/dev/null
}

validate_candidate_manifest() {
    [[ -n "$CANDIDATE_MANIFEST" ]] || return 0
    jq -e '
      .schema_version == "1.0"
      and .variant == "workflow-kernel-v1"
      and .promotion_gates.must_pass_case_regressions_allowed == 0
      and .promotion_gates.seeded_defect_recall_must_not_drop == true
      and .promotion_gates.false_positive_marker_hits_must_not_increase == true
      and .promotion_gates.question_mark_count_proxy_must_not_increase == true
      and .promotion_gates.median_rework_or_tool_calls_max_regression_percent == 20
      and .promotion_gates.semantic_false_positive_review_required == true
      and .promotion_gates.selected_initial_words_max == 1000
      and .promotion_gates.selected_entry_words_max == 2600
      and .promotion_gates.standing_context_growth_allowed == false
      and (.static_measurement.baseline_selected_initial_words | type == "number" and . >= 1 and . == floor)
      and (.static_measurement.candidate_selected_initial_words | type == "number" and . >= 1 and . == floor)
      and (.static_measurement.baseline_total_initial_words | type == "number" and . >= 1 and . == floor)
      and (.static_measurement.candidate_total_initial_words | type == "number" and . >= 1 and . == floor)
      and (.static_measurement.baseline_selected_entry_words | type == "number" and . >= 1 and . == floor)
      and (.static_measurement.candidate_selected_entry_words | type == "number" and . >= 1 and . == floor)
      and .static_measurement.candidate_selected_initial_words <= .promotion_gates.selected_initial_words_max
      and .static_measurement.candidate_selected_entry_words <= .promotion_gates.selected_entry_words_max
      and .static_measurement.selected_initial_word_delta == (.static_measurement.candidate_selected_initial_words - .static_measurement.baseline_selected_initial_words)
      and .static_measurement.selected_entry_word_delta == (.static_measurement.candidate_selected_entry_words - .static_measurement.baseline_selected_entry_words)
      and .static_measurement.candidate_total_initial_words - .static_measurement.baseline_total_initial_words == .static_measurement.selected_initial_word_delta
      and .static_measurement.standing_context_growth == 0
      and .semantic_review.case_category == "seeded_review"
      and .semantic_review.data_classification == "synthetic"
      and .semantic_review.max_findings_per_run == 8
      and .semantic_review.unclassified_finding_policy == "block"
      and .semantic_review.raw_response_retained == false
      and .smoke_cases == ["small-fix-stays-lightweight","seeded-code-review-regressions"]
      and .pilot_cases == ["small-fix-stays-lightweight","stale-journal-yields-to-current-evidence","requirements-map-through-completion","ordinary-medium-bounded-executor","seeded-code-review-regressions","medium-final-handoff-is-reconstructable"]
      and .smoke_repeats == 1
      and .pilot_repeats == 3
    ' "$CANDIDATE_MANIFEST" >/dev/null \
        || die "Candidate manifest does not match the supported workflow-kernel-v1 promotion contract."
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

selected_case_ids() {
    if [[ "$CASES" == "all" ]]; then
        jq -r '.cases[].id' "$FIXTURE"
        return
    fi

    local raw_id case_id seen_ids=","
    IFS=',' read -r -a requested_cases <<<"$CASES"
    for raw_id in "${requested_cases[@]}"; do
        case_id="$(printf '%s' "$raw_id" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -n "$case_id" ]] || die "--cases contains an empty case ID."
        case_exists "$case_id" || die "Unknown case ID: $case_id"
        [[ "$seen_ids" != *",$case_id,"* ]] || die "--cases contains duplicate case ID: $case_id"
        seen_ids+="$case_id,"
        printf '%s\n' "$case_id"
    done
}

blind_prompt_for_case() {
    local case_id="$1"
    jq -r --arg id "$case_id" '
      .cases[]
      | select(.id == $id)
      | "# Evaluation context\n"
        + (.setup_context | map("- " + .) | join("\n"))
        + "\n\n# User request\n\n"
        + .prompt
    ' "$FIXTURE"
}

case_hash() {
    local case_id="$1"
    jq -cS --arg id "$case_id" '.cases[] | select(.id == $id)' "$FIXTURE" | hash_stream
}

grader_hash() {
    local case_id="$1"
    local contract_hash runner_hash
    contract_hash="$(jq -cS --arg id "$case_id" '
      .cases[] | select(.id == $id) | {fail_signals, machine_expectations, semantic_review}
    ' "$FIXTURE" | hash_stream)"
    runner_hash="$(hash_file "${BASH_SOURCE[0]}")"
    printf 'contract_sha256=%s\nrunner_sha256=%s\n' "$contract_hash" "$runner_hash" | hash_stream
}

hash_seed_workspace() {
    local workspace="$1"
    local inventory=""
    local file relative digest
    while IFS= read -r file; do
        relative="${file#"$workspace"/}"
        digest="$(hash_file "$file")"
        inventory+="$relative $digest"$'\n'
    done < <(find "$workspace" -type f \
        ! -path "$workspace/.agents/*" \
        ! -path "$workspace/.git/*" \
        -print | LC_ALL=C sort)
    hash_text "$inventory"
}

is_synthetic_seeded_case() {
    local case_id="$1"
    jq -e --arg id "$case_id" '
      any(.cases[];
        .id == $id
        and .category == "seeded_review"
        and .data_classification == "synthetic"
        and (.semantic_review | type == "object"))
    ' "$FIXTURE" >/dev/null
}

write_blocked_semantic_extract() {
    local path="$1"
    local variant="$2"
    local reason_code="$3"
    jq -n --arg variant "$variant" --arg reason_code "$reason_code" \
        '{status:"blocked",variant:$variant,reason_code:$reason_code,findings:[],finding_failures:[]}' >"$path"
}

normalize_semantic_response() {
    local case_id="$1"
    local variant="$2"
    local response_path="$3"
    local extract_path="$4"
    local max_findings
    max_findings="$(jq -r --arg id "$case_id" '.cases[] | select(.id == $id) | .semantic_review.max_findings' "$FIXTURE")"

    if [[ ! -s "$response_path" ]] \
        || [[ "$(wc -c <"$response_path" | tr -d ' ')" -gt 16384 ]] \
        || ! jq -e --argjson max "$max_findings" --arg id "$case_id" --slurpfile fixture "$FIXTURE" '
          ($fixture[0].cases[] | select(.id == $id)) as $case
          | type == "object"
          and (keys_unsorted | sort) == ["findings"]
          and (.findings | type == "array" and length <= $max)
          and all(.findings[];
            type == "object"
            and (keys_unsorted | sort) == ["line", "severity", "source", "summary"]
            and (.severity == "P0" or .severity == "P1" or .severity == "P2" or .severity == "P3")
            and (.source as $source | ($source | type == "string") and ($case.semantic_review.allowed_sources | index($source)) != null)
            and (.line | type == "number" and . >= 1 and . <= 100000 and . == floor)
            and (.summary | type == "string" and length >= 1 and length <= 240 and (test("[\\r\\n]") | not)))
        ' "$response_path" >/dev/null 2>&1; then
        write_blocked_semantic_extract "$extract_path" "$variant" malformed_finding_payload
        return
    fi

    if jq -e 'any(.findings[].summary;
          explode | any(. < 32 or . > 126 or . == 47 or . == 92))' \
            "$response_path" >/dev/null \
        || jq -r '.findings[].summary' "$response_path" \
            | grep -Eqi '(^|[^[:alnum:]])(sk-[[:alnum:]_-]{8,}|ghp_[[:alnum:]_]{8,}|AKIA[[:alnum:]]{8,}|api[_-]?key|password|secret|bearer[[:space:]]+[[:alnum:]_.-]+|https?://|file://|/Users/|/home/|[A-Za-z]:\\|[[:alnum:]._%+-]+@[[:alnum:].-]+\\.[A-Za-z]{2,})([^[:alnum:]]|$)'; then
        write_blocked_semantic_extract "$extract_path" "$variant" unsafe_finding_content
        return
    fi

    local normalized
    normalized="$(jq -c --arg id "$case_id" --arg variant "$variant" --slurpfile fixture "$FIXTURE" '
      ($fixture[0].cases[] | select(.id == $id)) as $case
      | [
          .findings
          | to_entries[]
          | .key as $index
          | .value as $finding
          | [
              $case.semantic_review.claim_rules[]
              | select(.sources | index($finding.source) != null)
              | select([.detection_anchor_groups[]
                  | [.[] | ascii_downcase as $anchor
                    | ($finding.summary | ascii_downcase | contains($anchor))]
                  | any] | all)
            ] as $matches
          | {
              finding_id: ($variant + "-" + (if ($index + 1) < 10 then "0" else "" end) + (($index + 1) | tostring)),
              match_count: ($matches | length),
              finding: (if ($matches | length) == 1 then {
                finding_id: ($variant + "-" + (if ($index + 1) < 10 then "0" else "" end) + (($index + 1) | tostring)),
                severity: $finding.severity,
                source: $finding.source,
                line: $finding.line,
                claim_code: $matches[0].claim_code,
                normalized_claim: $matches[0].normalized_claim,
                review_summary: $finding.summary
              } else null end)
            }
        ] as $classifications
      | [$classifications[] | .finding | select(. != null)] as $normalized
      | [$classifications[] | select(.finding == null) | {
          finding_id,
          reason_code:(if .match_count == 0 then "no_claim_rule_match" else "multiple_claim_rule_matches" end)
        }] as $failures
      | if ($failures | length) > 0 then
          {status:"blocked",variant:$variant,reason_code:"unclassified_finding",findings:$normalized,finding_failures:$failures}
        else
          {status:"ready",variant:$variant,reason_code:null,findings:$normalized,finding_failures:[]}
        end
    ' "$response_path")"
    printf '%s\n' "$normalized" >"$extract_path"
}

validate_semantic_extract() {
    local extract="$1" expected_variant="$2"
    jq -e --arg variant "$expected_variant" '
      (keys_unsorted | sort) == (["finding_failures","findings","reason_code","status","variant"] | sort)
      and .variant == $variant
      and (.status == "ready" or .status == "blocked")
      and ((.status == "ready" and .reason_code == null and .finding_failures == [])
        or (.status == "blocked" and (.reason_code == "malformed_finding_payload"
          or .reason_code == "unsafe_finding_content" or .reason_code == "unclassified_finding")))
      and (.findings | type == "array" and length <= 8)
      and all(.findings[]; . as $finding
        | (keys_unsorted | sort) == (["claim_code","finding_id","line","normalized_claim","review_summary","severity","source"] | sort)
        and (.finding_id | test("^(baseline|candidate)-[0-9]{2}$"))
        and (.finding_id | startswith($variant + "-"))
        and (.severity == "P0" or .severity == "P1" or .severity == "P2" or .severity == "P3")
        and (.source == "REQUIREMENTS.md" or .source == "src/order.js" or .source == "tests/order.test.js")
        and (["missing_preferred_discount","mutates_input_order","negative_quantity_not_rejected","test_has_no_behavioral_assertion","unrelated_authentication_issue","unrelated_database_migration_issue"] | index($finding.claim_code) != null)
        and (["Preferred-customer discount is absent.","Calculation mutates the input order.","Negative quantity is not rejected.","The test has no behavioral assertion.","An authentication issue was claimed.","A database migration issue was claimed."] | index($finding.normalized_claim) != null)
        and (.line | type == "number" and . >= 1 and . <= 100000 and . == floor)
        and (.review_summary | type == "string" and length >= 1 and length <= 240 and (test("[\\r\\n]") | not))
        and (.review_summary | explode | all(. >= 32 and . <= 126 and . != 47 and . != 92)))
      and (.finding_failures | type == "array" and length <= 8)
      and all(.finding_failures[];
        (keys_unsorted | sort) == (["finding_id","reason_code"] | sort)
        and (.finding_id | test("^(baseline|candidate)-[0-9]{2}$"))
        and (.reason_code == "no_claim_rule_match" or .reason_code == "multiple_claim_rule_matches"))
    ' "$extract" >/dev/null
}

write_semantic_checkpoint() {
    local checkpoint_path="$1" pair_id="$2" case_id="$3" trial_index="$4" variant="$5"
    local trace_draft="$6" extract="$7"
    validate_semantic_extract "$extract" "$variant" || return 1
    jq -cnS \
      --arg pair_id "$pair_id" --arg case_id "$case_id" --arg variant "$variant" \
      --argjson trial_index "$trial_index" --slurpfile trace "$trace_draft" --slurpfile extract "$extract" '
      {
        schema_version:"1.0",pair_id:$pair_id,case_id:$case_id,trial_index:$trial_index,variant:$variant,
        trace_draft:$trace[0],semantic_extract:$extract[0]
      }
    ' | durable_atomic_write_json "$checkpoint_path"
}

pair_id_for() {
    local case_id="$1"
    local trial_index="$2"
    local digest
    digest="$(hash_text "case=$case_id;trial=$trial_index")"
    printf '%s-%s-%s\n' "$case_id" "$trial_index" "${digest:0:12}"
}

write_plan() {
    local baseline_hash="$1"
    local candidate_hash="$2"
    local fixture_hash="$3"
    local destination="${4:-$OUTPUT_DIR/run-plan.json}"
    local runs_file
    runs_file="$(mktemp "${TMPDIR:-/tmp}/codex-eval-plan-runs.XXXXXX")"
    trap 'rm -f "$runs_file"' RETURN

    local case_id trial pair_id variant instruction_dir instruction_hash execution_order execution_position pair_counter=0
    while IFS= read -r case_id; do
        for ((trial = 1; trial <= REPEATS; trial++)); do
            pair_counter=$((pair_counter + 1))
            pair_id="$(pair_id_for "$case_id" "$trial")"
            if (( pair_counter % 2 == 1 )); then
                execution_order="baseline_first"
                variants=(baseline candidate)
            else
                execution_order="candidate_first"
                variants=(candidate baseline)
            fi
            execution_position=0
            for variant in "${variants[@]}"; do
                execution_position=$((execution_position + 1))
                if [[ "$variant" == "baseline" ]]; then
                    instruction_dir="$baseline_dir"
                    instruction_hash="$baseline_hash"
                else
                    instruction_dir="$candidate_dir"
                    instruction_hash="$candidate_hash"
                fi
                jq -cn \
                    --arg pair_id "$pair_id" \
                    --arg case_id "$case_id" \
                    --arg variant "$variant" \
                    --arg execution_order "$execution_order" \
                    --arg instruction_sha256 "$instruction_hash" \
                    --argjson trial_index "$trial" \
                    --argjson execution_position "$execution_position" \
                    '{
                      pair_id: $pair_id,
                      case_id: $case_id,
                      trial_index: $trial_index,
                      variant: $variant,
                      execution_order: $execution_order,
                      execution_position: $execution_position,
                      instruction_sha256: $instruction_sha256
                    }' >>"$runs_file"
            done
        done
    done < <(selected_case_ids)

    jq -s \
        --arg mode "$MODE" \
        --arg requested_model "$MODEL" \
        --arg codex_binary_source "$(if [[ "$CODEX_BIN_OVERRIDDEN" == true ]]; then echo override; else echo default; fi)" \
        --arg model_selection_method "$MODEL_SELECTION_METHOD" \
        --arg model_catalog_source "$MODEL_CATALOG_SOURCE" \
        --arg model_catalog_status "$MODEL_CATALOG_STATUS" \
        --arg requested_model_catalog_entry_sha256 "$MODEL_CATALOG_ENTRY_SHA256" \
        --arg codex_executable_sha256 "$CODEX_EXECUTABLE_SHA256" \
        --arg cli_version "$CLI_VERSION" \
        --arg fixture_sha256 "$fixture_hash" \
        --arg baseline_sha256 "$baseline_hash" \
        --arg candidate_sha256 "$candidate_hash" \
        --arg candidate_manifest_sha256 "$CANDIDATE_MANIFEST_HASH" \
        --arg context_budget_evidence_sha256 "$CONTEXT_BUDGET_EVIDENCE_HASH" \
        --slurpfile context_budget_evidence "$CONTEXT_BUDGET_EVIDENCE_FILE" \
        --argjson repeats "$REPEATS" \
        --argjson run_timeout_seconds "$RUN_TIMEOUT_SECONDS" \
        --argjson total_timeout_seconds "$TOTAL_TIMEOUT_SECONDS" \
        --argjson model_catalog_timeout_seconds "$MODEL_CATALOG_TIMEOUT_SECONDS" '
      {
        schema_version: "1.0",
        mode: $mode,
        requested_model: $requested_model,
        model_selection_evidence: {
          method:$model_selection_method,
          catalog_source:$model_catalog_source,
          runtime_model_attestation:"not_exposed_by_codex_jsonl",
          requested_model_catalog_status:$model_catalog_status
        },
        requested_model_catalog_entry_sha256:(if $requested_model_catalog_entry_sha256 == "" then null else $requested_model_catalog_entry_sha256 end),
        codex_executable_sha256:(if $codex_executable_sha256 == "" then null else $codex_executable_sha256 end),
        cli_version:(if $cli_version == "" then null else $cli_version end),
        execution_profile: {
          mode:$mode,
          codex_binary_source:$codex_binary_source,
          required_promotion_model:"gpt-5.6-terra",
          promotion_profile_eligible:($mode == "execute" and $codex_binary_source == "default" and $requested_model == "gpt-5.6-terra")
        },
        repeats: $repeats,
        run_timeout_seconds: $run_timeout_seconds,
        total_timeout_seconds: $total_timeout_seconds,
        model_catalog_timeout_seconds: $model_catalog_timeout_seconds,
        max_incomplete_pairs: 1,
        fixture_sha256: $fixture_sha256,
        baseline_variant: {instruction_sha256: $baseline_sha256},
        candidate_variant: {instruction_sha256: $candidate_sha256},
        candidate_manifest_sha256: (if $candidate_manifest_sha256 == "" then null else $candidate_manifest_sha256 end),
        context_budget_evidence_sha256: $context_budget_evidence_sha256,
        context_budget_evidence: $context_budget_evidence[0],
        planned_pairs: ([.[].pair_id] | unique | length),
        planned_runs: length,
        runs: .
      }
    ' "$runs_file" | atomic_write_json "$destination"

    rm -f "$runs_file"
    trap - RETURN
}

clean_recognized_resume_temps() {
    local output="$1" expected_plan="$2" file pair_id variant
    for file in "$output"/.run-plan.json.tmp.* "$output"/.comparison.json.tmp.* \
        "$output"/.semantic-review-packet.json.tmp.*; do
        [[ -f "$file" && ! -L "$file" ]] && rm -f "$file"
    done
    while IFS=$'\t' read -r pair_id variant; do
        for file in "$output/traces/.$pair_id-$variant.json.tmp."* \
            "$output/semantic-checkpoints/.$pair_id-$variant.json.tmp."* \
            "$output/run-attempts/.$pair_id-$variant.json.tmp."*; do
            [[ -f "$file" && ! -L "$file" ]] && rm -f "$file"
        done
    done < <(jq -r '.runs[] | [.pair_id,.variant] | @tsv' "$expected_plan")
    return 0
}

validate_trace_identity() {
    local trace="$1" pair_id="$2" case_id="$3" trial_index="$4" variant="$5" instruction_hash="$6"
    jq -e \
      --arg pair_id "$pair_id" --arg case_id "$case_id" --arg variant "$variant" \
      --arg instruction_sha256 "$instruction_hash" --arg fixture_sha256 "$fixture_hash" \
      --arg case_sha256 "$(case_hash "$case_id")" --arg grader_sha256 "$(grader_hash "$case_id")" \
      --arg requested_model "$MODEL" --arg adapter_version "$ADAPTER_VERSION" \
      --arg model_selection_evidence "$(if [[ "$MODEL_SELECTION_METHOD" == "codex_debug_models_requested_entry" ]]; then echo catalog_entry_and_explicit_model_argument; else echo explicit_model_argument_only; fi)" \
      --arg requested_model_catalog_entry_sha256 "$MODEL_CATALOG_ENTRY_SHA256" \
      --arg codex_executable_sha256 "$CODEX_EXECUTABLE_SHA256" \
      --arg cli_version "$CLI_VERSION" \
      --argjson trial_index "$trial_index" '
      .pair_id == $pair_id
      and .run_id == ($pair_id + "-" + $variant)
      and .case_id == $case_id
      and .trial_index == $trial_index
      and .variant == $variant
      and (.status == "completed" or .status == "adapter_unavailable")
      and .provenance.fixture_sha256 == $fixture_sha256
      and .provenance.case_sha256 == $case_sha256
      and .provenance.grader_sha256 == $grader_sha256
      and .provenance.instruction_sha256 == $instruction_sha256
      and .model == $requested_model
      and .provenance.requested_model == $requested_model
      and .provenance.adapter_version == $adapter_version
      and .provenance.runtime_model_attestation == "not_exposed_by_codex_jsonl"
      and .provenance.model_selection_evidence == $model_selection_evidence
      and .provenance.requested_model_catalog_entry_sha256 == (if $requested_model_catalog_entry_sha256 == "" then null else $requested_model_catalog_entry_sha256 end)
      and .provenance.codex_executable_sha256 == (if $codex_executable_sha256 == "" then null else $codex_executable_sha256 end)
      and .provenance.cli_version == $cli_version
      and (.provenance | has("resolved_model") | not)
      and .execution.raw_artifacts_retained == false
    ' "$trace" >/dev/null
}

validate_semantic_checkpoint() {
    local checkpoint="$1" pair_id="$2" case_id="$3" trial_index="$4" variant="$5" instruction_hash="$6"
    local extract_file="$WORK_ROOT/checkpoint-extract-$variant.json"
    local draft_file="$WORK_ROOT/checkpoint-trace-$variant.json"
    jq -e \
      --arg pair_id "$pair_id" --arg case_id "$case_id" --arg variant "$variant" \
      --argjson trial_index "$trial_index" '
      (keys_unsorted | sort) == (["case_id","pair_id","schema_version","semantic_extract","trace_draft","trial_index","variant"] | sort)
      and .schema_version == "1.0" and .pair_id == $pair_id and .case_id == $case_id
      and .trial_index == $trial_index and .variant == $variant
      and (.trace_draft | type == "object") and (.semantic_extract | type == "object")
    ' "$checkpoint" >/dev/null || return 1
    jq -cS '.semantic_extract' "$checkpoint" >"$extract_file"
    jq -cS '.trace_draft' "$checkpoint" >"$draft_file"
    validate_semantic_extract "$extract_file" "$variant" \
        && validate_trace_identity "$draft_file" "$pair_id" "$case_id" "$trial_index" "$variant" "$instruction_hash" \
        && jq -e '.status == "completed" and (.execution | has("semantic_checkpoint_sha256") | not)' "$draft_file" >/dev/null
}

validate_resume_output() {
    local expected_plan="$1" entry name pair_id case_id trial_index variant instruction_hash trace checkpoint checkpoint_hash attempt
    local uncertain_file="$WORK_ROOT/uncertain-run-ids.txt" uncertain_ids
    local initialize_attempts=false
    : >"$uncertain_file"
    [[ -d "$OUTPUT_DIR" && ! -L "$OUTPUT_DIR" ]] || die "--resume requires an existing real output directory."
    [[ ! -e "$OUTPUT_DIR/semantic-review-verdict.json" && ! -e "$OUTPUT_DIR/promotion-decision.json" ]] \
        || die "Cannot resume finalized results."
    clean_recognized_resume_temps "$OUTPUT_DIR" "$expected_plan"

    while IFS= read -r entry; do
        name="$(basename "$entry")"
        case "$name" in
            run-plan.json|comparison.json|semantic-review-packet.json) [[ -f "$entry" && ! -L "$entry" ]] || die "Invalid resume artifact: $name" ;;
            traces|semantic-checkpoints|run-attempts) [[ -d "$entry" && ! -L "$entry" ]] || die "Invalid resume directory: $name" ;;
            *) die "Unknown file in resume output: $name" ;;
        esac
    done < <(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort)

    if [[ -f "$OUTPUT_DIR/run-plan.json" ]]; then
        cmp -s "$expected_plan" "$OUTPUT_DIR/run-plan.json" \
            || die "Existing run plan does not exactly match current trusted snapshots and execution inputs."
    else
        find "$OUTPUT_DIR" -mindepth 1 -print -quit | grep -q . \
            && die "Resume output without a run plan contains non-temporary artifacts."
        atomic_write_json "$OUTPUT_DIR/run-plan.json" <"$expected_plan"
        initialize_attempts=true
    fi
    mkdir -p "$OUTPUT_DIR/traces" "$OUTPUT_DIR/semantic-checkpoints" "$OUTPUT_DIR/run-attempts"
    if [[ "$initialize_attempts" == true ]]; then
        initialize_run_attempts
    fi

    for entry in "$OUTPUT_DIR/traces"/* "$OUTPUT_DIR/semantic-checkpoints"/* "$OUTPUT_DIR/run-attempts"/*; do
        [[ -e "$entry" ]] || continue
        [[ -f "$entry" && ! -L "$entry" ]] || die "Resume evidence must contain only regular files."
        name="$(basename "$entry")"
        jq -e --arg name "$name" 'any(.runs[]; ($name == (.pair_id + "-" + .variant + ".json")))' \
            "$expected_plan" >/dev/null || die "Unknown resume evidence file: $name"
    done

    while IFS=$'\t' read -r pair_id case_id trial_index variant instruction_hash; do
        trace="$OUTPUT_DIR/traces/$pair_id-$variant.json"
        checkpoint="$OUTPUT_DIR/semantic-checkpoints/$pair_id-$variant.json"
        attempt="$OUTPUT_DIR/run-attempts/$pair_id-$variant.json"
        if [[ -f "$checkpoint" ]]; then
            is_synthetic_seeded_case "$case_id" || die "Semantic checkpoint exists for a non-seeded case."
            validate_semantic_checkpoint "$checkpoint" "$pair_id" "$case_id" "$trial_index" "$variant" "$instruction_hash" \
                || die "Semantic checkpoint is invalid or tampered: $pair_id-$variant"
            checkpoint_hash="$(hash_file "$checkpoint")"
            if [[ ! -f "$trace" ]]; then
                jq -cS --arg checkpoint_sha256 "$checkpoint_hash" \
                    '.trace_draft | .execution.semantic_checkpoint_sha256 = $checkpoint_sha256' "$checkpoint" \
                    | durable_atomic_write_json "$trace"
            fi
        fi
        if [[ -f "$trace" ]]; then
            validate_trace_identity "$trace" "$pair_id" "$case_id" "$trial_index" "$variant" "$instruction_hash" \
                || die "Existing trace is invalid or does not match the current plan: $pair_id-$variant"
            if is_synthetic_seeded_case "$case_id" && jq -e '.status == "completed"' "$trace" >/dev/null; then
                [[ -f "$checkpoint" ]] || die "Completed seeded trace is missing its bounded semantic checkpoint."
                [[ "$(jq -r '.execution.semantic_checkpoint_sha256 // ""' "$trace")" == "$(hash_file "$checkpoint")" ]] \
                    || die "Trace and semantic checkpoint binding mismatch: $pair_id-$variant"
            else
                jq -e '(.execution | has("semantic_checkpoint_sha256") | not)' "$trace" >/dev/null \
                    || die "Unexpected semantic checkpoint binding: $pair_id-$variant"
            fi
        fi
        [[ -f "$attempt" ]] || die "Run-attempt state is missing: $pair_id-$variant"
        validate_run_attempt_identity "$attempt" "$pair_id" "$case_id" "$trial_index" "$variant" \
            || die "Run-attempt state is invalid or tampered: $pair_id-$variant"
        case "$(jq -r '.state' "$attempt")" in
            completed)
                [[ -f "$trace" ]] || die "Completed run-attempt state is missing its trace: $pair_id-$variant"
                ;;
            in_flight)
                if [[ -f "$trace" ]]; then
                    mark_run_attempt_completed "$attempt" \
                        || die "Could not reconcile completed trace state: $pair_id-$variant"
                else
                    printf '%s\n' "$pair_id-$variant" >>"$uncertain_file"
                fi
                ;;
            not_started)
                [[ ! -f "$trace" ]] || die "Not-started run-attempt state already has a trace: $pair_id-$variant"
                ;;
        esac
    done < <(jq -r '.runs[] | [.pair_id,.case_id,.trial_index,.variant,.instruction_sha256] | @tsv' "$expected_plan")

    if [[ -s "$uncertain_file" ]]; then
        uncertain_ids="$(LC_ALL=C sort -u "$uncertain_file" | paste -sd, -)"
        die "Uncertain in-flight run blocks resume: $uncertain_ids. Separate explicit retry authorization is required."
    fi

    if find "$OUTPUT_DIR/traces" -mindepth 1 -type f -name '*.json' -print -quit | grep -q .; then
        "$REPO_ROOT/tools/evals/run-framework-instruction-evals.sh" --validate-traces "$OUTPUT_DIR/traces" >/dev/null \
            || die "Existing trace set failed strict schema validation."
    fi
}

prepare_semantic_extracts_from_checkpoints() {
    local checkpoint variant pair_id
    mkdir -p "$RAW_ROOT/semantic-extracts"
    for checkpoint in "$OUTPUT_DIR/semantic-checkpoints"/*.json; do
        [[ -f "$checkpoint" ]] || continue
        pair_id="$(jq -r '.pair_id' "$checkpoint")"
        variant="$(jq -r '.variant' "$checkpoint")"
        jq -cS '.semantic_extract' "$checkpoint" >"$RAW_ROOT/semantic-extracts/$pair_id-$variant.json"
    done
}

bounded_error_message() {
    case "$1" in
        codex_not_found) printf '%s\n' 'Codex executable is unavailable.' ;;
        codex_exit_nonzero) printf '%s\n' 'Codex exited non-zero without a recognized structured failure class.' ;;
        codex_reported_failure) printf '%s\n' 'Codex reported a structured execution failure.' ;;
        local_execution_restricted) printf '%s\n' 'Local execution restrictions prevented Codex startup.' ;;
        model_unavailable) printf '%s\n' 'Requested model is unavailable or inaccessible.' ;;
        authentication_failed) printf '%s\n' 'Codex authentication failed.' ;;
        quota_or_rate_limited) printf '%s\n' 'Codex quota or rate limit prevented execution.' ;;
        network_unavailable) printf '%s\n' 'Codex could not reach the model service.' ;;
        configuration_error) printf '%s\n' 'Codex configuration prevented execution.' ;;
        cli_usage_error) printf '%s\n' 'Codex rejected the adapter command shape.' ;;
        unknown_event_shape) printf '%s\n' 'Codex JSONL contained an unknown event shape.' ;;
        missing_usage) printf '%s\n' 'Codex JSONL did not contain completed token usage.' ;;
        missing_final_output) printf '%s\n' 'Codex did not produce a final response.' ;;
        execution_timed_out) printf '%s\n' 'Codex exceeded the bounded per-run timeout.' ;;
        evaluation_time_cap_reached) printf '%s\n' 'The bounded total evaluation time cap was reached.' ;;
        *) die "Internal error: unbounded adapter error code: $1" ;;
    esac
}

classify_codex_failure() {
    local stderr_file="$1"
    local jsonl_file="$2"
    python3 - "$jsonl_file" "$stderr_file" "$FAILURE_DIAGNOSTIC_MAX_BYTES" <<'PY'
import json
import re
import sys

jsonl_path, stderr_path, limit_text = sys.argv[1:]
limit = int(limit_text)
max_structured_event_nesting = 128

patterns = (
    ("model_unavailable", r"unknown model|model[^\r\n]*(not found|not available|unavailable|unsupported|does not exist|no access)|not have access[^\r\n]*model"),
    ("authentication_failed", r"unauthorized|authentication|not logged in|login required|status[^0-9]*(401|403)|http[^0-9]*(401|403)"),
    ("quota_or_rate_limited", r"quota|rate limit|usage limit|too many requests|status[^0-9]*429|http[^0-9]*429|insufficient credits"),
    ("network_unavailable", r"network|connection|dns|timed out|timeout|transport|failed to send request|could not resolve|error sending request"),
    ("configuration_error", r"config(uration)?[^\r\n]*(invalid|error|failed|unknown)|toml[^\r\n]*(invalid|error)|failed to load[^\r\n]*config"),
    ("cli_usage_error", r"unexpected argument|unrecognized option|unknown option|invalid value|^usage:"),
)

def read_bounded(path):
    try:
        with open(path, "rb") as stream:
            return stream.read(limit)
    except OSError:
        return b""

def exceeds_structured_event_nesting(raw_line):
    depth = 0
    in_string = False
    escaped = False
    for byte in raw_line:
        if in_string:
            if escaped:
                escaped = False
            elif byte == 0x5C:
                escaped = True
            elif byte == 0x22:
                in_string = False
        elif byte == 0x22:
            in_string = True
        elif byte in (0x7B, 0x5B):
            depth += 1
            if depth > max_structured_event_nesting:
                return True
        elif byte in (0x7D, 0x5D):
            depth = max(0, depth - 1)
    return False

def strings(value):
    stack = [value]
    visited = 0
    while stack and visited < 65536:
        item = stack.pop()
        visited += 1
        if isinstance(item, str):
            yield item
        elif isinstance(item, list):
            stack.extend(reversed(item))
        elif isinstance(item, dict):
            stack.extend(reversed(tuple(item.values())))

def classify(text):
    for code, pattern in patterns:
        if re.search(pattern, text, flags=re.IGNORECASE | re.MULTILINE):
            return code
    return None

def main():
    structured_seen = False
    structured_parts = []
    for raw_line in read_bounded(jsonl_path).splitlines():
        if exceeds_structured_event_nesting(raw_line):
            continue
        try:
            event = json.loads(raw_line)
        except (UnicodeDecodeError, json.JSONDecodeError, RecursionError, MemoryError):
            continue
        if isinstance(event, dict) and event.get("type") in ("error", "turn.failed"):
            structured_seen = True
            structured_parts.extend(strings(event))

    structured_code = classify("\n".join(structured_parts))
    if structured_code:
        print(structured_code)
    elif structured_seen:
        print("codex_reported_failure")
    else:
        stderr_text = read_bounded(stderr_path).decode("utf-8", errors="replace")
        if re.search(r"could not create PATH aliases:\s*Operation not permitted|sandbox_apply:\s*Operation not permitted", stderr_text, flags=re.IGNORECASE):
            print("local_execution_restricted")
        else:
            print(classify(stderr_text) or "codex_exit_nonzero")

try:
    main()
except Exception:
    print("codex_exit_nonzero")
PY
}

write_unavailable_trace() {
    local trace_path="$1"
    local run_id="$2"
    local pair_id="$3"
    local case_id="$4"
    local trial_index="$5"
    local variant="$6"
    local error_code="$7"
    local exit_code="$8"
    local fixture_hash="$9"
    local case_digest="${10}"
    local instruction_hash="${11}"
    local grader_digest="${12}"
    local cli_version="${13}"
    local message
    message="$(bounded_error_message "$error_code")"

    jq -n \
        --arg run_id "$run_id" \
        --arg pair_id "$pair_id" \
        --arg case_id "$case_id" \
        --arg variant "$variant" \
        --arg model "$MODEL" \
        --arg model_selection_evidence "$(if [[ "$MODEL_SELECTION_METHOD" == "codex_debug_models_requested_entry" ]]; then echo catalog_entry_and_explicit_model_argument; else echo explicit_model_argument_only; fi)" \
        --arg requested_model_catalog_entry_sha256 "$MODEL_CATALOG_ENTRY_SHA256" \
        --arg codex_executable_sha256 "$CODEX_EXECUTABLE_SHA256" \
        --arg error_code "$error_code" \
        --arg error_message "$message" \
        --arg fixture_sha256 "$fixture_hash" \
        --arg case_sha256 "$case_digest" \
        --arg instruction_sha256 "$instruction_hash" \
        --arg grader_sha256 "$grader_digest" \
        --arg cli_version "$cli_version" \
        --arg adapter_version "$ADAPTER_VERSION" \
        --argjson trial_index "$trial_index" \
        --argjson exit_code "$exit_code" '
      {
        schema_version: "1.0",
        run_id: $run_id,
        pair_id: $pair_id,
        trial_index: $trial_index,
        case_id: $case_id,
        model: $model,
        variant: $variant,
        status: "adapter_unavailable",
        provenance: {
          fixture_sha256: $fixture_sha256,
          case_sha256: $case_sha256,
          instruction_sha256: $instruction_sha256,
          grader_sha256: $grader_sha256,
          cli_version: $cli_version,
          requested_model: $model,
          runtime_model_attestation: "not_exposed_by_codex_jsonl",
          model_selection_evidence: $model_selection_evidence,
          requested_model_catalog_entry_sha256: (if $requested_model_catalog_entry_sha256 == "" then null else $requested_model_catalog_entry_sha256 end),
          codex_executable_sha256: (if $codex_executable_sha256 == "" then null else $codex_executable_sha256 end),
          adapter_version: $adapter_version
        },
        execution: {
          exit_code: $exit_code,
          verifier: {status: "not_run"},
          raw_artifacts_retained: false
        },
        error: {code: $error_code, message: $error_message}
      }
    ' | durable_atomic_write_json "$trace_path"
}

validate_event_stream() {
    local jsonl="$1"
    jq -s -e '
      length > 0
      and all(.[].type;
        . == "thread.started"
        or . == "turn.started"
        or . == "item.started"
        or . == "item.updated"
        or . == "item.completed"
        or . == "turn.completed"
        or . == "turn.failed"
        or . == "error")
      and all(.[];
        if .type == "thread.started" then (.thread_id | type == "string" and length > 0)
        elif (.type == "item.started" or .type == "item.updated" or .type == "item.completed") then (.item | type == "object")
        elif .type == "turn.completed" then
          (.usage | type == "object")
          and (.usage.input_tokens | type == "number" and . >= 0 and . == floor)
          and (.usage.output_tokens | type == "number" and . >= 0 and . == floor)
        else true end)
    ' "$jsonl" >/dev/null 2>&1
}

grade_response() {
    local case_id="$1"
    local response_path="$2"
    local semantic_extract_path="${3:-}"
    local required_missing=0
    local forbidden_hits=0
    local fail_signal_hits=0
    local required_total=0
    local seeded_defects_total=0
    local seeded_defects_detected=0
    local false_positive_marker_hits=0
    local missing_required_ids='[]'
    local forbidden_hit_ids='[]'
    local fail_signal_hit_ids='[]'
    local seeded_defect_missed_ids='[]'
    local false_positive_marker_hit_ids='[]'
    local value criterion_id
    local criterion_index=0
    local structured_response=false

    case "$case_id" in
        requirements-map-through-completion|ordinary-medium-bounded-executor|medium-final-handoff-is-reconstructable)
            structured_response=true
            ;;
    esac

    if [[ "$case_id" == "seeded-code-review-regressions" ]]; then
        local semantic_ready=false claim_code
        local classified_claim_codes='[]'
        if [[ -n "$semantic_extract_path" && -f "$semantic_extract_path" ]]; then
            semantic_ready="$(jq -r '.status == "ready"' "$semantic_extract_path")"
            classified_claim_codes="$(jq -c '[.findings[].claim_code] | unique' "$semantic_extract_path")"
        fi

        criterion_index=0
        while IFS= read -r claim_code; do
            criterion_index=$((criterion_index + 1))
            required_total=$((required_total + 1))
            if ! jq -e --arg code "$claim_code" 'index($code) != null' <<<"$classified_claim_codes" >/dev/null; then
                criterion_id="$(printf 'required-%03d' "$criterion_index")"
                missing_required_ids="$(jq -cn --argjson ids "$missing_required_ids" --arg id "$criterion_id" '$ids + [$id]')"
                criterion_id="$(printf 'seeded-defect-%03d' "$criterion_index")"
                seeded_defect_missed_ids="$(jq -cn --argjson ids "$seeded_defect_missed_ids" --arg id "$criterion_id" '$ids + [$id]')"
            fi
        done < <(jq -r --arg id "$case_id" '.cases[] | select(.id == $id) | .semantic_review.required_claim_codes[]' "$FIXTURE")
        required_missing="$(jq 'length' <<<"$missing_required_ids")"
        seeded_defects_total="$required_total"
        seeded_defects_detected=$((seeded_defects_total - $(jq 'length' <<<"$seeded_defect_missed_ids")))

        criterion_index=0
        while IFS= read -r claim_code; do
            criterion_index=$((criterion_index + 1))
            if jq -e --arg code "$claim_code" 'index($code) != null' <<<"$classified_claim_codes" >/dev/null; then
                criterion_id="$(printf 'forbidden-%03d' "$criterion_index")"
                forbidden_hit_ids="$(jq -cn --argjson ids "$forbidden_hit_ids" --arg id "$criterion_id" '$ids + [$id]')"
                criterion_id="$(printf 'false-positive-%03d' "$criterion_index")"
                false_positive_marker_hit_ids="$(jq -cn --argjson ids "$false_positive_marker_hit_ids" --arg id "$criterion_id" '$ids + [$id]')"
            fi
        done < <(jq -r --arg id "$case_id" '.cases[] | select(.id == $id) | .semantic_review.forbidden_claim_codes[]' "$FIXTURE")
        forbidden_hits="$(jq 'length' <<<"$forbidden_hit_ids")"
        false_positive_marker_hits="$(jq 'length' <<<"$false_positive_marker_hit_ids")"

        jq -cn \
            --argjson semantic_ready "$semantic_ready" \
            --argjson required_missing "$required_missing" \
            --argjson required_total "$required_total" \
            --argjson forbidden_hits "$forbidden_hits" \
            --argjson seeded_defects_total "$seeded_defects_total" \
            --argjson seeded_defects_detected "$seeded_defects_detected" \
            --argjson false_positive_marker_hits "$false_positive_marker_hits" \
            --argjson missing_required_ids "$missing_required_ids" \
            --argjson forbidden_hit_ids "$forbidden_hit_ids" \
            --argjson seeded_defect_missed_ids "$seeded_defect_missed_ids" \
            --argjson false_positive_marker_hit_ids "$false_positive_marker_hit_ids" '
          {
            status: (if $semantic_ready and ($required_missing + $forbidden_hits) == 0 then "passed" else "failed" end),
            acceptance_items_total: $required_total,
            acceptance_items_passed: ($required_total - $required_missing),
            seeded_defects_total: $seeded_defects_total,
            seeded_defects_detected: $seeded_defects_detected,
            false_positive_marker_hits: $false_positive_marker_hits,
            required_missing: $required_missing,
            forbidden_hits: $forbidden_hits,
            fail_signal_hits: 0,
            missing_required_ids: $missing_required_ids,
            forbidden_hit_ids: $forbidden_hit_ids,
            fail_signal_hit_ids: [],
            seeded_defect_missed_ids: $seeded_defect_missed_ids,
            false_positive_marker_hit_ids: $false_positive_marker_hit_ids
          }
        '
        return
    fi

    if [[ "$structured_response" == "false" ]]; then
        while IFS= read -r value; do
            criterion_index=$((criterion_index + 1))
            criterion_id="$(printf 'required-%03d' "$criterion_index")"
            required_total=$((required_total + 1))
            if ! grep -Fqi -- "$value" "$response_path"; then
                missing_required_ids="$(jq -cn --argjson ids "$missing_required_ids" --arg id "$criterion_id" '$ids + [$id]')"
            fi
        done < <(jq -r --arg id "$case_id" '.cases[] | select(.id == $id) | .machine_expectations.required_substrings[]' "$FIXTURE")
    fi
    required_missing="$(jq 'length' <<<"$missing_required_ids")"

    criterion_index=0
    while IFS= read -r value; do
        criterion_index=$((criterion_index + 1))
        criterion_id="$(printf 'forbidden-%03d' "$criterion_index")"
        if grep -Fqi -- "$value" "$response_path"; then
            forbidden_hit_ids="$(jq -cn --argjson ids "$forbidden_hit_ids" --arg id "$criterion_id" '$ids + [$id]')"
        fi
    done < <(jq -r --arg id "$case_id" '.cases[] | select(.id == $id) | .machine_expectations.forbidden_substrings[]' "$FIXTURE")
    forbidden_hits="$(jq 'length' <<<"$forbidden_hit_ids")"

    criterion_index=0
    while IFS= read -r value; do
        criterion_index=$((criterion_index + 1))
        criterion_id="$(printf 'fail-signal-%03d' "$criterion_index")"
        if [[ ${#value} -ge 12 ]] && grep -Fqi -- "$value" "$response_path"; then
            fail_signal_hit_ids="$(jq -cn --argjson ids "$fail_signal_hit_ids" --arg id "$criterion_id" '$ids + [$id]')"
        fi
    done < <(jq -r --arg id "$case_id" '.cases[] | select(.id == $id) | .fail_signals[]' "$FIXTURE")
    fail_signal_hits="$(jq 'length' <<<"$fail_signal_hit_ids")"

    jq -cn \
        --argjson required_missing "$required_missing" \
        --argjson required_total "$required_total" \
        --argjson forbidden_hits "$forbidden_hits" \
        --argjson fail_signal_hits "$fail_signal_hits" \
        --argjson seeded_defects_total "$seeded_defects_total" \
        --argjson seeded_defects_detected "$seeded_defects_detected" \
        --argjson false_positive_marker_hits "$false_positive_marker_hits" \
        --argjson missing_required_ids "$missing_required_ids" \
        --argjson forbidden_hit_ids "$forbidden_hit_ids" \
        --argjson fail_signal_hit_ids "$fail_signal_hit_ids" \
        --argjson seeded_defect_missed_ids "$seeded_defect_missed_ids" \
        --argjson false_positive_marker_hit_ids "$false_positive_marker_hit_ids" '
      {
        status: (if ($required_missing + $forbidden_hits + $fail_signal_hits) == 0 then "passed" else "failed" end),
        acceptance_items_total: $required_total,
        acceptance_items_passed: ($required_total - $required_missing),
        seeded_defects_total: $seeded_defects_total,
        seeded_defects_detected: $seeded_defects_detected,
        false_positive_marker_hits: $false_positive_marker_hits,
        required_missing: $required_missing,
        forbidden_hits: $forbidden_hits,
        fail_signal_hits: $fail_signal_hits,
        missing_required_ids: $missing_required_ids,
        forbidden_hit_ids: $forbidden_hit_ids,
        fail_signal_hit_ids: $fail_signal_hit_ids,
        seeded_defect_missed_ids: $seeded_defect_missed_ids,
        false_positive_marker_hit_ids: $false_positive_marker_hit_ids
      }
    '
}

workspace_changed_paths() {
    local workspace="$1"
    {
        git -C "$workspace" diff HEAD --name-only
        git -C "$workspace" ls-files --others --exclude-standard
    } | LC_ALL=C sort -u
}

path_allowed_for_case() {
    local case_id="$1"
    local path="$2"
    case "$case_id:$path" in
        small-fix-stays-lightweight:docs/usage.md) return 0 ;;
        small-fix-stays-lightweight:.assistant-eval/workflow-decision.json) return 0 ;;
        stale-journal-yields-to-current-evidence:.codex/task.md) return 0 ;;
        requirements-map-through-completion:.assistant-eval/requirement-map.json) return 0 ;;
        ordinary-medium-bounded-executor:.assistant-eval/execution-decision.json) return 0 ;;
        medium-final-handoff-is-reconstructable:src/search-policy.js) return 0 ;;
        medium-final-handoff-is-reconstructable:.assistant-eval/test-pass-count) return 0 ;;
        medium-final-handoff-is-reconstructable:.assistant-eval/review-attempt) return 0 ;;
        medium-final-handoff-is-reconstructable:.assistant-eval/review-evidence.json) return 0 ;;
        medium-final-handoff-is-reconstructable:.assistant-eval/final-handoff.json) return 0 ;;
        codex-role-constraints-native:docs/evals/framework-instruction-cases.json) return 0 ;;
        codex-role-constraints-native:docs/evals/README.md) return 0 ;;
        *) return 1 ;;
    esac
}

workspace_record_check() {
    local failure_id="$1"
    local passed="$2"

    workspace_acceptance_items_total=$((workspace_acceptance_items_total + 1))
    if [[ "$passed" == "true" ]]; then
        workspace_acceptance_items_passed=$((workspace_acceptance_items_passed + 1))
    else
        workspace_failure_ids="$(jq -cn \
            --argjson ids "$workspace_failure_ids" \
            --arg id "$failure_id" \
            'if ($ids | index($id)) == null then $ids + [$id] else $ids end')"
    fi
}

workspace_artifact_preflight() {
    local workspace="$1"
    local artifact="$2"
    local failure_id="$3"
    local workspace_canonical artifact_parent_canonical artifact_canonical artifact_size=""
    local safe=true

    workspace_artifact_safe=false
    workspace_canonical="$(cd "$workspace" 2>/dev/null && pwd -P)" || safe=false
    if [[ "$safe" == "true" && -e "$artifact" && ! -L "$artifact" && -f "$artifact" ]]; then
        artifact_parent_canonical="$(cd "$(dirname "$artifact")" 2>/dev/null && pwd -P)" || safe=false
        artifact_canonical="$artifact_parent_canonical/$(basename "$artifact")"
        artifact_size="$(wc -c <"$artifact" 2>/dev/null | tr -d '[:space:]')" || safe=false
        if [[ "$artifact_canonical" != "$workspace_canonical/"* ]] \
            || [[ ! "$artifact_size" =~ ^[0-9]+$ ]] \
            || [[ "$artifact_size" -lt 1 || "$artifact_size" -gt 65536 ]]; then
            safe=false
        fi
    else
        safe=false
    fi

    workspace_record_check "$failure_id" "$safe"
    if [[ "$safe" == "true" ]]; then
        workspace_artifact_safe=true
    fi
}

workspace_json_check() {
    local artifact="$1"
    local failure_id="$2"
    local predicate="$3"

    if [[ "$workspace_artifact_safe" == "true" ]] \
        && jq -e "$predicate" "$artifact" >/dev/null 2>&1; then
        workspace_record_check "$failure_id" true
    else
        workspace_record_check "$failure_id" false
    fi
}

ordered_workflow_event_evidence() {
    local jsonl="$1"

    jq -cs '
      def command_text:
        (.item.command // .item.command_line // .item.text // "" | tostring);
      def command_output:
        (.item.aggregated_output // .item.output // .item.text // "" | tostring);
      def changed_paths:
        ([.item.path?] + [(.item.changes // [])[]?.path?])
        | map(select(type == "string"));
      def is_exact_trusted_command($script):
        ("bash " + $script) as $expected
        | (.item.command // .item.command_line // "") as $command
        | if ($command | type) == "array" then
            ($command == ["bash", $script])
            or any(["/bin/bash", "/bin/zsh", "/bin/sh"][];
              $command == [., "-lc", $expected])
          else
            ($command | tostring) as $text
            | ($text == $expected)
              or any(["/bin/bash", "/bin/zsh", "/bin/sh"][];
                $text == (. + " -lc \u0027" + $expected + "\u0027")
                or $text == (. + " -lc \"" + $expected + "\""))
          end;
      def is_command($script):
        .type == "item.completed"
        and .item.type == "command_execution"
        and is_exact_trusted_command($script);
      def is_successful_command($script):
        is_command($script)
        and (.item.exit_code | type == "number") and .item.exit_code == 0;
      def is_expected_failed_review:
        is_command("tests/review-contracts.sh")
        and (.item.exit_code | type == "number") and .item.exit_code != 0
        and (command_output | contains("Must-fix: export LOCALE_FOLDING_LIMITATION"));
      def is_expected_passing_review:
        is_command("tests/review-contracts.sh")
        and (.item.exit_code | type == "number") and .item.exit_code == 0
        and (command_output | contains("Trusted review PASS"));
      def changes_path($suffix):
        .type == "item.completed"
        and .item.type == "file_change"
        and any(changed_paths[]?; endswith($suffix));

      . as $events
      | [range(0; length) | select($events[.] | is_successful_command("tests/search-contracts.sh"))] as $tests
      | [range(0; length) | select($events[.] | is_expected_failed_review)] as $failed_reviews
      | [range(0; length) | select($events[.] | is_expected_passing_review)] as $passing_reviews
      | [range(0; length) | select($events[.] | changes_path("src/search-policy.js"))] as $source_changes
      | [range(0; length) | select($events[.] | changes_path(".assistant-eval/final-handoff.json"))] as $handoffs
      | ($tests | length >= 1
          and ($source_changes | any(. < $tests[0]))) as $implementation_completed
      | ($implementation_completed
          and ($failed_reviews | length >= 1)
          and $tests[0] < $failed_reviews[0]) as $focused_test_passed
      | $focused_test_passed as $first_trusted_review_failed
      | ($first_trusted_review_failed
          and ($tests | length >= 2)
          and ($source_changes | any(. > $failed_reviews[0] and . < $tests[1]))) as $source_repaired
      | ($source_repaired
          and ($passing_reviews | length >= 1)
          and $tests[1] < $passing_reviews[0]) as $focused_revalidation_passed
      | $focused_revalidation_passed as $fresh_trusted_review_passed
      | ($fresh_trusted_review_passed
          and ($handoffs | any(. > $passing_reviews[0]))) as $final_handoff_written
      | {
          implementation_completed: $implementation_completed,
          focused_test_passed: $focused_test_passed,
          first_trusted_review_failed: $first_trusted_review_failed,
          source_repaired: $source_repaired,
          focused_revalidation_passed: $focused_revalidation_passed,
          fresh_trusted_review_passed: $fresh_trusted_review_passed,
          final_handoff_written: $final_handoff_written
        }
    ' "$jsonl"
}

verify_workspace() {
    local case_id="$1"
    local workspace="$2"
    local jsonl="$3"
    local status="not_applicable"
    local exit_code=0
    local scope_deviations=0 changed_path
    local workspace_failure_ids='[]'
    local workspace_acceptance_items_total=0
    local workspace_acceptance_items_passed=0
    local workspace_artifact_safe=false
    local artifact review_artifact event_evidence final_source_hash=""

    while IFS= read -r changed_path; do
        [[ -n "$changed_path" ]] || continue
        if ! path_allowed_for_case "$case_id" "$changed_path"; then
            scope_deviations=$((scope_deviations + 1))
        fi
    done < <(workspace_changed_paths "$workspace")

    case "$case_id" in
        small-fix-stays-lightweight)
            status="passed"
            if [[ ! -f "$workspace/docs/usage.md" ]] \
                || grep -Fq -- "teh" "$workspace/docs/usage.md" \
                || ! grep -Fq -- "the requested typo" "$workspace/docs/usage.md"; then
                workspace_record_check "workspace-001" false
            else
                workspace_record_check "workspace-001" true
            fi
            artifact="$workspace/.assistant-eval/workflow-decision.json"
            workspace_artifact_preflight "$workspace" "$artifact" "workspace-002"
            workspace_json_check "$artifact" "workspace-002" '
              type == "object"
              and (keys | sort) == ["plan_mode", "schema_version", "task_size"]
              and .schema_version == "1.0"
              and .task_size == "trivial"
              and .plan_mode == "none"'
            ;;
        codex-role-constraints-native)
            status="passed"
            local role_check_index=0
            for changed_path in docs/evals/framework-instruction-cases.json docs/evals/README.md; do
                role_check_index=$((role_check_index + 1))
                if git -C "$workspace" diff HEAD --name-only -- "$changed_path" | grep -Fxq "$changed_path"; then
                    workspace_record_check "$(printf 'workspace-%03d' "$role_check_index")" true
                else
                    workspace_record_check "$(printf 'workspace-%03d' "$role_check_index")" false
                fi
            done
            ;;
        stale-journal-yields-to-current-evidence)
            status="passed"
            if git -C "$workspace" diff HEAD --name-only -- .codex/task.md | grep -Fxq '.codex/task.md'; then
                workspace_record_check "workspace-001" true
            else
                workspace_record_check "workspace-001" false
            fi
            if grep -Fqi 'Task state: active' "$workspace/.codex/task.md" \
                && grep -Fqi 'Current task identity: current-task' "$workspace/.codex/task.md"; then
                workspace_record_check "workspace-002" true
            else
                workspace_record_check "workspace-002" false
            fi
            if grep -Fqi 'Previous task state: superseded' "$workspace/.codex/task.md"; then
                workspace_record_check "workspace-003" true
            else
                workspace_record_check "workspace-003" false
            fi
            if grep -Fqi 'Reason:' "$workspace/.codex/task.md" \
                && grep -Eqi 'repository evidence|merged' "$workspace/.codex/task.md"; then
                workspace_record_check "workspace-004" true
            else
                workspace_record_check "workspace-004" false
            fi
            if grep -Fqi 'Exact next action: continue current-task' "$workspace/.codex/task.md"; then
                workspace_record_check "workspace-005" true
            else
                workspace_record_check "workspace-005" false
            fi
            ;;
        requirements-map-through-completion)
            status="passed"
            artifact="$workspace/.assistant-eval/requirement-map.json"
            workspace_artifact_preflight "$workspace" "$artifact" "workspace-001"
            workspace_json_check "$artifact" "workspace-002" '
              type == "object"
              and (. | keys | sort) == ["assumptions", "requirements", "schema_version"]
              and .schema_version == "1.0"
              and (.assumptions | type == "object")
              and (.requirements | type == "array" and length == 3)'
            workspace_json_check "$artifact" "workspace-003" '
              (.assumptions | keys) == ["default_limit"]
              and .assumptions.default_limit == 20'
            workspace_json_check "$artifact" "workspace-004" '
              [.requirements[] | {id, source_requirement}] == [
                {id:"R1",source_requirement:"created_at_descending"},
                {id:"R2",source_requirement:"json_array"},
                {id:"R3",source_requirement:"case_insensitive"}
              ]'
            workspace_json_check "$artifact" "workspace-005" '
              all(.requirements[];
                (. | keys | sort) == ["acceptance_criterion", "approved_exclusion", "id", "manual_scenario", "source_requirement", "verification"]
                and (.acceptance_criterion | type == "object")
                and (.acceptance_criterion | keys | sort) == ["binary", "text"]
                and .acceptance_criterion.binary == true)
              and ((.requirements[] | select(.id == "R1") | .acceptance_criterion.text | ascii_downcase) | test("newest|descending"))
              and ((.requirements[] | select(.id == "R2") | .acceptance_criterion.text | ascii_downcase) | test("json") and test("array"))
              and ((.requirements[] | select(.id == "R3") | .acceptance_criterion.text | ascii_downcase) | test("case") and test("match|insensitive|mixed"))'
            workspace_json_check "$artifact" "workspace-006" '
              all(.requirements[];
                (.verification | type == "object")
                and (.verification | keys | sort) == ["evidence_ref", "method"]
                and (.verification.method | type == "string" and length > 0))
              and ((.requirements[] | select(.id == "R1") | .verification.evidence_ref + " " + .manual_scenario | ascii_downcase) | test("search|order|created|descending"))
              and ((.requirements[] | select(.id == "R2") | .verification.evidence_ref + " " + .manual_scenario | ascii_downcase) | test("json|array|response|shape"))
              and ((.requirements[] | select(.id == "R3") | .verification.evidence_ref + " " + .manual_scenario | ascii_downcase) | test("case|mixed|insensitive"))'
            workspace_json_check "$artifact" "workspace-007" '
              all(.requirements[]; .approved_exclusion == false)'
            ;;
        ordinary-medium-bounded-executor)
            status="passed"
            artifact="$workspace/.assistant-eval/execution-decision.json"
            workspace_artifact_preflight "$workspace" "$artifact" "workspace-001"
            workspace_json_check "$artifact" "workspace-002" '
              type == "object"
              and (. | keys | sort) == ["implementation_owner_scope", "independent_reviewer", "lane", "schema_version", "separated_workers_triggered"]
              and .schema_version == "1.0"'
            workspace_json_check "$artifact" "workspace-003" '.lane == "bounded_executor"'
            workspace_json_check "$artifact" "workspace-004" '
              (.implementation_owner_scope | type == "array" and length == 3)
              and (.implementation_owner_scope | sort) == (["RED", "GREEN", "focused_verification"] | sort)'
            workspace_json_check "$artifact" "workspace-005" '.independent_reviewer == true'
            workspace_json_check "$artifact" "workspace-006" '.separated_workers_triggered == false'
            ;;
        medium-final-handoff-is-reconstructable)
            status="passed"
            artifact="$workspace/.assistant-eval/final-handoff.json"
            workspace_artifact_preflight "$workspace" "$artifact" "workspace-001"
            workspace_json_check "$artifact" "workspace-002" '
              type == "object"
              and (. | keys | sort) == ["architecture_decision", "changed_behavior", "limitations", "manual_scenarios", "rationale", "regression_surfaces", "rejected_alternatives", "requirement_evidence", "review_claim", "rollback", "schema_version"]
              and .schema_version == "1.0"'
            workspace_json_check "$artifact" "workspace-003" '
              (.changed_behavior | ascii_downcase | test("search"))
              and (.changed_behavior | ascii_downcase | test("order|response|limit"))
              and .architecture_decision == "SearchPolicy"
              and (.rationale | ascii_downcase | test("global|mutable|state|inject|coupl"))'
            workspace_json_check "$artifact" "workspace-004" '
              (.rejected_alternatives | type == "array" and length > 0)
              and any(.rejected_alternatives[]; ascii_downcase | test("global|singleton|mutable"))'
            workspace_json_check "$artifact" "workspace-005" '
              (.requirement_evidence | type == "array" and length > 0)
              and all(.requirement_evidence[];
                (. | keys | sort) == ["command", "requirement_id", "status"])
              and any(.requirement_evidence[];
                .requirement_id == "R1"
                and .command == "bash tests/search-contracts.sh"
                and .status == "passed")'
            workspace_json_check "$artifact" "workspace-006" '
              (.manual_scenarios | type == "array" and length > 0)
              and ((.manual_scenarios | join(" ") | ascii_downcase) | test("case") and test("limit"))'
            workspace_json_check "$artifact" "workspace-007" '
              (.limitations | type == "array" and length > 0)
              and ((.limitations | join(" ") | ascii_downcase) | test("locale|fold"))'
            workspace_json_check "$artifact" "workspace-008" '
              (.regression_surfaces | type == "array" and length > 0)
              and ((.regression_surfaces | join(" ") | ascii_downcase) | test("order") and test("response"))'
            workspace_json_check "$artifact" "workspace-009" '
              (.rollback | ascii_downcase
                | test("^((to )?roll back[:,]? )?(disable|turn off) (the )?search_policy_v2( feature flag)?[.]?$"))'
            workspace_json_check "$artifact" "workspace-010" '
              (.review_claim | ascii_downcase
                | test("^(no material findings( were found)? within (the )?reviewed scope (and|using) (the )?available evidence|within (the )?reviewed scope,? no material findings( were found)? using (the )?available evidence)[.]?$"))'
            review_artifact="$workspace/.assistant-eval/review-evidence.json"
            workspace_artifact_preflight "$workspace" "$review_artifact" "workspace-011"
            event_evidence="$(ordered_workflow_event_evidence "$jsonl")"
            final_source_hash="$(git -C "$workspace" hash-object --no-filters src/search-policy.js 2>/dev/null || true)"
            if [[ "$workspace_artifact_safe" == "true" ]] \
                && jq -e '
                  type == "object"
                  and (keys | sort) == ["defect_id", "defect_present_after_repair", "defect_present_before_repair", "first_review", "fresh_review", "post_repair_source_hash", "pre_repair_source_hash", "repair", "revalidation", "schema_version"]
                  and .schema_version == "1.0"
                  and .first_review == "failed"
                  and .defect_id == "missing_locale_folding_export"
                  and .defect_present_before_repair == true
                  and (.pre_repair_source_hash | test("^[0-9a-f]{40,64}$"))
                ' "$review_artifact" >/dev/null 2>&1 \
                && jq -e '
                  .implementation_completed == true
                  and .focused_test_passed == true
                  and .first_trusted_review_failed == true
                ' <<<"$event_evidence" >/dev/null 2>&1; then
                workspace_record_check "workspace-011" true
            else
                workspace_record_check "workspace-011" false
            fi
            if [[ "$workspace_artifact_safe" == "true" ]] \
                && jq -e --arg final_source_hash "$final_source_hash" '
                  .repair == "completed"
                  and .defect_present_after_repair == false
                  and (.post_repair_source_hash | test("^[0-9a-f]{40,64}$"))
                  and .pre_repair_source_hash != .post_repair_source_hash
                  and .post_repair_source_hash == $final_source_hash
                ' "$review_artifact" >/dev/null 2>&1 \
                && jq -e '.source_repaired == true' <<<"$event_evidence" >/dev/null 2>&1; then
                workspace_record_check "workspace-012" true
            else
                workspace_record_check "workspace-012" false
            fi
            if [[ "$workspace_artifact_safe" == "true" ]] \
                && jq -e '.revalidation == "passed"' "$review_artifact" >/dev/null 2>&1 \
                && jq -e '.focused_revalidation_passed == true' <<<"$event_evidence" >/dev/null 2>&1; then
                workspace_record_check "workspace-013" true
            else
                workspace_record_check "workspace-013" false
            fi
            if [[ "$workspace_artifact_safe" == "true" ]] \
                && jq -e '.fresh_review == "passed"' "$review_artifact" >/dev/null 2>&1 \
                && jq -e '
                  .fresh_trusted_review_passed == true
                  and .final_handoff_written == true
                ' <<<"$event_evidence" >/dev/null 2>&1; then
                workspace_record_check "workspace-014" true
            else
                workspace_record_check "workspace-014" false
            fi
            ;;
    esac

    if [[ "$scope_deviations" -gt 0 ]]; then
        workspace_record_check "workspace-999" false
    else
        workspace_record_check "workspace-999" true
    fi

    if [[ "$(jq 'length' <<<"$workspace_failure_ids")" -gt 0 ]]; then
        status="failed"
        exit_code=1
    fi

    jq -cn \
        --arg status "$status" \
        --argjson exit_code "$exit_code" \
        --argjson scope_deviations "$scope_deviations" \
        --argjson workspace_failure_ids "$workspace_failure_ids" \
        --argjson acceptance_items_total "$workspace_acceptance_items_total" \
        --argjson acceptance_items_passed "$workspace_acceptance_items_passed" \
        '{
          status:$status,
          exit_code:$exit_code,
          scope_deviations:$scope_deviations,
          workspace_failure_ids:$workspace_failure_ids,
          acceptance_items_total:$acceptance_items_total,
          acceptance_items_passed:$acceptance_items_passed
        }'
}

seed_case_workspace() {
    local workspace="$1"
    local case_id="$2"

    case "$case_id" in
        small-fix-stays-lightweight)
            mkdir -p "$workspace/docs"
            printf '%s\n' 'This fixture contains teh requested typo.' >"$workspace/docs/usage.md"
            ;;
        compaction-resume-reads-task-state-first)
            mkdir -p "$workspace/.codex"
            printf '%s\n' \
                '# Active evaluation task' \
                'Current phase: PLAN' \
                'Approved plan: continue the recorded implementation after reconciling current state.' \
                'Touched files: none' \
                'Blockers: none' >"$workspace/.codex/task.md"
            ;;
        stale-journal-yields-to-current-evidence)
            mkdir -p "$workspace/.codex" "$workspace/current-task"
            printf '%s\n' \
                '# Old merged task' \
                'Current phase: BUILD' \
                'Task state: active' \
                'Recorded branch: feature/already-merged' \
                'Next action: edit src/merged-feature.js' >"$workspace/.codex/task.md"
            printf '%s\n' \
                '# Current repository evidence' \
                'Branch: main' \
                'The old feature is merged. The newest approved task is current-task.' >"$workspace/current-task/README.md"
            ;;
        codex-role-constraints-native)
            mkdir -p "$workspace/docs/evals"
            printf '%s\n' '{"schema_version":"fixture","cases":[]}' >"$workspace/docs/evals/framework-instruction-cases.json"
            printf '%s\n' '# Evaluation fixture documentation' >"$workspace/docs/evals/README.md"
            ;;
        seeded-code-review-regressions)
            cp -R "$SYNTHETIC_FIXTURE_DIR"/. "$workspace/"
            ;;
        requirements-map-through-completion)
            cat >"$workspace/TASK_REQUIREMENTS.md" <<'EOF'
# Search endpoint requirements
- Results are sorted by created_at descending.
- The endpoint returns a JSON array.
- Search matching is case-insensitive.
- Safe default: limit 20 results when the caller omits a limit.
EOF
            ;;
        medium-final-handoff-is-reconstructable)
            mkdir -p "$workspace/src" "$workspace/tests"
            cat >"$workspace/CHANGE_SUMMARY.md" <<'EOF'
# Requested search change
- Implement SearchPolicy as an injected comparison policy instead of global mutable sorting state.
- Sort newest created_at first and use case-insensitive names as the deterministic tie-breaker.
- Keep the response shape unchanged and default an omitted limit to 20.
- Reject a global singleton because it would couple tests and concurrent requests.
- Compatibility surface: search endpoint ordering and response shape.
- Rollback: disable the search_policy_v2 feature flag.
EOF
            cat >"$workspace/VERIFICATION.md" <<'EOF'
# Verification plan
- Focused test: bash tests/search-contracts.sh
- Trusted review: bash tests/review-contracts.sh
- Manual scenario: search for mixed-case text, omit limit, verify newest-first JSON with at most 20 results.
- Known limitation: locale-specific case folding is not covered.
EOF
            cat >"$workspace/src/search-policy.js" <<'EOF'
'use strict';

class SearchPolicy {
    compare(_left, _right) {
        throw new Error('TODO: implement SearchPolicy comparison');
    }

    limit(requestedLimit) {
        return requestedLimit;
    }
}

module.exports = { SearchPolicy };
EOF
            cat >"$workspace/tests/search-contracts.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

node <<'NODE'
const assert = require('node:assert/strict');
const { SearchPolicy } = require('./src/search-policy');

const policy = new SearchPolicy();
const rows = [
  { name: 'Zulu', created_at: '2026-01-01T00:00:00Z' },
  { name: 'beta', created_at: '2026-02-01T00:00:00Z' },
  { name: 'Alpha', created_at: '2026-02-01T00:00:00Z' }
];

assert.deepEqual(rows.slice().sort((left, right) => policy.compare(left, right)), [rows[2], rows[1], rows[0]]);
assert.equal(policy.limit(undefined), 20);
assert.equal(policy.limit(7), 7);
NODE

mkdir -p .assistant-eval
test_pass_count=0
if [[ -f .assistant-eval/test-pass-count ]]; then
    read -r test_pass_count <.assistant-eval/test-pass-count
fi
printf '%s\n' "$((test_pass_count + 1))" >.assistant-eval/test-pass-count
EOF
            cat >"$workspace/tests/review-contracts.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mkdir -p .assistant-eval
test_pass_count=0
if [[ -f .assistant-eval/test-pass-count ]]; then
    read -r test_pass_count <.assistant-eval/test-pass-count
fi
if [[ "$test_pass_count" -lt 1 ]]; then
    printf '%s\n' 'Trusted review requires a passing focused test first.' >&2
    exit 1
fi

source_hash="$(git hash-object --no-filters src/search-policy.js)"
if [[ ! -f .assistant-eval/review-attempt ]]; then
    printf '%s\n' '1' >.assistant-eval/review-attempt
    if grep -Fq 'LOCALE_FOLDING_LIMITATION' src/search-policy.js; then
        printf '%s\n' "{\"schema_version\":\"1.0\",\"defect_id\":\"missing_locale_folding_export\",\"first_review\":\"passed\",\"pre_repair_source_hash\":\"$source_hash\",\"defect_present_before_repair\":false,\"repair\":\"not_required\",\"post_repair_source_hash\":\"$source_hash\",\"defect_present_after_repair\":false,\"revalidation\":\"pending\",\"fresh_review\":\"pending\"}" >.assistant-eval/review-evidence.json
        printf '%s\n' 'Trusted review PASS: no material findings within the reviewed scope and available evidence.'
        exit 0
    fi
    printf '%s\n' "{\"schema_version\":\"1.0\",\"defect_id\":\"missing_locale_folding_export\",\"first_review\":\"failed\",\"pre_repair_source_hash\":\"$source_hash\",\"defect_present_before_repair\":true,\"repair\":\"pending\",\"post_repair_source_hash\":\"\",\"defect_present_after_repair\":true,\"revalidation\":\"pending\",\"fresh_review\":\"pending\"}" >.assistant-eval/review-evidence.json
    printf '%s\n' 'Must-fix: export LOCALE_FOLDING_LIMITATION from src/search-policy.js so the policy boundary is explicit.' >&2
    exit 1
fi

if ! grep -Fq 'LOCALE_FOLDING_LIMITATION' src/search-policy.js; then
    printf '%s\n' 'Must-fix remains: LOCALE_FOLDING_LIMITATION is missing.' >&2
    exit 1
fi
pre_repair_source_hash="$(jq -r '.pre_repair_source_hash' .assistant-eval/review-evidence.json)"
if [[ "$pre_repair_source_hash" == "$source_hash" ]]; then
    printf '%s\n' 'Trusted review rejects a no-op repair: source hash did not change.' >&2
    exit 1
fi
if [[ "$test_pass_count" -lt 2 ]]; then
    printf '%s\n' 'Trusted review requires focused revalidation after the repair.' >&2
    exit 1
fi

printf '%s\n' "{\"schema_version\":\"1.0\",\"defect_id\":\"missing_locale_folding_export\",\"first_review\":\"failed\",\"pre_repair_source_hash\":\"$pre_repair_source_hash\",\"defect_present_before_repair\":true,\"repair\":\"completed\",\"post_repair_source_hash\":\"$source_hash\",\"defect_present_after_repair\":false,\"revalidation\":\"passed\",\"fresh_review\":\"passed\"}" >.assistant-eval/review-evidence.json
printf '%s\n' 'Trusted review PASS: no material findings within the reviewed scope and available evidence.'
EOF
            chmod +x "$workspace/tests/search-contracts.sh" "$workspace/tests/review-contracts.sh"
            ;;
        clear-medium-task-zero-clarification-questions)
            mkdir -p "$workspace/tests/p0-p4"
            printf '%s\n' \
                '#!/usr/bin/env bash' \
                '# Add contract guards for clarification confidence and cap wording.' \
                'exit 0' >"$workspace/tests/p0-p4/workflow-basics-contracts.sh"
            chmod +x "$workspace/tests/p0-p4/workflow-basics-contracts.sh"
            ;;
    esac
}

execute_one_run() {
    local instruction_dir="$1"
    local instruction_hash="$2"
    local fixture_hash="$3"
    local cli_version="$4"
    local pair_id="$5"
    local case_id="$6"
    local trial_index="$7"
    local variant="$8"
    local trace_path="$OUTPUT_DIR/traces/$pair_id-$variant.json"
    local attempt_path="$OUTPUT_DIR/run-attempts/$pair_id-$variant.json"
    local run_id="$pair_id-$variant"
    local case_digest grader_digest prompt
    case_digest="$(case_hash "$case_id")"
    grader_digest="$(grader_hash "$case_id")"
    prompt="$(blind_prompt_for_case "$case_id")"

    local run_raw workspace jsonl final_output stderr_file prompt_file seed_workspace_hash
    local now remaining_total effective_timeout
    now="$(date +%s)"
    if [[ "$EVALUATION_STARTED_AT" -eq 0 ]]; then EVALUATION_STARTED_AT="$now"; fi
    remaining_total=$((TOTAL_TIMEOUT_SECONDS - (now - EVALUATION_STARTED_AT)))
    if [[ "$remaining_total" -le 0 ]]; then
        write_unavailable_trace "$trace_path" "$run_id" "$pair_id" "$case_id" "$trial_index" "$variant" \
            evaluation_time_cap_reached 124 "$fixture_hash" "$case_digest" "$instruction_hash" "$grader_digest" "$cli_version"
        mark_run_attempt_completed "$attempt_path" || die "Could not complete capped run-attempt state for $run_id."
        return
    fi
    effective_timeout="$RUN_TIMEOUT_SECONDS"
    if [[ "$remaining_total" -lt "$effective_timeout" ]]; then effective_timeout="$remaining_total"; fi
    run_raw="$(mktemp -d "$RAW_ROOT/run.XXXXXX")"
    chmod 700 "$run_raw"
    workspace="$run_raw/workspace"
    jsonl="$run_raw/events.jsonl"
    final_output="$run_raw/final-response.txt"
    stderr_file="$run_raw/stderr.txt"
    prompt_file="$run_raw/prompt.txt"
    mkdir -p "$workspace/.agents/skills/assistant-workflow"
    cp -R "$instruction_dir"/. "$workspace/.agents/skills/assistant-workflow/"
    seed_case_workspace "$workspace" "$case_id"
    seed_workspace_hash="$(hash_seed_workspace "$workspace")"
    git -C "$workspace" init -q
    git -C "$workspace" add -A
    git -C "$workspace" \
        -c user.name='Framework Eval' \
        -c user.email='eval@invalid' \
        -c commit.gpgsign=false \
        -c core.hooksPath=/dev/null \
        commit -qm eval-baseline

    local started_at ended_at latency_ms exit_code=0 timed_out=false
    validate_run_attempt_identity "$attempt_path" "$pair_id" "$case_id" "$trial_index" "$variant" \
        || die "Run-attempt state is invalid before execution: $run_id"
    [[ "$(jq -r '.state' "$attempt_path")" == "not_started" ]] \
        || die "Run-attempt state is not executable without separate retry authorization: $run_id"
    write_run_attempt_in_flight "$attempt_path" \
        || die "Could not persist in-flight state for $run_id."
    started_at="$(date +%s)"
    printf '%s' "$prompt" >"$prompt_file"
    chmod 600 "$prompt_file"
    "$CODEX_BIN" exec \
        --ephemeral \
        --ignore-user-config \
        -m "$MODEL" \
        -C "$workspace" \
        --sandbox workspace-write \
        --json \
        --output-last-message "$final_output" \
        - <"$prompt_file" >"$jsonl" 2>"$stderr_file" &
    ACTIVE_CHILD_PID=$!
    while kill -0 "$ACTIVE_CHILD_PID" 2>/dev/null; do
        now="$(date +%s)"
        if [[ $((now - started_at)) -ge "$effective_timeout" ]]; then
            timed_out=true
            exit_code=124
            terminate_active_child
            break
        fi
        sleep 0.1
    done
    if [[ "$timed_out" == false ]]; then
        if wait "$ACTIVE_CHILD_PID"; then exit_code=0; else exit_code=$?; fi
        ACTIVE_CHILD_PID=""
    fi
    rm -f "$prompt_file"
    ended_at="$(date +%s)"
    latency_ms=$(((ended_at - started_at) * 1000))

    if [[ "$exit_code" -ne 0 ]]; then
        local failure_code
        if [[ "$timed_out" == true ]]; then
            failure_code=execution_timed_out
        else
            failure_code="$(classify_codex_failure "$stderr_file" "$jsonl")"
        fi
        write_unavailable_trace "$trace_path" "$run_id" "$pair_id" "$case_id" "$trial_index" "$variant" \
            "$failure_code" "$exit_code" "$fixture_hash" "$case_digest" "$instruction_hash" "$grader_digest" "$cli_version"
        mark_run_attempt_completed "$attempt_path" || die "Could not complete run-attempt state for $run_id."
        rm -rf "$run_raw"
        return
    fi
    if ! validate_event_stream "$jsonl"; then
        write_unavailable_trace "$trace_path" "$run_id" "$pair_id" "$case_id" "$trial_index" "$variant" \
            unknown_event_shape 0 "$fixture_hash" "$case_digest" "$instruction_hash" "$grader_digest" "$cli_version"
        mark_run_attempt_completed "$attempt_path" || die "Could not complete run-attempt state for $run_id."
        rm -rf "$run_raw"
        return
    fi
    if ! jq -s -e 'any(.[]; .type == "turn.completed" and (.usage | type == "object"))' "$jsonl" >/dev/null; then
        write_unavailable_trace "$trace_path" "$run_id" "$pair_id" "$case_id" "$trial_index" "$variant" \
            missing_usage 0 "$fixture_hash" "$case_digest" "$instruction_hash" "$grader_digest" "$cli_version"
        mark_run_attempt_completed "$attempt_path" || die "Could not complete run-attempt state for $run_id."
        rm -rf "$run_raw"
        return
    fi
    if [[ ! -s "$final_output" ]] || ! grep -q '[^[:space:]]' "$final_output"; then
        write_unavailable_trace "$trace_path" "$run_id" "$pair_id" "$case_id" "$trial_index" "$variant" \
            missing_final_output 0 "$fixture_hash" "$case_digest" "$instruction_hash" "$grader_digest" "$cli_version"
        mark_run_attempt_completed "$attempt_path" || die "Could not complete run-attempt state for $run_id."
        rm -rf "$run_raw"
        return
    fi

    local semantic_extract_path=""
    if is_synthetic_seeded_case "$case_id"; then
        semantic_extract_path="$RAW_ROOT/semantic-extracts/$pair_id-$variant.json"
        normalize_semantic_response "$case_id" "$variant" "$final_output" "$semantic_extract_path"
    fi

    local input_tokens output_tokens tool_calls question_marks file_changes rework_count forbidden_command_hits=0 response_verifier workspace_verifier verifier
    input_tokens="$(jq -s '[.[] | select(.type == "turn.completed") | .usage.input_tokens] | last' "$jsonl")"
    output_tokens="$(jq -s '[.[] | select(.type == "turn.completed") | .usage.output_tokens] | last' "$jsonl")"
    tool_calls="$(jq -s '[.[] | select(.type == "item.completed") | .item.type | select(. == "command_execution" or . == "mcp_tool_call" or . == "web_search")] | length' "$jsonl")"
    question_marks="$(grep -o '?' "$final_output" 2>/dev/null | wc -l | tr -d ' ' || true)"
    question_marks="${question_marks:-0}"
    file_changes="$(jq -s '[.[] | select(.type == "item.completed" and .item.type == "file_change")] | length' "$jsonl")"
    if [[ "$file_changes" -gt 1 ]]; then rework_count=$((file_changes - 1)); else rework_count=0; fi
    if [[ "$case_id" == "codex-role-constraints-native" ]]; then
        forbidden_command_hits="$(jq -s '[.[]
          | select(.type == "item.completed" and .item.type == "command_execution")
          | (.item.command // .item.command_line // .item.text // "")
          | tostring
          | sub("^\\s*((/usr/bin/env)\\s+)?(/bin/)?(bash|zsh|sh)\\s+-[a-z]*c\\s+[\\x22\\x27]\\s*"; ""; "i")
          | select(test("(^|[;&|]+\\s*)(npm\\s+(run\\s+)?test|pnpm\\s+(run\\s+)?test|yarn\\s+test|dotnet\\s+test|cargo\\s+test|go\\s+test|pytest|python(3)?\\s+-m\\s+pytest|jest|vitest|mocha|rspec|mvn\\s+test|gradle\\s+test|\\./gradlew\\s+test|bash\\s+[^;&|]*tests?/)(\\s|[\\x22\\x27]|$)"; "i"))
        ] | length' "$jsonl")"
    fi
    response_verifier="$(grade_response "$case_id" "$final_output" "$semantic_extract_path")"
    workspace_verifier="$(verify_workspace "$case_id" "$workspace" "$jsonl")"
    verifier="$(jq -cn \
        --argjson response "$response_verifier" \
        --argjson workspace "$workspace_verifier" \
        --argjson forbidden_command_hits "$forbidden_command_hits" '
      {
        status: (if $response.status == "passed" and ($workspace.status == "passed" or $workspace.status == "not_applicable") and $forbidden_command_hits == 0 then "passed" else "failed" end),
        required_missing: $response.required_missing,
        forbidden_hits: $response.forbidden_hits,
        fail_signal_hits: $response.fail_signal_hits,
        missing_required_ids: $response.missing_required_ids,
        forbidden_hit_ids: $response.forbidden_hit_ids,
        fail_signal_hit_ids: $response.fail_signal_hit_ids,
        seeded_defect_missed_ids: $response.seeded_defect_missed_ids,
        false_positive_marker_hit_ids: $response.false_positive_marker_hit_ids,
        workspace_failure_ids: $workspace.workspace_failure_ids,
        acceptance_items_total: ($response.acceptance_items_total + $workspace.acceptance_items_total),
        acceptance_items_passed: ($response.acceptance_items_passed + $workspace.acceptance_items_passed),
        seeded_defects_total: $response.seeded_defects_total,
        seeded_defects_detected: $response.seeded_defects_detected,
        false_positive_marker_hits: $response.false_positive_marker_hits,
        forbidden_command_hits: $forbidden_command_hits,
        workspace_status: $workspace.status,
        workspace_exit_code: $workspace.exit_code,
        scope_deviations: $workspace.scope_deviations
      }
    ')"

    local sanitized_trace="$run_raw/sanitized-trace.json"
    jq -n \
        --arg run_id "$run_id" \
        --arg pair_id "$pair_id" \
        --arg case_id "$case_id" \
        --arg variant "$variant" \
        --arg model "$MODEL" \
        --arg fixture_sha256 "$fixture_hash" \
        --arg case_sha256 "$case_digest" \
        --arg instruction_sha256 "$instruction_hash" \
        --arg grader_sha256 "$grader_digest" \
        --arg seed_workspace_sha256 "$seed_workspace_hash" \
        --arg cli_version "$cli_version" \
        --arg model_selection_evidence "$(if [[ "$MODEL_SELECTION_METHOD" == "codex_debug_models_requested_entry" ]]; then echo catalog_entry_and_explicit_model_argument; else echo explicit_model_argument_only; fi)" \
        --arg requested_model_catalog_entry_sha256 "$MODEL_CATALOG_ENTRY_SHA256" \
        --arg codex_executable_sha256 "$CODEX_EXECUTABLE_SHA256" \
        --arg adapter_version "$ADAPTER_VERSION" \
        --argjson trial_index "$trial_index" \
        --argjson input_tokens "$input_tokens" \
        --argjson output_tokens "$output_tokens" \
        --argjson latency_ms "$latency_ms" \
        --argjson tool_calls "$tool_calls" \
        --argjson question_mark_count_proxy "$question_marks" \
        --argjson rework_count "$rework_count" \
        --argjson verifier "$verifier" '
      {
        schema_version: "1.0",
        run_id: $run_id,
        pair_id: $pair_id,
        trial_index: $trial_index,
        case_id: $case_id,
        model: $model,
        variant: $variant,
        status: "completed",
        metrics: {
          input_tokens: $input_tokens,
          output_tokens: $output_tokens,
          latency_ms: $latency_ms,
          tool_calls: $tool_calls,
          question_mark_count_proxy: $question_mark_count_proxy,
          time_to_first_useful_action_ms: $latency_ms,
          rework_count: $rework_count,
          acceptance_passed: ($verifier.status == "passed"),
          acceptance_items_passed: $verifier.acceptance_items_passed,
          acceptance_items_total: $verifier.acceptance_items_total,
          seeded_defects_total: $verifier.seeded_defects_total,
          seeded_defects_detected: $verifier.seeded_defects_detected,
          false_positive_marker_hits: $verifier.false_positive_marker_hits,
          forbidden_command_hits: $verifier.forbidden_command_hits,
          scope_deviations: $verifier.scope_deviations,
          verifier_exit_code: $verifier.workspace_exit_code
        },
        provenance: {
          fixture_sha256: $fixture_sha256,
          case_sha256: $case_sha256,
          instruction_sha256: $instruction_sha256,
          grader_sha256: $grader_sha256,
          seed_workspace_sha256: $seed_workspace_sha256,
          cli_version: $cli_version,
          requested_model: $model,
          runtime_model_attestation: "not_exposed_by_codex_jsonl",
          model_selection_evidence: $model_selection_evidence,
          requested_model_catalog_entry_sha256: (if $requested_model_catalog_entry_sha256 == "" then null else $requested_model_catalog_entry_sha256 end),
          codex_executable_sha256: (if $codex_executable_sha256 == "" then null else $codex_executable_sha256 end),
          adapter_version: $adapter_version
        },
        execution: {
          exit_code: 0,
          verifier: $verifier,
          metric_methods: {
            time_to_first_useful_action_ms: "completion_latency_upper_bound",
            question_mark_count_proxy: "question_mark_count_proxy",
            rework_count: "additional_file_change_events_proxy"
          },
          raw_artifacts_retained: false
        }
      }
    ' >"$sanitized_trace"

    if is_synthetic_seeded_case "$case_id"; then
        local checkpoint_path="$OUTPUT_DIR/semantic-checkpoints/$pair_id-$variant.json"
        write_semantic_checkpoint "$checkpoint_path" "$pair_id" "$case_id" "$trial_index" "$variant" \
            "$sanitized_trace" "$semantic_extract_path" \
            || die "Could not persist a bounded semantic checkpoint for $run_id."
        jq -cS --arg checkpoint_sha256 "$(hash_file "$checkpoint_path")" \
            '.execution.semantic_checkpoint_sha256 = $checkpoint_sha256' "$sanitized_trace" \
            | durable_atomic_write_json "$trace_path"
    else
        jq -cS . "$sanitized_trace" | durable_atomic_write_json "$trace_path"
    fi

    mark_run_attempt_completed "$attempt_path" || die "Could not complete run-attempt state for $run_id."

    rm -rf "$run_raw"
}

write_semantic_review_packet() {
    [[ -n "$CANDIDATE_MANIFEST" ]] || return 0

    local case_ids_file="$RAW_ROOT/semantic-case-ids.txt"
    local pairs_file="$RAW_ROOT/semantic-pairs.jsonl"
    local diagnostics_file="$RAW_ROOT/semantic-diagnostics.jsonl"
    local reasons_file="$RAW_ROOT/semantic-reasons.txt"
    : >"$case_ids_file"
    : >"$pairs_file"
    : >"$diagnostics_file"
    : >"$reasons_file"

    jq -r --slurpfile fixture "$FIXTURE" '
      [.runs[].case_id] | unique[] as $id
      | select(any($fixture[0].cases[];
          .id == $id
          and .category == "seeded_review"
          and .data_classification == "synthetic"))
      | $id
    ' "$OUTPUT_DIR/run-plan.json" >"$case_ids_file"

    local case_id pair_id baseline_extract candidate_extract baseline_trace candidate_trace
    local reason baseline_seed candidate_seed pair_json pair_hash baseline_trace_hash candidate_trace_hash trial_index
    local diagnostic_json diagnostic_hash diagnostic_variant diagnostic_extract diagnostic_status diagnostic_reason
    while IFS= read -r case_id; do
        [[ -n "$case_id" ]] || continue
        while IFS= read -r pair_id; do
            [[ -n "$pair_id" ]] || continue
            baseline_extract="$RAW_ROOT/semantic-extracts/$pair_id-baseline.json"
            candidate_extract="$RAW_ROOT/semantic-extracts/$pair_id-candidate.json"
            baseline_trace="$OUTPUT_DIR/traces/$pair_id-baseline.json"
            candidate_trace="$OUTPUT_DIR/traces/$pair_id-candidate.json"

            if [[ ! -f "$baseline_extract" || ! -f "$candidate_extract" \
                || ! -f "$baseline_trace" || ! -f "$candidate_trace" ]] \
                || ! jq -e '.status == "completed"' "$baseline_trace" >/dev/null 2>&1 \
                || ! jq -e '.status == "completed"' "$candidate_trace" >/dev/null 2>&1; then
                printf '%s\n' missing_or_incomplete_seeded_pair >>"$reasons_file"
                continue
            fi

            baseline_seed="$(jq -r '.provenance.seed_workspace_sha256 // ""' "$baseline_trace")"
            candidate_seed="$(jq -r '.provenance.seed_workspace_sha256 // ""' "$candidate_trace")"
            if [[ ! "$baseline_seed" =~ ^[0-9a-f]{64}$ || "$baseline_seed" != "$candidate_seed" ]]; then
                printf '%s\n' fixture_hash_mismatch >>"$reasons_file"
                continue
            fi

            baseline_trace_hash="$(hash_file "$baseline_trace")"
            candidate_trace_hash="$(hash_file "$candidate_trace")"
            trial_index="$(jq -r '.trial_index' "$baseline_trace")"
            reason="$(jq -r 'select(.status != "ready") | .reason_code' "$baseline_extract" "$candidate_extract" | sed -n '1p')"
            if [[ -n "$reason" ]]; then
                printf '%s\n' "$reason" >>"$reasons_file"
                for diagnostic_variant in baseline candidate; do
                    if [[ "$diagnostic_variant" == "baseline" ]]; then
                        diagnostic_extract="$baseline_extract"
                        baseline_trace_hash="$(hash_file "$baseline_trace")"
                    else
                        diagnostic_extract="$candidate_extract"
                        candidate_trace_hash="$(hash_file "$candidate_trace")"
                    fi
                    diagnostic_status="$(jq -r '.status' "$diagnostic_extract")"
                    diagnostic_reason="$(jq -r 'if .status == "ready" then "paired_variant_blocked" else .reason_code end' "$diagnostic_extract")"
                    diagnostic_json="$(jq -cn \
                        --arg pair_id "$pair_id" \
                        --arg case_id "$case_id" \
                        --argjson trial_index "$trial_index" \
                        --arg variant "$diagnostic_variant" \
                        --arg status "$diagnostic_status" \
                        --arg reason_code "$diagnostic_reason" \
                        --arg case_sha256 "$(case_hash "$case_id")" \
                        --arg grader_sha256 "$(grader_hash "$case_id")" \
                        --arg seed_workspace_sha256 "$baseline_seed" \
                        --arg trace_sha256 "$(if [[ "$diagnostic_variant" == "baseline" ]]; then printf '%s' "$baseline_trace_hash"; else printf '%s' "$candidate_trace_hash"; fi)" \
                        --slurpfile extract "$diagnostic_extract" '
                      {
                        pair_id:$pair_id,
                        case_id:$case_id,
                        trial_index:$trial_index,
                        variant:$variant,
                        status:$status,
                        reason_code:$reason_code,
                        case_sha256:$case_sha256,
                        grader_sha256:$grader_sha256,
                        seed_workspace_sha256:$seed_workspace_sha256,
                        trace_sha256:$trace_sha256,
                        classified_claim_codes:([$extract[0].findings[].claim_code] | unique | sort),
                        finding_failures:$extract[0].finding_failures
                      }
                    ')"
                    diagnostic_hash="$(printf '%s' "$diagnostic_json" | jq -cS . | hash_stream)"
                    printf '%s' "$diagnostic_json" | jq -c --arg hash "$diagnostic_hash" '. + {diagnostic_sha256:$hash}' >>"$diagnostics_file"
                done
                continue
            fi

            pair_json="$(jq -cn \
                --arg pair_id "$pair_id" \
                --arg case_id "$case_id" \
                --argjson trial_index "$trial_index" \
                --arg case_sha256 "$(case_hash "$case_id")" \
                --arg grader_sha256 "$(grader_hash "$case_id")" \
                --arg seed_workspace_sha256 "$baseline_seed" \
                --arg candidate_manifest_sha256 "$CANDIDATE_MANIFEST_HASH" \
                --arg baseline_instruction_sha256 "$baseline_hash" \
                --arg candidate_instruction_sha256 "$candidate_hash" \
                --arg baseline_trace_sha256 "$baseline_trace_hash" \
                --arg candidate_trace_sha256 "$candidate_trace_hash" \
                --slurpfile baseline "$baseline_extract" \
                --slurpfile candidate "$candidate_extract" '
              {
                pair_id: $pair_id,
                case_id: $case_id,
                trial_index: $trial_index,
                case_sha256: $case_sha256,
                grader_sha256: $grader_sha256,
                seed_workspace_sha256: $seed_workspace_sha256,
                bindings: {
                  candidate_manifest_sha256: $candidate_manifest_sha256,
                  baseline_instruction_sha256: $baseline_instruction_sha256,
                  candidate_instruction_sha256: $candidate_instruction_sha256
                },
                baseline: {trace_sha256:$baseline_trace_sha256,findings:$baseline[0].findings},
                candidate: {trace_sha256:$candidate_trace_sha256,findings:$candidate[0].findings}
              }
            ')"
            pair_hash="$(printf '%s' "$pair_json" | jq -cS . | hash_stream)"
            printf '%s' "$pair_json" | jq -c --arg pair_hash "$pair_hash" '. + {pair_sha256:$pair_hash}' >>"$pairs_file"
        done < <(jq -r --arg id "$case_id" '.runs[] | select(.case_id == $id) | .pair_id' "$OUTPUT_DIR/run-plan.json" | LC_ALL=C sort -u)
    done <"$case_ids_file"

    local case_ids_json pairs_json diagnostics_json reasons_json review_status
    case_ids_json="$(jq -R -s 'split("\n") | map(select(length > 0))' "$case_ids_file")"
    pairs_json="$(jq -s . "$pairs_file")"
    diagnostics_json="$(jq -s . "$diagnostics_file")"
    reasons_json="$(LC_ALL=C sort -u "$reasons_file" | jq -R -s 'split("\n") | map(select(length > 0))')"
    if [[ "$(jq 'length' <<<"$case_ids_json")" -eq 0 ]]; then
        review_status=blocked
        reasons_json='["missing_synthetic_seeded_review_scope"]'
        pairs_json='[]'
        diagnostics_json='[]'
    elif [[ "$(jq 'length' <<<"$reasons_json")" -gt 0 ]]; then
        review_status=blocked
        pairs_json='[]'
    else
        review_status=ready
    fi

    jq -n \
        --arg review_status "$review_status" \
        --arg run_plan_sha256 "$(hash_file "$OUTPUT_DIR/run-plan.json")" \
        --arg comparison_sha256 "$(hash_file "$OUTPUT_DIR/comparison.json")" \
        --arg fixture_sha256 "$fixture_hash" \
        --arg candidate_manifest_sha256 "$CANDIDATE_MANIFEST_HASH" \
        --arg baseline_instruction_sha256 "$baseline_hash" \
        --arg candidate_instruction_sha256 "$candidate_hash" \
        --arg context_budget_evidence_sha256 "$CONTEXT_BUDGET_EVIDENCE_HASH" \
        --arg synthetic_fixture_ref "$SYNTHETIC_FIXTURE_REF" \
        --arg synthetic_fixture_sha256 "$(hash_directory "$SYNTHETIC_FIXTURE_DIR")" \
        --argjson case_ids "$case_ids_json" \
        --argjson reasons "$reasons_json" \
        --argjson pairs "$pairs_json" \
        --argjson diagnostics "$diagnostics_json" '
      {
        schema_version: "1.0",
        review_kind: "workflow_kernel_semantic_false_positive",
        scope: {
          data_classification: "synthetic",
          case_category: "seeded_review",
          case_ids: $case_ids,
          synthetic_fixture_ref: $synthetic_fixture_ref,
          synthetic_fixture_sha256: $synthetic_fixture_sha256,
          raw_artifacts_retained: false
        },
        bindings: {
          run_plan_sha256: $run_plan_sha256,
          comparison_sha256: $comparison_sha256,
          fixture_sha256: $fixture_sha256,
          candidate_manifest_sha256: $candidate_manifest_sha256,
          baseline_instruction_sha256: $baseline_instruction_sha256,
          candidate_instruction_sha256: $candidate_instruction_sha256,
          context_budget_evidence_sha256: $context_budget_evidence_sha256
        },
        reviewability: {status:$review_status,reason_codes:$reasons},
        pairs: $pairs,
        diagnostics: $diagnostics
      }
    ' | atomic_write_json "$OUTPUT_DIR/semantic-review-packet.json"
}

write_comparison() {
    local manifest_json='{}'
    if [[ -n "$CANDIDATE_MANIFEST" && -f "$CANDIDATE_MANIFEST" ]]; then
        manifest_json="$(jq -c . "$CANDIDATE_MANIFEST")"
    fi
    jq -s \
        --argjson manifest "$manifest_json" \
        --arg candidate_manifest_sha256 "$CANDIDATE_MANIFEST_HASH" \
        -f "$SCRIPT_DIR/lib/framework-comparison.jq" \
        "$OUTPUT_DIR"/traces/*.json | atomic_write_json "$OUTPUT_DIR/comparison.json"
}
if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --execute) MODE="execute"; shift ;;
        --resume) RESUME=true; shift ;;
        --model) [[ $# -ge 2 ]] || die "Missing value for --model."; MODEL="$2"; shift 2 ;;
        --baseline-variant) [[ $# -ge 2 ]] || die "Missing directory for --baseline-variant."; BASELINE_VARIANT="$2"; shift 2 ;;
        --candidate-variant) [[ $# -ge 2 ]] || die "Missing directory for --candidate-variant."; CANDIDATE_VARIANT="$2"; shift 2 ;;
        --cases) [[ $# -ge 2 ]] || die "Missing value for --cases."; CASES="$2"; shift 2 ;;
        --repeats) [[ $# -ge 2 ]] || die "Missing value for --repeats."; REPEATS="$2"; shift 2 ;;
        --run-timeout-seconds) [[ $# -ge 2 ]] || die "Missing value for --run-timeout-seconds."; RUN_TIMEOUT_SECONDS="$2"; shift 2 ;;
        --total-timeout-seconds) [[ $# -ge 2 ]] || die "Missing value for --total-timeout-seconds."; TOTAL_TIMEOUT_SECONDS="$2"; shift 2 ;;
        --model-catalog-timeout-seconds) [[ $# -ge 2 ]] || die "Missing value for --model-catalog-timeout-seconds."; MODEL_CATALOG_TIMEOUT_SECONDS="$2"; shift 2 ;;
        --output) [[ $# -ge 2 ]] || die "Missing directory for --output."; OUTPUT_DIR="$2"; shift 2 ;;
        --codex-bin) [[ $# -ge 2 ]] || die "Missing path for --codex-bin."; CODEX_BIN="$2"; CODEX_BIN_OVERRIDDEN=true; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
done

require_jq
[[ -f "$FIXTURE" ]] || die "Fixture not found: $FIXTURE"
[[ -n "$MODEL" ]] || die "--model must be non-empty."
[[ "$REPEATS" =~ ^[0-9]+$ ]] && [[ "$REPEATS" -ge 1 ]] && [[ "$REPEATS" -le 20 ]] \
    || die "--repeats must be an integer from 1 through 20."
[[ "$RUN_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] && [[ "$RUN_TIMEOUT_SECONDS" -ge 1 ]] && [[ "$RUN_TIMEOUT_SECONDS" -le 3600 ]] \
    || die "--run-timeout-seconds must be an integer from 1 through 3600."
[[ "$TOTAL_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] && [[ "$TOTAL_TIMEOUT_SECONDS" -ge 1 ]] && [[ "$TOTAL_TIMEOUT_SECONDS" -le 21600 ]] \
    || die "--total-timeout-seconds must be an integer from 1 through 21600."
[[ "$MODEL_CATALOG_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] && [[ "$MODEL_CATALOG_TIMEOUT_SECONDS" -ge 1 ]] && [[ "$MODEL_CATALOG_TIMEOUT_SECONDS" -le 120 ]] \
    || die "--model-catalog-timeout-seconds must be an integer from 1 through 120."
[[ -n "$BASELINE_VARIANT" ]] || die "--baseline-variant is required."
[[ -n "$CANDIDATE_VARIANT" ]] || die "--candidate-variant is required."
[[ -n "$OUTPUT_DIR" ]] || die "--output is required."
[[ "$RESUME" == false || "$MODE" == "execute" ]] || die "--resume is valid only with --execute."
[[ ! -L "$OUTPUT_DIR" ]] || die "--output must not be a symlink."
output_parent="$(dirname "$OUTPUT_DIR")"
output_name="$(basename "$OUTPUT_DIR")"
[[ "$output_name" != "." && "$output_name" != ".." ]] || die "--output must name a child directory."
[[ -d "$output_parent" ]] || die "--output parent must already exist and be a directory."
output_parent="$(cd "$output_parent" && pwd -P)"
OUTPUT_DIR="$output_parent/$output_name"
[[ ! -L "$OUTPUT_DIR" ]] || die "--output must not be a symlink."

baseline_overlay="$(resolve_overlay_file "$BASELINE_VARIANT")"
candidate_overlay="$(resolve_overlay_file "$CANDIDATE_VARIANT")"
if [[ -f "$(dirname "$candidate_overlay")/manifest.json" ]]; then
    CANDIDATE_MANIFEST="$(dirname "$candidate_overlay")/manifest.json"
    CANDIDATE_MANIFEST_HASH="$(hash_file "$CANDIDATE_MANIFEST")"
fi
validate_candidate_manifest
validate_synthetic_fixture
selected_case_ids >/dev/null
preflight_macos_seatbelt
WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-framework-eval-variants.XXXXXX")"
chmod 700 "$WORK_ROOT"
trap cleanup_all EXIT
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM
baseline_dir="$WORK_ROOT/baseline"
candidate_dir="$WORK_ROOT/candidate"
materialize_variant "$baseline_overlay" "$baseline_dir"
materialize_variant "$candidate_overlay" "$candidate_dir"
baseline_hash="$(hash_directory "$baseline_dir")"
candidate_hash="$(hash_directory "$candidate_dir")"
fixture_hash="$(hash_file "$FIXTURE")"
CONTEXT_BUDGET_EVIDENCE_FILE="$WORK_ROOT/context-budget-evidence.json"
context_budget_build_evidence \
    "$REPO_ROOT/tools/context-budget-report.sh" \
    "$baseline_dir/SKILL.md" "$candidate_dir/SKILL.md" "$baseline_hash" "$candidate_hash" \
    "$CONTEXT_BUDGET_EVIDENCE_FILE" \
    || die "Could not generate fresh context-budget evidence from the exact baseline and candidate snapshots."
context_budget_validate_evidence_structure "$CONTEXT_BUDGET_EVIDENCE_FILE" \
    || die "Fresh context-budget evidence is structurally invalid."
CONTEXT_BUDGET_EVIDENCE_HASH="$(hash_file "$CONTEXT_BUDGET_EVIDENCE_FILE")"
if [[ -n "$CANDIDATE_MANIFEST" ]]; then
    context_budget_validate_promotion_policy "$CONTEXT_BUDGET_EVIDENCE_FILE" \
        || die "Fresh context-budget evidence violates workflow-kernel promotion caps or standing-context policy."
    context_budget_validate_manifest "$CANDIDATE_MANIFEST" "$CONTEXT_BUDGET_EVIDENCE_FILE" \
        || die "Candidate manifest does not match fresh context-budget evidence."
fi

prepare_model_selection_evidence
expected_plan="$WORK_ROOT/expected-run-plan.json"
write_plan "$baseline_hash" "$candidate_hash" "$fixture_hash" "$expected_plan"
RUN_PLAN_HASH="$(hash_file "$expected_plan")"
if [[ "$RESUME" == true ]]; then
    validate_resume_output "$expected_plan"
else
    if [[ -d "$OUTPUT_DIR" ]] && find "$OUTPUT_DIR" -mindepth 1 -print -quit | grep -q .; then
        die "--output must be empty or not yet exist: $OUTPUT_DIR"
    fi
    mkdir -p "$OUTPUT_DIR"
    [[ -d "$OUTPUT_DIR" && ! -L "$OUTPUT_DIR" ]] || die "--output must resolve to a real directory."
    chmod 700 "$OUTPUT_DIR"
    atomic_write_json "$OUTPUT_DIR/run-plan.json" <"$expected_plan"
fi

if [[ "$MODE" == "plan" ]]; then
    echo "Planned paired Codex evals without model execution: $OUTPUT_DIR/run-plan.json"
    cleanup_all
    WORK_ROOT=""
    trap - EXIT INT TERM
    exit 0
fi

mkdir -p "$OUTPUT_DIR/traces" "$OUTPUT_DIR/semantic-checkpoints" "$OUTPUT_DIR/run-attempts"
fsync_path "$OUTPUT_DIR"
fsync_path "$(dirname "$OUTPUT_DIR")"
if [[ "$RESUME" == false ]]; then
    initialize_run_attempts
else
    enforce_incomplete_pair_breaker
fi
EVALUATION_STARTED_AT="$(jq -s '[.[].attempt_started_at[]] | min // 0' "$OUTPUT_DIR/run-attempts/"*.json)"
if [[ "$EVALUATION_STARTED_AT" -eq 0 ]]; then EVALUATION_STARTED_AT="$(date +%s)"; fi
if [[ "$CODEX_BIN" == */* ]]; then
    codex_available=false
    [[ -x "$CODEX_BIN" ]] && codex_available=true
else
    codex_available=false
    command -v "$CODEX_BIN" >/dev/null 2>&1 && codex_available=true
fi

if [[ "$codex_available" == "false" ]]; then
    while IFS=$'\t' read -r pair_id case_id trial_index variant instruction_hash; do
        [[ -f "$OUTPUT_DIR/traces/$pair_id-$variant.json" ]] && continue
        write_unavailable_trace \
            "$OUTPUT_DIR/traces/$pair_id-$variant.json" \
            "$pair_id-$variant" "$pair_id" "$case_id" "$trial_index" "$variant" \
            codex_not_found 127 "$fixture_hash" "$(case_hash "$case_id")" \
            "$instruction_hash" "$(grader_hash "$case_id")" unavailable
        mark_run_attempt_completed "$OUTPUT_DIR/run-attempts/$pair_id-$variant.json" \
            || die "Could not complete unavailable run-attempt state for $pair_id-$variant."
    done < <(jq -r '.runs[] | [.pair_id, .case_id, .trial_index, .variant, .instruction_sha256] | @tsv' "$OUTPUT_DIR/run-plan.json")
    write_comparison
    echo "Codex was unavailable; wrote redacted paired diagnostics to $OUTPUT_DIR"
    cleanup_all
    WORK_ROOT=""
    trap - EXIT INT TERM
    exit 0
fi

cli_version="$CLI_VERSION"
RAW_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-framework-evals.XXXXXX")"
chmod 700 "$RAW_ROOT"
mkdir -p "$RAW_ROOT/semantic-extracts"
while IFS=$'\t' read -r pair_id case_id trial_index variant instruction_hash execution_position; do
    if [[ ! -f "$OUTPUT_DIR/traces/$pair_id-$variant.json" ]]; then
        if [[ "$variant" == "baseline" ]]; then
            instruction_dir="$baseline_dir"
        else
            instruction_dir="$candidate_dir"
        fi
        execute_one_run "$instruction_dir" "$instruction_hash" "$fixture_hash" "$cli_version" \
            "$pair_id" "$case_id" "$trial_index" "$variant"
    fi
    if [[ "$execution_position" -eq 2 ]]; then
        verify_model_selection_evidence_unchanged
        enforce_incomplete_pair_breaker
    fi
done < <(jq -r '.runs[] | [.pair_id, .case_id, .trial_index, .variant, .instruction_sha256, .execution_position] | @tsv' "$OUTPUT_DIR/run-plan.json")

verify_model_selection_evidence_unchanged
write_comparison
prepare_semantic_extracts_from_checkpoints
write_semantic_review_packet
cleanup_raw_root
RAW_ROOT=""
cleanup_all
WORK_ROOT=""
trap - EXIT INT TERM
echo "Wrote redacted paired Codex eval results to $OUTPUT_DIR"
