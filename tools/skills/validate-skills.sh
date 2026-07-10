#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

INCLUDE_LOCAL=false
LIST_ONLY=false
SKILL_SELECTORS=()
SKILL_FILES=()
FAILURES=0

source "$SCRIPT_DIR/lib/validate-common.sh"
source "$SCRIPT_DIR/lib/validate-inventory.sh"
source "$SCRIPT_DIR/lib/validate-frontmatter.sh"
source "$SCRIPT_DIR/lib/validate-contracts.sh"

contract_index_resolve_path() {
    local skill_dir="$1"
    local relative_path="$2"
    local skill_root
    local resolved

    case "$relative_path" in
        ""|/*|.|..|./*|../*|*/../*|*/..|*//*|*/./*|*/.) return 3 ;;
    esac
    [[ -e "$skill_dir/$relative_path" ]] || return 2

    skill_root="$(realpath "$skill_dir")" || return 4
    resolved="$(realpath "$skill_dir/$relative_path")" || return 4
    case "$resolved" in
        "$skill_root"/*) printf '%s\n' "$resolved" ;;
        *) return 4 ;;
    esac
}

contract_index_extract_item() {
    local contract_file="$1"
    local section="$2"
    local key="$3"
    local wanted_name="$4"

    awk -v section="$section" -v key="$key" -v wanted="$wanted_name" '
        function trim(value) {
            gsub(/^[[:space:]]+/, "", value)
            gsub(/[[:space:]]+$/, "", value)
            if ((value ~ /^".*"$/) || (value ~ /^\047.*\047$/)) {
                value = substr(value, 2, length(value) - 2)
            }
            return value
        }
        function property_value(line, value) {
            value = line
            sub(/^[^:]*:[[:space:]]*/, "", value)
            sub(/[[:space:]]+#.*$/, "", value)
            return trim(value)
        }
        function inspect_property(line, property) {
            property = line
            sub(/^[[:space:]]*-[[:space:]]*/, "", property)
            sub(/^[[:space:]]*/, "", property)
            if (property ~ ("^" key ":[[:space:]]*")) {
                item_has_key = 1
                item_key_value = property_value(property)
            }
        }
        function finish_item() {
            if (!item_started) return
            if (item_has_key) key_count++
            if (item_has_key && item_key_value == wanted) {
                match_count++
                selected_words += item_words
            }
            item_started = 0
            item_has_key = 0
            item_key_value = ""
            item_words = 0
        }
        $0 == section ":" {
            finish_item()
            section_count++
            in_section = 1
            next
        }
        in_section && /^[^[:space:]#][^:]*:/ {
            finish_item()
            in_section = 0
        }
        in_section && /^  -([[:space:]]|$)/ {
            finish_item()
            item_started = 1
            item_words = NF
            inspect_property($0)
            next
        }
        in_section && item_started {
            item_words += NF
            if ($0 ~ ("^    " key ":[[:space:]]*")) inspect_property($0)
        }
        END {
            finish_item()
            print (section_count + 0) "|" (key_count + 0) "|" (match_count + 0) "|" (selected_words + 0)
        }
    ' "$contract_file"
}

