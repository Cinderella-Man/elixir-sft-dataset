  @spec unsubscribe(GenServer.server(), String.t(), reference()) :: :ok
  def unsubscribe(server, topic, ref), do: GenServer.call(server, {:unsubscribe, topic, ref})