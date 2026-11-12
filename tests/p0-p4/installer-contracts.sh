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
route_guidance="For ordinary repository changes, use assistant-workflow when that skill is installed; use assistant-clarify for unclear or tangled intent."

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
            && grep -Fq "When a skill's description matches the request, read its \`SKILL.md\` and follow it through to its handoff" "$agents_file" \
            && grep -Fq "the references and contracts the current phase needs" "$agents_file" \
            && grep -Fq "Implement and verify directly when useful, at every size/risk" "$agents_file" \
            && grep -Fq "Formal plan, code, finding-closure and acceptance reviews use newly created independent agents" "$agents_file" \
            && grep -Fq "Keep orchestration proportional" "$agents_file" \
            && grep -Fq "including when no skill matches" "$agents_file" \
            && cmp -s "$FRAMEWORK_DIR/tools/progress/operating-guidance.md" "$INSTALL_HOME/.codex/tools/progress/operating-guidance.md" \
            && cmp -s "$FRAMEWORK_DIR/tools/progress/stagnation.py" "$INSTALL_HOME/.codex/tools/progress/stagnation.py" \
            && grep -Fq "approve a plan before medium+ or elevated-risk development edits" "$agents_file" \
            && grep -Fq "Stop for the user only to:" "$agents_file" \
            && grep -Fq "Use subagents when the user asks or applicable project or skill instructions require them; no separate spawn consent is needed." "$agents_file" \
            && ! LC_ALL=C grep -q '[^ -~]' <(sed -n '/ASSISTANT_FRAMEWORK_AGENTS_MD_START/,/ASSISTANT_FRAMEWORK_AGENTS_MD_END/p' "$agents_file") \
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
    elif ! cmp -s "$FRAMEWORK_DIR/docs/lifecycle-verification.md" "$installed_skills_dir/assistant-verification/references/lifecycle-verification.md" \
        || ! grep -Fq "references/lifecycle-verification.md" "$installed_skills_dir/assistant-verification/SKILL.md"; then
        fail "workflow verification dependency cannot resolve its exact installed local lifecycle guide"
    elif [[ -d "$installed_skills_dir/assistant-docs" ]]; then
        fail "expected selected workflow install to avoid unrelated assistant-docs"
    elif [[ "$assistant_skill_rows" != "0" ]]; then
        fail "expected lean Codex AGENTS.md to avoid duplicating installed skill routing tables; found $assistant_skill_rows rows"
    elif ! grep -Fq "When a skill's description matches the request" "$agents_file"; then
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
    elif [[ "$agents_assistant_skill_rows" != "0" ]] || ! grep -Fq "When a skill's description matches the request" "$agents_file"; then
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
    elif [[ ! -f "$change_impact_skill_file" || ! -f "$change_impact_tool" || ! -f "$change_impact_protocol" || ! -f "$change_impact_example" || ! -f "$(dirname "$change_impact_skill_file")/../../tools/progress/operating-guidance.md" || ! -f "$(dirname "$change_impact_skill_file")/../../tools/progress/stagnation.py" ]]; then
        change_impact_install_failure="$change_impact_skill selective install omitted common validator resources at the path resolved from its loaded SKILL.md"
        break
    elif ! cmp -s "$FRAMEWORK_DIR/docs/lifecycle-verification.md" "$(dirname "$change_impact_skill_file")/references/lifecycle-verification.md" \
        || ! grep -Eq "references/lifecycle-verification.md|lifecycle_reviewer_context" "$change_impact_skill_file" \
        || ! grep -Fq "references/lifecycle-verification.md" "$(dirname "$change_impact_skill_file")/contracts/index.yaml"; then
        change_impact_install_failure="$change_impact_skill cannot resolve its exact portable lifecycle guide from root/index"
        break
    elif [[ "$change_impact_skill" == "assistant-review" && -d "$change_impact_home/.codex/skills/assistant-verification" ]]; then
        change_impact_install_failure="standalone review acquired a verification dependency solely for guidance"
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

test_start "Claude install writes one managed CLAUDE.md block, preserves user content, and stays idempotent"
claude_md_home="$(mktemp -d "${TMPDIR:-/tmp}/claude-md-install.XXXXXX")"
p0p4_register_cleanup "$claude_md_home"
mkdir -p "$claude_md_home/.claude"
printf '%s\n' '# My own rules' 'Keep this line.' >"$claude_md_home/.claude/CLAUDE.md"
claude_md_ok=true
HOME="$claude_md_home" bash "$FRAMEWORK_DIR/install.sh" --agent claude --skill assistant-workflow --no-hooks --dry-run >"$claude_md_home/dry.out" 2>&1 || claude_md_ok=false
[[ "$(cat "$claude_md_home/.claude/CLAUDE.md")" == $'# My own rules\nKeep this line.' ]] || claude_md_ok=false
for claude_md_pass in 1 2; do
    HOME="$claude_md_home" bash "$FRAMEWORK_DIR/install.sh" --agent claude --skill assistant-workflow --no-hooks >"$claude_md_home/pass$claude_md_pass.out" 2>&1 || claude_md_ok=false
done
claude_md_file="$claude_md_home/.claude/CLAUDE.md"
[[ "$(count_occurrences "ASSISTANT_FRAMEWORK_AGENTS_MD_START" "$claude_md_file")" == "1" ]] || claude_md_ok=false
[[ "$(count_occurrences "ASSISTANT_FRAMEWORK_AGENTS_MD_END" "$claude_md_file")" == "1" ]] || claude_md_ok=false
grep -Fq "# Assistant Framework - Claude Code Instructions" "$claude_md_file" || claude_md_ok=false
grep -Fq 'under `~/.claude` as the common operating guidance' "$claude_md_file" || claude_md_ok=false
grep -Fq "Stop for the user only to:" "$claude_md_file" || claude_md_ok=false
grep -Fq "Keep this line." "$claude_md_file" || claude_md_ok=false
! grep -Fq "CODEX_HOME" "$claude_md_file" || claude_md_ok=false
LC_ALL=C grep -q '[^ -~]' "$claude_md_file" && claude_md_ok=false
if [[ "$claude_md_ok" == true ]]; then pass; else fail "Claude install must write one ASCII managed block in CLAUDE.md and preserve user content"; fi

test_start "Claude install preserves CLAUDE.md with prose-only or unbalanced installer markers"
claude_marker_home="$(mktemp -d "${TMPDIR:-/tmp}/claude-marker-install.XXXXXX")"
p0p4_register_cleanup "$claude_marker_home"
mkdir -p "$claude_marker_home/.claude"
claude_marker_ok=true
claude_marker_file="$claude_marker_home/.claude/CLAUDE.md"
printf '%s\n' 'Prose mentions ASSISTANT_FRAMEWORK_AGENTS_MD_START here.' 'Keep my rule.' >"$claude_marker_file"
HOME="$claude_marker_home" bash "$FRAMEWORK_DIR/install.sh" --agent claude --skill assistant-workflow --no-hooks >"$claude_marker_home/prose.out" 2>&1 || claude_marker_ok=false
grep -Fq "Prose mentions ASSISTANT_FRAMEWORK_AGENTS_MD_START here." "$claude_marker_file" || claude_marker_ok=false
grep -Fq "Keep my rule." "$claude_marker_file" || claude_marker_ok=false
printf '%s\n' 'before' '<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_START -->' 'orphan user rule' >"$claude_marker_file"
cp "$claude_marker_file" "$claude_marker_home/orphan.before"
HOME="$claude_marker_home" bash "$FRAMEWORK_DIR/install.sh" --agent claude --skill assistant-workflow --no-hooks >"$claude_marker_home/orphan.out" 2>&1 || claude_marker_ok=false
cmp -s "$claude_marker_file" "$claude_marker_home/orphan.before" || claude_marker_ok=false
grep -Fq "preserved unchanged" "$claude_marker_home/orphan.out" || claude_marker_ok=false
if [[ "$claude_marker_ok" == true ]]; then pass; else fail "Claude install must keep user content when installer markers are prose-only or unbalanced"; fi

test_start "Claude install keeps the existing CLAUDE.md file mode when adding or refreshing the managed block"
claude_mode_home="$(mktemp -d "${TMPDIR:-/tmp}/claude-mode-install.XXXXXX")"
p0p4_register_cleanup "$claude_mode_home"
mkdir -p "$claude_mode_home/.claude"
claude_mode_ok=true
claude_mode_file="$claude_mode_home/.claude/CLAUDE.md"
printf '%s\n' 'private rule' >"$claude_mode_file"
chmod 600 "$claude_mode_file"
for claude_mode_pass in 1 2; do
    (umask 022; HOME="$claude_mode_home" bash "$FRAMEWORK_DIR/install.sh" --agent claude --skill assistant-workflow --no-hooks >"$claude_mode_home/pass$claude_mode_pass.out" 2>&1) || claude_mode_ok=false
    [[ "$(ls -l "$claude_mode_file" | cut -c1-10)" == "-rw-------" ]] || claude_mode_ok=false
done
grep -Fq "private rule" "$claude_mode_file" || claude_mode_ok=false
if [[ "$claude_mode_ok" == true ]]; then pass; else fail "Claude install must preserve the original CLAUDE.md file mode"; fi

test_start "Claude install reinstalls over a read-only CLAUDE.md and leaves a symlinked CLAUDE.md alone"
claude_edge_home="$(mktemp -d "${TMPDIR:-/tmp}/claude-edge-install.XXXXXX")"
p0p4_register_cleanup "$claude_edge_home"
mkdir -p "$claude_edge_home/.claude" "$claude_edge_home/dotfiles"
claude_edge_ok=true
claude_edge_file="$claude_edge_home/.claude/CLAUDE.md"
printf '%s\n' 'read-only user rule' >"$claude_edge_file"
chmod 444 "$claude_edge_file"
for claude_edge_pass in 1 2; do
    HOME="$claude_edge_home" bash "$FRAMEWORK_DIR/install.sh" --agent claude --skill assistant-workflow --no-hooks >"$claude_edge_home/ro$claude_edge_pass.out" 2>&1 || claude_edge_ok=false
    [[ "$(ls -l "$claude_edge_file" | cut -c1-10)" == "-r--r--r--" ]] || claude_edge_ok=false
    [[ "$(count_occurrences "ASSISTANT_FRAMEWORK_AGENTS_MD_START" "$claude_edge_file")" == "1" ]] || claude_edge_ok=false
    grep -Fq "read-only user rule" "$claude_edge_file" || claude_edge_ok=false
