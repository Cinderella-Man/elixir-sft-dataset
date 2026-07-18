  @spec publish(GenServer.server(), String.t(), term()) :: :ok
  def publish(server, topic, event) when is_binary(topic) do
    GenServer.call(server, {:publish, topic, event})
  end