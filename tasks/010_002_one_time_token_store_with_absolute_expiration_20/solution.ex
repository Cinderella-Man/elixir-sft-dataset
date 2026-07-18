  @doc """
  Returns the number of tokens that are still valid (not expired, not
  redeemed, not revoked).
  """
  @spec active_count(server()) :: non_neg_integer()
  def active_count(server) do
    GenServer.call(server, :active_count)
  end