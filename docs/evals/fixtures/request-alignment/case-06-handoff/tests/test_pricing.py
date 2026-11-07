import unittest
from decimal import Decimal

from shop.models import Coupon, Line, Order
from shop.orders.pricing import apply_discount


class ApplyDiscountTests(unittest.TestCase):
    def test_applies_coupon_percent(self):
        order = Order("A1", [Line("sku-1", 2, Decimal("10.00"))], Coupon("SAVE10", 10))
        self.assertEqual(apply_discount(order), Decimal("18.00"))


if __name__ == "__main__":
    unittest.main()
