from dataclasses import dataclass, field
from decimal import Decimal
from typing import List, Optional


@dataclass
class Coupon:
    code: str
    percent: int


@dataclass
class Line:
    sku: str
    quantity: int
    unit_price: Decimal


@dataclass
class Order:
    order_id: str
    lines: List[Line] = field(default_factory=list)
    coupon: Optional[Coupon] = None

    def subtotal(self):
        return sum((line.unit_price * line.quantity for line in self.lines), Decimal("0"))
