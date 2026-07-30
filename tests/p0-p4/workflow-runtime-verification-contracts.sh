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

init_topology_runtime_repo() {
    local repo="$1"
    local task="$2"

    git -C "$repo" init -q
    git -C "$repo" config user.email "p0p4@example.invalid"
    git -C "$repo" config user.name "P0 P4"
    printf 'fixture\n' >"$repo/README.md"
    printf '.worktrees/\n' >"$repo/.gitignore"
    git -C "$repo" add README.md .gitignore
    git -C "$repo" commit -q -m init
    git -C "$repo" branch "feature/${task}"
}

write_topology_runtime_brief() {
    local repo="$1"
    local task="$2"
    local number="$3"
    local slice_id="$4"
    local depends_on="$5"
    local promotion_mode="$6"
    shift 6
    local brief="$repo/briefs/slice-${number}-${slice_id}.md"
    local arg
    local target_base_sha
    local target_branch

    mkdir -p "$repo/briefs"
    target_branch=$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null || printf master)
    target_base_sha=$(git -C "$repo" merge-base "$target_branch" "feature/${task}" 2>/dev/null || git -C "$repo" rev-parse HEAD)
    cat >"$brief" <<BRIEF
## Slice Brief: ${slice_id}

### Strict slice packet (execution contract)
- slice_id: ${slice_id}
- slice_name: ${slice_id}
- target_branch: ${target_branch}
- target_base_sha: ${target_base_sha}
- task_branch: feature/${task}
- slice_branch: slice/${task}/${slice_id}
- promotion_mode: ${promotion_mode}
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
- deviation_rollback_rule: Return FAILED_VERIFICATION without promotion or VERIFIED status

### Supporting context (not the execution contract)
- Git branch: slice/${task}/${slice_id}
- Worktree: ${repo}/.worktrees/${slice_id}
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
    local integration_branch
    integration_branch="$(git -C "$repo" for-each-ref --format='%(refname:short)' 'refs/heads/feature/*/integration' | head -n 1)"
    if [[ -n "$integration_branch" ]]; then
        git -C "$repo" branch -f "$integration_branch" HEAD
    fi
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

test_start "workflow runner accepts a decompose-generated strict verification argv despite its supporting response example"
generated_brief_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-generated-brief.XXXXXX")"
p0p4_register_cleanup "$generated_brief_repo"
git -C "$generated_brief_repo" init -q
git -C "$generated_brief_repo" config user.email "p0p4@example.invalid"
git -C "$generated_brief_repo" config user.name "P0 P4"
printf 'fixture\n' >"$generated_brief_repo/README.md"
git -C "$generated_brief_repo" add README.md
git -C "$generated_brief_repo" commit -q -m init
cat >"$generated_brief_repo/decomposition.json" <<'JSON'
{
  "task": "generated-brief-argv",
  "description": "accept generated strict verification argv",
  "single_slice_rationale": "one generated packet exercises the runner boundary",
  "slice_manifest": [{
    "slice_id": "alpha",
    "name": "alpha",
    "observable_increment": "generated packet reaches dry-run validation",
    "deliverable_type": "behavior",
    "files_to_create": [],
    "files_to_modify": [],
    "files_to_test": [],
    "enabling_changes_included": [],
    "depends_on": [],
    "acceptance_criteria": ["generated strict packet is accepted"],
    "verification_command": ["true", "-f"],
    "expected_success_signal": "runner dry-run accepts the generated packet",
    "evidence_to_record": ["runner dry-run result"],
    "deviation_rollback_rule": "stop"
  }]
}
JSON
generated_brief_decompose_out="$runtime_output_dir/generated-brief-decompose.out"
generated_brief_decompose_err="$runtime_output_dir/generated-brief-decompose.err"
generated_brief_runner_out="$runtime_output_dir/generated-brief-runner.out"
generated_brief_runner_err="$runtime_output_dir/generated-brief-runner.err"
if ! (cd "$generated_brief_repo" && bash "$workflow/scripts/decompose.sh" --task generated-brief-argv --input decomposition.json >"$generated_brief_decompose_out" 2>"$generated_brief_decompose_err"); then
    fail "decompose.sh could not generate the strict packet fixture: $(tr '\n' ' ' <"$generated_brief_decompose_err")"
elif ! grep -Fq -- '  - -f' "$generated_brief_repo/briefs/slice-1-alpha.md"; then
    fail "decompose.sh did not preserve literal -f as a verification argv item in the generated strict packet"
elif ! bash "$workflow/scripts/run-agents.sh" --briefs "$generated_brief_repo/briefs" --repo "$generated_brief_repo" --dry-run >"$generated_brief_runner_out" 2>"$generated_brief_runner_err"; then
    fail "run-agents.sh rejected decompose-generated strict verification argv before dry-run dispatch: $(tr '\n' ' ' <"$generated_brief_runner_err")"
else
    pass
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

test_start "workflow review_gated verification emits exact review evidence without local promotion or dependency unlock"
review_gated_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-review-gated.XXXXXX")"
review_gated_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-review-gated-agent.XXXXXX")"
p0p4_register_cleanup "$review_gated_repo" "$review_gated_agent_bin"
init_topology_runtime_repo "$review_gated_repo" runtime-review-gated
add_verifier "$review_gated_repo" verify-pass.sh 'exit 0'
git -C "$review_gated_repo" branch -f feature/runtime-review-gated HEAD
git -C "$review_gated_repo" branch "slice/runtime-review-gated/alpha" feature/runtime-review-gated
git -C "$review_gated_repo" branch "slice/runtime-review-gated/beta" feature/runtime-review-gated
write_topology_runtime_brief "$review_gated_repo" runtime-review-gated 1 alpha none review_gated ./verify-pass.sh
write_topology_runtime_brief "$review_gated_repo" runtime-review-gated 2 beta alpha review_gated ./verify-pass.sh
make_fake_done_agent "$review_gated_agent_bin"
review_gated_task_before="$(git -C "$review_gated_repo" rev-parse feature/runtime-review-gated)"
review_gated_out="$runtime_output_dir/review-gated.out"
review_gated_err="$runtime_output_dir/review-gated.err"
if ! PATH="$review_gated_agent_bin:$PATH" bash "$workflow/scripts/run-agents.sh" --briefs "$review_gated_repo/briefs" --repo "$review_gated_repo" --agent codex >"$review_gated_out" 2>"$review_gated_err"; then
    fail "review_gated slice was not host-verified into REVIEW_PENDING: $(tr '\n' ' ' <"$review_gated_err")"
elif [[ "$(git -C "$review_gated_repo" rev-parse feature/runtime-review-gated)" != "$review_gated_task_before" ]]; then
    fail "review_gated verification promoted a slice into the task branch before external review"
elif ! git -C "$review_gated_repo" show "slice/runtime-review-gated/alpha:alpha-marker.txt" >/dev/null 2>&1; then
    fail "review_gated fake agent did not produce the immutable alpha slice head"
elif ! review_gated_alpha_head="$(git -C "$review_gated_repo" rev-parse slice/runtime-review-gated/alpha)"; then
    fail "review_gated fixture could not resolve the alpha slice SHA"
elif ! grep -Fq "REVIEW_PENDING" "$review_gated_out" \
    || ! grep -Fq "slice/runtime-review-gated/alpha" "$review_gated_out" \
    || ! grep -Fq "$review_gated_alpha_head" "$review_gated_out"; then
    fail "review_gated verification did not emit REVIEW_PENDING evidence bound to the exact slice SHA"
elif ! grep -Fq "provider_gate_state: not_evaluated" "$review_gated_out"; then
    fail "REVIEW_PENDING evidence does not explicitly record provider_gate_state: not_evaluated"
elif grep -Fq "state: VERIFIED" "$review_gated_out"; then
    fail "review_gated verification marked a slice VERIFIED before provider-neutral review evidence was supplied"
