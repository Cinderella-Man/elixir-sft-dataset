  @doc """
  Returns the list of all vertices currently in the graph.
  """
  @spec vertices(GenServer.server()) :: [term()]
  def vertices(server), do: GenServer.call(server, :vertices)