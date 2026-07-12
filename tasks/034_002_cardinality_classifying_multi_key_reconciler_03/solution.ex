  defp differences(left, right, %{key_fields: key_fields, compare_fields: compare_fields}) do
    fields = fields_to_compare(left, right, key_fields, compare_fields)

    Enum.reduce(fields, %{}, fn field, acc ->
      left_value = Map.get(left, field)
      right_value = Map.get(right, field)

      if left_value == right_value do
        acc
      else
        Map.put(acc, field, %{left: left_value, right: right_value})
      end
    end)
  end