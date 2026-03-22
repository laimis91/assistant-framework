# Assistant Framework

A Personal AI Assistant framework for developers. Eleven composable skills: structured workflow, TDD enforcement, thinking tools, research, security analysis, cross-session memory, documentation generation, codebase onboarding, idea generation, visual diagrams, and self-improving reflexion.

## What it does

1. **Structured Workflow** — TRIAGE > DISCOVER > PLAN > BUILD & TEST > DOCUMENT with approval gates and two-stage review
2. **TDD Enforcement** — Red-Green-Refactor cycle with strict verification gates at each transition
3. **Thinking Tools** — On-demand structured reasoning (first principles, multi-perspective debate, stress testing, etc.)
4. **Research Tools** — Tiered information gathering with URL verification and confidence scoring
5. **Security Analysis** — STRIDE threat modeling, OWASP code review, CVE dependency audit, attack surface mapping
6. **Memory System** — Cross-session learning: user preferences, feedback rules, task insights
7. **Documentation** — Auto-generates API docs, architecture docs, README, changelogs, migration guides, code explanations
8. **Onboarding** — Systematic codebase learning: maps structure, identifies patterns, generates project memory
9. **Idea Generation** — Diverge-converge-refine brainstorming pipeline with codebase awareness
10. **Visual Diagrams** — Mermaid diagrams from code: architecture, sequence, ER, flow, component, class, state
11. **Reflexion** — Self-improving agent: post-task reflection, lesson recall, strategy profiles, confidence calibration

## Installation

Install all skills for any supported agent:

```bash
./install.sh --agent claude   # → ~/.claude/skills/assistant-*/
./install.sh --agent codex    # → ~/.codex/skills/assistant-*/
./install.sh --agent gemini   # → ~/.gemini/skills/assistant-*/
```

Install a single skill:
```bash
./install.sh --agent claude --skill assistant-thinking
```

Preview without making changes:
```bash
./install.sh --agent claude --dry-run
```

Each skill auto-triggers independently based on what you're doing.

Skip hooks if you only want skills:
```bash
./install.sh --agent claude --no-hooks
```

Test hooks before installing:
```bash
./install.sh --agent claude --test-hooks
```

## Skills

### assistant-workflow
Core development pipeline: idea-to-action decomposition, triage, discover, plan, build & test, verify, document.

Triggers on: build, implement, fix, refactor, plan, create, idea

### assistant-tdd
Test-Driven Development enforcement: Red-Green-Refactor cycle with verification gates. Bug fix pattern (reproduce → fix → protect). Integrates with workflow's build loop and review cycle.

Triggers on: TDD, tests first, test-driven, write the test first, red green refactor

### assistant-thinking
Six structured reasoning tools: clarify, perspectives, stress-test, deep-think, hypothesize, creative.

Triggers on: think about, clarify, perspectives, stress test, brainstorm, debate

### assistant-research
Tiered research (quick/standard/extensive/deep), deep investigation, URL verification.

Triggers on: research, investigate, look into, find out, what is

### assistant-security
STRIDE threat model, OWASP code review, CVE dependency audit, attack surface mapping.

Triggers on: security, threat model, audit, vulnerability, OWASP

### assistant-memory
Memory management: templates, categories, pruning rules. Data lives in `~/.{agent}/memory/` (survives skill reinstalls).

Triggers on: remember this, save insight, update memory, preferences

### assistant-docs
Documentation generation and maintenance. Six modes: API docs, architecture overview, README, changelog, migration guide, code explainer. Detects stale docs and offers updates.

Triggers on: document, write docs, update readme, changelog, API docs, architecture doc

### assistant-onboard
Systematic codebase learning for new projects. Six-phase protocol: surface scan, architecture map, pattern recognition, knowledge gaps, generate project memory, report.

Triggers on: learn this codebase, onboard, get familiar with, map this project

### assistant-ideate
Structured brainstorming pipeline: understand → diverge (8-15 ideas) → converge (scored ranking) → refine (top candidates) → decide. Codebase-aware ideation scans TODOs, complexity hotspots, and recent momentum.

