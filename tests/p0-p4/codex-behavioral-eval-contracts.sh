#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

runner="$FRAMEWORK_DIR/tools/evals/run-codex-framework-evals.sh"
semantic_finalizer="$FRAMEWORK_DIR/tools/evals/finalize-workflow-kernel-review.sh"
legacy_runner="$FRAMEWORK_DIR/tools/evals/run-framework-instruction-evals.sh"
schema="$FRAMEWORK_DIR/docs/evals/framework-instruction-trace-result.schema.json"
semantic_packet_schema="$FRAMEWORK_DIR/docs/evals/framework-semantic-review-packet.schema.json"
semantic_verdict_schema="$FRAMEWORK_DIR/docs/evals/framework-semantic-review-verdict.schema.json"
promotion_decision_schema="$FRAMEWORK_DIR/docs/evals/framework-promotion-decision.schema.json"
comparison_program="$FRAMEWORK_DIR/tools/evals/lib/framework-comparison.jq"

test_sha256_stream() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    else
        shasum -a 256 | awk '{print $1}'
    fi
}

test_sha256_directory() {
    local directory="$1" inventory="" file relative digest
    while IFS= read -r file; do
        relative="${file#"$directory"/}"
        digest="$(test_sha256_stream <"$file")"
        inventory+="$relative $digest"$'\n'
    done < <(find "$directory" -type f -print | LC_ALL=C sort)
    printf '%s' "$inventory" | test_sha256_stream
}

fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-behavioral-eval-test.XXXXXX")"
p0p4_register_cleanup "$fixture_root"
baseline="$fixture_root/baseline"
candidate="$fixture_root/candidate"
capture="$fixture_root/capture"
mkdir -p "$baseline" "$candidate" "$capture"
cp "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md" "$baseline/SKILL.md"
cp "$FRAMEWORK_DIR/docs/evals/variants/workflow-kernel-v1/SKILL.md" "$candidate/SKILL.md"
mkdir -p "$baseline/evals" "$candidate/evals"
printf '%s\n' '{"secret":"baseline grader anchor"}' >"$baseline/evals/cases.json"
printf '%s\n' '{"secret":"candidate grader anchor"}' >"$candidate/evals/cases.json"
cp "$FRAMEWORK_DIR/docs/evals/variants/workflow-kernel-v1/manifest.json" "$candidate/manifest.json"

fake_codex="$fixture_root/fake-codex"
cat >"$fake_codex" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
    printf '%s\n' "${FAKE_CODEX_VERSION:-codex-cli 9.9.9-test}"
    exit 0
fi
if [[ "${1:-}" == "debug" && "${2:-}" == "models" ]]; then
    catalog_mode="${FAKE_CATALOG_MODE:-valid}"
    if [[ "$catalog_mode" == "changes_after_preflight" || "$catalog_mode" == "hang_after_preflight" ]]; then
        catalog_count_file="${FAKE_CODEX_CAPTURE_DIR:?}/catalog-query-count"
        catalog_count=0
        [[ ! -f "$catalog_count_file" ]] || catalog_count="$(cat "$catalog_count_file")"
        printf '%s\n' "$((catalog_count + 1))" >"$catalog_count_file"
        if [[ "$catalog_count" -eq 0 ]]; then
            catalog_mode=valid
        elif [[ "$catalog_mode" == "changes_after_preflight" ]]; then
            catalog_mode=changed
        else
            catalog_mode=hang
        fi
    fi
    case "$catalog_mode" in
        valid)
            printf '%s\n' '{"models":[{"slug":"gpt-5.6-terra","display_name":"GPT-5.6-Terra","visibility":"list","supported_in_api":true,"test_revision":1},{"slug":"gpt-5.6-sol","display_name":"GPT-5.6-Sol","visibility":"list","supported_in_api":true,"test_revision":1}]}'
            ;;
        changed)
            printf '%s\n' '{"models":[{"slug":"gpt-5.6-terra","display_name":"GPT-5.6-Terra","visibility":"list","supported_in_api":true,"test_revision":2},{"slug":"gpt-5.6-sol","display_name":"GPT-5.6-Sol","visibility":"list","supported_in_api":true,"test_revision":1}]}'
            ;;
        missing)
            printf '%s\n' '{"models":[{"slug":"gpt-5.6-sol","display_name":"GPT-5.6-Sol","visibility":"list","supported_in_api":true,"test_revision":1}]}'
            ;;
        duplicate)
            printf '%s\n' '{"models":[{"slug":"gpt-5.6-terra","test_revision":1},{"slug":"gpt-5.6-terra","test_revision":1}]}'
            ;;
        malformed)
            printf '%s\n' '{"models":['
            ;;
        oversize)
            head -c 5000000 /dev/zero | tr '\0' 'x'
            ;;
        hang)
            python3 -c 'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)' &
            catalog_child_pid=$!
            printf '%s\n' "$catalog_child_pid" >"${FAKE_CODEX_CAPTURE_DIR:?}/catalog-child-pid"
            wait "$catalog_child_pid"
            ;;
        *)
            printf 'unsupported FAKE_CATALOG_MODE: %s\n' "$catalog_mode" >&2
            exit 2
            ;;
    esac
    exit 0
fi

capture_dir="${FAKE_CODEX_CAPTURE_DIR:?}"
mkdir -p "$capture_dir"
call_id="$(find "$capture_dir" -maxdepth 1 -name 'call-*.args' | wc -l | tr -d ' ')"
args_file="$capture_dir/call-$call_id.args"
printf '%s\n' "$@" >"$args_file"

workspace=''
last_message=''
prompt=''
while [[ $# -gt 0 ]]; do
    case "$1" in
        -C|--cd)
            workspace="$2"
            shift 2
            ;;
        --output-last-message)
            last_message="$2"
            shift 2
            ;;
        -m|--model|--sandbox)
            shift 2
            ;;
        exec|--ephemeral|--ignore-user-config|--json)
            shift
            ;;
        *)
            prompt="$1"
            shift
            ;;
    esac
done

if [[ "$prompt" == "-" ]]; then
    prompt="$(cat)"
fi

if [[ "${FAKE_CODEX_BLOCK_AFTER_INVOCATION:-false}" == "true" ]]; then
    printf '%s\n' "$$" >"$capture_dir/call-$call_id.pid"
    while true; do
        sleep 1
    done
fi

if [[ -n "${FAKE_CODEX_FAILURE_MESSAGE:-}" ]]; then
    printf '%s\n' "$FAKE_CODEX_FAILURE_MESSAGE" >&2
    exit 1
fi

if [[ -n "${FAKE_CODEX_FAILURE_EVENT_MESSAGE:-}" ]]; then
    jq -cn \
        --arg type "${FAKE_CODEX_FAILURE_EVENT_TYPE:-error}" \
        --arg message "$FAKE_CODEX_FAILURE_EVENT_MESSAGE" \
        '{type: $type, error: {message: $message}}'
    if [[ -n "${FAKE_CODEX_FAILURE_STDERR:-}" ]]; then
        printf '%s\n' "$FAKE_CODEX_FAILURE_STDERR" >&2
    fi
    exit 1
fi

if [[ -n "${FAKE_CODEX_ITEM_FAILURE_MESSAGE:-}" ]]; then
    jq -cn \
        --arg message "$FAKE_CODEX_ITEM_FAILURE_MESSAGE" \
        '{type: "item.completed", item: {id: "item-failure", type: "agent_message", text: $message}}'
    if [[ -n "${FAKE_CODEX_FAILURE_STDERR:-}" ]]; then
        printf '%s\n' "$FAKE_CODEX_FAILURE_STDERR" >&2
    fi
    exit 1
fi

if [[ "${FAKE_CODEX_OVERSIZED_FAILURE_STREAM:-false}" == "true" ]]; then
    printf '%s' '{"type":"item.completed","item":{"id":"oversized","type":"agent_message","text":"'
    head -c 4195000 /dev/zero | tr '\0' x
    printf '%s\n' '"}}'
    printf '%s\n' '{"type":"error","error":{"message":"authentication failed beyond diagnostic byte cap"}}'
    exit 1
fi

if [[ "${FAKE_CODEX_DEEP_FAILURE_STREAM:-false}" == "true" ]]; then
    python3 -c 'print("{\"type\":\"error\",\"error\":" + "[" * 256 + "\"private-deep-detail\"" + "]" * 256 + "}")'
    exit 1
fi

printf '%s' "$prompt" >"$capture_dir/call-$call_id.prompt"
if [[ -f "$workspace/docs/usage.md" ]]; then
    printf '%s\n' 'docs-usage-present' >>"$capture_dir/call-$call_id.fixtures"
    sed -i.bak 's/teh/the/g' "$workspace/docs/usage.md"
    rm -f "$workspace/docs/usage.md.bak"
    if [[ "${FAKE_WRONG_SMALL_EDIT:-false}" == "true" ]]; then
        printf '%s\n' 'This fixture contains the wrong change.' >"$workspace/docs/usage.md"
    fi
    mkdir -p "$workspace/.assistant-eval"
    small_plan_mode=none
    if grep -Fq 'candidate instruction marker' "$workspace/.agents/skills/assistant-workflow/SKILL.md"; then
        small_plan_mode="${FAKE_SMALL_PLAN_MODE:-none}"
    fi
    printf '%s\n' "{\"schema_version\":\"1.0\",\"task_size\":\"trivial\",\"plan_mode\":\"$small_plan_mode\"}" >"$workspace/.assistant-eval/workflow-decision.json"
fi
if [[ -f "$workspace/.agents/skills/assistant-workflow/contracts/index.yaml" ]] \
    && [[ -f "$workspace/.agents/skills/assistant-workflow/references/phases.md" ]]; then
    printf '%s\n' 'canonical-skill-surfaces-present' >>"$capture_dir/call-$call_id.fixtures"
    if ! grep -R -Fq '{agent_state_dir}' "$workspace/.agents/skills/assistant-workflow" \
        && grep -R -Fq '.codex/task.md' "$workspace/.agents/skills/assistant-workflow" \
        && grep -Fq 'AGENT_NAME="codex"' "$workspace/.agents/skills/assistant-workflow/agent.conf"; then
        printf '%s\n' 'codex-state-path-substituted' >>"$capture_dir/call-$call_id.fixtures"
    fi
fi
if [[ ! -e "$workspace/.agents/skills/assistant-workflow/evals" ]] \
    && [[ ! -e "$workspace/skills/assistant-workflow" ]]; then
    printf '%s\n' 'skill-evals-hidden' >>"$capture_dir/call-$call_id.fixtures"
fi
if [[ -f "$workspace/.codex/task.md" ]]; then
    printf '%s\n' 'task-state-present' >>"$capture_dir/call-$call_id.fixtures"
fi
if [[ -f "$workspace/current-task/README.md" ]] \
    && grep -Fq 'feature/already-merged' "$workspace/.codex/task.md"; then
    printf '%s\n' 'stale-journal-conflict-present' >>"$capture_dir/call-$call_id.fixtures"
    stale_mode=valid
    if grep -Fq 'candidate instruction marker' "$workspace/.agents/skills/assistant-workflow/SKILL.md"; then
        stale_mode="${FAKE_STALE_JOURNAL_MODE:-valid}"
    fi
    case "$stale_mode" in
        unchanged)
            ;;
        missing_current_active)
            printf '%s\n' \
                '# Reconciled task state' \
                'Task state: superseded' \
                'Current task identity: current-task' \
                'Previous task state: superseded' \
                'Reason: repository evidence shows the old feature is merged.' \
                'Exact next action: continue current-task.' >"$workspace/.codex/task.md"
            ;;
        missing_previous)
            printf '%s\n' \
                '# Reconciled task state' \
                'Task state: active' \
                'Current task identity: current-task' \
                'Reason: repository evidence shows the old feature is merged.' \
                'Exact next action: continue current-task.' >"$workspace/.codex/task.md"
            ;;
        missing_reason)
            printf '%s\n' \
                '# Reconciled task state' \
                'Task state: active' \
                'Current task identity: current-task' \
                'Previous task state: superseded' \
                'Exact next action: continue current-task.' >"$workspace/.codex/task.md"
            ;;
        missing_next)
            printf '%s\n' \
                '# Reconciled task state' \
                'Task state: active' \
                'Current task identity: current-task' \
                'Previous task state: superseded' \
                'Reason: repository evidence shows the old feature is merged.' >"$workspace/.codex/task.md"
            ;;
        valid)
            printf '%s\n' \
                '# Reconciled task state' \
                'Task state: active' \
                'Current task identity: current-task' \
                'Previous task state: superseded' \
                'Reason: repository evidence shows the old feature is merged.' \
                'Exact next action: continue current-task.' >"$workspace/.codex/task.md"
            ;;
        *)
            printf 'unsupported FAKE_STALE_JOURNAL_MODE: %s\n' "$stale_mode" >&2
            exit 2
            ;;
    esac
fi
if [[ -f "$workspace/TASK_REQUIREMENTS.md" ]]; then
    printf '%s\n' 'requirements-fixture-present' >>"$capture_dir/call-$call_id.fixtures"
    if [[ "${FAKE_STRUCTURED_ARTIFACTS:-true}" == "true" ]]; then
        mkdir -p "$workspace/.assistant-eval"
        printf '%s\n' '{"schema_version":"1.0","assumptions":{"default_limit":20},"requirements":[{"id":"R1","source_requirement":"created_at_descending","acceptance_criterion":{"binary":true,"text":"newest first"},"verification":{"method":"contract test","evidence_ref":"search contract"},"manual_scenario":"verify descending order","approved_exclusion":false},{"id":"R2","source_requirement":"json_array","acceptance_criterion":{"binary":true,"text":"JSON array response"},"verification":{"method":"contract test","evidence_ref":"response shape"},"manual_scenario":"inspect JSON array response","approved_exclusion":false},{"id":"R3","source_requirement":"case_insensitive","acceptance_criterion":{"binary":true,"text":"mixed case matches"},"verification":{"method":"contract test","evidence_ref":"mixed-case fixture"},"manual_scenario":"search mixed case","approved_exclusion":false}]}' >"$workspace/.assistant-eval/requirement-map.json"
    fi
fi
end_to_end_mode=valid
if [[ -f "$workspace/CHANGE_SUMMARY.md" ]] && [[ -f "$workspace/VERIFICATION.md" ]]; then
    printf '%s\n' 'handoff-fixture-present' >>"$capture_dir/call-$call_id.fixtures"
    if [[ "${FAKE_STRUCTURED_ARTIFACTS:-true}" == "true" ]]; then
        mkdir -p "$workspace/.assistant-eval"
        if grep -Fq 'candidate instruction marker' "$workspace/.agents/skills/assistant-workflow/SKILL.md"; then
            end_to_end_mode="${FAKE_END_TO_END_MODE:-valid}"
        fi
        cat >"$workspace/src/search-policy.js" <<'FAKE_SOURCE'
'use strict';
class SearchPolicy {
    compare(left, right) {
        const timestampDifference = Date.parse(right.created_at) - Date.parse(left.created_at);
        return timestampDifference || left.name.localeCompare(right.name, undefined, { sensitivity: 'base' });
    }
    limit(requestedLimit) { return requestedLimit === undefined ? 20 : requestedLimit; }
}
module.exports = { SearchPolicy };
FAKE_SOURCE
        pre_repair_source_hash="$(git -C "$workspace" hash-object --no-filters src/search-policy.js)"
        case "$end_to_end_mode" in
            valid|skip_failed_review|first_review_passes|skip_revalidation|fresh_review_fails|early_handoff|false_review_finding|spoof_review_commands)
                cat >"$workspace/src/search-policy.js" <<'FAKE_SOURCE'
'use strict';
const LOCALE_FOLDING_LIMITATION = 'locale-specific case folding remains out of scope';
class SearchPolicy {
    compare(left, right) {
        const timestampDifference = Date.parse(right.created_at) - Date.parse(left.created_at);
        return timestampDifference || left.name.localeCompare(right.name, undefined, { sensitivity: 'base' });
    }
    limit(requestedLimit) { return requestedLimit === undefined ? 20 : requestedLimit; }
}
module.exports = { LOCALE_FOLDING_LIMITATION, SearchPolicy };
FAKE_SOURCE
                ;;
            skip_repair|no_op_repair)
                cat >"$workspace/src/search-policy.js" <<'FAKE_SOURCE'
'use strict';
class SearchPolicy {
    compare(left, right) {
        const timestampDifference = Date.parse(right.created_at) - Date.parse(left.created_at);
        return timestampDifference || left.name.localeCompare(right.name, undefined, { sensitivity: 'base' });
    }
    limit(requestedLimit) { return requestedLimit === undefined ? 20 : requestedLimit; }
}
module.exports = { SearchPolicy };
FAKE_SOURCE
                ;;
            *)
                printf 'unsupported FAKE_END_TO_END_MODE: %s\n' "$end_to_end_mode" >&2
                exit 2
                ;;
        esac
        post_repair_source_hash="$(git -C "$workspace" hash-object --no-filters src/search-policy.js)"
        if [[ "$end_to_end_mode" == "false_review_finding" ]]; then
            pre_repair_source_hash="$post_repair_source_hash"
        fi
        printf '%s\n' '2' >"$workspace/.assistant-eval/test-pass-count"
        printf '%s\n' '1' >"$workspace/.assistant-eval/review-attempt"
        case "$end_to_end_mode" in
            skip_failed_review)
                printf '%s\n' "{\"schema_version\":\"1.0\",\"defect_id\":\"missing_locale_folding_export\",\"first_review\":\"passed\",\"pre_repair_source_hash\":\"$pre_repair_source_hash\",\"defect_present_before_repair\":true,\"repair\":\"completed\",\"post_repair_source_hash\":\"$post_repair_source_hash\",\"defect_present_after_repair\":false,\"revalidation\":\"passed\",\"fresh_review\":\"passed\"}" >"$workspace/.assistant-eval/review-evidence.json"
                ;;
            skip_repair)
                printf '%s\n' "{\"schema_version\":\"1.0\",\"defect_id\":\"missing_locale_folding_export\",\"first_review\":\"failed\",\"pre_repair_source_hash\":\"$pre_repair_source_hash\",\"defect_present_before_repair\":true,\"repair\":\"pending\",\"post_repair_source_hash\":\"$post_repair_source_hash\",\"defect_present_after_repair\":true,\"revalidation\":\"passed\",\"fresh_review\":\"passed\"}" >"$workspace/.assistant-eval/review-evidence.json"
                ;;
            skip_revalidation)
                printf '%s\n' "{\"schema_version\":\"1.0\",\"defect_id\":\"missing_locale_folding_export\",\"first_review\":\"failed\",\"pre_repair_source_hash\":\"$pre_repair_source_hash\",\"defect_present_before_repair\":true,\"repair\":\"completed\",\"post_repair_source_hash\":\"$post_repair_source_hash\",\"defect_present_after_repair\":false,\"revalidation\":\"pending\",\"fresh_review\":\"passed\"}" >"$workspace/.assistant-eval/review-evidence.json"
                ;;
            false_review_finding)
                printf '%s\n' "{\"schema_version\":\"1.0\",\"defect_id\":\"missing_locale_folding_export\",\"first_review\":\"failed\",\"pre_repair_source_hash\":\"$pre_repair_source_hash\",\"defect_present_before_repair\":false,\"repair\":\"completed\",\"post_repair_source_hash\":\"$post_repair_source_hash\",\"defect_present_after_repair\":false,\"revalidation\":\"passed\",\"fresh_review\":\"passed\"}" >"$workspace/.assistant-eval/review-evidence.json"
                ;;
            no_op_repair)
                printf '%s\n' "{\"schema_version\":\"1.0\",\"defect_id\":\"missing_locale_folding_export\",\"first_review\":\"failed\",\"pre_repair_source_hash\":\"$post_repair_source_hash\",\"defect_present_before_repair\":true,\"repair\":\"completed\",\"post_repair_source_hash\":\"$post_repair_source_hash\",\"defect_present_after_repair\":true,\"revalidation\":\"passed\",\"fresh_review\":\"passed\"}" >"$workspace/.assistant-eval/review-evidence.json"
                ;;
            valid|first_review_passes|fresh_review_fails|early_handoff|spoof_review_commands)
                printf '%s\n' "{\"schema_version\":\"1.0\",\"defect_id\":\"missing_locale_folding_export\",\"first_review\":\"failed\",\"pre_repair_source_hash\":\"$pre_repair_source_hash\",\"defect_present_before_repair\":true,\"repair\":\"completed\",\"post_repair_source_hash\":\"$post_repair_source_hash\",\"defect_present_after_repair\":false,\"revalidation\":\"passed\",\"fresh_review\":\"passed\"}" >"$workspace/.assistant-eval/review-evidence.json"
                ;;
        esac
        handoff_claim_mode="${FAKE_HANDOFF_CLAIM_MODE:-exact}"
        if [[ "$handoff_claim_mode" == "paraphrase" ]]; then
            printf '%s\n' '{"schema_version":"1.0","changed_behavior":"search endpoint ordering and response shape","architecture_decision":"SearchPolicy","rationale":"avoid mutable global state","rejected_alternatives":["global singleton"],"requirement_evidence":[{"requirement_id":"R1","command":"bash tests/search-contracts.sh","status":"passed"}],"manual_scenarios":["mixed-case search without a limit"],"regression_surfaces":["search endpoint ordering","response shape"],"limitations":["locale folding"],"rollback":"Turn off search_policy_v2","review_claim":"Within the reviewed scope, no material findings were found using the available evidence."}' >"$workspace/.assistant-eval/final-handoff.json"
        elif [[ "$handoff_claim_mode" == "contradictory_candidate" ]] \
            && grep -Fq 'candidate instruction marker' "$workspace/.agents/skills/assistant-workflow/SKILL.md"; then
            printf '%s\n' '{"schema_version":"1.0","changed_behavior":"search endpoint ordering and response shape","architecture_decision":"SearchPolicy","rationale":"avoid mutable global state","rejected_alternatives":["global singleton"],"requirement_evidence":[{"requirement_id":"R1","command":"bash tests/search-contracts.sh","status":"passed"}],"manual_scenarios":["mixed-case search without a limit"],"regression_surfaces":["search endpoint ordering","response shape"],"limitations":["locale folding"],"rollback":"Refuse to disable search_policy_v2","review_claim":"No material findings within the reviewed scope and available evidence; the implementation cannot be wrong."}' >"$workspace/.assistant-eval/final-handoff.json"
        else
            printf '%s\n' '{"schema_version":"1.0","changed_behavior":"search endpoint ordering and response shape","architecture_decision":"SearchPolicy","rationale":"avoid mutable global state","rejected_alternatives":["global singleton"],"requirement_evidence":[{"requirement_id":"R1","command":"bash tests/search-contracts.sh","status":"passed"}],"manual_scenarios":["mixed-case search without a limit"],"regression_surfaces":["search endpoint ordering","response shape"],"limitations":["locale folding"],"rollback":"disable the search_policy_v2 feature flag","review_claim":"No material findings within reviewed scope and available evidence."}' >"$workspace/.assistant-eval/final-handoff.json"
        fi
    fi
