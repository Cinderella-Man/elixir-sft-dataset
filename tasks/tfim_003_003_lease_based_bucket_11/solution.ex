  test "refill caps at capacity", %{lb: lb} do
    # Acquire and cancel to leave bucket intact at full
    {:ok, l, _} = LeaseBucket.acquire_lease(lb, "k", 3, 1.0, 3, 60_000)
    LeaseBucket.release(lb, "k", l, :cancelled)

    # Idle for a long time — balance should cap at 3, not accumulate
    Clock.advance(100_000)

    # Should still only admit 3, not more
    assert {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "k", 3, 1.0, 3, 60_000)
    assert {:error, :empty, _} = LeaseBucket.acquire_lease(lb, "k", 3, 1.0, 1, 60_000)
  end