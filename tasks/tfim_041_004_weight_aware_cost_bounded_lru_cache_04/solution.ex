  test "weight tracks the sum of resident entry weights" do
    c = start_cache(10)
    assert WeightedLRUCache.weight(c) == 0
    WeightedLRUCache.put(c, :a, 1, 3)
    WeightedLRUCache.put(c, :b, 2, 4)
    assert WeightedLRUCache.weight(c) == 7
  end