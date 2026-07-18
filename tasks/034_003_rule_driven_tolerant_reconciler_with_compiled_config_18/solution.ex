  defp fields_to_compare(%__MODULE__{compare_fields: nil} = config, left_record, right_record) do
    left_record
    |> Map.keys()
    |> Enum.concat(Map.keys(right_record))
    |> Enum.uniq()
    |> Enum.reject(&(&1 in config.key_fields))
  end

  defp fields_to_compare(%__MODULE__{compare_fields: fields}, _left, _right) do
    Enum.uniq(fields)
  end