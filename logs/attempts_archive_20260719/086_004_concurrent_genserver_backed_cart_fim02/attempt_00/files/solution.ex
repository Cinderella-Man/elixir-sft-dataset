  defp compute_totals(state) do
    items =
      state.items
      |> Map.values()
      |> Enum.map(&build_summary/1)

    subtotal = Enum.reduce(items, 0.0, fn i, acc -> acc + i.line_total end)
    tax = subtotal * state.tax_rate

    %{
      items: items,
      subtotal: subtotal,
      tax: tax,
      grand_total: subtotal + tax
    }
  end