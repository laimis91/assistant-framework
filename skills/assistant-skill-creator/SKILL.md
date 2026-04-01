---
name: assistant-skill-creator
description: "This skill creates new V1 skills with proper contracts, phase gates, and handoffs following the contract design guide. Use when the user says 'create skill', 'new skill', 'add contracts', 'skill contracts', 'scaffold skill'. Also activates when validating existing skill contract compliance."
effort: medium
requires:
  - assistant-memory
triggers:
  - pattern: "create skill|new skill|add contracts|skill contracts|scaffold skill|create a skill|make a skill|build a skill"
    priority: 75
    min_words: 3
    reminder: "This request matches assistant-skill-creator. You MUST invoke the Skill tool with skill='assistant-skill-creator' BEFORE creating skill files directly."
---

# Skill Creator

Create V1 framework skills with proper contracts following the [contract design guide](references/skill-contract-design-guide.md). Think of this skill as a blueprint printer — you describe what you want the skill to do, and it produces the full directory structure with typed contracts.

## Contracts

| Contract | File | Purpose |
|---|---|---|
| **Input** | `contracts/input.yaml` | Fields to resolve before starting |
| **Output** | `contracts/output.yaml` | Artifacts that must exist when done |
| **Phase Gates** | `contracts/phase-gates.yaml` | Assertions at each phase transition |

## Phases

```
CAPTURE → DESIGN → BUILD → VALIDATE
```

### Phase 1: CAPTURE — Understand the Skill

> **Existing skill shortcut:** If `existing_skill_path` is provided, skip this phase entirely. Read the existing SKILL.md to extract skill_name, purpose, category, and triggers, then proceed directly to DESIGN.

Gather the following from the user (or infer from context):

1. **Skill name** — `kebab-case`, prefixed with domain (`assistant-`, `unity-`, etc.)
2. **Purpose** — One sentence: what does this skill enable the agent to do?
3. **Category** — Process, Analysis, or Utility (determines contract tier):

| Category | When to use | Contract files |
|---|---|---|
| **Process** | Multi-phase, subagent dispatch, approval gates | input + output + phase-gates + handoffs |
| **Analysis** | Multi-step pipeline, no subagents | input + output + phase-gates |
| **Utility** | Single-pass: accept input, produce output | input + output |

4. **Triggers** — What user phrases should activate this skill?
5. **Dependencies** — Does it require other skills? (e.g., `assistant-memory`)
6. **Effort** — low, medium, or high

If the user has a vague idea, help them sharpen it:
- "What should the skill produce as output?"
- "Is this a multi-step process or a single operation?"
- "What phrases would a user say when they need this?"

Print: `--- PHASE: CAPTURE COMPLETE ---`

### Phase 2: DESIGN — Design the Contracts

Read `references/skill-contract-design-guide.md` for the full schema reference. Then design contracts for the skill.

#### For ALL skills (input + output):

**Input contract** — What does the skill need to start?
- Identify 3-8 input fields
- Each field needs: name, type, required, description, on_missing
- Required fields MUST have `on_missing` actions (ask, infer, skip, fail)
- Enum types MUST list all valid values
- Add `examples:` for ambiguous fields
- Add `infer_from:` when the agent can derive a value

**Output contract** — What must the skill produce?
- Identify 2-6 output artifacts
- Each artifact needs: name, type, required, description
- Conditional artifacts use `condition:` to scope when they're needed
- Include `on_fail:` for required artifacts

#### For Process and Analysis skills (add phase-gates):

**Phase gates** — What must be true at each transition?
- Binary assertions only — "X is true" or "X is false"
- Each assertion: id, check (plain English), on_fail (actionable corrective action)
- "fix it" is NOT an actionable corrective action
- Add cross-phase invariants for things that must ALWAYS be true

#### For Process skills (add handoffs):

**Handoffs** — What data flows between subagents?
- Define from/to roles
- `context_fields` — what the orchestrator sends
- `return_fields` — what the subagent must return
- Producer's `return_fields` must satisfy consumer's `context_fields`

#### For Process skills with evaluation loops:

