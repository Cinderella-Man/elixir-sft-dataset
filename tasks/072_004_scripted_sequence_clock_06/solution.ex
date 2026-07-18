  @doc "Returns how many scripted values have not yet been consumed."
  @spec remaining(GenServer.server()) :: non_neg_integer()
  def remaining(server), do: GenServer.call(server, :remaining)