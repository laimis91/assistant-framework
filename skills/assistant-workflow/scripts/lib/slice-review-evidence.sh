#!/usr/bin/env bash
# Provider-neutral review-evidence parsing and validation. Evidence is always
# treated as bounded data; callers must never source these records.

SLICE_REVIEW_EVIDENCE_MAX_BYTES=65536
SLICE_REVIEW_PENDING_PATH=""
SLICE_REVIEW_APPROVAL_PATH=""
SLICE_REVIEW_VERIFIED_BASE_SHA=""
SLICE_REVIEW_VERIFIED_HEAD_SHA=""
SLICE_REVIEW_RECORD_KEYS=""

slice_review_nonblank() {
    [[ -n "${1//[[:space:]]/}" ]]
}

slice_review_evidence_paths() {
    local evidence_dir="$1"
    local brief_file="$2"
    local brief_name
    brief_name=$(basename "$brief_file" .md)
    SLICE_REVIEW_PENDING_PATH="$evidence_dir/${brief_name}.review-evidence.txt"
    SLICE_REVIEW_APPROVAL_PATH="$evidence_dir/${brief_name}.review-approval.txt"
}

slice_review_read_record() {
    local record_path="$1"
    local opening_marker="$2"
    local closing_marker="$3"
    local required_keys="$4"
    local byte_count line key value expected_key record_variable
    local -a lines=()
    local seen_keys=""

    [[ -f "$record_path" && ! -L "$record_path" ]] || {
        echo "Review evidence must be a regular non-symlink file: $record_path" >&2
        return 1
    }
    byte_count=$(wc -c <"$record_path") || return 1
    byte_count="${byte_count//[[:space:]]/}"
    [[ "$byte_count" =~ ^[0-9]+$ && "$byte_count" -le "$SLICE_REVIEW_EVIDENCE_MAX_BYTES" ]] || {
        echo "Review evidence exceeds the ${SLICE_REVIEW_EVIDENCE_MAX_BYTES}-byte limit: $record_path" >&2
        return 1
    }
    while IFS= read -r value || [[ -n "$value" ]]; do
        if [[ "$value" == *$'\r' ]]; then
            value="${value%$'\r'}"
        fi
        [[ "$value" != *$'\r'* ]] || {
            echo "Review evidence contains an unexpected carriage return: $record_path" >&2
            return 1
        }
        lines+=("$value")
    done <"$record_path"
    [[ ${#lines[@]} -ge 3 && "${lines[0]}" == "$opening_marker" && "${lines[${#lines[@]}-1]}" == "$closing_marker" ]] || {
        echo "Review evidence has invalid record markers: $record_path" >&2
        return 1
    }

    for expected_key in $required_keys; do
        unset "SLICE_REVIEW_RECORD_${expected_key}"
    done
    SLICE_REVIEW_RECORD_KEYS=""
    for ((line = 1; line < ${#lines[@]} - 1; line++)); do
        [[ "${lines[$line]}" =~ ^([a-z_]+):\ (.*)$ ]] || {
            echo "Review evidence has an invalid data line: $record_path" >&2
            return 1
        }
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        [[ " $seen_keys " != *" $key "* ]] || {
            echo "Review evidence duplicates canonical field '$key': $record_path" >&2
            return 1
        }
        seen_keys="$seen_keys $key"
        record_variable="SLICE_REVIEW_RECORD_${key}"
        printf -v "$record_variable" '%s' "$value"
        SLICE_REVIEW_RECORD_KEYS="$SLICE_REVIEW_RECORD_KEYS $key"
    done

    for expected_key in $required_keys; do
        record_variable="SLICE_REVIEW_RECORD_${expected_key}"
        [[ " $seen_keys " == *" $expected_key "* ]] && slice_review_nonblank "${!record_variable}" || {
            echo "Review evidence is missing nonblank canonical field '$expected_key': $record_path" >&2
            return 1
        }
    done
    for key in $seen_keys; do
        [[ " $required_keys " == *" $key "* ]] || {
            echo "Review evidence contains unsupported field '$key': $record_path" >&2
            return 1
        }
    done
}

slice_review_invalidate() {
    local evidence_dir="$1"
    local brief_file="$2"
    slice_review_evidence_paths "$evidence_dir" "$brief_file"
    rm -f -- "$SLICE_REVIEW_PENDING_PATH" "$SLICE_REVIEW_APPROVAL_PATH"
}

slice_review_write_pending() {
    local evidence_dir="$1"
    local brief_file="$2"
    local slice_id="$3"
    local target_branch="$4"
    local target_base_sha="$5"
    local task_branch="$6"
    local slice_branch="$7"
    local verified_base_sha="$8"
    local verified_head_sha="$9"
    local verification_evidence_ref="${10}"
    local current_head current_base current_target pending_tmp

    slice_review_evidence_paths "$evidence_dir" "$brief_file"
    current_head=$(git -C "$SLICE_REVIEW_REPO" rev-parse "${slice_branch}^{commit}" 2>/dev/null || printf 'unreadable')
    current_base=$(git -C "$SLICE_REVIEW_REPO" rev-parse "${task_branch}^{commit}" 2>/dev/null || printf 'unreadable')
    current_target=$(git -C "$SLICE_REVIEW_REPO" rev-parse "${target_branch}^{commit}" 2>/dev/null || printf 'unreadable')
    [[ "$current_head" == "$verified_head_sha" && "$current_base" == "$verified_base_sha" ]] || {
        echo "REVIEW_PENDING evidence rejected: slice or task ref changed after immutable verification for '$slice_id'." >&2
        return 1
    }
    git -C "$SLICE_REVIEW_REPO" merge-base --is-ancestor "$verified_base_sha" "$verified_head_sha" || {
        echo "REVIEW_PENDING evidence rejected: verified_base_sha '$verified_base_sha' must be an ancestor of verified_head_sha '$verified_head_sha' for '$slice_id'." >&2
        return 1
    }
    slice_metadata_is_canonical_commit_sha "$target_base_sha" \
        && git -C "$SLICE_REVIEW_REPO" merge-base --is-ancestor "$target_base_sha" "$current_target" \
        && git -C "$SLICE_REVIEW_REPO" merge-base --is-ancestor "$target_base_sha" "$current_base" || {
        echo "REVIEW_PENDING evidence rejected: immutable target_base_sha is not an ancestor of current target and task refs for '$slice_id'." >&2
        return 1
    }
    pending_tmp=$(mktemp "$evidence_dir/.review-evidence.XXXXXX") || return 1
    {
        printf '%s\n' '--- SLICE REVIEW EVIDENCE ---'
        printf '%s\n' 'schema_version: 1'
        printf '%s\n' 'state: REVIEW_PENDING'
        printf 'slice_id: %s\n' "$slice_id"
        printf '%s\n' 'promotion_mode: review_gated'
        printf 'target_branch: %s\n' "$target_branch"
        printf 'target_base_sha: %s\n' "$target_base_sha"
        printf 'task_branch: %s\n' "$task_branch"
        printf 'slice_branch: %s\n' "$slice_branch"
        printf 'review_base_ref: %s\n' "$task_branch"
        printf 'review_head_ref: %s\n' "$slice_branch"
        printf 'verified_base_sha: %s\n' "$verified_base_sha"
        printf 'verified_head_sha: %s\n' "$verified_head_sha"
        printf 'verification_evidence_ref: %s\n' "$verification_evidence_ref"
        printf '%s\n' 'provider_gate_state: not_evaluated'
        printf '%s\n' '--- END SLICE REVIEW EVIDENCE ---'
    } >"$pending_tmp" || { rm -f -- "$pending_tmp"; return 1; }
    mv -f -- "$pending_tmp" "$SLICE_REVIEW_PENDING_PATH" || { rm -f -- "$pending_tmp"; return 1; }
}

slice_review_validate_approved_pair() {
    local repo="$1"
    local evidence_dir="$2"
    local brief_file="$3"
    local slice_id="$4"
    local target_branch="$5"
    local target_base_sha="$6"
    local task_branch="$7"
    local slice_branch="$8"
    local pending_keys approval_keys key current_head record_variable pending_variable approval_variable

    pending_keys='schema_version state slice_id promotion_mode target_branch target_base_sha task_branch slice_branch review_base_ref review_head_ref verified_base_sha verified_head_sha verification_evidence_ref provider_gate_state'
    approval_keys="$pending_keys review_request_ref provider_gate_evidence_ref"
    slice_review_evidence_paths "$evidence_dir" "$brief_file"
    slice_review_read_record "$SLICE_REVIEW_PENDING_PATH" '--- SLICE REVIEW EVIDENCE ---' '--- END SLICE REVIEW EVIDENCE ---' "$pending_keys" || return 1
    for key in $pending_keys; do
        record_variable="SLICE_REVIEW_RECORD_${key}"
        pending_variable="SLICE_REVIEW_PENDING_${key}"
        printf -v "$pending_variable" '%s' "${!record_variable}"
    done
    slice_review_read_record "$SLICE_REVIEW_APPROVAL_PATH" '--- SLICE REVIEW APPROVAL ---' '--- END SLICE REVIEW APPROVAL ---' "$approval_keys" || return 1
    for key in $approval_keys; do
        record_variable="SLICE_REVIEW_RECORD_${key}"
        approval_variable="SLICE_REVIEW_APPROVAL_${key}"
        printf -v "$approval_variable" '%s' "${!record_variable}"
    done

    [[ "$SLICE_REVIEW_PENDING_schema_version" == 1 && "$SLICE_REVIEW_PENDING_state" == REVIEW_PENDING && "$SLICE_REVIEW_PENDING_promotion_mode" == review_gated && "$SLICE_REVIEW_PENDING_provider_gate_state" == not_evaluated ]] || {
        echo "Review evidence must be a REVIEW_PENDING record with provider_gate_state: not_evaluated." >&2
        return 1
    }
    [[ "$SLICE_REVIEW_APPROVAL_schema_version" == 1 && "$SLICE_REVIEW_APPROVAL_state" == REVIEW_APPROVED && "$SLICE_REVIEW_APPROVAL_promotion_mode" == review_gated && "$SLICE_REVIEW_APPROVAL_provider_gate_state" == passed ]] || {
        echo "Review approval must be REVIEW_APPROVED with provider_gate_state: passed." >&2
        return 1
    }
    slice_review_nonblank "$SLICE_REVIEW_APPROVAL_review_request_ref" && slice_review_nonblank "$SLICE_REVIEW_APPROVAL_provider_gate_evidence_ref" || {
        echo "Review approval requires nonblank opaque review_request_ref and provider_gate_evidence_ref." >&2
        return 1
    }
    for key in schema_version slice_id promotion_mode target_branch target_base_sha task_branch slice_branch review_base_ref review_head_ref verified_base_sha verified_head_sha verification_evidence_ref; do
        pending_variable="SLICE_REVIEW_PENDING_${key}"
        approval_variable="SLICE_REVIEW_APPROVAL_${key}"
        [[ "${!pending_variable}" == "${!approval_variable}" ]] || {
            echo "Review approval mismatch for '$key' between pending evidence and approval." >&2
            return 1
        }
    done
    [[ "$SLICE_REVIEW_PENDING_slice_id" == "$slice_id" && "$SLICE_REVIEW_PENDING_target_branch" == "$target_branch" && "$SLICE_REVIEW_PENDING_target_base_sha" == "$target_base_sha" && "$SLICE_REVIEW_PENDING_task_branch" == "$task_branch" && "$SLICE_REVIEW_PENDING_slice_branch" == "$slice_branch" && "$SLICE_REVIEW_PENDING_review_base_ref" == "$task_branch" && "$SLICE_REVIEW_PENDING_review_head_ref" == "$slice_branch" ]] || {
        echo "Review evidence does not match the current slice topology." >&2
        return 1
    }
    slice_metadata_is_canonical_commit_sha "$SLICE_REVIEW_PENDING_target_base_sha" || {
        echo "Review evidence must contain a canonical immutable target_base_sha." >&2
        return 1
    }
    [[ "$SLICE_REVIEW_PENDING_verified_base_sha" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ && "$SLICE_REVIEW_PENDING_verified_head_sha" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] || {
        echo "Review evidence must contain canonical verified commit SHAs." >&2
        return 1
    }
    [[ "$SLICE_REVIEW_PENDING_verified_head_sha" != "$SLICE_REVIEW_PENDING_verified_base_sha" ]] || {
        echo "Review approval cannot certify an empty transition: verified_head_sha must differ from verified_base_sha." >&2
        return 1
    }
    git -C "$repo" merge-base --is-ancestor "$SLICE_REVIEW_PENDING_verified_base_sha" "$SLICE_REVIEW_PENDING_verified_head_sha" || {
        echo "Review approval verified_base_sha must be an ancestor of verified_head_sha." >&2
        return 1
    }
    current_head=$(git -C "$repo" rev-parse "${slice_branch}^{commit}" 2>/dev/null || printf 'unreadable')
    [[ "$current_head" == "$SLICE_REVIEW_PENDING_verified_head_sha" ]] || {
        echo "Review evidence head SHA does not match the current slice ref." >&2
        return 1
    }
    git -C "$repo" merge-base --is-ancestor "$SLICE_REVIEW_PENDING_verified_base_sha" "$task_branch" || {
        echo "Review evidence base SHA is not an ancestor of current task branch '$task_branch'." >&2
        return 1
    }
    git -C "$repo" merge-base --is-ancestor "$SLICE_REVIEW_PENDING_verified_head_sha" "$task_branch" || {
        echo "Review approval head SHA is not integrated into current task branch '$task_branch'." >&2
        return 1
    }
    git -C "$repo" merge-base --is-ancestor "$SLICE_REVIEW_PENDING_target_base_sha" "$target_branch" \
        && git -C "$repo" merge-base --is-ancestor "$SLICE_REVIEW_PENDING_target_base_sha" "$task_branch" || {
        echo "Review evidence immutable target_base_sha is not an ancestor of current target and task branches." >&2
        return 1
    }
    SLICE_REVIEW_VERIFIED_BASE_SHA="$SLICE_REVIEW_PENDING_verified_base_sha"
    SLICE_REVIEW_VERIFIED_HEAD_SHA="$SLICE_REVIEW_PENDING_verified_head_sha"
}