elif grep -Fq "Agent 2: slice-2-beta" "$review_gated_out" || git -C "$review_gated_repo" show "slice/runtime-review-gated/beta:beta-marker.txt" >/dev/null 2>&1; then
    fail "review_gated REVIEW_PENDING alpha unlocked dependent beta before promotion evidence"
else
    pass
fi

test_start "workflow sequential review-gated scheduling continues independent slices while deferring dependent slices"
review_sequential_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-review-sequential.XXXXXX")"
review_sequential_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-review-sequential-agent.XXXXXX")"
p0p4_register_cleanup "$review_sequential_repo" "$review_sequential_agent_bin"
init_topology_runtime_repo "$review_sequential_repo" runtime-review-sequential
add_verifier "$review_sequential_repo" verify-pass.sh 'exit 0'
git -C "$review_sequential_repo" branch -f feature/runtime-review-sequential HEAD
git -C "$review_sequential_repo" branch "slice/runtime-review-sequential/alpha" feature/runtime-review-sequential
git -C "$review_sequential_repo" branch "slice/runtime-review-sequential/beta" feature/runtime-review-sequential
git -C "$review_sequential_repo" branch "slice/runtime-review-sequential/gamma" feature/runtime-review-sequential
write_topology_runtime_brief "$review_sequential_repo" runtime-review-sequential 1 alpha none review_gated ./verify-pass.sh
write_topology_runtime_brief "$review_sequential_repo" runtime-review-sequential 2 beta alpha review_gated ./verify-pass.sh
write_topology_runtime_brief "$review_sequential_repo" runtime-review-sequential 3 gamma none review_gated ./verify-pass.sh
make_fake_done_agent "$review_sequential_agent_bin"
review_sequential_task_before="$(git -C "$review_sequential_repo" rev-parse feature/runtime-review-sequential)"
review_sequential_out="$runtime_output_dir/review-sequential.out"
review_sequential_err="$runtime_output_dir/review-sequential.err"
review_sequential_alpha_evidence="$review_sequential_repo/briefs/logs/slice-1-alpha.review-evidence.txt"
review_sequential_beta_evidence="$review_sequential_repo/briefs/logs/slice-2-beta.review-evidence.txt"
review_sequential_gamma_evidence="$review_sequential_repo/briefs/logs/slice-3-gamma.review-evidence.txt"
if ! PATH="$review_sequential_agent_bin:$PATH" bash "$workflow/scripts/run-agents.sh" --briefs "$review_sequential_repo/briefs" --repo "$review_sequential_repo" --agent codex >"$review_sequential_out" 2>"$review_sequential_err"; then
    fail "sequential review_gated runner failed before processing independent slices: $(tr '\n' ' ' <"$review_sequential_err")"
elif [[ "$(git -C "$review_sequential_repo" rev-parse feature/runtime-review-sequential)" != "$review_sequential_task_before" ]]; then
    fail "sequential review_gated runner promoted a slice before external review"
elif ! git -C "$review_sequential_repo" show "slice/runtime-review-sequential/alpha:alpha-marker.txt" >/dev/null 2>&1 \
    || [[ ! -f "$review_sequential_alpha_evidence" ]] \
    || ! grep -Fq 'state: REVIEW_PENDING' "$review_sequential_alpha_evidence"; then
    fail "sequential review_gated runner did not host-verify alpha into REVIEW_PENDING"
elif ! git -C "$review_sequential_repo" show "slice/runtime-review-sequential/gamma:gamma-marker.txt" >/dev/null 2>&1; then
    fail "sequential review_gated runner did not continue to independent gamma after alpha became REVIEW_PENDING"
elif [[ ! -f "$review_sequential_gamma_evidence" ]] \
    || ! grep -Fq 'state: REVIEW_PENDING' "$review_sequential_gamma_evidence" \
    || ! grep -Fq 'slice_id: gamma' "$review_sequential_gamma_evidence" \
    || cmp -s "$review_sequential_alpha_evidence" "$review_sequential_gamma_evidence"; then
    fail "sequential review_gated runner did not emit distinct REVIEW_PENDING evidence for alpha and gamma"
elif git -C "$review_sequential_repo" show "slice/runtime-review-sequential/beta:beta-marker.txt" >/dev/null 2>&1 \
    || [[ -e "$review_sequential_beta_evidence" ]] \
    || grep -Fq 'Agent 2: slice-2-beta' "$review_sequential_out"; then
    fail "sequential review_gated runner launched beta before alpha received external approval"
elif ! grep -Fq "Deferring slice 'beta' in this run: waiting for VERIFIED prerequisite(s): alpha" "$review_sequential_out"; then
    fail "sequential review_gated runner did not report beta as deferred for unverified alpha"
else
    pass
fi

test_start "workflow review-gated verification rejects a stale independent sibling after task promotion"
review_ancestry_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-review-ancestry.XXXXXX")"
review_ancestry_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-review-ancestry-agent.XXXXXX")"
p0p4_register_cleanup "$review_ancestry_repo" "$review_ancestry_agent_bin"
init_topology_runtime_repo "$review_ancestry_repo" runtime-review-ancestry
review_ancestry_target="$(git -C "$review_ancestry_repo" branch --show-current)"
add_verifier "$review_ancestry_repo" verify-pass.sh 'exit 0'
git -C "$review_ancestry_repo" branch -f feature/runtime-review-ancestry HEAD
review_ancestry_base="$(git -C "$review_ancestry_repo" rev-parse feature/runtime-review-ancestry)"
git -C "$review_ancestry_repo" branch "slice/runtime-review-ancestry/alpha" "$review_ancestry_base"
git -C "$review_ancestry_repo" checkout -q slice/runtime-review-ancestry/alpha
printf 'reviewed sibling output\n' >"$review_ancestry_repo/alpha-reviewed.txt"
git -C "$review_ancestry_repo" add alpha-reviewed.txt
git -C "$review_ancestry_repo" commit -q -m 'promote reviewed alpha sibling'
git -C "$review_ancestry_repo" checkout -q feature/runtime-review-ancestry
git -C "$review_ancestry_repo" merge --ff-only -q slice/runtime-review-ancestry/alpha
review_ancestry_task_head="$(git -C "$review_ancestry_repo" rev-parse feature/runtime-review-ancestry)"
git -C "$review_ancestry_repo" branch "slice/runtime-review-ancestry/beta" "$review_ancestry_base"
git -C "$review_ancestry_repo" checkout -q "$review_ancestry_target"
write_topology_runtime_brief "$review_ancestry_repo" runtime-review-ancestry 1 beta none review_gated ./verify-pass.sh
make_fake_done_agent "$review_ancestry_agent_bin"
review_ancestry_out="$runtime_output_dir/review-ancestry.out"
review_ancestry_err="$runtime_output_dir/review-ancestry.err"
review_ancestry_evidence="$review_ancestry_repo/briefs/logs/slice-1-beta.review-evidence.txt"
if PATH="$review_ancestry_agent_bin:$PATH" bash "$workflow/scripts/run-agents.sh" --briefs "$review_ancestry_repo/briefs" --repo "$review_ancestry_repo" --agent codex >"$review_ancestry_out" 2>"$review_ancestry_err"; then
    fail "review_gated runner accepted divergent verified base/head after task promotion: base=$review_ancestry_task_head head=$(git -C "$review_ancestry_repo" rev-parse slice/runtime-review-ancestry/beta)"
elif [[ -e "$review_ancestry_evidence" ]]; then
    fail "review_gated runner wrote reusable REVIEW_PENDING evidence for a divergent verified base/head pair"
elif ! rg -q -i 'verified.*(base|head).*(ancestor|ancestry)|(ancestor|ancestry).*(verified.*(base|head))' "$review_ancestry_out" "$review_ancestry_err"; then
    fail "divergent verified base/head rejection did not identify the ancestry requirement"
else
    pass
fi

