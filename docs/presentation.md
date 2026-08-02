# Assistant Framework

## A development workflow that makes delivery more reliable

---

## The Problem

AI coding sessions can lack the structure needed for dependable delivery.

- No explicit task boundary
- No proportionate plan for a risky change
- No reliable evidence trail
- No independent review
- No structured workflow — just vibes

**You provide the goals. The framework provides a disciplined delivery loop.**

---

## What If Your AI Could...

- Cover your weaknesses (docs, diagrams, onboarding)
- Follow a battle-tested development workflow
- Use focused verification and independent review
- Work the same way across Claude, Codex, and Gemini

---

## Assistant Framework

**14 composable skills. One evidence-gated workflow system.**

Built from scratch. No imports. No marketplace dependencies.

Works with: **Claude Code** | **OpenAI Codex** | **Google Gemini CLI**

---

## The Skills

```
┌─────────────────────────────────────────────────────────┐
│                    CORE WORKFLOW                         │
│                                                         │
│  Triage → Discover → Plan → Build & Test → Review → Doc │
│                                                         │
│  Right-sized ceremony: small tasks get light treatment,  │
│  large tasks get full pipeline with approval gates       │
└─────────────────────────────────────────────────────────┘
         │           │           │            │
    ┌────▼────┐ ┌────▼────┐ ┌───▼────┐ ┌────▼─────┐
    │Thinking │ │Research │ │Security│ │  Review  │
    │ Tools   │ │ Tools   │ │Analysis│ │  Loop    │
    │         │ │         │ │        │ │          │
    │6 modes  │ │4 tiers  │ │STRIDE  │ │Max 5     │
    │debate   │ │URL      │ │OWASP   │ │rounds    │
    │stress   │ │verify   │ │CVE     │ │auto-fix  │
    │test     │ │scoring  │ │attack  │ │fresh     │
    │creative │ │         │ │surface │ │reviewer  │
    └─────────┘ └─────────┘ └────────┘ └──────────┘
         │           │           │            │
    ┌────▼────┐ ┌────▼────┐ ┌───▼────┐ ┌────▼─────┐
    │  Docs   │ │Onboard  │ │ Ideate │ │Diagrams  │
    │         │ │         │ │        │ │          │
    │API docs │ │6-phase  │ │diverge │ │7 types   │
    │arch doc │ │codebase │ │converge│ │from code │
    │README   │ │analysis │ │refine  │ │Mermaid   │
    │changes  │ │auto-    │ │score   │ │sequence  │
    │migrate  │ │report   │ │decide  │ │ER, flow  │
    │explain  │ │handoff  │ │        │ │class     │
    └─────────┘ └─────────┘ └────────┘ └──────────┘
```

---

## Skill 1: Structured Workflow

**The invisible backbone.**

```
You: "I want to add caching to our API"

Framework:
  → Decomposes into 7 testable criteria
  → Asks for approval
  → Triages as MEDIUM
  → Discovers: reads codebase, maps architecture
  → Plans: ordered steps, risks, test strategy
  → Waits for plan approval
  → Builds: one step at a time, tests alongside
  → Reviews: spec compliance + quality (autonomous loop)
  → Documents: updates README, changelog
```

**Key principle: if the user notices the framework, it's too heavy.**

Small tasks get lightweight treatment. Large tasks get full ceremony. The framework adapts.

---

## Skill 2: Autonomous Code Review

**Not one pass. An autonomous loop.**

```
Round 1: Dispatch fresh Reviewer → finds 4 evidence-backed issues
         Fix all must-fix and should-fix
         Run tests → pass

Round 2: Dispatch NEW Reviewer (fresh context)
         Previously-fixed list provided → no re-reports
         Finds 1 more high-confidence should-fix
         Fix → test → pass

Round 3: Dispatch NEW Reviewer
         Clean. Speculative concerns stay in Observations.

Result: CLEAN after 3 rounds.
```

