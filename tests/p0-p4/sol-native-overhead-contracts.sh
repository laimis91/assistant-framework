#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

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
        END { exit has_selector ? 0 : 1 }
    ' "$index_file"
}

rule_pattern_has_decision() {
    local rules_file="$1"
    local pattern="$2"
    local decision="$3"

    awk -v pattern="$pattern" -v decision="$decision" '
        /^[[:space:]]*prefix_rule\([[:space:]]*$/ {
            in_rule = 1
            has_pattern = 0
            has_decision = 0
            next
        }
        in_rule {
            assignment = $0
            sub(/[[:space:]]*#.*/, "", assignment)
            sub(/^[[:space:]]*/, "", assignment)
            sub(/[[:space:]]*$/, "", assignment)
            if (assignment == "pattern=" pattern ",") {
                has_pattern = 1
            }
            if (assignment == "decision=\"" decision "\",") {
                has_decision = 1
            }
        }
        in_rule && /^[[:space:]]*\)[[:space:]]*$/ {
            if (has_pattern && has_decision) {
                found = 1
            }
            in_rule = 0
        }
        END { exit found ? 0 : 1 }
    ' "$rules_file"
}

RULE_MATCH_FIXTURE="$(mktemp "${TMPDIR:-/tmp}/sol-native-rule-match.XXXXXX")"
p0p4_register_cleanup "$RULE_MATCH_FIXTURE"
cat > "$RULE_MATCH_FIXTURE" <<'RULES'
prefix_rule(
    # pattern=["git", "push"],
    # decision="prompt",
)

prefix_rule(
    pattern=["git", "commit"],
    decision="prompt", # operative assignment with a Starlark inline comment
)

prefix_rule(
    pattern=["git", "status"], trailing_invalid_tokens
    decision="prompt",
)

prefix_rule(
    pattern=["git", "fetch"],
    decision="prompt" if false else "allow",
)

prefix_rule(
    pattern=["git", "branch"]
    decision="prompt",
)

prefix_rule(
    pattern=["git", "restore"],
    decision="prompt"
)
RULES
test_start "execution-policy matcher requires exact operative assignments"
if ! rule_pattern_has_decision "$RULE_MATCH_FIXTURE" '["git", "push"]' prompt \
    && rule_pattern_has_decision "$RULE_MATCH_FIXTURE" '["git", "commit"]' prompt \
    && ! rule_pattern_has_decision "$RULE_MATCH_FIXTURE" '["git", "status"]' prompt \
    && ! rule_pattern_has_decision "$RULE_MATCH_FIXTURE" '["git", "fetch"]' prompt \
    && ! rule_pattern_has_decision "$RULE_MATCH_FIXTURE" '["git", "branch"]' prompt \
    && ! rule_pattern_has_decision "$RULE_MATCH_FIXTURE" '["git", "restore"]' prompt; then
    pass
else
    fail "only exact operative pattern/decision assignments with trailing commas may satisfy the matcher"
fi

agents_file="$FRAMEWORK_DIR/AGENTS.md"
workflow_rules="$FRAMEWORK_DIR/codex-rules/workflow.rules"
agents_word_count="$(wc -w < "$agents_file" | tr -d ' ')"
test_start "standing Codex guidance is compact/current and execution-policy safeguards remain deterministic (AGENTS words=$agents_word_count)"
standing_guidance_failures=()
if (( agents_word_count > 450 )); then
    standing_guidance_failures+=("AGENTS.md words $agents_word_count exceed 450")
fi
if rg -qi '^[[:space:]]*[.]\/install[.]sh[[:space:]]+--agent[[:space:]]+codex[[:space:]]+#.*hooks' "$agents_file"; then
    standing_guidance_failures+=("AGENTS.md still says the plain Codex install includes hooks")
fi
if rg -qi 'skills are routed by (the )?`?skill-router[.]sh`? hook|`?skill-router[.]sh`?.*UserPromptSubmit.*route prompts to matching skills' "$agents_file"; then
    standing_guidance_failures+=("AGENTS.md still presents skill-router.sh as normal Codex skill routing")
fi
if rg -qi '^[[:space:]]*#[[:space:]]*hooks[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$workflow_rules"; then
    standing_guidance_failures+=("workflow.rules still instructs enabling hooks=true")
fi
if ! rule_pattern_has_decision "$workflow_rules" '["git", "push"]' prompt; then
    standing_guidance_failures+=("workflow.rules lost the git push prompt")
fi
if ! rule_pattern_has_decision "$workflow_rules" '["git", "commit"]' prompt; then
    standing_guidance_failures+=("workflow.rules lost the git commit prompt")
fi
for force_push_pattern in \
    '["git", "push", "--force"]' \
    '["git", "push", "-f"]'; do
    if ! rule_pattern_has_decision "$workflow_rules" "$force_push_pattern" forbidden; then
        standing_guidance_failures+=("workflow.rules lost forbidden force-push pattern $force_push_pattern")
    fi
done
for destructive_pattern in \
    '["git", "reset", "--hard"]' \
    '["git", "branch", "-D"]' \
    '["rm", "-rf"]'; do
    if ! rule_pattern_has_decision "$workflow_rules" "$destructive_pattern" prompt; then
        standing_guidance_failures+=("workflow.rules lost destructive-operation prompt $destructive_pattern")
    fi
done
if [[ "${#standing_guidance_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "standing guidance contract failed (${#standing_guidance_failures[@]}): ${standing_guidance_failures[*]}"
fi

test_start "fresh Codex default installs native assets without hook runtime state"
CODEX_NATIVE_HOME="$(mktemp -d)"
p0p4_register_cleanup "$CODEX_NATIVE_HOME"
if HOME="$CODEX_NATIVE_HOME" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow \
    >/tmp/p0p4-sol-native-default.out 2>/tmp/p0p4-sol-native-default.err; then
    if [[ -f "$CODEX_NATIVE_HOME/.codex/skills/assistant-workflow/SKILL.md" ]] \
        && [[ -f "$CODEX_NATIVE_HOME/.codex/skills/assistant-workflow/contracts/index.yaml" ]] \
        && [[ ! -e "$CODEX_NATIVE_HOME/.codex/hooks.json" ]] \
        && [[ ! -d "$CODEX_NATIVE_HOME/.codex/hooks/assistant" ]] \
        && ! grep -Fq 'hooks = true' "$CODEX_NATIVE_HOME/.codex/config.toml" 2>/dev/null; then
        pass
    else
        fail "Codex default must install native workflow assets without creating hook configuration, shims, or enabling hooks"
    fi
else
    fail "fresh Codex default install failed; see /tmp/p0p4-sol-native-default.err"
fi

test_start "Codex execution-policy rules remain installed on the native path"
if [[ -f "$CODEX_NATIVE_HOME/.codex/rules/workflow.rules" ]] \
    && cmp -s "$FRAMEWORK_DIR/codex-rules/workflow.rules" "$CODEX_NATIVE_HOME/.codex/rules/workflow.rules" \
    && [[ ! -e "$CODEX_NATIVE_HOME/.codex/hooks.json" ]] \
    && [[ ! -d "$CODEX_NATIVE_HOME/.codex/hooks/assistant" ]]; then
    pass
else
    fail "native Codex install must retain workflow.rules without creating hook runtime state"
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
            contract_index_failures+=("$skill_name $load_set needs selector(s)")
        fi
    done
    if ! grep -Eq '^fallback:[[:space:]]*$' "$index_file" \
        || ! grep -Eq '^  on_missing_selector:[[:space:]]*load_full_authoritative_file[[:space:]]*$' "$index_file" \
        || ! grep -Eq '^  on_invalid_selector:[[:space:]]*load_full_authoritative_file[[:space:]]*$' "$index_file"; then
        contract_index_failures+=("$skill_name index lacks full-authoritative-file fallback for missing/invalid selectors")
    fi
done
if ! ruby -ryaml -e '
  sets = YAML.load_file(ARGV[0]).fetch("load_sets")
  protocol = "references/build-worker-protocol.md"
  builders = %w[orchestrator_to_code_writer orchestrator_to_builder_tester]
  other_roles = %w[orchestrator_to_code_mapper orchestrator_to_explorer orchestrator_to_architect_decompose orchestrator_to_architect]
  valid = lambda do |candidate|
    base = candidate.fetch("selected_handoff")
    build = candidate.fetch("build_handoff", {})
    selected = build.fetch("selectors", []).find { |item| item["name_from"] == "selected_handoff_name" }
    next false unless selected && selected["allowed_names"] == builders
    refs_for = lambda do |role|
      selected.fetch("allowed_names").include?(role) ? build.fetch("references", []) : base.fetch("references", [])
    end
    builders.all? { |role| refs_for.call(role).include?(protocol) } &&
      other_roles.none? { |role| refs_for.call(role).include?(protocol) }
  end
  abort "Build protocol leaks to non-Build handoffs or is unavailable to Build workers" unless valid.call(sets)
  leaked = Marshal.load(Marshal.dump(sets))
  leaked.fetch("selected_handoff")["references"] = [protocol]
  abort "unconditional protocol reference accepted" if valid.call(leaked)
  widened = Marshal.load(Marshal.dump(sets))
  widened.fetch("build_handoff").fetch("selectors").first.fetch("allowed_names") << "orchestrator_to_architect"
  abort "non-Build selector accepted" if valid.call(widened)
' "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/index.yaml"; then
    contract_index_failures+=("Build-only handoff loading boundary")
fi
if [[ "${#contract_index_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "contract index structure failed: ${contract_index_failures[*]}"
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
# Roots route to the index and relevant sets. The index owns the actual file
# mapping; duplicating that mapping in root prose is not a loading requirement.
for skill_name in assistant-workflow assistant-review; do
    skill_file="$FRAMEWORK_DIR/skills/$skill_name/SKILL.md"
    if ! grep -Fq 'contracts/index.yaml' "$skill_file"; then
        progressive_failures+=("$skill_name does not route through its selector index")
    fi
    if ! tr '\n' ' ' < "$skill_file" | grep -Eq 'relevant|applicable|only as needed'; then
        progressive_failures+=("$skill_name lacks conditional loading guidance")
    fi
    if ! ruby -ryaml -e '
      index = YAML.load_file(ARGV.fetch(0)).fetch("load_sets")
      current = ARGV.fetch(1) == "assistant-workflow" ? "current_phase" : "current_round"
      {"entry" => "input", "selected_handoff" => "handoffs", current => "phase-gates", "completion" => "output"}.each do |name, file|
        selectors = index.fetch(name).fetch("selectors")
        abort "#{name} has no #{file} selector" unless selectors.any? { |selector| selector["path"] == "contracts/#{file}.yaml" }
      end
    ' "$FRAMEWORK_DIR/skills/$skill_name/contracts/index.yaml" "$skill_name"; then
        progressive_failures+=("$skill_name index lost a boundary-specific canonical file mapping")
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
if rg -qi 'Learning Controller|Reflexion|memory_(reflect|signal|trend)' "$completion_controller"; then
    completion_failures+=("completion controller retains retired custom-memory behavior")
fi
if ! rg -qi 'metrics.*(optional|non-blocking|never a reason to block)|does not make metrics blocking' "$completion_controller"; then
    completion_failures+=("metrics are not explicitly optional or non-blocking")
fi
if ! rg -qi 'manual verification.+(only|required when).*(subjective|external|destructive|UI|explicit)' "$completion_controller"; then
    completion_failures+=("manual verification is not limited to subjective/external/destructive/UI/explicit acceptance")
fi
if ! rg -qi 'small.+(does not require|without).+(task journal|metrics|manual verification)' "$completion_controller"; then
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
