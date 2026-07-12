  @spec composite_key(record_t(), [atom()]) :: tuple()
  defp composite_key(record, key_fields) do
    key_fields
    |> Enum.map(&Map.get(record, &1))
    |> List.to_tuple()
  end