  @doc """
  Checks whether `token_id` is valid without consuming it.

  Returns `{:ok, payload}` if the token exists and has not expired or
  been redeemed, or `{:error, :not_found}` otherwise.
  """
  @spec verify(server(), token_id()) :: {:ok, payload()} | {:error, :not_found}
  def verify(server, token_id) do
    GenServer.call(server, {:verify, token_id})
  end