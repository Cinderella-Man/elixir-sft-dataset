  @doc """
  Returns a `MapSet` of all elements currently in the set.
  """
  @spec members(server()) :: MapSet.t()
  def members(server) do
    GenServer.call(server, :members)
  end