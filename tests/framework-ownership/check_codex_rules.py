"""Check that Codex prompt rules cover every documented destructive form (S11 R-S11-24).

Usage: check_codex_rules.py <framework root> <base workflow.rules>
Prints one problem per line; prints nothing when the rules cover every form.
"""
import re, sys
root, base_path = sys.argv[1], sys.argv[2]

def rules(text):
    found = []
    for block in re.findall(r"prefix_rule\((.*?)\n\)", text, re.S):
        pattern = re.search(r"pattern=\[(.*?)\]", block, re.S)
        decision = re.search(r'decision="(\w+)"', block)
        if pattern and decision:
            found.append((tuple(re.findall(r'"([^"]*)"', pattern.group(1))), decision.group(1)))
    return found

current = rules(open(f"{root}/codex-rules/workflow.rules", encoding="utf-8").read())
base = rules(open(base_path, encoding="utf-8").read())
problems = []
for rule in current:
    if rule[1] in ("allow", "forbidden") and rule not in base:
        problems.append(f"new {rule[1]} rule: {' '.join(rule[0])}")
for rule in base:
    if rule not in current:
        problems.append(f"base rule removed or changed: {' '.join(rule[0])}")
prompts = [pattern for pattern, decision in current if decision == "prompt"]

def destructive(command):
    return re.search(r"uninstall\.(sh|ps1)|ownership\.(py|ps1) apply", command) is not None

def covered(command, source):
    tokens = command.split()
    if not any(tuple(tokens[:len(p)]) == p for p in prompts):
        problems.append(f"no prompt rule matches: {command} ({source})")

readme = open(f"{root}/README.md", encoding="utf-8").read()
section = readme.split("\n## Uninstall and legacy cleanup\n", 1)
if len(section) != 2:
    problems.append("README has no Uninstall and legacy cleanup section")
else:
    body = section[1].split("\n## ", 1)[0]
    for fence in re.findall(r"```(?:bash|powershell)\n(.*?)```", body, re.S):
        for line in fence.splitlines():
            line = line.strip()
            if line.startswith("cd "):
                continue
            if destructive(line):
                covered(line, "README")
skill = open(f"{root}/skills/assistant-cleanup/SKILL.md", encoding="utf-8").read()
if "ownership-checkout" in skill:
    problems.append("SKILL.md names the checkout-only entry point")
# A concrete "cd <dir> && ..." form; the prose rule "never `cd … &&`" names no directory.
if re.search(r"\bcd\s+[^\s…`]+[^`\n]*&&", skill):
    problems.append("SKILL.md has a cd ... && form")
for token in re.findall(r"[^\s`(]*/uninstall\.(?:sh|ps1)", skill):
    if token != "./uninstall.sh":
        problems.append(f"SKILL.md puts a path before the uninstall script: {token}")
if re.search(r"\$CODEX_HOME/tools|~/\.codex/tools", skill):
    problems.append("SKILL.md uses an absolute Codex tools path")
spans = [span for span in re.findall(r"`([^`\n]+)`", skill) if destructive(span) and not span.startswith("cd ")]
for required in ("./uninstall.sh --agent <agent>", "pwsh -NoProfile -File uninstall.ps1 -Agent <agent>", "powershell -NoProfile -File uninstall.ps1 -Agent <agent>"):
    if required not in spans:
        problems.append(f"SKILL.md lacks the uninstall form: {required}")
if not any(span.startswith("python3 tools/framework-ownership/ownership.py apply") for span in spans):
    problems.append("SKILL.md lacks the fixed Unix apply form")
for prefix in ("pwsh -NoProfile -File tools/framework-ownership/ownership.ps1 apply", "powershell -NoProfile -File tools/framework-ownership/ownership.ps1 apply"):
    if not any(span.startswith(prefix) for span in spans):
        problems.append(f"SKILL.md lacks the fixed Windows apply form: {prefix}")
for span in spans:
    covered(span, "SKILL.md")
print("\n".join(problems))
