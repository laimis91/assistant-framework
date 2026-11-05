#!/usr/bin/env python3
"""Score one `claude plugin eval` trace against docs/specs/skill-activation.md.

Pure: makes no model calls, runs nothing, and treats every trace value as data.
It never opens a path found in a trace. A malformed trace scores as inconclusive.

Usage: score_trace.py TRACE.jsonl CASE.json --installed-root PLUGIN_ROOT

CASE.json fields: required, optional, excused (lists of skill names), forbidden
(a list, or "*" for every skill), prefix_activated (list), compaction_kind
("", "never_activated" or "activated_before"), allow_commands (list of command
prefixes the case adds to the read-only allowlist).
"""
import argparse
import json
import posixpath
import re
import sys

MUTATING_TOOLS = {"Edit", "Write", "NotebookEdit"}
READ_COMMANDS = {"cd", "ls", "rg", "grep", "cat", "head", "tail", "wc", "pwd", "echo", "true"}
FILE_READERS = {"cat", "head", "tail"}
READ_GIT = {"status", "diff", "log", "show", "rev-parse", "ls-files", "blame"}
MUTATING_COMMANDS = {"rm", "mv", "cp", "touch", "mkdir", "rmdir", "chmod", "chown", "ln", "tee", "dd", "truncate"}
MUTATING_GIT = {"add", "am", "apply", "checkout", "cherry-pick", "clean", "clone", "commit", "fetch", "format-patch",
                "init", "merge", "mv", "pull", "push", "rebase", "reset", "restore", "revert", "rm", "stash", "switch", "tag"}
MUTATING_GH_PR = {"create", "merge", "edit", "close", "ready", "comment", "review"}
GIT_VALUE_OPTIONS = {"-C", "-c", "--config-env", "--git-dir", "--work-tree", "--namespace", "--exec-path"}
FIND_WRITERS = ("-delete", "-fprint", "-fls")
FIND_EXECUTORS = {"-exec", "-execdir", "-ok", "-okdir"}
RG_EXECUTORS = ("--pre", "--hostname-bin")
SHELLS = {"bash", "sh", "zsh"}
WRAPPERS = {"timeout", "sudo", "nohup", "nice"}
XARGS_VALUE_OPTIONS = {"-n", "-I", "-P", "-L", "-d", "-s", "-E"}
BRANCH_READ_OPTIONS = {"-a", "--all", "-r", "--remotes", "-v", "--verbose", "--color", "--no-color", "--column", "--no-column",
                       "--abbrev", "--no-abbrev", "-i", "--ignore-case", "--show-current"}
TAG_READ_OPTIONS = {"-n", "--column", "--no-column", "--color", "--no-color", "-i", "--ignore-case"}
LISTING_OPTIONS = {"-l", "--list", "--merged", "--no-merged", "--contains", "--no-contains", "--points-at", "--format", "--sort"}
BRANCH_WRITE_OPTIONS = {"-d", "-D", "--delete", "-m", "-M", "--move", "-c", "-C", "--copy", "-f", "--force", "-u",
                        "--set-upstream-to", "--unset-upstream", "--edit-description", "-t", "--track", "--no-track"}
TAG_WRITE_OPTIONS = {"-a", "--annotate", "-s", "--sign", "-u", "-d", "--delete", "-f", "--force", "-m", "--message", "-F", "--file", "-e"}
GIT_WRITING_SUBCOMMANDS = {"remote": {"add", "remove", "rm", "rename", "set-url", "set-head", "prune", "update"},
                           "submodule": {"add", "update", "init", "deinit", "sync"}}
GIT_CONFIG_READ_OPTIONS = ("--get", "--list", "-l")
GIT_CONFIG_WRITE_OPTIONS = ("--unset", "--remove-section", "--rename-section", "--replace-all", "--add")
GIT_CONFIG_VALUE_OPTIONS = {"-f", "--file", "--blob"}
LISTING_VALUE_OPTIONS = {"--sort", "--format", "--contains", "--no-contains", "--points-at"}
COMMAND_PREFIXES = {"do", "then", "else", "elif", "if", "while", "until", "{", "!", "time", "env", "command"}
PREFIXES_WITH_OPTIONS = {"time", "env", "command"}
OPERATORS = ("&>>", "<<<", "<<-", "&&", "||", ";;", "|&", "&>", ">>", ">&", ">|", "<>", "<<", "<&", "<(", ">(",
             ";", "|", "&", "(", ")", ">", "<")
