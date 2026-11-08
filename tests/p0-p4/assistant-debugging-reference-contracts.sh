if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

debugging_root="$FRAMEWORK_DIR/skills/assistant-debugging"
debugging_skill="$debugging_root/SKILL.md"
debugging_reproduction="$debugging_root/references/reproduction.md"
debugging_state_inspection="$debugging_root/references/state-inspection.md"

test_start "reproduction status meaning is identical across Debugging, Workflow and TDD"
if ruby_output="$(ruby -ryaml -e '
    def find_field(fields, name)
      fields.find { |field| field["name"] == name } or raise "missing field #{name}"
    end
    def enum_text(values)
      values.map { |value| value == true ? "yes" : value == false ? "no" : value.to_s }
    end
    debugging = YAML.load_file(ARGV.fetch(0))
    workflow = YAML.load_file(ARGV.fetch(1))
    tdd = YAML.load_file(ARGV.fetch(2))
    failures = []

    debugging_field = find_field(find_field(debugging.fetch("artifacts"), "reproduction").fetch("object_fields"), "reproduced")
    workflow_field = find_field(find_field(workflow.fetch("artifacts"), "debugging_result").fetch("object_fields"), "reproduction_status")
    tdd_evidence = find_field(tdd.fetch("fields"), "debugging_evidence")
    tdd_field = find_field(tdd_evidence.fetch("object_fields"), "reproduction_status")

    fields = { "Debugging reproduction.reproduced" => debugging_field,
               "Workflow debugging_result.reproduction_status" => workflow_field,
               "TDD debugging_evidence.reproduction_status" => tdd_field }
    descriptions = fields.transform_values { |field| field["description"] }
    descriptions.each do |label, text|
      if text.nil? || text.strip.empty?
        failures << "#{label} has no description"
        next
      end
      ["exact reported symptom",
       "nearby unrelated failure on the same path would not satisfy that check",
       "`partial`: the symptom was observed, but the check does not distinguish it from a nearby unrelated failure",
       "only part of the symptom was observed",
       "Historical `yes` records may predate this discrimination rule"].each do |term|
        failures << "#{label} description lacks: #{term}" unless text.include?(term)
      end
    end
    present = descriptions.values.compact
    failures << "descriptions are not byte-identical" unless present.size == 3 && present.uniq.size == 1

    failures << "Debugging enum changed" unless enum_text(debugging_field.fetch("enum_values")) == %w[yes no blocked partial]
    failures << "Workflow enum changed" unless enum_text(workflow_field.fetch("enum_values")) == %w[yes no blocked partial]
    failures << "TDD enum changed" unless enum_text(tdd_field.fetch("enum_values")) == %w[yes partial blocked no]
    fields.each { |label, field| failures << "#{label} requiredness changed" unless field["required"] == true }

    failures << "Debugging output schema_version changed" unless debugging["schema_version"] == "3.0"
    failures << "Workflow output schema_version changed" unless workflow["schema_version"] == "16.0"
    failures << "TDD input schema_version changed" unless tdd["schema_version"] == "3.0"

    expected_validation = "Must include reproduction_status, root_cause_or_mitigation, confidence, and original_failure_path; do not start RED for unknown-cause bugfixes without this evidence or a documented blocker"
    failures << "TDD debugging_evidence.validation changed" unless tdd_evidence["validation"] == expected_validation

    puts failures
    exit(failures.empty? ? 0 : 1)
' "$debugging_root/contracts/output.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-tdd/contracts/input.yaml" 2>&1)"; then
    pass
else
    fail "$(tr '\n' ';' <<<"$ruby_output")"
fi

p0p4_debugging_forbidden_hits() {
    local file="$1"
    shift
    local term
    local hits=()
    for term in "$@"; do
        if grep -Fqi -- "$term" "$file"; then hits+=("forbidden: $term"); fi
    done
    printf '%s\n' "${hits[@]:-}"
}

p0p4_debugging_quota_hits() {
    local file="$1"
    if grep -Eqi '\b([0-9]+|two|three|four|five)\b[^.]{0,20}\b(attempts?|tries|retries)\b' "$file"; then
        echo "attempt-count quota"
    fi
    if grep -Eqi 'escalat' "$file"; then
        echo "escalation threshold"
    fi
}

test_start "reproduction reference carries the exact-symptom method without quotas"
reproduction_failures=()
if [[ ! -f "$debugging_reproduction" ]]; then
    reproduction_failures+=("missing skills/assistant-debugging/references/reproduction.md")
