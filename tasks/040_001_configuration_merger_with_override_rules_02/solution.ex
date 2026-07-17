  defp do_merge(base, override, current_path, opts) when is_map(base) and is_map(override) do
    # Collect all keys from both maps, base keys first for stable traversal.
    all_keys = Enum.uniq(Map.keys(base) ++ Map.keys(override))

    Enum.reduce(all_keys, %{}, fn key, acc ->
      key_path = current_path ++ [key]

      cond do
        # Key only exists in base — keep it unconditionally.
        not Map.has_key?(override, key) ->
          Map.put(acc, key, Map.fetch!(base, key))

        # The path is locked: the base value (if any) is authoritative. When the
        # base does not define the key, the override cannot inject it — a locked
        # path is never writable from the override side.
        locked?(key_path, opts) ->
          case Map.fetch(base, key) do
            {:ok, base_value} -> Map.put(acc, key, base_value)
            :error -> acc
          end

        # Key only exists in base-less territory and is not locked — take it.
        not Map.has_key?(base, key) ->
          Map.put(acc, key, Map.fetch!(override, key))

        # Both maps have the key and it is not locked — merge the values.
        true ->
          merged = merge_values(Map.fetch!(base, key), Map.fetch!(override, key), key_path, opts)
          Map.put(acc, key, merged)
      end
    end)
  end