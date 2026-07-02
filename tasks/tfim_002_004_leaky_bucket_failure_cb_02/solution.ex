  test "bucket starts empty", %{cb: cb} do
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)
  end