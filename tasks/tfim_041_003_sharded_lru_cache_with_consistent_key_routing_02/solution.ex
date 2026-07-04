  test "num_shards: 1 behaves like a plain LRU cache" do
    c = start_cache(1, 3)
    LRUCacheSharded.put(c, :a, 1)
    LRUCacheSharded.put(c, :b, 2)
    LRUCacheSharded.put(c, :c, 3)
    # evicts :a (LRU)
    LRUCacheSharded.put(c, :d, 4)

    assert :miss = LRUCacheSharded.get(c, :a)
    assert {:ok, 2} = LRUCacheSharded.get(c, :b)
    assert {:ok, 3} = LRUCacheSharded.get(c, :c)
    assert {:ok, 4} = LRUCacheSharded.get(c, :d)
  end