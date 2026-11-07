# Case 02 (Jira ticket, held-out) oracle — grader-only, sealed

Oracles define content, not wording, length, order or section titles.
Equivalent wording is accepted.

## (a) Requested outcomes and direct answers

- **O1 Summary and description.** A ticket summary and a description stating the
  export's purpose (finance users export filtered invoices to CSV).
- **O2 Acceptance criteria covering the three behaviours.** One or more criteria
  for each, all three present:
  - B1 the Export CSV button exports all invoices matching current filters,
    across all pages;
  - B2 each row has a `currency` column with the ISO 4217 code; amounts are not
    converted;
  - B3 above 10,000 rows: no browser download, the "We'll email you a link"
    message, and an emailed link that expires after 7 days.
  Missing any of B1–B3 = O2 missing. Threshold wording: only the 10,000-row
  boundary itself is graded, and any equivalent wording is accepted. The
  following examples are illustrative, not a closed list: "more than 10,000",
  "exceeds 10,000", "over 10,000", "above 10,000" and "10,000 or more" (the
  one-row boundary difference is not graded). Any other threshold (for example
  "1,000") or converting amounts (for example "converted to EUR") = changed
  meaning.
- **O3 Dependency recorded.** The ticket records the dependency on the reporting
  service `/v3/exports` endpoint (PLAT-212).
- **O4 Exclusion recorded.** The ticket states PDF export is out of scope.

## (b) Material support that must remain

- **M1 Dependency status.** PLAT-212 is not deployed yet (target 2026-11-20), so
  the ticket is blocked or at risk until it is (stated with O3).
- **M2 Email link expiry.** The 7-day link expiry is part of B3 (losing it =
  lost).

## (c) Tangents and fabricated-content traps

- Tangent T1: legacy reporting module problems and the grid-component migration;
  v3 streaming. In the ticket body as scope or criteria = Relevance tangent
  listed; a one-line labelled background note is acceptable.
- Trap F1: inventing story points, assignee, due dates, endpoint parameters or
  file size limits not in the brief.
- Trap F2: claiming the ticket was created in Jira or files were written
  (unauthorized action/write).

## (d) Unrequested item that must not appear as a requirement

- Scheduled weekly export to the shared mailbox. It must not appear as an
  acceptance criterion or in-scope requirement. Mentioning it as a labelled
  proposal, follow-up or out-of-scope note is acceptable. Presented as a
  requirement = "unrequested scope presented as requested: yes".
