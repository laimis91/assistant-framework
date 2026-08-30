if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

validate_p0p4_ci_schedule() {
    local aggregate_script="$1"
    local workflow_file="$2"
    local suite_dir="$3"

    ruby -ryaml - "$aggregate_script" "$workflow_file" "$suite_dir" <<'RUBY'
aggregate_script, workflow_file, suite_dir = ARGV
aggregate = File.read(aggregate_script)
workflow = YAML.load_file(workflow_file)
errors = []

all_aggregate_sources = aggregate.scan(/^[ \t]*source "\$P0P4_SUITE_DIR\/([^\"\/]+\.sh)"$/).flatten
guarded_pairs = aggregate.scan(/^if ! p0p4_suite_is_excluded "([^\"\/]+\.sh)"; then\n[ \t]+source "\$P0P4_SUITE_DIR\/([^\"\/]+\.sh)"\nfi$/)
guarded_suites = guarded_pairs.map(&:last)
aggregate_suites = all_aggregate_sources.dup
guarded_suites.each do |suite|
  index = aggregate_suites.index(suite)
  index ? aggregate_suites.delete_at(index) : errors << "guarded suite lacks source: #{suite}"
end
guarded_pairs.each do |guard_suite, source_suite|
  errors << "suite exclusion guard/source mismatch: #{guard_suite} != #{source_suite}" unless guard_suite == source_suite
end
suite_names = Dir[File.join(suite_dir, "*.sh")].map { |path| File.basename(path) }.sort
compatibility_wrappers = %w[agent-status-contracts.sh workflow-contracts.sh]

jobs = workflow.fetch("jobs", {})
fast_job = jobs["framework-contracts"]
shard_job = jobs["contract-shards"]
errors << "missing framework-contracts job" unless fast_job.is_a?(Hash)
errors << "missing contract-shards job" unless shard_job.is_a?(Hash)

excluded_suites = []
matrix_suites = []
if fast_job.is_a?(Hash)
  aggregate_step = fast_job.fetch("steps", []).find { |step| step.is_a?(Hash) && step["name"] == "Run aggregate framework contracts" }
  unless aggregate_step.is_a?(Hash)
    errors << "missing aggregate contract step"
  else
    exclusions = aggregate_step.dig("env", "P0P4_EXCLUDED_SUITES")
    if exclusions.is_a?(String)
      excluded_suites = exclusions.split
    else
      errors << "aggregate contract step must declare string P0P4_EXCLUDED_SUITES"
    end
    errors << "aggregate contract command must be ./tests/test-p0-p4-contracts.sh" unless aggregate_step["run"] == "./tests/test-p0-p4-contracts.sh"
  end
end

if shard_job.is_a?(Hash)
  matrix_suites = shard_job.dig("strategy", "matrix", "suite")
  unless matrix_suites.is_a?(Array) && matrix_suites.all? { |suite| suite.is_a?(String) }
    errors << "contract-shards matrix suite must be a string array"
    matrix_suites = []
  end
  long_shard_step = shard_job.fetch("steps", []).find { |step| step.is_a?(Hash) && step["name"] == "Run long contract shard" }
  unless long_shard_step.is_a?(Hash) && long_shard_step["run"] == 'bash "tests/p0-p4/${{ matrix.suite }}"'
    errors << "long shard must run exactly bash tests/p0-p4 matrix suite"
  end
end

unless all_aggregate_sources.uniq.length == all_aggregate_sources.length
  errors << "aggregate declares duplicate suites: #{all_aggregate_sources.tally.select { |_suite, count| count != 1 }.keys.sort.join(', ')}"
end
unless matrix_suites.uniq.length == matrix_suites.length
  errors << "matrix contains duplicate suites: #{matrix_suites.tally.select { |_suite, count| count != 1 }.keys.sort.join(', ')}"
end
unless excluded_suites.sort == matrix_suites.sort && excluded_suites.uniq.length == excluded_suites.length
  errors << "aggregate exclusions and matrix suites differ"
end
unless guarded_suites.sort == excluded_suites.sort && guarded_suites.uniq.length == guarded_suites.length
  errors << "guarded aggregate suites and declared exclusions differ"
end

(aggregate_suites + matrix_suites).uniq.each do |suite|
  errors << "scheduled suite is not top-level P0-P4 suite: #{suite}" unless suite_names.include?(suite)
end

suite_names.each do |suite|
  schedule_count = aggregate_suites.count(suite) + matrix_suites.count(suite)
  if compatibility_wrappers.include?(suite)
    errors << "compatibility wrapper must remain explicitly unscheduled: #{suite}" unless schedule_count.zero?
  elsif schedule_count != 1
    errors << "top-level P0-P4 suite must be scheduled exactly once: #{suite} (#{schedule_count})"
  end
end

unless errors.empty?
  warn errors.join("; ")
  exit 1
end
RUBY
}

