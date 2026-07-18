  @doc "Decrements the active count and returns the new value."
  @spec decrement(GenServer.server()) :: integer()
  def decrement(server), do: GenServer.call(server, :decrement)