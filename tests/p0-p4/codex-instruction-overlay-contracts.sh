#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

runner="$FRAMEWORK_DIR/tools/evals/run-codex-framework-evals.sh"
helper="$FRAMEWORK_DIR/tools/evals/lib/instruction-overlay.py"
finalizer="$FRAMEWORK_DIR/tools/evals/finalize-workflow-kernel-review.sh"
context_report="$FRAMEWORK_DIR/tools/context-budget-report.sh"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/instruction-overlay-contracts.XXXXXX")"
p0p4_register_cleanup "$fixture_root"

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
    else shasum -a 256 "$1" | awk '{print $1}'; fi
}

make_manifest() {
    local root="$1" base_hash="$2"
    jq -n --arg base "$base_hash" --arg skill "$(sha256_file "$root/SKILL.md")" \
      --arg reference "$(sha256_file "$root/references/phases.md")" \
      --arg contract "$(sha256_file "$root/contracts/index.yaml")" '
      {schema_version:"1.0",mode:"hashed_instruction_overlay",base_skill:"assistant-workflow",base_source_sha256:$base,
       files:[{path:"SKILL.md",sha256:$skill},{path:"contracts/index.yaml",sha256:$contract},{path:"references/phases.md",sha256:$reference}]}' \
      >"$root/overlay.json"
}

base_hash="$(python3 "$helper" source-hash --base-skill-tree "$FRAMEWORK_DIR/skills/assistant-workflow" | jq -r .base_source_sha256)"
overlay="$fixture_root/overlay"
legacy="$fixture_root/legacy"
mkdir -p "$overlay/references" "$overlay/contracts" "$legacy"
cp "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md" "$overlay/SKILL.md"
printf '\nExact root marker: {agent_state_dir}.\n' >>"$overlay/SKILL.md"
cp "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md" "$overlay/references/phases.md"
printf '\n<!-- exact reference marker: {agent_state_dir} -->\n' >>"$overlay/references/phases.md"
cp "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/index.yaml" "$overlay/contracts/index.yaml"
printf '\n# exact contract marker: {agent_state_dir}\n' >>"$overlay/contracts/index.yaml"
make_manifest "$overlay" "$base_hash"
cp "$overlay/SKILL.md" "$legacy/SKILL.md"
fake_codex="$fixture_root/fake-codex"
capture="$fixture_root/capture"
mkdir -p "$capture"
printf '%s\n' '#!/usr/bin/env bash' 'if [[ "${1:-}" == "--version" ]]; then echo "codex-cli 9.9.9-test"; fi' 'exit 0' >"$fake_codex"
chmod +x "$fake_codex"

test_start "context measurements keep an instruction boundary when a valid file lacks a final newline"
no_newline_tree="$fixture_root/no-newline-tree"
canonical_report="$fixture_root/canonical-context.json"
no_newline_report="$fixture_root/no-newline-context.json"
mkdir -p "$no_newline_tree"
while IFS= read -r entry; do cp -R "$entry" "$no_newline_tree/"; done < <(find "$FRAMEWORK_DIR/skills/assistant-workflow" -mindepth 1 -maxdepth 1 ! -name evals -print | LC_ALL=C sort)
python3 - "$no_newline_tree/SKILL.md" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_bytes(path.read_bytes().rstrip(b"\n"))
PY
if "$context_report" --agent codex --skill assistant-workflow --format json >"$canonical_report" \
    && "$context_report" --agent codex --skill assistant-workflow --skill-tree "$no_newline_tree" --format json >"$no_newline_report" \
    && jq -e --slurpfile canonical "$canonical_report" '
      .components.selected_skill_initial.words == $canonical[0].components.selected_skill_initial.words
      and .components.selected_skill_entry_boundary.words == $canonical[0].components.selected_skill_entry_boundary.words
    ' "$no_newline_report" >/dev/null; then
    pass
else
    fail "context measurement merged adjacent instruction files without a newline boundary"
fi

