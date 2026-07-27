#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

pattern_tool="$FRAMEWORK_DIR/tools/patterns/pattern-library.sh"
pattern_docs="$FRAMEWORK_DIR/docs/pattern-library.md"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/pattern-library-fixture.XXXXXX")"
config_file="$fixture_root/config.json"
index_file="$fixture_root/index.json"
missing_config="$fixture_root/missing.json"
symlink_config="$fixture_root/symlink-config.json"
library_root="$fixture_root/library"
library_link="$fixture_root/library-link"
outside_file="$fixture_root/outside.cs.txt"
p0p4_register_cleanup "$fixture_root"

mkdir -p "$library_root"
cat >"$library_root/Creational.Factories.Factory.cs.txt" <<'EOF'
public sealed class FactoryExample { }
EOF
cat >"$library_root/Creational.Builder.FunctionalBuilder.cs.txt" <<'EOF'
public sealed class FunctionalBuilderExample { }
EOF
cat >"$library_root/Structural.Adapter.WithCaching.cs.txt" <<'EOF'
public sealed class CachingAdapterExample { }
EOF
cat >"$library_root/Behavioral.Strategy.Dynamic.cs.txt" <<'EOF'
public sealed class DynamicStrategyExample { }
EOF
cat >"$library_root/Behavioral.Strategy.Static.cs.txt" <<'EOF'
public sealed class StaticStrategyExample { }
EOF
cat >"$outside_file" <<'EOF'
public sealed class EscapedExample { }
EOF
ln -s "$outside_file" "$library_root/Behavioral.Visitor.Escaped.cs.txt"
ln -s "$library_root" "$library_link"

jq -n \
    --arg root "$library_root" \
    '{schema_version:"1.0", libraries:[{id:"patterns", root:$root}]}' \
    >"$config_file"
jq -n \
    --arg root "$library_link" \
    '{schema_version:"1.0", libraries:[{id:"patterns", root:$root}]}' \
    >"$symlink_config"

test_start "pattern library CLI exists, is executable, and documents its commands"
help_output=""
if [[ -x "$pattern_tool" ]]; then
    help_output="$("$pattern_tool" --help 2>&1 || true)"
fi

if [[ -x "$pattern_tool" ]] \
    && printf '%s\n' "$help_output" | grep -Fq -- "validate-config" \
    && printf '%s\n' "$help_output" | grep -Fq -- "build-index" \
    && printf '%s\n' "$help_output" | grep -Fq -- "search" \
    && printf '%s\n' "$help_output" | grep -Fq -- "show"; then
    pass
else
    fail "pattern library CLI or required help is missing"
fi

test_start "installed workflow resolves the pattern tool outside the framework repository"
install_home="$fixture_root/install-home"
unrelated_cwd="$fixture_root/unrelated-project"
mkdir -p "$install_home" "$unrelated_cwd"
installed_tool="$install_home/.codex/tools/patterns/pattern-library.sh"
if HOME="$install_home" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow >/dev/null \
    && [[ -x "$installed_tool" ]] \
    && (cd "$unrelated_cwd" && "$installed_tool" validate-config --config "$missing_config") \
        | jq -e '.status == "not_configured"' >/dev/null \
    && p0p4_contains_text "$FRAMEWORK_DIR/skills/assistant-workflow/references/design-pattern-retrieval.md" '<framework-tools>/patterns/pattern-library.sh'; then
    pass
else
    fail "installed pattern retrieval depends on the framework repository working directory"
fi

test_start "missing configuration is a clean non-interactive no-op"
missing_ok=true
if ! missing_validate="$("$pattern_tool" validate-config --config "$missing_config" 2>/dev/null)"; then missing_ok=false; fi
if ! missing_build="$("$pattern_tool" build-index --config "$missing_config" --output "$index_file" 2>/dev/null)"; then missing_ok=false; fi
if ! missing_search="$("$pattern_tool" search --config "$missing_config" --query factory 2>/dev/null)"; then missing_ok=false; fi
if ! missing_show="$("$pattern_tool" show --config "$missing_config" --library patterns --relative-path Creational.Factories.Factory.cs.txt 2>/dev/null)"; then missing_ok=false; fi
if [[ "$missing_ok" == true ]] \
    && jq -e '.status == "not_configured"' <<<"$missing_validate" >/dev/null \
    && jq -e '.status == "not_configured"' <<<"$missing_build" >/dev/null \
    && jq -e '.status == "not_configured" and .results == []' <<<"$missing_search" >/dev/null \
    && jq -e '.status == "not_configured"' <<<"$missing_show" >/dev/null \
    && [[ ! -e "$index_file" ]] \
    && ! printf '%s\n' "$missing_validate$missing_build$missing_search$missing_show" | grep -Eqi 'ask|prompt|configure now'; then
    pass
else
    fail "missing config did not return clean not_configured responses"
fi

test_start "explicit configuration validates without exposing configured roots"
validate_output="$("$pattern_tool" validate-config --config "$config_file" 2>/dev/null || true)"
if jq -e '.status == "configured" and .library_ids == ["patterns"]' <<<"$validate_output" >/dev/null \
    && ! grep -Fq -- "$library_root" <<<"$validate_output"; then
    pass
else
    fail "valid explicit config was rejected or leaked its root"
