  @doc "Returns the number of timers not yet fired or cancelled."
  @spec pending(GenServer.server()) :: non_neg_integer()
  def pending(server), do: GenServer.call(server, :pending)