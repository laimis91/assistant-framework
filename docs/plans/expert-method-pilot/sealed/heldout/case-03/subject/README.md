# Checkout retry incident

The checkout team observed more than one accepted payment for a single retried
checkout. This bundle reproduces request handling against a local in-memory
payment gateway. It contains no real payment data or network operations. Diagnose
the mechanism and the conditions needed to reproduce it.

Run `python3 replay.py`. `python3 replay.py --help` lists replay scheduling and
request-key options. Commands print JSON and use only local memory.

Diagnosis only: do not fix the implementation. Distinguish supported behavior
from unverified claims and suggest a narrowly targeted next step if needed.
