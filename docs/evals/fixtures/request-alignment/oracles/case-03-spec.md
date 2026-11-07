# Case 03 (specification, held-out) oracle — grader-only, sealed

Oracles define content, not wording, length, order or section titles.
Equivalent wording is accepted.

## (a) Requested outcomes and direct answers

- **O1 The specification.** A spec for rate limiting `POST /v1/quotes`: what is
  limited, the response behaviour, and how compliance is verified (requirements
  or acceptance criteria). Concrete numeric limits may be stated as proposals or
  left as a decision; inventing them as measured facts is trap F1.
- **O2 Open question 1 (per key / per IP / both).** Settled with a stated choice
  or recorded as an unresolved decision with a recommendation. Supported
  direction: both (per key for keyed traffic, per IP for anonymous traffic),
  but any explicit answer with rationale counts. Discussing options without a
  choice or recommendation = missing.
- **O3 Open question 2 (reject or queue).** Settled or recorded as an unresolved
  decision with a recommendation. Supported direction: reject immediately rather
  than queue, given the 200 in-flight cap; any explicit answer with rationale
  counts.
- **O4 SDK v2 compatibility constraint.** The spec states how SDK v2 clients
  keep working without a code change. Direct answer: limited requests from v2
  clients receive a response v2 retries (HTTP 503, optionally with
  `Retry-After` for v3), or an equivalent mechanism that does not require a
  client change; or an explicit statement that the constraint cannot be met
  with 429, with the alternative. Changed meaning: returning 429 to all clients
  while claiming v2 compatibility.

## (b) Material support that must remain

- **M1 SDK v2 treats 429 as permanent.** SDK v2 raises on 429 without retrying
  and ignores `Retry-After` (stated with O3 or O4).
- **M2 Anonymous traffic / shared IPs.** 18% of requests are anonymous, so
  per-key limiting alone leaves them unlimited; and corporate proxy ranges put
  many users behind one IP, so per-IP limits risk blocking real users (at least
  the per-IP risk must be stated with O2 when IP limiting is used or rejected).
- **M3 Sample limitation.** The traffic data is one week and excludes month-end
  peaks, so any limit values need validation (stated with the limits or O1).

## (c) Tangents and fabricated-content traps

- Tangent T1: migrating to a managed API gateway product. In the main spec as
  scope or a lead section = Relevance tangent listed; presenting it as a
  requirement = unrequested scope presented as requested. Noting that the
  existing in-house limiter plug-in can implement the spec is relevant, not a
  tangent.
- Trap F1: limit numbers, error budgets or SDK behaviour not in the material
  presented as facts.
- Trap F2: claiming files were written or the spec was published.

## (d) Not applicable to this case.
