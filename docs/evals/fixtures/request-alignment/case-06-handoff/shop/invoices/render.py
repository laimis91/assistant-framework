from shop.orders.pricing import apply_discount


def render_invoice(order):
    """Return the invoice text for an order."""
    lines = [f"Invoice {order.order_id}"]
    for line in order.lines:
        lines.append(f"{line.sku} x{line.quantity} @ {line.unit_price}")
    lines.append(f"Coupon: {order.coupon.code} (-{order.coupon.percent}%)")
    lines.append(f"Total: {apply_discount(order)}")
    return "\n".join(lines)