done
chmod 644 "$claude_edge_file"
rm -f "$claude_edge_file"
printf '%s\n' 'dotfile rule' >"$claude_edge_home/dotfiles/CLAUDE.md"
ln -s "$claude_edge_home/dotfiles/CLAUDE.md" "$claude_edge_file"
HOME="$claude_edge_home" bash "$FRAMEWORK_DIR/install.sh" --agent claude --skill assistant-workflow --no-hooks >"$claude_edge_home/link.out" 2>&1 || claude_edge_ok=false
[[ -L "$claude_edge_file" ]] || claude_edge_ok=false
[[ "$(cat "$claude_edge_home/dotfiles/CLAUDE.md")" == "dotfile rule" ]] || claude_edge_ok=false
grep -Fq "symbolic link; preserved unchanged" "$claude_edge_home/link.out" || claude_edge_ok=false
if [[ "$claude_edge_ok" == true ]]; then pass; else fail "Claude install must handle a read-only CLAUDE.md and leave a symlinked CLAUDE.md unchanged"; fi

test_start "Claude reinstall works when stat behaves like GNU coreutils"
gnu_stat_home="$(mktemp -d "${TMPDIR:-/tmp}/gnu-stat-install.XXXXXX")"
p0p4_register_cleanup "$gnu_stat_home"
mkdir -p "$gnu_stat_home/.claude" "$gnu_stat_home/bin"
real_stat="$(command -v stat)"
cat >"$gnu_stat_home/bin/stat" <<GNUSTAT
#!/bin/bash
# GNU stat: -f prints filesystem status and fails on %Lp; -c %a prints the mode.
if [[ "\$1" == "-f" && "\$2" == "%Lp" ]]; then echo "  File: \$3"; echo "    ID: 0 Namelen: 255"; exit 1; fi
if [[ "\$1" == "-c" && "\$2" == "%a" ]]; then
    mode="\$("$real_stat" -c %a "\$3" 2>/dev/null)" || mode="\$("$real_stat" -f %Lp "\$3")" || exit 1
    echo "\$mode"
    exit 0
fi
exec "$real_stat" "\$@"
GNUSTAT
chmod +x "$gnu_stat_home/bin/stat"
gnu_stat_ok=true
printf '%s\n' 'user rule' >"$gnu_stat_home/.claude/CLAUDE.md"
for gnu_stat_pass in 1 2; do
    PATH="$gnu_stat_home/bin:$PATH" HOME="$gnu_stat_home" bash "$FRAMEWORK_DIR/install.sh" --agent claude --skill assistant-workflow --no-hooks >"$gnu_stat_home/pass$gnu_stat_pass.out" 2>&1 || gnu_stat_ok=false
done
[[ "$(count_occurrences "ASSISTANT_FRAMEWORK_AGENTS_MD_START" "$gnu_stat_home/.claude/CLAUDE.md")" == "1" ]] || gnu_stat_ok=false
grep -Fq "user rule" "$gnu_stat_home/.claude/CLAUDE.md" || gnu_stat_ok=false
if [[ "$gnu_stat_ok" == true ]]; then pass; else fail "Claude reinstall must not depend on BSD-only stat flags"; fi

# Fixed declared-protocol fixture: independent of the installer's compatibility reader.
write_ownership_workflow_fixture() {
    local workflow="$1" variant="$2" file
    mkdir -p "$workflow/contracts"
    printf '%s\n' '---' 'name: assistant-workflow' 'description: Retained ownership protocol fixture.' '---' >"$workflow/SKILL.md"
    printf '%s\n' 'schema_version: "16.0"' 'contract: index' 'skill: assistant-workflow' >"$workflow/contracts/index.yaml"
    cat >"$workflow/contracts/handoffs.yaml" <<'PROTOCOL'
schema_version: "16.0"
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
        old13|old14|old15|unknown-version)
            local target_version=14.0
            [[ "$variant" != old13 ]] || target_version=13.0
            [[ "$variant" != old15 ]] || target_version=15.0
            [[ "$variant" != unknown-version ]] || target_version=17.0
            for file in "$workflow/contracts/index.yaml" "$workflow/contracts/handoffs.yaml"; do
                sed "s/16.0/$target_version/" "$file" >"$workflow/version.tmp"; mv "$workflow/version.tmp" "$file"
            done ;;
        mixed-version) sed 's/16.0/14.0/' "$workflow/contracts/index.yaml" >"$workflow/version.tmp"; mv "$workflow/version.tmp" "$workflow/contracts/index.yaml" ;;
        old|recovery|full) printf '%s\n' 'schema_version: "12.0"' 'contract: index' 'skill: assistant-workflow' >"$workflow/contracts/index.yaml" ;;
        no-stages) sed '/^worker_stage_protocol:/,$d' "$workflow/contracts/handoffs.yaml" >"$workflow/handoffs.tmp"; mv "$workflow/handoffs.tmp" "$workflow/contracts/handoffs.yaml" ;;
        stage-mismatch) sed 's/current_matching_red/none/' "$workflow/contracts/handoffs.yaml" >"$workflow/handoffs.tmp"; mv "$workflow/handoffs.tmp" "$workflow/contracts/handoffs.yaml" ;;
        early-completion) sed 's/completes_build: false/completes_build: true/' "$workflow/contracts/handoffs.yaml" >"$workflow/handoffs.tmp"; mv "$workflow/handoffs.tmp" "$workflow/contracts/handoffs.yaml" ;;
        missing-index) rm "$workflow/contracts/index.yaml" ;;
        duplicate-index) printf '%s\n' 'skill: assistant-workflow' >>"$workflow/contracts/index.yaml" ;;
        duplicate-handoffs) printf '%s\n' 'schema_version: "16.0"' >>"$workflow/contracts/handoffs.yaml" ;;
        malformed) printf '%s\n' 'schema_version: "16.0' 'contract: index' 'skill: assistant-workflow' >"$workflow/contracts/index.yaml" ;;
        wrong-identity) printf '%s\n' 'schema_version: "16.0"' 'contract: output' 'skill: assistant-workflow' >"$workflow/contracts/index.yaml" ;;
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

ownership_install_fingerprint_difference() {
    local label="$1" before="$2" after="$3"
    [[ "$before" != "$after" ]] || return 0
    printf 'Fingerprint difference: %s (first 120 diff lines)\n' "$label" >&2
    diff -u <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -n 120 >&2 || true
}

test_start "selected Workflow closure preflights supported Python before real and dry-run writes"
runtime_root="$(mktemp -d "${TMPDIR:-/tmp}/workflow-runtime.XXXXXX")"
p0p4_register_cleanup "$runtime_root"
runtime_source="$runtime_root/source"
runtime_bin="$runtime_root/runtime bin"
runtime_host_python="$(command -v python3)"
mkdir -p "$runtime_source/skills" "$runtime_bin"
cp "$FRAMEWORK_DIR/install.sh" "$runtime_source/install.sh"
for runtime_skill in assistant-workflow assistant-docs assistant-runtime-dependent; do
    mkdir -p "$runtime_source/skills/$runtime_skill"
    printf '%s\n' '---' "name: $runtime_skill" 'description: Isolated interpreter preflight fixture.' >"$runtime_source/skills/$runtime_skill/SKILL.md"
    if [[ "$runtime_skill" == assistant-runtime-dependent ]]; then
        printf '%s\n' 'requires:' '  - assistant-workflow' >>"$runtime_source/skills/$runtime_skill/SKILL.md"
    fi
    printf '%s\n' '---' >>"$runtime_source/skills/$runtime_skill/SKILL.md"
done
# Preserve ordinary installer dependencies while making Python truly absent
# from this PATH. Supported proxies below use an independently captured binary.
for runtime_directory in /bin /usr/bin /sbin /usr/sbin; do
    for runtime_tool in "$runtime_directory"/*; do
        runtime_name="${runtime_tool##*/}"
        case "$runtime_name" in python*|py) continue ;; esac
        [[ -e "$runtime_bin/$runtime_name" ]] || ln -s "$runtime_tool" "$runtime_bin/$runtime_name" 2>/dev/null || true
    done
done
for runtime_name in rsync jq; do
    runtime_tool="$(command -v "$runtime_name")"
    [[ -e "$runtime_bin/$runtime_name" ]] || ln -s "$runtime_tool" "$runtime_bin/$runtime_name"
done
runtime_failures=()
for runtime_variant in missing old broken supported; do
    rm -f "$runtime_bin/python3"
    if [[ "$runtime_variant" != missing ]]; then
        # The old-runtime proxy executes the real -c version probe with a 3.8
        # version tuple; it cannot pass merely because a command exists.
        "$runtime_host_python" - "$runtime_bin/python3" "$runtime_host_python" "$runtime_variant" <<'PYPROXY'
from pathlib import Path
import sys
path, host, variant = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
# Suppress only fixture bootstrap bytecode; the supported child below still
# receives the exact installer arguments, so its cache behavior remains observable.
source = "#!" + host + " -B\nimport os, sys\n"
if variant == "broken":
    source += "sys.exit(86)\n"
elif variant == "supported":
    source += "os.execv(" + repr(host) + ", [" + repr(host) + "] + sys.argv[1:])\n"