Triggers on: brainstorm, feature idea, what if, how could we, possibilities

### assistant-diagrams
Visual documentation from code analysis. Seven diagram types: architecture, sequence, entity-relationship, flow, component, class, state. All output as Mermaid for markdown embedding.

Triggers on: diagram, draw, visualize, show me the flow, architecture diagram

### assistant-reflexion
Self-improving agent loop. Post-task reflection captures what worked and what didn't. Pre-task lesson recall loads relevant lessons from past work. Strategy profiles accumulate per project type. Confidence calibration tracks prediction accuracy.

Triggers on: reflect, what did we learn, lessons, how did that go, calibrate

## Tools

### Memory Graph (MCP Server)

A knowledge graph over the markdown memory system. Provides queryable context so the agent can ask targeted questions like "What do I know about the desktop app?" instead of reading all memory files.

**13 MCP tools:** `memory_context`, `memory_search` (FTS5-powered), `memory_add_entity`, `memory_add_relation`, `memory_add_insight`, `memory_remove_entity`, `memory_remove_relation`, `memory_graph`, `memory_reflect`, `memory_decide`, `memory_pattern`, `memory_consolidate`, `memory_stats`

Installed automatically to `~/.{agent}/tools/memory-graph/` by the installer. The installer auto-registers the MCP server in your agent settings when `jq` is available. If not auto-registered, add manually (replace `~` with your actual home directory — most MCP hosts do not expand tilde):

**Claude Code** (`~/.claude/settings.json`):
```json
{
  "mcpServers": {
    "memory-graph": {
      "command": "~/.claude/tools/memory-graph/run-memory-graph.sh",
      "args": ["--memory-dir", "~/.claude/memory"]
    }
  }
}
```

**Codex** (`~/.codex/config.toml` or equivalent):
```toml
[mcp.memory-graph]
command = "~/.codex/tools/memory-graph/run-memory-graph.sh"
args = ["--memory-dir", "~/.codex/memory"]
```

**Gemini** (`~/.gemini/settings.json`):
```json
{
  "mcpServers": {
    "memory-graph": {
      "command": "~/.gemini/tools/memory-graph/run-memory-graph.sh",
      "args": ["--memory-dir", "~/.gemini/memory"]
    }
  }
}
```

Requires .NET 8+ SDK for the initial build (builds automatically on first run). See `tools/memory-graph/DESIGN.md` for architecture details.

### Cognitive Complexity

Roslyn-based analyzer that scores method complexity. Used by the workflow skill's quality review stage. See `tools/cognitive-complexity/`.

## Structure

