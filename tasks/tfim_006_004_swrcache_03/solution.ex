  test "stale window returns {:ok, value, :stale}", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, &Loader.next_value/0)

    Clock.advance(1_000)
    assert {:ok, :v1, :stale} = SwrCache.get(c, :a)
  end