else
    for term in \
        'no adequate exact-symptom reproduction exists yet' \
        'existing failing test' \
        'CLI or HTTP probe' \
        'replay of a captured trace or payload' \
        'small harness around the failing path' \
        'controlled reproduction of a flaky failure' \
        'bisection between a known-good and a known-bad state' \
        'differential comparison' \
        'not an order' \
        'exact reported symptom' \
        'non-zero exit' \
        'nearby unrelated failure' \
        'record `partial`, not `yes`' \
        'contracts/output.yaml' \
        'fixed seed' \
        'runs with seed' \
        'never proof' \
        'restore' \
        'regression oracle' \
        'separate worktree' \
        'uncommitted work' \
        '[the shared stagnation guard](../../../tools/progress/operating-guidance.md)' \
        '(lifecycle-verification.md)'; do
        if ! p0p4_contains_text "$debugging_reproduction" "$term"; then reproduction_failures+=("missing: $term"); fi
    done
    while IFS= read -r hit; do
        [[ -n "$hit" ]] && reproduction_failures+=("$hit")
    done < <(p0p4_debugging_forbidden_hits "$debugging_reproduction" \
        'after three' 'after 3 ' 'success rate' 'git stash' 'reset --hard')
    if grep -Eqi '([0-9]+|three|five)[^.]{0,12}hypothes' "$debugging_reproduction"; then
        reproduction_failures+=("numeric hypothesis quota")
    fi
    while IFS= read -r hit; do
        [[ -n "$hit" ]] && reproduction_failures+=("$hit")
    done < <(p0p4_debugging_quota_hits "$debugging_reproduction")
fi
if [[ ${#reproduction_failures[@]} -eq 0 ]]; then pass; else fail "${reproduction_failures[*]}"; fi

test_start "state-inspection recipes stay local, non-interactive-first and clean"
inspection_failures=()
if [[ ! -f "$debugging_state_inspection" ]]; then
    inspection_failures+=("missing skills/assistant-debugging/references/state-inspection.md")
else
    for heading in '## Python' '## Node' '## .NET'; do
        if ! grep -Fxq -- "$heading" "$debugging_state_inspection"; then inspection_failures+=("missing heading: $heading"); fi
    done
    for term in \
        'runtime-state question' \
        'non-interactive' \
        'hang' \
        'loopback' \
        '127.0.0.1' \
        'ws://' \
        'read the actual endpoint' \
        'already installed' \
        'ask the user before installing' \
        'outside the repository' \
        'terminate' \
        'remove' \
        'report' \
        'VSTest' \
        'Microsoft.Testing.Platform' \
        'FullyQualifiedName~' \
        'Exception.ToString()' \
        'no TCP diagnostic port' \
        'stagnation guard'; do
        if ! p0p4_contains_text "$debugging_state_inspection" "$term"; then inspection_failures+=("missing: $term"); fi
    done
    while IFS= read -r hit; do
        [[ -n "$hit" ]] && inspection_failures+=("$hit")
    done < <(p0p4_debugging_forbidden_hits "$debugging_state_inspection" \
        '0.0.0.0' '9229' '5678' 'sudo' 'ptrace_scope' 'dotnet tool install' 'DiagnosticPorts' \
        'vsdbg' 'npm install -g' 'pip install' 'after three' 'success rate')
    while IFS= read -r hit; do
        [[ -n "$hit" ]] && inspection_failures+=("$hit")
    done < <(p0p4_debugging_quota_hits "$debugging_state_inspection")
fi
if [[ ${#inspection_failures[@]} -eq 0 ]]; then pass; else fail "${inspection_failures[*]}"; fi

test_start "debugging root links the new references with their load conditions"
root_failures=()
if ! grep -Fq -- '(references/reproduction.md)' "$debugging_skill"; then
    root_failures+=("SKILL.md does not link references/reproduction.md")
fi
if ! grep -Fq -- '(references/state-inspection.md)' "$debugging_skill"; then
    root_failures+=("SKILL.md does not link references/state-inspection.md")
fi
for term in \
    'when no adequate exact-symptom reproduction exists yet' \
    'runtime-state question in Python, Node or .NET that the reproduction, traceback or logs cannot answer' \
    'already has an exact-symptom reproduction loads neither' \
    '`reproduced` description in `contracts/output.yaml`'; do
    if ! p0p4_contains_text "$debugging_skill" "$term"; then root_failures+=("missing: $term"); fi
done
expected_frontmatter='---
name: assistant-debugging
description: "Diagnose an unknown failure by reproducing and isolating before fixing. Use for debugging, root causes, flaky tests, or unexplained breakage."
requires:
  - assistant-review
  - assistant-verification
  - assistant-tdd
---'
if [[ "$(sed -n '1,8p' "$debugging_skill")" != "$expected_frontmatter" ]]; then
    root_failures+=("SKILL.md frontmatter changed")
fi
if [[ ${#root_failures[@]} -eq 0 ]]; then pass; else fail "${root_failures[*]}"; fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
