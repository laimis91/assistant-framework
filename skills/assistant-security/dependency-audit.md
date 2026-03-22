# Dependency Audit

Analyze project dependencies for known vulnerabilities and supply chain risks.

## When to use
- Before a release
- After adding new packages
- Periodically (monthly recommended)
- When a major CVE is announced in your ecosystem

## Process

### Step 1: Run built-in scanners

**.NET:**
```bash
dotnet list package --vulnerable
dotnet list package --deprecated
dotnet list package --outdated
```

**Node.js:**
```bash
npm audit
npm outdated
```

**Python:**
```bash
pip audit
pip list --outdated
```

### Step 2: Analyze each vulnerability

For each finding:
- **CVE ID**: The specific vulnerability
- **Package**: Which dependency
- **Severity**: CRITICAL / HIGH / MEDIUM / LOW
- **Exploitable in our context?**: Not all CVEs apply to every usage
- **Fix available?**: Is there a patched version?
- **Breaking changes?**: Will upgrading break anything?

### Step 3: Assess supply chain risk

For each critical dependency (top 10 by importance):
- **Maintainer activity**: Last commit, release frequency
- **Bus factor**: How many active maintainers?
- **Download trend**: Growing, stable, or declining?
- **License**: Compatible with your project?
- **Alternatives**: If this dies, what's the replacement?

### Step 4: Check lock files
- Is the lock file committed? (package-lock.json, packages.lock.json, etc.)
- Does `install --frozen-lockfile` succeed?
- Any unexpected changes in the lock file?

## Output format

```
DEPENDENCY AUDIT: [project name]
Date: [YYYY-MM-DD]
Ecosystem: [.NET / Node / Python]

VULNERABILITIES
| Package | Version | CVE | Severity | Exploitable? | Fix |
|---------|---------|-----|----------|-------------|-----|
| ...     | ...     | ... | ...      | ...         | ... |

DEPRECATED
- [package] — deprecated since [date], replace with [alternative]

SUPPLY CHAIN RISKS
- [package]: [concern — e.g., single maintainer, no releases in 2 years]

ACTIONS
- [ ] Upgrade [package] to [version] (fixes CVE-XXXX)
- [ ] Replace [deprecated package] with [alternative]
- [ ] Monitor [risky package] for maintainer changes
```
