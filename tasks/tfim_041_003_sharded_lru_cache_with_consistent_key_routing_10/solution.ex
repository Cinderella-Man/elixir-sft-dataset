  test "size reports total entries across shards and respects per-shard caps" do
    c = start_cache(4, 2)
    # 4 shards * cap 2 = at most 8 entries retained
    for i <- 1..100, do: LRUCacheSharded.put(c, i, i)
    total = LRUCacheSharded.size(c)
    assert total <= 8
    assert total > 0
  end