SEPARATORS = {"&&", "||", ";;", "|&", ";", "|", "&"}
FILE_WRITE_OPERATORS = {">", ">>", ">|", "<>", "&>", "&>>"}
SAFE_REDIRECT_TARGETS = {"/dev/null", "/dev/stdout", "/dev/stderr", "/dev/tty"}
HEREDOC_OPERATORS = {"<<", "<<-"}
MAX_SUBSTITUTION_DEPTH = 20
SKILL_NAME = re.compile(r"^[A-Za-z0-9_-]+$")
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*\+?=")
SED_REGEX_ADDRESS = r"/(?:[^/\\]|\\.)*/"
SED_ADDRESS = re.compile(rf"^\s*(\d+|\$|{SED_REGEX_ADDRESS})?(\s*,\s*(\+?\d+|\$|{SED_REGEX_ADDRESS}))?\s*")
PLUGIN_ROOT_VARIABLE = re.compile(r"\$\{CLAUDE_PLUGIN_ROOT\}|\$CLAUDE_PLUGIN_ROOT\b")
REFUSED_BASH = "<tool_use_error>Error: No such tool available: Bash"
EXPANSION_FOLLOWERS = set("{_?!@#*-$")


class Parsed:
    """A shell command split into simple commands, with what could not be followed."""

    def __init__(self, depth=0):
        self.segments = []
        self.writes_file = False
        self.opaque = False
        self.depth = depth


def _balanced_end(command, start):
    """Return the index after the `)` closing a `$(` body, ignoring quotes, which heredocs break."""
    depth, index = 1, start
    while index < len(command):
        if command[index] == "(":
            depth += 1
        elif command[index] == ")":
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1
    return None


def _merge_body(body, parsed):
    if parsed.depth >= MAX_SUBSTITUTION_DEPTH:
        return
    nested = parse_bash(body, parsed.depth + 1)
    parsed.segments.extend(nested.segments)
    parsed.writes_file = parsed.writes_file or nested.writes_file


def _scan_substitution(command, index, parsed):
    """Handle `$(` or a backtick at index, reading its body. Return the next index, or None if it never closes."""
    parsed.opaque = True
    if command.startswith("$((", index):
        return _balanced_end(command, index + 2)
    if command[index] == "`":
        end = command.find("`", index + 1)
        _merge_body(command[index + 1:end] if end >= 0 else command[index + 1:], parsed)
        return end + 1 if end >= 0 else None
    end = _balanced_end(command, index + 2)
    _merge_body(command[index + 2:end - 1] if end else command[index + 2:], parsed)
    return end


def _expansion_at(command, index, in_double_quotes):
    """Return the length of a kept plugin-root variable, or 0 after marking any other expansion."""
    match = PLUGIN_ROOT_VARIABLE.match(command, index)
    if match:
        return len(match.group())
    return -1 if _is_expansion(command, index, in_double_quotes) else 0


def _is_expansion(command, index, in_double_quotes):
    follower = command[index + 1] if index + 1 < len(command) else ""
    if not in_double_quotes and follower in ("'", '"'):
        return True
    return follower.isalnum() or follower in EXPANSION_FOLLOWERS


def _scan_quoted(command, index, parsed):
    """Return (text, next index) for the quoted run at index, or (None, None) if it never closes."""
    quote = command[index]
    index += 1
    text = []
    while index < len(command):
        character = command[index]
        if character == quote:
            return "".join(text), index + 1
        if quote == '"' and character == "\\" and index + 1 < len(command):
            text.append(command[index + 1])
            index += 2
        elif quote == '"' and (character == "`" or command.startswith("$(", index)):
            index = _scan_substitution(command, index, parsed)
            if index is None:
                return None, None
        elif quote == '"' and character == "$":
            length = _expansion_at(command, index, True)
            if length > 0:
                text.append(command[index:index + length])
                index += length
            else:
                parsed.opaque = parsed.opaque or length < 0
                text.append(character)
                index += 1
        else:
            text.append(character)
            index += 1
    return None, None


