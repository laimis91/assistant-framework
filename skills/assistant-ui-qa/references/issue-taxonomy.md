# Issue taxonomy

Load this when an issue is found. Give each issue one severity and one category.

## Severity

Decide severity from the user impact you observed, then from whether a
workaround exists. Do not raise severity for an issue you inferred but did not
observe; record the inference separately.

| Severity | Use when | Examples |
|---|---|---|
| Critical | A core flow cannot be completed at all, data is lost or corrupted, or secrets or personal data are exposed. | Blank page on the entry route; a saved form silently drops the input; a token printed in the console. |
| High | A key function fails or gives a wrong result, and a workaround is awkward or unknown. | A primary button does nothing until reload; valid input is rejected; a navigation link leads to a not-found page; an uncaught exception on a core page. |
| Medium | The flow can be completed but the experience is noticeably degraded. | No validation message on bad input; overlapping layout in one section; images fail to load; a visible delay with no loading indicator. |
| Low | Polish that does not affect what the user can do. | Typos; small spacing inconsistencies; leftover placeholder text; debug output in the console. |

When unsure between two levels, pick the lower one and say what would raise it.

## Category

Choose the category of the visible effect. When one defect has several effects,
choose the one that most affects the user and mention the others.

| Category | Covers |
|---|---|
| Functional | Controls that do not respond, wrong data, flows that cannot be completed, partial features. |
| Visual | Layout, overlap, broken media, styling inconsistencies, truncated or overflowing text, responsive breakage. |
| Accessibility | Elements unreachable by keyboard, missing labels or alternative text, missing focus indicators, insufficient contrast. |
| Console | Uncaught exceptions, unhandled rejections, failed requests, warnings, without another visible effect. |
| UX | It works, but feedback is missing, error messages do not help recovery, patterns are inconsistent, or destructive actions lack confirmation. |
| Content | Wrong, outdated, missing or placeholder text, broken links, misleading labels. |

## Duplicates

Merge manifestations into one issue when the same cause is evident, such as the
same console error or the same component on several pages. List every place it
appears. Keep issues separate when only the symptom is similar and the cause is
not evident.

## Blocked or not tested

A flow is **blocked** when you tried to reach it and something outside your
control stopped you: missing credentials, an unauthorized destructive step, a
production target or an environment error. A flow or state is **not tested**
when you did not try it: out of scope, no runtime, or not reached.
