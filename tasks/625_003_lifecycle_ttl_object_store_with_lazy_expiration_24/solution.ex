  @doc """
  Sweep every bucket and permanently remove all currently expired objects.

  Returns `{:ok, count}` where `count` is the number of objects removed.
  """
  @spec purge_expired(server()) :: {:ok, non_neg_integer()}
  def purge_expired(server) do
    GenServer.call(server, :purge_expired)
  end