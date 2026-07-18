  test "missing get does NOT refresh anything", %{lru: c} do
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # A miss shouldn't change anything
    assert :miss = LRUCache.get(c, :nope)

    # Oldest is still :a, so this evicts :a
    LRUCache.put(c, :d, 4)
    assert :miss = LRUCache.get(c, :a)
  end