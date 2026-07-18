  def subscribe(server, topic, pid) do
    GenServer.call(server, {:subscribe, topic, pid})
  end