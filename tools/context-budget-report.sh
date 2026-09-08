#!/usr/bin/env bash
# Reproducible, content-free inventory of Assistant Framework instruction load.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

AGENT=""
SKILL=""
OUTPUT_FORMAT="json"
BASELINE=""
SKILL_OVERLAY=""
LOAD_SET=""
SKILL_TREE=""
INVENTORY_MODE="isolated_install"

usage() {
    cat <<'EOF'
Usage:
  context-budget-report.sh --agent AGENT --skill SKILL --format json [--baseline FILE] [--skill-overlay FILE] [--load-set NAME] [--skill-tree DIR]

Create a local, content-free inventory of framework instruction load. The
report never includes prompt bodies, instruction bodies, responses, credentials,
or environment values.

Options:
  --agent AGENT            target agent; currently codex only
  --skill SKILL            selected skill name, such as assistant-workflow
  --format json            emit the versioned JSON report
  --baseline FILE          add current-minus-baseline absolute/percent deltas
  --skill-overlay FILE     replace only the selected root SKILL.md measurement;
                           canonical contracts/references and standing context stay unchanged
  --load-set NAME          add static declared and worker-return-schema closure metrics
                           for the named contracts/index.yaml load set
  --skill-tree DIR         measure a safe, already materialized selected skill tree;
                           cannot be combined with --skill-overlay
  -h, --help               show this help
EOF
}

die() {
    echo "Error: $1" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required."
}

safe_cleanup() {
    local path="${WORK_ROOT:-}"
    if [[ -n "$path" && -d "$path" && "$path" == "${TMPDIR:-/tmp}"/assistant-context-budget.* ]]; then
        rm -rf "$path"
    fi
}

measure_file() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        printf '0 0\n'
        return
    fi
    printf '%s %s\n' \
        "$(awk '{ words += NF } END { print words + 0 }' "$path")" \
        "$(wc -c <"$path" | tr -d ' ')"
}

append_with_boundary() {
    local source="$1" destination="$2"
    [[ -f "$source" ]] || return 0
    if [[ -s "$destination" ]] && ! tail -c 1 "$destination" | grep -qx ''; then
        printf '\n' >>"$destination"
    fi
    cat "$source" >>"$destination"
}

extract_marker_block() {
    local source_file="$1"
    local start_marker="$2"
    local end_marker="$3"
    local output_file="$4"

    : >"$output_file"
    [[ -f "$source_file" ]] || return 0
    awk -v start_marker="$start_marker" -v end_marker="$end_marker" '
      index($0, start_marker) { in_block = 1 }
      in_block { print }
      in_block && index($0, end_marker) { exit }
    ' "$source_file" >"$output_file"
}

extract_skill_description() {
    local skill_file="$1"
    awk '
      NR == 1 && $0 == "---" { frontmatter = 1; next }
      frontmatter && $0 == "---" { exit }
      frontmatter && /^description:[[:space:]]*/ {
        value = $0
        sub(/^description:[[:space:]]*/, "", value)
        if (value == ">" || value == "|") {
          multiline = 1
          next
        }
        gsub(/^"|"$/, "", value)
        print value
        exit
      }
      frontmatter && multiline {
        if ($0 ~ /^[[:space:]]+/) {
          value = $0
          sub(/^[[:space:]]+/, "", value)
          print value
        } else {
          exit
        }
      }
    ' "$skill_file"
}

