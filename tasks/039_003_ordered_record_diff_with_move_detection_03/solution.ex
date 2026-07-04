  def diff(old_list, new_list, opts \\ []) do
    key = Keyword.get(opts, :key, :id)

    old_keys = Enum.map(old_list, &Map.fetch!(&1, key))
    new_keys = Enum.map(new_list, &Map.fetch!(&1, key))

    old_set = MapSet.new(old_keys)
    new_set = MapSet.new(new_keys)

    added = Enum.reject(new_list, &MapSet.member?(old_set, Map.fetch!(&1, key)))
    removed = Enum.reject(old_list, &MapSet.member?(new_set, Map.fetch!(&1, key)))

    old_index = index_by(old_list, key)
    new_index = index_by(new_list, key)
    old_pos = positions(old_list, key)
    new_pos = positions(new_list, key)

    common_new_seq = Enum.filter(new_keys, &MapSet.member?(old_set, &1))
    common_old_seq = Enum.filter(old_keys, &MapSet.member?(new_set, &1))
    stable = MapSet.new(lcs(common_old_seq, common_new_seq))

    changed =
      common_new_seq
      |> Enum.reduce([], fn kv, acc ->
        changes = diff_records(Map.fetch!(old_index, kv), Map.fetch!(new_index, kv))

        if map_size(changes) == 0 do
          acc
        else
          [%{key => kv, changes: changes} | acc]
        end
      end)
      |> Enum.reverse()

    moved =
      common_new_seq
      |> Enum.reject(&MapSet.member?(stable, &1))
      |> Enum.map(fn kv ->
        %{key => kv, from: Map.fetch!(old_pos, kv), to: Map.fetch!(new_pos, kv)}
      end)

    %{added: added, removed: removed, changed: changed, moved: moved}
  end