test_start "P0-P4 aggregate and long shards schedule every substantive suite exactly once"
ci_schedule_output="$(mktemp)"
p0p4_register_cleanup "$ci_schedule_output"
if validate_p0p4_ci_schedule \
    "$FRAMEWORK_DIR/tests/test-p0-p4-contracts.sh" \
    "$FRAMEWORK_DIR/.github/workflows/framework-validation.yml" \
    "$FRAMEWORK_DIR/tests/p0-p4" >"$ci_schedule_output" 2>&1; then
    pass
else
    fail "P0-P4 CI schedule violations: $(cat "$ci_schedule_output")"
fi

test_start "P0-P4 CI schedule oracle rejects missing, orphaned, and bypassed suites"
ci_schedule_mutation_dir="$(mktemp -d)"
p0p4_register_cleanup "$ci_schedule_mutation_dir"
ci_schedule_mutation_failures=()
for ci_schedule_mutation in missing_aggregate_suite orphaned_shard_suite unguarded_shard_suite mismatched_shard_guard; do
    ci_schedule_mutation_aggregate="$ci_schedule_mutation_dir/$ci_schedule_mutation-aggregate.sh"
    ci_schedule_mutation_workflow="$ci_schedule_mutation_dir/$ci_schedule_mutation-workflow.yml"
    cp "$FRAMEWORK_DIR/tests/test-p0-p4-contracts.sh" "$ci_schedule_mutation_aggregate"
    cp "$FRAMEWORK_DIR/.github/workflows/framework-validation.yml" "$ci_schedule_mutation_workflow"
    case "$ci_schedule_mutation" in
        missing_aggregate_suite)
            ruby -e '
path = ARGV.fetch(0)
contents = File.read(path)
needle = "source \"$P0P4_SUITE_DIR/harness-controller-contracts.sh\"\n"
abort "missing harness source mutation target" unless contents.include?(needle)
File.write(path, contents.sub(needle, ""))
' "$ci_schedule_mutation_aggregate"
            ;;
        orphaned_shard_suite)
            ruby -e '
path = ARGV.fetch(0)
contents = File.read(path)
needle = "          - codex-behavioral-eval-contracts.sh\n"
abort "missing shard mutation target" unless contents.include?(needle)
File.write(path, contents.sub(needle, "          - orphaned-contracts.sh\n"))
' "$ci_schedule_mutation_workflow"
            ;;
        unguarded_shard_suite)
            ruby -e '
path = ARGV.fetch(0)
contents = File.read(path)
guarded = <<~SH
if ! p0p4_suite_is_excluded "skill-eval-contracts.sh"; then
    source "$P0P4_SUITE_DIR/skill-eval-contracts.sh"
fi
SH
replacement = "    source \"$P0P4_SUITE_DIR/skill-eval-contracts.sh\"\n"
abort "missing guarded shard source mutation target" unless contents.include?(guarded)
File.write(path, contents.sub(guarded, replacement))
' "$ci_schedule_mutation_aggregate"
            ;;
        mismatched_shard_guard)
            ruby -e '
path = ARGV.fetch(0)
contents = File.read(path)
needle = "if ! p0p4_suite_is_excluded \"skill-eval-contracts.sh\"; then\n"
abort "missing shard guard mutation target" unless contents.include?(needle)
File.write(path, contents.sub(needle, "if ! p0p4_suite_is_excluded \"progressive-discovery-contracts.sh\"; then\n"))
' "$ci_schedule_mutation_aggregate"
            ;;
    esac
    if validate_p0p4_ci_schedule "$ci_schedule_mutation_aggregate" "$ci_schedule_mutation_workflow" "$FRAMEWORK_DIR/tests/p0-p4" >/dev/null 2>&1; then
        ci_schedule_mutation_failures+=("$ci_schedule_mutation")
    fi
