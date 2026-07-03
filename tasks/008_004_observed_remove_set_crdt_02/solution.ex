  @spec merge_states(or_state(), or_state()) :: or_state()
  defp merge_states(local, remote) do
    # 1. Union the tombstones
    merged_tombstones = MapSet.union(local.tombstones, remote.tombstones)

    # 2. Union the entries per element, then subtract tombstones
    all_elements =
      MapSet.union(
        MapSet.new(Map.keys(local.entries)),
        MapSet.new(Map.keys(remote.entries))
      )

    merged_entries =
      Enum.reduce(all_elements, %{}, fn element, acc ->
        local_tags = Map.get(local.entries, element, MapSet.new())
        remote_tags = Map.get(remote.entries, element, MapSet.new())
        merged_tags = MapSet.union(local_tags, remote_tags)
        # Remove tombstoned tags
        live_tags = MapSet.difference(merged_tags, merged_tombstones)

        if MapSet.size(live_tags) > 0 do
          Map.put(acc, element, live_tags)
        else
          acc
        end
      end)

    # 3. Merge clocks by taking per-node max
    merged_clock =
      Map.merge(local.clock, remote.clock, fn _node, l, r -> max(l, r) end)

    %{entries: merged_entries, tombstones: merged_tombstones, clock: merged_clock}
  end