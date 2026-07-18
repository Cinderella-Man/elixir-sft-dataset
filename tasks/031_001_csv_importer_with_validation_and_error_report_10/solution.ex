  # Validate a single row map against the full schema.
  # Returns a list of {field_name, error_message} tuples (empty if valid).
  defp validate_row(row_map, schema, _schema_by_name) do
    Enum.flat_map(schema, fn field ->
      value = Map.get(row_map, field.name, "")
      validate_field(value, field)
    end)
  end