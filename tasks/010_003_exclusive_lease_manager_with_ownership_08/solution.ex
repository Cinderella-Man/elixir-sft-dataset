  def renew(server, resource, owner) do
    GenServer.call(server, {:renew, resource, owner})
  end