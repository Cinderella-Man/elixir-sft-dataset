  @doc """
  Adds a list of nodes in order.

  Nodes whose id is already present (from a previous call or earlier in the same
  list) are skipped. Always returns `:ok`.
  """
  @spec add_many(GenServer.server(), [node_map()]) :: :ok
  def add_many(server, items), do: GenServer.call(server, {:add_many, items})