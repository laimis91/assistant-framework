if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "all concrete Codex writers retain the shared implementation and truthful partial-work contract"
if ruby - "$FRAMEWORK_DIR" <<'RUBY'
root=ARGV.fetch(0)
texts=%w[code-writer intelligent-writer mechanical-writer].map { |role| File.read("#{root}/agents/codex/#{role}.toml") }
shared=texts.map { |s| s[s.index('## What you do')..-1] }
raise 'common writer contract drift' unless shared.uniq.length == 1
texts.each do |text|
  ['current_task_packet','inline context','conflict blocks','mechanical_eligibility','changed_files','files_changed','FAILED_VERIFICATION','stop dependent mutations','Do NOT review your own code'].each do |term|
    # Case/wording-neutral static contract coverage; outcome controls are separate.
    next if term == 'conflict blocks' && text.include?('conflict blocks dispatch')
    next if term == 'mechanical_eligibility' && text.include?('four eligibility')
    raise "missing writer guarantee #{term}" unless text.downcase.include?(term.downcase)
  end
end
raise 'intelligent boundary missing' unless texts[1].include?('Never invent desired behavior') && texts[1].include?('NEEDS_CONTEXT')
raise 'mechanical judgment not constrained' unless texts[2].include?('Do not choose policy') && texts[2].include?('stale evidence stops dependent mutations')
raise 'legacy definition not deprecated' unless texts[0].include?('Deprecated standalone intelligent compatibility')
RUBY
then pass; else fail "writer definitions dropped shared guarantees or judgment boundaries"; fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
