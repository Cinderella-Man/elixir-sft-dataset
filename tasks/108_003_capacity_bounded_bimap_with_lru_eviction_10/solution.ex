  @spec size(GenServer.server()) :: non_neg_integer()
  def size(name), do: GenServer.call(name, :size)