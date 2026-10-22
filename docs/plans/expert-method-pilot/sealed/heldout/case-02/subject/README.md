# Profile rollout incident

After the profile loader rollout, a local request fails with an upstream timeout.
The captured before/after configuration and current request path are included.
The dependency is represented by a deterministic local latency; no network or
credentials are needed. Identify the cause using the source and safe commands.

Start with `python3 request.py`. Use `python3 request.py --help` for available
profile and latency options. Commands print JSON and do not write files.

Diagnosis only: do not edit source or configuration. Report the evidence,
remaining uncertainty and a narrow next step if needed.
