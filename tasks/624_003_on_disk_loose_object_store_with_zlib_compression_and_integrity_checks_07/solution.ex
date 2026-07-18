  def retrieve(server, hash) do
    GenServer.call(server, {:retrieve, hash})
  end