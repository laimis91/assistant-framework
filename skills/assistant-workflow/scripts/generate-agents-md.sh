#!/usr/bin/env bash
# generate-agents-md.sh — Auto-generates project context files for AI agents.
#
# Inspects the repository to capture architecture, conventions, build commands,
# dependency rules, and file structure. Outputs CLAUDE.md, AGENTS.md, or both.
#
# Usage:
#   ./scripts/generate-agents-md.sh                          # defaults to CLAUDE.md
#   ./scripts/generate-agents-md.sh --format agents          # AGENTS.md only
#   ./scripts/generate-agents-md.sh --format both            # both files
#   ./scripts/generate-agents-md.sh --format claude --output custom-name.md
#   ./scripts/generate-agents-md.sh --dry-run
#
# Prerequisites: git
# Optional: jq (for package.json parsing), dotnet (for .NET detection)

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────

FORMAT="claude"
OUTPUT=""
DRY_RUN=false
REPO="."

# ── Parse args ────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Generates project context files for AI coding agents.

Options:
  --format FORMAT  Which file(s) to generate: claude, agents, or both (default: claude)
                     claude  → CLAUDE.md  (auto-loaded by Claude Code)
                     agents  → AGENTS.md  (auto-loaded by Codex CLI)
                     both    → generates both files
  --output FILE    Override output filename (only valid with claude or agents, not both)
  --repo PATH      Repository root (default: current directory)
  --dry-run        Print to stdout instead of writing file
  -h, --help       Show this help

Examples:
  $(basename "$0")                                # → CLAUDE.md
  $(basename "$0") --format agents                # → AGENTS.md
  $(basename "$0") --format both                  # → CLAUDE.md + AGENTS.md
  $(basename "$0") --format claude --output docs/CLAUDE.md
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --format)   [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; FORMAT="$2"; shift 2 ;;
        --output)   [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; OUTPUT="$2"; shift 2 ;;
        --repo)     [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; REPO="$2"; shift 2 ;;
        --dry-run)  DRY_RUN=true; shift ;;
        -h|--help)  usage ;;
        *)          echo "Unknown option: $1"; usage ;;
    esac
done

# ── Validate ──────────────────────────────────────────────────────────────────

info() { echo "ℹ️  $1" >&2; }
ok()   { echo "✅ $1" >&2; }
fail() { echo "❌ $1" >&2; exit 1; }

case "$FORMAT" in
    claude|agents|both) ;;
    *) fail "Invalid --format: $FORMAT. Must be: claude, agents, or both." ;;
esac

if [[ -n "$OUTPUT" && "$FORMAT" == "both" ]]; then
    fail "--output cannot be used with --format both (two files are generated)."
fi

cd "$REPO"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    fail "Not a git repository: $REPO"
fi

PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT"

# ── Detect project type ──────────────────────────────────────────────────────

