  # Validate a single record against the full schema.
  # Returns a list of {field_name, error_message} tuples (empty if valid).
  defp validate_record(record, schema) do
    Enum.flat_map(schema, fn field ->
      value = Map.get(record, field.name)
      validate_field(value, field)
    end)
  end