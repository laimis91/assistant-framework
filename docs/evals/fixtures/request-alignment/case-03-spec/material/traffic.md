# POST /v1/quotes traffic sample

Sample: one week, 2026-10-19 to 2026-10-25, from the API gateway access log.

- 1.9 million requests in total.
- 82% carried an API key; 18% were anonymous (no key), which the endpoint still
  allows for the public price calculator widget.
- The top 5 API keys sent 41% of all keyed requests. One key peaked at 120
  requests per second for 6 minutes on 2026-10-22, which raised p99 latency for
  every client from 180 ms to 2.4 s.
- Anonymous traffic comes from about 37,000 distinct IP addresses. About 9% of
  anonymous requests come from 3 IP ranges that belong to large corporate
  proxies (many real users behind one address).
- Queueing capacity: each API node can hold at most 200 in-flight requests
  before it stops accepting connections.

Only this one week was sampled; seasonal peaks (month end) are not represented.
