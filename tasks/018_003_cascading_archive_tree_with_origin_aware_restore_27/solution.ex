  defp do_unarchive(state, node) do
    restored_target = %{node | archived_at: nil, archive_origin: nil}
    state = put_node(state, restored_target)

    {state, restored} = cascade_unarchive(state, node.id, [])
    {:reply, {:ok, %{node: restored_target, restored: Enum.sort(restored)}}, state}
  end