# Assistant Framework v0.2.0

## Your AI Becomes a Senior Developer That Never Forgets

---

## The Problem

Every AI coding session starts from zero.

- No memory of past decisions
- No knowledge of what worked before
- Repeats the same mistakes
- Doesn't know your preferences
- Can't cover your weaknesses
- No structured workflow — just vibes

**You are the memory. You are the process. You are the quality gate.**

---

## What If Your AI Could...

- Remember every decision and why it was made
- Learn from its own mistakes automatically
- Cover your weaknesses (docs, diagrams, onboarding)
- Follow a battle-tested development workflow
- Review its own code autonomously
- Get better at YOUR projects over time
- Work the same way across Claude, Codex, and Gemini

---

## Assistant Framework

**11 composable skills. 13 MCP tools. One self-improving system.**

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
    │README   │ │learning │ │refine  │ │Mermaid   │
    │changes  │ │auto-    │ │score   │ │sequence  │
    │migrate  │ │memory   │ │rank    │ │ER, flow  │
    │explain  │ │generate │ │decide  │ │class     │
    └─────────┘ └─────────┘ └────────┘ └──────────┘
                        │
              ┌─────────▼──────────┐
              │    REFLEXION       │
              │                    │
              │ Self-improving     │
              │ agent loop         │
              │                    │
              │ Every task makes   │
              │ the next one       │
              │ better             │
              └────────────────────┘
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
Round 1: Dispatch fresh Reviewer → finds 4 issues (80%+ confidence)
         Fix all must-fix and should-fix
         Run tests → pass

Round 2: Dispatch NEW Reviewer (fresh context)
         Previously-fixed list provided → no re-reports
         Finds 1 more issue (85%+ confidence)
         Fix → test → pass

Round 3: Dispatch NEW Reviewer
         Clean. No findings above nit level.

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
Phase 5: Generate Memory   → writes .claude/memory.md
Phase 6: Report            → concise summary

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

## The Breakthrough: Reflexion

**Every task makes the next task better.**

```
Session 1: Fix a bug in the API
  → Reflexion: "Wasted 5 min because I forgot to check DI registration"
  → Lesson stored: "In this project, always verify DI registration
     when NullReferenceException involves a service"

Session 5: Another API bug
  → Discover phase: "Found 2 relevant lessons from past tasks"
  → Applies lesson automatically → faster fix

Session 20: Strategy profile is rich
  → 12 accumulated lessons across discover/plan/build/review
  → "You tend to underestimate refactors by 1 size category"
  → Auto-adjusts estimate: suggests MEDIUM instead of SMALL
```

---

## Memory Architecture

**Not just files. A queryable knowledge system.**

```
┌─────────────────────────────────────────────────┐
│                  13 MCP Tools                    │
│                                                  │
│  memory_context    memory_search (FTS5)          │
│  memory_reflect    memory_decide                 │
│  memory_pattern    memory_consolidate            │
│  memory_stats      memory_add_entity             │
│  memory_add_relation  memory_add_insight          │
│  memory_remove_entity  memory_remove_relation     │
│  memory_graph                                    │
└──────────┬──────────────────────┬────────────────┘
           │                      │
    ┌──────▼──────┐     ┌────────▼────────┐
    │ Knowledge   │     │ SQLite + FTS5   │
    │ Graph       │     │                 │
    │ (JSONL)     │     │ Reflexions      │
    │             │     │ Decisions       │
    │ Entities    │     │ Strategy Lessons│
    │ Relations   │     │ Calibration     │
    │ Projects    │     │ FTS5 Index      │
    │ Technologies│     │                 │
    │ Patterns    │     │ Ranked search   │
    │ Insights    │     │ across ALL      │
    └─────────────┘     │ memory content  │
                        └─────────────────┘
```

**Strategy lessons accumulate per project type:**
- Confidence scoring (0.0 → 1.0)
- Reinforcement on re-observation
- Time decay for stale lessons
- Automatic consolidation

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

## Automated Hooks

**Six lifecycle hooks fire automatically. Zero manual steps.**

| Hook | When | What |
|---|---|---|
| **Session Start** | New session | Injects memory, task state, reflexion tools |
| **Skill Router** | Every prompt | Routes to correct skill automatically |
| **Pre-Compress** | Before compaction | Saves state before context is lost |
| **Post-Compact** | After compaction | Re-injects task journal and rules |
| **Stop Review** | Agent tries to stop | Blocks until review is complete |
| **Session End** | Session closes | Prompts for reflexion capture |

**The stop-review hook is structural enforcement** — the agent physically cannot finish a task without completing the review cycle.

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
- MCP server registers in each agent's config
- Memory is shared or independent — your choice

---

## By the Numbers

| Metric | Count |
|---|---|
| Skills | 11 |
| MCP tools | 13 |
| Lifecycle hooks | 6 |
| Specialized agents | 6 |
| Thinking tools | 6 |
| Diagram types | 7 |
| Doc generation modes | 6 |
| Tests passing | 65 + 26 hook tests |
| External dependencies | 1 (Microsoft.Data.Sqlite) |
| Lines of YAML config | 0 (auto-discovered) |
| Marketplace imports | 0 (100% built in-house) |

---

## What Makes This Different

| Others | Assistant Framework |
|---|---|
| Skills as suggestions | Skills as **mandatory enforcement** |
| Memory as chat history | Memory as **queryable knowledge graph + FTS5** |
| One-shot review | **Autonomous review loop** (max 5 rounds) |
| Generic patterns | **Your project's patterns**, learned over time |
| Reactive only | **Self-improving** — reflexion after every task |
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
7. **"What do you remember?"** → query the knowledge graph

---

## Getting Started

```bash
git clone <repo>
cd assistant-framework
./install.sh --agent claude
```

That's it. Skills auto-trigger. Hooks auto-fire. Memory accumulates.

The framework gets smarter every time you use it.

---

## Assistant Framework v0.2.0

**Your AI. Your workflow. Your memory.**

**It learns. It improves. It never forgets.**