else:
    source += """from collections import namedtuple
sys.version_info = namedtuple('VersionInfo', 'major minor micro releaselevel serial')(3, 8, 20, 'final', 0)
arguments = sys.argv[1:]
if arguments[:1] == ['-B']:
    if arguments[1:2] != ['-c']:
        sys.exit(87)
    arguments = arguments[1:]
if arguments in (['--version'], ['-V']):
    print('Python 3.8.20')
elif len(arguments) >= 2 and arguments[0] == '-c':
    code = arguments[1]
    sys.argv = ['-c'] + arguments[2:]
    exec(compile(code, '<isolated-python38-probe>', 'exec'))
else:
    sys.exit(87)
"""
path.write_text(source)
path.chmod(0o755)
PYPROXY
    fi
    for runtime_selection in workflow dependent docs full; do
        # One positive full-closure run is enough; the negative closure controls
        # cover full installs and transitive selection separately.
        if [[ "$runtime_variant" != missing && ( "$runtime_selection" == full || "$runtime_selection" == dependent ) ]]; then continue; fi
        for runtime_mode in normal dry-run; do
            runtime_home="$runtime_root/$runtime_variant-$runtime_selection-$runtime_mode"
            mkdir -p "$runtime_home/.gemini"
            printf 'personal sentinel\n' >"$runtime_home/.gemini/GEMINI.md"
            runtime_before="$(ownership_install_fingerprint "$runtime_home")"
            runtime_args=(--agent gemini --no-hooks)
            case "$runtime_selection" in
                workflow) runtime_args+=(--skill assistant-workflow) ;;
                dependent) runtime_args+=(--skill assistant-runtime-dependent) ;;
                docs) runtime_args+=(--skill assistant-docs) ;;
            esac
            [[ "$runtime_mode" != dry-run ]] || runtime_args+=(--dry-run)
            if HOME="$runtime_home" PATH="$runtime_bin" /bin/bash "$runtime_source/install.sh" "${runtime_args[@]}" >"$runtime_root/last.out" 2>"$runtime_root/last.err"; then runtime_status=0; else runtime_status=$?; fi
            runtime_after="$(ownership_install_fingerprint "$runtime_home")"
            runtime_expected=blocked
            [[ "$runtime_selection" != docs && "$runtime_variant" != supported ]] || runtime_expected=accepted
            runtime_label="$runtime_variant/$runtime_selection/$runtime_mode"
            if [[ "$runtime_expected" == blocked || "$runtime_mode" == dry-run ]]; then
                ownership_install_fingerprint_difference "$runtime_label" "$runtime_before" "$runtime_after"
            fi
            if [[ "$runtime_expected" == blocked ]]; then
                if [[ "$runtime_status" == 0 ]]; then runtime_failures+=("$runtime_label accepted unusable Python"); fi
                if [[ "$runtime_before" != "$runtime_after" ]]; then runtime_failures+=("$runtime_label changed home before interpreter refusal"); fi
                if ! grep -Eqi 'Python.*3\.9|3\.9.*Python' "$runtime_root/last.err" "$runtime_root/last.out"; then runtime_failures+=("$runtime_label lacks Python 3.9+ recovery guidance"); fi
            else
                if [[ "$runtime_status" != 0 ]]; then runtime_failures+=("$runtime_label rejected a supported closure"); fi
                if [[ "$runtime_mode" == dry-run && "$runtime_before" != "$runtime_after" ]]; then runtime_failures+=("$runtime_label dry-run wrote files"); fi
                if [[ "$runtime_mode" == normal ]]; then
                    runtime_installed=assistant-workflow
                    [[ "$runtime_selection" != docs ]] || runtime_installed=assistant-docs
                    if [[ ! -f "$runtime_home/.gemini/skills/$runtime_installed/SKILL.md" ]]; then runtime_failures+=("$runtime_label did not install selected skill"); fi
                fi
                if [[ "$runtime_variant" == supported && "$runtime_selection" == workflow ]] && ! grep -Fq 'python3' "$runtime_root/last.out"; then runtime_failures+=("$runtime_label omitted supported invocation"); fi
            fi
        done
    done
done
if [[ "${#runtime_failures[@]}" == 0 ]]; then pass; else fail "Workflow interpreter preflight: ${runtime_failures[*]}"; fi

