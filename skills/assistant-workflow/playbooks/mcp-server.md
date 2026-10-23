# MCP Server

Design around the concrete user question and smallest sufficient answer. Inspect
the nearest existing operation first: extend it when intent, result and authority
match; add a tool when the outcome or authority boundary is distinct. Inspection,
discovery, tracing, comparison, composition and capture are optional shapes,
not a required tool taxonomy. Compose demonstrated repeated work; batch homogeneous
reads with per-item outcomes. Avoid speculative DSLs, mega-tools and replay engines.

## Discover the actual boundary

Inspect the project's installed SDK, connected tool schemas, intended clients
and supported transports; consult current official protocol/SDK documentation
when a constraint is unknown. Select from those capabilities without prescribing
a remembered version or migrating transport as part of ordinary tool design.
Ask only remaining consequential questions about target, authority, persistence
or authentication that source/configuration cannot resolve.

Keep these distinct: configured provider, available session capability,
advertised schema and observed behavior. A configured provider may be unavailable;
an advertised operation may fail on the intended client. Name unavailable facets.
Capabilities and annotations grant neither permission nor target ownership.
Declare actual filesystem, process, network, UI and mutation effects, temporary
resources, and launch-versus-attach authority. Owning a connection does not grant
permission to terminate its attached target. Keep secrets in configuration.

## Inputs and results

Preserve target identity and meaningful choices. Specify absent, null, empty,
default and invalid semantics wherever they differ. Preserve genuine optionality
through SDK conversion; do not require every field merely to simplify a schema.
Reject ignored/unsupported options explicitly instead of returning misleading success.

Return useful facts, relevant identity/provenance, coverage, limits and per-item
or partial outcomes. Distinguish observation from inference. An empty visible
selection, missing health or failed collection does not prove source-wide absence.
Align CLI and MCP semantics when both surfaces exist; transport envelopes may differ.
Translate errors into useful structured diagnostics, preserving primary failures
and available partial results rather than returning raw exceptions.

For large results, use client-supported summaries/selections, stable ordering,
paging or retained references as needed. Keep complete-source access and source
identity/version consistent across pages; exhausting a page does not establish
source completeness. Do not rerun capture solely because a response was truncated.
If complete access is unavailable, report that gap. Small stateless tools need
neither mandatory retention nor a rerun/retention platform.

Derive limits from protocol, format, authority or measured constraints and enforce
them before expensive allocation. Account for expansion, concurrency, serialization,
retention and cleanup. State units and failure behavior; small payload size alone
does not establish memory, latency or cost efficiency.

## Illustrative structure

Handler-per-tool with shared services is a useful starting point when those
boundaries exist, not a mandatory architecture. Keep handlers independently
callable and move actually shared logic into services rather than tool-to-tool
coupling. Use named request/result types preserving domain identity and ownership.

C#:

```text
src/McpServer/
  Tools/       # Tool handlers
  Services/    # Shared behavior, injected where useful
  Models/      # Meaningful request/result contracts
  Program.cs   # Host, registration and configuration
 tests/McpServer.Tests/
```

TypeScript:

```text
src/
  tools/       # Tool handlers
  services/    # Shared behavior
  types/       # Request/result contracts
  index.ts     # Host and registration
 tests/
```

## Worked example: small stateless inspection

Question: “Which operations are declared by this local manifest?” The existing
`inspect_manifest` already reads one manifest and returns its declarations; reuse
it, adding a selection only if callers demonstrate that need. Do not introduce
separate discover/list/trace/capture tools to answer this one question.

Inputs: `manifest_path` is required and identifies an authorized local file.
Optional `operation_names` absent means all declarations; `[]` requests none;
null and empty/invalid names are rejected. If that distinction is supported by
source behavior, preserve it in the SDK-converted schema and handler. No ignored
`include_runtime_health` flag: a manifest read cannot observe runtime health.

Effects: one authorized filesystem read; no process, network, UI or persistent
resource. Result includes resolved source identity/content digest, selected
operations, declared-only provenance and selection coverage. A named operation
missing from a fully parsed manifest is absent from that manifest version only;
runtime availability remains unknown. Unreadable or malformed files yield a
structured diagnostic; no invented empty-success list. A bounded small result
needs no retention store.

