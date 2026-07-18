  @spec unsubscribe(GenServer.server(), String.t(), reference()) :: :ok
  def unsubscribe(server, topic, ref) when is_binary(topic) and is_reference(ref) do
    GenServer.call(server, {:unsubscribe, topic, ref})
  end