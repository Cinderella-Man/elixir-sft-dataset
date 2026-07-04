  test "intermingled successes don't reset the bucket", %{cb: cb} do
    # Unlike a consecutive-count breaker, successes here don't reduce the bucket.
    # 4 failures + a success + 1 more failure should still trip.
    for _ <- 1..4, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    LeakyBucketCircuitBreaker.call(cb, ok_fn())
    assert :closed = LeakyBucketCircuitBreaker.state(cb)
    assert 4.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert :open = LeakyBucketCircuitBreaker.state(cb)
  end