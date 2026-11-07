# Request

Draft a short specification for adding rate limiting to our public
`POST /v1/quotes` endpoint, using the material in `material/`. Two questions are
still open and the spec must settle them or record them as unresolved decisions
with a recommendation:

1. Should the limit be applied per API key, per client IP address, or both?
2. When a client is over the limit, should we reject the request immediately or
   queue it?

One constraint is fixed: existing integrations that use our Python SDK v2 must
keep working without a code change on their side.

Write the spec in your answer; do not change any files.
