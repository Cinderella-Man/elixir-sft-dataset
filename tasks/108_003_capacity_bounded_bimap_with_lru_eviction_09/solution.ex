  @spec delete(GenServer.server(), term()) :: :ok
  def delete(name, key), do: GenServer.call(name, {:delete, key})