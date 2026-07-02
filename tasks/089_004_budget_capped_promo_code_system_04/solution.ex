defp raw_discount(%{type: :percentage, value: v}, order_total),
  do: round(order_total * v / 100)

defp raw_discount(%{type: :fixed_amount, value: v}, order_total), do: min(v, order_total)
defp raw_discount(%{type: :free_shipping, value: v}, _order_total), do: v