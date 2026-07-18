  defp build_summary(%Item{} = item, tiers) do
    rate = discount_for(item.quantity, tiers)

    %{
      product_id: item.product_id,
      quantity: item.quantity,
      unit_price: item.unit_price,
      discount_rate: rate,
      line_total: item.unit_price * (1.0 - rate) * item.quantity
    }
  end