validate_contract_index() {
    local index_file="$1"
    local skill_name="$2"
    local skill_dir
    local tier
    local expected_contracts
    local event
    local field1 field2 field3 field4 field5 field6 field7 field8
    local resolved status header_info header_count header_type
    local row path declared_type load_set selector_id section key mode name_from names
    local name extract_info section_count key_count match_count selected_words selector_words
    local reference_path budget actual base_words
    local i j load_index authoritative_found first_name
    local -a authoritative_rows=()
    local -a load_set_names=()
    local -a load_set_budgets=()
    local -a load_set_words=()
    local -a reference_rows=()
    local -a selector_rows=()

    skill_dir="$(dirname -- "$(dirname -- "$index_file")")"
    tier="$(infer_contract_tier "$skill_dir/SKILL.md")"
    expected_contracts="contracts/input.yaml contracts/output.yaml"
    if [[ "$tier" == "Analysis" ]]; then
        expected_contracts="$expected_contracts contracts/phase-gates.yaml"
    elif [[ "$tier" == "Process" ]]; then
        expected_contracts="$expected_contracts contracts/phase-gates.yaml contracts/handoffs.yaml"
    fi

    while IFS='|' read -r event field1 field2 field3 field4 field5 field6 field7 field8; do
        [[ -n "$event" ]] || continue
        case "$event" in
            ERROR) record_error "$field1" "$index_file" "$field2" ;;
            AUTHORITATIVE) authoritative_rows+=("$field1|$field2") ;;
            LOAD_SET)
                load_set_names+=("$field1")
                load_set_budgets+=("$field2")
                ;;
            REFERENCE) reference_rows+=("$field1|$field2") ;;
            SELECTOR) selector_rows+=("$field1|$field2|$field3|$field4|$field5|$field6|$field7|$field8") ;;
        esac
    done < <(awk -v expected_skill="$skill_name" -v expected_contracts="$expected_contracts" '
        function trim(value) {
            gsub(/^[[:space:]]+/, "", value)
            gsub(/[[:space:]]+$/, "", value)
            return value
        }
        function scalar_value(line, value) {
            value = line
            sub(/^[^:]*:[[:space:]]*/, "", value)
            sub(/[[:space:]]+#.*$/, "", value)
            value = trim(value)
            if ((value ~ /^".*"$/) || (value ~ /^\047.*\047$/)) {
                value = substr(value, 2, length(value) - 2)
            }
            return value
        }
        function emit(validation_id, message) {
            print "ERROR|" validation_id "|" message
        }
        function list_values(value, result, count, part, i) {
            value = trim(value)
            if (value !~ /^\[.*\]$/) return "!invalid!"
            value = substr(value, 2, length(value) - 2)
            if (trim(value) == "") return ""
            count = split(value, part, ",")
            for (i = 1; i <= count; i++) {
                part[i] = trim(part[i])
                if ((part[i] ~ /^".*"$/) || (part[i] ~ /^\047.*\047$/)) {
                    part[i] = substr(part[i], 2, length(part[i]) - 2)
                }
                result = result (result == "" ? "" : ",") part[i]
            }
            return result
        }
        function add_selector_name(kind, value) {
            value = trim(value)
            if ((value ~ /^".*"$/) || (value ~ /^\047.*\047$/)) {
                value = substr(value, 2, length(value) - 2)
            }
            if (kind == "names") current_selector_names = current_selector_names (current_selector_names == "" ? "" : ",") value
            else current_selector_allowed = current_selector_allowed (current_selector_allowed == "" ? "" : ",") value
        }
        function finish_authoritative(derived_type) {
            if (!in_authoritative_item) return
            if (current_authoritative_path == "") {
                emit("CONTRACT_INDEX_AUTHORITATIVE_PATH", "each authoritative_contracts item must declare a non-empty path")
            } else {
                authoritative_count[current_authoritative_path]++
                if (authoritative_count[current_authoritative_path] > 1) {
                    emit("CONTRACT_INDEX_AUTHORITATIVE_DUPLICATE", "authoritative_contracts contains duplicate path \047" current_authoritative_path "\047")
                }
                if (!(current_authoritative_path in required)) {
                    emit("CONTRACT_INDEX_AUTHORITATIVE_EXTRA", "authoritative path \047" current_authoritative_path "\047 is not required for the inferred skill tier")
                }
            }
            if (current_authoritative_contract == "") {
                emit("CONTRACT_INDEX_AUTHORITATIVE_CONTRACT", "authoritative path \047" current_authoritative_path "\047 must declare a non-empty contract type")
            }
            print "AUTHORITATIVE|" current_authoritative_path "|" current_authoritative_contract
            in_authoritative_item = 0
            current_authoritative_path = ""
            current_authoritative_contract = ""
        }
        function validate_names(selector_label, values, count, parts, seen, i, address) {
            delete seen
            count = split(values, parts, ",")
            for (i = 1; i <= count; i++) {
                if (parts[i] == "") {
                    emit("CONTRACT_INDEX_SELECTOR_NAMES", selector_label " contains an empty selector name")
                    continue
                }
                if (++seen[parts[i]] > 1) {
                    emit("CONTRACT_INDEX_SELECTOR_NAME_DUPLICATE", selector_label " contains duplicate name \047" parts[i] "\047")
                }
                address = current_set SUBSEP current_selector_path SUBSEP current_selector_section SUBSEP current_selector_key SUBSEP parts[i]
                if (++selector_addresses[address] > 1) {
                    emit("CONTRACT_INDEX_SELECTOR_NAME_DUPLICATE", "load set \047" current_set "\047 selects address \047" current_selector_path ":" current_selector_section ":" current_selector_key ":" parts[i] "\047 more than once")
                }
            }
        }
        function finish_selector(selector_label, mode, selected_names) {
            if (!in_selector) return
            selector_count++
            selector_set_count++
            selector_label = "selector " selector_set_count " in load set \047" current_set "\047"
            if (current_selector_id == "") emit("CONTRACT_INDEX_SELECTOR_ID", selector_label " must declare a non-empty id")
            else if (++selector_ids[current_selector_id] > 1) emit("CONTRACT_INDEX_SELECTOR_ID_DUPLICATE", "selector id \047" current_selector_id "\047 must be unique")
            if (current_selector_path == "") emit("CONTRACT_INDEX_SELECTOR_PATH", selector_label " must declare a non-empty canonical path")
            if (current_selector_section == "") emit("CONTRACT_INDEX_SELECTOR_SECTION", selector_label " must declare a non-empty section")
            if (current_selector_key == "") emit("CONTRACT_INDEX_SELECTOR_KEY", selector_label " must declare a non-empty key")
            if (current_selector_match_seen) emit("CONTRACT_INDEX_SELECTOR_PROSE_MATCH", selector_label " uses forbidden prose match; use key plus names or name_from plus allowed_names")

            mode = ""
            selected_names = ""
            if (current_selector_names != "" && current_selector_name_from == "" && current_selector_allowed == "") {
                mode = "explicit"
                selected_names = current_selector_names
            } else if (current_selector_names == "" && current_selector_name_from != "" && current_selector_allowed != "") {
                mode = "runtime"
                selected_names = current_selector_allowed
            } else {
                emit("CONTRACT_INDEX_SELECTOR_NAMES", selector_label " must declare either non-empty names or name_from with non-empty allowed_names")
            }
            if (selected_names != "") validate_names(selector_label, selected_names)
            print "SELECTOR|" current_set "|" current_selector_id "|" current_selector_path "|" current_selector_section "|" current_selector_key "|" mode "|" current_selector_name_from "|" selected_names

            in_selector = 0
            current_selector_id = ""
            current_selector_path = ""
            current_selector_section = ""
            current_selector_key = ""
            current_selector_names = ""
            current_selector_name_from = ""
            current_selector_allowed = ""
            current_selector_match_seen = 0
            current_list = ""
        }
        function finish_load_set() {
            if (!in_load_set) return
            finish_selector()
            if (!has_selectors || selector_set_count == 0) {
                emit("CONTRACT_INDEX_LOAD_SET_SELECTORS", "load set \047" current_set "\047 must declare a non-empty selectors list")
            }
            if (budget_count != 1 || budget_words !~ /^[1-9][0-9]*$/) {
                emit("CONTRACT_INDEX_LOAD_SET_BUDGET", "load set \047" current_set "\047 must declare exactly one positive integer budget_words")
            }
            print "LOAD_SET|" current_set "|" budget_words
            in_load_set = 0
            in_selectors = 0
            in_references = 0
            has_selectors = 0
            selector_set_count = 0
            budget_count = 0
            budget_words = ""
        }
        BEGIN {
            expected_count = split(expected_contracts, expected, " ")
            for (i = 1; i <= expected_count; i++) required[expected[i]] = 1
        }
        /^schema_version:[[:space:]]*/ { schema_version = scalar_value($0); schema_version_count++ }
        /^contract:[[:space:]]*/ { contract = scalar_value($0); contract_count++ }
        /^skill:[[:space:]]*/ { skill = scalar_value($0); skill_count++ }
        /^authoritative_contracts:[[:space:]]*$/ { in_authoritative = 1; authoritative_declared = 1; next }
        in_authoritative && /^[^[:space:]#]/ { finish_authoritative(); in_authoritative = 0 }
        in_authoritative && /^  -[[:space:]]+path:[[:space:]]*/ {
            finish_authoritative()
            in_authoritative_item = 1
            current_authoritative_path = scalar_value($0)
            next
        }
        in_authoritative && in_authoritative_item && /^    contract:[[:space:]]*/ {
            current_authoritative_contract = scalar_value($0)
            next
        }
        in_authoritative && /^  -/ {
            finish_authoritative()
            in_authoritative_item = 1
            emit("CONTRACT_INDEX_AUTHORITATIVE_PATH", "each authoritative_contracts item must start with a non-empty path")
            next
        }
        /^load_sets:[[:space:]]*$/ {
            finish_authoritative()
            finish_load_set()
            in_load_sets = 1
            load_sets_declared = 1
            next
        }
        in_load_sets && /^[^[:space:]#]/ { finish_load_set(); in_load_sets = 0 }
        in_load_sets && /^  [^[:space:]#][^:]*:[[:space:]]*$/ {
            finish_load_set()
            current_set = trim($0)
            sub(/:.*/, "", current_set)
            load_set_count++
            if (++load_set_seen[current_set] > 1) emit("CONTRACT_INDEX_LOAD_SET_DUPLICATE", "load_sets contains duplicate set \047" current_set "\047")
            in_load_set = 1
            next
        }
        in_load_set && /^    references:[[:space:]]*$/ {
            finish_selector()
            in_selectors = 0
            in_references = 1
            next
        }
        in_load_set && in_references && /^      -[[:space:]]*/ {
            reference = $0
            sub(/^      -[[:space:]]*/, "", reference)
            reference = trim(reference)
            if (reference == "") emit("CONTRACT_INDEX_REFERENCE_PATH", "load set \047" current_set "\047 contains an empty reference path")
            else print "REFERENCE|" current_set "|" reference
            next
        }
        in_load_set && /^    selectors:[[:space:]]*$/ {
            finish_selector()
            in_references = 0
            in_selectors = 1
            has_selectors = 1
            next
        }
        in_load_set && /^    budget_words:[[:space:]]*/ {
            finish_selector()
            in_references = 0
            in_selectors = 0
            budget_count++
            budget_words = scalar_value($0)
            next
        }
        in_load_set && in_selectors && /^      -[[:space:]]+/ {
            finish_selector()
            in_selector = 1
            selector_item = $0
            sub(/^      -[[:space:]]+/, "", selector_item)
            if (selector_item ~ /^id:[[:space:]]*/) current_selector_id = scalar_value(selector_item)
            else if (selector_item ~ /^match:[[:space:]]*/) current_selector_match_seen = 1
            next
        }
        in_selector && /^        id:[[:space:]]*/ { current_list = ""; current_selector_id = scalar_value($0); next }
        in_selector && /^        path:[[:space:]]*/ { current_list = ""; current_selector_path = scalar_value($0); next }
        in_selector && /^        section:[[:space:]]*/ { current_list = ""; current_selector_section = scalar_value($0); next }
        in_selector && /^        key:[[:space:]]*/ { current_list = ""; current_selector_key = scalar_value($0); next }
        in_selector && /^        match:[[:space:]]*/ { current_list = ""; current_selector_match_seen = 1; next }
        in_selector && /^        name_from:[[:space:]]*/ { current_list = ""; current_selector_name_from = scalar_value($0); next }
        in_selector && /^        names:[[:space:]]*/ {
            value = scalar_value($0)
            if (value == "") current_list = "names"
            else { current_list = ""; current_selector_names = list_values(value) }
            next
        }
        in_selector && /^        allowed_names:[[:space:]]*/ {
            value = scalar_value($0)
            if (value == "") current_list = "allowed_names"
            else { current_list = ""; current_selector_allowed = list_values(value) }
            next
        }
        in_selector && current_list != "" && /^          -[[:space:]]*/ {
            value = $0
            sub(/^          -[[:space:]]*/, "", value)
            add_selector_name(current_list, value)
            next
        }
        /^fallback:[[:space:]]*$/ {
            finish_authoritative()
            finish_load_set()
            in_load_sets = 0
            in_fallback = 1
            fallback_declared = 1
            next
        }
        in_fallback && /^[^[:space:]#]/ { in_fallback = 0 }
        in_fallback && /^  on_missing_selector:[[:space:]]*/ { missing_fallback_count++; missing_fallback = scalar_value($0); next }
        in_fallback && /^  on_invalid_selector:[[:space:]]*/ { invalid_fallback_count++; invalid_fallback = scalar_value($0); next }
        END {
            finish_authoritative()
            finish_load_set()
            if (schema_version_count != 1 || schema_version !~ /^[0-9]+[.][0-9]+$/) emit("CONTRACT_INDEX_SCHEMA_VERSION", "index must declare exactly one numeric schema_version such as \0421.0\042")
            if (contract_count != 1 || contract != "index") emit("CONTRACT_INDEX_CONTRACT", "index must declare exactly one top-level contract: index")
            if (skill_count != 1 || skill != expected_skill) emit("CONTRACT_INDEX_SKILL", "index skill must match skill directory name \047" expected_skill "\047")
            for (i = 1; i <= expected_count; i++) if (!(expected[i] in authoritative_count)) emit("CONTRACT_INDEX_AUTHORITATIVE_MISSING", "authoritative_contracts must include required path \047" expected[i] "\047")
            if (!load_sets_declared || load_set_count == 0) emit("CONTRACT_INDEX_LOAD_SETS_EMPTY", "load_sets must contain at least one named load set")
            if (missing_fallback_count == 0) emit("CONTRACT_INDEX_FALLBACK_MISSING", "fallback must declare on_missing_selector: load_full_authoritative_file")
            else if (missing_fallback_count != 1 || missing_fallback != "load_full_authoritative_file") emit("CONTRACT_INDEX_FALLBACK_INVALID", "fallback on_missing_selector must equal load_full_authoritative_file")
            if (invalid_fallback_count == 0) emit("CONTRACT_INDEX_FALLBACK_MISSING", "fallback must declare on_invalid_selector: load_full_authoritative_file")
            else if (invalid_fallback_count != 1 || invalid_fallback != "load_full_authoritative_file") emit("CONTRACT_INDEX_FALLBACK_INVALID", "fallback on_invalid_selector must equal load_full_authoritative_file")
        }
    ' "$index_file")

    base_words=$(( $(wc -w < "$skill_dir/SKILL.md" | tr -d ' ') + $(wc -w < "$index_file" | tr -d ' ') ))
    for ((i = 0; i < ${#load_set_names[@]}; i++)); do
        load_set_words+=("$base_words")
    done

    for row in "${authoritative_rows[@]}"; do
        IFS='|' read -r path declared_type <<< "$row"
        if resolved="$(contract_index_resolve_path "$skill_dir" "$path")"; then
            header_info="$(awk '
                function value(line) { sub(/^[^:]*:[[:space:]]*/, "", line); gsub(/[[:space:]]+$/, "", line); gsub(/^"|"$/, "", line); gsub(/^\047|\047$/, "", line); return line }
                /^contract:[[:space:]]*/ { count++; type = value($0) }
                END { print count "|" type }
            ' "$resolved")"
            IFS='|' read -r header_count header_type <<< "$header_info"
            if [[ "$header_count" != "1" || "$header_type" != "$declared_type" ]]; then
                record_error "CONTRACT_INDEX_AUTHORITATIVE_CONTRACT" "$index_file" "authoritative path '$path' declares contract '$declared_type' but its file header declares '$header_type' $header_count time(s)"
            fi
        else
            status=$?
            case "$status" in
                2) record_error "CONTRACT_INDEX_AUTHORITATIVE_PATH_MISSING" "$index_file" "authoritative path '$path' does not exist under the skill root '$skill_dir'" ;;
                3) record_error "CONTRACT_INDEX_AUTHORITATIVE_PATH_ROOT" "$index_file" "authoritative path '$path' must be canonical and relative to the skill root" ;;
                *) record_error "CONTRACT_INDEX_AUTHORITATIVE_PATH_ROOT" "$index_file" "authoritative path '$path' resolves outside the skill root, including through a symlink" ;;
            esac
        fi
    done

    for row in ${reference_rows[@]+"${reference_rows[@]}"}; do
        IFS='|' read -r load_set reference_path <<< "$row"
        load_index=-1
        for ((i = 0; i < ${#load_set_names[@]}; i++)); do
            [[ "${load_set_names[$i]}" == "$load_set" ]] && load_index=$i
        done
        if resolved="$(contract_index_resolve_path "$skill_dir" "$reference_path")"; then
            if [[ "$load_index" -ge 0 ]]; then
                load_set_words[$load_index]=$(( ${load_set_words[$load_index]} + $(wc -w < "$resolved" | tr -d ' ') ))
            fi
        else
            status=$?
            if [[ "$status" == "2" ]]; then
                record_error "CONTRACT_INDEX_REFERENCE_PATH_MISSING" "$index_file" "reference '$reference_path' in load set '$load_set' does not exist"
            else
                record_error "CONTRACT_INDEX_REFERENCE_PATH_ROOT" "$index_file" "reference '$reference_path' in load set '$load_set' must stay canonically inside the skill root, including through symlinks"
            fi
        fi
    done

    for row in "${selector_rows[@]}"; do
        IFS='|' read -r load_set selector_id path section key mode name_from names <<< "$row"
        load_index=-1
        for ((i = 0; i < ${#load_set_names[@]}; i++)); do
            [[ "${load_set_names[$i]}" == "$load_set" ]] && load_index=$i
        done
        authoritative_found=false
        for ((i = 0; i < ${#authoritative_rows[@]}; i++)); do
            IFS='|' read -r field1 field2 <<< "${authoritative_rows[$i]}"
            [[ "$field1" == "$path" ]] && authoritative_found=true
        done
        if [[ "$authoritative_found" != true ]]; then
            record_error "CONTRACT_INDEX_SELECTOR_AUTHORITATIVE" "$index_file" "selector '$selector_id' path '$path' must name an authoritative_contracts path"
        fi
        if resolved="$(contract_index_resolve_path "$skill_dir" "$path")"; then
            :
        else
            status=$?
            if [[ "$status" == "2" ]]; then
                record_error "CONTRACT_INDEX_SELECTOR_PATH_MISSING" "$index_file" "selector '$selector_id' path '$path' does not exist"
            else
                record_error "CONTRACT_INDEX_SELECTOR_PATH_ROOT" "$index_file" "selector '$selector_id' path '$path' must stay canonically inside the skill root, including through symlinks"
            fi
            continue
        fi
        [[ -n "$names" ]] || continue
        selector_words=0
        first_name=true
        IFS=',' read -r -a field1 <<< "$names"
        for name in "${field1[@]}"; do
            extract_info="$(contract_index_extract_item "$resolved" "$section" "$key" "$name")"
            IFS='|' read -r section_count key_count match_count selected_words <<< "$extract_info"
            if [[ "$first_name" == true ]]; then
                if [[ "$section_count" != "1" ]]; then
                    record_error "CONTRACT_INDEX_SELECTOR_SECTION_UNRESOLVED" "$index_file" "selector '$selector_id' requires exactly one top-level section '$section' in '$path'; found $section_count"
                fi
                if [[ "$key_count" == "0" ]]; then
                    record_error "CONTRACT_INDEX_SELECTOR_KEY_UNRESOLVED" "$index_file" "selector '$selector_id' key '$key' does not exist on any item in section '$section'"
                fi
                first_name=false
            fi
            if [[ "$match_count" == "0" ]]; then
                record_error "CONTRACT_INDEX_SELECTOR_NAME_UNRESOLVED" "$index_file" "selector '$selector_id' name '$name' does not resolve in '$path' section '$section' by key '$key'"
            elif [[ "$match_count" != "1" ]]; then
                record_error "CONTRACT_INDEX_SELECTOR_NAME_AMBIGUOUS" "$index_file" "selector '$selector_id' name '$name' resolves $match_count times; exactly one item is required"
            elif [[ "$selected_words" == "0" ]]; then
                record_error "CONTRACT_INDEX_SELECTOR_CONTENT_UNRESOLVED" "$index_file" "selector '$selector_id' name '$name' resolves to empty content"
            elif [[ "$mode" == "runtime" ]]; then
                (( selected_words > selector_words )) && selector_words=$selected_words
            else
                selector_words=$(( selector_words + selected_words ))
            fi
        done
        if [[ "$load_index" -ge 0 ]]; then
            load_set_words[$load_index]=$(( ${load_set_words[$load_index]} + selector_words ))
        fi
    done

    for ((i = 0; i < ${#load_set_names[@]}; i++)); do
        budget="${load_set_budgets[$i]}"
        actual="${load_set_words[$i]}"
        if [[ "$budget" =~ ^[1-9][0-9]*$ ]] && (( actual >= budget )); then
            record_error "CONTRACT_INDEX_SELECTOR_BUDGET_EXCEEDED" "$index_file" "load set '${load_set_names[$i]}' declared boundary closure is $actual words and must stay strictly below budget_words $budget"
        fi
    done
}

# Keep legacy contract validation unchanged unless the optional progressive index exists.
validate_contract_file() {
    local contract_file="$1"
    local skill_name="$2"
    local contract_name

    contract_name="$(basename -- "$contract_file" .yaml)"
    case "$contract_name" in
        input|output|phase-gates|handoffs)
            validate_contract_header "$contract_file" "$contract_name" "$skill_name"
            validate_enum_values "$contract_file"

            if [[ "$contract_name" == "input" ]]; then
                validate_input_required_actions "$contract_file"
            elif [[ "$contract_name" == "output" ]]; then
                validate_output_required_behaviors "$contract_file"
            fi
            ;;
        index)
            validate_contract_index "$contract_file" "$skill_name"
            ;;
        *)
            record_error "CONTRACT_UNKNOWN" "$contract_file" "unknown contract file; expected input.yaml, output.yaml, phase-gates.yaml, or handoffs.yaml"
            validate_contract_header "$contract_file" "$contract_name" "$skill_name"
            validate_enum_values "$contract_file"
            ;;
    esac
}

usage() {
    cat <<'EOF'
Usage:
  validate-skills.sh [--include-local] [--list]
  validate-skills.sh --skill NAME|PATH [--skill NAME|PATH ...]
  validate-skills.sh --help

Validates Assistant Framework skill metadata and contract files.

Options:
  --skill NAME|PATH   Validate a specific skill by name, skill directory, or SKILL.md path.
  --include-local     Include every skills/*/SKILL.md in the default inventory.
  --list              Print selected skill names and exit.
  -h, --help          Show this help.

Default inventory validates first-class release skills only:
  skills/assistant-*/SKILL.md
EOF
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --skill)
            if [[ "$#" -lt 2 ]]; then
                printf 'ERROR [ARGS] --skill requires NAME or PATH\n' >&2
                exit 2
            fi
            SKILL_SELECTORS+=("$2")
            shift 2
            ;;
        --include-local)
            INCLUDE_LOCAL=true
            shift
            ;;
        --list)
            LIST_ONLY=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'ERROR [ARGS] unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

load_selected_inventory

if [[ "$LIST_ONLY" == true ]]; then
    for skill_file in "${SKILL_FILES[@]:-}"; do
        printf '%s\n' "$(basename -- "$(dirname -- "$skill_file")")"
    done
    exit 0
fi

if [[ "${#SKILL_FILES[@]}" -eq 0 ]]; then
    record_error "INVENTORY_EMPTY" "$REPO_ROOT/skills" "no skills found in selected inventory"
else
    for skill_file in "${SKILL_FILES[@]}"; do
        validate_skill "$skill_file"
    done
fi

if [[ "$FAILURES" -gt 0 ]]; then
    printf 'FAILED skill validation: %s error(s) across %s skill(s)\n' "$FAILURES" "${#SKILL_FILES[@]}" >&2
    exit 1
fi

printf 'OK skill validation: %s skill(s) validated\n' "${#SKILL_FILES[@]}"
