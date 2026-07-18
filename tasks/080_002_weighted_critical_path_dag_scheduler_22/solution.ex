  @doc """
  Returns the direct predecessors (incoming neighbours) of task `id`.
  """
  @spec predecessors(t(), id()) :: [id()]
  def predecessors(%__MODULE__{} = dag, id) do
    dag.in_edges |> Map.get(id, MapSet.new()) |> MapSet.to_list() |> Enum.sort()
  end