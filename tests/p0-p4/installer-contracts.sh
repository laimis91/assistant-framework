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

p0p4_seed_required_writer_profiles() {
    local fixture_root="$1" agent="${2:-codex}" extension=md
    [[ "$agent" != codex ]] || extension=toml
    mkdir -p "$fixture_root/agents/$agent"
    cp "$FRAMEWORK_DIR/agents/$agent/intelligent-writer.$extension" "$fixture_root/agents/$agent/"
    cp "$FRAMEWORK_DIR/agents/$agent/mechanical-writer.$extension" "$fixture_root/agents/$agent/"
}

legacy_orchestrator_role="You are an orchestrator. You delegate ALL ""file editing, code implementation, and phase execution to specialized agents."
stale_generated_phrase="delegate ALL ""file editing, code implementation, and phase execution"
route_guidance="For ordinary repository changes, use assistant-workflow when that skill is installed; assistant-clarify helps untangle or structure unclear intent."

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

p0p4_extract_current_agents_suffix() {
    local agents_file="$1"
    local suffix_file="$2"

    sed '1,/<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_END -->/d' "$agents_file" \
        | sed '1{/^$/d;}' >"$suffix_file"
}

test_start "Codex reinstall keeps one lean framework block and retires the memory protocol"
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
        if [[ "$starts" == "0" && "$ends" == "0" && "$preambles" == "0" ]] \
            && [[ "$agents_starts" == "1" && "$agents_ends" == "1" ]] \
            && [[ "$operating_stances" == "1" ]] \
            && ! grep -Fq "$stale_generated_phrase" "$agents_file" \
            && grep -Fq "Codex uses installed skills through native skill routing." "$agents_file" \
            && grep -Fq "load only the references or contracts relevant to the current phase" "$agents_file" \
            && grep -Fq "For small, low-risk, localized work, act as a hands-on worker" "$agents_file" \
            && grep -Fq "For medium+ or elevated-risk development work, remain the orchestrator" "$agents_file" \
            && grep -Fq "Keep orchestration proportional" "$agents_file" \
            && grep -Fq "Get plan approval before medium+ or risky edits." "$agents_file" \
            && grep -Fq "Use subagents when requested by the user or required by applicable project or skill instructions; do not ask for separate spawn consent." "$agents_file" \
            && ! grep -Fq "## Skills (loaded" "$agents_file" \
            && [[ -f "$INSTALL_HOME/.codex/agents/code-reviewer.toml" ]] \
            && grep -Fq 'sandbox_mode = "read-only"' "$INSTALL_HOME/.codex/agents/code-reviewer.toml" \
            && ! grep -Fq "The orchestrator owns framework state files" "$agents_file" \
            && ! grep -Fq ".codex/context-map.md" "$agents_file" \
            && ! grep -Fq "Do not infer that subagents are unavailable from the absence of a visible tool name" "$agents_file" \
            && grep -Fq "Preserve user-authored files and existing dirty work." "$agents_file"; then
            pass
        else
            fail "expected one lean native-Codex framework block with no retired memory protocol"
        fi
    else
        fail "second install failed; see /tmp/p0p4-install-2.err"
    fi
else
    fail "first install failed; see /tmp/p0p4-install-1.err"
fi

test_start "Codex selected workflow install keeps routing metadata and its canonical review and TDD producers"
INSTALL_HOME_SKILL_TABLE="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_SKILL_TABLE"
if HOME="$INSTALL_HOME_SKILL_TABLE" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-single-skill-table.out 2>/tmp/p0p4-install-single-skill-table.err; then
    agents_file="$INSTALL_HOME_SKILL_TABLE/.codex/AGENTS.md"
    installed_skills_dir="$INSTALL_HOME_SKILL_TABLE/.codex/skills"
    assistant_skill_rows="$(count_occurrences "^| assistant-" "$agents_file")"

    if [[ ! -d "$installed_skills_dir/assistant-workflow" || ! -d "$installed_skills_dir/assistant-review" || ! -f "$installed_skills_dir/assistant-tdd/contracts/output.yaml" ]]; then
        fail "expected assistant-workflow and its canonical assistant-review and assistant-tdd producers to be installed"
    elif [[ -d "$installed_skills_dir/assistant-docs" ]]; then
        fail "expected selected workflow install to avoid unrelated assistant-docs"
    elif [[ "$assistant_skill_rows" != "0" ]]; then
        fail "expected lean Codex AGENTS.md to avoid duplicating installed skill routing tables; found $assistant_skill_rows rows"
    elif ! grep -Fq "Codex uses installed skills through native skill routing." "$agents_file"; then
        fail "expected generated Codex AGENTS.md to delegate routing to the installed SKILL.md"
    elif ! grep -Fq -- "$route_guidance" "$agents_file"; then
        fail "expected generated Codex AGENTS.md to route through assistant-workflow only when that skill is installed"
    else
        pass
    fi
else
    fail "single-skill Codex install failed; see /tmp/p0p4-install-single-skill-table.err"
fi

test_start "Codex selective clarify install qualifies routing for an absent workflow skill"
INSTALL_HOME_CLARIFY_ONLY="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_CLARIFY_ONLY"
if HOME="$INSTALL_HOME_CLARIFY_ONLY" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-clarify --no-hooks >/tmp/p0p4-install-clarify-only.out 2>/tmp/p0p4-install-clarify-only.err; then
    agents_file="$INSTALL_HOME_CLARIFY_ONLY/.codex/AGENTS.md"
    installed_skills_dir="$INSTALL_HOME_CLARIFY_ONLY/.codex/skills"
    if [[ ! -f "$installed_skills_dir/assistant-clarify/SKILL.md" ]]; then
        fail "expected the selected assistant-clarify skill to be installed"
    elif [[ -e "$installed_skills_dir/assistant-workflow" ]]; then
        fail "expected assistant-clarify selective installation to omit assistant-workflow"
    elif ! grep -Fq -- "$route_guidance" "$agents_file" \
        || grep -Fq -- "go through assistant-workflow" "$agents_file"; then
        fail "expected generated Codex AGENTS.md to qualify workflow routing by installed-skill availability"
    else
        pass
    fi
else
    fail "assistant-clarify selective Codex install failed; see /tmp/p0p4-install-clarify-only.err"
fi

test_start "selected bundled requirements close transitively without duplicate cycle copies"
INSTALL_HOME_REQUIRES_CLOSURE="$(mktemp -d)"
REQUIRES_CLOSURE_FRAMEWORK_ROOT="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_REQUIRES_CLOSURE" "$REQUIRES_CLOSURE_FRAMEWORK_ROOT"
cp "$FRAMEWORK_DIR/install.sh" "$REQUIRES_CLOSURE_FRAMEWORK_ROOT/install.sh"
p0p4_seed_required_writer_profiles "$REQUIRES_CLOSURE_FRAMEWORK_ROOT"
for closure_skill in assistant-closure-a assistant-closure-b assistant-closure-c; do
    mkdir -p "$REQUIRES_CLOSURE_FRAMEWORK_ROOT/skills/$closure_skill"
done
cat >"$REQUIRES_CLOSURE_FRAMEWORK_ROOT/skills/assistant-closure-a/SKILL.md" <<'EOF'
---
name: assistant-closure-a
description: Closure root fixture.
requires:
  - assistant-closure-b
  - assistant-closure-c
---
EOF
cat >"$REQUIRES_CLOSURE_FRAMEWORK_ROOT/skills/assistant-closure-b/SKILL.md" <<'EOF'
---
name: assistant-closure-b
description: Closure transitive fixture.
requires:
  - assistant-closure-c
---
EOF
cat >"$REQUIRES_CLOSURE_FRAMEWORK_ROOT/skills/assistant-closure-c/SKILL.md" <<'EOF'
---
name: assistant-closure-c
description: Closure cycle fixture.
requires:
  - assistant-closure-a
---
EOF
if HOME="$INSTALL_HOME_REQUIRES_CLOSURE" bash "$REQUIRES_CLOSURE_FRAMEWORK_ROOT/install.sh" --agent codex --skill assistant-closure-a --dry-run >/tmp/p0p4-install-requires-closure-dry.out 2>/tmp/p0p4-install-requires-closure-dry.err \
    && grep -Fq -- "-> $INSTALL_HOME_REQUIRES_CLOSURE/.codex/skills/assistant-closure-a/" /tmp/p0p4-install-requires-closure-dry.out \
    && grep -Fq -- "-> $INSTALL_HOME_REQUIRES_CLOSURE/.codex/skills/assistant-closure-b/" /tmp/p0p4-install-requires-closure-dry.out \
    && grep -Fq -- "-> $INSTALL_HOME_REQUIRES_CLOSURE/.codex/skills/assistant-closure-c/" /tmp/p0p4-install-requires-closure-dry.out \
    && [[ ! -e "$INSTALL_HOME_REQUIRES_CLOSURE/.codex" && ! -e "$INSTALL_HOME_REQUIRES_CLOSURE/.agents" ]] \
    && HOME="$INSTALL_HOME_REQUIRES_CLOSURE" bash "$REQUIRES_CLOSURE_FRAMEWORK_ROOT/install.sh" --agent codex --skill assistant-closure-a >/tmp/p0p4-install-requires-closure.out 2>/tmp/p0p4-install-requires-closure.err; then
    installed_closure_skills="$(find "$INSTALL_HOME_REQUIRES_CLOSURE/.codex/skills" -mindepth 1 -maxdepth 1 -type d -name 'assistant-closure-*' -exec basename {} \; | sort | tr '\n' ' ')"
    if [[ "$installed_closure_skills" == "assistant-closure-a assistant-closure-b assistant-closure-c " ]] \
        && [[ "$(count_occurrences 'assistant-closure-a ->' /tmp/p0p4-install-requires-closure.out)" == "1" ]] \
        && [[ "$(count_occurrences 'assistant-closure-b ->' /tmp/p0p4-install-requires-closure.out)" == "1" ]] \
        && [[ "$(count_occurrences 'assistant-closure-c ->' /tmp/p0p4-install-requires-closure.out)" == "1" ]]; then
        pass
    else
        fail "selected bundled requirement closure did not install each cycle member exactly once"
    fi
