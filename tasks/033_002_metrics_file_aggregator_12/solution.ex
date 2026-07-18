  defp fetch_tags(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_map(value) -> {:ok, value}
      _ -> :error
    end
  end