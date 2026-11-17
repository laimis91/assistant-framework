# Source provenance

Use this only for a substantial report: a written report or document
deliverable, any five-lens run, or an explicit request for checkable citations
or fact-checking. Ordinary short answers keep near-claim citations and
`url-verify.md` with no register, identifiers, location fields or citation check.

## Register sources at retrieval

Register each source when you retrieve it, before writing claims that rely on
it. Never build or retype the source list from memory after drafting. Each
entry records:

- identity: title and publisher or author;
- a verified locator: a URL checked per `url-verify.md`, or the safe stable
  locator `research.md` allows for repository, authenticated or offline evidence;
- the retrieval date;
- live or snapshot; a snapshot also names its archive and capture date
  (`fetch-recovery.md`).

The register is task-local: keep it in working notes or the draft itself. It is
never a global, shared or persistent ledger, and it needs no file, tool, API key
or numbering scheme. Any citation style works when each identifier maps to
exactly one entry.

## Cite what the source states

- **Version and date.** For a version- or time-sensitive claim, keep the
  version, edition, publication or last-updated date the source states. When it
  states none, call the source undated; never infer or supply a date.
- **Location.** For each material claim, give the supporting section, heading,
  page, line range or anchor where the source has one, for example
  `[sdk-docs] §Configuration › Retries`.
- **Support.** A quote or location shows where to look; its presence does not
  prove support. Read the cited passage: if it does not support the claim,
  downgrade the claim, cite a passage that does, or report a gap.

## Check citations before delivery

Before delivering, check that:

1. every citation identifier in the draft resolves to exactly one register entry;
2. every listed source matches its entry: the same locator, version or date, and
   live or snapshot status.

Correct an unknown identifier or a mismatch, or remove the claim or report it as
a gap, before delivery.

## Layout and structured output

Provenance sits with the claims or in a sources list; it adds no mandatory
section, and the root's request-alignment ordering governs layout. Provenance
labels never replace claim-specific confidence (`research.md`).

In five-lens runs, build the root register from accepted lens results: their
`sources_or_verified_urls` and `evidence` rows. Take retrieval date, version or
date, live or snapshot status and location from an evidence row's `detail` when
the lens recorded them; otherwise record the missing field as a gap, for example
"retrieval date not recorded by lens", and never infer it. Carry them into the
root's `verified_source_evidence` rows as `verification_detail`.

In five-lens and other structured outputs, record snapshot status, archive and
capture date, version or date and supporting location inside the existing v5
fields: `verification_detail`, `sources` and
top-level `gaps`. A typed field would be a separately versioned contract change.
