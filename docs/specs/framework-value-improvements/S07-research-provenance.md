# S07 — Research provenance and recovery

Status: **Accepted by the user**, 2026-11-06 (drafted and revised the same day). Baseline: main d11756d. Implemented on branch `fvi/s07-research-provenance` (from main 7c9bdf8): new references `skills/assistant-research/source-provenance.md` (R-S07-1–6, R-S07-11; in the `five_lens` load set and linked from `SKILL.md` for substantial reports) and `skills/assistant-research/fetch-recovery.md` (R-S07-7–10; linked from `url-verify.md` on a failed fetch), five new eval cases in `skills/assistant-research/evals/cases.json`, one contract block in `tests/p0-p4/assistant-research-contracts.sh`, and two `README.md` file-tree lines for the new files (inventory only, no Research description). Decision 2 load-set outcome: only `source-provenance.md` joins a load set (`five_lens`); `source_research` and `investigate` stay unchanged for R-S07-6, and `fetch-recovery.md` loads only through `url-verify.md`. No v5 contract change. Live before/after spot checks not run (need user authorization).
Source: report §1 F "Research" (`docs/research/assistant-framework-value-assessment-2026-10-26.md:143-155`), §4 order 6 (`:216`), assessment rows 17–21 and 51 (`:290-294`, `:339`), and the §7 adjustment "Research is URL checking only" (`:352`). Slice map row S07 and "Report items not yet owned by a slice" (conditional adapt dispositions) in `docs/plans/framework-value-improvements/specification-index.md`.

## Problem and intended outcome

Research already requires near-claim citations, source identity, freshness checks, conflicts and verified URLs. It has no way to tie each citation back to the source actually retrieved, so in long reports a citation can drift to the wrong source or carry an invented identifier, and version or date details can be lost. When a fetch fails, `url-verify.md` simply drops the URL. There is no bounded way to find an official alternative or a dated snapshot, and no rule for rejecting HTTP 200 error or interstitial bodies. After this change, substantial reports should carry correctly attributed, dated and locatable sources. Failed retrievals should be recovered or reported as gaps within a bounded effort. A snapshot must never pass as the current page. Short answers should gain no new overhead.

## Requirements

- **R-S07-1** For a substantial report (trigger: Unresolved decision 1), Research registers each source when it retrieves it, before writing claims that rely on it. Each register entry records:
  - source identity (title and publisher or author);
  - a verified locator (a URL, or the existing safe stable locator for repository, authenticated or offline evidence);
  - the retrieval date;
  - whether the copy is live or a snapshot.
- **R-S07-2** The register is task-local: working notes or the draft itself. It is not a global, shared or persistent mutable ledger. It needs no new tool, file location, API key or numbering scheme. Any citation style works, provided each identifier maps to exactly one entry.
- **R-S07-3** Citations for version-sensitive or time-sensitive claims keep the version, edition, publication or last-updated date that the source states. When the source states none, the citation says it is undated instead of inferring a date.
- **R-S07-4** In a substantial report, each material claim's citation gives the supporting location in the source where the source has one: section, heading, page, line range or anchor. A quote or location shows where to look. It does not prove support by being present: the cited passage must actually support the claim, or the claim is downgraded or reported as a gap.
- **R-S07-5** Before delivering a substantial report, Research checks its citations:
  - every citation identifier in the draft resolves to exactly one register entry;
  - every source listed in the report matches its register entry (same locator, version or date, live or snapshot status).

  An unknown identifier or a mismatch is corrected, or the claim is removed or reported as a gap, before delivery.
- **R-S07-6** Ordinary short answers keep today's behaviour: near-claim citations and verification of presented URLs. They need no register, identifiers, location fields or citation check.
- **R-S07-7** When a source needed for a material claim cannot be retrieved (error status, timeout, block, paywall, login wall or interstitial), Research tries a bounded recovery before dropping it:
  1. official alternatives for the same content from the same publisher, such as a canonical or alternate URL, documentation source repository, release notes, PDF, feed, or a data or API endpoint serving the same content;
  2. an existing dated public snapshot from an archive service.

  Each route is tried at most once per source, and the same failing URL is not retried. Recovery stops at the first validated body. Exhausted routes become an explicit gap. Repeated unproductive work is governed by the shared stagnation guard.
