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
effort: low
triggers:
  - pattern: "fixture skill"
    priority: 50
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
