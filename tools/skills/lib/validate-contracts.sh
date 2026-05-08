contract_ref_exists() {
    local skill_file="$1"
    local contract_name="$2"

    grep -Eq "contracts/${contract_name}[.]yaml" "$skill_file"
}

infer_contract_tier() {
    local skill_file="$1"

    if contract_ref_exists "$skill_file" "handoffs"; then
        printf '%s\n' "Process"
    elif contract_ref_exists "$skill_file" "phase-gates"; then
        printf '%s\n' "Analysis"
    else
        printf '%s\n' "Utility"
    fi
}

validate_required_contract_files() {
    local skill_file="$1"
    local contract_dir="$2"
    local tier
    local contract_name
    local required_contracts

    tier="$(infer_contract_tier "$skill_file")"
    required_contracts="input output"

    if [[ "$tier" == "Analysis" ]]; then
        required_contracts="$required_contracts phase-gates"
    elif [[ "$tier" == "Process" ]]; then
        required_contracts="$required_contracts phase-gates handoffs"
    fi

    for contract_name in $required_contracts; do
        if [[ ! -f "$contract_dir/$contract_name.yaml" ]]; then
            record_error "CONTRACT_MISSING" "$contract_dir/$contract_name.yaml" "$tier skill requires contracts/$contract_name.yaml"
        fi
    done
}

