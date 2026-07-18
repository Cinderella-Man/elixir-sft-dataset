  @spec set_history_size(GenServer.server(), String.t(), non_neg_integer()) :: :ok
  def set_history_size(server, topic, size)
      when is_binary(topic) and is_integer(size) and size >= 0 do
    GenServer.call(server, {:set_history_size, topic, size})
  end