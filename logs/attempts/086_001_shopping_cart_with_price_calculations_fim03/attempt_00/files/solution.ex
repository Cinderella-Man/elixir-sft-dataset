  def calculate_totals(%Cart{items: items, tax_rate: tax_rate}) do
    item_summaries =
      items
      |> Map.values()
      |> Enum.map(&build_item_summary/1)

    subtotal = Enum.reduce(item_summaries, 0.0, fn i, acc -> acc + i.line_total end)
    tax = subtotal * tax_rate
    grand_total = subtotal + tax

    %{
      items: item_summaries,
      subtotal: subtotal,
      tax: tax,
      grand_total: grand_total
    }
  end