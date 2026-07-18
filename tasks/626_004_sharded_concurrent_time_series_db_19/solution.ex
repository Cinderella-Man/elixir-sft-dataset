  @doc """
  Returns the configured number of shards.
  """
  @spec shard_count(server()) :: non_neg_integer()
  def shard_count(server) do
    GenServer.call(server, :shard_count)
  end