```
install.sh                         <- Top-level installer (skills + hooks + memory)
version.txt                        <- Framework version

skills/
  assistant-workflow/
    SKILL.md                       <- Core pipeline (always loaded when triggered)
    references/                    <- Plan templates, checklists, prompt packs
    playbooks/                     <- Project-type architecture guides
    scripts/                       <- Mega task automation
    agents/                        <- Agent presets (claude/codex/gemini.conf)

  assistant-tdd/
    SKILL.md                       <- TDD enforcement (Red-Green-Refactor cycle)

  assistant-thinking/
    SKILL.md                       <- Tool descriptions and usage guidance
    clarify.md                     <- First principles: hard vs soft constraints
    perspectives.md                <- Multi-perspective debate (4 roles, 3 rounds)
    stress-test.md                 <- Steelman + counter-argument
    deep-think.md                  <- 8 analytical lenses
    hypothesize.md                 <- Goal-first + hypothesis plurality
    creative.md                    <- Low-probability sampling

  assistant-research/
    SKILL.md                       <- Tool descriptions and usage guidance
    research.md                    <- Tiered: quick / standard / extensive / deep
    investigate.md                 <- Deep investigation with ethical framework
    url-verify.md                  <- URL verification protocol

  assistant-security/
    SKILL.md                       <- Tool descriptions and severity scale
    threat-model.md                <- STRIDE analysis
    code-review.md                 <- OWASP Top 10 review
    dependency-audit.md            <- CVE dependency checking
    attack-surface.md              <- Attack surface mapping
    prompts/threat-model.md        <- Deep analysis prompt pack

  assistant-memory/
    SKILL.md                       <- Memory categories, rules, hygiene
    templates/                     <- Entry format templates
      insight-template.md
      feedback-template.md
      user-pref-template.md

  assistant-docs/
    SKILL.md                       <- Mode selection and general protocol
    api-docs.md                    <- API surface documentation
    architecture.md                <- System overview generation
    readme-gen.md                  <- README generation from code analysis
    changelog.md                   <- Release notes from git history
    migration.md                   <- Breaking change migration guides
    explainer.md                   <- Code explanation for learning

  assistant-onboard/
    SKILL.md                       <- Six-phase onboarding protocol

  assistant-ideate/
    SKILL.md                       <- Diverge-converge-refine pipeline

  assistant-diagrams/
    SKILL.md                       <- Diagram type selection and protocol
    arch-diagram.md                <- Architecture (component) diagrams
    sequence-diagram.md            <- Interaction sequence diagrams
    er-diagram.md                  <- Entity-relationship diagrams
    flow-diagram.md                <- Flowcharts and decision trees
    component-diagram.md           <- Module dependency diagrams
    class-diagram.md               <- Type hierarchy diagrams
    state-diagram.md               <- State machine diagrams

  assistant-reflexion/
    SKILL.md                       <- Self-improvement loop protocol

hooks/                             <- Automated behaviors (Claude + Gemini)
  scripts/
    session-start.sh               <- Inject task journal + memory on start/resume
    pre-compress.sh                <- Save state before context compression
    post-compact.sh                <- Restore context after compaction
    stop-review.sh                 <- Enforce self-review before task handoff
    session-end.sh                 <- Reminder to capture insights
    skill-router.sh                <- Data-driven skill routing (UserPromptSubmit)
  claude-settings.json             <- Hook config for Claude Code
  gemini-settings.json             <- Hook config for Gemini CLI

tools/
  cognitive-complexity/             <- Roslyn-based complexity analyzer
  memory-graph/
    DESIGN.md                      <- Architecture and data model
    run-memory-graph.sh            <- Build-and-run script
    src/MemoryGraph/               <- C# MCP server (stdio, JSON-RPC)
      Graph/                       <- In-memory knowledge graph + JSONL persistence
      Storage/                     <- SQLite + FTS5 store (reflexions, decisions, strategies)
      Tools/                       <- 13 MCP tool implementations
      Server/                      <- JSON-RPC message loop
      Sync/                        <- Markdown file scanner
    tests/MemoryGraph.Tests/       <- 65 xUnit tests

tests/
  test-hooks.sh                    <- Hook integration tests

memory-seed/                       <- Initial memory data (installed on first run)
  INDEX.md
  user/profile.md
  feedback/workflow-invisible.md   <- Workflow should feel invisible
  feedback/always-check-skills-first.md  <- Always invoke matching skills first
  insights/2026-03-17-*.md         <- Sample insight
```

## How it works

### For ideas (vague)
```
You: "I want to add caching to our API"
Workflow skill: Decomposes into 6-8 testable criteria, asks for confirmation, then triages
```

### For tasks (concrete)
```
You: "Fix the null reference in UserService.GetById"
Workflow skill: Triages as Small, quick discovery, lightweight plan, fix + test + self-review
```

### For TDD
```
You: "Use TDD to add a password strength validator"
TDD skill: Activates Red-Green-Refactor. Writes failing test first, implements minimum to pass, refactors, logs each cycle in task journal.
```

### For thinking
```
You: "Think about whether we should use microservices or modular monolith"
Thinking skill: Loads perspectives.md, runs 4-perspective debate
```

