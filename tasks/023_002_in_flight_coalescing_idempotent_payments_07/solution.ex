  @doc "Returns all payment records, oldest first."
  @spec get_payments(GenServer.server()) :: [response()]
  def get_payments(server), do: GenServer.call(server, :get_payments)