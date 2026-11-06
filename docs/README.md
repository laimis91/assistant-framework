# Documentation map

Start here for repository work. Select the relevant topic below and read only its guide, specification and owning source. Root `skills/assistant-*` files are editable source; installed skill copies and generated references are distribution views.

## Find the right document

| Task | Read | Update with changes to |
|---|---|---|
| Install, configure or understand the framework | [Repository README](../README.md) | Supported installation, user commands and public capabilities |
| Understand durable requirements or design rationale | [Specifications](specs/README.md) | The affected specification and its current implementation status |
| Create or change skills and contracts | [Skill contract design guide](skill-contract-design-guide.md) | Skill authoring rules; regenerate its portable mirror using the command in that guide |
| Change harness, review or recovery guidance | [Harness design guide](harness-design-guide.md) | Its documented controls, artifacts and role boundaries |
| Diagnose missing native delegation | [Subagent troubleshooting](troubleshooting-subagents.md) | Role definitions, dispatch prerequisites and installation verification |
| Use or change the optional local pattern library | [Pattern library](pattern-library.md) | Its configuration, commands and bounded lookup behavior |
| Validate skills, run evals or interpret evidence | [Evaluation documentation](evals/README.md) | The owning topic guide, runner/schema and affected fixture controls |
| Investigate earlier decisions | [Historical material](#historical-material) | Preserve the original dated claim; place current guidance with its owner above |

## Source and status

Specifications record durable requirements and rationale. Source, contracts, configuration and actual verification establish what is implemented. A spec may describe a proposal: keep intended, implemented and historical behavior explicit. If source and an accepted requirement disagree, resolve the discrepancy in the change instead of silently treating either as current truth.

Skill-local contracts own exact serialized rules. Link to them rather than copying their schemas into documentation. Check the current source before reusing a dated audit, old source manifest or prior passing result. Documentation navigation is guidance; it does not prove native agent compliance.

## Update documentation with the change

1. During discovery, use the table and [specification index](specs/README.md) to identify the affected durable requirements, guide and source owner.
2. For a feature or relevant bug fix, update the affected spec and canonical guide in the same change when their documented behavior, commands, constraints or examples change. For an internal correction that leaves them accurate, record a concrete no-documentation-change reason in the handoff.
3. Check changed claims against source and relevant verification. Update links/anchors when moving content. Add each new durable document to the owning index, with status and when to read/update it.
4. Before completion, report the documentation paths updated or the reason an update was unnecessary. Keep current guidance in its owning document; avoid a separate report for every fix.

Development plans, implementation sequences, journals and per-run evidence belong in local ignored task state, normally `.codex/`. The legacy `docs/plans/` directory is ignored for existing local work. Commit durable specifications under `docs/specs/`, together with selected provenance needed to understand them. Never promote a plan to a specification merely by renaming it. Reusable plan templates and synthetic test fixtures remain maintained framework source, rather than development plans for this repository.

## Research notes

Research and proposals that inform later work. They are not implemented behavior; verify against source before relying on them.

| Document | Status and when to read |
|---|---|
| [Skill activation research, 2026-11-02](research/skill-activation-research-2026-11-02.md) | Research note; the adopted requirements and measured results are in the [specification](specs/skill-activation.md). Read before rewriting skill descriptions, adding activation evals or changing skill-routing instructions. |
| [Review techniques catalog, 2026-10-28](research/review-techniques-catalog-2026-10-28.md) | Research input for `assistant-review` references. Read when extending review coverage. |
| [Framework value assessment, 2026-10-26](research/assistant-framework-value-assessment-2026-10-26.md) | Proposal, not implemented; its status section records what later commits changed. Read before specifying the planned skill improvements, new skills or the Telos/Diagrams retirement. |

## Historical material

These files retain dated context, not current capability, policy, approval or roadmap authority. Read them only for a relevant historical question.

| Material | Purpose |
|---|---|
| [Cleanup audit, 2026-06-25](cleanup-audit-2026-06-25.md) | Previous cleanup inventory and decisions |
| [Guidance audit, 2026-07-03](agent-guidance-violation-audit-2026-07-03.md) and [follow-up review, 2026-07-04](agent-guidance-clean-review-2026-07-04.md) | Findings and remediation evidence for the former architecture |
| [Eight-priority handoff, 2026-07-12](assistant-framework-priority-handoff-2026-07-12.md) | Earlier architecture, verification and runtime-evidence boundaries |
| [v0.2 research](v0.2.0-research.md) and [v0.3 research](v0.3.0-research-improvements.md) | Historical recommendations, including retired mechanisms |
| [Presentation text](presentation.md) and [v0.2 slide deck](Assistant-Framework-v0.2.0.pptx) | Presentation material; verify claims against current source before reuse |

Eval schemas, frozen fixture projects and variant assets under `evals/` are consumed test inputs. They are navigated through the eval guides and retain their existing paths. Historical preparation JSON under `specs/` retains original identities and baseline hashes; its directory index explains migration and limits.
