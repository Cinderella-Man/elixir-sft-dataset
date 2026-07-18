  test "put during revalidation: revalidation result must not clobber", %{c: c} do
    start_supervised!({Loader, [:from_loader]})

    :ok =
      SwrCache.put(c, :a, :v1, 1_000, 2_000, fn -> Loader.slow_next_value(100) end)

    Clock.advance(1_000)
    # trigger slow revalidation
    SwrCache.get(c, :a)

    # User puts a new value before the revalidation completes
    SwrCache.put(c, :a, :user_set, 500, 1_000, fn -> :ignored end)

    :ok = wait_for_idle(c)

    # The user's put must win — value AND the fresh window is from the put's time
    assert {:ok, :user_set, :fresh} = SwrCache.get(c, :a)
  end