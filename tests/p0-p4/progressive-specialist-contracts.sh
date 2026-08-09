if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

skill_validator="$FRAMEWORK_DIR/tools/skills/validate-skills.sh"
specialists=(assistant-debugging assistant-tdd assistant-research assistant-skill-creator)

index_has_load_set() {
    local index_file="$1"
    local load_set="$2"
    awk -v load_set="$load_set" '
        $0 == "  " load_set ":" { in_set = 1; next }
        in_set && /^  [[:alnum:]_-]+:[[:space:]]*$/ { exit }
        in_set && /^    (selectors|references):/ { bounded = 1 }
        in_set && /^    budget_words:[[:space:]]*[1-9][0-9]*[[:space:]]*$/ { budget = 1 }
        END { exit bounded && budget ? 0 : 1 }
    ' "$index_file"
}

phase_gate_invariant_ids() {
    local phase_gates_file="$1"
    awk '
        /^invariants:[[:space:]]*$/ { in_invariants = 1; next }
        in_invariants && /^[^[:space:]]/ { exit }
        in_invariants && /^[[:space:]]*-[[:space:]]+id:[[:space:]]*/ {
            invariant_id = $0
            sub(/^[[:space:]]*-[[:space:]]+id:[[:space:]]*/, "", invariant_id)
            sub(/[[:space:]]*#.*/, "", invariant_id)
            if (invariant_id != "") {
                print invariant_id
            }
        }
    ' "$phase_gates_file"
}

index_invariant_selector_ids() {
    local index_file="$1"
    awk '
        /^[[:space:]]+- id:/ { in_invariant_selector = 0 }
        /^[[:space:]]+section:[[:space:]]+invariants[[:space:]]*$/ {
            in_invariant_selector = 1
            next
        }
        in_invariant_selector && /^[[:space:]]+names:[[:space:]]*\[/ {
            names = $0
            sub(/^[^[]*\[/, "", names)
            sub(/\].*$/, "", names)
            count = split(names, values, ",")
            for (i = 1; i <= count; i++) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", values[i])
                if (values[i] != "") {
                    print values[i]
                }
            }
            exit
        }
    ' "$index_file"
}

index_covers_phase_gate_invariants() {
    local index_file="$1"
    local phase_gates_file="$2"
    local invariant_ids selected_ids invariant_id
    invariant_ids="$(phase_gate_invariant_ids "$phase_gates_file")"
    selected_ids="$(index_invariant_selector_ids "$index_file")"
    [[ -n "$invariant_ids" && -n "$selected_ids" ]] || return 1
    while IFS= read -r invariant_id; do
        if ! printf '%s\n' "$selected_ids" | grep -Fxq -- "$invariant_id"; then
            return 1
        fi
    done <<<"$invariant_ids"
}

validator_entry_closure_words() {
    local skill_name="$1"
    local fixture_root fixture_skill fixture_index validator_err
    fixture_root="$(mktemp -d)"
    p0p4_register_cleanup "$fixture_root"
    fixture_skill="$fixture_root/$skill_name"
    cp -R "$FRAMEWORK_DIR/skills/$skill_name" "$fixture_skill"
    fixture_index="$fixture_skill/contracts/index.yaml"
    validator_err="$fixture_root/validator.err"

    awk '
        $0 == "  entry:" { in_target = 1 }
        in_target && /^  [^[:space:]#][^:]*:[[:space:]]*$/ && $0 != "  entry:" { in_target = 0 }
        in_target && /^    budget_words:/ { print "    budget_words: 1"; next }
        { print }
    ' "$fixture_index" >"$fixture_index.tmp"
    mv "$fixture_index.tmp" "$fixture_index"
    "$skill_validator" --skill "$fixture_skill" >/dev/null 2>"$validator_err" || true
    sed -nE "s/.*load set 'entry' declared boundary closure is ([0-9]+) words.*/\\1/p" "$validator_err" | head -n 1
}

test_start "four heavy specialists define valid progressive contract indexes"
index_failures=()
if ! grep -Fq 'Non-trivial Process or Analysis skills MAY add `contracts/index.yaml`' "$FRAMEWORK_DIR/docs/skill-contract-design-guide.md"; then
    index_failures+=("contract guide does not allow progressive indexes for Analysis specialists")
fi
for skill_name in "${specialists[@]}"; do
    skill_dir="$FRAMEWORK_DIR/skills/$skill_name"
    index_file="$skill_dir/contracts/index.yaml"
    if [[ ! -f "$index_file" ]]; then
        index_failures+=("$skill_name missing contracts/index.yaml")
        continue
    fi
    if ! "$skill_validator" --skill "$skill_name" >/dev/null 2>&1; then
        index_failures+=("$skill_name index or contracts fail source validation")
    fi
    for load_set in entry current_phase completion; do
        if ! index_has_load_set "$index_file" "$load_set"; then
            index_failures+=("$skill_name $load_set load set is missing selectors/references or budget")
        fi
    done
    if ! grep -Fq 'section: invariants' "$index_file"; then
        index_failures+=("$skill_name current_phase does not load cross-phase invariants")
    fi
    for fallback in \
        "on_missing_selector: load_full_authoritative_file" \
        "on_invalid_selector: load_full_authoritative_file"; do
        if ! grep -Fq "$fallback" "$index_file"; then
            index_failures+=("$skill_name missing fallback $fallback")
        fi
    done
done
if [[ "${#index_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive specialist indexes failed: ${index_failures[*]}"
fi

test_start "specialist invariant selectors cover every canonical invariant"
invariant_failures=()
for skill_name in "${specialists[@]}"; do
    skill_dir="$FRAMEWORK_DIR/skills/$skill_name"
    if ! index_covers_phase_gate_invariants \
        "$skill_dir/contracts/index.yaml" \
        "$skill_dir/contracts/phase-gates.yaml"; then
        invariant_failures+=("$skill_name invariant selector is incomplete")
    fi
done
if [[ "${#invariant_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive invariant coverage failed: ${invariant_failures[*]}"
fi

test_start "invariant completeness rejects an omitted selected invariant"
invariant_fixture_root="$(mktemp -d)"
p0p4_register_cleanup "$invariant_fixture_root"
invariant_fixture_index="$invariant_fixture_root/index.yaml"
invariant_fixture_gates="$invariant_fixture_root/phase-gates.yaml"
cp "$FRAMEWORK_DIR/skills/assistant-debugging/contracts/index.yaml" "$invariant_fixture_index"
cp "$FRAMEWORK_DIR/skills/assistant-debugging/contracts/phase-gates.yaml" "$invariant_fixture_gates"
sed 's/, INV3//' "$invariant_fixture_index" >"$invariant_fixture_index.tmp"
mv "$invariant_fixture_index.tmp" "$invariant_fixture_index"
if grep -Fq 'INV3' "$invariant_fixture_index"; then
    fail "invariant fixture mutation did not remove INV3 from the selector"
elif index_covers_phase_gate_invariants "$invariant_fixture_index" "$invariant_fixture_gates"; then
    fail "invariant completeness accepted an index missing INV3"
else
    pass
fi

test_start "specialist roots route contract loading by enforcement boundary"
root_failures=()
for skill_name in "${specialists[@]}"; do
    skill_file="$FRAMEWORK_DIR/skills/$skill_name/SKILL.md"
    for term in \
        "contracts/index.yaml" \
        "load only" \
        "specialist gates are authoritative"; do
        if ! grep -Fqi "$term" "$skill_file"; then
            root_failures+=("$skill_name root missing $term")
        fi
    done
    if rg -qi 'read and follow the contract files in .contracts/. before|read (all |the )?contract files.*before executing|all contracts are mandatory' "$skill_file"; then
        root_failures+=("$skill_name still eagerly loads every contract")
    fi
done
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-debugging/SKILL.md::assistant-debugging owns diagnosis" \
    "$FRAMEWORK_DIR/skills/assistant-tdd/SKILL.md::assistant-tdd owns RED-GREEN-REFACTOR" \
    "$FRAMEWORK_DIR/skills/assistant-research/SKILL.md::assistant-research owns source selection" \
    "$FRAMEWORK_DIR/skills/assistant-skill-creator/SKILL.md::assistant-skill-creator owns skill contract design"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! grep -Fq "$term" "$file"; then
        root_failures+=("${file#$FRAMEWORK_DIR/} missing ownership boundary $term")
    fi
done
if ! grep -Fq 'Every URL presented is verified or omitted.' "$FRAMEWORK_DIR/skills/assistant-research/SKILL.md"; then
    root_failures+=("assistant-research root weakened the every-URL verification invariant")
fi
if [[ "${#root_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive specialist root guidance failed: ${root_failures[*]}"
fi

test_start "compacted specialist roots retain strict behavioral anchors"
anchor_failures=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-debugging/SKILL.md::at least three plausible causes" \
    "$FRAMEWORK_DIR/skills/assistant-debugging/SKILL.md::Stop before speculative edits" \
    "$FRAMEWORK_DIR/skills/assistant-debugging/SKILL.md::assistant-tdd" \
    "$FRAMEWORK_DIR/skills/assistant-tdd/SKILL.md::Do not write production code before RED evidence exists" \
    "$FRAMEWORK_DIR/skills/assistant-tdd/SKILL.md::selected production owner" \
    "$FRAMEWORK_DIR/skills/assistant-research/SKILL.md::Every URL presented is verified or omitted" \
    "$FRAMEWORK_DIR/skills/assistant-research/SKILL.md::candidate mechanisms with evidence" \
    "$FRAMEWORK_DIR/skills/assistant-research/SKILL.md::five_lens_briefing" \
    "$FRAMEWORK_DIR/skills/assistant-skill-creator/SKILL.md::user review before BUILD" \
    "$FRAMEWORK_DIR/skills/assistant-skill-creator/SKILL.md::verifier_result: approved" \
    "$FRAMEWORK_DIR/skills/assistant-skill-creator/SKILL.md::references/harness-patterns.md" \
    "$FRAMEWORK_DIR/skills/assistant-skill-creator/SKILL.md::14 contract design guide rules"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! grep -Fq -- "$term" "$file"; then
        anchor_failures+=("${file#$FRAMEWORK_DIR/} missing $term")
    fi
done
if [[ "${#anchor_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "specialist compaction weakened strict behavior: ${anchor_failures[*]}"
fi

test_start "specialist entry closures stay below 1500 words"
closure_failures=()
closure_summary=()
for skill_name in "${specialists[@]}"; do
    if [[ ! -f "$FRAMEWORK_DIR/skills/$skill_name/contracts/index.yaml" ]]; then
        closure_failures+=("$skill_name has no measurable entry closure")
        continue
    fi
    closure_words="$(validator_entry_closure_words "$skill_name")"
    closure_summary+=("$skill_name=$closure_words")
    if [[ ! "$closure_words" =~ ^[0-9]+$ ]]; then
        closure_failures+=("$skill_name validator did not report entry closure")
    elif (( closure_words >= 1500 )); then
        closure_failures+=("$skill_name entry closure is $closure_words words")
    fi
done
if [[ "${#closure_failures[@]}" -eq 0 ]]; then
    pass
else
    closure_summary_text="none"
    if [[ "${#closure_summary[@]}" -gt 0 ]]; then
        closure_summary_text="${closure_summary[*]}"
    fi
    fail "specialist entry budget failed ($closure_summary_text): ${closure_failures[*]}"
fi

test_start "research and skill-creator load heavyweight methods only on demand"
method_failures=()
research_index="$FRAMEWORK_DIR/skills/assistant-research/contracts/index.yaml"
creator_index="$FRAMEWORK_DIR/skills/assistant-skill-creator/contracts/index.yaml"
for file_and_term in \
    "$research_index::source_research:" \
    "$research_index::research.md" \
    "$research_index::five_lens:" \
    "$research_index::five-lens-briefing.md" \
    "$research_index::investigate:" \
    "$research_index::investigate.md" \
    "$research_index::url-verify.md" \
    "$creator_index::contract_design:" \
    "$creator_index::references/skill-contract-design-guide.md" \
    "$creator_index::harness_design:" \
    "$creator_index::references/harness-patterns.md" \
    "$creator_index::verified_distillation:" \
    "$creator_index::references/verified-skill-distillation.md" \
    "$creator_index::validation:" \
    "$creator_index::references/contract-design-checklist.md"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq "$term" "$file"; then
        method_failures+=("${file#$FRAMEWORK_DIR/} missing $term")
    fi
done
if [[ "${#method_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "on-demand specialist methods failed: ${method_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
