  def unsubscribe(server, topic, ref) do
    GenServer.call(server, {:unsubscribe, topic, ref})
  end