  test "two cache instances are fully independent" do
    c1 = start_cache(5)
    c2 = start_cache(5)
    WeightedLRUCache.put(c1, :k, :from_c1, 2)
    WeightedLRUCache.put(c2, :k, :from_c2, 2)

    assert {:ok, :from_c1} = WeightedLRUCache.get(c1, :k)
    assert {:ok, :from_c2} = WeightedLRUCache.get(c2, :k)
  end