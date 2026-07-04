  test "num_shards reports the configured shard count" do
    c = start_cache(8, 5)
    assert LRUCacheSharded.num_shards(c) == 8
  end