#!/usr/bin/env bash
# Closed-world semantic validators used by provider-neutral local eval grading.

semantic_validator_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

semantic_validator_id_for_case() {
    local fixture_file="$1"
    local case_id="$2"

    jq -r --arg id "$case_id" '.cases[] | select(.id == $id) | .semantic_validator // empty' "$fixture_file"
}

assistant_research_five_lens_v3_valid() {
    local response_path="$1"
    local fixture_file="$2"
    local case_id="$3"
    node "$semantic_validator_dir/research-semantic-validator.cjs" "$response_path" "$fixture_file" "$case_id"
}
run_semantic_validator() {
    local validator_id="$1"
    local response_path="$2"
    local fixture_file="$3"
    local case_id="$4"

    case "$validator_id" in
        assistant-research.five_lens_v3) assistant_research_five_lens_v3_valid "$response_path" "$fixture_file" "$case_id" ;;
        *)
            echo "Unknown semantic validator: $validator_id" >&2
            return 1
            ;;
    esac
}