**Higher confidence threshold each round.** Early rounds catch obvious issues. Later rounds require higher certainty. Fresh reviewer each round prevents stale context.

---

## Skill 3: Security Analysis

**Four specialized tools, not generic scanning.**

| Tool | What It Does |
|---|---|
| **STRIDE Threat Model** | Systematic threat identification per component |
| **OWASP Code Review** | Top 10 vulnerability check against actual code |
| **CVE Dependency Audit** | Known vulnerability detection in dependencies |
| **Attack Surface Map** | Entry points, trust boundaries, data flows |

```
You: "Audit the auth flow"
→ Traces actual code paths
→ Identifies 3 findings with severity + confidence
→ Provides specific fix recommendations with code
```

---

## Skill 4: Thinking Tools

**Six on-demand reasoning tools. Used when needed, not on every task.**

| Tool | When | How |
|---|---|---|
| **Clarify** | Stuck or challenging assumptions | Hard vs. soft constraint classification |
| **Perspectives** | Architecture decisions | 4-role debate, 3 rounds |
| **Stress Test** | Validating important choices | Steelman + counter-argument |
| **Deep Think** | Requirements discovery | 8 analytical lenses |
| **Hypothesize** | Debugging mysteries | 3+ hypotheses, evidence-ranked |
| **Creative** | Naming, breakthrough ideas | Low-probability sampling |

---

## Skill 5: Documentation Generator

**Covers the #1 developer weakness.**

Six modes, all generated from actual code — not hallucinated:

| Mode | Input | Output |
|---|---|---|
| **API Docs** | Scans endpoints, DTOs, attributes | Full API reference with examples |
| **Architecture** | Traces layers, dependencies, patterns | System overview with Mermaid diagrams |
| **README** | Analyzes project purpose, build, config | Project README from code truth |
| **Changelog** | Git history between versions | Keep-a-Changelog format |
| **Migration** | Diff between versions | Breaking changes + migration steps |
| **Explainer** | Complex code section | Why-focused explanation |

**Also detects stale docs:**
```
>> Scanning documentation freshness...
   README.md: last updated 45 days ago, 3 new features since
   API.md: references endpoints that no longer exist
```

---

## Skill 6: Codebase Onboarding

**Systematic learning, not random file browsing.**

```
You: "Learn this codebase"

Phase 1: Surface Scan      → README, build files, project shape
Phase 2: Architecture Map  → layers, boundaries, data flow
Phase 3: Pattern Recognition → naming, error handling, DI, testing
Phase 4: Knowledge Gaps    → what's still unclear, asks you
Phase 5: Report            → concise summary and open questions

Output:
  Project: InventoryAPI
  Stack: .NET 8, ASP.NET Core, EF Core, PostgreSQL
  Architecture: Clean Architecture with vertical slices
  Size: medium (~120 files, ~15k lines)
  Conventions: PascalCase, Result<T> error handling, xUnit
  Ready to work on this codebase.
```

---

## Skill 7: Idea Generation

**Structured brainstorming, not random suggestions.**

```
You: "What are some ideas for improving search?"

Phase 1: UNDERSTAND → clarify the real problem
Phase 2: DIVERGE   → 12 ideas using multiple techniques
                      (inversion, analogy, scale shift, subtraction...)
Phase 3: CONVERGE  → score each on impact, feasibility, alignment
Phase 4: REFINE    → top 3 get detailed writeups
Phase 5: DECIDE    → present choices, user picks

"Go with #2" → feeds directly into the workflow skill
```

---

## Skill 8: Diagram Generator

**Seven diagram types, all from code analysis. All Mermaid.**

| Type | Best For |
|---|---|
| Architecture | System overview, component relationships |
| Sequence | Request flows, interaction patterns |
| Entity-Relationship | Data models, database schema |
| Flow | Business logic, decision trees |
| Component | Module boundaries, dependencies |
| Class | Type hierarchies, interfaces |
| State | State machines, lifecycle transitions |

