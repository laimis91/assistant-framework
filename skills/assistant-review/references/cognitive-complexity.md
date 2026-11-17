# Cognitive Complexity Estimate

Use this method to point at functions that are hard to follow. It works on any
language by reading the code; no tool or runtime is needed. It follows the
published SonarSource cognitive-complexity rules (G. Ann Campbell, "Cognitive
Complexity", SonarSource white paper, 2017), so a hand count lands close to what
SonarQube reports for the same function.

The result is an estimate. It is advisory: it supports the "needless complexity"
and readability lenses in [review-principles.md](review-principles.md), and no
score, however high, blocks a review, a build or a merge by itself. A finding
still needs the concrete risk and the smallest durable fix that every review
finding needs.

## When to estimate

Estimate a changed function when it nests branches or loops, mixes boolean
operators, or reads as hard to follow. Skip straight-line code, simple guard
clauses and one-level dispatch. Estimate only changed or added functions unless
the request asks for more.

## Counting rules

Start at 0 and walk the function body top to bottom.

1. **+1 for each break in linear flow:**
   - `if`, `else if`, `else`; a ternary (`?:`) or conditional expression;
   - one `switch`, `match` or `when` statement as a whole (not per case);
   - each loop: `for`, `foreach`, `while`, `do … while`, and loop comprehensions
     with a condition;
   - each `catch` or `except` clause (`try` and `finally` add nothing);
   - `goto`, and `break` or `continue` to a label (plain `break`, `continue` and
     early `return` add nothing);
   - each sequence of like boolean operators: `a && b && c` is +1,
     `a && b || c` is +2, `a && b || c && d` is +3. Each change of operator
     starts a new sequence;
   - each call that completes a recursion cycle (direct or indirect).
2. **+nesting level for nested flow breaks.** `if`, ternary, `switch`, loops and
   `catch` get an extra increment equal to how deeply they are nested at that
   point. `else if` and `else` take the +1 from rule 1 but no nesting increment.
3. **What raises the nesting level.** The bodies of `if`, `else if`, `else`,
   ternaries, `switch`, loops and `catch`, and nested functions, lambdas and
   closures. A nested function or lambda raises the level for its body but adds
   no increment of its own.
4. **No increment for shorthand that aids reading:** null-coalescing and
   optional chaining (`??`, `?.`), a function call, an early return, `try`,
   `finally`, `using` or `with` blocks, and assigning a single boolean value
   with no operator.

## Worked examples

A flat dispatch scores low even when it is long:

```text
function label(kind):          # nesting 0
  switch kind:                 # +1
    case A: return "alpha"
    case B: return "beta"
    default: return "other"
                               # total 1
```

Nested loops with a labelled jump score higher:

```text
function firstPair(rows, target):
  OUTER: for row in rows:            # +1 (nesting 0)
    for cell in row:                 # +2 (+1, nesting 1)
      if cell == target:             # +3 (+1, nesting 2)
        found = cell
        break OUTER                  # +1 (jump to a label)
  return found
                                     # total 7
```

Mixed operators and an `else if` chain:

```text
function grade(score, late, excused):
  if score < 0 or score > 100:       # +1 if, +1 one sequence of `or`
    raise error
  if late and not excused:           # +1 if, +1 one sequence of `and`
    score = score - 10
  if score >= 90:                    # +1
    return "A"
  else if score >= 75:               # +1 (no nesting increment)
    return "B"
  else:                              # +1
    return "C"
                                     # total 7
```

A lambda raises nesting without its own increment:

```text
function activeNames(users):
  return users.filter(u =>           # lambda: nesting 1, +0
    u.active and u.age >= 18)        # +1 one sequence of `and`
                                     # total 1 (an `if` inside the
                                     # lambda would score +2)
```

## Reading the estimate

- Report the estimate with the counted lines, for example "about 18: three
  nested loops (+1, +2, +3), two mixed conditions (+4) …", so a reader can check
  it.
- Around 15 is SonarQube's default reporting point for most languages. Use it
  as a pointer for where to look, not as a pass or fail line.
- When the estimate is high, name the specific nesting or condition that makes
  the function hard to follow and the smallest fix: a guard clause that removes a
  nesting level, an extracted helper for a nested loop body, a named predicate
  for a mixed boolean condition, or a table or polymorphic dispatch for a long
  branch chain.
- A high estimate on code whose shape mirrors a real domain rule (a parser
  state machine, a protocol table) may be the clearest form. Say so rather than
  forcing a split.
- Classify a complexity finding as should-fix at most, unless the same code also
  has a correctness, security or testability defect that the complexity hides.
