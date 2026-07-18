  test "integer options are coerced to floats", %{cb: _cb} do
    # REMOVED: start_supervised!({Clock, 0})

    # All integer options — should still work
    {:ok, _pid} =
      LeakyBucketCircuitBreaker.start_link(
        name: :int_cb,
        bucket_capacity: 3,
        leak_rate_per_sec: 2,
        failure_weight: 1,
        reset_timeout_ms: 1_000,
        clock: &Clock.now/0
      )

    for _ <- 1..3, do: LeakyBucketCircuitBreaker.call(:int_cb, err_fn())
    assert :open == LeakyBucketCircuitBreaker.state(:int_cb)
  end