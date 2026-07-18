  test "half-open: excess calls beyond probe limit get circuit_open" do
    # Trip the breaker
    for _ <- 1..3, do: CircuitBreaker.call(:test_cb, error_fn())
    Clock.advance(5_000)

    # With half_open_max_probes = 1 and synchronous calls, the probe call
    # completes before any second call starts. A failed probe therefore
    # returns the breaker to :open and blocks the next call immediately.

    # Probe fails → back to open
    CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open

    # Immediately blocked again
    assert {:error, :circuit_open} = CircuitBreaker.call(:test_cb, ok_fn())
  end