test_start "workflow review_gated dry-runs do not write evidence or promote slice refs"
review_dry_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-review-dry.XXXXXX")"
p0p4_register_cleanup "$review_dry_repo"
init_topology_runtime_repo "$review_dry_repo" runtime-review-dry
git -C "$review_dry_repo" branch "slice/runtime-review-dry/alpha" feature/runtime-review-dry
git -C "$review_dry_repo" branch "slice/runtime-review-dry/beta" feature/runtime-review-dry
write_topology_runtime_brief "$review_dry_repo" runtime-review-dry 1 alpha none review_gated true
write_topology_runtime_brief "$review_dry_repo" runtime-review-dry 2 beta none review_gated true
review_dry_task_before="$(git -C "$review_dry_repo" rev-parse feature/runtime-review-dry)"
review_dry_refs_before="$(git -C "$review_dry_repo" for-each-ref --format='%(refname):%(objectname)' refs/heads/slice/runtime-review-dry/)"
review_dry_seq_out="$runtime_output_dir/review-dry-seq.out"
review_dry_parallel_out="$runtime_output_dir/review-dry-parallel.out"
review_dry_seq_exit=0
review_dry_parallel_exit=0
bash "$workflow/scripts/run-agents.sh" --briefs "$review_dry_repo/briefs" --repo "$review_dry_repo" --dry-run >"$review_dry_seq_out" 2>&1 || review_dry_seq_exit=$?
bash "$workflow/scripts/run-agents.sh" --briefs "$review_dry_repo/briefs" --repo "$review_dry_repo" --parallel --dry-run >"$review_dry_parallel_out" 2>&1 || review_dry_parallel_exit=$?
if [[ "$review_dry_seq_exit" -ne 0 || "$review_dry_parallel_exit" -ne 0 ]]; then
    fail "review_gated sequential or parallel dry-run failed: sequential=$(tr '\n' ' ' <"$review_dry_seq_out") parallel=$(tr '\n' ' ' <"$review_dry_parallel_out")"
elif find "$review_dry_repo/briefs" -name '*.review-evidence.txt' -type f -print -quit | grep -q .; then
    fail "review_gated dry-run wrote provider review evidence"
elif [[ "$(git -C "$review_dry_repo" rev-parse feature/runtime-review-dry)" != "$review_dry_task_before" ]] \
    || [[ "$(git -C "$review_dry_repo" for-each-ref --format='%(refname):%(objectname)' refs/heads/slice/runtime-review-dry/)" != "$review_dry_refs_before" ]]; then
    fail "review_gated dry-run promoted or otherwise mutated task/slice refs"
else
    pass
fi

test_start "workflow review-gated prerequisite promotion requires exact REVIEW_APPROVED evidence"
review_approval_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-review-approval.XXXXXX")"
p0p4_register_cleanup "$review_approval_repo"
init_topology_runtime_repo "$review_approval_repo" runtime-review-approval
git -C "$review_approval_repo" branch "slice/runtime-review-approval/alpha" feature/runtime-review-approval
git -C "$review_approval_repo" branch "slice/runtime-review-approval/beta" feature/runtime-review-approval
write_topology_runtime_brief "$review_approval_repo" runtime-review-approval 1 alpha none review_gated true
write_topology_runtime_brief "$review_approval_repo" runtime-review-approval 2 beta alpha review_gated true
review_approval_out="$runtime_output_dir/review-approval.out"
review_approval_err="$runtime_output_dir/review-approval.err"
if bash "$workflow/scripts/run-agents.sh" --briefs "$review_approval_repo/briefs" --repo "$review_approval_repo" --verified-slices alpha --dry-run >"$review_approval_out" 2>"$review_approval_err"; then
    fail "review_gated --verified-slices accepted ancestry/host proof without REVIEW_APPROVED evidence"
elif ! rg -q -i 'review.*approved|provider.*gate|review evidence' "$review_approval_out" "$review_approval_err"; then
    fail "review_gated prerequisite rejection did not identify missing REVIEW_APPROVED provider evidence"
else
    pass
fi

test_start "workflow exact approved review evidence re-verifies prerequisite and launches its dependent"
review_approved_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-review-approved.XXXXXX")"
review_approved_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-review-approved-agent.XXXXXX")"
p0p4_register_cleanup "$review_approved_repo" "$review_approved_agent_bin"
init_topology_runtime_repo "$review_approved_repo" runtime-review-approved
review_approved_target="$(git -C "$review_approved_repo" branch --show-current)"
add_verifier "$review_approved_repo" verify-pass.sh 'exit 0'
git -C "$review_approved_repo" branch -f feature/runtime-review-approved HEAD
git -C "$review_approved_repo" branch "slice/runtime-review-approved/alpha" feature/runtime-review-approved
git -C "$review_approved_repo" branch "slice/runtime-review-approved/beta" feature/runtime-review-approved
review_approved_base="$(git -C "$review_approved_repo" rev-parse feature/runtime-review-approved)"
git -C "$review_approved_repo" checkout -q slice/runtime-review-approved/alpha
printf 'approved alpha\n' >"$review_approved_repo/alpha-approved.txt"
git -C "$review_approved_repo" add alpha-approved.txt && git -C "$review_approved_repo" commit -q -m 'approved alpha transition'
git -C "$review_approved_repo" checkout -q feature/runtime-review-approved
git -C "$review_approved_repo" merge --ff-only -q slice/runtime-review-approved/alpha
git -C "$review_approved_repo" branch -f slice/runtime-review-approved/beta feature/runtime-review-approved
git -C "$review_approved_repo" checkout -q "$review_approved_target"
write_topology_runtime_brief "$review_approved_repo" runtime-review-approved 1 alpha none review_gated ./verify-pass.sh
write_topology_runtime_brief "$review_approved_repo" runtime-review-approved 2 beta alpha review_gated ./verify-pass.sh
sed -i.bak "s/^- target_base_sha:.*/- target_base_sha: ${review_approved_base}/" "$review_approved_repo/briefs/slice-1-alpha.md" "$review_approved_repo/briefs/slice-2-beta.md"
rm -f "$review_approved_repo/briefs/slice-1-alpha.md.bak" "$review_approved_repo/briefs/slice-2-beta.md.bak"
review_approved_head="$(git -C "$review_approved_repo" rev-parse slice/runtime-review-approved/alpha)"
mkdir -p "$review_approved_repo/briefs/logs"
cat >"$review_approved_repo/briefs/logs/slice-1-alpha.review-evidence.txt" <<EVIDENCE
--- SLICE REVIEW EVIDENCE ---
schema_version: 1
state: REVIEW_PENDING
slice_id: alpha
promotion_mode: review_gated
target_branch: ${review_approved_target}
target_base_sha: ${review_approved_base}
task_branch: feature/runtime-review-approved
slice_branch: slice/runtime-review-approved/alpha
review_base_ref: feature/runtime-review-approved
review_head_ref: slice/runtime-review-approved/alpha
verified_base_sha: ${review_approved_base}
verified_head_sha: ${review_approved_head}
verification_evidence_ref: local://host-verifier/alpha
provider_gate_state: not_evaluated
--- END SLICE REVIEW EVIDENCE ---
EVIDENCE
cat >"$review_approved_repo/briefs/logs/slice-1-alpha.review-approval.txt" <<EVIDENCE
--- SLICE REVIEW APPROVAL ---
schema_version: 1
state: REVIEW_APPROVED
slice_id: alpha
promotion_mode: review_gated
target_branch: ${review_approved_target}
target_base_sha: ${review_approved_base}
task_branch: feature/runtime-review-approved
slice_branch: slice/runtime-review-approved/alpha
review_base_ref: feature/runtime-review-approved
review_head_ref: slice/runtime-review-approved/alpha
verified_base_sha: ${review_approved_base}
verified_head_sha: ${review_approved_head}
verification_evidence_ref: local://host-verifier/alpha
review_request_ref: adapter://opaque-review-request/alpha-1
provider_gate_state: passed
provider_gate_evidence_ref: adapter://opaque-provider-gate/alpha-1
--- END SLICE REVIEW APPROVAL ---
EVIDENCE
make_fake_done_agent "$review_approved_agent_bin"
review_approved_out="$runtime_output_dir/review-approved.out"
review_approved_err="$runtime_output_dir/review-approved.err"
if ! PATH="$review_approved_agent_bin:$PATH" bash "$workflow/scripts/run-agents.sh" --briefs "$review_approved_repo/briefs" --repo "$review_approved_repo" --agent codex --verified-slices alpha >"$review_approved_out" 2>"$review_approved_err"; then
    fail "exact REVIEW_APPROVED evidence did not permit fresh prerequisite verification and dependent launch: $(tr '\n' ' ' <"$review_approved_err")"
