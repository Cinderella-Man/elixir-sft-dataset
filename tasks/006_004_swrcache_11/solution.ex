  @doc "Stores `value` under `key` with fresh/stale TTLs and a `loader`. Returns `:ok`."
  @spec put(GenServer.server(), term(), term(), pos_integer(), pos_integer(), (-> term())) :: :ok
  def put(server, key, value, fresh_ms, stale_ms, loader)
      when is_integer(fresh_ms) and fresh_ms > 0 and
             is_integer(stale_ms) and stale_ms > 0 and
             is_function(loader, 0) do
    GenServer.call(server, {:put, key, value, fresh_ms, stale_ms, loader})
  end