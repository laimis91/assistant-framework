# Investigate

Deep investigation of entities, domains, or topics with ethical framework and structured methodology.

## When to use
- Due diligence on a library, service, or vendor
- Understanding a domain before building for it
- Investigating a technical issue across multiple systems
- Competitive/landscape analysis

## Ethical Framework

Before any investigation:
1. **Scope**: Define what you're investigating and why
2. **Sources**: Public sources only (docs, repos, public APIs, published articles)
3. **Proportionality**: Investigation depth should match the decision's importance
4. **No PII**: Never investigate individuals' personal information unless they're public figures in a professional context and the user has legitimate need

## Investigation Types

### Technology/Library Assessment
Evaluate a technology choice:
- Official documentation quality and completeness
- GitHub activity (stars, issues, PRs, commit frequency, bus factor)
- Breaking changes history and versioning policy
- Community size and support channels
- Security track record (CVEs, response time)
- License compatibility
- Alternatives comparison

### Domain Research
Understand a problem space:
- Key concepts and terminology
- Major players and solutions
- Common patterns and anti-patterns
- Regulatory/compliance considerations
- Industry standards and protocols

### Issue Investigation
Track down a cross-cutting technical issue:
- Reproduce the conditions
- Map the dependency chain
- Check known issues in each dependency
- Cross-reference with community reports
- Timeline analysis (when did it start? what changed?)

## Process

1. **Define scope and question** — What specifically do we need to know? Why?
2. **Plan sources** — Which sources are most likely to have answers?
3. **Execute** — Search, read, cross-reference (use Research tool for parallel gathering)
4. **Verify** — Cross-validate claims, verify URLs, check dates
5. **Synthesize** — Answer the question with confidence levels
6. **Document** — Use `memory_add_insight` to store findings in the knowledge graph if they'll be useful later

## Output format

```
INVESTIGATION: [subject]
Scope: [what and why]
Date: [YYYY-MM-DD]

SUMMARY
[2-3 sentence executive summary]

FINDINGS
[Organized by sub-topic, each with confidence level]

ASSESSMENT
Strengths: [...]
Risks: [...]
Recommendation: [...]

SOURCES
- [source 1 — verified]
- [source 2 — verified]
```
