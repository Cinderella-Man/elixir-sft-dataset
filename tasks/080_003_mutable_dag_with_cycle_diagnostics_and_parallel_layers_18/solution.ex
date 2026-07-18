  @doc """
  Removes `vertex` and every edge incident to it (incoming and outgoing).

  If the vertex is absent, `dag` is returned unchanged.
  """
  @spec remove_vertex(t(), vertex()) :: t()
  def remove_vertex(%__MODULE__{} = dag, vertex) do
    if MapSet.member?(dag.vertices, vertex) do
      successors = Map.get(dag.out_edges, vertex, MapSet.new())
      predecessors = Map.get(dag.in_edges, vertex, MapSet.new())

      in_edges =
        Enum.reduce(successors, dag.in_edges, fn s, acc ->
          Map.update(acc, s, MapSet.new(), &MapSet.delete(&1, vertex))
        end)

      out_edges =
        Enum.reduce(predecessors, dag.out_edges, fn p, acc ->
          Map.update(acc, p, MapSet.new(), &MapSet.delete(&1, vertex))
        end)

      %{
        dag
        | vertices: MapSet.delete(dag.vertices, vertex),
          out_edges: Map.delete(out_edges, vertex),
          in_edges: Map.delete(in_edges, vertex)
      }
    else
      dag
    end
  end