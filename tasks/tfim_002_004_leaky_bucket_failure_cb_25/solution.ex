  test "default failure_weight of 1.0 adds one drop per failure", %{cb: _cb} do
    {:ok, _pid} =
      LeakyBucketCircuitBreaker.start_link(
        name: :default_wt_cb,
        bucket_capacity: 5.0,
        leak_rate_per_sec: 1.0,
        reset_timeout_ms: 1_000,
        clock: &Clock.now/0
      )

    LeakyBucketCircuitBreaker.call(:default_wt_cb, err_fn())
    assert 1.0 == LeakyBucketCircuitBreaker.bucket_level(:default_wt_cb)
  end