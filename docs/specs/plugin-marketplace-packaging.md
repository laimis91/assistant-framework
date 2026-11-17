# Plugin marketplace packaging

Status: **Draft**, 2026-11-17, awaiting user acceptance. Open questions Q1–Q4 answered by the user the same day (D-MP-4, D-MP-6, D-MP-8, D-MP-9). Revised the same day after an independent review (4 major, 8 minor, 2 nit findings), a second review (5 major, 3 minor, 1 nit) and a delta review (2 major, 3 minor, 1 nit); all addressed below. Baseline: main ae48ee1, after [self-contained skills](self-contained-skills.md) slices A–D merged.
Source: user decisions of 2026-11-12 (package the skills as Claude Code and Codex plugins once they are self-contained), 2026-11-16 (this specification owns the installer-managed instruction block; the removal decisions in Slice E) and 2026-11-17 (serve the marketplaces from this repository; reach Claude chat and mobile by uploading skill ZIPs, not through a marketplace).

## Problem and intended outcome

Today the framework reaches agents only through `install.sh` and `install.ps1`, which copy skills and agents into `~/.claude/`, `~/.codex/` and `~/.gemini/` and edit the instruction files. The user wants the skills on three surfaces, and then the installer retired:

| Surface | Route | Updates |
|---|---|---|
| Claude Code (CLI, desktop Code tab) and the desktop Cowork tab | This repository as a Claude plugin marketplace | Marketplace update |
| Codex (CLI and app) | This repository as a Codex plugin marketplace | `codex plugin marketplace upgrade` |
| Claude chat (web, desktop, mobile) | Skill ZIPs uploaded to the user's account under Customize → Skills | Manual re-upload |

No submission to Anthropic's or OpenAI's public directory is planned. Intended outcome: after Slices A–D one repository serves both marketplaces and builds the ZIPs; after Slice E the manual installer is gone and the marketplaces are the only supported channel.

## Platform facts this design relies on

Checked 2026-11-17 against vendor documentation. Each is rechecked during implementation by the Verification steps.

