# CI overhead analysis (platform team, background)

This note was written for the platform team's runner review and is included for
context.

Every CI job in the organization, for every service, starts on a cold runner.
Cold start (image pull, dependency cache restore, virtual environment creation)
takes a median of 90 seconds per job. The billing pipeline has 4 jobs, so about
6 minutes of each billing pipeline run is cold-start overhead.

The platform team plans to move to warm runner pools in Q1 2027, which is
expected to cut cold start to about 15 seconds per job. The plan is not yet
funded.

Breakdown of cold start by phase (median seconds): image pull 41, cache restore
27, virtual environment 14, other 8. Image pull time varies with registry load;
the 95th percentile is 140 seconds.

The cold-start overhead is the same whether or not any static-analysis add-on is
enabled: the add-ons run inside the existing lint job and do not add jobs.

Options the platform team is weighing: larger shared caches, pre-baked images
per language, and warm pools. A comparison of those options is outside this
note.
