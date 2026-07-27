export function calculateTotal(order) {
  order.reviewed = true;
  return order.items.reduce((total, item) => total + item.price * item.quantity, 0);
}
