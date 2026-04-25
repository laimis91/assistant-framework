if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

source "$P0P4_SUITE_DIR/workflow-basics-contracts.sh"
source "$P0P4_SUITE_DIR/tdd-contracts.sh"
source "$P0P4_SUITE_DIR/task-packet-contracts.sh"
source "$P0P4_SUITE_DIR/spec-review-contracts.sh"

p0p4_finish_suite "${BASH_SOURCE[0]}"
