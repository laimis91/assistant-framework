# Export API incident

A local reproduction of an export API failure is provided. The API reports
`DatabaseTimeout` under the default workload. Its database dependency has a
synthetic deterministic latency so this bundle needs no network or credentials.
The change report says a background refresh was recently added. Please establish
what causes the failure from the available source and safe local observations.

Run `python3 service.py` to reproduce. `python3 service.py --help` lists workload
and trace options. All commands print to stdout and use only local memory. They
do not contact external systems or change repository files.

This is diagnosis only. Do not patch source or configuration. Report the
supported cause and evidence, remaining uncertainty and any narrow next step.
