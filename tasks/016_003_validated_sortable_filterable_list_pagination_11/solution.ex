  defp maybe_filter(items, nil, _fun), do: items
  defp maybe_filter(items, value, fun), do: Enum.filter(items, &fun.(&1, value))