  @doc "Decrements the active count by 1. Returns the new value."
  def decrement(server), do: GenServer.call(server, :decrement)