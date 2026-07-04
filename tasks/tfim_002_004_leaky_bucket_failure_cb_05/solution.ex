  test "bucket leaks at leak_rate_per_sec", %{cb: cb} do
    for _ <- 1..3, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert 3.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    # 1 second elapsed — leak 1.0 drop
    Clock.advance(1_000)
    assert 2.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    # 2 more seconds — leaks to 0
    Clock.advance(2_000)
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)
  end