- **Claude marketplace.** `.claude-plugin/marketplace.json` at the marketplace root, with `name`, `owner` and `plugins[]`; each entry has `name` and `source` (a `./` relative path for a plugin inside the repository; `..` is rejected). The entry name must equal the plugin's manifest name. Users add it with `/plugin marketplace add laimis91/assistant-framework` and install with `/plugin install <plugin>@<marketplace>`. `claude plugin validate` checks both files. ([Create a marketplace](https://code.claude.com/docs/en/plugin-marketplaces))
- **Claude updates.** A user gets a new copy only when the plugin's computed version changes: bump `version` on each release, or omit it everywhere so users track commits. Never set it in both `plugin.json` and the marketplace entry. Auto-update is off for third-party marketplaces until the user turns it on. Plugin skills are namespaced by plugin name (`/<plugin>:<skill>`). ([Host and maintain a marketplace](https://code.claude.com/docs/en/plugins/host-marketplace.md))
- **Claude cache copy.** Installed plugins are copied into a cache. Symlinks to elsewhere in the same marketplace are dereferenced; symlinks outside it are skipped.
- **Codex marketplace.** `.agents/plugins/marketplace.json` at the repository root (`.claude-plugin/marketplace.json` is read as a legacy fallback). Each entry needs `name`, `source`, `policy` (`installation`, `authentication`) and `category`; a local source path starts with `./` and stays inside the root. Users add it with `codex plugin marketplace add laimis91/assistant-framework`; the app lists it in the Plugins Directory. Installed plugins are cached at `~/.codex/plugins/cache/<marketplace>/<plugin>/<version>/`. ([Build plugins](https://developers.openai.com/codex/plugins/build/))
- **Codex manifest.** The portable manifest is `plugin.json` at the plugin root; `.codex-plugin/plugin.json` is a supported fallback. Skills are discovered from the plugin's root `skills/<name>/SKILL.md`.
- **Claude chat skills.** Uploaded as a ZIP of one skill folder under Customize → Skills; code execution must be on. Account skills sync to Claude Code from v2.1.273. Anthropic's help page does not say whether they work in the mobile apps, and there is no upload API. ([Use skills](https://support.claude.com/en/articles/12512180-use-skills))

Not confirmed from vendor documentation and checked first in Slice B: that the desktop Cowork tab installs from a third-party marketplace, and that Codex accepts a root `plugin.json` as the main manifest next to `.claude-plugin/plugin.json`.

## What plugins cannot do that the installer does

1. **Path substitution.** The installer rewrites `{agent_state_dir}` to `.claude` or `.codex` in every copied Markdown, YAML and JSON file (install.sh:822-829, :1360-1378). The token appears 26 times in 15 files under `skills/`: 25 in `assistant-workflow` and one in `assistant-review/contracts/input.yaml:21`. The Codex eval runner substitutes it too (`tools/evals/run-codex-framework-evals.sh:945-950`). A plugin copy would ship the token unresolved.
2. **Agent definitions.** The installer copies `agents/claude/*.md` and `agents/codex/*.toml`. The user decided on 2026-11-16 that the marketplace does not ship them. Without them:
   - `assistant-workflow/references/subagent-roles.md:114` tells the agent to "report a deployment mismatch and stop" when Claude or Codex writer definitions are missing, so delegated Build would stop on every plugin install;
   - `subagent-roles.md:127` falls back to "the closest provider-neutral role prompt", but no skill holds one: the dispatch snippets (`subagent-roles.md:67`, :75, :93, :105) only name the agent, and the return schema and finding format live in the agent definitions.
3. **Instruction block.** The installer writes a marked block into `CLAUDE.md` and `AGENTS.md` (install.sh:1567-1601), filled per agent (install.sh:1555-1561; install.ps1:2218-2220 with `{{AGENT_NAME}}` and `{{GUIDANCE_HOME}}`). It tells the agent to read the installed `tools/progress/operating-guidance.md` "for every activity, including when no skill matches" (install.sh:1570). Plugins cannot write instruction files, and that path does not exist in a plugin install.
4. **Selective install and cleanup.** `--skill <name>` and the `assistant-cleanup` skill have no plugin equivalent; marketplace install is all-or-nothing per plugin, and plugin removal is the platform's own uninstall.
5. **Legacy hook cleanup.** The installer removes retired hook registrations from `settings.json` and `hooks.json` and leaves inert shims (install.sh:815-818, :1534-1543). A plugin cannot clean up after a manual install.

## Requirements

### Skill text works without the installer (Slice A)

- **R-MP-1. State directory without substitution.** `{agent_state_dir}` keeps its spelling and is defined once in `tools/progress/operating-guidance.md` (and so in every synced skill copy): it means `.claude` on Claude Code and `.codex` on Codex, in the project root unless the text says `~/`. The installer may keep substituting until Slice E. Both eval paths that substitute it stop doing so, so evals read the same text plugin users get: `tools/evals/run-codex-framework-evals.sh:945-950` and `tools/evals/finalize-workflow-kernel-review.sh:239`. The contract tests that expect substitution are updated to expect the token as written: `tests/p0-p4/codex-behavioral-eval-contracts.sh` (:447-448, :671-673, :4741), `tests/p0-p4/eval-contracts.sh:1209-1223` and `tests/p0-p4/codex-instruction-overlay-contracts.sh` (:35-39, :131). A test fails if a skill file uses the token while the synced guidance lacks the definition.
- **R-MP-2. Role prompts inside the skills.** Each formal role a skill dispatches gets a provider-neutral prompt in the owning skill: `assistant-review/references/roles/` for `code-reviewer`, `qa-evaluator` and the `reviewer` compatibility role (`subagent-roles.md:124`); `assistant-research/references/roles/` for `lens-researcher` and `research-peer-reviewer`; `assistant-workflow/references/roles/` for the Build, mapping and architecture roles. Each prompt carries the role's instructions, return schema and finding format. The Claude and Codex agent bodies already differ in substance (for example `agents/codex/code-reviewer.toml:14-16` and :26 against `agents/claude/code-reviewer.md:23`, and the context-map wording in `code-mapper.md:26` against `code-mapper.toml:30`), and several Claude bodies hard-code `.claude/` paths (`code-mapper.md:26` and :57, `architect.md:13`, `code-writer.md:129`). Slice A first reconciles each pair into one body that keeps every instruction from both, with state paths written as `{agent_state_dir}`, and updates both agent files to it. A sync script then writes the prompts from the Markdown body of `agents/claude/*.md` (frontmatter removed). A drift check fails when a prompt differs from that body, or from the `developer_instructions` text of the matching `agents/codex/*.toml` after line-ending and trailing-whitespace normalization, or contains a literal `.claude/` or `.codex/` path. Its exception list starts empty, and any entry names the role and the reason (D-MP-5).
- **R-MP-3. Missing agent definitions.** Every skill file that treats missing agent definitions as a deployment mismatch instead treats "framework agents not installed" as the normal plugin case. Today these are the four workflow sites `assistant-workflow/references/subagent-roles.md:114`, `subagent-dispatch.md:98`, `build-worker-protocol.md:114` and `assistant-workflow/contracts/phase-gates.yaml:514`. `assistant-review/references/qa-evaluation-loop.md:60` already keeps unavailable isolation incomplete, which is the rule kept below, so it does not change; a Slice A check finds no remaining "deployment mismatch" rule that applies to a plugin install. Optional Build delegation falls back to hands-on Build by the main agent, recorded with its reason. Formal review, QA and research-lens isolation still require a newly created fresh agent: the runtime's general-purpose agent given the R-MP-2 role prompt. This changes the workflow and review methods: their contract sets and evals are updated under `docs/skill-contract-design-guide.md`, and the workflow, review and research evals are rerun with user authorization. The user's own subagent setup, when present, is used the same way (D-MP-8).

### Plugin and marketplaces (Slice B)

- **R-MP-4. One plugin.** All skills except `assistant-cleanup` ship in one plugin named `assistant-framework`. The five skills that declare `requires` (`assistant-workflow`, `assistant-debugging`, `assistant-ui-qa`, `assistant-security`, `assistant-skill-creator`) and their targets (`assistant-review`, `assistant-verification`, `assistant-tdd`, `assistant-workflow`) then sit as sibling folders in the same cached plugin, so every cross-skill link resolves (D-MP-1).
- **R-MP-5. Generated plugin folder.** `plugins/assistant-framework/` holds the plugin: `.claude-plugin/plugin.json`, a root `plugin.json` for Codex, and `skills/` with a copy of each shipped skill. A sync script, `tools/skills/sync-plugin.sh` (following `sync-operating-guidance.sh`), writes the copy from `skills/` and the manifest versions from `version.txt`. `tools/evals/skill-activation/generate_plugin.py:143` already writes a `.claude-plugin/plugin.json`; the two share one manifest writer instead of keeping two. The editable source stays `skills/` until Slice E (D-MP-2). No other component folder (`agents/`, `hooks/`, `commands/`) is created (D-MP-8).
- **R-MP-6. Marketplace files.** The repository root carries `.claude-plugin/marketplace.json` and `.agents/plugins/marketplace.json`, each listing the one plugin with source `./plugins/assistant-framework`. The Codex entry has `policy.installation` `AVAILABLE`, `policy.authentication` `ON_INSTALL` and a `category`. Both marketplaces are named `assistant-framework`.
- **R-MP-7. Versioning.** The plugin version comes from `version.txt` and is set only in the manifests, never in the marketplace entries. Releasing means bumping `version.txt` and resyncing (D-MP-3).
- **R-MP-8. Drift and validity check.** A contract suite run by `tests/test-p0-p4-contracts.sh` fails when:
  - the plugin's `skills/` differs from the shipped skills in `skills/`, or contains `assistant-cleanup`;
  - a manifest version differs from `version.txt`;
  - the two marketplace files list different plugins or sources;
  - `tools/skills/check-skill-containment.py` reports a link leaving the plugin folder.

  It warns when the plugin's skills changed since the last commit that changed `version.txt`, because plugin users get no update until the version moves.
- **R-MP-9. Documentation.** README gains "Install from the marketplace" for Claude Code and Codex (add, install, enable auto-update, update). It states that plugin skills are namespaced (`/assistant-framework:assistant-workflow`) and that the same skill must not come from two sources: remove a manual install first, and see R-MP-12 for chat ZIPs. `docs/README.md` links it.

### Claude chat ZIPs (Slice C)

- **R-MP-10. Chat-suitable set.** A skill is packaged only when it declares no `requires`, needs no repository or git, and every path that needs a subagent reports itself incomplete or blocked instead of failing silently. The initial set is `assistant-research`, `assistant-thinking` and `assistant-clarify` (D-MP-4), and all three meet the rule:
  - research: single-agent source research is direct-capable (`assistant-research/SKILL.md:16-28`, :75), and five-lens research without isolation ends incomplete (:70-74);
  - thinking: an independent high-risk challenge needs a fresh reviewer (`assistant-thinking/SKILL.md:32-36`), and the skill reports a gap when its method cannot be applied with the available context (:28); the Slice C check confirms this in chat;
  - clarify: no subagent path.
- **R-MP-11. ZIP build.** `tools/skills/build-chat-zips.sh` writes `dist/chat-skills/<skill>.zip`, each holding one top-level `<skill>/` folder copied from `skills/`. `dist/` is Git-ignored. The script fails on:
  - a skill outside the set, or one with a `requires` entry;
  - a link leaving the folder;
  - a frontmatter `name` over 64 characters or outside lowercase letters, digits and hyphens;
  - a `description` over 1024 characters.

  These are the Agent Skills limits as understood on 2026-11-17, and Verification rechecks them.
- **R-MP-12. Account-sync duplicates.** Account skills sync into Claude Code (v2.1.273 or later), so a user with both the plugin and the chat ZIPs gets each of the three skills twice there, and the copies can drift between releases. README tells users to keep one copy in Claude Code. The documented way is to delete the account copy in Customize → Skills when the plugin is installed, at the cost of losing it in chat; if Claude Code can turn off account sync or disable one skill inside a plugin, README says how instead. Both of those are unconfirmed platform facts checked in Slice C. The Slice C check records what Claude Code actually shows.
- **R-MP-13. Upload guide.** README states the manual upload steps, that each release needs a re-upload, and that mobile availability is to be confirmed by the first trial (Verification).

### Instruction block (Slice D)

The [self-contained skills](self-contained-skills.md) specification assigned four items to this one: one canonical block file, self-contained pointer wording, an opt-in setup step and a copy-paste snippet.

- **R-MP-14. One canonical, agent-neutral block.** The block text lives in one file, `docs/instruction-block.md`. It has no placeholders: the guidance-home placeholder goes away with R-MP-15, and the title becomes "Assistant Framework instructions" for both `CLAUDE.md` and `AGENTS.md`. Both installers read it until Slice E, and the README snippet quotes it.
- **R-MP-15. Self-contained wording.** The block names no installed path. It keeps the four current sections, Skills, Involving the user, Operating stance and Boundaries (install.sh:1567-1601), and replaces the "read `tools/progress/operating-guidance.md` for every activity" line with the rule chosen in D-MP-6. This is a behavior change for work where no skill matches; the check in Verification covers it.
- **R-MP-16. Opt-in setup.** Setup is a README copy-paste snippet for global or project `CLAUDE.md` and `AGENTS.md`. No skill or hook writes it (D-MP-9).
- **R-MP-17. Skills work without it.** No skill depends on the block. A test fails when any file under `skills/` contains the block marker `ASSISTANT_FRAMEWORK_AGENTS_MD_START`, `docs/instruction-block.md`, or the heading "Assistant Framework instructions".

### Remove the manual installer (Slice E)

Planned after Slice B has been in use. These are the user's decisions of 2026-11-16.

- **R-MP-18. Removed.** These go, with no transition release:
  - `install.sh`, `install.ps1`, `uninstall.sh` and `uninstall.ps1`;
  - `tools/framework-ownership/` and the `assistant-cleanup` skill;
  - `codex-rules/`;
  - Gemini installer and support paths: `agents/gemini/` and Gemini install and setup text in README and `docs/`;
  - Gemini runtime guidance in workflow text that is not a released contract label: `subagent-roles.md:7`, :19 and :121, `mega-and-patterns.md:15`, `subagent-dispatch.md:104`, `build-worker-protocol.md:115` and `sub-task-brief-template.md:21` and :57; this changes workflow dispatch text, so the workflow evals are rerun;
  - the installer, ownership, path-substitution and Windows installer suites, including `tests/p0-p4/skill-install-path-substitution-contracts.sh`;
  - CI `windows-installer.yml`, and the installer and Gemini steps in `framework-validation.yml`;
  - in `assistant-security`, the findings about this framework's installer (`install-boundaries.md`, for example F1 at :29, and the `codex-rules` enforcement example in `agent-authority.md:22`) are retired or marked historical, and the security evals are rerun.

  `gemini` stays a readable historical label in released workflow contracts (for example the v13 `producer.runtime` enum in `plan-template.md:397-398` and its generated copies `plans/medium.md:370-371` and `plans/large.md:370-371`, `task-packet-admission.py:316` and :347, and every occurrence of the "Gemini native fallback" condition text, such as `handoffs.yaml:873` and `output.yaml:2467`). Removing it from current contracts would be a versioned workflow contract change with an eval rerun, and is not part of this slice (D-MP-7).
- **R-MP-19. Agents stay in the repository.** `agents/claude` and `agents/codex` stay as files users copy by hand, and docs say how. Workflow works without them (R-MP-3).
- **R-MP-20. Source of truth moves.** `skills/` moves to `plugins/assistant-framework/skills/` and `sync-plugin.sh` is deleted. Every script, test, eval runner (including `tools/evals/run-codex-framework-evals.sh`) and doc path that names `skills/` is updated in the same change.
- **R-MP-21. Manual migration.** Docs give exact removal steps for an existing manual install, in this order:
  1. Remove Assistant Framework hook registrations from `~/.claude/settings.json` and `~/.codex/hooks.json`.
  2. Delete the framework skills, tools and hook shims from `~/.claude/` and `~/.codex/`.
  3. Remove the marked instruction block.
  4. Delete the installed agents and Codex rules.

  Nothing automates it.
- **R-MP-22. Repository instructions.** `CLAUDE.md`, `AGENTS.md`, README, `docs/README.md` and the files named in R-MP-23 stop naming installer commands or `codex-rules`.
- **R-MP-23. Tools and suites that run the installer.** Each is rewritten to read the plugin folder, or deleted when it only tests installer behavior, in the same change:
  - rewritten: `tools/evals/skill-activation/generate_plugin.py` (:64, using the manifest code shared under R-MP-5), `tools/context-budget-report.sh` (:530), and the shared harness `tests/p0-p4/lib/p0p4-harness.sh:107`;
  - decided per suite, delete or rewrite: `tests/p0-p4/hook-retirement-contracts.sh` (:77, :81, :658), `sol-native-overhead-contracts.sh` (:158, :175), `codex-agent-config-contracts.sh` (:185-244) and `repo-guard-contracts.sh` (:285-287);
  - text updated under R-MP-22: `tools/skills/check-skill-containment.py` (:7, :25), `docs/troubleshooting-subagents.md` and `docs/presentation.md`.

## Delivery slices

One branch and PR per slice, in order A, B, C, D, E. B needs A, because plugin installs have no agents; C and D need A and B, because their checks use the installed plugin; E needs B and D.

| Slice | Requirements | Behavior change | Evals to rerun |
|---|---|---|---|
| A — Installer-free skill text | R-MP-1 to R-MP-3 | Dispatch fallback and role prompts | workflow, review, research |
| B — Plugin and marketplaces | R-MP-4 to R-MP-9 | New distribution channel; skills unchanged | None |
| C — Chat ZIPs | R-MP-10 to R-MP-13 | None to skill methods | None |
| D — Instruction block | R-MP-14 to R-MP-17 | Block wording for work where no skill matches | Framework instruction evals (`tools/evals/run-framework-instruction-evals.sh`) |
| E — Remove manual installer | R-MP-18 to R-MP-23 | Installer gone; Gemini dispatch text and security installer findings retired | workflow, security |

## Verification

- `tools/skills/validate-skills.sh` and `./tests/test-p0-p4-contracts.sh` pass after every slice.
- **Slice A:**
  - no skill file uses `{agent_state_dir}` without the guidance definition, and both eval paths in R-MP-1 leave the token as written;
  - the role-prompt drift check fails on a deliberately edited copy and on a prompt containing a `.claude/` or `.codex/` literal;
  - with no framework agents installed, a workflow review dispatches a general-purpose agent with the review role prompt and gets a schema-valid return.
- **Slice B:**
  - `claude plugin validate .` passes from the repository root.
  - In a disposable `HOME`, `claude plugin marketplace add <checkout>` and `claude plugin install assistant-framework@assistant-framework` succeed, and `claude plugin details assistant-framework` lists every shipped skill and not `assistant-cleanup`.
  - In a disposable `HOME`/`CODEX_HOME`, `codex plugin marketplace add <checkout>` succeeds and the plugin installs with the same skill list.
  - The self-containment check passes on each cached copy.
  - A workflow run in the disposable install loads an assistant-review reference (for example `domain-rubrics.md`) from the sibling folder in the cache.
  - Cowork installs the plugin from the marketplace.
  - After merge, the same from `laimis91/assistant-framework`.
- **Slice C:**
  - each ZIP unpacks to one folder whose links resolve, and the name and description limits are rechecked against Anthropic's custom-skill help;
  - the user uploads one ZIP and confirms it activates in Claude chat on desktop and on mobile, and that a thinking request needing an independent challenge reports the gap;
  - what Claude Code shows when the plugin and the account copy are both present is recorded, together with whether Claude Code can turn off account sync or disable one skill inside a plugin (R-MP-12).

  The mobile and duplicate results are recorded in this specification.
- **Slice D:**
  - the installers and the README quote the same block text;
  - a fresh Claude Code and a fresh Codex session with only the plugin and no block activate a skill that loads its operating guidance;
  - a session with the block and a request no skill matches follows the D-MP-6 rule.
- **Slice E:**
  - no file outside an allowlist names `install.sh`, `install.ps1`, `uninstall.sh`, `uninstall.ps1` or `codex-rules`; the allowlist covers historical specs, `docs/evals/`, `docs/research/`, dated documents, eval fixtures in `skills/*/evals/cases.json`, and `assistant-security` findings marked historical under R-MP-18;
  - Gemini mentions remain only in that allowlist and in the released contract labels of R-MP-18;
  - the Slice B install checks still pass.

## Decisions

- **D-MP-1.** One plugin for all shipped skills (R-MP-4). Recommended: `requires` links resolve inside one cache folder. Separate plugins with Claude plugin dependencies were not chosen because Codex has no documented equivalent.
- **D-MP-2.** A generated plugin folder until Slice E, not a plugin at the repository root (R-MP-5). Recommended: a root plugin would copy the whole tracked tree (about 14 MB in 602 files, against 5 MB for `skills/`), including `agents/`, `tests/` and `assistant-cleanup`, into every cache and could auto-load unwanted components. Symlinks were not chosen because Codex symlink handling is undocumented.
- **D-MP-3.** Explicit version from `version.txt` (R-MP-7). Recommended: releases are deliberate and both platforms cache by version. The alternative is to omit `version` so Claude users track every commit; Codex behavior without a version is undocumented.
- **D-MP-4.** Initial chat set of three skills (R-MP-10). Confirmed by the user 2026-11-17: the other skills act on a repository, run commands, declare `requires` or need subagents to finish.
- **D-MP-5.** Role prompts are synced from `agents/claude` into the owning skills, not authored twice (R-MP-2). Recommended: one source until Slice E keeps the agents and the plugin in step; after Slice E the skill copies can become the source and `agents/` can be generated from them.
- **D-MP-6.** Chosen by the user 2026-11-17 (option A). For work where no skill matches, the block inlines the short common rules it already carries (its four sections) and drops the instruction to read the full operating guidance. The full guidance still loads with every skill. Recommended: the four sections already state the rules that matter outside a skill, and a block cannot point at a plugin cache path.
- **D-MP-7.** `gemini` stays a historical label in released contracts (R-MP-18). Recommended: the contract design guide requires versioning and keeping historical labels when a consumed value is removed.
- **D-MP-8.** Agent definitions stay optional and are not shipped in either plugin (R-MP-5, R-MP-19). Chosen by the user 2026-11-17, keeping the 2026-11-16 decision: other users may have their own subagent setup. Skills dispatch through the runtime's available agents with the R-MP-2 role prompts.
- **D-MP-9.** Setup is a README snippet only; no setup skill (R-MP-16). Chosen by the user 2026-11-17.
