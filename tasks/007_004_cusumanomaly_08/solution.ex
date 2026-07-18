  @spec reset(GenServer.server(), term()) :: :ok
  def reset(server, name), do: GenServer.call(server, {:reset, name})