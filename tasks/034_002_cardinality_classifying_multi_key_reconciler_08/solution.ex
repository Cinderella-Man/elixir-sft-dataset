  defp fields_to_compare(left, right, key_fields, nil) do
    left
    |> Map.keys()
    |> Enum.concat(Map.keys(right))
    |> Enum.uniq()
    |> Enum.reject(&(&1 in key_fields))
  end

  defp fields_to_compare(_left, _right, _key_fields, compare_fields), do: compare_fields