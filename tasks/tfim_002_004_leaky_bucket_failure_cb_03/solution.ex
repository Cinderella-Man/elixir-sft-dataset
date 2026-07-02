  test "each failure adds failure_weight to bucket", %{cb: cb} do
    LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert 1.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert 2.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert 3.0 == LeakyBucketCircuitBreaker.bucket_level(cb)
  end