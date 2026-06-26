# Triage Rubric And Gate Packs

Use this during `--- PHASE: TRIAGE ---` before choosing phases. Triage produces structured metadata, not just a size label.

## Required Triage Output

Record these fields in the task journal for medium+ tasks and in the inline plan for small tasks:

- `Task type`: `feature`, `bugfix`, `refactor`, `migration`, `rewrite`, `config`, `infra`, `security`, `docs`, or `spike`
- `Risk tier`: `low`, `moderate`, `high`, or `critical`
- `Triaged as`: `small`, `medium`, `large`, or `mega`
- `Required agents`: the roles required by size and risk
- `Subagent policy state`: `not_required`, `authorization_required`, `delegation_authorized`, `authorization_denied`, `subagents_unavailable`, or `policy_disallowed`
- `Subagent execution mode`: `delegated`, `direct_fallback`, or `not_applicable`
- `Subagent authorization scope`: roles/phases/actions explicitly authorized by the user, or empty when none
- `Required gates`: the common gates plus every applicable task-category gate pack
- `Search mode`: `none`, `lightweight`, or `candidate_search`
- `Candidate scope scan`: likely touched paths or modules, symbols/search terms checked, adjacent tests/docs/contracts/config/mirrors to inspect, confidence, and unknowns

## Size Rules

| Size | Use when |
|---|---|
| `small` | One localized change, clear behavior, low risk, existing verification path, no public contract/data/security impact. |
| `medium` | A feature, bugfix, refactor, endpoint, hook, or contract change spanning several files or one boundary. |
| `large` | Cross-module/layer work, public API/config/data behavior, weak baseline tests, or high uncertainty. |
| `mega` | Rewrite, migration, port, legacy-to-new-structure work, 10+ files across layers, or behavior parity across subsystems. |

Escalate size when risk exceeds file count. Auth, PII, payments, destructive data changes, public API changes, or behavior-preserving legacy migration are at least `large` unless discovery proves they are isolated and fully covered.

## Candidate Scope Scan

Before finalizing Triage, run a quick read-only scan to avoid classifying from the prompt alone. Keep it bounded: named files from the prompt, likely modules/directories, obvious symbols/search terms, nearby tests, docs, contracts, config, generated mirrors, and runtime surfaces that can change the risk tier.

Record:
- `likely_touched_paths`: exact paths when known, otherwise directories/modules.
- `symbols_or_terms_searched`: names, commands, or search terms checked.
- `adjacent_surfaces`: tests, docs, contracts, config, generated mirrors, hooks, or APIs that may need Discover coverage.
- `confidence`: `low`, `medium`, or `high`.
- `unknowns`: remaining scope/risk questions for Discover.

This scan is not the Code Mapper context map. It is a shallow risk and size check. If the scan exposes broader references, weak tests, public contracts, or unclear ownership, escalate size/risk or required gates before Discover.

## Risk Tier Rules

| Risk tier | Use when |
|---|---|
| `low` | Local, reversible, tested, no public behavior or data impact. |
| `moderate` | Multiple files, shared helpers, unclear edge cases, or moderate verification work. |
| `high` | Public contracts, data shape, migration, behavior parity, security-sensitive paths, weak tests, or multi-layer coupling. |
| `critical` | Irreversible data loss risk, auth bypass, secret exposure, payment/security boundary, or production outage risk. |


## Search Mode Rules

Use `search_mode` to decide how much pre-code option exploration is useful. Keep ordinary tasks fast; do not add candidate-search ceremony unless it reduces real uncertainty.

- `none`: the safe path is obvious and acceptance criteria already constrain implementation.
- `lightweight`: there are 1-3 obvious options worth comparing in the plan's Analysis section.
- `candidate_search`: use Candidate Search when the request has explicit alternatives, open-ended architecture/design, optimization goals, high uncertainty, repeated failed attempts, unclear/flaky bugs, or a reviewer-requested pivot.

When `candidate_search` is selected, load `references/candidate-search.md`. The goal tree must decompose existing acceptance criteria and slice acceptance/verification criteria; the archive is stored at `{agent_state_dir}/candidate-search.md` only when local state is configured and policy-allowed, otherwise inline in the plan/task packet.

## Common Gates

Apply to every code task:

- requirements restated
- constraints recorded
- file scope identified
- verification commands listed
- tests/build executed
- spec review completed
- quality review completed

## Task Category Gate Packs

### Bugfix
- reproduction or failing test/log evidence captured
- root cause stated before fix
- regression test or targeted assertion added
- fix scope stays tied to the root cause

### Feature
- user-visible or API acceptance criteria are binary and testable
- new behavior has tests in the same build step
- public contract, config, telemetry, and docs impact are checked

### Refactor / Migration / Rewrite
- baseline behavior inventory captured before edits
- characterization, golden, or existing regression tests protect behavior parity
- public contracts and external behavior invariants are listed
- intentional behavior changes are explicitly approved
- source and target boundaries are mapped before Build

### Config / Infra
- environment matrix or affected runtime contexts listed
- rollback or disable path identified
- secrets and local machine state are not hardcoded
- dry-run or smoke verification exists when available

### Security / Input
- threat or abuse case considered
- validation, authorization, and trust-boundary checks listed
- no secrets, credentials, PII, or sensitive data are logged
- security review skill is loaded when auth, PII, payments, or external inputs are touched

### Docs-Only
- source evidence is cited from code, tests, or existing docs
- no code/test requirement unless docs generation or examples change runnable behavior
- outdated instructions are removed or reconciled with current behavior

## Required Agents

Start from the size table in `references/subagent-dispatch.md`, then add risk-driven roles:

- `security` gate: load `assistant-security`
- `refactor/migration/rewrite` gate: include Explorer for behavior tracing when parity is not fully test-covered
- `config/infra` gate: include Builder/Tester smoke or dry-run verification
- `docs-only`: no Code Writer/Builder handoff unless runnable examples or generated docs change

If required agents differ from the standard size flow, record the reason in the task journal. Required agents name role responsibilities; `Subagent execution mode` determines whether those roles are delegated or performed as direct fallback evidence.