test_start "exact instruction overlays are materialized byte-faithfully with bounded provenance"
materialized="$fixture_root/materialized"
if python3 "$helper" materialize --manifest "$overlay/overlay.json" \
    --base-skill-tree "$FRAMEWORK_DIR/skills/assistant-workflow" --destination "$materialized" >"$fixture_root/metadata.json" \
    && cmp -s "$overlay/SKILL.md" "$materialized/SKILL.md" \
    && cmp -s "$overlay/references/phases.md" "$materialized/references/phases.md" \
    && cmp -s "$overlay/contracts/index.yaml" "$materialized/contracts/index.yaml" \
    && cmp -s "$FRAMEWORK_DIR/skills/assistant-workflow/references/build-worker-protocol.md" "$materialized/references/build-worker-protocol.md" \
    && jq -e --arg base "$base_hash" '
        . == {base_source_sha256:$base,mode:"hashed_instruction_overlay",overlay_file_count:3,source_manifest_sha256:(.source_manifest_sha256)}
        and (.source_manifest_sha256 | test("^[0-9a-f]{64}$"))
      ' "$fixture_root/metadata.json" >/dev/null; then
    pass
else
    fail "exact instruction overlay materialization changed bytes or leaked unbounded provenance"
fi

test_start "exact overlays allow bounded nested instruction additions"
nested="$fixture_root/nested"
nested_materialized="$fixture_root/nested-materialized"
cp -R "$overlay" "$nested"
mkdir -p "$nested/references/a"
printf 'Nested instruction addition.\n' >"$nested/references/a/b.md"
jq --arg hash "$(sha256_file "$nested/references/a/b.md")" '.files += [{path:"references/a/b.md",sha256:$hash}] | .files |= sort_by(.path)' \
    "$nested/overlay.json" >"$nested/next.json" && mv "$nested/next.json" "$nested/overlay.json"
if python3 "$helper" materialize --manifest "$nested/overlay.json" --base-skill-tree "$FRAMEWORK_DIR/skills/assistant-workflow" --destination "$nested_materialized" >"$fixture_root/nested-metadata.json" \
    && cmp -s "$nested/references/a/b.md" "$nested_materialized/references/a/b.md" \
    && jq -e '.overlay_file_count == 4' "$fixture_root/nested-metadata.json" >/dev/null; then
    pass
else
    fail "nested exact instruction addition was not materialized"
fi

test_start "root-only variants retain their mode while exact references affect tree evidence"
root_plan="$fixture_root/root-plan"
exact_plan="$fixture_root/exact-plan"
if "$runner" --baseline-variant "$legacy" --candidate-variant "$legacy" \
    --cases small-fix-stays-lightweight --repeats 1 --output "$root_plan" >/dev/null \
    && "$runner" --baseline-variant "$overlay/overlay.json" --candidate-variant "$overlay/overlay.json" \
        --cases small-fix-stays-lightweight --repeats 1 --output "$exact_plan" >/dev/null \
    && jq -e '.baseline_variant.materialization.mode == "root_skill_overlay" and .baseline_variant.materialization.source_manifest_sha256 == null and .candidate_variant.materialization.overlay_file_count == 1' "$root_plan/run-plan.json" >/dev/null \
    && jq -e --arg manifest_sha "$(sha256_file "$overlay/overlay.json")" --arg base_sha "$base_hash" --slurpfile root "$root_plan/run-plan.json" '
        .baseline_variant.materialization.mode == "hashed_instruction_overlay"
        and .candidate_variant.materialization.overlay_file_count == 3
        and .baseline_variant.materialization.source_manifest_sha256 == $manifest_sha
        and .candidate_variant.materialization.source_manifest_sha256 == $manifest_sha
        and .baseline_variant.materialization.base_source_sha256 == $base_sha
        and .candidate_variant.materialization.base_source_sha256 == $base_sha
        and (.context_budget_evidence.candidate.selected_initial_words > 0)
        and (.context_budget_evidence.candidate.selected_entry_words > 0)
        and .baseline_variant.instruction_sha256 == .candidate_variant.instruction_sha256
        and .baseline_variant.instruction_sha256 != $root[0].baseline_variant.instruction_sha256
      ' "$exact_plan/run-plan.json" >/dev/null; then
    pass
else
    fail "root or exact run-plan materialization metadata is incomplete"
fi

test_start "exact adapter plans bind unmodified manifest bytes while legacy overlays render placeholders"
expected_tree_hash="$(python3 "$helper" source-hash --base-skill-tree "$materialized" | jq -r .base_source_sha256)"
sed 's|{agent_state_dir}|.codex|g' "$legacy/SKILL.md" >"$fixture_root/legacy-rendered.md"
if jq -e --arg tree "$expected_tree_hash" --arg skill "$(sha256_file "$overlay/SKILL.md")" '
      .baseline_variant.instruction_sha256 == $tree
      and .candidate_variant.instruction_sha256 == $tree
      and .candidate_variant.materialized_skill_sha256 == $skill
    ' "$exact_plan/run-plan.json" >/dev/null \
    && jq -e --arg skill "$(sha256_file "$fixture_root/legacy-rendered.md")" '
      .candidate_variant.materialized_skill_sha256 == $skill
    ' "$root_plan/run-plan.json" >/dev/null; then
    pass
