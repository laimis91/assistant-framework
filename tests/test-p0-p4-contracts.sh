#!/usr/bin/env bash
# Focused P0-P4 regression checks for installer idempotence and instruction contracts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
P0P4_SUITE_DIR="$SCRIPT_DIR/p0-p4"

source "$P0P4_SUITE_DIR/lib/p0p4-harness.sh"
source "$P0P4_SUITE_DIR/repo-guard-contracts.sh"
source "$P0P4_SUITE_DIR/installer-contracts.sh"
source "$P0P4_SUITE_DIR/codex-hook-reinstall-contracts.sh"
source "$P0P4_SUITE_DIR/skill-install-path-substitution-contracts.sh"
source "$P0P4_SUITE_DIR/installed-hook-smoke.sh"
source "$P0P4_SUITE_DIR/skill-instruction-quality-contracts.sh"
source "$P0P4_SUITE_DIR/skill-validator-contracts.sh"
source "$P0P4_SUITE_DIR/skill-eval-contracts.sh"
source "$P0P4_SUITE_DIR/plugin-boundary-contracts.sh"
source "$P0P4_SUITE_DIR/workflow-basics-contracts.sh"
source "$P0P4_SUITE_DIR/tdd-contracts.sh"
source "$P0P4_SUITE_DIR/task-packet-contracts.sh"
source "$P0P4_SUITE_DIR/spec-review-contracts.sh"
source "$P0P4_SUITE_DIR/runtime-phase-gate-contracts.sh"
source "$P0P4_SUITE_DIR/worker-status-contracts.sh"
source "$P0P4_SUITE_DIR/worker-prompt-contracts.sh"
source "$P0P4_SUITE_DIR/memory-doc-contracts.sh"
source "$P0P4_SUITE_DIR/docs-drift-contracts.sh"
source "$P0P4_SUITE_DIR/eval-contracts.sh"

finish