ownership_install_compatibility_matrix() {
    local matrix_root="$1" agent variant mode case_home agent_home skills workflow before after workflow_before status log
    local -a args
    for agent in codex claude gemini; do
        for variant in old13 old14 old no-stages stage-mismatch early-completion missing-index duplicate-index duplicate-handoffs malformed wrong-identity unsafe-workflow unsafe-skill unsafe-index absent current old15 unknown-version mixed-version bom-crlf recovery full; do
            for mode in normal dry-run; do
                [[ "$mode" == dry-run && ( "$variant" == recovery || "$variant" == full ) ]] && continue
                case_home="$matrix_root/$agent-$variant-$mode"
                mkdir -p "$case_home"
                if [[ "$agent" == codex ]]; then
                    agent_home="$case_home/Custom Codex Home"
                else
                    agent_home="$case_home/.$agent"
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
                # Non-Codex providers receive a hostile ambient CODEX_HOME.
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
        if [[ "$before" != "$after" ]]; then
            ownership_install_fingerprint_difference "$row missing-source refusal" "$before" "$after"
            ownership_matrix_failure="$row missing-source refusal mutated managed tree"; return 1
        fi
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

test_start "selective installs require a current retained workflow before writes for every provider"
ownership_matrix_root="$(mktemp -d "${TMPDIR:-/tmp}/ownership-upgrade.XXXXXX")"
p0p4_register_cleanup "$ownership_matrix_root"
ownership_matrix_failure=''
if ownership_install_compatibility_matrix "$ownership_matrix_root"; then pass; else fail "$ownership_matrix_failure"; fi

test_start "selective installs reject mixed protocol consumers before normal and dry-run writes"
protocol_root="$(mktemp -d)"
p0p4_register_cleanup "$protocol_root"
protocol_failures=()
for protocol_agent in codex claude gemini; do
    for protocol_case in review-with-old-workflow workflow-with-old-debugging review-with-old-debugging; do
        for protocol_mode in normal dry-run; do
            protocol_home="$protocol_root/$protocol_agent-$protocol_case-$protocol_mode"
            protocol_target="$protocol_home/.$protocol_agent/skills"
            mkdir -p "$protocol_target"
            protocol_args=(--agent "$protocol_agent")
            if [[ "$protocol_case" == review-with-old-workflow ]]; then
                write_ownership_workflow_fixture "$protocol_target/assistant-workflow" old15
                protocol_args+=(--skill assistant-review)
            else
                mkdir -p "$protocol_target/assistant-debugging/contracts"
                printf '%s\n' '---' 'name: assistant-debugging' 'description: Original v2 debugging consumer.' '---' >"$protocol_target/assistant-debugging/SKILL.md"
                printf '%s\n' 'schema_version: "2.0"' 'contract: index' 'skill: assistant-debugging' >"$protocol_target/assistant-debugging/contracts/index.yaml"
                # review-with-old-debugging exercises the debugging/review protocol pair alone.
                if [[ "$protocol_case" == review-with-old-debugging ]]; then protocol_args+=(--skill assistant-review); else protocol_args+=(--skill assistant-workflow); fi
            fi
            [[ "$protocol_mode" != dry-run ]] || protocol_args+=(--dry-run)
            protocol_before="$(ownership_install_fingerprint "$protocol_home")"
            if HOME="$protocol_home" CODEX_HOME="$protocol_home/.codex" bash "$FRAMEWORK_DIR/install.sh" "${protocol_args[@]}" >"$protocol_root/$protocol_agent-$protocol_case-$protocol_mode.log" 2>&1; then
                protocol_failures+=("$protocol_agent/$protocol_case/$protocol_mode accepted incompatible retained consumer")
            elif ! grep -Fq 'INCOMPATIBLE_SKILL_PROTOCOL_UPGRADE' "$protocol_root/$protocol_agent-$protocol_case-$protocol_mode.log"; then
                protocol_failures+=("$protocol_agent/$protocol_case/$protocol_mode rejected for wrong reason")
            fi
            [[ "$protocol_before" == "$(ownership_install_fingerprint "$protocol_home")" ]] || protocol_failures+=("$protocol_agent/$protocol_case/$protocol_mode wrote before rejection")
        done
    done
done
if [[ "${#protocol_failures[@]}" == 0 ]]; then pass; else fail "protocol compatibility preflight: ${protocol_failures[*]}"; fi

test_start "protocol preflight reports missing metadata and accepts CRLF metadata like Windows"
protocol_metadata_failures=()
for protocol_agent in codex claude gemini; do
    for protocol_case in missing-index crlf-current; do
        protocol_home="$protocol_root/metadata-$protocol_agent-$protocol_case"
        protocol_target="$protocol_home/.$protocol_agent/skills"
        mkdir -p "$protocol_target/assistant-debugging/contracts"
        printf '%s\n' '---' 'name: assistant-debugging' 'description: Retained debugging consumer.' '---' >"$protocol_target/assistant-debugging/SKILL.md"
        [[ "$protocol_case" == missing-index ]] \
            || printf '%s\r\n' 'schema_version: "3.0"' 'contract: index' 'skill: assistant-debugging' >"$protocol_target/assistant-debugging/contracts/index.yaml"
        protocol_log="$protocol_root/metadata-$protocol_agent-$protocol_case.log"
        protocol_before="$(ownership_install_fingerprint "$protocol_home")"
        protocol_status=0
        HOME="$protocol_home" CODEX_HOME="$protocol_home/.codex" bash "$FRAMEWORK_DIR/install.sh" --agent "$protocol_agent" --skill assistant-workflow --dry-run >"$protocol_log" 2>&1 || protocol_status=$?
        if [[ "$protocol_case" == missing-index ]]; then
            if [[ "$protocol_status" == 0 ]] || ! grep -Fq 'INCOMPATIBLE_SKILL_PROTOCOL_UPGRADE: missing or unreadable contracts/index.yaml' "$protocol_log" || grep -Fq 'No such file' "$protocol_log"; then
                protocol_metadata_failures+=("$protocol_agent/$protocol_case did not report missing metadata")
            fi
        elif grep -Fq 'INCOMPATIBLE_SKILL_PROTOCOL_UPGRADE' "$protocol_log"; then
            protocol_metadata_failures+=("$protocol_agent/$protocol_case rejected CRLF current metadata")
        fi
        [[ "$protocol_before" == "$(ownership_install_fingerprint "$protocol_home")" ]] || protocol_metadata_failures+=("$protocol_agent/$protocol_case wrote during dry-run")
    done
done
if [[ "${#protocol_metadata_failures[@]}" == 0 ]]; then pass; else fail "protocol metadata preflight: ${protocol_metadata_failures[*]}"; fi

overlap_tree_fingerprint() {
    find "$1" -type d -print -o -type l -exec ls -ld {} \; -o -type f -exec shasum -a 256 {} + | LC_ALL=C sort
}

test_start "installer refuses checkout and agent-home overlap before any write (audit F5)"
overlap_root="$(mktemp -d)"
overlap_logs="$(mktemp -d)"
p0p4_register_cleanup "$overlap_root" "$overlap_logs"
# The checkout copy sits where a Claude home would be, so one copy serves every case.
overlap_fw="$overlap_root/h/.claude"
mkdir -p "$overlap_fw"
rsync -a --exclude='.git' --exclude='node_modules' --exclude='/docs/plans/' "$FRAMEWORK_DIR/" "$overlap_fw/"
ln -s "$overlap_fw" "$overlap_root/fw-link"
mkdir -p "$overlap_root/outside"
ln -s "$overlap_fw/skills" "$overlap_root/outside/link"
overlap_failures=()
overlap_cases=(
    "codex|$overlap_root/codex-home|$overlap_fw|CODEX_HOME equals the checkout"
    "codex|$overlap_root/codex-home|$overlap_fw/|CODEX_HOME equals the checkout with a trailing slash"
    "codex|$overlap_root/codex-home|$overlap_root/h|CODEX_HOME is the checkout's parent"
    "codex|$overlap_root/codex-home|$overlap_root|CODEX_HOME is a further ancestor"
    "codex|$overlap_root/codex-home|$overlap_fw/nested/codex|CODEX_HOME is inside the checkout"
    "codex|$overlap_root/codex-home|$overlap_fw/skills/..|CODEX_HOME reaches the checkout through .."
    "codex|$overlap_root/codex-home|$overlap_root/fw-link|CODEX_HOME is a symlink to the checkout"
    "codex|$overlap_root/codex-home|$overlap_root/fw-link/missing/home|CODEX_HOME is inside the checkout through a symlink"
    "codex|$overlap_root/codex-home|$overlap_root/outside/new/../link/..|CODEX_HOME reaches the checkout through a symlink after a cancelled missing component"
    "claude|$overlap_root/h||Claude home equals the checkout"
    "gemini|$overlap_fw/inner||Gemini home is inside the checkout"
)
if [[ -d "$overlap_root/H" && "$overlap_root/H" -ef "$overlap_root/h" ]]; then
    overlap_cases+=("codex|$overlap_root/codex-home|$overlap_root/H/.CLAUDE|CODEX_HOME differs from the checkout only by letter case")
fi
for overlap_case in "${overlap_cases[@]}"; do
    IFS='|' read -r overlap_agent overlap_home overlap_codex_home overlap_label <<<"$overlap_case"
    for overlap_mode in real dry-run; do
        overlap_args=(--agent "$overlap_agent")
        [[ "$overlap_mode" == real ]] || overlap_args+=(--dry-run)
        overlap_before="$(overlap_tree_fingerprint "$overlap_root")"
        overlap_status=0
        if [[ -n "$overlap_codex_home" ]]; then
            HOME="$overlap_home" CODEX_HOME="$overlap_codex_home" bash "$overlap_fw/install.sh" "${overlap_args[@]}" >"$overlap_logs/out.log" 2>&1 || overlap_status=$?
        else
            HOME="$overlap_home" bash "$overlap_fw/install.sh" "${overlap_args[@]}" >"$overlap_logs/out.log" 2>&1 || overlap_status=$?
        fi
        overlap_after="$(overlap_tree_fingerprint "$overlap_root")"
        if [[ "$overlap_status" == 0 ]]; then
            overlap_failures+=("$overlap_label ($overlap_mode) was accepted")
        elif ! grep -Fq 'Refusing overlapping source and target for agent home' "$overlap_logs/out.log"; then
            overlap_failures+=("$overlap_label ($overlap_mode) failed without the overlap refusal: $(head -c 300 "$overlap_logs/out.log")")
        fi
        if [[ "$overlap_before" != "$overlap_after" ]]; then
            ownership_install_fingerprint_difference "$overlap_label ($overlap_mode)" "$overlap_before" "$overlap_after"
            overlap_failures+=("$overlap_label ($overlap_mode) changed the checkout or a home")
        fi
        rm -f "$overlap_logs/out.log"
    done
done
# Control: a sibling whose name only starts with the checkout's name does not overlap.
overlap_control_status=0
mkdir -p "$overlap_root/control-home"
HOME="$overlap_root/control-home" CODEX_HOME="$overlap_root/h/.claude2" bash "$overlap_fw/install.sh" --agent codex --skill assistant-thinking >"$overlap_logs/control.log" 2>&1 || overlap_control_status=$?
if [[ "$overlap_control_status" != 0 || ! -f "$overlap_root/h/.claude2/skills/assistant-thinking/SKILL.md" ]]; then
    overlap_failures+=("prefix-sibling CODEX_HOME was refused or did not install: $(head -c 300 "$overlap_logs/control.log")")
fi
if [[ "${#overlap_failures[@]}" == 0 ]]; then pass; else fail "overlap refusal: ${overlap_failures[*]}"; fi

test_start "installer calls the overlap check before its first write (audit F5)"
overlap_check_line="$(grep -n '^assert_no_framework_target_overlap ' "$FRAMEWORK_DIR/install.sh" | head -n 1 | cut -d: -f1 || true)"
overlap_first_write_line="$(grep -nE '^[[:space:]]*(mkdir -p|rsync -a|ln -s|cp |rm -|rmdir|mv )' "$FRAMEWORK_DIR/install.sh" | awk -F: -v s="$(grep -n '^# ── Validate' "$FRAMEWORK_DIR/install.sh" | cut -d: -f1)" '$1 > s { print $1; exit }' || true)"
if [[ -n "$overlap_check_line" && -n "$overlap_first_write_line" && "$overlap_check_line" -lt "$overlap_first_write_line" ]] \
    && awk -v c="$overlap_check_line" 'NR < c && /^(preflight_[a-z_]+|resolve_bundled_skill_closure)( |$)/ { found = 1 } END { exit found }' "$FRAMEWORK_DIR/install.sh"; then
    pass
else
    fail "assert_no_framework_target_overlap must run in the main flow before any preflight or write (check line: ${overlap_check_line:-none}, first write: ${overlap_first_write_line:-none})"
fi

owned_sync_user_fingerprint() {
    local entry
    for entry in "$@"; do
        if [[ -L "$entry" ]]; then
            printf 'link %s %s\n' "$entry" "$(readlink "$entry")"
        elif [[ -d "$entry" ]]; then
            printf 'dir %s %s\n' "$(ls -ld "$entry" | awk '{print $1}')" "$entry"
        elif [[ -f "$entry" ]]; then
            printf 'file %s %s\n' "$(ls -ld "$entry" | awk '{print $1}')" "$(shasum -a 256 "$entry")"
        else
            printf 'missing %s\n' "$entry"
        fi
    done
}

test_start "tools and eval-docs installs write only framework-owned entries (audit F4)"
owned_sync_home="$(mktemp -d)"
owned_sync_logs="$(mktemp -d)"
p0p4_register_cleanup "$owned_sync_home" "$owned_sync_logs"
owned_sync_tools="$owned_sync_home/.codex/tools"
owned_sync_eval_docs="$owned_sync_home/.codex/docs/evals"
mkdir -p "$owned_sync_tools/company-dir" "$owned_sync_tools/evals" "$owned_sync_eval_docs/company-fixtures" "$owned_sync_eval_docs/fixtures"
printf 'company custom tool\n' >"$owned_sync_tools/company-custom-tool.txt"
chmod 0640 "$owned_sync_tools/company-custom-tool.txt"
printf '#!/bin/sh\necho company\n' >"$owned_sync_tools/company-dir/run.sh"
chmod 0644 "$owned_sync_tools/company-dir/run.sh"
printf 'custom eval notes\n' >"$owned_sync_eval_docs/custom.md"
printf '{"company": true}\n' >"$owned_sync_eval_docs/company-fixtures/case.json"
printf 'stale owned tool file\n' >"$owned_sync_tools/evals/stale-owned.txt"
printf 'stale owned eval fixture\n' >"$owned_sync_eval_docs/fixtures/stale-owned.txt"
printf 'retired\n' >"$owned_sync_tools/cleanup-memory-graph.sh"
printf 'retired\n' >"$owned_sync_tools/cleanup-memory-graph.ps1"
owned_sync_user_entries=(
    "$owned_sync_tools/company-custom-tool.txt"
    "$owned_sync_tools/company-dir"
    "$owned_sync_tools/company-dir/run.sh"
    "$owned_sync_eval_docs/custom.md"
    "$owned_sync_eval_docs/company-fixtures"
    "$owned_sync_eval_docs/company-fixtures/case.json"
)
owned_sync_before="$(owned_sync_user_fingerprint "${owned_sync_user_entries[@]}")"
owned_sync_failures=()
if HOME="$owned_sync_home" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-thinking --dry-run >"$owned_sync_logs/dry.out" 2>&1; then
    for owned_sync_retired in cleanup-memory-graph.sh cleanup-memory-graph.ps1; do
        grep -Fq "Remove retired managed tool: $owned_sync_tools/$owned_sync_retired" "$owned_sync_logs/dry.out" \
            || owned_sync_failures+=("dry-run did not report retiring $owned_sync_retired")
        [[ -f "$owned_sync_tools/$owned_sync_retired" ]] || owned_sync_failures+=("dry-run removed $owned_sync_retired")
    done
    [[ -f "$owned_sync_tools/evals/stale-owned.txt" ]] || owned_sync_failures+=("dry-run removed a stale owned tool file")
else
    owned_sync_failures+=("dry-run failed: $(head -c 300 "$owned_sync_logs/dry.out")")
fi
for owned_sync_pass in first second; do
    if ! HOME="$owned_sync_home" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-thinking >"$owned_sync_logs/$owned_sync_pass.out" 2>&1; then
        owned_sync_failures+=("$owned_sync_pass install failed: $(head -c 300 "$owned_sync_logs/$owned_sync_pass.out")")
        continue
    fi
    owned_sync_after="$(owned_sync_user_fingerprint "${owned_sync_user_entries[@]}")"
    if [[ "$owned_sync_before" != "$owned_sync_after" ]]; then
        ownership_install_fingerprint_difference "owned sync user entries ($owned_sync_pass)" "$owned_sync_before" "$owned_sync_after"
        owned_sync_failures+=("$owned_sync_pass install changed user tool or eval-doc entries")
    fi
    [[ ! -e "$owned_sync_tools/evals/stale-owned.txt" ]] || owned_sync_failures+=("$owned_sync_pass install kept a stale file inside owned tools/evals")
    [[ ! -e "$owned_sync_eval_docs/fixtures/stale-owned.txt" ]] || owned_sync_failures+=("$owned_sync_pass install kept a stale file inside owned docs/evals/fixtures")
    [[ ! -e "$owned_sync_tools/cleanup-memory-graph.sh" && ! -e "$owned_sync_tools/cleanup-memory-graph.ps1" ]] \
        || owned_sync_failures+=("$owned_sync_pass install kept a retired cleanup-memory-graph tool")
    [[ -x "$owned_sync_tools/evals/run-skill-evals.sh" ]] || owned_sync_failures+=("$owned_sync_pass install did not install an executable owned eval runner")
    [[ -f "$owned_sync_tools/smoke-test-codex-agents.sh" ]] || owned_sync_failures+=("$owned_sync_pass install did not install an owned top-level tool file")
    cmp -s "$FRAMEWORK_DIR/docs/evals/README.md" "$owned_sync_eval_docs/README.md" || owned_sync_failures+=("$owned_sync_pass install did not install owned eval docs")
    [[ -e "$owned_sync_eval_docs/fixtures/$(ls "$FRAMEWORK_DIR/docs/evals/fixtures" | head -n 1)" ]] || owned_sync_failures+=("$owned_sync_pass install did not install owned eval fixtures")
    [[ ! -e "$owned_sync_tools/evals/package.json" && ! -e "$owned_sync_tools/context-budget-report.sh" && ! -e "$owned_sync_tools/plugins" ]] \
        || owned_sync_failures+=("$owned_sync_pass install copied a source-only or excluded tool")
done
if [[ "${#owned_sync_failures[@]}" == 0 ]]; then pass; else fail "owned sync: ${owned_sync_failures[*]}"; fi

test_start "tools and eval-docs installs refuse linked or wrong-type roots and owned entries before any write (audit F4)"
owned_link_root="$(mktemp -d)"
p0p4_register_cleanup "$owned_link_root"
owned_link_external="$owned_link_root/external"
mkdir -p "$owned_link_external/dir"
printf 'external sentinel\n' >"$owned_link_external/dir/sentinel.txt"
printf 'external file sentinel\n' >"$owned_link_external/file.txt"
owned_link_failures=()
for owned_link_kind in tools-root tools-dir-entry tools-file-entry tools-retired-leaf tools-retired-dir tools-wrong-type tools-file-is-dir docs-parent eval-docs-root eval-docs-dir-entry eval-docs-file-entry; do
    for owned_link_mode in real dry-run; do
        owned_link_home="$owned_link_root/$owned_link_kind-$owned_link_mode"
        owned_link_codex="$owned_link_home/.codex"
        mkdir -p "$owned_link_codex"
        case "$owned_link_kind" in
            tools-root) ln -s "$owned_link_external/dir" "$owned_link_codex/tools" ;;
            tools-dir-entry) mkdir -p "$owned_link_codex/tools" && ln -s "$owned_link_external/dir" "$owned_link_codex/tools/evals" ;;
            tools-file-entry) mkdir -p "$owned_link_codex/tools" && ln -s "$owned_link_external/file.txt" "$owned_link_codex/tools/smoke-test-codex-agents.sh" ;;
            tools-retired-leaf) mkdir -p "$owned_link_codex/tools" && ln -s "$owned_link_external/file.txt" "$owned_link_codex/tools/cleanup-memory-graph.sh" ;;
            tools-retired-dir) mkdir -p "$owned_link_codex/tools/cleanup-memory-graph.ps1" ;;
            tools-wrong-type) mkdir -p "$owned_link_codex/tools" && printf 'not a directory\n' >"$owned_link_codex/tools/evals" ;;
            tools-file-is-dir) mkdir -p "$owned_link_codex/tools/smoke-test-codex-agents.sh" ;;
            docs-parent) ln -s "$owned_link_external/dir" "$owned_link_codex/docs" ;;
            eval-docs-root) mkdir -p "$owned_link_codex/docs" && ln -s "$owned_link_external/dir" "$owned_link_codex/docs/evals" ;;
            eval-docs-dir-entry) mkdir -p "$owned_link_codex/docs/evals" && ln -s "$owned_link_external/dir" "$owned_link_codex/docs/evals/fixtures" ;;
            eval-docs-file-entry) mkdir -p "$owned_link_codex/docs/evals" && ln -s "$owned_link_external/file.txt" "$owned_link_codex/docs/evals/README.md" ;;
        esac
        owned_link_before="$(overlap_tree_fingerprint "$owned_link_root")"
        owned_link_args=(--agent codex --skill assistant-thinking)
        [[ "$owned_link_mode" == real ]] || owned_link_args+=(--dry-run)
        owned_link_status=0
        HOME="$owned_link_home" bash "$FRAMEWORK_DIR/install.sh" "${owned_link_args[@]}" >"$owned_link_root/out.log" 2>&1 || owned_link_status=$?
        owned_link_after="$(overlap_tree_fingerprint "$owned_link_root" | grep -v "$owned_link_root/out.log" || true)"
        owned_link_before="$(printf '%s\n' "$owned_link_before" | grep -v "$owned_link_root/out.log" || true)"
        if [[ "$owned_link_status" == 0 ]]; then
            owned_link_failures+=("$owned_link_kind ($owned_link_mode) was accepted")
        elif ! grep -q 'Refusing' "$owned_link_root/out.log"; then
            owned_link_failures+=("$owned_link_kind ($owned_link_mode) failed without a refusal: $(head -c 300 "$owned_link_root/out.log")")
        fi
        if [[ "$owned_link_before" != "$owned_link_after" ]]; then
            ownership_install_fingerprint_difference "$owned_link_kind ($owned_link_mode)" "$owned_link_before" "$owned_link_after"
            owned_link_failures+=("$owned_link_kind ($owned_link_mode) wrote before refusing")
        fi
        rm -f "$owned_link_root/out.log"
    done
