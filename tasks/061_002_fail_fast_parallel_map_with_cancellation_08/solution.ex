  @doc "Returns the highest value the counter has ever reached."
  @spec peak(GenServer.server()) :: integer()
  def peak(server), do: GenServer.call(server, :peak)