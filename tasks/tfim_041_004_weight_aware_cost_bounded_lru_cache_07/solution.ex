  test "an entry that exactly fills the budget is allowed" do
    c = start_cache(10)
    assert :ok = WeightedLRUCache.put(c, :a, "a", 10)
    assert WeightedLRUCache.weight(c) == 10
    # next insert must evict :a to make room
    assert :ok = WeightedLRUCache.put(c, :b, "b", 1)
    assert :miss = WeightedLRUCache.get(c, :a)
    assert {:ok, "b"} = WeightedLRUCache.get(c, :b)
    assert WeightedLRUCache.weight(c) == 1
  end