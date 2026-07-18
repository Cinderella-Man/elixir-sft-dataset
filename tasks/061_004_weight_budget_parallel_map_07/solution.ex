  @doc "Subtracts `weight` from the in-flight total and returns the new total."
  @spec sub(GenServer.server(), integer()) :: integer()
  def sub(server, weight), do: GenServer.call(server, {:sub, weight})