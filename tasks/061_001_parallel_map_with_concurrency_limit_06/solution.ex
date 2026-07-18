  @doc "Increments the active count by 1. Returns the new value."
  def increment(server), do: GenServer.call(server, :increment)