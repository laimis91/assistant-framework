---
name: framework-design-principles
description: Core design principles learned while building the Assistant Framework
type: insight
---

## Key Principles

1. **Skills should be invisible** — A good workflow doesn't feel like a workflow. If the user notices the ceremony, it's too heavy.
2. **Auto-discovery over registration** — Skills, hooks, and agents should be found by convention (SKILL.md presence) not by maintaining lists.
3. **Orchestrators above sub-skills** — When a glue skill exists (like unity-iterate), it should have higher trigger priority than the skills it orchestrates.
4. **Read-only agents stay read-only** — Don't give Bash to agents documented as read-only. The safety model depends on tool restrictions, not just instruction text.
