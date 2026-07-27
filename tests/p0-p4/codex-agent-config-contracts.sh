#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

agent_dir="$FRAMEWORK_DIR/agents/codex"
smoke_helper="$FRAMEWORK_DIR/tools/smoke-test-codex-agents.sh"
troubleshooting_doc="$FRAMEWORK_DIR/docs/troubleshooting-subagents.md"

expected_agents="architect
builder-tester
code-mapper
code-reviewer
code-writer
explorer
qa-evaluator
reviewer"

toml_quoted_value() {
    local key="$1"
    local file="$2"
    sed -n "s/^${key} = \"\(.*\)\"$/\1/p" "$file"
}

test_start "Codex agent inventory, names, and sandboxes remain exact"
actual_agents="$(
    for file in "$agent_dir"/*.toml; do
        basename "$file" .toml
    done | LC_ALL=C sort
)"
agent_baseline_failures=()
if [[ "$actual_agents" != "$expected_agents" ]]; then
    agent_baseline_failures+=("expected exactly eight agent files")
fi
while IFS='|' read -r agent expected_sandbox; do
    file="$agent_dir/$agent.toml"
    if [[ ! -f "$file" ]]; then
        agent_baseline_failures+=("$agent: missing")
        continue
    fi
    if [[ "$(toml_quoted_value name "$file")" != "$agent" ]]; then
        agent_baseline_failures+=("$agent: basename/name disagreement")
    fi
    if [[ "$(toml_quoted_value sandbox_mode "$file")" != "$expected_sandbox" ]]; then
        agent_baseline_failures+=("$agent: expected sandbox $expected_sandbox")
    fi
done <<'EOF'
architect|read-only
builder-tester|workspace-write
code-mapper|read-only
code-reviewer|read-only
code-writer|workspace-write
explorer|read-only
qa-evaluator|read-only
reviewer|read-only
EOF
if [[ "${#agent_baseline_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "Codex agent inventory/name/sandbox drift: ${agent_baseline_failures[*]}"
fi

test_start "Codex agents declare the approved model and reasoning effort matrix"
matrix_failures=()
while IFS='|' read -r agent expected_model expected_effort; do
    file="$agent_dir/$agent.toml"
    [[ -f "$file" ]] || continue

    model_count="$(grep -Ec '^model[[:space:]]*=' "$file" || true)"
    effort_count="$(grep -Ec '^model_reasoning_effort[[:space:]]*=' "$file" || true)"
    actual_model="$(toml_quoted_value model "$file")"
    actual_effort="$(toml_quoted_value model_reasoning_effort "$file")"
    developer_line="$(grep -n -m1 '^developer_instructions = ' "$file" | cut -d: -f1 || true)"
    model_line="$(grep -n -m1 '^model = ' "$file" | cut -d: -f1 || true)"
    effort_line="$(grep -n -m1 '^model_reasoning_effort = ' "$file" | cut -d: -f1 || true)"

    if [[ "$model_count" != "1" || "$actual_model" != "$expected_model" ]]; then
        matrix_failures+=("$agent: expected one model=$expected_model")
    fi
    if [[ "$effort_count" != "1" || "$actual_effort" != "$expected_effort" ]]; then
        matrix_failures+=("$agent: expected one model_reasoning_effort=$expected_effort")
    fi
    case "$actual_effort" in
        low|medium|high|xhigh) ;;
        *) matrix_failures+=("$agent: effort must be low/medium/high/xhigh, never light") ;;
    esac
    if [[ -z "$developer_line" || -z "$model_line" || -z "$effort_line" ]] \
        || (( model_line >= developer_line || effort_line >= developer_line )); then
        matrix_failures+=("$agent: model fields must precede developer_instructions")
    fi
done <<'EOF'
architect|gpt-5.6-sol|xhigh
builder-tester|gpt-5.6-terra|medium
code-mapper|gpt-5.6-luna|low
code-reviewer|gpt-5.6-sol|xhigh
code-writer|gpt-5.6-terra|high
explorer|gpt-5.6-terra|medium
qa-evaluator|gpt-5.6-sol|high
reviewer|gpt-5.6-sol|xhigh
EOF
if [[ "${#matrix_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "Codex model/effort contract violations: ${matrix_failures[*]}"
fi

test_start "Codex operating stances are compact and role-specific"
stance_failures=()
while IFS='|' read -r agent role_anchor; do
    file="$agent_dir/$agent.toml"
    [[ -f "$file" ]] || continue
    heading_count="$(grep -c '^## Operating stance$' "$file" || true)"
    stance="$(awk '
        /^## Operating stance$/ { in_stance = 1; next }
        in_stance && /^## / { exit }
        in_stance { print }
    ' "$file")"
    bullet_count="$(printf '%s\n' "$stance" | grep -c '^- ' || true)"
    nonblank_count="$(printf '%s\n' "$stance" | grep -c '[^[:space:]]' || true)"
    word_count="$(printf '%s\n' "$stance" | wc -w | tr -d '[:space:]')"

    if [[ "$heading_count" != "1" ]]; then
        stance_failures+=("$agent: expected exactly one Operating stance heading")
    fi
    if (( bullet_count < 2 || bullet_count > 4 || nonblank_count != bullet_count )); then
        stance_failures+=("$agent: stance must contain only 2-4 nonblank bullet lines")
    fi
    if (( word_count > 100 )); then
        stance_failures+=("$agent: stance exceeds 100 words")
    fi
    if ! printf '%s\n' "$stance" | grep -Fqi -- "$role_anchor"; then
        stance_failures+=("$agent: missing role anchor '$role_anchor'")
    fi
done <<'EOF'
architect|trade-off
builder-tester|repeatable
code-mapper|paths
code-reviewer|correctness
code-writer|smallest
explorer|evidence
qa-evaluator|acceptance
reviewer|compatibility
EOF
if [[ "${#stance_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "Codex Operating stance contract violations: ${stance_failures[*]}"
fi

test_start "Canonical and compatibility reviewers share configuration and review posture"
canonical_reviewer="$agent_dir/code-reviewer.toml"
compatibility_reviewer="$agent_dir/reviewer.toml"
if [[ "$(toml_quoted_value model "$canonical_reviewer")" == "$(toml_quoted_value model "$compatibility_reviewer")" ]] \
    && [[ "$(toml_quoted_value model_reasoning_effort "$canonical_reviewer")" == "$(toml_quoted_value model_reasoning_effort "$compatibility_reviewer")" ]] \
    && grep -Fq -- "Review the work, not the author." "$canonical_reviewer" \
    && grep -Fq -- "Review the work, not the author." "$compatibility_reviewer"; then
    pass
else
    fail "reviewer must mirror code-reviewer model/effort and both must say 'Review the work, not the author.'"
fi

test_start "Installer-managed Codex AGENTS guidance keeps one adaptive main stance without subagent role configuration"
lean_guidance_failures=()
for installer_source in "$FRAMEWORK_DIR/install.sh" "$FRAMEWORK_DIR/install.ps1"; do
    installer_label="${installer_source#$FRAMEWORK_DIR/}"
    if grep -Eq 'gpt-5\.6-(luna|terra|sol)|model_reasoning_effort' "$installer_source"; then
        lean_guidance_failures+=("$installer_label: embeds subagent model/effort guidance")
    fi
    if [[ "$(grep -Fc -- '## Operating stance' "$installer_source")" != "1" ]]; then
        lean_guidance_failures+=("$installer_label: expected exactly one adaptive Operating stance heading")
    fi
    for stance_anchor in \
        "For small, low-risk, localized work, act as a hands-on worker" \
        "For medium+ or elevated-risk development work, remain the orchestrator" \
        "Keep orchestration proportional"; do
        if ! grep -Fq -- "$stance_anchor" "$installer_source"; then
            lean_guidance_failures+=("$installer_label: missing adaptive stance anchor '$stance_anchor'")
        fi
    done
    if grep -Fq -- 'Review the work, not the author.' "$installer_source"; then
        lean_guidance_failures+=("$installer_label: embeds subagent-specific personality guidance")
    fi
done
if [[ "${#lean_guidance_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "Codex AGENTS installer source must keep only the compact main stance: ${lean_guidance_failures[*]}"
fi

test_start "Codex agent smoke helper is fixed-scope and metadata-only"
smoke_failures=()
if [[ ! -x "$smoke_helper" ]]; then
    smoke_failures+=("tools/smoke-test-codex-agents.sh: missing or not executable")
else
    smoke_source="$(tr '\n\t' '  ' <"$smoke_helper" | tr -s '[:space:]' ' ')"
    for required_term in \
        '--check-only' \
        '--live' \
        'code-mapper' \
        'explorer' \
        'code-writer' \
        'architect' \
        'qa-evaluator' \
        'ENVIRONMENT_FAILURE' \
        'RUNTIME_DISPATCH_OR_SCHEMA_FAILURE' \
        'CONFIG_MISMATCH' \
        'jq' \
        'source.subagent.thread_spawn.agent_role' \
        'turn_context' \
        '.payload.model' \
        '.payload.effort'; do
        if ! grep -Fq -- "$required_term" "$smoke_helper"; then
            smoke_failures+=("smoke helper missing '$required_term'")
        fi
    done
    if grep -Eq '(^|[[:space:];])(eval|bash[[:space:]]+-c|sh[[:space:]]+-c)([[:space:]]|$)' "$smoke_helper"; then
        smoke_failures+=("smoke helper must not use eval, bash -c, or sh -c")
    fi
    if ! grep -Fq -- 'cmp' "$smoke_helper"; then
        smoke_failures+=("smoke helper must verify source/install parity")
    fi
    if ! grep -Eq 'mktemp[[:space:]].*-d|mktemp[[:space:]]+-d' "$smoke_helper" \
        || ! grep -Eq 'git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+init' "$smoke_helper"; then
        smoke_failures+=("smoke helper must run in a temporary git repository")
    fi
    if ! grep -Fq -- 'touch' "$smoke_helper" || ! grep -Fq -- '-newer' "$smoke_helper"; then
        smoke_failures+=("smoke helper must bound metadata reads to newly created sessions")
    fi
    if ! printf '%s\n' "$smoke_source" | grep -Eq 'codex[[:space:]]+exec.*--json.*>'; then
        smoke_failures+=("smoke helper must suppress codex exec JSON/stdout to a file")
    fi
    if ! printf '%s\n' "$smoke_source" \
        | grep -Eq 'codex[[:space:]]+exec[^;]*<[[:space:]]*/dev/null'; then
        smoke_failures+=("live codex exec must close stdin with </dev/null")
    fi
    if ! printf '%s\n' "$smoke_source" \
        | grep -Eq "codex[[:space:]]+exec.*(--model|-m)([[:space:]]+|=)['\"]?gpt-5\\.6-luna['\"]?"; then
        smoke_failures+=("live probe parent must explicitly pin model gpt-5.6-luna")
    fi
    if ! grep -Fq -- 'model_reasoning_effort="low"' "$smoke_helper"; then
        smoke_failures+=("live probe parent must explicitly pin model_reasoning_effort=low")
    fi
    if ! grep -Eq '\.payload\.source[^[:cntrl:]]{0,100}exec|exec[^[:cntrl:]]{0,100}\.payload\.source' "$smoke_helper" \
        || ! grep -Fq -- '.payload.cwd' "$smoke_helper" \
        || ! grep -Fq -- 'smoke_repo' "$smoke_helper"; then
        smoke_failures+=("live smoke must select a new source=exec parent whose cwd is the temporary smoke repo")
    fi
    if ! grep -Fq -- '.payload.id' "$smoke_helper"; then
        smoke_failures+=("live smoke must extract the selected parent session payload.id")
    fi
    if ! grep -Fq -- '.payload.source.subagent.thread_spawn.parent_thread_id' "$smoke_helper"; then
        smoke_failures+=("live smoke must extract each child thread_spawn.parent_thread_id")
    fi
    if ! grep -Eq \
        'parent_thread_id[^[:cntrl:]]{0,240}(==|!=|-eq|-ne)|(==|!=|-eq|-ne)[^[:cntrl:]]{0,240}parent_thread_id' \
        "$smoke_helper"; then
        smoke_failures+=("live smoke must compare child parent_thread_id with the selected parent payload.id before accepting metadata")
    fi
    for representative_role in code-mapper explorer code-writer architect qa-evaluator; do
        prompt_case="$(awk -v role="$representative_role" '
            $0 ~ "^[[:space:]]*" role "\\)" { in_role = 1 }
            in_role { print }
            in_role && /^[[:space:]]*;;[[:space:]]*$/ { exit }
        ' "$smoke_helper")"
        if ! printf '%s\n' "$prompt_case" \
            | grep -Eq "agent_type.{0,100}${representative_role}"; then
            smoke_failures+=("role=$representative_role prompt must explicitly set agent_type=$representative_role")
        fi
    done
    probe_counter="$(sed -nE \
        's/^[[:space:]]*([[:alnum:]_]*(probe|verified|successful)[[:alnum:]_]*)=0[[:space:]]*$/\1/p' \
        "$smoke_helper" | sed -n '1p')"
    if [[ -z "$probe_counter" ]]; then
        smoke_failures+=("live smoke must initialize an actual successful/verified probe counter")
    else
        run_probe_line="$(grep -n -m1 'run_live_probe "\$role"' "$smoke_helper" | cut -d: -f1 || true)"
        increment_line="$(grep -nE -m1 \
            "${probe_counter}[[:space:]]*=[[:space:]]*\\$\\(\\([[:space:]]*${probe_counter}[[:space:]]*\\+[[:space:]]*1[[:space:]]*\\)\\)|\\(\\([[:space:]]*${probe_counter}[[:space:]]*(\\+=[[:space:]]*1|\\+\\+)[[:space:]]*\\)\\)" \
            "$smoke_helper" | cut -d: -f1 || true)"
        success_line="$(grep -n -m1 'LIVE_SMOKE_OK' "$smoke_helper" || true)"
        success_line_number="${success_line%%:*}"
        success_text="${success_line#*:}"
        verification_line="$(tr -d '"' <"$smoke_helper" \
            | tr -d "'" \
            | grep -nE \
                "(\\$\\{?${probe_counter}\\}?|${probe_counter})[[:space:]]*(-eq|==|-ne|!=)[[:space:]]*5" \
            | sed -n '1s/:.*//p')"

        if [[ -z "$run_probe_line" || -z "$increment_line" ]] \
            || (( increment_line <= run_probe_line )); then
            smoke_failures+=("live smoke must increment its probe counter after each successful run_live_probe")
        fi
        if [[ -z "$verification_line" || -z "$success_line_number" ]] \
            || (( verification_line >= success_line_number )); then
            smoke_failures+=("live smoke must verify the actual successful probe count equals five before success")
        fi
        if [[ "$success_text" != *'representatives='* ]] \
            || [[ "$success_text" == *'representatives=5'* ]] \
            || { [[ "$success_text" != *"\$$probe_counter"* ]] \
                && [[ "$success_text" != *'${'"$probe_counter"'}'* ]]; }; then
            smoke_failures+=("LIVE_SMOKE_OK must print the actual probe counter, not hard-code representatives=5")
        fi
    fi
    if grep -Eq '\.payload\.(message|content|text)|raw_prompt|prompt_body' "$smoke_helper"; then
        smoke_failures+=("smoke helper must extract metadata only")
    fi

    fake_bin="$(mktemp -d "${TMPDIR:-/tmp}/codex-agent-smoke-fake.XXXXXX")"
    p0p4_register_cleanup "$fake_bin"
    printf '%s\n' '#!/usr/bin/env bash' 'touch "${CODEX_FAKE_CALLED:?}"' 'exit 99' >"$fake_bin/codex"
    chmod +x "$fake_bin/codex"
    fake_called="$fake_bin/arbitrary-called"
    if CODEX_FAKE_CALLED="$fake_called" PATH="$fake_bin:$PATH" \
        "$smoke_helper" code-mapper >"$fake_bin/out" 2>"$fake_bin/err"; then
        smoke_failures+=("smoke helper accepted an arbitrary positional role")
    elif [[ -e "$fake_called" ]]; then
        smoke_failures+=("smoke helper invoked codex before rejecting an arbitrary positional role")
    fi
    fake_check_called="$fake_bin/check-called"
    if CODEX_FAKE_CALLED="$fake_check_called" PATH="$fake_bin:$PATH" \
        "$smoke_helper" --check-only >"$fake_bin/check.out" 2>"$fake_bin/check.err"; then
        if [[ -e "$fake_check_called" ]]; then
            smoke_failures+=("--check-only must not invoke codex")
        fi
    else
        smoke_failures+=("--check-only failed static source validation")
    fi

    fake_runtime_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-agent-unrelated-runtime.XXXXXX")"
    fake_codex_home="$fake_runtime_root/codex-home"
    fake_runtime_bin="$fake_runtime_root/bin"
    fake_runtime_state="$fake_runtime_root/state"
    mkdir -p "$fake_codex_home/agents" "$fake_codex_home/sessions" "$fake_runtime_bin" "$fake_runtime_state"
    cp "$agent_dir"/*.toml "$fake_codex_home/agents/"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -euo pipefail' \
        'state_file="${FAKE_CODEX_STATE:?}/call-count"' \
        'call_count=0' \
        'if [[ -f "$state_file" ]]; then read -r call_count <"$state_file"; fi' \
        'call_count=$((call_count + 1))' \
        'printf "%s\n" "$call_count" >"$state_file"' \
        'case "$call_count" in' \
        '    1) role="code-mapper"; model="gpt-5.6-luna"; effort="low" ;;' \
        '    2) role="explorer"; model="gpt-5.6-terra"; effort="medium" ;;' \
        '    3) role="code-writer"; model="gpt-5.6-terra"; effort="high" ;;' \
        '    4) role="architect"; model="gpt-5.6-sol"; effort="xhigh" ;;' \
        '    5) role="qa-evaluator"; model="gpt-5.6-sol"; effort="high" ;;' \
        '    *) exit 91 ;;' \
        'esac' \
        'session_file="$CODEX_HOME/sessions/fake-child-${call_count}.jsonl"' \
        'printf "{\"type\":\"session_meta\",\"payload\":{\"id\":\"fake-child-%s\",\"source\":{\"subagent\":{\"thread_spawn\":{\"parent_thread_id\":\"unrelated-parent\",\"agent_role\":\"%s\"}}}}}\n" "$call_count" "$role" >"$session_file"' \
        'printf "{\"type\":\"turn_context\",\"payload\":{\"model\":\"%s\",\"effort\":\"%s\"}}\n" "$model" "$effort" >>"$session_file"' \
        'exit 0' \
        >"$fake_runtime_bin/codex"
    chmod +x "$fake_runtime_bin/codex"
    p0p4_register_cleanup "$fake_runtime_root"

    fake_live_out="$fake_runtime_root/live.out"
    fake_live_err="$fake_runtime_root/live.err"
    if CODEX_HOME="$fake_codex_home" FAKE_CODEX_STATE="$fake_runtime_state" \
        PATH="$fake_runtime_bin:$PATH" \
        "$smoke_helper" --live >"$fake_live_out" 2>"$fake_live_err"; then
        if grep -Fq -- 'LIVE_SMOKE_OK' "$fake_live_out"; then
            smoke_failures+=("live smoke falsely accepted unrelated matching child sessions and emitted LIVE_SMOKE_OK")
        else
            smoke_failures+=("live smoke returned success for unrelated matching child sessions")
        fi
    else
        if ! grep -Fq -- 'RUNTIME_DISPATCH_OR_SCHEMA_FAILURE' "$fake_live_err"; then
            smoke_failures+=("unrelated child sessions must fail as RUNTIME_DISPATCH_OR_SCHEMA_FAILURE")
        fi
        if grep -Fq -- 'LIVE_SMOKE_OK' "$fake_live_out" "$fake_live_err"; then
            smoke_failures+=("unrelated child sessions must never emit LIVE_SMOKE_OK")
        fi
    fi
fi
if [[ ! -f "$troubleshooting_doc" ]]; then
    smoke_failures+=("docs/troubleshooting-subagents.md: missing")
else
    troubleshooting_text="$(tr '\n\t' '  ' <"$troubleshooting_doc" | tr -s '[:space:]' ' ')"
    if ! printf '%s\n' "$troubleshooting_text" \
        | grep -Eqi 'probe.{0,120}intentional[^.]{0,120}Luna.{0,40}v1|intentional[^.]{0,120}Luna.{0,40}v1.{0,120}probe'; then
        smoke_failures+=("troubleshooting must explain that the probe intentionally uses a Luna/v1 parent")
    fi
    if ! printf '%s\n' "$troubleshooting_text" \
        | grep -Eqi '(Sol.{0,40}Terra|Terra.{0,40}Sol).{0,80}v2.{0,160}(omit|missing|unavailable).{0,80}(custom[- ]role|role selection|agent_type)'; then
        smoke_failures+=("troubleshooting must explain that current Sol/Terra v2 runtimes may omit custom-role selection")
    fi
    if ! printf '%s\n' "$troubleshooting_text" \
        | grep -Eqi 'runtime limitation.{0,120}not.{0,40}(a )?TOML mismatch'; then
        smoke_failures+=("troubleshooting must classify the dispatch gap as a runtime limitation, not a TOML mismatch")
    fi
fi
if [[ "${#smoke_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "Codex smoke helper contract violations: ${smoke_failures[*]}"
fi

test_start "Codex agent contract scripts are registered and syntactically valid"
syntax_failures=()
if [[ "$(grep -Fc 'source "$P0P4_SUITE_DIR/codex-agent-config-contracts.sh"' "$FRAMEWORK_DIR/tests/test-p0-p4-contracts.sh" || true)" != "1" ]]; then
    syntax_failures+=("aggregate suite must source codex-agent-config-contracts.sh exactly once")
fi
for script in \
    "$FRAMEWORK_DIR/tests/test-p0-p4-contracts.sh" \
    "$FRAMEWORK_DIR/tests/p0-p4/codex-agent-config-contracts.sh"; do
    if ! bash -n "$script"; then
        syntax_failures+=("${script#$FRAMEWORK_DIR/}: bash syntax failure")
    fi
done
if [[ -e "$smoke_helper" ]] && ! bash -n "$smoke_helper"; then
    syntax_failures+=("tools/smoke-test-codex-agents.sh: bash syntax failure")
fi
if [[ "${#syntax_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "Codex agent contract registration/syntax violations: ${syntax_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
