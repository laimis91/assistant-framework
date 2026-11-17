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

# Contract test cleanup R-TC-8: one aggregate job runs every suite; no shards or exclusions.
aggregate_suites = aggregate.scan(/^[ \t]*source "\$P0P4_SUITE_DIR\/([^\"\/]+\.sh)"$/).flatten
errors << "aggregate must not exclude suites" if aggregate.include?("p0p4_suite_is_excluded") || aggregate.include?("P0P4_EXCLUDED_SUITES")
suite_names = Dir[File.join(suite_dir, "*.sh")].map { |path| File.basename(path) }.sort
compatibility_wrappers = %w[agent-status-contracts.sh workflow-contracts.sh]

jobs = workflow.fetch("jobs", {})
contract_job = jobs["framework-contracts"]
errors << "missing framework-contracts job" unless contract_job.is_a?(Hash)
jobs.each do |name, job|
  next unless job.is_a?(Hash)
  errors << "job #{name} must not shard contract suites" if job.dig("strategy", "matrix") || job.fetch("steps", []).any? { |step| step.is_a?(Hash) && step["run"].to_s.match?(/tests\/p0-p4\/[^ ]*\.sh/) && !step["run"].to_s.include?("response-fixture-entrypoint-probe.py") }
end

if contract_job.is_a?(Hash)
  steps = contract_job.fetch("steps", [])
  aggregate_index = steps.index { |step| step.is_a?(Hash) && step["name"] == "Run aggregate framework contracts" }
  if aggregate_index.nil?
    errors << "missing aggregate contract step"
  else
    aggregate_step = steps[aggregate_index]
    errors << "aggregate contract command must be ./tests/test-p0-p4-contracts.sh" unless aggregate_step["run"] == "./tests/test-p0-p4-contracts.sh"
    errors << "aggregate contract step must not exclude suites" if aggregate_step.fetch("env", {}).to_h.key?("P0P4_EXCLUDED_SUITES")
  end
  ruby_indexes = steps.each_index.select do |index|
    step = steps[index]
    next false unless step.is_a?(Hash) && step["name"] == "Verify runner prerequisites"
    run = step["run"]
    run.is_a?(String) && run.lines.any? { |line| line.strip == "command -v ruby" } &&
      run.lines.any? { |line| line.strip.start_with?("ruby -rjson -ryaml -rbigdecimal -e ") }
  end
  if ruby_indexes.empty?
    errors << "framework-contracts must verify Ruby with JSON, Psych/YAML, and BigDecimal support"
  elsif aggregate_index && ruby_indexes.none? { |index| index < aggregate_index }
    errors << "Ruby/Psych verification must precede the aggregate contracts"
  end
  probes = steps.select { |step| step.is_a?(Hash) && step["run"].to_s.include?("response-fixture-entrypoint-probe.py") }
  expected_probe = %w[skill-eval-contracts.sh progressive-discovery-contracts.sh].map { |suite| "python3 tests/p0-p4/lib/response-fixture-entrypoint-probe.py #{suite}" }
  if probes.length != 1 || probes[0]["name"] != "Check response fixture entrypoints" || probes[0]["run"].to_s.lines.map(&:strip).reject(&:empty?) != expected_probe
    errors << "one response entrypoint probe step must check both response-builder suites"
  elsif aggregate_index && steps.index(probes[0]) >= aggregate_index
    errors << "response entrypoint probe must precede the aggregate contracts"
  end
end

unless aggregate_suites.uniq.length == aggregate_suites.length
  errors << "aggregate declares duplicate suites: #{aggregate_suites.tally.select { |_suite, count| count != 1 }.keys.sort.join(', ')}"
end
aggregate_suites.uniq.each do |suite|
  errors << "scheduled suite is not top-level P0-P4 suite: #{suite}" unless suite_names.include?(suite)
end
suite_names.each do |suite|
  count = aggregate_suites.count(suite)
  if compatibility_wrappers.include?(suite)
    errors << "compatibility wrapper must remain explicitly unscheduled: #{suite}" unless count.zero?
  elsif count != 1
    errors << "top-level P0-P4 suite must be scheduled exactly once: #{suite} (#{count})"
  end
end

unless errors.empty?
  warn errors.join("; ")
  exit 1
