  @spec put(GenServer.server(), term(), term(), pos_integer(), (-> term())) :: :ok
  @doc """
  Stores `value` under `key` for `ttl_ms`, using `loader/0` to refresh the entry ahead
  of expiry. Returns `:ok`.
  """
  def put(server, key, value, ttl_ms, loader)
      when is_integer(ttl_ms) and ttl_ms > 0 and is_function(loader, 0) do
    GenServer.call(server, {:put, key, value, ttl_ms, loader})
  end