  test "reset clears the bucket and returns to :closed", %{cb: cb} do
    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert :open = LeakyBucketCircuitBreaker.state(cb)

    LeakyBucketCircuitBreaker.reset(cb)
    assert :closed = LeakyBucketCircuitBreaker.state(cb)
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)
  end