  test "cancel refund is capped at capacity even after a refill", %{lb: lb} do
    # Drain the bucket, then PERSIST a refill through a real acquire before
    # cancelling: free is 2.0 when the 5-token refund lands, so 2 + 5 must
    # cap at capacity 5 — an uncapped refund would leave 7.
    {:ok, lease_a, 0} = LeaseBucket.acquire_lease(lb, "cap", 5, 1.0, 5, 60_000)
    Clock.advance(3_000)
    {:ok, lease_b, 2} = LeaseBucket.acquire_lease(lb, "cap", 5, 1.0, 1, 60_000)
    assert :ok = LeaseBucket.release(lb, "cap", lease_a, :cancelled)

    # Exactly capacity 5 is available — and not a token more.
    assert {:ok, lease_c, 0} = LeaseBucket.acquire_lease(lb, "cap", 5, 1.0, 5, 60_000)
    assert {:error, :empty, _} = LeaseBucket.acquire_lease(lb, "cap", 5, 1.0, 1, 60_000)
    :ok = LeaseBucket.release(lb, "cap", lease_b, :completed)
    :ok = LeaseBucket.release(lb, "cap", lease_c, :completed)
  end