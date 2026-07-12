  defp do_archive(state, node) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    target = %{node | archived_at: now, archive_origin: :direct}
    state = put_node(state, target)

    {state, cascaded} = cascade_archive(state, node.id, now, [])
    {:reply, {:ok, %{node: target, cascaded: Enum.sort(cascaded)}}, state}
  end