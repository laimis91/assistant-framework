#!/usr/bin/env python3
"""Offline tests for the skill-activation scorer and plugin generator. No model calls."""
import io
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import activation
import generate_plugin
import report
import run_trials
import suite
from generate_plugin import checked_output, generate, skills_guidance, tree_hash
from score_trace import classify_bash, load_events, score

ROOT = "/repo/plugins/guided"
CWD = "/tmp/e-1/home/cwd"


def init():
    return {"type": "system", "subtype": "init", "cwd": CWD}


def call(name, identifier="t", **data):
    return {"type": "assistant", "message": {"content": [
        {"type": "tool_use", "id": identifier, "name": name, "input": data}]}}


def failed(identifier, text="boom"):
    return {"type": "user", "message": {"content": [
        {"type": "tool_result", "tool_use_id": identifier, "is_error": True, "content": text}]}}


def result(subtype="success", is_error=False):
    return {"type": "result", "subtype": subtype, "is_error": is_error}


IMPLEMENT = {"required": ["assistant-workflow", "assistant-verification"]}
REFUSED = "<tool_use_error>Error: No such tool available: Bash. Bash is disabled for this session.</tool_use_error>"


def verdict(events, case=None):
    return score([init(), *events], case or IMPLEMENT, ROOT)


class BashClassification(unittest.TestCase):
    def assert_kind(self, kind, commands):
        for command in commands:
            self.assertEqual(classify_bash(command), kind, command)

    def test_read_only_chains_are_read(self):
        self.assert_kind("read", [
            "git status", "cd /x && ls -la 2>/dev/null", "rg 'a>b' src | head -5", "ls 2>&1 | head",
            "git log --oneline -5 && git status --short", "find . -name '*.py'", "sed -n 1,5p f",
            "cat a < b", "wc -l <<< text"])

    def test_quoted_operators_are_arguments(self):
        self.assert_kind("read", ["rg '>' src", "rg '|' src", "rg ';' src", 'echo ""', "rg 'a && rm b' src", "echo \\> x"])

    def test_read_forms_of_mutating_git_commands(self):
        self.assert_kind("read", ["git stash list", "git stash show", "git tag", "git tag -l", "git tag --list"])
        self.assert_kind("mutation", ["git stash", "git stash pop", "git tag v1"])

    def test_descriptor_redirects_are_safe(self):
        self.assert_kind("read", ["ls 2>&-", "ls |& cat", "ls >/dev/null", "ls 2>&1 >/dev/null", "ls 1>&2"])

    def test_writes_are_mutations(self):
        self.assert_kind("mutation", [
            "git commit -m x", "cd /x && git push", "echo hi > f.txt", "cat a >> b", "rm f", "sed -i s/a/b/ f",
            "gh pr create --fill", "ls && touch f", "ls 2> errors.log", "ls &> f", "ls &>> f", "ls >| f", "ls >& f"])

    def test_files_named_like_descriptors_are_written(self):
        self.assert_kind("mutation", ["echo hi > 1", "cat a >> 2"])

    def test_glued_and_read_write_operators_are_mutations(self):
        self.assert_kind("mutation", ["ls;>f", "cat <> newfile", "ls|tee f"])

    def test_writing_forms_of_read_commands_are_not_read(self):
        self.assert_kind("mutation", [
            "sed -n 'w out.txt' f", "sed -n '1,5w out' f", "sed -n -Ei s/a/b/ f", "sed -n --in-place s/a/b/ f",
            "git diff --output=f", "git log --output=f", "git show --output f"])
        self.assert_kind("unclassified", [
            "find . -exec cat {} ;", "find . -okdir wc {} ;", "rg --pre ./script pat", "rg --pre=./script pat",
            "rg --hostname-bin=./x pat", "sed -E -n 1p f", "git -c core.pager=x status"])
        self.assert_kind("mutation", ["find . -fprintf out '%p'", "find . -fprint0 out", "find . -fls out", "find . -delete",
                                      "sed 's/a/b/gw out' f", "sed -n '1,5 w out' f"])

    def test_expansions_that_can_hide_a_write_are_not_read(self):
        self.assert_kind("unclassified", [
            "echo $'\\'' > f # '", "echo $'\\''; rm f #'", "git log {--output=f,-1}", "find . {-delete,-print}",
            "rg {--pre=./x,pat} src", "find . -del${U}ete", "ls $HOME", 'ls "$HOME"', "echo {a..c}"])
        self.assert_kind("mutation", ["find . -del\\\nete", "ls >&٣"])

    def test_plain_text_with_dollars_and_braces_stays_read(self):
        self.assert_kind("read", ["rg 'a$' src", 'rg "a$" src', "rg 'x{1,2}' src", "git log -1 --format='%H {a,b}'"])

    def test_sed_script_text_is_not_a_write_command(self):
        self.assert_kind("read", ["sed -n '/warning/p' f", "sed -n '/workflow/,+20p' f", "sed -n '$p' f"])
        self.assert_kind("read", ["sed -n '/a\\/w b/p' f"])
        self.assert_kind("unclassified", ["sed 's/old/world/' f", "sed -n 's/a/b/p' f", "sed 's/a\\/w/b/' f"])
        self.assert_kind("mutation", ["sed 's/a\\/x/b/w out' f", "sed 's|a|b|w out' f"])

    def test_near_misses_of_writing_options_stay_read(self):
        self.assert_kind("read", ["ls >& /dev/null", "git tag --sort=-creatordate", "git tag -n", "git log --output-indicator-new=+",
                                  "git branch", "git branch -a", "git worktree list"])
        self.assert_kind("mutation", ["git tag -d v1", "git branch new", "git worktree add x", "git init", "git clone u",
                                      "git format-patch -1", "git fetch", "git --config-env k=v commit"])

    def test_branch_and_tag_listing_forms_are_read(self):
        self.assert_kind("read", [
            "git branch --merged main", "git branch --no-merged main", "git branch -r --contains abc123", "git branch --list 'feature/*'",
            "git branch --format '%(refname:short)'", "git branch -vv", "git branch --show-current",
            "git tag --contains abc123", "git tag --points-at HEAD", "git tag -ln 'v*'", "git tag -n5"])

    def test_branch_and_tag_changing_forms_are_mutations(self):
        self.assert_kind("mutation", [
            "git branch --set-upstream-to=origin/main", "git branch --unset-upstream", "git branch --edit-description",
            "git branch -u origin/main", "git branch -D old", "git branch -m new", "git tag -a v1 -m x", "git tag -d v1", "git tag v1"])
        self.assert_kind("unclassified", ["git branch --unknown", "git tag --unknown"])

    def test_other_git_writers(self):
        self.assert_kind("mutation", ["git remote add origin u", "git config user.email x", "git submodule add u"])
        self.assert_kind("unclassified", ["git remote -v", "git config --get user.email", "git config user.email", "git submodule status"])

    def test_commands_run_by_other_commands_are_seen(self):
        self.assert_kind("mutation", [
            "find . -name '*.py' -exec sed -i 's/a/b/' {} +", "find . -name '*.pyc' -exec rm -f {} +", "find . -exec rm {} ;",
            "find . -okdir rm {} ;", "grep -rl foo . | xargs sed -i 's/a/b/'", "find . -name '*.orig' | xargs rm", "xargs -I {} rm {}",
            "timeout 60 git commit -m x", "sudo rm f", "nohup git push", "bash -c 'rm f'", "sh -c 'ls; git push'", "sed -I '' s/a/b/ f"])

    def test_standard_devices_arithmetic_and_existence_checks_are_not_writes(self):
        self.assert_kind("read", ["echo msg > /dev/stderr", "echo msg >/dev/stdout", "command -v rm", "command -V tee"])
        self.assert_kind("unclassified", ["echo $((2 > 1))", "echo $((x >> 1))", "if (( n > 0 )); then ls; fi", '[[ "$a" > "$b" ]]'])
        self.assert_kind("mutation", ["echo $((1)) > f", "[[ a > b ]] && rm f", "(( x > 1 )) && git push"])

    def test_mutation_after_a_broken_substitution_is_still_seen(self):
        self.assert_kind("mutation", ["x=$(cat <<'EOF'\nuse foo( here\nEOF\n); git commit -m \"$x\"", "msg=$(printf 'a)'); git commit -m \"$msg\""])

    def test_shell_option_clusters_with_c_are_read(self):
        self.assert_kind("mutation", ["bash -lc 'git push'", "sh -ec 'rm f'", "zsh -lc 'git commit -m x'", "bash -e -c 'rm f'"])
        self.assert_kind("unclassified", ["bash -lc ls", "bash -l script.sh", "bash --norc"])

    def test_git_config_forms(self):
        self.assert_kind("mutation", ["git config --global --unset core.hooksPath", "git config --unset user.name",
                                      "git config --remove-section foo", "git config --global user.email x", "git config set a b"])
        self.assert_kind("unclassified", ["git config get user.name", "git config list", "git config -f .gitmodules submodule.a.url"])

    def test_tests_under_control_words_are_not_redirects(self):
        self.assert_kind("unclassified", ['if [[ "$a" > "$b" ]]; then ls; fi', "while [[ $x > 5 ]]; do ls; done",
                                          'for f in *; do [[ "$f" > a ]] && echo "$f"; done', "! [[ a > b ]]"])
        self.assert_kind("mutation", ["if [[ a > b ]]; then rm f; fi"])

    def test_listing_option_values_are_not_short_flags(self):
        self.assert_kind("read", ["git branch --sort -committerdate", "git tag --sort -creatordate", "git tag --sort -v:refname",
                                  "git tag -n 'v*'", "git tag -n5 v1.0"])
        self.assert_kind("mutation", ["git branch -d --sort x old"])

    def test_existence_checks_under_control_words_are_not_mutations(self):
        self.assert_kind("unclassified", ["if command -v rm >/dev/null 2>&1; then ls; fi", "! command -v tee", "if ! command -v cp; then ls; fi"])

    def test_find_predicates_that_only_resemble_exec_stay_read(self):
        self.assert_kind("read", ["find . -type f -executable"])

    def test_line_continuations_join_words(self):
        self.assert_kind("mutation", ["cd /x && \\\n git commit -m y", "ls && \\\n rm f", "git \\\n commit -m x"])
        self.assert_kind("read", ["ls \\\n -la"])

    def test_heredocs_keep_scanning_and_skip_their_body(self):
        self.assert_kind("mutation", ["cat <<'EOF' > notes.md\nx\nEOF", "cat <<EOF\nx\nEOF\nrm f", "cat <<E | tee f\nx\nE",
                                      "cat <<-EOF\n\tx\n\tEOF\nrm f"])
        self.assert_kind("unclassified", ["cat <<EOF\nrm f\nEOF", "cat <<EOF\nrm f", "cat <<"])

    def test_prefixes_and_compound_commands_do_not_hide_a_mutation(self):
        self.assert_kind("mutation", [
            "HUSKY=0 git commit -m x", "GIT_EDITOR=true git rebase --continue", 'for f in a b; do git add "$f"; done',
            "if git diff --quiet; then git commit -m x; fi", "{ rm f; }", "! git push", "/usr/bin/git commit -m x",
            "/bin/rm f", "env A=1 rm f", "env -i rm f", "command rm f", "time rm f"])

    def test_prefixes_and_paths_never_make_a_command_read(self):
        self.assert_kind("unclassified", ["FOO=1 ls", "./ls", "/tmp/cat f", "env ls", "command ls", "! ls", "{", "A=1", "env"])

    def test_substitution_bodies_are_read(self):
        self.assert_kind("mutation", ["sha=$(git commit -m x)", 'echo "$(git push)"', "echo `rm f`", "echo $(echo $(rm f))",
                                      "echo $(rm f", "echo `rm f", "echo $(ls > f)"])
        self.assert_kind("unclassified", ["echo $(ls)", "$(", "`"])

    def test_deep_nesting_and_odd_strings_do_not_crash(self):
        for command in ("$(" * 2000, "`" * 2001, "\\", "'", '"', "<", ">", ">&", "<<", "&", ";", "((((", "$", "${", "{", "}", "#", "\n\n", "", "$((", "((", "[[", "bash -c", "xargs -n", "timeout", "timeout 1 " * 3000, "-"):
            self.assertIn(classify_bash(command), ("read", "mutation", "unclassified"), repr(command))

    def test_known_mutations_win_over_opaque_forms(self):
        self.assert_kind("mutation", [
            "git commit -m \"$(cat <<'EOF'\nIt's a fix (really)\nEOF\n)\"", "gh pr create --body \"$(cat x)\"", "rm $(ls)",
            "(cd x && rm f)", "git -C /x commit -m y", "git --no-pager -c a=b push", 'rm ""', "git commit -F - <<EOF\nbody\nEOF"])

    def test_unknown_commands_are_unclassified(self):
        self.assert_kind("unclassified", [
            "python -m pytest -q", "make", "ls $(pwd)", "ls `pwd`", "(ls)", "git frobnicate", "FOO=1 ls", "echo 'open",
            "cat <<EOF\nx\nEOF", "xargs cat", "xargs", "timeout 5 ls", "bash -c ls", "bash script.sh", "cat <(ls)"])

    def test_case_allowlist_adds_a_command(self):
        self.assertEqual(classify_bash("python -m pytest -q", ("python -m pytest",)), "read")
        self.assertEqual(classify_bash("python -m pytest -q && rm f", ("python -m pytest",)), "mutation")


