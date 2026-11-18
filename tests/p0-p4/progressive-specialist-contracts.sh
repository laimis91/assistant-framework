if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

skill_validator="$FRAMEWORK_DIR/tools/skills/validate-skills.sh"
specialists=(assistant-ci-audit assistant-debugging assistant-tdd assistant-research assistant-skill-creator assistant-verification)

index_has_load_set() {
    local index_file="$1"
    local load_set="$2"
    awk -v load_set="$load_set" '
        $0 == "  " load_set ":" { in_set = 1; next }
        in_set && /^  [[:alnum:]_-]+:[[:space:]]*$/ { exit }
        in_set && /^    (selectors|references):/ { bounded = 1 }
        END { exit bounded ? 0 : 1 }
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

test_start "specialists retain valid consumer-driven progressive contract indexes"
index_failures=()
if ! grep -Fq '`contracts/index.yaml` is optional.' "$FRAMEWORK_DIR/docs/skill-contract-design-guide.md"; then
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
            index_failures+=("$skill_name $load_set load set is missing selectors/references")
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

test_start "ordinary research excludes five-lens process bookkeeping while five-lens retains it"
research_loading_failures=()
research_index="$FRAMEWORK_DIR/skills/assistant-research/contracts/index.yaml"
source_research_references="$(awk '
    $0 == "  source_research:" { in_set = 1; next }
    in_set && /^  [[:alnum:]_-]+:[[:space:]]*$/ { exit }
    in_set && /^    references:/ { in_references = 1; next }
    in_references && /^    selectors:/ { exit }
    in_references && /^      - / { sub(/^      - /, ""); print }
' "$research_index")"
five_lens_references="$(awk '
    $0 == "  five_lens:" { in_set = 1; next }
    in_set && /^  [[:alnum:]_-]+:[[:space:]]*$/ { exit }
    in_set && /^    references:/ { in_references = 1; next }
    in_references && /^    selectors:/ { exit }
    in_references && /^      - / { sub(/^      - /, ""); print }
' "$research_index")"

if [[ "$source_research_references" != $'research.md\nurl-verify.md' ]]; then
    research_loading_failures+=("source_research references must resolve only research.md and url-verify.md")
fi
if ! printf '%s\n' "$five_lens_references" | grep -Fxq "five-lens-briefing.md"; then
    research_loading_failures+=("five_lens does not resolve five-lens-briefing.md")
fi
if [[ "${#research_loading_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "research method loading leaked or lost five-lens obligations: ${research_loading_failures[*]}"
fi

test_start "lifecycle detail remains a separate conditional specialist load set"
if ruby -ryaml -e '
  valid = %w[assistant-debugging assistant-verification].all? do |skill|
    root = File.join(ARGV.fetch(0), "skills", skill)
    index = YAML.load_file(File.join(root, "contracts/index.yaml"))
    sets = index.fetch("load_sets")
    local = "references/lifecycle-verification.md"
    conditional = sets.fetch("lifecycle").fetch("references") == [local]
    ordinary = sets.reject { |name, _| name == "lifecycle" }.values.all? { |set| !set.fetch("references", []).include?(local) }
    text = File.read(File.join(root, "SKILL.md"))
    conditional && ordinary && text.include?(local) && text.match?(/Synchronous|synchronous/)
  end
  exit valid ? 0 : 1
' "$FRAMEWORK_DIR"; then pass; else fail "lifecycle detail leaks into ordinary specialist context or lacks its local conditional path"; fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