def _scan_word(command, index, parsed):
    """Return (word, next index). A word that never closes is returned with next index None."""
    word = []
    while index < len(command):
        character = command[index]
        if character in " \t\n" or command.startswith(OPERATORS, index):
            break
        if character == "\\" and index + 1 < len(command):
            word.append(command[index + 1])
            index += 2
        elif character in "'\"":
            text, index = _scan_quoted(command, index, parsed)
            if index is None:
                return "".join(word), None
            word.append(text)
        elif character == "`" or command.startswith("$(", index):
            index = _scan_substitution(command, index, parsed)
            if index is None:
                return "".join(word), None
        elif character == "$":
            length = _expansion_at(command, index, False)
            if length > 0:
                word.append(command[index:index + length])
                index += length
            else:
                parsed.opaque = parsed.opaque or length < 0
                word.append(character)
                index += 1
        else:
            if character == "{":
                closing = command.find("}", index)
                if closing > 0 and ("," in command[index:closing] or ".." in command[index:closing]):
                    parsed.opaque = True
            word.append(character)
            index += 1
    return "".join(word), index


def _apply_redirect(operator, target, parsed):
    if operator in FILE_WRITE_OPERATORS:
        if target not in SAFE_REDIRECT_TARGETS:
            parsed.writes_file = True
    elif operator == ">&" and target not in SAFE_REDIRECT_TARGETS and target != "-" and not (target.isascii() and target.isdigit()):
        parsed.writes_file = True


def _skip_heredocs(command, index, delimiters):
    """Return the index of the newline ending the last heredoc body that starts after index."""
    for delimiter in delimiters:
        while index < len(command):
            end = command.find("\n", index + 1)
            line = command[index + 1:] if end < 0 else command[index + 1:end]
            index = len(command) if end < 0 else end
            if line.strip() == delimiter:
                break
    return index


def _skip_blanks(command, index):
    while index < len(command) and command[index] in " \t":
        index += 1
    return index


def _salvage(remainder, parsed):
    """After an unterminated quote, keep plain-word commands from the rest, so a later commit is still seen."""
    parsed.opaque = True
    for piece in re.split(r"[;&|\n]+", remainder):
        if piece.split():
            parsed.segments.append(piece.split())


def parse_bash(command, depth=0):
    """Scan with quoting kept, since `rg '>' src` is a read and `rg > src` is not.

    Parsing stops at anything unterminated and marks the result opaque, keeping what
    was read, so `git commit -m "$(cat <<'EOF'` is still known to be a commit.
    """
    parsed = Parsed(depth)
    command = command.replace("\\\n", "")
    current = []
    heredocs = []
    index = 0
    while index < len(command):
        character = command[index]
        if character == "\n":
            parsed.segments.append(current)
            current = []
            if heredocs:
                index = _skip_heredocs(command, index, heredocs)
                heredocs = []
            index += 1
        elif character in " \t":
            index += 1
        elif character == "#":
            newline = command.find("\n", index)
            index = len(command) if newline < 0 else newline
        else:
            operator = next((op for op in OPERATORS if command.startswith(op, index)), None)
            start = index
            if command.startswith("((", index):
                parsed.opaque = True
                index = _balanced_end(command, index + 1)
                if index is None:
                    _salvage(command[start:], parsed)
                    break
            elif operator is None:
                word, index = _scan_word(command, index, parsed)
                current.append(word)
                if index is None:
                    _salvage(command[start:], parsed)
                    break
                if word == "[[" and all(earlier in COMMAND_PREFIXES for earlier in current[:-1]):
                    current.pop()
                    parsed.opaque = True
                    closing = command.find("]]", index)
                    index = len(command) if closing < 0 else closing + 2
                elif word.isascii() and word.isdigit() and command.startswith((">", "<"), index):
                    current.pop()
            elif operator in SEPARATORS:
                parsed.segments.append(current)
                current = []
                index += len(operator)
            elif operator in ("(", ")", "<(", ">("):
                parsed.opaque = True
                parsed.segments.append(current)
                current = []
                index += len(operator)
            else:
                target, index = _scan_word(command, _skip_blanks(command, index + len(operator)), parsed)
                if operator in HEREDOC_OPERATORS:
                    parsed.opaque = True
                    heredocs.append(target)
                else:
                    _apply_redirect(operator, target, parsed)
                if index is None:
                    _salvage(command[start + len(operator):], parsed)
                    break
    parsed.segments.append(current)
    parsed.segments = [segment for segment in parsed.segments if segment]
    return parsed


