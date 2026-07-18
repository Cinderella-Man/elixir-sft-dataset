  @doc """
  Cache-only eviction of every entry for `table`.

  Clears the table's cache without touching the backing store. Always `:ok`.
  """
  @spec invalidate_all(GenServer.server(), atom()) :: :ok
  def invalidate_all(server, table) when is_atom(table) do
    GenServer.call(server, {:invalidate_all, table})
  end