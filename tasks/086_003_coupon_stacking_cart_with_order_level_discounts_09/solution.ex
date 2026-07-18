  defp coupon_amount(%{type: :percentage, value: value}, running), do: running * value
  defp coupon_amount(%{type: :fixed, value: value}, running), do: min(value, running)