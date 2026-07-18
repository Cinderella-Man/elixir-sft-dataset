  test "default leak_rate_per_sec of 1.0 leaks one drop per second", %{cb: _cb} do
    {:ok, _pid} =
      LeakyBucketCircuitBreaker.start_link(
        name: :default_leak_cb,
        bucket_capacity: 5.0,
        failure_weight: 1.0,
        reset_timeout_ms: 1_000,
        clock: &Clock.now/0
      )

    for _ <- 1..3, do: LeakyBucketCircuitBreaker.call(:default_leak_cb, err_fn())
    assert 3.0 == LeakyBucketCircuitBreaker.bucket_level(:default_leak_cb)

    Clock.advance(1_000)
    assert 2.0 == LeakyBucketCircuitBreaker.bucket_level(:default_leak_cb)
  end