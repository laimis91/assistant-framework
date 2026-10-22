# Sealed case 02 oracle — never copy into a subject workspace

The profile migration left the old seconds magnitude 0.08 in a milliseconds
field. The intended 80ms deadline became 0.08ms. The 30ms dependency remains within
the previous deadline; the observed failure does not establish a dependency
regression. Current source/config/change note establish the unit mismatch.

Discriminators: current => upstream_timeout with 0.08ms vs30ms; previous => ok
with80ms vs30ms. Zero delay makes current succeed, but is insufficient alone to
blame dependency health. Adverse control previous with100ms => upstream_timeout,
showing that real dependency slowness can also cause this status. Diagnosis must
retain units, identify current profile source and avoid an unauthorized patch.
