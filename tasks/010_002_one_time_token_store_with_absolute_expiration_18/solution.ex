  @doc """
  Consumes a valid token, returning its payload and permanently removing it.

  Returns `{:ok, payload}` on success, or `{:error, :not_found}` if the
  token doesn't exist, was already redeemed, or has expired.
  """
  @spec redeem(server(), token_id()) :: {:ok, payload()} | {:error, :not_found}
  def redeem(server, token_id) do
    GenServer.call(server, {:redeem, token_id})
  end