#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

skill_validator="$FRAMEWORK_DIR/tools/skills/validate-skills.sh"

write_index_validator_fixture() {
    local skill_dir="$1"
    local skill_name

    skill_name="$(basename "$skill_dir")"
    mkdir -p "$skill_dir/contracts"
    cat > "$skill_dir/SKILL.md" <<EOF
---
name: $skill_name
description: "Indexed validator review regression fixture."
---

# Indexed Validator Fixture

| \`contracts/input.yaml\` | fixture input |
| \`contracts/output.yaml\` | fixture output |
EOF
    cat > "$skill_dir/contracts/input.yaml" <<EOF
schema_version: "1.0"
contract: input
skill: $skill_name

fields:
  - name: request
    type: string
    required: true
    description: "Entry request selected by fixture"
    validation: "Non-empty request"
    on_missing: ask
EOF
    cat > "$skill_dir/contracts/output.yaml" <<EOF
schema_version: "1.0"
contract: output
skill: $skill_name

artifacts:
  - name: result
    type: string
    required: true
    description: "Fixture result"
    validation: "Non-empty result"
    on_fail: "Re-run the fixture and provide the result"
EOF
}

write_index_file() {
    local skill_dir="$1"
    local authoritative_type="$2"
    local section="$3"
    local key="$4"
    local names="$5"
    local prose_match="${6:-}"
    local skill_name
    local match_line=""

    skill_name="$(basename "$skill_dir")"
    if [[ -n "$prose_match" ]]; then
        match_line="        match: \"$prose_match\""
    fi
    cat > "$skill_dir/contracts/index.yaml" <<EOF
schema_version: "1.0"
contract: index
skill: $skill_name

authoritative_contracts:
  - path: contracts/input.yaml
    contract: $authoritative_type
  - path: contracts/output.yaml
    contract: output

load_sets:
  entry:
    selectors:
      - id: fixture-entry-fields
        path: contracts/input.yaml
        section: $section
        key: $key
        names: [$names]
$match_line

fallback:
  on_missing_selector: load_full_authoritative_file
  on_invalid_selector: load_full_authoritative_file
EOF
}

test_start "contract-index validator rejects wrong type, section, key, name, duplicate, and prose cases"
INDEX_VALIDATOR_ROOT="$(mktemp -d)"
p0p4_register_cleanup "$INDEX_VALIDATOR_ROOT"
index_validation_failures=()

wrong_type_dir="$INDEX_VALIDATOR_ROOT/wrong-authoritative-type"
write_index_validator_fixture "$wrong_type_dir"
write_index_file "$wrong_type_dir" output fields name request
wrong_type_err="$INDEX_VALIDATOR_ROOT/wrong-type.err"
if "$skill_validator" --skill "$wrong_type_dir" >/dev/null 2>"$wrong_type_err" \
    || ! grep -Fq 'CONTRACT_INDEX_AUTHORITATIVE_CONTRACT' "$wrong_type_err"; then
    index_validation_failures+=("wrong authoritative contract type was not rejected with CONTRACT_INDEX_AUTHORITATIVE_CONTRACT")
fi

section_dir="$INDEX_VALIDATOR_ROOT/unresolved-section"
write_index_validator_fixture "$section_dir"
write_index_file "$section_dir" input absent_fields name request
section_err="$INDEX_VALIDATOR_ROOT/section.err"
if "$skill_validator" --skill "$section_dir" >/dev/null 2>"$section_err" \
    || ! grep -Fq 'CONTRACT_INDEX_SELECTOR_SECTION_UNRESOLVED' "$section_err"; then
    index_validation_failures+=("unresolved section was not rejected with CONTRACT_INDEX_SELECTOR_SECTION_UNRESOLVED")
fi

key_dir="$INDEX_VALIDATOR_ROOT/unresolved-key"
write_index_validator_fixture "$key_dir"
write_index_file "$key_dir" input fields absent_key request
key_err="$INDEX_VALIDATOR_ROOT/key.err"
if "$skill_validator" --skill "$key_dir" >/dev/null 2>"$key_err" \
    || ! grep -Fq 'CONTRACT_INDEX_SELECTOR_KEY_UNRESOLVED' "$key_err"; then
    index_validation_failures+=("unresolved key was not rejected with CONTRACT_INDEX_SELECTOR_KEY_UNRESOLVED")
fi

name_dir="$INDEX_VALIDATOR_ROOT/unresolved-name"
write_index_validator_fixture "$name_dir"
write_index_file "$name_dir" input fields name missing_request
name_err="$INDEX_VALIDATOR_ROOT/name.err"
if "$skill_validator" --skill "$name_dir" >/dev/null 2>"$name_err" \
    || ! grep -Fq 'CONTRACT_INDEX_SELECTOR_NAME_UNRESOLVED' "$name_err"; then
    index_validation_failures+=("unresolved name was not rejected with CONTRACT_INDEX_SELECTOR_NAME_UNRESOLVED")
fi

duplicate_dir="$INDEX_VALIDATOR_ROOT/duplicate-name"
write_index_validator_fixture "$duplicate_dir"
write_index_file "$duplicate_dir" input fields name 'request, request'
duplicate_err="$INDEX_VALIDATOR_ROOT/duplicate.err"
if "$skill_validator" --skill "$duplicate_dir" >/dev/null 2>"$duplicate_err" \
    || ! grep -Fq 'CONTRACT_INDEX_SELECTOR_NAME_DUPLICATE' "$duplicate_err"; then
    index_validation_failures+=("duplicate selected name was not rejected with CONTRACT_INDEX_SELECTOR_NAME_DUPLICATE")
fi

prose_dir="$INDEX_VALIDATOR_ROOT/prose-match"
write_index_validator_fixture "$prose_dir"
write_index_file "$prose_dir" input fields name request 'Fields applicable at entry'
prose_err="$INDEX_VALIDATOR_ROOT/prose.err"
if "$skill_validator" --skill "$prose_dir" >/dev/null 2>"$prose_err" \
    || ! grep -Fq 'CONTRACT_INDEX_SELECTOR_PROSE_MATCH' "$prose_err"; then
    index_validation_failures+=("prose match selector was not rejected with CONTRACT_INDEX_SELECTOR_PROSE_MATCH")
fi

if [[ "${#index_validation_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${index_validation_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
