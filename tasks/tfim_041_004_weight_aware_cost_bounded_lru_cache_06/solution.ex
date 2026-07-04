  test "a single put may evict several entries in a row" do
    c = start_cache(10)
    WeightedLRUCache.put(c, :a, "a", 4)
    WeightedLRUCache.put(c, :b, "b", 4)
    # total 8; adding big(9) → evict :a → 4, still 4+9>10 → evict :b → 0, +9 = 9
    WeightedLRUCache.put(c, :big, "big", 9)

    assert :miss = WeightedLRUCache.get(c, :a)
    assert :miss = WeightedLRUCache.get(c, :b)
    assert {:ok, "big"} = WeightedLRUCache.get(c, :big)
    assert WeightedLRUCache.weight(c) == 9
  end