  defp compute(%{base: base, layers: layers, opts: opts}) do
    Enum.reduce(layers, base, fn {_name, map}, acc -> do_merge(acc, map, [], opts) end)
  end