else
    fail "selected bundled requirement closure or dry-run failed"
fi

test_start "selected custom root supports an empty assistant inventory and advisory external requires"
INSTALL_HOME_EMPTY_INVENTORY="$(mktemp -d)"
EMPTY_INVENTORY_FRAMEWORK_ROOT="$(mktemp -d)"
EMPTY_INVENTORY_SKILL_NAME="custom-root-$(basename "$EMPTY_INVENTORY_FRAMEWORK_ROOT")"
EMPTY_INVENTORY_SKILL="$EMPTY_INVENTORY_FRAMEWORK_ROOT/skills/$EMPTY_INVENTORY_SKILL_NAME"
p0p4_register_cleanup "$INSTALL_HOME_EMPTY_INVENTORY" "$EMPTY_INVENTORY_FRAMEWORK_ROOT"
mkdir -p "$EMPTY_INVENTORY_SKILL"
cp "$FRAMEWORK_DIR/install.sh" "$EMPTY_INVENTORY_FRAMEWORK_ROOT/install.sh"
p0p4_seed_required_writer_profiles "$EMPTY_INVENTORY_FRAMEWORK_ROOT"
cat >"$EMPTY_INVENTORY_SKILL/SKILL.md" <<EOF
---
name: $EMPTY_INVENTORY_SKILL_NAME
description: Explicit custom-root installer fixture.
requires:
  - external-skill
---
EOF
if HOME="$INSTALL_HOME_EMPTY_INVENTORY" bash "$EMPTY_INVENTORY_FRAMEWORK_ROOT/install.sh" --agent codex --skill "$EMPTY_INVENTORY_SKILL_NAME" --no-hooks >/tmp/p0p4-install-empty-inventory.out 2>/tmp/p0p4-install-empty-inventory.err; then
    if [[ -f "$INSTALL_HOME_EMPTY_INVENTORY/.codex/skills/$EMPTY_INVENTORY_SKILL_NAME/SKILL.md" ]] \
        && grep -Fq "NOTE: $EMPTY_INVENTORY_SKILL_NAME requires 'external-skill'" /tmp/p0p4-install-empty-inventory.out; then
        pass
    else
        fail "selected custom root did not install or report its missing external requirement"
    fi
else
    fail "selected custom root with an empty assistant inventory failed; see /tmp/p0p4-install-empty-inventory.err"
fi

test_start "selected skill names reject path traversal before dry-run or install writes"
INSTALL_HOME_PATHFUL_SKILL="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_PATHFUL_SKILL"
pathful_skill='../../V1/skills/assistant-review'
if HOME="$INSTALL_HOME_PATHFUL_SKILL" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill "$pathful_skill" --dry-run >/tmp/p0p4-install-pathful-skill-dry.out 2>/tmp/p0p4-install-pathful-skill-dry.err; then
    fail "pathful selected skill was accepted during dry-run"
elif HOME="$INSTALL_HOME_PATHFUL_SKILL" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill "$pathful_skill" >/tmp/p0p4-install-pathful-skill.out 2>/tmp/p0p4-install-pathful-skill.err; then
    fail "pathful selected skill was accepted during install"
elif [[ -e "$INSTALL_HOME_PATHFUL_SKILL/.codex" || -e "$INSTALL_HOME_PATHFUL_SKILL/.agents" || -e "$INSTALL_HOME_PATHFUL_SKILL/V1" ]]; then
    fail "pathful selected skill rejection wrote outside the managed skills root"
else
    pass
fi

test_start "selected closures reject unsafe implicit dependency targets before any write"
INSTALL_HOME_UNSAFE_DEPENDENCY_TARGET="$(mktemp -d)"
UNSAFE_DEPENDENCY_EXTERNAL="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_UNSAFE_DEPENDENCY_TARGET" "$UNSAFE_DEPENDENCY_EXTERNAL"
unsafe_dependency_workflow="$INSTALL_HOME_UNSAFE_DEPENDENCY_TARGET/.codex/skills/assistant-workflow"
unsafe_dependency_review="$INSTALL_HOME_UNSAFE_DEPENDENCY_TARGET/.codex/skills/assistant-review"
mkdir -p "$unsafe_dependency_workflow" "$UNSAFE_DEPENDENCY_EXTERNAL"
printf 'preserve selected root\n' >"$unsafe_dependency_workflow/SKILL.md"
printf 'preserve external sentinel\n' >"$UNSAFE_DEPENDENCY_EXTERNAL/sentinel.txt"
cp "$unsafe_dependency_workflow/SKILL.md" "$INSTALL_HOME_UNSAFE_DEPENDENCY_TARGET/workflow.before"
cp "$UNSAFE_DEPENDENCY_EXTERNAL/sentinel.txt" "$INSTALL_HOME_UNSAFE_DEPENDENCY_TARGET/sentinel.before"
ln -s "$UNSAFE_DEPENDENCY_EXTERNAL" "$unsafe_dependency_review"
if HOME="$INSTALL_HOME_UNSAFE_DEPENDENCY_TARGET" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow >/tmp/p0p4-install-unsafe-dependency-target.out 2>/tmp/p0p4-install-unsafe-dependency-target.err; then
    fail "selected closure accepted an implicit dependency target symlink"
elif ! cmp -s "$unsafe_dependency_workflow/SKILL.md" "$INSTALL_HOME_UNSAFE_DEPENDENCY_TARGET/workflow.before"; then
    fail "implicit dependency target rejection mutated the selected root"
elif ! cmp -s "$UNSAFE_DEPENDENCY_EXTERNAL/sentinel.txt" "$INSTALL_HOME_UNSAFE_DEPENDENCY_TARGET/sentinel.before"; then
    fail "implicit dependency target rejection mutated the external sentinel"
elif HOME="$INSTALL_HOME_UNSAFE_DEPENDENCY_TARGET" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --dry-run >/tmp/p0p4-install-unsafe-dependency-target-dry.out 2>/tmp/p0p4-install-unsafe-dependency-target-dry.err; then
    fail "selected closure accepted an implicit dependency target symlink during dry-run"
elif ! cmp -s "$unsafe_dependency_workflow/SKILL.md" "$INSTALL_HOME_UNSAFE_DEPENDENCY_TARGET/workflow.before" \
    || ! cmp -s "$UNSAFE_DEPENDENCY_EXTERNAL/sentinel.txt" "$INSTALL_HOME_UNSAFE_DEPENDENCY_TARGET/sentinel.before"; then
    fail "dry-run implicit dependency target rejection mutated a protected path"
else
    pass
fi

test_start "selected closures reject wrong-type managed targets before any write"
INSTALL_HOME_WRONG_TYPE_SKILL_TARGET="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_WRONG_TYPE_SKILL_TARGET"
wrong_type_dependency_target="$INSTALL_HOME_WRONG_TYPE_SKILL_TARGET/.codex/skills/assistant-review"
mkdir -p "$(dirname "$wrong_type_dependency_target")"
printf 'preserve wrong-type target\n' >"$wrong_type_dependency_target"
cp "$wrong_type_dependency_target" "$INSTALL_HOME_WRONG_TYPE_SKILL_TARGET/wrong-type.before"
if HOME="$INSTALL_HOME_WRONG_TYPE_SKILL_TARGET" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow >/tmp/p0p4-install-wrong-type-skill-target.out 2>/tmp/p0p4-install-wrong-type-skill-target.err; then
    fail "selected closure accepted a wrong-type managed target"
elif [[ -e "$INSTALL_HOME_WRONG_TYPE_SKILL_TARGET/.codex/skills/assistant-workflow" ]]; then
    fail "wrong-type managed target rejection copied the selected root"
elif ! cmp -s "$wrong_type_dependency_target" "$INSTALL_HOME_WRONG_TYPE_SKILL_TARGET/wrong-type.before"; then
    fail "wrong-type managed target rejection changed the target"
elif HOME="$INSTALL_HOME_WRONG_TYPE_SKILL_TARGET" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --dry-run >/tmp/p0p4-install-wrong-type-skill-target-dry.out 2>/tmp/p0p4-install-wrong-type-skill-target-dry.err; then
    fail "selected closure accepted a wrong-type managed target during dry-run"
