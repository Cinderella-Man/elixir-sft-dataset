  test "default bucket_capacity of 5.0 trips on the fifth failure", %{cb: _cb} do
    {:ok, _pid} =
      LeakyBucketCircuitBreaker.start_link(
        name: :default_cap_cb,
        leak_rate_per_sec: 1.0,
        failure_weight: 1.0,
        reset_timeout_ms: 1_000,
        clock: &Clock.now/0
      )

    for _ <- 1..4, do: LeakyBucketCircuitBreaker.call(:default_cap_cb, err_fn())
    assert :closed = LeakyBucketCircuitBreaker.state(:default_cap_cb)

    LeakyBucketCircuitBreaker.call(:default_cap_cb, err_fn())
    assert :open = LeakyBucketCircuitBreaker.state(:default_cap_cb)
  end