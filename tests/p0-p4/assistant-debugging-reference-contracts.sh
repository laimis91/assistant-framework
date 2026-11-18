if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

debugging_root="$FRAMEWORK_DIR/skills/assistant-debugging"

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
    present = descriptions.values.compact.reject { |text| text.strip.empty? }
    failures << "descriptions are not byte-identical" unless present.size == 3 && present.uniq.size == 1

    enums = fields.transform_values { |field| enum_text(field.fetch("enum_values")).sort }
    failures << "reproduction enums differ: #{enums}" unless enums.values.uniq.size == 1
    fields.each { |label, field| failures << "#{label} requiredness changed" unless field["required"] == true }

    puts failures
    exit(failures.empty? ? 0 : 1)
' "$debugging_root/contracts/output.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-tdd/contracts/input.yaml" 2>&1)"; then
    pass
else
    fail "$(tr '\n' ';' <<<"$ruby_output")"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
