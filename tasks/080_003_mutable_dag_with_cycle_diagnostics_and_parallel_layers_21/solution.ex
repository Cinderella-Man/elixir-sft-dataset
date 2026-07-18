  @doc """
  Groups every vertex into topological layers ("parallel waves").

  Layer 0 holds all vertices with no predecessors; each subsequent layer
  holds vertices whose predecessors have all appeared in earlier layers.
  Vertices within a layer are sorted by term ordering for determinism.
  Returns `{:ok, layers}`; an empty graph yields `{:ok, []}`.
  """
  @spec topological_layers(t()) :: {:ok, [[vertex()]]}
  def topological_layers(%__MODULE__{} = dag) do
    in_degree =
      Map.new(dag.vertices, fn v -> {v, MapSet.size(Map.fetch!(dag.in_edges, v))} end)

    {:ok, build_layers(in_degree, dag.out_edges, [])}
  end