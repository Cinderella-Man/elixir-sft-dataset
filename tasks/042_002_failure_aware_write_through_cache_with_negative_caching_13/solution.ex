  @doc """
  Removes all cached entries for the given `table`.

  Always returns `:ok`, even if the table has never been used.
  """
  @spec invalidate_all(GenServer.server(), atom()) :: :ok
  def invalidate_all(server, table) when is_atom(table) do
    GenServer.call(server, {:invalidate_all, table})
  end