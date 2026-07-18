  @doc """
  Removes every cached entry for `table`. Always returns `:ok`.
  """
  @spec invalidate_all(GenServer.server(), atom()) :: :ok
  def invalidate_all(server, table) when is_atom(table) do
    GenServer.call(server, {:invalidate_all, table})
  end