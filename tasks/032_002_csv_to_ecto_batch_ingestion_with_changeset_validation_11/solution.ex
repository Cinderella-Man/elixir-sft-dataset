  @spec schema_field_set(module()) :: MapSet.t(String.t())
  defp schema_field_set(schema) do
    schema.__schema__(:fields)
    |> Enum.map(&Atom.to_string/1)
    |> MapSet.new()
  end