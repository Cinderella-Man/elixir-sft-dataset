  @doc "Fetches a payment by id, returning `{:ok, payment}` or `{:error, :not_found}`."
  @spec get_payment(GenServer.server(), String.t()) :: {:ok, payment()} | {:error, :not_found}
  def get_payment(server, id), do: GenServer.call(server, {:get_payment, id})