  test "a miss creates nothing, evicts nothing and leaves ordering untouched" do
    c = start_cache(2)
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)

    assert :miss = LRUCache.get(c, :ghost)
    assert :miss = LRUCache.get(c, :ghost)

    # Both residents survived the misses, and :a is still the LRU.
    assert :ok = LRUCache.put(c, :d, 4)

    assert :miss = LRUCache.get(c, :a)
    assert {:ok, 2} = LRUCache.get(c, :b)
    assert {:ok, 4} = LRUCache.get(c, :d)
    assert :miss = LRUCache.get(c, :ghost)
  end