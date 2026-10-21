---
name: assistant-security
description: "Analyze threats, vulnerabilities, dependencies, and attack surfaces. Use for explicit security work or changes to auth, input, or sensitive data."
---

# Analyze Security Risks

## Shared operating guidance

Load [the common outcome guidance and shared stagnation policy](../../tools/progress/operating-guidance.md) for this activity. Keep specialist methods, authority and completion evidence below; single-pass work needs no progress artifact.


Inspect the requested surface and report concrete attack paths, their impact, and the smallest useful remediation. Infer scope and method from context; ask only when missing source, access, or deployment facts prevent a trustworthy conclusion. Keep analysis read-only unless remediation is authorized.

Load the relevant reference, using only checklist categories that apply:

| Analysis | Reference | Focus |
|---|---|---|
| Threat model | `threat-model.md` | Trust boundaries and threats; STRIDE where useful |
| Code review | `code-review.md` | Reachable vulnerabilities in changed code |
| Dependency audit | `dependency-audit.md` | Actual dependency versions and exposure |
| Attack surface | `attack-surface.md` | Entry points, privileges, and integrations |

For a detailed requested threat model, `prompts/threat-model.md` provides additional prompts. Check relevant paths such as authentication/authorization, tenant isolation, untrusted input, data access, shell/process execution, file paths, network integrations, serialization, dependency/configuration risk, and privacy/logging. Do not turn an irrelevant category into a finding.

Each finding needs specific redacted evidence (file/line, configuration, dependency, or threat path), a reachable attack or misuse path, impact, severity, remediation, and a verification step. Separate demonstrated behavior from assumptions. Do not invent vulnerabilities or report generic advice as findings. Respect the requested severity threshold and order findings by material risk.

Use a consistent severity scale:

- **critical**: immediate exploitation or breach risk;
- **high**: significant vulnerability needing attention before release;
- **medium**: material weakness with limited or conditional exploitability;
- **low**: minor exposure or defense improvement.

State the assessed scope, result, and confidence; report residual risks, inaccessible areas, and evidence gaps that limit a clean conclusion. Omit empty reporting sections. If structured output is requested, preserve `findings` with `severity`, `category`, `description`, `impact`, and `remediation`; include evidence and attack path, `summary`, highest material `risk_level` (or `none`), and prioritized `action_items` when findings require fixes.

Never paste, log, or repeat secret values; redact and cite location only. Use local/repo-native checks where available. Do not upload proprietary code, install scanners, or call external scanning services without authorization. If a credential exposure or active exploit path is found, promptly report the redacted evidence and required containment within the authorized scope; do not claim broad safety from inaccessible evidence or perform unapproved remediation.
