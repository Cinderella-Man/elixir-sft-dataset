  @doc """
  Returns the direct successors (outgoing neighbours) of `vertex`.
  """
  @spec successors(t(), vertex()) :: [vertex()]
  def successors(%__MODULE__{} = dag, vertex) do
    dag.out_edges |> Map.get(vertex, MapSet.new()) |> MapSet.to_list()
  end