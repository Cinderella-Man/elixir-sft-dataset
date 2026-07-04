  test "half-open: failed probe reopens the circuit" do
    # Trip the breaker
    for _ <- 1..3, do: CircuitBreaker.call(:test_cb, error_fn())
    Clock.advance(5_000)

    # Probe fails
    assert {:error, :boom} = CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open

    # Needs another full timeout before trying again
    assert {:error, :circuit_open} = CircuitBreaker.call(:test_cb, ok_fn())
  end