  test "reset from closed state is a no-op (stays closed, counter resets)" do
    CircuitBreaker.call(:test_cb, error_fn())
    CircuitBreaker.call(:test_cb, error_fn())

    CircuitBreaker.reset(:test_cb)
    assert CircuitBreaker.state(:test_cb) == :closed

    # The two failures before reset shouldn't count —
    # need full 3 new failures to trip
    CircuitBreaker.call(:test_cb, error_fn())
    CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :closed
  end