else
    pass
fi

test_start "selected custom roots reject source and metadata symlinks before reads or writes"
INSTALL_HOME_UNSAFE_SOURCE="$(mktemp -d)"
UNSAFE_SOURCE_FRAMEWORK_ROOT="$(mktemp -d)"
UNSAFE_SOURCE_EXTERNAL="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_UNSAFE_SOURCE" "$UNSAFE_SOURCE_FRAMEWORK_ROOT" "$UNSAFE_SOURCE_EXTERNAL"
cp "$FRAMEWORK_DIR/install.sh" "$UNSAFE_SOURCE_FRAMEWORK_ROOT/install.sh"
p0p4_seed_required_writer_profiles "$UNSAFE_SOURCE_FRAMEWORK_ROOT"
mkdir -p "$UNSAFE_SOURCE_FRAMEWORK_ROOT/skills"
for unsafe_source_kind in source metadata; do
    unsafe_source_skill="assistant-unsafe-$unsafe_source_kind"
    unsafe_source_home="$INSTALL_HOME_UNSAFE_SOURCE/$unsafe_source_kind"
    mkdir -p "$unsafe_source_home" "$UNSAFE_SOURCE_EXTERNAL/$unsafe_source_kind"
    printf '%s\n' '---' "name: $unsafe_source_skill" 'description: Unsafe source fixture.' '---' >"$UNSAFE_SOURCE_EXTERNAL/$unsafe_source_kind/SKILL.md"
    if [[ "$unsafe_source_kind" == "source" ]]; then
        ln -s "$UNSAFE_SOURCE_EXTERNAL/$unsafe_source_kind" "$UNSAFE_SOURCE_FRAMEWORK_ROOT/skills/$unsafe_source_skill"
    else
        mkdir -p "$UNSAFE_SOURCE_FRAMEWORK_ROOT/skills/$unsafe_source_skill"
        ln -s "$UNSAFE_SOURCE_EXTERNAL/$unsafe_source_kind/SKILL.md" "$UNSAFE_SOURCE_FRAMEWORK_ROOT/skills/$unsafe_source_skill/SKILL.md"
    fi

    if HOME="$unsafe_source_home" bash "$UNSAFE_SOURCE_FRAMEWORK_ROOT/install.sh" --agent codex --skill "$unsafe_source_skill" --dry-run >/tmp/p0p4-install-unsafe-${unsafe_source_kind}-dry.out 2>/tmp/p0p4-install-unsafe-${unsafe_source_kind}-dry.err \
        || HOME="$unsafe_source_home" bash "$UNSAFE_SOURCE_FRAMEWORK_ROOT/install.sh" --agent codex --skill "$unsafe_source_skill" >/tmp/p0p4-install-unsafe-${unsafe_source_kind}.out 2>/tmp/p0p4-install-unsafe-${unsafe_source_kind}.err \
        || [[ -e "$unsafe_source_home/.codex" || -e "$unsafe_source_home/.agents" ]]; then
        unsafe_source_failure="$unsafe_source_kind symlink was accepted or wrote to the managed home"
        break
    fi
done
if [[ -z "${unsafe_source_failure:-}" ]]; then
    pass
else
    fail "$unsafe_source_failure"
fi

test_start "requires fixtures stay outside the canonical skills inventory"
requires_fixture_prefix='assistant-requires-contract-fixture-'
canonical_fixture_creation='mktemp -d "$FRAMEWORK_DIR/skills/'"$requires_fixture_prefix"
if grep -Fq -- "$canonical_fixture_creation" "${BASH_SOURCE[0]}"; then
    fail "requires fixture is created inside the canonical skills inventory"
else
    pass
fi

test_start "Codex installer observes missing dependencies from canonical block requires"
INSTALL_HOME_REQUIRES="$(mktemp -d)"
REQUIRES_FRAMEWORK_ROOT="$(mktemp -d)"
REQUIRES_FIXTURE_NAME="assistant-requires-contract-fixture-$(basename "$REQUIRES_FRAMEWORK_ROOT")"
REQUIRES_FIXTURE="$REQUIRES_FRAMEWORK_ROOT/skills/$REQUIRES_FIXTURE_NAME"
p0p4_register_cleanup "$INSTALL_HOME_REQUIRES" "$REQUIRES_FRAMEWORK_ROOT"
mkdir -p "$REQUIRES_FIXTURE"
cp "$FRAMEWORK_DIR/install.sh" "$REQUIRES_FRAMEWORK_ROOT/install.sh"
p0p4_seed_required_writer_profiles "$REQUIRES_FRAMEWORK_ROOT"
cat >"$REQUIRES_FIXTURE/SKILL.md" <<EOF
---
name: $REQUIRES_FIXTURE_NAME
description: Canonical block requires installer fixture.
requires:
  - assistant-missing-dependency
---

# Canonical Requires Fixture
EOF
if [[ "$REQUIRES_FIXTURE" == "$FRAMEWORK_DIR/skills/"* ]]; then
    fail "requires fixture must not be created under canonical skills"
elif HOME="$INSTALL_HOME_REQUIRES" bash "$REQUIRES_FRAMEWORK_ROOT/install.sh" --agent codex --skill "$REQUIRES_FIXTURE_NAME" --no-hooks >/tmp/p0p4-install-requires.out 2>/tmp/p0p4-install-requires.err; then
    if grep -Fq "NOTE: $REQUIRES_FIXTURE_NAME requires 'assistant-missing-dependency'" /tmp/p0p4-install-requires.out; then
        pass
    else
        fail "canonical block requires did not produce the missing-dependency note"
    fi
else
    fail "canonical block requires fixture install failed; see /tmp/p0p4-install-requires.err"
fi

test_start "retired plugin option is rejected without filesystem mutation"
INSTALL_HOME_RETIRED_PLUGIN="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_RETIRED_PLUGIN"
printf 'preserve\n' >"$INSTALL_HOME_RETIRED_PLUGIN/sentinel.txt"
if HOME="$INSTALL_HOME_RETIRED_PLUGIN" bash "$FRAMEWORK_DIR/install.sh" --agent codex --plugin assistant-core >/tmp/p0p4-install-retired-plugin.out 2>/tmp/p0p4-install-retired-plugin.err; then
    fail "retired --plugin option should be rejected"
elif ! grep -Fq 'Unknown option: --plugin' /tmp/p0p4-install-retired-plugin.err; then
    fail "retired --plugin rejection should identify the unknown option"
elif [[ "$(cat "$INSTALL_HOME_RETIRED_PLUGIN/sentinel.txt")" != "preserve" ]] \
    || [[ -e "$INSTALL_HOME_RETIRED_PLUGIN/.codex" ]]; then
    fail "retired --plugin rejection mutated the target home"
else
    pass
fi

test_start "Claude and Gemini installs ignore hostile ambient CODEX_HOME"
installer_non_codex_home_failures=()
for installer_non_codex_agent in claude gemini; do
    installer_non_codex_home="$(mktemp -d)"
    p0p4_register_cleanup "$installer_non_codex_home"
    if ! HOME="$installer_non_codex_home" CODEX_HOME=/ bash "$FRAMEWORK_DIR/install.sh" --agent "$installer_non_codex_agent" --skill assistant-workflow --no-hooks >/tmp/p0p4-install-non-codex-home-${installer_non_codex_agent}.out 2>/tmp/p0p4-install-non-codex-home-${installer_non_codex_agent}.err \
        || [[ ! -f "$installer_non_codex_home/.${installer_non_codex_agent}/skills/assistant-workflow/SKILL.md" ]] \
        || [[ -e /skills/assistant-workflow ]]; then
        installer_non_codex_home_failures+=("$installer_non_codex_agent")
    fi
done
if [[ "${#installer_non_codex_home_failures[@]}" -ne 0 ]]; then
    fail "Claude or Gemini install forwarded hostile ambient CODEX_HOME instead of using only its selected agent home: ${installer_non_codex_home_failures[*]}"
else
    pass
fi

test_start "installer preserves an interrupted retired memory protocol while installing the current managed block"
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
cp "$INSTALL_HOME_THREE/.codex/AGENTS.md" "$INSTALL_HOME_THREE/.codex/AGENTS.before"
interrupted_codex_suffix="$(mktemp)"
interrupted_codex_mutated_suffix="$(mktemp)"
p0p4_register_cleanup "$interrupted_codex_suffix" "$interrupted_codex_mutated_suffix"
if HOME="$INSTALL_HOME_THREE" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-truncated.out 2>/tmp/p0p4-install-truncated.err \
    && [[ "$(count_occurrences "ASSISTANT_FRAMEWORK_AGENTS_MD_START" "$INSTALL_HOME_THREE/.codex/AGENTS.md")" == "1" ]] \
    && [[ "$(count_occurrences "ASSISTANT_FRAMEWORK_AGENTS_MD_END" "$INSTALL_HOME_THREE/.codex/AGENTS.md")" == "1" ]]; then
    p0p4_extract_current_agents_suffix "$INSTALL_HOME_THREE/.codex/AGENTS.md" "$interrupted_codex_suffix"
    sed '$d' "$INSTALL_HOME_THREE/.codex/AGENTS.before" >"$interrupted_codex_mutated_suffix"
    if cmp -s "$INSTALL_HOME_THREE/.codex/AGENTS.before" "$interrupted_codex_suffix" \
        && ! cmp -s "$interrupted_codex_mutated_suffix" "$interrupted_codex_suffix"; then
        pass
    else
        fail "interrupted retired memory protocol was not preserved as the exact suffix after the current managed block"
    fi
