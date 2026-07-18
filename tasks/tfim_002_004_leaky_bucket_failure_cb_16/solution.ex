  test "probe success → :closed with empty bucket", %{cb: cb} do
    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    Clock.advance(1_000)

    assert {:ok, :v} = LeakyBucketCircuitBreaker.call(cb, ok_fn())
    assert :closed = LeakyBucketCircuitBreaker.state(cb)
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    # Fresh bucket — can tolerate some new failures without tripping
    for _ <- 1..4, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert :closed = LeakyBucketCircuitBreaker.state(cb)
  end