end
RUBY
}

test_start "P0-P4 aggregate schedules every substantive suite exactly once in one CI job"
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

test_start "P0-P4 CI schedule oracle rejects missing, duplicated, excluded, sharded and misplaced checks"
ci_schedule_mutation_dir="$(mktemp -d)"
p0p4_register_cleanup "$ci_schedule_mutation_dir"
ci_schedule_mutation_failures=()
for ci_schedule_mutation in missing_aggregate_suite duplicate_aggregate_suite sourced_wrapper excluded_suite shard_job \
    excluded_env misplaced_ruby_prerequisite missing_response_probe misplaced_response_probe wrong_response_probe_command; do
    ci_schedule_mutation_aggregate="$ci_schedule_mutation_dir/$ci_schedule_mutation-aggregate.sh"
    ci_schedule_mutation_workflow="$ci_schedule_mutation_dir/$ci_schedule_mutation-workflow.yml"
    cp "$FRAMEWORK_DIR/tests/test-p0-p4-contracts.sh" "$ci_schedule_mutation_aggregate"
    cp "$FRAMEWORK_DIR/.github/workflows/framework-validation.yml" "$ci_schedule_mutation_workflow"
    ruby -ryaml -e '
aggregate_path, workflow_path, mutation = ARGV
aggregate = File.read(aggregate_path)
workflow = YAML.load_file(workflow_path)
steps = workflow.fetch("jobs").fetch("framework-contracts").fetch("steps")
harness = "source \"$P0P4_SUITE_DIR/harness-controller-contracts.sh\"\n"
abort "missing harness source mutation target" unless aggregate.include?(harness)
find = ->(name) { steps.find { |step| step["name"] == name } or abort "missing step #{name}" }
case mutation
when "missing_aggregate_suite" then aggregate = aggregate.sub(harness, "")
when "duplicate_aggregate_suite" then aggregate = aggregate.sub(harness, harness * 2)
when "sourced_wrapper" then aggregate = aggregate.sub(harness, harness + "source \"$P0P4_SUITE_DIR/workflow-contracts.sh\"\n")
when "excluded_suite" then aggregate = aggregate.sub(harness, "if ! p0p4_suite_is_excluded \"harness-controller-contracts.sh\"; then\n    #{harness}fi\n")
when "shard_job" then workflow["jobs"]["contract-shards"] = { "strategy" => { "matrix" => { "suite" => ["skill-eval-contracts.sh"] } }, "steps" => [{ "run" => "bash \"tests/p0-p4/${{ matrix.suite }}\"" }] }
when "excluded_env" then find.call("Run aggregate framework contracts")["env"] = { "P0P4_EXCLUDED_SUITES" => "skill-eval-contracts.sh" }
when "misplaced_ruby_prerequisite" then step = find.call("Verify runner prerequisites"); steps.delete(step); steps << step
when "missing_response_probe" then steps.delete(find.call("Check response fixture entrypoints"))
when "misplaced_response_probe" then step = find.call("Check response fixture entrypoints"); steps.delete(step); steps << step
when "wrong_response_probe_command" then find.call("Check response fixture entrypoints")["run"] = "echo skipped"
end
File.write(aggregate_path, aggregate)
File.write(workflow_path, YAML.dump(workflow))
' "$ci_schedule_mutation_aggregate" "$ci_schedule_mutation_workflow" "$ci_schedule_mutation" \
        || { ci_schedule_mutation_failures+=("$ci_schedule_mutation (mutation not applied)"); continue; }
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

test_start "general CI covers framework contracts without retired runtime or installer jobs"
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
        "timeout-minutes: 90" \
        "tools/skills/validate-skills.sh"; do
        if ! grep -Fq -- "$term" "$framework_validation_workflow"; then
            framework_validation_failures+=("framework-validation.yml: $term")
        fi
    done

    [[ "$(grep -Ec '^[[:space:]]+uses: actions/checkout@v5[[:space:]]*$' "$framework_validation_workflow")" -eq 1 ]] \
        || framework_validation_failures+=("framework-validation.yml: expected checkout@v5 in the contract job")
    [[ "$(grep -Ec '^[[:space:]]+persist-credentials: false[[:space:]]*$' "$framework_validation_workflow")" -eq 1 ]] \
        || framework_validation_failures+=("framework-validation.yml: the checkout must disable credential persistence")
    [[ "$(grep -Ec '^[[:space:]]+timeout-minutes: 90[[:space:]]*$' "$framework_validation_workflow")" -eq 1 ]] \
        || framework_validation_failures+=("framework-validation.yml: the fast framework-contract job must use the bounded timeout")
    if ! ruby -ryaml - "$framework_validation_workflow" <<'RUBY'
