  test "longer sequence produces the expected LRU evictions" do
    # Clock is already started by setup — reset it instead of starting again.
    Clock.set(0)

    {:ok, c} = LRUCache.start_link(capacity: 3, clock: &Clock.now/0)

    # Standard LRU textbook trace.
    # [:a]
    LRUCache.put(c, :a, 1)
    # [:b, :a]
    LRUCache.put(c, :b, 2)
    # [:c, :b, :a]
    LRUCache.put(c, :c, 3)
    # [:a, :c, :b]
    LRUCache.get(c, :a)
    # evicts :b → [:d, :a, :c]
    LRUCache.put(c, :d, 4)
    # [:c, :d, :a]
    LRUCache.get(c, :c)
    # evicts :a → [:e, :c, :d]
    LRUCache.put(c, :e, 5)

    assert :miss = LRUCache.get(c, :b)
    assert :miss = LRUCache.get(c, :a)
    assert {:ok, 3} = LRUCache.get(c, :c)
    assert {:ok, 4} = LRUCache.get(c, :d)
    assert {:ok, 5} = LRUCache.get(c, :e)
  end