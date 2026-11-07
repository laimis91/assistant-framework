# S01 — Request alignment and focused delivery

Status: **Accepted by the user**, 2026-11-06 (drafted and revised the same day). Baseline: main d11756d. Implemented in main b77a1e8 (#85); matched evaluation pending user authorization.
Source: report sections "Recommended direction", "Status against main", "High priority: broad analysis, focused answers" (sdlc-review, claude-design, combined method), §4 order 1, §6 rows 13 and 25; slice map row S01.

## Problem and intended outcome

Formal code review already reconciles the original request against delivery, but nothing earlier in the chain does. Research answers, Docs output, and Workflow preparation artifacts (specifications, plans, Jira tickets) and ordinary handoffs are not organized around the user's requested decisions and deliverables. Broad investigation can therefore crowd out a direct answer: the source report itself let framework-overhead analysis displace the per-skill answers the user asked for (report "High priority" section). The intended result: each requested outcome gets a direct, locatable answer. Material evidence, risks and counterevidence stay with the claims they support. Broader findings stay available where they help, and tangents that change no answer, rationale or limit are left out. The goal is relevance and decision usefulness, not brevity.

## Shared definitions (referenced by other slices)

These terms, together with the coverage and relevance checks, are defined once, in the shared outcome guidance (R-S01-1). Other slices and skills cite them by name and do not restate them; skill text adds only application to its own outputs.

- **Requested outcome**: a decision, deliverable, answer or acceptance item that the user's request (or an approved plan or ticket the request points to) explicitly or necessarily asks for. Examples: "the benefit of each skill" in a research request, an acceptance criterion in a ticket, an open question a spec must settle, a changed file plus "tell me whether other callers are affected" in a coding request.
- **Direct answer**: a statement that resolves a requested outcome. It may be a qualified answer ("cannot be determined because X; next step Y"). Leading with or citing analysis without stating the answer does not count.
- **Material support**: evidence, risks, counterevidence, uncertainty and limits that could change an answer, its rationale, or the reader's next action.
- **Coverage check**: a comparison of the complete draft with the original request before delivery. It flags any requested outcome that has no direct answer, any changed meaning, and any unrequested scope presented as if it had been requested.
- **Relevance check**: each major section has a stated or evident role in answering a requested outcome or carrying its material support. Content that does neither is moved to a supporting section or removed.

## Requirements

- **R-S01-1 Single authoritative wording.** The shared outcome guidance (`tools/progress/operating-guidance.md`) is the single owner of the whole reusable request-alignment method, stated compactly: the five definitions above, plus the coverage check and the relevance check, in the order identify requested outcomes → investigate as broadly as useful → present direct answers first → run the coverage and relevance checks. Each consuming skill (Research, Workflow, Docs, and Review's Document Review Checklist) holds only application text for its own outputs, with its own examples, and links to the guide for the method. No skill restates the definitions, the checks or the method sequence (D1, resolved).
- **R-S01-2 Identify before investigating.** Before substantive investigation or drafting, the agent establishes the requested outcomes from the request and any material it points to (ticket, plan, spec, prior decisions). This is an internal step and does not by itself produce a question to the user. Existing clarification rules (`operating-guidance.md:3-9`, Workflow `SKILL.md:26-31`) still decide whether to ask.
- **R-S01-3 Broad investigation preserved.** Request alignment does not narrow the investigation. Discovery of alternatives, hidden costs, risks and counterevidence continues wherever it could change a recommendation. Findings outside the requested outcomes that are material (they change an answer, a rationale or a consequential limit) are reported, labelled as additional findings.
- **R-S01-4 Direct answers first.** The delivered output presents the direct answer for each requested outcome before or alongside its supporting analysis, and the reader can find it without reading unrelated sections. With several requested outcomes, the structure follows them (one section, row or item per outcome) unless the user or the target format requires a different structure.
- **R-S01-5 Material support retained.** Material support stays next to the claim it supports, even when that makes the answer longer. A coverage or relevance edit never removes a material risk, counterevidence item, conflict, gap or limit.
- **R-S01-6 Coverage and relevance checks before delivery.** Before delivery, the agent runs the coverage check and the relevance check on the complete draft and repairs what they find: add the missing direct answer, restore changed meaning, label or remove unrequested scope, move or remove tangents. A requested outcome that cannot be answered is reported as unanswered, with the reason and the next step.
- **R-S01-7 Research application.** Research answers are organized around the requested outcomes and lead with the requested conclusions or recommendations. Claim-level citations, evidence quality, conflicts and gaps (`assistant-research/SKILL.md:25-28`) stay attached to the answers they qualify. Broader context goes in supporting sections.
- **R-S01-8 Workflow application.** Workflow applies R-S01-2 to R-S01-6 to the artifacts it writes for the user: preparation results, specifications, plans, Jira ticket text and the ordinary handoff. A plan or spec answers each open question the request raised or lists it as an unresolved decision. A ticket's acceptance criteria cover each requested behaviour. The handoff answers each question the user asked as well as describing the change. Existing formal reconciliation is unchanged (see Existing behaviour).
- **R-S01-9 Docs application.** Docs output serves the requested reader task: each section has a role for the stated audience and purpose. Unrequested sections, filler and decorative content are left out. Additions the user did not request that would materially help are proposed, not silently added. Placeholder or unverified text is marked as such (adapted from claude-design Content Discipline, `claude-design/SKILL.md:399-415`).
- **R-S01-10 Review only where review already applies.** Review does not become a new mandatory step for Research, Docs or ordinary outputs. Where review already applies, the Document Review Checklist intent item (`review-checklists.md:144`) and the existing request/plan reconciliation use the canonical coverage check by reference. A requested outcome with no direct answer and unrequested scope presented as requested are reportable findings. No duplicate checklist is added.
- **R-S01-11 No new machinery.** The change adds no mandatory ledger, schema field, section template, heading quota, word or character target, reviewer, round or controller. Human outputs need not show the coverage check unless a gap remains. Structured consumers keep their existing serialized fields.

## Existing behaviour to preserve

- The common outcome guidance establishes intended result, purpose, consumer, constraints and evidence, and asks only about consequential choices (`tools/progress/operating-guidance.md:3-18`). It is loaded for every activity through the managed instruction block (`install.sh:1103`), so any addition there is loaded every turn.
- Research: evidence quality, claim-adjacent citations, conflicts and gaps, omit empty sections (`skills/assistant-research/SKILL.md:13-28`); high-impact qualification (`:30-34`); five-lens method and its independence obligations (`:42-60`); structured consumer and compatibility fixtures, including tier/source-count rules (`:62-73`, `contracts/input.yaml:25-30,85`).
- Workflow: inspect callers and consumers before scoping (`skills/assistant-workflow/SKILL.md:17-22`); ask only about remaining material choices (`:26-31`); handoff contents and "omit empty sections" (`:56-58`); medium+/strict `final-handoff.md` sections, including requirement evidence (`references/final-handoff.md:12-30`).
- Formal request reconciliation already exists for code changes of every size. The final acceptance review owns request/plan/delivery reconciliation (`skills/assistant-review/SKILL.md:98-105`; `skills/assistant-workflow/references/prompts/spec-review.md:5,17`), and plan review checks original requirements (`assistant-review/SKILL.md:100-102`; `assistant-workflow/contracts/phase-gates.yaml:373`).
- Review's Document Review Checklist: intent, gaps, plan versus code, ticket, tests (`skills/assistant-review/references/review-checklists.md:142-148`). It is triggered for specification, plan, ticket or test material (`contracts/handoffs.yaml:64-65`). Jira write-back needs approval (`review-checklists.md:147`).
- Docs: source-backed claims, no invented content, canonical links over duplicate prose, "keep only sections useful to the intended reader" (`skills/assistant-docs/SKILL.md:26-28`); schema v4 structured consumers (`:34-40`).
- Existing eval fixtures that assert output shape: Research `technology-comparison-uses-standard-tier` (expects tier naming and confidence-scored findings, `skills/assistant-research/evals/cases.json`); Review `document-review-applies-spec-review-and-document-checklist` (`skills/assistant-review/evals/cases.json:2429`); framework case `requirements-map-through-completion` (`docs/evals/framework-instruction-cases.json`).

## Scope and non-goals

In scope: the shared outcome guidance; Research root and, if needed, `research.md`; Workflow root and the references that shape preparation, plan, ticket and handoff output; Docs root; Review checklist cross-reference; focused fixture updates; the bounded matched evaluation below.

Out of scope and not imported:
- From sdlc-review: Kanban tools and APIs, round-numbered lens scheduling, another mandatory reviewer, and a task ledger (report "sdlc-review" section; `sdlc-review/SKILL.md:55-67`). Its varied-lens review idea belongs to S05.
- From claude-design: the visual taste manual, slop scoring, hosted-tool assumptions and a blanket HTML preference (report §6 row 25).
- Universal section, heading, word-count or "Done when" formats (report §3, "New mandatory formatting rules").
- Changing Review's formal reconciliation contracts, Research/Docs serialized schemas, or clarification thresholds.
- Brevity as a goal in itself. Word counts may be recorded only as measurements.

## Affected owners and consumers

| Owner | Change | Compatibility concern |
|---|---|---|
| `tools/progress/operating-guidance.md` | Sole owner of the compact reusable method: the five definitions and the coverage and relevance checks (D1 resolved) | Loaded for every activity by every skill and the managed block. Also edited by S02, so coordinate. |
| `skills/assistant-research/SKILL.md` (+ `research.md` if needed) | Application to research answers | `technology-comparison-uses-standard-tier` and five-lens fixtures must still pass. Five-lens synthesis structure is unchanged. |
| `skills/assistant-workflow/SKILL.md`, preparation/plan/handoff references (`final-handoff.md`, `plan-template.md` or `references/plans/prepare-only.md` as the plan decides) | Application to artifacts and handoff | Generated phase views (`references/phases/`) must be regenerated if `phases.md` changes. Workflow contracts are unchanged. |
| `skills/assistant-docs/SKILL.md` | Application to documentation | Overlaps the S02 Docs editing checklist, which owns sentence-level editing. S01 owns coverage and relevance. |
| `skills/assistant-review/references/review-checklists.md` | Intent item cites the canonical coverage check | Must not duplicate the definitions. The `handoffs.yaml` checklist condition is unchanged. |
| Skill-creator guide parity, `tools/skills/validate-skills.sh` | Skill edits follow the contract design guide | No new contract fields. |
| `docs/evals/framework-instruction-cases.json` or a new local eval bundle | Matched evaluation cases | See Verification. |

## Evidence classification

| Item | behavior_status | work_status | Evidence |
|---|---|---|---|
| Common outcome guidance (intent, consumer, evidence) | existing_behavior_to_preserve | no_open_decision | `operating-guidance.md:3-18` |
| Formal request/plan/delivery reconciliation in Review | existing_behavior_to_preserve | no_open_decision | `assistant-review/SKILL.md:98-105`; `spec-review.md:17` |
| Document Review Checklist | existing_behavior_to_preserve | implementation_gap (cross-reference only) | `review-checklists.md:142-148` |
| Requested-outcome identification before investigating | new_behavior | implementation_gap | Not found: searched skills and `tools/progress` for "requested outcome", "requested deliverable", "request coverage". Only review-time reconciliation exists. |
| Direct answers first; relevance check | new_behavior | implementation_gap | Docs has a partial rule (`assistant-docs/SKILL.md:28`); Research has none |
| Location of canonical wording | new_behavior | no_open_decision | D1 resolved by the coordinator: the common guide owns definitions and checks; skills hold application text only. Per-turn loading via the managed block `install.sh:1100-1103`. |
| Research output shape fixtures (tier, confidence) | existing_behavior_to_preserve | technical_design_decision | `research/evals/cases.json` `technology-comparison-uses-standard-tier`; `contracts/input.yaml:25-30` |
| Benefit of the change | materially_unknown | evidence_gap | Report: "not measured in a new behavioral comparison". The matched evaluation addresses this. |

## Unresolved decisions

- **D1 Where the canonical wording lives — resolved by the coordinator (2026-11-06).** Options considered: (a) a short section in `operating-guidance.md`, already loaded by every skill; (b) a new `tools/progress/request-alignment.md`, linked from the guide and loaded by Research, Workflow, Docs and Review. **Resolution: (a), in compact form.** The common guide owns the five definitions and the coverage and relevance checks; that is the whole reusable method, so it has a single owner. Each consuming skill (Research, Workflow, Docs, Review's Document Review Checklist) holds only application text for its own outputs and its own examples, never a restated method. Reason: the report places "a compact check in the existing common outcome guidance"; the guide is loaded on every turn through the installer managed block (`install.sh:1100-1103`), so the method is always available without a new load path, while skill-specific application and examples stay out of every-turn loading. **Coordinator note (2026-11-06, updated):** the guide is limited to the definitions and the two checks stated compactly; application wording and examples go in the consuming skills, which link to the guide and do not restate the method or its procedure.
- **D2 Research fixture that requires confidence-scored output (technical default, coordinate with S02/S07).** `technology-comparison-uses-standard-tier` expects tier naming and "confidence-scored findings". The root now treats tiers as compatibility fixtures and confidence as claim-specific (`SKILL.md:71-73`; `research.md:4-5`). Recommended: keep the fixture passing (S01 does not require removing either element). The tension is owned by S07 (S07 Unresolved decision 6, recommended default: keep the fixture unchanged), which owns research presentation of provenance.
- **D3 Ticket/spec/plan outputs outside Workflow (product_question).** Should request alignment also apply when the user asks for a Jira ticket or spec without a repository change (no Workflow activation)? Recommended: yes. The shared guide applies to every activity, so no new routing is needed. Confirm that this is the intended reach. **Decided by user 2026-11-06:** yes, request alignment applies to tickets and specifications written without Workflow too (the recommended default).
- **D4 Held-out evaluation cases in the repository (technical default).** Recommended: commit development cases and the rubric. Keep held-out cases and oracles local and sealed until the candidate identity is frozen, then commit them with the result summary, as the expert-method pilot did.
- **D5 Evaluation run allowance (technical default).** Recommended: at most 12 charged subject starts (6 cases × 2 conditions, single trial), counting failed or partial starts, with no replacement runs. This matches the pilot precedent. It is a resource bound, not a text budget.

## Acceptance examples

- **R-S01-1.** Pass: Research, Workflow, Docs and Review's Document Review Checklist each link to the shared guide and add only application wording and examples for their own outputs. Fail: Research and Docs each carry their own paraphrased definition of "requested outcome", or Workflow restates the coverage-check procedure step by step.
- **R-S01-2/R-S01-3.** Pass: asked "for each of the 16 skills: benefit, improvements, removal, value vs cost", the agent lists those four outcomes per skill, still investigates instruction overhead, and reports overhead as an additional finding where it changes a removal recommendation. Fail: the agent drops the overhead investigation because it is "not requested", and a removal recommendation loses its cost rationale.
- **R-S01-4.** Pass: the per-skill table gives the four answers per row; supporting analysis follows. Fail (broad but unfocused): a long overhead analysis comes first, and two skills' "value vs cost" answers can only be inferred from it.
- **R-S01-5.** Pass: a shorter revision keeps "no behavioural comparison was run" next to the savings claim. Fail (concise but lossy): the revision is tighter but drops that limitation, so the savings claim reads as measured.
- **R-S01-6.** Pass: a draft spec omits one open question raised in the request; the coverage check adds it as an answer or an unresolved decision before delivery. Fail: the spec is delivered without it, or with an answer to a different question.
- **R-S01-8.** Pass: for "fix the null check and tell me whether other callers have the same bug", the handoff states the fix, its verification and a direct answer about the other callers, with evidence. Fail: the handoff describes the fix and test results only.
- **R-S01-8 (ticket).** Pass: a ticket drafted from a brief with three requested behaviours has acceptance criteria covering all three, and an unrequested fourth item is marked as a proposal. Fail: the fourth item appears as a criterion, or one requested behaviour has no criterion.
- **R-S01-9.** Pass: a README update for "how to install on Windows" adds that section, marks an unverified PowerShell step for review, and proposes, without adding, a troubleshooting section. Fail: it adds an unrequested feature grid and an unverified compatibility claim.
- **R-S01-10.** Pass: in a document review that already applies, a plan that omits a requested migration step yields a finding that cites the coverage check. Fail: Research acquires a mandatory review step, or `review-checklists.md` gains a second copy of the definitions.
- **R-S01-11.** Pass: no new contract field, heading quota or word target appears in the diff. Fail: a "Requested outcomes" section becomes mandatory in every response.

## Verification

Focused checks: `tools/skills/validate-skills.sh`; `./tests/test-p0-p4-contracts.sh` (in particular the review checklist, docs and research suites); `tools/evals/run-skill-evals.sh --validate-fixture` for the Research, Docs and Review fixtures; `tools/evals/run-framework-instruction-evals.sh --validate-fixture` if cases are added there. Source check: grep shows the definitions in one file only, and every application site links to it.

### Bounded matched evaluation

Precedent: `docs/plans/expert-method-pilot/` (local) — `plan.md`, `conditions.md`, `rubric.md`.

- **Question.** Does the changed instruction tree produce outputs that answer every requested outcome while retaining material support, more often than the current tree, without losing material content?
- **Conditions.** *current*: the main d11756d instruction tree (shared guide plus target skill). *changed*: the frozen candidate tree. Both are supplied explicitly (controlled loading, not native activation), with equivalent dependency resolution. Each start uses a fresh context, the same model, runtime, tools, permissions and subject bytes. Record the SHA-256 of the shared guide and each target skill tree per condition. A skill-disabled condition is not required.
- **Cases (6, frozen before any subject run).** Each has a fixture workspace or supplied material, and a request with 3–5 requested outcomes plus a tempting broad tangent:
  1. *Research* — a multi-part comparison asking for each option's benefit, cost and a recommendation, with an attractive but non-decisive overhead tangent (modelled on the report's own failure).
  2. *Jira ticket* — draft a ticket from a brief with three requested behaviours, one dependency and one explicit exclusion.
  3. *Specification* — draft a short spec from a request that raises two open questions and one compatibility constraint.
  4. *Plan* — plan a code change where the user asks two decision questions (migrate or not; rollback path) in a small fixture repository.
  5. *Documentation* — update a README section for a stated reader task. The fixture contains one unverifiable claim and one material limitation.
  6. *Coding handoff* — a small fix in a fixture repository where the user also asks whether other callers are affected. The fixture has one other affected caller.

  Cases 1 and 4 are development cases. Cases 2, 3, 5 and 6 are sealed held-out cases (D4). Do not tune on held-out results.
- **Frozen oracles (grader-only).** Per case: (a) the list of requested outcomes, each with what counts as a direct answer (equivalent wording accepted); (b) material-support items that must remain (risk, counterevidence, limitation, unverifiable-claim marking, the other affected caller); (c) known tangents and fabricated-content traps; (d) for case 2, the unrequested item that must not appear as a requirement. Oracles define content, not wording, length or section titles.
- **Oracle discrimination check (before any subject run, no model needed).** For each case, author three frozen reference drafts: a *passing* draft; a *broad-but-unfocused* draft that contains all evidence but leads with the tangent and gives no locatable direct answer for at least one requested outcome; and a *concise-but-omitting* draft that is direct and tidy but omits one requested answer or one material-support item. The rubric must pass the first and fail both others. If either failing draft passes, the oracle is fixed before freezing. A model-run result does not count until this check passes.
- **Grading rubric (recorded per dimension; no weighted score, no word limits).**
  1. *Coverage*: each requested outcome — direct answer present / qualified-unanswerable with reason / missing / changed meaning.
  2. *Material support*: each oracle item retained / lost.
  3. *Relevance*: unrequested scope presented as requested (yes/no); tangents that change no answer present in the main answer (list). Moving material to a labelled supporting section is acceptable.
  4. *Calibration guard*: fabricated or unsupported claims, unauthorized actions or writes (any = material failure).
  5. *Observations*: tool/call counts, elapsed time and output word count as measurements only, if available. Absent telemetry is recorded as unavailable.
  
  A response **passes** a case when every requested outcome has a direct or qualified answer with no changed meaning, every material-support item is retained, no unrequested scope is presented as requested, and the calibration guard is clean. Grading is condition-blind: an independent fresh-context grader receives responses with condition labels removed.
- **Comparison and claim rule.** Report development and held-out results separately, per case and per dimension. The changed tree is supported only if it has no held-out case where it loses a material-support item or coverage that current had, and it passes at least as many held-out cases as current. Ties and inconclusive results are valid outcomes and are reported as such. A no-change candidate is a valid result.
- **Tooling reuse.** Record runs in the existing trace-result shape (`docs/evals/framework-instruction-trace-result.schema.json`) with `variant` baseline/candidate, and aggregate with `tools/evals/run-framework-instruction-evals.sh --compare-traces`. The Codex adapter and `instruction-overlay.py` handle only Workflow skill-root/`references`/`contracts` overlays (`docs/evals/codex-trials.md:52-84`). They cannot vary `tools/progress/operating-guidance.md`, so supply the condition trees explicitly as in the pilot `conditions.md`.
- **Limits.** Six constructed cases, one model, single trials and explicit loading. No claim about native activation, generalization, population-level quality, or token or time savings. The result supports or fails to support this specific change only.

## Dependencies and overlap

- **S02**: shares `operating-guidance.md`, Docs `SKILL.md` and README. S01's definitions land first. S02's Docs editing checklist cites S01 for coverage and relevance and owns only sentence-level editing. Land them in coordinated order (index "Foundation").
- **S05**: Review methods. S01 touches only the Document Review Checklist intent item and the cross-reference; varied review lenses from sdlc-review belong to S05.
- **S07**: Research provenance. S07 must preserve R-S01-7 placement (citations next to answers). D2 is coordinated with it.
- **S03, S04, S06, S08, S09**: their outputs (diagnoses, test plans, advisories, spike verdicts, UI QA reports) inherit R-S01-2 to R-S01-6 by citing the shared definitions, not restating them.
- **S10**: Docs/Workflow consumers of Diagrams. No conflict, but edits to Docs `SKILL.md` must be sequenced.
