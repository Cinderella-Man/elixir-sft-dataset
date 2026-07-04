  test "put on an existing key never evicts another key", %{lru: c} do
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # Overwriting :a should NOT evict :b or :c
    LRUCache.put(c, :a, 99)

    assert LRUCache.size(c) == 3
    assert {:ok, 99} = LRUCache.get(c, :a)
    assert {:ok, 2} = LRUCache.get(c, :b)
    assert {:ok, 3} = LRUCache.get(c, :c)
  end