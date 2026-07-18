  @spec key_map([atom(), ...], key()) :: map()
  defp key_map(key_fields, key) do
    key_fields
    |> Enum.zip(Tuple.to_list(key))
    |> Map.new()
  end