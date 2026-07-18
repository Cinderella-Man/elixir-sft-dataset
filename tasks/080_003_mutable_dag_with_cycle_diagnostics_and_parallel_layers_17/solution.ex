  @doc """
  Removes the directed edge `from -> to` if present.

  If the edge or either vertex is absent, `dag` is returned unchanged.
  """
  @spec remove_edge(t(), vertex(), vertex()) :: t()
  def remove_edge(%__MODULE__{} = dag, from, to) do
    if MapSet.member?(dag.vertices, from) and MapSet.member?(dag.vertices, to) do
      %{
        dag
        | out_edges: Map.update(dag.out_edges, from, MapSet.new(), &MapSet.delete(&1, to)),
          in_edges: Map.update(dag.in_edges, to, MapSet.new(), &MapSet.delete(&1, from))
      }
    else
      dag
    end
  end