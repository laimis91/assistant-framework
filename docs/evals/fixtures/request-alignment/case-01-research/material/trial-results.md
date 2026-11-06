# Shadow trial results — billing service

Trial window: four weeks (2026-09-07 to 2026-10-04). All three add-ons ran in
shadow mode on every CI run of the `billing` service only; no other service was
included. Findings were triaged by one reviewer (R. Okafor); no second reviewer
confirmed the classifications.

## TypeGuard (strict type checks)

- Flagged 14 issues. 6 were confirmed real defects (wrong currency type passed to
  `round_minor_units`, two `None` returns used as amounts, three mismatched
  `Decimal`/`float` comparisons).
- 2 of the 6 confirmed defects match the root-cause class recorded in last
  quarter's billing incident reviews (float/Decimal comparison). The trial did
  not test whether TypeGuard would have caught those specific incidents.
- 8 of the 14 flags were false positives. All 8 were in `billing/legacy/`, which
  has no type annotations.
- Added a median of 3.5 minutes to each CI run.
- Enabling it on `billing/legacy/` needs an estimated 5 engineer-days of
  annotation work. The alternative is to exclude `billing/legacy/` from checking.

## DocLint (docstring checks)

- Raised 210 warnings, all about missing or malformed docstrings. No warning
  pointed to a functional defect.
- The API documentation owner says complete docstrings would let the public API
  reference be generated instead of hand-maintained.
- Added a median of 20 seconds to each CI run.
- Fixing the existing 210 warnings is estimated at 1 engineer-day.

## ImportOrder (import sorting)

- Auto-fixes import order; found no functional defects.
- Last quarter, 9 of the service's 41 merge conflicts were import-order-only
  conflicts, which ImportOrder's canonical ordering would remove.
- Added a median of 10 seconds to each CI run.
- Adoption needs a one-time auto-fix commit touching 180 files. That commit will
  conflict with most open branches (23 open branches at the time of writing).