def _option_names(arguments):
    """Return option names without values, with short clusters such as -ln split up."""
    names = []
    skip_value = False
    for argument in arguments:
        if skip_value:
            skip_value = False
        elif argument.startswith("--"):
            names.append(argument.split("=", 1)[0])
            skip_value = argument in LISTING_VALUE_OPTIONS
        elif argument.startswith("-") and len(argument) > 1:
            names.extend("-" + letter for letter in argument[1:] if not letter.isdigit())
    return names


def _classify_listing(arguments, read_options, write_options, listing_options=LISTING_OPTIONS):
    """Classify `git branch` or `git tag`, which list unless told to change something."""
    names = _option_names(arguments)
    if set(names) & write_options:
        return "mutation"
    if not set(names) <= read_options | listing_options:
        return "unclassified"
    if set(names) & listing_options or "--show-current" in names:
        return "read"
    return "mutation" if any(not argument.startswith("-") for argument in arguments) else "read"


def _classify_git_config(arguments):
    if any(argument.startswith(GIT_CONFIG_WRITE_OPTIONS) for argument in arguments):
        return "mutation"
    if any(argument.startswith(GIT_CONFIG_READ_OPTIONS) for argument in arguments):
        return "unclassified"
    positional, index = [], 0
    while index < len(arguments):
        if arguments[index] in GIT_CONFIG_VALUE_OPTIONS:
            index += 1
        elif not arguments[index].startswith("-"):
            positional.append(arguments[index])
        index += 1
    if positional[:1] in (["get"], ["list"]):
        return "unclassified"
    return "mutation" if len(positional) >= 2 else "unclassified"


def _classify_git(segment):
    index, has_config = 1, False
    while index < len(segment) and segment[index].startswith("-"):
        option = segment[index]
        has_config = has_config or option == "-c" or option.startswith("--config-env")
        index += 2 if option in GIT_VALUE_OPTIONS else 1
    sub = segment[index] if index < len(segment) else ""
    arguments = segment[index + 1:]
    if any(argument == "--output" or argument.startswith("--output=") for argument in arguments):
        return "mutation"
    if sub == "stash" and arguments[:1] in (["list"], ["show"]):
        kind = "read"
    elif sub == "tag":
        kind = _classify_listing(arguments, TAG_READ_OPTIONS, TAG_WRITE_OPTIONS, LISTING_OPTIONS | {"-n"})
    elif sub == "branch":
        kind = _classify_listing(arguments, BRANCH_READ_OPTIONS, BRANCH_WRITE_OPTIONS)
    elif sub == "config":
        kind = _classify_git_config(arguments)
    elif sub in GIT_WRITING_SUBCOMMANDS:
        kind = "mutation" if arguments[:1] and arguments[0] in GIT_WRITING_SUBCOMMANDS[sub] else "unclassified"
    elif sub == "worktree":
        kind = "read" if arguments[:1] == ["list"] else "mutation"
    elif sub in MUTATING_GIT:
        return "mutation"
    else:
        kind = "read" if sub in READ_GIT else "unclassified"
    return "unclassified" if has_config and kind == "read" else kind


def _sed_is_in_place(argument):
    if argument.startswith("--in-place"):
        return True
    return argument.startswith("-") and not argument.startswith("--") and ("i" in argument or "I" in argument)


