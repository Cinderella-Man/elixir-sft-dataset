  test "stale buckets are cleaned up and don't accumulate", %{lb: lb} do
    # A refill rate of 0.001 tokens/sec means barely anything refills over the
    # TTL window, so a bucket that is still tracked stays empty while an evicted
    # one comes back brand new and full at capacity.
    for i <- 1..100 do
      assert {:ok, 0} = LeakyBucket.acquire(lb, "bucket:#{i}", 1, 0.001)
    end

    # Advance past the default cleanup TTL (300_000ms = 5 minutes)
    Clock.advance(300_001)

    # Trigger cleanup via a message
    send(lb, :cleanup)

    # A synchronous request is handled after the queued cleanup message, so once
    # it returns the sweep has already happened.
    assert {:ok, _} = LeakyBucket.acquire(lb, "probe", 5, 1)

    # Every stale bucket was dropped: each one is brand new again, starting full
    # at capacity rather than remaining empty from the earlier drain.
    for i <- 1..100 do
      assert {:ok, 0} = LeakyBucket.acquire(lb, "bucket:#{i}", 1, 0.001)
    end
  end