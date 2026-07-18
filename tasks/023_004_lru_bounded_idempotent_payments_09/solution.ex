  @doc "Returns retained idempotency keys ordered least-recently-used first."
  @spec keys_by_recency(GenServer.server()) :: [String.t()]
  def keys_by_recency(server), do: GenServer.call(server, :keys_by_recency)