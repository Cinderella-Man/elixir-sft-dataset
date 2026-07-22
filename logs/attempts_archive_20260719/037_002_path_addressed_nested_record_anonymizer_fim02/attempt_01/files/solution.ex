  defp update_path(value, [], rule), do: apply_rule(value, rule)

  defp update_path(map, [{:key, key} | rest], rule) when is_map(map) do
    case fetch_key(map, key) do
      {:ok, actual_key, value} ->
        Map.put(map, actual_key, update_path(value, rest, rule))

      :error ->
        map
    end
  end

  defp update_path(list, [:each | rest], rule) when is_list(list) do
    Enum.map(list, fn element -> update_path(element, rest, rule) end)
  end

  defp update_path(other, _segments, _rule), do: other