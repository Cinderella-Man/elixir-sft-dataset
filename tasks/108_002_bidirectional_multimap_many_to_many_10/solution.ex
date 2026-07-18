  @doc "Removes `key` and all of its associations. Returns `:ok`."
  @spec delete_key(GenServer.server(), term()) :: :ok
  def delete_key(name, key), do: GenServer.call(name, {:delete_key, key})