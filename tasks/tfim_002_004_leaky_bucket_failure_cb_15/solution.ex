  test "open → half_open after reset_timeout_ms", %{cb: cb} do
    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    Clock.advance(1_000)
    assert :half_open = LeakyBucketCircuitBreaker.state(cb)
  end