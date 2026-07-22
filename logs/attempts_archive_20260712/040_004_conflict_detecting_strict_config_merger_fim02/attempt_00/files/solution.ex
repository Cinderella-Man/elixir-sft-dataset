  defp do_merge(base, over, path, opts) when is_map(base) and is_map(over) do
    keys = Enum.uniq(Map.keys(base) ++ Map.keys(over))

    Enum.reduce(keys, {%{}, []}, fn k, {acc, conf} ->
      kpath = path ++ [k]

      cond do
        not Map.has_key?(over, k) ->
          {Map.put(acc, k, Map.fetch!(base, k)), conf}

        not Map.has_key?(base, k) ->
          {Map.put(acc, k, Map.fetch!(over, k)), conf}

        true ->
          {value, new_conf} =
            merge_value(Map.fetch!(base, k), Map.fetch!(over, k), kpath, opts)

          {Map.put(acc, k, value), conf ++ new_conf}
      end
    end)
  end