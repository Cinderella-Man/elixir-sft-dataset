  @doc "Removes the single association `{key, value}` in both directions."
  @spec delete(GenServer.server(), term(), term()) :: :ok
  def delete(name, key, value), do: GenServer.call(name, {:delete, key, value})