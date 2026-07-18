  @doc """
  Adds `vertex` to the DAG.
  If the vertex already exists the DAG is returned unchanged.
  Vertices may be any Elixir term.
  """
  @spec add_vertex(t(), vertex()) :: t()
  def add_vertex(%__MODULE__{} = dag, vertex) do
    if MapSet.member?(dag.vertices, vertex) do
      dag
    else
      %{
        dag
        | vertices: MapSet.put(dag.vertices, vertex),
          out_edges: Map.put_new(dag.out_edges, vertex, MapSet.new()),
          in_edges: Map.put_new(dag.in_edges, vertex, MapSet.new())
      }
    end
  end