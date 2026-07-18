  # Build a map containing only the fields specified in the schema.
  defp build_valid_record(record, schema) do
    schema
    |> Enum.map(fn field ->
      {field.name, Map.get(record, field.name, "")}
    end)
    |> Map.new()
  end