  @doc """
  Returns the number of nodes currently held.
  """
  @spec count(GenServer.server()) :: non_neg_integer()
  def count(server), do: GenServer.call(server, :count)