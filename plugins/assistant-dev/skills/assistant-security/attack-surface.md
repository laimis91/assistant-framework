# Attack Surface Analysis

Map all entry points and input vectors in your application. Understand what's exposed before analyzing what's vulnerable.

## When to use
- Starting security work on an existing codebase
- Before a penetration test (know your own surface first)
- After adding new endpoints, integrations, or input methods
- When onboarding to a new project's security posture

## Process

### Step 1: Map endpoints

Search the codebase for all exposed entry points:

**.NET:**
```bash
# Find all controller actions / minimal API endpoints
rg "MapGet|MapPost|MapPut|MapDelete|HttpGet|HttpPost|HttpPut|HttpDelete" --type cs
# Find SignalR hubs
rg "Hub<|: Hub" --type cs
# Find background services / message handlers
rg "IHostedService|BackgroundService|IConsumer<" --type cs
```

**Node.js:**
```bash
rg "app\.(get|post|put|delete|patch)\(" --type js --type ts
rg "router\.(get|post|put|delete|patch)\(" --type js --type ts
```

### Step 2: Classify each endpoint

| Endpoint | Method | Auth | Input Sources | Data Touched | Risk |
|----------|--------|------|--------------|-------------|------|
| /api/users | GET | JWT | query params | User table | LOW |
| /api/upload | POST | JWT | multipart file | Blob storage | HIGH |
| /webhook/stripe | POST | Signature | raw body | Payment records | HIGH |
| /health | GET | None | — | — | LOW |

### Step 3: Identify input vectors

Beyond HTTP endpoints, look for:
- **File uploads**: What types accepted? Size limits? Where stored?
- **Webhooks**: Who can send? How verified (HMAC, IP whitelist)?
- **Message queues**: What messages consumed? Schema validated?
- **Scheduled jobs**: What data do they process? From where?
- **Environment/config**: What values affect behavior? Who can change them?
- **Database**: Direct access by other systems? Shared databases?

### Step 4: Rate exposure

For each entry point:
- **Public** (internet-facing, no auth) — highest scrutiny
- **Authenticated** (requires login) — moderate scrutiny
- **Internal** (service-to-service, not internet-facing) — lower scrutiny
- **Admin** (restricted access) — high impact if compromised

### Step 5: Prioritize review

Focus security review on:
1. Public endpoints with file/data input (highest risk)
2. Endpoints touching sensitive data (PII, payments)
3. Endpoints with complex authorization logic
4. Third-party integration points

## Output format

```
ATTACK SURFACE: [application name]
Date: [YYYY-MM-DD]

SUMMARY
- [N] HTTP endpoints ([M] public, [K] authenticated, [L] internal)
- [N] input vectors (files, webhooks, queues, etc.)
- [N] third-party integrations

ENDPOINT MAP
| Endpoint | Method | Auth | Inputs | Data | Risk |
|----------|--------|------|--------|------|------|
| ...      | ...    | ...  | ...    | ...  | ...  |

OTHER INPUT VECTORS
- [vector]: [description, auth mechanism, data affected]

HIGH-PRIORITY REVIEW TARGETS
1. [endpoint/vector] — [why it's high priority]
2. ...

RECOMMENDATIONS
- [ ] [action item]
```
