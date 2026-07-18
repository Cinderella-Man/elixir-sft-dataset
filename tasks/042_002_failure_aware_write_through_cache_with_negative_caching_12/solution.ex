  @doc """
  Removes the cached entry (success or failure) for `{table, key}`.

  Always returns `:ok`, even if no entry (or table) exists.
  """
  @spec invalidate(GenServer.server(), atom(), term()) :: :ok
  def invalidate(server, table, key) when is_atom(table) do
    GenServer.call(server, {:invalidate, table, key})
  end