  test "fresh window returns {:ok, value, :fresh}", %{c: c} do
    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, fn -> :should_not_be_called end)

    assert {:ok, :v1, :fresh} = SwrCache.get(c, :a)

    Clock.advance(999)
    assert {:ok, :v1, :fresh} = SwrCache.get(c, :a)
  end