fi

test_start "configured library roots cannot be symlinks"
if ! "$pattern_tool" validate-config --config "$symlink_config" >/dev/null 2>&1; then
    pass
else
    fail "validation accepted a symlink as a configured library root"
fi

test_start "index is metadata-only, portable, and excludes symlinks"
build_output="$("$pattern_tool" build-index --config "$config_file" --output "$index_file" 2>/dev/null || true)"
if jq -e '
      .schema_version == "1.0"
      and .status == "ready"
      and (.entries | length == 5)
      and (.entries | all(
        .library == "patterns"
        and (.relative_path | type == "string")
        and (.category | type == "string")
        and (.pattern | type == "string")
        and (.variant | type == "string")
        and .language == "csharp"
        and (.hash | test("^[0-9a-f]{64}$"))
        and (.word_count | type == "number" and . > 0)
        and (has("body") | not)
        and (has("root") | not)
        and (has("absolute_path") | not)
      ))
      and (.entries | any(
        .relative_path == "Creational.Factories.Factory.cs.txt"
        and .category == "Creational"
        and .pattern == "Factories"
        and .variant == "Factory"
      ))
      and (.entries | all(.relative_path != "Behavioral.Visitor.Escaped.cs.txt"))
    ' "$index_file" >/dev/null \
    && jq -e '.status == "built" and .entry_count == 5' <<<"$build_output" >/dev/null \
    && ! grep -Fq -- "$library_root" "$index_file" \
    && ! grep -Fq -- "FactoryExample" "$index_file"; then
    pass
else
    fail "index was not safe metadata-only output"
fi

test_start "search is metadata-only and defaults to at most three results"
search_output="$("$pattern_tool" search --config "$config_file" --query a 2>/dev/null || true)"
if jq -e '
      .status == "ready"
      and .query == "a"
      and (.results | length == 3)
      and (.results | all(has("body") | not))
      and (.results | all(has("root") | not))
    ' <<<"$search_output" >/dev/null \
    && ! grep -Fq -- "$library_root" <<<"$search_output"; then
    pass
else
    fail "search did not apply the safe default result limit"
fi

test_start "search accepts limits one through five and rejects values outside that range"
limited_output="$("$pattern_tool" search --config "$config_file" --query strategy --limit 1 2>/dev/null || true)"
if jq -e '.results | length == 1' <<<"$limited_output" >/dev/null \
    && ! "$pattern_tool" search --config "$config_file" --query strategy --limit 0 >/dev/null 2>&1 \
    && ! "$pattern_tool" search --config "$config_file" --query strategy --limit 6 >/dev/null 2>&1; then
    pass
else
    fail "search limit bounds were not enforced"
fi

test_start "show reads only an explicit safe relative path"
show_output="$("$pattern_tool" show --config "$config_file" --library patterns --relative-path Creational.Factories.Factory.cs.txt 2>/dev/null || true)"
if [[ "$show_output" == "public sealed class FactoryExample { }" ]] \
    && ! "$pattern_tool" show --config "$config_file" --library patterns --relative-path ../outside.cs.txt >/dev/null 2>&1 \
    && ! "$pattern_tool" show --config "$config_file" --library patterns --relative-path Behavioral.Visitor.Escaped.cs.txt >/dev/null 2>&1; then
    pass
else
    fail "show permitted an unsafe path or failed to read a safe explicit file"
fi

test_start "documentation explains private explicit pattern-library configuration without personal paths"
if [[ -f "$pattern_docs" ]] \
    && grep -Fq -- "opt-in" "$pattern_docs" \
    && grep -Fq -- "not_configured" "$pattern_docs" \
    && grep -Fq -- "metadata" "$pattern_docs" \
    && grep -Fq -- "company" "$pattern_docs" \
    && grep -Fq -- '~/.config/assistant-framework/pattern-libraries.json' "$FRAMEWORK_DIR/README.md" \
    && grep -Fq -- "resolved from the configuration file's directory" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq -- "personal or project instructions" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq -- '~/.codex/tools/patterns/pattern-library.sh validate-config' "$FRAMEWORK_DIR/README.md" \
    && ! grep -Eq -- '/Users/|/home/[^/]+/|[A-Za-z]:\\\\Users\\\\' "$pattern_docs" \
    && ! grep -Eq -- '/Users/|/home/[^/]+/|[A-Za-z]:\\\\Users\\\\' "$FRAMEWORK_DIR/README.md"; then
    pass
else
    fail "pattern library docs omit executable private configuration guidance or contain a personal path"
fi

test_start "workflow retrieves configured examples only after repository patterns and design force"
retrieval_ref="$FRAMEWORK_DIR/skills/assistant-workflow/references/design-pattern-retrieval.md"
if [[ -f "$retrieval_ref" ]] \
    && p0p4_contains_text "$retrieval_ref" "Search repository-native patterns first" \
    && p0p4_contains_text "$retrieval_ref" "concrete design force" \
    && p0p4_contains_text "$retrieval_ref" "load at most 1-3" \
    && p0p4_contains_text "$retrieval_ref" "KISS and YAGNI" \
    && p0p4_contains_text "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml" "design-pattern-retrieval.md"; then
    pass
else
    fail "workflow does not safely route optional external pattern retrieval"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