else
    fail "interrupted retired memory protocol was not preserved while installing the current managed block"
fi

test_start "Codex reinstall preserves duplicate retired memory protocol blocks while installing the current managed block"
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
cp "$INSTALL_HOME_SIX/.codex/AGENTS.md" "$INSTALL_HOME_SIX/.codex/AGENTS.before"
duplicate_codex_expected_suffix="$(mktemp)"
duplicate_codex_actual_suffix="$(mktemp)"
duplicate_codex_mutated_suffix="$(mktemp)"
p0p4_register_cleanup "$duplicate_codex_expected_suffix" "$duplicate_codex_actual_suffix" "$duplicate_codex_mutated_suffix"
sed '/<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_START -->/,/<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_END -->/d' "$INSTALL_HOME_SIX/.codex/AGENTS.before" >"$duplicate_codex_expected_suffix"
if HOME="$INSTALL_HOME_SIX" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-duplicate-codex.out 2>/tmp/p0p4-install-duplicate-codex.err \
    && [[ "$(count_occurrences "ASSISTANT_FRAMEWORK_AGENTS_MD_START" "$INSTALL_HOME_SIX/.codex/AGENTS.md")" == "1" ]] \
    && [[ "$(count_occurrences "ASSISTANT_FRAMEWORK_AGENTS_MD_END" "$INSTALL_HOME_SIX/.codex/AGENTS.md")" == "1" ]]; then
    p0p4_extract_current_agents_suffix "$INSTALL_HOME_SIX/.codex/AGENTS.md" "$duplicate_codex_actual_suffix"
    sed '$d' "$duplicate_codex_expected_suffix" >"$duplicate_codex_mutated_suffix"
    if cmp -s "$duplicate_codex_expected_suffix" "$duplicate_codex_actual_suffix" \
        && ! cmp -s "$duplicate_codex_mutated_suffix" "$duplicate_codex_actual_suffix"; then
        pass
    else
        fail "duplicate retired memory protocol blocks were not preserved as the exact current-block suffix"
    fi
else
    fail "duplicate retired memory protocol blocks were not preserved while installing the current managed block"
fi

test_start "installer preserves an interrupted Gemini retired memory protocol while installing the current managed skill"
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
cp "$INSTALL_HOME_FOUR/.gemini/GEMINI.md" "$INSTALL_HOME_FOUR/.gemini/GEMINI.before"
if HOME="$INSTALL_HOME_FOUR" bash "$FRAMEWORK_DIR/install.sh" --agent gemini --skill assistant-workflow --no-hooks >/tmp/p0p4-install-gemini-truncated.out 2>/tmp/p0p4-install-gemini-truncated.err \
    && cmp -s "$INSTALL_HOME_FOUR/.gemini/GEMINI.before" "$INSTALL_HOME_FOUR/.gemini/GEMINI.md" \
    && [[ -f "$INSTALL_HOME_FOUR/.gemini/skills/assistant-workflow/SKILL.md" ]]; then
    pass
else
    fail "interrupted Gemini retired memory protocol was not preserved while installing the current managed skill"
fi

test_start "installer removes stale build artifacts only from managed tools"
INSTALL_HOME_SEVEN="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_SEVEN"
if HOME="$INSTALL_HOME_SEVEN" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-tools-1.out 2>/tmp/p0p4-install-tools-1.err; then
    stale_publish="$INSTALL_HOME_SEVEN/.codex/tools/evals/.publish"
    stale_bin="$INSTALL_HOME_SEVEN/.codex/tools/evals/bin"
    stale_obj="$INSTALL_HOME_SEVEN/.codex/tools/evals/obj"
    legacy_publish="$INSTALL_HOME_SEVEN/.codex/tools/memory-graph/.publish"
    legacy_bin="$INSTALL_HOME_SEVEN/.codex/tools/memory-graph/src/MemoryGraph/bin"
    legacy_obj="$INSTALL_HOME_SEVEN/.codex/tools/memory-graph/src/MemoryGraph/obj"
    mkdir -p "$stale_publish" "$stale_bin" "$stale_obj" "$legacy_publish" "$legacy_bin" "$legacy_obj"
    touch "$stale_publish/managed" "$stale_bin/managed.dll" "$stale_obj/managed.dll"
    touch "$legacy_publish/MemoryGraph" "$legacy_bin/stale.dll" "$legacy_obj/stale.dll"
    if HOME="$INSTALL_HOME_SEVEN" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-tools-2.out 2>/tmp/p0p4-install-tools-2.err; then
        if [[ ! -e "$stale_publish" && ! -e "$stale_bin" && ! -e "$stale_obj" \
            && -e "$legacy_publish/MemoryGraph" && -e "$legacy_bin/stale.dll" && -e "$legacy_obj/stale.dll" ]]; then
            pass
        else
            fail "expected managed build artifacts to be removed without altering the legacy Memory Graph tool tree"
        fi
    else
        fail "second install for stale tool cleanup failed; see /tmp/p0p4-install-tools-2.err"
    fi
else
    fail "first install for stale tool cleanup failed; see /tmp/p0p4-install-tools-1.err"
fi

test_start "installer retires the exact plugin sync tool and preserves unrelated plugin tools"
INSTALL_HOME_RETIRED_PLUGIN_TOOL="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_RETIRED_PLUGIN_TOOL"
retired_plugin_tools_directory="$INSTALL_HOME_RETIRED_PLUGIN_TOOL/.codex/tools/plugins"
retired_plugin_sync_tool="$retired_plugin_tools_directory/sync-plugin-skills.sh"
custom_plugin_tool="$retired_plugin_tools_directory/custom/tool.txt"
mkdir -p "$(dirname "$custom_plugin_tool")"
printf 'legacy plugin sync tool\n' >"$retired_plugin_sync_tool"
printf 'preserve user plugin tool\n' >"$custom_plugin_tool"
cp "$custom_plugin_tool" "$INSTALL_HOME_RETIRED_PLUGIN_TOOL/custom-tool.before"
if HOME="$INSTALL_HOME_RETIRED_PLUGIN_TOOL" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks --dry-run >/tmp/p0p4-install-retired-plugin-tool-dry-run.out 2>/tmp/p0p4-install-retired-plugin-tool-dry-run.err \
    && grep -Fq 'Remove retired managed plugin tool:' /tmp/p0p4-install-retired-plugin-tool-dry-run.out \
    && [[ -f "$retired_plugin_sync_tool" ]] \
    && cmp -s "$custom_plugin_tool" "$INSTALL_HOME_RETIRED_PLUGIN_TOOL/custom-tool.before" \
    && HOME="$INSTALL_HOME_RETIRED_PLUGIN_TOOL" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-retired-plugin-tool.out 2>/tmp/p0p4-install-retired-plugin-tool.err \
    && [[ ! -e "$retired_plugin_sync_tool" && ! -L "$retired_plugin_sync_tool" ]] \
    && cmp -s "$custom_plugin_tool" "$INSTALL_HOME_RETIRED_PLUGIN_TOOL/custom-tool.before"; then
    pass
else
    fail "installer must remove only the exact retired plugin sync tool and preserve unrelated plugin tools"
fi

test_start "installer reports and prunes an otherwise empty retired plugin tools directory"
INSTALL_HOME_EMPTY_RETIRED_PLUGIN_ROOT="$(mktemp -d)"
INSTALL_HOME_EMPTY_RETIRED_PLUGIN_TOOL="$INSTALL_HOME_EMPTY_RETIRED_PLUGIN_ROOT/assistant-[x]-home"
p0p4_register_cleanup "$INSTALL_HOME_EMPTY_RETIRED_PLUGIN_ROOT"
empty_retired_plugin_tools_directory="$INSTALL_HOME_EMPTY_RETIRED_PLUGIN_TOOL/.codex/tools/plugins"
mkdir -p "$empty_retired_plugin_tools_directory"
printf 'legacy plugin sync tool\n' >"$empty_retired_plugin_tools_directory/sync-plugin-skills.sh"
if HOME="$INSTALL_HOME_EMPTY_RETIRED_PLUGIN_TOOL" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks --dry-run >/tmp/p0p4-install-empty-retired-plugin-tool-dry-run.out 2>/tmp/p0p4-install-empty-retired-plugin-tool-dry-run.err \
    && grep -Fq 'Remove retired managed plugin tool:' /tmp/p0p4-install-empty-retired-plugin-tool-dry-run.out \
    && grep -Fq 'Remove empty retired plugin tools directory:' /tmp/p0p4-install-empty-retired-plugin-tool-dry-run.out \
    && [[ -d "$empty_retired_plugin_tools_directory" ]] \
    && HOME="$INSTALL_HOME_EMPTY_RETIRED_PLUGIN_TOOL" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-empty-retired-plugin-tool.out 2>/tmp/p0p4-install-empty-retired-plugin-tool.err \
    && [[ ! -e "$empty_retired_plugin_tools_directory" && ! -L "$empty_retired_plugin_tools_directory" ]]; then
    pass
