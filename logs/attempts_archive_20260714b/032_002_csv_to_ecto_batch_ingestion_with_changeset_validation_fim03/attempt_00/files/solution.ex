  @spec build_attrs([String.t()], [atom()], MapSet.t()) :: map()
  defp build_attrs(cells, atom_headers, schema_keys) do
    atom_headers
    |> Enum.zip(cells)
    |> Enum.filter(fn {k, _v} -> MapSet.member?(schema_keys, Atom.to_string(k)) end)
    |> Enum.map(fn {k, v} -> {k, normalize_value(v)} end)
    |> Map.new()
  end