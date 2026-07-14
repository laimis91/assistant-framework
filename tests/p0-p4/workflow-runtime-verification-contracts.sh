#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

workflow="$FRAMEWORK_DIR/skills/assistant-workflow"
runtime_output_dir="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-output.XXXXXX")"
p0p4_register_cleanup "$runtime_output_dir"

init_runtime_repo() {
    local repo="$1"
    local task="$2"

    git -C "$repo" init -q
    git -C "$repo" config user.email "p0p4@example.invalid"
    git -C "$repo" config user.name "P0 P4"
    printf 'fixture\n' >"$repo/README.md"
    printf '.worktrees/\n' >"$repo/.gitignore"
    git -C "$repo" add README.md .gitignore
    git -C "$repo" commit -q -m init
    git -C "$repo" branch "feature/${task}/integration"
}

write_runtime_brief() {
    local repo="$1"
    local task="$2"
    local number="$3"
    local slice_id="$4"
    local depends_on="$5"
    shift 5
    local brief="$repo/briefs/slice-${number}-${slice_id}.md"
    local arg
    local worktree_hint="${RUNTIME_WORKTREE_HINT:-${repo}/.worktrees/${slice_id}}"

    mkdir -p "$repo/briefs"
    cat >"$brief" <<BRIEF
## Slice Brief: ${slice_id}

### Strict slice packet (execution contract)
- slice_id: ${slice_id}
- slice_name: ${slice_id}
- observable_increment: ${slice_id} increment
- deliverable_type: behavior
- files_to_create:
  - none
- files_to_modify:
  - ${slice_id}-marker.txt
- files_to_test:
  - host verification command
- enabling_changes_included:
  - none
- depends_on:
BRIEF
    if [[ "$depends_on" == "none" ]]; then
        printf '  - none\n' >>"$brief"
    else
        printf '  - %s\n' "$depends_on" >>"$brief"
    fi
    cat >>"$brief" <<BRIEF
- acceptance_criteria:
  - [ ] ${slice_id} is independently host verified
- verification_command:
BRIEF
    for arg in "$@"; do
        printf '  - %s\n' "$arg" >>"$brief"
    done
    cat >>"$brief" <<BRIEF
- expected_success_signal: verifier exits 0 without mutating HEAD
- evidence_to_record:
  - host verifier exit status and immutable HEAD proof
- deviation_rollback_rule: Return FAILED_VERIFICATION without merging or marking VERIFIED

### Supporting context (not the execution contract)
- Git branch: feature/${task}/slice-${slice_id}
- Worktree: ${worktree_hint}
BRIEF
}

make_fake_done_agent() {
    local bin_dir="$1"

    mkdir -p "$bin_dir"
    cat >"$bin_dir/codex" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail

cwd_arg=""
prompt_content=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|exec)
            shift
            prompt_content="${1:-}"
            ;;
        -C|--cd|--cwd)
            shift
            cwd_arg="${1:-}"
            ;;
    esac
    shift || true
done

slice_id="$(printf '%s\n' "$prompt_content" | awk '
    /^- slice_id:[[:space:]]*/ {
        value = $0
        sub(/^- slice_id:[[:space:]]*/, "", value)
        print value
        exit
    }
')"

[[ -n "$cwd_arg" && -d "$cwd_arg" ]] || exit 64
printf 'agent output for %s\n' "$slice_id" >"$cwd_arg/${slice_id}-marker.txt"
git -C "$cwd_arg" add "${slice_id}-marker.txt"
git -C "$cwd_arg" commit -q -m "${slice_id} agent output"
printf '## Slice Status: DONE\n\n### Slice evidence\n- slice_id: %s\n- result: pass\n' "$slice_id"
FAKE
    chmod +x "$bin_dir/codex"
}

make_fake_detaching_agent() {
    local bin_dir="$1"

    mkdir -p "$bin_dir"
    cat >"$bin_dir/codex" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail

cwd_arg=""
prompt_content=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|exec)
            shift
            prompt_content="${1:-}"
            ;;
        -C|--cd|--cwd)
            shift
            cwd_arg="${1:-}"
            ;;
    esac
    shift || true
done

slice_id="$(printf '%s\n' "$prompt_content" | awk '
    /^- slice_id:[[:space:]]*/ {
        value = $0
        sub(/^- slice_id:[[:space:]]*/, "", value)
        print value
        exit
    }
')"

[[ -n "$cwd_arg" && -d "$cwd_arg" ]] || exit 64
printf 'agent output for %s\n' "$slice_id" >"$cwd_arg/${slice_id}-marker.txt"
git -C "$cwd_arg" add "${slice_id}-marker.txt"
git -C "$cwd_arg" commit -q -m "${slice_id} agent output"
if [[ "${DETACH_TO_PARENT:-false}" == "true" ]]; then
    git -C "$cwd_arg" checkout -q --detach HEAD^
else
    git -C "$cwd_arg" checkout -q --detach HEAD
fi
printf '## Slice Status: DONE\n\n### Slice evidence\n- slice_id: %s\n- result: pass\n' "$slice_id"
FAKE
    chmod +x "$bin_dir/codex"
}

make_fake_quiescence_agent() {
    local bin_dir="$1"

    mkdir -p "$bin_dir"
    cat >"$bin_dir/codex" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail

cwd_arg=""
prompt_content=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|exec)
            shift
            prompt_content="${1:-}"
            ;;
        -C|--cd|--cwd)
            shift
            cwd_arg="${1:-}"
            ;;
    esac
    shift || true
done

slice_id="$(printf '%s\n' "$prompt_content" | awk '
    /^- slice_id:[[:space:]]*/ {
        value = $0
        sub(/^- slice_id:[[:space:]]*/, "", value)
        print value
        exit
    }
')"

[[ -n "$cwd_arg" && -d "$cwd_arg" ]] || exit 64
if [[ "$slice_id" == "beta" ]]; then
    : >"${PARALLEL_ACTIVE_FILE:?}"
else
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50; do
        [[ -e "${PARALLEL_ACTIVE_FILE:?}" ]] && break
        sleep 0.02
    done
fi

printf 'agent output for %s\n' "$slice_id" >"$cwd_arg/${slice_id}-marker.txt"
git -C "$cwd_arg" add "${slice_id}-marker.txt"
git -C "$cwd_arg" commit -q -m "${slice_id} agent output"

if [[ "$slice_id" == "beta" ]]; then
    sleep 1
    rm -f "${PARALLEL_ACTIVE_FILE:?}"
fi
printf '## Slice Status: DONE\n\n### Slice evidence\n- slice_id: %s\n- result: pass\n' "$slice_id"
FAKE
    chmod +x "$bin_dir/codex"
}

make_fake_verifier_creating_agent() {
    local bin_dir="$1"

    mkdir -p "$bin_dir"
    cat >"$bin_dir/codex" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail

cwd_arg=""
prompt_content=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|exec)
            shift
            prompt_content="${1:-}"
            ;;
        -C|--cd|--cwd)
            shift
            cwd_arg="${1:-}"
            ;;
    esac
    shift || true
done

slice_id="$(printf '%s\n' "$prompt_content" | awk '
    /^- slice_id:[[:space:]]*/ {
        value = $0
        sub(/^- slice_id:[[:space:]]*/, "", value)
        print value
        exit
    }
')"

[[ -n "$cwd_arg" && -d "$cwd_arg" ]] || exit 64
printf 'agent output for %s\n' "$slice_id" >"$cwd_arg/${slice_id}-marker.txt"
cat >"$cwd_arg/verify-slice.sh" <<'VERIFY'
#!/usr/bin/env bash
set -euo pipefail
test -f alpha-marker.txt
VERIFY
chmod +x "$cwd_arg/verify-slice.sh"
git -C "$cwd_arg" add "${slice_id}-marker.txt" verify-slice.sh
git -C "$cwd_arg" commit -q -m "${slice_id} output with verifier"
printf '## Slice Status: DONE\n\n### Slice evidence\n- slice_id: %s\n- result: pass\n' "$slice_id"
FAKE
    chmod +x "$bin_dir/codex"
}

make_fake_noisy_agent() {
    local bin_dir="$1"

    mkdir -p "$bin_dir"
    cat >"$bin_dir/codex" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
i=0
while [[ "$i" -lt 4096 ]]; do
    printf '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n'
    i=$((i + 1))
done
FAKE
    chmod +x "$bin_dir/codex"
}

add_verifier() {
    local repo="$1"
    local name="$2"
    local body="$3"

    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' "$body" >"$repo/$name"
    chmod +x "$repo/$name"
    git -C "$repo" add "$name"
    git -C "$repo" commit -q -m "add $name"
    git -C "$repo" branch -f "$(git -C "$repo" for-each-ref --format='%(refname:short)' 'refs/heads/feature/*/integration' | head -n 1)" HEAD
}

