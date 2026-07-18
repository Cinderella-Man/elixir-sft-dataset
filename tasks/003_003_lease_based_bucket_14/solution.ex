  @doc """
  Returns the number of currently active (not yet released or expired)
  leases on a bucket.  Unknown buckets return `{:ok, 0}`.
  """
  @spec active_leases(GenServer.server(), term()) :: {:ok, non_neg_integer()}
  def active_leases(server, bucket) do
    GenServer.call(server, {:active_leases, bucket})
  end