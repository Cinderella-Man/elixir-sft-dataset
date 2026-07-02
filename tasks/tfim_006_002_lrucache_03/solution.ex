  test "get on a missing key returns :miss", %{lru: c} do
    assert :miss = LRUCache.get(c, :nope)
  end