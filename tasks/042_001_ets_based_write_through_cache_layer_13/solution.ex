  @doc """
  Removes **all** cached entries for `table`.

  The ETS table itself is kept alive for future use; only its contents are
  cleared.

  Returns `:ok` whether or not the table had any entries.

  ## Examples

      :ok = CacheLayer.invalidate_all(:my_cache, :users)
  """
  @spec invalidate_all(GenServer.server(), atom()) :: :ok
  def invalidate_all(server, table) when is_atom(table) do
    GenServer.call(server, {:invalidate_all, table})
  end