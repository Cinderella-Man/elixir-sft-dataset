  test "transitions to open after failure_threshold failures" do
    for _ <- 1..2 do
      CircuitBreaker.call(:test_cb, error_fn())
    end

    assert CircuitBreaker.state(:test_cb) == :closed

    # Third failure trips the breaker
    CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open
  end