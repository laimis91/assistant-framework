# Gateway notes (architecture guild, background)

The architecture guild has discussed replacing our in-house API gateway with a
managed gateway product. The managed products offer built-in rate limiting,
request transformation, developer portals and analytics. A migration would
touch every public endpoint, the authentication flow and the deployment
pipeline. Licence costs vary by vendor and traffic tier. No decision or
timeline exists; the guild meets again in January.

Our in-house gateway already supports a token-bucket limiter plug-in keyed by
any request attribute, returning a configurable status code and headers.
