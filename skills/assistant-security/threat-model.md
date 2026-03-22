# Threat Model

Structured analysis of your application's security architecture. Use anytime — not just during planning.

## When to use
- Starting a new project or major feature
- Adding auth, payments, file uploads, or external integrations
- Before a release or security review
- When you want a comprehensive security picture (not just a code-level check)

## Process

### Step 1: Identify assets
What are you protecting? List the valuable things:
- User data (PII, credentials, sessions)
- Business data (transactions, intellectual property)
- System access (admin panels, APIs, databases)
- Reputation (availability, data integrity)

### Step 2: Map trust boundaries
Where does trust change? Draw the lines:
- Internet ↔ your API (authentication boundary)
- API ↔ database (authorization boundary)
- Your system ↔ third-party services (integration boundary)
- Frontend ↔ backend (input validation boundary)

### Step 3: Identify threats (STRIDE)
For each trust boundary, consider:

| Threat | Question |
|---|---|
| **S**poofing | Can someone pretend to be another user/system? |
| **T**ampering | Can data be modified in transit or at rest? |
| **R**epudiation | Can actions be denied without evidence? |
| **I**nformation disclosure | Can sensitive data leak? |
| **D**enial of service | Can the system be overwhelmed? |
| **E**levation of privilege | Can a user gain unauthorized access? |

### Step 4: Rate and mitigate
For each threat found:
- **Likelihood**: LOW / MEDIUM / HIGH / CRITICAL
- **Impact**: LOW / MEDIUM / HIGH / CRITICAL
- **Mitigation**: What controls exist or are needed?
- **Residual risk**: What remains after mitigation?

### Step 5: Detailed walkthrough (optional)
For deeper analysis, load `references/prompts/threat-model.md` — it covers data flow, auth boundaries, input validation, secrets management, dependencies, and OWASP common vulnerabilities in detail.

## Output format

```
THREAT MODEL: [application/feature name]
Date: [YYYY-MM-DD]

ASSETS
- [asset]: [why it matters]

TRUST BOUNDARIES
- [boundary]: [what changes across it]

THREATS
| # | Boundary | Threat (STRIDE) | Likelihood | Impact | Mitigation |
|---|----------|-----------------|------------|--------|------------|
| 1 | ...      | ...             | ...        | ...    | ...        |

RESIDUAL RISKS
- [risk]: [accepted because...]

ACTIONS
- [ ] [concrete action to implement]
```
