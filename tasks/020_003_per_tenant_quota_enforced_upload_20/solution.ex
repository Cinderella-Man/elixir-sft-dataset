  @doc """
  Returns the current used bytes for `account` (0 if unknown).
  """
  @spec usage(GenServer.server(), String.t()) :: non_neg_integer()
  def usage(server, account), do: GenServer.call(server, {:usage, account})