Falsifiable observations: a known manifest returns its exact declarations and
digest; absent versus `[]` selects all versus none. Null or malformed input is
rejected; an unreadable manifest reports failure rather than “no operations.”
Inspect the actual SDK-advertised schema for optionality and exercise these calls
through the intended client before claiming client usability. A source DTO or
snapshot alone cannot establish that. A task/description keyword match is only a
discovery proxy; native selection evidence would record the actual selected tool
and arguments for this representative question on the actual host. No such run
is claimed here.

## Worked example: large resource-owning capture

Question: “What failed across these workers during this capture interval, and can
I inspect every collected event?” An existing `inspect_capture` can read a stored
capture with matching authority, so reuse it for inspection. Add `capture_workers`
only for the distinct authorized acquisition outcome; keep acquisition separate
from reading/paging and avoid a mega-tool that also edits or restarts workers.

Inputs identify targets, interval and mode. A launch request may own children;
an attach request owns only its connection. Optional facets absent means the
supported default; null is rejected, `[]` means collect no optional facets, and
unsupported requested facets return explicit per-facet unavailable status. Preserve
these distinctions in the actual advertised schema and CLI contract if present.
Provider configuration is not proof of session support or successful collection.

Effects include declared process launch when authorized, connections, temporary
capture files and retention with a stated expiry/access policy. Attach grants no
shutdown authority over the target. Enforce justified event/expanded-byte,
concurrency and retention limits before allocating; make overflow/truncation and
cleanup outcomes explicit. Select lifecycle checks through workflow's existing
assistant-verification dependency, which conditionally loads its local lifecycle
guide; do not duplicate a universal lifecycle matrix here.

Result includes capture ID, immutable source version/digest, interval, target
identity, stable event ordering, collected/failed/unavailable facets per target,
coverage limits and the primary diagnostic. Return a summary and a supported
reference/page route to the complete retained source. Pages bind the same source
identity; retention expiry returns an explicit unavailable result. “No failures”
is restricted to collected covered facets and interval. Missing worker health
or incomplete capture remains unknown. Retain useful partial data when one
worker fails. Leader exit or lost transport cannot alone certify descendant or
handle release; report unresolved owners separately from capture success/failure.

Falsifiable observations: a successful controlled capture yields known events,
one source identity and complete stable pagination. Inject one bounded worker
collection failure: keep other events, the primary diagnostic and explicit unknown
coverage. Verify unavailable facets are not reported healthy. A finalization
cancellation check reaches a marker, observes retained partial data and settlement;
an attached-target control remains running after connection cleanup. A truncated
summary still resolves the original complete capture without a capture rerun.
Select only these material uncovered checks, reusing adequate existing evidence.

Inspect the SDK-converted advertised schema and calls on the intended client for
public-schema/client claims. An injected provider proves only the controlled
boundary; real-provider claims need actual corresponding observations. Discovery
proxies do not prove native choice: representative native evidence must record
actual selected tools/arguments and host/source identity. This example claims no
native, provider, efficiency or comparative result.

## Misleading valid-schema counterexample

A schema may accept optional `include_health: null` and `target_mode: attach`, yet
silently ignore both, launch a worker, return “healthy/no failures” from the first
truncated page and kill the target during cleanup. Schema validity cannot rescue
that contract: inputs/effects/authority disagree, unknown coverage becomes absence,
and truncation loses complete-source access. Reject the design even if source
schema checks pass. Prefer truthful unsupported-input/partial results and explicit
authority to success-shaped output.

## Verification

Use assistant-verification for proportionate selection. Select relevant success,
malformed, unavailable, partial, cancellation and cleanup observations at the
actual claimed boundary; there is no test-per-row requirement. Use repository
build/test commands for the installed SDK/runtime (for example `dotnet build`
and `dotnet test`, or project `npm run build` and `npm test` when defined).
Source types, offline fixtures, injected providers and real clients/providers
support different claims; preserve the limits rather than promising discovery
or runtime behavior from structural checks.

Source basis: REA tool-design/testing guides at
`5927937179476c66aa8621658faca42f9578b42a`; examples above are original and
provider-neutral. No upstream code or service is adopted and upstream tests were
not run.
