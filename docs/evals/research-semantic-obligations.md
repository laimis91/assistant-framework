# Research semantic validator obligation inventory

Frozen against `a1eff5b29f8fe32d35a35e3108227f41194fdf20` before source edits.

## Slice disposition

| Existing assertion family | Invariant and independent expected outcome | Production owner | Layer after slice | Disposition |
| --- | --- | --- | --- | --- |
| `research_optional_verified_urls_controls`, exactly five modes (`delegated`, `sequential_fallback`, `delegated_peer_fallback`, `quick_normalized`, `retained_follow_ups`) × `omitted` / `empty` / `bound-public-url` | A finding may omit `verified_urls`, use `[]`, or name the bound `https://www.iana.org/optional-verified-url`; all 15 combinations accept with no production errors. | `finalArtifactsValid` (resolved evidence relation); helpers `publicUrlValid` and `publicUrlIdentity`. | New direct Node control imports `validateResearchResponse`; representative shell test invokes it. | Replace official source-text VM execution. Private oracle comparison is retained in this slice. |
| Same five modes × `unbound-public-url` | A syntactically valid public URL which is not accepted or typed verified evidence rejects with exactly `final artifacts: finding shape` from the import API and `five-lens semantic validation: final artifacts: finding shape` from the CLI. | `finalArtifactsValid` | New direct Node control. | Replace official source-text VM execution; retain private comparison. |
| Same five modes × `null` / `string` / `object` / `non-string-entry` / `mixed-non-string-entry` | A supplied `verified_urls` field must be an array of resolving public URL strings. All 25 combinations reject with exactly `final artifacts: finding shape` from the import API and its one-line CLI rendering. | `finalArtifactsValid` | New direct Node control. | Replace official source-text VM execution; retain private comparison. |
| `research_completion_validator_controls peer`, same five modes × valid `accepted`, `accepted_with_concerns`, `revise` | Accepted states carry no closure metadata; revise supplies matching closure identifiers and a final synthesis different from the initial one. All 15 valid combinations accept. | `peerReviewValid` | New direct Node control imports production validator; shell entry remains a representative invocation. | Replace official source-text VM execution; retain private oracle extraction and comparison. |
| Same peer modes × six injected non-revise closure fields for each accepted verdict | `peer_review.revision_disposition_id`, `peer_review.revision_disposition`, and process closure id must not occur in accepted states (including supplied `null`). Private diagnostics remain `peer:status-and-revision-truth-table`; production errors are exactly `peer review: accepted revision closure; peer review: non-revise revision closure leakage` for peer fields and `peer review: non-revise revision closure leakage` for process-only leakage. | `peerReviewValid` | New direct Node control. | Replace official source-text VM execution only. |
| `research_completion_validator_controls capacity` plus `research_fixture_capacity_controls` | Adapter capacity accepts exactly 1, 2, and 9007199254740991; rejects 1.5, 0.5, string `"2"`, 0, and 9007199254740992. Every rejection returns `semantic context: required shape` from the import API and its one-line CLI rendering. | `semanticContextValid` | Direct Node compatibility control remains called from the existing shell wrapper; fixture CLI control stays. | Replace official source-text VM execution only. |
| `research_completion_validator_controls findings` plus `research_empty_findings_producer_controls` | The existing exact matrix remains: evidence-empty-with-gaps; sourced none-needed with/without optional finding; source-empty none-needed/material follow-ups for inference-only and unresolved; failures for missing top-level gaps, sourced main result without finding, mixed/duplicate none-needed, malformed own gap, each decision with empty evidence or source-backed empty evidence; material follow-up with/without finding. The direct expected errors remain `final artifacts: findings required unless evidence-empty completion has gaps`, `accepted result practitioner: follow-up none_needed exclusivity`, `accepted result practitioner follow-up: nonblank gaps array required`, `accepted result practitioner follow-up: empty non-source evidence requires a gap`, and `accepted result practitioner follow-up: source-backed result requires a source`. | `finalArtifactsValid` owns findings completion; `acceptedResultValid` owns per-result/follow-up validity. | New direct Node compatibility control; existing Ruby documentation/contract alignment check stays. | Replace official source-text VM execution only. |

