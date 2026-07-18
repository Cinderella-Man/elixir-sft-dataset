  test "keys_by_recency returns empty list for an empty cache", %{lru: c} do
    assert [] = LRUCache.keys_by_recency(c)
  end