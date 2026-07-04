  test "get returns :miss for unknown key" do
    c = start_cache(10)
    assert :miss = WeightedLRUCache.get(c, :nope)
  end