if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

skill_validator="$FRAMEWORK_DIR/tools/skills/validate-skills.sh"

p0p4_write_valid_skill_fixture() {
    local skill_dir="$1"
    local skill_name

    skill_name="$(basename "$skill_dir")"
    mkdir -p "$skill_dir/contracts"
    cat >"$skill_dir/SKILL.md" <<EOF
---
name: $skill_name
description: "Fixture skill used by the validator contract tests."
---

# Fixture Skill

## Contracts

| File | Purpose |
|---|---|
| \`contracts/input.yaml\` | fixture input |
| \`contracts/output.yaml\` | fixture output |
EOF

    cat >"$skill_dir/contracts/input.yaml" <<EOF
schema_version: "1.0"
contract: input
skill: $skill_name

fields:
  - name: request
    type: string
    required: true
    description: "Fixture request"
    validation: "Non-empty request"
    on_missing: ask
EOF

    cat >"$skill_dir/contracts/output.yaml" <<EOF
schema_version: "1.0"
contract: output
skill: $skill_name

artifacts:
  - name: result
    type: string
    required: true
    description: "Fixture result"
    validation: "Non-empty result"
    on_fail: "Re-run the fixture skill and provide a result"
EOF
}

test_start "skill validator exists and is executable"
if [[ -x "$skill_validator" ]]; then
    pass
else
    fail "missing or non-executable validator: $skill_validator"
fi

test_start "skill validator default repo validation passes"
if "$skill_validator" >/dev/null; then
    pass
else
    fail "default validator run failed"
fi

test_start "skill validator default list includes assistant skills and excludes local unity skills"
list_fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-validator-list.XXXXXX")"
p0p4_register_cleanup "$list_fixture_root"
unity_fixture_dir="$(mktemp -d "$FRAMEWORK_DIR/skills/unity-validator-local.XXXXXX")"
unity_fixture_name="$(basename "$unity_fixture_dir")"
p0p4_register_cleanup "$unity_fixture_dir"
p0p4_write_valid_skill_fixture "$unity_fixture_dir"
list_output="$("$skill_validator" --list)"
if printf '%s\n' "$list_output" | grep -Fq "assistant-workflow" \
    && ! printf '%s\n' "$list_output" | grep -Fq "$unity_fixture_name"; then
    pass
else
    fail "default skill list should include assistant skills and exclude local unity skills"
fi

test_start "skill validator targeted custom skill path works"
custom_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-validator-custom.XXXXXX")"
p0p4_register_cleanup "$custom_root"
p0p4_write_valid_skill_fixture "$custom_root/custom-validator-skill"
if "$skill_validator" --skill "$custom_root/custom-validator-skill" >/dev/null; then
    pass
else
    fail "targeted custom skill path did not validate"
fi

test_start "skill validator rejects semantically empty, non-string, and unsupported plain descriptions"
description_scalar_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-validator-description-scalars.XXXXXX")"
p0p4_register_cleanup "$description_scalar_root"
description_scalar_failures=()
for description_scalar_case in empty_single empty_double quoted_whitespace null_word null_tilde boolean number collection malformed_quote block_scalar sequence_entry mapping_entry mapping_pair reserved_at hex_number binary_number separator_number comma_number signed_comma_number comma_decimal_number leading_decimal iso_date loose_iso_date iso_timestamp; do
    case "$description_scalar_case" in
        empty_single) description_line="description: ''" ;;
        empty_double) description_line='description: ""' ;;
        quoted_whitespace) description_line='description: "   "' ;;
        null_word) description_line='description: null' ;;
        null_tilde) description_line='description: ~' ;;
        boolean) description_line='description: true' ;;
        number) description_line='description: 42' ;;
        collection) description_line='description: [fixture]' ;;
        malformed_quote) description_line='description: "unterminated' ;;
        block_scalar) description_line='description: >' ;;
        sequence_entry) description_line='description: - item' ;;
        mapping_entry) description_line='description: ? item' ;;
        mapping_pair) description_line='description: foo: bar' ;;
        reserved_at) description_line='description: @item' ;;
        hex_number) description_line='description: 0x10' ;;
        binary_number) description_line='description: 0b10' ;;
        separator_number) description_line='description: 1_000' ;;
        comma_number) description_line='description: 1,000' ;;
        signed_comma_number) description_line='description: +1,000' ;;
        comma_decimal_number) description_line='description: 1,000.5' ;;
        leading_decimal) description_line='description: .5' ;;
        iso_date) description_line='description: 2026-08-15' ;;
        loose_iso_date) description_line='description: 2026-8-15' ;;
        iso_timestamp) description_line='description: 2026-08-15T09:30:00Z' ;;
    esac
    description_skill="$description_scalar_root/$description_scalar_case-validator-skill"
    description_err="$description_scalar_root/$description_scalar_case.err"
    p0p4_write_valid_skill_fixture "$description_skill"
    awk -v line="$description_line" 'NR == 3 { print line; next } { print }' "$description_skill/SKILL.md" >"$description_skill/skill.tmp"
    mv "$description_skill/skill.tmp" "$description_skill/SKILL.md"
    if "$skill_validator" --skill "$description_skill" >/dev/null 2>"$description_err" \
        || ! grep -Fq "FRONTMATTER_DESCRIPTION" "$description_err"; then
        description_scalar_failures+=("$description_scalar_case")
    fi
done
if [[ ${#description_scalar_failures[@]} -eq 0 ]]; then
    pass
else
    fail "validator accepted invalid description scalars: ${description_scalar_failures[*]}"
fi

test_start "skill validator accepts a representative plain description"
plain_description_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-validator-plain-description.XXXXXX")"
p0p4_register_cleanup "$plain_description_root"
p0p4_write_valid_skill_fixture "$plain_description_root/plain-description-validator-skill"
awk 'NR == 3 { print "description: Fixture validates ordinary plain-language routing."; next } { print }' "$plain_description_root/plain-description-validator-skill/SKILL.md" >"$plain_description_root/skill.tmp"
mv "$plain_description_root/skill.tmp" "$plain_description_root/plain-description-validator-skill/SKILL.md"
if "$skill_validator" --skill "$plain_description_root/plain-description-validator-skill" >/dev/null; then
    pass
else
    fail "validator rejected representative plain description"
fi

test_start "skill validator accepts single- and double-quoted descriptions containing hash and trailing comments"
quoted_description_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-validator-quoted-description.XXXXXX")"
p0p4_register_cleanup "$quoted_description_root"
quoted_description_failures=()
for quoted_description_case in double single; do
    quoted_description_skill="$quoted_description_root/$quoted_description_case-description-validator-skill"
    p0p4_write_valid_skill_fixture "$quoted_description_skill"
    case "$quoted_description_case" in
        double)
            quoted_description_line='description: "Fixture: routing # details." # routing note'
            ;;
        single)
            quoted_description_line="description: 'Fixture: routing # details.' # routing note"
            ;;
    esac
    awk -v line="$quoted_description_line" 'NR == 3 { print line; next } { print }' "$quoted_description_skill/SKILL.md" >"$quoted_description_skill/skill.tmp"
    mv "$quoted_description_skill/skill.tmp" "$quoted_description_skill/SKILL.md"
    if ! "$skill_validator" --skill "$quoted_description_skill" >/dev/null; then
        quoted_description_failures+=("$quoted_description_case")
    fi
done
if [[ ${#quoted_description_failures[@]} -eq 0 ]]; then
    pass
else
    fail "validator rejected quoted descriptions containing hash and trailing comments: ${quoted_description_failures[*]}"
fi

test_start "skill validator accepts quoted numeric and date-like descriptions"
quoted_scalar_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-validator-quoted-scalars.XXXXXX")"
p0p4_register_cleanup "$quoted_scalar_root"
quoted_scalar_failures=()
for quoted_scalar_case in '1,000' '+1,000' '1,000.5' '2026-8-15'; do
    quoted_scalar_slug="$(printf '%s' "$quoted_scalar_case" | tr -cd '[:alnum:]')"
    quoted_scalar_skill="$quoted_scalar_root/$quoted_scalar_slug-validator-skill"
    p0p4_write_valid_skill_fixture "$quoted_scalar_skill"
    awk -v value="$quoted_scalar_case" 'NR == 3 { print "description: \"" value "\""; next } { print }' "$quoted_scalar_skill/SKILL.md" >"$quoted_scalar_skill/skill.tmp"
    mv "$quoted_scalar_skill/skill.tmp" "$quoted_scalar_skill/SKILL.md"
    if ! "$skill_validator" --skill "$quoted_scalar_skill" >/dev/null; then
        quoted_scalar_failures+=("$quoted_scalar_case")
    fi
done
if [[ ${#quoted_scalar_failures[@]} -eq 0 ]]; then
    pass
else
    fail "validator rejected quoted numeric or date-like descriptions: ${quoted_scalar_failures[*]}"
fi

test_start "skill validator rejects top-level legacy effort metadata"
legacy_effort_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-validator-legacy-effort.XXXXXX")"
legacy_effort_err="$(mktemp "${TMPDIR:-/tmp}/skill-validator-legacy-effort-err.XXXXXX")"
p0p4_register_cleanup "$legacy_effort_root" "$legacy_effort_err"
p0p4_write_valid_skill_fixture "$legacy_effort_root/legacy-effort-skill"
awk 'NR == 3 { print "effort: low" } { print }' "$legacy_effort_root/legacy-effort-skill/SKILL.md" >"$legacy_effort_root/skill.tmp"
mv "$legacy_effort_root/skill.tmp" "$legacy_effort_root/legacy-effort-skill/SKILL.md"
if "$skill_validator" --skill "$legacy_effort_root/legacy-effort-skill" >/dev/null 2>"$legacy_effort_err"; then
    fail "validator accepted top-level legacy effort metadata"
elif grep -Fq "FRONTMATTER_LEGACY_EFFORT" "$legacy_effort_err"; then
    pass
else
    fail "legacy effort rejection did not include FRONTMATTER_LEGACY_EFFORT, stderr=$(cat "$legacy_effort_err")"
fi

test_start "skill validator rejects top-level legacy triggers metadata"
legacy_triggers_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-validator-legacy-triggers.XXXXXX")"
legacy_triggers_err="$(mktemp "${TMPDIR:-/tmp}/skill-validator-legacy-triggers-err.XXXXXX")"
p0p4_register_cleanup "$legacy_triggers_root" "$legacy_triggers_err"
p0p4_write_valid_skill_fixture "$legacy_triggers_root/legacy-triggers-skill"
awk 'NR == 3 { print "triggers:"; print "  - pattern: \\\"fixture skill\\\"" } { print }' "$legacy_triggers_root/legacy-triggers-skill/SKILL.md" >"$legacy_triggers_root/skill.tmp"
mv "$legacy_triggers_root/skill.tmp" "$legacy_triggers_root/legacy-triggers-skill/SKILL.md"
if "$skill_validator" --skill "$legacy_triggers_root/legacy-triggers-skill" >/dev/null 2>"$legacy_triggers_err"; then
    fail "validator accepted top-level legacy triggers metadata"
elif grep -Fq "FRONTMATTER_LEGACY_TRIGGERS" "$legacy_triggers_err"; then
    pass
else
    fail "legacy triggers rejection did not include FRONTMATTER_LEGACY_TRIGGERS, stderr=$(cat "$legacy_triggers_err")"
fi

test_start "skill validator rejects spaced and quoted top-level legacy keys"
legacy_key_forms_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-validator-legacy-key-forms.XXXXXX")"
p0p4_register_cleanup "$legacy_key_forms_root"
legacy_key_form_failures=()
for legacy_key_form in \
    'effort : low::FRONTMATTER_LEGACY_EFFORT' \
    '"effort": low::FRONTMATTER_LEGACY_EFFORT' \
    "'effort' : low::FRONTMATTER_LEGACY_EFFORT" \
    'triggers : []::FRONTMATTER_LEGACY_TRIGGERS' \
    '"triggers": []::FRONTMATTER_LEGACY_TRIGGERS' \
    "'triggers' : []::FRONTMATTER_LEGACY_TRIGGERS"; do
    legacy_line="${legacy_key_form%%::*}"
    expected_error="${legacy_key_form##*::}"
    legacy_slug="$(printf '%s' "$legacy_line" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')"
    legacy_skill="$legacy_key_forms_root/$legacy_slug"
    legacy_err="$legacy_key_forms_root/$legacy_slug.err"
    p0p4_write_valid_skill_fixture "$legacy_skill"
    awk -v line="$legacy_line" 'NR == 3 { print line } { print }' "$legacy_skill/SKILL.md" >"$legacy_skill/skill.tmp"
    mv "$legacy_skill/skill.tmp" "$legacy_skill/SKILL.md"
    if "$skill_validator" --skill "$legacy_skill" >/dev/null 2>"$legacy_err" \
        || ! grep -Fq "$expected_error" "$legacy_err"; then
        legacy_key_form_failures+=("$legacy_line")
    fi
done
if [[ ${#legacy_key_form_failures[@]} -eq 0 ]]; then
    pass
else
    fail "validator did not reject legacy key forms: ${legacy_key_form_failures[*]}"
fi

test_start "skill validator allows canonical block-sequence top-level requires metadata"
requires_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-validator-requires.XXXXXX")"
p0p4_register_cleanup "$requires_root"
p0p4_write_valid_skill_fixture "$requires_root/requires-validator-skill"
awk 'NR == 3 { print "requires:"; print "  - assistant-review"; print "  - assistant-tdd" } { print }' "$requires_root/requires-validator-skill/SKILL.md" >"$requires_root/skill.tmp"
mv "$requires_root/skill.tmp" "$requires_root/requires-validator-skill/SKILL.md"
if "$skill_validator" --skill "$requires_root/requires-validator-skill" >/dev/null; then
    pass
else
    fail "validator rejected canonical block-sequence requires metadata"
fi

test_start "skill validator rejects repeated top-level requires blocks"
repeated_requires_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-validator-repeated-requires.XXXXXX")"
p0p4_register_cleanup "$repeated_requires_root"
repeated_requires_failures=()
for repeated_requires_case in same_dependency different_dependency; do
    repeated_requires_skill="$repeated_requires_root/${repeated_requires_case//_/-}-validator-skill"
    repeated_requires_err="$repeated_requires_root/$repeated_requires_case.err"
    p0p4_write_valid_skill_fixture "$repeated_requires_skill"
    case "$repeated_requires_case" in
        same_dependency)
            awk 'NR == 3 { print "requires:"; print "  - assistant-review"; print "requires:"; print "  - assistant-review" } { print }' "$repeated_requires_skill/SKILL.md" >"$repeated_requires_skill/skill.tmp"
            ;;
        different_dependency)
            awk 'NR == 3 { print "requires:"; print "  - assistant-review"; print "requires:"; print "  - assistant-tdd" } { print }' "$repeated_requires_skill/SKILL.md" >"$repeated_requires_skill/skill.tmp"
            ;;
    esac
    mv "$repeated_requires_skill/skill.tmp" "$repeated_requires_skill/SKILL.md"
    if "$skill_validator" --skill "$repeated_requires_skill" >/dev/null 2>"$repeated_requires_err" \
        || ! grep -Fq "FRONTMATTER_REQUIRES_DUPLICATE" "$repeated_requires_err"; then
        repeated_requires_failures+=("$repeated_requires_case")
    fi
done
if [[ ${#repeated_requires_failures[@]} -eq 0 ]]; then
    pass
else
    fail "validator did not reject repeated requires blocks: ${repeated_requires_failures[*]}"
fi

test_start "skill validator rejects inline and empty top-level requires metadata"
invalid_requires_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-validator-invalid-requires.XXXXXX")"
p0p4_register_cleanup "$invalid_requires_root"
invalid_requires_failures=()
for invalid_requires_line in \
    'requires: [assistant-review, assistant-tdd]' \
    'requires: []' \
    'requires:'; do
    invalid_requires_slug="$(printf '%s' "$invalid_requires_line" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')"
    invalid_requires_skill="$invalid_requires_root/$invalid_requires_slug"
    invalid_requires_err="$invalid_requires_root/$invalid_requires_slug.err"
    p0p4_write_valid_skill_fixture "$invalid_requires_skill"
    awk -v line="$invalid_requires_line" 'NR == 3 { print line } { print }' "$invalid_requires_skill/SKILL.md" >"$invalid_requires_skill/skill.tmp"
    mv "$invalid_requires_skill/skill.tmp" "$invalid_requires_skill/SKILL.md"
    if "$skill_validator" --skill "$invalid_requires_skill" >/dev/null 2>"$invalid_requires_err" \
        || ! grep -Fq "FRONTMATTER_REQUIRES_FORMAT" "$invalid_requires_err"; then
        invalid_requires_failures+=("$invalid_requires_line")
    fi
done
if [[ ${#invalid_requires_failures[@]} -eq 0 ]]; then
    pass
else
    fail "validator did not reject unsupported requires forms: ${invalid_requires_failures[*]}"
fi

test_start "skill validator rejects noncanonical requires items and interrupted block sequences"
requires_semantics_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-validator-requires-semantics.XXXXXX")"
p0p4_register_cleanup "$requires_semantics_root"
requires_semantics_failures=()
for requires_case in quoted_item self_dependency duplicate_dependency interrupted_sequence; do
    requires_case_slug="${requires_case//_/-}"
    requires_skill="$requires_semantics_root/$requires_case_slug-validator-skill"
    requires_err="$requires_semantics_root/$requires_case.err"
    p0p4_write_valid_skill_fixture "$requires_skill"
    case "$requires_case" in
        quoted_item)
            expected_error="FRONTMATTER_REQUIRES_ITEM"
            awk 'NR == 3 { print "requires:"; print "  - \"assistant-review\"" } { print }' "$requires_skill/SKILL.md" >"$requires_skill/skill.tmp"
            ;;
        self_dependency)
            expected_error="FRONTMATTER_REQUIRES_SELF"
            awk -v skill_name="$(basename "$requires_skill")" 'NR == 3 { print "requires:"; print "  - " skill_name } { print }' "$requires_skill/SKILL.md" >"$requires_skill/skill.tmp"
            ;;
        duplicate_dependency)
            expected_error="FRONTMATTER_REQUIRES_DUPLICATE"
            awk 'NR == 3 { print "requires:"; print "  - assistant-review"; print "  - assistant-review" } { print }' "$requires_skill/SKILL.md" >"$requires_skill/skill.tmp"
            ;;
        interrupted_sequence)
            expected_error="FRONTMATTER_REQUIRES_FORMAT"
            awk 'NR == 3 { print "requires:"; print "  - assistant-review"; print ""; print "  - assistant-tdd" } { print }' "$requires_skill/SKILL.md" >"$requires_skill/skill.tmp"
            ;;
    esac
    mv "$requires_skill/skill.tmp" "$requires_skill/SKILL.md"
    if "$skill_validator" --skill "$requires_skill" >/dev/null 2>"$requires_err" \
        || ! grep -Fq "$expected_error" "$requires_err"; then
        requires_semantics_failures+=("$requires_case")
    fi
done
if [[ ${#requires_semantics_failures[@]} -eq 0 ]]; then
    pass
else
    fail "validator did not reject invalid requires semantics: ${requires_semantics_failures[*]}"
fi

test_start "skill validator allows nested semantic effort and trigger keys"
nested_metadata_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-validator-nested-metadata.XXXXXX")"
p0p4_register_cleanup "$nested_metadata_root"
p0p4_write_valid_skill_fixture "$nested_metadata_root/nested-metadata-skill"
awk 'NR == 3 { print "execution:"; print "  effort: bounded"; print "  triggers:"; print "    - validation failure" } { print }' "$nested_metadata_root/nested-metadata-skill/SKILL.md" >"$nested_metadata_root/skill.tmp"
mv "$nested_metadata_root/skill.tmp" "$nested_metadata_root/nested-metadata-skill/SKILL.md"
if "$skill_validator" --skill "$nested_metadata_root/nested-metadata-skill" >/dev/null; then
    pass
else
    fail "validator rejected nested semantic effort or trigger keys"
fi

test_start "skill validator supports a valid contracts index"
indexed_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-validator-indexed.XXXXXX")"
p0p4_register_cleanup "$indexed_root"
p0p4_write_valid_skill_fixture "$indexed_root/indexed-validator-skill"
cat >"$indexed_root/indexed-validator-skill/contracts/index.yaml" <<'EOF'
schema_version: "1.0"
contract: index
skill: indexed-validator-skill

authoritative_contracts:
  - path: contracts/input.yaml
    contract: input
  - path: contracts/output.yaml
    contract: output

load_sets:
  entry:
    selectors:
      - id: fixture-entry-fields
        path: contracts/input.yaml
        section: fields
        key: name
        names: [request]
    budget_words: 500
  completion:
    selectors:
      - id: fixture-completion-artifacts
        path: contracts/output.yaml
        section: artifacts
        key: name
        names: [result]
    budget_words: 500

fallback:
  on_missing_selector: load_full_authoritative_file
  on_invalid_selector: load_full_authoritative_file
EOF
if "$skill_validator" --skill "$indexed_root/indexed-validator-skill" >/dev/null; then
    pass
else
    fail "validator rejected a valid contracts/index.yaml"
fi

test_start "skill validator reports CONTRACT_INDEX diagnostics for malformed indexes"
malformed_index_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-validator-malformed-index.XXXXXX")"
malformed_index_err="$(mktemp "${TMPDIR:-/tmp}/skill-validator-malformed-index-err.XXXXXX")"
p0p4_register_cleanup "$malformed_index_root" "$malformed_index_err"
p0p4_write_valid_skill_fixture "$malformed_index_root/malformed-index-skill"
cat >"$malformed_index_root/malformed-index-skill/contracts/index.yaml" <<'EOF'
schema_version: "1.0"
contract: malformed
skill: malformed-index-skill

authoritative_contracts:
  - path: contracts/input.yaml
    contract: input
  - path: contracts/output.yaml
    contract: output

load_sets:
  entry:
    selectors: []
    budget_words: 0

fallback:
  on_missing_selector: ignore
EOF
if "$skill_validator" --skill "$malformed_index_root/malformed-index-skill" >/dev/null 2>"$malformed_index_err"; then
    fail "validator accepted a malformed contracts index"
elif grep -Fq "CONTRACT_INDEX_" "$malformed_index_err"; then
    pass
else
    fail "malformed index failure did not include CONTRACT_INDEX diagnostics, stderr=$(cat "$malformed_index_err")"
fi

test_start "skill validator rejects missing contract headers"
missing_header_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-validator-missing-header.XXXXXX")"
missing_header_err="$(mktemp "${TMPDIR:-/tmp}/skill-validator-missing-header-err.XXXXXX")"
p0p4_register_cleanup "$missing_header_root" "$missing_header_err"
p0p4_write_valid_skill_fixture "$missing_header_root/missing-header-skill"
awk 'NR != 2 && NR != 3 { print }' "$missing_header_root/missing-header-skill/contracts/input.yaml" >"$missing_header_root/input.tmp"
mv "$missing_header_root/input.tmp" "$missing_header_root/missing-header-skill/contracts/input.yaml"
if "$skill_validator" --skill "$missing_header_root/missing-header-skill" >/dev/null 2>"$missing_header_err"; then
    fail "validator accepted missing contract header"
elif grep -Fq "CONTRACT_HEADER" "$missing_header_err"; then
    pass
else
    fail "missing contract header failure did not include CONTRACT_HEADER, stderr=$(cat "$missing_header_err")"
fi

test_start "skill validator rejects required input fields without on_missing"
missing_on_missing_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-validator-missing-on-missing.XXXXXX")"
missing_on_missing_err="$(mktemp "${TMPDIR:-/tmp}/skill-validator-missing-on-missing-err.XXXXXX")"
p0p4_register_cleanup "$missing_on_missing_root" "$missing_on_missing_err"
p0p4_write_valid_skill_fixture "$missing_on_missing_root/missing-on-missing-skill"
grep -v 'on_missing:' "$missing_on_missing_root/missing-on-missing-skill/contracts/input.yaml" >"$missing_on_missing_root/input.tmp"
mv "$missing_on_missing_root/input.tmp" "$missing_on_missing_root/missing-on-missing-skill/contracts/input.yaml"
if "$skill_validator" --skill "$missing_on_missing_root/missing-on-missing-skill" >/dev/null 2>"$missing_on_missing_err"; then
    fail "validator accepted required input without on_missing"
elif grep -Fq "INPUT_REQUIRED_ON_MISSING" "$missing_on_missing_err"; then
    pass
else
    fail "missing on_missing failure did not include INPUT_REQUIRED_ON_MISSING, stderr=$(cat "$missing_on_missing_err")"
fi

test_start "skill validator rejects enum fields without enum_values"
missing_enum_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-validator-missing-enum.XXXXXX")"
missing_enum_err="$(mktemp "${TMPDIR:-/tmp}/skill-validator-missing-enum-err.XXXXXX")"
p0p4_register_cleanup "$missing_enum_root" "$missing_enum_err"
p0p4_write_valid_skill_fixture "$missing_enum_root/missing-enum-skill"
cat >"$missing_enum_root/missing-enum-skill/contracts/input.yaml" <<'EOF'
schema_version: "1.0"
contract: input
skill: missing-enum-skill

fields:
  - name: mode
    type: enum
    required: true
    description: "Fixture mode"
    validation: "Must be a supported mode"
    on_missing: ask
EOF
if "$skill_validator" --skill "$missing_enum_root/missing-enum-skill" >/dev/null 2>"$missing_enum_err"; then
    fail "validator accepted enum field without enum_values"
elif grep -Fq "ENUM_VALUES" "$missing_enum_err"; then
    pass
else
    fail "missing enum_values failure did not include ENUM_VALUES, stderr=$(cat "$missing_enum_err")"
fi

test_start "skill validator rejects analysis skills missing phase gates contract"
missing_phase_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-validator-missing-phase.XXXXXX")"
missing_phase_err="$(mktemp "${TMPDIR:-/tmp}/skill-validator-missing-phase-err.XXXXXX")"
p0p4_register_cleanup "$missing_phase_root" "$missing_phase_err"
p0p4_write_valid_skill_fixture "$missing_phase_root/missing-phase-skill"
cat >>"$missing_phase_root/missing-phase-skill/SKILL.md" <<'EOF'
| `contracts/phase-gates.yaml` | fixture phase gates |
EOF
if "$skill_validator" --skill "$missing_phase_root/missing-phase-skill" >/dev/null 2>"$missing_phase_err"; then
    fail "validator accepted analysis skill missing phase-gates contract"
elif grep -Fq "CONTRACT_MISSING" "$missing_phase_err" \
    && grep -Fq "phase-gates.yaml" "$missing_phase_err"; then
    pass
else
    fail "missing phase-gates failure did not include CONTRACT_MISSING, stderr=$(cat "$missing_phase_err")"
fi

test_start "skill validator rejects process skills missing handoffs contract"
missing_handoffs_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-validator-missing-handoffs.XXXXXX")"
missing_handoffs_err="$(mktemp "${TMPDIR:-/tmp}/skill-validator-missing-handoffs-err.XXXXXX")"
p0p4_register_cleanup "$missing_handoffs_root" "$missing_handoffs_err"
p0p4_write_valid_skill_fixture "$missing_handoffs_root/missing-handoffs-skill"
cat >>"$missing_handoffs_root/missing-handoffs-skill/SKILL.md" <<'EOF'
| `contracts/phase-gates.yaml` | fixture phase gates |
| `contracts/handoffs.yaml` | fixture handoffs |
EOF
cat >"$missing_handoffs_root/missing-handoffs-skill/contracts/phase-gates.yaml" <<'EOF'
schema_version: "1.0"
contract: phase-gates
skill: missing-handoffs-skill

gates:
  - phase: FIXTURE
    checkpoint_start: "--- PHASE: FIXTURE ---"
    checkpoint_end: "--- PHASE: FIXTURE COMPLETE ---"
    exit_assertions:
      - id: F1
        check: "Fixture phase completed"
        on_fail: "Complete the fixture phase"
EOF
if "$skill_validator" --skill "$missing_handoffs_root/missing-handoffs-skill" >/dev/null 2>"$missing_handoffs_err"; then
    fail "validator accepted process skill missing handoffs contract"
elif grep -Fq "CONTRACT_MISSING" "$missing_handoffs_err" \
    && grep -Fq "handoffs.yaml" "$missing_handoffs_err"; then
    pass
else
    fail "missing handoffs failure did not include CONTRACT_MISSING, stderr=$(cat "$missing_handoffs_err")"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
