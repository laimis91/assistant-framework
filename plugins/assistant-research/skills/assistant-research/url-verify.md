# URL Verification Protocol

AI agents routinely hallucinate plausible-looking URLs. Every URL must be verified before presenting to the user.

## Rule
**Never present a URL to the user without first verifying it resolves to relevant content.**

## Process

1. For each URL in research results, use WebFetch to check it
2. If the URL returns an error (404, 403, timeout): drop it
3. If the URL resolves but content doesn't match the claimed topic: drop it
4. If the URL resolves and content is relevant: keep it

## When to verify
- Every URL from research agents
- URLs from WebSearch results (these are usually valid but still check)
- URLs you construct from memory (e.g., "I think the docs are at...")
- URLs from cached/learned knowledge (they may have moved)

## When verification is optional
- URLs the user provided (they know it works)
- URLs from `git remote -v` or similar local sources
- localhost URLs during development

## Output
Mark verified URLs in research output:
```
Sources:
- https://example.com/docs (verified)
- https://example.com/old-page (404 - dropped)
```
