  defp shipping_cost([], _subtotal, _cart), do: 0.0

  defp shipping_cost(_items, subtotal, %Cart{
         free_shipping_threshold: threshold,
         shipping_flat: flat
       }) do
    if is_number(threshold) and subtotal >= threshold, do: 0.0, else: flat
  end