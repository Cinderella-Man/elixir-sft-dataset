  defp fetch_integer(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_integer(value) -> {:ok, value}
      _ -> :error
    end
  end