  @doc """
  Returns a `MapSet` of all elements currently in the set.

  An element is included when its add timestamp is strictly greater than its
  remove timestamp (or it has never been removed).
  """
  @spec members(server()) :: MapSet.t()
  def members(server) do
    GenServer.call(server, :members)
  end