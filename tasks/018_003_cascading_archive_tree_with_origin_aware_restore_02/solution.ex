  defp cascade_unarchive(state, parent_id, acc) do
    state
    |> children_of(parent_id)
    |> Enum.reduce({state, acc}, fn child, {st, ids} ->
      if child.archive_origin == :cascade do
        restored = %{child | archived_at: nil, archive_origin: nil}
        st = put_node(st, restored)
        cascade_unarchive(st, child.id, [child.id | ids])
      else
        {st, ids}
      end
    end)
  end