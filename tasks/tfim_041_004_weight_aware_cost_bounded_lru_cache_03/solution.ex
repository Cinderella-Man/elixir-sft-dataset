  test "put and get round-trip" do
    c = start_cache(10)
    assert :ok = WeightedLRUCache.put(c, :a, "val", 3)
    assert {:ok, "val"} = WeightedLRUCache.get(c, :a)
  end