def _sed_script_kind(script):
    """Read the command after the address: only a `w` command or `s///w` flag writes."""
    rest = script[SED_ADDRESS.match(script).end():]
    if rest.startswith("w"):
        return "mutation"
    if rest.startswith("s") and len(rest) > 1:
        parts = re.split(r"(?<!\\)" + re.escape(rest[1]), rest[2:])
        if len(parts) >= 3 and "w" in parts[2]:
            return "mutation"
        return "unclassified"
    return "read" if rest == "p" else "unclassified"


def _classify_sed(segment):
    arguments = segment[1:]
    if any(_sed_is_in_place(argument) for argument in arguments):
        return "mutation"
    plain = [argument for argument in arguments if not argument.startswith("-")]
    kind = _sed_script_kind(plain[0]) if plain else "unclassified"
    if kind == "mutation":
        return kind
    flags = [argument for argument in arguments if argument.startswith("-")]
    return "read" if kind == "read" and flags == ["-n"] else "unclassified"


def _mutation_only(segment):
    """Classify a command run by another one. Only a mutation is certain; the wrapper could do anything else."""
    return "mutation" if segment and _classify_segment(segment, ()) == "mutation" else "unclassified"


def _find_kind(segment):
    if any(token.startswith(FIND_WRITERS) for token in segment):
        return "mutation"
    starts = [index for index, token in enumerate(segment) if token in FIND_EXECUTORS]
    if not starts:
        return "read"
    for start in starts:
        body = segment[start + 1:]
        for index, token in enumerate(body):
            if token in (";", "+"):
                body = body[:index]
                break
        if _mutation_only(body) == "mutation":
            return "mutation"
    return "unclassified"


def _xargs_kind(arguments):
    index = 0
    while index < len(arguments) and arguments[index].startswith("-"):
        index += 2 if arguments[index] in XARGS_VALUE_OPTIONS else 1
    return _mutation_only(arguments[index:])


def _wrapper_kind(arguments):
    index = 0
    while index < len(arguments) and (arguments[index].startswith("-") or arguments[index][:1].isdigit()):
        index += 1
    return _mutation_only(arguments[index:])


def _shell_kind(arguments):
    for index, argument in enumerate(arguments):
        if not argument.startswith("-"):
            return "unclassified"
        if not argument.startswith("--") and "c" in argument:
            script = next((item for item in arguments[index + 1:] if not item.startswith("-")), "")
            return "mutation" if classify_bash(script) == "mutation" else "unclassified"
    return "unclassified"


def _classify_command(segment):
    name = segment[0]
    if name == "xargs":
        return _xargs_kind(segment[1:])
    if name in WRAPPERS:
        return _wrapper_kind(segment[1:])
    if name in SHELLS:
        return _shell_kind(segment[1:])
    if name == "git":
        return _classify_git(segment)
    if name == "gh":
        return "mutation" if len(segment) > 2 and segment[1] == "pr" and segment[2] in MUTATING_GH_PR else "unclassified"
    if name == "sed":
        return _classify_sed(segment)
    if name in MUTATING_COMMANDS:
        return "mutation"
    if name == "find":
        return _find_kind(segment)
    if name == "rg" and any(token == option or token.startswith(option + "=") for option in RG_EXECUTORS for token in segment):
        return "unclassified"
    return "read" if name in READ_COMMANDS else "unclassified"


def _strip_prefixes(segment):
    """Return (the command under any prefix, whether anything was stripped)."""
    rest = list(segment)
    while rest and (ASSIGNMENT.match(rest[0]) or rest[0] in COMMAND_PREFIXES):
        word = rest.pop(0)
        if word == "command" and rest[:1] in (["-v"], ["-V"]):
            return [], True
        while word in PREFIXES_WITH_OPTIONS and rest and rest[0].startswith("-"):
            rest.pop(0)
    stripped = len(rest) != len(segment)
    if rest and "/" in rest[0]:
        rest[0] = posixpath.basename(rest[0])
        stripped = True
    return rest, stripped


def _classify_segment(segment, allow):
    joined = " ".join(segment)
    if any(joined == prefix or joined.startswith(prefix + " ") for prefix in allow):
        return "read"
    if segment[0] == "command" and segment[1:2] in (["-v"], ["-V"]):
        return "read"
    rest, stripped = _strip_prefixes(segment)
    if not rest:
        return "unclassified"
    kind = _classify_command(rest)
    # A prefix or a path can change what a read command does, so only a mutation survives one.
    return "unclassified" if stripped and kind == "read" else kind


