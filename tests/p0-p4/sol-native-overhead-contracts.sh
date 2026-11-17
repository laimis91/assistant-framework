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

agents_file="$FRAMEWORK_DIR/AGENTS.md"
agents_word_count="$(wc -w < "$agents_file" | tr -d ' ')"
test_start "standing Codex guidance is compact and current (AGENTS words=$agents_word_count)"
standing_guidance_failures=()
if (( agents_word_count > 450 )); then
    standing_guidance_failures+=("AGENTS.md words $agents_word_count exceed 450")
fi
if rg -qi 'skills are routed by (the )?`?skill-router[.]sh`? hook|`?skill-router[.]sh`?.*UserPromptSubmit.*route prompts to matching skills' "$agents_file"; then
    standing_guidance_failures+=("AGENTS.md still presents skill-router.sh as normal Codex skill routing")
fi
if [[ "${#standing_guidance_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "standing guidance contract failed (${#standing_guidance_failures[@]}): ${standing_guidance_failures[*]}"
fi

test_start "plugin ships native workflow assets without hook runtime state"
plugin_root="$FRAMEWORK_DIR/plugins/assistant-framework"
if [[ -f "$plugin_root/skills/assistant-workflow/SKILL.md" ]] \
    && [[ -f "$plugin_root/skills/assistant-workflow/contracts/index.yaml" ]] \
    && [[ ! -e "$plugin_root/hooks" ]] \
    && [[ -z "$(find "$plugin_root" -name hooks.json -print -quit)" ]]; then
    pass
else
    fail "plugin must ship native workflow assets without hook configuration"
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
