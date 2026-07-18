  @doc """
  Cache-only eviction of `{table, key}`.

  Removes the cached entry without touching the backing store. Always `:ok`.
  """
  @spec invalidate(GenServer.server(), atom(), term()) :: :ok
  def invalidate(server, table, key) when is_atom(table) do
    GenServer.call(server, {:invalidate, table, key})
  end