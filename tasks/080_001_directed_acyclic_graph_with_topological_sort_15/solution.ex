  @doc """
  Returns all vertices that `vertex` has a direct edge *pointing to*
  (i.e. what directly depends on `vertex`).
  """
  @spec successors(t(), vertex()) :: [vertex()]
  def successors(%__MODULE__{} = dag, vertex) do
    dag.out_edges
    |> Map.get(vertex, MapSet.new())
    |> MapSet.to_list()
  end