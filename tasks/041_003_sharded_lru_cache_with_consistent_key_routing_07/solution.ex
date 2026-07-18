  @doc "The shard index a key routes to."
  @spec shard_index(name(), key()) :: non_neg_integer()
  def shard_index(name, key), do: :erlang.phash2(key, num_shards(name))