Additional independently authored controls in the direct module: a clean response with missing `candidate_mechanisms` is accepted, while a refreshed response with a non-array `candidate_mechanisms` is rejected as `candidate mechanisms: array required`; repeated valid-invalid-valid calls; calls against distinct fixture cases; no mutation of the response, fixture, or earlier result array; importing the core does not read files, log, or change `process.exitCode`.

Measurement boundary: `assistant-research-semantic-controls.cjs --optional-urls` runs only the existing 45 optional-URL case/mode combinations and retains their private-oracle comparison. The existing shell function delegates to that exact mode. Import/isolation/held-out controls use a separate mode so focused before/after timing does not compare 45 cases with expanded coverage.

## Retained families and one production owner each

| Family (baseline locations at `a1eff5b`) | Covered invariant classes | Production owner(s) | Disposition in this slice |
| --- | --- | --- | --- |
| Private whole-response oracle (`tests/p0-p4/lib/assistant-research-fixtures.sh:160-584`; callers throughout contracts) | Independent constructed response/oracle, canonical JSON/digest, alternate valid schedules, public-source acceptance/rejection parity. | Independent test oracle `validate` (not a production owner); production rules are owned by `validateResearchResponse` and its named helper functions. | Retain. Private helper extraction is explicitly deferred; no source-text policy copy is removed. |
| Ruby verified-source predicate (`assistant-research-contracts.sh:216-307`, callers 2456 and typed URL matrix) | Method-specific public URL/local repository/authenticated/offline reference shapes; encoded source safety and IP/reference policy. | `publicUrlValid`, `sourceReferenceValid`, `unsafeOpaqueReference`, `verifiedSourceEvidenceRowValid`. | Retain pending a unique-case/replacement map. |
| Delegated structured mutations (`61-174`, invoked 2048-2130) | Lens identity, packet/digest binding, projections, resource ceilings, delegated lifecycle, peer lifecycle, source safety, final artifacts, topic relevance. | This helper currently invokes the independent private `research_response_oracle_is_valid`, not the CLI. The eventual production owner map is `validateResearchResponse` with `usageValid`, `overallUsageValid`, `retainedPacketsValid`, `peerInputBindingValid`, `semanticContextValid`, `peerReviewValid`, `sourceReferenceValid`, and `finalArtifactsValid`. | Retain private mutation chain unchanged. |
| Sequential fallback mutations (`175-215`, invoked 2137-2160) | Fallback-only lifecycle, no native dispatch leakage, root-pass uniqueness, resource/wave truth tables. | This helper currently invokes the independent private `research_response_oracle_is_valid`, not the CLI. The eventual production owner map is `validateResearchResponse`, `overallUsageValid`, `peerReviewValid`, and `semanticContextValid`. | Retain private mutation chain unchanged. |
| Official targeted CLI mutations (`424-662`, invoked 2167-2287) | Case-targeted `run-skill-evals` baseline/mutation rejection, case failure accounting, selected semantic-validation accounting, and no `TypeError` on malformed mutations. | The CommonJS CLI adapter owns file reads, fixture/case selection, and diagnostic/exit rendering; the shell adapter owns allowlisted dispatch; `validateResearchResponse` owns semantic errors. | Retain; this slice only swaps its implementation from heredoc to module. |
| Fixture validation and representative CLI witnesses (1706-2298, 3162-3217) | Five case modes, `source_research` compatibility, allowlisted dispatch, fixture schema/context and source coverage. Empty and missing response-file witnesses are separately owned by `tests/p0-p4/skill-eval-contracts.sh:1448`. | Fixture validator/runner are outside this production core; selected semantic dispatch uses shell adapter and core. | Retain. |
| URL and evidence direct parity controls (771-953; 2456-3075) | Typed labels versus verified-URL authority, canonical aliases, once-decoded lexical URLs, reserved delimiters, nested encoded scheme rejection, static opaque references, candidate confidence. | `publicUrlValid`, `sourceReferenceValid`, `publicUrlIdentity`, `verifiedSourceEvidenceRowValid`, `verifiedEvidenceAliases`, `candidateMechanismsValid`, `finalArtifactsValid`. | Retain all private/Ruby/CLI checks. |
| Lifecycle and close-out controls (3078-3159) | Unbound evidence, revision closure, response-authored capacity rejection, derived peer synthesis preservation. | `semanticContextValid`, `peerReviewValid`, `finalArtifactsValid`, `highStakesRecommendationValid`. | Retain. |
| Documentation producer alignment (`1227-1244`) | Output guidance, phase gate, and contract describe source-empty and material follow-up rules consistently. | Documentation contracts; semantic consumer owner remains `acceptedResultValid`/`finalArtifactsValid`. | Retain Ruby prose check. |

