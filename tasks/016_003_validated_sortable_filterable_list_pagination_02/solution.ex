  defp sort_items(items, field, order) do
    sorted = Enum.sort_by(items, &{Map.get(&1, field), &1.id})
    if order == :desc, do: Enum.reverse(sorted), else: sorted
  end