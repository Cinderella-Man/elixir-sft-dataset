  defp do_merge(base, over, path, opts) when is_map(base) and is_map(over) do
    keys = Enum.uniq(Map.keys(base) ++ Map.keys(over))

    Map.new(keys, fn k ->
      kpath = path ++ [k]

      value =
        cond do
          not Map.has_key?(over, k) -> Map.fetch!(base, k)
          not Map.has_key?(base, k) -> Map.fetch!(over, k)
          locked?(kpath, opts) -> Map.fetch!(base, k)
          true -> merge_value(Map.fetch!(base, k), Map.fetch!(over, k), kpath, opts)
        end

      {k, value}
    end)
  end