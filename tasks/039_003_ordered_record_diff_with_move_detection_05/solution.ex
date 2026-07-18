  defp index_by(records, key) do
    Map.new(records, fn record -> {Map.fetch!(record, key), record} end)
  end