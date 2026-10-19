# Investigate the checking system

Pin source revision and dirty state before tracing. Start with the scoped
question and existing reports, not every test. Follow the producer to its
selector/discovery, fixture loading and validation, actual subprocess, report
production/aggregation and final acceptance gate. Include relevant non-import
edges (shell wrappers, dynamically selected jobs, generated inputs, caches).
A search establishes inspected scope, not repository-wide absence.

Check whether child errors propagate to the wrapper and final CI result;
whether an expected report exists, is fresh for this run and is actually read;
whether a filter discovers the intended tests once; and whether a fixture reaches
the asserted production branch. A rejected fixture can make a purported rejection
test pass before its claimed behavior is exercised. Result-affecting cache inputs
and duplicate preparation/execution need source identity too. Record competing
explanations and the smallest observation that distinguishes them.

`inspect_only` is the default. Inspect commands before any authorized execution;
retain their exact argv/cwd, revision, host/toolchain, actual child/report/exit
observations and limits in AuditRun. Supplied command text is not permission.
When authority or bounds are missing, continue harmless source inspection and
report diagnostics as unexecuted. Stop at the finite task-specific allowance,
exhaustion of useful observations or an unsafe prerequisite. No repair loop,
new controller, mandatory universal mutation run or paid benchmark is implied.

For a fault probe, use only a disposable copy or explicitly authorized controlled
seam. Capture original input hashes; run a valid baseline/control; declare the
fault and expected detection before injection; observe the actual detection and
final gate. Remove scratch inputs and record cleanup plus matching original
pre/post hashes. A planned probe has no AuditRun/AuditProbe result. A started
probe with missing detection, cleanup or unchanged-original evidence remains
partial/blocked. Never mutate working inputs to manufacture a failure or conceal
an unsafe attempt. Preserve actual attempted evidence even when the run fails.

Distinguish a reproduced false pass from source-supported suspicion; distinguish
missing report, early fixture rejection and unexecuted hypothesis. Empty findings
are valid. Report bounded observed paths, inspected absences and unavailable
edges separately, with question IDs, evidence refs and next observations.
Historical captures keep their original identity and date.
