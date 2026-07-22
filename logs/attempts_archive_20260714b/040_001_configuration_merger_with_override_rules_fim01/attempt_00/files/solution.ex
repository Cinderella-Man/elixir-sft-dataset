  defp do_merge(base, override, current_path, opts) when is_map(base) and is_map(override) do
    # Collect all keys from both maps.
    all_keys = Map.keys(base) ++ Map.keys(override)
    all_keys = Enum.uniq(all_keys)

    Map.new(all_keys, fn key ->
      key_path = current_path ++ [key]

      merged_value =
        cond do
          # Key only exists in base — keep it unconditionally.
          not Map.has_key?(override, key) ->
            Map.fetch!(base, key)

          # Key only exists in override — but respect lock (do not introduce
          # a locked key if it genuinely isn't in base either; if it *is* in
          # base the guard below handles it).
          not Map.has_key?(base, key) ->
            Map.fetch!(override, key)

          # Both maps have the key. Check lock first.
          locked?(key_path, opts) ->
            Map.fetch!(base, key)

          # Both maps have the key, key is not locked — merge the values.
          true ->
            merge_values(
              Map.fetch!(base, key),
              Map.fetch!(override, key),
              key_path,
              opts
            )
        end

      {key, merged_value}
    end)
  end