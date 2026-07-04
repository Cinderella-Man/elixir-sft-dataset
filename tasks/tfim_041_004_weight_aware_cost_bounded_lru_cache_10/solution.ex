  test "growing an existing key's weight can evict other entries" do
    c = start_cache(10)
    WeightedLRUCache.put(c, :a, "a", 2)
    WeightedLRUCache.put(c, :b, "b", 2)
    # update :a to a big weight: release old 2 (total 2), then need room for 9
    WeightedLRUCache.put(c, :a, "a-big", 9)

    assert {:ok, "a-big"} = WeightedLRUCache.get(c, :a)
    assert :miss = WeightedLRUCache.get(c, :b)
    assert WeightedLRUCache.weight(c) == 9
  end