  test "successful revalidation gives new full fresh+stale budget", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, &Loader.next_value/0)

    Clock.advance(1_500)
    SwrCache.get(c, :a)
    :ok = wait_for_idle(c)

    # Revalidation happened at t=1500 so fresh until t=2500, stale until t=4500
    # t=2499
    Clock.advance(999)
    assert {:ok, :v2, :fresh} = SwrCache.get(c, :a)

    # t=2501
    Clock.advance(2)
    assert {:ok, :v2, :stale} = SwrCache.get(c, :a)
  end