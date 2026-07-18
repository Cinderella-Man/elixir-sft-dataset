  defp normalize(coupon) do
    %{
      code: coupon.code,
      type: coupon.type,
      value: coupon.value,
      min_subtotal: Map.get(coupon, :min_subtotal, 0.0)
    }
  end