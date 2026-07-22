  defp do_add_edge(state, from, to) do
    with :ok <- require_vertex(state, from),
         :ok <- require_vertex(state, to),
         :ok <- check_no_cycle(state, from, to) do
      new_state = %{
        state
        | out_edges: Map.update!(state.out_edges, from, &MapSet.put(&1, to)),
          in_edges: Map.update!(state.in_edges, to, &MapSet.put(&1, from))
      }

      {:ok, new_state}
    end
  end