done
if [[ "${#owned_link_failures[@]}" == 0 ]]; then pass; else fail "owned sync safety: ${owned_link_failures[*]}"; fi

test_start "tools sync skips top-level build output names like the former whole-root rsync (audit F4)"
owned_build_root="$(mktemp -d)"
p0p4_register_cleanup "$owned_build_root"
owned_build_fw="$owned_build_root/framework"
rsync -a --exclude='.git' --exclude='node_modules' --exclude='/docs/plans/' "$FRAMEWORK_DIR/" "$owned_build_fw/"
mkdir -p "$owned_build_fw/tools/__pycache__" "$owned_build_fw/tools/bin" "$owned_build_fw/tools/obj" "$owned_build_fw/tools/.publish"
printf 'cache\n' >"$owned_build_fw/tools/__pycache__/x.pyc"
printf 'bytecode\n' >"$owned_build_fw/tools/stray.pyc"
printf 'build\n' >"$owned_build_fw/tools/bin/tool.dll"
mkdir -p "$owned_build_root/home"
owned_build_status=0
HOME="$owned_build_root/home" bash "$owned_build_fw/install.sh" --agent codex --skill assistant-thinking >"$owned_build_root/out.log" 2>&1 || owned_build_status=$?
owned_build_tools="$owned_build_root/home/.codex/tools"
if [[ "$owned_build_status" == 0 && -d "$owned_build_tools/evals" ]] \
    && [[ ! -e "$owned_build_tools/__pycache__" && ! -e "$owned_build_tools/stray.pyc" && ! -e "$owned_build_tools/bin" && ! -e "$owned_build_tools/obj" && ! -e "$owned_build_tools/.publish" ]]; then
    pass
else
    fail "tools sync must skip top-level build output and still install owned tools (status $owned_build_status): $(head -c 300 "$owned_build_root/out.log")"
fi

test_start "tools and eval-docs syncs never mirror a whole shared root with rsync --delete (audit F4)"
if grep -nE '"\$[A-Z_]+/" "\$(TOOLS_TARGET|EVAL_DOCS_TARGET)/"|rsync .*"\$(TOOLS_TARGET|EVAL_DOCS_TARGET)/?"' "$FRAMEWORK_DIR/install.sh" | grep -q .; then
    fail "install.sh still passes a whole shared tools or eval-docs root as an rsync destination: $(grep -nE '"\$[A-Z_]+/" "\$(TOOLS_TARGET|EVAL_DOCS_TARGET)/"|rsync .*"\$(TOOLS_TARGET|EVAL_DOCS_TARGET)/?"' "$FRAMEWORK_DIR/install.sh" | tr '\n' ' ')"
else
    pass
fi

test_start "agent and rule writes refuse linked or wrong-type paths before any write (audit F2)"
link_write_root="$(mktemp -d)"
link_write_logs="$(mktemp -d)"
p0p4_register_cleanup "$link_write_root" "$link_write_logs"
link_write_external="$link_write_root/external"
mkdir -p "$link_write_external/dir"
printf 'external sentinel\n' >"$link_write_external/dir/sentinel.txt"
printf 'external file sentinel\n' >"$link_write_external/file.txt"
link_write_claude_agent="$(basename "$(ls "$FRAMEWORK_DIR/agents/claude/"*.md | head -n 1)")"
link_write_codex_agent="$(basename "$(ls "$FRAMEWORK_DIR/agents/codex/"*.toml | head -n 1)")"
link_write_rule="$(basename "$(ls "$FRAMEWORK_DIR/codex-rules/"*.rules | head -n 1)")"
link_write_failures=()
for link_write_case in \
    "claude|agents-dir" "claude|agent-leaf" "claude|agent-leaf-dir" \
    "codex|agents-dir" "codex|agent-leaf" "codex|rules-dir" "codex|rules-leaf"; do
    IFS='|' read -r link_write_agent link_write_kind <<<"$link_write_case"
    for link_write_mode in real dry-run; do
        link_write_home="$link_write_root/$link_write_agent-$link_write_kind-$link_write_mode"
        link_write_agent_home="$link_write_home/.$link_write_agent"
        mkdir -p "$link_write_agent_home"
        case "$link_write_kind" in
            agents-dir) ln -s "$link_write_external/dir" "$link_write_agent_home/agents" ;;
            agent-leaf)
                mkdir -p "$link_write_agent_home/agents"
                if [[ "$link_write_agent" == claude ]]; then link_write_leaf="$link_write_claude_agent"; else link_write_leaf="$link_write_codex_agent"; fi
                ln -s "$link_write_external/file.txt" "$link_write_agent_home/agents/$link_write_leaf"
                ;;
            agent-leaf-dir) mkdir -p "$link_write_agent_home/agents/$link_write_claude_agent" ;;
            rules-dir) ln -s "$link_write_external/dir" "$link_write_agent_home/rules" ;;
            rules-leaf) mkdir -p "$link_write_agent_home/rules" && ln -s "$link_write_external/file.txt" "$link_write_agent_home/rules/$link_write_rule" ;;
        esac
        link_write_args=(--agent "$link_write_agent" --skill assistant-thinking)
        [[ "$link_write_mode" == real ]] || link_write_args+=(--dry-run)
        link_write_before="$(overlap_tree_fingerprint "$link_write_root")"
        link_write_status=0
        HOME="$link_write_home" bash "$FRAMEWORK_DIR/install.sh" "${link_write_args[@]}" >"$link_write_logs/out.log" 2>&1 || link_write_status=$?
        link_write_after="$(overlap_tree_fingerprint "$link_write_root")"
        if [[ "$link_write_status" == 0 ]]; then
            link_write_failures+=("$link_write_case ($link_write_mode) was accepted")
        elif ! grep -q 'Refusing' "$link_write_logs/out.log"; then
            link_write_failures+=("$link_write_case ($link_write_mode) failed without a refusal: $(head -c 300 "$link_write_logs/out.log")")
        fi
        if [[ "$link_write_before" != "$link_write_after" ]]; then
            ownership_install_fingerprint_difference "$link_write_case ($link_write_mode)" "$link_write_before" "$link_write_after"
            link_write_failures+=("$link_write_case ($link_write_mode) wrote before refusing")
        fi
        rm -f "$link_write_logs/out.log"
    done
done
if [[ "${#link_write_failures[@]}" == 0 ]]; then pass; else fail "agent and rule link safety: ${link_write_failures[*]}"; fi

