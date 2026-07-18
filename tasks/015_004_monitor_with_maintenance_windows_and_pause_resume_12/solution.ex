  def maintenance(server, service_name, duration_ms) do
    GenServer.call(server, {:maintenance, service_name, duration_ms})
  end