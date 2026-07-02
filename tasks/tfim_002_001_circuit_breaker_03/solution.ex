  test "closed state: successful calls pass through" do
    assert {:ok, :success} = CircuitBreaker.call(:test_cb, ok_fn())
    assert CircuitBreaker.state(:test_cb) == :closed
  end