test_start "agent and rule reinstalls replace files without writing through hard links and keep cp file modes (audit F2)"
replace_root="$(mktemp -d)"
p0p4_register_cleanup "$replace_root"
replace_failures=()
replace_claude_agent="$(basename "$(ls "$FRAMEWORK_DIR/agents/claude/"*.md | head -n 1)")"
replace_claude_other="$(basename "$(ls "$FRAMEWORK_DIR/agents/claude/"*.md | sed -n 2p)")"
replace_rule="$(basename "$(ls "$FRAMEWORK_DIR/codex-rules/"*.rules | head -n 1)")"
replace_cp_probe="$replace_root/cp-probe"
cp "$FRAMEWORK_DIR/agents/claude/$replace_claude_agent" "$replace_cp_probe"
replace_expected_new_mode="$(p0p4_file_mode_octal "$replace_cp_probe")"
mkdir -p "$replace_root/claude/.claude/agents" "$replace_root/codex/.codex/rules"
printf 'external hard-link sentinel\n' >"$replace_root/external-agent.md"
ln "$replace_root/external-agent.md" "$replace_root/claude/.claude/agents/$replace_claude_agent"
printf 'old agent\n' >"$replace_root/claude/.claude/agents/$replace_claude_other"
chmod 0600 "$replace_root/claude/.claude/agents/$replace_claude_other"
printf 'external hard-link rule sentinel\n' >"$replace_root/external-rule.rules"
ln "$replace_root/external-rule.rules" "$replace_root/codex/.codex/rules/$replace_rule"
if ! HOME="$replace_root/claude" bash "$FRAMEWORK_DIR/install.sh" --agent claude --skill assistant-thinking >"$replace_root/claude.log" 2>&1; then
    replace_failures+=("claude install failed: $(head -c 300 "$replace_root/claude.log")")
else
    [[ "$(cat "$replace_root/external-agent.md")" == "external hard-link sentinel" ]] || replace_failures+=("claude agent write went through a hard link")
    cmp -s "$FRAMEWORK_DIR/agents/claude/$replace_claude_agent" "$replace_root/claude/.claude/agents/$replace_claude_agent" || replace_failures+=("claude agent was not installed over the hard link")
    cmp -s "$FRAMEWORK_DIR/agents/claude/$replace_claude_other" "$replace_root/claude/.claude/agents/$replace_claude_other" || replace_failures+=("claude agent was not refreshed")
    [[ "$(p0p4_file_mode_octal "$replace_root/claude/.claude/agents/$replace_claude_other")" == 600 ]] || replace_failures+=("claude agent refresh did not keep the existing file mode as cp does")
    for replace_agent_file in "$FRAMEWORK_DIR/agents/claude/"*.md; do
        replace_name="$(basename "$replace_agent_file")"
        [[ "$replace_name" == "$replace_claude_other" ]] && continue
        [[ "$(p0p4_file_mode_octal "$replace_root/claude/.claude/agents/$replace_name")" == "$replace_expected_new_mode" ]] \
            || { replace_failures+=("new claude agent $replace_name mode differs from cp ($replace_expected_new_mode)"); break; }
    done
    ls -a "$replace_root/claude/.claude/agents" | grep -q '^\.assistant-install' && replace_failures+=("claude agents dir kept a temporary install file")
fi
if ! HOME="$replace_root/codex" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-thinking >"$replace_root/codex.log" 2>&1; then
    replace_failures+=("codex install failed: $(head -c 300 "$replace_root/codex.log")")
else
    [[ "$(cat "$replace_root/external-rule.rules")" == "external hard-link rule sentinel" ]] || replace_failures+=("codex rule write went through a hard link")
    cmp -s "$FRAMEWORK_DIR/codex-rules/$replace_rule" "$replace_root/codex/.codex/rules/$replace_rule" || replace_failures+=("codex rule was not installed over the hard link")
    for replace_agent_file in "$FRAMEWORK_DIR/agents/codex/"*.toml; do
        cmp -s "$replace_agent_file" "$replace_root/codex/.codex/agents/$(basename "$replace_agent_file")" || { replace_failures+=("codex agent $(basename "$replace_agent_file") not installed"); break; }
    done
fi
if [[ "${#replace_failures[@]}" == 0 ]]; then pass; else fail "agent and rule replacement: ${replace_failures[*]}"; fi

test_start "agent, rule and hook shim writes go through the link-safe replace helper (audit F2)"
link_write_static="$(grep -nE 'cp "\$[a-z]+" "\$(AGENTS_TARGET|RULES_TARGET)/"|> "\$hooks_target/' "$FRAMEWORK_DIR/install.sh" || true)"
link_write_preflight_line="$(grep -n '^preflight_managed_file_writes$' "$FRAMEWORK_DIR/install.sh" | head -n 1 | cut -d: -f1 || true)"
link_write_first_skill_write="$(grep -n '^# ── Install skills' "$FRAMEWORK_DIR/install.sh" | head -n 1 | cut -d: -f1 || true)"
if [[ -z "$link_write_static" && -n "$link_write_preflight_line" && -n "$link_write_first_skill_write" && "$link_write_preflight_line" -lt "$link_write_first_skill_write" ]]; then
    pass
else
    fail "direct agent/rule cp or hook shim redirect remains, or the managed-file preflight does not run before skill installation: ${link_write_static:-none} (preflight line ${link_write_preflight_line:-none}, skills line ${link_write_first_skill_write:-none})"
fi

# ── S11 retired-item installer mode ───────────────────────────────────────────
# Every case installs into a disposable HOME (and CODEX_HOME); cases that alter
# the framework tree use a temporary copy of the checkout, never the checkout.

retired_seed_skill() {
    # Write the last released assistant-<name> skill as an install would have.
    # An optional fourth argument names the source revision (default: the last release before fdff2dc).
    local name="$1" agent="$2" target="$3" rev="${4:-fdff2dc7cf5719e3c231e5c17f34c9207239c343^}"
    (cd "$FRAMEWORK_DIR" && python3 -B - "$name" "$agent" "$target" "$rev" <<'SEED'
import os, subprocess, sys
name, agent, target, rev = sys.argv[1:]
source = f"skills/assistant-{name}"
files = subprocess.run(["git", "ls-tree", "-r", "--name-only", rev, source], check=True, capture_output=True, text=True).stdout.split()
for path in files:
    data = subprocess.run(["git", "show", f"{rev}:{path}"], check=True, capture_output=True).stdout
    if os.path.splitext(path)[1] in (".md", ".yaml", ".yml", ".json", ".conf", ".toml"):
        data = data.replace(b"{agent_state_dir}", ("." + agent).encode())
    out = os.path.join(target, os.path.relpath(path, source))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "wb") as handle:
        handle.write(data)
SEED
    )
}

retired_checkout_copy() {
    # Copy the tracked and untracked-unignored tree without .git.
    local target="$1"
    mkdir -p "$target"
    (cd "$FRAMEWORK_DIR" && git ls-files -co --exclude-standard -z | rsync -a --from0 --files-from=- ./ "$target/")
}