jobs = YAML.load_file(ARGV.fetch(0)).fetch("jobs")
abort "unexpected contract timeout policy" unless jobs.fetch("framework-contracts")["timeout-minutes"] == 90
abort "unexpected extra contract job" unless jobs.keys == ["framework-contracts"]
RUBY
    then
        framework_validation_failures+=("framework-validation.yml: one framework-contracts job with a 90-minute timeout")
    fi
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
    if rg -n -i -e 'install\.sh' -e 'install\.ps1' -e 'gemini' "$framework_validation_workflow" >/tmp/p0p4-framework-validation-retired-installer.out; then
        framework_validation_failures+=("framework-validation.yml: retired installer or Gemini step remains")
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

test_start "general CI verifies Ruby Psych before the contract job"
ruby_setup_failures=()
if [[ ! -f "$framework_validation_workflow" ]]; then
    ruby_setup_failures+=("missing .github/workflows/framework-validation.yml")
else
    ruby_verify_count="$(grep -Ec '^[[:space:]]+command -v ruby[[:space:]]*$' "$framework_validation_workflow" || true)"
    psych_verify_count="$(grep -Ec '^[[:space:]]+ruby -rjson -ryaml -rbigdecimal -e ' "$framework_validation_workflow" || true)"
    first_ruby_verify_line="$(grep -nF -- "command -v ruby" "$framework_validation_workflow" | sed -n '1s/:.*//p' || true)"
    aggregate_contract_line="$(grep -nF -- "./tests/test-p0-p4-contracts.sh" "$framework_validation_workflow" | sed -n '1s/:.*//p' || true)"

    [[ "$ruby_verify_count" -eq 1 ]] || ruby_setup_failures+=("framework-validation.yml: the contract job must verify Ruby once")
    [[ "$psych_verify_count" -eq 1 ]] || ruby_setup_failures+=("framework-validation.yml: the contract job must verify Ruby JSON, Psych/YAML, and BigDecimal")
    if [[ -z "$first_ruby_verify_line" || -z "$aggregate_contract_line" ]] \
        || ! (( first_ruby_verify_line < aggregate_contract_line )); then
        ruby_setup_failures+=("framework-validation.yml: Ruby verification must precede aggregate contracts")
    fi
fi
if [[ "${#ruby_setup_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "general CI Ruby/Psych setup violations: ${ruby_setup_failures[*]}"
fi

test_start "README preserves source-edit isolation and validator runtime prerequisites"
readme_contract_failures=()
if ! grep -Fq "Source-changing packets in a shared or unknown workspace remain sequential" "$FRAMEWORK_DIR/README.md"; then
    readme_contract_failures+=("missing shared-workspace sequential gate")
fi
if ! grep -Fq "parallel source-changing packets require runtime proof of isolated workspaces" "$FRAMEWORK_DIR/README.md"; then
    readme_contract_failures+=("missing isolated-workspace proof gate")
fi
if ! grep -Fq "skill-eval runner requires Ruby with JSON and Psych/YAML support" "$FRAMEWORK_DIR/README.md" \
    || ! grep -Fq "ruby -rbigdecimal" "$FRAMEWORK_DIR/README.md"; then
    readme_contract_failures+=("missing Ruby JSON/Psych/YAML/BigDecimal evaluator prerequisite")
fi
if [[ "${#readme_contract_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "README contract violations: ${readme_contract_failures[*]}"
fi

test_start "P0-P4 fixture installs isolate ambient CODEX_HOME and restore caller state"
ambient_codex_fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/p0p4-ambient-codex-home.XXXXXX")"
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
p0p4_install_codex_fixture "$install_home" "$state_dir/ordinary.out" "$state_dir/ordinary.err"
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
