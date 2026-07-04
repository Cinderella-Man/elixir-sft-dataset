  test "free balance refills lazily between calls", %{lb: lb} do
    # Drain to 0 by acquiring and then never releasing
    {:ok, _lease, 0} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 5, 60_000)
    assert {:error, :empty, _} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 1, 60_000)

    # Advance 2 seconds at 1 token/sec — free balance goes from 0 to 2
    Clock.advance(2_000)

    assert {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 2, 60_000)
  end