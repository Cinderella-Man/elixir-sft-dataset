  @spec resolve_compare_fields(record_t(), record_t(), [atom()], [atom()] | nil) :: [atom()]
  defp resolve_compare_fields(_left, _right, _key_fields, compare_fields)
       when is_list(compare_fields),
       do: compare_fields

  defp resolve_compare_fields(left, right, key_fields, nil) do
    all_fields =
      (Map.keys(left) ++ Map.keys(right))
      |> Enum.uniq()

    key_set = MapSet.new(key_fields)
    Enum.reject(all_fields, &MapSet.member?(key_set, &1))
  end