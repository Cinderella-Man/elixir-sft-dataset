  def calculate_totals(%Cart{} = cart) do
    items =
      cart.items
      |> Map.values()
      |> Enum.map(&build_summary(&1, cart.discount_tiers))

    subtotal = Enum.reduce(items, 0.0, fn i, acc -> acc + i.line_total end)
    tax = subtotal * cart.tax_rate
    shipping = shipping_cost(items, subtotal, cart)

    %{
      items: items,
      subtotal: subtotal,
      tax: tax,
      shipping: shipping,
      grand_total: subtotal + tax + shipping
    }
  end