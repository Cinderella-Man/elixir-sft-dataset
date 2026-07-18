  defp discount(%{type: :percentage, value: value}, order_total) do
    round(order_total * value / 100)
  end

  defp discount(%{type: :fixed_amount, value: value}, order_total) do
    min(value, order_total)
  end

  defp discount(%{type: :free_shipping, value: value}, _order_total) do
    value
  end