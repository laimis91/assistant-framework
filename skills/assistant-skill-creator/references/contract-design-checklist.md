# Skill Design Checklist

Use the [design guide](skill-contract-design-guide.md) for the changed boundary.
This is a set of prompts, not a requirement to add files or fields.

- Does the skill solve the requested job with concise, actionable instructions?
- Are its name, description, metadata, dependencies, and invocation policy valid
  and preserved unless explicitly changed?
- Are material questions resolved from context or safe defaults before asking?
- Does each added contract or controller have a named consumer and a concrete
  failure it prevents? Can existing instructions or a producer format suffice?
- Do supplied contracts have valid headers, types, explicit enums, conditional
  requiredness, and actionable recovery? Do handoff fields match their consumer?
- Do referenced files and any declared index resolve without escaping the root?
- Do public/domain interfaces preserve semantic meaning, with explicit primitive
  boundary exceptions, conversions, validation, and compatibility when needed?
- Are approvals, permissions, read-only operations, bounded recovery, and actual
  workflow safety requirements intact?
- Is persisted/shared state bound to current source identity, with pre-build and
  completion evidence where required? Are missing loaded runtimes still blockers?
- Are actual checks, evidence gaps, and exclusions reported without treating
  structural validity or phrase matches as proof of activation or improvement?

For existing consumed schemas, preserve the producer format and update affected
consumers together. Breaking required-field changes need versioning and a
migration note. Human-only summaries need no canonical verification envelope;
carry canonical verification results unchanged when a consumer requires them.
