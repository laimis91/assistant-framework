if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

p0p4_file_mode_octal() {
    local path="$1"
    case "$(uname -s)" in
        Darwin|FreeBSD)
            stat -f "%Lp" "$path"
            ;;
        *)
            stat -c "%a" "$path"
            ;;
    esac
}

legacy_orchestrator_role="You are an orchestrator. You delegate ALL ""file editing, code implementation, and phase execution to specialized agents."
stale_generated_phrase="delegate ALL ""file editing, code implementation, and phase execution"

p0p4_path_without_jq() {
    local tmpbin="$1"
    local d
    local f
    local name

    mkdir -p "$tmpbin"
    for d in /bin /usr/bin /usr/sbin /sbin; do
        [[ -d "$d" ]] || continue
        for f in "$d"/*; do
            name="$(basename "$f")"
            [[ "$name" == "jq" ]] && continue
            [[ -e "$tmpbin/$name" ]] || ln -s "$f" "$tmpbin/$name" 2>/dev/null || true
        done
    done
}

test_start "Codex reinstall keeps one lean framework block and one memory protocol block"
INSTALL_HOME="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME"
if HOME="$INSTALL_HOME" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-1.out 2>/tmp/p0p4-install-1.err; then
    if HOME="$INSTALL_HOME" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-2.out 2>/tmp/p0p4-install-2.err; then
        agents_file="$INSTALL_HOME/.codex/AGENTS.md"
        starts="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START" "$agents_file")"
        ends="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END" "$agents_file")"
        preambles="$(count_occurrences "^# Assistant Framework — Memory Protocol$" "$agents_file")"
        agents_starts="$(count_occurrences "ASSISTANT_FRAMEWORK_AGENTS_MD_START" "$agents_file")"
        agents_ends="$(count_occurrences "ASSISTANT_FRAMEWORK_AGENTS_MD_END" "$agents_file")"
        operating_stances="$(count_occurrences "^## Operating stance$" "$agents_file")"
        if [[ "$starts" == "1" && "$ends" == "1" && "$preambles" == "1" ]] \
            && [[ "$agents_starts" == "1" && "$agents_ends" == "1" ]] \
            && [[ "$operating_stances" == "1" ]] \
            && ! grep -Fq "$stale_generated_phrase" "$agents_file" \
            && grep -Fq "Codex uses installed skills through native skill routing." "$agents_file" \
            && grep -Fq "load only the references or contracts relevant to the current phase" "$agents_file" \
            && grep -Fq "For small, low-risk, localized work, act as a hands-on worker" "$agents_file" \
            && grep -Fq "For medium+ or elevated-risk development work, remain the orchestrator" "$agents_file" \
            && grep -Fq "Keep orchestration proportional" "$agents_file" \
            && grep -Fq "Get plan approval before medium+ or risky edits." "$agents_file" \
            && grep -Fq "Do not spawn subagents without explicit authorization; continue safe non-spawn work while authorization is unresolved." "$agents_file" \
            && ! grep -Fq "## Skills (loaded" "$agents_file" \
            && [[ -f "$INSTALL_HOME/.codex/agents/code-reviewer.toml" ]] \
            && grep -Fq 'sandbox_mode = "read-only"' "$INSTALL_HOME/.codex/agents/code-reviewer.toml" \
            && ! grep -Fq "The orchestrator owns framework state files" "$agents_file" \
            && ! grep -Fq ".codex/context-map.md" "$agents_file" \
            && ! grep -Fq "Do not infer that subagents are unavailable from the absence of a visible tool name" "$agents_file" \
            && grep -Fq "Preserve user-authored files and existing dirty work." "$agents_file"; then
            pass
        else
            fail "expected one lean native-Codex framework block and one current memory protocol block"
        fi
    else
        fail "second install failed; see /tmp/p0p4-install-2.err"
    fi
else
    fail "first install failed; see /tmp/p0p4-install-1.err"
fi

test_start "Codex single-skill install keeps routing metadata in the installed skill"
INSTALL_HOME_SKILL_TABLE="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_SKILL_TABLE"
if HOME="$INSTALL_HOME_SKILL_TABLE" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-single-skill-table.out 2>/tmp/p0p4-install-single-skill-table.err; then
    agents_file="$INSTALL_HOME_SKILL_TABLE/.codex/AGENTS.md"
    installed_skills_dir="$INSTALL_HOME_SKILL_TABLE/.codex/skills"
    assistant_skill_rows="$(count_occurrences "^| assistant-" "$agents_file")"

    if [[ ! -d "$installed_skills_dir/assistant-workflow" ]]; then
        fail "expected assistant-workflow to be installed"
    elif [[ -d "$installed_skills_dir/assistant-review" || -d "$installed_skills_dir/assistant-docs" ]]; then
        fail "expected single-skill install to avoid installing assistant-review and assistant-docs"
    elif [[ "$assistant_skill_rows" != "0" ]]; then
        fail "expected lean Codex AGENTS.md to avoid duplicating installed skill routing tables; found $assistant_skill_rows rows"
    elif ! grep -Fq "Codex uses installed skills through native skill routing." "$agents_file"; then
        fail "expected generated Codex AGENTS.md to delegate routing to the installed SKILL.md"
    else
        pass
    fi
else
    fail "single-skill Codex install failed; see /tmp/p0p4-install-single-skill-table.err"
fi

test_start "Codex plugin profile dry-run selects assistant-core skills only"
INSTALL_HOME_PLUGIN_DRY="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_PLUGIN_DRY"
if HOME="$INSTALL_HOME_PLUGIN_DRY" bash "$FRAMEWORK_DIR/install.sh" --agent codex --plugin assistant-core --no-hooks --dry-run >/tmp/p0p4-install-plugin-dry.out 2>/tmp/p0p4-install-plugin-dry.err; then
    plugin_dry_output="$(cat /tmp/p0p4-install-plugin-dry.out)"
    if printf '%s\n' "$plugin_dry_output" | grep -Fq "Plugin profile: assistant-core" \
        && printf '%s\n' "$plugin_dry_output" | grep -Fq "Plugin manifest: $FRAMEWORK_DIR/plugins/assistant-core/.codex-plugin/plugin.json" \
        && printf '%s\n' "$plugin_dry_output" | grep -Fq "[dry-run] Validate plugin manifest: assistant-core -> ./skills/" \
        && printf '%s\n' "$plugin_dry_output" | grep -Fq "[dry-run] Plugin manifest skills match profile boundary: assistant-clarify assistant-memory assistant-reflexion assistant-telos" \
        && printf '%s\n' "$plugin_dry_output" | grep -Fq "skills/assistant-clarify/" \
        && printf '%s\n' "$plugin_dry_output" | grep -Fq "skills/assistant-memory/" \
        && printf '%s\n' "$plugin_dry_output" | grep -Fq "skills/assistant-reflexion/" \
        && printf '%s\n' "$plugin_dry_output" | grep -Fq "skills/assistant-telos/" \
        && ! printf '%s\n' "$plugin_dry_output" | grep -Fq "skills/assistant-workflow/" \
        && ! printf '%s\n' "$plugin_dry_output" | grep -Fq "skills/assistant-research/" \
        && ! printf '%s\n' "$plugin_dry_output" | grep -Fq "skills/assistant-security/"; then
        pass
    else
        fail "assistant-core dry-run should list only core plugin skills"
    fi
else
    fail "assistant-core dry-run failed; see /tmp/p0p4-install-plugin-dry.err"
fi

test_start "Codex plugin profile dry-run selects assistant-research skills only"
INSTALL_HOME_PLUGIN_RESEARCH_DRY="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_PLUGIN_RESEARCH_DRY"
if HOME="$INSTALL_HOME_PLUGIN_RESEARCH_DRY" bash "$FRAMEWORK_DIR/install.sh" --agent codex --plugin assistant-research --no-hooks --dry-run >/tmp/p0p4-install-plugin-research-dry.out 2>/tmp/p0p4-install-plugin-research-dry.err; then
    plugin_research_dry_output="$(cat /tmp/p0p4-install-plugin-research-dry.out)"
    if printf '%s\n' "$plugin_research_dry_output" | grep -Fq "Plugin profile: assistant-research" \
        && printf '%s\n' "$plugin_research_dry_output" | grep -Fq "Plugin manifest: $FRAMEWORK_DIR/plugins/assistant-research/.codex-plugin/plugin.json" \
        && printf '%s\n' "$plugin_research_dry_output" | grep -Fq "[dry-run] Validate plugin manifest: assistant-research -> ./skills/" \
        && printf '%s\n' "$plugin_research_dry_output" | grep -Fq "[dry-run] Plugin manifest skills match profile boundary: assistant-ideate assistant-research assistant-thinking" \
        && printf '%s\n' "$plugin_research_dry_output" | grep -Fq "skills/assistant-ideate/" \
        && printf '%s\n' "$plugin_research_dry_output" | grep -Fq "skills/assistant-research/" \
        && printf '%s\n' "$plugin_research_dry_output" | grep -Fq "skills/assistant-thinking/" \
        && ! printf '%s\n' "$plugin_research_dry_output" | grep -Fq "skills/assistant-workflow/" \
        && ! printf '%s\n' "$plugin_research_dry_output" | grep -Fq "skills/assistant-security/" \
        && ! printf '%s\n' "$plugin_research_dry_output" | grep -Fq "skills/assistant-memory/"; then
        pass
    else
        fail "assistant-research dry-run should list only research plugin skills"
    fi
else
    fail "assistant-research dry-run failed; see /tmp/p0p4-install-plugin-research-dry.err"
fi

test_start "Codex plugin profile dry-run selects assistant-dev skills only"
INSTALL_HOME_PLUGIN_DEV_DRY="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_PLUGIN_DEV_DRY"
if HOME="$INSTALL_HOME_PLUGIN_DEV_DRY" bash "$FRAMEWORK_DIR/install.sh" --agent codex --plugin assistant-dev --no-hooks --dry-run >/tmp/p0p4-install-plugin-dev-dry.out 2>/tmp/p0p4-install-plugin-dev-dry.err; then
    plugin_dev_dry_output="$(cat /tmp/p0p4-install-plugin-dev-dry.out)"
    if printf '%s\n' "$plugin_dev_dry_output" | grep -Fq "Plugin profile: assistant-dev" \
        && printf '%s\n' "$plugin_dev_dry_output" | grep -Fq "Plugin manifest: $FRAMEWORK_DIR/plugins/assistant-dev/.codex-plugin/plugin.json" \
        && printf '%s\n' "$plugin_dev_dry_output" | grep -Fq "[dry-run] Validate plugin manifest: assistant-dev -> ./skills/" \
        && printf '%s\n' "$plugin_dev_dry_output" | grep -Fq "[dry-run] Plugin manifest skills match profile boundary: assistant-debugging assistant-diagrams assistant-docs assistant-onboard assistant-review assistant-security assistant-skill-creator assistant-tdd assistant-workflow" \
        && printf '%s\n' "$plugin_dev_dry_output" | grep -Fq "skills/assistant-debugging/" \
        && printf '%s\n' "$plugin_dev_dry_output" | grep -Fq "skills/assistant-diagrams/" \
        && printf '%s\n' "$plugin_dev_dry_output" | grep -Fq "skills/assistant-docs/" \
        && printf '%s\n' "$plugin_dev_dry_output" | grep -Fq "skills/assistant-onboard/" \
        && printf '%s\n' "$plugin_dev_dry_output" | grep -Fq "skills/assistant-review/" \
        && printf '%s\n' "$plugin_dev_dry_output" | grep -Fq "skills/assistant-security/" \
        && printf '%s\n' "$plugin_dev_dry_output" | grep -Fq "skills/assistant-skill-creator/" \
        && printf '%s\n' "$plugin_dev_dry_output" | grep -Fq "skills/assistant-tdd/" \
        && printf '%s\n' "$plugin_dev_dry_output" | grep -Fq "skills/assistant-workflow/" \
        && ! printf '%s\n' "$plugin_dev_dry_output" | grep -Fq "skills/assistant-memory/" \
        && ! printf '%s\n' "$plugin_dev_dry_output" | grep -Fq "skills/assistant-research/" \
        && ! printf '%s\n' "$plugin_dev_dry_output" | grep -Fq "skills/assistant-thinking/"; then
        pass
    else
        fail "assistant-dev dry-run should list only development plugin skills"
    fi
else
    fail "assistant-dev dry-run failed; see /tmp/p0p4-install-plugin-dev-dry.err"
fi

test_start "Codex plugin profile dry-run rejects manifest skill drift"
INSTALL_HOME_PLUGIN_DRY_DRIFT="$(mktemp -d)"
PLUGIN_MANIFEST="$FRAMEWORK_DIR/plugins/assistant-core/.codex-plugin/plugin.json"
PLUGIN_MANIFEST_BACKUP="$(mktemp "${TMPDIR:-/tmp}/assistant-core-plugin-json.XXXXXX")"
p0p4_register_cleanup "$INSTALL_HOME_PLUGIN_DRY_DRIFT" "$PLUGIN_MANIFEST_BACKUP"
cp "$PLUGIN_MANIFEST" "$PLUGIN_MANIFEST_BACKUP"
jq 'del(.skills)' "$PLUGIN_MANIFEST_BACKUP" >"$PLUGIN_MANIFEST"
if HOME="$INSTALL_HOME_PLUGIN_DRY_DRIFT" bash "$FRAMEWORK_DIR/install.sh" --agent codex --plugin assistant-core --no-hooks --dry-run >/tmp/p0p4-install-plugin-dry-drift.out 2>/tmp/p0p4-install-plugin-dry-drift.err; then
    cp "$PLUGIN_MANIFEST_BACKUP" "$PLUGIN_MANIFEST"
    fail "assistant-core dry-run should reject a manifest without skills metadata"
elif grep -Fq "Plugin manifest assistant-core must declare skills: ./skills/" /tmp/p0p4-install-plugin-dry-drift.err; then
    cp "$PLUGIN_MANIFEST_BACKUP" "$PLUGIN_MANIFEST"
    pass
else
    cp "$PLUGIN_MANIFEST_BACKUP" "$PLUGIN_MANIFEST"
    fail "assistant-core dry-run drift rejection should explain manifest skills metadata"
fi

test_start "Codex assistant-core plugin install installs only core skills with lean AGENTS guidance"
INSTALL_HOME_PLUGIN="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_PLUGIN"
if HOME="$INSTALL_HOME_PLUGIN" bash "$FRAMEWORK_DIR/install.sh" --agent codex --plugin assistant-core --no-hooks >/tmp/p0p4-install-plugin-core.out 2>/tmp/p0p4-install-plugin-core.err; then
    installed_skills_dir="$INSTALL_HOME_PLUGIN/.codex/skills"
    agents_file="$INSTALL_HOME_PLUGIN/.codex/AGENTS.md"
    agents_assistant_skill_rows="$(count_occurrences "^| assistant-" "$agents_file")"
    missing_core_skill=""
    unexpected_profile_skill=""
    for core_skill in assistant-clarify assistant-memory assistant-reflexion assistant-telos; do
        if [[ ! -d "$installed_skills_dir/$core_skill" ]]; then
            missing_core_skill="$core_skill"
            break
        fi
    done
    for non_core_skill in assistant-workflow assistant-review assistant-security assistant-research assistant-thinking assistant-docs; do
        if [[ -d "$installed_skills_dir/$non_core_skill" ]]; then
            unexpected_profile_skill="$non_core_skill"
            break
        fi
    done

    if [[ -n "$missing_core_skill" ]]; then
        fail "assistant-core plugin install missed $missing_core_skill"
    elif [[ -n "$unexpected_profile_skill" ]]; then
        fail "assistant-core plugin install included non-core skill $unexpected_profile_skill"
    elif [[ "$agents_assistant_skill_rows" != "0" ]] || ! grep -Fq "Codex uses installed skills through native skill routing." "$agents_file"; then
        fail "expected assistant-core Codex AGENTS.md to stay lean and delegate routing to installed skills"
    else
        pass
    fi
else
    fail "assistant-core plugin install failed; see /tmp/p0p4-install-plugin-core.err"
fi

test_start "Codex assistant-research plugin install installs only research skills with lean AGENTS guidance"
INSTALL_HOME_PLUGIN_RESEARCH="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_PLUGIN_RESEARCH"
if HOME="$INSTALL_HOME_PLUGIN_RESEARCH" bash "$FRAMEWORK_DIR/install.sh" --agent codex --plugin assistant-research --no-hooks >/tmp/p0p4-install-plugin-research.out 2>/tmp/p0p4-install-plugin-research.err; then
    installed_research_skills_dir="$INSTALL_HOME_PLUGIN_RESEARCH/.codex/skills"
    research_agents_file="$INSTALL_HOME_PLUGIN_RESEARCH/.codex/AGENTS.md"
    research_agents_assistant_skill_rows="$(count_occurrences "^| assistant-" "$research_agents_file")"
    missing_research_skill=""
    unexpected_research_profile_skill=""
    for research_skill in assistant-ideate assistant-research assistant-thinking; do
        if [[ ! -d "$installed_research_skills_dir/$research_skill" ]]; then
            missing_research_skill="$research_skill"
            break
        fi
    done
    for non_research_skill in assistant-workflow assistant-review assistant-security assistant-memory assistant-telos assistant-docs; do
        if [[ -d "$installed_research_skills_dir/$non_research_skill" ]]; then
            unexpected_research_profile_skill="$non_research_skill"
            break
        fi
    done

    if [[ -n "$missing_research_skill" ]]; then
        fail "assistant-research plugin install missed $missing_research_skill"
    elif [[ -n "$unexpected_research_profile_skill" ]]; then
        fail "assistant-research plugin install included non-research skill $unexpected_research_profile_skill"
    elif [[ "$research_agents_assistant_skill_rows" != "0" ]] || ! grep -Fq "Codex uses installed skills through native skill routing." "$research_agents_file"; then
        fail "expected assistant-research Codex AGENTS.md to stay lean and delegate routing to installed skills"
    else
        pass
    fi
else
    fail "assistant-research plugin install failed; see /tmp/p0p4-install-plugin-research.err"
fi

test_start "Codex assistant-dev plugin install installs only development skills with lean AGENTS guidance"
INSTALL_HOME_PLUGIN_DEV="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_PLUGIN_DEV"
if HOME="$INSTALL_HOME_PLUGIN_DEV" bash "$FRAMEWORK_DIR/install.sh" --agent codex --plugin assistant-dev --no-hooks >/tmp/p0p4-install-plugin-dev.out 2>/tmp/p0p4-install-plugin-dev.err; then
    installed_dev_skills_dir="$INSTALL_HOME_PLUGIN_DEV/.codex/skills"
    dev_agents_file="$INSTALL_HOME_PLUGIN_DEV/.codex/AGENTS.md"
    dev_agents_assistant_skill_rows="$(count_occurrences "^| assistant-" "$dev_agents_file")"
    missing_dev_skill=""
    unexpected_dev_profile_skill=""
    for dev_skill in assistant-debugging assistant-diagrams assistant-docs assistant-onboard assistant-review assistant-security assistant-skill-creator assistant-tdd assistant-workflow; do
        if [[ ! -d "$installed_dev_skills_dir/$dev_skill" ]]; then
            missing_dev_skill="$dev_skill"
            break
        fi
    done
    for non_dev_skill in assistant-clarify assistant-memory assistant-reflexion assistant-telos assistant-ideate assistant-research assistant-thinking; do
        if [[ -d "$installed_dev_skills_dir/$non_dev_skill" ]]; then
            unexpected_dev_profile_skill="$non_dev_skill"
            break
        fi
    done

    if [[ -n "$missing_dev_skill" ]]; then
        fail "assistant-dev plugin install missed $missing_dev_skill"
    elif [[ -n "$unexpected_dev_profile_skill" ]]; then
        fail "assistant-dev plugin install included non-development skill $unexpected_dev_profile_skill"
    elif [[ "$dev_agents_assistant_skill_rows" != "0" ]] || ! grep -Fq "Codex uses installed skills through native skill routing." "$dev_agents_file"; then
        fail "expected assistant-dev Codex AGENTS.md to stay lean and delegate routing to installed skills"
    else
        pass
    fi
else
    fail "assistant-dev plugin install failed; see /tmp/p0p4-install-plugin-dev.err"
fi

test_start "installer rejects boundary-only profiles without Unity hardcoding"
INSTALL_HOME_PLUGIN_UNITY="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_PLUGIN_UNITY"
if HOME="$INSTALL_HOME_PLUGIN_UNITY" bash "$FRAMEWORK_DIR/install.sh" --agent codex --plugin assistant-unity --no-hooks >/tmp/p0p4-install-plugin-unity.out 2>/tmp/p0p4-install-plugin-unity.err; then
    fail "assistant-unity boundary profile should not install until it has P0/P4 coverage"
elif grep -Fq "assistant-unity is boundary-defined but not installable yet" /tmp/p0p4-install-plugin-unity.err \
    && grep -Fq "assistant-core" /tmp/p0p4-install-plugin-unity.err \
    && grep -Fq "assistant-research" /tmp/p0p4-install-plugin-unity.err \
    && grep -Fq "assistant-dev" /tmp/p0p4-install-plugin-unity.err \
    && ! grep -Fq "assistant-unity is local-only" "$FRAMEWORK_DIR/install.sh" \
    && ! grep -Fq "skills/unity-*" "$FRAMEWORK_DIR/install.sh"; then
    pass
else
    fail "assistant-unity should use the generic boundary-only rejection without Unity-specific installer code"
fi

test_start "installer rejects unknown plugin profiles"
INSTALL_HOME_PLUGIN_UNKNOWN="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_PLUGIN_UNKNOWN"
if HOME="$INSTALL_HOME_PLUGIN_UNKNOWN" bash "$FRAMEWORK_DIR/install.sh" --agent codex --plugin assistant-unknown --no-hooks >/tmp/p0p4-install-plugin-unknown.out 2>/tmp/p0p4-install-plugin-unknown.err; then
    fail "unknown plugin profile should not install"
elif grep -Fq "Unknown plugin profile: assistant-unknown" /tmp/p0p4-install-plugin-unknown.err \
    && grep -Fq "Available install profiles are defined in docs/plugin-architecture.md" /tmp/p0p4-install-plugin-unknown.err; then
    pass
else
    fail "unknown plugin profile rejection should explain where profiles are defined"
fi

test_start "installer rejects combining --skill and --plugin"
INSTALL_HOME_PLUGIN_CONFLICT="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_PLUGIN_CONFLICT"
if HOME="$INSTALL_HOME_PLUGIN_CONFLICT" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --plugin assistant-core --no-hooks >/tmp/p0p4-install-plugin-conflict.out 2>/tmp/p0p4-install-plugin-conflict.err; then
    fail "installer should reject --skill combined with --plugin"
elif grep -Fq "Use either --skill or --plugin, not both" /tmp/p0p4-install-plugin-conflict.err; then
    pass
else
    fail "installer should explain --skill/--plugin mutual exclusion"
fi

test_start "installer replaces interrupted memory protocol install without duplicating blocks"
INSTALL_HOME_THREE="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_THREE"
mkdir -p "$INSTALL_HOME_THREE/.codex"
cat > "$INSTALL_HOME_THREE/.codex/AGENTS.md" <<TRUNCATED
User-managed heading before installer content.

# Assistant Framework — Memory Protocol

## Role

$legacy_orchestrator_role
<!-- This is a template. Paths like ~/.codex/ are substituted during install.sh for non-Claude agents. -->
<!-- Appended by Assistant Framework install. Do not remove this marker. -->
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->

Interrupted installer-owned memory content that should be removed.
TRUNCATED
if HOME="$INSTALL_HOME_THREE" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-truncated.out 2>/tmp/p0p4-install-truncated.err; then
    agents_file="$INSTALL_HOME_THREE/.codex/AGENTS.md"
    starts="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START" "$agents_file")"
    ends="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END" "$agents_file")"
    preambles="$(count_occurrences "^# Assistant Framework — Memory Protocol$" "$agents_file")"
    if [[ "$starts" == "1" && "$ends" == "1" && "$preambles" == "1" ]] \
        && grep -q "User-managed heading before installer content." "$agents_file" \
        && ! grep -q "Interrupted installer-owned memory content" "$agents_file"; then
        pass
    else
        fail "expected truncated installer block to be replaced once while preserving user content"
    fi
else
    fail "install after truncated memory protocol failed; see /tmp/p0p4-install-truncated.err"
fi

test_start "Codex reinstall collapses duplicate and interrupted memory protocol blocks while preserving user content"
INSTALL_HOME_SIX="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_SIX"
mkdir -p "$INSTALL_HOME_SIX/.codex"
cat > "$INSTALL_HOME_SIX/.codex/AGENTS.md" <<DUPLICATE_CODEX
User-managed content before old installer blocks.

<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_START -->
# Old Codex installer section
<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_END -->

User-managed content before first memory block.

<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->
# Assistant Framework — Memory Protocol

Old complete memory content A.
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->

User-managed content between complete memory blocks.

# Assistant Framework — Memory Protocol

## Role

$legacy_orchestrator_role
<!-- This is a template. Paths like ~/.codex/ are substituted during install.sh for non-Claude agents. -->
<!-- Appended by Assistant Framework install. Do not remove this marker. -->
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->

Old complete memory content B.
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->

User-managed content before interrupted memory block.

# Assistant Framework — Memory Protocol

## Role

$legacy_orchestrator_role
<!-- This is a template. Paths like ~/.codex/ are substituted during install.sh for non-Claude agents. -->
<!-- Appended by Assistant Framework install. Do not remove this marker. -->
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->

Interrupted installer-owned memory content that should be removed.
DUPLICATE_CODEX
if HOME="$INSTALL_HOME_SIX" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-duplicate-codex.out 2>/tmp/p0p4-install-duplicate-codex.err; then
    agents_file="$INSTALL_HOME_SIX/.codex/AGENTS.md"
    starts="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START" "$agents_file")"
    ends="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END" "$agents_file")"
    preambles="$(count_occurrences "^# Assistant Framework — Memory Protocol$" "$agents_file")"
    agents_starts="$(count_occurrences "ASSISTANT_FRAMEWORK_AGENTS_MD_START" "$agents_file")"
    agents_ends="$(count_occurrences "ASSISTANT_FRAMEWORK_AGENTS_MD_END" "$agents_file")"
    if [[ "$starts" == "1" && "$ends" == "1" && "$preambles" == "1" ]] \
        && [[ "$agents_starts" == "1" && "$agents_ends" == "1" ]] \
        && grep -q "User-managed content before old installer blocks." "$agents_file" \
        && grep -q "User-managed content before first memory block." "$agents_file" \
        && grep -q "User-managed content between complete memory blocks." "$agents_file" \
        && grep -q "User-managed content before interrupted memory block." "$agents_file" \
        && ! grep -q "Old complete memory content A" "$agents_file" \
        && ! grep -q "Old complete memory content B" "$agents_file" \
        && ! grep -q "Interrupted installer-owned memory content" "$agents_file"; then
        pass
    else
        fail "expected duplicate and interrupted Codex memory protocol blocks to be replaced once while preserving user content"
    fi
else
    fail "Codex install with duplicate memory protocols failed; see /tmp/p0p4-install-duplicate-codex.err"
fi

test_start "installer strips substituted Gemini legacy memory preamble"
INSTALL_HOME_FOUR="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_FOUR"
mkdir -p "$INSTALL_HOME_FOUR/.gemini"
cat > "$INSTALL_HOME_FOUR/.gemini/GEMINI.md" <<TRUNCATED_GEMINI
User-managed Gemini heading before installer content.

# Assistant Framework — Memory Protocol

## Role

$legacy_orchestrator_role
<!-- This is a template. Paths like ~/.gemini/ are substituted during install.sh for non-Claude agents. -->
<!-- Appended by Assistant Framework install. Do not remove this marker. -->
<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->

Interrupted installer-owned Gemini memory content that should be removed.
TRUNCATED_GEMINI
if HOME="$INSTALL_HOME_FOUR" bash "$FRAMEWORK_DIR/install.sh" --agent gemini --skill assistant-workflow --no-hooks >/tmp/p0p4-install-gemini-truncated.out 2>/tmp/p0p4-install-gemini-truncated.err; then
    gemini_file="$INSTALL_HOME_FOUR/.gemini/GEMINI.md"
    starts="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START" "$gemini_file")"
    ends="$(count_occurrences "ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END" "$gemini_file")"
    preambles="$(count_occurrences "^# Assistant Framework — Memory Protocol$" "$gemini_file")"
    if [[ "$starts" == "1" && "$ends" == "1" && "$preambles" == "1" ]] \
        && grep -q "User-managed Gemini heading before installer content." "$gemini_file" \
        && grep -Fq ".gemini/task.md" "$gemini_file" \
        && grep -Fq ".gemini/session.md" "$gemini_file" \
        && grep -Fq ".gemini/working-buffer.md" "$gemini_file" \
        && grep -Fq "Routine completion does not require reflection, metrics, memory writes, consolidation, or health checks." "$gemini_file" \
        && ! grep -Fq ".codex/task.md" "$gemini_file" \
        && ! grep -Fq ".claude/task.md" "$gemini_file" \
        && ! grep -q "Interrupted installer-owned Gemini memory content" "$gemini_file"; then
        pass
    else
        fail "expected substituted Gemini installer block to be replaced once, use .gemini state paths, and preserve user content"
    fi
else
    fail "Gemini install after truncated memory protocol failed; see /tmp/p0p4-install-gemini-truncated.err"
fi

test_start "installer reinstall removes stale installed tool build artifacts"
INSTALL_HOME_SEVEN="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_SEVEN"
if HOME="$INSTALL_HOME_SEVEN" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-tools-1.out 2>/tmp/p0p4-install-tools-1.err; then
    stale_publish="$INSTALL_HOME_SEVEN/.codex/tools/memory-graph/.publish"
    stale_bin="$INSTALL_HOME_SEVEN/.codex/tools/memory-graph/src/MemoryGraph/bin"
    stale_obj="$INSTALL_HOME_SEVEN/.codex/tools/memory-graph/src/MemoryGraph/obj"
    mkdir -p "$stale_publish" "$stale_bin" "$stale_obj"
    touch "$stale_publish/MemoryGraph" "$stale_bin/stale.dll" "$stale_obj/stale.dll"
    if HOME="$INSTALL_HOME_SEVEN" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-tools-2.out 2>/tmp/p0p4-install-tools-2.err; then
        if [[ ! -e "$stale_publish" && ! -e "$stale_bin" && ! -e "$stale_obj" ]]; then
            pass
        else
            fail "expected stale memory-graph .publish, bin, and obj artifacts to be removed after reinstall"
        fi
    else
        fail "second install for stale tool cleanup failed; see /tmp/p0p4-install-tools-2.err"
    fi
else
    fail "first install for stale tool cleanup failed; see /tmp/p0p4-install-tools-1.err"
fi

test_start "Codex reinstall refreshes stale memory-graph MCP config, preserves no-hooks profile, and file mode"
INSTALL_HOME_NINE="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_NINE"
mkdir -p "$INSTALL_HOME_NINE/.codex"
cat > "$INSTALL_HOME_NINE/.codex/config.toml" <<'STALE_CODEX_MCP'
model = "test-model"

[mcp_servers.other-server]
command = "/tmp/other-server"
args = ["--keep"]

[mcp_servers.memory-graph]
command = "/stale/memory-graph"
args = ["--old-memory-dir", "/stale/memory"]
startup_timeout_sec = 10

[mcp_servers.memory-graph.tools.memory_context]
approval_mode = "deny"

[mcp_servers.memory-graph.tools.memory_search]
approval_mode = "approve"

[mcp_servers.memory-graph.tools.memory_search]
approval_mode = "approve"

[features]
hooks = false
codex_hooks = false
STALE_CODEX_MCP
chmod 600 "$INSTALL_HOME_NINE/.codex/config.toml"
if HOME="$INSTALL_HOME_NINE" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-stale-codex-mcp.out 2>/tmp/p0p4-install-stale-codex-mcp.err; then
    config_file="$INSTALL_HOME_NINE/.codex/config.toml"
    config_mode="$(p0p4_file_mode_octal "$config_file")"
    expected_command="command = \"$INSTALL_HOME_NINE/.codex/tools/memory-graph/run-memory-graph.sh\""
    expected_args="args = [\"--memory-dir\", \"$INSTALL_HOME_NINE/.codex/memory\"]"
    expected_startup_timeout='startup_timeout_sec = 120'
    memory_tools=(
        memory_context
        memory_search
        memory_stats
        memory_doctor
        memory_add_entity
        memory_add_insight
        memory_add_relation
        memory_remove_entity
        memory_remove_relation
        memory_graph
        memory_reflect
        memory_decide
        memory_pattern
        memory_consolidate
        memory_signal
        memory_trend
    )

    if [[ "$(count_occurrences "^\\[mcp_servers\\.memory-graph\\]$" "$config_file")" != "1" ]] \
        || ! grep -Fq "$expected_command" "$config_file" \
        || ! grep -Fq "$expected_args" "$config_file" \
        || [[ "$(count_occurrences "^${expected_startup_timeout}$" "$config_file")" != "1" ]] \
        || grep -q '^startup_timeout_sec = 10$' "$config_file" \
        || grep -q "/stale/memory-graph" "$config_file" \
        || ! grep -q '^model = "test-model"$' "$config_file" \
        || ! grep -q '^\[mcp_servers\.other-server\]$' "$config_file" \
        || ! grep -q '^hooks = false$' "$config_file" \
        || ! grep -q '^[[:space:]]*codex_hooks[[:space:]]*= false$' "$config_file" \
        || [[ "$config_mode" != "600" ]]; then
        fail "expected stale Codex memory-graph command/args/startup timeout to refresh while preserving unrelated config, disabled hooks profile, and file mode"
    else
        missing_tool=""
        duplicate_tool=""
        bad_approval_tool=""
        for tool in "${memory_tools[@]}"; do
            section="mcp_servers\\.memory-graph\\.tools\\.$tool"
            if [[ "$(count_occurrences "^\\[$section\\]$" "$config_file")" == "0" ]]; then
                missing_tool="$tool"
                break
            fi
            if [[ "$(count_occurrences "^\\[$section\\]$" "$config_file")" != "1" ]]; then
                duplicate_tool="$tool"
                break
            fi
            if ! awk -v section="[mcp_servers.memory-graph.tools.$tool]" '
                $0 == section { in_section = 1; next }
                in_section && /^\[/ { exit }
                in_section && $0 == "approval_mode = \"approve\"" { found = 1; exit }
                END { exit found ? 0 : 1 }
            ' "$config_file"; then
                bad_approval_tool="$tool"
                break
            fi
        done

        if [[ -n "$missing_tool" ]]; then
            fail "expected refreshed Codex MCP config to include approval block for $missing_tool"
        elif [[ -n "$duplicate_tool" ]]; then
            fail "expected refreshed Codex MCP config to avoid duplicate approval blocks for $duplicate_tool"
        elif [[ -n "$bad_approval_tool" ]]; then
            fail "expected refreshed Codex MCP config to approve $bad_approval_tool"
        else
            pass
        fi
    fi
else
    fail "Codex install with stale memory-graph MCP config failed; see /tmp/p0p4-install-stale-codex-mcp.err"
fi

test_start "clean install keeps legacy offline evals but excludes source-only promotion evaluators"
INSTALL_HOME_EIGHT="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_EIGHT"
mkdir -p "$INSTALL_HOME_EIGHT/.codex/tools/evals/lib"
printf 'stale\n' >"$INSTALL_HOME_EIGHT/.codex/tools/evals/run-codex-framework-evals.sh"
printf 'stale\n' >"$INSTALL_HOME_EIGHT/.codex/tools/evals/finalize-workflow-kernel-review.sh"
printf 'stale\n' >"$INSTALL_HOME_EIGHT/.codex/tools/evals/lib/context-budget-evidence.sh"
printf 'stale\n' >"$INSTALL_HOME_EIGHT/.codex/tools/context-budget-report.sh"
if HOME="$INSTALL_HOME_EIGHT" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-evals.out 2>/tmp/p0p4-install-evals.err; then
    installed_runner="$INSTALL_HOME_EIGHT/.codex/tools/evals/run-framework-instruction-evals.sh"
    installed_fixture="$INSTALL_HOME_EIGHT/.codex/docs/evals/framework-instruction-cases.json"
    installed_codex_runner="$INSTALL_HOME_EIGHT/.codex/tools/evals/run-codex-framework-evals.sh"
    installed_finalizer="$INSTALL_HOME_EIGHT/.codex/tools/evals/finalize-workflow-kernel-review.sh"
    installed_evidence_lib="$INSTALL_HOME_EIGHT/.codex/tools/evals/lib/context-budget-evidence.sh"
    installed_context_reporter="$INSTALL_HOME_EIGHT/.codex/tools/context-budget-report.sh"
    if [[ -x "$installed_runner" ]] \
        && [[ -f "$installed_fixture" ]] \
        && [[ ! -e "$installed_codex_runner" ]] \
        && [[ ! -e "$installed_finalizer" ]] \
        && [[ ! -e "$installed_evidence_lib" ]] \
        && [[ ! -e "$installed_context_reporter" ]] \
        && HOME="$INSTALL_HOME_EIGHT" "$installed_runner" --validate-fixture >/tmp/p0p4-installed-eval-runner.out 2>/tmp/p0p4-installed-eval-runner.err; then
        pass
    else
        fail "clean install must omit source-only promotion evaluators while preserving the legacy offline runner and fixture"
    fi
else
    fail "codex install for eval runner fixture failed; see /tmp/p0p4-install-evals.err"
fi

test_start "default install uses assistant inventory without Unity hardcoding"
INSTALL_HOME_TEN="$(mktemp -d)"
UNITY_FIXTURE="$(mktemp -d "$FRAMEWORK_DIR/skills/unity-contract-fixture-XXXXXX")"
UNITY_FIXTURE_NAME="$(basename "$UNITY_FIXTURE")"
ASSISTANT_UNITY_FIXTURE="$(mktemp -d "$FRAMEWORK_DIR/skills/assistant-unity-contract-fixture-XXXXXX")"
ASSISTANT_UNITY_FIXTURE_NAME="$(basename "$ASSISTANT_UNITY_FIXTURE")"
p0p4_register_cleanup "$INSTALL_HOME_TEN" "$UNITY_FIXTURE" "$ASSISTANT_UNITY_FIXTURE"
cat > "$UNITY_FIXTURE/SKILL.md" <<'UNITY_SKILL'
---
name: unity-local-contract-fixture
description: Local-only Unity fixture that must not be installed by default.
---

# Unity Local Contract Fixture
UNITY_SKILL
cat > "$ASSISTANT_UNITY_FIXTURE/SKILL.md" <<'ASSISTANT_UNITY_SKILL'
---
name: assistant-unity-contract-fixture
description: Assistant-named Unity fixture that should follow the normal assistant inventory rule.
---

# Assistant Unity Contract Fixture
ASSISTANT_UNITY_SKILL
if HOME="$INSTALL_HOME_TEN" bash "$FRAMEWORK_DIR/install.sh" --agent codex --no-hooks >/tmp/p0p4-install-default-skills.out 2>/tmp/p0p4-install-default-skills.err; then
    installed_skills_dir="$INSTALL_HOME_TEN/.codex/skills"
    agents_file="$INSTALL_HOME_TEN/.codex/AGENTS.md"
    missing_assistant_skill=""
    unexpected_installed_skill=""
    source_assistant_skill_count=0
    agents_assistant_skill_rows="$(count_occurrences "^| assistant-" "$agents_file")"

    while IFS= read -r source_skill_md; do
        source_assistant_skill_count=$((source_assistant_skill_count + 1))
        source_skill="$(basename "$(dirname "$source_skill_md")")"
        if [[ ! -d "$installed_skills_dir/$source_skill" ]]; then
            missing_assistant_skill="$source_skill"
            break
        fi
    done < <(find "$FRAMEWORK_DIR/skills" -maxdepth 2 -path "$FRAMEWORK_DIR/skills/assistant-*/SKILL.md" -type f | sort)

    rm -rf "$UNITY_FIXTURE" "$ASSISTANT_UNITY_FIXTURE"

    if [[ -d "$installed_skills_dir" ]]; then
        while IFS= read -r installed_skill_dir; do
            installed_skill="$(basename "$installed_skill_dir")"
            case "$installed_skill" in
                assistant-*) ;;
                *)
                    unexpected_installed_skill="$installed_skill"
                    break
                    ;;
            esac
        done < <(find "$installed_skills_dir" -mindepth 1 -maxdepth 1 -type d | sort)
    fi

    if [[ -n "$missing_assistant_skill" ]]; then
        fail "expected default install to include first-class assistant skill $missing_assistant_skill"
    elif [[ "$source_assistant_skill_count" -lt "16" ]]; then
        fail "expected source inventory to contain at least 16 assistant skills including the assistant-named custom fixture; found $source_assistant_skill_count"
    elif [[ "$agents_assistant_skill_rows" != "0" ]] || ! grep -Fq "Codex uses installed skills through native skill routing." "$agents_file"; then
        fail "expected generated Codex AGENTS.md to stay lean and keep routing metadata in installed skills"
    elif [[ -n "$unexpected_installed_skill" ]]; then
        fail "expected default install to exclude non-assistant skill $unexpected_installed_skill"
    elif [[ -e "$installed_skills_dir/$UNITY_FIXTURE_NAME" ]]; then
        fail "expected default install to exclude non-assistant local Unity fixture"
    elif [[ ! -e "$installed_skills_dir/$ASSISTANT_UNITY_FIXTURE_NAME" ]]; then
        fail "expected default install to include assistant-named custom Unity fixture"
    else
        pass
    fi
else
    rm -rf "$UNITY_FIXTURE" "$ASSISTANT_UNITY_FIXTURE"
    fail "default install with Unity fixture coverage failed; see /tmp/p0p4-install-default-skills.err"
fi

test_start "deprecated --no-hooks remains a hookless no-op for one compatibility release"
CODEX_NO_HOOKS_HOME="$(mktemp -d)"
p0p4_register_cleanup "$CODEX_NO_HOOKS_HOME"
if HOME="$CODEX_NO_HOOKS_HOME" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-codex-no-hooks.out 2>/tmp/p0p4-install-codex-no-hooks.err; then
    if [[ ! -f "$CODEX_NO_HOOKS_HOME/.codex/hooks.json" ]] \
        && ! grep -Fq "hooks = true" "$CODEX_NO_HOOKS_HOME/.codex/config.toml" \
        && grep -Fq -- "--no-hooks is deprecated" /tmp/p0p4-install-codex-no-hooks.err; then
        pass
    else
        fail "deprecated --no-hooks should warn without creating hooks.json or enabling hooks"
    fi
else
    fail "Codex --no-hooks install failed; see /tmp/p0p4-install-codex-no-hooks.err"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