## Extraction contract

`research-semantic-validator.cjs` exports `validateResearchResponse(response, fixtureCase) -> errors`.

* Import is side-effect-free: no filesystem reads, output, process-exit changes, or global validation state.
* Errors are newly allocated per call. Callers receive no shared state.
* Caller response and fixture values are never changed. The historical missing-`candidate_mechanisms` normalization is made on an internal shallow response copy only.
* The CLI adapter owns reading JSON, resolving the selected fixture case, reproducing current diagnostics (`five-lens semantic validation: ...` with stable de-duplication/limit), and exit status.
* Compatibility is intentional for current false/zero/empty-string/null/scalar inputs: preserve existing shell-visible outcome. Do not reinterpret that behavior as a stronger object-validation policy.

## Maintenance and measurement ledger

* Production implementation count remains one: the shell heredoc moved into one CommonJS module. No duplicate policy implementation was removed; the private Node and Ruby copies remain.
* Source-text extraction sites removed from official production consumption: two (`research_optional_verified_urls_controls`, `research_completion_validator_controls`). Private fixture extraction remains.
* Retained targeted mutation families are not counted as deleted or accelerated. Root records before/after runner invocation count, wall time, decision outcomes, false accepts, and false rejects using identical instrumentation.
* No native five-subagent execution claim follows from these offline controls.

### Recorded first-slice measurements (2026-09-07)

| Measure | Before | After |
| --- | ---: | ---: |
| Existing optional-URL workload | 45 cases / 90 decisions; pass | 45 cases / 90 decisions; pass |
| Optional-URL wall time, one run | 0.306 s | 0.180 s (extraction checkpoint) |
| Existing research-suite workload | 49 assertions; pass | 49 assertions; pass |
| Research-suite wall time, one instrumented run | 435.087 s | 384.204 s |
| Actual runner entries | 385 | 385 |
| Case-targeted / response-corpus / fixture-validation entries | 377 / 6 / 2 | 377 / 6 / 2 |
| Optional-URL false accepts / false rejects | 0 / 0 | 0 / 0 |

The suite measurements use the same pristine-snapshot directory and a temporary
`bash` PATH wrapper that records script entry and then executes `/bin/bash` with
unchanged arguments. Source hashes were unchanged during each run. The after
measurement covers the original 49-assertion workload; final CI additionally
runs isolation, CLI-diagnostic, and counter-accounting witnesses. Those added witnesses
are validated separately and are not counted as part of the like-for-like
49-assertion timing. The 15 recorded shell-CLI input/dispatch probes also retain
exact exit-status, stdout, and stderr parity.

These are single observations with differing background test activity, not a
controlled performance study or an established speedup. A failed `BASH_ENV`
logger control and a `bash -x` run that contaminated stderr assertions are
excluded. No reduction in CLI invocation count or duplicate policy ownership
has been demonstrated by this slice; the measured maintenance improvement is
removal of the two production-source extraction sites.

`falseAccepts` and `falseRejects` count only the imported production validator's
classification against the authored expected result. Private-oracle agreement
and exact diagnostic checks remain separate pass/fail conditions.

After review repairs, the same 45-case workload passed in 0.173 s. The counter controls deliberately substitute accept-all/reject-all classifiers and require 30/15 classification errors for the optional-URL matrix and 5/3 for capacity. The CLI witness uses a configured portable temporary root and verifies cleanup. Full-suite timings above describe the earlier extraction checkpoint, before these test-harness repairs; they are not a final-code performance guarantee.
