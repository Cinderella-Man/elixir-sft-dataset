  @doc """
  Returns the direct successors (outgoing neighbours) of task `id`.
  """
  @spec successors(t(), id()) :: [id()]
  def successors(%__MODULE__{} = dag, id) do
    dag.out_edges |> Map.get(id, MapSet.new()) |> MapSet.to_list() |> Enum.sort()
  end