else
    fail "adapter rewrote exact manifest bytes or stopped rendering legacy placeholders"
fi

test_start "legacy root overlays retain plan-only operation without Python or Ruby"
restricted_path="$fixture_root/restricted-path"
restricted_output="$fixture_root/restricted-output"
mkdir -p "$restricted_path"
for command_name in awk bash basename cat chmod cp cut date dirname env find git grep head id jq ln mkdir mktemp mv paste pwd readlink rm rmdir rsync sed shasum sha256sum sleep sort stat tail tee touch tr uname wc xargs; do
    command_path="$(command -v "$command_name" 2>/dev/null || true)"
    [[ -z "$command_path" || -e "$restricted_path/$command_name" ]] || ln -s "$command_path" "$restricted_path/$command_name"
done
if [[ ! -e "$restricted_path/python3" && ! -e "$restricted_path/ruby" ]] \
    && PATH="$restricted_path" "$runner" --baseline-variant "$legacy" --candidate-variant "$legacy" \
        --cases small-fix-stays-lightweight --repeats 1 --output "$restricted_output" >/dev/null \
    && [[ -f "$restricted_output/run-plan.json" ]]; then
    pass
else
    fail "legacy root plan unexpectedly required Python or Ruby"
fi

test_start "legacy root overlay copy failures stop before run-plan admission"
copy_failure_bin="$fixture_root/copy-failure-bin"
copy_failure_candidate="$fixture_root/copy-failure-candidate"
copy_failure_success_output="$fixture_root/copy-failure-success-output"
copy_failure_output="$fixture_root/copy-failure-output"
mkdir -p "$copy_failure_bin" "$copy_failure_candidate"
cp "$legacy/SKILL.md" "$copy_failure_candidate/SKILL.md"
copy_failure_source="$(cd "$(dirname "$copy_failure_candidate/SKILL.md")" && pwd)/SKILL.md"
cat >"$copy_failure_bin/cp" <<'EOF'
#!/usr/bin/env bash

if [[ "${OVERLAY_COPY_FAILURE_SOURCE:-}" == "${1:-}" && "${2:-}" == */SKILL.md ]]; then
    exit 73
fi
exec "${OVERLAY_REAL_CP:?}" "$@"
EOF
chmod +x "$copy_failure_bin/cp"
if OVERLAY_REAL_CP="$(command -v cp)" PATH="$copy_failure_bin:$PATH" \
    "$runner" --baseline-variant "$legacy" --candidate-variant "$legacy" \
        --cases small-fix-stays-lightweight --repeats 1 --output "$copy_failure_success_output" >/dev/null \
    && ! OVERLAY_REAL_CP="$(command -v cp)" OVERLAY_COPY_FAILURE_SOURCE="$copy_failure_source" PATH="$copy_failure_bin:$PATH" \
        "$runner" --baseline-variant "$legacy" --candidate-variant "$copy_failure_candidate" \
            --cases small-fix-stays-lightweight --repeats 1 --output "$copy_failure_output" >/dev/null 2>&1 \
    && [[ -f "$copy_failure_success_output/run-plan.json" && ! -e "$copy_failure_output/run-plan.json" ]]; then
    pass
else
    fail "legacy root copy failure did not stop before run-plan admission"
fi

test_start "exact overlays fail closed with their explicit Python and Ruby prerequisites"
python_only_path="$fixture_root/python-only-path"
missing_python_error="$fixture_root/missing-python.stderr"
missing_ruby_error="$fixture_root/missing-ruby.stderr"
mkdir -p "$python_only_path"
cp -R "$restricted_path/." "$python_only_path/"
python_path="$(command -v python3 2>/dev/null || true)"
[[ -n "$python_path" ]] && ln -s "$python_path" "$python_only_path/python3"
if ! PATH="$restricted_path" "$runner" --baseline-variant "$overlay/overlay.json" --candidate-variant "$overlay/overlay.json" --cases small-fix-stays-lightweight --repeats 1 --output "$fixture_root/missing-python-output" >/dev/null 2>"$missing_python_error" \
    && ! PATH="$python_only_path" "$runner" --baseline-variant "$overlay/overlay.json" --candidate-variant "$overlay/overlay.json" --cases small-fix-stays-lightweight --repeats 1 --output "$fixture_root/missing-ruby-output" >/dev/null 2>"$missing_ruby_error" \
    && grep -Fxq 'Error: python3 is required for hashed instruction overlay variants.' "$missing_python_error" \
    && grep -Fxq 'Error: ruby is required for hashed instruction overlay context measurement.' "$missing_ruby_error"; then
    pass
