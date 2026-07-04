  test "successful calls in closed state reset the failure count" do
    # Two failures
    CircuitBreaker.call(:test_cb, error_fn())
    CircuitBreaker.call(:test_cb, error_fn())

    # A success should reset (or at least not contribute to threshold)
    CircuitBreaker.call(:test_cb, ok_fn())

    # Two more failures — should NOT trip if the success reset the count
    CircuitBreaker.call(:test_cb, error_fn())
    CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :closed

    # Third consecutive failure now trips it
    CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open
  end