elif ! grep -Fq "Agent 2: slice-2-beta" "$review_approved_out" \
    || ! git -C "$review_approved_repo" show "slice/runtime-review-approved/beta:beta-marker.txt" >/dev/null 2>&1; then
    fail "exact REVIEW_APPROVED evidence did not launch the dependent after host re-verification"
else
    pass
fi

test_start "workflow rejects mismatched REVIEW_APPROVED evidence before dependent dispatch"
review_mismatched_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-review-mismatched.XXXXXX")"
p0p4_register_cleanup "$review_mismatched_repo"
init_topology_runtime_repo "$review_mismatched_repo" runtime-review-mismatched
review_mismatched_target="$(git -C "$review_mismatched_repo" branch --show-current)"
git -C "$review_mismatched_repo" branch "slice/runtime-review-mismatched/alpha" feature/runtime-review-mismatched
git -C "$review_mismatched_repo" branch "slice/runtime-review-mismatched/beta" feature/runtime-review-mismatched
write_topology_runtime_brief "$review_mismatched_repo" runtime-review-mismatched 1 alpha none review_gated true
write_topology_runtime_brief "$review_mismatched_repo" runtime-review-mismatched 2 beta alpha review_gated true
review_mismatched_base="$(git -C "$review_mismatched_repo" rev-parse feature/runtime-review-mismatched)"
review_mismatched_head="$(git -C "$review_mismatched_repo" rev-parse slice/runtime-review-mismatched/alpha)"
mkdir -p "$review_mismatched_repo/briefs/logs"
cat >"$review_mismatched_repo/briefs/logs/slice-1-alpha.review-evidence.txt" <<EVIDENCE
--- SLICE REVIEW EVIDENCE ---
schema_version: 1
state: REVIEW_PENDING
slice_id: alpha
promotion_mode: review_gated
target_branch: ${review_mismatched_target}
target_base_sha: ${review_mismatched_base}
task_branch: feature/runtime-review-mismatched
slice_branch: slice/runtime-review-mismatched/alpha
review_base_ref: feature/runtime-review-mismatched
review_head_ref: slice/runtime-review-mismatched/alpha
verified_base_sha: ${review_mismatched_base}
verified_head_sha: ${review_mismatched_head}
verification_evidence_ref: local://host-verifier/alpha
provider_gate_state: not_evaluated
--- END SLICE REVIEW EVIDENCE ---
EVIDENCE
cat >"$review_mismatched_repo/briefs/logs/slice-1-alpha.review-approval.txt" <<EVIDENCE
--- SLICE REVIEW APPROVAL ---
schema_version: 1
state: REVIEW_APPROVED
slice_id: alpha
promotion_mode: review_gated
target_branch: ${review_mismatched_target}
target_base_sha: ${review_mismatched_base}
task_branch: feature/runtime-review-mismatched
slice_branch: slice/runtime-review-mismatched/alpha
review_base_ref: feature/runtime-review-mismatched
review_head_ref: slice/runtime-review-mismatched/alpha
verified_base_sha: ${review_mismatched_base}
verified_head_sha: 0000000000000000000000000000000000000000
verification_evidence_ref: local://host-verifier/alpha
review_request_ref: adapter://opaque-review-request/mismatched
provider_gate_state: passed
provider_gate_evidence_ref: adapter://opaque-provider-gate/mismatched
--- END SLICE REVIEW APPROVAL ---
EVIDENCE
review_mismatched_out="$runtime_output_dir/review-mismatched.out"
review_mismatched_err="$runtime_output_dir/review-mismatched.err"
if bash "$workflow/scripts/run-agents.sh" --briefs "$review_mismatched_repo/briefs" --repo "$review_mismatched_repo" --verified-slices alpha --dry-run >"$review_mismatched_out" 2>"$review_mismatched_err"; then
    fail "mismatched REVIEW_APPROVED evidence was accepted before dependent dispatch"
elif grep -Fq "Agent 2: slice-2-beta" "$review_mismatched_out"; then
    fail "mismatched REVIEW_APPROVED evidence reached dependent dispatch"
elif ! rg -q -i 'review.*(sha|head|evidence)|approval.*mismatch' "$review_mismatched_out" "$review_mismatched_err"; then
    fail "mismatched REVIEW_APPROVED evidence rejection was not actionable"
else
    pass
fi

test_start "workflow task-branch integration rejects review-gated slices without exact approval evidence"
review_integration_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-review-integration.XXXXXX")"
p0p4_register_cleanup "$review_integration_repo"
init_topology_runtime_repo "$review_integration_repo" runtime-review-integration
git -C "$review_integration_repo" checkout -q -b slice/runtime-review-integration/alpha feature/runtime-review-integration
printf 'review gated output\n' >"$review_integration_repo/alpha-marker.txt"
git -C "$review_integration_repo" add alpha-marker.txt
git -C "$review_integration_repo" commit -q -m 'review gated alpha output'
review_integration_base_branch="$(git -C "$review_integration_repo" symbolic-ref --quiet --short HEAD)"
git -C "$review_integration_repo" checkout -q "$review_integration_base_branch"
write_topology_runtime_brief "$review_integration_repo" runtime-review-integration 1 alpha none review_gated true
git -C "$review_integration_repo" add briefs
git -C "$review_integration_repo" commit -q -m 'add review integration brief fixture'
review_integration_out="$runtime_output_dir/review-integration.out"
review_integration_err="$runtime_output_dir/review-integration.err"
if (cd "$review_integration_repo" && bash "$workflow/scripts/check-integration.sh" --task-branch feature/runtime-review-integration --briefs "$review_integration_repo/briefs" --skip-validation 'review evidence fixture' >"$review_integration_out" 2>"$review_integration_err"); then
    fail "check-integration accepted a review_gated slice without exact REVIEW_APPROVED evidence"
elif ! rg -q -i 'review.*approved|provider.*gate|review evidence' "$review_integration_out" "$review_integration_err"; then
    fail "check-integration rejection did not identify missing REVIEW_APPROVED provider evidence: stdout=$(tr '\n' ' ' <"$review_integration_out") stderr=$(tr '\n' ' ' <"$review_integration_err")"
else
    pass
fi

