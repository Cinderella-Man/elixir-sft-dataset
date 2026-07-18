  def fetch_node(server, id, opts \\ []) do
    GenServer.call(server, {:fetch_node, id, include_archived?(opts)})
  end