- **R-S07-8** A retrieved body, live or recovered, counts only when its content matches the expected page: the expected title or claim-bearing text is present. An error page, rate-limit body, bot-check or CAPTCHA interstitial, redirect stub or login wall is rejected even when it returns HTTP 200. Status code and body size alone never count as success.
- **R-S07-9** Live-versus-snapshot provenance is always explicit. A snapshot citation names the archive and its capture date, is labelled as a snapshot, and is never presented as the live page or as the verified original URL. For current-state claims such as prices, "latest" versions, availability or status, a snapshot is context only: the claim is stated "as of <capture date>" or reported as a gap.
- **R-S07-10** Recovery keeps access boundaries. It does not bypass authentication, paywalls, CAPTCHAs or bot detection. It uses no proxy relays, adds no API-key or paid-service requirement, and does not send private, authenticated or non-public user-supplied URLs or content to third-party archive or render services. Requesting a new archive capture is an external write and needs the user's approval.
- **R-S07-11** In five-lens and other structured outputs, snapshot status, capture date, version or date and supporting location are recorded inside existing fields (`verification_detail`, `sources`, top-level `gaps`). This preserves the current v5.0 contracts. Any typed field would be a separately versioned contract change (Unresolved decision 4).

## Existing behaviour to preserve

- Evidence-calibrated answers that scale effort to decision risk: `skills/assistant-research/SKILL.md:13-14`. Source identity, freshness, applicability and disagreement checks: `:22`. Verify every presented URL or omit it, and use safe stable locators for repository, authenticated or offline evidence: `:22-24`. Citations close to claims, with observation, source statement, inference and unknowns kept distinct, and evidence quality judged rather than source counts: `:25-28`.
- Stop or qualify answers built on inaccessible, stale, conflicting or weak evidence; unverified URLs cannot be finalized: `SKILL.md:75-76`.
- Source method: identity, date and scope checks, and copies add no independent support (`research.md:7-12`). No source quotas (`research.md:4-5`, `:17-18`). URL and locator rules with no secrets, PII, private endpoints or host paths (`research.md:26-30`). Concise output without empty headings (`research.md:37-38`).
- URL verification process, and when verification is optional (user-provided, local and localhost URLs): `url-verify.md:6-24`. Behaviour changes only for failed fetches (R-S07-7).
- Five-lens method (v5): five sibling-blind lenses, root synthesis, separate peer, isolation requirements (`SKILL.md:42-60`, `five-lens-briefing.md:54-59`). Lens researchers verify every presented URL and never fabricate sources (`agents/claude/lens-researcher.md:15-23`).
- Structured v5.0 contracts:
  - `findings` with `sources`, conditional `source_provenance` and `verified_urls`, where every listed URL "was checked and returned a valid response" (`contracts/output.yaml:16-66`);
  - `verified_source_evidence` with method, reference and `verification_detail`, plus `verification_gaps` equal to top-level gaps (`contracts/handoffs.yaml:355-371`);
  - compatibility rules for historical v3 and v4 records (`SKILL.md:62-83`, `research.md:39-44`).
- Load sets: `url-verify.md` is loaded by `source_research`, `five_lens` and `investigate` (`contracts/index.yaml:43-97`).
- Existing eval `url-output-verifies-links` (`skills/assistant-research/evals/cases.json`) must keep passing.

## Scope and non-goals

In scope: provenance and citation-check guidance for substantial reports; a bounded failed-fetch recovery method with body validation and live-versus-snapshot labelling; small updates so `url-verify.md` and the research load sets point to that guidance; new focused eval cases.

Out of scope and not imported:
- mandatory numbered citations;
- per-sentence citation quotas or coverage thresholds;
- global or persistent mutable ledgers;
- new API-key, paid-service or proxy requirements, including the comparator's Jina route and proxy relays;
- treating quote presence as proof of support;
- any register, identifier or check overhead for short answers;
- the comparator's "Sources:" rendering script;
- multi-platform sweep fan-outs;
- automatic archive submission;
- fixed archive-domain rotation as a rule.

A helper script is not part of this slice (Unresolved decision 3).

## Affected owners and consumers

