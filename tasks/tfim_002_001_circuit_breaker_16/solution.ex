  test "full cycle: closed → open → half-open → open → half-open → closed" do
    # Trip it
    for _ <- 1..3, do: CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open

    # Wait, probe, fail
    Clock.advance(5_000)
    CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open

    # Wait again, probe, succeed
    Clock.advance(5_000)
    assert {:ok, :success} = CircuitBreaker.call(:test_cb, ok_fn())
    assert CircuitBreaker.state(:test_cb) == :closed
  end