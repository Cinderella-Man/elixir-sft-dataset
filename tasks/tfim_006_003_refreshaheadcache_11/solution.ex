  test "put during in-flight refresh: the refresh result must not clobber", %{c: c} do
    start_supervised!({Loader, [:from_loader]})

    :ok =
      RefreshAheadCache.put(c, :a, :v1, 1_000, fn -> Loader.slow_next_value(100) end)

    Clock.advance(850)
    RefreshAheadCache.get(c, :a)   # triggers slow refresh

    # User overwrites manually before refresh completes
    RefreshAheadCache.put(c, :a, :user_set, 1_000, fn -> :ignored end)

    :ok = wait_for_idle(c)

    # The manual put must win
    assert {:ok, :user_set} = RefreshAheadCache.get(c, :a)
  end