  test "get on the sole entry in a size-1 cache still returns it" do
    c = start_cache(1)
    LRUCache.put(c, :only, :value)
    assert {:ok, :value} = LRUCache.get(c, :only)
    assert {:ok, :value} = LRUCache.get(c, :only)
  end