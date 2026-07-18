  def holder(server, resource) do
    GenServer.call(server, {:holder, resource})
  end