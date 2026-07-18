  @doc """
  Returns every payment record created so far, in creation order.
  """
  @spec get_payments(GenServer.server()) :: [map()]
  def get_payments(server) do
    GenServer.call(server, :get_payments)
  end