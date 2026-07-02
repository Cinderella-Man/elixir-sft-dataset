  test "put / get round-trip", %{lru: c} do
    :ok = LRUCache.put(c, :a, 1)
    :ok = LRUCache.put(c, :b, 2)

    assert {:ok, 1} = LRUCache.get(c, :a)
    assert {:ok, 2} = LRUCache.get(c, :b)
  end