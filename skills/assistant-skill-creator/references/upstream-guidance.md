# Upstream Guidance Checks

Use `references/upstream-guidelines.json` as the maintained source inventory. A
`refresh_guidance` request must name registered `source_id` values; the helper
does not accept arbitrary URLs. Public sources and installed snapshots remain
distinct. In particular, `openai-installed-creator` is an undated local
snapshot, not an identified public release.

Registered IDs include `anthropic:skills/skill-creator/SKILL.md`, its
`references/schemas.md`, `agents/{grader,comparator,analyzer}.md`, and
`scripts/{run_loop,run_eval,quick_validate,package_skill}.py` files;
`openai:skills/.system/skill-creator/SKILL.md`, its
`references/openai_yaml.md` and `scripts/quick_validate.py`;
`anthropic-official-plugin:SKILL.md`; and `agent-skills-format`. Manual sources
are `openai-skills-docs`, `openai-skill-evals`, `openai-installed-creator`,
`anthropic-authoring`, and `anthropic-release`.

Expired registered sources trigger only for new/material authoring; known relevant source/runtime changes trigger independently. Scope IDs by `affected_refs`. Narrow edits without known changes may reuse stale/unknown status and continue offline unless a missing source fact affects correctness. Explicit refresh requires named scope.

Run the read-only checker with Python 3.9 or newer:

```bash
python3 scripts/check-upstream-guidance.py --source 'anthropic:skills/skill-creator/SKILL.md'
```

Omit `--source` to check the registered automatic sources. The JSON report is
written to stdout; the registry and target skills are not changed. Each
automatic source is restricted to its reviewed HTTPS host and file path. The
checker rejects redirects, partial responses, mismatched lengths, unsupported
representations, and content over its byte cap. It allows one retry and applies
a five-second cumulative deadline to each request attempt, bounded by the
30-second absolute invocation deadline. The earlier deadline covers DNS
resolution, TCP connection setup, TLS handshake, response headers, and body
reads; the supplied per-request timeout is not restarted for each byte read.
Hostname DNS resolution runs in a short-lived Python subprocess that is killed
and waited for when its remaining deadline expires. The operating system may delay
process creation itself; the checker checks the deadline again immediately
afterward. It also enforces a 256-KiB per-source cap and a 1-MiB total response
cap. Bytes from failed attempts and retries consume the same invocation budget.

Interpret `current` narrowly: complete bytes from the same configured path
match the last-assessed digest within the 30-day assessment window.
`review_required` means that path changed; a bounded text difference is
included only when the prior pinned bytes are retrieved completely and match
the recorded digest. `stale` means unchanged bytes have passed the assessment
window. `unavailable` means access or completeness was not established, and
the report retains the last-assessed identity and disposition. A pinned
snapshot retrieval is provenance for a comparison, not evidence that the
mutable path is current. No result changes adoption or disposition; a changed
source requires review before any separate authorized update.

Sources whose captured representation cannot be compared with a raw-byte
fetch remain manual and report `unavailable` to the checker. This includes the
documentation captures whose MCP-rendered content is not equivalent to raw
HTML. Record that limit rather than converting it into a change or freshness
claim. Apply `adopt`, `adapt`, `defer`, or `reject` only through a separately
reviewed change with its rationale and affected local references.
