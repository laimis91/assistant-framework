#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

framework_hook_names=(
    session-start.sh
    skill-router.sh
    learning-signals.sh
    workflow-enforcer.sh
    workflow-guard.sh
    stop-review.sh
    subagent-monitor.sh
    pre-compress.sh
    post-compact.sh
)

count_framework_hook_commands() {
    local hooks_file="$1"

    if [[ ! -f "$hooks_file" ]]; then
        printf '0\n'
        return 0
    fi

    jq -r '
        def first_shell_token:
            (gsub("^\\s+"; "") | gsub("\\s+"; " ") | split(" ") | .[0] // "");
        def framework_hook_name:
            [
                "session-start.sh",
                "skill-router.sh",
                "learning-signals.sh",
                "workflow-enforcer.sh",
                "workflow-guard.sh",
                "stop-review.sh",
                "subagent-monitor.sh",
                "pre-compress.sh",
                "post-compact.sh",
                "task-completed.sh",
                "task-journal-resolver.sh",
                "workflow-phase-gates.sh",
                "harness-gate.sh",
                "post-tool-context.sh",
                "tool-failure-advisor.sh"
            ];
        [
            .. | objects | .command? // empty
            | first_shell_token
            | split("/") | last
            | select(. as $name | any(framework_hook_name[]; . == $name))
        ] | length
    ' "$hooks_file"
}

marker_block_words() {
    local file="$1"
    local start_marker="$2"
    local end_marker="$3"

    awk -v start_marker="$start_marker" -v end_marker="$end_marker" '
        index($0, start_marker) { in_block = 1 }
        in_block { print }
        index($0, end_marker) && in_block { in_block = 0 }
    ' "$file" | wc -w | tr -d ' '
}

mandatory_skill_words() {
    local skill_dir="$1"
    local skill_file="$skill_dir/SKILL.md"
    local index_file="$skill_dir/contracts/index.yaml"
    local words

    words="$(wc -w < "$skill_file" | tr -d ' ')"
    if [[ -f "$index_file" ]]; then
        words=$(( words + $(wc -w < "$index_file" | tr -d ' ') ))
    fi
    if rg -qi \
        'all contracts are mandatory|read (all |the )?contract files in .contracts/.+before|load and follow .+contracts before' \
        "$skill_file"; then
        while IFS= read -r contract_file; do
            [[ "$(basename "$contract_file")" == "index.yaml" ]] && continue
            words=$(( words + $(wc -w < "$contract_file" | tr -d ' ') ))
        done < <(find "$skill_dir/contracts" -maxdepth 1 -type f -name '*.yaml' -print | sort)
    fi

    printf '%s\n' "$words"
}

skill_root_index_words() {
    local skill_dir="$1"
    local words

    words="$(wc -w < "$skill_dir/SKILL.md" | tr -d ' ')"
    if [[ -f "$skill_dir/contracts/index.yaml" ]]; then
        words=$(( words + $(wc -w < "$skill_dir/contracts/index.yaml" | tr -d ' ') ))
    fi
    printf '%s\n' "$words"
}

index_has_authoritative_contract() {
    local index_file="$1"
    local contract_path="$2"

    awk -v contract_path="$contract_path" '
        /^authoritative_contracts:[[:space:]]*$/ { in_contracts = 1; next }
        in_contracts && /^[^[:space:]#]/ { exit }
        in_contracts && $0 ~ "^[[:space:]]*-[[:space:]]*path:[[:space:]]*" contract_path "[[:space:]]*$" { found = 1 }
        END { exit found ? 0 : 1 }
    ' "$index_file"
}

index_load_set_is_bounded() {
    local index_file="$1"
    local load_set="$2"

    awk -v load_set="$load_set" '
        $0 == "  " load_set ":" { in_set = 1; next }
        in_set && /^  [[:alnum:]_-]+:[[:space:]]*$/ { exit }
        in_set && /^    selectors?:/ { has_selector = 1 }
        in_set && /^    budget_words:[[:space:]]*[1-9][0-9]*[[:space:]]*$/ { has_budget = 1 }
        END { exit has_selector && has_budget ? 0 : 1 }
    ' "$index_file"
}

test_start "fresh Codex default is native and registers zero framework hook commands"
CODEX_NATIVE_HOME="$(mktemp -d)"
p0p4_register_cleanup "$CODEX_NATIVE_HOME"
if HOME="$CODEX_NATIVE_HOME" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow \
    >/tmp/p0p4-sol-native-default.out 2>/tmp/p0p4-sol-native-default.err; then
    native_hook_count="$(count_framework_hook_commands "$CODEX_NATIVE_HOME/.codex/hooks.json")"
    if [[ "$native_hook_count" == "0" ]] \
        && ! grep -Fq 'hooks = true' "$CODEX_NATIVE_HOME/.codex/config.toml"; then
        pass
    else
        fail "Codex default must register zero Assistant Framework hook commands and must not enable hooks; found $native_hook_count commands"
    fi
else
    fail "fresh Codex default install failed; see /tmp/p0p4-sol-native-default.err"
fi

test_start "explicit Codex workflow and strict profiles retain enforcement stacks"
CODEX_WORKFLOW_HOME="$(mktemp -d)"
CODEX_STRICT_HOME="$(mktemp -d)"
p0p4_register_cleanup "$CODEX_WORKFLOW_HOME" "$CODEX_STRICT_HOME"
profile_failure=""
for profile in workflow strict; do
    if [[ "$profile" == "workflow" ]]; then
        profile_home="$CODEX_WORKFLOW_HOME"
    else
        profile_home="$CODEX_STRICT_HOME"
    fi
    if ! HOME="$profile_home" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --hook-profile "$profile" \
        >"/tmp/p0p4-sol-native-$profile.out" 2>"/tmp/p0p4-sol-native-$profile.err"; then
        profile_failure="$profile install failed"
        break
    fi
    if ! jq -e --arg command_dir "$profile_home/.codex/hooks/assistant" '
        {
            router: ([.hooks.UserPromptSubmit[]?.hooks[]?.command?] | any(. == ($command_dir + "/skill-router.sh"))),
            enforcer: ([.hooks.UserPromptSubmit[]?.hooks[]?.command?] | any(. == ($command_dir + "/workflow-enforcer.sh"))),
            guard: ([.hooks.PreToolUse[]?.hooks[]?.command?] | any(. == ($command_dir + "/workflow-guard.sh"))),
            review: ([.hooks.Stop[]?.hooks[]?.command?] | any(. == ($command_dir + "/stop-review.sh"))),
            subagents: ([.hooks.SubagentStart[]?.hooks[]?.command?] | any(. == ($command_dir + "/subagent-monitor.sh")))
        }
        | (.router | not) and .enforcer and .guard and .review and .subagents
    ' "$profile_home/.codex/hooks.json" >/dev/null; then
        profile_failure="$profile profile is missing its enforcement stack"
        break
    fi
done
if [[ -z "$profile_failure" ]]; then
    pass
else
    fail "$profile_failure"
fi

test_start "native Codex reinstall prunes framework commands, preserves custom hooks, and leaves inert cached entrypoints"
CODEX_MIGRATION_HOME="$(mktemp -d)"
p0p4_register_cleanup "$CODEX_MIGRATION_HOME"
mkdir -p "$CODEX_MIGRATION_HOME/.codex/hooks/assistant"
cat > "$CODEX_MIGRATION_HOME/.codex/hooks.json" <<'JSON'
{
  "hooks": {
    "UserPromptSubmit": [
      {"matcher":"","hooks":[
        {"type":"command","command":"$HOME/.codex/hooks/assistant/skill-router.sh"},
        {"type":"command","command":"/tmp/user-codex-prompt-hook.sh"}
      ]}
    ],
    "PreToolUse": [
      {"matcher":"","hooks":[
        {"type":"command","command":"$HOME/.codex/hooks/assistant/workflow-guard.sh"},
        {"type":"command","command":"/tmp/user-codex-pretool-hook.sh"}
      ]}
    ]
  }
}
JSON
for framework_hook in "${framework_hook_names[@]}"; do
    printf '%s\n' '#!/usr/bin/env bash' 'echo stale-framework-output' > "$CODEX_MIGRATION_HOME/.codex/hooks/assistant/$framework_hook"
    chmod +x "$CODEX_MIGRATION_HOME/.codex/hooks/assistant/$framework_hook"
done
if HOME="$CODEX_MIGRATION_HOME" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow \
    >/tmp/p0p4-sol-native-migration.out 2>/tmp/p0p4-sol-native-migration.err; then
    migration_failures=()
    migration_hook_count="$(count_framework_hook_commands "$CODEX_MIGRATION_HOME/.codex/hooks.json")"
    if [[ "$migration_hook_count" != "0" ]]; then
        migration_failures+=("$migration_hook_count framework commands remain")
    fi
    if ! jq -e '
        [.. | objects | .command? // empty] as $commands
        | ($commands | any(. == "/tmp/user-codex-prompt-hook.sh"))
          and ($commands | any(. == "/tmp/user-codex-pretool-hook.sh"))
    ' "$CODEX_MIGRATION_HOME/.codex/hooks.json" >/dev/null; then
        migration_failures+=("custom hooks were not preserved")
    fi
    for framework_hook in "${framework_hook_names[@]}"; do
        cached_entrypoint="$CODEX_MIGRATION_HOME/.codex/hooks/assistant/$framework_hook"
        if [[ ! -x "$cached_entrypoint" ]]; then
            migration_failures+=("missing executable shim $framework_hook")
            continue
        fi
        shim_output="$(HOME="$CODEX_MIGRATION_HOME" CODEX_PROJECT_DIR="$FRAMEWORK_DIR" bash "$cached_entrypoint" <<< '{}' 2>/dev/null || true)"
        if [[ -n "$shim_output" ]]; then
            migration_failures+=("$framework_hook shim is not silent")
        fi
    done
    if [[ "${#migration_failures[@]}" -eq 0 ]]; then
        pass
    else
        fail "native reinstall migration failed: ${migration_failures[*]}"
    fi
else
    fail "native Codex reinstall failed; see /tmp/p0p4-sol-native-migration.err"
fi

test_start "Codex execution-policy rules install independently from hooks"
if [[ -f "$CODEX_NATIVE_HOME/.codex/rules/workflow.rules" ]] \
    && cmp -s "$FRAMEWORK_DIR/codex-rules/workflow.rules" "$CODEX_NATIVE_HOME/.codex/rules/workflow.rules" \
    && [[ "$(count_framework_hook_commands "$CODEX_NATIVE_HOME/.codex/hooks.json")" == "0" ]]; then
    pass
else
    fail "native Codex install must retain workflow.rules without registering framework hooks"
fi

test_start "compatibility skill router selects one primary skill for overlapping prompts"
ROUTER_HOME="$(mktemp -d)"
p0p4_register_cleanup "$ROUTER_HOME"
mkdir -p "$ROUTER_HOME/.claude/skills/assistant-workflow" "$ROUTER_HOME/.claude/skills/assistant-review"
cp "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md" "$ROUTER_HOME/.claude/skills/assistant-workflow/SKILL.md"
cp "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md" "$ROUTER_HOME/.claude/skills/assistant-review/SKILL.md"
router_output="$({ printf '%s\n' '{"prompt":"Fix the review findings, then implement the changes."}' \
    | HOME="$ROUTER_HOME" CLAUDE_PROJECT_DIR="$FRAMEWORK_DIR" bash "$FRAMEWORK_DIR/hooks/scripts/skill-router.sh"; } 2>/dev/null || true)"
router_match_count="$(printf '%s\n' "$router_output" | awk -F'SKILL MATCH \\(' '{count += NF - 1} END {print count + 0}')"
if [[ "$router_match_count" == "1" ]] \
    && [[ "$router_output" == *"SKILL MATCH (1/1)"* ]] \
    && [[ "$router_output" == *"assistant-review"* ]] \
    && [[ "$router_output" != *"assistant-workflow"* ]]; then
    pass
else
    fail "overlap must select only highest-priority assistant-review; matches=$router_match_count output='$router_output'"
fi

test_start "workflow and review contract indexes define authoritative selector-bounded load sets"
contract_index_failures=()
for skill_name in assistant-workflow assistant-review; do
    index_file="$FRAMEWORK_DIR/skills/$skill_name/contracts/index.yaml"
    skill_file="$FRAMEWORK_DIR/skills/$skill_name/SKILL.md"
    if [[ ! -f "$index_file" ]]; then
        contract_index_failures+=("$skill_name missing contracts/index.yaml")
        continue
    fi
    if ! grep -Fq 'contracts/index.yaml' "$skill_file"; then
        contract_index_failures+=("$skill_name SKILL.md does not route through contracts/index.yaml")
    fi
    if ! grep -Eq '^schema_version:[[:space:]]*"?[0-9]+[.][0-9]+"?[[:space:]]*$' "$index_file" \
        || ! grep -Eq '^contract:[[:space:]]*index[[:space:]]*$' "$index_file" \
        || ! grep -Eq "^skill:[[:space:]]*$skill_name[[:space:]]*$" "$index_file"; then
        contract_index_failures+=("$skill_name index has no schema_version/contract=index/skill header")
    fi
    for contract_path in \
        contracts/input.yaml \
        contracts/output.yaml \
        contracts/phase-gates.yaml \
        contracts/handoffs.yaml; do
        if ! index_has_authoritative_contract "$index_file" "$contract_path"; then
            contract_index_failures+=("$skill_name index missing authoritative $contract_path")
        fi
    done
    load_sets=(entry selected_handoff completion)
    if [[ "$skill_name" == "assistant-workflow" ]]; then
        load_sets+=(current_phase)
    else
        load_sets+=(current_round)
    fi
    for load_set in "${load_sets[@]}"; do
        if ! index_load_set_is_bounded "$index_file" "$load_set"; then
            contract_index_failures+=("$skill_name $load_set needs selector(s) and positive budget_words")
        fi
    done
    if ! grep -Eq '^fallback:[[:space:]]*$' "$index_file" \
        || ! grep -Eq '^  on_missing_selector:[[:space:]]*load_full_authoritative_file[[:space:]]*$' "$index_file" \
        || ! grep -Eq '^  on_invalid_selector:[[:space:]]*load_full_authoritative_file[[:space:]]*$' "$index_file"; then
        contract_index_failures+=("$skill_name index lacks full-authoritative-file fallback for missing/invalid selectors")
    fi
done
if [[ "${#contract_index_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "contract index structure failed: ${contract_index_failures[*]}"
fi

workflow_words="$(mandatory_skill_words "$FRAMEWORK_DIR/skills/assistant-workflow")"
review_words="$(mandatory_skill_words "$FRAMEWORK_DIR/skills/assistant-review")"
workflow_root_index_words="$(skill_root_index_words "$FRAMEWORK_DIR/skills/assistant-workflow")"
review_root_index_words="$(skill_root_index_words "$FRAMEWORK_DIR/skills/assistant-review")"
agents_words="$(marker_block_words "$CODEX_NATIVE_HOME/.codex/AGENTS.md" ASSISTANT_FRAMEWORK_AGENTS_MD_START ASSISTANT_FRAMEWORK_AGENTS_MD_END)"
memory_words="$(marker_block_words "$CODEX_NATIVE_HOME/.codex/AGENTS.md" ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END)"
guidance_words=$(( agents_words + memory_words ))
test_start "initial instruction budgets count SKILL+index and eager closure (workflow initial=$workflow_root_index_words eager=$workflow_words; review initial=$review_root_index_words eager=$review_words; guidance=$guidance_words)"
budget_failures=()
if (( workflow_root_index_words >= 4000 )); then
    budget_failures+=("workflow SKILL+index words $workflow_root_index_words is not below 4000")
fi
if (( review_root_index_words >= 5000 )); then
    budget_failures+=("review SKILL+index words $review_root_index_words is not below 5000")
fi
if (( workflow_words >= 4000 )); then
    budget_failures+=("workflow transitive words $workflow_words is not below 4000")
fi
if (( review_words >= 5000 )); then
    budget_failures+=("review transitive words $review_words is not below 5000")
fi
if (( guidance_words >= 900 )); then
    budget_failures+=("generated AGENTS+memory words $guidance_words is not below 900")
fi
if [[ "${#budget_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "instruction load budget failed: ${budget_failures[*]}"
fi

test_start "workflow and review contracts are phase-scoped instead of eagerly loaded"
workflow_skill="$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md"
review_skill="$FRAMEWORK_DIR/skills/assistant-review/SKILL.md"
progressive_failures=()
if rg -qi 'all contracts are mandatory|load and follow .+contracts before acting' "$workflow_skill"; then
    progressive_failures+=("workflow still eagerly requires every contract")
fi
if rg -qi 'read (all |the )?contract files in .contracts/.+before|load and follow .+contracts before' "$review_skill"; then
    progressive_failures+=("review still eagerly requires every contract")
fi
if ! rg -qi 'load only .+contract.+(current|active|applicable|when needed)|do not load (all|every) contract' "$workflow_skill"; then
    progressive_failures+=("workflow lacks an explicit progressive contract-loading rule")
fi
if ! rg -qi 'load only .+contract.+(current|active|applicable|when needed)|do not load (all|every) contract' "$review_skill"; then
    progressive_failures+=("review lacks an explicit progressive contract-loading rule")
fi
if ! grep -Fq 'contracts/index.yaml' "$workflow_skill"; then
    progressive_failures+=("workflow does not load contracts/index.yaml as its selector index")
fi
if ! grep -Fq 'contracts/index.yaml' "$review_skill"; then
    progressive_failures+=("review does not load contracts/index.yaml as its selector index")
fi
for scoped_rule in \
    'input.yaml.*(Triage|Discover|entry)' \
    'handoffs.yaml.*(delegat|dispatch|handoff)' \
    'phase-gates.yaml.*(current|active|transition|round)' \
    'output.yaml.*(final|completion|exit)'; do
    if ! rg -qi "$scoped_rule" "$workflow_skill"; then
        progressive_failures+=("workflow missing scoped rule: $scoped_rule")
    fi
    if ! rg -qi "$scoped_rule" "$review_skill"; then
        progressive_failures+=("review missing scoped rule: $scoped_rule")
    fi
done
if [[ "${#progressive_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive contract loading failed: ${progressive_failures[*]}"
fi

test_start "completion ceremony is conditional and non-blocking outside applicable work"
completion_controller="$FRAMEWORK_DIR/skills/assistant-workflow/references/completion-controller.md"
workflow_phases="$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"
completion_failures=()
if rg -qi 'before completion, add .+learning controller' "$completion_controller"; then
    completion_failures+=("Learning Controller remains unconditional")
fi
if ! rg -qi '(metrics|reflexion|memory).*(optional|non-blocking|not a completion blocker)' "$completion_controller"; then
    completion_failures+=("metrics/reflexion/memory are not explicitly optional or non-blocking")
fi
if ! rg -qi 'manual verification.+(only|required when).*(subjective|external|destructive|UI|explicit)' "$completion_controller"; then
    completion_failures+=("manual verification is not limited to subjective/external/destructive/UI/explicit acceptance")
fi
if ! rg -qi 'small.+(does not require|without).+(task journal|metrics|reflexion|manual verification)' "$completion_controller"; then
    completion_failures+=("small completion does not explicitly omit ceremony")
fi
if ! rg -qi '(task journal.+(medium\+|cross-session|clarification|harness)|(medium\+|cross-session|clarification|harness).+task journal)' "$workflow_phases"; then
    completion_failures+=("task journals are not scoped to durable-state cases")
fi
if [[ "${#completion_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "conditional completion contract failed: ${completion_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
