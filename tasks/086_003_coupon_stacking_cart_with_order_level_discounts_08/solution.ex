  defp item_subtotal(%Cart{items: items}) do
    items
    |> Map.values()
    |> Enum.reduce(0.0, fn item, acc -> acc + build_summary(item).line_total end)
  end