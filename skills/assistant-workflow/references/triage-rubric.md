# Triage Rubric And Gate Packs

Use this during `--- PHASE: TRIAGE ---` before choosing phases. Triage produces structured metadata, not just a size label.

## Required Triage Output

Record these fields in the task journal for medium+ tasks and in the inline plan for small tasks:

- `Task type`: `feature`, `bugfix`, `refactor`, `migration`, `rewrite`, `config`, `infra`, `security`, `docs`, or `spike`
- `Risk tier`: `low`, `moderate`, `high`, or `critical`
- `Triaged as`: `small`, `medium`, `large`, or `mega`
- `Required agents`: the roles required by size and risk
- `Required gates`: the common gates plus every applicable task-category gate pack

## Size Rules

| Size | Use when |
|---|---|
| `small` | One localized change, clear behavior, low risk, existing verification path, no public contract/data/security impact. |
| `medium` | A feature, bugfix, refactor, endpoint, hook, or contract change spanning several files or one boundary. |
| `large` | Cross-module/layer work, public API/config/data behavior, weak baseline tests, or high uncertainty. |
| `mega` | Rewrite, migration, port, legacy-to-new-structure work, 10+ files across layers, or behavior parity across subsystems. |

Escalate size when risk exceeds file count. Auth, PII, payments, destructive data changes, public API changes, or behavior-preserving legacy migration are at least `large` unless discovery proves they are isolated and fully covered.

## Risk Tier Rules

| Risk tier | Use when |
|---|---|
| `low` | Local, reversible, tested, no public behavior or data impact. |
| `moderate` | Multiple files, shared helpers, unclear edge cases, or moderate verification work. |
| `high` | Public contracts, data shape, migration, behavior parity, security-sensitive paths, weak tests, or multi-layer coupling. |
| `critical` | Irreversible data loss risk, auth bypass, secret exposure, payment/security boundary, or production outage risk. |

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

If required agents differ from the standard size flow, record the reason in the task journal.
