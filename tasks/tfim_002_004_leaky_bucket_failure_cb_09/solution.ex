  test "does not trip when failure rate is outpaced by leak rate", %{cb: cb} do
    # One failure every 2 seconds, leak rate is 1/sec → bucket oscillates ≤ 1.0
    for _ <- 1..20 do
      LeakyBucketCircuitBreaker.call(cb, err_fn())
      Clock.advance(2_000)
    end

    assert :closed = LeakyBucketCircuitBreaker.state(cb)
  end