  def resume(server, service_name) do
    GenServer.call(server, {:resume, service_name})
  end