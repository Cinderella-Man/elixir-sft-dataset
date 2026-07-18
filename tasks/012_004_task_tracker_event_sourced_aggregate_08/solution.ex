  @doc "Returns the full history of events for a specific aggregate ID."
  @spec events(GenServer.server(), id()) :: [event()]
  def events(server, id) do
    GenServer.call(server, {:get_events, id})
  end