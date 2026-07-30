if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "workflow plan template defines executable task packet fields"
missing_packet_terms=()
for term in \
    "## Executable Task Packet" \
    "### Task [ID]: [short name]" \
    "- name: [task packet name; must populate current_task_packet.name]" \
    "- Behavior / acceptance criteria:" \
    "- Files:" \
    "- TDD / RED step:" \
    "  - tdd_applies: [true/false]" \
    "- Implementation notes / constraints:" \
    "  - implementation_notes:" \
    "- Verification:" \
    "- Deviation / rollback rule:" \
    "- Worker status / evidence:" \
    "## Task packets"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/plan-template.md"; then
        missing_packet_terms+=("$term")
    fi
done
if [[ "${#missing_packet_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "plan-template.md missing executable task packet terms: ${missing_packet_terms[*]}"
fi

test_start "workflow phase gates enforce executable task packet planning checks"
missing_phase_gate_terms=()
for term in \
    "- id: P9" \
    "For medium+ tasks: implementation work is represented as executable task packets using plan-template.md" \
    "- id: P10" \
    "verification command and expected success signal" \
    "- id: P11" \
    "deviation/rollback rule" \
    "- id: B12" \
    "every slice's acceptance and verification criteria from DECOMPOSE phase are independently checked, passing"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"; then
        missing_phase_gate_terms+=("$term")
    fi
done
if [[ "${#missing_phase_gate_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "phase-gates.yaml missing executable task packet gates: ${missing_phase_gate_terms[*]}"
fi

test_start "workflow build worker protocol enforces medium slice verification loop"
missing_slice_phase_terms=()
build_worker_ref="$FRAMEWORK_DIR/skills/assistant-workflow/references/build-worker-protocol.md"
for term in \
    "For medium+ tasks with slices, execute one slice at a time" \
    "Load the approved task packet for the slice, including slice_id, observable increment, deliverable type, files, acceptance criteria, verification command, expected success signal, evidence to record, and deviation/rollback rule" \
    "Confirm prior slice status is \`VERIFIED\` before advancing" \
    "Check each acceptance criterion from the slice manifest independently" \
    "Record verification evidence in the task journal slice verification ledger" \
    "Run a small self-check/local sanity check" \
    "Mark the slice \`VERIFIED\` only after all criteria pass and evidence is recorded" \
    "Only proceed to the next slice after the current one is fully verified"; do
    if ! p0p4_contains_text "$build_worker_ref" "$term"; then
        missing_slice_phase_terms+=("$term")
    fi
done
if ! grep -Fq -- "Load \`references/build-worker-protocol.md\` for source-changing Build work" "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"; then
    missing_slice_phase_terms+=("phases.md missing build-worker-protocol loader")
fi
if [[ "${#missing_slice_phase_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "build-worker-protocol.md missing per-slice verification loop terms: ${missing_slice_phase_terms[*]}"
fi

test_start "workflow task journal template includes slice verification ledger fields"
missing_slice_ledger_terms=()
for term in \
    "## Slice Verification Ledger" \
    "[required for medium+ tasks; update after each slice before starting the next]" \
    "| Slice | Task Packet | RED Status | Implementation Status | Verification Command/Result | Criteria Checked | Self-Check Result | Final Status |" \
    "[X/Y passed]" \
    "[pass/fail + note]" \
    "[VERIFIED/BLOCKED]" \
    "do not start the next slice until the current one is \`VERIFIED\`"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md"; then
        missing_slice_ledger_terms+=("$term")
    fi
done
if [[ "${#missing_slice_ledger_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "task-journal-template.md missing slice verification ledger terms: ${missing_slice_ledger_terms[*]}"
fi

test_start "workflow output contract requires slice verification summary for medium tasks"
missing_slice_output_terms=()
for term in \
    "- name: slice_verification_summary" \
    "- name: slice_manifest" \
    "condition: \"size in [medium, large, mega]\"" \
    "slice_id" \
    "slice_name" \
    "task_packet_id" \
    "red_status" \
    "verification_result" \
    "criteria_checked" \
    "self_check_result" \
    "final_status" \
    "enum_values: [REVIEW_PENDING, BLOCKED, VERIFIED]" \
    "Every slice final status must be VERIFIED before"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"; then
        missing_slice_output_terms+=("$term")
    fi
done
if ! awk '
    /- name: slice_verification_summary/ { in_summary = 1; next }
    in_summary && /^  - name: / { exit }
    in_summary && /required: true/ { found = 1; exit }
    END { exit found ? 0 : 1 }
' "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"; then
    missing_slice_output_terms+=("slice_verification_summary required: true")
fi
if [[ "${#missing_slice_output_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "output.yaml missing medium slice_verification_summary contract terms: ${missing_slice_output_terms[*]}"
fi

test_start "workflow output contract requires single-slice rationale for one-slice medium plans"
missing_single_slice_terms=()
for file in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml" \
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/contracts/output.yaml"; do
    for term in \
        "- name: single_slice_rationale" \
        "condition: \"size in [medium, large, mega] and slice_manifest has exactly one item\"" \
        "proves the one slice is the smallest iterable decomposition and not a broad fallback" \
        "single_slice_rationale must be present and non-blank"; do
        if ! grep -Fq -- "$term" "$file"; then
            missing_single_slice_terms+=("${file#$FRAMEWORK_DIR/}: $term")
        fi
    done
done
if [[ "${#missing_single_slice_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "output.yaml missing single-slice rationale contract terms: ${missing_single_slice_terms[*]}"
fi

test_start "workflow decompose enforces single-slice rationale with dry-run probes"
single_slice_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-single-slice-repo.XXXXXX")"
p0p4_register_cleanup "$single_slice_repo"
git -C "$single_slice_repo" init -q
git -C "$single_slice_repo" config user.email "p0p4@example.invalid"
git -C "$single_slice_repo" config user.name "P0 P4"
printf 'fixture\n' >"$single_slice_repo/README.md"
git -C "$single_slice_repo" add README.md
git -C "$single_slice_repo" commit -q -m init
single_slice_missing_manifest="$single_slice_repo/missing-rationale.json"
single_slice_valid_manifest="$single_slice_repo/valid-rationale.json"
cat >"$single_slice_missing_manifest" <<'JSON'
{
  "task": "single-slice",
  "description": "Single slice fixture",
  "slice_manifest": [
    {
      "slice_id": "only-slice",
      "name": "Only slice",
      "observable_increment": "Fixture behavior is represented as one verified increment",
      "deliverable_type": "behavior",
      "files_to_create": [],
      "files_to_modify": ["fixture.txt"],
      "files_to_test": [],
      "enabling_changes_included": [],
      "depends_on": [],
      "acceptance_criteria": ["Fixture criterion is checked"],
      "verification_command": ["true"],
      "expected_success_signal": "true exits 0",
      "evidence_to_record": ["dry-run result"],
      "deviation_rollback_rule": "Return DEVIATED rather than widening the slice"
    }
  ]
}
JSON
cat >"$single_slice_valid_manifest" <<'JSON'
{
  "task": "single-slice",
  "description": "Single slice fixture",
  "single_slice_rationale": "The behavior has one observable increment and cannot be split smaller without losing independent verification.",
  "slice_manifest": [
    {
      "slice_id": "only-slice",
      "name": "Only slice",
      "observable_increment": "Fixture behavior is represented as one verified increment",
      "deliverable_type": "behavior",
      "files_to_create": [],
      "files_to_modify": ["fixture.txt"],
      "files_to_test": [],
      "enabling_changes_included": [],
      "depends_on": [],
      "acceptance_criteria": ["Fixture criterion is checked"],
      "verification_command": ["true"],
      "expected_success_signal": "true exits 0",
      "evidence_to_record": ["dry-run result"],
      "deviation_rollback_rule": "Return DEVIATED rather than widening the slice"
    }
  ]
}
JSON
single_slice_missing_out="$single_slice_repo/missing.out"
single_slice_missing_err="$single_slice_repo/missing.err"
single_slice_valid_out="$single_slice_repo/valid.out"
single_slice_valid_err="$single_slice_repo/valid.err"
if (cd "$single_slice_repo" && bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/decompose.sh" --task single-slice --input "$single_slice_missing_manifest" --dry-run >"$single_slice_missing_out" 2>"$single_slice_missing_err"); then
    fail "decompose.sh accepted a one-slice manifest without single_slice_rationale"
elif ! grep -Fq "single_slice_rationale must be present and non-blank" "$single_slice_missing_err"; then
    fail "decompose.sh failed without actionable single_slice_rationale error"
elif ! (cd "$single_slice_repo" && bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/decompose.sh" --task single-slice --input "$single_slice_valid_manifest" --dry-run >"$single_slice_valid_out" 2>"$single_slice_valid_err"); then
    fail "decompose.sh rejected a one-slice manifest with single_slice_rationale; stderr: $(tr '\n' ' ' <"$single_slice_valid_err")"
else
    pass
fi

test_start "workflow output contract requires safe unique slice ids and declared dependencies"
missing_safe_slice_contract_terms=()
for file in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml" \
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/contracts/output.yaml"; do
    for term in \
        "slice_id values are unique branch/path-safe" \
        "depends_on entries reference only declared slice_id values" \
        "without self dependencies or circular dependencies" \
        "Stable descriptive outcome-oriented slice identifier that is branch/path-safe and reused for branches, worktrees, brief filenames, and depends_on references" \
        "Must be unique within slice_manifest; use only lowercase letters, digits, and hyphens; start and end with a letter or digit; no slashes, whitespace, path traversal, or branch separators" \
        "Every dependency is the slice_id of another declared slice in this manifest; no self dependency or circular dependency is allowed; use an empty array when there are no dependencies"; do
        if ! grep -Fq -- "$term" "$file"; then
            missing_safe_slice_contract_terms+=("${file#$FRAMEWORK_DIR/}: $term")
        fi
    done
done
if [[ "${#missing_safe_slice_contract_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "output.yaml missing safe slice_id/dependency contract terms: ${missing_safe_slice_contract_terms[*]}"
fi

test_start "workflow slice identities are descriptive while ordering stays display-only"
missing_descriptive_slice_terms=()
for skill_root in \
    "$FRAMEWORK_DIR/skills/assistant-workflow" \
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow"; do
    output_contract="$skill_root/contracts/output.yaml"
    phase_gates="$skill_root/contracts/phase-gates.yaml"
    plan_template="$skill_root/references/plan-template.md"
    journal_template="$skill_root/references/task-journal-template.md"
    topology_reference="$skill_root/references/slice-review-topology.md"

    for term in \
        "Stable descriptive outcome-oriented slice identifier" \
        "Ordinal-only or generic sequence labels such as s1, slice-2, or step-3 are invalid; manifest order and depends_on carry sequencing"; do
        if ! grep -Fq -- "$term" "$output_contract"; then
            missing_descriptive_slice_terms+=("${output_contract#$FRAMEWORK_DIR/}: $term")
        fi
    done
    for term in \
        "- id: DC_SLICE_IDENTITY" \
        "Every slice_id names its observable increment or verified deliverable" \
        "- id: DC_SLICE_SEQUENCE_LABEL" \
        "No slice_id is an ordinal-only or generic sequence label"; do
        if ! grep -Fq -- "$term" "$phase_gates"; then
            missing_descriptive_slice_terms+=("${phase_gates#$FRAMEWORK_DIR/}: $term")
        fi
    done
    if ! grep -Fq -- "- slice_id: [stable descriptive outcome/deliverable slug; never ordinal-only such as s1 or slice-2]" "$plan_template"; then
        missing_descriptive_slice_terms+=("${plan_template#$FRAMEWORK_DIR/}: descriptive slice_id template")
    fi
    if ! grep -Fq -- "| 1. [slice_id] [name] |" "$journal_template" \
        || grep -Fq -- "| S1: [slice_id] [name] |" "$journal_template"; then
        missing_descriptive_slice_terms+=("${journal_template#$FRAMEWORK_DIR/}: ordinal must be display-only and separate from slice_id")
    fi
    if ! grep -Fq -- "\`<slice-id>\` is a stable descriptive outcome or deliverable slug; sequence numbers belong to manifest order and display labels, not branch identity" "$topology_reference"; then
        missing_descriptive_slice_terms+=("${topology_reference#$FRAMEWORK_DIR/}: descriptive branch identity guidance")
    fi
done
if ! grep -Fq -- "descriptive outcome-oriented slice identifiers" "$FRAMEWORK_DIR/README.md"; then
    missing_descriptive_slice_terms+=("README.md: descriptive outcome-oriented slice identifier guidance")
fi
if [[ "${#missing_descriptive_slice_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow descriptive slice identity contract is incomplete: ${missing_descriptive_slice_terms[*]}"
fi

test_start "workflow decompose creates task and collision-safe slice refs with complete topology metadata"
decompose_branch_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-decompose-branches.XXXXXX")"
p0p4_register_cleanup "$decompose_branch_repo"
git -C "$decompose_branch_repo" init -q
git -C "$decompose_branch_repo" config user.email "p0p4@example.invalid"
git -C "$decompose_branch_repo" config user.name "P0 P4"
printf 'fixture\n' >"$decompose_branch_repo/README.md"
printf '.worktrees/\n' >"$decompose_branch_repo/.gitignore"
git -C "$decompose_branch_repo" add README.md .gitignore
git -C "$decompose_branch_repo" commit -q -m init
decompose_branch_base="$(git -C "$decompose_branch_repo" branch --show-current)"
decompose_branch_manifest="$decompose_branch_repo/decomposition.json"
cat >"$decompose_branch_manifest" <<'JSON'
{
  "task": "branch-safe",
  "description": "Two slice branch safety fixture",
  "slice_manifest": [
    {
      "slice_id": "alpha-core",
      "name": "Alpha core",
      "observable_increment": "Alpha core fixture can be verified independently",
      "deliverable_type": "behavior",
      "files_to_create": [],
      "files_to_modify": ["alpha.txt"],
      "files_to_test": [],
      "enabling_changes_included": [],
      "depends_on": [],
      "acceptance_criteria": ["Alpha fixture criterion is checked"],
      "verification_command": ["true"],
      "expected_success_signal": "true exits 0",
      "evidence_to_record": ["non-dry-run branch result"],
      "deviation_rollback_rule": "Return DEVIATED rather than widening the slice"
    },
    {
      "slice_id": "beta-flow",
      "name": "Beta flow",
      "observable_increment": "Beta flow fixture can consume alpha output",
      "deliverable_type": "behavior",
      "files_to_create": [],
      "files_to_modify": ["beta.txt"],
      "files_to_test": [],
      "enabling_changes_included": [],
      "depends_on": ["alpha-core"],
      "acceptance_criteria": ["Beta fixture criterion is checked"],
      "verification_command": ["true"],
      "expected_success_signal": "true exits 0",
      "evidence_to_record": ["non-dry-run branch result"],
      "deviation_rollback_rule": "Return DEVIATED rather than widening the slice"
    }
  ]
}
JSON
git -C "$decompose_branch_repo" add decomposition.json
git -C "$decompose_branch_repo" commit -q -m "add decomposition fixture"
decompose_runtime_output="$(mktemp -d "${TMPDIR:-/tmp}/workflow-decompose-runtime-output.XXXXXX")"
p0p4_register_cleanup "$decompose_runtime_output"
decompose_branch_out="$decompose_runtime_output/decompose.out"
decompose_branch_err="$decompose_runtime_output/decompose.err"
decompose_check_out="$decompose_runtime_output/check-integration.out"
decompose_check_err="$decompose_runtime_output/check-integration.err"
decompose_ready_briefs="$decompose_runtime_output/ready-briefs"
if ! (cd "$decompose_branch_repo" && bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/decompose.sh" --task branch-safe --input "$decompose_branch_manifest" --base "$decompose_branch_base" >"$decompose_branch_out" 2>"$decompose_branch_err"); then
    fail "decompose.sh non-dry-run branch probe failed: $(tr '\n' ' ' <"$decompose_branch_err")"
elif ! git -C "$decompose_branch_repo" show-ref --verify --quiet "refs/heads/feature/branch-safe"; then
    fail "decompose.sh did not create task branch feature/branch-safe from the --base alias"
elif [[ "$(git -C "$decompose_branch_repo" rev-parse feature/branch-safe)" != "$(git -C "$decompose_branch_repo" rev-parse "$decompose_branch_base")" ]]; then
    fail "decompose.sh task branch was not based on the explicit --base ref"
elif ! git -C "$decompose_branch_repo" show-ref --verify --quiet "refs/heads/slice/branch-safe/alpha-core"; then
    fail "decompose.sh did not create collision-safe slice/branch-safe/alpha-core"
elif git -C "$decompose_branch_repo" show-ref --verify --quiet "refs/heads/slice/branch-safe/beta-flow"; then
    fail "decompose.sh created dependent slice branch slice/branch-safe/beta-flow before alpha-core was verified"
elif git -C "$decompose_branch_repo" show-ref --verify --quiet "refs/heads/feature/branch-safe/integration"; then
    fail "decompose.sh retained the retired feature/<task>/integration topology"
elif [[ ! -d "$decompose_branch_repo/.worktrees/alpha-core" ]]; then
    fail "decompose.sh did not create dependency-free alpha-core worktree"
elif [[ -d "$decompose_branch_repo/.worktrees/beta-flow" ]]; then
    fail "decompose.sh created dependent beta-flow worktree before alpha-core was verified"
elif [[ ! -f "$decompose_branch_repo/briefs/slice-1-alpha-core.md" || ! -f "$decompose_branch_repo/briefs/slice-2-beta-flow.md" ]]; then
    fail "decompose.sh did not create expected slice brief files"
elif ! grep -Fq -- "- target_branch: ${decompose_branch_base}" "$decompose_branch_repo/briefs/slice-1-alpha-core.md" \
    || ! grep -Fq -- "- task_branch: feature/branch-safe" "$decompose_branch_repo/briefs/slice-1-alpha-core.md" \
    || ! grep -Fq -- "- slice_branch: slice/branch-safe/alpha-core" "$decompose_branch_repo/briefs/slice-1-alpha-core.md" \
    || ! grep -Fq -- "- promotion_mode: local" "$decompose_branch_repo/briefs/slice-1-alpha-core.md"; then
    fail "alpha brief did not emit complete strict target_branch/task_branch/slice_branch/promotion_mode metadata"
elif ! grep -Fq -- "Worktree: .worktrees/beta-flow (created at launch after dependencies are VERIFIED)" "$decompose_branch_repo/briefs/slice-2-beta-flow.md"; then
    fail "dependent beta brief did not record launch-time worktree creation"
elif ! grep -Fq -- "Deferring branch 'slice/branch-safe/beta-flow' until dependencies are VERIFIED" "$decompose_branch_out"; then
    fail "decompose summary did not explain deferred dependent branch creation"
elif ! grep -Fq -- "branch/worktree deferred until dependencies are VERIFIED" "$decompose_branch_out"; then
    fail "decompose summary did not list deferred dependent slice worktree"
elif ! grep -Fq -- "Task branch: feature/branch-safe" "$decompose_branch_out"; then
    fail "decompose summary did not record the task branch topology"
elif ! (mkdir -p "$decompose_ready_briefs" \
    && cp "$decompose_branch_repo/briefs/slice-1-alpha-core.md" "$decompose_ready_briefs/" \
    && cd "$decompose_branch_repo/.worktrees/alpha-core" \
    && printf 'alpha output\n' >alpha.txt \
    && git add alpha.txt \
    && git commit -q -m "alpha output"); then
    fail "decompose branch probe could not create required slice output commit before integration readiness check"
elif ! (git -C "$decompose_branch_repo" add briefs && git -C "$decompose_branch_repo" commit -q -m "record slice briefs"); then
    fail "decompose branch probe could not commit generated brief artifacts before clean integration validation"
elif ! (cd "$decompose_branch_repo" && bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/check-integration.sh" --task-branch feature/branch-safe --briefs "$decompose_ready_briefs" --dry-run --skip-validation "contract fixture" >"$decompose_check_out" 2>"$decompose_check_err"); then
    fail "check-integration.sh did not accept --task-branch with explicit briefs: $(tr '\n' ' ' <"$decompose_check_err")"
elif ! grep -Fq -- "Found 1 slice branch(es)" "$decompose_check_out"; then
    fail "check-integration.sh did not discover the dependency-free slice branch"
elif grep -Fq -- "  - feature/branch-safe" "$decompose_check_out"; then
    fail "check-integration.sh included the task branch as a slice"
else
    pass
fi

test_start "workflow check-integration rejects a declared new-topology slice branch that is missing"
declared_missing_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-declared-missing.XXXXXX")"
p0p4_register_cleanup "$declared_missing_repo"
git -C "$declared_missing_repo" init -q
git -C "$declared_missing_repo" config user.email "p0p4@example.invalid"
git -C "$declared_missing_repo" config user.name "P0 P4"
printf 'fixture\n' >"$declared_missing_repo/README.md"
git -C "$declared_missing_repo" add README.md
git -C "$declared_missing_repo" commit -q -m init
declared_missing_caller="$(git -C "$declared_missing_repo" branch --show-current)"
git -C "$declared_missing_repo" branch feature/declared-missing
git -C "$declared_missing_repo" checkout -q -b slice/declared-missing/alpha feature/declared-missing
printf 'alpha output\n' >"$declared_missing_repo/alpha.txt"
git -C "$declared_missing_repo" add alpha.txt
git -C "$declared_missing_repo" commit -q -m alpha
git -C "$declared_missing_repo" checkout -q "$declared_missing_caller"
mkdir -p "$declared_missing_repo/briefs"
for declared_missing_id in alpha beta; do
    cat >"$declared_missing_repo/briefs/slice-1-${declared_missing_id}.md" <<BRIEF
## Slice Brief: ${declared_missing_id}

### Strict slice packet (execution contract)
- slice_id: ${declared_missing_id}
- slice_name: ${declared_missing_id}
- target_branch: ${declared_missing_caller}
- target_base_sha: $(git -C "$declared_missing_repo" rev-parse "$declared_missing_caller")
- task_branch: feature/declared-missing
- slice_branch: slice/declared-missing/${declared_missing_id}
- promotion_mode: local
- observable_increment: fixture
- deliverable_type: behavior
- files_to_create:
  - none
- files_to_modify:
  - ${declared_missing_id}.txt
- files_to_test:
  - none
- enabling_changes_included:
  - none
- depends_on:
  - none
- acceptance_criteria:
  - [ ] fixture passes
- verification_command:
  - true
- expected_success_signal: true exits 0
- evidence_to_record:
  - fixture
- deviation_rollback_rule: Return DEVIATED
BRIEF
done
git -C "$declared_missing_repo" add briefs
git -C "$declared_missing_repo" commit -q -m briefs
declared_missing_out="$(mktemp "${TMPDIR:-/tmp}/workflow-declared-missing-out.XXXXXX")"
declared_missing_err="$(mktemp "${TMPDIR:-/tmp}/workflow-declared-missing-err.XXXXXX")"
p0p4_register_cleanup "$declared_missing_out" "$declared_missing_err"
if (cd "$declared_missing_repo" && bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/check-integration.sh" --task-branch feature/declared-missing --briefs "$declared_missing_repo/briefs" --skip-validation 'declared branch fixture' >"$declared_missing_out" 2>"$declared_missing_err"); then
    fail "check-integration silently omitted declared slice/declared-missing/beta"
elif ! grep -Eqi 'declared.*beta|beta.*(missing|not found)|slice branch.*missing' "$declared_missing_out" "$declared_missing_err"; then
    fail "missing declared slice rejection did not name beta before readiness evaluation"
else
    pass
fi

test_start "workflow decompose reuses the immutable target binding after target branch advances"
target_reuse_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-target-reuse.XXXXXX")"
p0p4_register_cleanup "$target_reuse_repo"
git -C "$target_reuse_repo" init -q
git -C "$target_reuse_repo" config user.email "p0p4@example.invalid"
git -C "$target_reuse_repo" config user.name "P0 P4"
printf 'base\n' >"$target_reuse_repo/README.md"
git -C "$target_reuse_repo" add README.md
git -C "$target_reuse_repo" commit -q -m base
target_reuse_target="$(git -C "$target_reuse_repo" branch --show-current)"
cat >"$target_reuse_repo/decomposition.json" <<'JSON'
{"task":"target-reuse","description":"binding fixture","single_slice_rationale":"One isolated fixture is sufficient.","slice_manifest":[{"slice_id":"alpha","name":"Alpha","observable_increment":"fixture","deliverable_type":"behavior","files_to_create":[],"files_to_modify":["alpha.txt"],"files_to_test":[],"enabling_changes_included":[],"depends_on":[],"acceptance_criteria":["fixture passes"],"verification_command":["true"],"expected_success_signal":"true exits 0","evidence_to_record":["fixture"],"deviation_rollback_rule":"Return DEVIATED"}]}
JSON
target_reuse_first_out="$target_reuse_repo/first.out"
target_reuse_first_err="$target_reuse_repo/first.err"
target_reuse_second_out="$target_reuse_repo/second.out"
target_reuse_second_err="$target_reuse_repo/second.err"
if ! (cd "$target_reuse_repo" && bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/decompose.sh" --task target-reuse --input decomposition.json --target-branch "$target_reuse_target" >"$target_reuse_first_out" 2>"$target_reuse_first_err"); then
    fail "initial target-binding decomposition failed: $(tr '\n' ' ' <"$target_reuse_first_err")"
elif ! target_reuse_bound_sha="$(sed -n 's/^- target_base_sha:[[:space:]]*//p' "$target_reuse_repo/briefs/slice-1-alpha.md")" || [[ -z "$target_reuse_bound_sha" ]]; then
    fail "decompose did not record target_base_sha in the strict brief"
else
    printf 'target moved\n' >"$target_reuse_repo/target-moved.txt"
    git -C "$target_reuse_repo" add target-moved.txt
    git -C "$target_reuse_repo" commit -q -m 'advance target'
    if ! (cd "$target_reuse_repo" && bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/decompose.sh" --task target-reuse --input decomposition.json --target-branch "$target_reuse_target" >"$target_reuse_second_out" 2>"$target_reuse_second_err"); then
        fail "decompose rejected a reusable task after its recorded target branch advanced: $(tr '\n' ' ' <"$target_reuse_second_err")"
    elif [[ "$(sed -n 's/^- target_base_sha:[[:space:]]*//p' "$target_reuse_repo/briefs/slice-1-alpha.md")" != "$target_reuse_bound_sha" ]]; then
        fail "decompose rewrote immutable target_base_sha after target branch advanced"
    else
        pass
    fi
fi

test_start "workflow decompose refuses a task branch with a divergent recorded target binding"
target_drift_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-target-drift.XXXXXX")"
p0p4_register_cleanup "$target_drift_repo"
git -C "$target_drift_repo" init -q
git -C "$target_drift_repo" config user.email "p0p4@example.invalid"
git -C "$target_drift_repo" config user.name "P0 P4"
printf 'common\n' >"$target_drift_repo/README.md"
git -C "$target_drift_repo" add README.md && git -C "$target_drift_repo" commit -q -m common
target_drift_common="$(git -C "$target_drift_repo" rev-parse HEAD)"
git -C "$target_drift_repo" checkout -q -b target-a "$target_drift_common"
printf 'a\n' >"$target_drift_repo/a.txt"
git -C "$target_drift_repo" add a.txt && git -C "$target_drift_repo" commit -q -m a
target_drift_a="$(git -C "$target_drift_repo" rev-parse HEAD)"
git -C "$target_drift_repo" checkout -q -b target-b "$target_drift_common"
printf 'b\n' >"$target_drift_repo/b.txt"
git -C "$target_drift_repo" add b.txt && git -C "$target_drift_repo" commit -q -m b
git -C "$target_drift_repo" branch feature/target-drift "$target_drift_a"
mkdir -p "$target_drift_repo/briefs"
printf '%s\n' "- target_branch: target-a" "- target_base_sha: $target_drift_a" "- task_branch: feature/target-drift" "- slice_branch: slice/target-drift/alpha" "- promotion_mode: local" >"$target_drift_repo/briefs/slice-1-alpha.md"
printf '%s\n' '{"task":"target-drift","single_slice_rationale":"Fixture.","slice_manifest":[{"slice_id":"alpha","name":"Alpha","observable_increment":"fixture","deliverable_type":"behavior","files_to_create":[],"files_to_modify":[],"files_to_test":[],"enabling_changes_included":[],"depends_on":[],"acceptance_criteria":["fixture"],"verification_command":["true"],"expected_success_signal":"true","evidence_to_record":["fixture"],"deviation_rollback_rule":"Return DEVIATED"}]}' >"$target_drift_repo/decomposition.json"
target_drift_before="$(git -C "$target_drift_repo" rev-parse feature/target-drift)"
target_drift_out="$(mktemp "${TMPDIR:-/tmp}/workflow-target-drift-out.XXXXXX")"
target_drift_err="$(mktemp "${TMPDIR:-/tmp}/workflow-target-drift-err.XXXXXX")"
p0p4_register_cleanup "$target_drift_out" "$target_drift_err"
if (cd "$target_drift_repo" && bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/decompose.sh" --task target-drift --input decomposition.json --target-branch target-b >"$target_drift_out" 2>"$target_drift_err"); then
    fail "decompose accepted a feature branch bound to divergent target-a for target-b"
elif [[ "$(git -C "$target_drift_repo" rev-parse feature/target-drift)" != "$target_drift_before" ]] \
    || git -C "$target_drift_repo" show-ref --verify --quiet refs/heads/slice/target-drift/alpha; then
    fail "divergent target rejection mutated task refs before failing"
elif ! grep -Eqi 'target.*(binding|base|diverg)|target_base_sha' "$target_drift_out" "$target_drift_err"; then
    fail "divergent target rejection did not identify target_base_sha binding"
else
    pass
fi

test_start "workflow check-integration rejects empty slice branches"
empty_slice_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-empty-slice.XXXXXX")"
p0p4_register_cleanup "$empty_slice_repo"
git -C "$empty_slice_repo" init -q
git -C "$empty_slice_repo" config user.email "p0p4@example.invalid"
git -C "$empty_slice_repo" config user.name "P0 P4"
printf 'fixture\n' >"$empty_slice_repo/README.md"
git -C "$empty_slice_repo" add README.md
git -C "$empty_slice_repo" commit -q -m init
git -C "$empty_slice_repo" branch "feature/empty/integration"
git -C "$empty_slice_repo" branch "feature/empty/slice-noop" "feature/empty/integration"
empty_slice_output="$(mktemp -d "${TMPDIR:-/tmp}/workflow-empty-slice-output.XXXXXX")"
p0p4_register_cleanup "$empty_slice_output"
empty_slice_out="$empty_slice_output/check.out"
empty_slice_err="$empty_slice_output/check.err"
if (cd "$empty_slice_repo" && bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/check-integration.sh" --integration-branch feature/empty/integration --dry-run --skip-validation "contract fixture" >"$empty_slice_out" 2>"$empty_slice_err"); then
    fail "check-integration.sh accepted an empty slice branch with no commits beyond integration"
elif ! grep -Fq -- "no commits ahead of integration branch" "$empty_slice_err"; then
    fail "empty slice branch failure did not explain missing commits: $(tr '\n' ' ' <"$empty_slice_err")"
elif grep -Eq -- "READY for integration|READY with warnings|NOT READY for integration" "$empty_slice_out"; then
    fail "empty slice branch dry-run emitted a readiness verdict"
elif ! grep -Fq -- "no readiness verdict" "$empty_slice_out"; then
    fail "empty slice branch dry-run did not state that no readiness verdict was produced"
else
    pass
fi

test_start "workflow check-integration accepts already merged slice branches"
merged_slice_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-merged-slice.XXXXXX")"
p0p4_register_cleanup "$merged_slice_repo"
git -C "$merged_slice_repo" init -q
git -C "$merged_slice_repo" config user.email "p0p4@example.invalid"
git -C "$merged_slice_repo" config user.name "P0 P4"
printf 'fixture\n' >"$merged_slice_repo/README.md"
git -C "$merged_slice_repo" add README.md
git -C "$merged_slice_repo" commit -q -m init
git -C "$merged_slice_repo" branch "feature/merged/integration"
git -C "$merged_slice_repo" checkout -q -b "feature/merged/slice-alpha" "feature/merged/integration"
printf 'alpha output\n' >"$merged_slice_repo/alpha.txt"
git -C "$merged_slice_repo" add alpha.txt
git -C "$merged_slice_repo" commit -q -m "alpha output"
git -C "$merged_slice_repo" checkout -q "feature/merged/integration"
git -C "$merged_slice_repo" merge --no-ff -q -m "merge alpha" "feature/merged/slice-alpha"
merged_slice_output="$(mktemp -d "${TMPDIR:-/tmp}/workflow-merged-slice-output.XXXXXX")"
p0p4_register_cleanup "$merged_slice_output"
merged_slice_out="$merged_slice_output/check.out"
merged_slice_err="$merged_slice_output/check.err"
if ! (cd "$merged_slice_repo" && bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/check-integration.sh" --integration-branch feature/merged/integration --dry-run --skip-validation "contract fixture" >"$merged_slice_out" 2>"$merged_slice_err"); then
    fail "check-integration.sh rejected an already merged slice branch: $(tr '\n' ' ' <"$merged_slice_err")"
elif ! grep -Fq -- "already merged into integration branch" "$merged_slice_out"; then
    fail "merged slice branch success did not explain already-integrated status"
elif grep -Fq -- "no commits ahead of integration branch" "$merged_slice_err"; then
    fail "merged slice branch was still reported as empty"
else
    pass
fi

test_start "workflow decompose rejects unsafe duplicate unknown self and cyclic slice dependencies"
decompose_validation_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-decompose-validation.XXXXXX")"
p0p4_register_cleanup "$decompose_validation_repo"
git -C "$decompose_validation_repo" init -q
git -C "$decompose_validation_repo" config user.email "p0p4@example.invalid"
git -C "$decompose_validation_repo" config user.name "P0 P4"
printf 'fixture\n' >"$decompose_validation_repo/README.md"
git -C "$decompose_validation_repo" add README.md
git -C "$decompose_validation_repo" commit -q -m init
unsafe_slice_manifest="$decompose_validation_repo/unsafe.json"
duplicate_slice_manifest="$decompose_validation_repo/duplicate.json"
unknown_dependency_manifest="$decompose_validation_repo/unknown-dependency.json"
self_dependency_manifest="$decompose_validation_repo/self-dependency.json"
cycle_dependency_manifest="$decompose_validation_repo/cycle-dependency.json"
cat >"$unsafe_slice_manifest" <<'JSON'
{
  "task": "invalid-slices",
  "description": "Unsafe slice id fixture",
  "slice_manifest": [
    {
      "slice_id": "bad/id",
      "name": "Bad id",
      "observable_increment": "Bad id fixture is rejected",
      "deliverable_type": "behavior",
      "files_to_create": [],
      "files_to_modify": ["bad.txt"],
      "files_to_test": [],
      "enabling_changes_included": [],
      "depends_on": [],
      "acceptance_criteria": ["Bad id is rejected"],
      "verification_command": ["true"],
      "expected_success_signal": "true exits 0",
      "evidence_to_record": ["validation result"],
      "deviation_rollback_rule": "Return DEVIATED rather than widening the slice"
    },
    {
      "slice_id": "safe-id",
      "name": "Safe id",
      "observable_increment": "Safe id fixture is present",
      "deliverable_type": "behavior",
      "files_to_create": [],
      "files_to_modify": ["safe.txt"],
      "files_to_test": [],
      "enabling_changes_included": [],
      "depends_on": [],
      "acceptance_criteria": ["Safe id is present"],
      "verification_command": ["true"],
      "expected_success_signal": "true exits 0",
      "evidence_to_record": ["validation result"],
      "deviation_rollback_rule": "Return DEVIATED rather than widening the slice"
    }
  ]
}
JSON
cat >"$duplicate_slice_manifest" <<'JSON'
{
  "task": "invalid-slices",
  "description": "Duplicate slice id fixture",
  "slice_manifest": [
    {
      "slice_id": "dup-id",
      "name": "Duplicate one",
      "observable_increment": "First duplicate fixture is rejected",
      "deliverable_type": "behavior",
      "files_to_create": [],
      "files_to_modify": ["one.txt"],
      "files_to_test": [],
      "enabling_changes_included": [],
      "depends_on": [],
      "acceptance_criteria": ["Duplicate one is rejected"],
      "verification_command": ["true"],
      "expected_success_signal": "true exits 0",
      "evidence_to_record": ["validation result"],
      "deviation_rollback_rule": "Return DEVIATED rather than widening the slice"
    },
    {
      "slice_id": "dup-id",
      "name": "Duplicate two",
      "observable_increment": "Second duplicate fixture is rejected",
      "deliverable_type": "behavior",
      "files_to_create": [],
      "files_to_modify": ["two.txt"],
      "files_to_test": [],
      "enabling_changes_included": [],
      "depends_on": [],
      "acceptance_criteria": ["Duplicate two is rejected"],
      "verification_command": ["true"],
      "expected_success_signal": "true exits 0",
      "evidence_to_record": ["validation result"],
      "deviation_rollback_rule": "Return DEVIATED rather than widening the slice"
    }
  ]
}
JSON
cat >"$unknown_dependency_manifest" <<'JSON'
{
  "task": "invalid-slices",
  "description": "Unknown dependency fixture",
  "slice_manifest": [
    {
      "slice_id": "alpha-id",
      "name": "Alpha id",
      "observable_increment": "Alpha fixture is declared",
      "deliverable_type": "behavior",
      "files_to_create": [],
      "files_to_modify": ["alpha.txt"],
      "files_to_test": [],
      "enabling_changes_included": [],
      "depends_on": [],
      "acceptance_criteria": ["Alpha is declared"],
      "verification_command": ["true"],
      "expected_success_signal": "true exits 0",
      "evidence_to_record": ["validation result"],
      "deviation_rollback_rule": "Return DEVIATED rather than widening the slice"
    },
    {
      "slice_id": "beta-id",
      "name": "Beta id",
      "observable_increment": "Beta fixture references an unknown dependency",
      "deliverable_type": "behavior",
      "files_to_create": [],
      "files_to_modify": ["beta.txt"],
      "files_to_test": [],
      "enabling_changes_included": [],
      "depends_on": ["missing-id"],
      "acceptance_criteria": ["Unknown dependency is rejected"],
      "verification_command": ["true"],
      "expected_success_signal": "true exits 0",
      "evidence_to_record": ["validation result"],
      "deviation_rollback_rule": "Return DEVIATED rather than widening the slice"
    }
  ]
}
JSON
cat >"$self_dependency_manifest" <<'JSON'
{
  "task": "invalid-slices",
  "description": "Self dependency fixture",
  "slice_manifest": [
    {
      "slice_id": "alpha-id",
      "name": "Alpha id",
      "observable_increment": "Alpha fixture references itself",
      "deliverable_type": "behavior",
      "files_to_create": [],
      "files_to_modify": ["alpha.txt"],
      "files_to_test": [],
      "enabling_changes_included": [],
      "depends_on": ["alpha-id"],
      "acceptance_criteria": ["Self dependency is rejected"],
      "verification_command": ["true"],
      "expected_success_signal": "true exits 0",
      "evidence_to_record": ["validation result"],
      "deviation_rollback_rule": "Return DEVIATED rather than widening the slice"
    }
  ],
  "single_slice_rationale": "This invalid fixture intentionally has one slice so self-dependency validation is reached."
}
JSON
cat >"$cycle_dependency_manifest" <<'JSON'
{
  "task": "invalid-slices",
  "description": "Cycle dependency fixture",
  "slice_manifest": [
    {
      "slice_id": "alpha-id",
      "name": "Alpha id",
      "observable_increment": "Alpha fixture depends on beta",
      "deliverable_type": "behavior",
      "files_to_create": [],
      "files_to_modify": ["alpha.txt"],
      "files_to_test": [],
      "enabling_changes_included": [],
      "depends_on": ["beta-id"],
      "acceptance_criteria": ["Alpha cycle is rejected"],
      "verification_command": ["true"],
      "expected_success_signal": "true exits 0",
      "evidence_to_record": ["validation result"],
      "deviation_rollback_rule": "Return DEVIATED rather than widening the slice"
    },
    {
      "slice_id": "beta-id",
      "name": "Beta id",
      "observable_increment": "Beta fixture depends on alpha",
      "deliverable_type": "behavior",
      "files_to_create": [],
      "files_to_modify": ["beta.txt"],
      "files_to_test": [],
      "enabling_changes_included": [],
      "depends_on": ["alpha-id"],
      "acceptance_criteria": ["Beta cycle is rejected"],
      "verification_command": ["true"],
      "expected_success_signal": "true exits 0",
      "evidence_to_record": ["validation result"],
      "deviation_rollback_rule": "Return DEVIATED rather than widening the slice"
    }
  ]
}
JSON
unsafe_err="$decompose_validation_repo/unsafe.err"
duplicate_err="$decompose_validation_repo/duplicate.err"
unknown_dependency_err="$decompose_validation_repo/unknown-dependency.err"
self_dependency_err="$decompose_validation_repo/self-dependency.err"
cycle_dependency_err="$decompose_validation_repo/cycle-dependency.err"
if (cd "$decompose_validation_repo" && bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/decompose.sh" --task invalid-slices --input "$unsafe_slice_manifest" --dry-run >/dev/null 2>"$unsafe_err"); then
    fail "decompose.sh accepted unsafe slice_id with slash"
elif ! grep -Fq -- "Invalid slice_id values" "$unsafe_err"; then
    fail "decompose.sh unsafe slice_id failure was not actionable"
elif (cd "$decompose_validation_repo" && bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/decompose.sh" --task invalid-slices --input "$duplicate_slice_manifest" --dry-run >/dev/null 2>"$duplicate_err"); then
    fail "decompose.sh accepted duplicate slice_id values"
elif ! grep -Fq -- "Duplicate slice_id values" "$duplicate_err"; then
    fail "decompose.sh duplicate slice_id failure was not actionable"
elif (cd "$decompose_validation_repo" && bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/decompose.sh" --task invalid-slices --input "$unknown_dependency_manifest" --dry-run >/dev/null 2>"$unknown_dependency_err"); then
    fail "decompose.sh accepted unknown depends_on references"
elif ! grep -Fq -- "Unknown depends_on references" "$unknown_dependency_err"; then
    fail "decompose.sh unknown dependency failure was not actionable"
elif (cd "$decompose_validation_repo" && bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/decompose.sh" --task invalid-slices --input "$self_dependency_manifest" >/dev/null 2>"$self_dependency_err"); then
    fail "decompose.sh accepted self dependency in depends_on"
elif ! grep -Fq -- "Self dependency detected" "$self_dependency_err"; then
    fail "decompose.sh self dependency failure was not actionable"
elif git -C "$decompose_validation_repo" show-ref --verify --quiet "refs/heads/feature/invalid-slices/integration" || [[ -d "$decompose_validation_repo/briefs" ]]; then
    fail "decompose.sh mutated repo state before rejecting self dependency"
elif (cd "$decompose_validation_repo" && bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/decompose.sh" --task invalid-slices --input "$cycle_dependency_manifest" >/dev/null 2>"$cycle_dependency_err"); then
    fail "decompose.sh accepted circular depends_on references"
elif ! grep -Fq -- "Circular dependency detected" "$cycle_dependency_err"; then
    fail "decompose.sh circular dependency failure was not actionable"
elif ! grep -Eq -- "alpha-id.*beta-id.*alpha-id|beta-id.*alpha-id.*beta-id" "$cycle_dependency_err"; then
    fail "decompose.sh circular dependency failure did not mention involved slice IDs"
elif git -C "$decompose_validation_repo" show-ref --verify --quiet "refs/heads/feature/invalid-slices/integration" || [[ -d "$decompose_validation_repo/briefs" ]]; then
    fail "decompose.sh mutated repo state before rejecting circular dependency"
else
    pass
fi

test_start "workflow assistant-workflow root and plugin branch surfaces stay synchronized"
workflow_sync_pairs=(
    "skills/assistant-workflow/SKILL.md|plugins/assistant-dev/skills/assistant-workflow/SKILL.md"
    "skills/assistant-workflow/scripts/decompose.sh|plugins/assistant-dev/skills/assistant-workflow/scripts/decompose.sh"
    "skills/assistant-workflow/scripts/check-integration.sh|plugins/assistant-dev/skills/assistant-workflow/scripts/check-integration.sh"
    "skills/assistant-workflow/scripts/run-agents.sh|plugins/assistant-dev/skills/assistant-workflow/scripts/run-agents.sh"
    "skills/assistant-workflow/contracts/input.yaml|plugins/assistant-dev/skills/assistant-workflow/contracts/input.yaml"
    "skills/assistant-workflow/contracts/output.yaml|plugins/assistant-dev/skills/assistant-workflow/contracts/output.yaml"
    "skills/assistant-workflow/contracts/phase-gates.yaml|plugins/assistant-dev/skills/assistant-workflow/contracts/phase-gates.yaml"
    "skills/assistant-workflow/contracts/handoffs.yaml|plugins/assistant-dev/skills/assistant-workflow/contracts/handoffs.yaml"
    "skills/assistant-workflow/references/phases.md|plugins/assistant-dev/skills/assistant-workflow/references/phases.md"
    "skills/assistant-workflow/references/build-worker-protocol.md|plugins/assistant-dev/skills/assistant-workflow/references/build-worker-protocol.md"
    "skills/assistant-workflow/references/review-qa-router.md|plugins/assistant-dev/skills/assistant-workflow/references/review-qa-router.md"
    "skills/assistant-workflow/references/harness-runtime-artifacts.md|plugins/assistant-dev/skills/assistant-workflow/references/harness-runtime-artifacts.md"
    "skills/assistant-workflow/references/completion-controller.md|plugins/assistant-dev/skills/assistant-workflow/references/completion-controller.md"
    "skills/assistant-workflow/references/plan-template.md|plugins/assistant-dev/skills/assistant-workflow/references/plan-template.md"
    "skills/assistant-workflow/references/subagent-dispatch.md|plugins/assistant-dev/skills/assistant-workflow/references/subagent-dispatch.md"
    "skills/assistant-workflow/references/task-journal-template.md|plugins/assistant-dev/skills/assistant-workflow/references/task-journal-template.md"
    "skills/assistant-workflow/references/triage-rubric.md|plugins/assistant-dev/skills/assistant-workflow/references/triage-rubric.md"
    "skills/assistant-workflow/references/sub-task-brief-template.md|plugins/assistant-dev/skills/assistant-workflow/references/sub-task-brief-template.md"
    "skills/assistant-workflow/references/context-handoff-templates.md|plugins/assistant-dev/skills/assistant-workflow/references/context-handoff-templates.md"
    "skills/assistant-workflow/references/mega-and-patterns.md|plugins/assistant-dev/skills/assistant-workflow/references/mega-and-patterns.md"
)
workflow_unsynced_pairs=()
for pair in "${workflow_sync_pairs[@]}"; do
    IFS='|' read -r root_path plugin_path <<< "$pair"
    if ! cmp -s "$FRAMEWORK_DIR/$root_path" "$FRAMEWORK_DIR/$plugin_path"; then
        workflow_unsynced_pairs+=("$root_path != $plugin_path")
    fi
done
if [[ "${#workflow_unsynced_pairs[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-workflow root/plugin mirrors differ: ${workflow_unsynced_pairs[*]}"
fi

test_start "workflow task journal template anchors native dispatch evidence to Created identity"
missing_task_identity_terms=()
task_journal_template_surfaces=(
    "skills/assistant-workflow/references/task-journal-template.md"
    "plugins/assistant-dev/skills/assistant-workflow/references/task-journal-template.md"
)
for surface in "${task_journal_template_surfaces[@]}"; do
    file="$FRAMEWORK_DIR/$surface"
    if [[ ! -f "$file" ]]; then
        missing_task_identity_terms+=("$surface: file missing")
        continue
    fi
    if ! awk '
        BEGIN { found_task = 0; ok = 0 }
        /^## Task:/ {
            found_task = 1
            getline
            if ($0 ~ /^Created: / && NR <= 35) ok = 1
            exit
        }
        END { exit (found_task && ok) ? 0 : 1 }
    ' "$file"; then
        missing_task_identity_terms+=("$surface: Created must immediately follow ## Task near top")
    fi
    for term in \
        "Native dispatch evidence:" \
        "agent id, task name, thread, or tool result" \
        "bind it to this journal's \`Created:\` identity"; do
        if ! grep -Fq -- "$term" "$file"; then
            missing_task_identity_terms+=("$surface: $term")
        fi
    done
done
if [[ "${#missing_task_identity_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "task-journal-template.md must anchor native dispatch evidence to Created identity: ${missing_task_identity_terms[*]}"
fi

test_start "workflow subagent policy state dispatches from instruction triggers before fallback"
missing_workflow_subagent_gate=()
workflow_subagent_gate_surfaces=(
    "skills/assistant-workflow/SKILL.md"
    "skills/assistant-workflow/contracts/index.yaml"
    "skills/assistant-workflow/contracts/input.yaml"
    "skills/assistant-workflow/contracts/output.yaml"
    "skills/assistant-workflow/contracts/phase-gates.yaml"
    "skills/assistant-workflow/references/subagent-dispatch.md"
    "skills/assistant-workflow/references/task-journal-template.md"
    "skills/assistant-workflow/references/phases.md"
)
for surface in "${workflow_subagent_gate_surfaces[@]}"; do
    if [[ ! -f "$FRAMEWORK_DIR/$surface" ]]; then
        missing_workflow_subagent_gate+=("$surface: file missing")
    fi
done
workflow_subagent_gate_terms=(
    "skills/assistant-workflow/SKILL.md|subagent_policy_state"
    "skills/assistant-workflow/SKILL.md|subagent_execution_mode"
    "skills/assistant-workflow/SKILL.md|subagent_trigger_scope"
    "skills/assistant-workflow/SKILL.md|direct user request or applicable \`AGENTS.md\` or active-skill instruction"
    "skills/assistant-workflow/SKILL.md|dispatch the configured role agents without a separate permission question"
    "skills/assistant-workflow/SKILL.md|delegation_triggered"
    "skills/assistant-workflow/SKILL.md|do not infer unavailability merely because no visible tool is named \`Task\`, \`delegate\`, or \`subagent\`"
    "skills/assistant-workflow/contracts/index.yaml|id: workflow-delegation-fields"
    "skills/assistant-workflow/contracts/index.yaml|names: [required_agents, subagent_policy_state, subagent_execution_mode, subagent_trigger_scope, policy_blocking_source]"
    "skills/assistant-workflow/contracts/input.yaml|subagent_policy_state"
    "skills/assistant-workflow/contracts/input.yaml|delegation_triggered"
    "skills/assistant-workflow/contracts/input.yaml|delegation_opted_out"
    "skills/assistant-workflow/contracts/input.yaml|subagent_execution_mode"
    "skills/assistant-workflow/contracts/input.yaml|direct_fallback"
    "skills/assistant-workflow/contracts/input.yaml|not_applicable is invalid for Build"
    "skills/assistant-workflow/contracts/input.yaml|Code Writer, Builder/Tester, and Code Reviewer"
    "skills/assistant-workflow/contracts/input.yaml|Reviewer may satisfy only compatibility routing"
    "skills/assistant-workflow/contracts/input.yaml|subagent_trigger_scope"
    "skills/assistant-workflow/contracts/output.yaml|subagent_policy_state"
    "skills/assistant-workflow/contracts/output.yaml|subagent_execution_mode"
    "skills/assistant-workflow/contracts/output.yaml|subagent_trigger_scope"
    "skills/assistant-workflow/contracts/output.yaml|- name: subagent_evidence"
    "skills/assistant-workflow/contracts/output.yaml|Evidence matches build_execution_lane"
    "skills/assistant-workflow/contracts/output.yaml|per_slice_dispatch_evidence"
    "skills/assistant-workflow/contracts/output.yaml|delegation_opted_out, subagents_unavailable, or policy_disallowed"
    "skills/assistant-workflow/contracts/phase-gates.yaml|D_SUBAGENT_TRIGGER"
    "skills/assistant-workflow/contracts/phase-gates.yaml|delegated dispatch without a separate permission question"
    "skills/assistant-workflow/contracts/phase-gates.yaml|direct_fallback with delegation_opted_out"
    "skills/assistant-workflow/contracts/phase-gates.yaml|B_SUBAGENT_EVIDENCE"
    "skills/assistant-workflow/contracts/phase-gates.yaml|B_SUBAGENT_SLICE_EVIDENCE"
    "skills/assistant-workflow/references/subagent-dispatch.md|Delegation Policy State"
    "skills/assistant-workflow/references/subagent-dispatch.md|direct user request or applicable \`AGENTS.md\` or active-skill instruction"
    "skills/assistant-workflow/references/subagent-dispatch.md|without a separate permission question"
    "skills/assistant-workflow/references/subagent-dispatch.md|For Codex, current CLI/app releases support native subagent workflows by default"
    "skills/assistant-workflow/references/subagent-dispatch.md|Do not mark \`subagents_unavailable\` merely because the visible tool list lacks a tool named \`Task\`, \`delegate\`, or \`subagent\`"
    "skills/assistant-workflow/references/subagent-dispatch.md|MUST dispatch that role"
    "skills/assistant-workflow/references/subagent-dispatch.md|MUST NOT spawn subagents"
    "skills/assistant-workflow/references/subagent-dispatch.md|direct fallback evidence"
    "skills/assistant-workflow/references/subagent-roles.md|Current Codex CLI/app releases support native subagent workflows by default"
    "skills/assistant-workflow/references/subagent-roles.md|Spawn the code-writer agent"
    "skills/assistant-workflow/references/subagent-roles.md|do not look for a visible Claude-style \`Agent\` tool"
    "skills/assistant-workflow/references/subagent-roles.md|optional limits; absence of those settings is not proof that subagents are unavailable"
    "skills/assistant-workflow/references/subagent-dispatch.md|Evidence gate for standard/strict work"
    "skills/assistant-workflow/references/task-journal-template.md|Agent Dispatch Log"
    "skills/assistant-workflow/references/task-journal-template.md|Code Mapper dispatch"
    "skills/assistant-workflow/references/task-journal-template.md|Reviewer dispatch"
    "skills/assistant-workflow/references/task-journal-template.md|not required"
    "skills/assistant-workflow/references/task-journal-template.md|Code Writer dispatch"
    "skills/assistant-workflow/references/task-journal-template.md|Builder/Tester dispatch/result/direct evidence"
    "skills/assistant-workflow/references/task-journal-template.md|Direct fallback reason"
    "skills/assistant-workflow/references/phases.md|Resolve \`subagent_policy_state\`, \`subagent_execution_mode\`, and \`subagent_trigger_scope\` before spawning any subagent"
    "skills/assistant-workflow/references/phases.md|add Code Mapper to \`Required agents\`"
    "skills/assistant-workflow/references/phases.md|Add Code Reviewer to \`Required agents\` before Stage 2"
    "skills/assistant-workflow/references/phases.md|\`assistant-review\` SKILL.md and contracts"
    "skills/assistant-workflow/references/phases.md|any Reviewer compatibility routing"
    "skills/assistant-workflow/references/phases.md|subagent_execution_mode=delegated"
    "skills/assistant-workflow/references/build-worker-protocol.md|Direct fallback mode"
    "skills/assistant-workflow/references/build-worker-protocol.md|Silent fallback cannot complete"
)
for pair in "${workflow_subagent_gate_terms[@]}"; do
    IFS='|' read -r root_surface term <<< "$pair"
    for surface in "$root_surface"; do
        if [[ -f "$FRAMEWORK_DIR/$surface" ]] && ! p0p4_contains_text "$FRAMEWORK_DIR/$surface" "$term"; then
            missing_workflow_subagent_gate+=("$surface: $term")
        fi
    done
done
if grep -Fq -- "Add Reviewer to \`Required agents\` before Stage 2" "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"; then
    missing_workflow_subagent_gate+=("skills/assistant-workflow/references/phases.md: stale bare Reviewer Stage 2 required-agent wording")
fi
if [[ "${#missing_workflow_subagent_gate[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-workflow must resolve subagent policy state before delegated or direct fallback execution: ${missing_workflow_subagent_gate[*]}"
fi

test_start "workflow delegation fallback requires trigger evidence or policy block"
workflow_delegation_proof_failures=()
workflow_delegation_proof_terms=(
    "skills/assistant-workflow/contracts/input.yaml|policy_blocking_source"
    "skills/assistant-workflow/contracts/input.yaml|subagent_policy_state == policy_disallowed"
    "skills/assistant-workflow/contracts/input.yaml|When required_agents is non-empty"
    "skills/assistant-workflow/contracts/input.yaml|direct user, applicable AGENTS.md, or active skill instruction"
    "skills/assistant-workflow/contracts/output.yaml|policy_blocking_source"
    "skills/assistant-workflow/contracts/output.yaml|policy_disallowed"
    "skills/assistant-workflow/contracts/phase-gates.yaml|policy_blocking_source"
    "skills/assistant-workflow/contracts/phase-gates.yaml|no applicable trigger exception"
    "skills/assistant-workflow/references/subagent-dispatch.md|direct user request or applicable \`AGENTS.md\` or active-skill instruction"
    "skills/assistant-workflow/references/subagent-dispatch.md|policy_blocking_source"
    "skills/assistant-workflow/references/subagent-dispatch.md|active skill requires subagents"
    "skills/assistant-workflow/references/task-journal-template.md|Policy blocking source"
    "skills/assistant-workflow/references/plan-template.md|Policy blocking source"
    "skills/assistant-workflow/evals/cases.json|workflow-required-roles-dispatch-from-instruction-trigger"
    "skills/assistant-workflow/evals/cases.json|delegation_triggered"
    "skills/assistant-workflow/evals/cases.json|direct user, applicable AGENTS.md, or active skill instruction"
    "skills/assistant-workflow/evals/cases.json|policy_blocking_source"
)
for pair in "${workflow_delegation_proof_terms[@]}"; do
    IFS='|' read -r root_surface term <<< "$pair"
    for surface in "$root_surface"; do
        if [[ ! -f "$FRAMEWORK_DIR/$surface" ]]; then
            workflow_delegation_proof_failures+=("$surface: file missing")
        elif ! p0p4_contains_text "$FRAMEWORK_DIR/$surface" "$term"; then
            workflow_delegation_proof_failures+=("$surface: $term")
        fi
    done
done
if [[ "${#workflow_delegation_proof_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow delegation fallback must carry trigger or policy-block evidence: ${workflow_delegation_proof_failures[*]}"
fi

test_start "workflow loads the delegation trigger invariant"
workflow_trigger_invariant_failures=()
for surface_and_term in \
    "skills/assistant-workflow/contracts/index.yaml|INV_SUBAGENT_TRIGGER_STATE" \
    "skills/assistant-workflow/contracts/phase-gates.yaml|- id: INV_SUBAGENT_TRIGGER_STATE" \
    "skills/assistant-workflow/contracts/phase-gates.yaml|direct user, applicable AGENTS.md, or active skill instruction" \
    "skills/assistant-workflow/contracts/phase-gates.yaml|direct_fallback only after delegation_opted_out, subagents_unavailable after a real spawn failure or supported configuration proof, or policy_disallowed with policy_blocking_source"; do
    IFS='|' read -r root_surface term <<< "$surface_and_term"
    for surface in "$root_surface"; do
        if [[ ! -f "$FRAMEWORK_DIR/$surface" ]]; then
            workflow_trigger_invariant_failures+=("$surface: file missing")
        elif ! p0p4_contains_text "$FRAMEWORK_DIR/$surface" "$term"; then
            workflow_trigger_invariant_failures+=("$surface: $term")
        fi
    done
done
if [[ "${#workflow_trigger_invariant_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow must load a trigger-state invariant for every phase: ${workflow_trigger_invariant_failures[*]}"
fi

test_start "delegation recovery preserves evidenced fallback and dispatches only from triggers"
delegation_recovery_failures=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml::Otherwise preserve and complete the evidenced fallback state" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml::applicable trigger exists" \
    "$FRAMEWORK_DIR/skills/assistant-thinking/contracts/phase-gates.yaml::Otherwise preserve and complete the evidenced sequential fallback state" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml::Otherwise preserve and complete the evidenced direct fallback state" \
    "$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json::active workflow instruction and its covered roles" \
    "$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json::direct-user opt-out is recorded only in subagent_policy_state=delegation_opted_out"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        delegation_recovery_failures+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#delegation_recovery_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "delegation recovery can overwrite opt-out or dispatch without a trigger: ${delegation_recovery_failures[*]}"
fi

test_start "active delegation surfaces exclude retired state identifiers"
retired_delegation_identifiers=(
    "authorization""_required"
    "subagent""_authorization_scope"
    "delegation""_authorized"
    "authorization""_denied"
)
active_delegation_surfaces=(
    "$FRAMEWORK_DIR/skills/assistant-workflow"
    "$FRAMEWORK_DIR/skills/assistant-thinking"
    "$FRAMEWORK_DIR/skills/assistant-review"
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow"
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-review"
    "$FRAMEWORK_DIR/plugins/assistant-research/skills/assistant-thinking"
    "$FRAMEWORK_DIR/install.sh"
    "$FRAMEWORK_DIR/install.ps1"
    "$FRAMEWORK_DIR/docs/troubleshooting-subagents.md"
    "$FRAMEWORK_DIR/docs/v0.3.0-research-improvements.md"
    "$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json"
    "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json"
    "$FRAMEWORK_DIR/skills/assistant-thinking/evals/cases.json"
    "$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json"
)
retired_delegation_matches=()
for identifier in "${retired_delegation_identifiers[@]}"; do
    if matches="$(rg -n -F -- "$identifier" "${active_delegation_surfaces[@]}" 2>/dev/null)"; then
        retired_delegation_matches+=("$matches")
    fi
done
if [[ "${#retired_delegation_matches[@]}" -eq 0 ]]; then
    pass
else
    fail "retired delegation identifiers remain on active surfaces: ${retired_delegation_matches[*]}"
fi

test_start "workflow Codex subagent docs do not require stale multi_agent feature flag"
missing_codex_subagent_doc_terms=()
for term in \
    "docs/v0.3.0-research-improvements.md|native subagent workflow" \
    "docs/v0.3.0-research-improvements.md|Current Codex CLI/app releases enable native subagent workflows by default" \
    "docs/v0.3.0-research-improvements.md|optional tuning knobs, not required enablers"; do
    IFS='|' read -r surface expected <<< "$term"
    if [[ ! -f "$FRAMEWORK_DIR/$surface" ]] || ! grep -Fq -- "$expected" "$FRAMEWORK_DIR/$surface"; then
        missing_codex_subagent_doc_terms+=("$surface: $expected")
    fi
done
if grep -Fq -- "features.multi_agent = true" "$FRAMEWORK_DIR/docs/v0.3.0-research-improvements.md"; then
    missing_codex_subagent_doc_terms+=("docs/v0.3.0-research-improvements.md: stale features.multi_agent = true")
fi
if [[ "${#missing_codex_subagent_doc_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "Codex subagent docs should match current native subagent behavior: ${missing_codex_subagent_doc_terms[*]}"
fi

test_start "workflow live output plan and decomposition review reject stale sub-task framing"
live_slice_framing_surfaces=(
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/plan-template.md"
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/decomposition-plan-review.md"
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/contracts/output.yaml"
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/references/plan-template.md"
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/references/decomposition-plan-review.md"
)
missing_live_slice_framing_surfaces=()
for file in "${live_slice_framing_surfaces[@]}"; do
    if [[ ! -f "$file" ]]; then
        missing_live_slice_framing_surfaces+=("${file#$FRAMEWORK_DIR/}")
    fi
done
stale_live_slice_framing_file="$(mktemp "${TMPDIR:-/tmp}/workflow-live-slice-framing-stale.XXXXXX")"
p0p4_register_cleanup "$stale_live_slice_framing_file"
if [[ "${#missing_live_slice_framing_surfaces[@]}" -gt 0 ]]; then
    fail "live slice framing surfaces missing: ${missing_live_slice_framing_surfaces[*]}"
elif rg -n --ignore-case "sub-task|subtask" "${live_slice_framing_surfaces[@]}" >"$stale_live_slice_framing_file"; then
    fail "live output/plan/decomposition review surfaces contain stale sub-task/subtask framing; see $stale_live_slice_framing_file"
else
    pass
fi

test_start "workflow decomposition review requires broad-split rejection proof"
missing_broad_split_review_terms=()
plan_broad_split_count="$(grep -Fc -- "- Broad-split rejection:" "$FRAMEWORK_DIR/skills/assistant-workflow/references/plan-template.md" || true)"
if [[ "$plan_broad_split_count" -lt 2 ]]; then
    missing_broad_split_review_terms+=("plan-template.md medium/full Broad-split rejection lines")
fi
for file in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml" \
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/contracts/phase-gates.yaml"; do
    for term in \
        "- id: DC8" \
        "broad_split_rejection proof" \
        "broad layer/module/folder/feature/setup/contract/component splits were rejected"; do
        if ! grep -Fq -- "$term" "$file"; then
            missing_broad_split_review_terms+=("${file#$FRAMEWORK_DIR/}: $term")
        fi
    done
done
for file in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md" \
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/references/phases.md"; do
    for term in \
        "Broad-split rejection" \
        "Broad-split rejection must explicitly prove broad layer/module/folder/feature/setup/contract/component splits were rejected"; do
        if ! grep -Fq -- "$term" "$file"; then
            missing_broad_split_review_terms+=("${file#$FRAMEWORK_DIR/}: $term")
        fi
    done
done
for term in \
    "- name: broad_split_rejection" \
    "feature-only, setup-only, contract-only" \
    "broad component-style splits were rejected"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"; then
        missing_broad_split_review_terms+=("output.yaml: $term")
    fi
done
if ! awk '
    $0 == "  - name: decomposition_plan_review" { in_review = 1; next }
    in_review && /^  - name: / { exit }
    in_review && $0 == "      - name: broad_split_rejection" { in_field = 1; next }
    in_field && /required: true/ { found = 1; exit }
    in_field && /^      - name: / { in_field = 0 }
    END { exit found ? 0 : 1 }
' "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"; then
    missing_broad_split_review_terms+=("output.yaml decomposition_plan_review.broad_split_rejection required: true")
fi
if [[ "${#missing_broad_split_review_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "broad-split rejection proof contract missing terms: ${missing_broad_split_review_terms[*]}"
fi

test_start "workflow phase gates require recorded slice evidence before advancing"
missing_slice_gate_terms=()
for term in \
    "- id: B12" \
    "independently checked, passing, and recorded with command/result evidence in the task journal, validation_results, or equivalent carried-forward slice ledger" \
    "record command/result evidence in the configured task journal or equivalent carried-forward state" \
    "- id: B13" \
    "each slice has a final status of VERIFIED, including self-check result, before the next slice started" \
    "slices must be verified sequentially with evidence before advancing"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"; then
        missing_slice_gate_terms+=("$term")
    fi
done
if [[ "${#missing_slice_gate_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "phase-gates.yaml missing recorded/sequential slice verification gate terms: ${missing_slice_gate_terms[*]}"
fi

test_start "workflow handoffs pass current task packets to CodeWriter and BuilderTester"
handoffs_file="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml"
task_packet_handoffs="$(count_occurrences "name: current_task_packet" "$handoffs_file")"
missing_task_packet_fields=()
for field in \
    slice_id \
    slice_name \
    name \
    acceptance_criteria \
    files_to_test \
    evidence_to_record \
    verification_command \
    expected_success_signal; do
    if ! grep -Fq -- "name: $field" "$handoffs_file"; then
        missing_task_packet_fields+=("$field")
    fi
done
if [[ "$task_packet_handoffs" -ge 2 && "${#missing_task_packet_fields[@]}" -eq 0 ]]; then
    pass
else
    fail "handoffs.yaml must define CodeWriter and BuilderTester current_task_packet fields; count=$task_packet_handoffs missing=${missing_task_packet_fields[*]}"
fi

handoff_context_field_has_direct_line() {
    local file="$1"
    local handoff="$2"
    local field="$3"
    local expected="$4"
    awk -v handoff="$handoff" -v field="$field" -v expected="$expected" '
        $0 == "  - name: " handoff { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && /^    context_fields:/ { in_context = 1; next }
        in_context && /^    return_fields:/ { exit }
        in_context && $0 == "      - name: " field { in_field = 1; next }
        in_field && /^        object_fields:/ { exit }
        in_field && index($0, expected) { found = 1; exit }
        in_field && /^      - name: / { exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

test_start "workflow handoffs require conditional slice manifest and current task packets"
missing_conditional_handoff_terms=()
for file in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml" \
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/contracts/handoffs.yaml"; do
    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_architect" "slice_manifest" "required: conditional"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: architect slice_manifest required: conditional")
    fi
    if handoff_context_field_has_direct_line "$file" "orchestrator_to_architect" "slice_manifest" "required: false"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: architect slice_manifest must not be required: false")
    fi
    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_architect" "slice_manifest" "size in [medium, large, mega] or the approved plan will use executable task packets"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: architect slice_manifest condition")
    fi
    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_architect" "slice_manifest" "on_missing: re-dispatch"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: architect slice_manifest on_missing")
    fi
    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_architect" "slice_manifest" "Block Architect dispatch"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: architect slice_manifest corrective text")
    fi

    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_code_writer" "current_task_packet" "required: conditional"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: CodeWriter current_task_packet required: conditional")
    fi
    if handoff_context_field_has_direct_line "$file" "orchestrator_to_code_writer" "current_task_packet" "required: false"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: CodeWriter current_task_packet must not be required: false")
    fi
    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_code_writer" "current_task_packet" "current build step executes a slice or the approved plan uses executable task packets"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: CodeWriter current_task_packet condition")
    fi
    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_code_writer" "current_task_packet" "on_missing: fail"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: CodeWriter current_task_packet on_missing")
    fi
    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_code_writer" "current_task_packet" "Block CodeWriter dispatch"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: CodeWriter current_task_packet corrective text")
    fi

    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_builder_tester" "current_task_packet" "required: conditional"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: BuilderTester current_task_packet required: conditional")
    fi
    if handoff_context_field_has_direct_line "$file" "orchestrator_to_builder_tester" "current_task_packet" "required: false"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: BuilderTester current_task_packet must not be required: false")
    fi
    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_builder_tester" "current_task_packet" "current verification step executes a slice or the approved plan uses executable task packets"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: BuilderTester current_task_packet condition")
    fi
    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_builder_tester" "current_task_packet" "on_missing: fail"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: BuilderTester current_task_packet on_missing")
    fi
    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_builder_tester" "current_task_packet" "Block BuilderTester dispatch"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: BuilderTester current_task_packet corrective text")
    fi
done
if [[ "${#missing_conditional_handoff_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "handoffs.yaml must conditionally require slice/task packet handoff fields: ${missing_conditional_handoff_terms[*]}"
fi

test_start "workflow architect plan handoff requires task packet execution fields"
missing_required_fields=()
for file in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml" \
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/contracts/handoffs.yaml"; do
    for field in \
        slice_id \
        slice_name \
        name \
        observable_increment \
        deliverable_type \
        files_to_create \
        files_to_modify \
        files_to_test \
        enabling_changes_included \
        depends_on \
        tdd_applies \
        acceptance_criteria \
        implementation_notes \
        verification_command \
        expected_success_signal \
        evidence_to_record \
        deviation_rollback_rule; do
        if ! field_required_true_after_anchor "$file" "- name: implementation_steps" "$field"; then
            missing_required_fields+=("${file#$FRAMEWORK_DIR/}: $field")
        fi
    done
done
if [[ "${#missing_required_fields[@]}" -eq 0 ]]; then
    pass
else
    fail "architect implementation_steps must require executable task packet fields: ${missing_required_fields[*]}"
fi

handoff_object_required_fields() {
    local file="$1"
    local handoff="$2"
    local section="$3"
    local object_field="$4"

    awk -v handoff="$handoff" -v section="$section" -v object_field="$object_field" '
        $0 == "  - name: " handoff { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && $0 == "    " section ":" { in_section = 1; next }
        in_section && /^    (context_fields|return_fields):/ { exit }
        in_section && $0 == "      - name: " object_field { in_object = 1; current = ""; next }
        in_object && /^      - name: / { exit }
        in_object && /^          - name: / {
            current = $0
            sub(/^          - name: /, "", current)
            next
        }
        in_object && current != "" && /^            required: true/ {
            print current
            current = ""
        }
    ' "$file"
}

field_in_required_list() {
    local needle="$1"
    shift

    local field
    for field in "$@"; do
        if [[ "$field" == "$needle" ]]; then
            return 0
        fi
    done

    return 1
}

test_start "workflow Architect implementation_steps cover consumer current_task_packet required fields"
missing_packet_coverage=()
for file in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml" \
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/contracts/handoffs.yaml"; do
    architect_required=()
    while IFS= read -r field; do
        architect_required+=("$field")
    done < <(handoff_object_required_fields "$file" "orchestrator_to_architect" "return_fields" "implementation_steps")
    if [[ "${#architect_required[@]}" -eq 0 ]]; then
        missing_packet_coverage+=("${file#$FRAMEWORK_DIR/}: Architect implementation_steps required field set is empty")
        continue
    fi

    for consumer in \
        "orchestrator_to_code_writer:CodeWriter" \
        "orchestrator_to_builder_tester:BuilderTester"; do
        IFS=':' read -r handoff consumer_name <<< "$consumer"
        consumer_required=()
        while IFS= read -r field; do
            consumer_required+=("$field")
        done < <(handoff_object_required_fields "$file" "$handoff" "context_fields" "current_task_packet")
        if [[ "${#consumer_required[@]}" -eq 0 ]]; then
            missing_packet_coverage+=("${file#$FRAMEWORK_DIR/}: ${consumer_name} current_task_packet required field set is empty")
            continue
        fi

        for field in "${consumer_required[@]}"; do
            if ! field_in_required_list "$field" "${architect_required[@]}"; then
                missing_packet_coverage+=("${file#$FRAMEWORK_DIR/}: Architect implementation_steps missing required ${consumer_name} current_task_packet.$field")
            fi
        done
    done
done
if [[ "${#missing_packet_coverage[@]}" -eq 0 ]]; then
    pass
else
    fail "Architect implementation_steps producer must cover consumer current_task_packet required fields: ${missing_packet_coverage[*]}"
fi

reuse_search_schema_signature() {
    local file="$1"
    local handoff="$2"
    local section="$3"
    local container="$4"

    awk -v handoff="$handoff" -v section="$section" -v container="$container" '
        function indent(line) { match(line, /^ */); return RLENGTH }
        $0 == "  - name: " handoff { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && $0 == "    " section ":" { in_section = 1; next }
        in_section && /^    (context_fields|return_fields):/ && $0 != "    " section ":" { exit }
        !in_section { next }
        container == "" && $0 == "      - name: reuse_search" { in_target = 1; target_indent = indent($0); next }
        container != "" && $0 == "      - name: " container { in_container = 1; next }
        in_container && /^      - name: / && $0 != "      - name: " container { exit }
        in_container && $0 == "          - name: reuse_search" { in_target = 1; target_indent = indent($0); next }
        !in_target { next }
        indent($0) == target_indent && /^ *- name: / { exit }
        /^ *- name: / {
            value = $0
            sub(/^ *- name: /, "", value)
            print "field|" (indent($0) - target_indent) "|" value
            next
        }
        /^ *(type|required|condition|enum_values|min_items): / {
            key = $0
            sub(/^ */, "", key)
            value = key
            sub(/^[^:]+: /, "", value)
            sub(/: .*/, "", key)
            print "attribute|" (indent($0) - target_indent) "|" key "|" value
        }
    ' "$file"
}

test_start "reuse-search schema is identical across mapper, task-packet, build, and review boundaries"
reuse_search_packet_failures=()
workflow_handoffs="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml"
review_handoffs="$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml"
canonical_reuse_search_schema="$(reuse_search_schema_signature "$workflow_handoffs" "orchestrator_to_code_mapper" "return_fields" "")"
if [[ -z "$canonical_reuse_search_schema" ]]; then
    reuse_search_packet_failures+=("CodeMapper return reuse_search schema is empty")
fi
for boundary in \
    "Architect input:$workflow_handoffs:orchestrator_to_architect:context_fields:" \
    "Architect implementation_steps:$workflow_handoffs:orchestrator_to_architect:return_fields:implementation_steps" \
    "CodeWriter current_task_packet:$workflow_handoffs:orchestrator_to_code_writer:context_fields:current_task_packet" \
    "BuilderTester current_task_packet:$workflow_handoffs:orchestrator_to_builder_tester:context_fields:current_task_packet" \
    "Reviewer return:$review_handoffs:orchestrator_to_reviewer:return_fields:"; do
    IFS=':' read -r boundary_name boundary_file boundary_handoff boundary_section boundary_container <<< "$boundary"
    boundary_schema="$(reuse_search_schema_signature "$boundary_file" "$boundary_handoff" "$boundary_section" "$boundary_container")"
    if [[ "$boundary_schema" != "$canonical_reuse_search_schema" ]]; then
        reuse_search_packet_failures+=("$boundary_name reuse_search schema differs from CodeMapper return")
    fi
done
if [[ "${#reuse_search_packet_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "reuse-search schema parity failed: ${reuse_search_packet_failures[*]}"
fi

test_start "workflow mega sub-task brief uses strict slice packet contract"
sub_task_template="$FRAMEWORK_DIR/skills/assistant-workflow/references/sub-task-brief-template.md"
missing_sub_task_packet_terms=()
for term in \
    "### Strict slice packet (execution contract)" \
    "Supporting context below cannot satisfy or override these fields" \
    "loose Goal/Scope prose" \
    "- slice_id:" \
    "- slice_name:" \
    "- observable_increment:" \
    "- deliverable_type:" \
    "- files_to_create:" \
    "- files_to_modify:" \
    "- files_to_test:" \
    "- enabling_changes_included:" \
    "- depends_on:" \
    "- acceptance_criteria:" \
    "- verification_command:" \
    "- expected_success_signal:" \
    "- evidence_to_record:" \
    "- deviation_rollback_rule:" \
    "### Supporting context (not the execution contract)" \
    "DEVIATED" \
    "deviation_rollback_rule applied"; do
    if ! grep -Fq -- "$term" "$sub_task_template"; then
        missing_sub_task_packet_terms+=("$term")
    fi
done
if rg -n "^### (Goal|Scope)$" "$sub_task_template" >/dev/null; then
    missing_sub_task_packet_terms+=("loose Goal/Scope execution sections must be absent")
fi
if [[ "${#missing_sub_task_packet_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "sub-task-brief-template.md missing strict slice packet contract terms: ${missing_sub_task_packet_terms[*]}"
fi

test_start "workflow reference templates reject stale sub-task branch and brief examples"
reference_template_surfaces=(
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/sub-task-brief-template.md"
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/context-handoff-templates.md"
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/references/sub-task-brief-template.md"
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/references/context-handoff-templates.md"
)
stale_reference_template_file="$(mktemp "${TMPDIR:-/tmp}/workflow-reference-template-stale.XXXXXX")"
p0p4_register_cleanup "$stale_reference_template_file"
if rg -n "sub-task|Sub-Task|briefs/sub-task-[^[:space:]]*\\.md|briefs/sub-task-\\*\\.md|feature/\\[mega-task\\]/sub-task|Sub-Task Brief from the decomposition phase|Completed sub-tasks|Merge all sub-task branches|Wire components together|Shared contracts:" \
    "${reference_template_surfaces[@]}" >"$stale_reference_template_file"; then
    fail "reference templates contain stale sub-task branch/brief examples or integration wording; see $stale_reference_template_file"
else
    pass
fi

test_start "workflow live decomposition scripts consume and emit strict slices"
live_slice_script_surfaces=(
    "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/decompose.sh"
    "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh"
    "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/check-integration.sh"
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/scripts/decompose.sh"
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/scripts/run-agents.sh"
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/scripts/check-integration.sh"
)
missing_live_slice_terms=()
for file in "${live_slice_script_surfaces[@]}"; do
    if [[ ! -f "$file" ]]; then
        missing_live_slice_terms+=("missing script: $file")
    fi
done
for file in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/decompose.sh" \
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/scripts/decompose.sh"; do
    for term in \
        '"slice_manifest"' \
        "Invalid JSON: must have a non-empty 'slice_manifest' array" \
        "single_slice_rationale must be present and non-blank" \
        'INTEGRATION_BRANCH="${TASK_BRANCH_PREFIX}/integration"' \
        'SLICE_BRANCH_PREFIX="${TASK_BRANCH_PREFIX}/slice-"' \
        "Invalid slice_id values" \
        "Duplicate slice_id values" \
        "Unknown depends_on references" \
        "Self dependency detected" \
        "Circular dependency detected" \
        "Creating dependency-free slice branches" \
        "Deferring branch" \
        "created at launch after dependencies are VERIFIED" \
        "Single-slice rationale:" \
        'BRIEF_FILE="$BRIEFS_DIR/slice-${NUM}-${SLICE_ID}.md"' \
        "### Strict slice packet (execution contract)" \
        "Supporting context may help orientation, but it cannot satisfy, replace, or override the strict slice packet above." \
        "- slice_id:" \
        "- slice_name:" \
        "- observable_increment:" \
        "- deliverable_type:" \
        "- files_to_create:" \
        "- files_to_modify:" \
        "- files_to_test:" \
        "- enabling_changes_included:" \
        "- depends_on:" \
        "- acceptance_criteria:" \
        "- verification_command:" \
        "- expected_success_signal:" \
        "- evidence_to_record:" \
        "- deviation_rollback_rule:" \
        "End with an explicit slice report" \
        "Dependency order comes from depends_on" \
        "Standalone contract/setup work is valid only when this slice itself is the verified deliverable artifact."; do
        if ! grep -Fq -- "$term" "$file"; then
            missing_live_slice_terms+=("$(basename "$file"): $term")
        fi
    done
done
for file in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" \
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/scripts/run-agents.sh"; do
    for term in \
        'find "$BRIEFS_DIR" -maxdepth 1 -name "slice-*.md"' \
        "find_ordered_slice_briefs" \
        "No slice brief files found" \
        "Skip slice #1 and treat its slice_id as already VERIFIED" \
        "--verified-slices CSV" \
        "Parallel launch blocked" \
        "Sequential launch blocked" \
        "Use this only when slice #1 is already VERIFIED" \
        "EXTERNALLY_VERIFIED_SLICES" \
        "prove_external_verified_prerequisites" \
        "merge-base --is-ancestor" \
        "External verified-slice proof failed" \
        "not merged into integration branch" \
        "ensure_slice_branch" \
        "verify_slice_log" \
        "## Slice Status: DONE" \
        "result: pass" \
        "merge_verified_slice_into_integration" \
        "reported DONE/pass evidence" \
        "Created branch:" \
        "Promoted verified slice" \
        "Deferred:" \
        "Merge verified slice branches into feature/<task>/integration" \
        "Rerun deferred dependent slices with --verified-slices after prerequisites are merged" \
        "feature/<task>/slice-<slice_id>" \
        "feature/<task>/integration"; do
        if ! grep -Fq -- "$term" "$file"; then
            missing_live_slice_terms+=("$(basename "$file"): $term")
        fi
    done
done
for file in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/check-integration.sh" \
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/scripts/check-integration.sh"; do
    for term in \
        "Validates that all slice branches are ready for integration." \
        "feature/<task>/integration" \
        "feature/<task>/slice-<slice_id>" \
        "No slice branches found" \
        "Expected branches like" \
        "Slice branches have commits beyond integration branch"; do
        if ! grep -Fq -- "$term" "$file"; then
            missing_live_slice_terms+=("$(basename "$file"): $term")
        fi
    done
done
stale_live_slice_file="$(mktemp "${TMPDIR:-/tmp}/workflow-live-slice-stale.XXXXXX")"
p0p4_register_cleanup "$stale_live_slice_file"
if rg -n "\\.sub_tasks|sub_tasks|sub-task-\\*\\.md|sub-task-|Build contracts first|contracts are merged|contract-first|contracts first|### Goal|### Scope" \
    "${live_slice_script_surfaces[@]}" >"$stale_live_slice_file"; then
    missing_live_slice_terms+=("stale live decomposition behavior found; see $stale_live_slice_file")
fi
if [[ "${#missing_live_slice_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "live decomposition scripts must use strict slice manifests and slice briefs: ${missing_live_slice_terms[*]}"
fi

test_start "workflow run-agents numerically orders slices and defers blocked parallel dependencies"
runner_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runner-repo.XXXXXX")"
p0p4_register_cleanup "$runner_repo"
git -C "$runner_repo" init -q
git -C "$runner_repo" config user.email "p0p4@example.invalid"
git -C "$runner_repo" config user.name "P0 P4"
printf 'fixture\n' >"$runner_repo/README.md"
git -C "$runner_repo" add README.md
git -C "$runner_repo" commit -q -m init
git -C "$runner_repo" branch "feature/runner/integration"
runner_briefs="$runner_repo/briefs"
mkdir -p "$runner_briefs"
write_runner_slice_brief() {
    local number="$1"
    local slice_id="$2"
    local deps_csv="$3"
    local brief_file="$runner_briefs/slice-${number}-${slice_id}.md"

    cat >"$brief_file" <<BRIEF
## Slice Brief: ${slice_id}

### Strict slice packet (execution contract)
- slice_id: ${slice_id}
- slice_name: ${slice_id}
- observable_increment: ${slice_id} increment
- deliverable_type: behavior
- files_to_create:
  - none
- files_to_modify:
  - fixture-${slice_id}.txt
- files_to_test:
  - none
- enabling_changes_included:
  - none
- depends_on:
BRIEF
    if [[ "$deps_csv" == "none" ]]; then
        printf '  - none\n' >>"$brief_file"
    else
        IFS=',' read -ra runner_deps <<< "$deps_csv"
        for runner_dep in "${runner_deps[@]}"; do
            trimmed_runner_dep="$(printf '%s' "$runner_dep" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
            printf '  - %s\n' "$trimmed_runner_dep" >>"$brief_file"
        done
    fi
    cat >>"$brief_file" <<BRIEF
- acceptance_criteria:
  - [ ] ${slice_id} criterion passes
- verification_command:
  - true
- expected_success_signal: true exits 0
- evidence_to_record:
  - dry-run result
- deviation_rollback_rule: Return DEVIATED rather than widening the slice

### Supporting context (not the execution contract)
- Git branch: feature/runner/slice-${slice_id}
- Worktree: ${runner_repo}/.worktrees/${slice_id}
BRIEF
}
write_runner_slice_brief 10 late none
write_runner_slice_brief 2 beta alpha
write_runner_slice_brief 1 alpha none
runner_order_out="$runner_repo/order.out"
runner_order_err="$runner_repo/order.err"
runner_parallel_out="$runner_repo/parallel.out"
runner_parallel_err="$runner_repo/parallel.err"
runner_order_expected="$(printf 'slice-1-alpha\nslice-2-beta\nslice-10-late')"
if ! bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$runner_briefs" --repo "$runner_repo" --dry-run >"$runner_order_out" 2>"$runner_order_err"; then
    fail "run-agents.sh sequential dry-run failed unexpectedly: $(tr '\n' ' ' <"$runner_order_err")"
else
    runner_order_actual="$(grep -E "Agent [0-9]+: slice-" "$runner_order_out" | sed -E 's/.*Agent [0-9]+: //')"
    if [[ "$runner_order_actual" != "$runner_order_expected" ]]; then
        fail "run-agents.sh did not use numeric slice order; got: $(printf '%s' "$runner_order_actual" | tr '\n' ' ')"
    elif ! bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$runner_briefs" --repo "$runner_repo" --parallel --dry-run >"$runner_parallel_out" 2>"$runner_parallel_err"; then
        fail "run-agents.sh parallel dry-run failed instead of launching the ready wave: $(tr '\n' ' ' <"$runner_parallel_err")"
    elif ! grep -Fq "Agent 1: slice-1-alpha" "$runner_parallel_out"; then
        fail "run-agents.sh parallel dry-run did not launch dependency-free alpha"
    elif ! grep -Fq "Agent 3: slice-10-late" "$runner_parallel_out"; then
        fail "run-agents.sh parallel dry-run did not launch independent late slice"
    elif grep -Fq "Agent 2: slice-2-beta" "$runner_parallel_out"; then
        fail "run-agents.sh parallel dry-run launched dependency-blocked beta"
    elif ! grep -Fq "Deferring slice 'beta' in this run" "$runner_parallel_out"; then
        fail "run-agents.sh parallel dry-run did not explain deferred beta"
    elif ! grep -Fq "Deferred: 1" "$runner_parallel_out"; then
        fail "run-agents.sh parallel summary did not count deferred slices"
    else
        pass
    fi
fi

test_start "workflow run-agents rejects incomplete old-style unsafe and duplicate strict briefs before launch"
brief_validation_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runner-brief-validation.XXXXXX")"
p0p4_register_cleanup "$brief_validation_repo"
git -C "$brief_validation_repo" init -q
git -C "$brief_validation_repo" config user.email "p0p4@example.invalid"
git -C "$brief_validation_repo" config user.name "P0 P4"
printf 'fixture\n' >"$brief_validation_repo/README.md"
git -C "$brief_validation_repo" add README.md
git -C "$brief_validation_repo" commit -q -m init
brief_validation_target="$(git -C "$brief_validation_repo" branch --show-current)"
brief_validation_target_base="$(git -C "$brief_validation_repo" rev-parse HEAD)"

write_strict_probe_brief() {
    local briefs_dir="$1"
    local file_name="$2"
    local slice_id="$3"
    mkdir -p "$briefs_dir"
    cat >"$briefs_dir/$file_name" <<BRIEF
## Slice Brief: ${slice_id}

### Strict slice packet (execution contract)
- slice_id: ${slice_id}
- slice_name: ${slice_id}
- observable_increment: ${slice_id} increment
- deliverable_type: behavior
- files_to_create:
  - none
- files_to_modify:
  - fixture-${slice_id}.txt
- files_to_test:
  - none
- enabling_changes_included:
  - none
- depends_on:
  - none
- acceptance_criteria:
  - [ ] ${slice_id} criterion passes
- verification_command:
  - true
- expected_success_signal: true exits 0
- evidence_to_record:
  - dry-run result
- deviation_rollback_rule: Return DEVIATED rather than widening the slice

### Supporting context (not the execution contract)
- Git branch: feature/brief-validation/slice-${slice_id}
- Worktree: ${brief_validation_repo}/.worktrees/${slice_id}
BRIEF
}

old_style_briefs="$brief_validation_repo/old-style"
incomplete_briefs="$brief_validation_repo/incomplete"
unsafe_briefs="$brief_validation_repo/unsafe"
duplicate_briefs="$brief_validation_repo/duplicate"
unsafe_verified_briefs="$brief_validation_repo/unsafe-verified"
unsafe_dependency_briefs="$brief_validation_repo/unsafe-dependency"
mkdir -p "$old_style_briefs" "$incomplete_briefs" "$unsafe_briefs" "$duplicate_briefs" "$unsafe_verified_briefs" "$unsafe_dependency_briefs"
cat >"$old_style_briefs/slice-1-old.md" <<'BRIEF'
## Slice Brief: old

### Goal
Do a legacy prose-only task.

### Scope
- fixture.txt
BRIEF
cat >"$incomplete_briefs/slice-1-incomplete.md" <<BRIEF
## Slice Brief: incomplete

### Strict slice packet (execution contract)
- slice_id: incomplete
- slice_name: incomplete
- deliverable_type: behavior
- files_to_create:
  - none
- files_to_modify:
  - fixture-incomplete.txt
- files_to_test:
  - none
- enabling_changes_included:
  - none
- depends_on:
  - none
- acceptance_criteria:
  - [ ] incomplete criterion passes
- verification_command:
  - true
- expected_success_signal: true exits 0
- evidence_to_record:
  - dry-run result
- deviation_rollback_rule: Return DEVIATED rather than widening the slice

### Supporting context (not the execution contract)
- Git branch: feature/brief-validation/slice-incomplete
- Worktree: ${brief_validation_repo}/.worktrees/incomplete
BRIEF
write_strict_probe_brief "$unsafe_briefs" "slice-1-unsafe.md" "bad/id"
write_strict_probe_brief "$duplicate_briefs" "slice-1-duplicate-a.md" "duplicate-id"
write_strict_probe_brief "$duplicate_briefs" "slice-2-duplicate-b.md" "duplicate-id"
write_strict_probe_brief "$unsafe_verified_briefs" "slice-1-safe.md" "safe-id"
cat >"$unsafe_dependency_briefs/slice-1-beta.md" <<BRIEF
## Slice Brief: beta

### Strict slice packet (execution contract)
- slice_id: beta
- slice_name: beta
- observable_increment: beta increment
- deliverable_type: behavior
- files_to_create:
  - none
- files_to_modify:
  - fixture-beta.txt
- files_to_test:
  - none
- enabling_changes_included:
  - none
- depends_on:
  - bad/id
- acceptance_criteria:
  - [ ] beta criterion passes
- verification_command:
  - true
- expected_success_signal: true exits 0
- evidence_to_record:
  - dry-run result
- deviation_rollback_rule: Return DEVIATED rather than widening the slice

### Supporting context (not the execution contract)
- Git branch: feature/brief-validation/slice-beta
- Worktree: ${brief_validation_repo}/.worktrees/beta
BRIEF

old_style_out="$brief_validation_repo/old-style.out"
old_style_err="$brief_validation_repo/old-style.err"
incomplete_out="$brief_validation_repo/incomplete.out"
incomplete_err="$brief_validation_repo/incomplete.err"
unsafe_out="$brief_validation_repo/unsafe.out"
unsafe_err="$brief_validation_repo/unsafe.err"
duplicate_out="$brief_validation_repo/duplicate.out"
duplicate_err="$brief_validation_repo/duplicate.err"
unsafe_verified_out="$brief_validation_repo/unsafe-verified.out"
unsafe_verified_err="$brief_validation_repo/unsafe-verified.err"
unsafe_dependency_out="$brief_validation_repo/unsafe-dependency.out"
unsafe_dependency_err="$brief_validation_repo/unsafe-dependency.err"
if bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$old_style_briefs" --repo "$brief_validation_repo" --dry-run >"$old_style_out" 2>"$old_style_err"; then
    fail "run-agents.sh accepted an old-style prose-only brief"
elif ! grep -Fq -- "missing or empty strict packet field 'slice_id'" "$old_style_err"; then
    fail "old-style brief rejection did not name the missing strict field"
elif grep -Fq -- "Agent " "$old_style_out"; then
    fail "old-style brief launched an agent before strict validation failed"
elif bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$incomplete_briefs" --repo "$brief_validation_repo" --dry-run >"$incomplete_out" 2>"$incomplete_err"; then
    fail "run-agents.sh accepted an incomplete strict packet"
elif ! grep -Fq -- "missing or empty strict packet field 'observable_increment'" "$incomplete_err"; then
    fail "incomplete strict packet rejection did not name observable_increment"
elif grep -Fq -- "Agent " "$incomplete_out"; then
    fail "incomplete strict packet launched an agent before strict validation failed"
elif bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$unsafe_briefs" --repo "$brief_validation_repo" --dry-run >"$unsafe_out" 2>"$unsafe_err"; then
    fail "run-agents.sh accepted an unsafe slice_id"
elif ! grep -Fq -- "Invalid slice_id 'bad/id'" "$unsafe_err"; then
    fail "unsafe slice_id rejection was not actionable"
elif grep -Fq -- "Agent " "$unsafe_out"; then
    fail "unsafe slice_id launched an agent before strict validation failed"
elif bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$duplicate_briefs" --repo "$brief_validation_repo" --dry-run >"$duplicate_out" 2>"$duplicate_err"; then
    fail "run-agents.sh accepted duplicate slice_id values"
elif ! grep -Fq -- "Duplicate slice_id 'duplicate-id'" "$duplicate_err"; then
    fail "duplicate slice_id rejection was not actionable"
elif grep -Fq -- "Agent " "$duplicate_out"; then
    fail "duplicate slice_id launched an agent before strict validation failed"
elif bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$unsafe_verified_briefs" --repo "$brief_validation_repo" --verified-slices bad/id --dry-run >"$unsafe_verified_out" 2>"$unsafe_verified_err"; then
    fail "run-agents.sh accepted an unsafe --verified-slices token"
elif ! grep -Fq -- "Invalid --verified-slices value 'bad/id'" "$unsafe_verified_err"; then
    fail "unsafe --verified-slices rejection was not actionable"
elif grep -Fq -- "Agent " "$unsafe_verified_out"; then
    fail "unsafe --verified-slices launched an agent before strict validation failed"
elif bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$unsafe_dependency_briefs" --repo "$brief_validation_repo" --verified-slices bad/id --dry-run >"$unsafe_dependency_out" 2>"$unsafe_dependency_err"; then
    fail "run-agents.sh accepted unsafe depends_on hidden by matching --verified-slices"
elif ! grep -Fq -- "Invalid depends_on value 'bad/id'" "$unsafe_dependency_err"; then
    fail "unsafe depends_on rejection was not actionable"
elif grep -Fq -- "Agent " "$unsafe_dependency_out"; then
    fail "unsafe depends_on launched an agent before strict validation failed"
else
    pass
fi

test_start "workflow topology metadata rejects unsafe partial and conflicting values before agent dispatch"
topology_metadata_briefs="$brief_validation_repo/topology-metadata"
topology_partial_out="$brief_validation_repo/topology-partial.out"
topology_partial_err="$brief_validation_repo/topology-partial.err"
topology_conflict_out="$brief_validation_repo/topology-conflict.out"
topology_conflict_err="$brief_validation_repo/topology-conflict.err"
mkdir -p "$topology_metadata_briefs"
cat >"$topology_metadata_briefs/slice-1-partial.md" <<BRIEF
## Slice Brief: partial

### Strict slice packet (execution contract)
- slice_id: partial
- slice_name: partial
- target_branch: ${brief_validation_target}
- target_base_sha: ${brief_validation_target_base}
- task_branch: feature/topology-metadata
- observable_increment: partial increment
- deliverable_type: behavior
- files_to_create:
  - none
- files_to_modify:
  - partial.txt
- files_to_test:
  - none
- enabling_changes_included:
  - none
- depends_on:
  - none
- acceptance_criteria:
  - [ ] partial criterion passes
- verification_command:
  - true
- expected_success_signal: true exits 0
- evidence_to_record:
  - dry-run result
- deviation_rollback_rule: Return DEVIATED
BRIEF
cat >"$topology_metadata_briefs/slice-2-conflict.md" <<BRIEF
## Slice Brief: conflict

### Strict slice packet (execution contract)
- slice_id: conflict
- slice_name: conflict
- target_branch: ${brief_validation_target}
- target_base_sha: ${brief_validation_target_base}
- task_branch: feature/topology-metadata
- slice_branch: slice/a-different-task/conflict
- promotion_mode: local
- observable_increment: conflict increment
- deliverable_type: behavior
- files_to_create:
  - none
- files_to_modify:
  - conflict.txt
- files_to_test:
  - none
- enabling_changes_included:
  - none
- depends_on:
  - none
- acceptance_criteria:
  - [ ] conflict criterion passes
- verification_command:
  - true
- expected_success_signal: true exits 0
- evidence_to_record:
  - dry-run result
- deviation_rollback_rule: Return DEVIATED
BRIEF
if bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$topology_metadata_briefs" --repo "$brief_validation_repo" --dry-run >"$topology_partial_out" 2>"$topology_partial_err"; then
    fail "run-agents.sh accepted partial topology metadata without slice_branch and promotion_mode"
elif ! grep -Fq -- "missing topology metadata field 'slice_branch'" "$topology_partial_err"; then
    fail "partial topology metadata failure did not identify the missing topology fields"
elif grep -Fq -- "Agent " "$topology_partial_out"; then
    fail "partial topology metadata reached dispatch before validation"
elif mv "$topology_metadata_briefs/slice-1-partial.md" "$topology_metadata_briefs/slice-1-partial.disabled" \
    && bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$topology_metadata_briefs" --repo "$brief_validation_repo" --dry-run >"$topology_conflict_out" 2>"$topology_conflict_err"; then
    fail "run-agents.sh accepted conflicting task_branch and slice_branch metadata"
elif ! grep -Fq -- "slice_branch 'slice/a-different-task/conflict' does not match task_branch 'feature/topology-metadata'" "$topology_conflict_err"; then
    fail "conflicting topology metadata failure was not actionable"
elif grep -Fq -- "Agent " "$topology_conflict_out"; then
    fail "conflicting topology metadata reached dispatch before validation"
else
    pass
fi

test_start "workflow whitespace topology metadata fails before dispatch without legacy fallback"
topology_blank_briefs="$brief_validation_repo/topology-blank"
mkdir -p "$topology_blank_briefs"
topology_blank_ok=true
for topology_blank_field in target_branch target_base_sha task_branch slice_branch promotion_mode; do
    topology_blank_brief="$topology_blank_briefs/slice-1-alpha.md"
    cat >"$topology_blank_brief" <<BRIEF
## Slice Brief: alpha

### Strict slice packet (execution contract)
- slice_id: alpha
- slice_name: alpha
- target_branch: ${brief_validation_target}
- target_base_sha: ${brief_validation_target_base}
- task_branch: feature/topology-blank
- slice_branch: slice/topology-blank/alpha
- promotion_mode: local
- observable_increment: alpha increment
- deliverable_type: behavior
- files_to_create:
  - none
- files_to_modify:
  - alpha.txt
- files_to_test:
  - none
- enabling_changes_included:
  - none
- depends_on:
  - none
- acceptance_criteria:
  - [ ] alpha criterion passes
- verification_command:
  - true
- expected_success_signal: true exits 0
- evidence_to_record:
  - dry-run result
- deviation_rollback_rule: Return DEVIATED

### Supporting context (not the execution contract)
- Git branch: feature/topology-blank/slice-alpha
BRIEF
    sed -i.bak "s/^- ${topology_blank_field}: .*/- ${topology_blank_field}:    /" "$topology_blank_brief"
    rm -f "$topology_blank_brief.bak"
    topology_blank_out="$brief_validation_repo/topology-blank-${topology_blank_field}.out"
    topology_blank_err="$brief_validation_repo/topology-blank-${topology_blank_field}.err"
    if bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$topology_blank_briefs" --repo "$brief_validation_repo" --dry-run >"$topology_blank_out" 2>"$topology_blank_err"; then
        fail "run-agents.sh accepted blank ${topology_blank_field} metadata"
        topology_blank_ok=false
        break
    elif grep -Fq -- "Agent " "$topology_blank_out" || grep -Eq 'legacy|feature/.*/slice-' "$topology_blank_out" "$topology_blank_err"; then
        fail "blank ${topology_blank_field} metadata reached dispatch or fell back to legacy topology"
        topology_blank_ok=false
        break
    fi
done
if $topology_blank_ok; then
    pass
fi

test_start "workflow all-whitespace topology metadata never downgrades to valid legacy context"
topology_all_blank_briefs="$brief_validation_repo/topology-all-blank"
topology_all_blank_out="$brief_validation_repo/topology-all-blank.out"
topology_all_blank_err="$brief_validation_repo/topology-all-blank.err"
mkdir -p "$topology_all_blank_briefs"
cat >"$topology_all_blank_briefs/slice-1-alpha.md" <<'BRIEF'
## Slice Brief: alpha

### Strict slice packet (execution contract)
- slice_id: alpha
- slice_name: alpha
- target_branch:
- target_base_sha:
- task_branch:
- slice_branch:
- promotion_mode:
- observable_increment: alpha increment
- deliverable_type: behavior
- files_to_create:
  - none
- files_to_modify:
  - alpha.txt
- files_to_test:
  - none
- enabling_changes_included:
  - none
- depends_on:
  - none
- acceptance_criteria:
  - [ ] alpha criterion passes
- verification_command:
  - true
- expected_success_signal: true exits 0
- evidence_to_record:
  - dry-run result
- deviation_rollback_rule: Return DEVIATED

### Supporting context (not the execution contract)
- Git branch: feature/topology-blank/slice-alpha
BRIEF
sed -i.bak \
    -e 's/^- target_branch:$/- target_branch:    /' \
    -e 's/^- target_base_sha:$/- target_base_sha:    /' \
    -e 's/^- task_branch:$/- task_branch:    /' \
    -e 's/^- slice_branch:$/- slice_branch:    /' \
    -e 's/^- promotion_mode:$/- promotion_mode:    /' \
    "$topology_all_blank_briefs/slice-1-alpha.md"
rm -f "$topology_all_blank_briefs/slice-1-alpha.md.bak"
if bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$topology_all_blank_briefs" --repo "$brief_validation_repo" --dry-run >"$topology_all_blank_out" 2>"$topology_all_blank_err"; then
    fail "run-agents.sh accepted all-whitespace topology metadata through legacy fallback"
elif grep -Fq -- "Agent " "$topology_all_blank_out" \
    || grep -Eq 'legacy topology|feature/topology-blank/slice-alpha' "$topology_all_blank_out" "$topology_all_blank_err"; then
    fail "all-whitespace topology metadata reached legacy dispatch instead of failing before launch"
else
    pass
fi

test_start "workflow decompose rejects unsafe task branch names before creating refs or briefs"
unsafe_task_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-unsafe-task.XXXXXX")"
p0p4_register_cleanup "$unsafe_task_repo"
git -C "$unsafe_task_repo" init -q
git -C "$unsafe_task_repo" config user.email "p0p4@example.invalid"
git -C "$unsafe_task_repo" config user.name "P0 P4"
printf 'fixture\n' >"$unsafe_task_repo/README.md"
git -C "$unsafe_task_repo" add README.md
git -C "$unsafe_task_repo" commit -q -m init
unsafe_task_manifest="$unsafe_task_repo/decomposition.json"
cat >"$unsafe_task_manifest" <<'JSON'
{
  "task": "unsafe-task",
  "description": "Unsafe task branch fixture",
  "single_slice_rationale": "One fixture increment is sufficient.",
  "slice_manifest": [{
    "slice_id": "only",
    "name": "Only",
    "observable_increment": "Fixture increment",
    "deliverable_type": "behavior",
    "files_to_create": [],
    "files_to_modify": ["fixture.txt"],
    "files_to_test": [],
    "enabling_changes_included": [],
    "depends_on": [],
    "acceptance_criteria": ["Fixture checks"],
    "verification_command": ["true"],
    "expected_success_signal": "true exits 0",
    "evidence_to_record": ["fixture evidence"],
    "deviation_rollback_rule": "Return DEVIATED"
  }]
}
JSON
unsafe_task_out="$unsafe_task_repo/unsafe-task.out"
unsafe_task_err="$unsafe_task_repo/unsafe-task.err"
if (cd "$unsafe_task_repo" && bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/decompose.sh" --task 'unsafe/task' --input "$unsafe_task_manifest" >"$unsafe_task_out" 2>"$unsafe_task_err"); then
    fail "decompose.sh accepted an unsafe task name containing a ref separator"
elif ! grep -Eqi 'invalid.*task|task.*(safe|slug|branch)' "$unsafe_task_err"; then
    fail "unsafe task name rejection was not actionable"
elif git -C "$unsafe_task_repo" show-ref --verify --quiet refs/heads/feature/unsafe/task || [[ -d "$unsafe_task_repo/briefs" ]]; then
    fail "unsafe task name mutated refs or generated briefs before validation"
else
    pass
fi

test_start "workflow run-agents non-dry-run passes clean worktree cwd and propagates failures"
fake_runner_agent_dir="$(mktemp -d "${TMPDIR:-/tmp}/workflow-fake-agent.XXXXXX")"
fake_runner_agent="$fake_runner_agent_dir/codex"
p0p4_register_cleanup "$fake_runner_agent_dir"
cat >"$fake_runner_agent" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail

cwd_arg=""
prompt_content=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p)
            shift
            prompt_content="${1:-}"
            ;;
        exec)
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

printf '%s\n' "$cwd_arg" >>"${FAKE_AGENT_CWD_RECORD:?}"

if [[ -z "$cwd_arg" || ! -d "$cwd_arg" ]]; then
    echo "invalid cwd: $cwd_arg" >&2
    exit 64
fi

if [[ "$cwd_arg" == *$'\n'* || "$cwd_arg" == *"Created worktree"* || "$cwd_arg" == *"No worktree available"* || "$cwd_arg" == *"dry-run"* ]]; then
    echo "contaminated cwd: $cwd_arg" >&2
    exit 65
fi

printf 'fake output for %s\n' "$slice_id" >"$cwd_arg/${slice_id}-marker.txt"
git -C "$cwd_arg" add "${slice_id}-marker.txt"
git -C "$cwd_arg" commit -q -m "${slice_id} fake output"

printf '## Slice Status: DONE\n\n### Slice evidence\n- slice_id: %s\n- result: pass\n' "$slice_id"

exit "${FAKE_AGENT_EXIT_CODE:-0}"
FAKE
chmod +x "$fake_runner_agent"

write_non_dry_runner_slice_brief() {
    local repo="$1"
    local slice_id="$2"
    local branch_slice_id="${3:-$slice_id}"
    local briefs_dir="$repo/briefs"
    mkdir -p "$briefs_dir"
    cat >"$briefs_dir/slice-1-${slice_id}.md" <<BRIEF
## Slice Brief: ${slice_id}

### Strict slice packet (execution contract)
- slice_id: ${slice_id}
- slice_name: ${slice_id}
- observable_increment: ${slice_id} increment
- deliverable_type: behavior
- files_to_create:
  - none
- files_to_modify:
  - fixture-${slice_id}.txt
- files_to_test:
  - none
- enabling_changes_included:
  - none
- depends_on:
  - none
- acceptance_criteria:
  - [ ] ${slice_id} criterion passes
- verification_command:
  - true
- expected_success_signal: true exits 0
- evidence_to_record:
  - non-dry-run result
- deviation_rollback_rule: Return DEVIATED rather than widening the slice

### Supporting context (not the execution contract)
- Git branch: feature/runner/slice-${branch_slice_id}
- Worktree: ${repo}/.worktrees/${slice_id}
BRIEF
}

prepare_non_dry_runner_repo() {
    local repo="$1"
    local slice_id="$2"
    local branch_slice_id="${3:-$slice_id}"
    git -C "$repo" init -q
    git -C "$repo" config user.email "p0p4@example.invalid"
    git -C "$repo" config user.name "P0 P4"
    printf 'fixture\n' >"$repo/README.md"
    printf '.worktrees/\n' >"$repo/.gitignore"
    git -C "$repo" add README.md .gitignore
    git -C "$repo" commit -q -m init
    git -C "$repo" branch "feature/runner/integration"
    git -C "$repo" branch "feature/runner/slice-${branch_slice_id}" "feature/runner/integration"
    write_non_dry_runner_slice_brief "$repo" "$slice_id" "$branch_slice_id"
}

prepare_existing_runner_worktree() {
    local repo="$1"
    local slice_id="$2"
    local branch="${3:-feature/runner/slice-${slice_id}}"
    mkdir -p "$repo/.worktrees"
    git -C "$repo" worktree add "$repo/.worktrees/${slice_id}" "$branch" --quiet
}

runner_success_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runner-success.XXXXXX")"
runner_failure_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runner-failure.XXXXXX")"
runner_mismatch_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runner-branch-mismatch.XXXXXX")"
runner_wrong_branch_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runner-wrong-branch.XXXXXX")"
runner_busy_branch_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runner-busy-branch.XXXXXX")"
p0p4_register_cleanup "$runner_success_repo" "$runner_failure_repo" "$runner_mismatch_repo" "$runner_wrong_branch_repo" "$runner_busy_branch_repo"
prepare_non_dry_runner_repo "$runner_success_repo" success
prepare_non_dry_runner_repo "$runner_failure_repo" fail
prepare_non_dry_runner_repo "$runner_mismatch_repo" identity other
prepare_non_dry_runner_repo "$runner_wrong_branch_repo" wrong
prepare_non_dry_runner_repo "$runner_busy_branch_repo" busy
git -C "$runner_wrong_branch_repo" branch "feature/runner/slice-other"
prepare_existing_runner_worktree "$runner_success_repo" success
prepare_existing_runner_worktree "$runner_wrong_branch_repo" wrong "feature/runner/slice-other"
git -C "$runner_busy_branch_repo" worktree add "$runner_busy_branch_repo/occupied-busy" "feature/runner/slice-busy" --quiet

runner_success_cwd_record="$runner_success_repo/cwd-record.txt"
runner_success_out="$runner_success_repo/run.out"
runner_success_err="$runner_success_repo/run.err"
runner_failure_cwd_record="$runner_failure_repo/cwd-record.txt"
runner_failure_out="$runner_failure_repo/run.out"
runner_failure_err="$runner_failure_repo/run.err"
runner_mismatch_cwd_record="$runner_mismatch_repo/cwd-record.txt"
runner_mismatch_out="$runner_mismatch_repo/run.out"
runner_mismatch_err="$runner_mismatch_repo/run.err"
runner_wrong_branch_cwd_record="$runner_wrong_branch_repo/cwd-record.txt"
runner_wrong_branch_out="$runner_wrong_branch_repo/run.out"
runner_wrong_branch_err="$runner_wrong_branch_repo/run.err"
runner_busy_branch_cwd_record="$runner_busy_branch_repo/cwd-record.txt"
runner_busy_branch_out="$runner_busy_branch_repo/run.out"
runner_busy_branch_err="$runner_busy_branch_repo/run.err"

if PATH="$fake_runner_agent_dir:$PATH" FAKE_AGENT_CWD_RECORD="$runner_mismatch_cwd_record" bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$runner_mismatch_repo/briefs" --repo "$runner_mismatch_repo" --agent codex --parallel --worktrees-dir "$runner_mismatch_repo/.worktrees" >"$runner_mismatch_out" 2>"$runner_mismatch_err"; then
    fail "run-agents.sh accepted a Git branch whose slice tail did not match strict packet slice_id"
elif [[ -s "$runner_mismatch_cwd_record" ]]; then
    fail "branch mismatch probe launched the fake agent before rejecting the slice identity"
elif grep -Fq -- "Agent 1: slice-1-identity" "$runner_mismatch_out"; then
    fail "branch mismatch probe reached agent launch output before rejecting the slice identity"
elif ! grep -Fq -- "branch identity mismatch" "$runner_mismatch_err"; then
    fail "branch mismatch failure did not explain the identity mismatch: $(tr '\n' ' ' <"$runner_mismatch_err")"
elif ! grep -Fq -- "expected 'slice-identity'" "$runner_mismatch_err"; then
    fail "branch mismatch failure did not name the expected slice tail: $(tr '\n' ' ' <"$runner_mismatch_err")"
elif PATH="$fake_runner_agent_dir:$PATH" FAKE_AGENT_CWD_RECORD="$runner_wrong_branch_cwd_record" bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$runner_wrong_branch_repo/briefs" --repo "$runner_wrong_branch_repo" --agent codex --parallel --worktrees-dir "$runner_wrong_branch_repo/.worktrees" >"$runner_wrong_branch_out" 2>"$runner_wrong_branch_err"; then
    fail "run-agents.sh accepted an existing Worktree path checked out to the wrong branch"
elif [[ -s "$runner_wrong_branch_cwd_record" ]]; then
    fail "wrong-branch Worktree probe launched the fake agent before rejecting the path"
elif grep -Fq -- "Agent 1: slice-1-wrong" "$runner_wrong_branch_out"; then
    fail "wrong-branch Worktree probe reached agent launch output before rejecting the path"
elif ! grep -Fq -- "checked out to 'feature/runner/slice-other', expected 'feature/runner/slice-wrong'" "$runner_wrong_branch_err"; then
    fail "wrong-branch Worktree failure was not actionable: $(tr '\n' ' ' <"$runner_wrong_branch_err")"
elif PATH="$fake_runner_agent_dir:$PATH" FAKE_AGENT_CWD_RECORD="$runner_busy_branch_cwd_record" bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$runner_busy_branch_repo/briefs" --repo "$runner_busy_branch_repo" --agent codex --parallel --worktrees-dir "$runner_busy_branch_repo/.worktrees" >"$runner_busy_branch_out" 2>"$runner_busy_branch_err"; then
    fail "run-agents.sh fell back to the main repo after worktree creation failed for a branch checked out elsewhere"
elif [[ -s "$runner_busy_branch_cwd_record" ]]; then
    fail "busy-branch Worktree probe launched the fake agent after worktree creation failed"
elif grep -Fq -- "Agent 1: slice-1-busy" "$runner_busy_branch_out"; then
    fail "busy-branch Worktree probe reached agent launch output after worktree creation failed"
elif ! grep -Fq -- "Parallel launch blocked: no valid worktree available for slice 'busy'" "$runner_busy_branch_err"; then
    fail "busy-branch Worktree failure was not fatal/actionable: $(tr '\n' ' ' <"$runner_busy_branch_err")"
elif ! PATH="$fake_runner_agent_dir:$PATH" FAKE_AGENT_CWD_RECORD="$runner_success_cwd_record" bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$runner_success_repo/briefs" --repo "$runner_success_repo" --agent codex --parallel --worktrees-dir "$runner_success_repo/.worktrees" >"$runner_success_out" 2>"$runner_success_err"; then
    fail "run-agents.sh non-dry-run success probe failed: $(tr '\n' ' ' <"$runner_success_err")"
elif grep -Fq "Created worktree" "$runner_success_out"; then
    fail "run-agents.sh emitted worktree creation progress to stdout during cwd resolution"
elif [[ "$(wc -l <"$runner_success_cwd_record" | tr -d ' ')" != "1" ]]; then
    fail "fake agent received a multi-line cwd argument: $(tr '\n' '|' <"$runner_success_cwd_record")"
else
    runner_success_cwd="$(cat "$runner_success_cwd_record")"
    if [[ ! -d "$runner_success_cwd" ]]; then
        fail "fake agent did not receive an existing worktree directory: $runner_success_cwd"
    elif [[ "$runner_success_cwd" == *"Created worktree"* || "$runner_success_cwd" == *"No worktree available"* || "$runner_success_cwd" == *"dry-run"* ]]; then
        fail "fake agent cwd was contaminated by runner log text: $runner_success_cwd"
    elif PATH="$fake_runner_agent_dir:$PATH" FAKE_AGENT_CWD_RECORD="$runner_failure_cwd_record" FAKE_AGENT_EXIT_CODE=37 bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$runner_failure_repo/briefs" --repo "$runner_failure_repo" --agent codex --parallel --worktrees-dir "$runner_failure_repo/.worktrees" >"$runner_failure_out" 2>"$runner_failure_err"; then
        fail "run-agents.sh returned success when a parallel fake agent failed"
    elif ! grep -Fq "Failed: 1" "$runner_failure_out"; then
        fail "run-agents.sh failure probe did not preserve failed summary"
    elif [[ "$(wc -l <"$runner_failure_cwd_record" | tr -d ' ')" != "1" ]]; then
        fail "fake failing agent received a multi-line cwd argument: $(tr '\n' '|' <"$runner_failure_cwd_record")"
    else
        runner_failure_cwd="$(cat "$runner_failure_cwd_record")"
        if [[ -d "$runner_failure_cwd" ]]; then
            pass
        else
            fail "fake failing agent did not receive an existing worktree directory: $runner_failure_cwd"
        fi
    fi
fi

test_start "workflow run-agents requires semantic slice reports before dependency advancement"
semantic_runner_agent_dir="$(mktemp -d "${TMPDIR:-/tmp}/workflow-semantic-agent.XXXXXX")"
semantic_runner_agent="$semantic_runner_agent_dir/codex"
p0p4_register_cleanup "$semantic_runner_agent_dir"
cat >"$semantic_runner_agent" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail

cwd_arg=""
prompt_content=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p)
            shift
            prompt_content="${1:-}"
            ;;
        exec)
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

mode="${FAKE_SEMANTIC_MODE:-pass-commit}"
status="DONE"
result="pass"

if [[ "$mode" == "blocked" ]]; then
    status="BLOCKED"
    result="blocker"
elif [[ "$mode" == "concern" ]]; then
    status="DONE_WITH_CONCERNS"
    result="pass"
else
    case "$slice_id" in
        alpha)
            printf 'verified prerequisite\n' >"$cwd_arg/prereq-marker.txt"
            git -C "$cwd_arg" add prereq-marker.txt
            git -C "$cwd_arg" commit -q -m "alpha marker"
            ;;
        beta)
            if [[ ! -f "$cwd_arg/prereq-marker.txt" ]]; then
                echo "missing prerequisite marker" >&2
                exit 77
            fi
            printf 'dependent saw prerequisite\n' >"$cwd_arg/beta-marker.txt"
            git -C "$cwd_arg" add beta-marker.txt
            git -C "$cwd_arg" commit -q -m "beta marker"
            ;;
    esac
fi

printf '## Slice Status: %s\n\n### Slice evidence\n- slice_id: %s\n- result: %s\n' "$status" "$slice_id" "$result"
exit 0
FAKE
chmod +x "$semantic_runner_agent"

write_semantic_slice_brief() {
    local repo="$1"
    local task="$2"
    local number="$3"
    local slice_id="$4"
    local deps_csv="$5"
    local briefs_dir="$repo/briefs"
    local brief_file="$briefs_dir/slice-${number}-${slice_id}.md"
    mkdir -p "$briefs_dir"

    cat >"$brief_file" <<BRIEF
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
  - none
- enabling_changes_included:
  - none
- depends_on:
BRIEF
    if [[ "$deps_csv" == "none" ]]; then
        printf '  - none\n' >>"$brief_file"
    else
        IFS=',' read -ra semantic_deps <<< "$deps_csv"
        for semantic_dep in "${semantic_deps[@]}"; do
            trimmed_semantic_dep="$(printf '%s' "$semantic_dep" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
            printf '  - %s\n' "$trimmed_semantic_dep" >>"$brief_file"
        done
    fi
    cat >>"$brief_file" <<BRIEF
- acceptance_criteria:
  - [ ] ${slice_id} criterion passes
- verification_command:
  - true
- expected_success_signal: true exits 0
- evidence_to_record:
  - semantic result
- deviation_rollback_rule: Return DEVIATED rather than widening the slice

### Supporting context (not the execution contract)
- Git branch: feature/${task}/slice-${slice_id}
- Worktree: ${repo}/.worktrees/${slice_id}
BRIEF
}

prepare_semantic_runner_repo() {
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

semantic_blocked_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-semantic-blocked.XXXXXX")"
semantic_fresh_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-semantic-fresh.XXXXXX")"
semantic_parallel_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-semantic-parallel.XXXXXX")"
semantic_output_dir="$(mktemp -d "${TMPDIR:-/tmp}/workflow-semantic-output.XXXXXX")"
p0p4_register_cleanup "$semantic_blocked_repo" "$semantic_fresh_repo" "$semantic_parallel_repo" "$semantic_output_dir"

prepare_semantic_runner_repo "$semantic_blocked_repo" semantic-blocked
write_semantic_slice_brief "$semantic_blocked_repo" semantic-blocked 1 alpha none
write_semantic_slice_brief "$semantic_blocked_repo" semantic-blocked 2 beta alpha
semantic_blocked_out="$semantic_output_dir/blocked.out"
semantic_blocked_err="$semantic_output_dir/blocked.err"

prepare_semantic_runner_repo "$semantic_fresh_repo" semantic-fresh
write_semantic_slice_brief "$semantic_fresh_repo" semantic-fresh 1 alpha none
write_semantic_slice_brief "$semantic_fresh_repo" semantic-fresh 2 beta alpha
semantic_fresh_out="$semantic_output_dir/fresh.out"
semantic_fresh_err="$semantic_output_dir/fresh.err"

prepare_semantic_runner_repo "$semantic_parallel_repo" semantic-parallel
write_semantic_slice_brief "$semantic_parallel_repo" semantic-parallel 1 alpha none
semantic_parallel_out="$semantic_output_dir/parallel.out"
semantic_parallel_err="$semantic_output_dir/parallel.err"

if PATH="$semantic_runner_agent_dir:$PATH" FAKE_SEMANTIC_MODE=blocked bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$semantic_blocked_repo/briefs" --repo "$semantic_blocked_repo" --agent codex >"$semantic_blocked_out" 2>"$semantic_blocked_err"; then
    fail "run-agents.sh accepted BLOCKED/result:blocker report because the fake agent exited 0"
elif ! grep -Fq -- "did not report explicit passing evidence" "$semantic_blocked_out"; then
    fail "semantic failure did not explain missing DONE/pass evidence"
elif grep -Fq -- "Agent 2: slice-2-beta" "$semantic_blocked_out"; then
    fail "run-agents.sh launched dependent beta after alpha reported BLOCKED"
elif git -C "$semantic_blocked_repo" show-ref --verify --quiet "refs/heads/feature/semantic-blocked/slice-beta"; then
    fail "run-agents.sh created dependent beta branch after alpha semantic failure"
elif ! PATH="$semantic_runner_agent_dir:$PATH" FAKE_SEMANTIC_MODE=pass-commit bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$semantic_fresh_repo/briefs" --repo "$semantic_fresh_repo" --agent codex >"$semantic_fresh_out" 2>"$semantic_fresh_err"; then
    fail "run-agents.sh rejected DONE/pass semantic reports with committed slice output: $(tr '\n' ' ' <"$semantic_fresh_err")"
elif ! grep -Fq -- "Agent 2: slice-2-beta" "$semantic_fresh_out"; then
    fail "run-agents.sh did not proceed to dependent beta after alpha DONE/pass verification"
elif ! grep -Fq -- "Promoted verified slice 'alpha' into feature/semantic-fresh/integration" "$semantic_fresh_out"; then
    fail "run-agents.sh did not merge alpha into integration before launching beta"
elif ! git -C "$semantic_fresh_repo" show "feature/semantic-fresh/slice-beta:prereq-marker.txt" >/dev/null 2>&1; then
    fail "dependent beta branch was not created from integration containing alpha's committed marker"
elif ! git -C "$semantic_fresh_repo" show "feature/semantic-fresh/integration:beta-marker.txt" >/dev/null 2>&1; then
    fail "run-agents.sh did not merge beta output back into integration"
elif PATH="$semantic_runner_agent_dir:$PATH" FAKE_SEMANTIC_MODE=concern bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$semantic_parallel_repo/briefs" --repo "$semantic_parallel_repo" --agent codex --parallel --worktrees-dir "$semantic_parallel_repo/.worktrees" >"$semantic_parallel_out" 2>"$semantic_parallel_err"; then
    fail "parallel run-agents.sh accepted DONE_WITH_CONCERNS/result:pass because the fake agent exited 0"
elif ! grep -Fq -- "Failed: 1" "$semantic_parallel_out"; then
    fail "parallel semantic failure did not return failed summary"
else
    pass
fi

test_start "workflow run-agents proves externally verified prerequisites are merged"
external_stale_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-external-stale.XXXXXX")"
external_skip_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-external-skip.XXXXXX")"
external_merged_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-external-merged.XXXXXX")"
external_stale_branch_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-external-stale-branch.XXXXXX")"
external_output_dir="$(mktemp -d "${TMPDIR:-/tmp}/workflow-external-output.XXXXXX")"
p0p4_register_cleanup "$external_stale_repo" "$external_skip_repo" "$external_merged_repo" "$external_stale_branch_repo" "$external_output_dir"

prepare_external_prereq_branch() {
    local repo="$1"
    local task="$2"
    local merge_to_integration="$3"

    git -C "$repo" checkout -q -b "feature/${task}/slice-alpha" "feature/${task}/integration"
    printf 'alpha prerequisite\n' >"$repo/alpha-marker.txt"
    git -C "$repo" add alpha-marker.txt
    git -C "$repo" commit -q -m "alpha prerequisite"
    git -C "$repo" checkout -q "feature/${task}/integration"
    if [[ "$merge_to_integration" == "yes" ]]; then
        git -C "$repo" merge --ff-only "feature/${task}/slice-alpha" -q
    fi
}

prepare_semantic_runner_repo "$external_stale_repo" external-stale
prepare_external_prereq_branch "$external_stale_repo" external-stale no
write_semantic_slice_brief "$external_stale_repo" external-stale 1 alpha none
write_semantic_slice_brief "$external_stale_repo" external-stale 2 beta alpha
external_stale_out="$external_output_dir/stale.out"
external_stale_err="$external_output_dir/stale.err"

prepare_semantic_runner_repo "$external_skip_repo" external-skip
prepare_external_prereq_branch "$external_skip_repo" external-skip no
write_semantic_slice_brief "$external_skip_repo" external-skip 1 alpha none
write_semantic_slice_brief "$external_skip_repo" external-skip 2 beta alpha
external_skip_out="$external_output_dir/skip.out"
external_skip_err="$external_output_dir/skip.err"

prepare_semantic_runner_repo "$external_merged_repo" external-merged
prepare_external_prereq_branch "$external_merged_repo" external-merged yes
write_semantic_slice_brief "$external_merged_repo" external-merged 1 alpha none
write_semantic_slice_brief "$external_merged_repo" external-merged 2 beta alpha
external_merged_out="$external_output_dir/merged.out"
external_merged_err="$external_output_dir/merged.err"

prepare_semantic_runner_repo "$external_stale_branch_repo" external-stale-branch
git -C "$external_stale_branch_repo" branch "feature/external-stale-branch/slice-beta" "feature/external-stale-branch/integration"
mkdir -p "$external_stale_branch_repo/.worktrees"
git -C "$external_stale_branch_repo" worktree add "$external_stale_branch_repo/.worktrees/beta" "feature/external-stale-branch/slice-beta" --quiet
prepare_external_prereq_branch "$external_stale_branch_repo" external-stale-branch yes
write_semantic_slice_brief "$external_stale_branch_repo" external-stale-branch 1 alpha none
write_semantic_slice_brief "$external_stale_branch_repo" external-stale-branch 2 beta alpha
external_stale_branch_out="$external_output_dir/stale-branch.out"
external_stale_branch_err="$external_output_dir/stale-branch.err"

if bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$external_stale_repo/briefs" --repo "$external_stale_repo" --verified-slices alpha --dry-run >"$external_stale_out" 2>"$external_stale_err"; then
    fail "run-agents.sh accepted --verified-slices alpha when alpha was not merged into integration"
elif ! grep -Fq -- "not merged into integration branch" "$external_stale_err"; then
    fail "--verified-slices stale prerequisite failure did not explain the merge proof requirement"
elif grep -Fq -- "Agent " "$external_stale_out"; then
    fail "--verified-slices stale prerequisite launched an agent before proof passed"
elif bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$external_skip_repo/briefs" --repo "$external_skip_repo" --skip-first --dry-run >"$external_skip_out" 2>"$external_skip_err"; then
    fail "run-agents.sh accepted --skip-first when first slice was not merged into integration"
elif ! grep -Fq -- "not merged into integration branch" "$external_skip_err"; then
    fail "--skip-first stale prerequisite failure did not explain the merge proof requirement"
elif grep -Fq -- "Agent 2: slice-2-beta" "$external_skip_out"; then
    fail "--skip-first stale prerequisite launched dependent beta before proof passed"
elif ! bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$external_merged_repo/briefs" --repo "$external_merged_repo" --verified-slices alpha --dry-run >"$external_merged_out" 2>"$external_merged_err"; then
    fail "run-agents.sh rejected --verified-slices alpha after alpha was merged into integration: $(tr '\n' ' ' <"$external_merged_err")"
elif ! grep -Fq -- "Agent 2: slice-2-beta" "$external_merged_out"; then
    fail "run-agents.sh did not launch beta after externally verified alpha proof passed"
elif ! grep -Fq -- "git branch feature/external-merged/slice-beta feature/external-merged/integration" "$external_merged_err"; then
    fail "run-agents.sh did not create beta branch from integration after external proof passed"
elif PATH="$semantic_runner_agent_dir:$PATH" FAKE_SEMANTIC_MODE=pass-commit bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$external_stale_branch_repo/briefs" --repo "$external_stale_branch_repo" --agent codex --verified-slices alpha --parallel --worktrees-dir "$external_stale_branch_repo/.worktrees" >"$external_stale_branch_out" 2>"$external_stale_branch_err"; then
    fail "run-agents.sh accepted stale existing dependent beta branch after alpha was merged into integration"
elif ! grep -Fq -- "Stale dependent slice branch" "$external_stale_branch_err"; then
    fail "stale existing dependent branch failure did not explain that the branch must contain current integration"
elif grep -Fq -- "Agent 1: slice-2-beta" "$external_stale_branch_out"; then
    fail "stale existing dependent branch launched beta before freshness proof passed"
else
    pass
fi

test_start "workflow architect plan keeps optional display files summary non-contractual"
missing_architect_display_files_terms=()
if ! handoff_return_field_has_line "$handoffs_file" "orchestrator_to_architect" "implementation_steps" "Optional display summaries may exist only for human readability"; then
    missing_architect_display_files_terms+=("implementation_steps description marks display summaries optional")
fi
if ! handoff_return_field_has_line "$handoffs_file" "orchestrator_to_architect" "implementation_steps" "cannot satisfy or replace exact slice and files_to_* fields"; then
    missing_architect_display_files_terms+=("implementation_steps description says display summaries cannot satisfy task packet contract")
fi
if ! field_required_true_after_anchor "$handoffs_file" "- name: implementation_steps" "files"; then
    :
else
    missing_architect_display_files_terms+=("implementation_steps.files must not be required")
fi
for term in \
    "          - name: files" \
    "            required: false" \
    "Optional display summary of file paths this step touches; cannot satisfy or replace executable files_to_* contract"; do
    if ! awk -v term="$term" '
        $0 == "  - name: orchestrator_to_architect" { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && $0 == "      - name: implementation_steps" { in_steps = 1; next }
        in_steps && index($0, term) { found = 1; exit }
        in_steps && $0 == "      - name: files_to_create" { exit }
        END { exit found ? 0 : 1 }
    ' "$handoffs_file"; then
        missing_architect_display_files_terms+=("$term")
    fi
done
if [[ "${#missing_architect_display_files_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "architect implementation_steps must use files_to_* as required fields and keep display summaries optional: ${missing_architect_display_files_terms[*]}"
fi

test_start "workflow live slicing surfaces reject stale component execution artifacts"
stale_component_artifacts_file="$(mktemp "${TMPDIR:-/tmp}/workflow-stale-component-artifacts.XXXXXX")"
p0p4_register_cleanup "$stale_component_artifacts_file"
if rg -n "component_manifest|component_verification_summary|component_name|component_id|Component Verification Ledger|per-component verification|component/subagent count|component verification criteria|per-component evidence" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/plan-template.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/decomposition-plan-review.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/prompts/spec-review.md" \
    "$FRAMEWORK_DIR/agents/codex/architect.toml" \
    "$FRAMEWORK_DIR/agents/claude/architect.md" >"$stale_component_artifacts_file"; then
    fail "found stale component execution artifacts; see $stale_component_artifacts_file"
else
    pass
fi

test_start "workflow pivot restart controller records decision packets and recovery refs"
missing_pivot_restart_terms=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::- name: pivot_restart_decision" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::trigger" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::affected_slice_or_round" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::options_considered" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::selected_action" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::reapproval_required" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::next_agent" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::recovery_pointer" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::exact_next_action" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::pivot_restart_decision_ref" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::pivot_restart_decision" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml::B_CODE_WRITER_BLOCKER_ROUTING" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml::R_PIVOT_RESTART_DECISION" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml::INV_PIVOT_RESTART_REAPPROVAL" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/harness-runtime-artifacts.md::## Pivot/Restart Controller" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/harness-runtime-artifacts.md::Round 10 remains terminal" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/build-worker-protocol.md::Code Writer Unexpected Blockers" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/review-qa-router.md::STAGNATION, repeated DRIFT, repeated REGRESSION, or rubric action PIVOT" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-harness-appendix.md::## Pivot/Restart Log" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-harness-appendix.md::pivot_restart_decision"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        missing_pivot_restart_terms+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#missing_pivot_restart_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow pivot/restart controller missing decision packet terms: ${missing_pivot_restart_terms[*]}"
fi

test_start "workflow CodeWriter unexpected blockers classify and route recovery"
missing_codewriter_blocker_terms=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::blocker_type" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::blocker_evidence" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::legacy_code_bug" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::broken_baseline" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::hidden_dependency" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::missing_contract" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::stale_plan" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::scope_conflict" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::tool_environment" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::tdd_red_missing" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/build-worker-protocol.md::debugging, explorer, architect, candidate_search, replan, restart" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/sub-task-brief-template.md::Unexpected blockers must be classified" \
    "$FRAMEWORK_DIR/agents/codex/code-writer.toml::Unexpected blocker protocol" \
    "$FRAMEWORK_DIR/agents/codex/code-writer.toml::Do not widen scope" \
    "$FRAMEWORK_DIR/agents/claude/code-writer.md::Unexpected blocker protocol" \
    "$FRAMEWORK_DIR/agents/claude/code-writer.md::Do not widen scope"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        missing_codewriter_blocker_terms+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#missing_codewriter_blocker_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "CodeWriter blocker classification and orchestrator routing terms missing: ${missing_codewriter_blocker_terms[*]}"
fi

test_start "assistant-review stagnation and QA pivot escalate to pivot restart decision"
missing_review_pivot_terms=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md::pivot_restart_signal" \
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md::orchestrator records \`pivot_restart_decision\`" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/review-loop.md::orchestrator records pivot_restart_decision" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml::pivot_restart_signal" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml::- name: pivot_restart_decision" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml::ESCALATE_PIVOT_RESTART" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml::QA STAGNATION, repeated DRIFT, repeated REGRESSION, or scoped domain action pivot" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/score-tracking.md::Pivot/Restart Decision Packet" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/score-tracking.md::repeated DRIFT triggers pivot_restart_decision" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/qa-evaluation-loop.md::Pivot/Restart Escalation" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/qa-evaluation-loop.md::QA does not silently continue"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        missing_review_pivot_terms+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#missing_review_pivot_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review pivot/restart stagnation escalation terms missing: ${missing_review_pivot_terms[*]}"
fi

test_start "assistant-review removes stale loose stagnation and drift exits"
stale_pivot_restart_terms=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-review/references/score-tracking.md::May need to PIVOT or accept current state with documented limitations" \
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md::On 3+ DRIFT occurrences: stop the loop and present findings for manual review"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ -f "$file" ]] && grep -Fq -- "$term" "$file"; then
        stale_pivot_restart_terms+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#stale_pivot_restart_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "stale loose stagnation/drift exits remain: ${stale_pivot_restart_terms[*]}"
fi

test_start "workflow runner rejects mixed legacy and new topology briefs before dispatch"
mixed_topology_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-mixed-topology.XXXXXX")"
p0p4_register_cleanup "$mixed_topology_repo"
git -C "$mixed_topology_repo" init -q
git -C "$mixed_topology_repo" config user.email "p0p4@example.invalid"
git -C "$mixed_topology_repo" config user.name "P0 P4"
printf 'fixture\n' >"$mixed_topology_repo/README.md"
git -C "$mixed_topology_repo" add README.md
git -C "$mixed_topology_repo" commit -q -m init
mixed_topology_base="$(git -C "$mixed_topology_repo" branch --show-current)"
git -C "$mixed_topology_repo" branch feature/mixed-topology/integration "$mixed_topology_base"
git -C "$mixed_topology_repo" branch feature/mixed-topology/slice-legacy feature/mixed-topology/integration
git -C "$mixed_topology_repo" branch slice/mixed-topology/new "$mixed_topology_base"
mixed_topology_briefs="$mixed_topology_repo/briefs"
mkdir -p "$mixed_topology_briefs"
cat >"$mixed_topology_briefs/slice-1-legacy.md" <<BRIEF
## Slice Brief: legacy

### Strict slice packet (execution contract)
- slice_id: legacy
- slice_name: legacy
- observable_increment: legacy increment
- deliverable_type: behavior
- files_to_create:
  - none
- files_to_modify:
  - legacy.txt
- files_to_test:
  - none
- enabling_changes_included:
  - none
- depends_on:
  - none
- acceptance_criteria:
  - [ ] legacy criterion passes
- verification_command:
  - true
- expected_success_signal: true exits 0
- evidence_to_record:
  - dry-run result
- deviation_rollback_rule: Return DEVIATED

### Supporting context (not the execution contract)
- Git branch: feature/mixed-topology/slice-legacy
- Worktree: ${mixed_topology_repo}/.worktrees/legacy
BRIEF
cat >"$mixed_topology_briefs/slice-2-new.md" <<BRIEF
## Slice Brief: new

### Strict slice packet (execution contract)
- slice_id: new
- slice_name: new
- target_branch: ${mixed_topology_base}
- target_base_sha: $(git -C "$mixed_topology_repo" rev-parse "$mixed_topology_base")
- task_branch: feature/mixed-topology
- slice_branch: slice/mixed-topology/new
- promotion_mode: local
- observable_increment: new increment
- deliverable_type: behavior
- files_to_create:
  - none
- files_to_modify:
  - new.txt
- files_to_test:
  - none
- enabling_changes_included:
  - none
- depends_on:
  - none
- acceptance_criteria:
  - [ ] new criterion passes
- verification_command:
  - true
- expected_success_signal: true exits 0
- evidence_to_record:
  - dry-run result
- deviation_rollback_rule: Return DEVIATED

### Supporting context (not the execution contract)
- Git branch: slice/mixed-topology/new
- Worktree: ${mixed_topology_repo}/.worktrees/new
BRIEF
mixed_topology_out="$mixed_topology_repo/mixed.out"
mixed_topology_err="$mixed_topology_repo/mixed.err"
if bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$mixed_topology_briefs" --repo "$mixed_topology_repo" --dry-run >"$mixed_topology_out" 2>"$mixed_topology_err"; then
    fail "run-agents.sh accepted a mixed legacy and new topology brief set"
elif ! grep -Fq -- "cannot mix legacy and new topology briefs" "$mixed_topology_err"; then
    fail "mixed topology rejection was not actionable"
elif grep -Fq -- "Agent " "$mixed_topology_out"; then
    fail "mixed topology reached dispatch before validation"
else
    pass
fi

test_start "workflow runner rejects duplicate supporting Git branch metadata before dispatch"
duplicate_support_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-duplicate-support.XXXXXX")"
p0p4_register_cleanup "$duplicate_support_repo"
git -C "$duplicate_support_repo" init -q
git -C "$duplicate_support_repo" config user.email "p0p4@example.invalid"
git -C "$duplicate_support_repo" config user.name "P0 P4"
printf 'fixture\n' >"$duplicate_support_repo/README.md"
git -C "$duplicate_support_repo" add README.md
git -C "$duplicate_support_repo" commit -q -m init
duplicate_support_base="$(git -C "$duplicate_support_repo" branch --show-current)"
git -C "$duplicate_support_repo" branch feature/duplicate-support/integration "$duplicate_support_base"
git -C "$duplicate_support_repo" branch feature/duplicate-support/slice-alpha feature/duplicate-support/integration
duplicate_support_briefs="$duplicate_support_repo/briefs"
mkdir -p "$duplicate_support_briefs"
cat >"$duplicate_support_briefs/slice-1-alpha.md" <<BRIEF
## Slice Brief: alpha

### Strict slice packet (execution contract)
- slice_id: alpha
- slice_name: alpha
- observable_increment: alpha increment
- deliverable_type: behavior
- files_to_create:
  - none
- files_to_modify:
  - alpha.txt
- files_to_test:
  - none
- enabling_changes_included:
  - none
- depends_on:
  - none
- acceptance_criteria:
  - [ ] alpha criterion passes
- verification_command:
  - true
- expected_success_signal: true exits 0
- evidence_to_record:
  - dry-run result
- deviation_rollback_rule: Return DEVIATED

### Supporting context (not the execution contract)
- Git branch: feature/duplicate-support/slice-alpha
- Git branch: feature/other-task/slice-alpha
- Worktree: ${duplicate_support_repo}/.worktrees/alpha
BRIEF
duplicate_support_out="$duplicate_support_repo/duplicate.out"
duplicate_support_err="$duplicate_support_repo/duplicate.err"
if bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/run-agents.sh" --briefs "$duplicate_support_briefs" --repo "$duplicate_support_repo" --dry-run >"$duplicate_support_out" 2>"$duplicate_support_err"; then
    fail "run-agents.sh accepted duplicate supporting Git branch metadata"
elif ! grep -Fq -- "duplicates supporting Git branch metadata" "$duplicate_support_err"; then
    fail "duplicate supporting Git branch rejection was not actionable"
elif grep -Fq -- "Agent " "$duplicate_support_out"; then
    fail "duplicate supporting Git branch metadata reached dispatch"
else
    pass
fi

test_start "workflow decompose rejects legacy child-ref collisions before caller checkout or brief creation"
legacy_collision_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-legacy-ref-collision.XXXXXX")"
p0p4_register_cleanup "$legacy_collision_repo"
git -C "$legacy_collision_repo" init -q
git -C "$legacy_collision_repo" config user.email "p0p4@example.invalid"
git -C "$legacy_collision_repo" config user.name "P0 P4"
printf 'fixture\n' >"$legacy_collision_repo/README.md"
git -C "$legacy_collision_repo" add README.md
git -C "$legacy_collision_repo" commit -q -m init
legacy_collision_base="$(git -C "$legacy_collision_repo" branch --show-current)"
git -C "$legacy_collision_repo" checkout -q -b caller
git -C "$legacy_collision_repo" branch feature/legacy-collision/integration "$legacy_collision_base"
legacy_collision_manifest="$legacy_collision_repo/decomposition.json"
cp "$unsafe_task_manifest" "$legacy_collision_manifest"
legacy_collision_before_branch="$(git -C "$legacy_collision_repo" branch --show-current)"
legacy_collision_before_head="$(git -C "$legacy_collision_repo" rev-parse HEAD)"
legacy_collision_out="$legacy_collision_repo/collision.out"
legacy_collision_err="$legacy_collision_repo/collision.err"
if (cd "$legacy_collision_repo" && bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/decompose.sh" --task legacy-collision --input "$legacy_collision_manifest" --target-branch "$legacy_collision_base" >"$legacy_collision_out" 2>"$legacy_collision_err"); then
    fail "decompose.sh accepted a legacy feature/<task> child-ref collision"
elif ! grep -Eqi 'legacy.*(child|ref|branch)|feature/legacy-collision' "$legacy_collision_err"; then
    fail "legacy child-ref collision rejection was not actionable"
elif [[ "$(git -C "$legacy_collision_repo" branch --show-current)" != "$legacy_collision_before_branch" || "$(git -C "$legacy_collision_repo" rev-parse HEAD)" != "$legacy_collision_before_head" ]]; then
    fail "legacy child-ref collision changed the caller branch or HEAD before failing"
elif [[ -d "$legacy_collision_repo/briefs" ]]; then
    fail "legacy child-ref collision generated briefs before failing"
else
    pass
fi

test_start "workflow decompose defaults the target branch to the currently checked-out local branch"
implicit_target_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-implicit-target.XXXXXX")"
p0p4_register_cleanup "$implicit_target_repo"
git -C "$implicit_target_repo" init -q
git -C "$implicit_target_repo" config user.email "p0p4@example.invalid"
git -C "$implicit_target_repo" config user.name "P0 P4"
printf 'fixture\n' >"$implicit_target_repo/README.md"
printf '.worktrees/\n' >"$implicit_target_repo/.gitignore"
git -C "$implicit_target_repo" add README.md .gitignore
git -C "$implicit_target_repo" commit -q -m init
implicit_initial_branch="$(git -C "$implicit_target_repo" branch --show-current)"
git -C "$implicit_target_repo" checkout -q -b develop
git -C "$implicit_target_repo" branch -D "$implicit_initial_branch"
implicit_target_manifest="$implicit_target_repo/decomposition.json"
cp "$unsafe_task_manifest" "$implicit_target_manifest"
git -C "$implicit_target_repo" add decomposition.json
git -C "$implicit_target_repo" commit -q -m "add implicit target fixture"
implicit_target_before="$(git -C "$implicit_target_repo" rev-parse develop)"
implicit_target_out="$implicit_target_repo/decompose.out"
implicit_target_err="$implicit_target_repo/decompose.err"
if ! (cd "$implicit_target_repo" && bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/decompose.sh" --task implicit-target --input "$implicit_target_manifest" >"$implicit_target_out" 2>"$implicit_target_err"); then
    fail "decompose.sh did not infer the checked-out develop branch: $(tr '\n' ' ' <"$implicit_target_err")"
elif [[ "$(git -C "$implicit_target_repo" rev-parse feature/implicit-target)" != "$implicit_target_before" ]]; then
    fail "decompose.sh did not create feature/implicit-target from the inferred develop target"
elif ! grep -Fq -- "- target_branch: develop" "$implicit_target_repo/briefs/slice-1-only.md"; then
    fail "decompose.sh did not emit the inferred develop target_branch in the strict brief"
elif git -C "$implicit_target_repo" show-ref --verify --quiet refs/heads/main; then
    fail "implicit target fixture unexpectedly recreated or required a universal main branch"
else
    pass
fi

test_start "workflow decompose requires an explicit target branch from detached HEAD before creating refs or briefs"
detached_target_repo="$(mktemp -d "${TMPDIR:-/tmp}/workflow-detached-target.XXXXXX")"
p0p4_register_cleanup "$detached_target_repo"
git -C "$detached_target_repo" init -q
git -C "$detached_target_repo" config user.email "p0p4@example.invalid"
git -C "$detached_target_repo" config user.name "P0 P4"
printf 'fixture\n' >"$detached_target_repo/README.md"
printf '.worktrees/\n' >"$detached_target_repo/.gitignore"
git -C "$detached_target_repo" add README.md .gitignore
git -C "$detached_target_repo" commit -q -m init
detached_target_manifest="$detached_target_repo/decomposition.json"
cp "$unsafe_task_manifest" "$detached_target_manifest"
git -C "$detached_target_repo" add decomposition.json
git -C "$detached_target_repo" commit -q -m "add detached target fixture"
git -C "$detached_target_repo" checkout -q --detach
detached_target_head="$(git -C "$detached_target_repo" rev-parse HEAD)"
detached_target_out="$detached_target_repo/decompose.out"
detached_target_err="$detached_target_repo/decompose.err"
if (cd "$detached_target_repo" && bash "$FRAMEWORK_DIR/skills/assistant-workflow/scripts/decompose.sh" --task detached-target --input "$detached_target_manifest" >"$detached_target_out" 2>"$detached_target_err"); then
    fail "decompose.sh inferred a target branch from detached HEAD without explicit --target-branch"
elif ! grep -Eqi 'detached.*HEAD.*--target-branch|--target-branch.*detached' "$detached_target_err"; then
    fail "detached HEAD target inference failure was not actionable"
elif [[ "$(git -C "$detached_target_repo" rev-parse HEAD)" != "$detached_target_head" || "$(git -C "$detached_target_repo" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" != "" ]]; then
    fail "detached HEAD target inference failure changed the caller checkout"
elif git -C "$detached_target_repo" show-ref --verify --quiet refs/heads/feature/detached-target || [[ -d "$detached_target_repo/briefs" ]]; then
    fail "detached HEAD target inference created refs or briefs before requiring an explicit target"
else
    pass
fi

test_start "workflow decompose surfaces reject broad layer module folder strategies"
missing_slice_rejection_terms=()
for term in \
    "layer-only, module-only, folder-only" \
    "Contract-only/setup-only work is valid only when it is the deliverable artifact slice" \
    "Broad feature-only splits are invalid live decomposition output" \
    "by_layer" \
    "by_module" \
    "by_feature" \
    "contracts_first"; do
    case "$term" in
        by_layer|by_module|by_feature|contracts_first)
            if ! rg -n "$term" "$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json" "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json" >/dev/null; then
                missing_slice_rejection_terms+=("eval forbidden substring: $term")
            fi
            ;;
        *)
            if ! rg -n "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts" >/dev/null; then
                missing_slice_rejection_terms+=("$term")
            fi
            ;;
    esac
done
if [[ "${#missing_slice_rejection_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "strict slice broad-split rejection terms missing: ${missing_slice_rejection_terms[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
