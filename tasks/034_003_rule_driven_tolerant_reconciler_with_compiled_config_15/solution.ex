  defp index_by_key(records, key_fields) do
    Enum.reduce(records, %{}, fn record, acc ->
      Map.put(acc, key_of(record, key_fields), record)
    end)
  end