  def status(server, service_name) do
    GenServer.call(server, {:status, service_name})
  end