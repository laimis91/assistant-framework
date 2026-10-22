# Sealed case 03 oracle — never copy into a subject workspace

The completed lookup and write are individually locked, but the absent-key
check, external charge and completion publication are not one idempotent
operation. Parallel retries sharing one key can both observe absence and charge.
The deterministic barrier exposes a legal interleaving without introducing a
business-state mutation. Gateway operations are themselves synchronized and both
return accepted; no gateway failure/retry is necessary. Exact receipt assignment
between worker replies is nondeterministic and irrelevant.

Default parallel/same => two receipts/payments for one key, both uncached; final
cache retains only one. serial/same => one payment and one cached response.
parallel/distinct => two payments for distinct keys is correct, an adverse
control against treating every pair of payments as duplicate. serial/distinct
also two. A diagnosis of an unprotected Python dictionary, gateway timeout or a
missing retry limit alone fails to identify the check/act lifecycle. Equivalent
explanations of concurrent missing-key handling pass. No repair is authorized.