prepare_external_alpha() {
    local repo="$1"
    local task="$2"

    git -C "$repo" checkout -q -b "feature/${task}/slice-alpha" "feature/${task}/integration"
    printf 'externally completed alpha\n' >"$repo/alpha-marker.txt"
    git -C "$repo" add alpha-marker.txt
    git -C "$repo" commit -q -m "alpha external output"
    git -C "$repo" checkout -q "feature/${task}/integration"
    git -C "$repo" merge --ff-only -q "feature/${task}/slice-alpha"
}

test_start "workflow verification_command is canonical argv and shell reparsing is forbidden"
bad_verification_types="$(awk '
    /- name: verification_command$/ {
        field_line = FNR
        if ((getline next_line) <= 0 || next_line !~ /type: string\[\]/) {
            print FILENAME ":" field_line
        }
    }
' "$workflow/contracts/output.yaml" "$workflow/contracts/handoffs.yaml")"
unsafe_reparse="$(rg -n -e '(^|[^[:alnum:]_])eval([[:space:](]|$)' -e '(^|[[:space:]])(bash|sh)[[:space:]]+-c([[:space:]]|$)' "$workflow/scripts/run-agents.sh" 2>/dev/null || true)"
if [[ -n "$bad_verification_types" ]]; then
    fail "verification_command is not string[] argv at: $(printf '%s' "$bad_verification_types" | tr '\n' ' ')"
elif ! grep -A2 -F -- '- verification_command:' "$workflow/references/sub-task-brief-template.md" | grep -Eq '^[[:space:]]+- \[argv'; then
    fail "sub-task brief template does not represent verification_command as one argv item per list entry"
elif [[ -n "$unsafe_reparse" ]]; then
    fail "run-agents.sh reparses verification commands through a shell: $(printf '%s' "$unsafe_reparse" | tr '\n' ' ')"
else
    pass
fi

test_start "workflow rejects inline interpreter and control-token verification argv"
unsafe_argv_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-unsafe-argv.XXXXXX")"
p0p4_register_cleanup "$unsafe_argv_repo"
init_runtime_repo "$unsafe_argv_repo" runtime-unsafe-argv
write_runtime_brief "$unsafe_argv_repo" runtime-unsafe-argv 1 shell-inline none bash -c true
unsafe_inline_out="$runtime_output_dir/unsafe-inline.out"
unsafe_inline_err="$runtime_output_dir/unsafe-inline.err"
if bash "$workflow/scripts/run-agents.sh" --briefs "$unsafe_argv_repo/briefs" --repo "$unsafe_argv_repo" --dry-run >"$unsafe_inline_out" 2>"$unsafe_inline_err"; then
    fail "run-agents.sh accepted bash -c inline verification argv"
elif ! grep -Eqi 'inline|shell.*-c|interpreter' "$unsafe_inline_out" "$unsafe_inline_err"; then
    fail "inline interpreter rejection was not actionable"
else
    write_runtime_brief "$unsafe_argv_repo" runtime-unsafe-argv 1 control none '&&'
    unsafe_control_out="$runtime_output_dir/unsafe-control.out"
    unsafe_control_err="$runtime_output_dir/unsafe-control.err"
    if bash "$workflow/scripts/run-agents.sh" --briefs "$unsafe_argv_repo/briefs" --repo "$unsafe_argv_repo" --dry-run >"$unsafe_control_out" 2>"$unsafe_control_err"; then
        fail "run-agents.sh accepted a shell control token as verification executable"
    elif ! grep -Eqi 'control|executable' "$unsafe_control_out" "$unsafe_control_err"; then
        fail "control-token verification rejection was not actionable"
    else
        pass
    fi
fi

test_start "workflow verification executable policy rejects wrappers unknown outside and symlink targets"
executable_policy_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-executable-policy.XXXXXX")"
p0p4_register_cleanup "$executable_policy_repo"
init_runtime_repo "$executable_policy_repo" runtime-executable-policy
ln -s /bin/true "$executable_policy_repo/symlink-verifier"
accepted_executable_variants=()
for executable_variant in env-wrapper unknown-path outside-path symlink-target; do
    case "$executable_variant" in
        env-wrapper)
            write_runtime_brief "$executable_policy_repo" runtime-executable-policy 1 alpha none env bash -c true
            ;;
        unknown-path)
            write_runtime_brief "$executable_policy_repo" runtime-executable-policy 1 alpha none definitely-not-an-approved-verifier
            ;;
        outside-path)
            write_runtime_brief "$executable_policy_repo" runtime-executable-policy 1 alpha none "${TMPDIR:-/tmp}/outside-verifier.sh"
            ;;
        symlink-target)
            write_runtime_brief "$executable_policy_repo" runtime-executable-policy 1 alpha none ./symlink-verifier
            ;;
    esac
    executable_variant_out="$runtime_output_dir/executable-${executable_variant}.out"
    executable_variant_err="$runtime_output_dir/executable-${executable_variant}.err"
    if bash "$workflow/scripts/run-agents.sh" --briefs "$executable_policy_repo/briefs" --repo "$executable_policy_repo" --dry-run >"$executable_variant_out" 2>"$executable_variant_err"; then
        accepted_executable_variants+=("$executable_variant")
    fi
done
if [[ ${#accepted_executable_variants[@]} -gt 0 ]]; then
    fail "run-agents.sh accepted unsafe verification executable variants: ${accepted_executable_variants[*]}"
else
    pass
fi

test_start "workflow interpreter verification is bound to tracked repository scripts and rejects inline aliases"
interpreter_policy_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-interpreter-policy.XXXXXX")"
interpreter_policy_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-interpreter-agent.XXXXXX")"
p0p4_register_cleanup "$interpreter_policy_repo" "$interpreter_policy_agent_bin"
init_runtime_repo "$interpreter_policy_repo" runtime-interpreter-policy
add_verifier "$interpreter_policy_repo" verify-pass.sh 'exit 0'
make_fake_done_agent "$interpreter_policy_agent_bin"
accepted_interpreter_variants=()
for interpreter_variant in bash-outside python-outside node-outside pwsh-outside pwsh-short-command pwsh-short-encoded cmd-keep-open; do
    case "$interpreter_variant" in
        bash-outside)
            write_runtime_brief "$interpreter_policy_repo" runtime-interpreter-policy 1 alpha none bash /tmp/outside-verifier.sh
            ;;
        python-outside)
            write_runtime_brief "$interpreter_policy_repo" runtime-interpreter-policy 1 alpha none python /tmp/outside-verifier.py
            ;;
        node-outside)
            write_runtime_brief "$interpreter_policy_repo" runtime-interpreter-policy 1 alpha none node /tmp/outside-verifier.js
            ;;
        pwsh-outside)
            write_runtime_brief "$interpreter_policy_repo" runtime-interpreter-policy 1 alpha none pwsh -File 'C:\outside-verifier.ps1'
            ;;
        pwsh-short-command)
            write_runtime_brief "$interpreter_policy_repo" runtime-interpreter-policy 1 alpha none pwsh -c 'exit 0'
            ;;
        pwsh-short-encoded)
            write_runtime_brief "$interpreter_policy_repo" runtime-interpreter-policy 1 alpha none powershell.exe -e ZQB4AGkAdAAgADAA
            ;;
        cmd-keep-open)
            write_runtime_brief "$interpreter_policy_repo" runtime-interpreter-policy 1 alpha none cmd.exe /k verify-pass.cmd
            ;;
    esac
    interpreter_variant_out="$runtime_output_dir/interpreter-${interpreter_variant}.out"
    interpreter_variant_err="$runtime_output_dir/interpreter-${interpreter_variant}.err"
    if bash "$workflow/scripts/run-agents.sh" --briefs "$interpreter_policy_repo/briefs" --repo "$interpreter_policy_repo" --dry-run >"$interpreter_variant_out" 2>"$interpreter_variant_err"; then
        accepted_interpreter_variants+=("$interpreter_variant")
    fi
