  test "default reset_timeout_ms of 30_000 keeps circuit open until 30s elapse", %{cb: _cb} do
    {:ok, _pid} =
      LeakyBucketCircuitBreaker.start_link(
        name: :default_rt_cb,
        bucket_capacity: 5.0,
        leak_rate_per_sec: 1.0,
        failure_weight: 1.0,
        clock: &Clock.now/0
      )

    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(:default_rt_cb, err_fn())
    assert :open = LeakyBucketCircuitBreaker.state(:default_rt_cb)

    Clock.advance(29_999)
    assert :open = LeakyBucketCircuitBreaker.state(:default_rt_cb)

    Clock.advance(1)
    assert :half_open = LeakyBucketCircuitBreaker.state(:default_rt_cb)
  end