- `skills/assistant-research/`:
  - `SKILL.md`: one pointer line for substantial reports and failed fetches;
  - `url-verify.md`: replace "drop on error" with "drop after bounded recovery";
  - new focused reference file(s) (Unresolved decision 2);
  - `contracts/index.yaml`: add the new reference(s) to the `source_research`, `five_lens` and `investigate` load sets, or load them conditionally;
  - `evals/cases.json`: new cases.
- No input, output or handoff field changes, so `tools/evals/lib/research-semantic-validator.cjs`, `tests/p0-p4/lib/assistant-research-semantic-controls.cjs` and `tests/p0-p4/fixtures/research-v4-cases.json` are unaffected. If a pinned term in `tests/p0-p4/assistant-research-contracts.sh`, which reads `SKILL.md` and `research.md`, is reworded, the plan must keep or update that pin deliberately.
- `agents/claude/lens-researcher.md` (and its Codex counterpart) already defers to "the assistant-research URL-verification rule" (`:15`), so lenses inherit recovery through `url-verify.md` without an agent edit.
- Skill description: no change, so no activation-case change under `docs/specs/skill-activation.md`.
- Existing Research eval fixture `technology-comparison-uses-standard-tier` (`skills/assistant-research/evals/cases.json:62`). It expects "standard tier, confidence-scored findings, conflicts, and gaps" (`:65`) and tier logging (`:74-75`), under a structured v5 consumer setup (`:71`). The Research root now treats tiers as compatibility fixtures and confidence as claim-specific (`SKILL.md:71-73`; `research.md:4-5`). S01 D2 records this tension and delegates it to S07, which owns Research presentation of provenance. S07's provenance additions (dates, versions, locations, recovery gaps) must not make that fixture fail. See Unresolved decision 6.
- `README.md` Research wording. S02 R-S02-6 corrects README's Research description (`README.md:16`, `:506`, `:597`) and requires it to match S07's final Research presentation (S02 Dependencies). S07 adds no README text itself; it supplies the final presentation that S02's README wording must describe.

## Evidence classification

| Item | behavior_status | work_status | Evidence |
|---|---|---|---|
| Near-claim citations, source identity, freshness, conflicts | existing_behavior_to_preserve | no_open_decision | `SKILL.md:22-28`; `research.md:7-12` |
| Retrieval-time source register for substantial reports (R1–R2) | new_behavior | implementation_gap | Not found. Grep for "register\|ledger\|retriev" over `skills/assistant-research/*.md` finds none. |
| Version, date and undated labelling (R3) | explicit_change | implementation_gap | Date checking exists (`research.md:8`, `SKILL.md:22`). Nothing requires preserving it in citations. |
| Supporting location; quotes are not proof (R4) | new_behavior | implementation_gap | Not found. `SKILL.md:25-27` requires support assessment without locations. |
| Unknown or mismatched citation-ID check (R5) | new_behavior | implementation_gap | Not found for ordinary reports. Five-lens contracts check canonical identity only for structured output (`output.yaml:32,65`). |
| No overhead for short answers (R6) | existing_behavior_to_preserve | no_open_decision | `SKILL.md:13-14`; `research.md:20-21` |
| Failed-fetch recovery (R7) | explicit_change | implementation_gap | `url-verify.md:11` drops any 404, 403 or timeout URL with no recovery. |
| Error and interstitial body rejection (R8) | new_behavior | implementation_gap | Not found. `url-verify.md:12` checks topic match but does not name 200 interstitials. |
| Live-versus-snapshot provenance (R9) | new_behavior | implementation_gap | Grep for "archive\|wayback\|snapshot" (excluding packet/identity uses) over `skills/assistant-research`: none. |
| Access boundaries during recovery (R10) | existing_behavior_to_preserve (extended) | no_open_decision | Private endpoints and secrets are excluded (`research.md:28-29`). External actions need approval: shared guidance and `five-lens-briefing.md:64`. |
| Structured provenance within existing v5.0 fields (R11) | existing_behavior_to_preserve | technical_design_decision | `handoffs.yaml:355-371` (`verification_detail` is free text) |
| "Substantial report" trigger | materially_unknown | product_question | See Unresolved decision 1 |
| arxiv, youtube-content, competitor-news-monitor, llm-wiki adaptations | materially_unknown | product_question | See Unresolved decision 5 |