done
write_runtime_brief "$interpreter_policy_repo" runtime-interpreter-policy 1 alpha none bash ./verify-pass.sh
interpreter_tracked_out="$runtime_output_dir/interpreter-tracked.out"
interpreter_tracked_err="$runtime_output_dir/interpreter-tracked.err"
if [[ ${#accepted_interpreter_variants[@]} -gt 0 ]]; then
    fail "run-agents.sh accepted unsafe interpreter variants: ${accepted_interpreter_variants[*]}"
elif ! PATH="$interpreter_policy_agent_bin:$PATH" bash "$workflow/scripts/run-agents.sh" --briefs "$interpreter_policy_repo/briefs" --repo "$interpreter_policy_repo" --agent codex >"$interpreter_tracked_out" 2>"$interpreter_tracked_err"; then
    fail "run-agents.sh rejected a tracked repository script invoked through an approved interpreter: stdout=$(tr '\n' ' ' <"$interpreter_tracked_out") stderr=$(tr '\n' ' ' <"$interpreter_tracked_err")"
else
    pass
fi

test_start "workflow permits a slice-created verifier only when bound to the exact clean slice commit"
created_verifier_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-created-verifier.XXXXXX")"
created_verifier_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-created-verifier-agent.XXXXXX")"
p0p4_register_cleanup "$created_verifier_repo" "$created_verifier_agent_bin"
init_runtime_repo "$created_verifier_repo" runtime-created-verifier
write_runtime_brief "$created_verifier_repo" runtime-created-verifier 1 alpha none ./verify-slice.sh
make_fake_verifier_creating_agent "$created_verifier_agent_bin"
created_verifier_out="$runtime_output_dir/created-verifier.out"
created_verifier_err="$runtime_output_dir/created-verifier.err"
if ! PATH="$created_verifier_agent_bin:$PATH" bash "$workflow/scripts/run-agents.sh" --briefs "$created_verifier_repo/briefs" --repo "$created_verifier_repo" --agent codex >"$created_verifier_out" 2>"$created_verifier_err"; then
    fail "run-agents.sh rejected a verifier created and committed by its slice: stdout=$(tr '\n' ' ' <"$created_verifier_out") stderr=$(tr '\n' ' ' <"$created_verifier_err")"
elif ! git -C "$created_verifier_repo" show "feature/runtime-created-verifier/integration:verify-slice.sh" >/dev/null 2>&1; then
    fail "the exact commit-bound slice verifier was not promoted with the verified output"
else
    pass
fi

test_start "workflow canonical argv parser rejects lossy and duplicate Markdown representations"
argv_parser_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-argv-parser.XXXXXX")"
p0p4_register_cleanup "$argv_parser_repo"
init_runtime_repo "$argv_parser_repo" runtime-argv-parser
add_verifier "$argv_parser_repo" verify.sh 'exit 0'
accepted_parser_variants=()
for parser_variant in newline carriage-return leading-space trailing-space duplicate-field; do
    case "$parser_variant" in
        newline)
            write_runtime_brief "$argv_parser_repo" runtime-argv-parser 1 alpha none $'./verify.sh\ninjected-continuation'
            ;;
        carriage-return)
            write_runtime_brief "$argv_parser_repo" runtime-argv-parser 1 alpha none $'./verify.sh\r'
            ;;
        leading-space)
            write_runtime_brief "$argv_parser_repo" runtime-argv-parser 1 alpha none ' ./verify.sh'
            ;;
        trailing-space)
            write_runtime_brief "$argv_parser_repo" runtime-argv-parser 1 alpha none './verify.sh '
            ;;
        duplicate-field)
            write_runtime_brief "$argv_parser_repo" runtime-argv-parser 1 alpha none $'./verify.sh\n- verification_command:\n  - ./second-verifier.sh'
            ;;
    esac
    parser_variant_out="$runtime_output_dir/parser-${parser_variant}.out"
    parser_variant_err="$runtime_output_dir/parser-${parser_variant}.err"
    if bash "$workflow/scripts/run-agents.sh" --briefs "$argv_parser_repo/briefs" --repo "$argv_parser_repo" --dry-run >"$parser_variant_out" 2>"$parser_variant_err"; then
        accepted_parser_variants+=("$parser_variant")
    fi
