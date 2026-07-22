  def calculate_totals(%Cart{} = cart) do
    items = cart.items |> Map.values() |> Enum.map(&build_summary/1)
    subtotal = Enum.reduce(items, 0.0, fn i, acc -> acc + i.line_total end)

    {discounted, discount} =
      Enum.reduce(cart.coupons, {subtotal, 0.0}, fn coupon, {running, disc} ->
        amount = coupon_amount(coupon, running)
        {running - amount, disc + amount}
      end)

    tax = discounted * cart.tax_rate

    %{
      items: items,
      subtotal: subtotal,
      discount: discount,
      discounted_subtotal: discounted,
      tax: tax,
      grand_total: discounted + tax,
      coupons: Enum.map(cart.coupons, & &1.code)
    }
  end