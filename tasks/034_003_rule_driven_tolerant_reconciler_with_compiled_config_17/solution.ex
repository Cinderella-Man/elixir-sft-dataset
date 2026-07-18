  defp records_for(index, keys) do
    Enum.map(keys, &Map.fetch!(index, &1))
  end