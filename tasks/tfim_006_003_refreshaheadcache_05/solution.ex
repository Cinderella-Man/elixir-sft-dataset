  test "delete removes entry", %{c: c} do
    :ok = RefreshAheadCache.put(c, :a, 1, 1_000, fn -> :never end)
    :ok = RefreshAheadCache.delete(c, :a)
    assert :miss = RefreshAheadCache.get(c, :a)
  end