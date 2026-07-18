  defp shard_name(key, name) do
    n = num_shards(name)
    shard_name_for_index(name, :erlang.phash2(key, n))
  end