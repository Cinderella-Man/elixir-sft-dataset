  test "put on an existing key updates both value AND access timestamp", %{lru: c} do
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # Overwrite :a — makes it MRU, oldest is now :b
    LRUCache.put(c, :a, 99)

    # Next new-key insert must evict :b
    LRUCache.put(c, :d, 4)

    assert {:ok, 99} = LRUCache.get(c, :a)
    assert :miss = LRUCache.get(c, :b)
  end