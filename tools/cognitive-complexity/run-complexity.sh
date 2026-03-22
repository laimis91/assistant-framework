#!/usr/bin/env bash
# run-complexity.sh — Run cognitive complexity analysis on C# files.
#
# Usage:
#   run-complexity.sh [options] <files...>
#   run-complexity.sh --changed              # analyze git-changed .cs files
#   run-complexity.sh --changed --base main  # changed vs specific base
#
# Options:
#   --changed          Analyze only git-changed .cs files
#   --base BRANCH      Base branch for --changed (default: auto-detect)
#   --threshold N      Complexity threshold for warnings (default: 15)
#   --verbose          Show per-line breakdown
#   --build            Force rebuild of the tool
#   -h, --help         Show this help
#
# Exit codes:
#   0  All functions within threshold (or no .cs files to analyze)
#   1  Error (build failed, file not found, etc.)
#   2  One or more functions exceed threshold
#
# Requires: .NET SDK 8.0+. Builds once on first run, reuses cached binary after.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_FILE="$SCRIPT_DIR/CognitiveComplexity.csproj"
PUBLISH_DIR="$SCRIPT_DIR/.publish"
TOOL_DLL="$PUBLISH_DIR/CognitiveComplexity.dll"

# Defaults
THRESHOLD=15
VERBOSE=false
CHANGED=false
BASE_BRANCH=""
FORCE_BUILD=false
FILES=()

# ── Argument parsing ──────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --changed)    CHANGED=true; shift ;;
        --base)       [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }; BASE_BRANCH="$2"; shift 2 ;;
        --threshold)  [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }; THRESHOLD="$2"; shift 2 ;;
        --verbose)    VERBOSE=true; shift ;;
        --build)      FORCE_BUILD=true; shift ;;
        -h|--help)    head -22 "$0" | tail -20; exit 0 ;;
        -*)           echo "Unknown option: $1" >&2; exit 1 ;;
        *)            FILES+=("$1"); shift ;;
    esac
done

# ── Validate inputs ──────────────────────────────────────────────────────

[[ "$THRESHOLD" =~ ^[0-9]+$ ]] || { echo "Error: --threshold must be a positive integer, got '$THRESHOLD'" >&2; exit 1; }

# ── Build tool if needed ──────────────────────────────────────────────────

if [[ ! -f "$TOOL_DLL" ]] || $FORCE_BUILD; then
    command -v dotnet >/dev/null 2>&1 || {
        echo "Error: dotnet SDK 8.0+ is required. Install from https://dot.net/download" >&2
        exit 1
    }

    echo "Building cognitive complexity tool..." >&2
    mkdir -p "$PUBLISH_DIR"
    dotnet publish "$PROJECT_FILE" \
        -c Release \
        -o "$PUBLISH_DIR" \
        --nologo \
        -v quiet \
        2>&1 >&2 || {
        echo "Error: Failed to build cognitive complexity tool" >&2
        exit 1
    }
    echo "Tool built successfully." >&2
fi

# ── Collect files ─────────────────────────────────────────────────────────

if $CHANGED; then
    if [[ -z "$BASE_BRANCH" ]]; then
        # Auto-detect: try main, then master, then fall back to HEAD~1
        if git rev-parse --verify main >/dev/null 2>&1; then
            BASE_BRANCH="main"
        elif git rev-parse --verify master >/dev/null 2>&1; then
            BASE_BRANCH="master"
        else
            BASE_BRANCH="HEAD~1"
        fi
    fi

    # Get changed .cs files (both committed and uncommitted)
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            FILES+=("$file")
        fi
    done < <(
        {
            git diff --name-only "$BASE_BRANCH"...HEAD 2>/dev/null || true
            git diff --name-only 2>/dev/null || true
            git diff --name-only --cached 2>/dev/null || true
        } | grep '\.cs$' | sort -u
    )
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "No .cs files to analyze." >&2
    exit 0
fi

# ── Run analysis ──────────────────────────────────────────────────────────

TOOL_ARGS=(-t "$THRESHOLD")
if $VERBOSE; then
    TOOL_ARGS+=(-v)
fi

dotnet "$TOOL_DLL" "${TOOL_ARGS[@]}" "${FILES[@]}"
