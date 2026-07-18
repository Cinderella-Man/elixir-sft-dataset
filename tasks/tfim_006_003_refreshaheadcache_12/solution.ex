  test "a failing loader leaves the current value in place", %{c: c} do
    :ok =
      RefreshAheadCache.put(c, :a, :good, 1_000, fn -> raise "nope" end)

    Clock.advance(850)
    assert {:ok, :good} = RefreshAheadCache.get(c, :a)

    :ok = wait_for_idle(c)
    assert %{refreshes_in_flight: 0} = RefreshAheadCache.stats(c)

    # Still returns the original value
    assert {:ok, :good} = RefreshAheadCache.get(c, :a)
  end