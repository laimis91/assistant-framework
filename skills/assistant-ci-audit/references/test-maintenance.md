# Assess protection and maintenance

Establish expected accepted behavior from the task and authoritative contracts
before judging an assertion. Classify a failing expectation as product regression,
outdated after accepted change, implementation-coupled/duplicate, baseline or
environment failure, or unresolved cause; preserve interacting causes and doubts.
Unknown failures belong to debugging. Audit findings grant no repair authority.
Do not bend production behavior to incidental internal calls, shapes or ordering.
Exact text/schema checks are appropriate when those bytes/shapes are contractual.

For a new or changed test, ask four authoring questions: (1) which observable
contract does it protect; (2) which credible regression makes it fail; (3) why
existing proof misses that regression; (4) does it need a production seam (export,
flag, wrapper or hook) with no real caller? A yes to (4) points the proof back to
the real boundary: a proposed test that adds `export function _resetCacheForTest()`
should exercise cache expiry through the public API instead.

For an applicable finding, use its maintenance record rather than a per-test
ledger: identify test/family, important claim, plausible detected defect,
remaining unique protection, evidence_state, and `keep`, `consolidate`, `rewrite`
or `remove`. Use `source_confirmed` only when finding.evidence_refs establish the
inspected assertion, accepted behavior and retained protection or obsolete rationale.
Use `unresolved` with an explicit gap for unknown protection. The four finding kinds
remain unchanged: `hypothesis` can describe an unexecuted effect/disposition without
downgrading established source facts; source inspection alone establishes neither
`reproduced_defect` nor `supported_cost`.
Assess duplicate behavior, mutable inventories, internal call coupling, obsolete
expectations, speculative cases and expensive fixtures in the relevant flow.
Similar code or many tests proves no waste. Two similar authorization tests may
protect owner allowance and cross-owner denial independently: retain both claims.

Audit-time examples of proof that proves nothing, each beside a retained contrast:

- A fixture that fabricates the receipt, ordering or persistence the owner should
  produce: a fixture writes the shipment receipt the fulfilment service should
  emit, and the test asserts the receipt exists. It passes when the service writes
  nothing; `rewrite` it to assert the owner's own output. Contrast: a test of the
  exact bytes of an installed prompt block is `keep`; those bytes are the contract.
- A negative test that passes on the wrong guard or an unreachable rejection: an
  "unauthorised user is rejected" test whose request already fails input validation
  before the permission check passes with the permission check deleted. `rewrite`
  it so only the intended guard can reject. Contrast: a test that a malformed
  message is rejected as a platform or protocol contract defines is `keep`.
- Authoring-time classes, named only: self-comparison or subject-generated expected
  value, internal call-shape assertion, and a mock that supplies the asserted
  behaviour. Each is `rewrite`, unless the call or exchange is itself the external
  contract, which is `keep`.

Consolidation/removal maps duplicate assertions to retained adequate protection
at the relevant boundary. An obsolete/invalid expectation needs accepted-behavior
source evidence rather than an invented replacement to preserve test count.
Uncertain protection stays a gap; removing a genuine accepted requirement needs
separate authorization. Recommend a bounded correction, never automatically edit,
delete, quarantine, suppress errors, raise timeouts or add retries for green.
Owner-level cleanup names the remaining proof for each removed claim: "remove
`test_invoice_total_internal`; remaining proof: `test_invoice_pdf_total` at
`invoice_test.py:88` detects rounding regressions at the public boundary." "Remove
14 duplicate tests" names no remaining proof and is not a recommendation. When the
remaining proof cannot be named, record the protection as an unresolved gap and
the test is not removed.

Failed discovery is not a valid empty result. Worked case, audit F3 as at d11756d:
`tools/cognitive-complexity/run-complexity.sh --changed --base nonexistent`
suppresses the failed `git diff` (`2>/dev/null || true`, `:101-103`), finds no
uncommitted `.cs` files and exits 0 with "No .cs files to analyze." (`:108-111`);
without `--base` and with neither `main` nor `master`, it silently falls back to
`HEAD~1` (`:89-90`). An invalid requested comparison, such as a nonexistent base or
a run outside a repository, must surface as a failure. A valid base with no `.cs`
changes is a valid empty result and may report nothing to analyze. Report the
defect as a finding; its repair belongs to the separate audit session.
Workflow retains one shared semantic progress guard across tests/checks/workers/
sessions: an audit recommendation does not reset its history, frontier or consecutive
no-progress count. Productive corrections have no cumulative allowance.

Separate source-supported coupling from measured cost. A `supported_cost` finding
needs actual measurements; a claim of savings also needs equivalent completed
accepted obligations/protection and comparable conditions. Identical test counts
are unnecessary; disclose changed/redundant checks and why retained checks protect
the same important faults. Fewer completed obligations or failed work cannot win.

Record actual baseline/candidate run refs and conditions: host/toolchain, revision,
preparation, fixture/instrumentation work, cache/warmup, failures/repairs/review,
elapsed time or available cost units, sample count/variability and unmeasured work.
Do not invent unavailable telemetry or extrapolate one local measurement to general
savings. Mark missing, failed or incomparable evidence explicitly; an inspect-only
report may have no executions, no findings, and useful unresolved questions.
Schema validation, canned responses and packaging do not establish model adherence,
native selection, company-PC diagnosis or comparative benefit.
