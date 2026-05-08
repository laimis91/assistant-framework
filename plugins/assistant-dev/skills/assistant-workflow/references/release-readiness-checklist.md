# Release Readiness Checklist

Complete this during Phase 7 (Document). The checklist scales by task size from triage. Check items that apply, mark N/A for those that don't. Items that need human sign-off are flagged — the AI fills in what it can verify and flags the rest.

## Checklist by task size

### All sizes (small, medium, large, mega)

- [ ] Code compiles / builds with zero errors
- [ ] All existing tests pass
- [ ] New code has tests (unit tests at minimum)
- [ ] Code reviewed by a human (AI review is not sufficient)
- [ ] CHANGELOG updated (if user-facing change)
- [ ] No hardcoded secrets, API keys, or credentials in code
- [ ] No TODO/FIXME left without a tracking issue

### Medium and above

- [ ] README updated if setup, config, or usage changed
- [ ] SAST / code scanning run (e.g., CodeQL, Roslyn analyzers, SonarQube)
- [ ] Dependency scan run — no known critical/high vulnerabilities
- [ ] New dependencies justified and lock file updated
- [ ] Secrets handled via configuration (not code) — environment variables, user secrets, or vault
- [ ] Threat model reviewed if change touches: auth, PII, payments, external inputs
  - ⚠️ Human sign-off required: [Security / Tech Lead]
- [ ] New API endpoints documented (OpenAPI, README, or inline docs)
- [ ] Observability: new code paths have logging and/or metrics
- [ ] Error handling: new failure modes have structured error responses

### Large and mega

- [ ] Architecture docs updated if layers or patterns changed
- [ ] AGENTS.md / CONTRIBUTING.md updated if conventions changed
- [ ] SBOM generated for release (CycloneDX or SPDX format)
- [ ] Rollback plan defined:
  - [ ] Feature flag available: [yes/no]
  - [ ] DB migration reversible: [yes/no/N/A]
  - [ ] Revert commit sufficient: [yes/no]
  - [ ] Rollback tested or steps documented
- [ ] SLO impact assessed — will this change affect service reliability?
  - ⚠️ Human sign-off required: [SRE / Tech Lead]
- [ ] Observability: dashboards, alerts, or runbooks updated
- [ ] Performance: no regressions in critical paths (load test or benchmark if applicable)
- [ ] Integration tests pass across module/service boundaries
- [ ] Runbook updated for on-call (if new service, infrastructure, or failure mode)
  - ⚠️ Human sign-off required: [SRE / Platform]
- [ ] Deploy strategy defined (direct, canary, blue-green)

## How to use this checklist

1. During Phase 7, the AI generates this checklist pre-filled based on task size
2. AI checks off items it can verify (tests pass, no secrets in code, docs updated)
3. AI flags items that need human action with ⚠️
4. Present the completed checklist to the user for review
5. Attach the checklist to the PR or release notes

## Output format

```
Release Readiness: [task name]
Size: [small/medium/large/mega]
Date: [YYYY-MM-DD]

✅ Verified by AI:
- [x] Build passes
- [x] All tests pass (N unit, M integration)
- [x] No secrets in code
- [x] CHANGELOG updated
- ...

⚠️ Needs human verification:
- [ ] Code review by human
- [ ] Security sign-off (threat model for auth changes)
- [ ] SLO impact assessment
- ...

N/A for this change:
- SBOM (small task, no release artifact)
- Rollback plan (config change only)
- ...
```

## CI/CD mapping (reference)

For teams with CI pipelines, these checklist items map to automated gates:

| Checklist item | CI job | Blocks merge? |
|---|---|---|
| Build passes | `dotnet build` / `npm run build` / `pio run` | Yes |
| Tests pass | `dotnet test` / `npm test` / `pio test` | Yes |
| SAST scan | CodeQL / SonarQube / Roslyn | Yes (medium+) |
| Dependency scan | Dependabot / OWASP Dependency-Check | Yes (medium+) |
| Secrets scan | git-secrets / truffleHog / gitleaks | Yes |
| SBOM generation | CycloneDX CLI / Syft | No (artifact) |
| Lock file present | Check for packages.lock.json / package-lock.json | Yes |

Items without CI automation remain manual checklist items reviewed during PR.