```
You: "Draw the architecture"
→ Reads code, traces dependencies
→ Outputs verified Mermaid diagram
→ Every box and arrow corresponds to real code
```

---

## Multi-Agent Orchestration

**Specialized roles with constrained access.**

| Role | Access | What It Does |
|---|---|---|
| **Code Mapper** | Read-only | Lightweight structural map |
| **Explorer** | Read-only | Deep execution path tracing |
| **Architect** | Read-only | Implementation blueprint design |
| **Code Writer** | Write | Implements code following the plan |
| **Builder/Tester** | Write | Builds, writes tests, runs tests |
| **Reviewer** | Read-only | Independent review, confidence-filtered |

**Reviewer cannot edit files. Code Writer doesn't run tests.**
Separation of concerns at the agent level.

---

## Native Orchestration

**Provider-native capabilities plus portable framework contracts.**

| Layer | Owner | What |
|---|---|---|
| **Skill discovery** | Provider runtime | Selects installed skills from metadata and instructions |
| **Permissions** | Provider runtime | Owns command and file-operation approvals |
| **Subagents** | Provider runtime | Spawns configured specialist roles |
| **Compaction** | Provider runtime | Manages context lifecycle and continuation |
| **Contracts** | Assistant Framework | Defines phase, handoff, and completion evidence |
| **Evals + review** | Assistant Framework | Checks conformance and catches material defects |

Native capabilities stay native; Assistant Framework adds portable workflow discipline without a separate lifecycle layer.

---

## Cross-Platform

**One framework. Three agents. Same behavior.**

```bash
./install.sh --agent claude   # Claude Code
./install.sh --agent codex    # OpenAI Codex
./install.sh --agent gemini   # Google Gemini CLI
```

- Skills auto-adapt paths (`.claude/` → `.codex/` → `.gemini/`)
- Agent definitions per platform (`.md` for Claude, `.toml` for Codex)
- Native skill routing selects installed skills from metadata and instructions

---

## By the Numbers

| Metric | Count |
|---|---|
| Skills | 14 |
| Contract levels | 4 |
| Specialized agents | 6 |
| Thinking tools | 6 |
| Diagram types | 7 |
| Doc generation modes | 6 |
| Lines of YAML config | 0 (auto-discovered) |
| Marketplace imports | 0 (100% built in-house) |

---

## What Makes This Different

| Others | Assistant Framework |
|---|---|
| Skills as suggestions | Skills as **mandatory enforcement** |
| One-shot review | **Autonomous review loop** (max 10 rounds) |
| Generic patterns | **Current repository evidence** informs the task |
| Single agent | **Multi-agent orchestration** with role separation |
| One platform | **Three platforms** (Claude, Codex, Gemini) |
| Import from marketplace | **100% built in-house** |

---

## The Invisible Principle

> "If the user notices the framework, it's too heavy."

- Small tasks: quick discovery → lightweight plan → build → done
- Large tasks: full ceremony with approval gates and review loops
- The framework adapts to the task, not the other way around
- Phases feel like natural conversation, not bureaucratic checkpoints

---

## Live Demo Ideas

1. **"Learn this codebase"** → watch it systematically map a new project
2. **"Document the API"** → generates accurate docs from code in minutes
3. **"Think about microservices vs monolith"** → 4-perspective debate
4. **"Brainstorm ways to improve performance"** → scored, ranked ideas
5. **"Draw the architecture"** → Mermaid diagram from code analysis
6. **"Fix this bug" (with workflow)** → watch the full pipeline in action

---

## Getting Started

```bash
git clone <repo>
cd assistant-framework
./install.sh --agent claude
```

That's it. Skills route natively. Contracts guide execution and review.

---

## Assistant Framework v0.2.0

**Your AI. Your workflow. Your evidence.**

**It plans, verifies, reviews, and documents.**
