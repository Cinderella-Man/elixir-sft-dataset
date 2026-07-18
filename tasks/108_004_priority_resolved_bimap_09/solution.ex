  @spec priority(GenServer.server(), term()) :: {:ok, integer()} | :error
  def priority(name, key), do: GenServer.call(name, {:priority, key})