else
    fail "installer dry-run must report and reinstall must prune an otherwise empty retired plugin tools directory"
fi

test_start "installer rejects unsafe retired plugin tool parents before skill mutation"
INSTALL_HOME_UNSAFE_RETIRED_PLUGIN_ROOT="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_UNSAFE_RETIRED_PLUGIN_ROOT"
unsafe_retired_plugin_failure=""
for unsafe_parent_kind in symlink wrong-type; do
    unsafe_home="$INSTALL_HOME_UNSAFE_RETIRED_PLUGIN_ROOT/$unsafe_parent_kind"
    unsafe_skill_directory="$unsafe_home/.codex/skills/assistant-workflow"
    unsafe_plugin_parent="$unsafe_home/.codex/tools/plugins"
    mkdir -p "$unsafe_skill_directory" "$(dirname "$unsafe_plugin_parent")"
    printf 'preserve existing skill\n' >"$unsafe_skill_directory/SKILL.md"
    cp "$unsafe_skill_directory/SKILL.md" "$unsafe_home/skill.before"
    if [[ "$unsafe_parent_kind" == "symlink" ]]; then
        unsafe_external_directory="$INSTALL_HOME_UNSAFE_RETIRED_PLUGIN_ROOT/external-target"
        mkdir -p "$unsafe_external_directory"
        printf 'preserve external target\n' >"$unsafe_external_directory/sentinel.txt"
        cp "$unsafe_external_directory/sentinel.txt" "$unsafe_home/external.before"
        ln -s "$unsafe_external_directory" "$unsafe_plugin_parent"
    else
        printf 'preserve wrong-type parent\n' >"$unsafe_plugin_parent"
    fi

    if HOME="$unsafe_home" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-unsafe-retired-plugin.out 2>/tmp/p0p4-install-unsafe-retired-plugin.err; then
        unsafe_retired_plugin_failure="$unsafe_parent_kind parent was accepted"
        break
    elif ! cmp -s "$unsafe_skill_directory/SKILL.md" "$unsafe_home/skill.before"; then
        unsafe_retired_plugin_failure="$unsafe_parent_kind rejection mutated the existing skill"
        break
    elif [[ "$unsafe_parent_kind" == "symlink" ]] && ! cmp -s "$unsafe_external_directory/sentinel.txt" "$unsafe_home/external.before"; then
        unsafe_retired_plugin_failure="symlink rejection mutated the external target"
        break
    fi
done
if [[ -z "$unsafe_retired_plugin_failure" ]]; then
    pass
else
    fail "$unsafe_retired_plugin_failure"
fi

test_start "Codex reinstall preserves legacy Memory Graph MCP config without a Codex CLI"
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

[features]
hooks = false
codex_hooks = false
STALE_CODEX_MCP
chmod 600 "$INSTALL_HOME_NINE/.codex/config.toml"
cp "$INSTALL_HOME_NINE/.codex/config.toml" "$INSTALL_HOME_NINE/original-config.toml"
if HOME="$INSTALL_HOME_NINE" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-stale-codex-mcp.out 2>/tmp/p0p4-install-stale-codex-mcp.err; then
    config_file="$INSTALL_HOME_NINE/.codex/config.toml"
    config_mode="$(p0p4_file_mode_octal "$config_file")"
    if ! cmp -s "$config_file" "$INSTALL_HOME_NINE/original-config.toml" \
        || [[ "$config_mode" != "600" ]]; then
        fail "expected legacy Codex MCP configuration to remain byte-for-byte unchanged with its file mode preserved"
    else
        pass
    fi
else
    fail "Codex install with legacy memory-graph MCP config failed; see /tmp/p0p4-install-stale-codex-mcp.err"
fi

test_start "clean install keeps legacy offline evals but excludes source-only promotion evaluators"
INSTALL_HOME_EIGHT="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_EIGHT"
mkdir -p "$INSTALL_HOME_EIGHT/.codex/tools/evals/lib"
printf 'stale\n' >"$INSTALL_HOME_EIGHT/.codex/tools/evals/run-codex-framework-evals.sh"
printf 'stale\n' >"$INSTALL_HOME_EIGHT/.codex/tools/evals/finalize-workflow-kernel-review.sh"
printf 'stale\n' >"$INSTALL_HOME_EIGHT/.codex/tools/evals/lib/context-budget-evidence.sh"
printf 'stale\n' >"$INSTALL_HOME_EIGHT/.codex/tools/evals/validate-promotion-decision-schema.cjs"
printf 'stale\n' >"$INSTALL_HOME_EIGHT/.codex/tools/evals/package.json"
printf 'stale\n' >"$INSTALL_HOME_EIGHT/.codex/tools/evals/package-lock.json"
mkdir -p "$INSTALL_HOME_EIGHT/.codex/tools/evals/node_modules/stale/nested"
printf 'stale\n' >"$INSTALL_HOME_EIGHT/.codex/tools/evals/node_modules/stale/nested/package.json"
printf 'stale\n' >"$INSTALL_HOME_EIGHT/.codex/tools/context-budget-report.sh"
if HOME="$INSTALL_HOME_EIGHT" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-evals.out 2>/tmp/p0p4-install-evals.err; then
    installed_runner="$INSTALL_HOME_EIGHT/.codex/tools/evals/run-framework-instruction-evals.sh"
    installed_fixture="$INSTALL_HOME_EIGHT/.codex/docs/evals/framework-instruction-cases.json"
    installed_codex_runner="$INSTALL_HOME_EIGHT/.codex/tools/evals/run-codex-framework-evals.sh"
    installed_finalizer="$INSTALL_HOME_EIGHT/.codex/tools/evals/finalize-workflow-kernel-review.sh"
    installed_evidence_lib="$INSTALL_HOME_EIGHT/.codex/tools/evals/lib/context-budget-evidence.sh"
    installed_promotion_validator="$INSTALL_HOME_EIGHT/.codex/tools/evals/validate-promotion-decision-schema.cjs"
    installed_eval_package="$INSTALL_HOME_EIGHT/.codex/tools/evals/package.json"
    installed_eval_package_lock="$INSTALL_HOME_EIGHT/.codex/tools/evals/package-lock.json"
    installed_eval_node_modules="$INSTALL_HOME_EIGHT/.codex/tools/evals/node_modules"
    installed_context_reporter="$INSTALL_HOME_EIGHT/.codex/tools/context-budget-report.sh"
    if [[ -x "$installed_runner" ]] \
        && [[ -f "$installed_fixture" ]] \
        && [[ ! -e "$installed_codex_runner" ]] \
        && [[ ! -e "$installed_finalizer" ]] \
        && [[ ! -e "$installed_evidence_lib" ]] \
        && [[ ! -e "$installed_promotion_validator" ]] \
        && [[ ! -e "$installed_eval_package" ]] \
        && [[ ! -e "$installed_eval_package_lock" ]] \
        && [[ ! -e "$installed_eval_node_modules" ]] \
        && [[ ! -e "$installed_context_reporter" ]] \
        && HOME="$INSTALL_HOME_EIGHT" "$installed_runner" --validate-fixture >/tmp/p0p4-installed-eval-runner.out 2>/tmp/p0p4-installed-eval-runner.err; then
        pass
    else
        fail "clean install must omit source-only promotion evaluators while preserving the legacy offline runner and fixture"
    fi
else
    fail "codex install for eval runner fixture failed; see /tmp/p0p4-install-evals.err"
fi

test_start "default install uses assistant inventory without domain-specific rules"
INSTALL_HOME_TEN="$(mktemp -d)"
CUSTOM_INVENTORY_FIXTURE="$(mktemp -d "$FRAMEWORK_DIR/skills/custom-inventory-fixture-XXXXXX")"
CUSTOM_INVENTORY_FIXTURE_NAME="$(basename "$CUSTOM_INVENTORY_FIXTURE")"
ASSISTANT_INVENTORY_FIXTURE="$(mktemp -d "$FRAMEWORK_DIR/skills/assistant-inventory-fixture-XXXXXX")"
ASSISTANT_INVENTORY_FIXTURE_NAME="$(basename "$ASSISTANT_INVENTORY_FIXTURE")"
p0p4_register_cleanup "$INSTALL_HOME_TEN" "$CUSTOM_INVENTORY_FIXTURE" "$ASSISTANT_INVENTORY_FIXTURE"
cat > "$CUSTOM_INVENTORY_FIXTURE/SKILL.md" <<CUSTOM_INVENTORY_SKILL
---
name: $CUSTOM_INVENTORY_FIXTURE_NAME
description: Local-only custom fixture that must not be installed by default.
---

# Custom Inventory Fixture
CUSTOM_INVENTORY_SKILL
cat > "$ASSISTANT_INVENTORY_FIXTURE/SKILL.md" <<ASSISTANT_INVENTORY_SKILL
---
name: $ASSISTANT_INVENTORY_FIXTURE_NAME
description: Assistant-named custom fixture that should follow the normal assistant inventory rule.
---

