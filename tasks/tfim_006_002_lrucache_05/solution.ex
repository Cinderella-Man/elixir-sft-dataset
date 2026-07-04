  test "delete on missing key returns :ok", %{lru: c} do
    assert :ok = LRUCache.delete(c, :ghost)
  end