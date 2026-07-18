  defp do_add_vertex(state, vertex) do
    if MapSet.member?(state.vertices, vertex) do
      state
    else
      %{
        state
        | vertices: MapSet.put(state.vertices, vertex),
          out_edges: Map.put_new(state.out_edges, vertex, MapSet.new()),
          in_edges: Map.put_new(state.in_edges, vertex, MapSet.new())
      }
    end
  end