test_start "workflow task-branch integration accepts exact approved evidence from a custom evidence directory"
review_checker_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-review-checker.XXXXXX")"
p0p4_register_cleanup "$review_checker_repo"
init_topology_runtime_repo "$review_checker_repo" runtime-review-checker
review_checker_base="$(git -C "$review_checker_repo" rev-parse feature/runtime-review-checker)"
review_checker_caller_branch="$(git -C "$review_checker_repo" symbolic-ref --quiet --short HEAD)"
git -C "$review_checker_repo" checkout -q -b slice/runtime-review-checker/alpha feature/runtime-review-checker
printf 'approved review output\n' >"$review_checker_repo/alpha-marker.txt"
git -C "$review_checker_repo" add alpha-marker.txt
git -C "$review_checker_repo" commit -q -m 'approved review alpha output'
review_checker_head="$(git -C "$review_checker_repo" rev-parse HEAD)"
git -C "$review_checker_repo" checkout -q feature/runtime-review-checker
git -C "$review_checker_repo" reset --hard -q "$review_checker_head"
git -C "$review_checker_repo" checkout -q "$review_checker_caller_branch"
write_topology_runtime_brief "$review_checker_repo" runtime-review-checker 1 alpha none review_gated true
git -C "$review_checker_repo" add briefs
git -C "$review_checker_repo" commit -q -m 'add checker review brief fixture'
review_checker_evidence="$review_checker_repo/review-evidence"
mkdir -p "$review_checker_evidence"
cat >"$review_checker_evidence/slice-1-alpha.review-evidence.txt" <<EVIDENCE
--- SLICE REVIEW EVIDENCE ---
schema_version: 1
state: REVIEW_PENDING
slice_id: alpha
promotion_mode: review_gated
target_branch: ${review_checker_caller_branch}
target_base_sha: ${review_checker_base}
task_branch: feature/runtime-review-checker
slice_branch: slice/runtime-review-checker/alpha
review_base_ref: feature/runtime-review-checker
review_head_ref: slice/runtime-review-checker/alpha
verified_base_sha: ${review_checker_base}
verified_head_sha: ${review_checker_head}
verification_evidence_ref: local://host-verifier/alpha
provider_gate_state: not_evaluated
--- END SLICE REVIEW EVIDENCE ---
EVIDENCE
cat >"$review_checker_evidence/slice-1-alpha.review-approval.txt" <<EVIDENCE
--- SLICE REVIEW APPROVAL ---
schema_version: 1
state: REVIEW_APPROVED
slice_id: alpha
promotion_mode: review_gated
target_branch: ${review_checker_caller_branch}
target_base_sha: ${review_checker_base}
task_branch: feature/runtime-review-checker
slice_branch: slice/runtime-review-checker/alpha
review_base_ref: feature/runtime-review-checker
review_head_ref: slice/runtime-review-checker/alpha
verified_base_sha: ${review_checker_base}
verified_head_sha: ${review_checker_head}
verification_evidence_ref: local://host-verifier/alpha
review_request_ref: adapter://opaque-review-request/checker-alpha
provider_gate_state: passed
provider_gate_evidence_ref: adapter://opaque-provider-gate/checker-alpha
--- END SLICE REVIEW APPROVAL ---
EVIDENCE
review_checker_out="$runtime_output_dir/review-checker.out"
review_checker_err="$runtime_output_dir/review-checker.err"
if ! (cd "$review_checker_repo" && bash "$workflow/scripts/check-integration.sh" --task-branch feature/runtime-review-checker --briefs "$review_checker_repo/briefs" --review-evidence-dir "$review_checker_evidence" --skip-validation 'approved review fixture' >"$review_checker_out" 2>"$review_checker_err"); then
    fail "check-integration rejected exact REVIEW_APPROVED evidence from custom evidence directory: $(tr '\n' ' ' <"$review_checker_err")"
elif ! grep -Eq 'READY|BRANCH-ONLY' "$review_checker_out"; then
    fail "check-integration did not report readiness after exact approved review evidence"
else
    pass
fi

test_start "workflow shared review evidence parsing accepts CRLF records and rejects remaining carriage returns"
for review_crlf_record in \
    "$review_approved_repo/briefs/logs/slice-1-alpha.review-evidence.txt" \
    "$review_approved_repo/briefs/logs/slice-1-alpha.review-approval.txt" \
    "$review_checker_evidence/slice-1-alpha.review-evidence.txt" \
    "$review_checker_evidence/slice-1-alpha.review-approval.txt"; do
    awk '{ printf "%s\r\n", $0 }' "$review_crlf_record" >"${review_crlf_record}.tmp"
    mv "${review_crlf_record}.tmp" "$review_crlf_record"
done
review_crlf_runner_out="$runtime_output_dir/review-crlf-runner.out"
review_crlf_runner_err="$runtime_output_dir/review-crlf-runner.err"
review_crlf_checker_out="$runtime_output_dir/review-crlf-checker.out"
review_crlf_checker_err="$runtime_output_dir/review-crlf-checker.err"
review_crlf_invalid_out="$runtime_output_dir/review-crlf-invalid.out"
review_crlf_invalid_err="$runtime_output_dir/review-crlf-invalid.err"
if ! bash "$workflow/scripts/run-agents.sh" --briefs "$review_approved_repo/briefs" --repo "$review_approved_repo" --verified-slices alpha --dry-run >"$review_crlf_runner_out" 2>"$review_crlf_runner_err"; then
    fail "run-agents rejected standards-compliant CRLF REVIEW_APPROVED evidence: $(tr '\n' ' ' <"$review_crlf_runner_err")"
elif ! (cd "$review_checker_repo" && bash "$workflow/scripts/check-integration.sh" --task-branch feature/runtime-review-checker --briefs "$review_checker_repo/briefs" --review-evidence-dir "$review_checker_evidence" --skip-validation 'CRLF review evidence fixture' >"$review_crlf_checker_out" 2>"$review_crlf_checker_err"); then
    fail "check-integration rejected standards-compliant CRLF REVIEW_APPROVED evidence: $(tr '\n' ' ' <"$review_crlf_checker_err")"
else
    awk 'NR == 2 { printf "%s\r\r\n", $0; next } { printf "%s\r\n", $0 }' "$review_checker_evidence/slice-1-alpha.review-approval.txt" >"$review_checker_evidence/slice-1-alpha.review-approval.txt.tmp"
    mv "$review_checker_evidence/slice-1-alpha.review-approval.txt.tmp" "$review_checker_evidence/slice-1-alpha.review-approval.txt"
    if (cd "$review_checker_repo" && bash "$workflow/scripts/check-integration.sh" --task-branch feature/runtime-review-checker --briefs "$review_checker_repo/briefs" --review-evidence-dir "$review_checker_evidence" --skip-validation 'malformed CRLF review evidence fixture' >"$review_crlf_invalid_out" 2>"$review_crlf_invalid_err"); then
        fail "check-integration accepted review evidence with a remaining carriage return"
    else
        pass
    fi
fi

prepare_approval_toctou_fixture() {
    local kind="$1"
    TOCTOU_REPO="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-toctou-${kind}.XXXXXX")"
    TOCTOU_BIN="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-toctou-bin-${kind}.XXXXXX")"
    p0p4_register_cleanup "$TOCTOU_REPO" "$TOCTOU_BIN"
    init_topology_runtime_repo "$TOCTOU_REPO" "toctou-${kind}"
    TOCTOU_CALLER="$(git -C "$TOCTOU_REPO" symbolic-ref --quiet --short HEAD)"
    TOCTOU_BASE="$(git -C "$TOCTOU_REPO" rev-parse "feature/toctou-${kind}")"
    git -C "$TOCTOU_REPO" checkout -q -b "slice/toctou-${kind}/alpha" "feature/toctou-${kind}"
    printf 'approved\n' >"$TOCTOU_REPO/alpha.txt"
    git -C "$TOCTOU_REPO" add alpha.txt && git -C "$TOCTOU_REPO" commit -q -m approved
    TOCTOU_HEAD="$(git -C "$TOCTOU_REPO" rev-parse HEAD)"
    git -C "$TOCTOU_REPO" checkout -q "feature/toctou-${kind}"
    git -C "$TOCTOU_REPO" merge --no-ff --no-edit -q "slice/toctou-${kind}/alpha"
    git -C "$TOCTOU_REPO" checkout -q "$TOCTOU_CALLER"
    printf 'moved\n' >"$TOCTOU_REPO/moved.txt"
    git -C "$TOCTOU_REPO" add moved.txt && git -C "$TOCTOU_REPO" commit -q -m moved
    TOCTOU_MOVED="$(git -C "$TOCTOU_REPO" rev-parse HEAD)"
    if [[ "$kind" == target ]]; then
        TOCTOU_MOVED="$(git -C "$TOCTOU_REPO" mktree </dev/null | xargs git -C "$TOCTOU_REPO" commit-tree -m 'orphan target move')"
    fi
    git -C "$TOCTOU_REPO" update-ref "refs/heads/slice/toctou-${kind}/alpha" "$TOCTOU_HEAD"
    write_topology_runtime_brief "$TOCTOU_REPO" "toctou-${kind}" 1 alpha none review_gated true
    sed -i.bak "s/^- target_base_sha:.*/- target_base_sha: ${TOCTOU_BASE}/" "$TOCTOU_REPO/briefs/slice-1-alpha.md"
    rm -f "$TOCTOU_REPO/briefs/slice-1-alpha.md.bak"
    git -C "$TOCTOU_REPO" add briefs && git -C "$TOCTOU_REPO" commit -q -m briefs
    TOCTOU_EVIDENCE="$TOCTOU_REPO/evidence"
    mkdir -p "$TOCTOU_EVIDENCE"
    for state_file in evidence approval; do
        if [[ "$state_file" == evidence ]]; then state=REVIEW_PENDING; gate=not_evaluated; marker=EVIDENCE; else state=REVIEW_APPROVED; gate=passed; marker=APPROVAL; fi
        cat >"$TOCTOU_EVIDENCE/slice-1-alpha.review-${state_file}.txt" <<EVIDENCE
