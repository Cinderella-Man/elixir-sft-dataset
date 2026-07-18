  @doc """
  Returns the 0-based shard index that owns the given series.
  """
  @spec shard_of(server(), term(), labels()) :: non_neg_integer()
  def shard_of(server, metric_name, labels) do
    GenServer.call(server, {:shard_of, metric_name, labels})
  end