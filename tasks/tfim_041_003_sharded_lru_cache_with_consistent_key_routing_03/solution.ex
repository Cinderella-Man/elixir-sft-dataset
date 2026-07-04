  test "get refreshes recency within a single shard" do
    c = start_cache(1, 3)
    LRUCacheSharded.put(c, :a, 1)
    LRUCacheSharded.put(c, :b, 2)
    LRUCacheSharded.put(c, :c, 3)
    # touch :a → :b becomes LRU
    LRUCacheSharded.get(c, :a)
    LRUCacheSharded.put(c, :d, 4)

    assert {:ok, 1} = LRUCacheSharded.get(c, :a)
    assert :miss = LRUCacheSharded.get(c, :b)
  end