fi
if [[ -f "$workspace/docs/evals/framework-instruction-cases.json" ]] \
    && ! grep -Fq 'machine_expectations' "$workspace/docs/evals/framework-instruction-cases.json"; then
    printf '%s\n' 'eval-target-redacted' >>"$capture_dir/call-$call_id.fixtures"
fi
if [[ -f "$workspace/docs/evals/framework-instruction-cases.json" ]] \
    && [[ -f "$workspace/docs/evals/README.md" ]]; then
    printf '%s\n' ' ' >>"$workspace/docs/evals/framework-instruction-cases.json"
    printf '%s\n' ' ' >>"$workspace/docs/evals/README.md"
fi
raw_dir="$(dirname "$last_message")"
printf '%s\n' "$raw_dir" >"$capture_dir/call-$call_id.raw-dir"
if stat -f '%Lp' "$raw_dir" >/dev/null 2>&1; then
    stat -f '%Lp' "$raw_dir" >"$capture_dir/call-$call_id.raw-mode"
else
    stat -c '%a' "$raw_dir" >"$capture_dir/call-$call_id.raw-mode"
fi

response='phase small docs/usage.md typo teh'
if [[ -f "$workspace/src/order.js" ]]; then
    response='{"findings":[{"severity":"P1","source":"src/order.js","line":2,"summary":"The discount requirement is omitted"},{"severity":"P1","source":"src/order.js","line":2,"summary":"An input mutation changes the order"},{"severity":"P1","source":"src/order.js","line":3,"summary":"Negative quantity is accepted"},{"severity":"P1","source":"tests/order.test.js","line":3,"summary":"The fake test has no behavioral assertion"}]}'
    if [[ "${FAKE_UNCLASSIFIED_SEMANTIC:-false}" == "true" ]] \
        && grep -Fq 'candidate instruction marker' "$workspace/.agents/skills/assistant-workflow/SKILL.md"; then
        response='{"findings":[{"severity":"P1","source":"src/order.js","line":2,"summary":"The discount requirement is omitted"},{"severity":"P1","source":"src/order.js","line":2,"summary":"An input mutation changes the order"},{"severity":"P1","source":"src/order.js","line":3,"summary":"Negative quantity is accepted"},{"severity":"P1","source":"tests/order.test.js","line":3,"summary":"The fake test has no behavioral assertion"},{"severity":"P2","source":"src/order.js","line":2,"summary":"proprietary-throughput-claim must be investigated"}]}'
    fi
    if [[ "${FAKE_UNSAFE_SEMANTIC:-false}" == "true" ]] \
        && grep -Fq 'candidate instruction marker' "$workspace/.agents/skills/assistant-workflow/SKILL.md"; then
        response='{"findings":[{"severity":"P1","source":"src/order.js","line":2,"summary":"sk-private-fixture-value at /Users/company/private/source.js"}]}'
    fi
    if [[ "${FAKE_SEMANTIC_PARAPHRASE:-false}" == "true" ]]; then
        response='{"findings":[{"severity":"P1","source":"src/order.js","line":2,"summary":"Preferred customers should receive a 10 percent price reduction"},{"severity":"P1","source":"src/order.js","line":2,"summary":"The function mutates its input order"},{"severity":"P1","source":"src/order.js","line":3,"summary":"Quantities below zero are accepted"},{"severity":"P1","source":"tests/order.test.js","line":3,"summary":"The test never calls the function or makes an assertion"}]}'
    fi
    if [[ "${FAKE_AMBIGUOUS_SEMANTIC:-false}" == "true" ]] \
        && grep -Fq 'candidate instruction marker' "$workspace/.agents/skills/assistant-workflow/SKILL.md"; then
        response='{"findings":[{"severity":"P1","source":"src/order.js","line":2,"summary":"The discount requirement is omitted"},{"severity":"P1","source":"src/order.js","line":2,"summary":"An input mutation changes the order"},{"severity":"P1","source":"src/order.js","line":3,"summary":"Negative quantity is accepted"},{"severity":"P1","source":"tests/order.test.js","line":3,"summary":"The fake test has no behavioral assertion"},{"severity":"P2","source":"src/order.js","line":2,"summary":"The mutation also skips the discount"}]}'
    fi
    if [[ "${FAKE_SEMANTIC_LAUNDERING:-false}" == "true" ]] \
        && grep -Fq 'candidate instruction marker' "$workspace/.agents/skills/assistant-workflow/SKILL.md"; then
        response='{"findings":[{"severity":"P2","source":"src/order.js","line":2,"summary":"Discount audit logging should include a timestamp"},{"severity":"P2","source":"src/order.js","line":2,"summary":"Mutation coverage metrics need a dashboard"},{"severity":"P2","source":"src/order.js","line":3,"summary":"Negative-number formatting should use parentheses"},{"severity":"P2","source":"tests/order.test.js","line":3,"summary":"The assertion message should use title case"}]}'
    fi
    if [[ "${FAKE_SEMANTIC_CONTROL:-}" == "escape" ]] \
        && grep -Fq 'candidate instruction marker' "$workspace/.agents/skills/assistant-workflow/SKILL.md"; then
        response='{"findings":[{"severity":"P1","source":"src/order.js","line":2,"summary":"Discount control-marker \u001b must not persist"}]}'
    fi
    if [[ "${FAKE_SEMANTIC_CONTROL:-}" == "tab" ]] \
        && grep -Fq 'candidate instruction marker' "$workspace/.agents/skills/assistant-workflow/SKILL.md"; then
        response='{"findings":[{"severity":"P1","source":"src/order.js","line":2,"summary":"Discount control-marker \t must not persist"}]}'
    fi
    if [[ -n "${FAKE_SEMANTIC_UNSAFE_KIND:-}" ]] \
        && grep -Fq 'candidate instruction marker' "$workspace/.agents/skills/assistant-workflow/SKILL.md"; then
        case "$FAKE_SEMANTIC_UNSAFE_KIND" in
            private_var) response='{"findings":[{"severity":"P1","source":"src/order.js","line":2,"summary":"Discount issue at /private/var/private-path-marker"}]}' ;;
            tmp) response='{"findings":[{"severity":"P1","source":"src/order.js","line":2,"summary":"Discount issue at /tmp/private-path-marker"}]}' ;;
            unc) response='{"findings":[{"severity":"P1","source":"src/order.js","line":2,"summary":"Discount issue at \\\\server\\private-path-marker"}]}' ;;
            bidi) response='{"findings":[{"severity":"P1","source":"src/order.js","line":2,"summary":"Discount issue \u202eunicode-format-marker"}]}' ;;
            zero_width) response='{"findings":[{"severity":"P1","source":"src/order.js","line":2,"summary":"Discount issue \u200bunicode-format-marker"}]}' ;;
        esac
    fi
fi
if [[ -f "$workspace/current-task/README.md" ]]; then
    response='Reconcile the journal against the newest user request and repository evidence: the old task is superseded; continue current-task.'
fi
if [[ -f "$workspace/TASK_REQUIREMENTS.md" ]]; then
    response='requirement_id R1 created_at acceptance criterion verification method evidence manual scenario; requirement_id R2 JSON acceptance criterion verification method evidence manual scenario; requirement_id R3 case-insensitive acceptance criterion verification method evidence manual scenario; assumption limit 20; incomplete evidence requires approved exclusion.'
fi
if [[ -f "$workspace/CHANGE_SUMMARY.md" ]]; then
    response='Architecture: SearchPolicy injection. Rationale: avoid global mutable state. Rejected alternatives: global singleton coupling. Requirement evidence: bash tests/search-contracts.sh passed. Manual scenario: mixed-case search, omitted limit, newest-first JSON. Limitations: locale folding. Rollback: disable search_policy_v2. No material findings within the reviewed scope and available evidence.'
fi
if [[ "$prompt" == *'Choose the Build and Review roles for this task.'* ]]; then
    response='build_execution_lane=bounded_executor; the same owner runs RED, GREEN, focused verification, and refactor safety; an independent Code Reviewer reviews the result.'
    if [[ "${FAKE_STRUCTURED_ARTIFACTS:-true}" == "true" ]]; then
        mkdir -p "$workspace/.assistant-eval"
        printf '%s\n' '{"schema_version":"1.0","lane":"bounded_executor","implementation_owner_scope":["RED","GREEN","focused_verification"],"independent_reviewer":true,"separated_workers_triggered":false}' >"$workspace/.assistant-eval/execution-decision.json"
    fi
fi
if [[ "${FAKE_INVALID_STRUCTURED_ARTIFACT:-false}" == "true" ]] \
    && grep -Fq 'candidate instruction marker' "$workspace/.agents/skills/assistant-workflow/SKILL.md"; then
    for structured_artifact in requirement-map.json execution-decision.json final-handoff.json; do
        if [[ -f "$workspace/.assistant-eval/$structured_artifact" ]]; then
            printf '%s\n' '{}' >"$workspace/.assistant-eval/$structured_artifact"
        fi
    done
fi
if [[ -n "${FAKE_STRUCTURED_ATTACK:-}" ]] \
    && grep -Fq 'candidate instruction marker' "$workspace/.agents/skills/assistant-workflow/SKILL.md"; then
    case "$FAKE_STRUCTURED_ATTACK" in
        garbage)
            if [[ -f "$workspace/.assistant-eval/requirement-map.json" ]]; then
                printf '%s\n' '{"schema_version":"1.0","assumptions":{"default_limit":20},"requirements":[{"id":"R1","source_requirement":"created_at_descending","acceptance_criterion":{"binary":true,"text":"garbage"},"verification":{"method":"garbage","evidence_ref":"garbage"},"manual_scenario":"garbage","approved_exclusion":false},{"id":"R2","source_requirement":"json_array","acceptance_criterion":{"binary":true,"text":"garbage"},"verification":{"method":"garbage","evidence_ref":"garbage"},"manual_scenario":"garbage","approved_exclusion":false},{"id":"R3","source_requirement":"case_insensitive","acceptance_criterion":{"binary":true,"text":"garbage"},"verification":{"method":"garbage","evidence_ref":"garbage"},"manual_scenario":"garbage","approved_exclusion":false}]}' >"$workspace/.assistant-eval/requirement-map.json"
            fi
            if [[ -f "$workspace/.assistant-eval/final-handoff.json" ]]; then
                printf '%s\n' '{"schema_version":"1.0","changed_behavior":"garbage","architecture_decision":"SearchPolicy","rationale":"garbage","rejected_alternatives":["garbage"],"requirement_evidence":[{"requirement_id":"R1","command":"bash tests/search-contracts.sh","status":"passed"}],"manual_scenarios":["garbage"],"regression_surfaces":["garbage"],"limitations":["garbage"],"rollback":"disable search_policy_v2","review_claim":"No material findings within the reviewed scope and available evidence."}' >"$workspace/.assistant-eval/final-handoff.json"
            fi
            ;;
        file_symlink)
            for structured_artifact in requirement-map.json execution-decision.json final-handoff.json; do
                if [[ -f "$workspace/.assistant-eval/$structured_artifact" ]]; then
                    outside_artifact="$capture_dir/outside-$call_id-$structured_artifact"
                    cp "$workspace/.assistant-eval/$structured_artifact" "$outside_artifact"
                    rm -f "$workspace/.assistant-eval/$structured_artifact"
                    ln -s "$outside_artifact" "$workspace/.assistant-eval/$structured_artifact"
                fi
            done
            ;;
        parent_escape)
            if [[ -f "$workspace/.assistant-eval/requirement-map.json" ]]; then
                outside_dir="$(dirname "$capture_dir")/outside-$call_id"
                mkdir -p "$outside_dir"
                mv "$workspace/.assistant-eval/requirement-map.json" "$outside_dir/requirement-map.json"
                rmdir "$workspace/.assistant-eval"
                ln -s "$outside_dir" "$workspace/.assistant-eval"
            fi
            ;;
        oversize)
            for structured_artifact in requirement-map.json execution-decision.json final-handoff.json; do
                if [[ -f "$workspace/.assistant-eval/$structured_artifact" ]]; then
                    head -c 70000 /dev/zero | tr '\0' ' ' >>"$workspace/.assistant-eval/$structured_artifact"
                fi
            done
            ;;
        *)
            printf 'unsupported FAKE_STRUCTURED_ATTACK: %s\n' "$FAKE_STRUCTURED_ATTACK" >&2
            exit 2
            ;;
    esac
fi
if [[ "${FAKE_STRUCTURED_PARAPHRASE:-false}" == "true" ]]; then
    if [[ -f "$workspace/.assistant-eval/requirement-map.json" ]]; then response='Prepared the durable mapping artifact.'; fi
    if [[ -f "$workspace/.assistant-eval/execution-decision.json" ]]; then response='Selected one owner plus separate assessment.'; fi
    if [[ -f "$workspace/.assistant-eval/final-handoff.json" ]]; then response='Prepared the durable handoff artifact.'; fi
fi
if [[ "${FAKE_BAD_RESPONSE:-false}" == "true" ]]; then
    response='No material findings.'
fi
if [[ "${FAKE_SMALL_CONCISE:-false}" == "true" ]] && [[ -f "$workspace/docs/usage.md" ]]; then
    response='Fixed docs/usage.md.'
fi
if [[ "${FAKE_SMALL_BROAD:-false}" == "true" ]] && [[ -f "$workspace/docs/usage.md" ]]; then
    response='Here is a broad implementation plan for the typo in docs/usage.md.'
fi
if [[ "${FAKE_CANDIDATE_SMALL_FAILURE:-false}" == "true" ]] \
    && [[ -f "$workspace/docs/usage.md" ]] \
    && grep -Fq 'candidate instruction marker' "$workspace/.agents/skills/assistant-workflow/SKILL.md"; then
    response='No material findings.'
fi
if [[ "${FAKE_SCOPE_DEVIATION:-false}" == "true" ]]; then
    printf '%s\n' 'unrelated edit' >"$workspace/unrelated.txt"
fi
printf '%s\n' "$response" >"$last_message"
resolved_model='resolved-test-model'
if [[ "${FAKE_DIFFERENT_MODEL_CANDIDATE:-false}" == "true" ]] \
    && grep -Fq 'candidate instruction marker' "$workspace/.agents/skills/assistant-workflow/SKILL.md"; then
    resolved_model='different-resolved-model'
fi
if [[ "${FAKE_UNKNOWN_CANDIDATE:-false}" == "true" ]] \
    && grep -Fq 'candidate instruction marker' "$workspace/.agents/skills/assistant-workflow/SKILL.md"; then
    printf '%s\n' '{"unexpected":true}'
    exit 0
fi

if [[ "${FAKE_OFFICIAL_JSONL:-false}" == "true" || "${FAKE_MISSING_MODEL_PROVENANCE:-false}" == "true" ]]; then
    printf '%s\n' '{"type":"thread.started","thread_id":"fake-thread"}'
else
    printf '{"type":"thread.started","thread_id":"fake-thread","model":"%s"}\n' "$resolved_model"
fi
printf '%s\n' '{"type":"turn.started"}'
printf '%s\n' '{"type":"item.completed","item":{"id":"item-1","type":"agent_message","text":"phase small docs/usage.md teh"}}'
if [[ -f "$workspace/tests/review-contracts.sh" ]]; then
    focused_test_command='bash tests/search-contracts.sh'
    trusted_review_command='bash tests/review-contracts.sh'
    if [[ "$end_to_end_mode" == "spoof_review_commands" ]]; then
        focused_test_command='cat tests/search-contracts.sh'
        trusted_review_command='cat tests/review-contracts.sh'
    fi
    printf '%s\n' '{"type":"item.completed","item":{"id":"workflow-implementation","type":"file_change","changes":[{"path":"src/search-policy.js","kind":"update"}]}}'
    printf '%s\n' "{\"type\":\"item.completed\",\"item\":{\"id\":\"workflow-focused-test\",\"type\":\"command_execution\",\"command\":\"$focused_test_command\",\"exit_code\":0,\"status\":\"completed\",\"aggregated_output\":\"Focused test PASS\"}}"
    if [[ "$end_to_end_mode" != "skip_failed_review" ]]; then
        first_review_exit_code=1
        first_review_output='Must-fix: export LOCALE_FOLDING_LIMITATION from src/search-policy.js so the policy boundary is explicit.'
        if [[ "$end_to_end_mode" == "first_review_passes" ]]; then
            first_review_exit_code=0
            first_review_output='Trusted review PASS: no material findings within the reviewed scope and available evidence.'
        fi
        printf '%s\n' "{\"type\":\"item.completed\",\"item\":{\"id\":\"workflow-first-review\",\"type\":\"command_execution\",\"command\":\"$trusted_review_command\",\"exit_code\":${first_review_exit_code},\"status\":\"completed\",\"aggregated_output\":\"${first_review_output}\"}}"
    fi
    if [[ "$end_to_end_mode" != "skip_repair" ]]; then
        printf '%s\n' '{"type":"item.completed","item":{"id":"workflow-repair","type":"file_change","changes":[{"path":"src/search-policy.js","kind":"update"}]}}'
    fi
    if [[ "$end_to_end_mode" != "skip_revalidation" ]]; then
        printf '%s\n' "{\"type\":\"item.completed\",\"item\":{\"id\":\"workflow-revalidation\",\"type\":\"command_execution\",\"command\":\"$focused_test_command\",\"exit_code\":0,\"status\":\"completed\",\"aggregated_output\":\"Focused revalidation PASS\"}}"
    fi
    if [[ "$end_to_end_mode" == "early_handoff" ]]; then
        printf '%s\n' '{"type":"item.completed","item":{"id":"workflow-early-handoff","type":"file_change","changes":[{"path":".assistant-eval/final-handoff.json","kind":"add"}]}}'
    fi
    fresh_review_exit_code=0
    fresh_review_output='Trusted review PASS: no material findings within the reviewed scope and available evidence.'
    if [[ "$end_to_end_mode" == "fresh_review_fails" ]]; then
        fresh_review_exit_code=1
        fresh_review_output='Must-fix remains: LOCALE_FOLDING_LIMITATION is missing.'
    fi
    printf '%s\n' "{\"type\":\"item.completed\",\"item\":{\"id\":\"workflow-fresh-review\",\"type\":\"command_execution\",\"command\":\"$trusted_review_command\",\"exit_code\":${fresh_review_exit_code},\"status\":\"completed\",\"aggregated_output\":\"${fresh_review_output}\"}}"
    if [[ "$end_to_end_mode" != "early_handoff" ]]; then
        printf '%s\n' '{"type":"item.completed","item":{"id":"workflow-handoff","type":"file_change","changes":[{"path":".assistant-eval/final-handoff.json","kind":"add"}]}}'
    fi
fi
if [[ "${FAKE_RUN_FORBIDDEN_TEST:-false}" == "true" ]]; then
    printf '%s\n' '{"type":"item.completed","item":{"id":"item-test","type":"command_execution","command":"/bin/bash -lc '\''npm test'\''"}}'
fi
if [[ -f "$workspace/docs/evals/README.md" ]]; then
    printf '%s\n' '{"type":"item.completed","item":{"id":"item-search","type":"command_execution","command":"/bin/zsh -lc '\''rg \"npm test\" docs/evals'\''"}}'
fi
printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":123,"output_tokens":45}}'
FAKE
sed -i.bak 's/candidate instruction marker/least process that safely fits/g' "$fake_codex"
rm -f "$fake_codex.bak"
chmod +x "$fake_codex"