else
    fail "exact overlay prerequisites were not explicit or fail-closed"
fi

test_start "unsafe stale base-stale duplicate symlink unlisted files or directories and oversized overlays fail before plan admission"
rejections=()
for kind in unsafe stale base_stale duplicate symlink unlisted unlisted_directory oversized; do
    candidate="$fixture_root/$kind"
    cp -R "$overlay" "$candidate"
    case "$kind" in
        unsafe) jq '.files[1].path = "references/../escape.md"' "$candidate/overlay.json" >"$candidate/next.json" && mv "$candidate/next.json" "$candidate/overlay.json" ;;
        stale) printf '\nstale\n' >>"$candidate/SKILL.md" ;;
        base_stale) jq '.base_source_sha256 = ("f" * 64)' "$candidate/overlay.json" >"$candidate/next.json" && mv "$candidate/next.json" "$candidate/overlay.json" ;;
        duplicate) jq -c . "$candidate/overlay.json" | sed 's/"schema_version":"1.0"/"schema_version":"1.0","schema_version":"1.0"/' >"$candidate/next.json" && mv "$candidate/next.json" "$candidate/overlay.json" ;;
        symlink) ln -s "$candidate/SKILL.md" "$candidate/references/symlink.md" ;;
        unlisted) printf 'unlisted\n' >"$candidate/references/unlisted.md" ;;
        unlisted_directory) mkdir -p "$candidate/references/unlisted/empty" ;;
        oversized) dd if=/dev/zero of="$candidate/references/phases.md" bs=1024 count=1025 >/dev/null 2>&1 ;;
    esac
    output="$fixture_root/$kind-output"
    if "$runner" --baseline-variant "$candidate/overlay.json" --candidate-variant "$candidate/overlay.json" --cases small-fix-stays-lightweight --repeats 1 --output "$output" >/dev/null 2>&1 || [[ -e "$output/run-plan.json" ]]; then
        rejections+=("$kind")
    fi
done
if [[ ${#rejections[@]} -eq 0 ]]; then pass; else fail "unsafe input reached plan admission: ${rejections[*]}"; fi

test_start "changed exact overlay input rejects resume and cannot enter kernel promotion"
resume_plan="$fixture_root/exact-resume-plan"
if ! FRAMEWORK_EVAL_CONTRACT_TEST_MODE=true FRAMEWORK_EVAL_TEST_EXIT_AFTER_PLAN_PERSISTENCE=true FAKE_CODEX_CAPTURE_DIR="$capture" \
    "$runner" --execute --model test-model --codex-bin "$fake_codex" --baseline-variant "$overlay/overlay.json" --candidate-variant "$overlay/overlay.json" --cases small-fix-stays-lightweight --repeats 1 --output "$resume_plan" >/dev/null; then
    fail "could not prepare the isolated exact-overlay resume fixture"
fi
printf '\nresume drift\n' >>"$overlay/SKILL.md"
resume_error="$fixture_root/resume.stderr"
promotion_error="$fixture_root/promotion.stderr"
promotion_results="$fixture_root/promotion-results"
mkdir -p "$promotion_results"
cp "$exact_plan/run-plan.json" "$promotion_results/run-plan.json"
if ! FRAMEWORK_EVAL_CONTRACT_TEST_MODE=true FRAMEWORK_EVAL_TEST_EXIT_AFTER_PLAN_PERSISTENCE=true FAKE_CODEX_CAPTURE_DIR="$capture" \
    "$runner" --resume --execute --model test-model --codex-bin "$fake_codex" --baseline-variant "$overlay/overlay.json" --candidate-variant "$overlay/overlay.json" --cases small-fix-stays-lightweight --repeats 1 --output "$resume_plan" >/dev/null 2>"$resume_error" \
    && ! "$finalizer" --results "$promotion_results" --write-verdict-template "$fixture_root/template.json" >/dev/null 2>"$promotion_error" \
    && grep -Fq 'hash is stale' "$resume_error" \
    && grep -Fq 'Exact instruction overlays are ineligible' "$promotion_error"; then
    pass
else
    fail "resume or promotion did not reject an exact overlay"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
