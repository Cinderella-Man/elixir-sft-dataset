  @doc "Returns the highest value the counter has ever reached."
  def peak(server), do: GenServer.call(server, :peak)