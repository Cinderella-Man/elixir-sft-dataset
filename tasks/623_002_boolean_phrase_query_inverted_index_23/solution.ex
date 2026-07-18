  @doc """
  Evaluates a Boolean `query` and returns the sorted list of matching ids.
  """
  @spec search(GenServer.server(), query()) :: [String.t()]
  def search(server, query) do
    GenServer.call(server, {:search, query})
  end