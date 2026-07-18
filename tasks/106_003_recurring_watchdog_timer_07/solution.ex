  @spec unregister(term()) :: :ok
  def unregister(name), do: GenServer.call(__MODULE__, {:unregister, name})