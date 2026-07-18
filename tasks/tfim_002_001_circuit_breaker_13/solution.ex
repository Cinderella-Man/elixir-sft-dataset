  test "reset from open state returns to closed" do
    for _ <- 1..3, do: CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open

    CircuitBreaker.reset(:test_cb)
    assert CircuitBreaker.state(:test_cb) == :closed

    # Fully operational
    assert {:ok, :success} = CircuitBreaker.call(:test_cb, ok_fn())
  end