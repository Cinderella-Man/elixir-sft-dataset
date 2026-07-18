  @spec keys_by_recency(GenServer.server()) :: [term()]
  def keys_by_recency(name), do: GenServer.call(name, :keys_by_recency)