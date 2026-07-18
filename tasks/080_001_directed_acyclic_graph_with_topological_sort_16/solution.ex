  @doc """
  Returns `{:ok, ordering}` where `ordering` is a list of every vertex in a
  valid topological order — each vertex appears before all of its successors.

  Uses **Kahn's algorithm** (BFS over in-degrees).

  Returns `{:ok, []}` for an empty graph.  Because `add_edge/3` guarantees the
  graph is always acyclic, this function will always succeed.
  """
  @spec topological_sort(t()) :: {:ok, [vertex()]}
  def topological_sort(%__MODULE__{} = dag) do
    # Build in-degree map: vertex => number of incoming edges
    in_degree =
      Map.new(dag.vertices, fn v ->
        {v, MapSet.size(Map.fetch!(dag.in_edges, v))}
      end)

    # Seed the queue with all vertices that have no incoming edges.
    # Sort for determinism when multiple zero-in-degree vertices exist.
    initial_queue =
      in_degree
      |> Enum.filter(fn {_v, deg} -> deg == 0 end)
      |> Enum.map(fn {v, _} -> v end)
      |> Enum.sort()

    {order, _in_degree} = kahn(initial_queue, in_degree, dag.out_edges, [])

    {:ok, order}
  end