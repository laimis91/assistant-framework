# Test craft: worked examples

Load this only when TDD is already active and a test is being authored or
corrected. It shows what a test worth entering the cycle looks like. It adds no
phase, gate, report field, test quota or activation rule; `SKILL.md` and the
contracts stay authoritative.

All examples use one requirement: **a 100-cent promotion is applied once to an
order; a 1000-cent order totals 900.** Amounts are in cents. The public entry
point is `checkout(order)`, which already exists; it calls `compute_total(order)`,
which calls the pricing rules in `rules.apply(order)`. The defect the good tests
of the total catch, and the weak ones miss, is **double application**: the pricing rules
subtract the promotion twice, so the total is 800.

## Good and bad test for one requirement

Good: real order, real promotion, the public entry point, and an expected value
taken from the requirement.

```python
def test_promotion_is_applied_once():
    order = Order(items=[1000], promotions=[Promotion(code="SAVE100", amount=100)])

    assert checkout(order).total == 900
```

With the double-application defect this test fails with 800, so it protects the
requirement.

Bad: the pricing rules are replaced by a mock that returns the answer.

```python
def test_promotion_is_applied_once(mocker):
    mocker.patch("shop.rules.apply", return_value=900)
    order = Order(items=[1000], promotions=[Promotion(code="SAVE100", amount=100)])

    assert checkout(order).total == 900
```

Misses: double application in the real pricing rules. The mock supplies 900
whatever the rules do, so the test passes with the defect present.

## Intended and wrong-reason RED for the same test

Run the good test before the fix.

Intended RED, the exact symptom of the missing behaviour:

```text
FAILED tests/test_checkout.py::test_promotion_is_applied_once
E   assert 800 == 900
```

Expected 900, got 800: the promotion was subtracted twice. Record this as the
meaningful failure. It authorises the production edit.

Wrong-reason RED from the same test:

```text
E   ModuleNotFoundError: No module named 'shop.promotions'
```

or a missing fixture file such as `FileNotFoundError: fixtures/order_1000.json`.
These are import and setup failures. They say nothing about the total, so they
do not authorise production edits; repair the test or environment and rerun
until the failure is "expected 900, got 800". Record the exact symptom, not a
generic failure such as "test failed" or "exit code 1".

If the good test passes on its first run, the behaviour may already exist or the
oracle may be wrong. Inspect both, as the RED step says, before changing code.

## One vertical slice at a time

Take one behaviour through RED and GREEN, all the way through `checkout`, before
writing the next test.

1. Slice 1, promotion applied once: write `test_promotion_is_applied_once`,
   observe "expected 900, got 800", make the smallest change that passes.
2. Slice 2, second identical promotion rejected: only now write the next test,
   observe its RED, then make it pass.

```python
def test_second_identical_promotion_is_rejected():
    save100 = Promotion(code="SAVE100", amount=100)
    order = Order(items=[1000], promotions=[save100, save100])

    with pytest.raises(ValueError, match="duplicate promotion SAVE100"):
        checkout(order)
```

Its intended RED is `Failed: DID NOT RAISE <class 'ValueError'>`: the duplicate
was accepted.

Contrast: writing parser, rule-engine and receipt-formatter tests first, then
implementing all layers. Those tests fix internal boundaries that may never be
needed, often fail for import reasons rather than missing behaviour, and none
shows the requirement working through `checkout` until every layer is done.

Under `separated_workers`, each slice runs as its own active packet whose single
intersecting CheckSpec ID binds its RED: the writer authors slice 2's test only
after slice 1's cycle, never in the same `test_authoring` stage.

## Tests that pass without protecting the requirement

Each of these can pass while the total is wrong.

### Asserting an internal call shape

```python
def test_checkout_applies_rules(mocker):
    mocker.spy(rules, "apply")
    order = Order(items=[1000], promotions=[Promotion(code="SAVE100", amount=100)])

    checkout(order)

    rules.apply.assert_called_once_with(order)
```

Misses: double application inside `rules.apply`. The rules are called once with
the right order and still subtract 100 twice. This RED cannot fail for the
intended reason, because it checks how the rules are called, not the total. It
also fails when a harmless refactor splits or merges the call.

### Deriving the expected value from the subject

```python
def test_total_matches_computed_total():
    order = Order(items=[1000], promotions=[Promotion(code="SAVE100", amount=100)])
    expected = compute_total(order)

    assert checkout(order).total == expected
```

Misses: double application in `compute_total`, which `checkout` also uses. Both
sides return 800 and the test passes. This RED cannot fail for the intended
reason, because the expected value carries the same defect as the result. Take
the expected value from the requirement: 900.

### Asserting what a stub supplies

This and the next section assume `checkout` already accepts an injected rate
service or payment gateway, that an order can carry `promotion_codes` and an
`id`, and that `receipt.discount` reports the discount the rate service quoted.

```python
def test_discount_comes_from_rate_service(mocker):
    rate_service = mocker.Mock()
    rate_service.discount_for.return_value = 100
    order = Order(items=[1000], promotion_codes=["SAVE100"])

    receipt = checkout(order, rate_service=rate_service)

    assert receipt.discount == 100
```

Misses: double application of the discount to the total. The assertion reads
back the stub's own value, so it tests the stub, not `checkout`. This RED cannot
fail for the intended reason; assert the subject's result instead, as below.

## When substitutes and exact checks are right

Substitutes stay valid at unstable or external boundaries, such as a remote
rate service, a clock or a payment provider, when the assertion is on the
subject's own result:

```python
def test_rate_service_discount_is_applied_once(mocker):
    rate_service = mocker.Mock()
    rate_service.discount_for.return_value = 100
    order = Order(items=[1000], promotion_codes=["SAVE100"])

    assert checkout(order, rate_service=rate_service).total == 900
```

The stub supplies an input; `checkout` computes the 900, so double application
still fails it with 800.

An exact check is valid when those bytes or interactions are themselves the
contract. If the payment provider's API defines the request, asserting the exact
request is correct:

```python
def test_checkout_charges_the_promoted_total():
    gateway = RecordingPaymentGateway()
    order = Order(id="o-17", items=[1000], promotions=[Promotion(code="SAVE100", amount=100)])

    checkout(order, payments=gateway)

    assert gateway.requests == [
        {"amount": 900, "currency": "EUR", "idempotency_key": "o-17"}
    ]
```

The exact request is the contract with the provider, so an extra field, a wrong
amount or a second charge is a real defect. The same holds for exact text or a
schema that another system parses. A call assertion is coupling only when the
call is an internal detail.

## Other languages

The shapes are the same in C# (xUnit or NUnit with a mocking library) and
TypeScript (Jest or Vitest): assert the public result against the requirement's
value, and keep substitutes at the boundary.
