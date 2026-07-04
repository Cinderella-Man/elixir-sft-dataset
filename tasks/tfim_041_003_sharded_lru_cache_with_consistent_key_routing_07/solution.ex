  test "shard_index is deterministic and in range" do
    c = start_cache(4, 5)

    for k <- 1..50 do
      idx = LRUCacheSharded.shard_index(c, k)
      assert idx >= 0 and idx < 4
      assert LRUCacheSharded.shard_index(c, k) == idx
    end
  end