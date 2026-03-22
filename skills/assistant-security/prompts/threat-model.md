# Threat Model Prompt

Load this during Phase 2 (Plan) when the Security section flags any of: auth changes, PII handling, payment processing, or external input surfaces. Walk through each section and produce a structured threat summary for the plan.

## When to use

Use this prompt when the task involves any of:
- Authentication or authorization changes
- Handling PII, health data, financial data, or credentials
- Payment or billing logic
- New API endpoints exposed to the internet
- File uploads, webhooks, or other external input surfaces
- Third-party integrations that receive or send sensitive data

Skip for: internal tooling with no auth, pure UI styling, documentation-only changes.

## Walkthrough

Work through these sections in order. For each, state what applies and what doesn't. "N/A" is a valid answer — the goal is to think through each area, not to force-fit risks.

### 1. Data flow

- What data enters the system in this change? (user input, API calls, file uploads, webhooks)
- Where does it go? (memory only, database, cache, external service, logs, browser storage)
- Who can access it? (anonymous, authenticated user, admin, service account, third-party)
- Is any data sensitive? (PII, credentials, financial, health — classify it)
- Data at rest: encrypted? Data in transit: TLS enforced?

### 2. Auth boundaries

- What's authenticated? (which endpoints/actions require a logged-in user)
- What's authorized? (which actions check permissions beyond "is logged in")
- What's public? (what's intentionally accessible without auth)
- Any elevation paths? (can a regular user reach admin functionality?)
- Token/session handling: expiry, rotation, revocation — what changes?

### 3. Input validation

List every new input surface introduced by this change:

| Input | Source | Validation | Max size | Encoding |
|---|---|---|---|---|
| [field/param] | [user form / query param / header / body / file] | [type check, regex, allow-list, etc.] | [limit] | [UTF-8, base64, etc.] |

For each: what happens if validation fails? (reject with error, sanitize, log and continue)

### 4. Secrets management

- New secrets introduced? (API keys, connection strings, signing keys)
- Where stored? (environment variable, user-secrets, vault, config file — never in code)
- How injected at runtime? (DI, env var, config provider)
- Rotation plan: can this secret be rotated without downtime?
- Who has access to the secret? (dev machine only, CI, production)

### 5. Dependencies

- New packages added? List each with:
  - Name and version
  - What it's used for
  - Maintainer activity (last publish date, open issues)
  - Known vulnerabilities (`dotnet list package --vulnerable` / `npm audit`)
  - Trust level: official SDK, well-known OSS, or lesser-known?
- Any new native/system dependencies?
- Supply chain: are lock files updated and committed?

### 6. Common vulnerability check

Quickly assess these against the change (check or N/A):

- [ ] SQL injection — parameterized queries or ORM used?
- [ ] XSS — output encoded? CSP headers?
- [ ] CSRF — anti-forgery tokens on state-changing requests?
- [ ] Path traversal — file paths validated against allow-list?
- [ ] Mass assignment — DTOs restrict bindable properties?
- [ ] Insecure deserialization — no untrusted type deserialization?
- [ ] SSRF — outbound URLs validated against allow-list?
- [ ] Logging PII — no sensitive data in logs?

## Output format

Produce a threat summary block that drops into the plan's Security section:

```markdown
### Threat Summary

**Scope:** [one-line description of what's being secured]
**Risk level:** [low / medium / high] — [one sentence justification]

**Data flow:**
- [summary of data in/out and classification]

**Auth:**
- [summary of auth boundaries affected]

**Input surfaces:**
- [count] new inputs, all validated via [approach]
- Failure mode: [reject / sanitize]

**Secrets:**
- [count] new — stored in [mechanism], injected via [method]
- Rotation: [yes, via X / no, because Y]

**Dependencies:**
- [count] new packages, [vulnerability status]
- Lock file: [updated / already current]

**Vulnerability check:**
- [any items flagged from the common check, or "all clear"]

**Residual risks:**
- [anything that can't be fully mitigated, with accepted risk rationale]

**Requires human sign-off:** [yes/no] — [who, if yes]
```
