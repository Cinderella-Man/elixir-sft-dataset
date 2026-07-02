  test "successes do not add to bucket", %{cb: cb} do
    for _ <- 1..20, do: LeakyBucketCircuitBreaker.call(cb, ok_fn())
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)
  end