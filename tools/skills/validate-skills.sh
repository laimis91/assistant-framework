#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

INCLUDE_LOCAL=false
LIST_ONLY=false
SKILL_SELECTORS=()
SKILL_FILES=()
FAILURES=0

source "$SCRIPT_DIR/lib/validate-common.sh"
source "$SCRIPT_DIR/lib/validate-inventory.sh"
source "$SCRIPT_DIR/lib/validate-frontmatter.sh"
source "$SCRIPT_DIR/lib/validate-contracts.sh"

usage() {
    cat <<'EOF'
Usage:
  validate-skills.sh [--include-local] [--list]
  validate-skills.sh --skill NAME|PATH [--skill NAME|PATH ...]
  validate-skills.sh --help

Validates Assistant Framework skill metadata and contract files.

Options:
  --skill NAME|PATH   Validate a specific skill by name, skill directory, or SKILL.md path.
  --include-local     Include every skills/*/SKILL.md in the default inventory.
  --list              Print selected skill names and exit.
  -h, --help          Show this help.

Default inventory validates first-class release skills only:
  skills/assistant-*/SKILL.md
EOF
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --skill)
            if [[ "$#" -lt 2 ]]; then
                printf 'ERROR [ARGS] --skill requires NAME or PATH\n' >&2
                exit 2
            fi
            SKILL_SELECTORS+=("$2")
            shift 2
            ;;
        --include-local)
            INCLUDE_LOCAL=true
            shift
            ;;
        --list)
            LIST_ONLY=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'ERROR [ARGS] unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

load_selected_inventory

if [[ "$LIST_ONLY" == true ]]; then
    for skill_file in "${SKILL_FILES[@]:-}"; do
        printf '%s\n' "$(basename -- "$(dirname -- "$skill_file")")"
    done
    exit 0
fi

if [[ "${#SKILL_FILES[@]}" -eq 0 ]]; then
    record_error "INVENTORY_EMPTY" "$REPO_ROOT/skills" "no skills found in selected inventory"
else
    for skill_file in "${SKILL_FILES[@]}"; do
        validate_skill "$skill_file"
    done
fi

if [[ "$FAILURES" -gt 0 ]]; then
    printf 'FAILED skill validation: %s error(s) across %s skill(s)\n' "$FAILURES" "${#SKILL_FILES[@]}" >&2
    exit 1
fi

printf 'OK skill validation: %s skill(s) validated\n' "${#SKILL_FILES[@]}"
