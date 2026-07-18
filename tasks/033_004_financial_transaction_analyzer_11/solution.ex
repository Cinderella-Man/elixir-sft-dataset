  defp fetch_type(map) do
    case Map.fetch(map, "type") do
      {:ok, "credit"} -> {:ok, "credit"}
      {:ok, "debit"} -> {:ok, "debit"}
      _ -> :error
    end
  end