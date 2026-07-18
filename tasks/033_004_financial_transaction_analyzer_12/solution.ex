  defp fetch_positive_number(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_number(value) and value > 0 -> {:ok, value}
      _ -> :error
    end
  end