# Assistant Inventory Fixture
ASSISTANT_INVENTORY_SKILL
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
        if [[ "$source_skill" == "assistant-memory" || "$source_skill" == "assistant-reflexion" ]]; then
            continue
        fi
        if [[ ! -d "$installed_skills_dir/$source_skill" ]]; then
            missing_assistant_skill="$source_skill"
            break
        fi
    done < <(find "$FRAMEWORK_DIR/skills" -maxdepth 2 -path "$FRAMEWORK_DIR/skills/assistant-*/SKILL.md" -type f | sort)

    rm -rf "$CUSTOM_INVENTORY_FIXTURE" "$ASSISTANT_INVENTORY_FIXTURE"

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
    elif [[ "$source_assistant_skill_count" -lt "14" ]]; then
        fail "expected source inventory to contain at least 14 non-retired assistant skills including the assistant-named custom fixture; found $source_assistant_skill_count"
    elif [[ "$agents_assistant_skill_rows" != "0" ]] || ! grep -Fq "Codex uses installed skills through native skill routing." "$agents_file"; then
        fail "expected generated Codex AGENTS.md to stay lean and keep routing metadata in installed skills"
    elif [[ -n "$unexpected_installed_skill" ]]; then
        fail "expected default install to exclude non-assistant skill $unexpected_installed_skill"
    elif [[ -e "$installed_skills_dir/$CUSTOM_INVENTORY_FIXTURE_NAME" ]]; then
        fail "expected default install to exclude non-assistant local custom fixture"
    elif [[ ! -e "$installed_skills_dir/$ASSISTANT_INVENTORY_FIXTURE_NAME" ]]; then
        fail "expected default install to include assistant-named custom fixture"
    else
        pass
    fi
else
    rm -rf "$CUSTOM_INVENTORY_FIXTURE" "$ASSISTANT_INVENTORY_FIXTURE"
    fail "default install with custom fixture coverage failed; see /tmp/p0p4-install-default-skills.err"
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

test_start "selective debugging and review installs ship an executable common change-impact checker"
CHANGE_IMPACT_INSTALL_ROOT="$(mktemp -d)"
p0p4_register_cleanup "$CHANGE_IMPACT_INSTALL_ROOT"
change_impact_install_failure=""
for change_impact_skill in assistant-debugging assistant-review; do
    change_impact_home="$CHANGE_IMPACT_INSTALL_ROOT/$change_impact_skill home [isolated]"
    change_impact_case="$change_impact_home/change impact fixture"
    change_impact_skill_file="$change_impact_home/.codex/skills/$change_impact_skill/SKILL.md"
    change_impact_tool="$(dirname "$change_impact_skill_file")/../../tools/change-impact/validate-change-impact.cjs"
    change_impact_protocol="$(dirname "$change_impact_skill_file")/../../tools/change-impact/protocol.v1.json"
    change_impact_example="$(dirname "$change_impact_skill_file")/../../tools/change-impact/example.completion.v1.json"
    change_impact_reference="$change_impact_home/.codex/skills/$change_impact_skill/references/change-impact.md"
    mkdir -p "$change_impact_case"
    if ! HOME="$change_impact_home" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill "$change_impact_skill" --no-hooks >/tmp/p0p4-change-impact-${change_impact_skill}.out 2>/tmp/p0p4-change-impact-${change_impact_skill}.err; then
        change_impact_install_failure="$change_impact_skill selective install failed"
        break
    elif [[ ! -f "$change_impact_skill_file" || ! -f "$change_impact_tool" || ! -f "$change_impact_protocol" || ! -f "$change_impact_example" ]]; then
        change_impact_install_failure="$change_impact_skill selective install omitted common validator resources at the path resolved from its loaded SKILL.md"
        break
    elif [[ -d "$change_impact_home/.codex/skills/assistant-workflow" || ! -f "$change_impact_reference" ]] \
        || ! grep -Fq '../../tools/change-impact/validate-change-impact.cjs' "$change_impact_reference"; then
        change_impact_install_failure="$change_impact_skill did not resolve the installed common checker without workflow"
        break
    elif [[ "$change_impact_skill" == "assistant-debugging" && ! -f "$change_impact_home/.codex/skills/assistant-review/SKILL.md" ]]; then
        change_impact_install_failure="assistant-debugging selective installation omitted its canonical assistant-review producer"
        break
    elif [[ "$change_impact_skill" == "assistant-debugging" && ! -f "$change_impact_home/.codex/skills/assistant-verification/SKILL.md" ]]; then
        change_impact_install_failure="assistant-debugging selective installation omitted its canonical assistant-verification producer"
        break
    elif [[ "$change_impact_skill" == "assistant-debugging" && ! -f "$change_impact_home/.codex/skills/assistant-tdd/SKILL.md" ]]; then
        change_impact_install_failure="assistant-debugging selective installation omitted its canonical assistant-tdd dependency"
        break
    elif [[ "$change_impact_skill" == "assistant-review" ]] && { [[ -d "$change_impact_home/.codex/skills/assistant-debugging" ]] || [[ -d "$change_impact_home/.codex/skills/assistant-workflow" ]]; }; then
        change_impact_install_failure="assistant-review selective installation copied an unrelated consumer"
        break
    elif ! node -e 'const fs=require("node:fs"); const source=JSON.parse(fs.readFileSync(process.argv[1], "utf8")); const target=process.argv[2]; for (const [name, value] of Object.entries(source)) fs.writeFileSync(`${target}/${name}.json`, JSON.stringify(value));' "$FRAMEWORK_DIR/tools/change-impact/example.completion.v1.json" "$change_impact_case"; then
        change_impact_install_failure="$change_impact_skill could not materialize the valid checker fixture"
        break
    elif ! node "$change_impact_tool" --phase completion --capture "$change_impact_case/capture.json" --expected "$change_impact_case/expected.json" --assessment "$change_impact_case/assessment.json" --review "$change_impact_case/review.json" >/tmp/p0p4-change-impact-${change_impact_skill}-valid.out; then
        change_impact_install_failure="$change_impact_skill installed checker rejected its valid protocol example"
        break
    elif ! node -e 'const fs=require("node:fs"); const p=process.argv[1]; const value=JSON.parse(fs.readFileSync(p,"utf8")); const edge=value.edges.pop(); value.requirements=value.requirements.filter((requirement) => requirement.edge_id !== edge.id); fs.writeFileSync(p,JSON.stringify(value));' "$change_impact_case/capture.json"; then
        change_impact_install_failure="$change_impact_skill could not materialize the consumer-omission fixture"
        break
    elif node "$change_impact_tool" --phase completion --capture "$change_impact_case/capture.json" --expected "$change_impact_case/expected.json" --assessment "$change_impact_case/assessment.json" --review "$change_impact_case/review.json" >/tmp/p0p4-change-impact-${change_impact_skill}-consumer-omission.out; then
        change_impact_install_failure="$change_impact_skill installed checker accepted a capture missing a known consumer"
        break
    elif ! grep -Fq 'CAPTURE_EXPECTED_EDGES_MISMATCH' /tmp/p0p4-change-impact-${change_impact_skill}-consumer-omission.out; then
        change_impact_install_failure="$change_impact_skill consumer omission did not fail against independent expected truth"
        break
    elif ! node -e 'const fs=require("node:fs"); const source=JSON.parse(fs.readFileSync(process.argv[1], "utf8")); fs.writeFileSync(process.argv[2],JSON.stringify(source.capture));' "$FRAMEWORK_DIR/tools/change-impact/example.completion.v1.json" "$change_impact_case/capture.json"; then
        change_impact_install_failure="$change_impact_skill could not restore the root-omission fixture"
        break
    elif ! node -e 'const fs=require("node:fs"); const p=process.argv[1]; const value=JSON.parse(fs.readFileSync(p,"utf8")); value.roots=[]; fs.writeFileSync(p,JSON.stringify(value));' "$change_impact_case/capture.json"; then
        change_impact_install_failure="$change_impact_skill could not materialize the omission fixture"
        break
    elif node "$change_impact_tool" --phase completion --capture "$change_impact_case/capture.json" --expected "$change_impact_case/expected.json" --assessment "$change_impact_case/assessment.json" --review "$change_impact_case/review.json" >/tmp/p0p4-change-impact-${change_impact_skill}-omission.out; then
        change_impact_install_failure="$change_impact_skill installed checker accepted an empty shared discovery-root capture"
        break
    elif ! grep -Fq 'CAPTURE_DISCOVERY_ROOTS_MISSING' /tmp/p0p4-change-impact-${change_impact_skill}-omission.out; then
        change_impact_install_failure="$change_impact_skill omission did not fail for the missing discovery-root reason"
        break
    fi
done
if [[ -z "$change_impact_install_failure" ]]; then
    pass
else
    fail "$change_impact_install_failure"
fi


