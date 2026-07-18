  test "a miss consumes no counter value at all" do
    c = start_cache(3)

    LRUCache.put(c, :a, 1)
    assert timestamp(c, :a) == 1

    assert :miss = LRUCache.get(c, :ghost)
    assert :miss = LRUCache.get(c, :ghost)

    # Had the misses burned counter values, :b would not be stamped 2.
    assert :ok = LRUCache.put(c, :b, 2)
    assert timestamp(c, :b) == 2
  end