  test "an unexpected return shape counts as a failure and fills the bucket", %{cb: cb} do
    weird = fn -> :not_a_tuple end
    LeakyBucketCircuitBreaker.call(cb, weird)
    assert 1.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    for _ <- 1..4, do: LeakyBucketCircuitBreaker.call(cb, weird)
    assert :open = LeakyBucketCircuitBreaker.state(cb)
  end