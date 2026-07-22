  defp validate_and_coerce_row(row_map, schema, headers) do
    schema
    |> Enum.filter(fn field -> field.name in headers end)
    |> Enum.reduce({[], %{}}, fn field, {errs, coerced} ->
      value = Map.get(row_map, field.name, "")
      key = Map.get(field, :key, String.to_atom(field.name))

      case validate_and_coerce_field(value, field) do
        {:ok, coerced_value} ->
          {errs, Map.put(coerced, key, coerced_value)}

        {:errors, field_errors} ->
          {errs ++ field_errors, coerced}
      end
    end)
  end