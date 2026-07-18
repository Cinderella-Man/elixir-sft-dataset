  @doc """
  Adds `vertex` to the graph. If it already exists, the graph is unchanged.

  Vertices may be any term. Returns `:ok`.
  """
  @spec add_vertex(GenServer.server(), term()) :: :ok
  def add_vertex(server, vertex), do: GenServer.call(server, {:add_vertex, vertex})