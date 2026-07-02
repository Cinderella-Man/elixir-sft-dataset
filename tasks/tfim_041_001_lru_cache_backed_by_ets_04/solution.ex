  test "put overwrites an existing key" do
    c = start_cache(3)
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :a, 42)
    assert {:ok, 42} = LRUCache.get(c, :a)
  end