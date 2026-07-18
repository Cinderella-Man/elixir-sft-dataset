  @doc """
  Looks up a single payment record by its id.
  """
  @spec get_payment(GenServer.server(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_payment(server, id) do
    GenServer.call(server, {:get_payment, id})
  end