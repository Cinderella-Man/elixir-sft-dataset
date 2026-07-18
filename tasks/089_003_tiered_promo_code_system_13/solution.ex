  defp tier_discount(%{type: :percentage, value: v}, order_total),
    do: round(order_total * v / 100)

  defp tier_discount(%{type: :fixed_amount, value: v}, order_total), do: min(v, order_total)