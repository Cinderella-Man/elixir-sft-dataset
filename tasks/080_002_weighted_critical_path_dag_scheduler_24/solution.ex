  @doc """
  Returns `{:ok, ordering}`, a topological order of the tasks (Kahn's
  algorithm).  Returns `{:ok, []}` for an empty graph.
  """
  @spec topological_sort(t()) :: {:ok, [id()]}
  def topological_sort(%__MODULE__{} = dag) do
    {:ok, topo_order(dag)}
  end