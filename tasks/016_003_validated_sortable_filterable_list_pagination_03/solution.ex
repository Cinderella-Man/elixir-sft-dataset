  defp apply_filters(items, filters) do
    items
    |> maybe_filter(filters.min_age, fn i, v -> i.age >= v end)
    |> maybe_filter(filters.max_age, fn i, v -> i.age <= v end)
    |> maybe_filter(filters.name_contains, fn i, v ->
      String.contains?(String.downcase(i.name), String.downcase(v))
    end)
  end