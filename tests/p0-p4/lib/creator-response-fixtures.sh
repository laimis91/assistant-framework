#!/usr/bin/env bash

P0P4_CREATOR_BOUND_FIXTURE_BUNDLE="${P0P4_CREATOR_BOUND_FIXTURE_BUNDLE:-}"
P0P4_CREATOR_FIXTURE_OWNER_SUBSHELL="${BASH_SUBSHELL:-0}"

p0p4_write_creator_bound_response_fixtures() {
    local output_dir="$1"
    local bundle_dir="$P0P4_CREATOR_BOUND_FIXTURE_BUNDLE"
    local creator_fixture="$P0P4_SUITE_DIR/../../skills/assistant-skill-creator/evals/cases.json"
    local case_id
    local response_path
    local retained_run_root
    local response_source
    local created_bundle=false
    local builder_subshell=false

    if [[ "${P0P4_RESPONSE_FIXTURE_PREFLIGHT:-0}" == "1" ]]; then
        mkdir -p "$output_dir/assistant-skill-creator"
        while IFS= read -r case_id; do
            response_path="$output_dir/assistant-skill-creator/$case_id.txt"
            if jq -e --arg id "$case_id" '
              .cases[] | select(.id == $id)
              | ((.machine_expectations.structured_json_assertions // [] | length) > 0
                or .semantic_validator != null)
            ' "$creator_fixture" >/dev/null; then
                printf '{}\n' >"$response_path"
            else
                printf 'Completeness-only response placeholder.\n' >"$response_path"
            fi
        done < <(jq -r '.cases[].id' "$creator_fixture")
        return 0
    fi

    [[ "${BASH_SUBSHELL:-0}" == "$P0P4_CREATOR_FIXTURE_OWNER_SUBSHELL" ]] || builder_subshell=true
    if [[ -z "$bundle_dir" ]]; then
        bundle_dir="$(mktemp -d "${TMPDIR:-/tmp}/creator-bound-fixtures.XXXXXX")" || return 1
        P0P4_CREATOR_BOUND_FIXTURE_BUNDLE="$bundle_dir"
        created_bundle=true
        if [[ "$builder_subshell" == false ]]; then
            p0p4_register_cleanup "$bundle_dir"
        fi
        if ! bash "$P0P4_SUITE_DIR/skill-creator-semantic-contracts.sh" --export-bound-fixtures "$bundle_dir" >"$bundle_dir/export.log" 2>&1; then
            cat "$bundle_dir/export.log" >&2
            rm -rf "$bundle_dir"
            P0P4_CREATOR_BOUND_FIXTURE_BUNDLE=""
            return 1
        fi
        retained_run_root="$(jq -r '.retained_run_root' "$bundle_dir/manifest.json")"
        [[ -d "$retained_run_root" ]] || { echo "Creator fixture capture root is missing: $retained_run_root" >&2; rm -rf "$bundle_dir"; return 1; }
        if [[ "$builder_subshell" == false ]]; then
            p0p4_register_cleanup "$retained_run_root"
        fi
    fi

    response_source="$bundle_dir/responses/assistant-skill-creator"
    [[ -d "$response_source" && -f "$bundle_dir/manifest.json" ]] || {
        echo "Bound creator response bundle is incomplete: $bundle_dir" >&2
        return 1
    }
    mkdir -p "$output_dir/assistant-skill-creator" "$output_dir/.creator-bound"
    cp "$response_source"/* "$output_dir/assistant-skill-creator/"
    rm -rf "$output_dir/.creator-bound/assistant-skill-creator"
    cp -R "$bundle_dir/skill/assistant-skill-creator" "$output_dir/.creator-bound/"
    if [[ "$builder_subshell" == true && "$created_bundle" == true ]]; then
        rm -rf "$retained_run_root" "$bundle_dir"
        P0P4_CREATOR_BOUND_FIXTURE_BUNDLE=""
    fi
}

p0p4_run_default_response_grades() {
    local response_dir="$1"
    local fixture_file
    local skill_name
    local args=(--responses "$response_dir")
    shift

    while IFS= read -r fixture_file; do
        skill_name="$(basename "$(dirname "$(dirname "$fixture_file")")")"
        [[ "$skill_name" == "assistant-skill-creator" ]] && continue
        args+=(--skill "$skill_name")
    done < <(p0p4_skill_eval_default_fixtures)

    args+=(--skill "$response_dir/.creator-bound/assistant-skill-creator")
    "$skill_eval_runner" "${args[@]}" "$@"
}
