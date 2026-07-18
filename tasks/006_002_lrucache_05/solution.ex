  @doc "Stores `value` under `key`, evicting the LRU entry when full. Returns `:ok`."
  @spec put(GenServer.server(), term(), term()) :: :ok
  def put(server, key, value), do: GenServer.call(server, {:put, key, value})