  test "rejects an entry whose weight alone exceeds the budget without evicting" do
    c = start_cache(10)
    WeightedLRUCache.put(c, :a, "a", 8)
    assert {:error, :too_large} = WeightedLRUCache.put(c, :big, "big", 11)

    # nothing evicted, nothing inserted
    assert {:ok, "a"} = WeightedLRUCache.get(c, :a)
    assert :miss = WeightedLRUCache.get(c, :big)
    assert WeightedLRUCache.weight(c) == 8
  end