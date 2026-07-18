  @doc """
  Returns `{:ok, ordering}` with all vertices in a valid topological order
  (Kahn's algorithm). Returns `{:ok, []}` when the graph is empty.
  """
  @spec topological_sort(GenServer.server()) :: {:ok, [term()]}
  def topological_sort(server), do: GenServer.call(server, :topological_sort)