--- SLICE REVIEW ${marker} ---
schema_version: 1
state: ${state}
slice_id: alpha
promotion_mode: review_gated
target_branch: ${TOCTOU_CALLER}
target_base_sha: ${TOCTOU_BASE}
task_branch: feature/toctou-${kind}
slice_branch: slice/toctou-${kind}/alpha
review_base_ref: feature/toctou-${kind}
review_head_ref: slice/toctou-${kind}/alpha
verified_base_sha: ${TOCTOU_BASE}
verified_head_sha: ${TOCTOU_HEAD}
verification_evidence_ref: local://verifier
provider_gate_state: ${gate}
EVIDENCE
        if [[ "$state_file" == approval ]]; then printf '%s\n' 'review_request_ref: adapter://request' 'provider_gate_evidence_ref: adapter://gate' >>"$TOCTOU_EVIDENCE/slice-1-alpha.review-${state_file}.txt"; fi
        printf '%s\n' "--- END SLICE REVIEW ${marker} ---" >>"$TOCTOU_EVIDENCE/slice-1-alpha.review-${state_file}.txt"
    done
    if [[ "$kind" == slice ]]; then
        TOCTOU_MOVE_REF="refs/heads/slice/toctou-${kind}/alpha"
    elif [[ "$kind" == task ]]; then
        TOCTOU_MOVE_REF="refs/heads/feature/toctou-${kind}"
    else
        TOCTOU_MOVE_REF="refs/heads/${TOCTOU_CALLER}"
    fi
    cat >"$TOCTOU_BIN/git" <<WRAPPER
#!/usr/bin/env bash
if { [[ "\$1" == worktree && "\$2" == add ]] || [[ "\$3" == worktree && "\$4" == add ]]; }; then
  "\$REAL_GIT" -C "$TOCTOU_REPO" update-ref "$TOCTOU_MOVE_REF" "$TOCTOU_MOVED"
fi
exec "\$REAL_GIT" "\$@"
WRAPPER
    chmod +x "$TOCTOU_BIN/git"
}

test_start "workflow rejects an empty REVIEW_APPROVED fast-forward equality"
review_empty_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-review-empty.XXXXXX")"
p0p4_register_cleanup "$review_empty_repo"
init_topology_runtime_repo "$review_empty_repo" runtime-review-empty
review_empty_base="$(git -C "$review_empty_repo" rev-parse feature/runtime-review-empty)"
git -C "$review_empty_repo" branch slice/runtime-review-empty/alpha "$review_empty_base"
write_topology_runtime_brief "$review_empty_repo" runtime-review-empty 1 alpha none review_gated true
git -C "$review_empty_repo" add briefs && git -C "$review_empty_repo" commit -q -m briefs
review_empty_evidence="$review_empty_repo/evidence"
mkdir -p "$review_empty_evidence"
for review_empty_file in evidence approval; do
    if [[ "$review_empty_file" == evidence ]]; then review_empty_state=REVIEW_PENDING; review_empty_gate=not_evaluated; review_empty_marker=EVIDENCE; else review_empty_state=REVIEW_APPROVED; review_empty_gate=passed; review_empty_marker=APPROVAL; fi
    cat >"$review_empty_evidence/slice-1-alpha.review-${review_empty_file}.txt" <<EVIDENCE
--- SLICE REVIEW ${review_empty_marker} ---
schema_version: 1
state: ${review_empty_state}
slice_id: alpha
promotion_mode: review_gated
target_branch: master
target_base_sha: ${review_empty_base}
task_branch: feature/runtime-review-empty
slice_branch: slice/runtime-review-empty/alpha
review_base_ref: feature/runtime-review-empty
review_head_ref: slice/runtime-review-empty/alpha
verified_base_sha: ${review_empty_base}
verified_head_sha: ${review_empty_base}
verification_evidence_ref: local://verifier
provider_gate_state: ${review_empty_gate}
EVIDENCE
    if [[ "$review_empty_file" == approval ]]; then printf '%s\n' 'review_request_ref: adapter://empty' 'provider_gate_evidence_ref: adapter://empty' >>"$review_empty_evidence/slice-1-alpha.review-${review_empty_file}.txt"; fi
done
review_empty_out="$runtime_output_dir/review-empty.out"
review_empty_err="$runtime_output_dir/review-empty.err"
if (cd "$review_empty_repo" && bash "$workflow/scripts/check-integration.sh" --task-branch feature/runtime-review-empty --briefs "$review_empty_repo/briefs" --review-evidence-dir "$review_empty_evidence" --skip-validation fixture >"$review_empty_out" 2>"$review_empty_err"); then
    fail "check-integration accepted REVIEW_APPROVED evidence with no reviewed transition"
elif ! rg -q -i 'empty|head.*base|no.*commit|review.*transition' "$review_empty_out" "$review_empty_err"; then
    fail "empty approved review rejection did not identify the missing reviewed transition"
else
    pass
fi

test_start "workflow integration allows only exact untracked generated brief artifacts"
dirty_allow_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-dirty-allow.XXXXXX")"
p0p4_register_cleanup "$dirty_allow_repo"
init_topology_runtime_repo "$dirty_allow_repo" runtime-dirty-allow
dirty_allow_caller="$(git -C "$dirty_allow_repo" symbolic-ref --quiet --short HEAD)"
dirty_allow_base="$(git -C "$dirty_allow_repo" rev-parse feature/runtime-dirty-allow)"
git -C "$dirty_allow_repo" checkout -q -b slice/runtime-dirty-allow/alpha feature/runtime-dirty-allow
printf 'approved\n' >"$dirty_allow_repo/alpha.txt"
git -C "$dirty_allow_repo" add alpha.txt && git -C "$dirty_allow_repo" commit -q -m alpha
dirty_allow_head="$(git -C "$dirty_allow_repo" rev-parse HEAD)"
git -C "$dirty_allow_repo" checkout -q "$dirty_allow_caller"
write_topology_runtime_brief "$dirty_allow_repo" runtime-dirty-allow 1 alpha none local true
sed -i.bak "s/^- target_base_sha:.*/- target_base_sha: ${dirty_allow_base}/" "$dirty_allow_repo/briefs/slice-1-alpha.md" && rm -f "$dirty_allow_repo/briefs/slice-1-alpha.md.bak"
mkdir -p "$dirty_allow_repo/briefs/logs"
for dirty_suffix in .log .host-verify.log .external.host-verify.log .review-evidence.txt .review-approval.txt; do
    printf 'generated artifact\n' >"$dirty_allow_repo/briefs/logs/slice-1-alpha${dirty_suffix}"