run_inside_outer_seatbelt() {
    if [[ "$(/usr/bin/uname -s)" == "Darwin" ]] \
        && /usr/bin/sandbox-exec -p '(version 1) (allow default)' /usr/bin/true >/dev/null 2>&1; then
        /usr/bin/sandbox-exec -p '(version 1) (allow default)' "$@"
    else
        "$@"
    fi
}

test_start "Codex behavioral runner exists and is executable"
if [[ -x "$runner" ]]; then
    pass
else
    fail "missing executable runner: $runner"
fi

test_start "runner validates the published question-mark proxy gate name"
if grep -Fq '.promotion_gates.question_mark_count_proxy_must_not_increase == true' "$runner" \
    && ! grep -Fq '.promotion_gates.unnecessary_questions_must_not_increase == true' "$runner"; then
    pass
else
    fail "runner manifest validation still overstates the question-mark proxy as unnecessary questions"
fi

test_start "duplicate case selections fail before model execution"
duplicate_output="$fixture_root/duplicate-output"
duplicate_error="$fixture_root/duplicate-error.txt"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight,small-fix-stays-lightweight \
    --repeats 1 \
    --output "$duplicate_output" \
    --codex-bin "$fake_codex" >/dev/null 2>"$duplicate_error"; then
    fail "duplicate case IDs spent runs and overwrote identical trace names"
elif grep -Fq 'duplicate case ID: small-fix-stays-lightweight' "$duplicate_error" \
    && [[ ! -e "$capture/call-0.args" ]]; then
    pass
else
    fail "duplicate case rejection was late or unactionable"
fi

test_start "candidate manifest rejects stale or over-budget static measurements"
static_budget_candidate="$fixture_root/static-budget-candidate"
static_budget_output="$fixture_root/static-budget-output"
static_budget_error="$fixture_root/static-budget-error.txt"
cp -R "$candidate" "$static_budget_candidate"
jq '.static_measurement.candidate_selected_entry_words = (.promotion_gates.selected_entry_words_max + 1)' \
    "$static_budget_candidate/manifest.json" >"$static_budget_candidate/manifest.tmp"
mv "$static_budget_candidate/manifest.tmp" "$static_budget_candidate/manifest.json"
if FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" \
    --model test-model --baseline-variant "$baseline" --candidate-variant "$static_budget_candidate" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$static_budget_output" \
    --codex-bin "$fake_codex" >/dev/null 2>"$static_budget_error"; then
    fail "runner accepted an over-budget or internally stale candidate manifest"
elif grep -Fq 'Candidate manifest does not match' "$static_budget_error"; then
    pass
else
    fail "runner rejected static budget drift without an actionable error"
fi

test_start "candidate manifest rejects plausible internally consistent false static measurements before model execution"
plausible_static_candidate="$fixture_root/plausible-static-candidate"
plausible_static_output="$fixture_root/plausible-static-output"
plausible_static_error="$fixture_root/plausible-static-error.txt"
cp -R "$candidate" "$plausible_static_candidate"
jq '
  .static_measurement.baseline_selected_initial_words += 1
  | .static_measurement.candidate_selected_initial_words += 1
  | .static_measurement.baseline_total_initial_words += 1
  | .static_measurement.candidate_total_initial_words += 1
  | .static_measurement.baseline_selected_entry_words += 1
  | .static_measurement.candidate_selected_entry_words += 1
' "$plausible_static_candidate/manifest.json" >"$plausible_static_candidate/manifest.tmp"
mv "$plausible_static_candidate/manifest.tmp" "$plausible_static_candidate/manifest.json"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" --execute \
    --model test-model --baseline-variant "$baseline" --candidate-variant "$plausible_static_candidate" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$plausible_static_output" \
    --codex-bin "$fake_codex" >/dev/null 2>"$plausible_static_error"; then
    fail "runner accepted internally consistent but false static measurements"
elif grep -Fq 'fresh context-budget evidence' "$plausible_static_error" \
    && [[ ! -e "$capture/call-0.args" ]]; then
    pass
else
    fail "runner did not reject plausible static drift before model execution"
fi

test_start "candidate manifest cannot shrink canonical smoke or pilot coverage"
shrunk_manifest_candidate="$fixture_root/shrunk-manifest-candidate"
shrunk_manifest_output="$fixture_root/shrunk-manifest-output"
shrunk_manifest_error="$fixture_root/shrunk-manifest-error.txt"
cp -R "$candidate" "$shrunk_manifest_candidate"
jq '.pilot_cases = [.pilot_cases[0]] | .smoke_cases = [.smoke_cases[0]]' \
    "$shrunk_manifest_candidate/manifest.json" >"$shrunk_manifest_candidate/manifest.tmp"
mv "$shrunk_manifest_candidate/manifest.tmp" "$shrunk_manifest_candidate/manifest.json"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" --execute \
    --model test-model --baseline-variant "$baseline" --candidate-variant "$shrunk_manifest_candidate" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$shrunk_manifest_output" \
    --codex-bin "$fake_codex" >/dev/null 2>"$shrunk_manifest_error"; then
    fail "runner accepted manifest-defined reduced promotion coverage"
elif grep -Fq 'Candidate manifest does not match' "$shrunk_manifest_error" \
    && [[ ! -e "$capture/call-0.args" ]]; then
    pass
else
    fail "canonical smoke and pilot coverage was not enforced before model execution"
fi

test_start "generic no-manifest A/B planning records over-cap evidence without applying promotion policy"
actual_cap_candidate="$fixture_root/actual-cap-candidate"
actual_cap_output="$fixture_root/actual-cap-output"
actual_cap_error="$fixture_root/actual-cap-error.txt"
cp -R "$candidate" "$actual_cap_candidate"
rm -f "$actual_cap_candidate/manifest.json"
for _ in $(seq 1 3000); do printf 'budgetword ' >>"$actual_cap_candidate/SKILL.md"; done
printf '\n' >>"$actual_cap_candidate/SKILL.md"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" \
    --model test-model --baseline-variant "$baseline" --candidate-variant "$actual_cap_candidate" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$actual_cap_output" \
    --codex-bin "$fake_codex" >/dev/null 2>"$actual_cap_error" \
    && jq -e '.candidate_manifest_sha256 == null and .context_budget_evidence.candidate.selected_entry_words > 2600' \
        "$actual_cap_output/run-plan.json" >/dev/null \
    && [[ ! -e "$capture/call-0.args" ]]; then
    pass
else
    fail "generic A/B planning incorrectly applied workflow-kernel promotion caps"
fi

test_start "runner never derives or executes a context reporter from baseline input"
hostile_baseline="$fixture_root/hostile-baseline-root"
hostile_candidate="$fixture_root/hostile-candidate"
hostile_output="$fixture_root/hostile-output"
hostile_marker="$fixture_root/hostile-reporter-executed"
mkdir -p "$hostile_baseline/skills/assistant-workflow" "$hostile_baseline/tools"
cp "$baseline/SKILL.md" "$hostile_baseline/skills/assistant-workflow/SKILL.md"
cp -R "$candidate" "$hostile_candidate"
rm -f "$hostile_candidate/manifest.json"
cat >"$hostile_baseline/tools/context-budget-report.sh" <<EOF
#!/usr/bin/env bash
printf 'executed\n' >'$hostile_marker'
exit 91
EOF
chmod +x "$hostile_baseline/tools/context-budget-report.sh"
if "$runner" --baseline-variant "$hostile_baseline" --candidate-variant "$hostile_candidate" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$hostile_output" >/dev/null 2>&1 \
    && [[ ! -e "$hostile_marker" ]] \
    && jq -e '.context_budget_evidence.reporter_sha256 | test("^[0-9a-f]{64}$")' \
        "$hostile_output/run-plan.json" >/dev/null; then
    pass
else
    fail "runner trusted or executed the baseline-supplied context reporter"
fi

test_start "default mode plans exact paired trials without invoking a model"
plan_output="$fixture_root/plan-output"
if FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight \
    --repeats 2 \
    --output "$plan_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && [[ ! -e "$capture/call-0.args" ]] \
    && jq -e '
        .mode == "plan"
        and .requested_model == "test-model"
        and .planned_pairs == 2
        and .planned_runs == 4
        and .max_incomplete_pairs == 1
        and .model_catalog_timeout_seconds == 30
        and ([.runs[].pair_id] | group_by(.) | all(length == 2))
        and ([.runs[].trial_index] | sort | unique) == [1, 2]
        and ([.runs[].execution_order] | sort | unique) == ["baseline_first", "candidate_first"]
        and ([.runs[] | select(.execution_position == 1) | .variant] | sort | unique) == ["baseline", "candidate"]
        and (.baseline_variant | has("path") | not)
        and (.candidate_variant | has("path") | not)
        and (.candidate_manifest_sha256 | test("^[0-9a-f]{64}$"))
        and .execution_profile == {
          mode:"plan",
          codex_binary_source:"override",
          required_promotion_model:"gpt-5.6-terra",
          promotion_profile_eligible:false
        }
        and (.context_budget_evidence_sha256 | test("^[0-9a-f]{64}$"))
        and (.context_budget_evidence | type == "object")
        and .context_budget_evidence.policy_caps == {
          selected_initial_words_max:1000,
          selected_entry_words_max:2600,
          standing_context_growth_allowed:false
        }
        and (.context_budget_evidence.reporter_sha256 | test("^[0-9a-f]{64}$"))
    ' "$plan_output/run-plan.json" >/dev/null; then
    canonical_evidence_hash="$(jq -cS '.context_budget_evidence' "$plan_output/run-plan.json" | test_sha256_stream)"
    if [[ "$canonical_evidence_hash" == "$(jq -r '.context_budget_evidence_sha256' "$plan_output/run-plan.json")" ]] \
        && ! grep -Eq '/Users/|/home/|# Assistant Workflow|Purpose' "$plan_output/run-plan.json"; then
        pass
    else
        fail "plan context-budget evidence was not canonical, count-only, or path-free"
    fi
else
    fail "plan mode invoked Codex or did not emit exact pairs and context-budget evidence"
fi

test_start "default model uses the current GPT-5.6-Sol Codex catalog slug"
default_model_output="$fixture_root/default-model-output"
if FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight \
    --repeats 1 \
    --output "$default_model_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -e '.requested_model == "gpt-5.6-sol"' "$default_model_output/run-plan.json" >/dev/null; then
    pass
else
    fail "default model did not use the current gpt-5.6-sol Codex catalog slug"
fi

test_start "documented smoke command is explicitly GPT-5.6-Terra while runner default remains Sol"
if grep -Fq -- '--model gpt-5.6-terra' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq -- '--cases small-fix-stays-lightweight,seeded-code-review-regressions' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq -- '--repeats 1' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq 'The general runner default remains `gpt-5.6-sol`' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq 'GPT-5.6-Terra represents the common simple-task smoke profile' "$FRAMEWORK_DIR/docs/evals/README.md"; then
    pass
else
    fail "smoke guidance did not pin Terra explicitly without changing the Sol default"
fi

