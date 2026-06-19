# Review Finding to Permanent Rule

Use this at the end of review when a finding reveals a recurring process gap, missing contract, missing eval, missing checklist, or repeatable failure mode.

A review finding has two possible outcomes:

1. **One-off fix** — fix the current code or plan only.
2. **Permanent rule candidate** — add or update a checklist, contract, phase gate, eval, template, or skill guidance so the same class of failure is caught earlier next time.

Do not turn every nit into a rule. Promote only findings with evidence of recurrence, high impact, framework-level applicability, or a clear fake-pass risk.

## Classification packet

```text
Review Finding Rule Distillation:
- Finding: [short finding title]
- Evidence: [file/path/contract/eval/review evidence]
- Failure pattern: [what class of mistake this represents]
- Classification: one_off_fix | permanent_rule_candidate | no_action
- Rule target: checklist | input_contract | output_contract | phase_gate | handoff | eval | template | skill_reference | none
- Proposed rule: [plain-English rule]
- Verification/eval update: [how future runs catch it]
- Scope and exclusions: [where rule applies / does not apply]
- Promotion decision: promote | defer | reject
```

## Promotion rules

Promote when:

- the same issue appeared before or is likely to recur;
- a shallow/checklist-only response could pass without the new rule;
- the finding exposes missing verification, missing evidence, or missing contract coverage;
- the impact is high enough that future prevention is cheaper than repeated review comments.

Defer or reject when:

- it is pure style preference;
- it applies only to one file or one PR;
- it would create broad ceremony for rare low-risk work;
- evidence is insufficient.

## Output expectation

For every blocker or must-fix finding, include at least a short classification. For lower-severity findings, classify only when the issue is recurring or framework-level.
