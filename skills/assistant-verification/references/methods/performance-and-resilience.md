# Performance and resilience checks

Load when the request states a measurable quality target or a credible load, resource, dependency-failure, cancellation, retry, or recovery concern exists.

## Claim and setup

Name the workload, representative data, environment, concurrency, resource or latency budget, and failure condition. If a target, baseline, or metric is unknown, state that gap instead of inventing a threshold. Use a stable comparable baseline and control competing load where practical.

## Procedure and oracle

Measure relevant latency, throughput, memory, CPU, or cost with units and collection conditions. Inject only bounded, reversible faults that correspond to a material risk. Observe recovery, cancellation, idempotency, retry limits, and cleanup as applicable. Keep functional correctness criteria separate from quality budgets.

## Traps and evidence

Synthetic workloads, warm-cache-only samples, uncontrolled shared hosts, unbounded fault loops, and unsupported telemetry can create false precision. Record workload, environment, raw observations, variability, baseline identity, and exclusions. Repeat enough to interpret variability and stakes, not to reach a fixed count.

Do not claim memory, performance, or resilience improvement without comparable observations and a stated failure condition. If no material quality target or failure concern exists, use ordinary functional evidence and stop.
