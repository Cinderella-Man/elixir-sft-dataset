  test "put overwrites an existing key" do
    c = start_cache(3)
    LFUCache.put(c, :a, 1)
    LFUCache.put(c, :a, 42)
    assert {:ok, 42} = LFUCache.get(c, :a)
  end