retired_path_without_python() {
    local target="$1" directory file name
    mkdir -p "$target"
    for directory in /bin /usr/bin /usr/sbin /sbin /opt/homebrew/bin /usr/local/bin; do
        [[ -d "$directory" ]] || continue
        for file in "$directory"/*; do
            name="$(basename "$file")"
            case "$name" in python*) continue ;; esac
            [[ -e "$target/$name" ]] || ln -s "$file" "$target/$name" 2>/dev/null || true
        done
    done
}

retired_tree_listing() {
    # Portable listing (path, mode, size, mtime) without BSD or GNU stat flags.
    python3 -B - "$1" <<'LISTING'
import os, sys
root = sys.argv[1]
for directory, names, files in sorted(os.walk(root)):
    for name in sorted(names + files):
        path = os.path.join(directory, name)
        info = os.lstat(path)
        print(os.path.relpath(path, root), oct(info.st_mode), info.st_size, info.st_mtime_ns)
LISTING
}

test_start "install removes byte-identical retired skills and keeps modified, user, other-product and linked items"
retired_failures=()
retired_home="$(mktemp -d)"
p0p4_register_cleanup "$retired_home"
retired_skills="$retired_home/.claude/skills"
retired_seed_skill reflexion claude "$retired_skills/assistant-reflexion"
retired_seed_skill memory claude "$retired_skills/assistant-memory"
printf '\nlocal edit\n' >>"$retired_skills/assistant-memory/SKILL.md"
mkdir -p "$retired_home/.claude/tools/memory-graph"
printf 'graph\n' >"$retired_home/.claude/tools/memory-graph/data.json"
printf '<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->\nold\n<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->\n' >"$retired_home/.claude/CLAUDE.md"
if HOME="$retired_home" bash "$FRAMEWORK_DIR/install.sh" --agent claude --skill assistant-clarify --no-hooks </dev/null >"$retired_home/install.out" 2>"$retired_home/install.err"; then
    [[ ! -e "$retired_skills/assistant-reflexion" ]] || retired_failures+=("byte-identical assistant-reflexion was kept")
    [[ -f "$retired_skills/assistant-memory/SKILL.md" ]] || retired_failures+=("modified assistant-memory was removed")
    [[ -f "$retired_home/.claude/tools/memory-graph/data.json" ]] || retired_failures+=("memory-graph data was removed")
    grep -Fq 'ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START' "$retired_home/.claude/CLAUDE.md" || retired_failures+=("retired memory protocol block was removed by install")
    grep -Fq 'Retired skills and agents for claude' "$retired_home/install.out" || retired_failures+=("install printed no retired-item plan")
    grep -Eq 'Retired-item plan digest: [0-9a-f]{64}' "$retired_home/install.out" || retired_failures+=("install printed no plan digest")
    [[ -z "$(find "$retired_home" -name 'ownership-checkout.*' -print -quit)" ]] || retired_failures+=("checkout-only entry point was installed")
else
    retired_failures+=("install failed: $(tail -n 2 "$retired_home/install.err")")
fi
# Other product: a same-named skill that is not framework content is kept as unrelated.
retired_other_home="$(mktemp -d)"
p0p4_register_cleanup "$retired_other_home"
mkdir -p "$retired_other_home/.claude/skills/assistant-memory"
printf -- '---\nname: assistant-memory\ndescription: another product\n---\n' >"$retired_other_home/.claude/skills/assistant-memory/SKILL.md"
if HOME="$retired_other_home" bash "$FRAMEWORK_DIR/install.sh" --agent claude --skill assistant-clarify --no-hooks </dev/null >"$retired_other_home/install.out" 2>"$retired_other_home/install.err"; then
    [[ -f "$retired_other_home/.claude/skills/assistant-memory/SKILL.md" ]] || retired_failures+=("other-product assistant-memory was removed")
    grep -Fq 'skills/assistant-memory' "$retired_other_home/install.out" || retired_failures+=("other-product assistant-memory was not reported")
else
    retired_failures+=("other-product install failed: $(tail -n 2 "$retired_other_home/install.err")")
fi
# Linked item: a symlinked retired skill is always kept.
retired_link_home="$(mktemp -d)"
p0p4_register_cleanup "$retired_link_home"
mkdir -p "$retired_link_home/.claude/skills" "$retired_link_home/target"
retired_seed_skill reflexion claude "$retired_link_home/target/assistant-reflexion"
ln -s "$retired_link_home/target/assistant-reflexion" "$retired_link_home/.claude/skills/assistant-reflexion"
if HOME="$retired_link_home" bash "$FRAMEWORK_DIR/install.sh" --agent claude --skill assistant-clarify --no-hooks </dev/null >"$retired_link_home/install.out" 2>"$retired_link_home/install.err"; then
    [[ -L "$retired_link_home/.claude/skills/assistant-reflexion" && -f "$retired_link_home/target/assistant-reflexion/SKILL.md" ]] \
        || retired_failures+=("linked retired skill or its target was removed")
else
    retired_failures+=("linked install failed: $(tail -n 2 "$retired_link_home/install.err")")
fi
if [[ "${#retired_failures[@]}" == 0 ]]; then pass; else fail "${retired_failures[*]}"; fi

test_start "install removes byte-identical S10-retired skills, keeps modified or user-extended copies, and leaves purpose files alone"
# R-S11-25 with the skills S10 retired (Telos, Diagrams, Ideate), seeded from the S10 base revision, plus R-S10-11.
s10_retired_rev="68da3fd9c653d02ed58561fde66d057d0e5f16dc"
s10_retired_failures=()
s10_retired_home="$(mktemp -d)"
p0p4_register_cleanup "$s10_retired_home"
s10_retired_skills="$s10_retired_home/.claude/skills"
retired_seed_skill telos claude "$s10_retired_skills/assistant-telos" "$s10_retired_rev"
retired_seed_skill diagrams claude "$s10_retired_skills/assistant-diagrams" "$s10_retired_rev"
retired_seed_skill ideate claude "$s10_retired_skills/assistant-ideate" "$s10_retired_rev"
# One changed byte in Diagrams' SKILL.md and one user file in Ideate make both ambiguous.
python3 -B - "$s10_retired_skills/assistant-diagrams/SKILL.md" <<'FLIP'
import sys
path = sys.argv[1]
data = bytearray(open(path, "rb").read())
data[-2] = ord("X") if data[-2] != ord("X") else ord("Y")
open(path, "wb").write(bytes(data))
FLIP
printf 'my notes\n' >"$s10_retired_skills/assistant-ideate/notes.md"
mkdir -p "$s10_retired_home/purpose" "$s10_retired_home/project/docs"
printf '# Telos\nMission: user-authored.\n' >"$s10_retired_home/purpose/TELOS.md"
printf '# Project telos\nGoals: user-authored.\n' >"$s10_retired_home/project/docs/telos.md"
s10_purpose_before="$(cat "$s10_retired_home/purpose/TELOS.md" "$s10_retired_home/project/docs/telos.md" | shasum -a 256)"
s10_diagrams_before="$(shasum -a 256 <"$s10_retired_skills/assistant-diagrams/SKILL.md")"
if HOME="$s10_retired_home" bash "$FRAMEWORK_DIR/install.sh" --agent claude --skill assistant-clarify --no-hooks </dev/null >"$s10_retired_home/install.out" 2>"$s10_retired_home/install.err"; then
    [[ ! -e "$s10_retired_skills/assistant-telos" ]] || s10_retired_failures+=("byte-identical assistant-telos was kept")
    [[ -f "$s10_retired_skills/assistant-diagrams/SKILL.md" ]] || s10_retired_failures+=("modified assistant-diagrams was removed")
    [[ "$(shasum -a 256 <"$s10_retired_skills/assistant-diagrams/SKILL.md")" == "$s10_diagrams_before" ]] || s10_retired_failures+=("modified assistant-diagrams was changed")
    [[ -f "$s10_retired_skills/assistant-ideate/notes.md" && -f "$s10_retired_skills/assistant-ideate/SKILL.md" ]] || s10_retired_failures+=("assistant-ideate with a user file was removed")
    grep -Fq 'skills/assistant-diagrams' "$s10_retired_home/install.out" || s10_retired_failures+=("modified assistant-diagrams was not reported")
    grep -Fq 'skills/assistant-ideate' "$s10_retired_home/install.out" || s10_retired_failures+=("user-extended assistant-ideate was not reported")
    [[ "$(cat "$s10_retired_home/purpose/TELOS.md" "$s10_retired_home/project/docs/telos.md" | shasum -a 256)" == "$s10_purpose_before" ]] \
        || s10_retired_failures+=("a user purpose file changed")
else
    s10_retired_failures+=("install failed: $(tail -n 2 "$s10_retired_home/install.err")")
fi
if [[ "${#s10_retired_failures[@]}" == 0 ]]; then pass; else fail "${s10_retired_failures[*]}"; fi

test_start "Codex install removes a byte-identical retired skill under CODEX_HOME"
retired_codex_home="$(mktemp -d)"
p0p4_register_cleanup "$retired_codex_home"
retired_seed_skill reflexion codex "$retired_codex_home/active/skills/assistant-reflexion"
mkdir -p "$retired_codex_home/.codex/skills"
retired_seed_skill reflexion codex "$retired_codex_home/.codex/skills/assistant-reflexion"
if HOME="$retired_codex_home" CODEX_HOME="$retired_codex_home/active" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-clarify --no-hooks </dev/null >"$retired_codex_home/install.out" 2>"$retired_codex_home/install.err" \
    && [[ ! -e "$retired_codex_home/active/skills/assistant-reflexion" ]] \
    && [[ -f "$retired_codex_home/.codex/skills/assistant-reflexion/SKILL.md" ]]; then
    pass
else
    fail "CODEX_HOME retired skill was not removed, or ~/.codex was touched: $(tail -n 2 "$retired_codex_home/install.err")"
fi

test_start "install dry-run prints the same plan digest as the real run and changes nothing"
retired_dry_home="$(mktemp -d)"
p0p4_register_cleanup "$retired_dry_home"
retired_seed_skill reflexion claude "$retired_dry_home/.claude/skills/assistant-reflexion"
retired_dry_before="$(retired_tree_listing "$retired_dry_home")"
if HOME="$retired_dry_home" bash "$FRAMEWORK_DIR/install.sh" --agent claude --skill assistant-clarify --no-hooks --dry-run </dev/null >"$retired_dry_home/../$(basename "$retired_dry_home").dry" 2>&1; then
    retired_dry_out="$retired_dry_home/../$(basename "$retired_dry_home").dry"
    p0p4_register_cleanup "$retired_dry_out"
    retired_dry_after="$(retired_tree_listing "$retired_dry_home")"
    retired_dry_digest="$(sed -n 's/.*Retired-item plan digest: \([0-9a-f]\{64\}\).*/\1/p' "$retired_dry_out")"
    HOME="$retired_dry_home" bash "$FRAMEWORK_DIR/install.sh" --agent claude --skill assistant-clarify --no-hooks </dev/null >"$retired_dry_out.real" 2>&1 || true
    p0p4_register_cleanup "$retired_dry_out.real"
    retired_real_digest="$(sed -n 's/.*Retired-item plan digest: \([0-9a-f]\{64\}\).*/\1/p' "$retired_dry_out.real")"
    if [[ "$retired_dry_before" == "$retired_dry_after" && -n "$retired_dry_digest" && "$retired_dry_digest" == "$retired_real_digest" \
        && ! -e "$retired_dry_home/.claude/skills/assistant-reflexion" ]]; then
        pass
    else
        fail "dry-run mutated the home or digests differ ('$retired_dry_digest' vs '$retired_real_digest')"
    fi
else
    fail "install dry-run failed"
fi

test_start "install dry-run with TMPDIR inside the agent home leaves the home untouched"
retired_tmp_home="$(mktemp -d)"
p0p4_register_cleanup "$retired_tmp_home"
retired_seed_skill reflexion claude "$retired_tmp_home/.claude/skills/assistant-reflexion"
mkdir -p "$retired_tmp_home/.claude/tmp"
retired_tmp_before="$(retired_tree_listing "$retired_tmp_home/.claude"; python3 -B -c 'import os, sys; [print(p, os.lstat(p).st_mtime_ns) for p in sys.argv[1:]]' "$retired_tmp_home/.claude" "$retired_tmp_home/.claude/tmp")"
if HOME="$retired_tmp_home" TMPDIR="$retired_tmp_home/.claude/tmp" bash "$FRAMEWORK_DIR/install.sh" --agent claude --skill assistant-clarify --no-hooks --dry-run </dev/null >"$retired_tmp_home.out" 2>&1; then
    p0p4_register_cleanup "$retired_tmp_home.out"
    retired_tmp_after="$(retired_tree_listing "$retired_tmp_home/.claude"; python3 -B -c 'import os, sys; [print(p, os.lstat(p).st_mtime_ns) for p in sys.argv[1:]]' "$retired_tmp_home/.claude" "$retired_tmp_home/.claude/tmp")"
    if [[ "$retired_tmp_before" == "$retired_tmp_after" ]]; then
        pass
    else
        fail "dry-run with TMPDIR in the agent home changed it: $(diff <(printf '%s\n' "$retired_tmp_before") <(printf '%s\n' "$retired_tmp_after") | head -n 4)"
    fi
else
    p0p4_register_cleanup "$retired_tmp_home.out"
    fail "install dry-run failed: $(tail -n 3 "$retired_tmp_home.out")"
fi

test_start "install without Python keeps retired skills, retires source-only tools from the list and completes"
retired_nopy_home="$(mktemp -d)"
retired_nopy_bin="$(mktemp -d)"
p0p4_register_cleanup "$retired_nopy_home" "$retired_nopy_bin"
retired_path_without_python "$retired_nopy_bin"
retired_seed_skill reflexion claude "$retired_nopy_home/.claude/skills/assistant-reflexion"
mkdir -p "$retired_nopy_home/.claude/tools/evals"
printf 'old\n' >"$retired_nopy_home/.claude/tools/context-budget-report.sh"
printf 'old\n' >"$retired_nopy_home/.claude/tools/evals/package.json"
if [[ -e "$retired_nopy_bin/python3" ]]; then
    fail "no-Python PATH fixture still contains python3"
elif HOME="$retired_nopy_home" PATH="$retired_nopy_bin" bash "$FRAMEWORK_DIR/install.sh" --agent claude --skill assistant-clarify --no-hooks </dev/null >"$retired_nopy_home/install.out" 2>"$retired_nopy_home/install.err" \
    && [[ -f "$retired_nopy_home/.claude/skills/assistant-reflexion/SKILL.md" ]] \
    && [[ ! -e "$retired_nopy_home/.claude/tools/context-budget-report.sh" && ! -e "$retired_nopy_home/.claude/tools/evals/package.json" ]] \
    && grep -Fq 'ownership helper unavailable; kept' "$retired_nopy_home/install.out"; then
    pass
else
    fail "Python-less install: $(tail -n 3 "$retired_nopy_home/install.out") $(tail -n 2 "$retired_nopy_home/install.err")"
fi

test_start "install from a checkout copy without .git reports the refusal, keeps retired skills and completes"
retired_copy_root="$(mktemp -d)"
p0p4_register_cleanup "$retired_copy_root"
retired_checkout_copy "$retired_copy_root/checkout"
mkdir -p "$retired_copy_root/home/.claude/skills"
retired_seed_skill reflexion claude "$retired_copy_root/home/.claude/skills/assistant-reflexion"
if HOME="$retired_copy_root/home" bash "$retired_copy_root/checkout/install.sh" --agent claude --skill assistant-clarify --no-hooks </dev/null >"$retired_copy_root/install.out" 2>"$retired_copy_root/install.err" \
    && [[ -f "$retired_copy_root/home/.claude/skills/assistant-reflexion/SKILL.md" ]] \
    && grep -Fq 'ownership helper refused:' "$retired_copy_root/install.out"; then
    pass
else
    fail "no-.git copy: $(grep -F 'ownership' "$retired_copy_root/install.out" | head -n 2) $(tail -n 2 "$retired_copy_root/install.err")"
fi

test_start "a hand-placed checkout entry point in an agent home refuses"
retired_hand_home="$(mktemp -d)"
p0p4_register_cleanup "$retired_hand_home"
mkdir -p "$retired_hand_home/.claude/tools/framework-ownership"
cp "$FRAMEWORK_DIR/tools/framework-ownership/"*.py "$FRAMEWORK_DIR/tools/framework-ownership/"*.json "$retired_hand_home/.claude/tools/framework-ownership/"
retired_seed_skill reflexion claude "$retired_hand_home/.claude/skills/assistant-reflexion"
retired_hand_status=0
HOME="$retired_hand_home" python3 -B "$retired_hand_home/.claude/tools/framework-ownership/ownership-checkout.py" install --agent claude >"$retired_hand_home/run.out" 2>&1 || retired_hand_status=$?
if [[ "$retired_hand_status" == 2 && -f "$retired_hand_home/.claude/skills/assistant-reflexion/SKILL.md" ]]; then
    pass
else
    fail "hand-placed entry point exited $retired_hand_status: $(tail -n 2 "$retired_hand_home/run.out")"
fi

test_start "an inventory error stops retired removal and installs no source-only tool"
retired_bad_root="$(mktemp -d)"
p0p4_register_cleanup "$retired_bad_root"
retired_checkout_copy "$retired_bad_root/checkout"
printf '{"schema_version": "9.0", "entries": []}\n' >"$retired_bad_root/checkout/tools/framework-ownership/retired-items.json"
mkdir -p "$retired_bad_root/home/.claude/tools"
printf 'old\n' >"$retired_bad_root/home/.claude/tools/context-budget-report.sh"
if HOME="$retired_bad_root/home" bash "$retired_bad_root/checkout/install.sh" --agent claude --skill assistant-clarify --no-hooks </dev/null >"$retired_bad_root/install.out" 2>"$retired_bad_root/install.err" \
    && grep -Fq 'retired tool and hook removal skipped' "$retired_bad_root/install.out" \
    && [[ -f "$retired_bad_root/home/.claude/tools/context-budget-report.sh" ]] \
    && [[ ! -e "$retired_bad_root/home/.claude/tools/evals/package.json" && ! -e "$retired_bad_root/home/.claude/tools/evals/run-codex-framework-evals.sh" ]] \
    && [[ ! -e "$retired_bad_root/home/.claude/tools/framework-ownership/ownership-checkout.py" ]]; then
    pass
else
    fail "inventory error: $(grep -F 'retired' "$retired_bad_root/install.out" | head -n 2) $(tail -n 2 "$retired_bad_root/install.err")"
fi

test_start "Python-less install refuses a traversal or malformed retired list line and removes nothing listed"
retired_tsv_failures=()
retired_tsv_bin="$(mktemp -d)"
p0p4_register_cleanup "$retired_tsv_bin"
retired_path_without_python "$retired_tsv_bin"
for retired_tsv_case in traversal malformed absolute crlf hook-module hook-helper hook-entrypoint-directory; do
    retired_tsv_root="$(mktemp -d)"
    p0p4_register_cleanup "$retired_tsv_root"
    retired_checkout_copy "$retired_tsv_root/checkout"
    retired_tsv="$retired_tsv_root/checkout/tools/framework-ownership/installer-exact-removal.tsv"
    case "$retired_tsv_case" in
        traversal) printf 'source_only_tool\tfile\tcontext-budget-report.sh\nsource_only_tool\tfile\t../sentinel\n' >"$retired_tsv" ;;
        malformed) printf 'source_only_tool\tfile\tcontext-budget-report.sh\nsource_only_tool\tfile\n' >"$retired_tsv" ;;
        absolute) printf 'source_only_tool\tfile\tcontext-budget-report.sh\nsource_only_tool\tdirectory\t/tmp\n' >"$retired_tsv" ;;
        crlf) printf 'source_only_tool\tfile\tcontext-budget-report.sh\r\n' >"$retired_tsv" ;;
        hook-module) printf 'source_only_tool\tfile\tcontext-budget-report.sh\nhook_module\tfile\t../sentinel-hook\n' >"$retired_tsv" ;;
        hook-helper) printf 'source_only_tool\tfile\tcontext-budget-report.sh\nhook_helper\tfile\ta/b.sh\n' >"$retired_tsv" ;;
        hook-entrypoint-directory) printf 'source_only_tool\tfile\tcontext-budget-report.sh\nhook_entrypoint\tdirectory\tsession-start.sh\n' >"$retired_tsv" ;;
    esac
    mkdir -p "$retired_tsv_root/home/.claude/tools"
    printf 'keep\n' >"$retired_tsv_root/home/.claude/sentinel"
    mkdir -p "$retired_tsv_root/home/.claude/hooks"
    printf 'keep\n' >"$retired_tsv_root/home/.claude/hooks/sentinel-hook"
    printf 'old\n' >"$retired_tsv_root/home/.claude/tools/context-budget-report.sh"
    if ! HOME="$retired_tsv_root/home" PATH="$retired_tsv_bin" bash "$retired_tsv_root/checkout/install.sh" --agent claude --skill assistant-clarify --no-hooks </dev/null >"$retired_tsv_root/install.out" 2>"$retired_tsv_root/install.err"; then
        retired_tsv_failures+=("$retired_tsv_case install failed: $(tail -n 1 "$retired_tsv_root/install.err")")
        continue
    fi
    grep -Fq 'retired tool list invalid: line' "$retired_tsv_root/install.out" || retired_tsv_failures+=("$retired_tsv_case: no invalid-list message")
    [[ -f "$retired_tsv_root/home/.claude/sentinel" ]] || retired_tsv_failures+=("$retired_tsv_case: sentinel removed")
    [[ -f "$retired_tsv_root/home/.claude/hooks/sentinel-hook" ]] || retired_tsv_failures+=("$retired_tsv_case: hook sentinel removed")
    [[ ! -e "$retired_tsv_root/home/.claude/hooks/assistant/session-start.sh" ]] || retired_tsv_failures+=("$retired_tsv_case: a hook shim was written")
    [[ -f "$retired_tsv_root/home/.claude/tools/context-budget-report.sh" ]] || retired_tsv_failures+=("$retired_tsv_case: a valid line was acted on")
