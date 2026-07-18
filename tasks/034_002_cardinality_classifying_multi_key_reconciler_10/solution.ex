  defp key_map(key_tuple, key_fields) do
    key_fields
    |> Enum.zip(Tuple.to_list(key_tuple))
    |> Map.new()
  end