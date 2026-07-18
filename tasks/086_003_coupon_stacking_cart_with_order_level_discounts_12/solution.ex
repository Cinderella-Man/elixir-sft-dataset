  defp ensure_minimum(%Cart{} = cart, coupon) do
    minimum = Map.get(coupon, :min_subtotal, 0.0)
    if item_subtotal(cart) >= minimum, do: :ok, else: {:error, :below_minimum}
  end