detect_project_type() {
    local types=()

    # .NET
    if ls *.sln >/dev/null 2>&1 || find . -maxdepth 3 -name "*.csproj" -print -quit | grep -q .; then
        types+=("dotnet")
        if grep -rq "Blazor" --include="*.csproj" . 2>/dev/null; then
            types+=("blazor")
        fi
        if grep -rq "Microsoft.Maui" --include="*.csproj" . 2>/dev/null; then
            types+=("maui")
        fi
        if grep -rq "Microsoft.AspNetCore" --include="*.csproj" . 2>/dev/null; then
            types+=("aspnet")
        fi
    fi

    # Node.js
    if [[ -f "package.json" ]]; then
        types+=("node")
        if [[ -f "next.config.js" ]] || [[ -f "next.config.mjs" ]] || [[ -f "next.config.ts" ]]; then
            types+=("nextjs")
        fi
        if grep -q '"react"' package.json 2>/dev/null; then
            types+=("react")
        fi
    fi

    # Unity
    if [[ -d "Assets" ]] && [[ -f "ProjectSettings/ProjectVersion.txt" ]]; then
        types+=("unity")
    fi

    # ESP32 / PlatformIO
    if [[ -f "platformio.ini" ]]; then
        types+=("esp32")
    fi

    # Python
    if [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]] || [[ -f "requirements.txt" ]]; then
        types+=("python")
        if grep -q "fastapi" pyproject.toml 2>/dev/null || grep -q "fastapi" requirements.txt 2>/dev/null; then
            types+=("fastapi")
        fi
    fi

    # Rust
    if [[ -f "Cargo.toml" ]]; then
        types+=("rust")
    fi

    # Go
    if [[ -f "go.mod" ]]; then
        types+=("go")
    fi

    # Static site
    if [[ -f "index.html" ]] && [[ ! -f "package.json" ]]; then
        types+=("static")
    fi

    if [[ ${#types[@]} -eq 0 ]]; then
        types+=("unknown")
    fi

    echo "${types[*]}"
}

# ── Detect architecture pattern ───────────────────────────────────────────────

detect_architecture() {
    local types="$1"
    local arch="Not determined"

    if [[ -d "src/Domain" ]] || [[ -d "src/Core" ]] || [[ -d "Domain" ]]; then
        if [[ -d "src/Application" ]] || [[ -d "Application" ]]; then
            arch="Clean Architecture (Onion)"
        fi
    fi

    if find . -maxdepth 4 -name "*ViewModel*" -print -quit 2>/dev/null | grep -q .; then
        if [[ "$arch" == *"Clean"* ]]; then
            arch="$arch + MVVM"
        else
            arch="MVVM"
        fi
    fi

    if [[ "$types" == *"unity"* ]]; then
        if find . -name "*.asmdef" -print -quit 2>/dev/null | grep -q .; then
            arch="Clean Architecture with asmdef layering"
        else
            arch="Unity (standard)"
        fi
    fi

    if [[ "$types" == *"esp32"* ]]; then
        if [[ -d "lib" ]] || [[ -d "src/hal" ]] || [[ -d "src/services" ]]; then
            arch="Layered (HAL → Services → App → main)"
        fi
    fi

    echo "$arch"
}

# ── Detect build & test commands ──────────────────────────────────────────────

detect_build_cmd() {
    local types="$1"
    if [[ "$types" == *"dotnet"* ]]; then
        local sln
        sln=$(ls *.sln 2>/dev/null | head -1)
        if [[ -n "$sln" ]]; then
            echo "dotnet build $sln"
        else
            echo "dotnet build"
        fi
    elif [[ "$types" == *"node"* ]]; then
        echo "npm run build"
    elif [[ "$types" == *"esp32"* ]]; then
        echo "pio run"
    elif [[ "$types" == *"python"* ]]; then
        echo "# No build step (interpreted)"
    elif [[ "$types" == *"rust"* ]]; then
        echo "cargo build"
    elif [[ "$types" == *"go"* ]]; then
        echo "go build ./..."
    else
        echo "# TODO: add build command"
    fi
}

detect_test_cmd() {
    local types="$1"
    if [[ "$types" == *"dotnet"* ]]; then
        echo "dotnet test"
    elif [[ "$types" == *"node"* ]]; then
        echo "npm test"
    elif [[ "$types" == *"esp32"* ]]; then
        echo "pio test"
    elif [[ "$types" == *"python"* ]]; then
        if [[ -f "pyproject.toml" ]] && grep -q "pytest" pyproject.toml 2>/dev/null; then
            echo "pytest"
        else
            echo "python -m pytest"
        fi
    elif [[ "$types" == *"rust"* ]]; then
        echo "cargo test"
    elif [[ "$types" == *"go"* ]]; then
        echo "go test ./..."
    else
        echo "# TODO: add test command"
    fi
}

# ── Generate file structure ───────────────────────────────────────────────────

generate_file_structure() {
    find . -maxdepth 2 -type d \
        -not -path "./.git*" \
        -not -path "./node_modules*" \
        -not -path "./bin*" \
        -not -path "./obj*" \
        -not -path "./.vs*" \
        -not -path "./.idea*" \
        -not -path "./Library*" \
        -not -path "./Temp*" \
        -not -path "./Logs*" \
        -not -path "./.pio*" \
        -not -path "./dist*" \
        -not -path "./build*" \
        -not -path "./__pycache__*" \
        -not -path "./.venv*" \
        -not -path "./target*" \
        -not -path "./.worktrees*" \
        2>/dev/null | sort | head -40 | sed 's|^\./||' | sed 's|^|  |'
}

# ── Detect dependency rules ──────────────────────────────────────────────────

detect_dependency_rules() {
    local types="$1"
    local arch="$2"
    local rules=""

    if [[ "$arch" == *"Clean"* ]]; then
        rules="- Domain layer has no external dependencies (no framework, no infrastructure references)
- Application layer depends only on Domain
- Infrastructure implements Application interfaces
- UI/Presentation depends on Application, never directly on Infrastructure
- Dependency injection wires Infrastructure to Application interfaces at composition root"
    fi

    if [[ "$types" == *"unity"* ]] && [[ "$arch" == *"asmdef"* ]]; then
        rules="$rules
- Assembly definitions (asmdef) enforce layer boundaries at compile time
- Game logic assemblies must not reference Unity Editor assemblies
- Shared contracts in a dedicated assembly referenced by all layers"
    fi

    if [[ -z "$rules" ]]; then
        rules="- No specific dependency rules detected — define as project matures"
    fi

    echo "$rules"
}

# ── Detect key conventions ────────────────────────────────────────────────────

detect_conventions() {
    local conventions=""

    if find . -maxdepth 4 -name "I*.cs" -print -quit 2>/dev/null | grep -q .; then
        conventions="$conventions
- Interface naming: prefix with I (e.g., IOrderService)"
    fi

    if find . -maxdepth 4 -name "*Tests.cs" -print -quit 2>/dev/null | grep -q .; then
        conventions="$conventions
- Test class naming: {ClassName}Tests"
    fi

    if find . -maxdepth 4 \( -name "*.test.ts" -o -name "*.test.js" -o -name "*.spec.ts" -o -name "*.spec.js" \) 2>/dev/null | head -1 | grep -q .; then
        conventions="$conventions
- Test file naming: {name}.test.{ext} or {name}.spec.{ext}"
    fi

    local last_commits
    last_commits=$(git log --oneline -10 2>/dev/null || echo "")
    if echo "$last_commits" | grep -qiE "^[a-f0-9]+ (feat|fix|chore|docs|refactor|test|style|perf)\b"; then
        conventions="$conventions
- Commit messages: Conventional Commits (feat:, fix:, chore:, etc.)"
    fi

    if [[ -f "appsettings.json" ]] || find . -maxdepth 3 -name "appsettings.json" -print -quit 2>/dev/null | grep -q .; then
        conventions="$conventions
- Configuration: appsettings.json with environment overrides"
    fi

    if [[ -f ".env.example" ]] || [[ -f ".env.sample" ]]; then
        conventions="$conventions
- Environment variables: documented in .env.example"
    fi

    if [[ -f ".editorconfig" ]]; then
        conventions="$conventions
- Code style: enforced via .editorconfig"
    fi

    if [[ -f ".prettierrc" ]] || [[ -f ".prettierrc.json" ]]; then
        conventions="$conventions
- Code formatting: Prettier"
    fi

    if [[ -f ".eslintrc.json" ]] || [[ -f ".eslintrc.js" ]] || [[ -f "eslint.config.js" ]]; then
        conventions="$conventions
- Linting: ESLint"
    fi

    if [[ -z "$conventions" ]]; then
        conventions="
- No specific conventions detected — define as project matures"
    fi

    echo "$conventions"
}

# ── Build the document body (format-agnostic) ────────────────────────────────

info "Inspecting project..."

PROJECT_TYPES=$(detect_project_type)
ARCHITECTURE=$(detect_architecture "$PROJECT_TYPES")
BUILD_CMD=$(detect_build_cmd "$PROJECT_TYPES")
TEST_CMD=$(detect_test_cmd "$PROJECT_TYPES")
DEP_RULES=$(detect_dependency_rules "$PROJECT_TYPES" "$ARCHITECTURE")
CONVENTIONS=$(detect_conventions)
FILE_STRUCTURE=$(generate_file_structure)
PROJECT_NAME=$(basename "$PROJECT_ROOT")
GENERATED_DATE=$(date +%Y-%m-%d)

# Try to get description from README
DESCRIPTION=""
if [[ -f "README.md" ]]; then
    DESCRIPTION=$(grep -m1 -vE '^(#|$|\s*$)' README.md 2>/dev/null | head -1 || echo "")
fi
[[ -z "$DESCRIPTION" ]] && DESCRIPTION="TODO: Add project description"

# ── Detect assistant-workflow skill ───────────────────────────────────────────

WORKFLOW_SECTION=""
# Check global skill install locations for any supported agent
for agent_dir in "$HOME/.claude" "$HOME/.codex" "$HOME/.gemini"; do
    if [[ -f "$agent_dir/skills/assistant-workflow/SKILL.md" ]]; then
        WORKFLOW_SECTION="
## Development Workflow

This project uses the AI-Assisted Development Workflow (assistant-workflow skill).
Follow it for all code changes: Triage → Discover → Plan → [Design] → Build & Test → Document.

Key rules:
- Never guess — ask before assuming
- Plan before coding — get approval before implementation
- One step at a time — build + test after each plan step
- Flag deviations — stop if reality doesn't match the plan"
        info "Detected assistant-workflow skill — adding workflow section."
        break
    fi
done

# ── Generate content for a given format ───────────────────────────────────────

generate_content() {
    local fmt="$1"   # "claude" or "agents"

    local title
    local subtitle
    case "$fmt" in
        claude)
            title="CLAUDE.md"
            subtitle="Project context for Claude Code. Auto-generated — edit to refine."
            ;;
        agents)
            title="AGENTS.md"
            subtitle="Project context for AI coding agents. Auto-generated — edit to refine."
            ;;
    esac

    cat <<EOF
# $title

> $subtitle

## Project

- **Name:** $PROJECT_NAME
- **Description:** $DESCRIPTION
- **Type:** $PROJECT_TYPES
- **Generated:** $GENERATED_DATE

## Architecture

**Pattern:** $ARCHITECTURE

### Dependency rules

$DEP_RULES

## Build & Test

\`\`\`bash
# Build
$BUILD_CMD

# Test
$TEST_CMD
\`\`\`

## File Structure

\`\`\`
$FILE_STRUCTURE
\`\`\`

## Key Conventions
$CONVENTIONS

## AI Agent Instructions

When working on this project:

1. **Read this file first** before making any changes
2. **Respect layer boundaries** — see dependency rules above
3. **Run build + test** after every change: \`$BUILD_CMD && $TEST_CMD\`
4. **Follow existing patterns** — check nearby files before creating new ones
5. **No hardcoded secrets** — use configuration / environment variables
6. **Ask before adding dependencies** — justify new packages
$WORKFLOW_SECTION

## Notes

<!-- Add project-specific notes, gotchas, and tribal knowledge here -->
<!-- Examples:
- The legacy OrderService uses a different pattern — don't copy it
- Auth tokens expire every 30 min in dev, 24h in prod
- The /api/v1/ endpoints are frozen — all new work goes in /api/v2/
-->
EOF
}

# ── Write a single file ──────────────────────────────────────────────────────

write_file() {
    local fmt="$1"
    local output_path="$2"
    local content
    content=$(generate_content "$fmt")

    if $DRY_RUN; then
        echo "$content"
        info "Dry run ($output_path) — nothing written."
    else
        echo "$content" > "$output_path"
        ok "Generated: $output_path"
    fi
}

# ── Output ────────────────────────────────────────────────────────────────────

case "$FORMAT" in
    claude)
        [[ -z "$OUTPUT" ]] && OUTPUT="CLAUDE.md"
        write_file "claude" "$OUTPUT"
        ;;
    agents)
        [[ -z "$OUTPUT" ]] && OUTPUT="AGENTS.md"
        write_file "agents" "$OUTPUT"
        ;;
    both)
        write_file "claude" "CLAUDE.md"
        write_file "agents" "AGENTS.md"
        ;;
esac

info "Review and edit the file(s) to add project-specific knowledge."
