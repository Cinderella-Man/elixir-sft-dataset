  defp render(p) do
    %{id: p.id, name: p.name, category: p.category, price: format_price(p.price_cents)}
  end