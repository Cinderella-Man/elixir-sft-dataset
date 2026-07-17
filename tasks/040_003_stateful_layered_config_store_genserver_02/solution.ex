  defp do_merge(base, over, path, opts) when is_map(base) and is_map(over) do
    keys = Enum.uniq(Map.keys(base) ++ Map.keys(over))

    Enum.reduce(keys, %{}, fn k, acc ->
      kpath = path ++ [k]

      cond do
        locked?(kpath, opts) ->
          # A locked path always keeps the base value — including its absence, so a
          # layer cannot introduce a key that the base never defined.
          case Map.fetch(base, k) do
            {:ok, v} -> Map.put(acc, k, v)
            :error -> acc
          end

        not Map.has_key?(over, k) ->
          Map.put(acc, k, Map.fetch!(base, k))

        not Map.has_key?(base, k) ->
          Map.put(acc, k, Map.fetch!(over, k))

        true ->
          Map.put(acc, k, merge_value(Map.fetch!(base, k), Map.fetch!(over, k), kpath, opts))
      end
    end)
  end