done
if [[ ${#accepted_parser_variants[@]} -gt 0 ]]; then
    fail "run-agents.sh accepted non-round-trippable verification argv representations: ${accepted_parser_variants[*]}"
else
    decompose_argv_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-decompose-argv.XXXXXX")"
    p0p4_register_cleanup "$decompose_argv_repo"
    git -C "$decompose_argv_repo" init -q
    git -C "$decompose_argv_repo" config user.email "p0p4@example.invalid"
    git -C "$decompose_argv_repo" config user.name "P0 P4"
    printf 'fixture\n' >"$decompose_argv_repo/README.md"
    git -C "$decompose_argv_repo" add README.md
    git -C "$decompose_argv_repo" commit -q -m init
    cat >"$decompose_argv_repo/decomposition.json" <<'JSON'
{
  "task": "lossy-argv",
  "description": "reject lossy argv",
  "single_slice_rationale": "one validation slice",
  "slice_manifest": [{
    "slice_id": "alpha",
    "name": "alpha",
    "observable_increment": "argv validation",
    "deliverable_type": "behavior",
    "files_to_create": [],
    "files_to_modify": [],
    "files_to_test": [],
    "enabling_changes_included": [],
    "depends_on": [],
    "acceptance_criteria": ["argv is rejected"],
    "verification_command": ["true\ninjected"],
    "expected_success_signal": "rejected",
    "evidence_to_record": ["validation result"],
    "deviation_rollback_rule": "stop"
  }]
}
JSON
    if (cd "$decompose_argv_repo" && bash "$workflow/scripts/decompose.sh" --task lossy-argv --input decomposition.json --dry-run >/dev/null 2>&1); then
        fail "decompose.sh accepted a verification argv item containing a newline"
    else
        pass
    fi
fi

test_start "workflow host verifier preserves argv boundaries and gates DONE pass reports"
argv_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-argv.XXXXXX")"
argv_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-argv-agent.XXXXXX")"
p0p4_register_cleanup "$argv_repo" "$argv_agent_bin"
init_runtime_repo "$argv_repo" runtime-argv
add_verifier "$argv_repo" verify-argv.sh 'printf "%s\n" "$@" >"${HOST_VERIFIER_RECORD:?}"'
write_runtime_brief "$argv_repo" runtime-argv 1 alpha none ./verify-argv.sh "argument with spaces" 'literal;false'
make_fake_done_agent "$argv_agent_bin"
argv_record="$runtime_output_dir/argv-record.txt"
argv_out="$runtime_output_dir/argv.out"
argv_err="$runtime_output_dir/argv.err"
if ! PATH="$argv_agent_bin:$PATH" HOST_VERIFIER_RECORD="$argv_record" bash "$workflow/scripts/run-agents.sh" --briefs "$argv_repo/briefs" --repo "$argv_repo" --agent codex >"$argv_out" 2>"$argv_err"; then
    fail "run-agents.sh rejected a passing canonical argv verifier: stdout=$(tr '\n' ' ' <"$argv_out") stderr=$(tr '\n' ' ' <"$argv_err")"
elif [[ ! -f "$argv_record" ]]; then
    fail "run-agents.sh trusted DONE/pass without executing the host verification_command"
elif [[ "$(cat "$argv_record")" != $'argument with spaces\nliteral;false' ]]; then
    fail "host verifier argv boundaries were not preserved: $(tr '\n' '|' <"$argv_record")"
elif ! git -C "$argv_repo" show "feature/runtime-argv/integration:alpha-marker.txt" >/dev/null 2>&1; then
    fail "host-verified slice was not merged after its canonical argv verifier passed"
else
    pass
fi

test_start "workflow host verification logs cannot follow a pre-existing symlink"
log_symlink_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-log-symlink.XXXXXX")"
log_symlink_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-log-symlink-agent.XXXXXX")"
p0p4_register_cleanup "$log_symlink_repo" "$log_symlink_agent_bin"
init_runtime_repo "$log_symlink_repo" runtime-log-symlink
add_verifier "$log_symlink_repo" verify-pass.sh 'exit 0'
write_runtime_brief "$log_symlink_repo" runtime-log-symlink 1 alpha none ./verify-pass.sh
make_fake_done_agent "$log_symlink_agent_bin"
mkdir -p "$log_symlink_repo/briefs/logs"
log_symlink_target="$runtime_output_dir/log-symlink-target.txt"
printf 'do not overwrite\n' >"$log_symlink_target"
ln -s "$log_symlink_target" "$log_symlink_repo/briefs/logs/slice-1-alpha.host-verify.log"
log_symlink_out="$runtime_output_dir/log-symlink.out"
log_symlink_err="$runtime_output_dir/log-symlink.err"
log_symlink_exit=0
PATH="$log_symlink_agent_bin:$PATH" bash "$workflow/scripts/run-agents.sh" --briefs "$log_symlink_repo/briefs" --repo "$log_symlink_repo" --agent codex >"$log_symlink_out" 2>"$log_symlink_err" || log_symlink_exit=$?
if [[ "$(cat "$log_symlink_target")" != "do not overwrite" ]]; then
    fail "host verification followed a pre-existing log symlink and overwrote its target"
elif [[ "$log_symlink_exit" -ne 0 ]] && ! grep -Eqi 'symlink|unsafe.*log|log.*target' "$log_symlink_out" "$log_symlink_err"; then
    fail "unsafe log destination was rejected without an actionable reason"
else
    pass
fi

test_start "workflow host verification has an enforceable timeout"
timeout_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-timeout.XXXXXX")"
timeout_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-timeout-agent.XXXXXX")"
p0p4_register_cleanup "$timeout_repo" "$timeout_agent_bin"
init_runtime_repo "$timeout_repo" runtime-timeout
timeout_survival_file="$runtime_output_dir/timeout-child-survived.txt"
add_verifier "$timeout_repo" verify-slow.sh 'trap "" TERM; (sleep 3; printf "survived\n" >"${TIMEOUT_SURVIVAL_FILE:?}") & wait'
write_runtime_brief "$timeout_repo" runtime-timeout 1 alpha none ./verify-slow.sh
make_fake_done_agent "$timeout_agent_bin"
timeout_out="$runtime_output_dir/timeout.out"
timeout_err="$runtime_output_dir/timeout.err"
timeout_started="$(date +%s)"
timeout_exit=0
PATH="$timeout_agent_bin:$PATH" HOST_VERIFY_TIMEOUT_SECONDS=1 TIMEOUT_SURVIVAL_FILE="$timeout_survival_file" bash "$workflow/scripts/run-agents.sh" --briefs "$timeout_repo/briefs" --repo "$timeout_repo" --agent codex >"$timeout_out" 2>"$timeout_err" || timeout_exit=$?
timeout_elapsed=$(( $(date +%s) - timeout_started ))
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
    [[ -e "$timeout_survival_file" ]] && break
    sleep 0.1
done
if [[ "$timeout_exit" -eq 0 ]]; then
    fail "host verifier ignored HOST_VERIFY_TIMEOUT_SECONDS and accepted a command beyond its deadline"
elif [[ "$timeout_elapsed" -ge 3 ]]; then
    fail "host verifier timeout did not stop the command promptly (${timeout_elapsed}s elapsed for a 1s limit)"
elif [[ -e "$timeout_survival_file" ]]; then
    fail "host verifier timeout left a child process running after the deadline"
elif ! grep -Eqi 'timed out|timeout|deadline' "$timeout_out" "$timeout_err"; then
    fail "host verifier timeout failure was not actionable"
else
    pass
fi

test_start "workflow agent logs are private bounded and cannot follow pre-existing symlinks"
agent_log_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-agent-log.XXXXXX")"
agent_log_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-agent-log-agent.XXXXXX")"
p0p4_register_cleanup "$agent_log_repo" "$agent_log_agent_bin"
init_runtime_repo "$agent_log_repo" runtime-agent-log
add_verifier "$agent_log_repo" verify-pass.sh 'exit 0'
write_runtime_brief "$agent_log_repo" runtime-agent-log 1 alpha none ./verify-pass.sh
make_fake_done_agent "$agent_log_agent_bin"
mkdir -p "$agent_log_repo/briefs/logs"
agent_log_sentinel="$runtime_output_dir/agent-log-sentinel.txt"
printf 'preserve agent log target\n' >"$agent_log_sentinel"
ln -s "$agent_log_sentinel" "$agent_log_repo/briefs/logs/slice-1-alpha.log"
agent_log_out="$runtime_output_dir/agent-log.out"
agent_log_err="$runtime_output_dir/agent-log.err"
agent_log_exit=0
PATH="$agent_log_agent_bin:$PATH" AGENT_LOG_MAX_BYTES=4096 bash "$workflow/scripts/run-agents.sh" --briefs "$agent_log_repo/briefs" --repo "$agent_log_repo" --agent codex >"$agent_log_out" 2>"$agent_log_err" || agent_log_exit=$?

noisy_log_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-noisy-agent-log.XXXXXX")"
noisy_log_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-noisy-agent.XXXXXX")"
p0p4_register_cleanup "$noisy_log_repo" "$noisy_log_agent_bin"
init_runtime_repo "$noisy_log_repo" runtime-noisy-agent-log
add_verifier "$noisy_log_repo" verify-pass.sh 'exit 0'
write_runtime_brief "$noisy_log_repo" runtime-noisy-agent-log 1 alpha none ./verify-pass.sh
make_fake_noisy_agent "$noisy_log_agent_bin"
noisy_log_out="$runtime_output_dir/noisy-agent-log.out"
noisy_log_err="$runtime_output_dir/noisy-agent-log.err"
noisy_log_exit=0
PATH="$noisy_log_agent_bin:$PATH" AGENT_LOG_MAX_BYTES=4096 bash "$workflow/scripts/run-agents.sh" --briefs "$noisy_log_repo/briefs" --repo "$noisy_log_repo" --agent codex >"$noisy_log_out" 2>"$noisy_log_err" || noisy_log_exit=$?
noisy_log_file="$noisy_log_repo/briefs/logs/slice-1-alpha.log"
if [[ "$agent_log_exit" -ne 0 ]]; then
    fail "safe publication rejected a normal agent log: stdout=$(tr '\n' ' ' <"$agent_log_out") stderr=$(tr '\n' ' ' <"$agent_log_err")"
elif [[ "$(cat "$agent_log_sentinel")" != "preserve agent log target" ]]; then
    fail "agent output followed a pre-existing log symlink and overwrote its target"
elif [[ "$noisy_log_exit" -eq 0 ]]; then
    fail "agent output beyond AGENT_LOG_MAX_BYTES was not stopped fail-closed"
elif [[ -f "$noisy_log_file" && "$(wc -c <"$noisy_log_file" | tr -d ' ')" -gt 4096 ]]; then
    fail "published noisy agent log exceeded AGENT_LOG_MAX_BYTES"
else
    pass
fi

test_start "workflow runtime uses private verifier capture and argv-safe integration commands"
runtime_script="$workflow/scripts/run-agents.sh"
integration_script="$workflow/scripts/check-integration.sh"
if rg -q 'raw_log=.*\.raw\.\$\$' "$runtime_script"; then
    fail "host verifier raw log path is predictable instead of privately created"
elif ! rg -q 'raw_log=.*mktemp|mktemp.*raw_log' "$runtime_script"; then
    fail "host verifier does not create raw capture with mktemp"
elif rg -q 'read[[:space:]]+-ra[[:space:]]+(build_arr|test_arr)' "$integration_script"; then
    fail "check-integration.sh reparses build/test command strings and loses argv boundaries"
elif rg -q '(^|[^[:alnum:]_])eval([[:space:](]|$)|(^|[[:space:]])(bash|sh)[[:space:]]+-c([[:space:]]|$)' "$integration_script"; then
    fail "check-integration.sh uses shell reparsing for validation commands"
else
    pass
fi

test_start "workflow baseline validation uses canonical argv without shell-string reparsing"
if grep -Fq 'BASELINE_TEST_CMD' "$runtime_script"; then
    fail "run-agents.sh still accepts shell-form BASELINE_TEST_CMD"
elif rg -q 'read[[:space:]]+-ra[[:space:]]+test_cmd_arr' "$runtime_script"; then
    fail "run-agents.sh reparses baseline validation through shell word splitting"
elif ! grep -Fq 'BASELINE_TEST_ARGV' "$runtime_script"; then
    fail "run-agents.sh has no canonical baseline argv configuration"
else
    pass
fi

test_start "workflow fails closed when worktree storage is not already gitignored"
gitignore_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-gitignore.XXXXXX")"
p0p4_register_cleanup "$gitignore_repo"
init_runtime_repo "$gitignore_repo" runtime-gitignore
printf 'fixture\n' >"$gitignore_repo/.gitignore"
git -C "$gitignore_repo" add .gitignore
git -C "$gitignore_repo" commit -q -m "remove worktree ignore"
mkdir -p "$gitignore_repo/.worktrees"
add_verifier "$gitignore_repo" verify-pass.sh 'exit 0'
write_runtime_brief "$gitignore_repo" runtime-gitignore 1 alpha none ./verify-pass.sh
gitignore_before="$(cat "$gitignore_repo/.gitignore")"
gitignore_out="$runtime_output_dir/gitignore.out"
gitignore_err="$runtime_output_dir/gitignore.err"
if bash "$workflow/scripts/run-agents.sh" --briefs "$gitignore_repo/briefs" --repo "$gitignore_repo" --parallel --worktrees-dir "$gitignore_repo/.worktrees" --dry-run >"$gitignore_out" 2>"$gitignore_err"; then
    fail "parallel runner accepted worktree storage that is not gitignored"
elif [[ "$(cat "$gitignore_repo/.gitignore")" != "$gitignore_before" ]]; then
    fail "parallel safety gate mutated .gitignore instead of failing with an actionable instruction"
elif ! grep -Eqi 'gitignore|gitignored|check-ignore' "$gitignore_out" "$gitignore_err"; then
    fail "worktree ignore rejection was not actionable"
else
    pass
fi

test_start "workflow rejects lying DONE pass when host verification fails"
lying_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-lying.XXXXXX")"
lying_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-lying-agent.XXXXXX")"
p0p4_register_cleanup "$lying_repo" "$lying_agent_bin"
init_runtime_repo "$lying_repo" runtime-lying
add_verifier "$lying_repo" verify-fail.sh 'exit 23'
write_runtime_brief "$lying_repo" runtime-lying 1 alpha none ./verify-fail.sh
make_fake_done_agent "$lying_agent_bin"
lying_out="$runtime_output_dir/lying.out"
lying_err="$runtime_output_dir/lying.err"
if PATH="$lying_agent_bin:$PATH" bash "$workflow/scripts/run-agents.sh" --briefs "$lying_repo/briefs" --repo "$lying_repo" --agent codex >"$lying_out" 2>"$lying_err"; then
    fail "run-agents.sh accepted agent-reported DONE/pass even though the host verification command exits 23"
elif git -C "$lying_repo" show "feature/runtime-lying/integration:alpha-marker.txt" >/dev/null 2>&1; then
    fail "failed host verification was merged into integration"
elif ! grep -Eqi 'host verification|verification command.*fail|FAILED_VERIFICATION' "$lying_out" "$lying_err"; then
    fail "host verification failure was not reported as the rejection reason"
else
    pass
fi

test_start "workflow rejects verifier HEAD mutation"
mutation_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-head-mutation.XXXXXX")"
mutation_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-head-mutation-agent.XXXXXX")"
p0p4_register_cleanup "$mutation_repo" "$mutation_agent_bin"
init_runtime_repo "$mutation_repo" runtime-head-mutation
add_verifier "$mutation_repo" verify-mutates-head.sh 'printf "verifier mutation\n" >verifier-mutation.txt; git add verifier-mutation.txt; git commit -q -m "verifier mutated HEAD"'
write_runtime_brief "$mutation_repo" runtime-head-mutation 1 alpha none ./verify-mutates-head.sh
make_fake_done_agent "$mutation_agent_bin"
mutation_out="$runtime_output_dir/mutation.out"
mutation_err="$runtime_output_dir/mutation.err"
if PATH="$mutation_agent_bin:$PATH" bash "$workflow/scripts/run-agents.sh" --briefs "$mutation_repo/briefs" --repo "$mutation_repo" --agent codex >"$mutation_out" 2>"$mutation_err"; then
    fail "run-agents.sh accepted a verifier that changed the slice HEAD"
elif git -C "$mutation_repo" show "feature/runtime-head-mutation/integration:verifier-mutation.txt" >/dev/null 2>&1; then
    fail "verifier-created HEAD mutation reached integration"
elif ! grep -Eqi 'HEAD.*(changed|mutat)|mutat.*HEAD' "$mutation_out" "$mutation_err"; then
    fail "HEAD mutation rejection did not identify the immutable verifier boundary"
else
    pass
fi

test_start "workflow host verification is bound to the expected slice worktree HEAD"
wrong_head_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-wrong-head.XXXXXX")"
wrong_head_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-wrong-head-agent.XXXXXX")"
p0p4_register_cleanup "$wrong_head_repo" "$wrong_head_agent_bin"
init_runtime_repo "$wrong_head_repo" runtime-wrong-head
add_verifier "$wrong_head_repo" verify-pass.sh 'exit 0'
write_runtime_brief "$wrong_head_repo" runtime-wrong-head 1 alpha none ./verify-pass.sh
make_fake_detaching_agent "$wrong_head_agent_bin"
wrong_head_out="$runtime_output_dir/wrong-head.out"
wrong_head_err="$runtime_output_dir/wrong-head.err"
if PATH="$wrong_head_agent_bin:$PATH" DETACH_TO_PARENT=true bash "$workflow/scripts/run-agents.sh" --briefs "$wrong_head_repo/briefs" --repo "$wrong_head_repo" --agent codex >"$wrong_head_out" 2>"$wrong_head_err"; then
    fail "run-agents.sh verified a clean parent checkout instead of the expected slice branch tip"
elif git -C "$wrong_head_repo" show "feature/runtime-wrong-head/integration:alpha-marker.txt" >/dev/null 2>&1; then
    fail "slice output reached integration after a different worktree HEAD was host verified"
elif ! grep -Eqi 'expected.*(branch|commit|HEAD)|HEAD.*(branch|commit|mismatch)|worktree.*HEAD' "$wrong_head_out" "$wrong_head_err"; then
    fail "wrong-worktree-HEAD rejection did not identify the expected slice commit binding"
else
    pass
fi

test_start "workflow merges the exact immutable commit that passed host verification"
ref_binding_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-ref-binding.XXXXXX")"
ref_binding_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-ref-binding-agent.XXXXXX")"
p0p4_register_cleanup "$ref_binding_repo" "$ref_binding_agent_bin"
init_runtime_repo "$ref_binding_repo" runtime-ref-binding
add_verifier "$ref_binding_repo" verify-moves-slice-ref.sh 'git update-ref refs/heads/feature/runtime-ref-binding/slice-alpha "${MUTATED_COMMIT:?}"'
printf 'unverified ref target\n' >"$ref_binding_repo/unverified-target.txt"
git -C "$ref_binding_repo" add unverified-target.txt
git -C "$ref_binding_repo" commit -q -m "unverified alternate target"
mutated_commit="$(git -C "$ref_binding_repo" rev-parse HEAD)"
write_runtime_brief "$ref_binding_repo" runtime-ref-binding 1 alpha none ./verify-moves-slice-ref.sh
make_fake_detaching_agent "$ref_binding_agent_bin"
ref_binding_out="$runtime_output_dir/ref-binding.out"
ref_binding_err="$runtime_output_dir/ref-binding.err"
if PATH="$ref_binding_agent_bin:$PATH" MUTATED_COMMIT="$mutated_commit" bash "$workflow/scripts/run-agents.sh" --briefs "$ref_binding_repo/briefs" --repo "$ref_binding_repo" --agent codex >"$ref_binding_out" 2>"$ref_binding_err"; then
    fail "run-agents.sh accepted a moved slice ref and merged a commit that did not pass host verification"
elif git -C "$ref_binding_repo" show "feature/runtime-ref-binding/integration:unverified-target.txt" >/dev/null 2>&1; then
    fail "the ref target substituted after verification reached integration"
elif grep -Fq "Host-verified slice 'alpha'" "$ref_binding_out" && ! grep -Eqi 'ref.*(changed|mutat)|commit.*(changed|mismatch)' "$ref_binding_out" "$ref_binding_err"; then
    fail "slice ref mutation was detected only after an invalid Host-verified claim"
else
    pass
fi

test_start "workflow promotion uses compare-and-swap against the verified integration base"
promotion_cas_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-promotion-cas.XXXXXX")"
promotion_cas_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-promotion-cas-agent.XXXXXX")"
p0p4_register_cleanup "$promotion_cas_repo" "$promotion_cas_agent_bin"
init_runtime_repo "$promotion_cas_repo" runtime-promotion-cas
add_verifier "$promotion_cas_repo" verify-pass.sh 'exit 0'
printf 'concurrent integration target\n' >"$promotion_cas_repo/concurrent-target.txt"
git -C "$promotion_cas_repo" add concurrent-target.txt
git -C "$promotion_cas_repo" commit -q -m "concurrent integration target"
promotion_concurrent_commit="$(git -C "$promotion_cas_repo" rev-parse HEAD)"
write_runtime_brief "$promotion_cas_repo" runtime-promotion-cas 1 alpha none ./verify-pass.sh
make_fake_done_agent "$promotion_cas_agent_bin"
promotion_git_dir="$(git -C "$promotion_cas_repo" rev-parse --git-dir)"
if [[ "$promotion_git_dir" != /* ]]; then
    promotion_git_dir="$promotion_cas_repo/$promotion_git_dir"
fi
promotion_hooks_dir="$promotion_git_dir/hooks"
mkdir -p "$promotion_hooks_dir"
cat >"$promotion_hooks_dir/post-merge" <<HOOK
#!/usr/bin/env bash
git update-ref refs/heads/feature/runtime-promotion-cas/integration "$promotion_concurrent_commit"
HOOK
chmod +x "$promotion_hooks_dir/post-merge"
promotion_cas_out="$runtime_output_dir/promotion-cas.out"
promotion_cas_err="$runtime_output_dir/promotion-cas.err"
promotion_cas_exit=0
PATH="$promotion_cas_agent_bin:$PATH" bash "$workflow/scripts/run-agents.sh" --briefs "$promotion_cas_repo/briefs" --repo "$promotion_cas_repo" --agent codex >"$promotion_cas_out" 2>"$promotion_cas_err" || promotion_cas_exit=$?
if [[ "$promotion_cas_exit" -eq 0 ]]; then
    fail "run-agents.sh marked a slice successful after the integration ref changed during promotion"
elif [[ "$(git -C "$promotion_cas_repo" rev-parse feature/runtime-promotion-cas/integration)" != "$promotion_concurrent_commit" ]]; then
    fail "promotion did not preserve the concurrent integration ref target after compare-and-swap rejection: actual=$(git -C "$promotion_cas_repo" rev-parse feature/runtime-promotion-cas/integration) expected=$promotion_concurrent_commit stdout=$(tr '\n' ' ' <"$promotion_cas_out") stderr=$(tr '\n' ' ' <"$promotion_cas_err")"
elif git -C "$promotion_cas_repo" show "feature/runtime-promotion-cas/integration:alpha-marker.txt" >/dev/null 2>&1; then
    fail "verified slice output replaced a concurrently moved integration base"
elif ! grep -Eqi 'compare-and-swap|changed.*integration|integration.*changed|ref.*changed' "$promotion_cas_out" "$promotion_cas_err"; then
    fail "concurrent integration movement was rejected without an actionable promotion reason"
else
    pass
fi

test_start "workflow parallel success is host verified before merge and VERIFIED state"
parallel_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-parallel.XXXXXX")"
parallel_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-parallel-agent.XXXXXX")"
p0p4_register_cleanup "$parallel_repo" "$parallel_agent_bin"
init_runtime_repo "$parallel_repo" runtime-parallel
add_verifier "$parallel_repo" verify-record.sh 'printf "%s\n" "$PWD" >>"${HOST_VERIFIER_RECORD:?}"'
write_runtime_brief "$parallel_repo" runtime-parallel 1 alpha none ./verify-record.sh
make_fake_done_agent "$parallel_agent_bin"
parallel_record="$runtime_output_dir/parallel-record.txt"
parallel_out="$runtime_output_dir/parallel.out"
parallel_err="$runtime_output_dir/parallel.err"
if ! PATH="$parallel_agent_bin:$PATH" HOST_VERIFIER_RECORD="$parallel_record" bash "$workflow/scripts/run-agents.sh" --briefs "$parallel_repo/briefs" --repo "$parallel_repo" --agent codex --parallel --worktrees-dir "$parallel_repo/.worktrees" >"$parallel_out" 2>"$parallel_err"; then
    fail "parallel passing slice was rejected: $(tr '\n' ' ' <"$parallel_err")"
elif [[ ! -s "$parallel_record" ]]; then
    fail "parallel DONE/pass slice was not host verified"
elif ! git -C "$parallel_repo" show "feature/runtime-parallel/integration:alpha-marker.txt" >/dev/null 2>&1; then
    fail "parallel slice was not merged after host verification"
elif ! grep -Fq "Host-verified slice 'alpha'" "$parallel_out"; then
    fail "parallel slice did not record host-verified evidence before VERIFIED/merge state"
else
    pass
fi

test_start "workflow waits for every parallel child before host verification or merge"
quiescence_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-quiescence.XXXXXX")"
quiescence_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-quiescence-agent.XXXXXX")"
p0p4_register_cleanup "$quiescence_repo" "$quiescence_agent_bin"
init_runtime_repo "$quiescence_repo" runtime-quiescence
add_verifier "$quiescence_repo" verify-quiescent.sh 'if [[ -e "${PARALLEL_ACTIVE_FILE:?}" ]]; then echo "another agent is still active" >&2; exit 42; fi'
write_runtime_brief "$quiescence_repo" runtime-quiescence 1 alpha none ./verify-quiescent.sh
write_runtime_brief "$quiescence_repo" runtime-quiescence 2 beta none ./verify-quiescent.sh
make_fake_quiescence_agent "$quiescence_agent_bin"
quiescence_active_file="$runtime_output_dir/quiescence-agent-active"
quiescence_out="$runtime_output_dir/quiescence.out"
quiescence_err="$runtime_output_dir/quiescence.err"
if ! PATH="$quiescence_agent_bin:$PATH" PARALLEL_ACTIVE_FILE="$quiescence_active_file" bash "$workflow/scripts/run-agents.sh" --briefs "$quiescence_repo/briefs" --repo "$quiescence_repo" --agent codex --parallel --worktrees-dir "$quiescence_repo/.worktrees" >"$quiescence_out" 2>"$quiescence_err"; then
    fail "parallel host verification began before all children were quiescent: $(tr '\n' ' ' <"$quiescence_err")"
elif [[ -e "$quiescence_active_file" ]]; then
    fail "parallel runner returned while a child-agent active marker remained"
elif ! git -C "$quiescence_repo" show "feature/runtime-quiescence/integration:alpha-marker.txt" >/dev/null 2>&1 \
    || ! git -C "$quiescence_repo" show "feature/runtime-quiescence/integration:beta-marker.txt" >/dev/null 2>&1; then
    fail "quiescent independently verified parallel outputs were not both merged"
else
    pass
fi

test_start "workflow cleanup removes only clean worktrees created by this invocation"
cleanup_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-cleanup.XXXXXX")"
cleanup_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-cleanup-agent.XXXXXX")"
p0p4_register_cleanup "$cleanup_repo" "$cleanup_agent_bin"
init_runtime_repo "$cleanup_repo" runtime-cleanup
add_verifier "$cleanup_repo" verify-pass.sh 'exit 0'
git -C "$cleanup_repo" branch preserved-worktree feature/runtime-cleanup/integration
mkdir -p "$cleanup_repo/.worktrees"
git -C "$cleanup_repo" worktree add -q "$cleanup_repo/.worktrees/preserved" preserved-worktree
printf 'dirty recovery evidence\n' >"$cleanup_repo/.worktrees/preserved/recovery.txt"
write_runtime_brief "$cleanup_repo" runtime-cleanup 1 alpha none ./verify-pass.sh
make_fake_done_agent "$cleanup_agent_bin"
cleanup_out="$runtime_output_dir/cleanup.out"
cleanup_err="$runtime_output_dir/cleanup.err"
if ! PATH="$cleanup_agent_bin:$PATH" bash "$workflow/scripts/run-agents.sh" --briefs "$cleanup_repo/briefs" --repo "$cleanup_repo" --agent codex --parallel --cleanup --worktrees-dir "$cleanup_repo/.worktrees" >"$cleanup_out" 2>"$cleanup_err"; then
    fail "parallel cleanup fixture failed before cleanup ownership could be checked: $(tr '\n' ' ' <"$cleanup_err")"
elif [[ ! -d "$cleanup_repo/.worktrees/preserved" || ! -f "$cleanup_repo/.worktrees/preserved/recovery.txt" ]]; then
    fail "--cleanup force-removed a pre-existing dirty worktree and its recovery evidence"
elif ! git -C "$cleanup_repo" worktree list --porcelain | grep -Fq "worktree $(cd "$cleanup_repo/.worktrees/preserved" && pwd -P)"; then
    fail "--cleanup unregistered a pre-existing worktree"
elif [[ -d "$cleanup_repo/.worktrees/alpha" ]]; then
    fail "--cleanup did not remove the clean alpha worktree created by this invocation"
else
    pass
fi

test_start "workflow cleanup preserves a pre-existing slice worktree referenced by a relative path"
relative_cleanup_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-relative-cleanup.XXXXXX")"
relative_cleanup_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-relative-cleanup-agent.XXXXXX")"
p0p4_register_cleanup "$relative_cleanup_repo" "$relative_cleanup_agent_bin"
init_runtime_repo "$relative_cleanup_repo" runtime-relative-cleanup
add_verifier "$relative_cleanup_repo" verify-pass.sh 'exit 0'
git -C "$relative_cleanup_repo" branch feature/runtime-relative-cleanup/slice-alpha feature/runtime-relative-cleanup/integration
mkdir -p "$relative_cleanup_repo/.worktrees"
git -C "$relative_cleanup_repo" worktree add -q "$relative_cleanup_repo/.worktrees/alpha" feature/runtime-relative-cleanup/slice-alpha
RUNTIME_WORKTREE_HINT=.worktrees/alpha write_runtime_brief "$relative_cleanup_repo" runtime-relative-cleanup 1 alpha none ./verify-pass.sh
make_fake_done_agent "$relative_cleanup_agent_bin"
relative_cleanup_out="$runtime_output_dir/relative-cleanup.out"
relative_cleanup_err="$runtime_output_dir/relative-cleanup.err"
if ! (cd "$relative_cleanup_repo" && PATH="$relative_cleanup_agent_bin:$PATH" bash "$workflow/scripts/run-agents.sh" --briefs briefs --repo . --agent codex --parallel --cleanup --worktrees-dir .worktrees >"$relative_cleanup_out" 2>"$relative_cleanup_err"); then
    fail "relative pre-existing worktree fixture failed: $(tr '\n' ' ' <"$relative_cleanup_err")"
elif [[ ! -d "$relative_cleanup_repo/.worktrees/alpha" ]]; then
    fail "--cleanup removed a pre-existing clean slice worktree after comparing relative and absolute path forms"
elif ! git -C "$relative_cleanup_repo" worktree list --porcelain | grep -Fq "worktree $(cd "$relative_cleanup_repo/.worktrees/alpha" && pwd -P)"; then
    fail "--cleanup unregistered the pre-existing relative slice worktree"
else
    pass
fi

test_start "workflow external verified and skip-first prerequisites require briefs and host re-verification"
external_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-external.XXXXXX")"
external_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-external-agent.XXXXXX")"
skip_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-skip-first.XXXXXX")"
p0p4_register_cleanup "$external_repo" "$external_agent_bin" "$skip_repo"
make_fake_done_agent "$external_agent_bin"
init_runtime_repo "$external_repo" runtime-external
add_verifier "$external_repo" verify-pass.sh 'exit 0'
prepare_external_alpha "$external_repo" runtime-external
write_runtime_brief "$external_repo" runtime-external 2 beta alpha ./verify-pass.sh
external_out="$runtime_output_dir/external.out"
external_err="$runtime_output_dir/external.err"

init_runtime_repo "$skip_repo" runtime-skip-first
add_verifier "$skip_repo" verify-pass.sh 'exit 0'
add_verifier "$skip_repo" verify-prereq-fail.sh 'exit 31'
prepare_external_alpha "$skip_repo" runtime-skip-first
write_runtime_brief "$skip_repo" runtime-skip-first 1 alpha none ./verify-prereq-fail.sh
write_runtime_brief "$skip_repo" runtime-skip-first 2 beta alpha ./verify-pass.sh
skip_out="$runtime_output_dir/skip-first.out"
skip_err="$runtime_output_dir/skip-first.err"

if PATH="$external_agent_bin:$PATH" bash "$workflow/scripts/run-agents.sh" --briefs "$external_repo/briefs" --repo "$external_repo" --agent codex --verified-slices alpha >"$external_out" 2>"$external_err"; then
    fail "--verified-slices accepted external prerequisite alpha without its strict slice brief"
elif ! grep -Eqi 'brief.*alpha|alpha.*brief' "$external_out" "$external_err"; then
    fail "missing external prerequisite brief rejection was not actionable"
elif PATH="$external_agent_bin:$PATH" bash "$workflow/scripts/run-agents.sh" --briefs "$skip_repo/briefs" --repo "$skip_repo" --agent codex --skip-first >"$skip_out" 2>"$skip_err"; then
    fail "--skip-first trusted merged ancestry without re-running alpha host verification"
elif git -C "$skip_repo" show-ref --verify --quiet "refs/heads/feature/runtime-skip-first/slice-beta"; then
    fail "dependent beta launched after skipped alpha failed host re-verification"
elif ! grep -Eqi 'host verification|verification command.*fail|FAILED_VERIFICATION' "$skip_out" "$skip_err"; then
    fail "skipped prerequisite host re-verification failure was not reported"
else
    pass
fi

test_start "workflow re-verifies external prerequisites on the snapshotted integration commit"
external_integration_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-external-integration.XXXXXX")"
external_integration_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-external-integration-agent.XXXXXX")"
p0p4_register_cleanup "$external_integration_repo" "$external_integration_agent_bin"
init_runtime_repo "$external_integration_repo" runtime-external-integration
add_verifier "$external_integration_repo" verify-prerequisite.sh 'grep -qx good prerequisite-state.txt'
add_verifier "$external_integration_repo" verify-pass.sh 'exit 0'
printf 'good\n' >"$external_integration_repo/prerequisite-state.txt"
git -C "$external_integration_repo" add prerequisite-state.txt
git -C "$external_integration_repo" commit -q -m "good prerequisite state"
git -C "$external_integration_repo" branch -f feature/runtime-external-integration/integration HEAD
prepare_external_alpha "$external_integration_repo" runtime-external-integration
write_runtime_brief "$external_integration_repo" runtime-external-integration 1 alpha none ./verify-prerequisite.sh
write_runtime_brief "$external_integration_repo" runtime-external-integration 2 beta alpha ./verify-pass.sh
printf 'regressed\n' >"$external_integration_repo/prerequisite-state.txt"
git -C "$external_integration_repo" add prerequisite-state.txt
git -C "$external_integration_repo" commit -q -m "regress prerequisite on integration"
make_fake_done_agent "$external_integration_agent_bin"
external_integration_out="$runtime_output_dir/external-integration.out"
external_integration_err="$runtime_output_dir/external-integration.err"
if PATH="$external_integration_agent_bin:$PATH" bash "$workflow/scripts/run-agents.sh" --briefs "$external_integration_repo/briefs" --repo "$external_integration_repo" --agent codex --verified-slices alpha >"$external_integration_out" 2>"$external_integration_err"; then
    fail "external prerequisite proof passed on the old slice branch although its verifier fails on current integration"
elif git -C "$external_integration_repo" show-ref --verify --quiet refs/heads/feature/runtime-external-integration/slice-beta; then
    fail "dependent beta launched before alpha was re-verified on the current integration commit"
elif ! grep -Eqi 'external.*(integration|prerequisite)|host verification.*fail|FAILED_VERIFICATION' "$external_integration_out" "$external_integration_err"; then
    fail "stale external prerequisite rejection did not identify current integration verification"
else
    pass
fi

prepare_integration_repo() {
    local repo="$1"
    local task="$2"

    init_runtime_repo "$repo" "$task"
    git -C "$repo" checkout -q -b "feature/${task}/slice-alpha" "feature/${task}/integration"
    printf 'slice output\n' >"$repo/alpha.txt"
    git -C "$repo" add alpha.txt
    git -C "$repo" commit -q -m "alpha output"
    git -C "$repo" checkout -q "feature/${task}/integration"
}

test_start "workflow integration readiness is fail-closed with explicit branch-only skips and verdict-free dry-run"
integration_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-integration.XXXXXX")"
p0p4_register_cleanup "$integration_repo"
prepare_integration_repo "$integration_repo" runtime-integration
integration_missing_out="$runtime_output_dir/integration-missing.out"
integration_missing_err="$runtime_output_dir/integration-missing.err"
integration_skip_out="$runtime_output_dir/integration-skip.out"
integration_skip_err="$runtime_output_dir/integration-skip.err"
integration_blank_out="$runtime_output_dir/integration-blank.out"
integration_blank_err="$runtime_output_dir/integration-blank.err"
integration_legacy_out="$runtime_output_dir/integration-legacy.out"
integration_legacy_err="$runtime_output_dir/integration-legacy.err"
integration_dry_out="$runtime_output_dir/integration-dry.out"
integration_dry_err="$runtime_output_dir/integration-dry.err"

if (cd "$integration_repo" && bash "$workflow/scripts/check-integration.sh" --integration-branch feature/runtime-integration/integration >"$integration_missing_out" 2>"$integration_missing_err"); then
    fail "check-integration.sh reported readiness when neither build nor test validation command existed"
elif ! grep -Eqi 'no (build|test|validation) command|validation.*required' "$integration_missing_out" "$integration_missing_err"; then
    fail "missing validation command failure was not actionable"
elif ! (cd "$integration_repo" && bash "$workflow/scripts/check-integration.sh" --integration-branch feature/runtime-integration/integration --skip-validation "branch-only fixture" >"$integration_skip_out" 2>"$integration_skip_err"); then
    fail "check-integration.sh rejected explicit nonblank --skip-validation reason: $(tr '\n' ' ' <"$integration_skip_err")"
elif ! grep -Fq 'BRANCH-ONLY' "$integration_skip_out" || ! grep -Fq 'branch-only fixture' "$integration_skip_out"; then
    fail "explicit validation skip did not yield a reasoned BRANCH-ONLY result"
elif (cd "$integration_repo" && bash "$workflow/scripts/check-integration.sh" --integration-branch feature/runtime-integration/integration --skip-validation "   " >"$integration_blank_out" 2>"$integration_blank_err"); then
    fail "check-integration.sh accepted a blank validation skip reason"
elif (cd "$integration_repo" && bash "$workflow/scripts/check-integration.sh" --integration-branch feature/runtime-integration/integration --skip-build >"$integration_legacy_out" 2>"$integration_legacy_err"); then
    fail "check-integration.sh still accepts legacy bare --skip-build"
elif ! (cd "$integration_repo" && bash "$workflow/scripts/check-integration.sh" --integration-branch feature/runtime-integration/integration --dry-run >"$integration_dry_out" 2>"$integration_dry_err"); then
    fail "check-integration.sh dry-run failed: $(tr '\n' ' ' <"$integration_dry_err")"
elif grep -Eq 'READY for integration|READY with warnings|NOT READY for integration' "$integration_dry_out"; then
    fail "check-integration.sh dry-run emitted a readiness verdict"
else
    pass
fi

test_start "workflow integration check preserves and rejects a dirty caller worktree"
dirty_integration_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-dirty-integration.XXXXXX")"
p0p4_register_cleanup "$dirty_integration_repo"
prepare_integration_repo "$dirty_integration_repo" runtime-dirty-integration
printf 'local dirty sentinel\n' >"$dirty_integration_repo/README.md"
dirty_before_status="$(git -C "$dirty_integration_repo" status --porcelain --untracked-files=all)"
dirty_before_branch="$(git -C "$dirty_integration_repo" branch --show-current)"
dirty_integration_out="$runtime_output_dir/dirty-integration.out"
dirty_integration_err="$runtime_output_dir/dirty-integration.err"
dirty_integration_exit=0
(cd "$dirty_integration_repo" && bash "$workflow/scripts/check-integration.sh" --integration-branch feature/runtime-dirty-integration/integration --skip-validation "dirty preservation fixture" >"$dirty_integration_out" 2>"$dirty_integration_err") || dirty_integration_exit=$?
if [[ "$(cat "$dirty_integration_repo/README.md")" != "local dirty sentinel" ]] \
    || [[ "$(git -C "$dirty_integration_repo" status --porcelain --untracked-files=all)" != "$dirty_before_status" ]] \
    || [[ "$(git -C "$dirty_integration_repo" branch --show-current)" != "$dirty_before_branch" ]]; then
    fail "check-integration.sh mutated or discarded the caller's dirty worktree state"
elif [[ "$dirty_integration_exit" -eq 0 ]]; then
    fail "check-integration.sh did not reject a dirty caller worktree before readiness mutation"
elif ! grep -Eqi 'dirty|uncommitted|working tree.*clean' "$dirty_integration_out" "$dirty_integration_err"; then
    fail "dirty worktree rejection was not actionable"
else
    pass
fi

test_start "workflow integration check uses collision-safe non-mutating temporary state"
collision_integration_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-integration-collision.XXXXXX")"
collision_date_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-date-bin.XXXXXX")"
p0p4_register_cleanup "$collision_integration_repo" "$collision_date_bin"
prepare_integration_repo "$collision_integration_repo" runtime-integration-collision
cat >"$collision_date_bin/date" <<'DATE'
#!/usr/bin/env sh
printf '424242\n'
DATE
chmod +x "$collision_date_bin/date"
git -C "$collision_integration_repo" branch __integration-check-424242 feature/runtime-integration-collision/integration
collision_branch_before="$(git -C "$collision_integration_repo" rev-parse __integration-check-424242)"
collision_original_branch="$(git -C "$collision_integration_repo" branch --show-current)"
collision_integration_out="$runtime_output_dir/integration-collision.out"
collision_integration_err="$runtime_output_dir/integration-collision.err"
if ! (cd "$collision_integration_repo" && PATH="$collision_date_bin:$PATH" bash "$workflow/scripts/check-integration.sh" --integration-branch feature/runtime-integration-collision/integration --skip-validation "collision fixture" >"$collision_integration_out" 2>"$collision_integration_err"); then
    fail "check-integration.sh collided with predictable temporary branch state: $(tr '\n' ' ' <"$collision_integration_err")"
elif ! git -C "$collision_integration_repo" show-ref --verify --quiet refs/heads/__integration-check-424242; then
    fail "check-integration.sh cleanup deleted a pre-existing branch with its temporary-name pattern"
elif [[ "$(git -C "$collision_integration_repo" rev-parse __integration-check-424242)" != "$collision_branch_before" ]]; then
    fail "check-integration.sh mutated a pre-existing temporary-name branch"
elif [[ "$(git -C "$collision_integration_repo" branch --show-current)" != "$collision_original_branch" ]]; then
    fail "check-integration.sh did not restore the caller's original branch"
else
    pass
fi

test_start "workflow integration validation rejects mutation of the cumulative merge candidate"
mutating_validation_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-mutating-validation.XXXXXX")"
p0p4_register_cleanup "$mutating_validation_repo"
init_runtime_repo "$mutating_validation_repo" runtime-mutating-validation
cat >"$mutating_validation_repo/mutate-candidate.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
git reset --hard -q HEAD^
SCRIPT
chmod +x "$mutating_validation_repo/mutate-candidate.sh"
git -C "$mutating_validation_repo" add mutate-candidate.sh
git -C "$mutating_validation_repo" commit -q -m "add mutating validation fixture"
git -C "$mutating_validation_repo" branch -f feature/runtime-mutating-validation/integration HEAD
git -C "$mutating_validation_repo" checkout -q -b feature/runtime-mutating-validation/slice-alpha feature/runtime-mutating-validation/integration
printf 'slice output\n' >"$mutating_validation_repo/alpha.txt"
git -C "$mutating_validation_repo" add alpha.txt
git -C "$mutating_validation_repo" commit -q -m "alpha output"
git -C "$mutating_validation_repo" checkout -q feature/runtime-mutating-validation/integration
mutating_validation_out="$runtime_output_dir/mutating-validation.out"
mutating_validation_err="$runtime_output_dir/mutating-validation.err"
mutating_validation_exit=0
(cd "$mutating_validation_repo" && bash "$workflow/scripts/check-integration.sh" --integration-branch feature/runtime-mutating-validation/integration --test-arg ./mutate-candidate.sh >"$mutating_validation_out" 2>"$mutating_validation_err") || mutating_validation_exit=$?
if [[ "$mutating_validation_exit" -eq 0 ]]; then
    fail "check-integration.sh reported READY after validation moved the cumulative candidate HEAD"
elif grep -Eq '^(✅ READY for integration|⚠️  READY with warnings)' "$mutating_validation_out"; then
    fail "check-integration.sh emitted a readiness verdict after candidate mutation"
elif ! grep -Eqi 'mutat|candidate.*(changed|HEAD)|HEAD.*changed' "$mutating_validation_out" "$mutating_validation_err"; then
    fail "candidate mutation was rejected without identifying the integrity failure"
else
    pass
fi

test_start "workflow Build repair is bounded persistent and routes unknown or terminal failures"
repair_output="$workflow/contracts/output.yaml"
repair_gates="$workflow/contracts/phase-gates.yaml"
repair_protocol="$workflow/references/build-worker-protocol.md"
missing_repair_terms=()
for file_and_term in \
    "$repair_output::- name: build_repair_state" \
    "$repair_output::- name: max_attempts" \
    "$repair_output::- name: no_progress_limit" \
    "$repair_output::- name: failure_signature" \
    "$repair_output::- name: progress_evidence" \
    "$repair_output::- name: cumulative_attempt_count" \
    "$repair_output::- name: plan_version" \
    "$repair_output::- name: terminal_route"; do
    repair_file="${file_and_term%%::*}"
    repair_term="${file_and_term#*::}"
    if ! grep -Fq -- "$repair_term" "$repair_file"; then
        missing_repair_terms+=("${repair_file#$FRAMEWORK_DIR/}: $repair_term")
    fi
done
if [[ "${#missing_repair_terms[@]}" -gt 0 ]]; then
    fail "build_repair_state contract fields missing: ${missing_repair_terms[*]}"
elif ! p0p4_contains_text_ci "$repair_output" "max_attempts 3" \
    || ! p0p4_contains_text_ci "$repair_output" "no_progress_limit 2"; then
    fail "build_repair_state does not fix max_attempts=3 and no_progress_limit=2"
elif ! p0p4_contains_text_ci "$repair_gates" "matching failure_signature" \
    || ! p0p4_contains_text_ci "$repair_gates" "two consecutive" \
    || ! p0p4_contains_text_ci "$repair_gates" "stagnation"; then
    fail "Build gates do not classify two matching no-progress signatures as stagnation"
elif ! p0p4_contains_text_ci "$repair_gates" "unknown-cause" \
    || ! p0p4_contains_text_ci "$repair_gates" "assistant-debugging"; then
    fail "Build gates do not route unknown-cause failures through assistant-debugging"
elif ! p0p4_contains_text_ci "$repair_gates" "attempt 3" \
    || ! p0p4_contains_text_ci "$repair_gates" "pivot_restart_decision" \
    || ! p0p4_contains_text_ci "$repair_gates" "blocked"; then
    fail "Build gates do not terminate attempt 3 with a pivot decision or blocked result"
elif ! p0p4_contains_text_ci "$repair_protocol" "same plan version" \
    || ! p0p4_contains_text_ci "$repair_protocol" "must not reset" \
    || ! p0p4_contains_text_ci "$repair_protocol" "cumulative_attempt_count"; then
    fail "same-scope restart can reset the cumulative Build repair budget"
else
    pass
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
