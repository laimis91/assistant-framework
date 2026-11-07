# Request

`apply_discount` in `shop/orders/pricing.py` crashes with
`AttributeError: 'NoneType' object has no attribute 'percent'` when an order has
no coupon. Fix it so an order without a coupon is priced at its full subtotal,
add a test for that case, and tell me whether any other callers have the same
bug.