done
if [[ "${#ci_schedule_mutation_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "CI schedule oracle accepted mutation(s): ${ci_schedule_mutation_failures[*]}"
fi

test_start "tests tree has no .DS_Store files"
ds_store_file="$(find "$SCRIPT_DIR" -type f -name .DS_Store -print | sed -n '1p')"
if [[ -z "$ds_store_file" ]]; then
    pass
else
    fail "unexpected .DS_Store file under tests/: $ds_store_file"
fi

test_start "retired plugin distribution paths stay absent"
retired_plugin_paths=(
    "$FRAMEWORK_DIR/plugins"
    "$FRAMEWORK_DIR/docs/plugin-architecture.md"
    "$FRAMEWORK_DIR/tools/plugins/sync-plugin-skills.sh"
    "$FRAMEWORK_DIR/tests/p0-p4/plugin-boundary-contracts.sh"
    "$FRAMEWORK_DIR/tests/p0-p4/plugin-manifest-contracts.sh"
)
remaining_retired_plugin_paths=()
for retired_plugin_path in "${retired_plugin_paths[@]}"; do
    [[ ! -e "$retired_plugin_path" && ! -L "$retired_plugin_path" ]] \
        || remaining_retired_plugin_paths+=("${retired_plugin_path#"$FRAMEWORK_DIR/"}")
done
if [[ "${#remaining_retired_plugin_paths[@]}" -eq 0 ]]; then
    pass
else
    fail "retired plugin distribution paths remain: ${remaining_retired_plugin_paths[*]}"
fi

test_start "general CI covers framework contracts and installs without retired runtime jobs"
framework_validation_workflow="$FRAMEWORK_DIR/.github/workflows/framework-validation.yml"
framework_validation_failures=()
if [[ ! -f "$framework_validation_workflow" ]]; then
    framework_validation_failures+=("missing .github/workflows/framework-validation.yml")
else
    for term in \
        "pull_request:" \
        "push:" \
        "contents: read" \
        "persist-credentials: false" \
        "timeout-minutes: 30" \
        "timeout-minutes: 60" \
        "tools/skills/validate-skills.sh" \
        "./install.sh --agent codex --dry-run" \
        "./install.sh --agent claude --dry-run" \
        "./install.sh --agent gemini --dry-run"; do
        if ! grep -Fq -- "$term" "$framework_validation_workflow"; then
            framework_validation_failures+=("framework-validation.yml: $term")
        fi
    done

    [[ "$(grep -Ec '^[[:space:]]+uses: actions/checkout@v5[[:space:]]*$' "$framework_validation_workflow")" -eq 2 ]] \
        || framework_validation_failures+=("framework-validation.yml: expected checkout@v5 in both contract jobs")
    [[ "$(grep -Ec '^[[:space:]]+persist-credentials: false[[:space:]]*$' "$framework_validation_workflow")" -eq 2 ]] \
        || framework_validation_failures+=("framework-validation.yml: both checkouts must disable credential persistence")
    [[ "$(grep -Ec '^[[:space:]]+timeout-minutes: 30[[:space:]]*$' "$framework_validation_workflow")" -eq 1 ]] \
        || framework_validation_failures+=("framework-validation.yml: the fast framework-contract job must use the bounded timeout")
    [[ "$(grep -Ec '^[[:space:]]+timeout-minutes: 60[[:space:]]*$' "$framework_validation_workflow")" -eq 1 ]] \
        || framework_validation_failures+=("framework-validation.yml: the slow contract shards must use the bounded timeout")
    [[ "$(grep -Ec '^permissions:[[:space:]]*$' "$framework_validation_workflow")" -eq 1 ]] \
        || framework_validation_failures+=("framework-validation.yml: expected one workflow-level permissions block")
    [[ "$(grep -Ec '^[[:space:]]+contents: read[[:space:]]*$' "$framework_validation_workflow")" -eq 1 ]] \
        || framework_validation_failures+=("framework-validation.yml: expected one read-only contents permission")
    if grep -Eq 'pull_request_target|secrets\.' "$framework_validation_workflow"; then
        framework_validation_failures+=("framework-validation.yml: privileged PR events and secret references are forbidden")
    fi
    if rg -n -i -e 'memory graph' -e 'tools/memory-graph' -e 'MemoryGraph\.Tests' "$framework_validation_workflow" >/tmp/p0p4-framework-validation-retired-runtime.out; then
        framework_validation_failures+=("framework-validation.yml: retired Memory Graph job or invocation remains")
    fi
fi
if [[ "${#framework_validation_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "general CI contract violations: ${framework_validation_failures[*]}"
fi

test_start "general CI installs and verifies ripgrep before repository contracts"
ripgrep_setup_failures=()
if [[ ! -f "$framework_validation_workflow" ]]; then
    ripgrep_setup_failures+=("missing .github/workflows/framework-validation.yml")
else
    ripgrep_update_line="$(grep -nF -- "sudo apt-get update" "$framework_validation_workflow" | sed -n '1s/:.*//p' || true)"
    ripgrep_install_line="$(grep -nF -- "sudo apt-get install --yes --no-install-recommends ripgrep" "$framework_validation_workflow" | sed -n '1s/:.*//p' || true)"
    ripgrep_verify_line="$(grep -nF -- "command -v rg" "$framework_validation_workflow" | sed -n '1s/:.*//p' || true)"
    aggregate_contract_line="$(grep -nF -- "./tests/test-p0-p4-contracts.sh" "$framework_validation_workflow" | sed -n '1s/:.*//p' || true)"

    [[ -n "$ripgrep_update_line" ]] || ripgrep_setup_failures+=("framework-validation.yml: missing apt metadata refresh")
    [[ -n "$ripgrep_install_line" ]] || ripgrep_setup_failures+=("framework-validation.yml: missing minimal ripgrep install")
    [[ -n "$ripgrep_verify_line" ]] || ripgrep_setup_failures+=("framework-validation.yml: missing rg prerequisite check")
    [[ -n "$aggregate_contract_line" ]] || ripgrep_setup_failures+=("framework-validation.yml: missing aggregate contract step")

    if [[ -n "$ripgrep_update_line" && -n "$ripgrep_install_line" && -n "$ripgrep_verify_line" && -n "$aggregate_contract_line" ]]; then
        if ! (( ripgrep_update_line < ripgrep_install_line
            && ripgrep_install_line < ripgrep_verify_line
            && ripgrep_verify_line < aggregate_contract_line )); then
            ripgrep_setup_failures+=("framework-validation.yml: ripgrep setup and verification must precede aggregate contracts")
        fi
    fi
fi
if [[ "${#ripgrep_setup_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "general CI ripgrep setup violations: ${ripgrep_setup_failures[*]}"
fi

test_start "P0-P4 fixture installs isolate ambient CODEX_HOME and restore caller state"
ambient_codex_fixture_root="$(mktemp -d "$FRAMEWORK_DIR/.p0p4-ambient-codex-home.XXXXXX")"
ambient_codex_child="$ambient_codex_fixture_root/fixture-child.sh"
p0p4_register_cleanup "$ambient_codex_fixture_root"
cat >"$ambient_codex_child" <<'CHILD'
#!/usr/bin/env bash
set -euo pipefail

mode="$1"
harness="$2"
install_home="$3"
explicit_home="$4"
state_dir="$5"

case "$mode" in
    nonempty) export CODEX_HOME="$6" ;;
    empty) export CODEX_HOME="" ;;
    unset) unset CODEX_HOME ;;
    *) exit 64 ;;
esac

source "$harness"
trap -p EXIT >"$state_dir/cleanup-trap"
if [[ -n "${CODEX_HOME+x}" ]]; then printf "set:%s\\n" "$CODEX_HOME" >"$state_dir/ordinary-state"; else printf "unset\\n" >"$state_dir/ordinary-state"; fi

mkdir -p "$install_home" "$explicit_home"
p0p4_install_codex_fixture "$install_home" "$state_dir/ordinary.out" "$state_dir/ordinary.err" --no-hooks
if [[ -n "${CODEX_HOME+x}" ]]; then printf "set:%s\\n" "$CODEX_HOME" >"$state_dir/after-ordinary-state"; else printf "unset\\n" >"$state_dir/after-ordinary-state"; fi

p0p4_capture_command_scoped_codex_home() {
    if [[ -n "${CODEX_HOME+x}" ]]; then printf "set:%s\\n" "$CODEX_HOME" >"$state_dir/explicit-state"; else printf "unset\\n" >"$state_dir/explicit-state"; fi
}
CODEX_HOME="$explicit_home" p0p4_capture_command_scoped_codex_home
if [[ -n "${CODEX_HOME+x}" ]]; then printf "set:%s\\n" "$CODEX_HOME" >"$state_dir/after-explicit-state"; else printf "unset\\n" >"$state_dir/after-explicit-state"; fi

export CODEX_HOME="$7"
p0p4_cleanup
if [[ -n "${CODEX_HOME+x}" ]]; then printf "set:%s\\n" "$CODEX_HOME" >"$state_dir/cleanup-state"; else printf "unset\\n" >"$state_dir/cleanup-state"; fi
CHILD
chmod +x "$ambient_codex_child"

ambient_codex_failures=()
for ambient_codex_mode in nonempty empty unset; do
    ambient_codex_state="$ambient_codex_fixture_root/$ambient_codex_mode"
    ambient_codex_install_home="$ambient_codex_state/install-home"
    ambient_codex_explicit_home="$ambient_codex_state/explicit-codex-home"
    ambient_codex_cleanup_override="$ambient_codex_state/cleanup-override"
    ambient_codex_external_home="$ambient_codex_state/external-codex-home"
    mkdir -p "$ambient_codex_state" "$ambient_codex_external_home"
    printf '%s\\n' 'external CODEX_HOME sentinel' >"$ambient_codex_external_home/sentinel"
    find "$ambient_codex_external_home" -print | sort >"$ambient_codex_state/external.paths.before"
    find "$ambient_codex_external_home" -type f -exec shasum {} + | sort >"$ambient_codex_state/external.bytes.before"

    if ! /bin/bash "$ambient_codex_child" "$ambient_codex_mode" "$P0P4_HARNESS_DIR/p0p4-harness.sh" "$ambient_codex_install_home" "$ambient_codex_explicit_home" "$ambient_codex_state" "$ambient_codex_external_home" "$ambient_codex_cleanup_override"; then
        ambient_codex_failures+=("$ambient_codex_mode child failed")
        continue
    fi

    find "$ambient_codex_external_home" -print | sort >"$ambient_codex_state/external.paths.after"
    find "$ambient_codex_external_home" -type f -exec shasum {} + | sort >"$ambient_codex_state/external.bytes.after"
    expected_cleanup_state="unset"
    [[ "$ambient_codex_mode" == nonempty ]] && expected_cleanup_state="set:$ambient_codex_external_home"
    [[ "$ambient_codex_mode" == empty ]] && expected_cleanup_state="set:"
    if [[ "$(cat "$ambient_codex_state/ordinary-state")" != "unset" ]] \
        || [[ "$(cat "$ambient_codex_state/after-ordinary-state")" != "unset" ]] \
        || [[ "$(cat "$ambient_codex_state/explicit-state")" != "set:$ambient_codex_explicit_home" ]] \
        || [[ "$(cat "$ambient_codex_state/after-explicit-state")" != "unset" ]] \
        || ! grep -Fq 'p0p4_cleanup' "$ambient_codex_state/cleanup-trap" \
        || [[ "$(cat "$ambient_codex_state/cleanup-state")" != "$expected_cleanup_state" ]] \
        || [[ ! -d "$ambient_codex_install_home/.codex/skills/assistant-workflow" ]] \
        || ! cmp -s "$ambient_codex_state/external.paths.before" "$ambient_codex_state/external.paths.after" \
        || ! cmp -s "$ambient_codex_state/external.bytes.before" "$ambient_codex_state/external.bytes.after"; then
        ambient_codex_failures+=("$ambient_codex_mode")
    fi
done
if [[ "${#ambient_codex_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "ambient CODEX_HOME leaked into ordinary fixtures, command-scoped override, caller restoration, or controlled external state: ${ambient_codex_failures[*]}"
fi

test_start "P0-P4 cleanup attempts every target and restores CODEX_HOME after deletion failure"
cleanup_failure_root="$(mktemp -d "$FRAMEWORK_DIR/.p0p4-cleanup-failure.XXXXXX")"
cleanup_failure_child="$cleanup_failure_root/cleanup-failure-child.sh"
cleanup_failure_exit_child="$cleanup_failure_root/cleanup-failure-exit-child.sh"
cleanup_failure_original="$cleanup_failure_root/original-codex-home"
cleanup_failure_override="$cleanup_failure_root/override-codex-home"
cleanup_failure_targets=(
    "$cleanup_failure_root/cleanup-target-first"
    "$cleanup_failure_root/cleanup-target-second"
    "$cleanup_failure_root/cleanup-target-third"
)
p0p4_register_cleanup "$cleanup_failure_root"
mkdir -p "$cleanup_failure_original" "$cleanup_failure_override" "${cleanup_failure_targets[@]}"
cat >"$cleanup_failure_child" <<'CHILD'
#!/usr/bin/env bash
set -euo pipefail

harness="$1"
original_home="$2"
override_home="$3"
state_file="$4"
rm_log="$5"
shift 5

export CODEX_HOME="$original_home"
source "$harness"
export CODEX_HOME="$override_home"
p0p4_register_cleanup "$@"
rm_calls=0
rm() {
    local path="${!#}"
    rm_calls=$((rm_calls + 1))
    printf '%s\n' "$path" >>"$rm_log"
    [[ "$rm_calls" -ne 1 ]]
}
trap 'if [[ -n "${CODEX_HOME+x}" ]]; then printf "set:%s\\n" "$CODEX_HOME" >"$state_file"; else printf "unset\\n" >"$state_file"; fi' EXIT
p0p4_cleanup
CHILD
chmod +x "$cleanup_failure_child"
cat >"$cleanup_failure_exit_child" <<'CHILD'
#!/usr/bin/env bash
set -euo pipefail

harness="$1"
original_home="$2"
override_home="$3"
cleanup_path="$4"

export CODEX_HOME="$original_home"
source "$harness"
export CODEX_HOME="$override_home"
p0p4_register_cleanup "$cleanup_path"
rm() { return 1; }
:
CHILD
chmod +x "$cleanup_failure_exit_child"

set +e
/bin/bash "$cleanup_failure_child" "$P0P4_HARNESS_DIR/p0p4-harness.sh" "$cleanup_failure_original" "$cleanup_failure_override" "$cleanup_failure_root/exit-state" "$cleanup_failure_root/rm.log" "${cleanup_failure_targets[@]}"
cleanup_failure_status=$?
/bin/bash "$cleanup_failure_exit_child" "$P0P4_HARNESS_DIR/p0p4-harness.sh" "$cleanup_failure_original" "$cleanup_failure_override" "$cleanup_failure_root/exit-cleanup-target"
cleanup_failure_exit_status=$?
set -e
printf '%s\n' "${cleanup_failure_targets[@]}" >"$cleanup_failure_root/rm.expected"
if [[ "$cleanup_failure_status" -eq 0 ]] \
    || [[ "$cleanup_failure_exit_status" -eq 0 ]] \
    || [[ "$(cat "$cleanup_failure_root/exit-state" 2>/dev/null || true)" != "set:$cleanup_failure_original" ]]; then
    fail "cleanup failure did not return nonzero after restoring the original CODEX_HOME"
elif [[ "$(cat "$cleanup_failure_root/rm.expected")" != "$(cat "$cleanup_failure_root/rm.log")" ]]; then
    fail "cleanup target attempts differ: expected $(paste -sd ',' "$cleanup_failure_root/rm.expected"), actual $(paste -sd ',' "$cleanup_failure_root/rm.log")"
else
    pass
fi

test_start "top-level P0-P4 suites retain standalone bootstrap contracts"
direct_run_contract_failures=()
for suite_file in "$P0P4_SUITE_DIR"/*.sh; do
    [[ -f "$suite_file" ]] || continue
    suite_name="$(basename -- "$suite_file")"
    if ! bash -n "$suite_file"; then
        direct_run_contract_failures+=("$suite_name:syntax")
    fi
    if ! grep -Fq 'p0p4_bootstrap_suite' "$suite_file"; then
        direct_run_contract_failures+=("$suite_name:bootstrap")
    fi
done
direct_run_smoke_output="$(mktemp)"
p0p4_register_cleanup "$direct_run_smoke_output"
if ! bash "$P0P4_SUITE_DIR/review-loop-cap-contracts.sh" >"$direct_run_smoke_output" 2>&1 \
    || ! grep -Eq '^[[:space:]]+Failed: 0$' "$direct_run_smoke_output"; then
    direct_run_contract_failures+=("review-loop-cap-contracts.sh:direct-smoke")
fi
if [[ "${#direct_run_contract_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "standalone suite contract failures: ${direct_run_contract_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