If the skill includes a multi-round loop (review, refinement, optimization), read `references/harness-patterns.md` and apply the relevant patterns:

| Pattern | When to Apply |
|---|---|
| **Rubric Scoring** | Loop evaluates quality against criteria |
| **Drift Detection** | Loop runs 2+ rounds with scoring |
| **Harness Gates** | Loop must complete before task finishes |
| **Generation/Evaluation Separation** | One agent creates, another evaluates |

These patterns add rubric return fields to handoffs, drift invariants to phase-gates, and score progression to output contracts. Most loop-based Process skills will use all four.

Present the contract design to the user for review before building.

Print: `--- PHASE: DESIGN COMPLETE ---`

### Phase 3: BUILD — Create the Files

Create the skill directory under `skills/`:

```
skills/<skill-name>/
  SKILL.md              # Entry point with YAML frontmatter
  contracts/
    input.yaml          # Always
    output.yaml         # Always
    phase-gates.yaml    # Process + Analysis only
    handoffs.yaml       # Process only
```

#### SKILL.md structure:

```yaml
---
name: <skill-name>
description: "<what it does>. <when to trigger>. Triggers on: '<trigger phrases>'."
effort: <low|medium|high>
requires:              # optional
  - <dependency>
triggers:
  - pattern: "<regex pattern for routing>"
    priority: <40-90>
    min_words: <2-5>
    reminder: "This request matches <skill-name>. You MUST invoke the Skill tool with skill='<skill-name>' BEFORE proceeding."
---
```

Body structure:
1. **Contracts table** — Link to contract files with one-line purpose
2. **Phases/Steps** — How the skill executes (phases for Process/Analysis, steps for Utility)
3. **References** — Pointers to sub-files loaded on demand

Keep SKILL.md under 500 lines. If longer, split into sub-files in `references/`.

#### Contract YAML structure:

Follow the schemas from the contract design guide exactly. Every contract file starts with:

```yaml
schema_version: "1.0"
contract: <input|output|phase-gates|handoffs>
skill: <skill-name>
```

Print: `--- PHASE: BUILD COMPLETE ---`

### Phase 4: VALIDATE — Check Against Design Guide Rules

Run through the 10 contract design guide rules as a checklist. Read `references/contract-design-checklist.md` for the full list.

**Must pass all 10:**

1. Required fields have `on_missing` actions
2. Enum types list all values (no open-ended enums)
3. Validation rules are plain English (no regex/code)
4. Phase gates are binary assertions (if applicable)
5. Handoff schemas match: producer return_fields satisfy consumer context_fields (if applicable)
6. Corrective actions are actionable (not "fix it")
7. Contracts are additive (new fields only)
8. Conditional fields use `condition:`
9. Ambiguous fields have `examples:`
10. Cross-phase invariants exist for drift prevention (if applicable)

If any rule fails: fix the contract, explain what was wrong, and re-check.

Present a summary of the created skill:
- File count and paths
- Contract tier (Process/Analysis/Utility)
- Field count per contract
- Phase count (if applicable)

Print: `--- PHASE: VALIDATE COMPLETE ---`

## References

- [Contract Design Guide](references/skill-contract-design-guide.md) — mandatory reading before designing contracts
- [Contract Design Checklist](references/contract-design-checklist.md) — validation checklist for Phase 4
- [Harness Patterns](references/harness-patterns.md) — rubric, drift detection, gates, and separation patterns for loop-based Process skills
- Existing skills in `skills/` — use as examples for your category tier

## Tips

- **Start simple.** A Utility skill with 3 input fields and 2 output artifacts is better than an over-designed Process skill. You can always add phases later.
- **Steal from existing skills.** Look at `assistant-memory` (Utility), `assistant-ideate` (Analysis), or `assistant-workflow` (Process) for your tier's pattern.
- **Descriptions are triggers.** The `description:` field in frontmatter is what the skill router uses for matching. Be specific about when to trigger — include example phrases.
- **Progressive loading matters.** SKILL.md loads into context whenever triggered. Keep it lean. Put detailed reference material in sub-files.
