  test "put and get round-trip" do
    c = start_cache(3)
    assert :ok = LRUCache.put(c, :a, 1)
    assert {:ok, 1} = LRUCache.get(c, :a)
  end