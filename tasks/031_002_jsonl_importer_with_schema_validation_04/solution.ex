  # Build a map containing only the fields specified in the schema.
  # String values are trimmed.
  defp build_valid_record(record, schema) do
    schema
    |> Enum.filter(fn field -> Map.has_key?(record, field.name) end)
    |> Enum.map(fn field ->
      value = Map.get(record, field.name)
      trimmed = if is_binary(value), do: String.trim(value), else: value
      {field.name, trimmed}
    end)
    |> Map.new()
  end