  defp parse_filters(params) do
    with {:ok, min_age} <- parse_int_filter(params, "min_age"),
         {:ok, max_age} <- parse_int_filter(params, "max_age") do
      name_contains =
        case Map.get(params, "name_contains") do
          v when is_binary(v) -> v
          _ -> nil
        end

      {:ok, %{min_age: min_age, max_age: max_age, name_contains: name_contains}}
    end
  end