done
if [[ "${#retired_tsv_failures[@]}" == 0 ]]; then pass; else fail "${retired_tsv_failures[*]}"; fi

test_start "Python-less install retires listed hook registrations with jq and preserves settings without jq"
retired_hook_failures=()
retired_hook_bin="$(mktemp -d)"
retired_hook_nojq_bin="$(mktemp -d)"
p0p4_register_cleanup "$retired_hook_bin" "$retired_hook_nojq_bin"
retired_path_without_python "$retired_hook_bin"
for retired_hook_name in $(ls "$retired_hook_bin"); do
    [[ "$retired_hook_name" == jq ]] || ln -s "$retired_hook_bin/$retired_hook_name" "$retired_hook_nojq_bin/$retired_hook_name"
done
for retired_hook_case in jq nojq; do
    retired_hook_home="$(mktemp -d)"
    p0p4_register_cleanup "$retired_hook_home"
    mkdir -p "$retired_hook_home/.claude/hooks/assistant"
    while IFS=$'\t' read -r retired_hook_kind _ retired_hook_path; do
        case "$retired_hook_kind" in
            hook_entrypoint|hook_helper|hook_module)
                mkdir -p "$(dirname "$retired_hook_home/.claude/hooks/assistant/$retired_hook_path")"
                printf '#!/bin/sh\necho old framework hook\n' >"$retired_hook_home/.claude/hooks/assistant/$retired_hook_path" ;;
        esac
    done <"$FRAMEWORK_DIR/tools/framework-ownership/installer-exact-removal.tsv"
    cat >"$retired_hook_home/.claude/settings.json" <<'JSON'
{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"$HOME/.claude/hooks/assistant/session-start.sh"},{"type":"command","command":"/tmp/custom-hook.sh"}]}]}}
JSON
    if [[ "$retired_hook_case" == jq ]]; then retired_hook_path="$retired_hook_bin"; else retired_hook_path="$retired_hook_nojq_bin"; fi
    if ! HOME="$retired_hook_home" PATH="$retired_hook_path" bash "$FRAMEWORK_DIR/install.sh" --agent claude --skill assistant-clarify </dev/null >"$retired_hook_home/install.out" 2>"$retired_hook_home/install.err"; then
        retired_hook_failures+=("$retired_hook_case install failed: $(tail -n 1 "$retired_hook_home/install.err")")
        continue
    fi
    grep -Fq '/tmp/custom-hook.sh' "$retired_hook_home/.claude/settings.json" || retired_hook_failures+=("$retired_hook_case: custom hook registration lost")
    while IFS=$'\t' read -r retired_hook_kind _ retired_hook_path; do
        retired_hook_file="$retired_hook_home/.claude/hooks/assistant/$retired_hook_path"
        case "$retired_hook_kind" in
            hook_helper|hook_module) [[ ! -e "$retired_hook_file" ]] || retired_hook_failures+=("$retired_hook_case: $retired_hook_path kept") ;;
            hook_entrypoint) [[ -f "$retired_hook_file" ]] && ! grep -Fq 'old framework hook' "$retired_hook_file" || retired_hook_failures+=("$retired_hook_case: $retired_hook_path not replaced by a shim") ;;
        esac
    done <"$FRAMEWORK_DIR/tools/framework-ownership/installer-exact-removal.tsv"
    if [[ "$retired_hook_case" == jq ]] && grep -Fq 'hooks/assistant/session-start.sh' "$retired_hook_home/.claude/settings.json"; then
        retired_hook_failures+=("jq: listed framework registration kept")
    fi
done
if [[ "${#retired_hook_failures[@]}" == 0 ]]; then pass; else fail "${retired_hook_failures[*]}"; fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
