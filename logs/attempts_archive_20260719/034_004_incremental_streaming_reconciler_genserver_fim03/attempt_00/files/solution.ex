  @spec fields_to_compare(state(), stream_record(), stream_record()) :: [atom()]
  defp fields_to_compare(%__MODULE__{compare_fields: nil} = state, left, right) do
    key_fields = MapSet.new(state.key_fields)

    left
    |> Map.keys()
    |> Kernel.++(Map.keys(right))
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(key_fields, &1))
  end

  defp fields_to_compare(%__MODULE__{compare_fields: fields}, _left, _right), do: fields