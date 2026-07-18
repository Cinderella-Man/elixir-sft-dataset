  @doc """
  Returns the direct predecessors (incoming neighbours) of `vertex`.
  """
  @spec predecessors(t(), vertex()) :: [vertex()]
  def predecessors(%__MODULE__{} = dag, vertex) do
    dag.in_edges |> Map.get(vertex, MapSet.new()) |> MapSet.to_list()
  end