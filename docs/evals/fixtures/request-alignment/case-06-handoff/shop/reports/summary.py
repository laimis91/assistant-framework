def coupon_usage(orders):
    """Count how many orders used each coupon code."""
    counts = {}
    for order in orders:
        if order.coupon:
            counts[order.coupon.code] = counts.get(order.coupon.code, 0) + 1
    return counts
