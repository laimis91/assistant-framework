#!/usr/bin/env bash
# Provider-neutral local runner for Assistant Framework per-skill eval fixtures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MODE=""
OUTPUT_DIR=""
RESPONSES_DIR=""
INCLUDE_LOCAL=false
SKILL_SELECTORS=()
SKILL_NAMES=()
SKILL_FILES=()
FIXTURE_FILES=()

source "$SCRIPT_DIR/lib/skill-eval-common.sh"
source "$SCRIPT_DIR/lib/skill-eval-inventory.sh"
source "$SCRIPT_DIR/lib/skill-eval-fixtures.sh"
source "$SCRIPT_DIR/lib/skill-eval-render.sh"
source "$SCRIPT_DIR/lib/skill-eval-grade.sh"

usage() {
    cat <<'EOF'
Usage:
  run-skill-evals.sh --validate-fixture [--skill NAME|PATH ...] [--include-local]
  run-skill-evals.sh --list [--skill NAME|PATH ...] [--include-local]
  run-skill-evals.sh --emit-prompts DIR [--skill NAME|PATH ...] [--include-local]
  run-skill-evals.sh --responses DIR [--skill NAME|PATH ...] [--include-local]
  run-skill-evals.sh --help

Runs offline, provider-neutral helpers for skill-local eval fixtures:
  skills/<skill>/evals/cases.json

No provider SDKs, network calls, or model APIs are used.

Options:
  --skill NAME|PATH   Select a skill by name, skill directory, or SKILL.md path.
                      May be specified more than once.
  --include-local     Include every skills/*/SKILL.md with evals/cases.json in
                      the default inventory. Without this, only first-class
                      skills/assistant-*/SKILL.md fixtures are selected.
  --validate-fixture  Validate selected fixture schemas and case shapes.
  --list              Print skill, case id, category, and title as tab-separated lines.
  --emit-prompts DIR  Write one Markdown prompt packet per case under DIR/<skill>/.
  --responses DIR     Heuristically grade local response files from DIR.
  -h, --help          Show this help.

Fixture schema:
  Each fixture must include provider-neutral suite metadata, skill identity via
  skill, skill.name, or skill_name, and cases matching docs/evals framework
  fixture case fields, including non-empty machine_expectations
  required/forbidden arrays.
EOF
}

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --validate-fixture)
            [[ -z "$MODE" ]] || die "Only one mode may be specified."
            MODE="validate"
            shift
            ;;
        --list)
            [[ -z "$MODE" ]] || die "Only one mode may be specified."
            MODE="list"
            shift
            ;;
        --emit-prompts)
            [[ -z "$MODE" ]] || die "Only one mode may be specified."
            [[ $# -ge 2 ]] || die "Missing directory for --emit-prompts."
            MODE="emit"
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --responses)
            [[ -z "$MODE" ]] || die "Only one mode may be specified."
            [[ $# -ge 2 ]] || die "Missing directory for --responses."
            MODE="responses"
            RESPONSES_DIR="$2"
            shift 2
            ;;
        --skill)
            [[ $# -ge 2 ]] || die "Missing NAME or PATH for --skill."
            SKILL_SELECTORS+=("$2")
            shift 2
            ;;
        --include-local)
            INCLUDE_LOCAL=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

load_selected_inventory

case "$MODE" in
    validate)
        validate_all_fixtures
        for index in "${!FIXTURE_FILES[@]}"; do
            echo "Fixture valid: $(display_path "${FIXTURE_FILES[$index]}")"
        done
        echo "OK skill eval fixtures: ${#FIXTURE_FILES[@]} fixture(s) validated"
        ;;
    list)
        list_cases
        ;;
    emit)
        emit_prompts
        ;;
    responses)
        grade_responses
        ;;
    *)
        die "No mode specified."
        ;;
esac
