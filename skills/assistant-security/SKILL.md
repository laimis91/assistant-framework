---
name: assistant-security
description: "This skill provides security analysis: threat modeling, code review, dependency auditing, and attack surface mapping. Use when the user says 'security', 'threat model', 'audit', 'vulnerability', 'attack surface', 'OWASP', 'CVE', 'dependency check'. Also activates when touching authentication, user inputs, or sensitive data handling."
triggers:
  - pattern: "security review|security audit|security analysis"
    priority: 85
    reminder: "This request matches assistant-security. You MUST invoke the Skill tool with skill='assistant-security' BEFORE proceeding."
  - pattern: "security|threat model|vulnerability|attack surface|owasp|cve|dependency check"
    priority: 75
    reminder: "This request matches assistant-security. You MUST invoke the Skill tool with skill='assistant-security' BEFORE proceeding."
---

# Security Tools

## Contracts

| Contract | File | Purpose |
|---|---|---|
| **Input** | `contracts/input.yaml` | Analysis type, scope, severity threshold |
| **Output** | `contracts/output.yaml` | Findings with severity, remediation, and risk level |
| **Phase Gates** | `contracts/phase-gates.yaml` | Scope → Analyze → Report pipeline gates |
| **Handoffs** | `contracts/handoffs.yaml` | Subagent dispatch contracts (currently none) |

**Rules:**
- Every finding must have severity, impact, and remediation — observations without fixes are not actionable
- Severity levels follow the 4-level scale consistently
- Findings must be evidence-based — cite specific code, config, or dependency

On-demand security analysis. Use when touching auth, inputs, dependencies, or preparing for review.

## Goal

Identify concrete security risks with evidence, severity, impact, and remediation that can be acted on before release or merge.

## Success Criteria

- Scope, analysis type, and severity threshold are explicit.
- Findings cite specific code, config, dependency, or threat paths.
- Each finding includes severity, impact, and smallest useful remediation.
- Residual risks and unassessed areas are called out separately from findings.

## Constraints

- Do not report generic security advice without evidence in the reviewed surface.
- Ask only when missing scope or access prevents a trustworthy security conclusion.
- Treat exploitable vulnerabilities and secret exposure as blockers, not nits.

## Available Tools

| Tool | File | When to use |
|---|---|---|
| **Threat Model** | `threat-model.md` | New features, auth changes, external integrations. STRIDE analysis. |
| **Code Review** | `code-review.md` | Before merging PRs touching auth, input handling, data access. OWASP Top 10. |
| **Dependency Audit** | `dependency-audit.md` | Before releases, after adding packages, periodic CVE checks. |
| **Attack Surface** | `attack-surface.md` | Starting security work, after adding endpoints/integrations. |

## Usage

Read the relevant tool file when the situation calls for it.

**When to use which tool:**
- Starting a new feature with external input -> Attack Surface first, then Threat Model
- Adding/updating NuGet packages -> Dependency Audit
- PR touches auth, sessions, or data access -> Code Review (OWASP)
- New API endpoints or integrations -> Threat Model (STRIDE)

**Deep analysis:**
For thorough threat modeling, also load `prompts/threat-model.md` — it provides a detailed prompt pack for comprehensive STRIDE analysis.

## Severity Scale

All tools use a consistent 4-level scale:
- **CRITICAL**: Immediate exploitation risk, data breach potential
- **HIGH**: Significant vulnerability, needs fix before release
- **MEDIUM**: Should fix, but not immediately exploitable
- **LOW**: Minor concern, fix when convenient

## Output

Return:
- **Status** - completion state and confidence for the security analysis.
- **Risk summary** - overall result and scope assessed.
- **Findings** - actionable items with severity, impact, evidence, and remediation.
- **Evidence** - specific code, config, dependency, or threat path for each finding.
- **Residual risk** - accepted risks, assumptions, or areas not assessed.
- **Blockers** - missing access, missing context, or follow-up questions required for confidence.

## Stop Rules

- Stop and ask when required source, dependency, or deployment context is unavailable and affects severity.
- Stop and escalate immediately if a secret, credential, or active exploit path is found.
- Do not finalize a clean security result when important scope was inaccessible; report the residual risk.
