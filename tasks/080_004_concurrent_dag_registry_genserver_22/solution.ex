  @doc """
  Returns the list of direct incoming neighbours (predecessors) of `vertex`.
  """
  @spec predecessors(GenServer.server(), term()) :: [term()]
  def predecessors(server, vertex), do: GenServer.call(server, {:predecessors, vertex})