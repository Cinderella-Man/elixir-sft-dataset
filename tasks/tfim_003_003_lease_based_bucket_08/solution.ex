  test "expired leases disappear without refunding tokens", %{lb: lb} do
    # Acquire a lease with a 1-second timeout
    {:ok, lease_id, 2} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 1_000)
    assert {:ok, 1} = LeaseBucket.active_leases(lb, "k")

    # Advance past lease expiry.  The next operation must expire the lease.
    Clock.advance(1_500)

    # active_leases triggers the expiry sweep for this bucket
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "k")

    # Explicitly releasing the expired lease should fail
    assert {:error, :unknown_lease} = LeaseBucket.release(lb, "k", lease_id, :cancelled)

    # Tokens are NOT refunded — but some will have refilled due to elapsed time.
    # At 1.0 tokens/sec with 1.5s elapsed, the free balance went from 2 to 3.5.
    # Acquiring 4 should still fail (only 3.5 free, floor = 3)
    assert {:error, :empty, _} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 4, 60_000)
    assert {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 60_000)
  end