## Unresolved decisions

1. **What counts as a substantial report** (product_question). Options:
   - (a) a written report or document deliverable, any five-lens run, or an explicit request for checkable citations or fact-checking;
   - (b) also any answer that cites more than a handful of sources;
   - (c) only on explicit request.

   **Recommended default: (a).** It ties the overhead to deliverables a reader will audit, and needs no source-count threshold, which the brief forbids as a quota. **Decided by user 2026-11-06:** option (a), substantial means a deliverable report, a five-lens run, or an explicit user request (the recommended default).
2. **File placement** (technical_design_decision). The report suggests "two focused references" (`report:155`). Research keeps its references at the skill root (`research.md`, `url-verify.md`, `investigate.md`), with no `references/` directory. **Recommended default:** two new root-level files, `source-provenance.md` (R1–R5, R11) and `fetch-recovery.md` (R7–R10). `url-verify.md` points to `fetch-recovery.md` only on a failed fetch, and `SKILL.md` points to `source-provenance.md` only for substantial reports. Both are added to the relevant load sets.
3. **Helper script for the register and citation check** (technical_design_decision). The report says to adapt a helper "only if repeated ledger errors justify maintaining it" (`report:155`). **Recommended default:** no helper now. Revisit if focused evals or real use show recurring unknown or mismatched identifiers that the manual check misses.
4. **Typed snapshot and version fields in v5 contracts** (technical_design_decision). **Recommended default:** none. Use `verification_detail` and `gaps`. A typed field needs a versioned change (v5.1) with aligned producers, validators and fixtures, under the contract design guide's compatibility rule. Do it only when a structured consumer actually needs it.
5. **Conditional "adapt" items for research** (product_question; from the index's unassigned list).
   - arxiv: version-preserving IDs and withdrawal checks (`report:290`).
   - youtube-content: timestamped transcript provenance (`report:339`).
   - competitor-news-monitor: event-level deduplication for an explicitly requested watch (`report:291`).
   - llm-wiki: an immutable source layer and drift checks (`report:293`).

   **Recommended default: defer all four.** Revisit an item only when repeated actual use shows a need: arXiv papers, video sources or standing watches recurring in research tasks, or a maintained research corpus. R-S07-3 already preserves versions for any source, including arXiv identifiers, and R-S07-9 covers dated copies. The index's other unassigned adapt items (document-to-action-items, meeting-action-items, hermes-agent-skill-authoring) are not research-owned and are left to the coordinator. **Decided by user 2026-11-06:** defer arxiv, youtube-content, competitor-news-monitor and llm-wiki (the recommended default).

6. **Research fixture that expects tier naming and confidence-scored output** (technical_design_decision; delegated from S01 D2). Options: (a) keep `technology-comparison-uses-standard-tier` passing unchanged; S07 neither requires nor removes tier naming or confidence scoring, and provenance details sit alongside claim-specific confidence; (b) rewrite the fixture to expect claim-specific confidence and provenance instead of "confidence-scored findings", as a separate fixture change with its own review; (c) retire the fixture. **Recommended default: (a).** The fixture models a structured v5 consumer whose compatibility tier and confidence rules the root keeps (`SKILL.md:71-73`), and S07 changes no v5 field. Revisit (b) only if a later change retires the tier/confidence compatibility rules, under the contract guide's compatibility rule.
7. **README Research wording** (technical default; coordinated with S02). Recommended default: S02 owns the README text (R-S02-6/R-S02-7) and lands it after S07's Research presentation is fixed, or in the same coordinated change. README should then describe Research as source-backed research with verified links, claim-specific confidence, conflicts and gaps (as `README.md:245` already does), and may mention bounded fetch recovery and dated-snapshot labelling only if S07 lands; it must not describe tiers as the method or confidence scoring as universal.

## Acceptance examples

- **R1–R2, positive:** a written comparison report registers "Postgres 17 release notes, postgresql.org, retrieved 2026-11-06, live" when it fetches the page, and cites it as `[pg17-notes]`. **Negative (must fail):** the Sources list is typed from memory after drafting, or the agent writes to a shared ledger file that persists across tasks.
- **R3, positive:** "`--foo` was removed in v3.2 (CLI reference, v3.2, updated 2026-09-01)". **Negative:** a version claim citing a docs page with no version, or a date the page never states.
- **R4, positive:** "Retries default to 3 ([sdk-docs] §Configuration › Retries)", and the section really says so. **Negative:** a quote is attached, but the quoted sentence concerns timeouts, not retries, and the claim is still presented as supported.
- **R5, positive:** the draft cites `[4]`, the register has no entry 4, and the check fixes or removes the claim before delivery. **Negative:** the report ships with `[4]` pointing to a URL that differs from the registered one.
- **R6, positive:** "What's the default port for Redis?" is answered with one verified official link and no register or identifiers. **Negative:** a short answer gets a numbered Sources block and citation-check narrative.
- **R7, positive:** a vendor docs page returns 403. Research finds the same content in the vendor's public docs repository and cites that, or, failing that, a dated archive copy. **Negative:** the same URL is refetched repeatedly, or the source is dropped silently without trying an official alternative or reporting a gap.
- **R8, positive:** a 200 response titled "Just a moment..." is rejected as a bot interstitial. **Negative:** that body is treated as the page because the status was 200 and the body was large.
- **R9, positive:** "Pricing as archived 2026-08-06 (archive snapshot); current pricing could not be retrieved." **Negative:** the snapshot price is presented as today's price, or the snapshot is listed under `verified_urls` as the original vendor URL.
- **R10, positive:** a paywalled article with no public alternative is reported as an inaccessible source gap. **Negative:** a proxy relay is used, a CAPTCHA is solved, or a user's private intranet URL is submitted to an archive service.
- **Fixture compatibility (decision 6), positive:** after S07 lands, `technology-comparison-uses-standard-tier` still passes `--validate-fixture` and its tier and confidence expectations are unchanged. **Negative:** an S07 instruction makes provenance labels replace confidence in structured output, so the fixture fails, or the fixture is edited in the S07 change without decision 6 choosing (b).
- **R11, positive:** a five-lens `verified_source_evidence` row uses the snapshot URL as the `public_url` reference, with `verification_detail` "archive snapshot captured 2026-08-06; live page returned 403". **Negative:** a new `snapshot_date` field is added to `handoffs.yaml` without a version change and consumer alignment.

## Verification

Focused checks only (no matched evaluation for S07, per the 2026-11-06 decision):
- `tools/skills/validate-skills.sh`;
- `./tests/test-p0-p4-contracts.sh`, in particular `tests/p0-p4/assistant-research-contracts.sh`, `tests/p0-p4/progressive-specialist-contracts.sh` and `tests/p0-p4/skill-eval-contracts.sh`;
- `tools/evals/run-skill-evals.sh --validate-fixture --skill assistant-research`;
- link checks.

New eval cases in `skills/assistant-research/evals/cases.json`, each with `fail_signals` that a plausible wrong response triggers:
1. blocked page recovered via a dated snapshot, with a current-data caveat (R7, R9);
2. HTTP 200 interstitial rejected (R8);
3. substantial report with an unknown or mismatched citation identifier caught before delivery (R5);
4. short factual question answered without register overhead (R6);
5. recovery refusing to send a private URL to an archive service (R10).

The existing `url-output-verifies-links` and `technology-comparison-uses-standard-tier` cases must still pass. Optionally, run each new case once against the current and changed instructions as a focused before/after spot check. This is not a matched evaluation.

## Dependencies and overlap

- **S01:** request alignment changes Research's output presentation. S07 must not add mandatory sections. Provenance details sit with claims or in a sources list, and S01's "lead with the requested answer" ordering governs layout.
- **S02:** conditional loading. The new references are loaded only under their stated conditions, consistent with S02's loading rules. README Research wording (S02 R-S02-6) must match S07's final Research presentation (decision 7), and S02's D5 change to the Research root's legacy prose (`SKILL.md:62-83`) touches the same file, so the plan sequences the two edits.
- **S01 D2:** the Research fixture tension (tier naming, confidence-scored output) is owned here as decision 6.
- **S05 and S06:** none directly. S06's advisory triage may cite Research's provenance rules and must use its own copy, since skills declare no `requires` for Research.
- No dependency on S10 or S11. S07 can be implemented independently once S01's Research presentation wording is fixed, or in parallel if the plan assigns disjoint edits to `SKILL.md`.
