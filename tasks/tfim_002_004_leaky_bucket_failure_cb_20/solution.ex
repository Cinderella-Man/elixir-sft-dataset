  test "reset from :closed with partial bucket clears it", %{cb: cb} do
    for _ <- 1..3, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert 3.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    LeakyBucketCircuitBreaker.reset(cb)
    assert :closed = LeakyBucketCircuitBreaker.state(cb)
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)
  end