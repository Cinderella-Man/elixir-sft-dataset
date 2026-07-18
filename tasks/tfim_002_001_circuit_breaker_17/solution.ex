  test "closed state: raising functions count toward the failure threshold" do
    # threshold is 3; three raises must trip exactly like three {:error, _}
    CircuitBreaker.call(:test_cb, raise_fn())
    CircuitBreaker.call(:test_cb, raise_fn())
    assert CircuitBreaker.state(:test_cb) == :closed

    CircuitBreaker.call(:test_cb, raise_fn())
    assert CircuitBreaker.state(:test_cb) == :open
  end