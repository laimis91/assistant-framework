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
INVENTORY_MODE="isolated_install"

usage() {
    cat <<'EOF'
Usage:
  context-budget-report.sh --agent AGENT --skill SKILL --format json [--baseline FILE] [--skill-overlay FILE]

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

collect_entry_index_rows() {
    local index_file="$1"
    awk '
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
      /^  entry:[[:space:]]*$/ { in_entry = 1; next }
      in_entry && /^  [[:alnum:]_-]+:[[:space:]]*$/ { flush_selector(); exit }
      !in_entry { next }
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
      END { if (in_entry) flush_selector() }
    ' "$index_file"
}

append_selected_contract_items() {
    local contract_file="$1"
    local section="$2"
    local key="$3"
    local names="$4"
    local destination="$5"

    [[ -f "$contract_file" && -n "$section" && -n "$key" && -n "$names" ]] || return
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
    local index_file="$skill_dir/contracts/index.yaml"

    : >"$initial_file"
    cat "$root_file" >>"$initial_file"
    if [[ -f "$index_file" ]]; then
        cat "$index_file" >>"$initial_file"
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
                    cat "$candidate" >>"$entry_file"
                fi
                ;;
            selector)
                if [[ -f "$candidate" && "$(cd "$(dirname "$candidate")" && pwd -P)/$(basename "$candidate")" == "$canonical_skill"/* ]]; then
                    append_selected_contract_items "$candidate" "$field2" "$field3" "$field4" "$entry_file"
                fi
                ;;
        esac
    done < <(collect_entry_index_rows "$index_file")
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
