  @spec delete(GenServer.server(), term()) :: :ok
  def delete(server, key), do: GenServer.call(server, {:delete, key})