  test "get saves an entry from weight eviction" do
    c = start_cache(6)
    WeightedLRUCache.put(c, :a, "a", 2)
    WeightedLRUCache.put(c, :b, "b", 2)
    WeightedLRUCache.put(c, :c, "c", 2)
    # touch :a → :b is now LRU
    WeightedLRUCache.get(c, :a)
    # adding d(2) → 6+2 > 6 → evict LRU (:b)
    WeightedLRUCache.put(c, :d, "d", 2)

    assert {:ok, "a"} = WeightedLRUCache.get(c, :a)
    assert :miss = WeightedLRUCache.get(c, :b)
    assert {:ok, "c"} = WeightedLRUCache.get(c, :c)
    assert {:ok, "d"} = WeightedLRUCache.get(c, :d)
    assert WeightedLRUCache.weight(c) == 6
  end