  @doc """
  Invalidates a token without redeeming it.

  Always returns `:ok`, even if the token did not exist.
  """
  @spec revoke(server(), token_id()) :: :ok
  def revoke(server, token_id) do
    GenServer.call(server, {:revoke, token_id})
  end