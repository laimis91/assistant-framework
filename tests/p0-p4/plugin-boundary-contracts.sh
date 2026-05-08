if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

plugin_doc="$FRAMEWORK_DIR/docs/plugin-architecture.md"

p0p4_plugin_assignments() {
    awk '
        /^PLUGIN_BOUNDARY_START$/ { inside = 1; next }
        /^PLUGIN_BOUNDARY_END$/ { inside = 0; next }
        inside && /^[a-z0-9-]+:/ {
            sub(/^[^:]+:[[:space:]]*/, "")
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^assistant-[a-z0-9-]+$/) {
                    print $i
                }
            }
        }
    ' "$plugin_doc" | sort
}

test_start "plugin architecture doc exists and preserves current install compatibility"
if [[ -f "$plugin_doc" ]] \
    && grep -Fq "current_install_inventory: skills/assistant-*/SKILL.md" "$plugin_doc" \
    && grep -Fq "current_plugin_profiles: assistant-core via --plugin assistant-core; assistant-research via --plugin assistant-research; assistant-dev via --plugin assistant-dev" "$plugin_doc" \
    && grep -Fq "current_plugin_manifests: plugins/assistant-core/.codex-plugin/plugin.json plugins/assistant-research/.codex-plugin/plugin.json plugins/assistant-dev/.codex-plugin/plugin.json" "$plugin_doc" \
    && grep -Fq "no root skill directories move in this slice" "$plugin_doc" \
    && grep -Fq "Auto-discovers first-class release skills from skills/assistant-*/SKILL.md" "$FRAMEWORK_DIR/install.sh"; then
    pass
else
    fail "plugin architecture doc must preserve current root assistant-skill install behavior"
fi

test_start "plugin architecture defines required planned plugin groups"
if grep -Fq "assistant-core:" "$plugin_doc" \
    && grep -Fq "assistant-dev:" "$plugin_doc" \
    && grep -Fq "assistant-research:" "$plugin_doc" \
    && grep -Fq "assistant-unity: skills/unity-*" "$plugin_doc"; then
    pass
else
    fail "plugin architecture doc is missing one or more planned plugin groups"
fi

test_start "plugin boundary assigns every tracked assistant skill exactly once"
inventory_file="$(mktemp "${TMPDIR:-/tmp}/plugin-boundary-inventory.XXXXXX")"
assigned_file="$(mktemp "${TMPDIR:-/tmp}/plugin-boundary-assigned.XXXXXX")"
duplicates_file="$(mktemp "${TMPDIR:-/tmp}/plugin-boundary-duplicates.XXXXXX")"
missing_file="$(mktemp "${TMPDIR:-/tmp}/plugin-boundary-missing.XXXXXX")"
extra_file="$(mktemp "${TMPDIR:-/tmp}/plugin-boundary-extra.XXXXXX")"
p0p4_register_cleanup "$inventory_file" "$assigned_file" "$duplicates_file" "$missing_file" "$extra_file"
while IFS= read -r skill_file; do
    basename "$(dirname "$skill_file")"
done < <(find "$FRAMEWORK_DIR/skills" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -path "$FRAMEWORK_DIR/skills/assistant-*/SKILL.md" -print | sort) >"$inventory_file"
p0p4_plugin_assignments >"$assigned_file"
sort "$assigned_file" | uniq -d >"$duplicates_file"
comm -23 "$inventory_file" "$assigned_file" >"$missing_file"
comm -13 "$inventory_file" "$assigned_file" >"$extra_file"
if [[ -s "$inventory_file" ]] \
    && [[ ! -s "$duplicates_file" ]] \
    && [[ ! -s "$missing_file" ]] \
    && [[ ! -s "$extra_file" ]]; then
    pass
else
    fail "plugin assignments must match tracked assistant skills exactly; missing=$(tr '\n' ' ' <"$missing_file") extra=$(tr '\n' ' ' <"$extra_file") duplicate=$(tr '\n' ' ' <"$duplicates_file")"
fi

test_start "plugin plan keeps Unity local-only and out of tracked release skills"
if grep -Fq "assistant-unity: skills/unity-*" "$plugin_doc" \
    && grep -Fq "Unity skills remain local-only in the current release" "$plugin_doc" \
    && [[ -z "$(git -C "$FRAMEWORK_DIR" ls-files 'skills/unity-*')" ]]; then
    pass
else
    fail "plugin plan must keep Unity skills local-only and untracked in the release inventory"
fi

test_start "README documents installable plugin profiles without changing current installer semantics"
if grep -Fq "Plugin boundaries are contract-backed" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "docs/plugin-architecture.md" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "./install.sh --agent codex --plugin assistant-core" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "./install.sh --agent codex --plugin assistant-research" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "./install.sh --agent codex --plugin assistant-dev" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "uses the root \`skills/assistant-*\` release inventory by default" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "The release inventory is the tracked \`skills/assistant-*\` set." "$FRAMEWORK_DIR/README.md"; then
    pass
else
    fail "README must document installable profiles while preserving current root installer semantics"
fi

test_start "plugin scaffold slice exposes core, research, and dev manifests only"
manifest_output="$(find "$FRAMEWORK_DIR" \
    -path "$FRAMEWORK_DIR/.git" -prune -o \
    \( -path "*/.codex-plugin/plugin.json" -o -name plugin.json \) -print | sort)"
expected_manifest_output="$(printf '%s\n%s\n%s\n' \
    "$FRAMEWORK_DIR/plugins/assistant-core/.codex-plugin/plugin.json" \
    "$FRAMEWORK_DIR/plugins/assistant-dev/.codex-plugin/plugin.json" \
    "$FRAMEWORK_DIR/plugins/assistant-research/.codex-plugin/plugin.json" | sort)"
if [[ "$manifest_output" == "$expected_manifest_output" ]]; then
    pass
else
    fail "only assistant-core, assistant-research, and assistant-dev plugin manifests should exist in this scaffold slice: $manifest_output"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
