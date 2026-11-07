from decimal import Decimal, ROUND_HALF_UP


def apply_discount(order):
    """Return the order total after its coupon discount."""
    subtotal = order.subtotal()
    discount = subtotal * Decimal(order.coupon.percent) / Decimal(100)
    return (subtotal - discount).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
