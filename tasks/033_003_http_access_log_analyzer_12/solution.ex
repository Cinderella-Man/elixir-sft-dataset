  defp fetch_number(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_number(value) -> {:ok, value}
      _ -> :error
    end
  end