def _classification(parsed, allow):
    try:
        kinds = [_classify_segment(segment, allow) for segment in parsed.segments]
    except RecursionError:
        return "mutation" if parsed.writes_file else "unclassified"
    if parsed.writes_file or "mutation" in kinds:
        return "mutation"
    return "unclassified" if parsed.opaque or "unclassified" in kinds or not kinds else "read"


def classify_bash(command, allow=()):
    """Return read, mutation or unclassified. A known mutation wins over anything opaque."""
    return _classification(parse_bash(command), allow)


def _skill_from_path(path, installed_root, cwd):
    normal = posixpath.normpath(path)
    if cwd and (normal == cwd or normal.startswith(cwd.rstrip("/") + "/")):
        return None
    prefix = installed_root.rstrip("/") + "/skills/"
    if not normal.startswith(prefix):
        return None
    parts = normal[len(prefix):].split("/")
    return parts[0] if len(parts) == 2 and parts[1] == "SKILL.md" and SKILL_NAME.match(parts[0]) else None


def _skills_read_by_shell(parsed, installed_root, cwd):
    """Return skills whose SKILL.md a read-only command printed, following `cd` within it."""
    skills = []
    directory = cwd
    for segment in parsed.segments:
        name = segment[0]
        arguments = [PLUGIN_ROOT_VARIABLE.sub(installed_root.rstrip("/"), token) for token in segment[1:]]
        if name == "cd" and arguments:
            directory = posixpath.join(directory, arguments[0])
        elif name in FILE_READERS or name == "sed":
            for argument in arguments:
                if not argument.startswith("-"):
                    skill = _skill_from_path(posixpath.join(directory, argument), installed_root, cwd)
                    if skill:
                        skills.append(skill)
    return skills


def _plain_name(name):
    return name.split(":")[-1]


def _tool_results(event):
    message = event.get("message")
    content = message.get("content") if isinstance(message, dict) else None
    blocks = content if isinstance(content, list) else []
    return [block for block in blocks if isinstance(block, dict) and block.get("type") == "tool_result"]


def _tool_calls(event):
    """Return the tool calls of an assistant event, or None if the event is malformed."""
    message = event.get("message")
    content = message.get("content") if isinstance(message, dict) else None
    if not isinstance(content, list) or not all(isinstance(block, dict) for block in content):
        return None
    calls = [block for block in content if block.get("type") == "tool_use"]
    if not all(isinstance(block.get("name"), str) and isinstance(block.get("input", {}), dict) for block in calls):
        return None
    return calls


def _errored_calls(events):
    refused, errored = set(), set()
    for event in events:
        if isinstance(event, dict) and event.get("type") == "user":
            for block in _tool_results(event):
                call = block.get("tool_use_id")
                if block.get("is_error") and isinstance(call, str):
                    errored.add(call)
                    text = block.get("content")
                    if isinstance(text, str) and text.startswith(REFUSED_BASH):
                        refused.add(call)
    return refused, errored


def _session_cwd(events):
    for event in events:
        if isinstance(event, dict) and event.get("type") == "system" and event.get("subtype") == "init":
            return event.get("cwd") if isinstance(event.get("cwd"), str) else ""
    return ""


