  defp diff_records(config, left_record, right_record) do
    config
    |> fields_to_compare(left_record, right_record)
    |> Enum.reduce(%{}, fn field, acc ->
      rule = Map.get(config.rules, field, :exact)
      left_value = Map.get(left_record, field)
      right_value = Map.get(right_record, field)

      if rule == :ignore or equal?(rule, left_value, right_value) do
        acc
      else
        Map.put(acc, field, %{left: left_value, right: right_value, rule: rule})
      end
    end)
  end