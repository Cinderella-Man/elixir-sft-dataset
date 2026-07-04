  test "closed state: raising functions return error without crashing the GenServer" do
    result = CircuitBreaker.call(:test_cb, raise_fn())
    assert {:error, _exception} = result
    # GenServer still alive
    assert CircuitBreaker.state(:test_cb) == :closed
  end