def walk(events, installed_root, allow=()):
    """Return (activations in order, stop kind, stop tool) up to the decision point."""
    refused, errored = _errored_calls(events)
    cwd = _session_cwd(events)
    activations = []
    for event in events:
        if not isinstance(event, dict):
            return activations, "run_error", ""
        if event.get("type") == "result":
            if event.get("subtype") == "success" and not event.get("is_error"):
                return activations, "final_answer", ""
            return activations, "limit" if event.get("subtype") == "error_max_turns" else "run_error", ""
        if event.get("type") != "assistant":
            continue
        calls = _tool_calls(event)
        if calls is None:
            return activations, "run_error", ""
        for block in calls:
            name, data, call = block["name"], block.get("input", {}), block.get("id")
            call = call if isinstance(call, str) else None
            if name in MUTATING_TOOLS:
                return activations, "mutation", name
            if name == "Skill" and call not in errored:
                skill = data.get("skill")
                if isinstance(skill, str) and skill:
                    activations.append(_plain_name(skill))
            elif name == "Read" and call not in errored:
                path = data.get("file_path")
                skill = _skill_from_path(path, installed_root, cwd) if isinstance(path, str) else None
                if skill:
                    activations.append(skill)
            elif name == "Bash":
                command = data.get("command")
                if not isinstance(command, str):
                    return activations, "unclassified_bash", "Bash"
                parsed = parse_bash(command)
                kind = _classification(parsed, allow)
                if kind == "mutation":
                    return activations, "mutation", "Bash"
                if kind == "unclassified" and call not in refused:
                    return activations, "unclassified_bash", "Bash"
                if kind == "read" and call not in errored:
                    activations.extend(_skills_read_by_shell(parsed, installed_root, cwd))
    return activations, "truncated", ""


def validate_case(case):
    if not isinstance(case, dict):
        raise ValueError("a case must be a JSON object")
    for field in ("required", "optional", "excused", "prefix_activated", "allow_commands"):
        value = case.get(field, [])
        if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
            raise ValueError(f"{field} must be a list of strings")
    kind = case.get("compaction_kind", "")
    if kind not in ("", "never_activated", "activated_before"):
        raise ValueError(f"unknown compaction_kind: {kind}")
    required = set(case.get("required", []))
    prefix = set(case.get("prefix_activated", []))
    forbidden = case.get("forbidden", [])
    if kind == "never_activated" and required & prefix:
        raise ValueError("a never_activated compaction case cannot list a required skill as activated in the prefix")
    if forbidden != "*" and (not isinstance(forbidden, list) or not all(isinstance(item, str) for item in forbidden)):
        raise ValueError('forbidden must be a list of strings or "*"')
    if required and (forbidden == "*" or required & set(forbidden)):
        raise ValueError("a case cannot both require and forbid a skill")


def score(events, case, installed_root):
    validate_case(case)
    kind = case.get("compaction_kind", "")
    prefix = list(case.get("prefix_activated", []))
    required = set(case.get("required", []))
    forbidden = case.get("forbidden", [])

    activations, stop, stop_tool = walk(events, installed_root, case.get("allow_commands", ()))
    fresh = list(dict.fromkeys(activations))
    forbidden_hits = fresh if forbidden == "*" else [skill for skill in fresh if skill in forbidden]
    missing = sorted(required - set(fresh) - set(prefix))
    known = required | set(case.get("optional", [])) | set(case.get("excused", []))

    if stop in ("unclassified_bash", "truncated", "run_error"):
        verdict = "inconclusive"
    elif forbidden_hits:
        verdict = "fail"
    elif stop == "limit":
        verdict = "pass" if required and not missing else "inconclusive"
    else:
        verdict = "fail" if missing else "pass"
    return {
        "verdict": verdict,
        "stop": stop,
        "stop_tool": stop_tool,
        "activated": fresh,
        "missing": missing,
        "forbidden_hits": forbidden_hits,
        "extra": [skill for skill in fresh if skill not in known],
        "compaction_kind": kind,
        "reinvoked": sorted(set(fresh) & set(prefix)) if kind == "activated_before" else [],
    }


def load_events(handle):
    """Read trace lines. An unreadable line, such as a killed run's last one, stops scoring there."""
    events = []
    for line in handle:
        if line.strip():
            try:
                events.append(json.loads(line))
            except (ValueError, RecursionError):
                events.append({"type": "result", "subtype": "unreadable_trace_line", "is_error": True})
                break
    return events


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace")
    parser.add_argument("case")
    parser.add_argument("--installed-root", required=True)
    args = parser.parse_args()
    with open(args.trace, encoding="utf-8", errors="replace") as handle:
        events = load_events(handle)
    with open(args.case, encoding="utf-8") as handle:
        case = json.load(handle)
    json.dump(score(events, case, args.installed_root), sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
