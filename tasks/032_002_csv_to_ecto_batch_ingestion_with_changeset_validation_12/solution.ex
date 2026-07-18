  @spec maybe_put_ts(map(), atom(), NaiveDateTime.t(), MapSet.t()) :: map()
  defp maybe_put_ts(row, field, value, schema_keys) do
    if MapSet.member?(schema_keys, Atom.to_string(field)) do
      Map.put_new(row, field, value)
    else
      row
    end
  end