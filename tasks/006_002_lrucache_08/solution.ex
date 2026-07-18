  @spec size(GenServer.server()) :: non_neg_integer()
  def size(server), do: GenServer.call(server, :size)