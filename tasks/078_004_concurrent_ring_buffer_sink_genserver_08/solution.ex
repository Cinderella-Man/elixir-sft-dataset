  @doc "Returns the number of items currently stored (0..capacity)."
  @spec size(GenServer.server()) :: non_neg_integer()
  def size(server), do: GenServer.call(server, :size)