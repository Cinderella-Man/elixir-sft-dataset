  test "rejects a non-positive or non-integer weight" do
    c = start_cache(10)
    assert {:error, :invalid_weight} = WeightedLRUCache.put(c, :a, "a", 0)
    assert {:error, :invalid_weight} = WeightedLRUCache.put(c, :b, "b", -3)
    assert {:error, :invalid_weight} = WeightedLRUCache.put(c, :c, "c", 1.5)

    assert :miss = WeightedLRUCache.get(c, :a)
    assert WeightedLRUCache.weight(c) == 0
  end