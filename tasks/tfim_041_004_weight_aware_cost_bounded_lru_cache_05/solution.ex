  test "inserting evicts LRU entries until the newcomer fits" do
    c = start_cache(10)
    WeightedLRUCache.put(c, :a, "a", 6)
    WeightedLRUCache.put(c, :b, "b", 3)
    # total 9; adding c(4) → 13 > 10 → evict LRU (:a, 6) → 3, +4 = 7 ≤ 10
    WeightedLRUCache.put(c, :c, "c", 4)

    assert :miss = WeightedLRUCache.get(c, :a)
    assert {:ok, "b"} = WeightedLRUCache.get(c, :b)
    assert {:ok, "c"} = WeightedLRUCache.get(c, :c)
    assert WeightedLRUCache.weight(c) == 7
  end