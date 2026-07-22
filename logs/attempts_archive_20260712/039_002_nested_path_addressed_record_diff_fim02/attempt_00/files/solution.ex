  def diff(old_list, new_list, opts \\ []) do
    key = Keyword.get(opts, :key, :id)

    old_index = index_by(old_list, key)
    new_index = index_by(new_list, key)

    old_keys = old_index |> Map.keys() |> MapSet.new()
    new_keys = new_index |> Map.keys() |> MapSet.new()

    added = new_keys |> MapSet.difference(old_keys) |> to_records(new_index)
    removed = old_keys |> MapSet.difference(new_keys) |> to_records(old_index)

    changed =
      old_keys
      |> MapSet.intersection(new_keys)
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.reduce([], fn kv, acc ->
        changes = deep_changes(Map.fetch!(old_index, kv), Map.fetch!(new_index, kv))

        if map_size(changes) == 0 do
          acc
        else
          [%{key => kv, changes: changes} | acc]
        end
      end)
      |> Enum.reverse()

    %{added: added, removed: removed, changed: changed}
  end