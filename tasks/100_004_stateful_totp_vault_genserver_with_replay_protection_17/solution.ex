  @doc """
  Returns `{:ok, secret}` for a registered account, or `{:error, :not_found}`.
  """
  @spec secret(server(), account_id()) :: {:ok, secret()} | {:error, :not_found}
  def secret(server, account_id) do
    GenServer.call(server, {:secret, account_id})
  end