  test "two cache instances are fully independent" do
    c1 = start_cache(2)
    c2 = start_cache(2)

    LFUCache.put(c1, :a, :from_c1)
    LFUCache.put(c2, :a, :from_c2)

    assert {:ok, :from_c1} = LFUCache.get(c1, :a)
    assert {:ok, :from_c2} = LFUCache.get(c2, :a)
  end