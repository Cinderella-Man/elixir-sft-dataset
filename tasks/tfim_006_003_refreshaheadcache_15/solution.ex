  test "refresh triggers exactly at the age >= 800ms boundary", %{c: c} do
    start_supervised!({Loader, [:v2]})
    :ok = RefreshAheadCache.put(c, :a, :v1, 1_000, &Loader.next_value/0)

    # age 799ms: below the boundary, no refresh must be scheduled.
    Clock.advance(799)
    assert {:ok, :v1} = RefreshAheadCache.get(c, :a)
    :ok = wait_for_idle(c)
    assert Loader.calls() == 0

    # age exactly 800ms: at the boundary the refresh must fire.
    Clock.advance(1)
    assert {:ok, :v1} = RefreshAheadCache.get(c, :a)
    :ok = wait_for_idle(c)
    assert Loader.calls() == 1
  end