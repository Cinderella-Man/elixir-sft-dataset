  test "cache of size 1 always holds only the latest inserted entry" do
    c = start_cache(1)
    LFUCache.put(c, :a, 1)
    LFUCache.put(c, :b, 2)

    assert :miss = LFUCache.get(c, :a)
    assert {:ok, 2} = LFUCache.get(c, :b)
  end