done
dirty_allow_out="$runtime_output_dir/dirty-allow.out"
dirty_allow_err="$runtime_output_dir/dirty-allow.err"
if ! (cd "$dirty_allow_repo" && bash "$workflow/scripts/check-integration.sh" --task-branch feature/runtime-dirty-allow --briefs "$dirty_allow_repo/briefs" --skip-validation fixture >"$dirty_allow_out" 2>"$dirty_allow_err"); then
    fail "check-integration rejected only exact generated untracked brief/log artifacts: $(tr '\n' ' ' <"$dirty_allow_err")"
else
    printf 'unrelated\n' >"$dirty_allow_repo/unrelated.tmp"
    if (cd "$dirty_allow_repo" && bash "$workflow/scripts/check-integration.sh" --task-branch feature/runtime-dirty-allow --briefs "$dirty_allow_repo/briefs" --skip-validation fixture >/dev/null 2>&1); then
        fail "check-integration accepted an unrelated untracked path"
    else
        rm -f "$dirty_allow_repo/unrelated.tmp"
        printf 'tracked mutation\n' >>"$dirty_allow_repo/README.md"
        if (cd "$dirty_allow_repo" && bash "$workflow/scripts/check-integration.sh" --task-branch feature/runtime-dirty-allow --briefs "$dirty_allow_repo/briefs" --skip-validation fixture >/dev/null 2>&1); then
            fail "check-integration accepted a tracked modification"
        else
            pass
        fi
    fi
fi

test_start "workflow integration fails closed when an approved slice ref moves after evidence validation"
prepare_approval_toctou_fixture slice
toctou_slice_out="$runtime_output_dir/toctou-slice.out"
toctou_slice_err="$runtime_output_dir/toctou-slice.err"
if (cd "$TOCTOU_REPO" && PATH="$TOCTOU_BIN:$PATH" REAL_GIT="$(command -v git)" bash "$workflow/scripts/check-integration.sh" --task-branch feature/toctou-slice --briefs "$TOCTOU_REPO/briefs" --review-evidence-dir "$TOCTOU_EVIDENCE" --skip-validation fixture >"$toctou_slice_out" 2>"$toctou_slice_err"); then
    fail "check-integration accepted a post-approval moved slice ref"
elif grep -Eq '^(✅ READY|⚠️  READY|ℹ️  BRANCH-ONLY)' "$toctou_slice_out"; then
    fail "moved approved slice emitted a readiness verdict"
elif ! rg -q -i 'slice.*(moved|changed)|review.*stale|approved.*(changed|mismatch)' "$toctou_slice_out" "$toctou_slice_err"; then
    fail "moved slice rejection was not explicitly bound to post-snapshot approval staleness"
else
    pass
fi

test_start "workflow integration fails closed when an approved task ref moves after evidence validation"
prepare_approval_toctou_fixture task
toctou_task_out="$runtime_output_dir/toctou-task.out"
toctou_task_err="$runtime_output_dir/toctou-task.err"
if (cd "$TOCTOU_REPO" && PATH="$TOCTOU_BIN:$PATH" REAL_GIT="$(command -v git)" bash "$workflow/scripts/check-integration.sh" --task-branch feature/toctou-task --briefs "$TOCTOU_REPO/briefs" --review-evidence-dir "$TOCTOU_EVIDENCE" --skip-validation fixture >"$toctou_task_out" 2>"$toctou_task_err"); then
    fail "check-integration accepted a post-approval moved task ref"
elif grep -Eq '^(✅ READY|⚠️  READY|ℹ️  BRANCH-ONLY)' "$toctou_task_out"; then
    fail "moved approved task emitted a readiness verdict"
elif ! rg -q -i 'task.*(moved|changed)|review.*stale|approved.*(changed|mismatch)' "$toctou_task_out" "$toctou_task_err"; then
    fail "moved task rejection was not explicitly bound to post-snapshot approval staleness"
else
    pass
fi

test_start "workflow integration fails closed when target branch moves after immutable readiness snapshot"
prepare_approval_toctou_fixture target
toctou_target_out="$runtime_output_dir/toctou-target.out"
toctou_target_err="$runtime_output_dir/toctou-target.err"
if (cd "$TOCTOU_REPO" && PATH="$TOCTOU_BIN:$PATH" REAL_GIT="$(command -v git)" bash "$workflow/scripts/check-integration.sh" --task-branch feature/toctou-target --briefs "$TOCTOU_REPO/briefs" --review-evidence-dir "$TOCTOU_EVIDENCE" --skip-validation fixture >"$toctou_target_out" 2>"$toctou_target_err"); then
    fail "check-integration accepted a post-snapshot moved target branch"
elif grep -Eq '^(✅ READY|⚠️  READY|ℹ️  BRANCH-ONLY)' "$toctou_target_out"; then
    fail "moved target branch emitted a positive readiness verdict"
elif ! rg -q -i 'target.*(moved|changed)|target.*stale|review.*stale' "$toctou_target_out" "$toctou_target_err"; then
    fail "moved target rejection did not identify immutable target ref staleness"
else
    pass
fi

test_start "workflow integration permits target advancement that remains descended from target_base_sha"
prepare_approval_toctou_fixture target-forward
toctou_target_forward_out="$runtime_output_dir/toctou-target-forward.out"
toctou_target_forward_err="$runtime_output_dir/toctou-target-forward.err"
if ! (cd "$TOCTOU_REPO" && PATH="$TOCTOU_BIN:$PATH" REAL_GIT="$(command -v git)" bash "$workflow/scripts/check-integration.sh" --task-branch feature/toctou-target-forward --briefs "$TOCTOU_REPO/briefs" --review-evidence-dir "$TOCTOU_EVIDENCE" --skip-validation fixture >"$toctou_target_forward_out" 2>"$toctou_target_forward_err"); then
    fail "check-integration rejected a descendant target advancement: $(tr '\n' ' ' <"$toctou_target_forward_err")"
elif ! grep -Eq '^(✅ READY|⚠️  READY|ℹ️  BRANCH-ONLY)' "$toctou_target_forward_out"; then
    fail "descendant target advancement did not reach a positive readiness result"
elif rg -q -i 'target.*(stale|moved|changed)|target_base_sha.*ancestor' "$toctou_target_forward_out" "$toctou_target_forward_err"; then
    fail "descendant target advancement was incorrectly classified as stale"
else
    pass
fi

test_start "workflow integration implementation snapshots approved target and slice SHAs before readiness"
if ! rg -q 'target_base_sha' "$workflow/scripts/check-integration.sh"; then
    fail "check-integration has no target_base_sha validation for approved review evidence"
elif ! rg -q -i 'approved.*(head|slice).*(sha|commit)|(sha|commit).*approved' "$workflow/scripts/check-integration.sh"; then
    fail "check-integration has no immutable approved slice SHA snapshot before readiness"
elif ! rg -q -i '(changed|moved|stale).*?(slice|task)|(slice|task).*?(changed|moved|stale)' "$workflow/scripts/check-integration.sh"; then
    fail "check-integration has no fail-closed moved task/slice ref guard after approval validation"
else
    pass
fi

test_start "workflow review_gated mode rejects moved slice refs after immutable verification"
review_moved_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-review-moved.XXXXXX")"
review_moved_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-review-moved-agent.XXXXXX")"
p0p4_register_cleanup "$review_moved_repo" "$review_moved_agent_bin"
init_topology_runtime_repo "$review_moved_repo" runtime-review-moved
add_verifier "$review_moved_repo" verify-moves-slice-ref.sh 'git update-ref refs/heads/slice/runtime-review-moved/alpha "${MUTATED_COMMIT:?}"'
git -C "$review_moved_repo" branch -f feature/runtime-review-moved HEAD
printf 'unverified ref target\n' >"$review_moved_repo/unverified-target.txt"
git -C "$review_moved_repo" add unverified-target.txt
git -C "$review_moved_repo" commit -q -m "unverified alternate target"
review_moved_commit="$(git -C "$review_moved_repo" rev-parse HEAD)"
git -C "$review_moved_repo" branch "slice/runtime-review-moved/alpha" feature/runtime-review-moved
write_topology_runtime_brief "$review_moved_repo" runtime-review-moved 1 alpha none review_gated ./verify-moves-slice-ref.sh
make_fake_detaching_agent "$review_moved_agent_bin"
review_moved_out="$runtime_output_dir/review-moved.out"
review_moved_err="$runtime_output_dir/review-moved.err"
if PATH="$review_moved_agent_bin:$PATH" MUTATED_COMMIT="$review_moved_commit" bash "$workflow/scripts/run-agents.sh" --briefs "$review_moved_repo/briefs" --repo "$review_moved_repo" --agent codex >"$review_moved_out" 2>"$review_moved_err"; then
    fail "review_gated mode accepted a slice branch moved after immutable verification"