collect_load_set_rows() {
    local index_file="$1"
    local load_set="$2"
    awk -v load_set="$load_set" '
      function trim(value) {
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)
        return value
      }
      function flush_selector() {
        if (selector_path != "") {
          print "selector|" selector_path "|" selector_section "|" selector_key "|" selector_names
        }
        selector_path = ""
        selector_section = ""
        selector_key = ""
        selector_names = ""
      }
      $0 == "  " load_set ":" { in_set = 1; next }
      in_set && /^  [[:alnum:]_-]+:[[:space:]]*$/ { flush_selector(); exit }
      !in_set { next }
      /^    references:[[:space:]]*$/ { in_references = 1; in_selectors = 0; next }
      /^    selectors:[[:space:]]*$/ { in_references = 0; in_selectors = 1; next }
      /^    budget_words:/ { flush_selector(); in_references = 0; in_selectors = 0; next }
      in_references && /^      -[[:space:]]*/ {
        value = $0
        sub(/^      -[[:space:]]*/, "", value)
        print "reference|" trim(value)
        next
      }
      in_selectors && /^      - id:/ { flush_selector(); next }
      in_selectors && /^        path:/ {
        value = $0; sub(/^        path:[[:space:]]*/, "", value); selector_path = trim(value); next
      }
      in_selectors && /^        section:/ {
        value = $0; sub(/^        section:[[:space:]]*/, "", value); selector_section = trim(value); next
      }
      in_selectors && /^        key:/ {
        value = $0; sub(/^        key:[[:space:]]*/, "", value); selector_key = trim(value); next
      }
      in_selectors && /^        names:/ {
        value = $0
        sub(/^        names:[[:space:]]*\[/, "", value)
        sub(/\][[:space:]]*$/, "", value)
        selector_names = trim(value)
        next
      }
      END { if (in_set) flush_selector() }
    ' "$index_file"
}

