  @spec keys_by_recency(GenServer.server()) :: [term()]
  def keys_by_recency(server), do: GenServer.call(server, :keys_by_recency)