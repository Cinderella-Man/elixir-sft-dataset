  @doc "Stores the `key`<->`value` pair, evicting the LRU entry when at capacity. Returns `:ok`."
  @spec put(GenServer.server(), term(), term()) :: :ok
  def put(name, key, value), do: GenServer.call(name, {:put, key, value})