class Scoring(unittest.TestCase):
    def activate_both(self):
        return [call("Skill", "a", skill="af:assistant-workflow"), call("Skill", "b", skill="assistant-verification")]

    def test_all_required_before_mutation_passes(self):
        self.assertEqual(verdict([*self.activate_both(), call("Edit", "e"), result()])["verdict"], "pass")

    def test_write_before_activation_fails_even_when_edit_comes_after(self):
        run = verdict([call("Write", "w"), *self.activate_both(), call("Edit", "e"), result()])
        self.assertEqual((run["verdict"], run["stop_tool"]), ("fail", "Write"))

    def test_refused_write_is_still_the_decision_point(self):
        run = verdict([call("Write", "w"), failed("w", "denied"), *self.activate_both(), result()])
        self.assertEqual(run["verdict"], "fail")

    def test_one_of_two_required_fails(self):
        run = verdict([call("Skill", "a", skill="af:assistant-workflow"), call("Edit", "e"), result()])
        self.assertEqual((run["verdict"], run["missing"]), ("fail", ["assistant-verification"]))

    def test_nested_mutation_counts(self):
        nested = call("Edit", "e")
        nested["parent_tool_use_id"] = "agent"
        self.assertEqual(verdict([nested, *self.activate_both(), result()])["verdict"], "fail")

    def test_failed_skill_call_is_not_an_activation(self):
        run = verdict([call("Skill", "a", skill="assistant-workflow"), failed("a"), call("Skill", "b", skill="assistant-verification"),
                       call("Edit", "e"), result()])
        self.assertEqual(run["missing"], ["assistant-workflow"])

    def test_installed_skill_read_activates_and_fixture_read_does_not(self):
        installed = call("Read", "a", file_path=f"{ROOT}/skills/assistant-workflow/SKILL.md")
        fixture = call("Read", "b", file_path=f"{CWD}/skills/assistant-verification/SKILL.md")
        run = verdict([installed, fixture, call("Edit", "e"), result()])
        self.assertEqual((run["activated"], run["missing"]), (["assistant-workflow"], ["assistant-verification"]))

    def test_path_traversal_out_of_the_fixture_is_normalized(self):
        path = f"{CWD}/../../../../..{ROOT}/skills/assistant-workflow/SKILL.md"
        self.assertEqual(verdict([call("Read", "a", file_path=path), result()])["activated"], ["assistant-workflow"])

    def test_shell_reads_of_installed_skill_activate(self):
        path = f"{ROOT}/skills/assistant-workflow/SKILL.md"
        for command in (f"cat {path}", f"head -5 {path}", f"sed -n 1,5p {path}", f"cd {ROOT}/skills/assistant-workflow && cat SKILL.md",
                        'cat "$CLAUDE_PLUGIN_ROOT/skills/assistant-workflow/SKILL.md"', "cat ${CLAUDE_PLUGIN_ROOT}/skills/assistant-workflow/SKILL.md"):
            self.assertEqual(verdict([call("Bash", "a", command=command), result()])["activated"], ["assistant-workflow"], command)

    def test_mentioning_a_skill_path_is_not_an_activation(self):
        path = f"{ROOT}/skills/assistant-workflow/SKILL.md"
        for command in (f"ls -la {path}", f"echo {path}", f"git log -- {path}", f"head -5 {ROOT}/skills/*/SKILL.md", f"cat {path}.bak",
                        f"cat {CWD}{path}", "cd skills/assistant-workflow && cat SKILL.md"):
            self.assertEqual(verdict([call("Bash", "a", command=command), result()])["activated"], [], command)

    def test_unclassified_command_is_inconclusive(self):
        self.assertEqual(verdict([call("Bash", "a", command="make"), result()])["verdict"], "inconclusive")

    def test_refused_unknown_command_did_not_run_and_does_not_stop(self):
        run = verdict([call("Bash", "x", command="make"), failed("x", REFUSED), *self.activate_both(), call("Edit", "e"), result()])
        self.assertEqual(run["verdict"], "pass")

    def test_command_that_only_printed_the_refusal_text_still_stops(self):
        run = verdict([call("Bash", "x", command="make"), failed("x", "make: No such tool available: Bash"), *self.activate_both(), result()])
        self.assertEqual(run["verdict"], "inconclusive")

    def test_refused_known_mutation_is_the_decision_point(self):
        run = verdict([call("Bash", "x", command="git commit -m y"), failed("x", REFUSED), *self.activate_both(), result()])
        self.assertEqual((run["verdict"], run["stop_tool"]), ("fail", "Bash"))

    def test_turn_limit_after_all_required_passes_and_before_is_inconclusive(self):
        self.assertEqual(verdict([*self.activate_both(), result("error_max_turns", True)])["verdict"], "pass")
        self.assertEqual(verdict([result("error_max_turns", True)])["verdict"], "inconclusive")

    def test_turn_limit_after_a_forbidden_skill_fails(self):
        case = {"required": ["assistant-review"], "forbidden": ["assistant-docs"]}
        events = [call("Skill", "a", skill="assistant-review"), call("Skill", "b", skill="assistant-docs"), result("error_max_turns", True)]
        self.assertEqual(verdict(events, case)["verdict"], "fail")

    def test_run_errors_and_missing_results_are_inconclusive(self):
        everything = {"required": [], "forbidden": "*"}
        self.assertEqual(verdict([result("success", True)], everything)["verdict"], "inconclusive")
        self.assertEqual(verdict([result("error_during_execution", True)], everything)["stop"], "run_error")
        self.assertEqual(verdict([*self.activate_both()])["verdict"], "inconclusive")

    def test_final_answer_without_required_fails(self):
        self.assertEqual(verdict([result()])["verdict"], "fail")

    def test_forbidden_fails_and_extra_does_not(self):
        case = {"required": ["assistant-review"], "forbidden": ["assistant-skill-creator"], "excused": []}
        hit = verdict([call("Skill", "a", skill="assistant-review"), call("Skill", "b", skill="assistant-skill-creator"), result()], case)
        extra = verdict([call("Skill", "a", skill="assistant-review"), call("Skill", "b", skill="assistant-docs"), result()], case)
        self.assertEqual(hit["verdict"], "fail")
        self.assertEqual((extra["verdict"], extra["extra"]), ("pass", ["assistant-docs"]))

    def test_every_skill_forbidden(self):
        case = {"required": [], "forbidden": "*"}
        self.assertEqual(verdict([result()], case)["verdict"], "pass")
        self.assertEqual(verdict([call("Skill", "a", skill="assistant-docs"), result()], case)["verdict"], "fail")
        self.assertEqual(verdict([result("error_max_turns", True)], case)["verdict"], "inconclusive")

    def test_forbidden_after_the_decision_point_is_not_read(self):
        case = {"required": [], "forbidden": "*"}
        run = verdict([call("Edit", "e"), call("Skill", "a", skill="assistant-docs"), result()], case)
        self.assertEqual(run["verdict"], "pass")

    def test_prefix_activation_satisfies(self):
        case = {**IMPLEMENT, "prefix_activated": ["assistant-workflow", "assistant-verification"]}
        self.assertEqual(verdict([call("Edit", "e"), result()], case)["verdict"], "pass")

    def test_compaction_kinds(self):
        never = {**IMPLEMENT, "compaction_kind": "never_activated"}
        self.assertEqual(verdict([call("Edit", "e"), result()], never)["verdict"], "fail")
        other_skill = {"required": ["assistant-verification"], "prefix_activated": ["assistant-workflow"], "compaction_kind": "never_activated"}
        self.assertEqual(verdict([call("Edit", "e"), result()], other_skill)["missing"], ["assistant-verification"])
        before = {"required": ["assistant-workflow"], "prefix_activated": ["assistant-workflow"], "compaction_kind": "activated_before"}
        kept = verdict([call("Edit", "e"), result()], before)
        again = verdict([call("Skill", "a", skill="assistant-workflow"), call("Edit", "e"), result()], before)
        self.assertEqual((kept["verdict"], kept["reinvoked"]), ("pass", []))
        self.assertEqual((again["verdict"], again["reinvoked"]), ("pass", ["assistant-workflow"]))

    def test_case_defects_are_rejected(self):
        for case in ({"required": ["a"], "forbidden": ["a"]}, {"required": ["a"], "forbidden": "*"}, {"forbidden": "all"},
                     {"required": ["a"], "prefix_activated": ["a"], "compaction_kind": "never_activated"}, {"compaction_kind": "other"},
                     {"required": "assistant-review"}, {"required": None}, {"forbidden": {"a": 1}}, {"allow_commands": "make"},
                     {"allow_commands": [1]}, {"optional": "a"}, {"prefix_activated": [1]}, [], None, "x"):
            with self.assertRaises(ValueError, msg=case):
                score([init(), result()], case, ROOT)


