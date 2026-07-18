  test "refilled buckets are dropped in cleanup; global is kept", %{sp: sp} do
    # Touch 50 buckets
    for i <- 1..50, do: SharedPoolBucket.acquire(sp, "k:#{i}", 2, 5.0)

    # Advance long enough for per-key buckets to fully refill
    Clock.advance(10_000)

    send(sp, :cleanup)

    # Global pool survives the sweep and has refilled to capacity.  This
    # synchronous read also waits until the sweep has been processed.
    assert {:ok, 10} = SharedPoolBucket.global_level(sp)

    # Every swept bucket is gone: re-querying under a larger capacity reports a
    # fresh, full bucket instead of the 2-token balance a retained bucket
    # would still carry.
    for i <- 1..50 do
      assert {:ok, 50} = SharedPoolBucket.key_level(sp, "k:#{i}", 50, 1.0)
    end
  end