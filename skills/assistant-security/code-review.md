# Security Code Review

Review code for common vulnerabilities. Focused on OWASP Top 10 and language-specific pitfalls.

## When to use
- Before merging a PR that touches auth, input handling, or data access
- After writing new API endpoints or data processing code
- As a self-check before requesting human security review
- When you suspect a vulnerability but aren't sure where

## Process

### Step 1: Scope the review
Identify what to review:
- Changed files (from git diff or plan steps)
- Focus areas: input handling, auth checks, data access, output encoding, error handling

### Step 2: Check each category

**Injection (SQL, Command, LDAP, XSS)**
- Are all database queries parameterized? (No string concatenation in SQL)
- Are shell commands avoided? If not, are inputs sanitized?
- Is user-provided content HTML-encoded before rendering?
- Are Content-Security-Policy headers set?

**Authentication & Session**
- Are passwords hashed with bcrypt/Argon2 (not MD5/SHA1)?
- Do sessions expire? Are tokens rotated after login?
- Is auth checked on every protected endpoint (not just the frontend)?
- Are failed login attempts rate-limited?

**Authorization**
- Is there a check beyond "is logged in" for sensitive operations?
- Can users access other users' data by changing IDs in URLs/params?
- Are admin endpoints protected by role checks, not just URL obscurity?

**Data Exposure**
- Are API responses filtered to exclude internal fields?
- Are error messages generic (no stack traces, SQL errors in production)?
- Are logs free of PII, tokens, and credentials?
- Is sensitive data encrypted at rest?

**Input Validation**
- Does every input have a type check, length limit, and format validation?
- Are file uploads restricted by type, size, and stored outside webroot?
- Are redirects validated against an allow-list (no open redirects)?

**Dependencies**
- Run `dotnet list package --vulnerable` or `npm audit`
- Are lock files committed?
- Any packages with known CVEs?

**Cryptography**
- No custom crypto (use established libraries)?
- Are secrets in environment variables, not code?
- Is TLS enforced for all external communication?

### Step 3: Report findings

## Output format

```
SECURITY REVIEW: [scope description]

FINDINGS
| # | Severity | Category | File:Line | Issue | Fix |
|---|----------|----------|-----------|-------|-----|
| 1 | HIGH     | Injection | src/api.cs:42 | Raw SQL concatenation | Use parameterized query |
| 2 | MEDIUM   | Auth     | ... | ... | ... |

CLEAN AREAS
- [category]: No issues found in [scope]

RECOMMENDATION
- [ ] [action items, ordered by severity]
```

## Severity guide
- **CRITICAL**: Exploitable now, data loss or unauthorized access likely
- **HIGH**: Exploitable with moderate effort, significant impact
- **MEDIUM**: Requires specific conditions, limited impact
- **LOW**: Defense-in-depth improvement, no direct exploit path