elif ! grep -Eqi 'slice.*ref.*(changed|moved)|ref.*(changed|moved)|commit.*(changed|mismatch)' "$review_moved_out" "$review_moved_err"; then
    fail "review_gated moved-ref rejection did not identify invalidated immutable evidence"
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
elif ! grep -Eqi 'dirty|uncommitted|working tree.*clean|tracked modifications|unrelated untracked|declared briefs|runner-owned artifacts' "$dirty_integration_out" "$dirty_integration_err"; then
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

test_start "workflow review_gated verification retains exact checked-out branch binding"
review_detached_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-review-detached.XXXXXX")"
review_detached_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-review-detached-agent.XXXXXX")"
p0p4_register_cleanup "$review_detached_repo" "$review_detached_agent_bin"
init_topology_runtime_repo "$review_detached_repo" runtime-review-detached
add_verifier "$review_detached_repo" verify-pass.sh 'exit 0'
git -C "$review_detached_repo" branch -f feature/runtime-review-detached HEAD
git -C "$review_detached_repo" branch "slice/runtime-review-detached/alpha" feature/runtime-review-detached
write_topology_runtime_brief "$review_detached_repo" runtime-review-detached 1 alpha none review_gated ./verify-pass.sh
make_fake_detaching_agent "$review_detached_agent_bin"
review_detached_out="$runtime_output_dir/review-detached.out"
review_detached_err="$runtime_output_dir/review-detached.err"
if PATH="$review_detached_agent_bin:$PATH" DETACH_TO_PARENT=false bash "$workflow/scripts/run-agents.sh" --briefs "$review_detached_repo/briefs" --repo "$review_detached_repo" --agent codex >"$review_detached_out" 2>"$review_detached_err"; then
    fail "review_gated verification accepted a detached worktree at the verified slice SHA"
elif ! grep -Eqi 'worktree branch.*expected branch|branch.*does not match expected' "$review_detached_out" "$review_detached_err"; then
    fail "review_gated detached-worktree rejection did not preserve branch-binding evidence"
elif grep -Fq "REVIEW_PENDING" "$review_detached_out"; then
    fail "review_gated detached worktree emitted REVIEW_PENDING evidence despite failed branch binding"
else
    pass
fi

test_start "workflow review_gated stale runs invalidate prior REVIEW_PENDING evidence"
review_stale_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-review-stale.XXXXXX")"
review_stale_agent_bin="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-review-stale-agent.XXXXXX")"
p0p4_register_cleanup "$review_stale_repo" "$review_stale_agent_bin"
init_topology_runtime_repo "$review_stale_repo" runtime-review-stale
add_verifier "$review_stale_repo" verify-pass.sh 'exit 0'
add_verifier "$review_stale_repo" verify-conditional-move.sh 'if [[ "${MOVE_SLICE_REF:-false}" == true ]]; then git update-ref refs/heads/slice/runtime-review-stale/alpha "${MUTATED_COMMIT:?}"; fi'
git -C "$review_stale_repo" branch -f feature/runtime-review-stale HEAD
git -C "$review_stale_repo" branch "slice/runtime-review-stale/alpha" feature/runtime-review-stale
printf 'alternate ref target\n' >"$review_stale_repo/alternate.txt"
git -C "$review_stale_repo" add alternate.txt
git -C "$review_stale_repo" commit -q -m "alternate review ref target"
review_stale_alternate="$(git -C "$review_stale_repo" rev-parse HEAD)"
write_topology_runtime_brief "$review_stale_repo" runtime-review-stale 1 alpha none review_gated ./verify-conditional-move.sh
make_fake_done_agent "$review_stale_agent_bin"
review_stale_out="$runtime_output_dir/review-stale.out"
review_stale_err="$runtime_output_dir/review-stale.err"
if ! PATH="$review_stale_agent_bin:$PATH" bash "$workflow/scripts/run-agents.sh" --briefs "$review_stale_repo/briefs" --repo "$review_stale_repo" --agent codex >"$review_stale_out" 2>"$review_stale_err"; then
    fail "review_gated fixture could not create initial REVIEW_PENDING evidence: $(tr '\n' ' ' <"$review_stale_err")"
fi
review_stale_evidence="$review_stale_repo/briefs/logs/slice-1-alpha.review-evidence.txt"
review_stale_second_out="$runtime_output_dir/review-stale-second.out"
review_stale_second_err="$runtime_output_dir/review-stale-second.err"
if [[ ! -f "$review_stale_evidence" ]] || ! grep -Fq "state: REVIEW_PENDING" "$review_stale_evidence"; then
    fail "review_gated fixture did not write initial REVIEW_PENDING evidence"
elif PATH="$review_stale_agent_bin:$PATH" MOVE_SLICE_REF=true MUTATED_COMMIT="$review_stale_alternate" bash "$workflow/scripts/run-agents.sh" --briefs "$review_stale_repo/briefs" --repo "$review_stale_repo" --agent codex >"$review_stale_second_out" 2>"$review_stale_second_err"; then
    fail "review_gated stale run accepted a moved slice ref"
elif [[ -f "$review_stale_evidence" ]] && grep -Fq "state: REVIEW_PENDING" "$review_stale_evidence"; then
    fail "review_gated stale run left prior reusable REVIEW_PENDING evidence after immutable binding failed"
else
    pass
fi

test_start "workflow new-topology runner next steps target the resolved task branch"
new_topology_steps_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime-new-topology-steps.XXXXXX")"
p0p4_register_cleanup "$new_topology_steps_repo"
init_topology_runtime_repo "$new_topology_steps_repo" runtime-new-topology-steps
git -C "$new_topology_steps_repo" branch "slice/runtime-new-topology-steps/alpha" feature/runtime-new-topology-steps
write_topology_runtime_brief "$new_topology_steps_repo" runtime-new-topology-steps 1 alpha none local true
new_topology_steps_out="$runtime_output_dir/new-topology-steps.out"
new_topology_steps_err="$runtime_output_dir/new-topology-steps.err"
if ! bash "$workflow/scripts/run-agents.sh" --briefs "$new_topology_steps_repo/briefs" --repo "$new_topology_steps_repo" --dry-run >"$new_topology_steps_out" 2>"$new_topology_steps_err"; then
    fail "new-topology runner dry-run failed: $(tr '\n' ' ' <"$new_topology_steps_err")"
elif ! grep -Fq -- "Task branch: feature/runtime-new-topology-steps" "$new_topology_steps_out"; then
    fail "new-topology runner next steps did not name the resolved task branch"
elif ! grep -Fq -- "check-integration.sh --task-branch feature/runtime-new-topology-steps --briefs $new_topology_steps_repo/briefs" "$new_topology_steps_out"; then
    fail "new-topology runner next steps did not direct task-branch integration validation with the brief directory"
elif grep -Fq -- "feature/<task>/integration" "$new_topology_steps_out" \
    || grep -Fq -- "--integration-branch feature/<task>/integration" "$new_topology_steps_out"; then
    fail "new-topology runner next steps still advertised the retired feature/<task>/integration route"
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
