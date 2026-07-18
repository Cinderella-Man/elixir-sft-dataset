  @doc """
  Permanently removes every currently `:expired` document.

  Returns `{:ok, purged_count}`.
  """
  @spec purge_expired(GenServer.server()) :: {:ok, non_neg_integer()}
  def purge_expired(server), do: GenServer.call(server, :purge_expired)