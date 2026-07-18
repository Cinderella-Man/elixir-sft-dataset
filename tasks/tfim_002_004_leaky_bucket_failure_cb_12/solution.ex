  test "failure_weight scales how many drops each failure adds", %{cb: _cb} do
    # REMOVED: start_supervised!({Clock, 0})

    {:ok, _pid} =
      LeakyBucketCircuitBreaker.start_link(
        name: :weighted_cb,
        bucket_capacity: 10.0,
        leak_rate_per_sec: 1.0,
        failure_weight: 3.0,
        reset_timeout_ms: 1_000,
        clock: &Clock.now/0
      )

    # 3 failures = 9 drops, still under 10
    for _ <- 1..3, do: LeakyBucketCircuitBreaker.call(:weighted_cb, err_fn())
    assert 9.0 == LeakyBucketCircuitBreaker.bucket_level(:weighted_cb)

    # 4th failure → 12 drops, trips
    LeakyBucketCircuitBreaker.call(:weighted_cb, err_fn())
    assert :open == LeakyBucketCircuitBreaker.state(:weighted_cb)
  end