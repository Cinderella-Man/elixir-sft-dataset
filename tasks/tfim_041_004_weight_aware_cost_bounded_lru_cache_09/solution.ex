  test "updating a key replaces its value and adjusts total weight" do
    c = start_cache(10)
    WeightedLRUCache.put(c, :a, "a", 5)
    assert WeightedLRUCache.weight(c) == 5
    WeightedLRUCache.put(c, :a, "a2", 2)
    assert {:ok, "a2"} = WeightedLRUCache.get(c, :a)
    assert WeightedLRUCache.weight(c) == 2
  end