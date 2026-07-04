  test "delete on a nonexistent key returns :ok", %{cache: cache} do
    assert :ok = TTLCache.delete(cache, "ghost")
  end