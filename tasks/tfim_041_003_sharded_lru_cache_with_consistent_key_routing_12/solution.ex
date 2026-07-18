  test "updating a key at exactly capacity evicts nothing and refreshes its recency" do
    c = start_cache(1, 2)
    LRUCacheSharded.put(c, :a, 1)
    LRUCacheSharded.put(c, :b, 2)
    assert LRUCacheSharded.size(c) == 2

    # in-place update while the shard is exactly full
    LRUCacheSharded.put(c, :a, 99)
    assert LRUCacheSharded.size(c) == 2

    # :a was refreshed by the update, so :b is now the eviction victim
    LRUCacheSharded.put(c, :c, 3)
    assert :miss = LRUCacheSharded.get(c, :b)
    assert {:ok, 99} = LRUCacheSharded.get(c, :a)
    assert {:ok, 3} = LRUCacheSharded.get(c, :c)
    assert LRUCacheSharded.size(c) == 2
  end