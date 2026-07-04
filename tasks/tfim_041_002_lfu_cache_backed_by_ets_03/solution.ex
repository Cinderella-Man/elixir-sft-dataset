  test "put and get round-trip" do
    c = start_cache(3)
    assert :ok = LFUCache.put(c, :a, 1)
    assert {:ok, 1} = LFUCache.get(c, :a)
  end