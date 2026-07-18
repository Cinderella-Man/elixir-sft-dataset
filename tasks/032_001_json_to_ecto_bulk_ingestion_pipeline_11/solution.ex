  @spec maybe_put_new(map(), atom(), term(), MapSet.t(String.t())) :: map()
  defp maybe_put_new(row, field, value, schema_keys) do
    if MapSet.member?(schema_keys, Atom.to_string(field)) do
      Map.put_new(row, field, value)
    else
      row
    end
  end