test_start "execute mode uses hardened Codex flags and blind prompts"
execute_output="$fixture_root/execute-output"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight \
    --repeats 1 \
    --output "$execute_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && [[ "$(find "$capture" -maxdepth 1 -name 'call-*.args' | wc -l | tr -d ' ')" -eq 2 ]] \
    && grep -Fxq -- 'exec' "$capture/call-0.args" \
    && grep -Fxq -- '--ephemeral' "$capture/call-0.args" \
    && grep -Fxq -- '--ignore-user-config' "$capture/call-0.args" \
    && grep -Fxq -- '-m' "$capture/call-0.args" \
    && grep -Fxq -- '-C' "$capture/call-0.args" \
    && grep -Fxq -- '--sandbox' "$capture/call-0.args" \
    && grep -Fxq -- 'workspace-write' "$capture/call-0.args" \
    && grep -Fxq -- '--json' "$capture/call-0.args" \
    && grep -Fxq -- '--output-last-message' "$capture/call-0.args" \
    && ! grep -Fq "Fix the typo 'teh' to 'the'" "$capture/call-0.args" \
    && grep -Fq "Fix the typo 'teh' to 'the'" "$capture/call-0.prompt" \
    && ! grep -Fq 'Expected Behavior' "$capture/call-0.prompt" \
    && ! grep -Fq 'Pass Criteria' "$capture/call-0.prompt" \
    && ! grep -Fq 'Fail Signals' "$capture/call-0.prompt" \
    && ! grep -Fq 'Machine Expectations' "$capture/call-0.prompt" \
    && grep -Fxq 'docs-usage-present' "$capture/call-0.fixtures" \
    && [[ "$(grep -lFx 'canonical-skill-surfaces-present' "$capture"/*.fixtures | wc -l | tr -d ' ')" -eq 2 ]] \
    && [[ "$(grep -lFx 'codex-state-path-substituted' "$capture"/*.fixtures | wc -l | tr -d ' ')" -eq 2 ]] \
    && [[ "$(grep -lFx 'skill-evals-hidden' "$capture"/*.fixtures | wc -l | tr -d ' ')" -eq 2 ]] \
    && jq -e '
      .mode == "execute"
      and .execution_profile.codex_binary_source == "override"
      and .execution_profile.required_promotion_model == "gpt-5.6-terra"
      and .execution_profile.promotion_profile_eligible == false
    ' "$execute_output/run-plan.json" >/dev/null; then
    pass
else
    fail "execute mode missed required Codex flags or leaked grader material into the runtime prompt"
fi

test_start "official Codex JSONL completes without inventing runtime model resolution"
official_jsonl_output="$fixture_root/official-jsonl-output"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_OFFICIAL_JSONL=true "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight \
    --repeats 1 \
    --output "$official_jsonl_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e '
      length == 2
      and all(.[];
        .status == "completed"
        and .model == "test-model"
        and .provenance.requested_model == "test-model"
        and .provenance.runtime_model_attestation == "not_exposed_by_codex_jsonl"
        and .provenance.model_selection_evidence == "explicit_model_argument_only"
        and .provenance.requested_model_catalog_entry_sha256 == null
        and (.provenance | has("resolved_model") | not)
        and .provenance.adapter_version == "codex-framework-eval-v5")
    ' "$official_jsonl_output/traces/"*.json >/dev/null \
    && jq -e '.complete_pairs == 1 and .excluded_incomplete_pairs == 0' \
        "$official_jsonl_output/comparison.json" >/dev/null; then
    pass
else
    fail "official thread.started shape was rejected or requested model was mislabeled as runtime resolution"
fi

trusted_bin="$fixture_root/trusted-bin"
trusted_output="$fixture_root/trusted-catalog-output"
mkdir -p "$trusted_bin"
cp "$fake_codex" "$trusted_bin/codex"
chmod +x "$trusted_bin/codex"

test_start "nested macOS Seatbelt execution fails before catalog lookup or model calls"
seatbelt_blocked_output="$fixture_root/seatbelt-blocked-output"
seatbelt_blocked_error="$fixture_root/seatbelt-blocked-error.txt"
rm -f "$capture"/*
if [[ "$(/usr/bin/uname -s)" != "Darwin" ]]; then
    pass
elif ! run_inside_outer_seatbelt /usr/bin/env \
    PATH="$trusted_bin:$PATH" \
    FAKE_CODEX_VERSION='codex-cli 0.144.1' \
    FAKE_CATALOG_MODE=changes_after_preflight \
    FAKE_CODEX_CAPTURE_DIR="$capture" \
    "$runner" --execute --model gpt-5.6-terra \
    --baseline-variant "$baseline" --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$seatbelt_blocked_output" \
    >/dev/null 2>"$seatbelt_blocked_error" \
    && grep -Fq 'host-side execution' "$seatbelt_blocked_error" \
    && grep -Fq 'Seatbelt' "$seatbelt_blocked_error" \
    && [[ ! -e "$seatbelt_blocked_output" ]] \
    && [[ ! -e "$capture/catalog-query-count" ]] \
    && ! find "$capture" -maxdepth 1 \( -name 'catalog-call-*' -o -name 'call-*.args' \) -print -quit | grep -q .; then
    pass
else
    fail "nested Seatbelt execution reached catalog lookup, model calls, or durable attempt state"
fi

test_start "plan mode never requires the macOS Seatbelt execution capability"
seatbelt_plan_output="$fixture_root/seatbelt-plan-output"
if "$runner" \
    --model gpt-5.6-terra \
    --baseline-variant "$baseline" --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$seatbelt_plan_output" \
    >/dev/null \
    && jq -e '.mode == "plan" and (.runs | length) == 2' "$seatbelt_plan_output/run-plan.json" >/dev/null; then
    pass
else
    fail "plan-only evidence incorrectly depended on the macOS execution sandbox"
fi

test_start "an explicit real Codex path cannot bypass the macOS Seatbelt preflight"
seatbelt_override_output="$fixture_root/seatbelt-override-output"
seatbelt_override_error="$fixture_root/seatbelt-override-error.txt"
rm -f "$capture"/*
if [[ "$(/usr/bin/uname -s)" != "Darwin" ]]; then
    pass
elif ! run_inside_outer_seatbelt /usr/bin/env \
    FAKE_CODEX_VERSION='codex-cli 0.144.1' \
    FAKE_CODEX_CAPTURE_DIR="$capture" \
    "$runner" --execute --model gpt-5.6-terra \
    --baseline-variant "$baseline" --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$seatbelt_override_output" \
    --codex-bin "$trusted_bin/codex" >/dev/null 2>"$seatbelt_override_error" \
    && grep -Fq 'host-side execution' "$seatbelt_override_error" \
    && [[ ! -e "$seatbelt_override_output" ]] \
    && ! find "$capture" -maxdepth 1 \( -name 'catalog-call-*' -o -name 'call-*.args' \) -print -quit | grep -q .; then
    pass
else
    fail "an explicitly supplied real Codex executable bypassed the Seatbelt preflight"
fi

test_start "trusted default CLI binds one exact requested catalog entry before model calls"
rm -f "$capture"/*
if PATH="$trusted_bin:$PATH" FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_OFFICIAL_JSONL=true \
    "$runner" --execute --model gpt-5.6-terra \
    --baseline-variant "$baseline" --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$trusted_output" >/dev/null \
    && jq -e '
      .execution_profile.codex_binary_source == "default"
      and .execution_profile.promotion_profile_eligible == true
      and .model_selection_evidence == {
        method:"codex_debug_models_requested_entry",
        catalog_source:"active",
        runtime_model_attestation:"not_exposed_by_codex_jsonl",
        requested_model_catalog_status:"present"
      }
      and (.requested_model_catalog_entry_sha256 | test("^[0-9a-f]{64}$"))
      and (.codex_executable_sha256 | test("^[0-9a-f]{64}$"))
      and .cli_version == "codex-cli 9.9.9-test"
    ' "$trusted_output/run-plan.json" >/dev/null \
    && jq -s -e --slurpfile plan "$trusted_output/run-plan.json" '
      length == 2
      and all(.[];
        .status == "completed"
        and .provenance.requested_model_catalog_entry_sha256 == $plan[0].requested_model_catalog_entry_sha256
        and .provenance.codex_executable_sha256 == $plan[0].codex_executable_sha256
        and .provenance.cli_version == $plan[0].cli_version)
    ' "$trusted_output/traces/"*.json >/dev/null; then
    pass
else
    fail "default CLI execution did not bind exact catalog-entry and executable evidence"
fi

test_start "invalid default catalog evidence fails before every model call"
catalog_failure_ok=true
for catalog_mode in malformed missing duplicate oversize; do
    catalog_output="$fixture_root/catalog-$catalog_mode-output"
    catalog_error="$fixture_root/catalog-$catalog_mode-error.txt"
    rm -f "$capture"/*
    if PATH="$trusted_bin:$PATH" FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_CATALOG_MODE="$catalog_mode" \
        "$runner" --execute --model gpt-5.6-terra \
        --baseline-variant "$baseline" --candidate-variant "$candidate" \
        --cases small-fix-stays-lightweight --repeats 1 --output "$catalog_output" \
        >/dev/null 2>"$catalog_error"; then
        catalog_failure_ok=false
    fi
    if find "$capture" -maxdepth 1 -name 'call-*.args' -print -quit | grep -q .; then
        catalog_failure_ok=false
    fi
done
if [[ "$catalog_failure_ok" == true ]]; then
    pass
else
    fail "malformed, missing, or duplicate requested catalog entries reached model execution"
fi

test_start "catalog-entry drift during execution withholds comparison and promotion artifacts"
midrun_drift_output="$fixture_root/midrun-catalog-drift-output"
midrun_drift_error="$fixture_root/midrun-catalog-drift-error.txt"
rm -f "$capture"/*
if ! PATH="$trusted_bin:$PATH" FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_CATALOG_MODE=changes_after_preflight \
    FAKE_OFFICIAL_JSONL=true "$runner" --execute --model gpt-5.6-terra \
    --baseline-variant "$baseline" --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$midrun_drift_output" \
    >/dev/null 2>"$midrun_drift_error" \
    && [[ "$(find "$capture" -maxdepth 1 -name 'call-*.args' | wc -l | tr -d ' ')" == "2" ]] \
    && [[ ! -e "$midrun_drift_output/comparison.json" ]] \
    && [[ ! -e "$midrun_drift_output/semantic-review-packet.json" ]]; then
    pass
else
    fail "mid-run model-selection drift produced aggregate or promotion evidence"
fi

test_start "systematic incomplete pairs stop before spending the remaining authorized batch"
breaker_output="$fixture_root/incomplete-pair-breaker-output"
breaker_error="$fixture_root/incomplete-pair-breaker-error.txt"
rm -f "$capture"/*
if ! FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_CODEX_FAILURE_MESSAGE='network unavailable' \
    "$runner" --execute --model test-model \
    --baseline-variant "$baseline" --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight,requirements-map-through-completion,medium-final-handoff-is-reconstructable \
    --repeats 1 --output "$breaker_output" --codex-bin "$fake_codex" \
    >/dev/null 2>"$breaker_error" \
    && [[ "$(find "$capture" -maxdepth 1 -name 'call-*.args' | wc -l | tr -d ' ')" == "4" ]] \
    && [[ "$(jq -s '[.[] | select(.state == "completed")] | length' "$breaker_output/run-attempts/"*.json)" == "4" ]] \
    && [[ "$(jq -s '[.[] | select(.state == "not_started")] | length' "$breaker_output/run-attempts/"*.json)" == "2" ]] \
    && [[ ! -e "$breaker_output/comparison.json" ]] \
    && [[ ! -e "$breaker_output/semantic-review-packet.json" ]]; then
    pass
else
    fail "systematic adapter failure spent calls past two incomplete pairs or emitted aggregate evidence"
fi

test_start "bounded catalog recheck stops a hanging lookup before later model calls"
catalog_hang_output="$fixture_root/catalog-hang-output"
catalog_hang_error="$fixture_root/catalog-hang-error.txt"
rm -f "$capture"/*
hang_started_at="$(date +%s)"
if ! PATH="$trusted_bin:$PATH" FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_CATALOG_MODE=hang_after_preflight \
    FAKE_OFFICIAL_JSONL=true "$runner" --execute --model gpt-5.6-terra \
    --baseline-variant "$baseline" --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight,requirements-map-through-completion,medium-final-handoff-is-reconstructable \
    --repeats 1 --model-catalog-timeout-seconds 1 --output "$catalog_hang_output" \
    >/dev/null 2>"$catalog_hang_error" \
    && [[ "$(( $(date +%s) - hang_started_at ))" -le 8 ]] \
    && [[ "$(find "$capture" -maxdepth 1 -name 'call-*.args' | wc -l | tr -d ' ')" == "2" ]] \
    && [[ -f "$capture/catalog-child-pid" ]] \
    && ! kill -0 "$(cat "$capture/catalog-child-pid")" 2>/dev/null \
    && [[ ! -e "$catalog_hang_output/comparison.json" ]] \
    && [[ ! -e "$catalog_hang_output/semantic-review-packet.json" ]]; then
    pass
else
    fail "hanging catalog recheck exceeded its bound or allowed later model calls"
fi

test_start "catalog entry drift blocks resume before any additional model call"
calls_before_drift="$(find "$capture" -maxdepth 1 -name 'call-*.args' | wc -l | tr -d ' ')"
drift_error="$fixture_root/catalog-drift-error.txt"
if ! PATH="$trusted_bin:$PATH" FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_CATALOG_MODE=changed \
    "$runner" --resume --execute --model gpt-5.6-terra \
    --baseline-variant "$baseline" --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$trusted_output" \
    >/dev/null 2>"$drift_error" \
    && [[ "$(find "$capture" -maxdepth 1 -name 'call-*.args' | wc -l | tr -d ' ')" == "$calls_before_drift" ]]; then
    pass
else
    fail "resume ignored requested catalog-entry drift or spent another model call"
fi

test_start "finalizer rechecks exact catalog-entry and executable evidence without model calls"
if (export PATH="$trusted_bin:$PATH" FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_CATALOG_MODE=valid
    source "$semantic_finalizer"
    trusted_execution_profile_passes "$trusted_output/run-plan.json" "$trusted_output/traces") \
    && ! (export PATH="$trusted_bin:$PATH" FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_CATALOG_MODE=changed
        source "$semantic_finalizer"
        trusted_execution_profile_passes "$trusted_output/run-plan.json" "$trusted_output/traces"); then
    pass
else
    fail "finalizer accepted missing or drifted current model-selection evidence"
fi

test_start "finalizer bounds a hanging current catalog recheck"
bounded_finalizer_plan="$fixture_root/bounded-finalizer-plan.json"
jq '.model_catalog_timeout_seconds = 1' "$trusted_output/run-plan.json" >"$bounded_finalizer_plan"
finalizer_hang_started_at="$(date +%s)"
if ! (export PATH="$trusted_bin:$PATH" FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_CATALOG_MODE=hang
    source "$semantic_finalizer"
    trusted_execution_profile_passes "$bounded_finalizer_plan" "$trusted_output/traces") \
    && [[ "$(( $(date +%s) - finalizer_hang_started_at ))" -le 8 ]]; then
    pass
else
    fail "finalizer catalog attestation could hang without a bounded failure"
fi

test_start "catalog attestation streams selected evidence without raw catalog temp files"
if ! grep -Eq 'codex-model-catalog[^[:space:]]*\.json|workflow-kernel-model-catalog\.' "$runner" "$semantic_finalizer" \
    && grep -Fq 'read_selected_model_catalog_entry' "$runner" \
    && grep -Fq 'read_selected_model_catalog_entry' "$semantic_finalizer"; then
    pass
else
    fail "runner or finalizer still materializes the instruction-bearing raw model catalog"
fi

test_start "official JSONL without runtime model telemetry remains explicit and untrusted under overrides"
missing_model_output="$fixture_root/missing-model-output"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_MISSING_MODEL_PROVENANCE=true \
    "$runner" --execute --model gpt-5.6-terra \
    --baseline-variant "$baseline" --candidate-variant "$hostile_candidate" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$missing_model_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e 'length == 2 and all(.[];
      .status == "completed"
      and .provenance.requested_model == "gpt-5.6-terra"
      and .provenance.runtime_model_attestation == "not_exposed_by_codex_jsonl"
      and .provenance.requested_model_catalog_entry_sha256 == null
      and (.provenance | has("resolved_model") | not))' \
        "$missing_model_output/traces/"*.json >/dev/null \
    && jq -e '.complete_pairs == 1 and .behavioral_promotion_eligible == false' \
        "$missing_model_output/comparison.json" >/dev/null; then
    pass
else
    fail "runner fabricated runtime resolution or trusted an override without catalog evidence"
fi

test_start "fresh plan and execute outputs reject symlink directories"
symlink_target="$fixture_root/symlink-output-target"
symlink_output="$fixture_root/symlink-output"
mkdir -p "$symlink_target"
chmod 755 "$symlink_target"
ln -s "$symlink_target" "$symlink_output"
if symlink_target_mode="$(stat -f '%Lp' "$symlink_target" 2>/dev/null)"; then
    :
else
    symlink_target_mode="$(stat -c '%a' "$symlink_target")"
fi
if ! FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" \
    --baseline-variant "$baseline" --candidate-variant "$hostile_candidate" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$symlink_output" \
    --codex-bin "$fake_codex" >/dev/null 2>&1 \
    && [[ ! -e "$symlink_target/run-plan.json" ]] \
    && [[ "$symlink_target_mode" == "755" ]]; then
    pass
else
    fail "fresh output followed a symlink or changed its target"
fi
rm -f "$symlink_output"

test_start "paid-call state and trace commits are fsync-backed before later transitions"
if grep -Fq 'os.fsync(handle)' "$runner" \
    && grep -Fq 'durable_atomic_write_json "$path"' "$runner" \
    && grep -Fq 'durable_atomic_write_json "$trace_path"' "$runner" \
    && grep -Fq 'durable_atomic_write_json "$trace"' "$runner" \
    && grep -Fq 'durable_atomic_write_json "$checkpoint_path"' "$runner"; then
    pass
else
    fail "paid-call state or evidence lacks an explicit fsync-backed durable write boundary"
fi

test_start "runner owns Codex termination and enforces a bounded per-run timeout"
lifecycle_ok=true
owned_child_output="$fixture_root/owned-child-output"
rm -f "$capture"/*
FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_CODEX_BLOCK_AFTER_INVOCATION=true \
    "$runner" --execute --model test-model \
    --baseline-variant "$baseline" --candidate-variant "$hostile_candidate" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$owned_child_output" \
    --codex-bin "$fake_codex" >/dev/null 2>&1 &
owned_runner_pid=$!
owned_invoked=false
for _ in {1..100}; do
    if [[ -f "$capture/call-0.pid" ]]; then owned_invoked=true; break; fi
    sleep 0.05
done
if [[ "$owned_invoked" == true ]]; then
    owned_codex_pid="$(cat "$capture/call-0.pid")"
    kill -TERM "$owned_runner_pid" 2>/dev/null || true
    owned_runner_exited=false
    for _ in {1..100}; do
        if ! kill -0 "$owned_runner_pid" 2>/dev/null; then owned_runner_exited=true; break; fi
        sleep 0.05
    done
    owned_child_alive=false
    kill -0 "$owned_codex_pid" 2>/dev/null && owned_child_alive=true
    if [[ "$owned_runner_exited" != true || "$owned_child_alive" == true ]]; then lifecycle_ok=false; fi
    kill -KILL "$owned_codex_pid" 2>/dev/null || true
    kill -KILL "$owned_runner_pid" 2>/dev/null || true
    wait "$owned_runner_pid" 2>/dev/null || true
else
    lifecycle_ok=false
    kill -KILL "$owned_runner_pid" 2>/dev/null || true
    wait "$owned_runner_pid" 2>/dev/null || true
fi

timeout_output="$fixture_root/timeout-output"
rm -f "$capture"/*
if ! FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_CODEX_BLOCK_AFTER_INVOCATION=true \
    "$runner" --execute --model test-model --run-timeout-seconds 1 \
    --baseline-variant "$baseline" --candidate-variant "$hostile_candidate" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$timeout_output" \
    --codex-bin "$fake_codex" >/dev/null 2>&1 \
    || ! jq -s -e 'length == 2 and all(.[]; .status == "adapter_unavailable"
      and .error.code == "execution_timed_out")' "$timeout_output/traces/"*.json >/dev/null 2>&1 \
    || find "$capture" -maxdepth 1 -name 'call-*.pid' -exec sh -c '
        for file do kill -0 "$(cat "$file")" 2>/dev/null && exit 1; done
      ' sh {} +; then
    lifecycle_ok=false
fi
if [[ "$lifecycle_ok" == true ]]; then
    pass
else
    fail "runner left Codex alive or did not classify and stop bounded timeouts"
fi

test_start "resume cleans an orphan plan temp and executes the newly recovered exact plan"
plan_temp_output="$fixture_root/resume-plan-temp-output"
mkdir -p "$plan_temp_output"
printf 'partial\n' >"$plan_temp_output/.run-plan.json.tmp.interrupted"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" --resume --execute \
    --model test-model --baseline-variant "$baseline" --candidate-variant "$hostile_candidate" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$plan_temp_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && [[ "$(find "$capture" -maxdepth 1 -name 'call-*.args' | wc -l | tr -d ' ')" -eq 2 ]] \
    && [[ -f "$plan_temp_output/run-plan.json" && -f "$plan_temp_output/comparison.json" ]] \
    && [[ ! -e "$plan_temp_output/.run-plan.json.tmp.interrupted" ]]; then
    pass
else
    fail "resume did not safely recover an orphan atomic plan temp"
fi

test_start "partial generic resume executes only the missing planned run"
resume_generic_output="$fixture_root/resume-generic-output"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" --execute \
    --model test-model --baseline-variant "$baseline" --candidate-variant "$hostile_candidate" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$resume_generic_output" \
    --codex-bin "$fake_codex" >/dev/null; then
    missing_generic_trace="$(find "$resume_generic_output/traces" -type f -name '*-candidate.json' -print -quit)"
    missing_generic_attempt="$resume_generic_output/run-attempts/$(basename "$missing_generic_trace")"
    rm -f "$missing_generic_trace" "$resume_generic_output/comparison.json"
    jq -cS '.state = "not_started" | .attempt_started_at = [] | .completed_at = null' \
        "$missing_generic_attempt" >"$missing_generic_attempt.tmp"
    mv "$missing_generic_attempt.tmp" "$missing_generic_attempt"
    rm -f "$capture"/*
    if FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" --resume --execute \
        --model test-model --baseline-variant "$baseline" --candidate-variant "$hostile_candidate" \
        --cases small-fix-stays-lightweight --repeats 1 --output "$resume_generic_output" \
        --codex-bin "$fake_codex" >/dev/null \
        && [[ "$(find "$capture" -maxdepth 1 -name 'call-*.args' | wc -l | tr -d ' ')" -eq 1 ]] \
        && [[ "$(find "$resume_generic_output/traces" -type f -name '*.json' | wc -l | tr -d ' ')" -eq 2 ]] \
        && jq empty "$resume_generic_output/comparison.json"; then
        pass
    else
        fail "resume repeated a completed generic run or omitted the missing run"
    fi
else
    fail "generic resume fixture could not be created"
fi

test_start "partial seeded resume restores a trace from bounded checkpoint and rebuilds the packet"
resume_seeded_output="$fixture_root/resume-seeded-output"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" --execute \
    --model test-model --baseline-variant "$baseline" --candidate-variant "$candidate" \
    --cases seeded-code-review-regressions --repeats 1 --output "$resume_seeded_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && [[ "$(find "$resume_seeded_output/semantic-checkpoints" -type f -name '*.json' | wc -l | tr -d ' ')" -eq 2 ]]; then
    rm -f "$resume_seeded_output/traces/"*-candidate.json \
        "$resume_seeded_output/comparison.json" "$resume_seeded_output/semantic-review-packet.json"
    rm -f "$capture"/*
    if FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" --resume --execute \
        --model test-model --baseline-variant "$baseline" --candidate-variant "$candidate" \
        --cases seeded-code-review-regressions --repeats 1 --output "$resume_seeded_output" \
        --codex-bin "$fake_codex" >/dev/null \
        && [[ ! -e "$capture/call-0.args" ]] \
        && jq -e '.reviewability.status == "ready" and (.pairs | length) == 1' \
            "$resume_seeded_output/semantic-review-packet.json" >/dev/null \
        && ! grep -REq 'thread\.started|turn\.completed|# Evaluation context|baseline grader anchor|candidate grader anchor' \
            "$resume_seeded_output/semantic-checkpoints"; then
        pass
    else
        fail "seeded resume repeated a paid call, lost bounded review evidence, or retained raw content"
    fi
else
    fail "seeded checkpoint fixture could not be created"
fi

test_start "resume blocks uncertain in-flight seeded and non-seeded runs before another model call"
uncertain_cases_ok=true
for uncertain_spec in \
    'small-fix-stays-lightweight generic' \
    'seeded-code-review-regressions seeded'; do
    read -r uncertain_case uncertain_kind <<<"$uncertain_spec"
    uncertain_output="$fixture_root/uncertain-$uncertain_kind-output"
    uncertain_candidate="$hostile_candidate"
    if [[ "$uncertain_kind" == "seeded" ]]; then
        uncertain_candidate="$candidate"
    fi
    rm -f "$capture"/*
    FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_CODEX_BLOCK_AFTER_INVOCATION=true \
        "$runner" --execute --model test-model \
        --baseline-variant "$baseline" --candidate-variant "$uncertain_candidate" \
        --cases "$uncertain_case" --repeats 1 --output "$uncertain_output" \
        --codex-bin "$fake_codex" >/dev/null 2>&1 &
    uncertain_runner_pid=$!
    uncertain_invoked=false
    for _ in {1..100}; do
        if [[ -f "$capture/call-0.pid" ]]; then
            uncertain_invoked=true
            break
        fi
        sleep 0.05
    done
    if [[ "$uncertain_invoked" != true ]]; then
        uncertain_cases_ok=false
        kill -KILL "$uncertain_runner_pid" 2>/dev/null || true
        wait "$uncertain_runner_pid" 2>/dev/null || true
        continue
    fi
    uncertain_codex_pid="$(cat "$capture/call-0.pid")"
    uncertain_workspace="$(awk 'previous == "-C" { print; exit } { previous = $0 }' "$capture/call-0.args")"
    uncertain_raw_root="$(dirname "$(dirname "$uncertain_workspace")")"
    kill -KILL "$uncertain_runner_pid" 2>/dev/null || true
    wait "$uncertain_runner_pid" 2>/dev/null || true
    kill -KILL "$uncertain_codex_pid" 2>/dev/null || true
    case "$uncertain_raw_root" in
        "${TMPDIR:-/tmp}"/codex-framework-evals.*) rm -rf -- "$uncertain_raw_root" ;;
        *) uncertain_cases_ok=false ;;
    esac

    uncertain_marker=""
    for candidate_marker in "$uncertain_output/run-attempts"/*.json; do
        [[ -f "$candidate_marker" ]] || continue
        if jq -e '.state == "in_flight"' "$candidate_marker" >/dev/null; then
            uncertain_marker="$candidate_marker"
            break
        fi
    done
    uncertain_run_id=""
    if [[ -n "$uncertain_marker" ]]; then
        uncertain_run_id="$(jq -r '.run_id // empty' "$uncertain_marker")"
    fi
    rm -f "$capture"/*
    if [[ -z "$uncertain_marker" || -z "$uncertain_run_id" ]] \
        || FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" --resume --execute --model test-model \
            --baseline-variant "$baseline" --candidate-variant "$uncertain_candidate" \
            --cases "$uncertain_case" --repeats 1 --output "$uncertain_output" \
            --codex-bin "$fake_codex" >"$fixture_root/uncertain-$uncertain_kind.stdout" \
            2>"$fixture_root/uncertain-$uncertain_kind.stderr" \
        || [[ -e "$capture/call-0.args" ]] \
        || ! grep -Fq "$uncertain_run_id" "$fixture_root/uncertain-$uncertain_kind.stderr" \
        || ! grep -Fq 'Separate explicit retry authorization is required.' \
            "$fixture_root/uncertain-$uncertain_kind.stderr" \
        || ! jq -e '
            (keys_unsorted | sort) == (["attempt_started_at","case_id","completed_at","pair_id","run_id","run_plan_sha256","schema_version","state","trial_index","variant"] | sort)
            and .schema_version == "1.0"
            and .state == "in_flight"
            and (.run_plan_sha256 | test("^[0-9a-f]{64}$"))
            and (.attempt_started_at | type == "array" and length == 1 and all(.[]; type == "number" and . == floor and . > 0))
            and .completed_at == null
        ' "$uncertain_marker" >/dev/null \
        || grep -Eqi 'prompt|response|event|stderr|workspace|secret|token|credential|environment' "$uncertain_marker"; then
        uncertain_cases_ok=false
    fi
done
if [[ "$uncertain_cases_ok" == true ]]; then
    pass
else
    fail "resume retried or did not safely report a seeded/non-seeded uncertain in-flight run"
fi

test_start "resume rejects unknown files and tampered traces or checkpoints before calls"
resume_tampered_trace="$fixture_root/resume-tampered-trace"
resume_tampered_checkpoint="$fixture_root/resume-tampered-checkpoint"
resume_unknown="$fixture_root/resume-unknown"
resume_finalized="$fixture_root/resume-finalized"
cp -R "$resume_generic_output" "$resume_tampered_trace"
cp -R "$resume_seeded_output" "$resume_tampered_checkpoint"
cp -R "$resume_generic_output" "$resume_unknown"
cp -R "$resume_generic_output" "$resume_finalized"
tampered_trace="$(find "$resume_tampered_trace/traces" -type f -name '*.json' -print -quit)"
jq '.provenance.fixture_sha256 = ("f" * 64)' "$tampered_trace" >"$tampered_trace.tmp"
mv "$tampered_trace.tmp" "$tampered_trace"
tampered_checkpoint="$(find "$resume_tampered_checkpoint/semantic-checkpoints" -type f -name '*.json' -print -quit)"
jq '.trace_sha256 = ("f" * 64)' "$tampered_checkpoint" >"$tampered_checkpoint.tmp"
mv "$tampered_checkpoint.tmp" "$tampered_checkpoint"
printf 'unknown\n' >"$resume_unknown/unrecognized.txt"
printf '{}\n' >"$resume_finalized/semantic-review-verdict.json"
rm -f "$capture"/*
resume_rejections=0
for rejected_output in "$resume_tampered_trace" "$resume_tampered_checkpoint" "$resume_unknown" "$resume_finalized"; do
    rejected_candidate="$hostile_candidate"
    rejected_cases="small-fix-stays-lightweight"
    if [[ "$rejected_output" == "$resume_tampered_checkpoint" ]]; then
        rejected_candidate="$candidate"
        rejected_cases="seeded-code-review-regressions"
    fi
    if ! FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" --resume --execute \
        --model test-model --baseline-variant "$baseline" --candidate-variant "$rejected_candidate" \
        --cases "$rejected_cases" --repeats 1 --output "$rejected_output" \
        --codex-bin "$fake_codex" >/dev/null 2>&1; then
        resume_rejections=$((resume_rejections + 1))
    fi
done
if [[ "$resume_rejections" -eq 4 && ! -e "$capture/call-0.args" ]]; then
    pass
else
    fail "resume accepted unknown, finalized, or tampered persisted evidence"
fi

test_start "stale-state case contains real conflicting journal and repository evidence"
stale_output="$fixture_root/stale-output"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases stale-journal-yields-to-current-evidence \
    --repeats 1 \
    --output "$stale_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && [[ "$(grep -lFx 'stale-journal-conflict-present' "$capture"/*.fixtures | wc -l | tr -d ' ')" -eq 2 ]] \
    && grep -Fq 'Continue the approved current-task work' "$capture/call-0.prompt" \
    && ! grep -Fq 'Continue the active work from the journal' "$capture/call-0.prompt" \
    && jq -s -e 'all(.[].execution.verifier;
      .workspace_status == "passed"
      and .workspace_failure_ids == []
      and .acceptance_items_passed == .acceptance_items_total
    )' "$stale_output/traces/"*.json >/dev/null; then
    pass
else
    fail "stale-journal behavior is still evaluated only by prompt restatement"
fi

test_start "stale-state verifier reports the exact failed reconciliation predicate"
stale_predicates_ok=true
for stale_spec in \
    'unchanged workspace-001' \
    'missing_current_active workspace-002' \
    'missing_previous workspace-003' \
    'missing_reason workspace-004' \
    'missing_next workspace-005'; do
    read -r stale_mode expected_workspace_id <<<"$stale_spec"
    stale_mode_output="$fixture_root/stale-$stale_mode-output"
    rm -f "$capture"/*
    if ! FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_STALE_JOURNAL_MODE="$stale_mode" "$runner" --execute \
        --model test-model --baseline-variant "$baseline" --candidate-variant "$candidate" \
        --cases stale-journal-yields-to-current-evidence --repeats 1 --output "$stale_mode_output" \
        --codex-bin "$fake_codex" >/dev/null \
        || ! jq -s -e --arg expected "$expected_workspace_id" '
          all(.[] | select(.variant == "baseline");
            .execution.verifier.workspace_status == "passed"
            and .execution.verifier.workspace_failure_ids == [])
          and all(.[] | select(.variant == "candidate");
            .execution.verifier.workspace_status == "failed"
            and (.execution.verifier.workspace_failure_ids | index($expected)) != null
            and .execution.verifier.acceptance_items_passed < .execution.verifier.acceptance_items_total)
        ' "$stale_mode_output/traces/"*.json >/dev/null; then
        stale_predicates_ok=false
    fi
done
if [[ "$stale_predicates_ok" == true ]]; then
    pass
else
    fail "stale-journal predicate failures were missing, unbounded, or conflated"
fi

test_start "state traceability and handoff cases use concrete fixtures and verifiers"
evidence_cases_output="$fixture_root/evidence-cases-output"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases stale-journal-yields-to-current-evidence,requirements-map-through-completion,medium-final-handoff-is-reconstructable \
    --repeats 1 \
    --output "$evidence_cases_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && [[ "$(grep -lFx 'stale-journal-conflict-present' "$capture"/*.fixtures | wc -l | tr -d ' ')" -eq 2 ]] \
    && [[ "$(grep -lFx 'requirements-fixture-present' "$capture"/*.fixtures | wc -l | tr -d ' ')" -eq 2 ]] \
    && [[ "$(grep -lFx 'handoff-fixture-present' "$capture"/*.fixtures | wc -l | tr -d ' ')" -eq 2 ]] \
    && jq -s -e 'all(.[];
      .status == "completed"
      and .metrics.acceptance_passed == true
      and .metrics.scope_deviations == 0
      and .metrics.verifier_exit_code == 0
    )' "$evidence_cases_output/traces/"*.json >/dev/null; then
    pass
else
    fail "R1 R3 or R7 behavioral cases remained prompt-only or unverifiable"
fi

test_start "structured workflow artifacts grade behavior independently of final response wording"
structured_positive_output="$fixture_root/structured-positive-output"
structured_negative_output="$fixture_root/structured-negative-output"
structured_cases="requirements-map-through-completion,ordinary-medium-bounded-executor,medium-final-handoff-is-reconstructable"
rm -f "$capture"/*
structured_positive_ok=false
structured_negative_ok=false
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_STRUCTURED_ARTIFACTS=true FAKE_STRUCTURED_PARAPHRASE=true \
    "$runner" --execute \
    --model test-model --baseline-variant "$baseline" --candidate-variant "$candidate" \
    --cases "$structured_cases" --repeats 1 --output "$structured_positive_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e 'all(.[].execution.verifier;
      .status == "passed"
      and .workspace_status == "passed"
      and .workspace_failure_ids == []
      and .required_missing == 0
      and .acceptance_items_total > 0
      and .acceptance_items_passed == .acceptance_items_total
    )' "$structured_positive_output/traces/"*.json >/dev/null \
    && [[ "$(grep -lF '.assistant-eval/' "$capture"/*.prompt | wc -l | tr -d ' ')" -eq 6 ]] \
    && ! grep -Fq '.codex/requirement-map.json' "$capture"/*.prompt \
    && ! grep -Fq '.codex/execution-decision.json' "$capture"/*.prompt \
    && ! grep -Fq '.codex/final-handoff.json' "$capture"/*.prompt \
    && ! grep -R -E 'newest first|avoid mutable global state|mixed-case fixture' "$structured_positive_output" >/dev/null 2>&1; then
    structured_positive_ok=true
fi

rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_STRUCTURED_ARTIFACTS=true FAKE_STRUCTURED_PARAPHRASE=true \
    FAKE_INVALID_STRUCTURED_ARTIFACT=true "$runner" --execute \
    --model test-model --baseline-variant "$baseline" --candidate-variant "$candidate" \
    --cases "$structured_cases" --repeats 1 --output "$structured_negative_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e '
      all(.[] | select(.variant == "baseline");
        .metrics.acceptance_passed == true and .execution.verifier.workspace_failure_ids == [])
      and all(.[] | select(.variant == "candidate");
        .metrics.acceptance_passed == false
        and .execution.verifier.workspace_status == "failed"
        and (.execution.verifier.workspace_failure_ids | length) > 0
        and .execution.verifier.acceptance_items_passed < .execution.verifier.acceptance_items_total
        and all(.execution.verifier.workspace_failure_ids[]; test("^workspace-[0-9]{3}$")))
    ' "$structured_negative_output/traces/"*.json >/dev/null \
    && ! grep -R -E 'newest first|avoid mutable global state|mixed-case fixture' "$structured_negative_output" >/dev/null 2>&1; then
    structured_negative_ok=true
fi
if [[ "$structured_positive_ok" == true && "$structured_negative_ok" == true ]]; then
    pass
else
    fail "structured workflow artifacts were ignored, lexically graded, unbounded, or retained"
fi

test_start "ordered workflow verifier rejects every missing repair-loop stage"
ordered_workflow_negative_ok=true
for workflow_spec in \
    'skip_failed_review workspace-011' \
    'first_review_passes workspace-011' \
    'skip_repair workspace-012' \
    'skip_revalidation workspace-013' \
    'fresh_review_fails workspace-014' \
    'early_handoff workspace-014' \
    'false_review_finding workspace-011' \
    'no_op_repair workspace-012' \
    'spoof_review_commands workspace-011'; do
    read -r workflow_mode expected_workspace_id <<<"$workflow_spec"
    workflow_output="$fixture_root/ordered-workflow-$workflow_mode-output"
    rm -f "$capture"/*
    if ! FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_END_TO_END_MODE="$workflow_mode" \
        "$runner" --execute \
        --model test-model --baseline-variant "$baseline" --candidate-variant "$candidate" \
        --cases medium-final-handoff-is-reconstructable --repeats 1 \
        --output "$workflow_output" --codex-bin "$fake_codex" >/dev/null \
        || ! jq -s -e --arg expected "$expected_workspace_id" '
          all(.[] | select(.variant == "baseline");
            .metrics.acceptance_passed == true
            and .execution.verifier.workspace_status == "passed"
            and .execution.verifier.workspace_failure_ids == [])
          and all(.[] | select(.variant == "candidate");
            .metrics.acceptance_passed == false
            and .execution.verifier.workspace_status == "failed"
            and (.execution.verifier.workspace_failure_ids | index($expected)) != null)
        ' "$workflow_output/traces/"*.json >/dev/null; then
        ordered_workflow_negative_ok=false
    fi
done
if [[ "$ordered_workflow_negative_ok" == true ]]; then
    pass
else
    fail "ordered workflow omissions were accepted or reported without their stable workspace failure id"
fi

test_start "handoff grading uses anchored bounded grammars for rollback and review claims"
handoff_paraphrase_output="$fixture_root/handoff-paraphrase-output"
handoff_absolute_output="$fixture_root/handoff-absolute-output"
rm -f "$capture"/*
handoff_paraphrase_ok=false
handoff_absolute_ok=false
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_HANDOFF_CLAIM_MODE=paraphrase \
    "$runner" --execute \
    --model test-model --baseline-variant "$baseline" --candidate-variant "$candidate" \
    --cases medium-final-handoff-is-reconstructable --repeats 1 \
    --output "$handoff_paraphrase_output" --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e 'all(.[].execution.verifier;
      .status == "passed" and .workspace_status == "passed" and .workspace_failure_ids == [])' \
      "$handoff_paraphrase_output/traces/"*.json >/dev/null; then
    handoff_paraphrase_ok=true
fi
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_HANDOFF_CLAIM_MODE=contradictory_candidate \
    "$runner" --execute \
    --model test-model --baseline-variant "$baseline" --candidate-variant "$candidate" \
    --cases medium-final-handoff-is-reconstructable --repeats 1 \
    --output "$handoff_absolute_output" --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e '
      all(.[] | select(.variant == "baseline"); .metrics.acceptance_passed == true)
      and all(.[] | select(.variant == "candidate");
        .metrics.acceptance_passed == false
        and (.execution.verifier.workspace_failure_ids | index("workspace-009")) != null
        and (.execution.verifier.workspace_failure_ids | index("workspace-010")) != null)
    ' "$handoff_absolute_output/traces/"*.json >/dev/null; then
    handoff_absolute_ok=true
fi
if [[ "$handoff_paraphrase_ok" == true && "$handoff_absolute_ok" == true ]]; then
    pass
else
    fail "handoff verifier remained literal-only or accepted text outside its bounded grammars"
fi

test_start "structured grading rejects valid garbage and unsafe artifact paths before parsing"
structured_hardening_ok=true
garbage_output="$fixture_root/structured-garbage-output"
rm -f "$capture"/*
if ! FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_STRUCTURED_ATTACK=garbage FAKE_STRUCTURED_PARAPHRASE=true \
    "$runner" --execute \
    --model test-model --baseline-variant "$baseline" --candidate-variant "$candidate" \
    --cases requirements-map-through-completion,medium-final-handoff-is-reconstructable \
    --repeats 1 --output "$garbage_output" --codex-bin "$fake_codex" >/dev/null \
    || ! jq -s -e '
      all(.[] | select(.variant == "baseline"); .metrics.acceptance_passed == true)
      and all(.[] | select(.variant == "candidate");
        .metrics.acceptance_passed == false
        and .execution.verifier.workspace_status == "failed"
        and (.execution.verifier.workspace_failure_ids | length) > 0)
    ' "$garbage_output/traces/"*.json >/dev/null; then
    structured_hardening_ok=false
fi
for attack in file_symlink parent_escape oversize; do
    attack_output="$fixture_root/structured-$attack-output"
    rm -f "$capture"/*
    if ! FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_STRUCTURED_ATTACK="$attack" FAKE_STRUCTURED_PARAPHRASE=true \
        "$runner" --execute \
        --model test-model --baseline-variant "$baseline" --candidate-variant "$candidate" \
        --cases requirements-map-through-completion --repeats 1 \
        --output "$attack_output" --codex-bin "$fake_codex" >/dev/null \
        || ! jq -s -e '
          all(.[] | select(.variant == "baseline");
            .metrics.acceptance_passed == true and .execution.verifier.workspace_failure_ids == [])
          and all(.[] | select(.variant == "candidate");
            .metrics.acceptance_passed == false
            and .execution.verifier.workspace_status == "failed"
            and (.execution.verifier.workspace_failure_ids | index("workspace-001")) != null)
        ' "$attack_output/traces/"*.json >/dev/null; then
        structured_hardening_ok=false
    fi
done
if [[ "$structured_hardening_ok" == true ]] \
    && ! grep -R -E 'outside-[0-9]+|garbage' \
        "$garbage_output" "$fixture_root"/structured-file_symlink-output \
        "$fixture_root"/structured-parent_escape-output "$fixture_root"/structured-oversize-output >/dev/null 2>&1; then
    pass
else
    fail "structured artifact path guards or closed-world semantic checks failed or leaked content"
fi

test_start "isolated workspaces seed state and editable targets without grader anchors"
seed_output="$fixture_root/seed-output"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases compaction-resume-reads-task-state-first,codex-role-constraints-native \
    --repeats 1 \
    --output "$seed_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && [[ "$(grep -lFx 'task-state-present' "$capture"/*.fixtures | wc -l | tr -d ' ')" -eq 2 ]] \
    && [[ "$(grep -lFx 'eval-target-redacted' "$capture"/*.fixtures | wc -l | tr -d ' ')" -eq 2 ]] \
    && jq -s -e 'all(.[] | select(.case_id == "codex-role-constraints-native"); .metrics.scope_deviations == 0 and .metrics.verifier_exit_code == 0)' "$seed_output/traces/"*.json >/dev/null; then
    pass
else
    fail "isolated case fixtures were missing or copied hidden machine expectations"
fi

test_start "variant directories reject symlinks before planning or execution"
symlink_output="$fixture_root/symlink-output"
ln -s "$FRAMEWORK_DIR/README.md" "$baseline/external-link"
symlink_error="$fixture_root/symlink-error.txt"
if "$runner" \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight \
    --output "$symlink_output" \
    --codex-bin "$fake_codex" > /dev/null 2>"$symlink_error"; then
    fail "runner accepted a variant symlink that could escape the isolated workspace"
elif grep -Fq 'Variant directories may contain only regular files and directories' "$symlink_error"; then
    pass
else
    fail "variant symlink rejection was not actionable"
fi
rm -f "$baseline/external-link"

test_start "completed traces carry pair identity, provenance, verifier evidence, and no raw bodies"
if [[ "$(find "$execute_output/traces" -maxdepth 1 -name '*.json' | wc -l | tr -d ' ')" -eq 2 ]] \
    && jq -e '
        .schema_version == "1.0"
        and (.pair_id | type == "string" and length > 0)
        and .trial_index == 1
        and .status == "completed"
        and .metrics.input_tokens == 123
        and .metrics.output_tokens == 45
        and .metrics.acceptance_items_total > 0
        and .metrics.acceptance_items_passed == .metrics.acceptance_items_total
        and .metrics.seeded_defects_detected == 0
        and .metrics.seeded_defects_total == 0
        and .metrics.false_positive_marker_hits == 0
        and .metrics.forbidden_command_hits == 0
        and .metrics.scope_deviations == 0
        and .metrics.verifier_exit_code == 0
        and (.provenance.fixture_sha256 | test("^[0-9a-f]{64}$"))
        and (.provenance.case_sha256 | test("^[0-9a-f]{64}$"))
        and (.provenance.instruction_sha256 | test("^[0-9a-f]{64}$"))
        and (.provenance.grader_sha256 | test("^[0-9a-f]{64}$"))
        and .provenance.cli_version == "codex-cli 9.9.9-test"
        and .provenance.requested_model == "test-model"
        and .provenance.runtime_model_attestation == "not_exposed_by_codex_jsonl"
        and .provenance.model_selection_evidence == "explicit_model_argument_only"
        and .provenance.requested_model_catalog_entry_sha256 == null
        and (.provenance.codex_executable_sha256 | test("^[0-9a-f]{64}$"))
        and (.provenance | has("resolved_model") | not)
        and (.provenance.adapter_version | type == "string" and length > 0)
        and .execution.exit_code == 0
        and .execution.verifier.status == "passed"
        and .execution.verifier.workspace_status == "passed"
        and .execution.metric_methods.time_to_first_useful_action_ms == "completion_latency_upper_bound"
        and .execution.metric_methods.question_mark_count_proxy == "question_mark_count_proxy"
        and (.metrics.question_mark_count_proxy | type == "number")
        and (.metrics | has("unnecessary_questions") | not)
        and (.execution.metric_methods | has("unnecessary_questions") | not)
        and .execution.metric_methods.rework_count == "additional_file_change_events_proxy"
        and (has("prompt") | not)
        and (has("response") | not)
    ' "$execute_output/traces/"*.json >/dev/null \
    && "$legacy_runner" --validate-traces "$execute_output/traces" >/dev/null \
    && ! find "$execute_output" -type f \( -name '*.jsonl' -o -name '*.txt' -o -name '*.md' \) | grep -q .; then
    pass
else
    fail "persisted traces lack provenance/verifier fields, violate the schema, or retain raw content"
fi

test_start "grader provenance binds the canonical contract and full v5 runner bytes"
small_contract_hash="$(jq -cS --arg id small-fix-stays-lightweight '
  .cases[] | select(.id == $id) | {fail_signals,machine_expectations,semantic_review}
' "$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json" | test_sha256_stream)"
runner_implementation_hash="$(test_sha256_stream <"$runner")"
expected_grader_hash="$(printf 'contract_sha256=%s\nrunner_sha256=%s\n' \
    "$small_contract_hash" "$runner_implementation_hash" | test_sha256_stream)"
changed_grader_hash="$(printf 'contract_sha256=%s\nrunner_sha256=%064d\n' \
    "$small_contract_hash" 0 | test_sha256_stream)"
if jq -s -e --arg expected "$expected_grader_hash" 'all(.[].provenance;
      .grader_sha256 == $expected and .adapter_version == "codex-framework-eval-v5")
    ' "$execute_output/traces/"*.json >/dev/null \
    && [[ "$changed_grader_hash" != "$expected_grader_hash" ]]; then
    pass
else
    fail "grader hash is not bound to the exact case contract and full v5 runner implementation"
fi

test_start "case-specific command verifier catches forbidden test execution"
forbidden_command_output="$fixture_root/forbidden-command-output"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_RUN_FORBIDDEN_TEST=true "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases codex-role-constraints-native \
    --repeats 1 \
    --output "$forbidden_command_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e 'all(.[];
      .metrics.forbidden_command_hits == 1
      and .metrics.acceptance_passed == false
      and .execution.verifier.forbidden_command_hits == 1
    )' "$forbidden_command_output/traces/"*.json >/dev/null; then
    pass
else
    fail "case-forbidden test commands did not fail redacted verification"
fi

test_start "raw mode-0700 storage is deleted after every run"
raw_storage_ok=true
raw_path_files=()
while IFS= read -r raw_path_file; do
    raw_path_files+=("$raw_path_file")
done < <(find "$capture" -maxdepth 1 -name '*.raw-dir' -print | LC_ALL=C sort)
if [[ "${#raw_path_files[@]}" -eq 0 ]]; then
    raw_storage_ok=false
fi
for raw_path_file in "${raw_path_files[@]}"; do
    raw_path="$(cat "$raw_path_file")"
    mode_file="${raw_path_file%.raw-dir}.raw-mode"
    if [[ "$(cat "$mode_file")" != "700" || -e "$raw_path" ]]; then
        raw_storage_ok=false
    fi
done
if [[ "$raw_storage_ok" == "true" ]]; then
    pass
else
    fail "raw execution storage was not mode 0700 or survived successful execution"
fi

test_start "completed traces retain bounded criterion IDs with count parity and no response prose"
diagnostic_output="$fixture_root/diagnostic-output"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_BAD_RESPONSE=true "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight \
    --repeats 1 \
    --output "$diagnostic_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e 'all(.[].execution.verifier;
      .missing_required_ids == ["required-001"]
      and .required_missing == (.missing_required_ids | length)
      and .forbidden_hits == (.forbidden_hit_ids | length)
      and .fail_signal_hits == (.fail_signal_hit_ids | length)
      and .seeded_defects_detected == (.seeded_defects_total - (.seeded_defect_missed_ids | length))
      and .false_positive_marker_hits == (.false_positive_marker_hit_ids | length)
      and all(
        .missing_required_ids[],
        .forbidden_hit_ids[],
        .fail_signal_hit_ids[],
        .seeded_defect_missed_ids[],
        .false_positive_marker_hit_ids[];
        test("^(required|forbidden|fail-signal|seeded-defect|false-positive)-[0-9]{3}$")
      )
    )' "$diagnostic_output/traces/"*.json >/dev/null \
    && ! grep -R -F 'No material findings.' "$diagnostic_output" >/dev/null 2>&1; then
    pass
else
    fail "trace diagnostics were count-only, unbounded, inconsistent, or retained response prose"
fi

test_start "small-fix acceptance is workspace-primary while concise handoff passes and broad or scoped work fails"
small_concise_output="$fixture_root/small-concise-output"
small_broad_output="$fixture_root/small-broad-output"
small_scope_output="$fixture_root/small-scope-output"
small_wrong_output="$fixture_root/small-wrong-output"
small_plan_mode_output="$fixture_root/small-plan-mode-output"
rm -f "$capture"/*
small_concise_ok=false
small_broad_ok=false
small_scope_ok=false
small_wrong_ok=false
small_plan_mode_ok=false
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_SMALL_CONCISE=true "$runner" --execute \
    --model test-model --baseline-variant "$baseline" --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$small_concise_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e 'all(.[].execution.verifier;
      .status == "passed"
      and .workspace_status == "passed"
      and .required_missing == 0
      and .forbidden_hits == 0
      and .scope_deviations == 0
    )' "$small_concise_output/traces/"*.json >/dev/null; then
    small_concise_ok=true
fi
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_SMALL_BROAD=true "$runner" --execute \
    --model test-model --baseline-variant "$baseline" --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$small_broad_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e 'all(.[].execution.verifier;
      .status == "failed" and .workspace_status == "passed" and .forbidden_hits == 1
    )' "$small_broad_output/traces/"*.json >/dev/null; then
    small_broad_ok=true
fi
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_SMALL_CONCISE=true FAKE_SCOPE_DEVIATION=true "$runner" --execute \
    --model test-model --baseline-variant "$baseline" --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$small_scope_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e 'all(.[].execution.verifier;
      .status == "failed" and .workspace_status == "failed" and .scope_deviations == 1
    )' "$small_scope_output/traces/"*.json >/dev/null; then
    small_scope_ok=true
fi
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_SMALL_CONCISE=true FAKE_WRONG_SMALL_EDIT=true "$runner" --execute \
    --model test-model --baseline-variant "$baseline" --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$small_wrong_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e 'all(.[].execution.verifier;
      .status == "failed" and .workspace_status == "failed" and .scope_deviations == 0
    )' "$small_wrong_output/traces/"*.json >/dev/null; then
    small_wrong_ok=true
fi
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_SMALL_CONCISE=true FAKE_SMALL_PLAN_MODE=inline "$runner" --execute \
    --model test-model --baseline-variant "$baseline" --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$small_plan_mode_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e '
      all(.[] | select(.variant == "baseline");
        .metrics.acceptance_passed == true and .execution.verifier.workspace_status == "passed")
      and all(.[] | select(.variant == "candidate");
        .metrics.acceptance_passed == false
        and .execution.verifier.workspace_status == "failed"
        and (.execution.verifier.workspace_failure_ids | index("workspace-002")) != null)
    ' "$small_plan_mode_output/traces/"*.json >/dev/null; then
    small_plan_mode_ok=true
fi
if [[ "$small_concise_ok" == true && "$small_broad_ok" == true && "$small_scope_ok" == true && "$small_wrong_ok" == true && "$small_plan_mode_ok" == true ]]; then
    pass
else
    fail "small-fix grader required ritual words or accepted broad/out-of-scope/plan_mode behavior"
fi

test_start "seeded review case reports defect recall and false positives"
seeded_output="$fixture_root/seeded-output"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases seeded-code-review-regressions \
    --repeats 1 \
    --output "$seeded_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e 'all(.[];
        .metrics.seeded_defects_detected == 4
        and .metrics.seeded_defects_total == 4
        and .metrics.false_positive_marker_hits == 0
        and .metrics.acceptance_passed == true
      )' "$seeded_output/traces/"*.json >/dev/null \
    && jq -e '
      .complete_pairs == 1
      and (.candidate_manifest_sha256 | test("^[0-9a-f]{64}$"))
      and .variants.baseline.metrics.seeded_defect_recall == 1
      and .variants.candidate.metrics.seeded_defect_recall == 1
      and .variants.baseline.metrics.false_positive_marker_hits_total == 0
      and .variants.candidate.metrics.scope_deviations_total == 0
      and .promotion_gate_results.seeded_defect_recall_not_lower == true
      and .promotion_gate_results.false_positive_marker_hits_not_higher == true
      and .promotion_gate_results.scope_deviations_not_higher == true
      and .smoke_passed == false
      and .pilot_coverage_complete == false
      and .behavioral_promotion_eligible == false
      and .semantic_false_positive_review_required == true
    ' "$seeded_output/comparison.json" >/dev/null; then
    pass
else
    fail "seeded review trace did not preserve measurable recall and false-positive evidence"
fi

test_start "seeded review acceptance uses source-scoped normalized claims across paraphrases and blocks ambiguity"
paraphrase_output="$fixture_root/semantic-paraphrase-output"
ambiguous_output="$fixture_root/semantic-ambiguous-output"
rm -f "$capture"/*
paraphrase_ok=false
ambiguity_ok=false
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_SEMANTIC_PARAPHRASE=true "$runner" --execute \
    --model test-model --baseline-variant "$baseline" --candidate-variant "$candidate" \
    --cases seeded-code-review-regressions --repeats 1 --output "$paraphrase_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e 'all(.[];
      .metrics.acceptance_passed == true
      and .metrics.seeded_defects_detected == 4
      and .execution.verifier.required_missing == 0
      and .execution.verifier.seeded_defect_missed_ids == []
      and .execution.verifier.false_positive_marker_hit_ids == []
    )' "$paraphrase_output/traces/"*.json >/dev/null \
    && jq -e '
      .reviewability.status == "ready"
      and .diagnostics == []
      and all(.pairs[].baseline.findings[], .pairs[].candidate.findings[];
        .claim_code == "missing_preferred_discount"
        or .claim_code == "mutates_input_order"
        or .claim_code == "negative_quantity_not_rejected"
        or .claim_code == "test_has_no_behavioral_assertion")
    ' "$paraphrase_output/semantic-review-packet.json" >/dev/null; then
    paraphrase_ok=true
fi
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_AMBIGUOUS_SEMANTIC=true "$runner" --execute \
    --model test-model --baseline-variant "$baseline" --candidate-variant "$candidate" \
    --cases seeded-code-review-regressions --repeats 1 --output "$ambiguous_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -e '
      .reviewability.status == "blocked"
      and .pairs == []
      and (.diagnostics[] | select(.variant == "candidate")
        | .finding_failures == [{finding_id:"candidate-05",reason_code:"multiple_claim_rule_matches"}])
    ' "$ambiguous_output/semantic-review-packet.json" >/dev/null; then
    ambiguity_ok=true
fi
if [[ "$paraphrase_ok" == true && "$ambiguity_ok" == true ]]; then
    pass
else
    fail "seeded review remained tied to exact prose or accepted an ambiguous claim"
fi

test_start "synthetic semantic packet preserves bounded review summaries and rejected laundering fails closed"
laundering_output="$fixture_root/semantic-laundering-output"
laundering_missing_output="$fixture_root/semantic-laundering-missing-output"
laundering_missing_packet="$fixture_root/semantic-laundering-missing-packet.json"
laundering_template="$fixture_root/semantic-laundering-template.json"
laundering_verdict="$fixture_root/semantic-laundering-verdict.json"
rm -f "$capture"/*
laundering_summary_ok=false
laundering_missing_blocked=false
laundering_rejected=false
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_SEMANTIC_LAUNDERING=true "$runner" --execute \
    --model test-model --baseline-variant "$baseline" --candidate-variant "$candidate" \
    --cases seeded-code-review-regressions --repeats 1 --output "$laundering_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -e '
      .reviewability.status == "ready"
      and ([.pairs[].candidate.findings[].review_summary] | sort) == ([
        "Discount audit logging should include a timestamp",
        "Mutation coverage metrics need a dashboard",
        "Negative-number formatting should use parentheses",
        "The assertion message should use title case"
      ] | sort)
      and all(.pairs[].baseline.findings[], .pairs[].candidate.findings[];
        (.review_summary | type == "string" and length >= 1 and length <= 240 and (test("[\\r\\n]") | not)))
    ' "$laundering_output/semantic-review-packet.json" >/dev/null; then
    laundering_summary_ok=true
fi
cp -R "$laundering_output" "$laundering_missing_output"
jq 'del(.pairs[0].candidate.findings[0].review_summary)' \
    "$laundering_missing_output/semantic-review-packet.json" >"$laundering_missing_packet"
mv "$laundering_missing_packet" "$laundering_missing_output/semantic-review-packet.json"
if ! "$semantic_finalizer" --results "$laundering_missing_output" --write-verdict-template "$fixture_root/missing-summary-template.json" >/dev/null 2>&1; then
    laundering_missing_blocked=true
fi
if "$semantic_finalizer" --results "$laundering_output" --write-verdict-template "$laundering_template" >/dev/null \
    && jq '
      .reviewer.kind = "human"
      | .reviewer.attestation = "reviewed_all_candidate_findings_against_synthetic_fixture"
      | .reviewed_at = "2026-07-12T12:00:00Z"
      | .pair_verdicts[].candidate_findings[].verdict = "supported"
      | .pair_verdicts[].candidate_findings[].reason_code = "supported_by_synthetic_fixture"
      | .pair_verdicts[0].candidate_findings[0].verdict = "false_positive"
      | .pair_verdicts[0].candidate_findings[0].reason_code = "not_supported_by_synthetic_fixture"
      | .pair_verdicts[].verdict = "rejected"
      | .overall_verdict = "rejected"
    ' "$laundering_template" >"$laundering_verdict" \
    && ! "$semantic_finalizer" --results "$laundering_output" --candidate-variant "$candidate" --verdict "$laundering_verdict" >/dev/null 2>&1 \
    && jq -e '
      .semantic_false_positive_review.status == "rejected"
      and (.failed_gates | index("semantic_review_not_approved") != null)
      and .behavioral_promotion_eligible == false
    ' "$laundering_output/promotion-decision.json" >/dev/null; then
    laundering_rejected=true
fi
if [[ "$laundering_summary_ok" == true && "$laundering_missing_blocked" == true && "$laundering_rejected" == true ]]; then
    pass
else
    fail "semantic laundering was hidden from human review or could proceed without explicit bounded evidence"
fi

test_start "synthetic review summaries reject C0 DEL and C1 controls before persistence and finalization"
control_chars_ok=true
for control_kind in escape tab; do
    control_output="$fixture_root/semantic-control-$control_kind-output"
    rm -f "$capture"/*
    if ! FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_SEMANTIC_CONTROL="$control_kind" "$runner" --execute \
        --model test-model --baseline-variant "$baseline" --candidate-variant "$candidate" \
        --cases seeded-code-review-regressions --repeats 1 --output "$control_output" \
        --codex-bin "$fake_codex" >/dev/null \
        || ! jq -e '
          .reviewability.status == "blocked"
          and (.reviewability.reason_codes | index("unsafe_finding_content") != null)
          and .pairs == []
        ' "$control_output/semantic-review-packet.json" >/dev/null \
        || grep -R -F 'control-marker' "$control_output" >/dev/null 2>&1; then
        control_chars_ok=false
        break
    fi
done
control_tampered_output="$fixture_root/semantic-control-tampered-output"
control_tampered_packet="$fixture_root/semantic-control-tampered-packet.json"
cp -R "$laundering_output" "$control_tampered_output"
jq '.pairs[0].candidate.findings[0].review_summary = "Discount\u001bcontrol"' \
    "$control_tampered_output/semantic-review-packet.json" >"$control_tampered_packet"
mv "$control_tampered_packet" "$control_tampered_output/semantic-review-packet.json"
if [[ "$control_chars_ok" != true ]] \
    || "$semantic_finalizer" --results "$control_tampered_output" \
        --write-verdict-template "$fixture_root/control-summary-template.json" >/dev/null 2>&1 \
    || ! grep -Fq '\\u0020-\\u002E' "$semantic_packet_schema" \
    || ! grep -Fq '\\u005D-\\u007E' "$semantic_packet_schema"; then
    fail "control characters entered a ready packet, survived finalization, or escaped the strict schema"
else
    pass
fi

test_start "synthetic review summaries reject paths and non-ASCII format characters before persistence"
unsafe_summary_ok=true
for unsafe_kind in private_var tmp unc bidi zero_width; do
    unsafe_summary_output="$fixture_root/semantic-unsafe-$unsafe_kind-output"
    rm -f "$capture"/*
    if ! FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_SEMANTIC_UNSAFE_KIND="$unsafe_kind" "$runner" --execute \
        --model test-model --baseline-variant "$baseline" --candidate-variant "$candidate" \
        --cases seeded-code-review-regressions --repeats 1 --output "$unsafe_summary_output" \
        --codex-bin "$fake_codex" >/dev/null \
        || ! jq -e '
          .reviewability.status == "blocked"
          and (.reviewability.reason_codes | index("unsafe_finding_content") != null)
          and .pairs == []
        ' "$unsafe_summary_output/semantic-review-packet.json" >/dev/null \
        || grep -R -E 'private-path-marker|unicode-format-marker|/private/var|/tmp|\\\\server' "$unsafe_summary_output" >/dev/null 2>&1; then
        unsafe_summary_ok=false
        break
    fi
done
if [[ "$unsafe_summary_ok" == true ]] \
    && grep -Fq '\\u0020-\\u002E' "$semantic_packet_schema" \
    && grep -Fq '\\u0030-\\u005B' "$semantic_packet_schema" \
    && grep -Fq '\\u005D-\\u007E' "$semantic_packet_schema"; then
    pass
else
    fail "absolute/UNC paths or non-ASCII format characters entered persisted semantic summaries"
fi

test_start "smoke success is distinct from fail-closed pilot promotion"
smoke_output="$fixture_root/smoke-output"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight,seeded-code-review-regressions \
    --repeats 1 \
    --output "$smoke_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -e '
      .complete_pairs == 2
      and .excluded_incomplete_pairs == 0
      and .smoke_passed == true
      and .pilot_coverage_complete == false
      and .behavioral_promotion_eligible == false
      and .semantic_false_positive_review_required == true
    ' "$smoke_output/comparison.json" >/dev/null; then
    pass
else
    fail "four-run smoke was conflated with production promotion eligibility"
fi

test_start "semantic review schemas and manifest enforce a synthetic closed-world packet"
if [[ -x "$semantic_finalizer" ]] \
    && jq -e '
      .semantic_review.case_category == "seeded_review"
      and .semantic_review.data_classification == "synthetic"
      and .semantic_review.max_findings_per_run == 8
      and .semantic_review.unclassified_finding_policy == "block"
      and .semantic_review.raw_response_retained == false
    ' "$candidate/manifest.json" >/dev/null \
    && jq -e '
      .additionalProperties == false
      and (.required | contains(["schema_version", "review_kind", "scope", "bindings", "reviewability", "pairs"]))
      and .properties.scope.properties.data_classification.const == "synthetic"
      and .properties.scope.properties.case_category.const == "seeded_review"
    ' "$semantic_packet_schema" >/dev/null \
    && jq -e '
      .additionalProperties == false
      and .properties.reviewer.properties.kind.const == "human"
      and (.properties | has("notes") | not)
    ' "$semantic_verdict_schema" >/dev/null \
    && jq -e '
      .additionalProperties == false
      and (.properties.behavioral_promotion_eligible.type == "boolean")
      and (.required | index("trusted_execution_profile_passed") != null)
      and (.properties.failed_gates.items.enum | index("untrusted_execution_profile") != null)
    ' "$promotion_decision_schema" >/dev/null; then
    pass
else
    fail "semantic review schemas, finalizer, or manifest closed-world policy is missing"
fi

test_start "semantic review documentation distinguishes whole-response deletion from bounded synthetic summaries"
if grep -Fq 'It never persists the whole model response.' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq 'ready synthetic-only semantic packet' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq '`review_summary`' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && ! grep -Fq 'It never persists the model-authored summary.' "$FRAMEWORK_DIR/docs/evals/README.md"; then
    pass
else
    fail "semantic review docs contradicted the bounded synthetic summary retention contract"
fi

test_start "semantic schemas declare fail-closed aggregate and eligibility invariants"
contradictory_verdict="$fixture_root/contradictory-verdict.json"
contradictory_decision="$fixture_root/contradictory-decision.json"
jq -n '{overall_verdict:"approved",pair_verdicts:[{verdict:"rejected"}]}' >"$contradictory_verdict"
jq -n '{behavioral_promotion_eligible:true,automatic_behavioral_gates_passed:false,trusted_execution_profile_passed:false,semantic_false_positive_review:{status:"rejected"},failed_gates:["pilot_coverage_or_automatic_gates"]}' >"$contradictory_decision"
if ! jq -e '(.overall_verdict != "approved") or all(.pair_verdicts[]; .verdict == "approved")' "$contradictory_verdict" >/dev/null \
    && ! jq -e '(.behavioral_promotion_eligible | not) or (.automatic_behavioral_gates_passed and .trusted_execution_profile_passed and .semantic_false_positive_review.status == "approved" and .failed_gates == [])' "$contradictory_decision" >/dev/null \
    && jq -e '
      ([.properties.pair_verdicts.items.allOf[].if.properties.verdict.const] | sort)
        == ["approved","rejected"]
      and ([.allOf[].if.properties.overall_verdict.const] | sort)
        == ["approved","rejected"]
    ' "$semantic_verdict_schema" >/dev/null \
    && jq -e '
      ([.allOf[].if.properties.behavioral_promotion_eligible.const | select(type == "boolean")] | unique | sort)
        == [false,true]
      and any(.allOf[]; .if.properties.automatic_behavioral_gates_passed.const == false)
      and any(.allOf[]; .if.properties.trusted_execution_profile_passed.const == false)
      and any(.allOf[]; .if.properties.semantic_false_positive_review.properties.status.const == "rejected")
    ' "$promotion_decision_schema" >/dev/null; then
    pass
else
    fail "published schemas accept contradictory human verdict or promotion states"
fi

test_start "seeded review emits a safe hash-bound packet without retaining model prose"
semantic_output="$fixture_root/semantic-output"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight,seeded-code-review-regressions \
    --repeats 1 \
    --output "$semantic_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && packet_pair_hash="$(jq -cS '.pairs[0] | del(.pair_sha256)' "$semantic_output/semantic-review-packet.json" | test_sha256_stream)" \
    && jq -e --arg pair_hash "$packet_pair_hash" '
      .review_kind == "workflow_kernel_semantic_false_positive"
      and .scope.data_classification == "synthetic"
      and .scope.case_category == "seeded_review"
      and .scope.case_ids == ["seeded-code-review-regressions"]
      and .scope.raw_artifacts_retained == false
      and .reviewability == {status:"ready",reason_codes:[]}
      and (.bindings.run_plan_sha256 | test("^[0-9a-f]{64}$"))
      and (.bindings.fixture_sha256 | test("^[0-9a-f]{64}$"))
      and (.bindings.candidate_manifest_sha256 | test("^[0-9a-f]{64}$"))
      and (.bindings.baseline_instruction_sha256 | test("^[0-9a-f]{64}$"))
      and (.bindings.candidate_instruction_sha256 | test("^[0-9a-f]{64}$"))
      and (.pairs | length == 1)
      and .pairs[0].pair_sha256 == $pair_hash
      and (.pairs[0].seed_workspace_sha256 | test("^[0-9a-f]{64}$"))
      and ([.pairs[0].baseline.findings[].claim_code] | sort) == ([
        "missing_preferred_discount", "mutates_input_order",
        "negative_quantity_not_rejected", "test_has_no_behavioral_assertion"
      ] | sort)
      and ([.pairs[0].candidate.findings[].claim_code] | sort) == ([
        "missing_preferred_discount", "mutates_input_order",
        "negative_quantity_not_rejected", "test_has_no_behavioral_assertion"
      ] | sort)
      and all(.pairs[0].baseline.findings[], .pairs[0].candidate.findings[];
        (.source == "src/order.js" or .source == "tests/order.test.js")
        and (.finding_id | test("^(baseline|candidate)-[0-9]{2}$"))
        and (.normalized_claim | type == "string" and length > 0))
    ' "$semantic_output/semantic-review-packet.json" >/dev/null \
    && jq -s -e 'all(.[].provenance.seed_workspace_sha256; test("^[0-9a-f]{64}$"))' "$semantic_output/traces/"*.json >/dev/null \
    && ! grep -R -E '/Users/|sk-private|api[_-]?key|password|secret' "$semantic_output" >/dev/null 2>&1; then
    pass
else
    fail "safe semantic packet was absent, unbound, unnormalized, or retained raw/private content"
fi

test_start "semantic review preserves reconstructable bounded synthetic fixture evidence"
synthetic_fixture="$FRAMEWORK_DIR/docs/evals/fixtures/seeded-code-review-regressions"
synthetic_fixture_hash="$(test_sha256_directory "$synthetic_fixture" 2>/dev/null || true)"
fixture_drift_results="$fixture_root/fixture-drift-results"
fixture_drift_packet="$fixture_root/fixture-drift-packet.json"
fixture_drift_template="$fixture_root/fixture-drift-template.json"
fixture_drift_verdict="$fixture_root/fixture-drift-verdict.json"
fixture_evidence_ok=false
fixture_drift_blocked=false
if [[ -f "$synthetic_fixture/REQUIREMENTS.md" \
      && -f "$synthetic_fixture/src/order.js" \
      && -f "$synthetic_fixture/tests/order.test.js" ]] \
    && jq -e --arg hash "$synthetic_fixture_hash" '
      .scope.synthetic_fixture_ref == "docs/evals/fixtures/seeded-code-review-regressions"
      and .scope.synthetic_fixture_sha256 == $hash
      and all(.pairs[]; .seed_workspace_sha256 == $hash)
    ' "$semantic_output/semantic-review-packet.json" >/dev/null; then
    fixture_evidence_ok=true
fi
cp -R "$semantic_output" "$fixture_drift_results"
jq '.scope.synthetic_fixture_sha256 = ("0" * 64)' \
    "$fixture_drift_results/semantic-review-packet.json" >"$fixture_drift_packet"
mv "$fixture_drift_packet" "$fixture_drift_results/semantic-review-packet.json"
if "$semantic_finalizer" --results "$fixture_drift_results" --write-verdict-template "$fixture_drift_template" >/dev/null 2>&1 \
    && jq '
      .reviewer.kind = "human"
      | .reviewer.attestation = "reviewed_all_candidate_findings_against_synthetic_fixture"
      | .reviewed_at = "2026-07-12T12:00:00Z"
      | .pair_verdicts[].candidate_findings[].verdict = "supported"
      | .pair_verdicts[].candidate_findings[].reason_code = "supported_by_synthetic_fixture"
      | .pair_verdicts[].verdict = "approved"
      | .overall_verdict = "approved"
    ' "$fixture_drift_template" >"$fixture_drift_verdict" \
    && ! "$semantic_finalizer" --results "$fixture_drift_results" --candidate-variant "$candidate" --verdict "$fixture_drift_verdict" >/dev/null 2>&1 \
    && [[ ! -e "$fixture_drift_results/semantic-review-verdict.json" ]] \
    && [[ ! -e "$fixture_drift_results/promotion-decision.json" ]]; then
    fixture_drift_blocked=true
fi
if [[ "$fixture_evidence_ok" == true && "$fixture_drift_blocked" == true ]]; then
    pass
else
    fail "synthetic review evidence was not reconstructable or fixture drift was accepted"
fi

test_start "unsafe or unclassified semantic findings block review without copying offending text"
unclassified_output="$fixture_root/unclassified-semantic-output"
unsafe_output="$fixture_root/unsafe-semantic-output"
rm -f "$capture"/*
unclassified_ok=false
unsafe_ok=false
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_UNCLASSIFIED_SEMANTIC=true "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases seeded-code-review-regressions \
    --repeats 1 \
    --output "$unclassified_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -e '
      .reviewability.status == "blocked"
      and (.reviewability.reason_codes | index("unclassified_finding") != null)
      and .pairs == []
      and (.diagnostics | length == 2)
      and ([.diagnostics[].variant] | sort) == ["baseline", "candidate"]
      and all(.diagnostics[];
        (.diagnostic_sha256 | test("^[0-9a-f]{64}$"))
        and (.case_sha256 | test("^[0-9a-f]{64}$"))
        and (.grader_sha256 | test("^[0-9a-f]{64}$"))
        and (.seed_workspace_sha256 | test("^[0-9a-f]{64}$"))
        and (.trace_sha256 | test("^[0-9a-f]{64}$"))
        and all(.classified_claim_codes[]; test("^[a-z][a-z0-9_]+$"))
      )
      and (.diagnostics[] | select(.variant == "baseline")
        | .status == "ready"
        and .reason_code == "paired_variant_blocked"
        and (.classified_claim_codes | length) == 4
        and .finding_failures == [])
      and (.diagnostics[] | select(.variant == "candidate")
        | .status == "blocked"
        and .reason_code == "unclassified_finding"
        and (.classified_claim_codes | length) == 4
        and .finding_failures == [{finding_id:"candidate-05",reason_code:"no_claim_rule_match"}])
    ' "$unclassified_output/semantic-review-packet.json" >/dev/null \
    && ! grep -R -F 'proprietary-throughput-claim' "$unclassified_output" >/dev/null 2>&1; then
    unclassified_ok=true
fi
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_UNSAFE_SEMANTIC=true "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases seeded-code-review-regressions \
    --repeats 1 \
    --output "$unsafe_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -e '
      .reviewability.status == "blocked"
      and (.reviewability.reason_codes | index("unsafe_finding_content") != null)
      and .pairs == []
    ' "$unsafe_output/semantic-review-packet.json" >/dev/null \
    && ! grep -R -E 'sk-private-fixture-value|/Users/company|private/source' "$unsafe_output" >/dev/null 2>&1; then
    unsafe_ok=true
fi
if [[ "$unclassified_ok" == "true" && "$unsafe_ok" == "true" ]]; then
    pass
else
    fail "unsafe or unclassified semantic content remained reviewable or leaked into persisted output"
fi

test_start "pending human review timestamp cannot finalize"
pending_timestamp_template="$fixture_root/pending-timestamp-template.json"
pending_timestamp_verdict="$fixture_root/pending-timestamp-verdict.json"
impossible_timestamp_verdict="$fixture_root/impossible-timestamp-verdict.json"
if "$semantic_finalizer" --results "$semantic_output" --write-verdict-template "$pending_timestamp_template" >/dev/null \
    && jq -e '.reviewed_at == "pending"' "$pending_timestamp_template" >/dev/null \
    && jq '
      .reviewer.kind = "human"
      | .reviewer.attestation = "reviewed_all_candidate_findings_against_synthetic_fixture"
      | .pair_verdicts[].candidate_findings[].verdict = "supported"
      | .pair_verdicts[].candidate_findings[].reason_code = "supported_by_synthetic_fixture"
      | .pair_verdicts[].verdict = "approved"
      | .overall_verdict = "approved"
    ' "$pending_timestamp_template" >"$pending_timestamp_verdict" \
    && ! "$semantic_finalizer" --results "$semantic_output" --candidate-variant "$candidate" --verdict "$pending_timestamp_verdict" >/dev/null 2>&1 \
    && [[ ! -e "$semantic_output/semantic-review-verdict.json" ]] \
    && [[ ! -e "$semantic_output/promotion-decision.json" ]] \
    && jq '
      .reviewer.kind = "human"
      | .reviewer.attestation = "reviewed_all_candidate_findings_against_synthetic_fixture"
      | .reviewed_at = "2026-02-30T25:61:61Z"
      | .pair_verdicts[].candidate_findings[].verdict = "supported"
      | .pair_verdicts[].candidate_findings[].reason_code = "supported_by_synthetic_fixture"
      | .pair_verdicts[].verdict = "approved"
      | .overall_verdict = "approved"
    ' "$pending_timestamp_template" >"$impossible_timestamp_verdict" \
    && ! "$semantic_finalizer" --results "$semantic_output" --candidate-variant "$candidate" --verdict "$impossible_timestamp_verdict" >/dev/null 2>&1 \
    && [[ ! -e "$semantic_output/semantic-review-verdict.json" ]] \
    && [[ ! -e "$semantic_output/promotion-decision.json" ]]; then
    pass
else
    fail "pending reviewed_at value was accepted or the template pre-attested a review time"
fi

test_start "human semantic verdict is exact, hash-bound, and cannot promote smoke coverage"
smoke_verdict_template="$fixture_root/smoke-verdict-template.json"
smoke_unattested_verdict="$fixture_root/smoke-unattested-verdict.json"
smoke_verdict="$fixture_root/smoke-verdict.json"
if [[ -x "$semantic_finalizer" ]] \
    && "$semantic_finalizer" --results "$semantic_output" --write-verdict-template "$smoke_verdict_template" >/dev/null \
    && jq '
      .pair_verdicts[].candidate_findings[].verdict = "supported"
      | .pair_verdicts[].candidate_findings[].reason_code = "supported_by_synthetic_fixture"
      | .pair_verdicts[].verdict = "approved"
      | .overall_verdict = "approved"
    ' "$smoke_verdict_template" >"$smoke_unattested_verdict" \
    && jq -e '.reviewer == {kind:"pending",attestation:"pending"}' "$smoke_verdict_template" >/dev/null \
    && ! "$semantic_finalizer" --results "$semantic_output" --candidate-variant "$candidate" --verdict "$smoke_unattested_verdict" >/dev/null 2>&1 \
    && [[ ! -e "$semantic_output/semantic-review-verdict.json" ]] \
    && [[ ! -e "$semantic_output/promotion-decision.json" ]] \
    && jq '
      .reviewer.kind = "human"
      | .reviewer.attestation = "reviewed_all_candidate_findings_against_synthetic_fixture"
      | .reviewed_at = "2026-07-12T12:00:00Z"
    ' "$smoke_unattested_verdict" >"$smoke_verdict" \
    && ! "$semantic_finalizer" --results "$semantic_output" --candidate-variant "$candidate" --verdict "$smoke_verdict" >/dev/null 2>&1 \
    && jq -e '
      .automatic_behavioral_gates_passed == false
      and .semantic_false_positive_review.status == "approved"
      and (.failed_gates | index("pilot_coverage_or_automatic_gates") != null)
      and .behavioral_promotion_eligible == false
    ' "$semantic_output/promotion-decision.json" >/dev/null; then
    pass
else
    fail "approved human review bypassed exact pilot coverage or lacked hash-bound verdict artifacts"
fi

test_start "comparison tampering cannot turn smoke evidence into pilot eligibility"
tampered_results="$fixture_root/tampered-comparison-results"
tampered_comparison="$fixture_root/tampered-comparison.json"
cp -R "$semantic_output" "$tampered_results"
rm -f "$tampered_results/semantic-review-verdict.json" "$tampered_results/promotion-decision.json"
jq '.automatic_behavioral_gates_passed = true' \
    "$tampered_results/comparison.json" >"$tampered_comparison"
mv "$tampered_comparison" "$tampered_results/comparison.json"
if ! "$semantic_finalizer" --results "$tampered_results" --candidate-variant "$candidate" --verdict "$smoke_verdict" >/dev/null 2>&1 \
    && [[ ! -e "$tampered_results/semantic-review-verdict.json" ]] \
    && [[ ! -e "$tampered_results/promotion-decision.json" ]]; then
    pass
else
    fail "mutable comparison data bypassed exact pilot coverage"
fi

test_start "rebound smoke artifacts still cannot satisfy exact pilot identity"
rebound_results="$fixture_root/rebound-smoke-results"
rebound_comparison="$fixture_root/rebound-comparison.json"
rebound_packet="$fixture_root/rebound-packet.json"
rebound_template="$fixture_root/rebound-template.json"
rebound_verdict="$fixture_root/rebound-verdict.json"
cp -R "$semantic_output" "$rebound_results"
rm -f "$rebound_results/semantic-review-verdict.json" "$rebound_results/promotion-decision.json"
jq '.automatic_behavioral_gates_passed = true | .pilot_coverage_complete = true' \
    "$rebound_results/comparison.json" >"$rebound_comparison"
mv "$rebound_comparison" "$rebound_results/comparison.json"
rebound_comparison_sha="$(test_sha256_stream <"$rebound_results/comparison.json")"
jq --arg sha "$rebound_comparison_sha" '.bindings.comparison_sha256 = $sha' \
    "$rebound_results/semantic-review-packet.json" >"$rebound_packet"
mv "$rebound_packet" "$rebound_results/semantic-review-packet.json"
if "$semantic_finalizer" --results "$rebound_results" --write-verdict-template "$rebound_template" >/dev/null \
    && jq '
      .reviewer.kind = "human"
      | .reviewer.attestation = "reviewed_all_candidate_findings_against_synthetic_fixture"
      | .reviewed_at = "2026-07-12T12:00:00Z"
      | .pair_verdicts[].candidate_findings[].verdict = "supported"
      | .pair_verdicts[].candidate_findings[].reason_code = "supported_by_synthetic_fixture"
      | .pair_verdicts[].verdict = "approved"
      | .overall_verdict = "approved"
    ' "$rebound_template" >"$rebound_verdict" \
    && ! "$semantic_finalizer" --results "$rebound_results" --candidate-variant "$candidate" --verdict "$rebound_verdict" >/dev/null 2>&1 \
    && [[ ! -e "$rebound_results/semantic-review-verdict.json" ]] \
    && [[ ! -e "$rebound_results/promotion-decision.json" ]]; then
    pass
else
    fail "hash-consistent smoke artifacts bypassed exact pilot pair identity validation"
fi

test_start "fake complete pilot remains permanently ineligible despite exact human approval"
pilot_output="$fixture_root/pilot-output"
pilot_template="$fixture_root/pilot-verdict-template.json"
pilot_verdict="$fixture_root/pilot-verdict.json"
pilot_cases="$(jq -r '.pilot_cases | join(",")' "$candidate/manifest.json")"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases "$pilot_cases" \
    --repeats 3 \
    --output "$pilot_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && "$semantic_finalizer" --results "$pilot_output" --write-verdict-template "$pilot_template" >/dev/null \
    && jq '
      .reviewer.kind = "human"
      | .reviewer.attestation = "reviewed_all_candidate_findings_against_synthetic_fixture"
      | .reviewed_at = "2026-07-12T12:00:00Z"
      | .pair_verdicts[].candidate_findings[].verdict = "supported"
      | .pair_verdicts[].candidate_findings[].reason_code = "supported_by_synthetic_fixture"
      | .pair_verdicts[].verdict = "approved"
      | .overall_verdict = "approved"
    ' "$pilot_template" >"$pilot_verdict" \
    && ! "$semantic_finalizer" --results "$pilot_output" --candidate-variant "$candidate" --verdict "$pilot_verdict" >/dev/null 2>&1 \
    && jq -e '
      .automatic_behavioral_gates_passed == true
      and .trusted_execution_profile_passed == false
      and .semantic_false_positive_review.status == "approved"
      and .semantic_false_positive_review.reviewed_pairs == 3
      and .semantic_false_positive_review.reviewed_candidate_findings == 12
      and .failed_gates == ["untrusted_execution_profile"]
      and .behavioral_promotion_eligible == false
    ' "$pilot_output/promotion-decision.json" >/dev/null \
    && jq -e '
      .reviewer.kind == "human"
      and .reviewer.attestation == "reviewed_all_candidate_findings_against_synthetic_fixture"
      and .overall_verdict == "approved"
      and (.pair_verdicts | length == 3)
      and all(.pair_verdicts[].candidate_findings[]; .verdict == "supported")
    ' "$pilot_output/semantic-review-verdict.json" >/dev/null \
    && jq -e --slurpfile plan "$pilot_output/run-plan.json" \
        --slurpfile packet "$pilot_output/semantic-review-packet.json" \
        --slurpfile verdict "$pilot_output/semantic-review-verdict.json" '
      .bindings.context_budget_evidence_sha256 == $plan[0].context_budget_evidence_sha256
      and .bindings.context_budget_evidence_sha256 == $packet[0].bindings.context_budget_evidence_sha256
      and .bindings.context_budget_evidence_sha256 == $verdict[0].bindings.context_budget_evidence_sha256
    ' "$pilot_output/promotion-decision.json" >/dev/null \
    && ! find "$pilot_output" -type f \( -name '*.jsonl' -o -name '*.txt' -o -name '*.md' \) | grep -q .; then
    pass
else
    fail "fake or overridden Codex execution became promotion-eligible"
fi

test_start "final artifacts use atomic writes and safely recover from either one-artifact interruption"
semantic_only_results="$fixture_root/semantic-only-retry"
decision_only_results="$fixture_root/decision-only-retry"
cp -R "$pilot_output" "$semantic_only_results"
cp -R "$pilot_output" "$decision_only_results"
rm -f "$semantic_only_results/promotion-decision.json"
printf 'partial\n' >"$semantic_only_results/.promotion-decision.json.tmp.interrupted"
rm -f "$decision_only_results/semantic-review-verdict.json"
if grep -Fq 'atomic_write_json' "$runner" \
    && grep -Fq 'atomic_write_json' "$semantic_finalizer" \
    && ! "$semantic_finalizer" --results "$semantic_only_results" --baseline-variant "$baseline" \
        --candidate-variant "$candidate" --verdict "$pilot_verdict" >/dev/null 2>&1 \
    && ! "$semantic_finalizer" --results "$decision_only_results" --baseline-variant "$baseline" \
        --candidate-variant "$candidate" --verdict "$pilot_verdict" >/dev/null 2>&1 \
    && jq -e '.behavioral_promotion_eligible == false and .failed_gates == ["untrusted_execution_profile"]' \
        "$semantic_only_results/promotion-decision.json" "$decision_only_results/promotion-decision.json" >/dev/null \
    && jq -e '.overall_verdict == "approved"' \
        "$semantic_only_results/semantic-review-verdict.json" "$decision_only_results/semantic-review-verdict.json" >/dev/null; then
    pass
else
    fail "atomic finalization could not recover safely from a one-artifact interruption"
fi

test_start "finalizer rejects baseline candidate and context-evidence drift before writing review artifacts"
baseline_drift="$fixture_root/baseline-drift"
candidate_drift="$fixture_root/candidate-drift"
context_tamper_results="$fixture_root/context-tamper-results"
context_tamper_plan="$fixture_root/context-tamper-plan.json"
context_tamper_packet="$fixture_root/context-tamper-packet.json"
cp -R "$baseline" "$baseline_drift"
cp -R "$candidate" "$candidate_drift"
printf '\nDrift control.\n' >>"$baseline_drift/SKILL.md"
printf '\nDrift control.\n' >>"$candidate_drift/SKILL.md"
cp -R "$pilot_output" "$context_tamper_results"
rm -f "$context_tamper_results/semantic-review-verdict.json" "$context_tamper_results/promotion-decision.json"
jq '.context_budget_evidence.reporter_sha256 = ("f" * 64)' \
    "$context_tamper_results/run-plan.json" >"$context_tamper_plan"
context_tamper_hash="$(jq -cS '.context_budget_evidence' "$context_tamper_plan" | test_sha256_stream)"
jq --arg hash "$context_tamper_hash" '.context_budget_evidence_sha256 = $hash' \
    "$context_tamper_plan" >"$context_tamper_results/run-plan.json"
context_tamper_plan_hash="$(test_sha256_stream <"$context_tamper_results/run-plan.json")"
jq --arg plan_hash "$context_tamper_plan_hash" --arg evidence_hash "$context_tamper_hash" '
  .bindings.run_plan_sha256 = $plan_hash
  | .bindings.context_budget_evidence_sha256 = $evidence_hash
' "$context_tamper_results/semantic-review-packet.json" >"$context_tamper_packet"
mv "$context_tamper_packet" "$context_tamper_results/semantic-review-packet.json"
if ! "$semantic_finalizer" --results "$pilot_output" --baseline-variant "$baseline_drift" \
        --candidate-variant "$candidate" --write-verdict-template "$fixture_root/baseline-drift-template.json" >/dev/null 2>&1 \
    && ! "$semantic_finalizer" --results "$pilot_output" --baseline-variant "$baseline" \
        --candidate-variant "$candidate_drift" --write-verdict-template "$fixture_root/candidate-drift-template.json" >/dev/null 2>&1 \
    && ! "$semantic_finalizer" --results "$context_tamper_results" --baseline-variant "$baseline" \
        --candidate-variant "$candidate" --write-verdict-template "$fixture_root/context-tamper-template.json" >/dev/null 2>&1 \
    && [[ ! -e "$fixture_root/baseline-drift-template.json" \
        && ! -e "$fixture_root/candidate-drift-template.json" \
        && ! -e "$fixture_root/context-tamper-template.json" ]]; then
    pass
else
    fail "finalizer accepted variant, reporter, or embedded context-evidence drift"
fi

test_start "fully rebound failed pilot comparison cannot fabricate automatic eligibility"
failed_pilot_output="$fixture_root/failed-pilot-output"
failed_pilot_comparison="$fixture_root/failed-pilot-comparison.json"
failed_pilot_packet="$fixture_root/failed-pilot-packet.json"
failed_pilot_template="$fixture_root/failed-pilot-template.json"
failed_pilot_verdict="$fixture_root/failed-pilot-verdict.json"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_CANDIDATE_SMALL_FAILURE=true "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases "$pilot_cases" \
    --repeats 3 \
    --output "$failed_pilot_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -e '
      .pilot_coverage_complete == true
      and .promotion_gate_results.candidate_must_pass_failed_runs > 0
      and .automatic_behavioral_gates_passed == false
    ' "$failed_pilot_output/comparison.json" >/dev/null \
    && jq '.automatic_behavioral_gates_passed = true' \
        "$failed_pilot_output/comparison.json" >"$failed_pilot_comparison" \
    && mv "$failed_pilot_comparison" "$failed_pilot_output/comparison.json" \
    && rebound_failed_comparison_sha="$(test_sha256_stream <"$failed_pilot_output/comparison.json")" \
    && jq --arg sha "$rebound_failed_comparison_sha" '.bindings.comparison_sha256 = $sha' \
        "$failed_pilot_output/semantic-review-packet.json" >"$failed_pilot_packet" \
    && mv "$failed_pilot_packet" "$failed_pilot_output/semantic-review-packet.json" \
    && "$semantic_finalizer" --results "$failed_pilot_output" --write-verdict-template "$failed_pilot_template" >/dev/null \
    && jq '
      .reviewer.kind = "human"
      | .reviewer.attestation = "reviewed_all_candidate_findings_against_synthetic_fixture"
      | .reviewed_at = "2026-07-12T12:00:00Z"
      | .pair_verdicts[].candidate_findings[].verdict = "supported"
      | .pair_verdicts[].candidate_findings[].reason_code = "supported_by_synthetic_fixture"
      | .pair_verdicts[].verdict = "approved"
      | .overall_verdict = "approved"
    ' "$failed_pilot_template" >"$failed_pilot_verdict" \
    && ! "$semantic_finalizer" --results "$failed_pilot_output" --candidate-variant "$candidate" --verdict "$failed_pilot_verdict" >/dev/null 2>&1 \
    && [[ ! -e "$failed_pilot_output/semantic-review-verdict.json" ]] \
    && [[ ! -e "$failed_pilot_output/promotion-decision.json" ]]; then
    pass
else
    fail "a fully rebound failed pilot comparison fabricated automatic eligibility"
fi

test_start "stale, non-human, false-positive, or incomplete verdicts fail closed"
invalid_results="$fixture_root/invalid-verdict-results"
cp -R "$pilot_output" "$invalid_results"
rm -f "$invalid_results/promotion-decision.json" "$invalid_results/semantic-review-verdict.json"
invalid_verdict="$fixture_root/invalid-verdict.json"
if [[ -x "$semantic_finalizer" && -f "$pilot_verdict" ]] \
    && jq '
      .reviewer.kind = "agent"
      | .pair_verdicts[0].candidate_findings[0].verdict = "false_positive"
      | .pair_verdicts[0].candidate_findings[0].reason_code = "not_supported_by_synthetic_fixture"
      | .pair_verdicts[0].verdict = "rejected"
      | .overall_verdict = "rejected"
    ' "$pilot_verdict" >"$invalid_verdict" \
    && ! "$semantic_finalizer" --results "$invalid_results" --candidate-variant "$candidate" --verdict "$invalid_verdict" >/dev/null 2>&1 \
    && [[ ! -e "$invalid_results/semantic-review-verdict.json" ]] \
    && [[ ! -e "$invalid_results/promotion-decision.json" ]]; then
    pass
else
    fail "invalid reviewer identity or rejected finding produced a persisted eligible decision"
fi

test_start "candidate failures block automatic gates even when baseline also fails"
mutual_failure_output="$fixture_root/mutual-failure-output"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_BAD_RESPONSE=true "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight,seeded-code-review-regressions \
    --repeats 1 \
    --output "$mutual_failure_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -e '
      .promotion_gate_results.candidate_must_pass_failed_runs > 0
      and .smoke_passed == false
      and .automatic_behavioral_gates_passed == false
      and .behavioral_promotion_eligible == false
    ' "$mutual_failure_output/comparison.json" >/dev/null; then
    pass
else
    fail "mutually failing required cases could still satisfy automatic promotion gates"
fi

test_start "extra unlisted cases invalidate exact smoke coverage"
extra_case_output="$fixture_root/extra-case-output"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight,seeded-code-review-regressions,ordinary-medium-bounded-executor \
    --repeats 1 \
    --output "$extra_case_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -e '
      .complete_pairs == 3
      and .smoke_passed == false
      and .pilot_coverage_complete == false
      and .behavioral_promotion_eligible == false
    ' "$extra_case_output/comparison.json" >/dev/null; then
    pass
else
    fail "extra cases were accepted as the exact manifest smoke profile"
fi

test_start "workspace verifier fails unexpected edits and review-only mutations"
scope_output="$fixture_root/scope-output"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_SCOPE_DEVIATION=true "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases seeded-code-review-regressions \
    --repeats 1 \
    --output "$scope_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e 'all(.[];
      .metrics.scope_deviations == 1
      and .metrics.verifier_exit_code == 1
      and .metrics.acceptance_passed == false
      and .execution.verifier.workspace_status == "failed"
    )' "$scope_output/traces/"*.json >/dev/null; then
    pass
else
    fail "unexpected or review-only edits were reported as zero scope deviations"
fi

test_start "unknown JSONL event shapes become bounded adapter_unavailable results and incomplete pairs"
unknown_output="$fixture_root/unknown-output"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_UNKNOWN_CANDIDATE=true "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight \
    --repeats 1 \
    --output "$unknown_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -e '
        .status == "adapter_unavailable"
        and .error.code == "unknown_event_shape"
        and (has("metrics") | not)
    ' "$unknown_output/traces/"*candidate.json >/dev/null \
    && jq -e '
        .complete_pairs == 0
        and .excluded_incomplete_pairs == 1
        and (.incomplete_pairs | length) == 1
        and .incomplete_pairs[0].baseline_status == "completed"
        and .incomplete_pairs[0].candidate_status == "adapter_unavailable"
        and (.variants.baseline.completed_runs == 0)
        and (.variants.candidate.completed_runs == 0)
    ' "$unknown_output/comparison.json" >/dev/null; then
    pass
else
    fail "unknown events were converted to zero metrics or an incomplete pair entered comparison aggregates"
fi

test_start "missing Codex binaries produce redacted unavailable pairs instead of aborting the report"
missing_codex_output="$fixture_root/missing-codex-output"
if "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight \
    --repeats 1 \
    --output "$missing_codex_output" \
    --codex-bin "$fixture_root/codex-does-not-exist" >/dev/null 2>&1 \
    && [[ "$(find "$missing_codex_output/traces" -name '*.json' | wc -l | tr -d ' ')" -eq 2 ]] \
    && jq -s -e 'all(.[]; .status == "adapter_unavailable" and .error.code == "codex_not_found" and (has("metrics") | not))' \
        "$missing_codex_output/traces/"*.json >/dev/null \
    && jq -e '.complete_pairs == 0 and .excluded_incomplete_pairs == 1' "$missing_codex_output/comparison.json" >/dev/null; then
    pass
else
    fail "missing Codex executable aborted without a bounded paired diagnostic"
fi

test_start "nonzero Codex exits retain only a bounded actionable failure class"
classified_failure_output="$fixture_root/classified-failure-output"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" \
    FAKE_CODEX_FAILURE_MESSAGE='Model gpt-5.6 is not available for this account' \
    "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight \
    --repeats 1 \
    --output "$classified_failure_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e 'all(.[];
      .status == "adapter_unavailable"
      and .error.code == "model_unavailable"
      and .error.message == "Requested model is unavailable or inaccessible."
      and .execution.exit_code == 1
    )' "$classified_failure_output/traces/"*.json >/dev/null \
    && ! find "$classified_failure_output" -type f \( -name '*.txt' -o -name '*.jsonl' \) | grep -q .; then
    pass
else
    fail "nonzero exits remained opaque or leaked raw stderr"
fi

test_start "structured Codex failures are classified before stderr without retaining provider text"
structured_failure_output="$fixture_root/structured-failure-output"
structured_secret_marker='sk-private-structured-marker'
structured_path_marker='/Users/company/private/structured-source.js'
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" \
    FAKE_CODEX_FAILURE_EVENT_MESSAGE="Model gpt-5.6 is not available; $structured_secret_marker at $structured_path_marker request-id-private" \
    FAKE_CODEX_FAILURE_STDERR='unrelated adapter warning' \
    "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight \
    --repeats 1 \
    --output "$structured_failure_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e 'all(.[];
      .status == "adapter_unavailable"
      and .error.code == "model_unavailable"
      and .error.message == "Requested model is unavailable or inaccessible."
    )' "$structured_failure_output/traces/"*.json >/dev/null \
    && ! rg -l -F "$structured_secret_marker" "$structured_failure_output" >/dev/null \
    && ! rg -l -F "$structured_path_marker" "$structured_failure_output" >/dev/null \
    && ! find "$structured_failure_output" -type f \( -name '*.txt' -o -name '*.jsonl' \) | grep -q .; then
    pass
else
    fail "structured failure classification lost precedence or retained provider text"
fi

test_start "unknown structured failures use one bounded generic code"
generic_structured_output="$fixture_root/generic-structured-output"
generic_structured_marker='proprietary-provider-detail-private'
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" \
    FAKE_CODEX_FAILURE_EVENT_TYPE='turn.failed' \
    FAKE_CODEX_FAILURE_EVENT_MESSAGE="$generic_structured_marker" \
    "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight \
    --repeats 1 \
    --output "$generic_structured_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e 'all(.[];
      .status == "adapter_unavailable"
      and .error.code == "codex_reported_failure"
      and .error.message == "Codex reported a structured execution failure."
    )' "$generic_structured_output/traces/"*.json >/dev/null \
    && ! rg -l -F "$generic_structured_marker" "$generic_structured_output" >/dev/null; then
    pass
else
    fail "unknown structured provider text was exposed or misclassified"
fi

test_start "ordinary response events cannot influence failure classification"
response_event_failure_output="$fixture_root/response-event-failure-output"
response_event_marker='authentication failed private response marker'
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" \
    FAKE_CODEX_ITEM_FAILURE_MESSAGE="$response_event_marker" \
    FAKE_CODEX_FAILURE_STDERR='unclassified process failure' \
    "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight \
    --repeats 1 \
    --output "$response_event_failure_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e 'all(.[];
      .status == "adapter_unavailable"
      and .error.code == "codex_exit_nonzero"
      and .error.message == "Codex exited non-zero without a recognized structured failure class."
    )' "$response_event_failure_output/traces/"*.json >/dev/null \
    && ! rg -l -F "$response_event_marker" "$response_event_failure_output" >/dev/null; then
    pass
else
    fail "ordinary response content influenced bounded failure classification"
fi

test_start "local nested-sandbox startup restrictions use a bounded diagnostic"
local_restriction_output="$fixture_root/local-restriction-output"
local_restriction_marker='/Users/private/local-restriction-marker'
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" \
    FAKE_CODEX_FAILURE_MESSAGE="could not create PATH aliases: Operation not permitted $local_restriction_marker" \
    "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight \
    --repeats 1 \
    --output "$local_restriction_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e 'all(.[];
      .status == "adapter_unavailable"
      and .error.code == "local_execution_restricted"
      and .error.message == "Local execution restrictions prevented Codex startup."
    )' "$local_restriction_output/traces/"*.json >/dev/null \
    && ! rg -l -F "$local_restriction_marker" "$local_restriction_output" >/dev/null; then
    pass
else
    fail "local execution restrictions remained opaque or leaked local paths"
fi

test_start "oversized failure streams are bounded and cannot classify later response text"
oversized_failure_output="$fixture_root/oversized-failure-output"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_CODEX_OVERSIZED_FAILURE_STREAM=true \
    "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight \
    --repeats 1 \
    --output "$oversized_failure_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e 'all(.[];
      .status == "adapter_unavailable"
      and .error.code == "codex_exit_nonzero"
    )' "$oversized_failure_output/traces/"*.json >/dev/null \
    && ! find "$oversized_failure_output" -type f \( -name '*.txt' -o -name '*.jsonl' \) | grep -q .; then
    pass
else
    fail "failure classification exceeded its byte cap or inspected events beyond it"
fi

test_start "deeply nested failure JSON cannot strand a paid-call attempt in flight"
deep_failure_output="$fixture_root/deep-failure-output"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_CODEX_DEEP_FAILURE_STREAM=true \
    "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight \
    --repeats 1 \
    --output "$deep_failure_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -s -e 'all(.[];
      .status == "adapter_unavailable"
      and .error.code == "codex_exit_nonzero"
    )' "$deep_failure_output/traces/"*.json >/dev/null \
    && jq -s -e 'all(.[]; .state == "completed" and (.attempt_started_at | length) == 1)' \
        "$deep_failure_output/run-attempts/"*.json >/dev/null; then
    pass
else
    fail "deeply nested failure JSON aborted classification or stranded in-flight state"
fi

test_start "unsupported JSONL model fields cannot split or relabel paired aggregates"
model_mismatch_output="$fixture_root/model-mismatch-output"
rm -f "$capture"/*
if FAKE_CODEX_CAPTURE_DIR="$capture" FAKE_DIFFERENT_MODEL_CANDIDATE=true "$runner" --execute \
    --model test-model \
    --baseline-variant "$baseline" \
    --candidate-variant "$candidate" \
    --cases small-fix-stays-lightweight \
    --repeats 1 \
    --output "$model_mismatch_output" \
    --codex-bin "$fake_codex" >/dev/null \
    && jq -e '
      .complete_pairs == 1
      and .excluded_incomplete_pairs == 0
      and .variants.baseline.completed_runs == 1
      and .variants.candidate.completed_runs == 1
    ' "$model_mismatch_output/comparison.json" >/dev/null; then
    pass
else
    fail "unsupported JSONL model metadata affected persisted model evidence"
fi

test_start "trace import rejects adapter error codes outside the bounded vocabulary"
unbounded_trace_dir="$fixture_root/unbounded-trace"
mkdir -p "$unbounded_trace_dir"
jq '.error.code = "provider_secret_specific_error"' \
    "$missing_codex_output/traces/"*candidate.json >"$unbounded_trace_dir/unbounded.json"
unbounded_error="$fixture_root/unbounded-trace-error.txt"
if "$legacy_runner" --validate-traces "$unbounded_trace_dir" >/dev/null 2>"$unbounded_error"; then
    fail "legacy trace import accepted an unbounded adapter error code"
elif grep -Fq 'error.code is not in the bounded vocabulary' "$unbounded_error"; then
    pass
else
    fail "unbounded adapter error rejection was not actionable"
fi

test_start "trace import rejects raw or mismatched adapter error messages"
unbounded_message_trace_dir="$fixture_root/unbounded-message-trace"
unbounded_message_error="$fixture_root/unbounded-message-error.txt"
unbounded_message_marker='sk-private-imported-provider-message'
mkdir -p "$unbounded_message_trace_dir"
jq --arg marker "$unbounded_message_marker" '.error.message = ($marker * 5000)' \
    "$missing_codex_output/traces/"*candidate.json >"$unbounded_message_trace_dir/unbounded-message.json"
if "$legacy_runner" --validate-traces "$unbounded_message_trace_dir" >/dev/null 2>"$unbounded_message_error"; then
    fail "trace import accepted an unbounded raw provider error message"
elif grep -Fq 'error.message does not match bounded message for error.code' "$unbounded_message_error"; then
    pass
else
    fail "raw adapter error message rejection was not actionable"
fi

test_start "v4 resolved-model traces cannot mix with the v5 attestation contract"
legacy_v4_trace_dir="$fixture_root/legacy-v4-trace"
legacy_v4_error="$fixture_root/legacy-v4-error.txt"
mkdir -p "$legacy_v4_trace_dir"
jq '
  .provenance.resolved_model = .provenance.requested_model
  | del(.provenance.runtime_model_attestation)
  | del(.provenance.model_selection_evidence)
  | del(.provenance.requested_model_catalog_entry_sha256)
  | del(.provenance.codex_executable_sha256)
  | .provenance.adapter_version = "codex-framework-eval-v4"
' "$(find "$official_jsonl_output/traces" -name '*.json' | LC_ALL=C sort | sed -n '1p')" \
    >"$legacy_v4_trace_dir/legacy-v4.json"
if ! "$legacy_runner" --validate-traces "$legacy_v4_trace_dir" >/dev/null 2>"$legacy_v4_error" \
    && grep -Eq 'runtime_model_attestation|resolved_model' "$legacy_v4_error"; then
    pass
else
    fail "legacy resolved-model evidence remained valid under the v5 schema"
fi

test_start "trace identity rejects requested-model alias contradictions"
model_alias_trace_dir="$fixture_root/model-alias-trace"
model_alias_error="$fixture_root/model-alias-error.txt"
mkdir -p "$model_alias_trace_dir"
jq '.model = "different-requested-model"' \
    "$(find "$official_jsonl_output/traces" -name '*.json' | LC_ALL=C sort | sed -n '1p')" \
    >"$model_alias_trace_dir/model-alias.json"
if ! "$legacy_runner" --validate-traces "$model_alias_trace_dir" >/dev/null 2>"$model_alias_error" \
    && grep -Fq 'model must equal provenance.requested_model' "$model_alias_error"; then
    pass
else
    fail "trace top-level requested-model alias could contradict provenance"
fi

test_start "catalog and argument-only evidence enforce their hash invariants in validation and comparison"
attestation_invariant_dir="$fixture_root/attestation-invariant-traces"
attestation_invariant_error="$fixture_root/attestation-invariant-error.txt"
mkdir -p "$attestation_invariant_dir"
official_trace="$(find "$official_jsonl_output/traces" -name '*.json' | LC_ALL=C sort | sed -n '1p')"
trusted_trace="$(find "$trusted_output/traces" -name '*.json' | LC_ALL=C sort | sed -n '1p')"
jq '.provenance.requested_model_catalog_entry_sha256 = ("a" * 64)' "$official_trace" \
    >"$attestation_invariant_dir/argument-only-with-catalog.json"
jq '.provenance.requested_model_catalog_entry_sha256 = null' "$trusted_trace" \
    >"$attestation_invariant_dir/catalog-without-entry-hash.json"
invalid_catalog_pair_dir="$fixture_root/invalid-catalog-pair"
mkdir -p "$invalid_catalog_pair_dir"
for trace in "$trusted_output/traces/"*.json; do
    jq '.provenance.requested_model_catalog_entry_sha256 = null' "$trace" \
        >"$invalid_catalog_pair_dir/$(basename "$trace")"
done
invalid_catalog_comparison="$fixture_root/invalid-catalog-comparison.json"
if ! "$legacy_runner" --validate-traces "$attestation_invariant_dir" >/dev/null 2>"$attestation_invariant_error" \
    && grep -Fq 'model-selection evidence hashes are inconsistent' "$attestation_invariant_error" \
    && jq -s --argjson manifest '{}' --arg candidate_manifest_sha256 '' \
        -f "$comparison_program" "$invalid_catalog_pair_dir/"*.json >"$invalid_catalog_comparison" \
    && jq -e '.complete_pairs == 0 and .excluded_incomplete_pairs == 1' "$invalid_catalog_comparison" >/dev/null; then
    pass
else
    fail "impossible catalog-attestation combinations entered validation or complete aggregates"
fi

test_start "trace validator enforces published hash metric and proxy-method schema"
schema_drift_dir="$fixture_root/schema-drift-trace"
mkdir -p "$schema_drift_dir"
completed_trace="$(find "$execute_output/traces" -name '*.json' | LC_ALL=C sort | sed -n '1p')"
jq '
  .provenance.fixture_sha256 = "not-a-sha"
  | .metrics.scope_deviations = "zero"
  | .execution.metric_methods.rework_count = "unbounded_guess"
' "$completed_trace" >"$schema_drift_dir/invalid.json"
schema_drift_error="$fixture_root/schema-drift-error.txt"
if "$legacy_runner" --validate-traces "$schema_drift_dir" >/dev/null 2>"$schema_drift_error"; then
    fail "hand-written validator accepted a trace rejected by the published schema"
elif grep -Fq 'provenance.fixture_sha256 must be a lowercase SHA-256' "$schema_drift_error" \
    && grep -Fq 'scope_deviations' "$schema_drift_error" \
    && grep -Fq 'execution.metric_methods does not match the published proxy contract' "$schema_drift_error"; then
    pass
else
    fail "schema-parity validation errors were incomplete or unactionable"
fi

test_start "trace schema declares behavioral provenance and bounded adapter errors"
if jq -e '
    (.properties.pair_id.type == "string")
    and (.properties.trial_index.type == "integer")
    and (.properties.provenance.required | contains([
      "fixture_sha256", "case_sha256", "instruction_sha256", "grader_sha256", "cli_version",
      "requested_model", "runtime_model_attestation", "model_selection_evidence",
      "requested_model_catalog_entry_sha256", "codex_executable_sha256", "adapter_version"
    ]))
    and (.properties.provenance.properties | has("resolved_model") | not)
    and (.properties.model.description | contains("provenance.requested_model"))
    and (.properties.provenance.allOf | length == 2)
    and (.properties.execution.required | contains(["exit_code", "verifier"]))
    and ([.allOf[] | select(.if.properties.status.const == "completed") | .then.required][0]
      | contains(["metrics", "provenance", "execution"]))
    and (.properties.error.properties.code.enum | contains([
      "codex_not_found", "codex_exit_nonzero", "codex_reported_failure", "local_execution_restricted", "unknown_event_shape",
      "missing_usage", "missing_final_output"
    ]))
    and (.properties.error as $error
      | ($error.oneOf | length) == ($error.properties.code.enum | length))
' "$schema" >/dev/null; then
    pass
else
    fail "trace schema does not expose the required behavioral provenance contract"
fi

test_start "Codex workflow examples use the current -C working-directory flag"
if grep -Fq 'AGENT_CWD_FLAG="-C"' "$FRAMEWORK_DIR/skills/assistant-workflow/agents/codex.conf" \
    && grep -Fq 'codex exec "PROMPT" -C DIR' "$FRAMEWORK_DIR/skills/assistant-workflow/agent.conf" \
    && grep -Fq -- "codex exec \"\$(cat 'briefs/slice-<N>-<slice_id>.md')\" -C ." "$FRAMEWORK_DIR/skills/assistant-workflow/references/sub-task-brief-template.md" \
    && ! grep -Fq -- 'codex exec "PROMPT" --cwd DIR' "$FRAMEWORK_DIR/skills/assistant-workflow/agent.conf"; then
    pass
else
    fail "one or more approved Codex launch examples still use --cwd"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
