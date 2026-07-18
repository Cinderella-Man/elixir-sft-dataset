  @doc "Returns the highest in-flight total the meter has ever reached."
  @spec peak(GenServer.server()) :: integer()
  def peak(server), do: GenServer.call(server, :peak)