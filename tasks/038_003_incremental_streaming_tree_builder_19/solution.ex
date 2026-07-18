  @doc """
  Adds one node.

  Returns `:ok`, or `{:error, {:duplicate_id, id}}` if a node with that id was
  already added (the new item is rejected and the state is left unchanged).
  """
  @spec add(GenServer.server(), node_map()) :: :ok | {:error, {:duplicate_id, id()}}
  def add(server, item), do: GenServer.call(server, {:add, item})