append_selected_contract_items() {
    local contract_file="$1"
    local section="$2"
    local key="$3"
    local names="$4"
    local destination="$5"

    [[ -f "$contract_file" && -n "$section" && -n "$key" && -n "$names" ]] || return
    if [[ -s "$destination" ]] && ! tail -c 1 "$destination" | grep -qx ''; then
        printf '\n' >>"$destination"
    fi
    awk -v section="$section" -v key="$key" -v names="$names" '
      BEGIN {
        count = split(names, wanted_names, ",")
        for (i = 1; i <= count; i++) {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", wanted_names[i])
          wanted[wanted_names[i]] = 1
        }
      }
      $0 == section ":" { in_section = 1; next }
      in_section && /^[^[:space:]#]/ { exit }
      in_section && /^  - / {
        keep = 0
        line = $0
        marker = "  - " key ":"
        if (index(line, marker) == 1) {
          value = substr(line, length(marker) + 1)
          gsub(/^[[:space:]"\047]+|[[:space:]"\047]+$/, "", value)
          if (wanted[value]) keep = 1
        }
      }
      in_section && keep { print }
    ' "$contract_file" >>"$destination"
}

build_selected_boundaries() {
    local skill_dir="$1"
    local initial_file="$2"
    local entry_file="$3"
    local root_file="${4:-$skill_dir/SKILL.md}"
    local load_set="${5:-entry}"
    local index_file="$skill_dir/contracts/index.yaml"

    : >"$initial_file"
    append_with_boundary "$root_file" "$initial_file"
    if [[ -f "$index_file" ]]; then
        append_with_boundary "$index_file" "$initial_file"
    fi
    cp "$initial_file" "$entry_file"
    [[ -f "$index_file" ]] || return 0

    local kind field1 field2 field3 field4 candidate canonical_skill
    canonical_skill="$(cd "$skill_dir" && pwd -P)"
    while IFS='|' read -r kind field1 field2 field3 field4; do
        [[ -n "$kind" ]] || continue
        candidate="$skill_dir/$field1"
        case "$kind" in
            reference)
                if [[ -f "$candidate" && "$(cd "$(dirname "$candidate")" && pwd -P)/$(basename "$candidate")" == "$canonical_skill"/* ]]; then
                    append_with_boundary "$candidate" "$entry_file"
                fi
                ;;
            selector)
                if [[ -f "$candidate" && "$(cd "$(dirname "$candidate")" && pwd -P)/$(basename "$candidate")" == "$canonical_skill"/* ]]; then
                    append_selected_contract_items "$candidate" "$field2" "$field3" "$field4" "$entry_file"
                fi
                ;;
        esac
    done < <(collect_load_set_rows "$index_file" "$load_set")
}

validate_static_load_set_and_project_workers() {
    local skill_dir="$1"
    local load_set="$2"
    local projection_file="$3"
    local declared_file="$4"

    ruby -r yaml -r json - "$skill_dir" "$load_set" "$projection_file" "$declared_file" <<'RUBY'
def fail!(message)
  abort "Error: static load set: #{message}"
end

def reject_duplicate_mapping_keys(node)
  if node.is_a?(Psych::Nodes::Mapping)
    keys = {}
    node.children.each_slice(2) do |key_node, value_node|
      fail!("YAML mapping key is malformed") unless key_node.is_a?(Psych::Nodes::Scalar)
      key = key_node.value
      fail!("YAML has duplicate mapping key #{key.inspect}") if keys[key]
      keys[key] = true
      reject_duplicate_mapping_keys(value_node)
    end
  elsif node.respond_to?(:children) && node.children
    node.children.each { |child| reject_duplicate_mapping_keys(child) }
  end
end

def safe_document(path)
  content = File.read(path)
  stream = Psych.parse_stream(content)
  reject_duplicate_mapping_keys(stream)
  YAML.safe_load(content, aliases: false)
rescue Psych::Exception => error
  fail!("malformed YAML at #{path}: #{error.message}")
end

def resolve_inside(root, relative)
  fail!("path must be a non-empty relative string") unless relative.is_a?(String) && !relative.empty?
  fail!("unsafe path #{relative.inspect}") if relative.start_with?("/") || relative.include?("\\") || relative.split("/").any? { |part| part == "." || part == ".." || part.empty? }
  candidate = File.expand_path(relative, root)
  physical = File.realpath(candidate)
  fail!("path escapes skill tree: #{relative}") unless physical.start_with?(root + "/") && File.file?(physical) && !File.symlink?(candidate)
  physical
rescue Errno::ENOENT
  fail!("path is missing: #{relative}")
end

def scalar?(value)
  value.is_a?(String) || value.is_a?(Integer) || value.is_a?(Float) || value == true || value == false
end

def project_field(field, depth = 0)
  fail!("worker return field is not an object") unless field.is_a?(Hash)
  fail!("worker return shape exceeds nesting bound") if depth > 16
  name = field["name"]
  type = field["type"]
  required = field["required"]
  fail!("worker return field name is missing") unless name.is_a?(String) && !name.empty?
  fail!("worker return field #{name} type is missing") unless type.is_a?(String) && !type.empty?
  fail!("worker return field #{name} required is malformed") unless required == true || required == false || required == "conditional"
  if required == "conditional"
    condition = field["condition"]
    fail!("conditional worker return field #{name} has no condition") unless condition.is_a?(String) && !condition.empty?
  end
  result = { "name" => name, "type" => type, "required" => required }
  result["condition"] = field["condition"] if field.key?("condition")
  if type == "enum"
    values = field["enum_values"]
    fail!("worker return field #{name} enum_values is malformed") unless values.is_a?(Array) && !values.empty? && values.all? { |value| scalar?(value) } && values.uniq.length == values.length
    result["enum_values"] = values
  elsif field.key?("enum_values")
    values = field["enum_values"]
    fail!("worker return field #{name} enum_values is malformed") unless values.is_a?(Array) && values.all? { |value| scalar?(value) }
    result["enum_values"] = values
  end
  %w[min_items max_items].each do |key|
    next unless field.key?(key)
    value = field[key]
    fail!("worker return field #{name} #{key} is malformed") unless value.is_a?(Integer) && value >= 0
    result[key] = value
  end
  if field.key?("object_fields")
    nested = field["object_fields"]
    fail!("worker return field #{name} object_fields is malformed") unless nested.is_a?(Array)
    names = nested.map { |item| item.is_a?(Hash) ? item["name"] : nil }
    fail!("worker return field #{name} object_fields has duplicate or missing names") unless names.all? { |nested_name| nested_name.is_a?(String) && !nested_name.empty? } && names.uniq.length == names.length
    result["object_fields"] = nested.map { |item| project_field(item, depth + 1) }
  end
  result
end

def source_property_value(line, key)
  property = line.sub(/^[[:space:]]*-[[:space:]]*/, "").sub(/^[[:space:]]*/, "")
  return nil unless property.match?(/\A#{Regexp.escape(key)}:[[:space:]]*/)
  value = property.sub(/\A[^:]*:[[:space:]]*/, "").sub(/[[:space:]]+#.*\z/, "").strip
  value = value[1...-1] if (value.start_with?("\"") && value.end_with?("\"")) || (value.start_with?("'") && value.end_with?("'"))
  value
end

def exact_source_items(path, section, key, names)
  lines = File.readlines(path)
  section_lines = lines.each_index.select { |index| lines[index].chomp == "#{section}:" }
  fail!("selector section #{section} is missing or ambiguous in source") unless section_lines.length == 1
  start = section_lines.first + 1
  finish = (start...lines.length).find { |index| lines[index].match?(/^[^[:space:]#][^:]*:/) } || lines.length
  items = Hash.new { |hash, item_name| hash[item_name] = [] }
  item_start = nil
  item_name = nil
  append_item = lambda do |end_index|
    items[item_name] << lines[item_start...end_index].join if item_start && item_name
  end
  (start...finish).each do |index|
    line = lines[index]
    if line.match?(/^  -([[:space:]]|$)/)
      append_item.call(index)
      item_start = index
      item_name = source_property_value(line, key)
    elsif item_start && line.match?(/^    #{Regexp.escape(key)}:[[:space:]]*/)
      item_name = source_property_value(line, key)
    end
  end
  append_item.call(finish)
  names.map do |name|
    matches = items[name]
    fail!("selector #{name} has missing, ambiguous, or unsupported source content") unless matches.length == 1 && !matches.first.empty?
    matches.first
  end
end

skill_dir, load_set_name, projection_file, declared_file = ARGV
root = File.realpath(skill_dir)
fail!("skill tree is not a directory") unless File.directory?(root) && !File.symlink?(skill_dir)
index = safe_document(resolve_inside(root, "contracts/index.yaml"))
fail!("contracts/index.yaml root is malformed") unless index.is_a?(Hash)
load_sets = index["load_sets"]
fail!("load_sets is missing") unless load_sets.is_a?(Hash)
load_set = load_sets[load_set_name]
fail!("unknown load set #{load_set_name}") unless load_set.is_a?(Hash)
budget = load_set["budget_words"]
fail!("load set #{load_set_name} budget_words is malformed") unless budget.is_a?(Integer) && budget > 0
references = load_set.fetch("references", [])
fail!("load set #{load_set_name} references is malformed") unless references.is_a?(Array)
fail!("load set #{load_set_name} has duplicate references") unless references.uniq.length == references.length
reference_paths = references.map { |reference| resolve_inside(root, reference) }
selectors = load_set.fetch("selectors", [])
fail!("load set #{load_set_name} selectors is malformed") unless selectors.is_a?(Array)

worker_selectors = []
selected_rows = []
selected_source_spans = []
selected_keys = {}
selectors.each do |selector|
  fail!("load set #{load_set_name} selector is malformed") unless selector.is_a?(Hash)
  fail!("load set #{load_set_name} has runtime name_from selector") if selector.key?("name_from")
  path, section, key, names = selector.values_at("path", "section", "key", "names")
  fail!("load set #{load_set_name} selector is missing static names") unless path.is_a?(String) && section.is_a?(String) && key.is_a?(String) && names.is_a?(Array) && !names.empty? && names.all? { |name| name.is_a?(String) && !name.empty? } && names.uniq.length == names.length
  document = safe_document(resolve_inside(root, path))
  source_file = resolve_inside(root, path)
  rows = document.is_a?(Hash) ? document[section] : nil
  fail!("load set #{load_set_name} selector section #{section} is malformed") unless rows.is_a?(Array)
  names.each do |name|
    selected_key = [path, section, key, name].join("\u0000")
    fail!("load set #{load_set_name} has duplicate selected selector #{name}") if selected_keys[selected_key]
    selected_keys[selected_key] = true
    matches = rows.select { |row| row.is_a?(Hash) && row[key] == name }
    fail!("load set #{load_set_name} selector #{name} is missing or ambiguous") unless matches.length == 1
    selected_rows << matches.first
    selected_source_spans.concat(exact_source_items(source_file, section, key, [name]))
    worker_selector = matches.first["worker_return_schema_selector"]
    worker_selectors << worker_selector unless worker_selector.nil?
  end
end

projections = worker_selectors.map do |selector|
  fail!("worker_return_schema_selector is malformed") unless selector.is_a?(Hash)
  source_path = selector["source_path"]
  reference = selector["return_schema_ref"]
  fail!("worker return schema source_path is not canonical") unless source_path == "contracts/handoffs.yaml"
  source = safe_document(resolve_inside(root, source_path))
  match = /\Ahandoffs\.([a-z0-9_]+)\.return_fields\z/.match(reference)
  fail!("worker return schema reference is malformed") unless match
  handoffs = source.is_a?(Hash) ? source["handoffs"] : nil
  fail!("worker return schema handoffs are malformed") unless handoffs.is_a?(Array)
  matches = handoffs.select { |handoff| handoff.is_a?(Hash) && handoff["name"] == match[1] }
  fail!("worker return schema reference #{reference} is missing or ambiguous") unless matches.length == 1
  fields = matches.first["return_fields"]
  fail!("worker return schema #{reference} is malformed") unless fields.is_a?(Array) && fields.length <= 512
  field_names = fields.map { |field| field.is_a?(Hash) ? field["name"] : nil }
  fail!("worker return schema #{reference} has duplicate or missing names") unless field_names.all? { |name| name.is_a?(String) && !name.empty? } && field_names.uniq.length == field_names.length
  { "return_schema_ref" => reference, "return_fields" => fields.map { |field| project_field(field) } }
end

def append_with_boundary(content, addition)
  return addition if content.empty?
  return content + addition if content.end_with?("\n")
  content + "\n" + addition
end

declared_content = ""
declared_content = append_with_boundary(declared_content, File.binread(resolve_inside(root, "SKILL.md")))
declared_content = append_with_boundary(declared_content, File.binread(resolve_inside(root, "contracts/index.yaml")))
reference_paths.each { |path| declared_content = append_with_boundary(declared_content, File.binread(path)) }
selected_source_spans.each { |span| declared_content = append_with_boundary(declared_content, span) }
File.binwrite(declared_file, declared_content)
File.write(projection_file, JSON.pretty_generate(projections) + "\n")
RUBY
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --agent)
            [[ $# -ge 2 ]] || die "Missing value for --agent."
            AGENT="$2"; shift 2
            ;;
        --skill)
            [[ $# -ge 2 ]] || die "Missing value for --skill."
            SKILL="$2"; shift 2
            ;;
        --format)
            [[ $# -ge 2 ]] || die "Missing value for --format."
            OUTPUT_FORMAT="$2"; shift 2
            ;;
        --baseline)
            [[ $# -ge 2 ]] || die "Missing value for --baseline."
            BASELINE="$2"; shift 2
            ;;
        --skill-overlay)
            [[ $# -ge 2 ]] || die "Missing value for --skill-overlay."
            SKILL_OVERLAY="$2"; shift 2
            ;;
        --load-set)
            [[ $# -ge 2 ]] || die "Missing value for --load-set."
            LOAD_SET="$2"; shift 2
            ;;
        --skill-tree)
            [[ $# -ge 2 ]] || die "Missing value for --skill-tree."
            SKILL_TREE="$2"; shift 2
            ;;
        -h|--help)
            usage; exit 0
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

require_command jq
[[ "$AGENT" == "codex" ]] || die "--agent currently supports codex only."
[[ -n "$SKILL" ]] || die "--skill is required."
[[ "$SKILL" != */* && "$SKILL" != .* ]] || die "--skill must be a skill name, not a path."
[[ "$OUTPUT_FORMAT" == "json" ]] || die "Only --format json is supported."
SOURCE_SKILL_DIR="$REPO_ROOT/skills/$SKILL"
[[ -f "$SOURCE_SKILL_DIR/SKILL.md" ]] || die "Skill not found: $SKILL"
if [[ -n "$SKILL_TREE" ]]; then
    [[ -z "$SKILL_OVERLAY" ]] || die "--skill-tree cannot be combined with --skill-overlay."
    [[ -d "$SKILL_TREE" && ! -L "$SKILL_TREE" && -f "$SKILL_TREE/SKILL.md" && ! -L "$SKILL_TREE/SKILL.md" ]] \
        || die "--skill-tree must be a non-symlink directory with a regular SKILL.md."
    if find -H "$SKILL_TREE" -type l -print -quit | grep -q .; then
        die "--skill-tree must not contain symlinks."
    fi
    grep -Eq "^name:[[:space:]]*[\"']?$SKILL[\"']?[[:space:]]*$" "$SKILL_TREE/SKILL.md" \
        || die "Skill tree name does not match --skill $SKILL."
    SOURCE_SKILL_DIR="$SKILL_TREE"
fi
if [[ -n "$SKILL_OVERLAY" ]]; then
    [[ -f "$SKILL_OVERLAY" ]] || die "Skill overlay not found: $SKILL_OVERLAY"
    grep -Eq "^name:[[:space:]]*[\"']?$SKILL[\"']?[[:space:]]*$" "$SKILL_OVERLAY" \
        || die "Skill overlay name does not match --skill $SKILL."
fi
if [[ -n "$BASELINE" ]]; then
    [[ -f "$BASELINE" ]] || die "Baseline file not found: $BASELINE"
    jq empty "$BASELINE" >/dev/null 2>&1 || die "Baseline is not valid JSON: $BASELINE"
fi

WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/assistant-context-budget.XXXXXX")"
trap safe_cleanup EXIT INT TERM
INSTALL_HOME="$WORK_ROOT/home"
mkdir -p "$INSTALL_HOME"

if ! HOME="$INSTALL_HOME" CODEX_HOME="$INSTALL_HOME/.codex" \
    bash "$REPO_ROOT/install.sh" \
        --agent "$AGENT" \
        --skill "$SKILL" \
        >"$WORK_ROOT/install.out" 2>"$WORK_ROOT/install.err"; then
    die "Isolated framework install failed; context inventory was not emitted."
fi

PROJECT_AGENTS_FILE="$REPO_ROOT/AGENTS.md"
GLOBAL_INSTRUCTIONS_FILE="$INSTALL_HOME/.codex/AGENTS.md"

GLOBAL_AGENTS_BLOCK="$WORK_ROOT/generated-global-agents.md"
extract_marker_block "$GLOBAL_INSTRUCTIONS_FILE" \
    ASSISTANT_FRAMEWORK_AGENTS_MD_START ASSISTANT_FRAMEWORK_AGENTS_MD_END \
    "$GLOBAL_AGENTS_BLOCK"

CATALOG_FILE="$WORK_ROOT/native-skill-catalog-descriptions.txt"
: >"$CATALOG_FILE"
while IFS= read -r relative_skill_file; do
    extract_skill_description "$REPO_ROOT/$relative_skill_file" >>"$CATALOG_FILE"
done < <(
    cd "$REPO_ROOT"
    find skills -mindepth 2 -maxdepth 2 -type f \
        -path 'skills/assistant-*/SKILL.md' -print | LC_ALL=C sort
)

SELECTED_INITIAL_FILE="$WORK_ROOT/selected-skill-initial.txt"
SELECTED_ENTRY_FILE="$WORK_ROOT/selected-skill-entry-boundary.txt"
SELECTED_ROOT_FILE="$SOURCE_SKILL_DIR/SKILL.md"
if [[ -n "$SKILL_OVERLAY" ]]; then
    SELECTED_ROOT_FILE="$SKILL_OVERLAY"
fi
build_selected_boundaries "$SOURCE_SKILL_DIR" "$SELECTED_INITIAL_FILE" "$SELECTED_ENTRY_FILE" "$SELECTED_ROOT_FILE"

if [[ -n "$SKILL_TREE" && -f "$SOURCE_SKILL_DIR/contracts/index.yaml" ]]; then
    TREE_ENTRY_FILE="$WORK_ROOT/materialized-tree-entry-boundary.txt"
    TREE_ENTRY_PROJECTION_FILE="$WORK_ROOT/materialized-tree-entry-projection.json"
    validate_static_load_set_and_project_workers "$SOURCE_SKILL_DIR" entry "$TREE_ENTRY_PROJECTION_FILE" "$TREE_ENTRY_FILE"
    cp "$TREE_ENTRY_FILE" "$SELECTED_ENTRY_FILE"
fi

LOAD_SET_CONTEXT_FILE=""
if [[ -n "$LOAD_SET" ]]; then
    LOAD_SET_DECLARED_FILE="$WORK_ROOT/selected-load-set-declared-boundary.txt"
    LOAD_SET_PROJECTION_FILE="$WORK_ROOT/worker-return-schema-projection.json"
    validate_static_load_set_and_project_workers "$SOURCE_SKILL_DIR" "$LOAD_SET" "$LOAD_SET_PROJECTION_FILE" "$LOAD_SET_DECLARED_FILE"
    read -r LOAD_SET_DECLARED_WORDS LOAD_SET_DECLARED_BYTES < <(measure_file "$LOAD_SET_DECLARED_FILE")
    WORKER_SELECTORS_RESOLVED="$(jq 'length' "$LOAD_SET_PROJECTION_FILE")"
    if [[ "$WORKER_SELECTORS_RESOLVED" -eq 0 ]]; then
        WORKER_PROJECTION_WORDS=0
        WORKER_PROJECTION_BYTES=0
    else
        read -r WORKER_PROJECTION_WORDS WORKER_PROJECTION_BYTES < <(measure_file "$LOAD_SET_PROJECTION_FILE")
    fi
    LOAD_SET_WORKER_CLOSURE_WORDS=$((LOAD_SET_DECLARED_WORDS + WORKER_PROJECTION_WORDS))
    LOAD_SET_WORKER_CLOSURE_BYTES=$((LOAD_SET_DECLARED_BYTES + WORKER_PROJECTION_BYTES))
    LOAD_SET_DECLARED_BUDGET="$(ruby -r yaml - "$SOURCE_SKILL_DIR/contracts/index.yaml" "$LOAD_SET" <<'RUBY'
document = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: false)
puts document.fetch("load_sets").fetch(ARGV.fetch(1)).fetch("budget_words")
RUBY
)"
    LOAD_SET_CONTEXT_FILE="$WORK_ROOT/selected-load-set-context.json"
    jq -n \
        --arg name "$LOAD_SET" \
        --argjson declared_budget_words "$LOAD_SET_DECLARED_BUDGET" \
        --argjson declared_words "$LOAD_SET_DECLARED_WORDS" \
        --argjson declared_bytes "$LOAD_SET_DECLARED_BYTES" \
        --argjson worker_selectors_resolved "$WORKER_SELECTORS_RESOLVED" \
        --argjson worker_projection_words "$WORKER_PROJECTION_WORDS" \
        --argjson worker_projection_bytes "$WORKER_PROJECTION_BYTES" \
        --argjson worker_closure_words "$LOAD_SET_WORKER_CLOSURE_WORDS" \
        --argjson worker_closure_bytes "$LOAD_SET_WORKER_CLOSURE_BYTES" '
        {
          name: $name,
          measurement_scope: "static_selected_skill_instruction_surface",
          declared_budget_words: $declared_budget_words,
          declared_boundary_closure: {words: $declared_words, bytes: $declared_bytes},
          transitive_worker_additions: {
            worker_return_schema_projection: {
              selectors_resolved: $worker_selectors_resolved,
              words: $worker_projection_words,
              bytes: $worker_projection_bytes
            }
          },
          worker_instruction_closure: {words: $worker_closure_words, bytes: $worker_closure_bytes}
        }
      ' >"$LOAD_SET_CONTEXT_FILE"
fi

read -r PROJECT_WORDS PROJECT_BYTES < <(measure_file "$PROJECT_AGENTS_FILE")
read -r GLOBAL_WORDS GLOBAL_BYTES < <(measure_file "$GLOBAL_AGENTS_BLOCK")
read -r CATALOG_WORDS CATALOG_BYTES < <(measure_file "$CATALOG_FILE")
CATALOG_CHARACTERS="$(wc -m <"$CATALOG_FILE" | tr -d ' ')"
read -r INITIAL_WORDS INITIAL_BYTES < <(measure_file "$SELECTED_INITIAL_FILE")
read -r ENTRY_WORDS ENTRY_BYTES < <(measure_file "$SELECTED_ENTRY_FILE")

STANDING_WORDS=$((PROJECT_WORDS + GLOBAL_WORDS + CATALOG_WORDS))
STANDING_BYTES=$((PROJECT_BYTES + GLOBAL_BYTES + CATALOG_BYTES))
TOTAL_INITIAL_WORDS=$((STANDING_WORDS + INITIAL_WORDS))
TOTAL_INITIAL_BYTES=$((STANDING_BYTES + INITIAL_BYTES))
TOTAL_ENTRY_WORDS=$((STANDING_WORDS + ENTRY_WORDS))
TOTAL_ENTRY_BYTES=$((STANDING_BYTES + ENTRY_BYTES))

REPORT_FILE="$WORK_ROOT/report.json"
OVERLAY_APPLIED=false
if [[ -n "$SKILL_OVERLAY" ]]; then
    OVERLAY_APPLIED=true
fi
jq -n \
    --arg agent "$AGENT" \
    --arg skill "$SKILL" \
    --arg inventory_mode "$INVENTORY_MODE" \
    --argjson overlay_applied "$OVERLAY_APPLIED" \
    --argjson project_words "$PROJECT_WORDS" \
    --argjson project_bytes "$PROJECT_BYTES" \
    --argjson global_words "$GLOBAL_WORDS" \
    --argjson global_bytes "$GLOBAL_BYTES" \
    --argjson catalog_words "$CATALOG_WORDS" \
    --argjson catalog_bytes "$CATALOG_BYTES" \
    --argjson catalog_characters "$CATALOG_CHARACTERS" \
    --argjson initial_words "$INITIAL_WORDS" \
    --argjson initial_bytes "$INITIAL_BYTES" \
    --argjson entry_words "$ENTRY_WORDS" \
    --argjson entry_bytes "$ENTRY_BYTES" \
    --argjson total_initial_words "$TOTAL_INITIAL_WORDS" \
    --argjson total_initial_bytes "$TOTAL_INITIAL_BYTES" \
    --argjson total_entry_words "$TOTAL_ENTRY_WORDS" \
    --argjson total_entry_bytes "$TOTAL_ENTRY_BYTES" '
    {
      schema_version: "2.0",
      agent: $agent,
      skill: $skill,
      inventory_mode: $inventory_mode,
      overlay_applied: $overlay_applied,
      components: {
        project_agents: {words: $project_words, bytes: $project_bytes},
        generated_global_agents: {words: $global_words, bytes: $global_bytes},
        native_skill_catalog_descriptions: {
          words: $catalog_words,
          bytes: $catalog_bytes,
          characters: $catalog_characters
        },
        selected_skill_initial: {words: $initial_words, bytes: $initial_bytes},
        selected_skill_entry_boundary: {words: $entry_words, bytes: $entry_bytes}
      },
      totals: {
        initial_words: $total_initial_words,
        initial_bytes: $total_initial_bytes,
        entry_boundary_words: $total_entry_words,
        entry_boundary_bytes: $total_entry_bytes
      }
    }
  ' >"$REPORT_FILE"

if [[ -n "$LOAD_SET_CONTEXT_FILE" ]]; then
    jq --slurpfile selected_load_set_context "$LOAD_SET_CONTEXT_FILE" \
        '. + {selected_load_set_context: $selected_load_set_context[0]}' \
        "$REPORT_FILE" >"$REPORT_FILE.next"
    mv "$REPORT_FILE.next" "$REPORT_FILE"
fi

if [[ -n "$BASELINE" ]]; then
    if ! jq -e '
      [
        .totals.initial_words,
        .totals.initial_bytes,
        .totals.entry_boundary_words,
        .totals.entry_boundary_bytes
      ] | all(.[]; type == "number")
    ' "$BASELINE" >/dev/null 2>&1; then
        die "Baseline is missing numeric totals."
    fi
    jq --slurpfile baseline "$BASELINE" '
      def delta($current; $old): $current - $old;
      def percent($current; $old):
        if $old == 0 then null else (($current - $old) / $old) * 100 end;
      . + {
        comparison: {
          absolute: {
            initial_words: delta(.totals.initial_words; $baseline[0].totals.initial_words),
            initial_bytes: delta(.totals.initial_bytes; $baseline[0].totals.initial_bytes),
            entry_boundary_words: delta(.totals.entry_boundary_words; $baseline[0].totals.entry_boundary_words),
            entry_boundary_bytes: delta(.totals.entry_boundary_bytes; $baseline[0].totals.entry_boundary_bytes)
          },
          percent: {
            initial_words: percent(.totals.initial_words; $baseline[0].totals.initial_words),
            initial_bytes: percent(.totals.initial_bytes; $baseline[0].totals.initial_bytes),
            entry_boundary_words: percent(.totals.entry_boundary_words; $baseline[0].totals.entry_boundary_words),
            entry_boundary_bytes: percent(.totals.entry_boundary_bytes; $baseline[0].totals.entry_boundary_bytes)
          }
        }
      }
    ' "$REPORT_FILE"
else
    cat "$REPORT_FILE"
fi
