def calculate_total(items):
    """Sum item prices including tax."""
    subtotal = sum(item["price"] for item in items)
    tax = subtotal * 0.08
    return subtotal + tax


def apply_discount(total, code):
    """Apply discount code to total."""
    discounts = {"SAVE10": 0.10, "SAVE20": 0.20, "SAVE50": 0.50}
    rate = discounts.get(code, 0.0)
    return total * (1 - rate)


def format_invoice(items, code=None):
    """Render invoice as plain text."""
    total = calculate_total(items)
    if code:
        total = apply_discount(total, code)
    lines = [f"{i['name']}: ${i['price']}" for i in items]
    lines.append(f"TOTAL: ${total:.2f}")
    return "\n".join(lines)


def send_invoice(invoice, email):
    """Send invoice via email."""
    print(f"Sending to {email}:\n{invoice}")
    return True
