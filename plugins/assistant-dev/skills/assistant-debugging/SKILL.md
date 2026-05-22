---
name: assistant-debugging
description: "This skill runs evidence-first debugging: reproduce, hypothesize, isolate, fix, and verify without random patching. Use when the user says 'debug', 'root cause', 'investigate failure', 'why is this broken', 'reproduce bug', 'flaky test', 'production issue', or when assistant-tdd cannot yet write a meaningful failing test because the failure mechanism is unknown."
effort: high
triggers:
  - pattern: "debug|root cause|investigate (failure|bug|issue)|why .* broken|reproduce (bug|issue)|flaky test|production issue|failing test|test failure"
    priority: 88
    reminder: "This request matches assistant-debugging. Load and follow this SKILL.md and its contracts before patching code. Reproduce and isolate root cause before fixing."
---

# Evidence-First Debugging

## Contracts

This skill enforces a reproduce -> hypothesize -> isolate -> fix -> verify loop. Read and follow the contract files in `contracts/` before executing.

| Contract | File | Purpose |
|---|---|---|
| **Input** | `contracts/input.yaml` | Symptom, scope, constraints, severity, and reproduction target |
| **Output** | `contracts/output.yaml` | Root cause, evidence, fix summary, verification, confidence, and residual risks |
| **Phase Gates** | `contracts/phase-gates.yaml` | Binary gates for reproduce, isolate, fix, and verify phases |
| **Handoffs** | `contracts/handoffs.yaml` | Optional investigator/fixer handoff schemas when delegation is available |

**Rules:**
- Resolve symptom and scope before making code changes.
- Reproduce or explain why reproduction is not currently possible before diagnosing.
- Maintain at least three plausible hypotheses unless fewer are justified by evidence.
- Prefer the cheapest/highest-signal diagnostic test first.
- Patch only after one hypothesis has evidence strong enough to identify a root cause or bounded fix target.
- Verify the fix with the original reproduction plus regression checks.

## Goal

Find and fix the real cause of a failure with minimum churn. The user should receive a clear explanation of what broke, why it broke, how it was fixed, and what evidence proves it.

## Success Criteria

- The observed symptom is captured with source, command, error, or user-visible behavior.
- Reproduction evidence exists, or a specific blocker explains why it cannot be reproduced yet.
- Hypotheses are ranked by likelihood and diagnostic value, with disconfirming evidence tracked.
- Root cause is supported by code/config/runtime evidence rather than guesses.
- The fix is the smallest durable change that addresses the cause, not just the symptom.
- Verification includes the original failure path and at least one regression or adjacent-surface check when feasible.

## Constraints

- Company-safe by default: use local files, local commands, and repo-native diagnostics; do not require external SaaS or unapproved installs.
- Do not leak secrets, customer data, tokens, hostnames, or private payloads in the report; redact values and cite safe locations.
- Do not run destructive diagnostics, data migrations, deletes, network probes, or production-affecting commands without explicit approval.
- Do not randomly edit likely files. Each edit must trace back to a confirmed or strongly supported hypothesis.
- Do not claim root cause when evidence only supports mitigation; label mitigations as such.
- Ask only when missing environment, data, or permission materially blocks reproduction or diagnosis and cannot be inferred locally.

## Phase Workflow

### 1. Scope

Capture:
- symptom and expected behavior
- affected command, test, endpoint, workflow, or user path
- recent changes if discoverable from git/diff/logs
- environment constraints and safety boundaries
- severity: low, medium, high, or critical

If the user gives a vague report, inspect local context first. Ask only when the missing detail changes what you can safely run or inspect.

### 2. Reproduce

Try the smallest safe reproduction:
- run the failing test or command
- inspect the supplied stack trace/log line
- run a narrow script or request against local/dev environment
- create a minimal characterization test when appropriate

Valid reproduction evidence includes command, input, observed result, and why it matches the reported symptom. If reproduction is blocked, record the exact blocker and continue only with evidence available from logs/code/config.

### 3. Hypothesize

List at least three plausible causes unless evidence narrows the space. For each hypothesis include:
- cause statement
- supporting evidence
- disconfirming evidence or what would refute it
- next diagnostic check
- expected signal if true

Rank by a mix of likelihood, diagnostic cost, and blast-radius risk. Run the cheapest/highest-signal check first, not the most convenient patch.

### 4. Isolate

Use diagnostics to eliminate hypotheses:
- compare expected vs actual code path
- inspect boundary inputs/outputs
- bisect recent changes when useful
- add temporary logs only locally and remove them unless explicitly intended
- write a failing regression test once the failure mechanism is understood

Stop when one hypothesis is confirmed strongly enough to explain the symptom and predict the fix.

### 5. Fix

Apply the smallest durable fix:
- address the cause, not only the thrown error
- preserve public contracts unless an approved breaking change is required
- add or update tests when behavior changes
- avoid opportunistic refactors unless they directly reduce the confirmed failure risk

When the correct fix is uncertain but mitigation is necessary, label the change as a mitigation and record follow-up risk.

### 6. Verify

Run:
- the original reproduction path
- focused test or command covering the fix
- relevant regression checks
- static/lint/build checks when normally required by the project

If a check cannot run, record why and provide the closest safe alternative. Do not count skipped checks as proof.

## Relationship to TDD and Workflow

- Use `assistant-debugging` before `assistant-tdd` when the bug cannot yet be reproduced with a meaningful failing test.
- Once the failure mechanism is understood, prefer a regression test and then use the `assistant-tdd` bug-fix pattern when feasible.
- In `assistant-workflow`, this skill belongs in Discovery/Build for bugfix tasks before implementation if root cause is unknown.
- Use `assistant-review` after the fix when the change is non-trivial or touches risky surfaces.

## Output

Return:
- **Status** - fixed, root_cause_found, mitigated, not_reproduced, blocked, or inconclusive.
- **Symptom** - observed failure and expected behavior.
- **Reproduction** - command/input/result or blocker.
- **Hypotheses** - ranked hypotheses with evidence and diagnostic results.
- **Root cause** - confirmed cause, confidence, and evidence.
- **Fix** - changed files and why the fix addresses the cause.
- **Verification** - commands/checks and pass/fail outcomes.
- **Residual risks** - remaining uncertainty, skipped checks, follow-ups.

## Stop Rules

- Stop before editing if the failure cannot be reproduced or bounded and edits would be speculative.
- Stop and ask before any destructive, production-affecting, or sensitive-data diagnostic.
- Stop if all hypotheses are refuted and gather new evidence instead of cycling guesses.
- Stop after mitigation if confidence is insufficient for a root-cause claim.

## Common Pitfalls

1. **Patching before reproduction.** This often fixes a visible symptom while hiding the real failure.
2. **One-hypothesis debugging.** The first theory is usually biased by the stack trace or last edited file.
3. **Ignoring disconfirming evidence.** A hypothesis survives only if it predicts observed behavior and withstands checks.
4. **Treating skipped tests as green.** Skipped or unavailable checks are residual risk, not validation.
5. **Adding permanent noisy logging.** Temporary diagnostics should be removed unless explicitly useful and approved.
6. **Over-refactoring during fixes.** Debugging fixes should minimize changed surface unless the refactor directly removes the cause.
7. **Claiming certainty from weak evidence.** Use `mitigated` or `inconclusive` when proof is incomplete.
