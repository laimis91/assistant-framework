if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

plugin_doc="$FRAMEWORK_DIR/docs/plugin-architecture.md"

p0p4_plugin_boundary() {
    local plugin_name="$1"
    awk -v plugin_name="$plugin_name" '
        /^PLUGIN_BOUNDARY_START$/ { inside = 1; next }
        /^PLUGIN_BOUNDARY_END$/ { inside = 0; next }
        inside && index($0, plugin_name ":") == 1 {
            sub(/^[^:]+:[[:space:]]*/, "")
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^assistant-[a-z0-9-]+$/) {
                    print $i
                }
            }
            exit
        }
    ' "$plugin_doc" | sort
}

p0p4_verify_plugin_skill_inventory() {
    local plugin_name="$1"
    local plugin_skills_dir="$FRAMEWORK_DIR/plugins/$plugin_name/skills"
    local expected_file
    local actual_file
    local missing_file
    local extra_file

    expected_file="$(mktemp "${TMPDIR:-/tmp}/${plugin_name}-boundary.XXXXXX")"
    actual_file="$(mktemp "${TMPDIR:-/tmp}/${plugin_name}-plugin-skills.XXXXXX")"
    missing_file="$(mktemp "${TMPDIR:-/tmp}/${plugin_name}-plugin-missing.XXXXXX")"
    extra_file="$(mktemp "${TMPDIR:-/tmp}/${plugin_name}-plugin-extra.XXXXXX")"
    p0p4_register_cleanup "$expected_file" "$actual_file" "$missing_file" "$extra_file"

    p0p4_plugin_boundary "$plugin_name" >"$expected_file"
    if [[ -d "$plugin_skills_dir" ]]; then
        while IFS= read -r skill_file; do
            basename "$(dirname "$skill_file")"
        done < <(find "$plugin_skills_dir" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print | sort) >"$actual_file"
    fi

    comm -23 "$expected_file" "$actual_file" >"$missing_file"
    comm -13 "$expected_file" "$actual_file" >"$extra_file"
    [[ -s "$expected_file" ]] && [[ ! -s "$missing_file" ]] && [[ ! -s "$extra_file" ]]
}

p0p4_verify_plugin_copy_parity() {
    local plugin_name="$1"
    local plugin_skills_dir="$FRAMEWORK_DIR/plugins/$plugin_name/skills"
    local skill
    local root_skill_dir
    local plugin_skill_dir
    local root_files
    local plugin_files
    local relative_file

    while IFS= read -r skill; do
        root_skill_dir="$FRAMEWORK_DIR/skills/$skill"
        plugin_skill_dir="$plugin_skills_dir/$skill"
        root_files="$(mktemp "${TMPDIR:-/tmp}/${plugin_name}-root-files.XXXXXX")"
        plugin_files="$(mktemp "${TMPDIR:-/tmp}/${plugin_name}-plugin-files.XXXXXX")"
        p0p4_register_cleanup "$root_files" "$plugin_files"

        [[ -d "$root_skill_dir" && -d "$plugin_skill_dir" ]] || return 1

        (cd "$root_skill_dir" && find . -type f ! -name .DS_Store -print | sort) >"$root_files"
        (cd "$plugin_skill_dir" && find . -type f ! -name .DS_Store -print | sort) >"$plugin_files"
        cmp -s "$root_files" "$plugin_files" || return 1

        while IFS= read -r relative_file; do
            cmp -s "$root_skill_dir/$relative_file" "$plugin_skill_dir/$relative_file" || return 1
        done <"$root_files"
    done < <(p0p4_plugin_boundary "$plugin_name")

    [[ -z "$(find "$plugin_skills_dir" -type f -name .DS_Store -print 2>/dev/null)" ]]
}

test_start "assistant-core plugin manifest has valid Codex scaffold metadata"
if [[ -f "$FRAMEWORK_DIR/plugins/assistant-core/.codex-plugin/plugin.json" ]] \
    && jq -e '
        .name == "assistant-core"
        and .version == "0.1.0"
        and .description == "Foundation skills for clarification, memory, reflexion, and Telos context."
        and .repository == "https://github.com/laimis91/assistant-framework"
        and .skills == "./skills/"
        and (has("hooks") | not)
        and (has("mcpServers") | not)
        and (has("apps") | not)
        and .interface.displayName == "Assistant Core"
        and .interface.shortDescription == "Foundation context and clarification skills"
        and .interface.category == "Productivity"
        and (.interface.capabilities == ["Interactive"])
        and (.interface.defaultPrompt | length == 3)
    ' "$FRAMEWORK_DIR/plugins/assistant-core/.codex-plugin/plugin.json" >/dev/null; then
    pass
else
    fail "assistant-core plugin manifest must exist with filled scaffold metadata"
fi

test_start "assistant-research plugin manifest has valid Codex scaffold metadata"
if [[ -f "$FRAMEWORK_DIR/plugins/assistant-research/.codex-plugin/plugin.json" ]] \
    && jq -e '
        .name == "assistant-research"
        and .version == "0.1.0"
        and .description == "Research, ideation, and structured thinking skills."
        and .repository == "https://github.com/laimis91/assistant-framework"
        and .skills == "./skills/"
        and (has("hooks") | not)
        and (has("mcpServers") | not)
        and (has("apps") | not)
        and .interface.displayName == "Assistant Research"
        and .interface.shortDescription == "Research, ideation, and thinking skills"
        and .interface.category == "Productivity"
        and (.interface.capabilities == ["Interactive"])
        and (.interface.defaultPrompt | length == 3)
    ' "$FRAMEWORK_DIR/plugins/assistant-research/.codex-plugin/plugin.json" >/dev/null; then
    pass
else
    fail "assistant-research plugin manifest must exist with filled scaffold metadata"
fi

test_start "assistant-core plugin-local skills match boundary ownership"
if p0p4_verify_plugin_skill_inventory "assistant-core"; then
    pass
else
    fail "assistant-core plugin skills must match boundary ownership"
fi

test_start "assistant-research plugin-local skills match boundary ownership"
if p0p4_verify_plugin_skill_inventory "assistant-research"; then
    pass
else
    fail "assistant-research plugin skills must match boundary ownership"
fi

test_start "assistant-core plugin-local skill copies match root source skills"
if p0p4_verify_plugin_copy_parity "assistant-core"; then
    pass
else
    fail "assistant-core plugin skill copies must match root source without .DS_Store files"
fi

test_start "assistant-research plugin-local skill copies match root source skills"
if p0p4_verify_plugin_copy_parity "assistant-research"; then
    pass
else
    fail "assistant-research plugin skill copies must match root source without .DS_Store files"
fi

test_start "assistant plugin scaffolds are documented without marketplace registration"
marketplace_file="$FRAMEWORK_DIR/.agents/plugins/marketplace.json"
if grep -Fq "plugins/assistant-core/.codex-plugin/plugin.json" "$plugin_doc" \
    && grep -Fq "plugins/assistant-research/.codex-plugin/plugin.json" "$plugin_doc" \
    && grep -Fq "plugin-local copies of the four core skills" "$plugin_doc" \
    && grep -Fq "plugin-local copies of the three research skills" "$plugin_doc" \
    && grep -Fq "manifest-aware dry-run validation" "$plugin_doc" \
    && grep -Fq "plugin-local copies of the four core skills" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "plugin-local copies of the three research skills" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "manifest-aware dry-run validation" "$FRAMEWORK_DIR/README.md" \
    && [[ ! -f "$marketplace_file" ]]; then
    pass
else
    fail "assistant plugin scaffold docs must describe manifests/copies and avoid marketplace registration"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
