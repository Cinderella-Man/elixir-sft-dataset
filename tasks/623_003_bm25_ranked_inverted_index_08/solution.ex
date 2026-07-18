  def search(server, query, opts \\ []) do
    GenServer.call(server, {:search, query, opts})
  end