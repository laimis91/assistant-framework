if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

plugin_doc="$FRAMEWORK_DIR/docs/plugin-architecture.md"
plugin_root="$FRAMEWORK_DIR/plugins/assistant-core"
plugin_manifest="$plugin_root/.codex-plugin/plugin.json"
plugin_skills_dir="$plugin_root/skills"

p0p4_assistant_core_boundary() {
    awk '
        /^PLUGIN_BOUNDARY_START$/ { inside = 1; next }
        /^PLUGIN_BOUNDARY_END$/ { inside = 0; next }
        inside && /^assistant-core:/ {
            sub(/^assistant-core:[[:space:]]*/, "")
            for (i = 1; i <= NF; i++) {
                print $i
            }
            exit
        }
    ' "$plugin_doc" | sort
}

test_start "assistant-core plugin manifest has valid Codex scaffold metadata"
if [[ -f "$plugin_manifest" ]] \
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
    ' "$plugin_manifest" >/dev/null; then
    pass
else
    fail "assistant-core plugin manifest must exist with filled scaffold metadata"
fi

test_start "assistant-core plugin-local skills match boundary ownership"
expected_file="$(mktemp "${TMPDIR:-/tmp}/assistant-core-boundary.XXXXXX")"
actual_file="$(mktemp "${TMPDIR:-/tmp}/assistant-core-plugin-skills.XXXXXX")"
missing_file="$(mktemp "${TMPDIR:-/tmp}/assistant-core-plugin-missing.XXXXXX")"
extra_file="$(mktemp "${TMPDIR:-/tmp}/assistant-core-plugin-extra.XXXXXX")"
p0p4_register_cleanup "$expected_file" "$actual_file" "$missing_file" "$extra_file"
p0p4_assistant_core_boundary >"$expected_file"
if [[ -d "$plugin_skills_dir" ]]; then
    while IFS= read -r skill_file; do
        basename "$(dirname "$skill_file")"
    done < <(find "$plugin_skills_dir" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print | sort) >"$actual_file"
fi
comm -23 "$expected_file" "$actual_file" >"$missing_file"
comm -13 "$expected_file" "$actual_file" >"$extra_file"
if [[ -s "$expected_file" ]] && [[ ! -s "$missing_file" ]] && [[ ! -s "$extra_file" ]]; then
    pass
else
    fail "assistant-core plugin skills must match boundary; missing=$(tr '\n' ' ' <"$missing_file") extra=$(tr '\n' ' ' <"$extra_file")"
fi

test_start "assistant-core plugin-local skill copies match root source skills"
mismatch=""
while IFS= read -r skill; do
    root_skill_dir="$FRAMEWORK_DIR/skills/$skill"
    plugin_skill_dir="$plugin_skills_dir/$skill"
    root_files="$(mktemp "${TMPDIR:-/tmp}/assistant-core-root-files.XXXXXX")"
    plugin_files="$(mktemp "${TMPDIR:-/tmp}/assistant-core-plugin-files.XXXXXX")"
    p0p4_register_cleanup "$root_files" "$plugin_files"

    if [[ ! -d "$root_skill_dir" || ! -d "$plugin_skill_dir" ]]; then
        mismatch="$skill missing directory"
        break
    fi

    (cd "$root_skill_dir" && find . -type f ! -name .DS_Store -print | sort) >"$root_files"
    (cd "$plugin_skill_dir" && find . -type f ! -name .DS_Store -print | sort) >"$plugin_files"
    if ! cmp -s "$root_files" "$plugin_files"; then
        mismatch="$skill file inventory differs"
        break
    fi

    while IFS= read -r relative_file; do
        if ! cmp -s "$root_skill_dir/$relative_file" "$plugin_skill_dir/$relative_file"; then
            mismatch="$skill/$relative_file differs"
            break
        fi
    done <"$root_files"

    [[ -z "$mismatch" ]] || break
done < <(p0p4_assistant_core_boundary)
if [[ -z "$mismatch" ]] && [[ -z "$(find "$plugin_skills_dir" -type f -name .DS_Store -print 2>/dev/null)" ]]; then
    pass
else
    fail "assistant-core plugin skill copies must match root source without .DS_Store files: $mismatch"
fi

test_start "assistant-core scaffold is documented without marketplace registration"
marketplace_file="$FRAMEWORK_DIR/.agents/plugins/marketplace.json"
if grep -Fq "plugins/assistant-core/.codex-plugin/plugin.json" "$plugin_doc" \
    && grep -Fq "plugin-local copies of the four core skills" "$plugin_doc" \
    && grep -Fq "manifest-aware dry-run validation" "$plugin_doc" \
    && grep -Fq "plugin-local copies of the four core skills" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "manifest-aware dry-run validation" "$FRAMEWORK_DIR/README.md" \
    && [[ ! -f "$marketplace_file" ]]; then
    pass
else
    fail "assistant-core scaffold docs must describe manifest/copies and avoid marketplace registration"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
