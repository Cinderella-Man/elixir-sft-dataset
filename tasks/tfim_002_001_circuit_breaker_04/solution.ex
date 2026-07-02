  test "closed state: failed calls return the error" do
    assert {:error, :boom} = CircuitBreaker.call(:test_cb, error_fn())
    # Still closed after one failure (threshold is 3)
    assert CircuitBreaker.state(:test_cb) == :closed
  end