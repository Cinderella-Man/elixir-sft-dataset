  test "starts in closed state" do
    assert CircuitBreaker.state(:test_cb) == :closed
  end