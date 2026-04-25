if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

source "$P0P4_SUITE_DIR/worker-status-contracts.sh"
source "$P0P4_SUITE_DIR/worker-prompt-contracts.sh"
source "$P0P4_SUITE_DIR/memory-doc-contracts.sh"
source "$P0P4_SUITE_DIR/eval-contracts.sh"

p0p4_finish_suite "${BASH_SOURCE[0]}"
