  @doc "Returns all live items in insertion order (oldest → newest)."
  @spec to_list(GenServer.server()) :: list()
  def to_list(server), do: GenServer.call(server, :to_list)