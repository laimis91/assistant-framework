#!/usr/bin/env bash
# Focused P0-P4 regression checks for installer idempotence and instruction contracts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
P0P4_SUITE_DIR="$SCRIPT_DIR/p0-p4"

source "$P0P4_SUITE_DIR/lib/p0p4-harness.sh"

p0p4_suite_is_excluded() {
    local suite_name="$1"
    case " ${P0P4_EXCLUDED_SUITES:-} " in
        *" $suite_name "*) return 0 ;;
        *) return 1 ;;
    esac
}

source "$P0P4_SUITE_DIR/repo-guard-contracts.sh"
source "$P0P4_SUITE_DIR/harness-controller-contracts.sh"
source "$P0P4_SUITE_DIR/installer-contracts.sh"
source "$P0P4_SUITE_DIR/windows-installer-contracts.sh"
source "$P0P4_SUITE_DIR/hook-retirement-contracts.sh"
source "$P0P4_SUITE_DIR/sol-native-overhead-contracts.sh"
source "$P0P4_SUITE_DIR/review-round1-regressions.sh"
source "$P0P4_SUITE_DIR/skill-install-path-substitution-contracts.sh"
source "$P0P4_SUITE_DIR/skill-instruction-quality-contracts.sh"
source "$P0P4_SUITE_DIR/skill-activation-precision-contracts.sh"
source "$P0P4_SUITE_DIR/progressive-specialist-contracts.sh"
source "$P0P4_SUITE_DIR/skill-contract-guide-sync.sh"
source "$P0P4_SUITE_DIR/assistant-ideate-reference-contracts.sh"
source "$P0P4_SUITE_DIR/assistant-review-reference-contracts.sh"
source "$P0P4_SUITE_DIR/assistant-research-contracts.sh"
source "$P0P4_SUITE_DIR/domain-rubrics-contracts.sh"
source "$P0P4_SUITE_DIR/qa-evaluator-contracts.sh"
source "$P0P4_SUITE_DIR/review-loop-cap-contracts.sh"
source "$P0P4_SUITE_DIR/skill-validator-contracts.sh"
if ! p0p4_suite_is_excluded "skill-eval-contracts.sh"; then
    source "$P0P4_SUITE_DIR/skill-eval-contracts.sh"
fi
source "$P0P4_SUITE_DIR/workflow-basics-contracts.sh"
if ! p0p4_suite_is_excluded "progressive-discovery-contracts.sh"; then
    source "$P0P4_SUITE_DIR/progressive-discovery-contracts.sh"
fi
if ! p0p4_suite_is_excluded "workflow-architecture-completion-contracts.sh"; then
    source "$P0P4_SUITE_DIR/workflow-architecture-completion-contracts.sh"
fi
source "$P0P4_SUITE_DIR/workflow-end-to-end-eval-contracts.sh"
source "$P0P4_SUITE_DIR/workflow-evidence-spine-contracts.sh"
source "$P0P4_SUITE_DIR/feature-preparation-evidence-contracts.sh"
source "$P0P4_SUITE_DIR/adaptive-execution-contracts.sh"
source "$P0P4_SUITE_DIR/tdd-contracts.sh"
source "$P0P4_SUITE_DIR/task-packet-contracts.sh"
source "$P0P4_SUITE_DIR/spec-review-contracts.sh"
source "$P0P4_SUITE_DIR/worker-status-contracts.sh"
source "$P0P4_SUITE_DIR/worker-prompt-contracts.sh"
source "$P0P4_SUITE_DIR/docs-drift-contracts.sh"
source "$P0P4_SUITE_DIR/harness-docs-evals-contracts.sh"
source "$P0P4_SUITE_DIR/eval-contracts.sh"
if ! p0p4_suite_is_excluded "codex-behavioral-eval-contracts.sh"; then
    source "$P0P4_SUITE_DIR/codex-behavioral-eval-contracts.sh"
fi
source "$P0P4_SUITE_DIR/codex-agent-config-contracts.sh"
source "$P0P4_SUITE_DIR/context-budget-report-contracts.sh"
source "$P0P4_SUITE_DIR/pattern-library-contracts.sh"

finish
