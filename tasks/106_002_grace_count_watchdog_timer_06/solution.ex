  @spec heartbeat(term()) :: :ok
  def heartbeat(name), do: GenServer.call(__MODULE__, {:heartbeat, name})