  @spec record_key(stream_record(), [atom(), ...]) :: key()
  defp record_key(record, key_fields) do
    key_fields
    |> Enum.map(&Map.get(record, &1))
    |> List.to_tuple()
  end