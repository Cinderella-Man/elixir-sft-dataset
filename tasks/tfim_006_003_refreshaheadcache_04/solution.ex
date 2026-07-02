  test "hard expiry returns :miss and evicts", %{c: c} do
    :ok = RefreshAheadCache.put(c, :a, 1, 1_000, fn -> :never end)

    Clock.advance(1_000)
    assert :miss = RefreshAheadCache.get(c, :a)

    assert %{entries: 0} = RefreshAheadCache.stats(c)
  end