test_start "Codex writer migration fresh upgrade and dry-run preserve unrelated configuration"
writer_install_home="$(mktemp -d "${TMPDIR:-/tmp}/writer-install.XXXXXX")"
p0p4_register_cleanup "$writer_install_home"
mkdir -p "$writer_install_home/.codex/agents"
printf '%s\n' 'personal setting = retained' >"$writer_install_home/.codex/config.toml"
printf '%s\n' 'unrelated custom role' >"$writer_install_home/.codex/agents/personal-role.toml"
cp "$writer_install_home/.codex/config.toml" "$writer_install_home/config.before"
writer_install_ok=true
for writer_install_phase in fresh upgrade; do
    if ! HOME="$writer_install_home" CODEX_HOME="$writer_install_home/.codex" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >"$writer_install_home/$writer_install_phase.out" 2>"$writer_install_home/$writer_install_phase.err"; then
        writer_install_ok=false
        break
    fi
    writer_definition_count=0
    for writer_source in "$FRAMEWORK_DIR/agents/codex/"*.toml; do
        writer_definition_count=$((writer_definition_count + 1))
        cmp -s "$writer_source" "$writer_install_home/.codex/agents/${writer_source##*/}" || writer_install_ok=false
    done
    [[ "$writer_definition_count" == 12 ]] || writer_install_ok=false
    cmp -s "$writer_install_home/config.before" "$writer_install_home/.codex/config.toml" || writer_install_ok=false
    [[ "$(cat "$writer_install_home/.codex/agents/personal-role.toml")" == 'unrelated custom role' ]] || writer_install_ok=false
    # Simulate an old managed compatibility definition before upgrade.
    if [[ "$writer_install_phase" == fresh ]]; then
        printf '%s\n' 'old managed writer' >"$writer_install_home/.codex/agents/code-writer.toml"
        rm "$writer_install_home/.codex/agents/intelligent-writer.toml" "$writer_install_home/.codex/agents/mechanical-writer.toml"
    fi
done
writer_before="$(find "$writer_install_home/.codex" "$writer_install_home/.agents" -type f -exec shasum -a 256 {} + | LC_ALL=C sort)"
if ! HOME="$writer_install_home" CODEX_HOME="$writer_install_home/.codex" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks --dry-run >"$writer_install_home/dry.out" 2>"$writer_install_home/dry.err"; then writer_install_ok=false; fi
writer_after="$(find "$writer_install_home/.codex" "$writer_install_home/.agents" -type f -exec shasum -a 256 {} + | LC_ALL=C sort)"
[[ "$writer_before" == "$writer_after" ]] || writer_install_ok=false
if [[ "$writer_install_ok" == true ]]; then pass; else fail "writer migration installer parity/preservation/dry-run failure"; fi

test_start "Claude writer migration preserves native metadata compatibility and unrelated configuration"
claude_writer_home="$(mktemp -d "${TMPDIR:-/tmp}/claude-writer-install.XXXXXX")"
p0p4_register_cleanup "$claude_writer_home"
mkdir -p "$claude_writer_home/.claude/agents"
printf '%s\n' '{"personal":true}' >"$claude_writer_home/.claude/settings.json"
printf '%s\n' 'unrelated custom role' >"$claude_writer_home/.claude/agents/personal-role.md"
cp "$claude_writer_home/.claude/settings.json" "$claude_writer_home/settings.before"
claude_writer_ok=true
for claude_writer_phase in fresh upgrade; do
    if ! HOME="$claude_writer_home" bash "$FRAMEWORK_DIR/install.sh" --agent claude --skill assistant-workflow --no-hooks >"$claude_writer_home/$claude_writer_phase.out" 2>"$claude_writer_home/$claude_writer_phase.err"; then
        claude_writer_ok=false
        break
    fi
    for claude_writer_source in "$FRAMEWORK_DIR/agents/claude/"*.md; do
        cmp -s "$claude_writer_source" "$claude_writer_home/.claude/agents/${claude_writer_source##*/}" || claude_writer_ok=false
    done
    cmp -s "$claude_writer_home/settings.before" "$claude_writer_home/.claude/settings.json" || claude_writer_ok=false
    [[ "$(cat "$claude_writer_home/.claude/agents/personal-role.md")" == 'unrelated custom role' ]] || claude_writer_ok=false
    if [[ "$claude_writer_phase" == fresh ]]; then
        printf '%s\n' 'old managed writer' >"$claude_writer_home/.claude/agents/code-writer.md"
        rm "$claude_writer_home/.claude/agents/intelligent-writer.md" "$claude_writer_home/.claude/agents/mechanical-writer.md"
    fi
done
claude_writer_before="$(find "$claude_writer_home/.claude" -type f -exec shasum -a 256 {} + | LC_ALL=C sort)"
if ! HOME="$claude_writer_home" bash "$FRAMEWORK_DIR/install.sh" --agent claude --skill assistant-workflow --no-hooks --dry-run >"$claude_writer_home/dry.out" 2>"$claude_writer_home/dry.err"; then claude_writer_ok=false; fi
claude_writer_after="$(find "$claude_writer_home/.claude" -type f -exec shasum -a 256 {} + | LC_ALL=C sort)"
[[ "$claude_writer_before" == "$claude_writer_after" ]] || claude_writer_ok=false
if [[ "$claude_writer_ok" == true ]]; then pass; else fail "Claude writer migration parity/preservation/dry-run failure"; fi

# Fixed declared-protocol fixture: independent of the installer's compatibility reader.
write_ownership_workflow_fixture() {
    local workflow="$1" variant="$2" file
    mkdir -p "$workflow/contracts"
    printf '%s\n' '---' 'name: assistant-workflow' 'description: Retained ownership protocol fixture.' '---' >"$workflow/SKILL.md"
    printf '%s\n' 'schema_version: "13.0"' 'contract: index' 'skill: assistant-workflow' >"$workflow/contracts/index.yaml"
    cat >"$workflow/contracts/handoffs.yaml" <<'PROTOCOL'
schema_version: "13.0"
contract: handoffs
skill: assistant-workflow
worker_stage_protocol:
  stages:
    - value: test_authoring
      mutation_scope: tests_only
      active_tdd_prerequisite: none
      completes_build: false
    - value: production
      mutation_scope: tests_and_production
      active_tdd_prerequisite: current_matching_red
      completes_build: false
    - value: refactor
      mutation_scope: behavior_neutral
      active_tdd_prerequisite: current_passing_green
      completes_build: false
PROTOCOL
    case "$variant" in
        old|recovery|full|gemini) printf '%s\n' 'schema_version: "12.0"' 'contract: index' 'skill: assistant-workflow' >"$workflow/contracts/index.yaml" ;;
        no-stages) sed '/^worker_stage_protocol:/,$d' "$workflow/contracts/handoffs.yaml" >"$workflow/handoffs.tmp"; mv "$workflow/handoffs.tmp" "$workflow/contracts/handoffs.yaml" ;;
        stage-mismatch) sed 's/current_matching_red/none/' "$workflow/contracts/handoffs.yaml" >"$workflow/handoffs.tmp"; mv "$workflow/handoffs.tmp" "$workflow/contracts/handoffs.yaml" ;;
        early-completion) sed 's/completes_build: false/completes_build: true/' "$workflow/contracts/handoffs.yaml" >"$workflow/handoffs.tmp"; mv "$workflow/handoffs.tmp" "$workflow/contracts/handoffs.yaml" ;;
        missing-index) rm "$workflow/contracts/index.yaml" ;;
        duplicate-index) printf '%s\n' 'skill: assistant-workflow' >>"$workflow/contracts/index.yaml" ;;
        duplicate-handoffs) printf '%s\n' 'schema_version: "13.0"' >>"$workflow/contracts/handoffs.yaml" ;;
        malformed) printf '%s\n' 'schema_version: "13.0' 'contract: index' 'skill: assistant-workflow' >"$workflow/contracts/index.yaml" ;;
        wrong-identity) printf '%s\n' 'schema_version: "13.0"' 'contract: output' 'skill: assistant-workflow' >"$workflow/contracts/index.yaml" ;;
        unsafe-workflow) rm -r "$workflow"; printf 'wrong path type\n' >"$workflow" ;;
        unsafe-skill) rm "$workflow/SKILL.md"; mkdir "$workflow/SKILL.md" ;;
        unsafe-index) rm "$workflow/contracts/index.yaml"; ln -s "$workflow/SKILL.md" "$workflow/contracts/index.yaml" ;;
        bom-crlf)
            for file in "$workflow/SKILL.md" "$workflow/contracts/index.yaml" "$workflow/contracts/handoffs.yaml"; do
                { printf '\357\273\277'; awk '{printf "%s\r\n", $0}' "$file"; } >"$workflow/encoded.tmp"
                mv "$workflow/encoded.tmp" "$file"
            done
            ;;
    esac
}

ownership_install_fingerprint() {
    # Same file-hash basis as the existing dry-run controls, plus directories/links.
    find "$1" -type d -print -o -type l -exec ls -ld {} \; -o -type f -exec shasum -a 256 {} \; | LC_ALL=C sort
}

