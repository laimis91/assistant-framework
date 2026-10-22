# Creator expert-method change outline

Preparation only; no skill source changed. Authority is
`user:2026-10-22:approve`, captured in `../plan.md`. The independent expected
context remains `/tmp/expert-pilot-impact-authority/expected-prebuild.json`;
this outline neither rewrites that authority nor claims a pre-build pass.
The source inventory was checked against actual bytes at
`c920fd89ee232032aafd2541dd51c9c5bd9744f3`: all five declared hashes match.

The shared guard remains `expert-method-pilot`, with the source-bound window
of three consecutive unproductive semantic cycles and history owned by root in
`../journal.md`. No new worker allowance or evaluation allowance is created.
TDD remains false, `not_selected`, applicable IDs empty, `test_change=none`.
The existing CheckSpecs, exclusions and stop rule in `../selection.json` remain
controlling. Root owns verification and independent review.

## Natural

Consumer: human authoring through `skills/assistant-skill-creator/SKILL.md`.

1. Add a conditional paragraph in “Load only the needed detail”, before the
   existing controller/distillation routes:

   > For new or materially changed capability guidance whose quality depends on
   > expert judgment, load `expert_method_design` and
   > `references/expert-method-design.md`. Use representative expert cases or an
   > authoritative method to connect observed cues, method choices, raw inputs,
   > expected artifacts, applicability limits, and an independent wrong-outcome
   > check to existing success criteria. Mechanical and preference-only changes
   > do not trigger this work. Model guesses without evidence remain candidates.

