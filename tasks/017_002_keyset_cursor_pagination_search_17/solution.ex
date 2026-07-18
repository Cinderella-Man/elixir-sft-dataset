  defp sort_value(p, "name"), do: p.name
  defp sort_value(p, "price"), do: p.price_cents
  defp sort_value(p, "id"), do: p.id