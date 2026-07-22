  defp leaf_provenance(value, name, path, pr) when is_map(value) do
    Enum.reduce(value, pr, fn {k, v}, acc -> leaf_provenance(v, name, path ++ [k], acc) end)
  end

  defp leaf_provenance(_value, name, path, pr), do: Map.put(pr, path, name)