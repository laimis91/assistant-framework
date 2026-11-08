# URL Verification Protocol

AI agents routinely hallucinate plausible-looking URLs. Every URL must be verified before presenting to the user.

## Rule
**Never present a URL to the user without first verifying it resolves to relevant content.**

## Process

1. For each URL in research results, use WebFetch to check it
2. If the URL fails (error status such as 404 or 403, timeout, block, paywall, login wall or interstitial):
   - when it supports a material claim, follow [fetch-recovery.md](fetch-recovery.md) and cite the recovered source, never the original URL, as verified; when recovery fails, drop it and report the gap;
   - otherwise drop it
3. Check the body, not the status: it must contain the expected title or claim-bearing text, and status code or body size alone never counts as success. An error page, rate-limit body, bot-check or CAPTCHA interstitial, redirect stub or login wall is a failed fetch even with HTTP 200: handle it under step 2. A real page on a different topic: drop it
4. If the URL resolves and content is relevant: keep it

## When to verify
- Every URL from research agents
- URLs from WebSearch results (these are usually valid but still check)
- URLs you construct from memory (e.g., "I think the docs are at...")
- URLs from cached/learned knowledge (they may have moved)

## When verification is optional
- URLs the user provided (they know it works); a private, authenticated or other non-public URL, whoever supplied it, is never sent to a third-party archive, cache or render service
- URLs from `git remote -v` or similar local sources
- localhost URLs during development

## Output
Mark verified URLs in research output:
```
Sources:
- https://example.com/docs (verified)
- https://web.archive.org/web/20260806000000/https://example.com/pricing (verified; archive snapshot captured 2026-08-06; live page returned 403)
- https://example.com/old-page (404; no official alternative or snapshot found - dropped, reported as a gap)
```
