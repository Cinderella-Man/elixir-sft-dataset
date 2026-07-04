  test "size never exceeds capacity", %{lru: c} do
    for i <- 1..10, do: LRUCache.put(c, i, i * 10)
    assert LRUCache.size(c) == 3
  end