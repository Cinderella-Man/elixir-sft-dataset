  @doc """
  Returns the list of direct outgoing neighbours (successors) of `vertex`.
  """
  @spec successors(GenServer.server(), term()) :: [term()]
  def successors(server, vertex), do: GenServer.call(server, {:successors, vertex})