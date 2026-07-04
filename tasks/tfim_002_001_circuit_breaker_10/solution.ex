  test "half-open: successful probe closes the circuit" do
    # Trip the breaker
    for _ <- 1..3, do: CircuitBreaker.call(:test_cb, error_fn())
    Clock.advance(5_000)

    # Probe succeeds
    assert {:ok, :success} = CircuitBreaker.call(:test_cb, ok_fn())
    assert CircuitBreaker.state(:test_cb) == :closed

    # Now fully operational again
    assert {:ok, :success} = CircuitBreaker.call(:test_cb, ok_fn())
  end