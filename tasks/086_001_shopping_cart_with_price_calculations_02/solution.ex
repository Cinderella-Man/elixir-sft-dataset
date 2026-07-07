  defp build_item_summary(%Item{
         product_id: product_id,
         quantity: quantity,
         unit_price: unit_price
       }) do
    discount_rate = if quantity >= @bulk_discount_threshold, do: @bulk_discount_rate, else: 0.0
    line_total = unit_price * (1.0 - discount_rate) * quantity

    %{
      product_id: product_id,
      quantity: quantity,
      unit_price: unit_price,
      discount_rate: discount_rate,
      line_total: line_total
    }
  end