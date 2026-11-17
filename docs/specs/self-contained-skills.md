# Self-contained skills

Status: **Accepted by the user**, 2026-11-16 (drafted 2026-11-12). Baseline: main 388ec03 (rebased 2026-11-16 from 68da3fd after S10 retired Telos and Diagrams and merged Ideate into Thinking; all citations rechecked). Revised the same day after an independent plan review (2 blockers, 7 major, 3 minor findings; all addressed below) and a final review (1 blocker, 1 major; both addressed). Slice A implemented 2026-11-16 and merged (laimis91/assistant-framework#121). Slices B, C and D implemented 2026-11-17 on branch `self-contained/slices-b-c-d` in one PR, by user decision of 2026-11-17 (see Delivery slices).
Source: user decisions of 2026-11-12 in the marketplace-packaging discussion: make skills self-contained before packaging them as Claude Code and Codex plugins; replace the .NET cognitive-complexity scorer with a markdown method; treat Node and Python as possibly unavailable.

## Problem and intended outcome

Claude Code and Codex install a plugin by copying its folder into a cache. A skill that links outside its own folder breaks there. Today skills under `skills/` do so in these ways:

- All 17 `SKILL.md` files, several references, and contract text (for example `assistant-workflow/contracts/phase-gates.yaml`, `output.yaml`, `handoffs.yaml`; `assistant-review/contracts/phase-gates.yaml`) name `tools/progress/operating-guidance.md`. Links use four relative forms (`tools/…`, `../../tools/…`, `../../../tools/…`, `../../../../tools/…`). The guidance itself links to its sibling `tools/progress/wire-boundary.md` (operating-guidance.md:114, :121).
- `skills/assistant-workflow/scripts/task-packet-admission.py` imports `tools/progress/stagnation.py` by a path four levels up.
- `assistant-workflow`, `assistant-review` and `assistant-debugging` run `tools/change-impact/validate-change-impact.cjs` under Node 22+ for expanded change-impact work, and their contracts require its receipt.
- `assistant-workflow` (`references/prompts/pr-review.md`) and `assistant-ci-audit` (`references/test-maintenance.md`) cite `tools/cognitive-complexity/run-complexity.sh`, which needs the .NET SDK and scores only C#.
- `assistant-ui-qa` links into `assistant-workflow` and `assistant-review`, and `assistant-security` (`install-boundaries.md`) links into `assistant-review`, without declaring `requires`.
- `assistant-cleanup` runs `tools/framework-ownership/ownership.py` and `.ps1` from the agent home.

Intended outcome: every skill folder is self-contained. A skill works when only its own folder and the folders of skills it `requires` are present, and its methods work without .NET or Node. Python stays only where a large existing deterministic helper has no practical prose equivalent, and is then optional with a stated fallback. Plugin packaging itself is out of scope and follows as a separate specification. By the user's decision of 2026-11-16, that specification also owns the installer-managed instruction block for `CLAUDE.md` and `AGENTS.md` (install.sh:1567-1601), which plugins cannot write. It covers:
- one canonical block file shared by the installers and the docs;
- self-contained wording for the block's operating-guidance pointer;
- an opt-in setup step that writes the block only with the user's consent;
- a documented copy-paste snippet for global or project instruction files.

Skills must keep working without the block, and no `SessionStart` hook is used to inject it.

## Principle

- **P-1. Scripts are optional accelerators.** Every rule a skill script enforces is also stated in the skill as binary prose checks. A missing runtime never blocks ordinary work: the agent follows the prose checks and records that the deterministic check did not run. A script may make a check faster or exact; it never holds the only copy of a rule. Existing "no manual pass" wording that contradicts this (for example `assistant-workflow/contracts/output.yaml:75`) is rewritten in the slice that removes the script.

## Requirements

### Shared operating guidance (slice A)

- **R-SC-1. One canonical source, synced copies.** `tools/progress/operating-guidance.md` and `tools/progress/wire-boundary.md` stay the editable sources. A sync script, `tools/skills/sync-operating-guidance.sh` (following `sync-skill-contract-guide.sh` and `sync-lifecycle-verification.sh`), writes byte-identical copies of both to `skills/<name>/references/` for every skill, so the guidance's sibling link resolves inside each skill.
- **R-SC-2. Uniform reference.** Every skill file, including contract text, refers to its own copy with one form relative to the referring file (from `SKILL.md`: `references/operating-guidance.md`). Generated workflow views under `references/phases/` and `references/plans/` are changed by editing their sources (`phases.md`, `plan-template.md`) and rerunning `sync-workflow-references.py`, never by hand. `plan-template.md:208-209` ("resolved from … installed provider root containing `skills/` and `tools/`") is reworded to resolve from the skill folder.
- **R-SC-3. Undeclared cross-skill links.** `assistant-ui-qa` declares `requires: [assistant-workflow, assistant-review]` and `assistant-security` declares `requires: [assistant-review]` (D-SC-4). This narrows the S06 test that forbade any `requires` on security: R-S06-19 still holds, so security never requires `assistant-advisory-triage`, and `assistant-review` is the only allowed dependency.
- **R-SC-4. Drift and containment check.** A contract suite run by `tests/test-p0-p4-contracts.sh` fails when a synced copy differs from its source, when a skill lacks a copy, or when a Markdown link or runtime-instruction path under `skills/` (including `{agent_state_dir}/tools/…` paths) reaches outside its own skill folder other than into a `requires` dependency. Whole files exempt are `assistant-skill-creator/references/skill-contract-design-guide.md`, `assistant-skill-creator/references/upstream-guidelines.json` and eval prompts in `evals/cases.json`. Maintainer notes naming `tools/skills/sync-*` (the `lifecycle-verification.md` sync notes and generated-file headers) are allowed anywhere. Plain-text paths are checked only when they point into the framework's `tools/`, `docs/`, `agents/`, `hooks/` or `codex-rules/` with at least two segments, or into an installed tools directory, so illustrative layouts such as `assistant-workflow/playbooks/mcp-server.md:75` and single-word prose like `docs/tests` are not matched; references to other skills are checked through Markdown links. Other allowlist entries are exact (file, path) pairs, and an entry whose file exists but no longer contains the path is reported. They also keep the optional `<framework-tools>/patterns/pattern-library.sh` in `assistant-workflow/references/design-pattern-retrieval.md`, used only "If configured" (P-1); four paths that name the user's or the reviewed project, not a dependency (`assistant-docs/api-docs.md`, `assistant-review/references/review-checklists.md`, `assistant-security/install-boundaries.md`, `assistant-workflow/contracts/input.yaml`); and temporary entries for the paths slices B, C and D remove, including `assistant-ci-audit/references/test-maintenance.md` for slice B. Implemented as `tools/skills/check-skill-containment.py` and `tests/p0-p4/skill-self-containment-contracts.sh`.
- **R-SC-5. Non-skill consumers unchanged.** The installers' managed instruction block, the agent definitions in `agents/`, and the installed `tools/progress/` keep pointing at the canonical files. Agents are not skills and are out of scope.
- **R-SC-6. Cleanup skill exempt.** `assistant-cleanup` manages a framework installation and depends on installed ownership helpers by design. It stays installer-only, is excluded from plugin packaging, and is on the R-SC-4 allowlist for its `tools/framework-ownership` paths (D-SC-5).
- **R-SC-7. Tests.** Suites that assert the old link (for example `tests/p0-p4/skill-install-path-substitution-contracts.sh:107-108`, and about 40 lines across 11 suites naming the guidance path) are updated in the same slice.

### Cognitive complexity (slice B)

- **R-SC-8. Markdown method.** A new reference, `skills/assistant-review/references/cognitive-complexity.md`, gives a language-neutral method based on the published SonarSource cognitive-complexity rules: +1 for each break in linear flow (branch, loop, catch, jump to a label, recursion, each sequence of like boolean operators), +1 per nesting level for nested flow breaks, no increment for shorthand that aids reading. It includes worked examples and states that the result is an estimate.
- **R-SC-9. Advisory, not a gate.** Reviewers use the estimate to point at functions that are hard to follow, alongside the existing "needless complexity" rubric criterion. No numeric score blocks a review or a build (D-SC-2).
- **R-SC-10. Consumers.** `assistant-workflow/references/prompts/pr-review.md` (including its `{agent_state_dir}/tools` path at :106), `assistant-ci-audit/references/test-maintenance.md` and the reviewer agent prompts (`agents/claude/code-reviewer.md`, `agents/claude/reviewer.md`, `agents/codex/code-reviewer.toml`, `agents/codex/reviewer.toml`) stop calling `run-complexity.sh` and use the method. `assistant-workflow` requires `assistant-review` already; `assistant-ci-audit` gets the method by an inline summary or a synced copy, not a cross-skill link.
- **R-SC-11. Removal.** `tools/cognitive-complexity/` is deleted. README, `CLAUDE.md`, `AGENTS.md` build commands, and the framework-ownership tests (`tests/framework-ownership/test_ownership.py`, `tests/windows/framework-ownership-contracts.ps1`) stop naming it. Installers stop syncing it. Stale installed copies (including `.publish/`, `obj/`, `bin/` build output) are removed by the cleanup skill and uninstall, not by reinstall: the retired-item inventory gets entries with content-proof fingerprints, and `source_only_tool` entries marked `installer_generated` for the build output. Installers do not remove retired tool directories (install.sh:1053-1057).

### Progress helpers and Python (slice C)

- **R-SC-12. Relocation.** `tools/progress/stagnation.py` moves to `skills/assistant-workflow/scripts/`, since workflow is its only skill consumer, and `task-packet-admission.py` imports it from its own folder. Tests that load it (`tests/p0-p4/lib/task-packet-admission-controls.py` and the suites that use it) and the installer suites that pin the old location (`tests/p0-p4/installer-contracts.sh:78`, :824; `tests/windows/installer-contracts.ps1:2434`, :2466, :2527) are updated. `wire-boundary.md` stays canonical in `tools/progress/` and is synced under R-SC-1.
- **R-SC-13. Installers and retirement.** Installers stop syncing `stagnation.py` into `tools/progress/`, including the Codex common-tools root on Windows. The stale installed file gets a plain `managed_tool` file entry in the retired-item inventory with a content-proof fingerprint and no `installer_exact_removal` (only the seeded entries may carry it: `tools/framework-ownership/README.md:59`, enforced by `build-data --check`). Cleanup and uninstall remove it, as in R-SC-11 and R-SC-20.
- **R-SC-14. Python scope stated.** Workflow states that Python is needed only for executable packet admission and the stagnation helper. Ordinary, light and standard non-packet work needs no Python. The stagnation policy is fully stated in the operating guidance (three consecutive completed unproductive semantic cycles), so a missing Python runtime never removes the guard.
- **R-SC-15. Admission fallback.** When executable admission is selected and Python is unavailable, workflow reports that packet/delegated admission cannot run and continues on the ordinary hands-on path with fresh independent review, or stops for the user when the task requires strict admission. It never claims admission passed (D-SC-3).
- **R-SC-16. Out of scope.** Replacing `task-packet-admission.py` or `assistant-skill-creator/scripts/check-upstream-guidance.py` with prose is a separate design question.

### Change impact (slice D)

- **R-SC-17. Prose checklist replaces the Node checker.** Each of the three change-impact references (`assistant-workflow`, `assistant-review`, `assistant-debugging`) states the expanded-work checks as binary assertions: the base/candidate universe is recorded; each consumer class (configuration, registration, event, state, public, wrapper, added, removed) is covered by evidence or recorded as not applicable with a reason; artifact identity is unchanged between discovery and completion; completion binds the verification identity and the review's `scope_manifest` and `coverage_ledger`.
- **R-SC-18. Independent check.** The fresh independent reviewer checks the checklist result against the diff. That review replaces the deterministic receipt.
- **R-SC-19. Contract change.** `validator_result_ref` is `required: true` in `assistant-workflow/contracts/handoffs.yaml` (:1328, :2509, :3509) and `assistant-debugging/contracts/handoffs.yaml:69`, and phase gates require running the checker (`assistant-workflow/contracts/phase-gates.yaml:509-511`, `assistant-debugging/contracts/phase-gates.yaml:79`, `assistant-review/contracts/phase-gates.yaml:254`). Following `docs/skill-contract-design-guide.md`, this slice:
  - bumps the major `schema_version` of each affected contract set (workflow 16.0 → 17.0, and the review and debugging sets);
  - removes checker-only fields (`validator_result_ref`, receipt and run records) and replaces them with a checklist-result field that has an `on_missing` action;
  - rewrites the gates and their `on_fail` text as binary checks on the checklist and the independent review;
  - adds a migration note in each affected `SKILL.md`; workflow extends `references/legacy-compatibility.md`, and review and debugging state in their `references/change-impact.md` how an older packet carrying the removed fields is read;
  - updates contract mirrors, `evals/cases.json` of all three skills, `tests/p0-p4/change-impact-contracts.sh` (still sourced by `tests/test-p0-p4-contracts.sh:22`, rewritten to test the checklist and contract shape), `tests/p0-p4/skill-eval-contracts.sh`, and `tests/p0-p4/lib/feature-preparation-response-fixtures.sh`;
  - rewrites the installer suites that install and run the Node checker (`tests/p0-p4/installer-contracts.sh:808-880`, `tests/windows/installer-contracts.ps1:2444-2485`) to assert that each selectively installed change-impact reference holds the prose checklist and no checker path, and updates `tests/windows/framework-ownership-contracts.ps1:443` to match `ownership-checkout.ps1:60`.
- **R-SC-20. Removal and installers.** `tools/change-impact/` and `tests/change-impact/` are deleted. `install.sh` and `install.ps1` stop syncing it, including the Codex Windows `~/.agents/tools/change-impact` sync (install.ps1:2651, :2701, :2747), and `tools/framework-ownership/ownership-checkout.ps1:60` drops `change-impact` from `OwnershipCodexCommonTools`. Stale installed copies are removed by the cleanup skill and uninstall through retired-item inventory entries with content-proof fingerprints, as in R-SC-11.

## Delivery slices

Each slice was planned as one branch and one PR, in order A, B, C, D. A is a prerequisite for the others; B, C and D are independent of each other in source but share the inventory file. On 2026-11-17 the user chose to land B, C and D together in one PR; they stay separate commits, and each deletion is its own commit.

| Slice | Requirements | Behavior change | Evals to rerun |
|---|---|---|---|
| A — Shared guidance sync | R-SC-1 to R-SC-7 | None to skill methods; test and contract text paths change | None |
| B — Cognitive complexity method | R-SC-8 to R-SC-11 | Review method | review, workflow, ci-audit |
| C — Progress helpers | R-SC-12 to R-SC-16 | Stated Python fallback | workflow |
| D — Change-impact checklist | R-SC-17 to R-SC-20 | Consumed-contract major version | workflow, review, debugging |

## Verification

- `tools/skills/validate-skills.sh` and `./tests/test-p0-p4-contracts.sh` pass after every slice.
- After slice A: no file under `skills/` outside the allowlist contains `tools/progress/`; the drift check fails on a deliberately edited copy and passes after resync; `sync-workflow-references.py` reports no drift.
- Self-containment check after each slice: copy each skill folder alone, plus its `requires`, into an empty directory, and confirm every relative Markdown link resolves and no runtime-instruction path points outside it.
- After each slice: the Unix and Windows installer contract suites pass; installing into a disposable home with `--skill <name>` for each changed skill leaves no broken link; for slices C and D, `install.ps1 --agent codex` runs on Windows (CI `windows-installer.yml`).
- Slices B and D: the listed skills' eval cases are rerun and compared with the baseline before merge.

## Decisions

- **D-SC-1.** Change-impact receipt fields are removed with a major schema version bump (R-SC-19), not kept as optional dead fields. Recommended.
- **D-SC-2.** The cognitive-complexity estimate is advisory with no numeric threshold (R-SC-9). Recommended.
- **D-SC-3.** Packet admission keeps Python with a stated fallback; no prose rewrite now (R-SC-15, R-SC-16). Recommended.
- **D-SC-4.** Undeclared cross-skill links are fixed by declaring `requires` (R-SC-3), not by copying the target files. Recommended: plugins will bundle dependent skills together.
- **D-SC-5.** `assistant-cleanup` stays installer-only and is excluded from plugin packaging (R-SC-6). Recommended.
- **D-SC-6.** Stale installed tool directories are removed by cleanup and uninstall, not by reinstall (R-SC-11, R-SC-20). Recommended: matches the current installer rule for retired directories.
- **D-SC-7.** The expanded-work checklist lives once, in `assistant-review/references/change-impact.md#expanded-work-checklist`; the workflow and debugging references link to it instead of restating it (R-SC-17). Both skills already require assistant-review, so the link stays inside their declared dependencies. Implemented 2026-11-17.
- **D-SC-8.** Slice D keeps `plan_schema_version` at 16.0 under workflow contract set 17.0, and admission accepts review producers 10.0 and 11.0 as current. Slice D changes no plan field, so in-flight plans need no admission migration or re-review; an older packet's `validator_result_ref` stays readable but is not a current checklist result. Implemented 2026-11-17; see `assistant-workflow/references/legacy-compatibility.md`.
