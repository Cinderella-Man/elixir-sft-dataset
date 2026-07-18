  @spec ready(GenServer.server(), term(), non_neg_integer()) :: [map()]
  def ready(server, queue_name, count) when is_integer(count) and count >= 0 do
    GenServer.call(server, {:ready, queue_name, count})
  end