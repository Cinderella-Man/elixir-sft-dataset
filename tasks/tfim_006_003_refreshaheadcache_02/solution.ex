  test "put/get round-trip", %{c: c} do
    :ok = RefreshAheadCache.put(c, :a, 1, 1_000, fn -> :should_not_be_called end)
    assert {:ok, 1} = RefreshAheadCache.get(c, :a)
  end