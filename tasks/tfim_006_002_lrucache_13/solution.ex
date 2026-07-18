  test "keys_by_recency returns MRU first, LRU last", %{lru: c} do
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    assert [:c, :b, :a] = LRUCache.keys_by_recency(c)

    LRUCache.get(c, :a)
    assert [:a, :c, :b] = LRUCache.keys_by_recency(c)

    LRUCache.put(c, :b, 99)
    assert [:b, :a, :c] = LRUCache.keys_by_recency(c)
  end