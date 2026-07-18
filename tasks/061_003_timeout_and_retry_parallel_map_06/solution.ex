  @doc "Increments the active count and returns the new value."
  @spec increment(GenServer.server()) :: integer()
  def increment(server), do: GenServer.call(server, :increment)