validate_contract_header() {
    local contract_file="$1"
    local expected_contract="$2"
    local expected_skill="$3"
    local validation_id
    local message

    while IFS='|' read -r validation_id message; do
        [[ -n "$validation_id" ]] || continue
        record_error "$validation_id" "$contract_file" "$message"
    done < <(awk -v expected_contract="$expected_contract" -v expected_skill="$expected_skill" '
        function trim(value) {
            gsub(/^[[:space:]]+/, "", value)
            gsub(/[[:space:]]+$/, "", value)
            return value
        }
        function header_value(line, key, value) {
            value = line
            sub("^[[:space:]]*" key ":[[:space:]]*", "", value)
            sub(/[[:space:]]+#.*$/, "", value)
            value = trim(value)
            if (value ~ /^".*"$/) {
                sub(/^"/, "", value)
                sub(/"$/, "", value)
            }
            return value
        }
        function has_key(line, key) {
            return line ~ "^[[:space:]]*" key ":[[:space:]]*"
        }
        /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
        header_count < 3 {
            header_count++
            header[header_count] = $0
            next
        }
        END {
            if (header_count < 3) {
                print "CONTRACT_HEADER|contract header must start with schema_version, contract, and skill"
                exit
            }

            if (!has_key(header[1], "schema_version") || header_value(header[1], "schema_version") == "") {
                print "CONTRACT_HEADER_SCHEMA_VERSION|first contract header field must be non-empty schema_version"
            }
            if (!has_key(header[2], "contract")) {
                print "CONTRACT_HEADER_CONTRACT|second contract header field must be contract"
            } else if (header_value(header[2], "contract") != expected_contract) {
                print "CONTRACT_HEADER_CONTRACT|contract header must match file name '" expected_contract "'"
            }
            if (!has_key(header[3], "skill")) {
                print "CONTRACT_HEADER_SKILL|third contract header field must be skill"
            } else if (header_value(header[3], "skill") != expected_skill) {
                print "CONTRACT_HEADER_SKILL|skill header must match skill name '" expected_skill "'"
            }
        }
    ' "$contract_file")
}

validate_input_required_actions() {
    local contract_file="$1"
    local validation_id
    local line_number
    local field_name

    while IFS='|' read -r validation_id line_number field_name; do
        [[ -n "$validation_id" ]] || continue
        record_error "$validation_id" "$contract_file" "required input field '$field_name' at line $line_number must declare on_missing before the next sibling field"
    done < <(awk '
        function emit_missing() {
            if (in_field && required && !has_on_missing) {
                print "INPUT_REQUIRED_ON_MISSING|" field_line "|" field_name
            }
        }
        /^  - name:[[:space:]]*/ {
            emit_missing()
            in_field = 1
            required = 0
            has_on_missing = 0
            field_line = FNR
            field_name = $0
            sub(/^  - name:[[:space:]]*/, "", field_name)
            next
        }
        in_field && /^    required:[[:space:]]*true[[:space:]]*$/ { required = 1 }
        in_field && /^    on_missing:/ { has_on_missing = 1 }
        END { emit_missing() }
    ' "$contract_file")
}

validate_output_required_behaviors() {
    local contract_file="$1"
    local validation_id
    local line_number
    local artifact_name

    while IFS='|' read -r validation_id line_number artifact_name; do
        [[ -n "$validation_id" ]] || continue
        record_error "$validation_id" "$contract_file" "required output artifact '$artifact_name' at line $line_number must declare on_fail or validation before the next sibling artifact"
    done < <(awk '
        function emit_missing() {
            if (in_artifact && required && !has_failure_behavior) {
                print "OUTPUT_REQUIRED_FAILURE_BEHAVIOR|" artifact_line "|" artifact_name
            }
        }
        /^  - name:[[:space:]]*/ {
            emit_missing()
            in_artifact = 1
            required = 0
            has_failure_behavior = 0
            artifact_line = FNR
            artifact_name = $0
            sub(/^  - name:[[:space:]]*/, "", artifact_name)
            next
        }
        in_artifact && /^    required:[[:space:]]*true[[:space:]]*$/ { required = 1 }
        in_artifact && /^    (on_fail:|validation:)/ { has_failure_behavior = 1 }
        END { emit_missing() }
    ' "$contract_file")
}

validate_enum_values() {
    local contract_file="$1"
    local validation_id
    local line_number

    while IFS='|' read -r validation_id line_number; do
        [[ -n "$validation_id" ]] || continue
        record_error "$validation_id" "$contract_file" "enum field at line $line_number must declare enum_values before the next sibling item"
    done < <(awk '
        function indent_of(line, copy) {
            copy = line
            sub(/[^ ].*$/, "", copy)
            return length(copy)
        }
        function emit_missing() {
            if (in_enum && !has_enum_values) {
                print "ENUM_VALUES|" enum_line
            }
        }
        /^[[:space:]]*- name:/ {
            item_indent = indent_of($0)
            if (in_enum && item_indent <= enum_item_indent) {
                emit_missing()
                in_enum = 0
                has_enum_values = 0
            }
            current_item_indent = item_indent
        }
        /^[[:space:]]*type:[[:space:]]*enum[[:space:]]*$/ {
            emit_missing()
            in_enum = 1
            has_enum_values = 0
            enum_line = FNR
            enum_item_indent = current_item_indent
            next
        }
        in_enum && /^[[:space:]]*enum_values:/ {
            has_enum_values = 1
            in_enum = 0
            next
        }
        END { emit_missing() }
    ' "$contract_file")
}

validate_contract_file() {
    local contract_file="$1"
    local skill_name="$2"
    local contract_name

    contract_name="$(basename -- "$contract_file" .yaml)"
    case "$contract_name" in
        input|output|phase-gates|handoffs)
            ;;
        *)
            record_error "CONTRACT_UNKNOWN" "$contract_file" "unknown contract file; expected input.yaml, output.yaml, phase-gates.yaml, or handoffs.yaml"
            ;;
    esac

    validate_contract_header "$contract_file" "$contract_name" "$skill_name"
    validate_enum_values "$contract_file"

    if [[ "$contract_name" == "input" ]]; then
        validate_input_required_actions "$contract_file"
    elif [[ "$contract_name" == "output" ]]; then
        validate_output_required_behaviors "$contract_file"
    fi
}

validate_contracts() {
    local skill_file="$1"
    local skill_name="$2"
    local skill_dir
    local contract_dir
    local contract_file

    skill_dir="$(dirname -- "$skill_file")"
    contract_dir="$skill_dir/contracts"

    validate_required_contract_files "$skill_file" "$contract_dir"

    if [[ ! -d "$contract_dir" ]]; then
        return
    fi

    while IFS= read -r contract_file; do
        validate_contract_file "$contract_file" "$skill_name"
    done < <(find "$contract_dir" -maxdepth 1 -type f -name '*.yaml' -print | sort)
}

validate_skill() {
    local skill_file="$1"
    local skill_dir
    local skill_name

    if [[ ! -f "$skill_file" ]]; then
        record_error "SKILL_MISSING" "$skill_file" "SKILL.md does not exist"
        return
    fi

    skill_dir="$(dirname -- "$skill_file")"
    skill_name="$(basename -- "$skill_dir")"

    validate_frontmatter "$skill_file" "$skill_name"
    validate_contracts "$skill_file" "$skill_name"
}
