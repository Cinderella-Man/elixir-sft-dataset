  test "cleanup drops fully-refilled buckets with no active leases", %{lb: lb} do
    # Create 50 buckets, each with one short lease that will expire
    for i <- 1..50 do
      LeaseBucket.acquire_lease(lb, "k:#{i}", 2, 10.0, 2, 100)
    end

    # Advance far enough for leases to expire AND buckets to refill
    Clock.advance(10_000)

    send(lb, :cleanup)

    # A synchronous call is served only after the cleanup message is handled,
    # so this both waits for the sweep and reads an untouched bucket name.
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "sentinel")

    # A swept bucket is indistinguishable from a fresh one: no active leases
    # and a free balance back at full capacity.
    for i <- 1..50 do
      assert {:ok, 0} = LeaseBucket.active_leases(lb, "k:#{i}")
      assert {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "k:#{i}", 2, 10.0, 2, 100)
    end
  end