  test "default reset_timeout_ms of 30_000 governs half-open transition" do
    {:ok, _pid} =
      CircuitBreaker.start_link(
        name: :default_rst_cb,
        failure_threshold: 1,
        clock: &Clock.now/0
      )

    CircuitBreaker.call(:default_rst_cb, error_fn())
    assert CircuitBreaker.state(:default_rst_cb) == :open

    # One millisecond short of the default window: still failing fast
    Clock.advance(29_999)
    assert {:error, :circuit_open} = CircuitBreaker.call(:default_rst_cb, ok_fn())

    # Exactly 30_000ms elapsed: the next call is allowed through as a probe
    Clock.advance(1)
    assert {:ok, :success} = CircuitBreaker.call(:default_rst_cb, ok_fn())
  end