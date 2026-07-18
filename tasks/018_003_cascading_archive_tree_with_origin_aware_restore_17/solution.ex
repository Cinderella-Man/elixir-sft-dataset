  defp do_create(state, fields) do
    id = state.next_id

    node =
      Map.merge(fields, %{id: id, archived_at: nil, archive_origin: nil})

    new_state = %{state | nodes: Map.put(state.nodes, id, node), next_id: id + 1}
    {:reply, {:ok, node}, new_state}
  end