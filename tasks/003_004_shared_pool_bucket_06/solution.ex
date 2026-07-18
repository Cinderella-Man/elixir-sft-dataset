  @doc "Returns the current global pool balance (floor of float)."
  @spec global_level(GenServer.server()) :: {:ok, non_neg_integer()}
  def global_level(server), do: GenServer.call(server, :global_level)