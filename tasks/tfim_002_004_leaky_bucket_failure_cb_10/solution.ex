  test "trips on burst even after a long quiet period leaks the bucket empty", %{cb: cb} do
    # Earn some drops, then wait long enough for the bucket to empty
    for _ <- 1..2, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    Clock.advance(10_000)
    # Bucket should be at 0 now
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    # Fresh burst fills the bucket to capacity and trips
    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert :open = LeakyBucketCircuitBreaker.state(cb)
  end