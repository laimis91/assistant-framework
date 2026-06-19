# Artifact-First Output Contract

Use this before planning and building. A task is not ready for implementation until the deliverable is concrete enough to verify.

Avoid vague outputs such as "make it work", "write a report", or "improve the workflow". Name the artifact first, then plan backward from how it will be validated.

## Required contract

```text
Artifact Contract:
- Artifact type: code | docs | report | dataset | chart | slide_deck | plan | eval | PR | config | other
- Required files or deliverables: [exact paths or named external artifacts]
- Output format/schema: [markdown/json/yaml/csv/pdf/etc.]
- Acceptance criteria: [binary user-visible checks]
- Verification command or method: [command, inspection, manual validation, or review gate]
- Expected success signal: [exact passing output, created file, PR URL, green test, approved review]
- Owner/consumer: [user, reviewer, downstream tool, runtime]
- Non-goals/exclusions: [what must not be produced]
```

## Rules

- Put the artifact contract before task packets.
- Every medium+ task packet must map to at least one required artifact or acceptance criterion.
- If the artifact is a PR, include branch name, files in scope, validation commands, and review gates.
- If the artifact is a report/dataset/chart, include format, source policy, and completeness checks.
- If the artifact is code/config, include file paths and runnable verification.
- If no artifact is needed, record a no-op/discovery rationale and do not pretend implementation completed.
