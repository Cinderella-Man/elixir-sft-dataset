  test "past hard expiry returns :miss and evicts", %{c: c} do
    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, fn -> :never end)

    Clock.advance(3_000)
    assert :miss = SwrCache.get(c, :a)
    assert %{entries: 0} = SwrCache.stats(c)
  end