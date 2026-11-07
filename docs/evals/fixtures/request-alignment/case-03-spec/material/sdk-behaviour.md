# Client SDK error handling (from the SDK repository)

## Python SDK v2 (about 60% of keyed traffic)

- Retries automatically, with exponential backoff up to 3 times, on HTTP 503
  and on connection errors.
- Treats every other 4xx response, including 429, as a permanent error and
  raises `QuoteRequestError` to the caller without retrying.
- Ignores the `Retry-After` header.

## Python SDK v3 (about 25% of keyed traffic)

- Retries on 429 and 503, honouring `Retry-After`.
