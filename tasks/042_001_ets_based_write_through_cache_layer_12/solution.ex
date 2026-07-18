  @doc """
  Removes the cached entry for `{table, key}`.

  Returns `:ok` whether or not the entry existed.

  ## Examples

      :ok = CacheLayer.invalidate(:my_cache, :users, 42)
  """
  @spec invalidate(GenServer.server(), atom(), term()) :: :ok
  def invalidate(server, table, key) when is_atom(table) do
    GenServer.call(server, {:invalidate, table, key})
  end