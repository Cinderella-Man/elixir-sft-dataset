  def status(server, key) do
    GenServer.call(server, {:status, key})
  end