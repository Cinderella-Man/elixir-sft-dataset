  test "closed state: the tripping call returns the function result not circuit_open" do
    CircuitBreaker.call(:test_cb, error_fn())
    CircuitBreaker.call(:test_cb, error_fn())

    # The threshold-crossing call itself must surface the func's error, not :circuit_open
    assert {:error, :boom} = CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open
  end