class MalformedTraces(unittest.TestCase):
    def test_malformed_events_are_inconclusive_and_do_not_raise(self):
        every = {"required": [], "forbidden": "*"}
        for event in (1, "x", None, ["x"], {"type": "assistant"}, {"type": "assistant", "message": None},
                      {"type": "assistant", "message": {"content": None}}, {"type": "assistant", "message": {"content": "text"}},
                      {"type": "assistant", "message": {"content": ["x"]}},
                      {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": [], "input": {}}]}},
                      {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Read", "input": "x"}]}}):
            self.assertEqual(verdict([event, result()], every)["verdict"], "inconclusive", event)

    def test_odd_values_in_otherwise_valid_events_do_not_raise(self):
        events = [{"type": "user", "message": "x"}, {"type": "user", "message": {"content": ["x"]}},
                  {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": [], "is_error": True}]}},
                  call("Skill", [], skill="assistant-docs"), call("Bash", "b", command=5), call("Read", "r", file_path=None), result()]
        self.assertEqual(verdict(events, {"required": ["assistant-docs"]})["stop"], "unclassified_bash")

    def test_non_string_cwd_does_not_raise(self):
        events = [{"type": "system", "subtype": "init", "cwd": 5}, call("Read", "a", file_path=f"{ROOT}/skills/assistant-docs/SKILL.md"), result()]
        self.assertEqual(score(events, {"required": ["assistant-docs"]}, ROOT)["verdict"], "pass")

    def test_malformed_skill_input_is_not_an_activation(self):
        every = {"required": [], "forbidden": "*"}
        for data in ({}, {"skill": None}, {"skill": ["x"]}, {"skill": ""}):
            self.assertEqual(verdict([call("Skill", "a", **data), result()], every)["activated"], [], data)

    def test_deeply_nested_trace_line_is_unreadable_not_a_crash(self):
        events = load_events([json.dumps(init()), "[" * 1000000])
        self.assertEqual(score(events, {"required": []}, ROOT)["verdict"], "inconclusive")

    def test_truncated_last_line_is_inconclusive(self):
        lines = [json.dumps(init()), json.dumps(call("Skill", "a", skill="assistant-docs")), '{"type": "resu']
        events = load_events(lines)
        self.assertEqual(score(events, {"required": ["assistant-docs"]}, ROOT)["verdict"], "inconclusive")

    def test_unreadable_line_does_not_hide_an_earlier_mutation(self):
        lines = [json.dumps(init()), json.dumps(call("Edit", "e")), "not json"]
        self.assertEqual(score(load_events(lines), {"required": ["assistant-docs"]}, ROOT)["verdict"], "fail")


def fake_install(home):
    (home / ".claude" / "skills" / "assistant-x").mkdir(parents=True)
    (home / ".claude" / "skills" / "assistant-x" / "SKILL.md").write_text("---\nname: assistant-x\ndescription: Does x.\n---\n\nBody\n")
    (home / ".claude" / "tools" / "progress").mkdir(parents=True)
    (home / ".claude" / "tools" / "progress" / "operating-guidance.md").write_text("Guidance\n")
    (home / ".claude" / "CLAUDE.md").write_text("# T\n\n## Skills\n\n- Use skills.\n\n## Other\n\nNo.\n")


class Generator(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve() / "plugins"
        self.root.mkdir()
        for name, replacement in (("install_into", fake_install), ("source_state", lambda: ("abc123", True))):
            patcher = mock.patch.object(generate_plugin, name, replacement)
            patcher.start()
            self.addCleanup(patcher.stop)

    def build(self, name="a", **options):
        return generate(self.root / name, allowed_root=self.root, **options)

    def test_output_outside_allowed_root_is_refused(self):
        self.assertEqual(checked_output(self.root / "a", self.root), self.root / "a")
        for bad in (self.root, self.root.parent / "other", self.root / ".." / "other", Path.home() / ".claude"):
            with self.assertRaises(ValueError, msg=bad):
                checked_output(bad, self.root)

    def test_symlink_out_of_the_root_is_refused(self):
        outside = self.root.parent / "outside"
        outside.mkdir()
        (self.root / "link").symlink_to(outside)
        with self.assertRaises(ValueError):
            checked_output(self.root / "link" / "a", self.root)

    def test_generate_applies_the_guard_itself(self):
        with self.assertRaises(ValueError):
            generate(self.root.parent / "other", allowed_root=self.root)

    def test_default_root_is_the_plugins_directory(self):
        expected = generate_plugin.REPO / ".codex" / "skill-activation" / "plugins"
        self.assertEqual(generate_plugin.ALLOWED_OUTPUT_ROOT, expected)
        with self.assertRaises(ValueError):
            checked_output(expected.parent / "probe")

    def test_existing_directory_without_a_manifest_is_kept(self):
        keep = self.root / "keep"
        keep.mkdir()
        (keep / "results.txt").write_text("evidence")
        with self.assertRaises(ValueError):
            self.build("keep")
        self.assertEqual((keep / "results.txt").read_text(), "evidence")

    def test_generated_plugin_can_be_replaced(self):
        self.build()
        (self.root / "a" / "stale.txt").write_text("old")
        self.build()
        self.assertFalse((self.root / "a" / "stale.txt").exists())

    def test_failed_build_keeps_the_old_plugin_and_leaves_nothing_behind(self):
        first = self.build()
        with mock.patch.object(generate_plugin, "source_state", side_effect=OSError("no git")):
            with self.assertRaises(OSError):
                self.build()
        self.assertEqual(tree_hash(self.root / "a"), first["tree_sha256"])
        self.assertEqual([path.name for path in self.root.iterdir()], ["a"])

    def test_plugin_layout_and_hook_shape(self):
        self.build()
        output = self.root / "a"
        self.assertEqual(json.loads((output / ".claude-plugin" / "plugin.json").read_text())["name"], "af")
        self.assertTrue((output / "skills" / "assistant-x" / "SKILL.md").is_file())
        self.assertTrue((output / "tools" / "progress" / "operating-guidance.md").is_file())
        context = json.loads((output / "hooks" / "session-context.json").read_text())["hookSpecificOutput"]
        self.assertEqual((context["hookEventName"], context["additionalContext"]), ("SessionStart", "- Use skills."))
        hook = json.loads((output / "hooks" / "hooks.json").read_text())["hooks"]["SessionStart"][0]["hooks"][0]
        self.assertIn("${CLAUDE_PLUGIN_ROOT}/hooks/session-context.json", hook["command"])

    def test_manifest_identifies_the_packaged_tree(self):
        first = self.build()
        self.assertEqual((first["source_commit"], first["source_dirty"], first["listing_condition"]), ("abc123", True, "isolated"))
        output = self.root / "a"
        self.assertEqual(tree_hash(output), first["tree_sha256"])
        (output / "skills" / "assistant-x" / "SKILL.md").write_text("changed body")
        self.assertNotEqual(tree_hash(output), first["tree_sha256"])
        self.build()
        self.assertEqual(tree_hash(output), first["tree_sha256"])
        self.assertNotEqual(self.build(guidance_override="- Other.")["guidance_sha256"], first["guidance_sha256"])

    def test_description_hash_tracks_descriptions_and_ignores_stubs(self):
        isolated = self.build("a")
        crowded = self.build("b", stubs=40)
        self.assertEqual(isolated["description_sha256"], crowded["description_sha256"])
        self.assertEqual((crowded["listing_condition"], crowded["stubs"]), ("crowded", 40))
        self.assertEqual(len(list((self.root / "b" / "skills").glob("stub-*/SKILL.md"))), 40)
        skill = self.root / "a" / "skills" / "assistant-x" / "SKILL.md"
        before = generate_plugin.description_hash(self.root / "a" / "skills")
        skill.write_text("---\nname: assistant-x\ndescription: Does y.\n---\n")
        self.assertNotEqual(generate_plugin.description_hash(self.root / "a" / "skills"), before)

    def test_only_defined_stub_counts_are_accepted(self):
        for stubs in (-1, 5, 41):
            with self.assertRaises(ValueError, msg=stubs):
                self.build(stubs=stubs)

    def test_empty_guidance_override_is_an_error(self):
        for text in ("", "  \n"):
            with self.assertRaises(ValueError):
                self.build(guidance_override=text)

    def test_guidance_is_only_the_skills_section(self):
        text = "# T\n\n## Skills\n\n- Use skills.\n\n## Other\n\nNo.\n"
        self.assertEqual(skills_guidance(text), "- Use skills.")
        with self.assertRaises(ValueError):
            skills_guidance("# T\n\n## Other\n\nNo.\n")


class InstallerEnvironment(unittest.TestCase):
    def test_installer_gets_a_minimal_environment(self):
        secrets = {"ANTHROPIC_API_KEY": "x", "GH_TOKEN": "x", "CODEX_HOME": "/real", "SSH_AUTH_SOCK": "/s", "CLAUDE_CONFIG_DIR": "/real"}
        with mock.patch.dict(os.environ, secrets), mock.patch.object(generate_plugin.subprocess, "run") as run:
            generate_plugin.install_into(Path("/tmp/home"))
        environment = run.call_args.kwargs["env"]
        self.assertEqual(set(environment), {"HOME", "PATH", "TMPDIR"})
        self.assertEqual(environment["HOME"], "/tmp/home")


class CommandLine(unittest.TestCase):
    def test_main_applies_the_output_guard(self):
        with mock.patch.object(sys, "argv", ["generate_plugin.py", "--output", "/tmp/not-allowed"]), \
                mock.patch.object(generate_plugin, "install_into") as install:
            with self.assertRaises(ValueError):
                generate_plugin.main()
        install.assert_not_called()


class Suite(unittest.TestCase):
    def test_committed_suite_is_valid(self):
        problems, facts = suite.validate_all()
        self.assertEqual(problems, [])
        self.assertEqual(facts["uncovered_pairs"], 0)

    def test_committed_suite_is_valid_when_the_home_name_is_an_ordinary_word(self):
        for home in ("/root", "/home/runner"):
            with self.subTest(home=home), mock.patch.object(suite, "PRIVATE_TEXT", suite.private_text(home, "")):
                self.assertEqual(suite.validate_all()[0], [])

    def test_private_text_matches_the_home_path_and_named_terms_only(self):
        pattern = suite.private_text("/root", "alice, Example Corp, @bob")
        for text in ("see /root/.ssh", "cd /root", "ask Alice", "from example corp", "ping @bob now", "/Users/x", "key sk-abcdefgh1234"):
            self.assertTrue(pattern.search(text), text)
        for text in ("find the root cause", "/rootfs/bin", "alicetown", "the test runner", "a risk-assessment step"):
            self.assertIsNone(pattern.search(text), text)

    def test_routing_data_matches_the_spec_table(self):
        routing = suite.load_routing()
        self.assertEqual(suite.routing_problems(routing), [])
        changed = json.loads(json.dumps(routing))
        changed["rows"]["review"]["required"] = ["assistant-docs"]
        self.assertEqual(len(suite.routing_problems(changed)), 1)
        del changed["rows"]["telos"]
        self.assertEqual(len(suite.routing_problems(changed)), 2)

    def test_resolve_applies_union_and_precedence(self):
        routing = suite.load_routing()
        data = {"prefixes": {"p": {"turns": [["user", "x"]]}}}
        both = suite.resolve({"rows": ["ci_known", "skill_change"], "prefix": "p"}, data, routing)
        self.assertEqual(both["required"], ["assistant-skill-creator", "assistant-verification", "assistant-workflow"])
        self.assertEqual(both["optional"], ["assistant-review"])
        forbids = suite.resolve({"rows": ["thinking"], "prefix": "p", "forbidden": ["assistant-workflow"]}, data, routing)
        self.assertEqual(forbids["forbidden"], ["assistant-workflow"])
        forbidden_beats_optional = suite.resolve({"rows": ["prepare"], "prefix": "p", "forbidden": ["assistant-thinking"]}, data, routing)
        self.assertNotIn("assistant-thinking", forbidden_beats_optional["optional"])
        self.assertEqual(suite.resolve({"rows": ["none"], "prefix": "p"}, data, routing)["forbidden"], "*")

    def test_compaction_kind_comes_from_the_prefix(self):
        routing = suite.load_routing()
        data = {"prefixes": {"a": {"compacted": True, "turns": [["user", "x"]]},
                             "b": {"compacted": True, "activated": ["assistant-workflow"], "turns": [["user", "x"]]},
                             "c": {"compacted": True, "activated": ["assistant-research"], "turns": [["user", "x"]]}}}
        kinds = [suite.resolve({"rows": ["resume"], "prefix": name}, data, routing)["compaction_kind"] for name in "abc"]
        self.assertEqual(kinds, ["never_activated", "activated_before", "never_activated"])

    def test_every_resolved_case_is_accepted_by_the_scorer(self):
        routing = suite.load_routing()
        for name in suite.SETS:
            data = suite.load_set(name)
            for case in data["cases"]:
                score([init(), result()], suite.resolve(case, data, routing), ROOT)

    def test_uncovered_pairs_reports_a_gap(self):
        cases = [{"dims": ["small", "new", "terse", "none", "code"]}]
        missing = suite.uncovered_pairs(cases)
        self.assertIn("size=large phase=approval", missing)
        self.assertNotIn("size=small phase=new", missing)

    def test_materialized_case_has_the_host_format(self):
        with tempfile.TemporaryDirectory() as name:
            (Path(name) / "generation.json").write_text("{}")
            out = Path(name) / "evals"
            selected = suite.materialize("development", ["d-seed-resume-compacted"], False, out)
            self.assertEqual(len(selected), 1)
            directory = out / "d-seed-resume-compacted"
            self.assertIn("Go ahead with P1 now.", (directory / "prompt.md").read_text())
            self.assertIn("runs: 1", (directory / "prompt.md").read_text())
            self.assertNotIn("Bash", (directory / "prompt.md").read_text())
            self.assertIn("history_file: history.jsonl", (directory / "case.yaml").read_text())
            self.assertIn("scaffold_script: fixture.sh", (directory / "case.yaml").read_text())
            rows = [json.loads(line) for line in (directory / "history.jsonl").read_text().splitlines()]
            self.assertEqual(rows[0]["subtype"], "compact_boundary")
            self.assertEqual(rows[1]["parentUuid"], rows[0]["uuid"])
            self.assertEqual(rows[2]["parentUuid"], rows[1]["uuid"])
            self.assertTrue(rows[1]["isCompactSummary"])
            with self.assertRaises(ValueError):
                suite.materialize("development", ["no-such-case"], False, out)
            with self.assertRaises(ValueError):
                suite.materialize("development", [], False, Path(name) / "other")

    def test_seed_selection(self):
        with tempfile.TemporaryDirectory() as name:
            (Path(name) / "generation.json").write_text("{}")
            selected = suite.materialize("development", [], True, Path(name) / "evals")
            self.assertTrue(selected and all(case.get("seed") for case in selected))

    def test_materialize_refuses_an_evals_directory_outside_a_generated_plugin(self):
        with tempfile.TemporaryDirectory() as name:
            tracked = Path(name) / "tools" / "evals"
            tracked.mkdir(parents=True)
            (tracked / "keep.txt").write_text("keep")
            with self.assertRaises(ValueError):
                suite.materialize("development", [], True, tracked)
            self.assertTrue((tracked / "keep.txt").is_file())

    def build_workspace(self, directory, name, key):
        suite.materialize_case({"id": "x", "prompt": "p", "prefix": key}, suite.load_set(name), Path(directory) / "case")
        workspace = Path(directory) / "workspace"
        workspace.mkdir()
        completed = subprocess.run(["bash", str(Path(directory) / "case" / "fixture.sh")], cwd=workspace, capture_output=True, text=True,
                                   env={"PATH": os.environ["PATH"], "HOME": directory})
        self.assertEqual(completed.returncode, 0, completed.stderr)
        # bash exits 0 on a lost heredoc terminator and swallows the lines after it.
        self.assertNotIn("here-document", completed.stderr)
        return workspace

    def test_every_prefix_setup_runs_in_the_fixture(self):
        for name in suite.SETS:
            for key in suite.load_set(name)["prefixes"]:
                with self.subTest(prefix=f"{name}/{key}"), tempfile.TemporaryDirectory() as directory:
                    self.build_workspace(directory, name, key)

    def test_setups_produce_the_state_their_prefix_claims(self):
        export = [("src/report.py", 'format="csv"'), ("src/report.py", "ValueError"), ("tests/test_report.py", "test_unknown_format"), ("tests/test_report.py", "test_render_is_fast")]
        expected = {
            ("development", "compacted"): [("src/sync_job.py", "max_retries=None"), ("tasks/retry-limit.md", "P1 stop at the limit")],
            ("development", "building"): [("src/sync_job.py", "on_item=None")],
            ("development", "compacted_active"): [("src/report.py", 'format="csv"')],
            ("development", "unprocessed"): [("tests/test_report.py", "test_report_title"), ("docs/specs/export.md", "title case"), ("docs/plans/export-plan.md", "report titles")],
            ("development", "pr_open_export"): export,
            ("heldout", "compacted_active"): [("tasks/report-header.md", "P1 write the header"), ("src/report.py", "header=None")],
            ("heldout", "building"): [("src/report.py", 'format="csv"'), ("src/report_cli.py", "fmt=")],
            ("heldout", "skill_building"): [("skills/assistant-demo/SKILL.md", 'description: "Formats demo reports as tables')],
            ("heldout", "review_back"): export,
        }
        have_setup = {(name, key) for name in suite.SETS for key, prefix in suite.load_set(name)["prefixes"].items() if prefix.get("setup")}
        self.assertEqual(set(expected), have_setup)
        for (name, key), checks in expected.items():
            with self.subTest(prefix=f"{name}/{key}"), tempfile.TemporaryDirectory() as directory:
                workspace = self.build_workspace(directory, name, key)
                for path, text in checks:
                    self.assertIn(text, (workspace / path).read_text(), path)

    def test_skill_building_setup_replaces_only_the_description(self):
        with tempfile.TemporaryDirectory() as directory:
            text = (self.build_workspace(directory, "heldout", "skill_building") / "skills/assistant-demo/SKILL.md").read_text()
            self.assertIn("name: assistant-demo", text)
            self.assertEqual(text.count("description:"), 1)
            self.assertEqual(text.count("---"), 2)
            self.assertNotIn("Use for explicit demo", text)

    def test_export_setup_commits_on_a_branch(self):
        for name, key in (("development", "pr_open_export"), ("heldout", "review_back")):
            with self.subTest(prefix=f"{name}/{key}"), tempfile.TemporaryDirectory() as directory:
                workspace = self.build_workspace(directory, name, key)
                environment = {"PATH": os.environ["PATH"], "HOME": directory}
                log = subprocess.run(["git", "log", "--format=%s"], cwd=workspace, capture_output=True, text=True, env=environment).stdout
                self.assertIn("Add report export", log)
                branch = subprocess.run(["git", "branch", "--show-current"], cwd=workspace, capture_output=True, text=True, env=environment).stdout
                self.assertEqual(branch.strip(), "export-reports")

    def test_paths_named_by_cases_and_prefixes_exist(self):
        pattern = re.compile(r"(?:src|tests|docs|tools|skills|tasks|tickets)/[\w./-]+")
        for name in suite.SETS:
            data = suite.load_set(name)
            named = {}
            for case in data["cases"]:
                named.setdefault(case["prefix"], set()).update(pattern.findall(case["prompt"]))
            for key, paths in named.items():
                paths |= set(pattern.findall(json.dumps(data["prefixes"][key]["turns"])))
                with self.subTest(prefix=f"{name}/{key}"), tempfile.TemporaryDirectory() as directory:
                    workspace = self.build_workspace(directory, name, key)
                    for path in paths:
                        self.assertTrue((workspace / path.rstrip(".")).exists(), path)

    def test_prefix_shared_across_sets_is_a_problem(self):
        shared = {"turns": [["user", "x"]]}
        original = suite.load_set

        def load(name):
            data = json.loads(json.dumps(original(name)))
            data["prefixes"]["shared"] = shared
            return data

        with mock.patch.object(suite, "load_set", load):
            self.assertIn("prefix shared across sets: shared", suite.validate_all()[0])

    def test_compaction_kind_is_empty_without_a_requirement(self):
        data = {"prefixes": {"a": {"compacted": True, "turns": [["user", "x"]]}}}
        self.assertEqual(suite.resolve({"rows": ["typo"], "prefix": "a"}, data, suite.load_routing())["compaction_kind"], "")

    def test_freeze_covers_routing_and_fixture(self):
        with tempfile.TemporaryDirectory() as name:
            routing = Path(name) / "routing.json"
            with mock.patch.object(suite, "HERE", Path(name)):
                routing.write_text("{}")
                first = suite.heldout_hash()
                routing.write_text('{"changed": true}')
                self.assertNotEqual(suite.heldout_hash(), first)

    def test_freeze_refuses_to_overwrite_a_different_freeze(self):
        with tempfile.TemporaryDirectory() as name:
            hash_file = Path(name) / "heldout.sha256"
            hash_file.write_text("0" * 64)
            with mock.patch.object(suite, "HELDOUT_HASH", hash_file), mock.patch.object(sys, "stdout", io.StringIO()):
                with mock.patch.object(sys, "argv", ["suite.py", "freeze"]):
                    self.assertEqual(suite.main(), 1)
                self.assertEqual(hash_file.read_text(), "0" * 64)
                with mock.patch.object(sys, "argv", ["suite.py", "freeze", "--refreeze"]):
                    self.assertEqual(suite.main(), 0)
                self.assertEqual(hash_file.read_text().strip(), suite.heldout_hash())

    def test_neighbour_case_must_be_able_to_fail_on_the_neighbour(self):
        case = {"id": "x", "neighbour": ["assistant-review", "assistant-skill-creator"]}
        self.assertIsNone(suite.neighbour_problem(case, {"required": ["assistant-review"], "forbidden": ["assistant-skill-creator"]}))
        self.assertIsNone(suite.neighbour_problem(case, {"required": ["assistant-skill-creator"], "forbidden": ["assistant-review"]}))
        self.assertIn("x", suite.neighbour_problem(case, {"required": ["assistant-review"], "forbidden": []}))

    def test_fixture_runs_and_stays_in_its_workspace(self):
        with tempfile.TemporaryDirectory() as name:
            workspace = Path(name) / "workspace"
            workspace.mkdir()
            completed = subprocess.run(["bash", str(suite.FIXTURE)], cwd=workspace, capture_output=True, text=True,
                                       env={"PATH": os.environ["PATH"], "HOME": name})
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual([path.name for path in Path(name).iterdir()], ["workspace"])
            self.assertTrue((workspace / "skills" / "assistant-demo" / "SKILL.md").is_file())
            status = subprocess.run(["git", "status", "--short"], cwd=workspace, capture_output=True, text=True, env={"PATH": os.environ["PATH"], "HOME": name})
            self.assertEqual(status.stdout.strip(), "M src/report.py")


class ExistingActivationCases(unittest.TestCase):
    POSITIVE = {"skill": "assistant-docs", "should_activate": True}
    NEGATIVE = {"skill": "assistant-docs", "should_activate": False}
    DOCS = {"name": "Skill", "tool": "a", "skill": "af:assistant-docs"}

    def trace(self, *skills, end=None):
        events = [init()] + [call("Skill", f"s{index}", skill=f"af:{skill}") for index, skill in enumerate(skills)]
        return events + [end or result()]

    def verdict(self, case, *skills, end=None):
        return activation.score(self.trace(*skills, end=end), case, ROOT)["verdict"]

    def test_all_activation_cases_load_with_unique_ids(self):
        cases = activation.load_cases()
        self.assertEqual(len(cases), 71)
        self.assertEqual(len({case["id"] for case in cases}), 71)
        self.assertEqual(sum(case["should_activate"] for case in cases), 45)
        self.assertEqual(sum(case["run_only"] for case in cases), 2)

    def test_positive_counts_every_activation_so_order_does_not_matter(self):
        self.assertEqual(self.verdict(self.POSITIVE, "assistant-workflow", "assistant-docs"), "pass")
        self.assertEqual(self.verdict(self.POSITIVE, "assistant-workflow"), "fail")

    def test_negative_counts_only_the_first_activation(self):
        self.assertEqual(self.verdict(self.NEGATIVE, "assistant-workflow", "assistant-docs"), "pass")
        self.assertEqual(self.verdict(self.NEGATIVE, "assistant-docs"), "fail")
        self.assertEqual(self.verdict(self.NEGATIVE), "pass")

    def test_reaching_the_limit_is_inconclusive_unless_activation_already_decides(self):
        limit = {"type": "result", "subtype": "error_max_turns", "is_error": True}
        self.assertEqual(self.verdict(self.POSITIVE, end=limit), "inconclusive")
        self.assertEqual(self.verdict(self.NEGATIVE, end=limit), "inconclusive")
        self.assertEqual(self.verdict(self.POSITIVE, "assistant-docs", end=limit), "pass")
        self.assertEqual(self.verdict(self.NEGATIVE, "assistant-docs", end=limit), "fail")
        self.assertEqual(self.verdict(self.POSITIVE, "assistant-workflow", end=limit), "inconclusive")
        self.assertEqual(self.verdict(self.NEGATIVE, "assistant-workflow", end=limit), "pass")

    def test_an_unreliable_run_is_inconclusive_even_after_an_activation(self):
        error = {"type": "result", "subtype": "error_during_execution", "is_error": True}
        self.assertEqual(self.verdict(self.POSITIVE, "assistant-docs", end=error), "inconclusive")
        self.assertEqual(self.verdict(self.NEGATIVE, "assistant-docs", end=error), "inconclusive")
        truncated = [init(), call("Skill", "s", skill="af:assistant-docs")]
        self.assertEqual(activation.score(truncated, self.POSITIVE, ROOT)["verdict"], "inconclusive")

    def test_a_mutation_after_activation_still_decides(self):
        trace = [init(), call("Skill", "s", skill="af:assistant-docs"), call("Edit", "e", file_path="a.py"), result()]
        self.assertEqual(activation.score(trace, self.POSITIVE, ROOT)["verdict"], "pass")
        self.assertEqual(activation.score(trace, self.NEGATIVE, ROOT)["verdict"], "fail")

    def listing(self, root, content):
        logs = Path(root) / "config" / "projects" / "cwd"
        logs.mkdir(parents=True)
        (logs / "s.jsonl").write_text("not json\n" + json.dumps({"attachment": {"type": "skill_listing", "content": content}}) + "\n")

    def test_listing_validity(self):
        with tempfile.TemporaryDirectory() as plugin:
            (Path(plugin) / "skills" / "assistant-a").mkdir(parents=True)
            (Path(plugin) / "skills" / "assistant-b").mkdir()
            for content, expected in (("- af:assistant-a: does a\n- af:assistant-b: does b", True), ("- af:assistant-a: does a\n- af:assistant-b", False), ("- af:assistant-a: does a", False)):
                with tempfile.TemporaryDirectory() as root:
                    self.listing(root, content)
                    self.assertEqual(activation.listing_valid(root, plugin), expected)
            with tempfile.TemporaryDirectory() as root:
                self.assertIsNone(activation.listing_valid(root, plugin))

    def rows(self, arm, case, verdicts):
        return [{"arm": arm, "model": "m", "case": case, "verdict": verdict} for verdict in verdicts]

    def test_majority_uses_conclusive_repeats_and_a_tie_is_inconclusive(self):
        results = activation.case_results(self.rows("a", "x", ["pass", "pass", "fail"]) + self.rows("a", "y", ["pass", "fail", "inconclusive"]) + self.rows("a", "z", ["inconclusive"] * 3))
        self.assertEqual(results, {("a", "m", "x"): "pass", ("a", "m", "y"): "inconclusive", ("a", "m", "z"): "inconclusive"})

    def test_regression_needs_both_baselines_to_pass(self):
        rows = (self.rows("b1", "x", ["pass"]) + self.rows("b2", "x", ["pass"]) + self.rows("c", "x", ["fail"])
                + self.rows("b1", "y", ["pass"]) + self.rows("b2", "y", ["fail"]) + self.rows("c", "y", ["fail"])
                + self.rows("b1", "z", ["pass"]) + self.rows("b2", "z", ["pass"]) + self.rows("c", "z", ["inconclusive"]))
        self.assertEqual(activation.regressions(rows, ["b1", "b2"], "c"), ([("m", "x")], [("m", "y")]))

    def full_rows(self, arm, **extra):
        return [dict({"arm": arm, "model": "m", "case": case, "repeat": 0, "verdict": "pass", "suite_sha256": "s", "host_version": "1", "tree_sha256": "base" if arm in ("b1", "b2") else arm,
                      "listing_condition": "isolated", "batch": arm, "run_only": False, "stop": "final_answer"}, **extra) for case in ("x", "y")]

    def compare_problems(self, rows):
        return activation.comparison_problems(rows, ["b1", "b2"], "c")

    def test_baselines_must_be_the_same_plugin(self):
        rows = self.full_rows("b1") + self.full_rows("b2", tree_sha256="other") + self.full_rows("c")
        self.assertEqual(self.compare_problems(rows), ["m: the baselines are different plugins"])

    def test_comparable_arms_have_no_problems(self):
        self.assertEqual(self.compare_problems(self.full_rows("b1") + self.full_rows("b2") + self.full_rows("c")), [])

    def test_an_arm_that_was_not_measured_cannot_be_compared(self):
        self.assertEqual(self.compare_problems(self.full_rows("b1") + self.full_rows("b2")), ["c has no valid rows"])
        self.assertEqual(self.compare_problems(self.full_rows("c")), ["b1 has no valid rows", "b2 has no valid rows"])
        self.assertEqual(self.compare_problems(self.full_rows("b1") + self.full_rows("b2") + self.full_rows("c")[:1]), ["m: arms did not run the same cases and repeats"])
        rows = self.full_rows("b1") + self.full_rows("b2") + self.full_rows("c")
        self.assertTrue(activation.comparison_problems(rows, ["b1", "b1"], "c"))
        self.assertTrue(activation.comparison_problems(rows, ["b1", "c"], "c"))

    def test_mixed_inputs_and_duplicates_cannot_be_compared(self):
        base = self.full_rows("b1") + self.full_rows("b2")
        self.assertEqual(self.compare_problems(base + self.full_rows("c", host_version="2")), ["m: host_version differs between arms"])
        self.assertEqual(self.compare_problems(base + self.full_rows("c", suite_sha256="t")), ["m: suite_sha256 differs between arms"])
        self.assertEqual(self.compare_problems(base + self.full_rows("c", listing_condition="crowded")), ["m: listing_condition differs between arms"])
        one, two = self.full_rows("c"), self.full_rows("c", tree_sha256="other")
        self.assertEqual(self.compare_problems(base + [one[0], two[1]]), ["m: c mixes plugin trees"])
        self.assertIn("the same trial appears more than once", self.compare_problems(base + self.full_rows("c") * 2))

    def report_output(self, rows, *arguments):
        with tempfile.TemporaryDirectory() as name:
            path = Path(name) / "results.jsonl"
            path.write_text("".join(json.dumps(dict(row, set="activation")) + "\n" for row in rows))
            with mock.patch.object(sys, "argv", ["report.py", str(path), *arguments]), mock.patch.object(sys, "stdout", io.StringIO()) as out:
                return report.main(), out.getvalue()

    def valid(self, arm, **extra):
        return self.full_rows(arm, batch_valid=True, **extra)

    def test_report_says_not_evaluated_when_the_candidate_batch_was_invalid(self):
        rows = self.valid("b1") + self.valid("b2") + [dict(row, batch_valid=False) for row in self.full_rows("c")]
        code, text = self.report_output(rows, "--baselines", "b1,b2", "--candidate", "c")
        self.assertEqual(code, 1)
        self.assertIn("Regressions on c: not evaluated. c has no valid rows.", text)
        self.assertNotIn("none. Baselines", text)

    def test_report_states_how_many_cases_it_compared(self):
        rows = self.valid("b1") + self.valid("b2") + [dict(row, verdict="fail") for row in self.valid("c")]
        code, text = self.report_output(rows, "--baselines", "b1,b2", "--candidate", "c", "--json")
        printed = json.loads(text)
        self.assertEqual(code, 0)
        self.assertEqual((printed["compared_cases"], printed["total_cases"]), (2, 71))
        self.assertEqual(printed["regressions"], [["m", "x"], ["m", "y"]])
        self.assertEqual(printed["activation_cases"]["c / m"]["fail"], 2)
        self.assertEqual(printed["groups"], {})

    def test_inconclusive_cases_do_not_count_as_compared(self):
        none = [dict(row, verdict="inconclusive", stop="listing_invalid") for row in self.valid("c")]
        code, text = self.report_output(self.valid("b1") + self.valid("b2") + none, "--baselines", "b1,b2", "--candidate", "c")
        self.assertEqual(code, 1)
        self.assertIn("not evaluated. no case is conclusive in all three arms.", text)
        partial = [none[0], self.valid("c")[1]]
        code, text = self.report_output(self.valid("b1") + self.valid("b2") + partial, "--baselines", "b1,b2", "--candidate", "c", "--json")
        self.assertEqual((code, json.loads(text)["compared_cases"]), (0, 1))

    def test_report_warns_about_a_mixed_arm(self):
        _, text = self.report_output(self.valid("a") + self.valid("a", repeat=1, host_version="2"))
        self.assertIn("WARNING: this arm mixes host_version.", text)

    def test_baselines_and_candidate_go_together(self):
        with mock.patch.object(sys, "stderr", io.StringIO()), self.assertRaises(SystemExit):
            self.report_output(self.valid("a"), "--baselines", "a,b")

    def test_crowded_plugin_is_refused_for_this_set(self):
        with tempfile.TemporaryDirectory() as name:
            base = Path(name).resolve()
            plugin = make_plugin(base, "arm")
            manifest = json.loads((plugin / "generation.json").read_text())
            arguments = ["run_trials.py", "--batch", "b", "--arm", "arm", "--set", "activation", "--repeats", "1", "--max-cost-usd", "2", "--authorized-calls", "71"]
            crowded = dict(manifest, listing_condition="crowded")
            with mock.patch.object(run_trials, "PLUGINS", base), mock.patch.object(run_trials, "load_manifest", return_value=(plugin, crowded)), \
                    mock.patch.object(sys, "stderr", io.StringIO()) as err, mock.patch.object(sys, "stdout", io.StringIO()), mock.patch.object(sys, "argv", arguments):
                self.assertEqual(run_trials.main(), 2)
            self.assertIn("isolated condition only", err.getvalue())

    def test_fresh_case_has_no_history(self):
        with tempfile.TemporaryDirectory() as name:
            suite.materialize_case(activation.load_cases()[0], {"prefixes": {}}, Path(name) / "case", 3)
            self.assertFalse((Path(name) / "case" / "history.jsonl").exists())
            self.assertNotIn("history_file", (Path(name) / "case" / "case.yaml").read_text())
            self.assertIn("runs: 3", (Path(name) / "case" / "prompt.md").read_text())

    def test_batch_runs_without_a_probe_and_checks_each_listing(self):
        with tempfile.TemporaryDirectory() as name:
            base = Path(name).resolve()
            (base / "tmp").mkdir()
            plugin = make_plugin(base, "arm")
            calls = []

            def fake_eval(binary, plugin_path, model, repeats, cap, output, environment, key):
                names = sorted(path.name for path in (plugin_path / "evals").iterdir())
                calls.append(names)
                output.mkdir(parents=True)
                cases = []
                for index, case_id in enumerate(names):
                    root = base / "tmp" / f"e-run{index}"
                    (root / "out").mkdir(parents=True)
                    trace = root / "out" / "trace.jsonl"
                    first = dict(init(), plugin_path=str(plugin_path))
                    trace.write_text("".join(json.dumps(event) + "\n" for event in [first, call("Skill", "s", skill="af:assistant-workflow"), result()]))
                    if index == 0:
                        self.listing(root, "- af:assistant-workflow: Prepare, plan and build.")
                    cases.append({"name": case_id, "arms": {"with": [{"tracePath": str(trace), "turns": 1, "costUsd": 0.1}]}})
                (output / "aggregate-result.json").write_text(json.dumps({"cases": cases, "costUsd": 0.2, "partial": False, "claudeVersion": "9.9"}))
                return 0, None

            ids = [case["id"] for case in activation.load_cases() if case["skill"] == "assistant-workflow"][:2]
            arguments = ["run_trials.py", "--batch", "b", "--arm", "arm", "--set", "activation", "--ids", ",".join(ids), "--repeats", "1",
                         "--max-cost-usd", "2", "--authorized-calls", "2", "--run"]
            with mock.patch.object(run_trials, "PLUGINS", base), mock.patch.object(run_trials, "RESULTS", base / "results"), \
                    mock.patch.object(run_trials, "RUN_ROOT_PARENTS", (base / "tmp",)), mock.patch.object(run_trials, "read_key", return_value="k-secret"), \
                    mock.patch.object(run_trials, "claude_binary", return_value="claude"), mock.patch.object(run_trials, "run_eval", fake_eval), \
                    mock.patch.object(run_trials, "run_refusals", return_value=[]), mock.patch.object(sys, "stdout", io.StringIO()), \
                    mock.patch.object(sys, "argv", arguments):
                self.assertEqual(run_trials.main(), 0)
            self.assertEqual(len(calls), 1)
            rows = [json.loads(line) for line in (base / "results" / "b" / "results.jsonl").read_text().splitlines()]
            self.assertEqual([row["stop"] for row in sorted(rows, key=lambda row: row["case"])], ["final_answer", "listing_invalid"])
            self.assertEqual(rows[0]["set"], "activation")
            self.assertTrue(all(row["batch_valid"] for row in rows))
            self.assertEqual(list((base / "tmp").iterdir()), [])
            self.assertFalse((plugin / "evals").exists())


class HostPin(unittest.TestCase):
    def install(self, home, version):
        path = Path(home) / "Library/Application Support/Claude/claude-code" / version / "abc/claude.app/Contents/MacOS/claude"
        path.parent.mkdir(parents=True)
        path.write_text("")
        return str(path)

    def test_pinned_version_wins_and_a_missing_one_is_refused(self):
        with tempfile.TemporaryDirectory() as home:
            old = self.install(home, "1.0.0")
            new = self.install(home, "2.0.0")
            os.utime(old, (1, 1))
            with mock.patch.object(Path, "home", return_value=Path(home)):
                self.assertEqual(run_trials.claude_binary(), new)
                self.assertEqual(run_trials.claude_binary("1.0.0"), old)
                with self.assertRaises(RuntimeError):
                    run_trials.claude_binary("3.0.0")


class CandidateDescriptions(unittest.TestCase):
    def make_skill(self, root, body="---\nname: assistant-x\ndescription: \"Old text.\"\nrequires:\n  - assistant-y\n---\n\ndescription: body line stays\n"):
        skill = Path(root) / "assistant-x"
        skill.mkdir()
        (skill / "SKILL.md").write_text(body)
        return skill / "SKILL.md"

    def test_only_the_frontmatter_line_changes(self):
        with tempfile.TemporaryDirectory() as name:
            path = self.make_skill(name)
            generate_plugin.apply_descriptions(name, {"assistant-x": "New \"quoted\" text with \\1."})
            self.assertEqual(path.read_text(), '---\nname: assistant-x\ndescription: "New \\"quoted\\" text with \\\\1."\nrequires:\n  - assistant-y\n---\n\ndescription: body line stays\n')
            self.assertEqual(run_trials.skill_description(path), 'New "quoted" text with \\1.')

    def test_bad_descriptions_are_refused(self):
        with tempfile.TemporaryDirectory() as name:
            self.make_skill(name)
            for candidate in ({"assistant-none": "x"}, {"other": "x"}, {"assistant-x": ""}, {"assistant-x": "a\nb"}, {"assistant-x": "x" * 1025}):
                with self.assertRaises(ValueError):
                    generate_plugin.apply_descriptions(name, candidate)

    def test_a_name_cannot_leave_the_skills_directory(self):
        with tempfile.TemporaryDirectory() as name:
            outside = Path(name) / "real" / "assistant-x"
            outside.mkdir(parents=True)
            target = outside / "SKILL.md"
            target.write_text('---\ndescription: "Original."\n---\n')
            copy = Path(name) / "plugin" / "skills"
            copy.mkdir(parents=True)
            self.make_skill(copy)
            with self.assertRaises(ValueError):
                generate_plugin.apply_descriptions(copy, {"assistant-x/../../../real/assistant-x": "Changed."})
            self.assertIn("Original.", target.read_text())

    def test_only_descriptions_that_differ_are_reported_as_changed(self):
        with tempfile.TemporaryDirectory() as name:
            self.make_skill(name)
            self.assertEqual(generate_plugin.apply_descriptions(name, {"assistant-x": "Old text."}), [])
            self.assertEqual(generate_plugin.apply_descriptions(name, {"assistant-x": "New text."}), ["assistant-x"])

    def test_folded_or_absent_description_is_refused(self):
        for body in ("---\nname: assistant-x\n---\nbody\n", "---\ndescription: >-\n  Old text.\n---\nbody\n", "---\ndescription: |\n  Old text.\n---\nbody\n", "---\ndescription:\n  Old text.\n---\nbody\n"):
            with tempfile.TemporaryDirectory() as name:
                path = self.make_skill(name, body)
                with self.assertRaises(ValueError):
                    generate_plugin.apply_descriptions(name, {"assistant-x": "x"})
                self.assertEqual(path.read_text(), body)


class Runner(unittest.TestCase):
    def test_call_count_includes_the_listing_probe(self):
        self.assertEqual(run_trials.expected_calls(4, 1), 5)
        self.assertEqual(run_trials.expected_calls(60, 3), 181)

    def test_child_environment_is_an_allowlist(self):
        source = {"PATH": "/bin", "HOME": "/h", "GH_TOKEN": "x", "GITHUB_TOKEN": "x", "SSH_AUTH_SOCK": "/s", "ANTHROPIC_AUTH_TOKEN": "x",
                  "CLAUDE_CODE_OAUTH_TOKEN": "x", "AWS_SECRET_ACCESS_KEY": "x", "SOME_OTHER": "x"}
        environment = run_trials.child_environment("deepseek-flash", "k", source)
        for name in ("GH_TOKEN", "GITHUB_TOKEN", "SSH_AUTH_SOCK", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "AWS_SECRET_ACCESS_KEY", "SOME_OTHER"):
            self.assertNotIn(name, environment)
        self.assertEqual(environment["ANTHROPIC_API_KEY"], "k")
        self.assertEqual(environment["SLASH_COMMAND_TOOL_CHAR_BUDGET"], run_trials.LISTING_BUDGET)

    def test_command_grants_no_bash_and_holds_no_key(self):
        command = run_trials.eval_command("claude", "/p", "m", 3, 2.5, "/o")
        self.assertNotIn("Bash", " ".join(command))
        self.assertEqual(command[command.index("--allow-tools") + 1:], ["Edit", "Write"])
        self.assertEqual(command[command.index("--runs") + 1], "3")
        self.assertEqual(command[:4], ["claude", "plugin", "eval", "/p"])

    def test_run_eval_scrubs_the_child_and_keeps_only_a_bounded_reason(self):
        environment = {"ANTHROPIC_API_KEY": "secret-value"}
        with tempfile.TemporaryDirectory() as name, mock.patch.object(run_trials.subprocess, "run") as child:
            child.return_value = subprocess.CompletedProcess([], 1, stderr="first\nbad secret-value " + "x" * 500 + "\n")
            code, reason = run_trials.run_eval("claude", "/p", "m", 2, 1.0, Path(name) / "out", environment, "secret-value")
            arguments, options = child.call_args
            self.assertIs(options["env"], environment)
            self.assertEqual(options["stdin"], subprocess.DEVNULL)
            self.assertEqual(options["stdout"], subprocess.DEVNULL)
            self.assertEqual(options["stderr"], subprocess.PIPE)
            self.assertNotIn("secret-value", " ".join(arguments[0]))
            self.assertEqual(code, 1)
            self.assertNotIn("secret-value", reason)
            self.assertLessEqual(len(reason), 200)
            child.return_value = subprocess.CompletedProcess([], 0, stderr="noise")
            self.assertEqual(run_trials.run_eval("claude", "/p", "m", 2, 1.0, Path(name) / "other", environment, "k"), (0, None))

    def test_host_reason_ignores_the_report_path_line(self):
        self.assertEqual(run_trials.host_reason(2, "budget reached\nReport: /x/report.html\n", "k"), "budget reached")
        self.assertIsNone(run_trials.host_reason(2, "Report: /x/report.html\n", "k"))

    def test_malformed_aggregates_are_flagged(self):
        with tempfile.TemporaryDirectory() as name:
            path = Path(name) / "aggregate-result.json"
            for text in ('{"cases": null, "costUsd": 0.5}', '{"cases": [{"name": "a", "arms": []}], "costUsd": 0.5}',
                         '{"cases": [{"name": "a", "arms": {"with": 3}}], "costUsd": 0.5}'):
                path.write_text(text)
                self.assertEqual(run_trials.read_aggregate(Path(name)), {"malformed": True, "costUsd": 0.5})
            path.write_text('{"cases": [], "costUsd": "free"}')
            self.assertIsNone(run_trials.read_aggregate(Path(name))["costUsd"])
            path.write_text("not json")
            self.assertEqual(run_trials.read_aggregate(Path(name)), {})

    def test_scan_skips_a_fifo_instead_of_blocking(self):
        with tempfile.TemporaryDirectory() as name:
            os.mkfifo(Path(name) / "pipe")
            self.assertEqual(run_trials.scan_for_secret(name, "secret-value"), (0, 0))

    def test_run_roots_lists_only_host_named_directories(self):
        with tempfile.TemporaryDirectory() as name:
            parent = Path(name).resolve()
            (parent / "e-abc123").mkdir()
            (parent / "e-file").write_text("x")
            (parent / "important").mkdir()
            (parent / "e-with-dash").mkdir()
            (parent / "e-link").symlink_to(parent / "important")
            with mock.patch.object(run_trials, "RUN_ROOT_PARENTS", (parent,)):
                self.assertEqual(run_trials.run_roots(), {parent / "e-abc123"})

    def test_a_secret_in_a_sealed_directory_is_found_after_unsealing(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name) / "e-abc123"
            (root / "sealed" / "inner").mkdir(parents=True)
            (root / "sealed" / "inner" / "file").write_text("x secret-value y")
            (root / "sealed" / "inner" / "file").chmod(0)
            (root / "sealed" / "inner").chmod(0)
            (root / "sealed").chmod(0)
            self.assertEqual(run_trials.scan_for_secret(root, "secret-value"), (0, 1))
            run_trials.unseal(root)
            self.assertEqual(run_trials.scan_for_secret(root, "secret-value"), (1, 0))
            self.assertEqual(run_trials.scan_for_secret(root, "other-value"), (0, 0))

    def test_unseal_does_not_follow_links_out_of_the_run(self):
        with tempfile.TemporaryDirectory() as name:
            outside = Path(name) / "outside"
            outside.mkdir()
            outside.chmod(0o500)
            root = Path(name) / "e-abc123"
            root.mkdir()
            (root / "link").symlink_to(outside)
            run_trials.unseal(root)
            self.assertEqual(stat.S_IMODE(outside.stat().st_mode), 0o500)

    def test_tokens_include_subagents_and_are_null_when_absent(self):
        event = {"type": "result", "usage": {"input_tokens": 1}, "modelUsage": {"a": {"inputTokens": 5, "outputTokens": 2, "cacheReadInputTokens": 3},
                                                                                "b": {"inputTokens": 7, "outputTokens": 1, "cacheCreationInputTokens": 4}}}
        self.assertEqual(run_trials.trace_tokens([event]), {"input": 12, "output": 3, "cache_read": 3, "cache_creation": 4})
        self.assertIsNone(run_trials.trace_tokens([init()]))

    def test_listing_probe_compares_the_quote_and_fails_on_any_tool_call(self):
        with tempfile.TemporaryDirectory() as name:
            skill = Path(name) / "skills" / "assistant-workflow"
            skill.mkdir(parents=True)
            (skill / "SKILL.md").write_text('---\nname: assistant-workflow\ndescription: "Prepare, plan and build."\n---\n')
            quoted = {"type": "assistant", "message": {"content": [{"type": "text", "text": "af:assistant-workflow: Prepare, plan\nand build."}]}}
            other = {"type": "assistant", "message": {"content": [{"type": "text", "text": "NAME ONLY"}]}}
            self.assertTrue(run_trials.listing_probe_passed([quoted], name))
            self.assertFalse(run_trials.listing_probe_passed([other], name))
            self.assertFalse(run_trials.listing_probe_passed([call("Read", "r", file_path="x"), quoted], name))

    def test_load_manifest_refuses_a_changed_plugin(self):
        with tempfile.TemporaryDirectory() as name:
            plugin = make_plugin(Path(name), "arm")
            with mock.patch.object(run_trials, "PLUGINS", Path(name)):
                self.assertEqual(run_trials.load_manifest("arm")[0], plugin.resolve())
                (plugin / "evals").mkdir()
                (plugin / "evals" / "a").write_text("materialized cases do not change identity")
                run_trials.load_manifest("arm")
                (plugin / "skills" / "assistant-workflow" / "SKILL.md").write_text("changed")
                with self.assertRaises(ValueError):
                    run_trials.load_manifest("arm")
                with self.assertRaises(ValueError):
                    run_trials.load_manifest("absent")

    def test_heldout_needs_a_matching_freeze(self):
        with tempfile.TemporaryDirectory() as name:
            hash_file = Path(name) / "heldout.sha256"
            with mock.patch.object(suite, "HELDOUT_HASH", hash_file):
                self.assertEqual(run_trials.run_refusals("development"), [])
                self.assertEqual(len(run_trials.run_refusals("heldout")), 1)
                hash_file.write_text(suite.heldout_hash() + "\n")
                self.assertEqual(run_trials.run_refusals("heldout"), [])
                hash_file.write_text("0" * 64)
                self.assertEqual(len(run_trials.run_refusals("heldout")), 1)

    def test_tree_hash_ignores_materialized_evals(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            (root / "a.txt").write_text("a")
            before = tree_hash(root)
            (root / "evals" / "case").mkdir(parents=True)
            (root / "evals" / "case" / "prompt.md").write_text("x")
            self.assertEqual(tree_hash(root), before)


def make_plugin(parent, arm):
    plugin = parent / arm
    skill = plugin / "skills" / "assistant-workflow"
    skill.mkdir(parents=True)
    (skill / "SKILL.md").write_text('---\nname: assistant-workflow\ndescription: "Prepare, plan and build."\n---\n')
    manifest = {"source_commit": "c", "source_dirty": True, "tree_sha256": tree_hash(plugin), "description_sha256": "d", "guidance_sha256": "g",
                "listing_condition": "isolated", "stubs": 0}
    (plugin / "generation.json").write_text(json.dumps(manifest))
    return plugin


class RunnerBatch(unittest.TestCase):
    """Drive main --run with a fake host, so collection, scoring and cleanup run without a model."""
    IDS = ["d-seed-approve", "d-seed-ci"]
    QUOTE = {"type": "assistant", "message": {"content": [{"type": "text", "text": "Prepare, plan and build."}]}}
    RESULT = {"type": "result", "subtype": "success", "is_error": False, "modelUsage": {"m": {"inputTokens": 5, "outputTokens": 2}}}

    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.base = Path(directory.name).resolve()
        (self.base / "tmp").mkdir()
        self.plugin = make_plugin(self.base, "arm")
        self.calls = []
        self.probe_events = [init(), self.QUOTE, self.RESULT]
        self.case_runs = None
        self.fail_cases = False
        self.leak = False
        self.foreign = False
        self.host_exit = 0
        self.probe_partial = False
        self.aggregate_text = None
        self.versions = ["9.9", "9.9"]
        self.interrupt = None
        patches = [mock.patch.object(run_trials, "PLUGINS", self.base), mock.patch.object(run_trials, "RESULTS", self.base / "results"),
                   mock.patch.object(run_trials, "RUN_ROOT_PARENTS", (self.base / "tmp",)), mock.patch.object(run_trials, "read_key", return_value="secret-value"),
                   mock.patch.object(run_trials, "claude_binary", return_value="claude"), mock.patch.object(run_trials, "run_eval", self.fake_eval),
                   mock.patch.object(run_trials, "run_refusals", return_value=[]), mock.patch.object(sys, "stdout", io.StringIO()), mock.patch.object(sys, "stderr", io.StringIO())]
        for patcher in patches:
            patcher.start()
            self.addCleanup(patcher.stop)

    def run_root(self, events):
        root = self.base / "tmp" / f"e-run{len(list((self.base / 'tmp').iterdir()))}"
        (root / "out").mkdir(parents=True)
        (root / "sealed").mkdir()
        (root / "sealed").chmod(0)
        trace = root / "out" / "trace.jsonl"
        events = [dict(events[0], plugin_path=str(self.plugin.resolve()))] + events[1:]
        trace.write_text("".join(json.dumps(event) + "\n" for event in events))
        if self.leak:
            (root / "out" / "leak").write_text("secret-value")
        return str(trace)

    def fake_eval(self, binary, plugin, model, repeats, cap, output, environment, key):
        names = sorted(path.name for path in (plugin / "evals").iterdir())
        self.calls.append({"cases": names, "repeats": repeats, "cap": cap, "front": (plugin / "evals" / names[0] / "prompt.md").read_text()})
        output.mkdir(parents=True)
        probing = names == [run_trials.LISTING_PROBE_ID]
        if names == [run_trials.LISTING_PROBE_ID]:
            cases = [{"name": names[0], "arms": {"with": [{"tracePath": self.run_root(self.probe_events)}]}}]
            cost = 0.25
        else:
            if self.foreign:
                other = self.base / "tmp" / "e-foreign"
                (other / "out").mkdir(parents=True)
                (other / "out" / "trace.jsonl").write_text("{}")
            if self.interrupt:
                self.run_root([init()])
                raise self.interrupt
            if self.fail_cases:
                self.run_root([init()])
                raise RuntimeError("host failed")
            events = [init(), call("Skill", "a", skill="af:assistant-workflow"), call("Edit", "e"), self.RESULT]
            cases = self.case_runs if self.case_runs is not None else [
                {"name": name, "arms": {"with": [{"tracePath": self.run_root(events), "turns": 3, "costUsd": 0.1, "durationSeconds": 9} for _ in range(repeats)]}} for name in names]
            cost = 0.5
        version = self.versions[0 if probing else 1]
        text = json.dumps({"cases": cases, "costUsd": cost, "partial": probing and self.probe_partial, "claudeVersion": version})
        (output / "aggregate-result.json").write_text(self.aggregate_text if self.aggregate_text and not probing else text)
        return self.host_exit, ("host said no" if self.host_exit else None)

    def main(self, repeats=1, authorized=None):
        arguments = ["run_trials.py", "--batch", "b", "--arm", "arm", "--set", "development", "--ids", ",".join(self.IDS), "--repeats", str(repeats),
                     "--max-cost-usd", "2", "--authorized-calls", str(authorized if authorized is not None else 2 * repeats + 1), "--run"]
        with mock.patch.object(sys, "argv", arguments):
            return run_trials.main()

    def rows(self):
        return [json.loads(line) for line in (self.base / "results" / "b" / "results.jsonl").read_text().splitlines()]

    def summary(self):
        return json.loads((self.base / "results" / "b" / "summary.json").read_text())

    def assert_clean(self):
        self.assertEqual(list((self.base / "tmp").iterdir()), [])
        self.assertFalse((self.base / "results" / "b" / "raw").exists())
        self.assertFalse((self.plugin / "evals").exists())

    def test_probe_runs_first_once_then_cases_with_the_remaining_cap(self):
        self.assertEqual(self.main(repeats=2), 0)
        self.assertEqual([(call_["cases"], call_["repeats"], call_["cap"]) for call_ in self.calls],
                         [([run_trials.LISTING_PROBE_ID], 1, 2.0), (sorted(self.IDS), 2, 1.75)])
        self.assertIn("runs: 1", self.calls[0]["front"])
        self.assertIn("runs: 2", self.calls[1]["front"])
        rows = self.rows()
        self.assertEqual(len(rows), 4)
        self.assertTrue(all(row["batch_valid"] for row in rows))
        self.assertEqual(rows[0]["tokens"]["input"], 5)
        self.assertEqual(rows[0]["host_version"], "9.9")
        self.assertEqual(self.summary()["observed_runs"], 5)
        self.assert_clean()

    def test_results_hold_no_prompt_or_response_text(self):
        self.assertEqual(self.main(), 0)
        text = (self.base / "results" / "b" / "results.jsonl").read_text() + (self.base / "results" / "b" / "summary.json").read_text()
        self.assertNotIn("Prepare, plan and build", text)
        for case in suite.load_set("development")["cases"]:
            if case["id"] in self.IDS:
                self.assertNotIn(case["prompt"], text)

    def test_failed_probe_stops_the_batch_and_marks_it_invalid(self):
        self.probe_events = [init(), {"type": "assistant", "message": {"content": [{"type": "text", "text": "NAME ONLY"}]}}]
        self.assertEqual(self.main(), 4)
        self.assertEqual(len(self.calls), 1)
        rows = self.rows()
        self.assertEqual({row["stop"] for row in rows}, {"not_run"})
        self.assertFalse(any(row["batch_valid"] for row in rows))
        self.assert_clean()

    def test_host_failure_still_cleans_up_and_writes_rows(self):
        self.fail_cases = True
        self.assertEqual(self.main(), 4)
        self.assertEqual(self.summary()["failure"], "RuntimeError")
        self.assertEqual(len(self.rows()), 2)
        self.assert_clean()

    def test_missing_and_extra_runs_invalidate_the_batch(self):
        trace = None
        self.case_runs = [{"name": self.IDS[0], "arms": {"with": [{"tracePath": trace}]}},
                          {"name": "not-selected", "arms": {"with": [{"tracePath": trace}]}}]
        self.assertEqual(self.main(), 4)
        stops = {row["case"]: row["stop"] for row in self.rows()}
        self.assertEqual(stops, {self.IDS[0]: "no_trace", self.IDS[1]: "not_run"})
        self.assertTrue(all(row["phase"] for row in self.rows()))
        self.assertFalse(self.summary()["valid"])

    def test_bad_token_data_loses_only_its_own_row(self):
        bad = {"type": "result", "subtype": "success", "is_error": False, "modelUsage": {"m": None}}
        events = [init(), call("Skill", "a", skill="af:assistant-workflow"), call("Edit", "e")]
        self.case_runs = [{"name": self.IDS[0], "arms": {"with": [{"tracePath": self.run_root(events + [bad])}]}},
                          {"name": self.IDS[1], "arms": {"with": [{"tracePath": self.run_root(events + [self.RESULT])}]}}]
        self.main()
        stops = {row["case"]: row["stop"] for row in self.rows()}
        self.assertEqual(stops, {self.IDS[0]: "score_error", self.IDS[1]: "mutation"})

    def test_an_unreadable_trace_loses_only_its_own_row(self):
        events = [init(), call("Skill", "a", skill="af:assistant-workflow"), call("Edit", "e"), self.RESULT]
        self.case_runs = [{"name": self.IDS[0], "arms": {"with": [{"tracePath": str(self.base / "gone" / "trace.jsonl")}]}},
                          {"name": self.IDS[1], "arms": {"with": [{"tracePath": self.run_root(events)}]}}]
        self.main()
        stops = {row["case"]: row["stop"] for row in self.rows()}
        self.assertEqual(stops[self.IDS[0]], "score_error")
        self.assertEqual(stops[self.IDS[1]], "mutation")

    def test_nonzero_probe_exit_spends_no_case_calls(self):
        self.host_exit = 1
        self.assertEqual(self.main(), 4)
        self.assertEqual(len(self.calls), 1)
        self.assertFalse(self.summary()["valid"])
        self.assertEqual(self.summary()["probe_reason"], "host said no")

    def test_partial_probe_spends_no_case_calls(self):
        self.probe_partial = True
        self.assertEqual(self.main(), 4)
        self.assertEqual(len(self.calls), 1)

    def test_malformed_case_aggregate_writes_an_invalid_summary(self):
        self.aggregate_text = '{"cases": null, "costUsd": 0.5, "claudeVersion": "9.9"}'
        self.assertEqual(self.main(), 4)
        self.assertTrue(self.summary()["malformed_aggregate"])
        self.assertEqual(self.summary()["cost_usd"], 0.75)
        self.assertEqual(len(self.rows()), 2)
        self.assert_clean()

    def test_changed_or_missing_host_version_invalidates_the_batch(self):
        for versions in (["9.9", "10.0"], [None, None]):
            self.versions = versions
            shutil.rmtree(self.base / "results", ignore_errors=True)
            self.assertEqual(self.main(), 4)
            self.assertFalse(self.summary()["valid"])

    def test_interrupt_records_the_batch_cleans_up_and_still_stops(self):
        for interrupt in (KeyboardInterrupt(), SystemExit(143)):
            self.interrupt = interrupt
            shutil.rmtree(self.base / "results", ignore_errors=True)
            with self.assertRaises(type(interrupt)):
                self.main()
            self.assertEqual(self.summary()["failure"], type(interrupt).__name__)
            self.assertEqual(len(self.rows()), 2)
            self.assert_clean()

    def test_a_directory_from_another_eval_during_the_batch_is_left_and_counted(self):
        self.foreign = True
        self.assertEqual(self.main(), 4)
        self.assertEqual(self.summary()["foreign_run_directories_left"], 1)
        self.assertEqual([path.name for path in (self.base / "tmp").iterdir()], ["e-foreign"])

    def test_a_held_lock_refuses_the_batch(self):
        (self.base / "results").mkdir()
        with open(self.base / "results" / ".lock", "w") as lock:
            run_trials.fcntl.flock(lock, run_trials.fcntl.LOCK_EX)
            self.assertEqual(self.main(), 2)
        self.assertEqual(self.calls, [])

    def test_failed_probe_in_crowded_continues_and_records_the_finding(self):
        manifest = self.plugin / "generation.json"
        manifest.write_text(json.dumps({**json.loads(manifest.read_text()), "listing_condition": "crowded"}))
        self.probe_events = [init(), {"type": "assistant", "message": {"content": [{"type": "text", "text": "NAME ONLY"}]}}]
        self.assertEqual(self.main(), 0)
        self.assertEqual(len(self.calls), 2)
        self.assertIs(self.summary()["listing_probe_passed"], False)

    def test_bad_cost_cap_is_refused(self):
        for cap in ("0", "-1", "inf", "nan"):
            arguments = ["run_trials.py", "--batch", "b", "--arm", "arm", "--set", "development", "--ids", self.IDS[0], "--repeats", "1",
                         "--max-cost-usd", cap, "--authorized-calls", "2"]
            with mock.patch.object(sys, "argv", arguments), self.assertRaises(ValueError):
                run_trials.main()

    def test_probe_tokens_are_in_the_summary(self):
        self.main()
        self.assertEqual(self.summary()["probe_tokens"]["input"], 5)

    def test_key_in_output_is_counted_and_never_printed(self):
        self.leak = True
        self.assertEqual(self.main(), 4)
        self.assertGreater(self.summary()["key_found_in_output"], 0)
        self.assertNotIn("secret-value", sys.stdout.getvalue() + sys.stderr.getvalue())
        self.assertNotIn("secret-value", (self.base / "results" / "b" / "summary.json").read_text())
        self.assert_clean()

    def test_other_run_directories_are_left_alone(self):
        other = self.base / "tmp" / "e-other"
        (other / "out").mkdir(parents=True)
        self.main()
        self.assertEqual(list((self.base / "tmp").iterdir()), [other])

    def test_wrong_authorization_makes_no_call_and_writes_nothing(self):
        for authorized in (2, 4):
            self.assertEqual(self.main(authorized=authorized), 2)
        self.assertEqual(self.calls, [])
        self.assertFalse((self.base / "results").exists())

    def test_plan_only_makes_no_call(self):
        arguments = ["run_trials.py", "--batch", "b", "--arm", "arm", "--set", "development", "--ids", ",".join(self.IDS), "--repeats", "1",
                     "--max-cost-usd", "2", "--authorized-calls", "3"]
        with mock.patch.object(sys, "argv", arguments):
            self.assertEqual(run_trials.main(), 0)
        self.assertEqual(self.calls, [])
        plan = sys.stdout.getvalue()
        for field in ("listing_condition", "stub_description_chars", "permission_mode"):
            self.assertIn(field, plan)

    def test_refusal_makes_no_call(self):
        with mock.patch.object(run_trials, "run_refusals", return_value=["held-out not frozen"]):
            self.assertEqual(self.main(), 2)
        self.assertEqual(self.calls, [])


class Reporting(unittest.TestCase):
    def row(self, verdict, **extra):
        base = {"arm": "a", "case": "c", "repeat": 0, "verdict": verdict, "stop": "mutation", "required": ["assistant-workflow", "assistant-verification"],
                "prefix_activated": [], "missing": [], "activated": [], "extra": [], "forbidden_hits": [], "forbidden": [], "phase": "approval", "model": "m",
                "listing_condition": "isolated", "kind": "positive", "compaction_kind": "", "batch_valid": True, "set": "development"}
        return {**base, **extra}

    def test_counts_keep_denominators_and_leave_out_inconclusive(self):
        rows = [self.row("pass", activated=["assistant-workflow", "assistant-verification"]),
                self.row("fail", missing=["assistant-verification"], activated=["assistant-workflow"]),
                self.row("fail", missing=["assistant-workflow", "assistant-verification"]),
                self.row("inconclusive", stop="unclassified_bash", missing=["assistant-workflow"])]
        summary = report.summarize(rows)
        self.assertEqual(summary["pass_rate"], {"hits": 1, "total": 3})
        self.assertEqual(summary["inconclusive"], {"hits": 1, "total": 4})
        self.assertEqual(summary["recall_by_skill"]["assistant-workflow"], {"hits": 2, "total": 3})
        self.assertEqual(summary["recall_by_skill"]["assistant-verification"], {"hits": 1, "total": 3})
        self.assertEqual(summary["set_completeness"], {"hits": 1, "total": 3})
        self.assertEqual(summary["no_skill_before_mutation"], {"hits": 1, "total": 3})
        self.assertIn("Pass rate 1/3", report.render(summary))

    def test_only_compaction_activated_before_is_left_out_of_the_pass_rate(self):
        satisfied = {"required": ["assistant-workflow"], "prefix_activated": ["assistant-workflow"]}
        summary = report.summarize([self.row("pass", compaction_kind="activated_before", **satisfied)])
        self.assertEqual(summary["recall_by_skill"], {})
        self.assertEqual(summary["pass_rate"], {"hits": 0, "total": 0})
        self.assertEqual(summary["compaction_not_graded"], 1)
        self.assertEqual(report.summarize([self.row("pass", **satisfied)])["pass_rate"], {"hits": 1, "total": 1})

    def test_no_skill_cases_are_not_in_the_pass_rate(self):
        summary = report.summarize([self.row("pass", required=[], kind="negative_none", forbidden="*")])
        self.assertEqual(summary["pass_rate"], {"hits": 0, "total": 0})
        self.assertEqual(summary["negatives"]["negative_none"], {"hits": 1, "total": 1})

    def test_precision_counts_a_forbidden_skill_once_using_real_scorer_output(self):
        routing = suite.load_routing()
        data = {"prefixes": {"p": {"turns": [["user", "x"]]}}}
        resolved = suite.resolve({"rows": ["none"], "prefix": "p"}, data, routing)
        verdict = score([init(), call("Skill", "a", skill="af:assistant-research"), result()], resolved, ROOT)
        self.assertEqual(verdict["forbidden_hits"], ["assistant-research"])
        summary = report.summarize([self.row(verdict["verdict"], required=[], kind="negative_none", forbidden="*", activated=verdict["activated"],
                                             extra=verdict["extra"], forbidden_hits=verdict["forbidden_hits"], stop=verdict["stop"])])
        self.assertEqual(summary["precision"], {"hits": 0, "total": 1})
        self.assertEqual(summary["false_activation"], {"hits": 1, "total": 1})
        self.assertEqual(summary["extra_activations"], 0)

    def test_compaction_reports_reinvocation_separately(self):
        summary = report.summarize([self.row("pass", compaction_kind="activated_before", reinvoked=["assistant-workflow"]),
                                    self.row("pass", compaction_kind="activated_before", reinvoked=[]),
                                    self.row("fail", compaction_kind="never_activated", missing=["assistant-workflow"])])
        self.assertEqual(summary["compaction_reinvoked"], {"hits": 1, "total": 2})
        self.assertEqual(summary["compaction_never_activated"], {"hits": 0, "total": 1})

    def test_groups_keep_arms_models_and_conditions_apart(self):
        groups = report.by_group([self.row("pass"), self.row("fail", arm="b"), self.row("fail", model="n"), self.row("fail", listing_condition="crowded"),
                                  self.row("fail", set="heldout")])
        self.assertEqual(len(groups), 5)
        self.assertEqual(groups["development / a / m / isolated"]["pass_rate"], {"hits": 1, "total": 1})
        self.assertFalse(groups["development / a / m / isolated"]["mixed_inputs"])

    def test_mixed_inputs_are_flagged(self):
        group = report.by_group([self.row("pass", host_version="1"), self.row("pass", host_version="2")])["development / a / m / isolated"]
        self.assertTrue(group["mixed_inputs"])
        self.assertIn("WARNING", report.render(group))

    def test_invalid_batches_are_left_out_and_named(self):
        with tempfile.TemporaryDirectory() as name:
            path = Path(name) / "results.jsonl"
            rows = [self.row("pass", batch="good"), self.row("fail", batch="bad", batch_valid=False)]
            path.write_text("".join(json.dumps(row) + "\n" for row in rows))
            with mock.patch.object(sys, "argv", ["report.py", str(path), "--json"]), mock.patch.object(sys, "stdout", io.StringIO()) as out:
                self.assertEqual(report.main(), 0)
            printed = json.loads(out.getvalue())
            self.assertEqual(printed["invalid_batches"], ["bad"])
            self.assertEqual(printed["groups"]["development / a / m / isolated"]["trials"], 1)

    def test_not_run_rows_keep_their_phase_and_count_as_inconclusive(self):
        summary = report.summarize([self.row("inconclusive", stop="not_run", tokens=None)])
        self.assertEqual(summary["by_phase"], {"approval": {"pass": 0, "fail": 0, "inconclusive": 1}})
        self.assertEqual(summary["trials_without_tokens"], 1)


if __name__ == "__main__":
    unittest.main()
