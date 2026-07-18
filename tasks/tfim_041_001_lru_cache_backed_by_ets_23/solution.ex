  test "falsy stored values are hits, not misses" do
    c = start_cache(3)

    LRUCache.put(c, :flag, false)
    assert {:ok, false} = LRUCache.get(c, :flag)

    LRUCache.put(c, :flag, nil)
    assert {:ok, nil} = LRUCache.get(c, :flag)

    LRUCache.put(c, :flag, false)
    assert {:ok, false} = LRUCache.get(c, :flag)
  end