  test "stale read triggers revalidation; later reads see new value", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, &Loader.next_value/0)

    # Enter stale window
    Clock.advance(1_000)
    assert {:ok, :v1, :stale} = SwrCache.get(c, :a)

    :ok = wait_for_idle(c)
    assert Loader.calls() == 1

    # New value is :v2, and since revalidation happened at t=1000, it's fresh
    # until t=2000.
    assert {:ok, :v2, :fresh} = SwrCache.get(c, :a)
  end