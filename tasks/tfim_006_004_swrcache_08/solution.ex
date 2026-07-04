  test "concurrent stale reads trigger only ONE revalidation", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok =
      SwrCache.put(c, :a, :v1, 1_000, 2_000, fn -> Loader.slow_next_value(100) end)

    Clock.advance(1_000)

    # Fire many stale reads while a slow revalidation is still in flight.
    for _ <- 1..10, do: assert({:ok, :v1, :stale} = SwrCache.get(c, :a))

    assert %{revalidations_in_flight: 1} = SwrCache.stats(c)

    :ok = wait_for_idle(c)
    assert Loader.calls() == 1
  end