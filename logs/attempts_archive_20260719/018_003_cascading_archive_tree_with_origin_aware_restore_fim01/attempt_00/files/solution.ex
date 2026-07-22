  defp cascade_archive(state, parent_id, now, acc) do
    state
    |> children_of(parent_id)
    |> Enum.reduce({state, acc}, fn child, {st, ids} ->
      if live?(child) do
        archived = %{child | archived_at: now, archive_origin: :cascade}
        st = put_node(st, archived)
        cascade_archive(st, child.id, now, [child.id | ids])
      else
        {st, ids}
      end
    end)
  end