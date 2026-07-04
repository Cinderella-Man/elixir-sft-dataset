  test "bucket never goes below zero even after long idle", %{cb: cb} do
    Clock.advance(1_000_000)
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert 1.0 == LeakyBucketCircuitBreaker.bucket_level(cb)
  end