2. Add `references/expert-method-design.md`. Its complete intended content is
   bounded to these instructions:

   - Apply during existing DESIGN work for the material capability case above.
     Reuse adequate existing cases, methods and verification evidence before
     collecting more. Do not create another phase, report, schema or expert mode.
   - Start from existing `success_criteria` and a consequential decision where
     an inexperienced approach can produce a plausible wrong outcome. Inspect a
     representative expert case or authoritative method; preserve source identity
     and distinguish observed conduct, the source's recommendation, and inference.
     Do not substitute role labels, expert vocabulary or a longer procedure for
     evidence. An evidence-free model proposal is a candidate to check.
   - Trace the decision from raw inputs: which cue matters, what method the cue
     selects or rules out, what action follows, and which artifact or observation
     the method should produce. Retain decision-relevant uncertainty, alternative
     explanations, conditions under which the method is inappropriate, and
     permission/tool/access limits. Choose sufficient representative cases for
     the consequential decisions; impose no case, hypothesis or step quota.
   - Select an independent wrong-outcome check against the existing criteria:
     expected observations, adverse cases or external evidence capable of
     rejecting a plausible incorrect result. Avoid circular checks that merely
     repeat the authored prose. Reuse canonical verification selection and
     evidence outputs when those have a consumer. Match claims to evidence;
     source inspection and method plausibility do not establish behavioral gain.
   - Put only the reusable cue-to-method decisions and limits in the target
     instructions; keep supporting detail in references when useful. Preserve
     the target's metadata, dependencies, read-only operations, permissions and
     existing approval gates. Do not install tools, exaggerate targets or extend
     persistence. Ask only for unresolved consequential source or outcome gaps.
   - Include one compact illustrative diagnosis design: rising request latency
     alone cannot select database tuning; compare queue/lock wait with query
     duration and vary suspected contributors independently. The expected
     artifact is a timing comparison locating the delay; a real query-delay
     control can reject an incorrect upstream-wait conclusion. State that this
     is an illustrative method hypothesis, not an assertion that every latency
     problem has that cause or a measured creator benefit. No pilot case values,
     hidden answers or held-out details belong in the reference.
   - Cite the source rationale with calibrated claims:
     [Felix Rieseberg's article](https://felixrieseberg.com/how-to-be-more-ambitious-a-tutorial-for-humans-with-models/)
     motivates field methods, raw evidence and external checks;
     [FRA cognitive task analysis](https://railroads.dot.gov/human-factors/elearning-attention/cognitive-task-analysis)
     describes incident-based elicitation of expert cues and judgments. Root
     refreshed source identity on 2026-10-22. These sources motivate the authoring
     hypothesis; they do not establish best-expert equivalence or causal gains.

V5 inspects this content and resolves the changed reference paths. There is no
creator-task behavioral comparison or model-quality claim in this change.

## Structured

Consumer: existing creator DESIGN gate and progressive-loading index.

1. Add `expert_method_design` to
   `skills/assistant-skill-creator/contracts/index.yaml`, following the current
   reference-plus-selector convention:

   ```yaml
   expert_method_design:
     references:
       - references/expert-method-design.md
     selectors:
       - id: skill-creator-expert-method-criteria
         path: contracts/input.yaml
         section: fields
         key: name
         names: [skill_value_kind, success_criteria]
     budget_words: 2400
   ```

   This only loads existing input fields and the conditional detail. The root
   route determines applicability; it adds no input/output fields or metadata.

2. Append one DESIGN `exit_assertions` entry in
   `skills/assistant-skill-creator/contracts/phase-gates.yaml`:

   ```yaml
   - id: SD10
     check: "Expert-method design connects source-backed cues and method choices to raw inputs, expected artifacts, applicability limits, and an independent wrong-outcome check against existing success criteria; unsupported model proposals remain candidates"
     condition: "authoring adds or materially changes capability guidance whose quality depends on expert judgment"
     on_fail: "Load expert_method_design; reuse representative expert cases or an authoritative method, resolve consequential evidence gaps, and keep unsupported improvement claims out of the design"
   ```

   The conditional assertion is needed because structured consumers may load
   current DESIGN gates without the human-facing root. It leaves existing gate
   conditions, v3 output envelope and read-only operations intact. The existing
   `current_phase` budget is 5000 words; this localized assertion fits that path.

V4-creator reuses the existing semantic suite to protect retained consumers.
It cannot establish the quality of the new method; V5 inspects the new assertion,
conditional load path and scope instead. No phrase/inventory tests are added.

## Guide

Consumer: canonical guide readers and the generated skill-local guide.

Add this compact paragraph after the instructions-first opening guidance in
`docs/skill-contract-design-guide.md`:

> For new or materially changed capability guidance that depends on expert
> judgment, derive the consequential cue-to-method decisions from representative
> expert cases or an authoritative method. Connect raw inputs, expected artifacts,
> applicability limits, and an independent wrong-outcome check to existing
> success criteria. Keep unsupported model proposals provisional; more procedure
> or expert vocabulary does not establish improvement. Mechanical and
> preference-only changes do not require this process. The creator's
> `references/expert-method-design.md` contains the conditional detail; reuse
> existing design and verification outputs rather than adding an authoring report.

Mirror only by running `tools/skills/sync-skill-contract-guide.sh --apply` after
source authorization. Do not hand-edit the generated
`skills/assistant-skill-creator/references/skill-contract-design-guide.md`.
V3 checks byte parity; V4-guide retains existing sync controls. These checks do
not establish expert competence or behavioral improvement.

## Boundaries and handoff

Planned production diff: the creator root, creator index, one conditional DESIGN
assertion, one new expert-method reference, canonical guide, generated guide.
No debugging change, test changes, installer change, registry mutation, metadata
change, dependency change, new schema or tool dependency is planned.

Root's development disposition is no debugging change, identity
`f628d37b86e1831fee38e08a2f0827028a09edec32e7cf7cab60ccad815cccd2`.
Root reports both disabled and current localized the development contention
correctly; one extra current inspection command does not establish harmful
overhead. V2 is not applicable. Root manages the eight planned diagnostic
observations (four cases, disabled/current), retains the hard cap of twelve
charged starts, and does not repurpose unused slots. This worker has neither
read held-out material nor run evaluations.

Root next runs the installed checker in `pre_build` with
`capture.prebuild.json`, independent expected context and
`assessment.prebuild.json`. Production waits for that result and root's next
task. Completion needs recaptured actual source identity, current verification,
independent review bindings and root's corresponding authority.
