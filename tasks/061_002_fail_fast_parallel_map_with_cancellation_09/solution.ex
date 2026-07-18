  @doc "Returns how many times `increment/1` has ever been called."
  @spec started(GenServer.server()) :: non_neg_integer()
  def started(server), do: GenServer.call(server, :started)