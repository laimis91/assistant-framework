# Fetch recovery

Use this when a source needed for a material claim cannot be retrieved: an error
status, timeout, block, paywall, login wall or interstitial.

## Bounded recovery

Never refetch the failing URL. Try each route at most once per source, in order,
and stop at the first body that passes validation:

1. **Official alternative.** The same content from the same publisher: a
   canonical or alternate URL, the documentation source repository, release
   notes, a PDF, a feed, or a data or API endpoint serving the same content.
2. **Existing dated snapshot.** A capture that a public archive service already
   holds.

When both routes fail, report the source as an inaccessible-source gap and
qualify or drop the claims it would have supported. Repeated unproductive
attempts fall under the shared task guard.

## Validate the body

A retrieved body, live or recovered, counts only when its content matches the
expected page: the expected title or claim-bearing text is present. Reject an
error page, rate-limit body, bot-check or CAPTCHA interstitial (for example a
page titled "Just a moment..."), redirect stub or login wall, even with HTTP
200. Status code and body size never count as success.

## Label snapshots

- Name the archive and the capture date, and label the copy as a snapshot.
- Never present a snapshot as the live page, and never list the original URL as
  verified because a snapshot of it was read. In structured output the snapshot
  URL, never the original, is the verified reference (in `verified_urls` or the
  evidence row's reference). Carry the label in `verification_detail` where that
  field exists, otherwise in the finding's `sources` entry, for example "archive
  snapshot captured 2026-08-06; live page returned 403", and put a current-state
  gap in top-level `gaps`.
- A snapshot is context only for current-state claims such as prices, latest
  versions, availability or status: state the claim as of the capture date, or
  report it as a gap.

## Access boundaries

- Never bypass authentication, paywalls, CAPTCHAs or bot detection.
- Use no proxy relay, and add no API-key or paid-service requirement.
- Never send any private, authenticated or other non-public URL or content,
  whoever supplied it, to a third-party archive, cache or render service.
- Requesting a new archive capture is an external write: do it only with the
  user's approval.
