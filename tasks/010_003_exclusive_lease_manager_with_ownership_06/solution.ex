  def acquire(server, resource, owner) do
    GenServer.call(server, {:acquire, resource, owner})
  end