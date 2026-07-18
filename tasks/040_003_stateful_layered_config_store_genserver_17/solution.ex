  defp fetch_path(map, []), do: map

  defp fetch_path(map, [k | rest]) when is_map(map) do
    case Map.fetch(map, k) do
      {:ok, v} -> fetch_path(v, rest)
      :error -> nil
    end
  end

  defp fetch_path(_map, _path), do: nil