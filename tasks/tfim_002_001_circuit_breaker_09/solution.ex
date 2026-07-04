  test "transitions to half-open after reset_timeout_ms" do
    # Trip the breaker
    for _ <- 1..3, do: CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open

    # Not enough time
    Clock.advance(4_999)
    CircuitBreaker.call(:test_cb, ok_fn())
    assert CircuitBreaker.state(:test_cb) == :open

    # Enough time — next call should go through as a probe
    # now at 5000ms total
    Clock.advance(1)
    result = CircuitBreaker.call(:test_cb, ok_fn())
    # The call should have been allowed through
    assert result == {:ok, :success}
  end