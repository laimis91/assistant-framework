#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENTS_DIR="${ROLE_PROMPTS_AGENTS_DIR:-$REPO_ROOT/agents}"
SKILLS_DIR="${ROLE_PROMPTS_SKILLS_DIR:-$REPO_ROOT/skills}"

# role:owning-skill. Each role prompt is written to
# skills/<owning-skill>/references/roles/<role>.md (R-MP-2).
ROLE_TARGETS=(
    code-reviewer:assistant-review
    qa-evaluator:assistant-review
    reviewer:assistant-review
    lens-researcher:assistant-research
    research-peer-reviewer:assistant-research
    architect:assistant-workflow
    builder-tester:assistant-workflow
    code-mapper:assistant-workflow
    explorer:assistant-workflow
    intelligent-writer:assistant-workflow
    mechanical-writer:assistant-workflow
)

# "role|reason" entries exempt a role from the Codex developer_instructions
# parity check only. Every entry must name the role and the reason (D-MP-5).
CODEX_PARITY_EXCEPTIONS=()

usage() {
    cat <<'EOF'
Usage: sync-role-prompts.sh --apply|--check

Write each formal role prompt into its owning skill's references/roles/ folder
from the Markdown body of agents/claude/<role>.md (frontmatter removed).
--check fails when a role prompt is missing or differs from that body, when
agents/codex/<role>.toml developer_instructions differ from it after line-ending
and trailing-whitespace normalization, or when a role prompt contains a literal
.claude/ or .codex/ path. Edit only agents/claude and agents/codex, then --apply.
EOF
}

die() {
    echo "Error: $1" >&2
    exit 1
}

# Markdown body of a Claude agent file: everything after the closing
# frontmatter fence, without leading blank lines.
claude_body() {
    awk '
        { line = $0; sub(/[[:space:]]+$/, "", line) }
        NR == 1 && line == "---" { in_front = 1; next }
        in_front && line == "---" { in_front = 0; started = 0; next }
        in_front { next }
        !started && $0 ~ /^[[:space:]]*$/ { next }
        { started = 1; print }
    ' "$1"
}

# developer_instructions text of a Codex agent file (multi-line basic string).
codex_body() {
    awk '
        { line = $0; sub(/[[:space:]]+$/, "", line) }
        line == "developer_instructions = \"\"\"" { active = 1; next }
        active && line == "\"\"\"" { exit }
        active { print }
    ' "$1"
}

normalize() {
    tr -d '\r' | sed -e 's/[[:space:]]*$//'
}

header_for() {
    printf '<!-- Generated from agents/claude/%s.md by tools/skills/sync-role-prompts.sh; edit the agent files, then run it with --apply. -->\n\n' "$1"
}

expected_prompt() {
    header_for "$1"
    claude_body "$AGENTS_DIR/claude/$1.md"
}

is_codex_parity_exception() {
    local entry
    for entry in ${CODEX_PARITY_EXCEPTIONS[@]+"${CODEX_PARITY_EXCEPTIONS[@]}"}; do
        [[ "${entry%%|*}" == "$1" ]] && return 0
    done
    return 1
}

for entry in ${CODEX_PARITY_EXCEPTIONS[@]+"${CODEX_PARITY_EXCEPTIONS[@]}"}; do
    [[ "$entry" == *"|"* && -n "${entry%%|*}" && -n "${entry#*|}" ]] \
        || die "exception entry must name the role and the reason as role|reason: $entry"
done

for target in "${ROLE_TARGETS[@]}"; do
    role="${target%%:*}"
    skill="${target#*:}"
    [[ -f "$AGENTS_DIR/claude/$role.md" ]] || die "Claude agent file is missing: $AGENTS_DIR/claude/$role.md"
    [[ -f "$AGENTS_DIR/codex/$role.toml" ]] || die "Codex agent file is missing: $AGENTS_DIR/codex/$role.toml"
    [[ -f "$SKILLS_DIR/$skill/SKILL.md" ]] || die "owning skill is missing: $SKILLS_DIR/$skill"
done

case "${1:-}" in
    --apply)
        for target in "${ROLE_TARGETS[@]}"; do
            role="${target%%:*}"
            skill="${target#*:}"
            mkdir -p "$SKILLS_DIR/$skill/references/roles"
            expected_prompt "$role" >"$SKILLS_DIR/$skill/references/roles/$role.md"
        done
        echo "synced ${#ROLE_TARGETS[@]} role prompts"
        ;;
    --check)
        problems=()
        for target in "${ROLE_TARGETS[@]}"; do
            role="${target%%:*}"
            skill="${target#*:}"
            prompt="$SKILLS_DIR/$skill/references/roles/$role.md"
            relative="$skill/references/roles/$role.md"
            if [[ ! -f "$prompt" ]]; then
                problems+=("missing: $relative")
                continue
            fi
            if ! cmp -s <(expected_prompt "$role") "$prompt"; then
                problems+=("drifted from agents/claude/$role.md: $relative")
            fi
            if grep -Eq '\.(claude|codex)/' "$prompt"; then
                problems+=("literal .claude/ or .codex/ path: $relative")
            fi
            if ! is_codex_parity_exception "$role" \
                && ! cmp -s <(claude_body "$AGENTS_DIR/claude/$role.md" | normalize) \
                    <(codex_body "$AGENTS_DIR/codex/$role.toml" | normalize); then
                problems+=("agents/codex/$role.toml developer_instructions differ from agents/claude/$role.md")
            fi
        done
        if [[ ${#problems[@]} -gt 0 ]]; then
            printf '%s\n' "${problems[@]}" >&2
            die "role prompts are out of date or diverged; reconcile the agent files, then run tools/skills/sync-role-prompts.sh --apply"
        fi
        echo "checked ${#ROLE_TARGETS[@]} role prompts"
        ;;
    -h|--help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
