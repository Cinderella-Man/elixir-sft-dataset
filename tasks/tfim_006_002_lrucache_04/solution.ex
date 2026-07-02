  test "delete removes the key", %{lru: c} do
    LRUCache.put(c, :a, 1)
    :ok = LRUCache.delete(c, :a)
    assert :miss = LRUCache.get(c, :a)
  end