### For research
```
You: "Research the best .NET caching libraries"
Research skill: Runs standard-tier research with URL verification
```

### For security
```
You: "Audit the auth flow for vulnerabilities"
Security skill: Loads code-review.md, runs OWASP Top 10 analysis
```

### For documentation
```
You: "Document the API"
Docs skill: Scans endpoints, extracts parameters/types, generates API reference with examples
```

### For new projects
```
You: "Learn this codebase"
Onboard skill: Maps structure, identifies patterns, generates project memory (.claude/memory.md or .codex/memory.md), reports summary
```

### For brainstorming
```
You: "What are some ideas for improving the search experience?"
Ideate skill: Understands context, generates 10+ ideas, scores them, refines top 3
```

### For diagrams
```
You: "Draw the architecture diagram"
Diagrams skill: Traces code, maps components and dependencies, outputs Mermaid diagram
```

### For self-improvement
```
[After completing a task]
Reflexion skill: Captures what worked, what didn't, extracts lessons for future tasks
[Before starting next task]
Reflexion: Recalls relevant lessons, adjusts plan based on past experience
```

## Hooks (automated behaviors)

Hooks fire automatically on agent lifecycle events. Installed for Claude Code and Gemini CLI (Codex not yet supported).

| Hook | Event | What it does |
|---|---|---|
| **Session start** | Session begins/resumes | Injects task journal + memory feedback into context |
| **Pre-compress** | Before context compaction | Reminds agent to update task journal before state is lost |
| **Post-compact** | After compaction completes (Claude only) | Re-injects task journal and feedback rules |
| **Stop review** | Agent finishes responding (during active build) | Enforces self-review before task handoff |
| **Skill router** | User submits prompt | Pattern-matches prompt against skill triggers; injects reminder to invoke the correct skill |
| **Session end** | Session terminates | Logs reminder about uncaptured insights |

These replace manual steps — you no longer need to ask "did you read the task journal?" or "do a fresh review".

### Skill routing

The skill router hook prevents the agent from freelancing tasks that skills already handle. It fires on every user prompt, scans all installed skills for `triggers:` frontmatter, and injects a context reminder when a match is found.

**Adding triggers to a skill** — add a `triggers:` block to the SKILL.md frontmatter:

```yaml
---
name: my-skill
description: "..."
triggers:
  - pattern: "keyword1|keyword2|multi word phrase"
    priority: 80
    reminder: "You MUST invoke the Skill tool with skill='my-skill' BEFORE proceeding."
  - pattern: "another pattern"
    priority: 60
    min_words: 5
    reminder: "Consider invoking my-skill for this request."
---
```

| Field | Required | Description |
|---|---|---|
| `pattern` | Yes | Regex pattern matched against the user's prompt (case-insensitive, word-boundary) |
| `priority` | No | Higher = checked first. Default: 50. Use 80-90 for specific triggers, 30-50 for broad ones |
| `reminder` | No | Custom text injected into agent context. Default: generic "invoke skill X" message |
| `min_words` | No | Minimum word count in prompt to trigger. Prevents false positives on short messages |

**Priority ordering** ensures specific skills match before broad ones (e.g., "use TDD to implement X" matches assistant-tdd at priority 85, not assistant-workflow at priority 30).

No script changes needed when adding new skills — just add the frontmatter and reinstall.

## Design principles

- **Never guess** — Ask when ambiguous, state assumptions when clear
- **Right-sized ceremony** — Small tasks get lightweight treatment, large tasks get full workflow
- **Composable skills** — Each skill works standalone; use one or all eleven
- **Progressive loading** — Each SKILL.md is small. Tool files load on demand.
- **Thinking tools are tools, not phases** — Use them when needed, not on every task
- **Memory survives reinstalls** — Data in `~/.{agent}/memory/`, not in skill directories
- **Learning compounds** — Insights from past work inform future decisions
- **Self-improving** — Every task makes the next task better through reflexion
- **Covers weaknesses** — Documentation, diagrams, and onboarding compensate for developer blind spots
