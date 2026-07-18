  @spec reset(GenServer.server()) :: :ok
  def reset(name), do: GenServer.call(name, :reset)