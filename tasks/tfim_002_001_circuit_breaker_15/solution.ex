  test "full cycle: closed → open → half-open → closed" do
    # Closed: working fine
    assert {:ok, :success} = CircuitBreaker.call(:test_cb, ok_fn())
    assert CircuitBreaker.state(:test_cb) == :closed

    # Closed → Open: three failures
    for _ <- 1..3, do: CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open

    # Open: blocked
    assert {:error, :circuit_open} = CircuitBreaker.call(:test_cb, ok_fn())

    # Open → Half-open: wait for timeout
    Clock.advance(5_000)

    # Half-open → Closed: successful probe
    assert {:ok, :success} = CircuitBreaker.call(:test_cb, ok_fn())
    assert CircuitBreaker.state(:test_cb) == :closed

    # Back to normal
    assert {:ok, :success} = CircuitBreaker.call(:test_cb, ok_fn())
  end