ownership_install_compatibility_matrix() {
    local matrix_root="$1" agent variant mode case_home agent_home skills workflow before after workflow_before status log
    local -a args
    for agent in codex claude; do
        for variant in old no-stages stage-mismatch early-completion missing-index duplicate-index duplicate-handoffs malformed wrong-identity unsafe-workflow unsafe-skill unsafe-index absent current bom-crlf recovery full; do
            for mode in normal dry-run; do
                [[ "$mode" == dry-run && ( "$variant" == recovery || "$variant" == full ) ]] && continue
                case_home="$matrix_root/$agent-$variant-$mode"
                mkdir -p "$case_home"
                if [[ "$agent" == codex ]]; then
                    agent_home="$case_home/Custom Codex Home"
                else
                    agent_home="$case_home/.claude"
                fi
                skills="$agent_home/skills"; workflow="$skills/assistant-workflow"
                mkdir -p "$agent_home/agents" "$agent_home/tools"
                printf 'old role sentinel\n' >"$agent_home/agents/builder-tester.$([[ "$agent" == codex ]] && printf toml || printf md)"
                printf 'old tool sentinel\n' >"$agent_home/tools/sentinel.txt"
                if [[ "$agent" == codex ]]; then printf 'personal = "retained"\n' >"$agent_home/config.toml"; else printf '{"personal":true}\n' >"$agent_home/settings.json"; fi
                if [[ "$variant" != absent ]]; then write_ownership_workflow_fixture "$workflow" "$variant"; fi
                if [[ "$variant" == recovery || "$variant" == full ]]; then
                    mkdir -p "$skills/assistant-tdd"
                    printf 'OLD_SPECIALIST_SENTINEL\n' >"$skills/assistant-tdd/SKILL.md"
                fi
                before="$(ownership_install_fingerprint "$case_home")"
                workflow_before="$(if [[ -d "$workflow" ]]; then ownership_install_fingerprint "$workflow"; fi)"
                args=(--agent "$agent" --no-hooks)
                if [[ "$variant" == recovery ]]; then args+=(--skill assistant-workflow); elif [[ "$variant" != full ]]; then args+=(--skill assistant-docs); fi
                [[ "$mode" == dry-run ]] && args+=(--dry-run)
                log="$matrix_root/$agent-$variant-$mode.log"
                status=0
                # Claude deliberately receives a hostile ambient CODEX_HOME.
                HOME="$case_home" CODEX_HOME="$([[ "$agent" == codex ]] && printf '%s' "$agent_home" || printf /)" bash "$FRAMEWORK_DIR/install.sh" "${args[@]}" >"$log" 2>&1 || status=$?
                after="$(ownership_install_fingerprint "$case_home")"
                case "$variant" in
                    absent|current|bom-crlf|recovery|full)
                        if [[ "$status" != 0 ]]; then ownership_matrix_failure="$agent/$variant/$mode unexpectedly rejected; $log"; return 1; fi
                        if [[ "$mode" == dry-run && "$before" != "$after" ]]; then ownership_matrix_failure="$agent/$variant dry-run mutated managed tree"; return 1; fi
                        if [[ "$variant" == absent && -e "$workflow" ]]; then ownership_matrix_failure="$agent selective absent install added workflow"; return 1; fi
                        if [[ "$variant" == current || "$variant" == bom-crlf ]]; then
                            if [[ "$workflow_before" != "$(ownership_install_fingerprint "$workflow")" ]]; then ownership_matrix_failure="$agent selective install refreshed retained compatible controller"; return 1; fi
                        fi
                        if [[ "$variant" == recovery || "$variant" == full ]]; then
                            if ! cmp -s <(sed -e "s|{agent_state_dir}|.${agent}|g" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml") "$workflow/contracts/handoffs.yaml" \
                                || ! cmp -s "$FRAMEWORK_DIR/skills/assistant-tdd/contracts/phase-gates.yaml" "$skills/assistant-tdd/contracts/phase-gates.yaml"; then
                                ownership_matrix_failure="$agent coupled refresh omitted controller or old TDD recovery"; return 1
                            fi
                            if [[ "$variant" == recovery ]] && ! HOME="$case_home" CODEX_HOME="$([[ "$agent" == codex ]] && printf '%s' "$agent_home" || printf /)" bash "$FRAMEWORK_DIR/install.sh" --agent "$agent" --skill assistant-docs --no-hooks >"$log.retry" 2>&1; then
                                ownership_matrix_failure="$agent docs retry failed after workflow-first recovery"; return 1
                            fi
                        fi
                        ;;
                    *)
                        if [[ "$status" == 0 ]]; then ownership_matrix_failure="$agent/$variant/$mode accepted incompatible retained workflow"; return 1; fi
                        if [[ "$before" != "$after" ]]; then ownership_matrix_failure="$agent/$variant/$mode rejected after managed-tree mutation"; return 1; fi
                        if [[ "$variant" != unsafe-* ]] && { ! grep -Fq 'INCOMPATIBLE_WORKFLOW_ROLE_UPGRADE' "$log" || ! grep -Fq -- '--skill assistant-workflow' "$log" || ! grep -Fq "$workflow" "$log"; }; then
                            ownership_matrix_failure="$agent/$variant/$mode lacks diagnostic/path/workflow-first recovery; $log"; return 1
                        fi
                        ;;
                esac
            done
        done
    done
    # Gemini does not copy the coupled profiles and keeps native fallback behavior.
    case_home="$matrix_root/gemini"; mkdir -p "$case_home"
    write_ownership_workflow_fixture "$case_home/.gemini/skills/assistant-workflow" gemini
    if ! HOME="$case_home" CODEX_HOME=/ bash "$FRAMEWORK_DIR/install.sh" --agent gemini --skill assistant-docs --no-hooks >"$matrix_root/gemini.log" 2>&1; then
        ownership_matrix_failure='Gemini incorrectly inherited the ownership profile guard'; return 1
    fi

    # One common pre-mode source guard: representative branches, not a Cartesian inventory.
    local missing selection preview source_root extension expected_definition row
    while IFS='|' read -r agent missing selection preview; do
        row="$agent-$missing-$selection-$preview"
        source_root="$matrix_root/source-$row"
        mkdir -p "$source_root/skills/assistant-docs" "$source_root/skills/assistant-workflow"
        source_root="$(cd -P "$source_root" && pwd -P)"
        cp "$FRAMEWORK_DIR/install.sh" "$source_root/install.sh"
        for variant in assistant-docs assistant-workflow; do
            printf '%s\n' '---' "name: $variant" 'description: Source profile admission fixture.' '---' >"$source_root/skills/$variant/SKILL.md"
        done
        extension=md; [[ "$agent" != codex ]] || extension=toml
        if [[ "$missing" != absent-agent-source ]]; then
            p0p4_seed_required_writer_profiles "$source_root" "$agent"
            cp "$FRAMEWORK_DIR/agents/$agent/builder-tester.$extension" "$source_root/agents/$agent/"
            rm "$source_root/agents/$agent/$missing.$extension"
        fi
        expected_definition="$source_root/agents/$agent/$([[ "$missing" == absent-agent-source ]] && printf intelligent-writer || printf '%s' "$missing").$extension"
        case_home="$matrix_root/home-$row"; mkdir -p "$case_home"
        agent_home="$case_home/.$agent"
        mkdir -p "$agent_home/agents" "$agent_home/tools"
        printf 'old role sentinel\n' >"$agent_home/agents/builder-tester.$extension"
        printf 'old tool sentinel\n' >"$agent_home/tools/sentinel.txt"
        if [[ "$agent" == codex ]]; then printf 'personal = "retained"\n' >"$agent_home/config.toml"; else printf '{"personal":true}\n' >"$agent_home/settings.json"; fi
        before="$(ownership_install_fingerprint "$case_home")"
        args=(--agent "$agent" --no-hooks)
        [[ "$selection" == full ]] || args+=(--skill "assistant-$selection")
        [[ "$preview" != dry-run ]] || args+=(--dry-run)
        log="$matrix_root/source-$row.log"; status=0
        HOME="$case_home" CODEX_HOME="$([[ "$agent" == codex ]] && printf '%s' "$agent_home" || printf /)" bash "$source_root/install.sh" "${args[@]}" >"$log" 2>&1 || status=$?
        after="$(ownership_install_fingerprint "$case_home")"
        if [[ "$status" == 0 ]]; then ownership_matrix_failure="$row accepted missing mandatory writer source; $log"; return 1; fi
        if [[ "$before" != "$after" ]]; then ownership_matrix_failure="$row missing-source refusal mutated managed tree"; return 1; fi
        if ! grep -Fq 'required writer definition' "$log" || ! grep -Fq "$expected_definition" "$log" || ! grep -Fq 'No installation files have been changed' "$log"; then
            ownership_matrix_failure="$row lacks actionable missing-definition diagnostic; $log"; return 1
        fi
    done <<'SOURCE_PROFILE_CASES'
codex|intelligent-writer|full|normal
codex|mechanical-writer|workflow|dry-run
claude|intelligent-writer|docs|normal
claude|mechanical-writer|full|dry-run
codex|absent-agent-source|docs|dry-run
claude|absent-agent-source|workflow|normal
SOURCE_PROFILE_CASES
}

test_start "selective Claude and Codex role upgrades require a compatible retained workflow before writes"
ownership_matrix_root="$(mktemp -d "${TMPDIR:-/tmp}/ownership-upgrade.XXXXXX")"
p0p4_register_cleanup "$ownership_matrix_root"
ownership_matrix_failure=''
if ownership_install_compatibility_matrix "$ownership_matrix_root"; then pass; else fail "$ownership_matrix_failure"; fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
