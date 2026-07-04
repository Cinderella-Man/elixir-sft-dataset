  test "bucket never exceeds capacity after long idle", %{lb: lb} do
    # Drain 1 token from a capacity-5 bucket
    assert {:ok, 4} = LeakyBucket.acquire(lb, "b", 5, 10)

    # Advance a very long time
    Clock.advance(1_000_000)

    # Bucket should be full at capacity, not over
    assert {:ok, 4} = LeakyBucket.acquire(lb, "b", 5, 10)
  end