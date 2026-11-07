# Team notes (not scheduled)

- Finance asked whether totals should use banker's rounding (ROUND_HALF_EVEN)
  instead of ROUND_HALF_UP. No decision yet; changing it would alter historical
  invoice totals when re-rendered.
- `Line.unit_price` is a `Decimal`, but the storefront still sends floats in a
  few places. Consider a `Money` type.
- `render_invoice` builds plain text; the PDF renderer is planned for Q2.
