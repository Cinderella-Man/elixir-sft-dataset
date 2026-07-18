  test "recently accessed buckets survive cleanup", %{lb: lb} do
    # Capacity 2 with a negligible refill rate: the tokens drained here stay
    # drained for as long as the bucket is tracked.
    assert {:ok, 1} = LeakyBucket.acquire(lb, "active", 2, 0.001)
    assert {:ok, 1} = LeakyBucket.acquire(lb, "stale", 2, 0.001)

    # Advance 200 seconds
    Clock.advance(200_000)

    # Touch "active" again so its last-access is recent
    assert {:ok, 0} = LeakyBucket.acquire(lb, "active", 2, 0.001)

    # Advance another 150 seconds (total 350s for "stale", 150s for "active")
    Clock.advance(150_000)

    # Trigger cleanup (TTL is 300_000ms)
    send(lb, :cleanup)

    # "active" was accessed within the TTL, so it keeps its drained balance and
    # cannot hand out another token.
    assert {:error, :empty, _} = LeakyBucket.acquire(lb, "active", 2, 0.001)

    # "stale" was idle past the TTL, so it was evicted and starts full again.
    assert {:ok, 1} = LeakyBucket.acquire(lb, "stale", 2, 0.001)
  end