#!/usr/bin/env bash
# Shared, data-only parser and validator for slice execution topology metadata.
# Callers must not source briefs or evidence files.

SLICE_METADATA_SAFE_TASK_PATTERN='^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'

slice_metadata_is_safe_task() {
    [[ "$1" =~ $SLICE_METADATA_SAFE_TASK_PATTERN ]]
}

slice_metadata_is_safe_branch() {
    [[ -n "$1" ]] && git check-ref-format --branch "$1" >/dev/null 2>&1
}

slice_metadata_is_canonical_commit_sha() {
    [[ "$1" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]
}

slice_metadata_strict_scalar() {
    local brief_file="$1"
    local field="$2"
    awk -v field="$field" '
        /^### Supporting context/ { exit }
        $0 ~ ("^- " field ":[[:space:]]*") {
            value = $0
            sub("^- " field ":[[:space:]]*", "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            print value
            exit
        }
    ' "$brief_file"
}

slice_metadata_strict_scalar_count() {
    local brief_file="$1"
    local field="$2"
    awk -v field="$field" '
        /^### Supporting context/ { exit }
        $0 ~ ("^- " field ":[[:space:]]*") { count++ }
        END { print count + 0 }
    ' "$brief_file"
}

slice_metadata_supporting_git_branch() {
    local brief_file="$1"
    awk '
        /^### Supporting context/ { in_supporting = 1; next }
        in_supporting && /^- Git branch:[[:space:]]*/ {
            value = $0
            sub(/^- Git branch:[[:space:]]*/, "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            print value
            exit
        }
    ' "$brief_file"
}

slice_metadata_supporting_git_branch_count() {
    local brief_file="$1"
    awk '
        /^### Supporting context/ { in_supporting = 1; next }
        in_supporting && /^- Git branch:[[:space:]]*/ { count++ }
        END { print count + 0 }
    ' "$brief_file"
}

# Sets SLICE_METADATA_* globals. Returns nonzero with an actionable error on
# stderr. New topology metadata is deliberately all-or-none.
slice_metadata_resolve() {
    local brief_file="$1"
    local slice_id="$2"
    local target target_base task slice mode supporting task_name expected_task expected_slice field field_count supporting_count
    local occurrence_count=0

    for field in target_branch target_base_sha task_branch slice_branch promotion_mode; do
        field_count=$(slice_metadata_strict_scalar_count "$brief_file" "$field")
        [[ "$field_count" -le 1 ]] || { echo "Slice '$slice_id' brief '$brief_file' duplicates topology metadata field '$field'." >&2; return 1; }
        occurrence_count=$((occurrence_count + field_count))
    done
    supporting_count=$(slice_metadata_supporting_git_branch_count "$brief_file")
    [[ "$supporting_count" -le 1 ]] || { echo "Slice '$slice_id' brief '$brief_file' duplicates supporting Git branch metadata." >&2; return 1; }
    target=$(slice_metadata_strict_scalar "$brief_file" target_branch)
    target_base=$(slice_metadata_strict_scalar "$brief_file" target_base_sha)
    task=$(slice_metadata_strict_scalar "$brief_file" task_branch)
    slice=$(slice_metadata_strict_scalar "$brief_file" slice_branch)
    mode=$(slice_metadata_strict_scalar "$brief_file" promotion_mode)
    supporting=$(slice_metadata_supporting_git_branch "$brief_file")
    if [[ "$occurrence_count" -eq 0 ]]; then
        [[ -n "$supporting" ]] || { echo "Slice '$slice_id' brief '$brief_file' is missing 'Git branch:' for legacy topology." >&2; return 1; }
        if [[ "$supporting" != feature/*/slice-"$slice_id" ]]; then
            echo "Slice '$slice_id' branch identity mismatch: legacy Git branch '$supporting' must end with expected 'slice-$slice_id' under feature/<task>." >&2
            return 1
        fi
        task_name="${supporting#feature/}"
        task_name="${task_name%/slice-$slice_id}"
        slice_metadata_is_safe_task "$task_name" || { echo "Slice '$slice_id' legacy Git branch '$supporting' does not contain a safe task name." >&2; return 1; }
        SLICE_METADATA_LEGACY=true
        SLICE_METADATA_TARGET_BRANCH=""
        SLICE_METADATA_TARGET_BASE_SHA=""
        SLICE_METADATA_TASK_BRANCH="feature/$task_name/integration"
        SLICE_METADATA_SLICE_BRANCH="$supporting"
        SLICE_METADATA_PROMOTION_MODE="local"
        return 0
    fi

    for field in target_branch target_base_sha task_branch slice_branch promotion_mode; do
        case "$field" in
            target_branch) [[ -n "$target" ]] ;;
            target_base_sha) [[ -n "$target_base" ]] ;;
            task_branch) [[ -n "$task" ]] ;;
            slice_branch) [[ -n "$slice" ]] ;;
            promotion_mode) [[ -n "$mode" ]] ;;
        esac || { echo "Slice '$slice_id' brief '$brief_file' is missing topology metadata field '$field'. New topology fields are all required together." >&2; return 1; }
    done
    slice_metadata_is_safe_branch "$target" || { echo "Slice '$slice_id' target_branch '$target' is not a safe git branch ref." >&2; return 1; }
    slice_metadata_is_canonical_commit_sha "$target_base" || { echo "Slice '$slice_id' target_base_sha '$target_base' must be a canonical 40- or 64-character lowercase commit SHA." >&2; return 1; }
    if [[ "$task" != feature/* ]]; then
        echo "Slice '$slice_id' task_branch '$task' must use feature/<task>." >&2
        return 1
    fi
    task_name="${task#feature/}"
    slice_metadata_is_safe_task "$task_name" || { echo "Slice '$slice_id' task_branch '$task' must contain one safe task name." >&2; return 1; }
    expected_task="feature/$task_name"
    expected_slice="slice/$task_name/$slice_id"
    if [[ "$task" != "$expected_task" ]] || ! slice_metadata_is_safe_branch "$task"; then
        echo "Slice '$slice_id' task_branch '$task' must use feature/<safe-task>." >&2
        return 1
    fi
    if [[ "$slice" != "$expected_slice" ]]; then
        echo "Slice '$slice_id' slice_branch '$slice' does not match task_branch '$task'; expected '$expected_slice'." >&2
        return 1
    fi
    slice_metadata_is_safe_branch "$slice" || { echo "Slice '$slice_id' slice_branch '$slice' is not a safe git branch ref." >&2; return 1; }
    [[ "$mode" == local || "$mode" == review_gated ]] || { echo "Slice '$slice_id' promotion_mode '$mode' must be local or review_gated." >&2; return 1; }
    if [[ -n "$supporting" && "$supporting" != "$slice" ]]; then
        echo "Slice '$slice_id' supporting Git branch '$supporting' must be absent or equal slice_branch '$slice'." >&2
        return 1
    fi

    SLICE_METADATA_LEGACY=false
    SLICE_METADATA_TARGET_BRANCH="$target"
    SLICE_METADATA_TARGET_BASE_SHA="$target_base"
    SLICE_METADATA_TASK_BRANCH="$task"
    SLICE_METADATA_SLICE_BRANCH="$slice"
    SLICE_METADATA_PROMOTION_MODE="$mode"
}
